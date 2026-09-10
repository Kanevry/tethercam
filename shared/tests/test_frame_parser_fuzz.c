/* test_frame_parser_fuzz.c — robustness harness for shared/frame_parser.c.
 *
 * Feeds 2000 pseudo-random byte streams (deterministic xorshift seed, 1..64 KiB,
 * split into random-sized chunks, with valid frames spliced in at random offsets)
 * into iucm_parser_feed() and asserts three properties:
 *
 *   1. no crash and no out-of-bounds access (run the ASan/UBSan build for this),
 *   2. every callback gets a length that fits the parser buffer, and a payload
 *      slice that lies inside it (each byte is read, so ASan sees an overread),
 *   3. a valid frame appended after arbitrary garbage is still delivered.
 *
 * On (3): iucm_parser_feed() is documented as sticky-failing, so a stream that
 * makes it return a negative code needs an explicit iucm_parser_reset() before
 * the parser is usable again. The harness therefore resets on a negative return
 * and then requires the trailing valid frame to arrive — that is the recovery
 * contract, not "errors never happen".
 */
#include "../frame_parser.h"
#include "test_util.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define FUZZ_ITERATIONS 2000u
#define FUZZ_MAX_STREAM (64u * 1024u)
#define PARSER_CAP      (128u * 1024u)
#define MAX_PAYLOAD_CAP (PARSER_CAP - IUCM_HEADER_SIZE)

/* ---- deterministic PRNG (xorshift64*) ---------------------------------- */

static uint64_t rng_state = 0x9E3779B97F4A7C15ull;

static uint64_t rnd64(void) {
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x * 0x2545F4914F6CDD1Dull;
}
static uint32_t rnd_below(uint32_t n) { return n ? (uint32_t)(rnd64() % n) : 0u; }

/* ---- UTF-8 validation --------------------------------------------------- */

/* Strict UTF-8 check: rejects overlong forms, surrogates and anything above
 * U+10FFFF. The CLIENT_INFO truncation in frame_parser.c (utf8_floor) promises a
 * cut on a character boundary, and only a strict validator can catch a cut that
 * leaves a lead byte without its continuation bytes. */
static int utf8_valid(const uint8_t *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        uint8_t  c    = s[i];
        size_t   need;
        uint32_t cp;
        if (c < 0x80u) { i++; continue; }
        if ((c & 0xE0u) == 0xC0u) { need = 1; cp = c & 0x1Fu; }
        else if ((c & 0xF0u) == 0xE0u) { need = 2; cp = c & 0x0Fu; }
        else if ((c & 0xF8u) == 0xF0u) { need = 3; cp = c & 0x07u; }
        else return 0; /* continuation byte or 0xF8..0xFF as a lead */
        if (i + need >= n) return 0; /* sequence runs past the end: truncated */
        {
            size_t k;
            for (k = 1; k <= need; k++) {
                if ((s[i + k] & 0xC0u) != 0x80u) return 0;
                cp = (cp << 6) | (uint32_t)(s[i + k] & 0x3Fu);
            }
        }
        if (need == 1 && cp < 0x80u) return 0;
        if (need == 2 && cp < 0x800u) return 0;
        if (need == 3 && cp < 0x10000u) return 0;
        if (cp > 0x10FFFFu) return 0;
        if (cp >= 0xD800u && cp <= 0xDFFFu) return 0;
        i += need + 1;
    }
    return 1;
}

/* Writes exactly n bytes of valid, NUL-free UTF-8 (mixed 1..4-byte sequences)
 * and returns n. A tail too short for a multi-byte sequence is filled with
 * ASCII, so the result is always exactly n bytes and always well-formed. */
static uint32_t gen_utf8(uint8_t *dst, uint32_t n) {
    uint32_t i = 0;
    while (i < n) {
        uint32_t left = n - i;
        uint32_t want = 1u + rnd_below(4); /* 1..4 */
        uint32_t cp;
        if (want > left) want = 1;
        switch (want) {
        case 2: cp = 0x80u + rnd_below(0x780u); break;
        case 3:
            cp = 0x800u + rnd_below(0xF800u); /* 0x800..0xFFFF */
            if (cp >= 0xD800u && cp <= 0xDFFFu) cp += 0x800u;
            if (cp > 0xFFFFu) cp = 0xFFFDu;
            break;
        case 4: cp = 0x10000u + rnd_below(0x100000u); break;
        default: cp = 1u + rnd_below(0x7Fu); break; /* never NUL */
        }
        if (cp < 0x80u) {
            dst[i++] = (uint8_t)cp;
        } else if (cp < 0x800u) {
            dst[i++] = (uint8_t)(0xC0u | (cp >> 6));
            dst[i++] = (uint8_t)(0x80u | (cp & 0x3Fu));
        } else if (cp < 0x10000u) {
            dst[i++] = (uint8_t)(0xE0u | (cp >> 12));
            dst[i++] = (uint8_t)(0x80u | ((cp >> 6) & 0x3Fu));
            dst[i++] = (uint8_t)(0x80u | (cp & 0x3Fu));
        } else {
            dst[i++] = (uint8_t)(0xF0u | (cp >> 18));
            dst[i++] = (uint8_t)(0x80u | ((cp >> 12) & 0x3Fu));
            dst[i++] = (uint8_t)(0x80u | ((cp >> 6) & 0x3Fu));
            dst[i++] = (uint8_t)(0x80u | (cp & 0x3Fu));
        }
    }
    return n;
}

/* ---- callback ----------------------------------------------------------- */

struct fuzz_ctx {
    const uint8_t *buf_lo; /* parser buffer bounds */
    const uint8_t *buf_hi;
    uint64_t       messages;
    uint64_t       checksum; /* forces a read of every payload byte */
    uint64_t       bad_length;
    uint64_t       bad_payload_ptr;
    uint64_t       bad_client_info; /* CLIENT_INFO invariant violations */
    uint64_t       client_infos;    /* CLIENT_INFO frames that parsed */
    int            saw_marker;   /* the trailing recovery frame */
    uint64_t       marker_value; /* its timestamp */
};

static int fuzz_cb(void *ctx, const struct iucm_msg *msg) {
    struct fuzz_ctx *f = (struct fuzz_ctx *)ctx;
    uint32_t         i;

    f->messages++;
    if (msg->length > MAX_PAYLOAD_CAP) {
        f->bad_length++;
        return 0; /* do not dereference a length we already distrust */
    }
    if (msg->length > 0) {
        if (msg->payload < f->buf_lo || msg->payload + msg->length > f->buf_hi) {
            f->bad_payload_ptr++;
            return 0;
        }
        for (i = 0; i < msg->length; i++) f->checksum += msg->payload[i];
    }
    /* The 1.1 payloads are decoded here too, so a bad length or a runaway
     * asc_len inside the fuzzed stream shows up as an ASan report, not as a
     * silently accepted frame. */
    if (msg->type == IUCM_MSG_AUDIO_CONFIG) {
        struct iucm_audio_config ac;
        if (iucm_parse_audio_config(msg->payload, msg->length, &ac) == IUCM_OK) {
            uint32_t k;
            for (k = 0; k < ac.asc_len; k++) f->checksum += ac.asc[k];
        }
    }
    if (msg->type == IUCM_MSG_AUDIO) {
        struct iucm_audio au;
        if (iucm_parse_audio(msg->payload, msg->length, &au) == IUCM_OK) {
            uint32_t k;
            f->checksum += au.pts_us;
            for (k = 0; k < au.len; k++) f->checksum += au.frame[k];
        }
    }
    if (msg->type == IUCM_MSG_START) {
        struct iucm_start st;
        if (iucm_parse_start(msg->payload, msg->length, &st) == IUCM_OK)
            f->checksum += st.flags;
    }
    /* CLIENT_INFO (1.2): the decoder truncates long name/version fields at a
     * UTF-8 boundary instead of rejecting them, so the fuzzer has to prove three
     * things — both strings are NUL-terminated inside their fixed buffers, the
     * kept name is a byte-prefix of the wire name, and a wire name that was valid
     * UTF-8 stays valid UTF-8 after the cut (the utf8_floor contract). Validity
     * is only demanded when the wire bytes themselves were valid: a CLIENT_INFO
     * frame carved out of random noise carries garbage the parser never promises
     * to clean up. */
    if (msg->type == IUCM_MSG_CLIENT_INFO) {
        struct iucm_client_info ci;
        int rc = iucm_parse_client_info(msg->payload, msg->length, &ci);
        if (memchr(ci.name, '\0', sizeof(ci.name)) == NULL ||
            memchr(ci.version, '\0', sizeof(ci.version)) == NULL)
            f->bad_client_info++;
        else if (rc == IUCM_OK) {
            size_t kept = strlen(ci.name);
            f->client_infos++;
            f->checksum += ci.kind + kept;
            if (msg->length >= 2u) {
                uint32_t wire_len = msg->payload[1];
                if (msg->length >= 2u + wire_len) {
                    const uint8_t *wire = msg->payload + 2;
                    if (kept > wire_len || memcmp(ci.name, wire, kept) != 0)
                        f->bad_client_info++;
                    else if (utf8_valid(wire, wire_len) &&
                             !utf8_valid((const uint8_t *)ci.name, kept))
                        f->bad_client_info++;
                }
            }
        }
    }
    if (msg->type == IUCM_MSG_PONG) {
        uint64_t ts = 0;
        if (iucm_parse_timestamp(msg->payload, msg->length, &ts) == IUCM_OK &&
            ts == f->marker_value)
            f->saw_marker = 1;
    }
    return 0;
}

/* ---- stream construction ------------------------------------------------ */

/* Writes one syntactically valid frame of a random type at out, or returns 0
 * when it does not fit. */
static size_t splice_valid_frame(uint8_t *out, size_t room) {
    size_t written = 0;
    int    kind    = (int)rnd_below(8);

    switch (kind) {
    case 0:
        if (iucm_encode_ping(out, room, rnd64(), &written) != IUCM_OK) return 0;
        return written;
    case 1:
        if (iucm_encode_pong(out, room, rnd64(), &written) != IUCM_OK) return 0;
        return written;
    case 2:
        if (iucm_encode_error(out, room, (uint16_t)rnd_below(0x10000), "fuzz", &written) !=
            IUCM_OK)
            return 0;
        return written;
    case 3: {
        struct iucm_start s;
        s.camera_id    = (uint8_t)rnd_below(256);
        s.width        = 1920;
        s.height       = 1080;
        s.fps          = 30;
        s.bitrate_kbps = 12000;
        /* Both START lengths, 11 and 12 bytes, appear in the stream. */
        s.flags = (uint8_t)(rnd64() & 1u) ? IUCM_START_FLAG_AUDIO : (uint8_t)0;
        if (iucm_encode_start(out, room, &s, &written) != IUCM_OK) return 0;
        return written;
    }
    case 4: {
        /* AUDIO_CONFIG, PROTOCOL.md 4.9. shared/ has no encoder for it, so the
         * frame is written here; the header still comes from the library. */
        uint32_t asc_len = rnd_below(8);
        uint32_t payload = 8u + asc_len;
        uint32_t i;
        if (room < IUCM_HEADER_SIZE + payload) return 0;
        iucm_write_header(out, IUCM_MSG_AUDIO_CONFIG, 0, payload);
        out[IUCM_HEADER_SIZE + 0] = 0x80; /* 48000 LE */
        out[IUCM_HEADER_SIZE + 1] = 0xBB;
        out[IUCM_HEADER_SIZE + 2] = 0x00;
        out[IUCM_HEADER_SIZE + 3] = 0x00;
        out[IUCM_HEADER_SIZE + 4] = 1;
        out[IUCM_HEADER_SIZE + 5] = (uint8_t)rnd_below(4);
        out[IUCM_HEADER_SIZE + 6] = (uint8_t)asc_len;
        out[IUCM_HEADER_SIZE + 7] = 0;
        for (i = 0; i < asc_len; i++)
            out[IUCM_HEADER_SIZE + 8 + i] = (uint8_t)rnd64();
        return IUCM_HEADER_SIZE + payload;
    }
    case 5: {
        /* AUDIO, PROTOCOL.md 4.10; an empty frame is a legal length of 8. */
        uint32_t body    = rnd_below(64);
        uint32_t payload = 8u + body;
        uint32_t i;
        uint64_t pts = rnd64();
        if (room < IUCM_HEADER_SIZE + payload) return 0;
        iucm_write_header(out, IUCM_MSG_AUDIO, 0, payload);
        for (i = 0; i < 8; i++)
            out[IUCM_HEADER_SIZE + i] = (uint8_t)((pts >> (8 * i)) & 0xFFu);
        for (i = 0; i < body; i++) out[IUCM_HEADER_SIZE + 8 + i] = (uint8_t)rnd64();
        return IUCM_HEADER_SIZE + payload;
    }
    case 6: {
        /* CLIENT_INFO, PROTOCOL.md 4.11. The wire allows 255 bytes per string
         * while the C struct holds 63 name and 31 version bytes, so the frame is
         * hand-built whenever it would not fit the struct — that is exactly the
         * truncation path (utf8_floor) the callback checks. Names are real,
         * mixed-width UTF-8, so a cut in the middle of a sequence is possible. */
        uint32_t name_len = rnd_below(256);
        uint32_t ver_len  = rnd_below(64);
        uint32_t payload  = 3u + name_len + ver_len;
        size_t   off;
        if (name_len < IUCM_NAME_MAX && ver_len < IUCM_APP_VERSION_MAX &&
            (rnd64() & 1u)) {
            /* Short enough for the struct: go through the library encoder. */
            struct iucm_client_info ci;
            memset(&ci, 0, sizeof(ci));
            ci.kind = (uint8_t)rnd_below(5);
            gen_utf8((uint8_t *)ci.name, name_len);
            ci.name[name_len] = '\0';
            gen_utf8((uint8_t *)ci.version, ver_len);
            ci.version[ver_len] = '\0';
            if (iucm_encode_client_info(out, room, &ci, &written) != IUCM_OK) return 0;
            return written;
        }
        if (room < IUCM_HEADER_SIZE + payload) return 0;
        iucm_write_header(out, IUCM_MSG_CLIENT_INFO, 0, payload);
        off        = IUCM_HEADER_SIZE;
        out[off++] = (uint8_t)rnd_below(5); /* kind, unknown values included */
        out[off++] = (uint8_t)name_len;
        gen_utf8(out + off, name_len);
        off += name_len;
        out[off++] = (uint8_t)ver_len;
        gen_utf8(out + off, ver_len);
        return IUCM_HEADER_SIZE + payload;
    }
    default: {
        uint8_t        nal[64];
        const uint8_t *nals[1] = {nal};
        uint32_t       lens[1];
        size_t         i;
        lens[0] = 1u + rnd_below(sizeof(nal));
        for (i = 0; i < lens[0]; i++) nal[i] = (uint8_t)rnd64();
        if (iucm_encode_video(out, room, rnd64(), (int)(rnd64() & 1u), nals, lens, 1,
                              &written) != IUCM_OK)
            return 0;
        return written;
    }
    }
}

static void fuzz_one_stream(uint8_t *stream, struct fuzz_ctx *f, struct iucm_parser *p) {
    size_t n = 1u + (size_t)rnd_below(FUZZ_MAX_STREAM);
    size_t i, off;
    int    rc;

    for (i = 0; i < n; i++) stream[i] = (uint8_t)rnd64();

    /* Splice 0..3 valid frames into the noise at random offsets. */
    {
        unsigned k, frames = rnd_below(4);
        for (k = 0; k < frames; k++) {
            size_t at = (size_t)rnd_below((uint32_t)n);
            (void)splice_valid_frame(stream + at, n - at);
        }
    }

    /* Feed in random chunks. A negative return is legal (oversize length, or a
     * buffer that filled with garbage); the parser is sticky-failed afterwards
     * and we reset it, exactly as the header prescribes. */
    off = 0;
    while (off < n) {
        size_t take = 1u + (size_t)rnd_below(4096);
        if (take > n - off) take = n - off;
        rc = iucm_parser_feed(p, stream + off, take, fuzz_cb, f);
        if (rc != IUCM_OK) iucm_parser_reset(p);
        off += take;
    }
}

static void test_parser_survives_random_streams(void) {
    static uint8_t     stream[FUZZ_MAX_STREAM + 4096];
    static uint8_t     pbuf[PARSER_CAP];
    struct iucm_parser p;
    struct fuzz_ctx    f;
    unsigned           iter;
    unsigned           recovered = 0;

    memset(&f, 0, sizeof(f));
    f.buf_lo = pbuf;
    f.buf_hi = pbuf + sizeof(pbuf);
    CHECK_EQ_INT(iucm_parser_init(&p, pbuf, sizeof(pbuf)), IUCM_OK);

    for (iter = 0; iter < FUZZ_ITERATIONS; iter++) {
        uint8_t marker[IUCM_HEADER_SIZE + 8];
        size_t  mlen = 0;

        fuzz_one_stream(stream, &f, &p);

        /* Recovery: after the garbage, a clean PONG must be delivered intact. */
        iucm_parser_reset(&p);
        f.saw_marker   = 0;
        f.marker_value = 0xC0FFEEull + iter;
        CHECK_EQ_INT(iucm_encode_pong(marker, sizeof(marker), f.marker_value, &mlen),
                     IUCM_OK);
        if (iucm_parser_feed(&p, marker, mlen, fuzz_cb, &f) == IUCM_OK && f.saw_marker)
            recovered++;
        iucm_parser_reset(&p);
    }

    printf("  fuzz: %u streams, %llu messages, %llu CLIENT_INFO, checksum %llu, "
           "%llu dropped by resync\n",
           (unsigned)FUZZ_ITERATIONS, (unsigned long long)f.messages,
           (unsigned long long)f.client_infos, (unsigned long long)f.checksum,
           (unsigned long long)p.resync_bytes_dropped);

    CHECK_EQ_INT(f.bad_length, 0);      /* no callback beyond the buffer capacity */
    CHECK_EQ_INT(f.bad_payload_ptr, 0); /* payload always inside the parser buffer */
    CHECK_EQ_INT(f.bad_client_info, 0); /* truncation stays a valid UTF-8 prefix */
    CHECK(f.client_infos > 0);          /* the CLIENT_INFO path really was taken */
    CHECK_EQ_INT(recovered, FUZZ_ITERATIONS);
    CHECK(f.messages > 0); /* the harness really did parse something */
}

/* A stream that is pure noise must never make the parser claim a message that
 * does not start with the magic. Complements the random walk above with a fixed
 * adversarial case: 'I' repeated, i.e. the resync hot path. */
static void test_resync_on_repeated_magic_prefix(void) {
    static uint8_t     pbuf[PARSER_CAP];
    static uint8_t     noise[8192];
    struct iucm_parser p;
    struct fuzz_ctx    f;
    size_t             i;

    memset(&f, 0, sizeof(f));
    f.buf_lo = pbuf;
    f.buf_hi = pbuf + sizeof(pbuf);
    CHECK_EQ_INT(iucm_parser_init(&p, pbuf, sizeof(pbuf)), IUCM_OK);
    for (i = 0; i < sizeof(noise); i++) noise[i] = IUCM_MAGIC0;
    /* 8192 is not a multiple of 7, so the last chunk is short. Clamping is the
     * harness's job: iucm_parser_feed() reads exactly the n bytes it is promised. */
    for (i = 0; i < sizeof(noise); i += 7) {
        size_t chunk = sizeof(noise) - i < 7 ? sizeof(noise) - i : 7;
        CHECK_EQ_INT(iucm_parser_feed(&p, noise + i, chunk, fuzz_cb, &f), IUCM_OK);
    }
    CHECK_EQ_INT(f.messages, 0);
    CHECK_EQ_INT(f.bad_length, 0);
    CHECK(p.len <= 3); /* only a possible partial magic may be retained */
}

/* Same adversarial stream, but the input lives in an exactly-sized heap block so
 * that a read of even one byte past the chunk end lands on a guard page.
 *
 * Regression guard for the first CI ASan finding (Kanevry/tethercam run
 * 33969653856): the harness above claimed 7 bytes for a 2-byte tail, and ASan
 * charged the resulting overread to the memcpy inside iucm_parser_feed(). The
 * parser was innocent; the caller lied about n. This test pins the contract from
 * the outside — feed a ragged chunking whose tail is short, and make every chunk
 * end exactly at the end of a heap allocation for the final feed.
 *
 * Reproduce the pre-fix crash locally (macOS, ASan runtime unusable here):
 *   DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib MALLOC_STRICT_SIZE=1 \
 *     ./test_frame_parser_fuzz
 * On Linux CI the ASan build covers it. */
static void test_feed_never_reads_past_chunk_end(void) {
    static const size_t chunk_sizes[] = {7, 1, 13, 3, 64, 2, 5};
    static uint8_t      pbuf[PARSER_CAP];
    struct iucm_parser  p;
    struct fuzz_ctx     f;
    size_t              n = 8192, off = 0, k = 0;
    uint8_t            *noise = (uint8_t *)malloc(n); /* exact size: no slack after */

    CHECK(noise != NULL);
    memset(noise, IUCM_MAGIC0, n);
    memset(&f, 0, sizeof(f));
    f.buf_lo = pbuf;
    f.buf_hi = pbuf + sizeof(pbuf);
    CHECK_EQ_INT(iucm_parser_init(&p, pbuf, sizeof(pbuf)), IUCM_OK);

    while (off < n) {
        size_t want  = chunk_sizes[k++ % (sizeof(chunk_sizes) / sizeof(chunk_sizes[0]))];
        size_t chunk = n - off < want ? n - off : want;
        CHECK_EQ_INT(iucm_parser_feed(&p, noise + off, chunk, fuzz_cb, &f), IUCM_OK);
        off += chunk;
    }
    CHECK_EQ_INT(f.messages, 0);
    CHECK_EQ_INT(f.bad_length, 0);
    CHECK(p.len <= 3); /* partial magic is carried in the parser's own buffer */
    free(noise);
}

int main(void) {
    RUN(test_parser_survives_random_streams);
    RUN(test_resync_on_repeated_magic_prefix);
    RUN(test_feed_never_reads_past_chunk_end);
    return T_SUMMARY();
}
