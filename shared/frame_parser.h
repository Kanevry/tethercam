/* frame_parser.h — IUCM wire protocol, see protocol/PROTOCOL.md
 * Pure C11. No I/O, no allocation. MIT, (c) 2026 Bernhard Goetzendorfer. */
#ifndef IUCM_FRAME_PARSER_H
#define IUCM_FRAME_PARSER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define IUCM_MAGIC0 0x49 /* 'I' */
#define IUCM_MAGIC1 0x55 /* 'U' */
#define IUCM_MAGIC2 0x43 /* 'C' */
#define IUCM_MAGIC3 0x4D /* 'M' */

#define IUCM_HEADER_SIZE 12u
#define IUCM_MAX_PAYLOAD (8u * 1024u * 1024u) /* 8 MiB, PROTOCOL.md 2 */

#define IUCM_VERSION_1_0 0x0100u
#define IUCM_VERSION_1_1 0x0101u
#define IUCM_VERSION_1_2 0x0102u
#define IUCM_VERSION_MAJOR(v) ((uint8_t)((v) >> 8))
#define IUCM_VERSION_MINOR(v) ((uint8_t)((v) & 0xFFu))

/* message types */
enum {
    IUCM_MSG_HELLO  = 0x01,
    IUCM_MSG_START  = 0x02,
    IUCM_MSG_STOP   = 0x03,
    /* 1.2 */
    IUCM_MSG_CLIENT_INFO = 0x04,
    IUCM_MSG_STATS  = 0x12,
    IUCM_MSG_CONFIG = 0x10,
    IUCM_MSG_VIDEO  = 0x11,
    /* 1.1 */
    IUCM_MSG_AUDIO_CONFIG = 0x13,
    IUCM_MSG_AUDIO        = 0x14,
    IUCM_MSG_PING   = 0x20,
    IUCM_MSG_PONG   = 0x21,
    IUCM_MSG_ERROR  = 0x30
};

/* header flags, VIDEO only (PROTOCOL.md 2) */
#define IUCM_FLAG_KEYFRAME 0x01u

/* START payload flags, PROTOCOL.md 4.2 (since 1.1) */
#define IUCM_START_FLAG_AUDIO 0x01u

/* error codes carried in ERROR payloads */
enum {
    IUCM_ERRCODE_BUSY                = 1,
    IUCM_ERRCODE_CAMERA_DENIED       = 2,
    IUCM_ERRCODE_FORMAT_UNSUPPORTED  = 3,
    IUCM_ERRCODE_ENCODER_FAILED      = 4,
    IUCM_ERRCODE_VERSION_UNSUPPORTED = 5,
    IUCM_ERRCODE_MIC_DENIED          = 6 /* since 1.1 */
};

/* AUDIO_CONFIG codec ids, PROTOCOL.md 4.9. Unknown values are passed through,
 * never rejected: the receiver logs them and leaves audio off. */
enum { IUCM_AUDIO_CODEC_AAC_LC = 1 };

/* CLIENT_INFO kinds, PROTOCOL.md 4.11. Unknown values are mapped to
 * IUCM_CLIENT_UNKNOWN by the consumer; name and version survive. */
enum {
    IUCM_CLIENT_UNKNOWN    = 0,
    IUCM_CLIENT_OBS_PLUGIN = 1,
    IUCM_CLIENT_MAC_APP    = 2,
    IUCM_CLIENT_TOOL       = 3
};

/* camera positions */
enum { IUCM_CAMERA_BACK = 0, IUCM_CAMERA_FRONT = 1 };

/* return codes of this module */
enum {
    IUCM_OK            = 0,
    IUCM_ERR_BADARG    = -1, /* NULL pointer or nonsensical size */
    IUCM_ERR_OVERSIZE  = -2, /* length field exceeds IUCM_MAX_PAYLOAD */
    IUCM_ERR_CAPACITY  = -3, /* parser buffer / output buffer too small */
    IUCM_ERR_TRUNCATED = -4, /* payload ends inside a field */
    IUCM_ERR_RANGE     = -5, /* value does not fit the caller-supplied struct */
    IUCM_ERR_ABORTED   = -6  /* callback asked to stop */
};

struct iucm_msg {
    uint8_t        type;
    uint8_t        flags;
    uint32_t       length;  /* payload length */
    const uint8_t *payload; /* points into the parser buffer, valid during callback */
};

/* Return 0 to continue parsing, non-zero to abort the feed with IUCM_ERR_ABORTED. */
typedef int (*iucm_msg_cb)(void *ctx, const struct iucm_msg *msg);

struct iucm_parser {
    uint8_t *buf;
    size_t   cap;    /* usable bytes in buf; must be >= IUCM_HEADER_SIZE + largest message */
    size_t   len;    /* bytes currently buffered */
    int      failed; /* sticky error code, 0 while healthy */
    uint64_t resync_bytes_dropped;
    uint64_t messages;
};

/* ---- framing ---- */
int  iucm_parser_init(struct iucm_parser *p, uint8_t *buf, size_t cap);
void iucm_parser_reset(struct iucm_parser *p);
/* Feed bytes; invokes cb once per complete message. Returns IUCM_OK or a negative code.
 * After a negative return the parser is sticky-failed; call iucm_parser_reset(). */
int  iucm_parser_feed(struct iucm_parser *p, const uint8_t *data, size_t n,
                      iucm_msg_cb cb, void *ctx);

void iucm_write_header(uint8_t out[IUCM_HEADER_SIZE], uint8_t type, uint8_t flags,
                       uint32_t length);
/* Reads a 12-byte header. Returns IUCM_OK, IUCM_ERR_BADARG (bad magic) or
 * IUCM_ERR_OVERSIZE. */
int  iucm_read_header(const uint8_t in[IUCM_HEADER_SIZE], uint8_t *type, uint8_t *flags,
                      uint32_t *length);

/* ---- payload structs ---- */
#define IUCM_MAX_CAMERAS      16
#define IUCM_NAME_MAX         64  /* incl. terminating NUL */
#define IUCM_APP_VERSION_MAX  32
#define IUCM_ERROR_TEXT_MAX   256

struct iucm_camera {
    uint8_t id;
    uint8_t position;
    char    name[IUCM_NAME_MAX];
};

struct iucm_hello {
    uint16_t           version;
    char               name[IUCM_NAME_MAX];
    char               app_version[IUCM_APP_VERSION_MAX];
    uint8_t            camera_count;
    struct iucm_camera cameras[IUCM_MAX_CAMERAS];
};

/* flags is the optional 12th byte; an 11-byte START parses as flags == 0. It sits
 * last so the existing positional initialisers keep their meaning. */
/* CLIENT_INFO payload, PROTOCOL.md 4.11 (since 1.2). Optional on the wire: a
 * 1.0/1.1 receiver never sends it. */
struct iucm_client_info {
    uint8_t kind;
    char    name[IUCM_NAME_MAX];
    char    version[IUCM_APP_VERSION_MAX];
};

struct iucm_start {
    uint8_t  camera_id;
    uint16_t width, height, fps;
    uint32_t bitrate_kbps;
    uint8_t  flags;
};

/* AUDIO_CONFIG payload, PROTOCOL.md 4.9. channels and codec are passed through
 * unvalidated; asc_len == 0 is legal on the wire. */
struct iucm_audio_config {
    uint32_t       sample_rate;
    uint8_t        channels;
    uint8_t        codec;
    uint16_t       asc_len;
    const uint8_t *asc; /* points into the payload, NULL when asc_len == 0 */
};

/* AUDIO payload, PROTOCOL.md 4.10: pts plus exactly one raw AAC frame. An empty
 * frame (len == 0) is valid framing; the consumer drops it. */
struct iucm_audio {
    uint64_t       pts_us;
    const uint8_t *frame; /* points into the payload, NULL when len == 0 */
    uint32_t       len;
};

struct iucm_config {
    uint16_t       width, height, fps;
    uint32_t       hvcc_len;
    const uint8_t *hvcc; /* points into the payload */
};

/* STATS payload, PROTOCOL.md 4.8. Fixed-point on the wire; the _x10 / _x1000
 * fields are divided by the consumer, never here, so this stays integer-only. */
struct iucm_stats {
    int16_t  continuous_angle_x10;
    uint16_t sector;
    int16_t  residual_x10;
    uint16_t gravity_m_x1000;
    uint16_t leveler_ms_x10;
    uint16_t dropped_frames;
    uint16_t source_width, source_height;
    uint16_t output_width, output_height;
    uint8_t  flags;
    uint8_t  camera_id;
};

#define IUCM_STATS_PAYLOAD_SIZE   22
#define IUCM_STATS_FLAG_AUTO      0x01
#define IUCM_STATS_FLAG_LEVEL     0x02
#define IUCM_STATS_FLAG_OVERSAMP  0x04
#define IUCM_STATS_FLAG_FLAT_HOLD 0x08
/* Reserved in 1.1: read for the log, never acted upon (PROTOCOL.md 4.8). */
#define IUCM_STATS_FLAG_AUDIO_ACTIVE 0x10
#define IUCM_STATS_FLAG_AUDIO_MUTED  0x20

struct iucm_error {
    uint16_t code;
    uint16_t text_len; /* bytes on the wire, may exceed the copied text */
    char     text[IUCM_ERROR_TEXT_MAX];
};

/* ---- encoders (write a full framed message) ----
 * Each returns IUCM_OK and sets *written, or IUCM_ERR_CAPACITY / IUCM_ERR_RANGE. */
int iucm_encode_hello(uint8_t *out, size_t cap, const struct iucm_hello *h, size_t *written);
/* Writes the 12-byte payload when s->flags != 0, else the 1.0-compatible 11-byte
 * form (PROTOCOL.md 4.2). */
int iucm_encode_start(uint8_t *out, size_t cap, const struct iucm_start *s, size_t *written);
int iucm_encode_stop(uint8_t *out, size_t cap, size_t *written);
/* CLIENT_INFO, PROTOCOL.md 4.11. name and version are NUL-terminated C strings
 * of at most 255 bytes each; they travel u8-length-prefixed like HELLO's. */
int iucm_encode_client_info(uint8_t *out, size_t cap, const struct iucm_client_info *ci,
                            size_t *written);
int iucm_encode_config(uint8_t *out, size_t cap, uint16_t width, uint16_t height,
                       uint16_t fps, const uint8_t *hvcc, uint32_t hvcc_len,
                       size_t *written);
/* nal_lens[i] bytes are taken from nals[i]; length prefixes are written big-endian. */
int iucm_encode_video(uint8_t *out, size_t cap, uint64_t pts_us, int keyframe,
                      const uint8_t *const *nals, const uint32_t *nal_lens, size_t nal_count,
                      size_t *written);
int iucm_encode_ping(uint8_t *out, size_t cap, uint64_t timestamp_us, size_t *written);
int iucm_encode_pong(uint8_t *out, size_t cap, uint64_t timestamp_us, size_t *written);
int iucm_encode_error(uint8_t *out, size_t cap, uint16_t code, const char *text,
                      size_t *written);

/* ---- decoders (payload only, without the 12-byte header) ---- */
int iucm_parse_hello(const uint8_t *payload, uint32_t len, struct iucm_hello *out);
/* Accepts 11 and 12 bytes; 11 yields flags == 0, anything beyond 12 is ignored. */
int iucm_parse_start(const uint8_t *payload, uint32_t len, struct iucm_start *out);
/* Trailing bytes are ignored: later minor versions may append fields (4.11). */
int iucm_parse_client_info(const uint8_t *payload, uint32_t len,
                           struct iucm_client_info *out);
int iucm_parse_config(const uint8_t *payload, uint32_t len, struct iucm_config *out);
int iucm_parse_error(const uint8_t *payload, uint32_t len, struct iucm_error *out);
int iucm_parse_stats(const uint8_t *payload, uint32_t len, struct iucm_stats *out);
int iucm_parse_audio_config(const uint8_t *payload, uint32_t len,
                            struct iucm_audio_config *out);
int iucm_parse_audio(const uint8_t *payload, uint32_t len, struct iucm_audio *out);
/* PING and PONG share this. */
int iucm_parse_timestamp(const uint8_t *payload, uint32_t len, uint64_t *out_us);

struct iucm_video_iter {
    const uint8_t *p;
    size_t         remaining;
    uint64_t       pts_us;
};
/* Initialises the iterator and extracts pts. */
int iucm_video_iter_init(struct iucm_video_iter *it, const uint8_t *payload, uint32_t len);
/* Returns 1 and fills nal plus nal_len for each NAL, 0 at the end, negative on a bad prefix. */
int iucm_video_iter_next(struct iucm_video_iter *it, const uint8_t **nal, uint32_t *nal_len);

const char *iucm_strerror(int code);
const char *iucm_type_name(uint8_t type);

#ifdef __cplusplus
}
#endif
#endif /* IUCM_FRAME_PARSER_H */
