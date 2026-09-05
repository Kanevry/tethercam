/* Tests for shared/usbmux.c — header layout, plist encode/decode against the
 * recorded fixtures in tests/fixtures/. No socket is opened. */
#include "../usbmux.h"
#include "test_util.h"

/* The fixtures were captured from a probe that identified itself like this.
 * Passing the same identity lets us compare byte-exactly. */
#define PROBE_PROG   "usbmux_probe"
#define PROBE_CLIENT "usbmux-probe-1.0"

static void check_encode_matches(const char *fixture, const char *got, size_t got_len) {
    size_t         want_len = 0;
    unsigned char *want     = t_read_file(fixture, &want_len);
    CHECK_EQ_INT(got_len, want_len);
    if (got_len == want_len) {
        if (memcmp(got, want, got_len) != 0) {
            size_t i;
            for (i = 0; i < got_len; i++)
                if (got[i] != (char)want[i]) break;
            fprintf(stderr, "byte mismatch with %s at offset %zu\n", fixture, i);
            fprintf(stderr, "got : %.60s\n", got + (i > 30 ? i - 30 : 0));
            fprintf(stderr, "want: %.60s\n", (const char *)want + (i > 30 ? i - 30 : 0));
        }
        CHECK(memcmp(got, want, got_len) == 0);
    }
    free(want);
}

/* ---- header ------------------------------------------------------------ */

static void test_header_layout(void) {
    uint8_t        hdr[USBMUX_HEADER_SIZE];
    uint32_t       plen = 0, ver = 0, msg = 0, tag = 0;
    size_t         flen = 0;
    unsigned char *fix;

    usbmux_write_header(hdr, 413, 1);
    /* length INCLUDES the 16-byte header: 413 + 16 = 429 = 0x01AD */
    CHECK_EQ_INT(hdr[0], 0xAD);
    CHECK_EQ_INT(hdr[1], 0x01);
    CHECK_EQ_INT(hdr[4], 1); /* version */
    CHECK_EQ_INT(hdr[8], 8); /* message = plist */
    CHECK_EQ_INT(hdr[12], 1); /* tag */

    fix = t_read_file("listdevices-req.bin", &flen);
    CHECK(memcmp(hdr, fix, USBMUX_HEADER_SIZE) == 0);

    CHECK_EQ_INT(usbmux_parse_header(fix, &plen, &ver, &msg, &tag), USBMUX_OK);
    CHECK_EQ_INT(plen, flen - USBMUX_HEADER_SIZE);
    CHECK_EQ_INT(ver, 1);
    CHECK_EQ_INT(msg, 8);
    CHECK_EQ_INT(tag, 1);
    free(fix);
}

static void test_listen_events_carry_tag_zero(void) {
    size_t         len = 0;
    unsigned char *fix = t_read_file("listen-resp-1-2.bin", &len);
    uint32_t       tag = 99;
    CHECK_EQ_INT(usbmux_parse_header(fix, NULL, NULL, NULL, &tag), USBMUX_OK);
    CHECK_EQ_INT(tag, 0); /* NOT the tag of the Listen request */
    free(fix);

    fix = t_read_file("listen-resp-1.bin", &len);
    CHECK_EQ_INT(usbmux_parse_header(fix, NULL, NULL, NULL, &tag), USBMUX_OK);
    CHECK_EQ_INT(tag, 2); /* the Result on the Listen request does carry its tag */
    free(fix);
}

/* ---- encoders vs. fixtures --------------------------------------------- */

static void test_encode_listdevices(void) {
    char   buf[1024];
    size_t n = 0;
    CHECK_EQ_INT(usbmux_plist_encode_listdevices(buf, sizeof(buf), PROBE_PROG,
                                                 PROBE_CLIENT, &n),
                 USBMUX_OK);
    check_encode_matches("listdevices-req.plist", buf, n);
}

static void test_encode_listen(void) {
    char   buf[1024];
    size_t n = 0;
    CHECK_EQ_INT(usbmux_plist_encode_listen(buf, sizeof(buf), PROBE_PROG, PROBE_CLIENT,
                                            &n),
                 USBMUX_OK);
    check_encode_matches("listen-req.plist", buf, n);
}

static void test_encode_connect_swaps_the_port(void) {
    char   buf[1024];
    size_t n = 0;

    /* 7878 -> PortNumber 50718, the byte-swapped value. */
    CHECK_EQ_INT(usbmux_plist_encode_connect(buf, sizeof(buf), 623, 7878, PROBE_PROG,
                                             PROBE_CLIENT, &n),
                 USBMUX_OK);
    check_encode_matches("connect-7878-req.plist", buf, n);
    CHECK(strstr(buf, "<key>PortNumber</key>\n\t<integer>50718</integer>") != NULL);

    /* 62078 -> 32498 */
    CHECK_EQ_INT(usbmux_plist_encode_connect(buf, sizeof(buf), 623, 62078, PROBE_PROG,
                                             PROBE_CLIENT, &n),
                 USBMUX_OK);
    check_encode_matches("connect-62078-req.plist", buf, n);

    /* The host-order fixture is what a WRONG implementation produces; ours must
     * never equal it. That request got Number 3 — the same answer as a closed port. */
    {
        size_t         wlen = 0;
        unsigned char *wrong = t_read_file("connect-62078-hostorder-req.plist", &wlen);
        CHECK(!(n == wlen && memcmp(buf, wrong, n) == 0));
        CHECK(strstr((const char *)wrong, "<integer>62078</integer>") != NULL);
        free(wrong);
    }
}

static void test_encode_capacity(void) {
    char   small[32];
    size_t n = 0;
    CHECK_EQ_INT(usbmux_plist_encode_listen(small, sizeof(small), NULL, NULL, &n),
                 USBMUX_ERR_CAPACITY);
    CHECK_EQ_INT(usbmux_plist_encode_connect(small, sizeof(small), 1, 7878, NULL, NULL, &n),
                 USBMUX_ERR_CAPACITY);
    CHECK_EQ_INT(usbmux_plist_encode_listdevices(NULL, 0, NULL, NULL, &n),
                 USBMUX_ERR_BADARG);
}

/* ---- decoders vs. fixtures --------------------------------------------- */

static void test_decode_result_numbers(void) {
    struct {
        const char *file;
        uint32_t    number;
    } cases[] = {
        {"connect-7878-resp.plist", 3},           /* app was not listening */
        {"connect-62078-resp.plist", 0},          /* lockdown port, correct byte order */
        {"connect-62078-hostorder-resp.plist", 3},/* SAME 3 as a closed port */
        {"listen-resp-1.plist", 0},
        {"badversion-0-resp.plist", 6},
        {"badversion-2-resp.plist", 6},
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        size_t         len = 0;
        unsigned char *xml = t_read_file(cases[i].file, &len);
        uint32_t       n   = 0xFFFFFFFFu;
        char           mt[32];
        CHECK_EQ_INT(usbmux_plist_decode_result((const char *)xml, len, &n), USBMUX_OK);
        CHECK_EQ_INT(n, cases[i].number);
        CHECK_EQ_INT(usbmux_plist_message_type((const char *)xml, len, mt, sizeof(mt)),
                     USBMUX_OK);
        CHECK_EQ_STR(mt, "Result");
        free(xml);
    }
}

static void test_decode_devicelist_filters_network(void) {
    size_t               len = 0;
    unsigned char       *xml = t_read_file("listdevices-resp.plist", &len);
    struct usbmux_device devs[8];
    size_t               count = 99;
    char                 mt[32];

    memset(devs, 0, sizeof(devs));
    CHECK_EQ_INT(usbmux_plist_decode_devicelist((const char *)xml, len, devs, 8, &count),
                 USBMUX_OK);
    /* The phone appears twice — USB (623) and Network (622), same SerialNumber.
     * Only the USB entry may survive. */
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(devs[0].device_id, 623);
    CHECK_EQ_STR(devs[0].serial, "00008130-000C0DC40213803A");
    CHECK_EQ_INT(devs[0].product_id, 4776);
    /* the Network twin's DeviceID must not show up anywhere */
    CHECK(devs[1].device_id == 0);

    CHECK_EQ_INT(usbmux_plist_message_type((const char *)xml, len, mt, sizeof(mt)),
                 USBMUX_ERR_NOTFOUND); /* the reply has no top-level MessageType */
    free(xml);
}

static void test_decode_devicelist_capacity(void) {
    size_t               len = 0;
    unsigned char       *xml = t_read_file("listdevices-resp.plist", &len);
    struct usbmux_device dev;
    size_t               count = 0;
    CHECK_EQ_INT(usbmux_plist_decode_devicelist((const char *)xml, len, &dev, 1, &count),
                 USBMUX_OK);
    CHECK_EQ_INT(count, 1);
    CHECK_EQ_INT(usbmux_plist_decode_devicelist((const char *)xml, len, &dev, 0, &count),
                 USBMUX_ERR_BADARG);
    free(xml);
}

static void test_decode_attach_events(void) {
    size_t              len = 0;
    unsigned char      *xml;
    struct usbmux_event ev;

    xml = t_read_file("listen-resp-1-2.plist", &len);
    CHECK_EQ_INT(usbmux_plist_decode_event((const char *)xml, len, &ev), USBMUX_OK);
    CHECK_EQ_INT(ev.type, USBMUX_EVENT_ATTACHED);
    CHECK_EQ_INT(ev.device.device_id, 623);
    CHECK_EQ_STR(ev.device.serial, "00008130-000C0DC40213803A");
    CHECK_EQ_INT(ev.device.product_id, 4776);
    free(xml);

    /* the Network twin arrives as an event too and must be filtered out */
    xml = t_read_file("listen-resp-1-3.plist", &len);
    CHECK_EQ_INT(usbmux_plist_decode_event((const char *)xml, len, &ev), USBMUX_OK);
    CHECK_EQ_INT(ev.type, USBMUX_EVENT_NONE);
    free(xml);

    /* a Result is not an event */
    xml = t_read_file("listen-resp-1.plist", &len);
    CHECK_EQ_INT(usbmux_plist_decode_event((const char *)xml, len, &ev),
                 USBMUX_ERR_NOTFOUND);
    free(xml);
}

static void test_decode_synthetic_detached(void) {
    const char *xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n<dict>\n"
        "\t<key>MessageType</key>\n\t<string>Detached</string>\n"
        "\t<key>DeviceID</key>\n\t<integer>623</integer>\n"
        "</dict>\n</plist>\n";
    struct usbmux_event ev;
    CHECK_EQ_INT(usbmux_plist_decode_event(xml, strlen(xml), &ev), USBMUX_OK);
    CHECK_EQ_INT(ev.type, USBMUX_EVENT_DETACHED);
    CHECK_EQ_INT(ev.device.device_id, 623);
}

static void test_reader_tolerances(void) {
    /* No DOCTYPE, minimal whitespace, an unknown <data> blob and a nested dict
     * the decoder does not care about: none of this may derail the parse. */
    const char *xml =
        "<plist version=\"1.0\"><dict>"
        "<key>MessageType</key><string>Result</string>"
        "<key>Blob</key><data>\n\tSGVsbG8gd29ybGQ=\n\t</data>"
        "<key>Nested</key><dict><key>Deep</key><dict><key>X</key><integer>1</integer>"
        "</dict></dict>"
        "<key>Flag</key><true/>"
        "<key>Number</key><integer>3</integer>"
        "</dict></plist>";
    uint32_t n = 0;
    CHECK_EQ_INT(usbmux_plist_decode_result(xml, strlen(xml), &n), USBMUX_OK);
    CHECK_EQ_INT(n, 3);
}

static void test_reader_rejects_garbage(void) {
    uint32_t    n   = 0;
    const char *bad = "not xml at all";
    CHECK(usbmux_plist_decode_result(bad, strlen(bad), &n) != USBMUX_OK);
    {
        const char *unbalanced = "<plist version=\"1.0\"><dict><key>MessageType</key>"
                                 "<string>Result</string>";
        CHECK(usbmux_plist_decode_result(unbalanced, strlen(unbalanced), &n) != USBMUX_OK);
    }
    {
        const char *mismatched = "<plist version=\"1.0\"><dict><key>A</key>"
                                 "<string>x</integer></dict></plist>";
        CHECK(usbmux_plist_decode_result(mismatched, strlen(mismatched), &n) != USBMUX_OK);
    }
    CHECK_EQ_INT(usbmux_plist_decode_result(NULL, 0, &n), USBMUX_ERR_BADARG);
    CHECK(strlen(usbmux_strerror(USBMUX_ERR_TIMEOUT)) > 0);
}


/* ---- fuzz: mutated fixtures -------------------------------------------- */
/* The reader walks a caller-supplied (xml, len) slice that is NOT required to be
 * NUL-terminated, so every mutated case is copied into an exact-size heap block:
 * under ASan a single byte read past `len` aborts the run. Mutations are bit
 * flips, byte splices and truncation — the three ways a framed plist actually
 * arrives damaged over a socket. Deterministic seed, 2000 iterations. */

#define PLIST_FUZZ_ITERATIONS 2000u

static uint64_t pf_state = 0xDEADBEEFCAFEBABEull;

static uint64_t pf_rnd(void) {
    uint64_t x = pf_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    pf_state = x;
    return x * 0x2545F4914F6CDD1Dull;
}
static size_t pf_below(size_t n) { return n ? (size_t)(pf_rnd() % n) : 0u; }

static const char *const PF_FIXTURES[] = {
    "listdevices-resp.plist", "listen-resp-1-2.plist", "listen-resp-1-3.plist",
    "connect-7878-resp.plist", "badversion-2-resp.plist", "listdevices-req.plist"};

static void test_plist_reader_fuzz_mutated_fixtures(void) {
    unsigned char *fixtures[sizeof(PF_FIXTURES) / sizeof(PF_FIXTURES[0])];
    size_t         fixture_lens[sizeof(PF_FIXTURES) / sizeof(PF_FIXTURES[0])];
    const size_t   nfix = sizeof(PF_FIXTURES) / sizeof(PF_FIXTURES[0]);
    size_t         i;
    unsigned       iter, ok_results = 0, ok_types = 0;

    for (i = 0; i < nfix; i++) fixtures[i] = t_read_file(PF_FIXTURES[i], &fixture_lens[i]);

    for (iter = 0; iter < PLIST_FUZZ_ITERATIONS; iter++) {
        size_t         pick = pf_below(nfix);
        size_t         len  = fixture_lens[pick];
        unsigned char *copy;
        unsigned       mutations;

        if (len == 0) continue;
        /* truncation, including the empty slice */
        if ((pf_rnd() & 3u) == 0u) len = pf_below(len + 1);

        copy = (unsigned char *)malloc(len ? len : 1u); /* exact size on purpose */
        CHECK(copy != NULL);
        if (!copy) break;
        memcpy(copy, fixtures[pick], len);

        mutations = (unsigned)pf_below(9);
        for (i = 0; i < mutations && len > 0; i++) {
            size_t at = pf_below(len);
            if (pf_rnd() & 1u)
                copy[at] ^= (unsigned char)(1u << (pf_rnd() % 8u)); /* bit flip */
            else
                copy[at] = (unsigned char)(pf_rnd() & 0xFFu); /* byte splice */
        }

        {
            char                 type[64];
            uint32_t             number = 0;
            struct usbmux_device devs[8];
            size_t               count = 0xAAAA;
            struct usbmux_event  ev;
            int                  rc;

            /* Only "does not crash / does not read out of bounds" is asserted:
             * a mutated document may legitimately parse, fail or be filtered. */
            rc = usbmux_plist_message_type((const char *)copy, len, type, sizeof(type));
            if (rc == USBMUX_OK) ok_types++;

            rc = usbmux_plist_decode_result((const char *)copy, len, &number);
            if (rc == USBMUX_OK) ok_results++;

            rc = usbmux_plist_decode_devicelist((const char *)copy, len, devs,
                                                sizeof(devs) / sizeof(devs[0]), &count);
            if (rc == USBMUX_OK) CHECK(count <= sizeof(devs) / sizeof(devs[0]));

            memset(&ev, 0, sizeof(ev));
            rc = usbmux_plist_decode_event((const char *)copy, len, &ev);
            if (rc == USBMUX_OK)
                CHECK(ev.type == USBMUX_EVENT_NONE || ev.type == USBMUX_EVENT_ATTACHED ||
                      ev.type == USBMUX_EVENT_DETACHED);
        }
        free(copy);
    }

    printf("  plist fuzz: %u iterations, %u parsed as Result, %u yielded a MessageType\n",
           (unsigned)PLIST_FUZZ_ITERATIONS, ok_results, ok_types);
    /* Unmutated documents must still survive the same code path, otherwise the
     * loop above could be passing because nothing ever parses. */
    CHECK(ok_types > 0);

    for (i = 0; i < nfix; i++) free(fixtures[i]);
}

int main(void) {
    RUN(test_header_layout);
    RUN(test_listen_events_carry_tag_zero);
    RUN(test_encode_listdevices);
    RUN(test_encode_listen);
    RUN(test_encode_connect_swaps_the_port);
    RUN(test_encode_capacity);
    RUN(test_decode_result_numbers);
    RUN(test_decode_devicelist_filters_network);
    RUN(test_decode_devicelist_capacity);
    RUN(test_decode_attach_events);
    RUN(test_decode_synthetic_detached);
    RUN(test_reader_tolerances);
    RUN(test_reader_rejects_garbage);
    RUN(test_plist_reader_fuzz_mutated_fixtures);
    return T_SUMMARY();
}
