/* usbmux.h — minimal usbmuxd client, see protocol/PROTOCOL.md section 6.
 * C11 + POSIX sockets. Hand-written XML plist codec, no CoreFoundation, so this
 * builds and tests on Linux. MIT, (c) 2026 Bernhard Goetzendorfer. */
#ifndef IUCM_USBMUX_H
#define IUCM_USBMUX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define USBMUX_SOCKET_PATH   "/var/run/usbmuxd"
#define USBMUX_HEADER_SIZE   16u
#define USBMUX_VERSION       1u
#define USBMUX_MESSAGE_PLIST 8u
#define USBMUX_MAX_PAYLOAD   (1u * 1024u * 1024u)

/* Result numbers from usbmuxd. */
enum {
    USBMUX_RESULT_OK          = 0,
    USBMUX_RESULT_BAD_DEVICE  = 2,
    USBMUX_RESULT_REFUSED     = 3, /* port closed, app not listening, OR wrong byte order */
    USBMUX_RESULT_BAD_VERSION = 6
};

/* Return codes of this module. */
enum {
    USBMUX_OK           = 0,
    USBMUX_ERR_BADARG   = -1,
    USBMUX_ERR_CAPACITY = -2, /* output buffer too small */
    USBMUX_ERR_PARSE    = -3, /* malformed plist */
    USBMUX_ERR_NOTFOUND = -4, /* expected key or message type absent */
    USBMUX_ERR_IO       = -5, /* socket / syscall failure, errno is set */
    USBMUX_ERR_PROTOCOL = -6, /* header not version 1 / not a plist message */
    USBMUX_ERR_TIMEOUT  = -7,
    USBMUX_ERR_RESULT   = -8  /* usbmuxd answered with a non-zero Number */
};

struct usbmux_device {
    uint32_t device_id;
    char     serial[64];
    uint32_t product_id; /* 0 when absent */
};

enum { USBMUX_EVENT_NONE = 0, USBMUX_EVENT_ATTACHED = 1, USBMUX_EVENT_DETACHED = 2 };

struct usbmux_event {
    int                  type; /* USBMUX_EVENT_* */
    struct usbmux_device device; /* device_id always set; serial only on Attached */
};

/* ---- header ---- */
void usbmux_write_header(uint8_t out[USBMUX_HEADER_SIZE], uint32_t payload_len,
                         uint32_t tag);
int  usbmux_parse_header(const uint8_t in[USBMUX_HEADER_SIZE], uint32_t *payload_len,
                         uint32_t *version, uint32_t *message, uint32_t *tag);

/* ---- plist encoders ----
 * prog_name / client_version may be NULL for the library defaults.
 * The written text is NOT NUL-terminated in *written; the buffer is NUL-terminated
 * when there is room. */
int usbmux_plist_encode_listdevices(char *out, size_t cap, const char *prog_name,
                                    const char *client_version, size_t *written);
int usbmux_plist_encode_listen(char *out, size_t cap, const char *prog_name,
                               const char *client_version, size_t *written);
/* port is in HOST order; htons() happens in here. Never pass a swapped port. */
int usbmux_plist_encode_connect(char *out, size_t cap, uint32_t device_id, uint16_t port,
                                const char *prog_name, const char *client_version,
                                size_t *written);

/* ---- plist decoders ---- */
/* Reads MessageType. Copies into out (NUL-terminated). */
int usbmux_plist_message_type(const char *xml, size_t len, char *out, size_t cap);
/* Requires MessageType == Result. */
int usbmux_plist_decode_result(const char *xml, size_t len, uint32_t *number);
/* DeviceList reply. Network entries are dropped: only ConnectionType == "USB". */
int usbmux_plist_decode_devicelist(const char *xml, size_t len, struct usbmux_device *out,
                                   size_t max, size_t *count);
/* Attached / Detached event. Attached with ConnectionType != "USB" yields
 * USBMUX_EVENT_NONE and USBMUX_OK — a filtered, not a failed, event. */
int usbmux_plist_decode_event(const char *xml, size_t len, struct usbmux_event *out);

/* ---- socket API ---- */
/* Connects, sends ListDevices, fills out[]. USB devices only. */
int usbmux_list_devices(struct usbmux_device *out, size_t max, size_t *count);
/* Opens a tunnel to device_id:port (port in HOST order). Returns the fd, or -1.
 * On -1, *result (may be NULL) carries the usbmuxd Number when one was received,
 * otherwise -1; errno is set for syscall failures. */
int usbmux_connect(uint32_t device_id, uint16_t port, int *result);
/* Opens the event connection and sends Listen. Returns USBMUX_OK and sets *fd_out. */
int usbmux_listen(int *fd_out);
/* Waits up to timeout_ms for the next Attached/Detached. USBMUX_ERR_TIMEOUT when
 * none arrived. Filtered (non-USB) events are returned as USBMUX_EVENT_NONE. */
int usbmux_listen_next(int fd, struct usbmux_event *out, int timeout_ms);

const char *usbmux_strerror(int code);

#ifdef __cplusplus
}
#endif
#endif /* IUCM_USBMUX_H */
