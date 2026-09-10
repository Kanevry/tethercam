/* Tests for shared/frame_parser.c — framing, round-trips, resync, bounds. */
#include "../frame_parser.h"
#include "test_util.h"

/* ---- collecting callback ---------------------------------------------- */

#define MAX_COLLECT 32
#define COPY_MAX    4096

struct collected {
    uint8_t  type;
    uint8_t  flags;
    uint32_t length;
    uint8_t  payload[COPY_MAX];
};

struct sink {
    struct collected msgs[MAX_COLLECT];
    size_t           count;
    int              abort_after; /* -1 = never */
};

static int sink_cb(void *ctx, const struct iucm_msg *m) {
    struct sink *s = (struct sink *)ctx;
    if (s->count < MAX_COLLECT) {
        struct collected *c = &s->msgs[s->count];
        c->type             = m->type;
        c->flags            = m->flags;
        c->length           = m->length;
        if (m->length <= COPY_MAX) memcpy(c->payload, m->payload, m->length);
        s->count++;
    }
    if (s->abort_after >= 0 && (int)s->count >= s->abort_after) return 1;
    return 0;
}

static void sink_init(struct sink *s) {
    memset(s, 0, sizeof(*s));
    s->abort_after = -1;
}

/* ---- header ------------------------------------------------------------ */

static void test_header_roundtrip(void) {
    uint8_t  h[IUCM_HEADER_SIZE];
    uint8_t  type = 0, flags = 0;
    uint32_t len = 0;

    iucm_write_header(h, IUCM_MSG_VIDEO, IUCM_FLAG_KEYFRAME, 0x0078CDEF);
    CHECK_EQ_INT(h[0], 'I');
    CHECK_EQ_INT(h[1], 'U');
    CHECK_EQ_INT(h[2], 'C');
    CHECK_EQ_INT(h[3], 'M');
    CHECK_EQ_INT(h[4], IUCM_MSG_VIDEO);
    CHECK_EQ_INT(h[5], IUCM_FLAG_KEYFRAME);
    CHECK_EQ_INT(h[6], 0);
    CHECK_EQ_INT(h[7], 0);
    /* length is little-endian */
    CHECK_EQ_INT(h[8], 0xEF);
    CHECK_EQ_INT(h[9], 0xCD);
    CHECK_EQ_INT(h[10], 0x78);
    CHECK_EQ_INT(h[11], 0x00);

    CHECK_EQ_INT(iucm_read_header(h, &type, &flags, &len), IUCM_OK);
    CHECK_EQ_INT(type, IUCM_MSG_VIDEO);
    CHECK_EQ_INT(flags, IUCM_FLAG_KEYFRAME);
    CHECK_EQ_INT(len, 0x0078CDEF);

    h[1] = 'X';
    CHECK_EQ_INT(iucm_read_header(h, &type, &flags, &len), IUCM_ERR_BADARG);
}

static void test_version_constant(void) {
    CHECK_EQ_INT(IUCM_VERSION_1_0, 0x0100);
    CHECK_EQ_INT(IUCM_VERSION_MAJOR(IUCM_VERSION_1_0), 1);
    CHECK_EQ_INT(IUCM_VERSION_MINOR(IUCM_VERSION_1_0), 0);
    CHECK_EQ_INT(IUCM_VERSION_1_1, 0x0101);
    CHECK_EQ_INT(IUCM_VERSION_MAJOR(IUCM_VERSION_1_1), 1);
    CHECK_EQ_INT(IUCM_VERSION_MINOR(IUCM_VERSION_1_1), 1);
}

/* ---- round-trips ------------------------------------------------------- */

static void test_roundtrip_hello(void) {
    struct iucm_hello in, out;
    uint8_t           buf[512];
    size_t            n = 0;
    struct sink       s;
    struct iucm_parser p;
    uint8_t            pbuf[1024];

    memset(&in, 0, sizeof(in));
    in.version = IUCM_VERSION_1_0;
    strcpy(in.name, "iPhone von Bernhard");
    strcpy(in.app_version, "1.0.0");
    in.camera_count   = 3;
    in.cameras[0].id  = 0;
    in.cameras[0].position = IUCM_CAMERA_BACK;
    strcpy(in.cameras[0].name, "Rueck-Weitwinkel");
    in.cameras[1].id       = 1;
    in.cameras[1].position = IUCM_CAMERA_BACK;
    strcpy(in.cameras[1].name, "Rueck-Ultraweit");
    in.cameras[2].id       = 2;
    in.cameras[2].position = IUCM_CAMERA_FRONT;
    strcpy(in.cameras[2].name, "Front");

    CHECK_EQ_INT(iucm_encode_hello(buf, sizeof(buf), &in, &n), IUCM_OK);
    /* 12 hdr + 2 ver + 1+19 name + 1+5 app + 1 count + (3+16)+(3+15)+(3+5) */
    CHECK_EQ_INT(n, 12 + 2 + 20 + 6 + 1 + 19 + 18 + 8);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 1);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_HELLO);

    CHECK_EQ_INT(iucm_parse_hello(s.msgs[0].payload, s.msgs[0].length, &out), IUCM_OK);
    CHECK_EQ_INT(out.version, IUCM_VERSION_1_0);
    CHECK_EQ_STR(out.name, "iPhone von Bernhard");
    CHECK_EQ_STR(out.app_version, "1.0.0");
    CHECK_EQ_INT(out.camera_count, 3);
    CHECK_EQ_INT(out.cameras[1].id, 1);
    CHECK_EQ_STR(out.cameras[1].name, "Rueck-Ultraweit");
    CHECK_EQ_INT(out.cameras[2].position, IUCM_CAMERA_FRONT);
    CHECK_EQ_STR(out.cameras[2].name, "Front");
}

static void test_roundtrip_start_stop(void) {
    struct iucm_start in = {2, 1920, 1080, 30, 12000, 0}, out;
    uint8_t           buf[64];
    size_t            n = 0;
    struct sink       s;
    struct iucm_parser p;
    uint8_t            pbuf[256];

    CHECK_EQ_INT(iucm_encode_start(buf, sizeof(buf), &in, &n), IUCM_OK);
    CHECK_EQ_INT(n, 12 + 11);
    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_START);
    CHECK_EQ_INT(s.msgs[0].length, 11);
    CHECK_EQ_INT(iucm_parse_start(s.msgs[0].payload, s.msgs[0].length, &out), IUCM_OK);
    CHECK_EQ_INT(out.camera_id, 2);
    CHECK_EQ_INT(out.width, 1920);
    CHECK_EQ_INT(out.height, 1080);
    CHECK_EQ_INT(out.fps, 30);
    CHECK_EQ_INT(out.bitrate_kbps, 12000);

    CHECK_EQ_INT(iucm_encode_stop(buf, sizeof(buf), &n), IUCM_OK);
    CHECK_EQ_INT(n, 12);
    sink_init(&s);
    iucm_parser_reset(&p);
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 1);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_STOP);
    CHECK_EQ_INT(s.msgs[0].length, 0);
}

/* PROTOCOL.md 4.2: 11 and 12 bytes are both valid, longer is not an error. */
static void test_start_flags_lengths(void) {
    struct iucm_start in = {3, 1280, 720, 60, 8000, IUCM_START_FLAG_AUDIO}, out;
    uint8_t           buf[64];
    size_t            n = 0;

    /* flags set -> 12-byte payload */
    CHECK_EQ_INT(iucm_encode_start(buf, sizeof(buf), &in, &n), IUCM_OK);
    CHECK_EQ_INT(n, 12 + 12);
    CHECK_EQ_INT(buf[12 + 11], IUCM_START_FLAG_AUDIO);
    CHECK_EQ_INT(iucm_parse_start(buf + 12, 12, &out), IUCM_OK);
    CHECK_EQ_INT(out.camera_id, 3);
    CHECK_EQ_INT(out.width, 1280);
    CHECK_EQ_INT(out.height, 720);
    CHECK_EQ_INT(out.fps, 60);
    CHECK_EQ_INT(out.bitrate_kbps, 8000);
    CHECK_EQ_INT(out.flags, IUCM_START_FLAG_AUDIO);

    /* flags clear -> 1.0-compatible 11-byte payload */
    in.flags = 0;
    CHECK_EQ_INT(iucm_encode_start(buf, sizeof(buf), &in, &n), IUCM_OK);
    CHECK_EQ_INT(n, 12 + 11);
    CHECK_EQ_INT(iucm_parse_start(buf + 12, 11, &out), IUCM_OK);
    CHECK_EQ_INT(out.flags, 0);
    CHECK_EQ_INT(out.bitrate_kbps, 8000);

    /* 13 bytes: the surplus byte is ignored, flags still read from offset 11 */
    {
        uint8_t payload[13];
        memset(payload, 0, sizeof(payload));
        payload[0]  = 7;
        payload[11] = IUCM_START_FLAG_AUDIO;
        payload[12] = 0xAB;
        CHECK_EQ_INT(iucm_parse_start(payload, 13, &out), IUCM_OK);
        CHECK_EQ_INT(out.camera_id, 7);
        CHECK_EQ_INT(out.flags, IUCM_START_FLAG_AUDIO);
    }

    /* 10 bytes is short of the 1.0 minimum and stays an error */
    {
        uint8_t payload[10];
        memset(payload, 0, sizeof(payload));
        CHECK_EQ_INT(iucm_parse_start(payload, 10, &out), IUCM_ERR_TRUNCATED);
    }
}

/* PROTOCOL.md 4.9 / 4.10. */
static void test_parse_audio_config_and_audio(void) {
    struct iucm_audio_config ac;
    struct iucm_audio        au;

    {
        /* 48000 Hz, 1 channel, AAC-LC, 2-byte ASC */
        uint8_t payload[10] = {0x80, 0xBB, 0x00, 0x00, 1, IUCM_AUDIO_CODEC_AAC_LC,
                               0x02, 0x00, 0x11, 0x90};
        CHECK_EQ_INT(iucm_parse_audio_config(payload, sizeof(payload), &ac), IUCM_OK);
        CHECK_EQ_INT(ac.sample_rate, 48000);
        CHECK_EQ_INT(ac.channels, 1);
        CHECK_EQ_INT(ac.codec, IUCM_AUDIO_CODEC_AAC_LC);
        CHECK_EQ_INT(ac.asc_len, 2);
        CHECK(ac.asc == payload + 8);
        CHECK_EQ_INT(ac.asc[0], 0x11);
        CHECK_EQ_INT(ac.asc[1], 0x90);

        /* asc_len past the payload end is truncated, not a buffer overread */
        CHECK_EQ_INT(iucm_parse_audio_config(payload, 9, &ac), IUCM_ERR_TRUNCATED);
        /* a header without the asc_len field is truncated as well */
        CHECK_EQ_INT(iucm_parse_audio_config(payload, 7, &ac), IUCM_ERR_TRUNCATED);
        /* asc_len == 0 is legal on the wire */
        payload[6] = 0;
        CHECK_EQ_INT(iucm_parse_audio_config(payload, 8, &ac), IUCM_OK);
        CHECK_EQ_INT(ac.asc_len, 0);
        CHECK(ac.asc == NULL);
        /* an unknown codec is passed through, never rejected */
        payload[5] = 99;
        CHECK_EQ_INT(iucm_parse_audio_config(payload, 8, &ac), IUCM_OK);
        CHECK_EQ_INT(ac.codec, 99);
    }
    {
        uint8_t payload[11] = {0x40, 0xE2, 0x01, 0, 0, 0, 0, 0, 0xDE, 0xAD, 0xBE};
        CHECK_EQ_INT(iucm_parse_audio(payload, sizeof(payload), &au), IUCM_OK);
        CHECK_EQ_INT(au.pts_us, 123456);
        CHECK_EQ_INT(au.len, 3);
        CHECK(au.frame == payload + 8);
        CHECK_EQ_INT(au.frame[0], 0xDE);

        /* an empty frame is valid framing and carries nothing */
        CHECK_EQ_INT(iucm_parse_audio(payload, 8, &au), IUCM_OK);
        CHECK_EQ_INT(au.pts_us, 123456);
        CHECK_EQ_INT(au.len, 0);
        CHECK(au.frame == NULL);

        /* a pts that does not fit is a truncated payload */
        CHECK_EQ_INT(iucm_parse_audio(payload, 7, &au), IUCM_ERR_TRUNCATED);
    }
    CHECK_EQ_STR(iucm_type_name(IUCM_MSG_AUDIO_CONFIG), "AUDIO_CONFIG");
    CHECK_EQ_STR(iucm_type_name(IUCM_MSG_AUDIO), "AUDIO");
}

static void test_roundtrip_config(void) {
    const uint8_t      hvcc[] = {0x01, 0x02, 0x20, 0x00, 0xFF, 0x42};
    uint8_t            buf[128];
    size_t             n = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[256];
    struct iucm_config cfg;

    CHECK_EQ_INT(iucm_encode_config(buf, sizeof(buf), 1920, 1080, 30, hvcc, sizeof(hvcc),
                                    &n),
                 IUCM_OK);
    CHECK_EQ_INT(n, 12 + 10 + (int)sizeof(hvcc));
    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_CONFIG);
    CHECK_EQ_INT(iucm_parse_config(s.msgs[0].payload, s.msgs[0].length, &cfg), IUCM_OK);
    CHECK_EQ_INT(cfg.width, 1920);
    CHECK_EQ_INT(cfg.height, 1080);
    CHECK_EQ_INT(cfg.fps, 30);
    CHECK_EQ_INT(cfg.hvcc_len, sizeof(hvcc));
    CHECK(memcmp(cfg.hvcc, hvcc, sizeof(hvcc)) == 0);

    /* hvcc_len pointing past the payload end must be caught */
    {
        uint8_t bad[12 + 10];
        memcpy(bad, buf, sizeof(bad));
        bad[12 + 6] = 0xFF; /* hvcc_len = 0xFF.. while no bytes follow */
        CHECK_EQ_INT(iucm_parse_config(bad + 12, 10, &cfg), IUCM_ERR_TRUNCATED);
    }
}

static void test_roundtrip_video_and_nal_iteration(void) {
    const uint8_t  nal0[] = {0x26, 0x01, 0xAF, 0xFE};
    const uint8_t  nal1[] = {0x02, 0x01, 0x11};
    const uint8_t *nals[2];
    uint32_t       lens[2];
    uint8_t        buf[128];
    size_t         n = 0;
    struct sink    s;
    struct iucm_parser     p;
    uint8_t                pbuf[256];
    struct iucm_video_iter it;
    const uint8_t         *nal;
    uint32_t               nlen;

    nals[0] = nal0;
    nals[1] = nal1;
    lens[0] = sizeof(nal0);
    lens[1] = sizeof(nal1);

    CHECK_EQ_INT(iucm_encode_video(buf, sizeof(buf), 1234567890ULL, 1, nals, lens, 2, &n),
                 IUCM_OK);
    CHECK_EQ_INT(n, 12 + 8 + 4 + 4 + 4 + 3);
    CHECK_EQ_INT(buf[5], IUCM_FLAG_KEYFRAME);
    /* NAL length prefixes are BIG-endian */
    CHECK_EQ_INT(buf[12 + 8 + 0], 0);
    CHECK_EQ_INT(buf[12 + 8 + 1], 0);
    CHECK_EQ_INT(buf[12 + 8 + 2], 0);
    CHECK_EQ_INT(buf[12 + 8 + 3], 4);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_VIDEO);
    CHECK_EQ_INT(s.msgs[0].flags & IUCM_FLAG_KEYFRAME, IUCM_FLAG_KEYFRAME);

    CHECK_EQ_INT(iucm_video_iter_init(&it, s.msgs[0].payload, s.msgs[0].length), IUCM_OK);
    CHECK_EQ_INT(it.pts_us, 1234567890ULL);
    CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), 1);
    CHECK_EQ_INT(nlen, sizeof(nal0));
    CHECK(memcmp(nal, nal0, sizeof(nal0)) == 0);
    CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), 1);
    CHECK_EQ_INT(nlen, sizeof(nal1));
    CHECK(memcmp(nal, nal1, sizeof(nal1)) == 0);
    CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), 0);
    CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), 0);
}

static void test_video_iter_rejects_bad_prefix(void) {
    uint8_t                payload[8 + 4 + 2];
    struct iucm_video_iter it;
    const uint8_t         *nal;
    uint32_t               nlen;

    memset(payload, 0, sizeof(payload));
    /* NAL claims 5 bytes but only 2 follow */
    payload[8] = 0; payload[9] = 0; payload[10] = 0; payload[11] = 5;
    CHECK_EQ_INT(iucm_video_iter_init(&it, payload, sizeof(payload)), IUCM_OK);
    CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), IUCM_ERR_TRUNCATED);

    /* dangling 3-byte tail is a framing error, not a silent end */
    {
        uint8_t tail[8 + 3];
        memset(tail, 0, sizeof(tail));
        CHECK_EQ_INT(iucm_video_iter_init(&it, tail, sizeof(tail)), IUCM_OK);
        CHECK_EQ_INT(iucm_video_iter_next(&it, &nal, &nlen), IUCM_ERR_TRUNCATED);
    }
    /* a VIDEO payload shorter than the pts field is truncated */
    CHECK_EQ_INT(iucm_video_iter_init(&it, payload, 7), IUCM_ERR_TRUNCATED);
}

static void test_roundtrip_ping_pong(void) {
    uint8_t            buf[64];
    size_t             n = 0, n2 = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[256];
    uint64_t           ts = 0xDEADBEEFCAFEULL, got = 0;

    CHECK_EQ_INT(iucm_encode_ping(buf, sizeof(buf), ts, &n), IUCM_OK);
    CHECK_EQ_INT(iucm_encode_pong(buf + n, sizeof(buf) - n, ts, &n2), IUCM_OK);
    CHECK_EQ_INT(n, 20);
    CHECK_EQ_INT(n2, 20);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n + n2, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_PING);
    CHECK_EQ_INT(s.msgs[1].type, IUCM_MSG_PONG);
    CHECK_EQ_INT(iucm_parse_timestamp(s.msgs[0].payload, s.msgs[0].length, &got), IUCM_OK);
    CHECK(got == ts);
    got = 0;
    CHECK_EQ_INT(iucm_parse_timestamp(s.msgs[1].payload, s.msgs[1].length, &got), IUCM_OK);
    CHECK(got == ts);
    /* 7 bytes is not a timestamp */
    CHECK_EQ_INT(iucm_parse_timestamp(s.msgs[1].payload, 7, &got), IUCM_ERR_TRUNCATED);
}

static void test_roundtrip_error(void) {
    uint8_t            buf[256];
    size_t             n = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[512];
    struct iucm_error  e;

    CHECK_EQ_INT(iucm_encode_error(buf, sizeof(buf), IUCM_ERRCODE_BUSY,
                                   "already connected", &n),
                 IUCM_OK);
    CHECK_EQ_INT(n, 12 + 4 + 17);
    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_ERROR);
    CHECK_EQ_INT(iucm_parse_error(s.msgs[0].payload, s.msgs[0].length, &e), IUCM_OK);
    CHECK_EQ_INT(e.code, IUCM_ERRCODE_BUSY);
    CHECK_EQ_INT(e.text_len, 17);
    CHECK_EQ_STR(e.text, "already connected");

    /* empty text is legal */
    CHECK_EQ_INT(iucm_encode_error(buf, sizeof(buf), IUCM_ERRCODE_VERSION_UNSUPPORTED,
                                   NULL, &n),
                 IUCM_OK);
    CHECK_EQ_INT(n, 16);
    CHECK_EQ_INT(iucm_parse_error(buf + 12, 4, &e), IUCM_OK);
    CHECK_EQ_INT(e.code, 5);
    CHECK_EQ_INT(e.text_len, 0);
    CHECK_EQ_STR(e.text, "");

    /* text_len longer than the payload is truncation, not a read past the end */
    {
        uint8_t bad[8] = {1, 0, 200, 0, 'a', 'b', 'c', 'd'};
        CHECK_EQ_INT(iucm_parse_error(bad, sizeof(bad), &e), IUCM_ERR_TRUNCATED);
    }
}

/* ---- stream behaviour --------------------------------------------------- */

static void test_partial_frames_byte_by_byte(void) {
    struct iucm_hello  h;
    uint8_t            wire[512];
    size_t             total = 0, n = 0, i;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[1024];

    memset(&h, 0, sizeof(h));
    h.version = IUCM_VERSION_1_0;
    strcpy(h.name, "iPhone");
    strcpy(h.app_version, "1.0.0");
    h.camera_count = 1;
    strcpy(h.cameras[0].name, "Rueck-Weitwinkel");
    CHECK_EQ_INT(iucm_encode_hello(wire, sizeof(wire), &h, &n), IUCM_OK);
    total = n;
    CHECK_EQ_INT(iucm_encode_ping(wire + total, sizeof(wire) - total, 42, &n), IUCM_OK);
    total += n;
    CHECK_EQ_INT(iucm_encode_stop(wire + total, sizeof(wire) - total, &n), IUCM_OK);
    total += n;

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    for (i = 0; i < total; i++) {
        CHECK_EQ_INT(iucm_parser_feed(&p, wire + i, 1, sink_cb, &s), IUCM_OK);
        /* no message can appear before its last byte was fed */
        if (i + 1 < 12 + 2 + 7 + 6 + 1 + 3 + 16) CHECK_EQ_INT(s.count, 0);
    }
    CHECK_EQ_INT(s.count, 3);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_HELLO);
    CHECK_EQ_INT(s.msgs[1].type, IUCM_MSG_PING);
    CHECK_EQ_INT(s.msgs[2].type, IUCM_MSG_STOP);
    CHECK_EQ_INT(p.messages, 3);

    /* also in two arbitrary chunks */
    sink_init(&s);
    iucm_parser_reset(&p);
    CHECK_EQ_INT(iucm_parser_feed(&p, wire, 17, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 0);
    CHECK_EQ_INT(iucm_parser_feed(&p, wire + 17, total - 17, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 3);
}

static void test_garbage_before_magic(void) {
    uint8_t            wire[256];
    uint8_t            garbage[] = {0x00, 0xFF, 'I', 'U', 'C', 0x41, 'I', 0x7F, 0x00};
    size_t             n = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[512];

    memcpy(wire, garbage, sizeof(garbage));
    CHECK_EQ_INT(iucm_encode_ping(wire + sizeof(garbage), sizeof(wire) - sizeof(garbage),
                                  7, &n),
                 IUCM_OK);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, wire, sizeof(garbage) + n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 1);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_PING);
    CHECK_EQ_INT(p.resync_bytes_dropped, sizeof(garbage));

    /* the same garbage byte by byte: a split near-magic must not fool the resync */
    {
        size_t i;
        sink_init(&s);
        iucm_parser_reset(&p);
        p.resync_bytes_dropped = 0;
        for (i = 0; i < sizeof(garbage) + n; i++)
            CHECK_EQ_INT(iucm_parser_feed(&p, wire + i, 1, sink_cb, &s), IUCM_OK);
        CHECK_EQ_INT(s.count, 1);
        CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_PING);
    }
}

static void test_oversize_length_rejected(void) {
    uint8_t            hdr[IUCM_HEADER_SIZE];
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[256];
    uint32_t           len = 0;

    /* exactly at the limit: accepted by the header reader */
    iucm_write_header(hdr, IUCM_MSG_VIDEO, 0, IUCM_MAX_PAYLOAD);
    CHECK_EQ_INT(iucm_read_header(hdr, NULL, NULL, &len), IUCM_OK);
    CHECK_EQ_INT(len, IUCM_MAX_PAYLOAD);

    /* one byte over: rejected */
    iucm_write_header(hdr, IUCM_MSG_VIDEO, 0, IUCM_MAX_PAYLOAD + 1);
    CHECK_EQ_INT(iucm_read_header(hdr, NULL, NULL, &len), IUCM_ERR_OVERSIZE);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, hdr, sizeof(hdr), sink_cb, &s), IUCM_ERR_OVERSIZE);
    CHECK_EQ_INT(s.count, 0);
    /* sticky: further feeds keep failing until reset */
    CHECK_EQ_INT(iucm_parser_feed(&p, hdr, sizeof(hdr), sink_cb, &s), IUCM_ERR_OVERSIZE);
    iucm_parser_reset(&p);
    CHECK_EQ_INT(p.failed, 0);

    /* a legal length that does not fit our buffer is a capacity error, not a crash */
    iucm_write_header(hdr, IUCM_MSG_VIDEO, 0, 100000);
    CHECK_EQ_INT(iucm_parser_feed(&p, hdr, sizeof(hdr), sink_cb, &s), IUCM_ERR_CAPACITY);
}

static void test_unknown_type_is_skipped(void) {
    uint8_t            wire[64];
    size_t             n = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[256];

    iucm_write_header(wire, 0x77, 0, 4);
    memcpy(wire + 12, "junk", 4);
    CHECK_EQ_INT(iucm_encode_stop(wire + 16, sizeof(wire) - 16, &n), IUCM_OK);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, wire, 16 + n, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT(s.count, 2);
    CHECK_EQ_INT(s.msgs[0].type, 0x77); /* handed up, decision is the caller's */
    CHECK_EQ_INT(s.msgs[1].type, IUCM_MSG_STOP);
}

static void test_callback_abort(void) {
    uint8_t            wire[64];
    size_t             n = 0, n2 = 0;
    struct sink        s;
    struct iucm_parser p;
    uint8_t            pbuf[256];

    CHECK_EQ_INT(iucm_encode_ping(wire, sizeof(wire), 1, &n), IUCM_OK);
    CHECK_EQ_INT(iucm_encode_ping(wire + n, sizeof(wire) - n, 2, &n2), IUCM_OK);
    sink_init(&s);
    s.abort_after = 1;
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, wire, n + n2, sink_cb, &s), IUCM_ERR_ABORTED);
    CHECK_EQ_INT(s.count, 1);
}

static void test_bad_arguments(void) {
    struct iucm_parser p;
    uint8_t            small[4];
    struct iucm_hello  h;
    uint8_t            out[8];
    size_t             n = 0;

    CHECK_EQ_INT(iucm_parser_init(&p, small, sizeof(small)), IUCM_ERR_BADARG);
    CHECK_EQ_INT(iucm_parser_init(NULL, small, 64), IUCM_ERR_BADARG);
    CHECK_EQ_INT(iucm_parse_hello(NULL, 0, &h), IUCM_ERR_BADARG);
    memset(&h, 0, sizeof(h));
    CHECK_EQ_INT(iucm_encode_hello(out, sizeof(out), &h, &n), IUCM_ERR_CAPACITY);
    /* an empty payload is not a HELLO */
    {
        uint8_t empty[1] = {0};
        CHECK_EQ_INT(iucm_parse_hello(empty, 0, &h), IUCM_ERR_TRUNCATED);
    }
    /* camera_count beyond the struct capacity is rejected, not overflowed */
    {
        uint8_t payload[16];
        memset(payload, 0, sizeof(payload));
        payload[0] = 0x00; payload[1] = 0x01; /* version */
        payload[2] = 0;                        /* name_len */
        payload[3] = 0;                        /* app_version_len */
        payload[4] = 99;                       /* camera_count */
        CHECK_EQ_INT(iucm_parse_hello(payload, 5, &h), IUCM_ERR_RANGE);
    }
    /* a name longer than the struct field is rejected, not truncated silently */
    {
        uint8_t payload[300];
        memset(payload, 'x', sizeof(payload));
        payload[0] = 0x00; payload[1] = 0x01;
        payload[2] = 200; /* name_len > IUCM_NAME_MAX */
        CHECK_EQ_INT(iucm_parse_hello(payload, sizeof(payload), &h), IUCM_ERR_RANGE);
    }
    CHECK_EQ_STR(iucm_type_name(IUCM_MSG_CONFIG), "CONFIG");
    CHECK_EQ_STR(iucm_type_name(0x99), "UNKNOWN");
    CHECK(strlen(iucm_strerror(IUCM_ERR_OVERSIZE)) > 0);
}

/* ---- CLIENT_INFO (1.2, PROTOCOL.md 4.11) ------------------------------- */

static void test_client_info_roundtrip_and_fixture(void) {
    struct iucm_client_info ci = {IUCM_CLIENT_TOOL, "usbcam-recv", "dev"};
    struct iucm_client_info back;
    uint8_t                 buf[128];
    size_t                  written = 0;
    struct sink             s;
    struct iucm_parser      p;
    uint8_t                 pbuf[256];
    unsigned char          *fx;
    size_t                  fx_len = 0;

    CHECK_EQ_INT(iucm_encode_client_info(buf, sizeof(buf), &ci, &written), IUCM_OK);
    /* 12 header + 1 kind + 1 + 11 name + 1 + 3 version */
    CHECK_EQ_INT((int)written, 29);
    CHECK_EQ_INT(buf[4], IUCM_MSG_CLIENT_INFO);

    sink_init(&s);
    iucm_parser_init(&p, pbuf, sizeof(pbuf));
    CHECK_EQ_INT(iucm_parser_feed(&p, buf, written, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT((int)s.count, 1);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_CLIENT_INFO);
    CHECK_EQ_INT(iucm_parse_client_info(s.msgs[0].payload, s.msgs[0].length, &back), IUCM_OK);
    CHECK_EQ_INT(back.kind, IUCM_CLIENT_TOOL);
    CHECK_EQ_STR(back.name, "usbcam-recv");
    CHECK_EQ_STR(back.version, "dev");

    /* A later minor version may append fields: the surplus byte is ignored. */
    {
        uint8_t payload[8] = {9, 1, 'x', 1, 'y', 0xAA, 0xBB, 0xCC};
        CHECK_EQ_INT(iucm_parse_client_info(payload, sizeof(payload), &back), IUCM_OK);
        CHECK_EQ_INT(back.kind, 9); /* unknown kind survives; the consumer maps it to 0 */
        CHECK_EQ_STR(back.name, "x");
        CHECK_EQ_STR(back.version, "y");
    }
    /* A payload that ends inside version_len is truncated, not silently empty. */
    {
        uint8_t payload[4] = {2, 1, 'x', 5};
        CHECK_EQ_INT(iucm_parse_client_info(payload, sizeof(payload), &back),
                     IUCM_ERR_TRUNCATED);
    }

    /* Golden bytes: the fixture is the cross-implementation contract, so a field
     * order or prefix-width change here breaks the Swift and ObjC++ sides too. */
    fx = t_read_file("clientinfo-macapp.bin", &fx_len);
    sink_init(&s);
    iucm_parser_reset(&p);
    CHECK_EQ_INT(iucm_parser_feed(&p, fx, fx_len, sink_cb, &s), IUCM_OK);
    CHECK_EQ_INT((int)s.count, 1);
    CHECK_EQ_INT(s.msgs[0].type, IUCM_MSG_CLIENT_INFO);
    CHECK_EQ_INT(iucm_parse_client_info(s.msgs[0].payload, s.msgs[0].length, &back), IUCM_OK);
    CHECK_EQ_INT(back.kind, IUCM_CLIENT_MAC_APP);
    CHECK_EQ_STR(back.name, "TetherCam for Mac");
    CHECK_EQ_STR(back.version, "0.3.0");
    free(fx);

    CHECK_EQ_STR(iucm_type_name(IUCM_MSG_CLIENT_INFO), "CLIENT_INFO");
    CHECK_EQ_INT(IUCM_VERSION_1_2, 0x0102);
    CHECK_EQ_INT(iucm_encode_client_info(buf, 12, &ci, &written), IUCM_ERR_CAPACITY);
    CHECK_EQ_INT(iucm_encode_client_info(buf, sizeof(buf), NULL, &written), IUCM_ERR_BADARG);
}

/* Bug: iucm_parse_client_info rejected a contract-conforming name longer than
 * IUCM_NAME_MAX with IUCM_ERR_RANGE. PROTOCOL.md 4.11 allows 255 bytes, so the
 * C side truncates instead. */
static void test_client_info_long_name_is_truncated(void) {
    struct iucm_client_info back;
    uint8_t                 payload[3 + 100 + 40];
    size_t                  i, off = 0;

    payload[off++] = IUCM_CLIENT_OBS_PLUGIN;
    payload[off++] = 100;
    for (i = 0; i < 100; i++) payload[off++] = (uint8_t)('a' + (i % 26));
    payload[off++] = 40;
    for (i = 0; i < 40; i++) payload[off++] = (uint8_t)('0' + (i % 10));
    CHECK_EQ_INT((int)off, (int)sizeof(payload));

    CHECK_EQ_INT(iucm_parse_client_info(payload, (uint32_t)sizeof(payload), &back), IUCM_OK);
    CHECK_EQ_INT(back.kind, IUCM_CLIENT_OBS_PLUGIN);
    /* Kept: IUCM_NAME_MAX - 1 bytes plus NUL, and the same for version. */
    CHECK_EQ_INT((int)strlen(back.name), IUCM_NAME_MAX - 1);
    CHECK_EQ_INT((int)strlen(back.version), IUCM_APP_VERSION_MAX - 1);
    CHECK_EQ_INT(back.name[0], 'a');
    CHECK_EQ_INT(back.name[IUCM_NAME_MAX - 2], (int)('a' + ((IUCM_NAME_MAX - 2) % 26)));
    CHECK_EQ_INT(back.version[0], '0');
    /* The cursor still advanced over all 100 name bytes: version parsed at all. */
    CHECK_EQ_INT(back.version[IUCM_APP_VERSION_MAX - 2],
                 (int)('0' + ((IUCM_APP_VERSION_MAX - 2) % 10)));
}

int main(void) {
    RUN(test_header_roundtrip);
    RUN(test_version_constant);
    RUN(test_roundtrip_hello);
    RUN(test_roundtrip_start_stop);
    RUN(test_client_info_roundtrip_and_fixture);
    RUN(test_client_info_long_name_is_truncated);
    RUN(test_start_flags_lengths);
    RUN(test_parse_audio_config_and_audio);
    RUN(test_roundtrip_config);
    RUN(test_roundtrip_video_and_nal_iteration);
    RUN(test_video_iter_rejects_bad_prefix);
    RUN(test_roundtrip_ping_pong);
    RUN(test_roundtrip_error);
    RUN(test_partial_frames_byte_by_byte);
    RUN(test_garbage_before_magic);
    RUN(test_oversize_length_rejected);
    RUN(test_unknown_type_is_skipped);
    RUN(test_callback_abort);
    RUN(test_bad_arguments);
    return T_SUMMARY();
}
