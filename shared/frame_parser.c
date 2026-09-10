/* frame_parser.c — IUCM wire protocol. See protocol/PROTOCOL.md.
 * MIT, (c) 2026 Bernhard Goetzendorfer. */
#include "frame_parser.h"

#include <string.h>

/* ------------------------------------------------------------------ helpers */

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)(v >> 8);
}
static void put_u32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}
static void put_u32_be(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)((v >> 24) & 0xFFu);
    p[1] = (uint8_t)((v >> 16) & 0xFFu);
    p[2] = (uint8_t)((v >> 8) & 0xFFu);
    p[3] = (uint8_t)(v & 0xFFu);
}
static void put_u64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)((v >> (8 * i)) & 0xFFu);
}
static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static uint32_t get_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}
static uint32_t get_u32_be(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) |
           (uint32_t)p[3];
}
static uint64_t get_u64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | (uint64_t)p[i];
    return v;
}

/* Bounded cursor over a payload. Every read checks first. */
struct cur {
    const uint8_t *p;
    uint32_t       len;
    uint32_t       off;
};
static int cur_need(const struct cur *c, uint32_t n) {
    return (c->len - c->off) >= n; /* off <= len is an invariant */
}
static int cur_u8(struct cur *c, uint8_t *out) {
    if (!cur_need(c, 1)) return IUCM_ERR_TRUNCATED;
    *out = c->p[c->off++];
    return IUCM_OK;
}
static int cur_u16(struct cur *c, uint16_t *out) {
    if (!cur_need(c, 2)) return IUCM_ERR_TRUNCATED;
    *out = get_u16(c->p + c->off);
    c->off += 2;
    return IUCM_OK;
}
static int cur_u32(struct cur *c, uint32_t *out) {
    if (!cur_need(c, 4)) return IUCM_ERR_TRUNCATED;
    *out = get_u32(c->p + c->off);
    c->off += 4;
    return IUCM_OK;
}
static int cur_u64(struct cur *c, uint64_t *out) {
    if (!cur_need(c, 8)) return IUCM_ERR_TRUNCATED;
    *out = get_u64(c->p + c->off);
    c->off += 8;
    return IUCM_OK;
}
/* Copies n bytes into a NUL-terminated buffer of capacity cap. */
static int cur_str(struct cur *c, uint32_t n, char *dst, size_t cap) {
    if (!cur_need(c, n)) return IUCM_ERR_TRUNCATED;
    if ((size_t)n + 1u > cap) return IUCM_ERR_RANGE;
    memcpy(dst, c->p + c->off, n);
    dst[n] = '\0';
    c->off += n;
    return IUCM_OK;
}

/* ------------------------------------------------------------------ framing */

void iucm_write_header(uint8_t out[IUCM_HEADER_SIZE], uint8_t type, uint8_t flags,
                       uint32_t length) {
    out[0] = IUCM_MAGIC0;
    out[1] = IUCM_MAGIC1;
    out[2] = IUCM_MAGIC2;
    out[3] = IUCM_MAGIC3;
    out[4] = type;
    out[5] = flags;
    put_u16(out + 6, 0);
    put_u32(out + 8, length);
}

int iucm_read_header(const uint8_t in[IUCM_HEADER_SIZE], uint8_t *type, uint8_t *flags,
                     uint32_t *length) {
    uint32_t len;
    if (!in) return IUCM_ERR_BADARG;
    if (in[0] != IUCM_MAGIC0 || in[1] != IUCM_MAGIC1 || in[2] != IUCM_MAGIC2 ||
        in[3] != IUCM_MAGIC3)
        return IUCM_ERR_BADARG;
    len = get_u32(in + 8);
    if (len > IUCM_MAX_PAYLOAD) return IUCM_ERR_OVERSIZE;
    if (type) *type = in[4];
    if (flags) *flags = in[5];
    if (length) *length = len;
    return IUCM_OK;
}

int iucm_parser_init(struct iucm_parser *p, uint8_t *buf, size_t cap) {
    if (!p || !buf || cap < IUCM_HEADER_SIZE) return IUCM_ERR_BADARG;
    p->buf                  = buf;
    p->cap                  = cap;
    p->len                  = 0;
    p->failed               = 0;
    p->resync_bytes_dropped = 0;
    p->messages             = 0;
    return IUCM_OK;
}

void iucm_parser_reset(struct iucm_parser *p) {
    if (!p) return;
    p->len    = 0;
    p->failed = 0;
}

/* Drops leading bytes until buf starts with the magic, or until only a possible
 * partial magic prefix remains. Returns the number of bytes dropped. */
static size_t parser_resync(struct iucm_parser *p) {
    size_t i = 0;
    while (i < p->len) {
        size_t avail = p->len - i;
        if (p->buf[i] == IUCM_MAGIC0) {
            /* Enough bytes to decide? If not, keep them: the rest may still arrive. */
            if (avail < 4) break;
            if (p->buf[i + 1] == IUCM_MAGIC1 && p->buf[i + 2] == IUCM_MAGIC2 &&
                p->buf[i + 3] == IUCM_MAGIC3)
                break;
        }
        i++;
    }
    if (i > 0) {
        memmove(p->buf, p->buf + i, p->len - i);
        p->len -= i;
        p->resync_bytes_dropped += (uint64_t)i;
    }
    return i;
}

/* Consumes as many complete messages as the buffer holds. */
static int parser_drain(struct iucm_parser *p, iucm_msg_cb cb, void *ctx) {
    for (;;) {
        struct iucm_msg msg;
        uint32_t        length;
        size_t          total;
        int             rc;

        if (p->len > 0 && !(p->len >= 4 && p->buf[0] == IUCM_MAGIC0 &&
                            p->buf[1] == IUCM_MAGIC1 && p->buf[2] == IUCM_MAGIC2 &&
                            p->buf[3] == IUCM_MAGIC3)) {
            parser_resync(p);
        }
        if (p->len < IUCM_HEADER_SIZE) return IUCM_OK;

        rc = iucm_read_header(p->buf, &msg.type, &msg.flags, &length);
        if (rc != IUCM_OK) return rc; /* oversize; bad magic is impossible here */

        total = IUCM_HEADER_SIZE + (size_t)length;
        if (total > p->cap) return IUCM_ERR_CAPACITY;
        if (p->len < total) return IUCM_OK; /* need more bytes */

        msg.length  = length;
        msg.payload = p->buf + IUCM_HEADER_SIZE;
        p->messages++;
        if (cb) {
            if (cb(ctx, &msg) != 0) {
                /* Consume the message anyway so a resumed feed stays aligned. */
                memmove(p->buf, p->buf + total, p->len - total);
                p->len -= total;
                return IUCM_ERR_ABORTED;
            }
        }
        memmove(p->buf, p->buf + total, p->len - total);
        p->len -= total;
    }
}

int iucm_parser_feed(struct iucm_parser *p, const uint8_t *data, size_t n, iucm_msg_cb cb,
                     void *ctx) {
    if (!p || !p->buf) return IUCM_ERR_BADARG;
    if (p->failed != 0) return p->failed;
    if (n > 0 && !data) return IUCM_ERR_BADARG;

    while (n > 0) {
        size_t room = p->cap - p->len;
        size_t take;
        int    rc;

        if (room == 0) {
            /* Buffer full without a complete message: either the peer sent a message
             * larger than our buffer, or we are stuck in garbage. Both are fatal. */
            p->failed = IUCM_ERR_CAPACITY;
            return p->failed;
        }
        take = (n < room) ? n : room;
        memcpy(p->buf + p->len, data, take);
        p->len += take;
        data += take;
        n -= take;

        rc = parser_drain(p, cb, ctx);
        if (rc != IUCM_OK) {
            p->failed = rc;
            return rc;
        }
    }
    return IUCM_OK;
}

/* ----------------------------------------------------------------- encoders */

static int frame_begin(uint8_t *out, size_t cap, size_t payload_len, uint8_t type,
                       uint8_t flags, size_t *written) {
    if (!out || !written) return IUCM_ERR_BADARG;
    if (payload_len > IUCM_MAX_PAYLOAD) return IUCM_ERR_OVERSIZE;
    if (cap < IUCM_HEADER_SIZE + payload_len) return IUCM_ERR_CAPACITY;
    iucm_write_header(out, type, flags, (uint32_t)payload_len);
    *written = IUCM_HEADER_SIZE + payload_len;
    return IUCM_OK;
}

int iucm_encode_hello(uint8_t *out, size_t cap, const struct iucm_hello *h,
                      size_t *written) {
    size_t   name_len, app_len, payload = 0, off;
    unsigned i;
    int      rc;

    if (!h) return IUCM_ERR_BADARG;
    if (h->camera_count > IUCM_MAX_CAMERAS) return IUCM_ERR_RANGE;
    name_len = strlen(h->name);
    app_len  = strlen(h->app_version);
    if (name_len > 255 || app_len > 255) return IUCM_ERR_RANGE;
    payload = 2 + 1 + name_len + 1 + app_len + 1;
    for (i = 0; i < h->camera_count; i++) {
        size_t cn = strlen(h->cameras[i].name);
        if (cn > 255) return IUCM_ERR_RANGE;
        payload += 3 + cn;
    }
    rc = frame_begin(out, cap, payload, IUCM_MSG_HELLO, 0, written);
    if (rc != IUCM_OK) return rc;

    off = IUCM_HEADER_SIZE;
    put_u16(out + off, h->version);
    off += 2;
    out[off++] = (uint8_t)name_len;
    memcpy(out + off, h->name, name_len);
    off += name_len;
    out[off++] = (uint8_t)app_len;
    memcpy(out + off, h->app_version, app_len);
    off += app_len;
    out[off++] = h->camera_count;
    for (i = 0; i < h->camera_count; i++) {
        size_t cn  = strlen(h->cameras[i].name);
        out[off++] = h->cameras[i].id;
        out[off++] = h->cameras[i].position;
        out[off++] = (uint8_t)cn;
        memcpy(out + off, h->cameras[i].name, cn);
        off += cn;
    }
    return IUCM_OK;
}

int iucm_encode_start(uint8_t *out, size_t cap, const struct iucm_start *s,
                      size_t *written) {
    size_t off;
    int    rc;
    if (!s) return IUCM_ERR_BADARG;
    /* The short form stays the default: a 1.0 app treats a surplus byte as a
     * framing error, so the flags byte is only written when it carries a wish. */
    rc = frame_begin(out, cap, s->flags != 0 ? 12u : 11u, IUCM_MSG_START, 0, written);
    if (rc != IUCM_OK) return rc;
    off        = IUCM_HEADER_SIZE;
    out[off++] = s->camera_id;
    put_u16(out + off, s->width);
    off += 2;
    put_u16(out + off, s->height);
    off += 2;
    put_u16(out + off, s->fps);
    off += 2;
    put_u32(out + off, s->bitrate_kbps);
    off += 4;
    if (s->flags != 0) out[off] = s->flags;
    return IUCM_OK;
}

int iucm_encode_stop(uint8_t *out, size_t cap, size_t *written) {
    return frame_begin(out, cap, 0, IUCM_MSG_STOP, 0, written);
}

int iucm_encode_client_info(uint8_t *out, size_t cap, const struct iucm_client_info *ci,
                            size_t *written) {
    size_t name_len, ver_len, off;
    int    rc;

    if (!ci) return IUCM_ERR_BADARG;
    name_len = strlen(ci->name);
    ver_len  = strlen(ci->version);
    if (name_len > 255 || ver_len > 255) return IUCM_ERR_RANGE;
    rc = frame_begin(out, cap, 3 + name_len + ver_len, IUCM_MSG_CLIENT_INFO, 0, written);
    if (rc != IUCM_OK) return rc;
    off        = IUCM_HEADER_SIZE;
    out[off++] = ci->kind;
    out[off++] = (uint8_t)name_len;
    memcpy(out + off, ci->name, name_len);
    off += name_len;
    out[off++] = (uint8_t)ver_len;
    memcpy(out + off, ci->version, ver_len);
    return IUCM_OK;
}

int iucm_encode_config(uint8_t *out, size_t cap, uint16_t width, uint16_t height,
                       uint16_t fps, const uint8_t *hvcc, uint32_t hvcc_len,
                       size_t *written) {
    size_t off;
    int    rc;
    if (hvcc_len > 0 && !hvcc) return IUCM_ERR_BADARG;
    rc = frame_begin(out, cap, (size_t)10 + hvcc_len, IUCM_MSG_CONFIG, 0, written);
    if (rc != IUCM_OK) return rc;
    off = IUCM_HEADER_SIZE;
    put_u16(out + off, width);
    off += 2;
    put_u16(out + off, height);
    off += 2;
    put_u16(out + off, fps);
    off += 2;
    put_u32(out + off, hvcc_len);
    off += 4;
    if (hvcc_len > 0) memcpy(out + off, hvcc, hvcc_len);
    return IUCM_OK;
}

int iucm_encode_video(uint8_t *out, size_t cap, uint64_t pts_us, int keyframe,
                      const uint8_t *const *nals, const uint32_t *nal_lens,
                      size_t nal_count, size_t *written) {
    size_t payload = 8, off, i;
    int    rc;
    if (nal_count > 0 && (!nals || !nal_lens)) return IUCM_ERR_BADARG;
    for (i = 0; i < nal_count; i++) {
        if (!nals[i] && nal_lens[i] > 0) return IUCM_ERR_BADARG;
        if (nal_lens[i] > IUCM_MAX_PAYLOAD) return IUCM_ERR_OVERSIZE;
        payload += (size_t)4 + nal_lens[i];
        if (payload > IUCM_MAX_PAYLOAD) return IUCM_ERR_OVERSIZE;
    }
    rc = frame_begin(out, cap, payload, IUCM_MSG_VIDEO,
                     keyframe ? (uint8_t)IUCM_FLAG_KEYFRAME : (uint8_t)0, written);
    if (rc != IUCM_OK) return rc;
    off = IUCM_HEADER_SIZE;
    put_u64(out + off, pts_us);
    off += 8;
    for (i = 0; i < nal_count; i++) {
        put_u32_be(out + off, nal_lens[i]);
        off += 4;
        if (nal_lens[i] > 0) memcpy(out + off, nals[i], nal_lens[i]);
        off += nal_lens[i];
    }
    return IUCM_OK;
}

static int encode_ts(uint8_t *out, size_t cap, uint8_t type, uint64_t ts, size_t *written) {
    int rc = frame_begin(out, cap, 8, type, 0, written);
    if (rc != IUCM_OK) return rc;
    put_u64(out + IUCM_HEADER_SIZE, ts);
    return IUCM_OK;
}

int iucm_encode_ping(uint8_t *out, size_t cap, uint64_t timestamp_us, size_t *written) {
    return encode_ts(out, cap, IUCM_MSG_PING, timestamp_us, written);
}
int iucm_encode_pong(uint8_t *out, size_t cap, uint64_t timestamp_us, size_t *written) {
    return encode_ts(out, cap, IUCM_MSG_PONG, timestamp_us, written);
}

int iucm_encode_error(uint8_t *out, size_t cap, uint16_t code, const char *text,
                      size_t *written) {
    size_t tlen = text ? strlen(text) : 0;
    size_t off;
    int    rc;
    if (tlen > 0xFFFFu) return IUCM_ERR_RANGE;
    rc = frame_begin(out, cap, 4 + tlen, IUCM_MSG_ERROR, 0, written);
    if (rc != IUCM_OK) return rc;
    off = IUCM_HEADER_SIZE;
    put_u16(out + off, code);
    off += 2;
    put_u16(out + off, (uint16_t)tlen);
    off += 2;
    if (tlen > 0) memcpy(out + off, text, tlen);
    return IUCM_OK;
}

/* ----------------------------------------------------------------- decoders */

int iucm_parse_hello(const uint8_t *payload, uint32_t len, struct iucm_hello *out) {
    struct cur c;
    uint8_t    n8;
    unsigned   i;
    int        rc;

    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;

    if ((rc = cur_u16(&c, &out->version)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &n8)) != IUCM_OK) return rc;
    if ((rc = cur_str(&c, n8, out->name, sizeof(out->name))) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &n8)) != IUCM_OK) return rc;
    if ((rc = cur_str(&c, n8, out->app_version, sizeof(out->app_version))) != IUCM_OK)
        return rc;
    if ((rc = cur_u8(&c, &out->camera_count)) != IUCM_OK) return rc;
    if (out->camera_count > IUCM_MAX_CAMERAS) return IUCM_ERR_RANGE;
    for (i = 0; i < out->camera_count; i++) {
        struct iucm_camera *cam = &out->cameras[i];
        if ((rc = cur_u8(&c, &cam->id)) != IUCM_OK) return rc;
        if ((rc = cur_u8(&c, &cam->position)) != IUCM_OK) return rc;
        if ((rc = cur_u8(&c, &n8)) != IUCM_OK) return rc;
        if ((rc = cur_str(&c, n8, cam->name, sizeof(cam->name))) != IUCM_OK) return rc;
    }
    /* Trailing bytes are tolerated: minor versions may append fields. */
    return IUCM_OK;
}

int iucm_parse_start(const uint8_t *payload, uint32_t len, struct iucm_start *out) {
    struct cur c;
    int        rc;
    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;
    if ((rc = cur_u8(&c, &out->camera_id)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->width)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->height)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->fps)) != IUCM_OK) return rc;
    if ((rc = cur_u32(&c, &out->bitrate_kbps)) != IUCM_OK) return rc;
    /* The flags byte is optional (PROTOCOL.md 4.2): 11 bytes mean flags == 0,
     * and bytes past the twelfth belong to a later minor version. */
    if (cur_need(&c, 1)) out->flags = c.p[c.off];
    return IUCM_OK;
}

int iucm_parse_client_info(const uint8_t *payload, uint32_t len,
                           struct iucm_client_info *out) {
    struct cur c;
    uint8_t    n8;
    int        rc;

    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;

    if ((rc = cur_u8(&c, &out->kind)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &n8)) != IUCM_OK) return rc;
    if ((rc = cur_str(&c, n8, out->name, sizeof(out->name))) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &n8)) != IUCM_OK) return rc;
    if ((rc = cur_str(&c, n8, out->version, sizeof(out->version))) != IUCM_OK) return rc;
    /* Trailing bytes are tolerated: minor versions may append fields (4.11). */
    return IUCM_OK;
}

int iucm_parse_config(const uint8_t *payload, uint32_t len, struct iucm_config *out) {
    struct cur c;
    int        rc;
    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;
    if ((rc = cur_u16(&c, &out->width)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->height)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->fps)) != IUCM_OK) return rc;
    if ((rc = cur_u32(&c, &out->hvcc_len)) != IUCM_OK) return rc;
    if (!cur_need(&c, out->hvcc_len)) return IUCM_ERR_TRUNCATED;
    out->hvcc = payload + c.off;
    return IUCM_OK;
}

int iucm_parse_error(const uint8_t *payload, uint32_t len, struct iucm_error *out) {
    struct cur c;
    uint32_t   copy;
    int        rc;
    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;
    if ((rc = cur_u16(&c, &out->code)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->text_len)) != IUCM_OK) return rc;
    if (!cur_need(&c, out->text_len)) return IUCM_ERR_TRUNCATED;
    /* Long texts are truncated, not rejected: an error message must never be the
     * reason a connection dies. text_len keeps the on-wire length. */
    copy = out->text_len;
    if (copy > IUCM_ERROR_TEXT_MAX - 1) copy = IUCM_ERROR_TEXT_MAX - 1;
    memcpy(out->text, payload + c.off, copy);
    out->text[copy] = '\0';
    return IUCM_OK;
}

int iucm_parse_timestamp(const uint8_t *payload, uint32_t len, uint64_t *out_us) {
    struct cur c;
    if (!payload || !out_us) return IUCM_ERR_BADARG;
    c.p = payload; c.len = len; c.off = 0;
    return cur_u64(&c, out_us);
}

int iucm_parse_stats(const uint8_t *payload, uint32_t len, struct iucm_stats *out) {
    struct cur c;
    uint16_t v;
    int rc;
    if (!payload || !out) return IUCM_ERR_BADARG;
    if (len < IUCM_STATS_PAYLOAD_SIZE) return IUCM_ERR_TRUNCATED;
    c.p = payload; c.len = len; c.off = 0;
    /* Signed fields travel as two's-complement u16; convert once, here. */
    if ((rc = cur_u16(&c, &v)) != IUCM_OK) return rc;
    out->continuous_angle_x10 = (int16_t)v;
    if ((rc = cur_u16(&c, &out->sector)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &v)) != IUCM_OK) return rc;
    out->residual_x10 = (int16_t)v;
    if ((rc = cur_u16(&c, &out->gravity_m_x1000)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->leveler_ms_x10)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->dropped_frames)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->source_width)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->source_height)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->output_width)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->output_height)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &out->flags)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &out->camera_id)) != IUCM_OK) return rc;
    /* Trailing bytes are tolerated on purpose: a future 1.x may append fields. */
    return IUCM_OK;
}

int iucm_parse_audio_config(const uint8_t *payload, uint32_t len,
                            struct iucm_audio_config *out) {
    struct cur c;
    int        rc;
    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    c.p = payload; c.len = len; c.off = 0;
    if ((rc = cur_u32(&c, &out->sample_rate)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &out->channels)) != IUCM_OK) return rc;
    if ((rc = cur_u8(&c, &out->codec)) != IUCM_OK) return rc;
    if ((rc = cur_u16(&c, &out->asc_len)) != IUCM_OK) return rc;
    if (!cur_need(&c, out->asc_len)) return IUCM_ERR_TRUNCATED;
    /* channels and codec travel unvalidated on purpose (PROTOCOL.md 4.9). */
    if (out->asc_len > 0) out->asc = payload + c.off;
    return IUCM_OK;
}

int iucm_parse_audio(const uint8_t *payload, uint32_t len, struct iucm_audio *out) {
    if (!payload || !out) return IUCM_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    if (len < 8) return IUCM_ERR_TRUNCATED;
    out->pts_us = get_u64(payload);
    out->len    = len - 8u;
    /* An empty frame is valid framing, PROTOCOL.md 4.10; the consumer drops it. */
    if (out->len > 0) out->frame = payload + 8;
    return IUCM_OK;
}

int iucm_video_iter_init(struct iucm_video_iter *it, const uint8_t *payload, uint32_t len) {
    if (!it || !payload) return IUCM_ERR_BADARG;
    if (len < 8) return IUCM_ERR_TRUNCATED;
    it->pts_us    = get_u64(payload);
    it->p         = payload + 8;
    it->remaining = (size_t)len - 8u;
    return IUCM_OK;
}

int iucm_video_iter_next(struct iucm_video_iter *it, const uint8_t **nal,
                         uint32_t *nal_len) {
    uint32_t n;
    if (!it || !nal || !nal_len) return IUCM_ERR_BADARG;
    if (it->remaining == 0) return 0;
    if (it->remaining < 4) return IUCM_ERR_TRUNCATED;
    n = get_u32_be(it->p);
    if ((size_t)n > it->remaining - 4u) return IUCM_ERR_TRUNCATED;
    *nal       = it->p + 4;
    *nal_len   = n;
    it->p += (size_t)4 + n;
    it->remaining -= (size_t)4 + n;
    return 1;
}

const char *iucm_strerror(int code) {
    switch (code) {
    case IUCM_OK:            return "ok";
    case IUCM_ERR_BADARG:    return "bad argument or bad magic";
    case IUCM_ERR_OVERSIZE:  return "message exceeds 8 MiB";
    case IUCM_ERR_CAPACITY:  return "buffer too small";
    case IUCM_ERR_TRUNCATED: return "payload truncated";
    case IUCM_ERR_RANGE:     return "value out of range";
    case IUCM_ERR_ABORTED:   return "aborted by callback";
    default:                 return "unknown error";
    }
}

const char *iucm_type_name(uint8_t type) {
    switch (type) {
    case IUCM_MSG_HELLO:  return "HELLO";
    case IUCM_MSG_START:  return "START";
    case IUCM_MSG_STOP:   return "STOP";
    case IUCM_MSG_CLIENT_INFO: return "CLIENT_INFO";
    case IUCM_MSG_CONFIG: return "CONFIG";
    case IUCM_MSG_VIDEO:  return "VIDEO";
    case IUCM_MSG_AUDIO_CONFIG: return "AUDIO_CONFIG";
    case IUCM_MSG_AUDIO:  return "AUDIO";
    case IUCM_MSG_PING:   return "PING";
    case IUCM_MSG_PONG:   return "PONG";
    case IUCM_MSG_ERROR:  return "ERROR";
    default:              return "UNKNOWN";
    }
}
