/* Tiny assert-based test runner. No framework, no dependencies. */
#ifndef IUCM_TEST_UTIL_H
#define IUCM_TEST_UTIL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef FIXTURE_DIR
#define FIXTURE_DIR "."
#endif

#if defined(__GNUC__)
#define T_UNUSED __attribute__((unused))
#else
#define T_UNUSED
#endif

T_UNUSED static int t_failures = 0;
T_UNUSED static int t_checks   = 0;

#define CHECK(cond)                                                                       \
    do {                                                                                  \
        t_checks++;                                                                       \
        if (!(cond)) {                                                                    \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);               \
            t_failures++;                                                                 \
        }                                                                                 \
    } while (0)

#define CHECK_EQ_INT(a, b)                                                                \
    do {                                                                                  \
        long long va_ = (long long)(a), vb_ = (long long)(b);                             \
        t_checks++;                                                                       \
        if (va_ != vb_) {                                                                 \
            fprintf(stderr, "FAIL %s:%d  %s == %s  (%lld vs %lld)\n", __FILE__, __LINE__, \
                    #a, #b, va_, vb_);                                                    \
            t_failures++;                                                                 \
        }                                                                                 \
    } while (0)

#define CHECK_EQ_STR(a, b)                                                                \
    do {                                                                                  \
        const char *sa_ = (a), *sb_ = (b);                                                \
        t_checks++;                                                                       \
        if (strcmp(sa_, sb_) != 0) {                                                      \
            fprintf(stderr, "FAIL %s:%d  \"%s\" != \"%s\"\n", __FILE__, __LINE__, sa_,    \
                    sb_);                                                                 \
            t_failures++;                                                                 \
        }                                                                                 \
    } while (0)

#define RUN(fn)                                                                           \
    do {                                                                                  \
        int before_ = t_failures;                                                         \
        fn();                                                                             \
        printf("%-40s %s\n", #fn, (t_failures == before_) ? "ok" : "FAILED");             \
    } while (0)

#define T_SUMMARY()                                                                       \
    (printf("%d checks, %d failures\n", t_checks, t_failures), t_failures ? 1 : 0)

/* Reads a fixture file into a malloc'd buffer. Aborts on failure. */
T_UNUSED static unsigned char *t_read_file(const char *name, size_t *len) {
    char           path[1024];
    FILE          *f;
    long           sz;
    unsigned char *buf;
    snprintf(path, sizeof(path), "%s/%s", FIXTURE_DIR, name);
    f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "cannot open fixture %s\n", path);
        exit(2);
    }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = (unsigned char *)malloc((size_t)sz + 1);
    if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        fprintf(stderr, "cannot read fixture %s\n", path);
        exit(2);
    }
    buf[sz] = 0;
    fclose(f);
    *len = (size_t)sz;
    return buf;
}

#endif
