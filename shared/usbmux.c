/* usbmux.c — minimal usbmuxd client + hand-written XML plist codec.
 * See protocol/PROTOCOL.md section 6. MIT, (c) 2026 Bernhard Goetzendorfer. */
#define _POSIX_C_SOURCE 200809L

#include "usbmux.h"

#include <errno.h>
#include <stdarg.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define USBMUX_DEFAULT_PROG_NAME      "obs-iphone-usb-cam"
#define USBMUX_DEFAULT_CLIENT_VERSION "obs-iphone-usb-cam-1.0"

/* ------------------------------------------------------------------ header */

static void put_u32le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}
static uint32_t get_u32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

void usbmux_write_header(uint8_t out[USBMUX_HEADER_SIZE], uint32_t payload_len,
                         uint32_t tag) {
    put_u32le(out + 0, USBMUX_HEADER_SIZE + payload_len); /* length INCLUDES the header */
    put_u32le(out + 4, USBMUX_VERSION);
    put_u32le(out + 8, USBMUX_MESSAGE_PLIST);
    put_u32le(out + 12, tag);
}

int usbmux_parse_header(const uint8_t in[USBMUX_HEADER_SIZE], uint32_t *payload_len,
                        uint32_t *version, uint32_t *message, uint32_t *tag) {
    uint32_t total, ver, msg;
    if (!in) return USBMUX_ERR_BADARG;
    total = get_u32le(in + 0);
    ver   = get_u32le(in + 4);
    msg   = get_u32le(in + 8);
    if (total < USBMUX_HEADER_SIZE) return USBMUX_ERR_PROTOCOL;
    if (total - USBMUX_HEADER_SIZE > USBMUX_MAX_PAYLOAD) return USBMUX_ERR_PROTOCOL;
    if (payload_len) *payload_len = total - USBMUX_HEADER_SIZE;
    if (version) *version = ver;
    if (message) *message = msg;
    if (tag) *tag = get_u32le(in + 12);
    return USBMUX_OK;
}

/* ---------------------------------------------------------------- encoders */

#define PLIST_PROLOGUE                                                                    \
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"                                        \
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "                             \
    "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"                               \
    "<plist version=\"1.0\">\n<dict>\n"
#define PLIST_EPILOGUE "</dict>\n</plist>\n"

#if defined(__GNUC__)
__attribute__((format(printf, 4, 5)))
#endif
static int emit(char *out, size_t cap, size_t *written, const char *fmt, ...) {
    va_list ap;
    int     n;
    va_start(ap, fmt);
    n = vsnprintf(out + *written, (cap > *written) ? (cap - *written) : 0, fmt, ap);
    va_end(ap);
    if (n < 0) return USBMUX_ERR_BADARG;
    *written += (size_t)n;
    if (*written >= cap) return USBMUX_ERR_CAPACITY;
    return USBMUX_OK;
}

/* usbmuxd's own serializer sorts keys by byte value, which puts the lowercase
 * kLibUSBMuxVersion last. The fixtures under tests/fixtures/ are byte-exact, so
 * this order is part of the test contract. */
static int encode_simple(char *out, size_t cap, const char *message_type,
                         const char *prog_name, const char *client_version,
                         size_t *written) {
    size_t w  = 0;
    int    rc = USBMUX_OK;
    if (!out || !message_type || !written || cap == 0) return USBMUX_ERR_BADARG;
    if (!prog_name) prog_name = USBMUX_DEFAULT_PROG_NAME;
    if (!client_version) client_version = USBMUX_DEFAULT_CLIENT_VERSION;

    rc = emit(out, cap, &w, "%s", PLIST_PROLOGUE);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>ClientVersionString</key>\n\t<string>%s</string>\n",
              client_version);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>MessageType</key>\n\t<string>%s</string>\n",
              message_type);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>ProgName</key>\n\t<string>%s</string>\n", prog_name);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>kLibUSBMuxVersion</key>\n\t<integer>3</integer>\n");
    if (rc) return rc;
    rc = emit(out, cap, &w, "%s", PLIST_EPILOGUE);
    if (rc) return rc;
    *written = w;
    return USBMUX_OK;
}

int usbmux_plist_encode_listdevices(char *out, size_t cap, const char *prog_name,
                                    const char *client_version, size_t *written) {
    return encode_simple(out, cap, "ListDevices", prog_name, client_version, written);
}

int usbmux_plist_encode_listen(char *out, size_t cap, const char *prog_name,
                               const char *client_version, size_t *written) {
    return encode_simple(out, cap, "Listen", prog_name, client_version, written);
}

int usbmux_plist_encode_connect(char *out, size_t cap, uint32_t device_id, uint16_t port,
                                const char *prog_name, const char *client_version,
                                size_t *written) {
    /* The byte swap lives HERE and nowhere else. A host-order port is answered with
     * the same Number 3 as a closed port, so the mistake is invisible from outside. */
    uint16_t wire_port = (uint16_t)(((port & 0x00FFu) << 8) | ((port & 0xFF00u) >> 8));
    size_t   w         = 0;
    int      rc;
    if (!out || !written || cap == 0) return USBMUX_ERR_BADARG;
    if (!prog_name) prog_name = USBMUX_DEFAULT_PROG_NAME;
    if (!client_version) client_version = USBMUX_DEFAULT_CLIENT_VERSION;

    rc = emit(out, cap, &w, "%s", PLIST_PROLOGUE);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>ClientVersionString</key>\n\t<string>%s</string>\n",
              client_version);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>DeviceID</key>\n\t<integer>%lu</integer>\n",
              (unsigned long)device_id);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>MessageType</key>\n\t<string>Connect</string>\n");
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>PortNumber</key>\n\t<integer>%u</integer>\n",
              (unsigned)wire_port);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>ProgName</key>\n\t<string>%s</string>\n", prog_name);
    if (rc) return rc;
    rc = emit(out, cap, &w, "\t<key>kLibUSBMuxVersion</key>\n\t<integer>3</integer>\n");
    if (rc) return rc;
    rc = emit(out, cap, &w, "%s", PLIST_EPILOGUE);
    if (rc) return rc;
    *written = w;
    return USBMUX_OK;
}

/* ------------------------------------------------------- plist walker (read) */

enum { PX_DICT_BEGIN, PX_DICT_END, PX_ARRAY_BEGIN, PX_ARRAY_END, PX_VALUE };

struct px_slice {
    const char *p;
    size_t      len;
};

/* key/value slices point into the source buffer and are not NUL-terminated. */
typedef int (*px_visitor)(void *ctx, int ev, int depth, struct px_slice key,
                          struct px_slice type, struct px_slice value);

struct px {
    const char *p;
    const char *end;
};

struct px_tag {
    struct px_slice name;
    int             closing;
    int             self_closing;
};

static int px_is_space(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static void px_skip_space(struct px *x) {
    while (x->p < x->end && px_is_space(*x->p)) x->p++;
}

/* Reads the next real element tag, skipping declarations, DOCTYPE and comments. */
static int px_next_tag(struct px *x, struct px_tag *t) {
    for (;;) {
        const char *lt, *gt, *n;
        px_skip_space(x);
        while (x->p < x->end && *x->p != '<') x->p++; /* stray text between elements */
        if (x->p >= x->end) return USBMUX_ERR_NOTFOUND;
        lt = x->p;
        if ((size_t)(x->end - lt) >= 4 && strncmp(lt, "<!--", 4) == 0) {
            const char *e = lt + 4;
            while (e + 3 <= x->end && strncmp(e, "-->", 3) != 0) e++;
            if (e + 3 > x->end) return USBMUX_ERR_PARSE;
            x->p = e + 3;
            continue;
        }
        gt = lt + 1;
        while (gt < x->end && *gt != '>') gt++;
        if (gt >= x->end) return USBMUX_ERR_PARSE;
        if (lt[1] == '?' || lt[1] == '!') { /* <?xml ...?> or <!DOCTYPE ...> */
            x->p = gt + 1;
            continue;
        }
        t->closing      = (lt[1] == '/');
        t->self_closing = (gt[-1] == '/');
        n               = lt + 1 + (t->closing ? 1 : 0);
        t->name.p       = n;
        {
            const char *e = n;
            while (e < gt && !px_is_space(*e) && *e != '/') e++;
            t->name.len = (size_t)(e - n);
        }
        x->p = gt + 1;
        return USBMUX_OK;
    }
}

static int px_name_is(struct px_slice s, const char *lit) {
    size_t n = strlen(lit);
    return s.len == n && strncmp(s.p, lit, n) == 0;
}

/* Text up to the next '<'; the caller consumes the closing tag afterwards. */
static int px_text(struct px *x, struct px_slice *out) {
    const char *start = x->p;
    while (x->p < x->end && *x->p != '<') x->p++;
    if (x->p >= x->end) return USBMUX_ERR_PARSE;
    out->p   = start;
    out->len = (size_t)(x->p - start);
    return USBMUX_OK;
}

#define PX_MAX_DEPTH 16

static int px_parse_value(struct px *x, struct px_tag *tag, struct px_slice key, int depth,
                          px_visitor v, void *ctx);

static int px_parse_container(struct px *x, int is_dict, struct px_slice key, int depth,
                              px_visitor v, void *ctx) {
    struct px_slice empty = {NULL, 0};
    int             rc;

    if (depth >= PX_MAX_DEPTH) return USBMUX_ERR_PARSE;
    rc = v(ctx, is_dict ? PX_DICT_BEGIN : PX_ARRAY_BEGIN, depth, key, empty, empty);
    if (rc) return rc;

    for (;;) {
        struct px_tag   t;
        struct px_slice child_key = {NULL, 0};
        rc                        = px_next_tag(x, &t);
        if (rc) return rc;
        if (t.closing) {
            if (!px_name_is(t.name, is_dict ? "dict" : "array")) return USBMUX_ERR_PARSE;
            return v(ctx, is_dict ? PX_DICT_END : PX_ARRAY_END, depth, key, empty, empty);
        }
        if (is_dict) {
            if (!px_name_is(t.name, "key")) return USBMUX_ERR_PARSE;
            rc = px_text(x, &child_key);
            if (rc) return rc;
            rc = px_next_tag(x, &t); /* </key> */
            if (rc) return rc;
            if (!t.closing || !px_name_is(t.name, "key")) return USBMUX_ERR_PARSE;
            rc = px_next_tag(x, &t); /* the value's opening tag */
            if (rc) return rc;
            if (t.closing) return USBMUX_ERR_PARSE;
        }
        rc = px_parse_value(x, &t, child_key, depth + 1, v, ctx);
        if (rc) return rc;
    }
}

static int px_parse_value(struct px *x, struct px_tag *tag, struct px_slice key, int depth,
                          px_visitor v, void *ctx) {
    struct px_slice empty = {NULL, 0};
    struct px_slice text  = {NULL, 0};
    struct px_tag   close;
    int             rc;

    if (px_name_is(tag->name, "dict")) return px_parse_container(x, 1, key, depth, v, ctx);
    if (px_name_is(tag->name, "array")) return px_parse_container(x, 0, key, depth, v, ctx);

    if (tag->self_closing) /* <true/>, <false/> */
        return v(ctx, PX_VALUE, depth, key, tag->name, empty);

    rc = px_text(x, &text);
    if (rc) return rc;
    rc = px_next_tag(x, &close);
    if (rc) return rc;
    if (!close.closing || close.name.len != tag->name.len ||
        strncmp(close.name.p, tag->name.p, tag->name.len) != 0)
        return USBMUX_ERR_PARSE;
    return v(ctx, PX_VALUE, depth, key, tag->name, text);
}

static int px_walk(const char *xml, size_t len, px_visitor v, void *ctx) {
    struct px       x;
    struct px_tag   t;
    struct px_slice none = {NULL, 0};
    int             rc;
    if (!xml || !v) return USBMUX_ERR_BADARG;
    x.p   = xml;
    x.end = xml + len;
    rc    = px_next_tag(&x, &t); /* <plist> */
    if (rc) return rc;
    if (!px_name_is(t.name, "plist")) return USBMUX_ERR_PARSE;
    rc = px_next_tag(&x, &t); /* root value */
    if (rc) return rc;
    return px_parse_value(&x, &t, none, 0, v, ctx);
}

/* ---------------------------------------------------------------- decoders */

static int slice_eq(struct px_slice s, const char *lit) {
    size_t n = strlen(lit);
    return s.len == n && strncmp(s.p, lit, n) == 0;
}

static void slice_copy(struct px_slice s, char *dst, size_t cap) {
    size_t n = (s.len < cap - 1) ? s.len : cap - 1;
    /* The messages we handle carry no XML entities; a literal '&' would arrive
     * escaped and is copied verbatim rather than silently mangled. */
    memcpy(dst, s.p, n);
    dst[n] = '\0';
}

static uint32_t slice_u32(struct px_slice s) {
    char buf[24];
    slice_copy(s, buf, sizeof(buf));
    return (uint32_t)strtoul(buf, NULL, 10);
}

/* --- MessageType --- */
struct mt_ctx {
    char   out[64];
    int    found;
};
static int mt_visit(void *c, int ev, int depth, struct px_slice key, struct px_slice type,
                    struct px_slice value) {
    struct mt_ctx *m = (struct mt_ctx *)c;
    (void)type;
    if (ev == PX_VALUE && depth == 1 && slice_eq(key, "MessageType")) {
        slice_copy(value, m->out, sizeof(m->out));
        m->found = 1;
    }
    return 0;
}

int usbmux_plist_message_type(const char *xml, size_t len, char *out, size_t cap) {
    struct mt_ctx m;
    int           rc;
    if (!out || cap == 0) return USBMUX_ERR_BADARG;
    m.found = 0;
    m.out[0] = '\0';
    rc = px_walk(xml, len, mt_visit, &m);
    if (rc) return rc;
    if (!m.found) return USBMUX_ERR_NOTFOUND;
    if (strlen(m.out) + 1 > cap) return USBMUX_ERR_CAPACITY;
    memcpy(out, m.out, strlen(m.out) + 1);
    return USBMUX_OK;
}

/* --- Result --- */
struct res_ctx {
    uint32_t number;
    int      have_number;
    char     type[32];
};
static int res_visit(void *c, int ev, int depth, struct px_slice key, struct px_slice type,
                     struct px_slice value) {
    struct res_ctx *r = (struct res_ctx *)c;
    (void)type;
    if (ev != PX_VALUE || depth != 1) return 0;
    if (slice_eq(key, "MessageType")) slice_copy(value, r->type, sizeof(r->type));
    if (slice_eq(key, "Number")) {
        r->number      = slice_u32(value);
        r->have_number = 1;
    }
    return 0;
}

int usbmux_plist_decode_result(const char *xml, size_t len, uint32_t *number) {
    struct res_ctx r;
    int            rc;
    if (!number) return USBMUX_ERR_BADARG;
    memset(&r, 0, sizeof(r));
    rc = px_walk(xml, len, res_visit, &r);
    if (rc) return rc;
    if (strcmp(r.type, "Result") != 0) return USBMUX_ERR_NOTFOUND;
    if (!r.have_number) return USBMUX_ERR_NOTFOUND;
    *number = r.number;
    return USBMUX_OK;
}

/* --- device records, shared by DeviceList and Attached --- */
struct dev_ctx {
    struct usbmux_device *out;
    size_t                max;
    size_t                count;
    int                   overflow;
    int                   base_depth; /* depth of the per-device dict */
    struct usbmux_device  cur;
    int                   cur_is_usb;
    int                   cur_open;
    char                  msgtype[32];
};

static void dev_reset(struct dev_ctx *d) {
    memset(&d->cur, 0, sizeof(d->cur));
    d->cur_is_usb = 0;
}

static void dev_commit(struct dev_ctx *d) {
    if (!d->cur_is_usb) return; /* Network twin of the same phone — see PROTOCOL 6.5 */
    if (d->count >= d->max) {
        d->overflow = 1;
        return;
    }
    d->out[d->count++] = d->cur;
}

static int dev_visit(void *c, int ev, int depth, struct px_slice key, struct px_slice type,
                     struct px_slice value) {
    struct dev_ctx *d = (struct dev_ctx *)c;
    (void)type;
    if (ev == PX_DICT_BEGIN && depth == d->base_depth) {
        dev_reset(d);
        d->cur_open = 1;
        return 0;
    }
    if (ev == PX_DICT_END && depth == d->base_depth && d->cur_open) {
        dev_commit(d);
        d->cur_open = 0;
        return 0;
    }
    if (ev != PX_VALUE) return 0;
    if (depth == 1 && slice_eq(key, "MessageType"))
        slice_copy(value, d->msgtype, sizeof(d->msgtype));
    if (!d->cur_open) return 0;
    if (depth == d->base_depth + 1 && slice_eq(key, "DeviceID"))
        d->cur.device_id = slice_u32(value);
    if (depth == d->base_depth + 2) { /* inside Properties */
        if (slice_eq(key, "ConnectionType")) d->cur_is_usb = slice_eq(value, "USB");
        if (slice_eq(key, "SerialNumber")) slice_copy(value, d->cur.serial,
                                                      sizeof(d->cur.serial));
        if (slice_eq(key, "ProductID")) d->cur.product_id = slice_u32(value);
        if (slice_eq(key, "DeviceID") && d->cur.device_id == 0)
            d->cur.device_id = slice_u32(value);
    }
    return 0;
}

int usbmux_plist_decode_devicelist(const char *xml, size_t len, struct usbmux_device *out,
                                   size_t max, size_t *count) {
    struct dev_ctx d;
    int            rc;
    if (!out || !count || max == 0) return USBMUX_ERR_BADARG;
    memset(&d, 0, sizeof(d));
    d.out        = out;
    d.max        = max;
    d.base_depth = 2; /* root dict(0) -> DeviceList array(1) -> device dict(2) */
    rc           = px_walk(xml, len, dev_visit, &d);
    if (rc) return rc;
    *count = d.count;
    return d.overflow ? USBMUX_ERR_CAPACITY : USBMUX_OK;
}

int usbmux_plist_decode_event(const char *xml, size_t len, struct usbmux_event *out) {
    struct dev_ctx       d;
    struct usbmux_device slot;
    int                  rc;
    if (!out) return USBMUX_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    memset(&d, 0, sizeof(d));
    memset(&slot, 0, sizeof(slot));
    d.out        = &slot;
    d.max        = 1;
    d.base_depth = 0; /* the root dict IS the device record */
    rc           = px_walk(xml, len, dev_visit, &d);
    if (rc) return rc;

    if (strcmp(d.msgtype, "Detached") == 0) {
        out->type             = USBMUX_EVENT_DETACHED;
        out->device.device_id = d.cur.device_id; /* Detached carries no Properties */
        return USBMUX_OK;
    }
    if (strcmp(d.msgtype, "Attached") != 0) return USBMUX_ERR_NOTFOUND;
    if (d.count == 0) { /* filtered: Network twin */
        out->type = USBMUX_EVENT_NONE;
        return USBMUX_OK;
    }
    out->type   = USBMUX_EVENT_ATTACHED;
    out->device = slot;
    return USBMUX_OK;
}

/* ------------------------------------------------------------ socket layer */

static int ux_open_socket(void) {
    struct sockaddr_un addr;
    int                fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, USBMUX_SOCKET_PATH, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    return fd;
}

static int ux_write_all(int fd, const uint8_t *p, size_t n) {
    while (n > 0) {
        ssize_t w = write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return USBMUX_ERR_IO;
        }
        if (w == 0) return USBMUX_ERR_IO;
        p += (size_t)w;
        n -= (size_t)w;
    }
    return USBMUX_OK;
}

static int ux_read_all(int fd, uint8_t *p, size_t n, int timeout_ms) {
    while (n > 0) {
        ssize_t r;
        if (timeout_ms >= 0) {
            struct pollfd pfd;
            int           pr;
            pfd.fd     = fd;
            pfd.events = POLLIN;
            pfd.revents = 0;
            pr         = poll(&pfd, 1, timeout_ms);
            if (pr == 0) return USBMUX_ERR_TIMEOUT;
            if (pr < 0) {
                if (errno == EINTR) continue;
                return USBMUX_ERR_IO;
            }
        }
        r = read(fd, p, n);
        if (r < 0) {
            if (errno == EINTR) continue;
            return USBMUX_ERR_IO;
        }
        if (r == 0) return USBMUX_ERR_IO; /* peer closed */
        p += (size_t)r;
        n -= (size_t)r;
    }
    return USBMUX_OK;
}

static int ux_send_plist(int fd, uint32_t tag, const char *xml, size_t len) {
    uint8_t hdr[USBMUX_HEADER_SIZE];
    int     rc;
    usbmux_write_header(hdr, (uint32_t)len, tag);
    rc = ux_write_all(fd, hdr, sizeof(hdr));
    if (rc) return rc;
    return ux_write_all(fd, (const uint8_t *)xml, len);
}

/* Reads one framed plist message into buf. */
static int ux_recv_plist(int fd, char *buf, size_t cap, size_t *len, uint32_t *tag,
                         int timeout_ms) {
    uint8_t  hdr[USBMUX_HEADER_SIZE];
    uint32_t payload_len = 0, version = 0, message = 0;
    int      rc = ux_read_all(fd, hdr, sizeof(hdr), timeout_ms);
    if (rc) return rc;
    rc = usbmux_parse_header(hdr, &payload_len, &version, &message, tag);
    if (rc) return rc;
    if (version != USBMUX_VERSION || message != USBMUX_MESSAGE_PLIST)
        return USBMUX_ERR_PROTOCOL;
    if (payload_len >= cap) return USBMUX_ERR_CAPACITY;
    rc = ux_read_all(fd, (uint8_t *)buf, payload_len, timeout_ms);
    if (rc) return rc;
    buf[payload_len] = '\0';
    *len             = payload_len;
    return USBMUX_OK;
}

int usbmux_list_devices(struct usbmux_device *out, size_t max, size_t *count) {
    char     req[1024];
    char    *resp;
    size_t   req_len = 0, resp_len = 0;
    uint32_t tag     = 0;
    int      fd, rc;

    if (!out || !count || max == 0) return USBMUX_ERR_BADARG;
    *count = 0;
    rc     = usbmux_plist_encode_listdevices(req, sizeof(req), NULL, NULL, &req_len);
    if (rc) return rc;

    fd = ux_open_socket();
    if (fd < 0) return USBMUX_ERR_IO;

    resp = (char *)malloc(USBMUX_MAX_PAYLOAD + 1);
    if (!resp) {
        close(fd);
        return USBMUX_ERR_IO;
    }
    rc = ux_send_plist(fd, 1, req, req_len);
    if (rc == USBMUX_OK)
        rc = ux_recv_plist(fd, resp, USBMUX_MAX_PAYLOAD + 1, &resp_len, &tag, 5000);
    if (rc == USBMUX_OK) rc = usbmux_plist_decode_devicelist(resp, resp_len, out, max, count);
    free(resp);
    close(fd);
    return rc;
}

int usbmux_connect(uint32_t device_id, uint16_t port, int *result) {
    char     req[1024], resp[4096];
    size_t   req_len = 0, resp_len = 0;
    uint32_t tag = 0, number = 0;
    int      fd, rc;

    if (result) *result = -1;
    /* port stays in host order all the way down: the swap happens in the encoder. */
    rc = usbmux_plist_encode_connect(req, sizeof(req), device_id, port, NULL, NULL,
                                     &req_len);
    if (rc) return -1;

    fd = ux_open_socket();
    if (fd < 0) return -1;

    rc = ux_send_plist(fd, 3, req, req_len);
    if (rc == USBMUX_OK) rc = ux_recv_plist(fd, resp, sizeof(resp), &resp_len, &tag, 5000);
    if (rc == USBMUX_OK) rc = usbmux_plist_decode_result(resp, resp_len, &number);
    if (rc != USBMUX_OK) {
        close(fd);
        return -1;
    }
    if (result) *result = (int)number;
    if (number != USBMUX_RESULT_OK) {
        close(fd);
        return -1;
    }
    /* From here the socket is a raw byte tunnel to the device port. */
    return fd;
}

int usbmux_listen(int *fd_out) {
    char     req[1024], resp[4096];
    size_t   req_len = 0, resp_len = 0;
    uint32_t tag = 0, number = 0;
    int      fd, rc;

    if (!fd_out) return USBMUX_ERR_BADARG;
    *fd_out = -1;
    rc      = usbmux_plist_encode_listen(req, sizeof(req), NULL, NULL, &req_len);
    if (rc) return rc;

    fd = ux_open_socket();
    if (fd < 0) return USBMUX_ERR_IO;

    rc = ux_send_plist(fd, 2, req, req_len);
    if (rc == USBMUX_OK) rc = ux_recv_plist(fd, resp, sizeof(resp), &resp_len, &tag, 5000);
    if (rc == USBMUX_OK) rc = usbmux_plist_decode_result(resp, resp_len, &number);
    if (rc != USBMUX_OK) {
        close(fd);
        return rc;
    }
    if (number != USBMUX_RESULT_OK) {
        close(fd);
        return USBMUX_ERR_RESULT;
    }
    *fd_out = fd;
    return USBMUX_OK;
}

#define USBMUX_EVENT_BUF 65536

int usbmux_listen_next(int fd, struct usbmux_event *out, int timeout_ms) {
    char     resp[USBMUX_EVENT_BUF];
    size_t   resp_len = 0;
    uint32_t tag      = 0;
    int      rc;
    if (!out || fd < 0) return USBMUX_ERR_BADARG;
    memset(out, 0, sizeof(*out));
    rc = ux_recv_plist(fd, resp, sizeof(resp), &resp_len, &tag, timeout_ms);
    if (rc) return rc;
    /* Events carry tag 0, not the tag of the Listen request. Filtering by the
     * request tag here would silently drop every event. */
    return usbmux_plist_decode_event(resp, resp_len, out);
}

const char *usbmux_strerror(int code) {
    switch (code) {
    case USBMUX_OK:           return "ok";
    case USBMUX_ERR_BADARG:   return "bad argument";
    case USBMUX_ERR_CAPACITY: return "buffer too small";
    case USBMUX_ERR_PARSE:    return "malformed plist";
    case USBMUX_ERR_NOTFOUND: return "expected key or message type missing";
    case USBMUX_ERR_IO:       return "socket error";
    case USBMUX_ERR_PROTOCOL: return "bad usbmux header";
    case USBMUX_ERR_TIMEOUT:  return "timeout";
    case USBMUX_ERR_RESULT:   return "usbmuxd returned a non-zero Number";
    default:                  return "unknown error";
    }
}
