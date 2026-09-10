/*
obs-iphone-usb-cam: OBS source "TetherCam (iPhone via USB)"
Copyright (C) 2026 Bernhard Goetzendorfer <venturestudio@ai-at.eu>
SPDX-License-Identifier: GPL-2.0-or-later

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>
*/

#include "iphone_source.h"
#include "aac_decoder.h"
#include "hevc_decoder.h"

#include <obs-module.h>
#include <plugin-support.h>
#include <media-io/audio-io.h>
#include <media-io/video-io.h>

extern "C" {
#include "frame_parser.h"
#include "usbmux.h"
}

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define S_DEVICE "device_serial"
#define S_CAMERA "camera_id"
#define S_RESOLUTION "resolution"
#define S_FPS "fps"
#define S_BITRATE "bitrate_kbps"
#define S_DEBUG_TCP "debug_tcp"
#define S_ROTATION "rotation"
#define S_AUDIO "audio"

/* AUDIO arrives ~47x per second; every irregularity is logged at most once
 * per 5 s, same idiom as the STATS info line. */
#define IUCM_AUDIO_LOG_INTERVAL_MS 5000

#define IUCM_PORT 7878
#define IUCM_PARSER_CAP (IUCM_HEADER_SIZE + IUCM_MAX_PAYLOAD + 64u)
#define IUCM_PING_INTERVAL_MS 2000
#define IUCM_MAX_MISSED_PONG 3
/* A tunnel that opens but never speaks would otherwise keep the session in
 * link_state::starting forever; these two deadlines force the reconnect path. */
#define IUCM_HELLO_TIMEOUT_MS 5000
#define IUCM_CONFIG_TIMEOUT_MS 5000
/* "no USB device attached" is the normal state of an unplugged Mac and the
 * retry runs every 1-5 s, so the line is rate-limited. */
#define IUCM_NO_DEVICE_LOG_INTERVAL_MS 30000

namespace {

struct camera_entry {
	uint8_t id;
	std::string name;
};

/* What the properties dialog tells the user. The worker owns the transitions,
 * the UI thread only reads. Deliberately coarse: the dialog is opened by hand,
 * so a state that is a second stale is still the right answer. */
enum class link_state {
	no_device,  /* usbmuxd lists no USB device */
	waiting,    /* device attached, but nothing listening on 7878 (app closed or backgrounded) */
	starting,   /* socket open, no CONFIG yet */
	streaming,
	incompatible, /* peer speaks a protocol major we do not support */
	busy,         /* the phone already serves another receiver */
};

struct iphone_source {
	obs_source_t *source = nullptr;

	std::thread worker;
	std::atomic<bool> running{false};
	std::atomic<bool> restart{false};

	/* Self-pipe. Created in create() before the worker starts, closed in
	 * destroy() after the join. update()/destroy() set their flag and write one
	 * byte here; the worker has the read end in its poll() set and wakes up at
	 * once. Only the worker ever closes the data fd (fd, below), so the UI
	 * thread can never touch an fd number the worker has already recycled. */
	int wake_r = -1;
	int wake_w = -1;

	/* settings snapshot, guarded by cfg_mutex */
	std::mutex cfg_mutex;
	std::string serial;
	std::string debug_tcp;
	int camera_id = 0;
	int width = 1920;
	int height = 1080;
	int fps = 30;
	int bitrate_kbps = 12000;
	int rotation = 0;    /* 0/90/180/270, applied by OBS on the async frame */
	bool audio = true;   /* ask the phone for AUDIO via START bit 0 */

	/* camera list cached from the last HELLO, guarded by cfg_mutex */
	std::vector<camera_entry> cameras;

	/* status snapshot for the properties dialog, guarded by cfg_mutex */
	link_state status_state = link_state::no_device;
	std::string status_serial;
	int status_width = 0;
	int status_height = 0;
	int status_fps = 0;
	double status_measured_fps = 0.0;
	/* 0 = no audio on this connection. The rate comes from AUDIO_CONFIG, the
	 * mute flag from STATS (PROTOCOL.md 4.8, bit 5). */
	int status_audio_rate = 0;
	bool status_audio_muted = false;
	/* The phone answered the audio request with ERROR 6 MIC_DENIED
	 * (PROTOCOL.md 4.7). Video keeps running, so this is a note in the status
	 * line, not a connection state. */
	bool status_audio_denied = false;

	/* per-connection state, worker thread only */
	int fd = -1;
	iucm_decoder_t *dec = nullptr;
	bool started = false;
	bool config_seen = false;
	int missed_pongs = 0;
	uint64_t last_ping_ts = 0;
	uint64_t frames_since_report = 0;
	uint64_t bytes_since_report = 0;
	uint64_t report_deadline_ms = 0;
	uint8_t active_camera_id = 0;
	/* STATS (0x12) arrives once a second; LOG_INFO would flood the log, so the
	 * info line is rate-limited to one per 5 s. Every STATS still goes to
	 * LOG_DEBUG. 0 = log the first one immediately after connecting. */
	uint64_t stats_log_deadline_ms = 0;
	/* Set when the phone closed the socket cleanly (app backgrounded, STOP).
	 * Reconnecting in the same millisecond just races the listener teardown,
	 * so the worker waits 250 ms once. */
	bool peer_closed = false;
	/* Consecutive failed connect attempts. A phone that is simply unplugged is
	 * the normal case, so the first four retries stay at LOG_INFO. */
	int connect_failures = 0;
	bool fatal = false; /* close the connection, do not retry immediately */
	/* Status shown while a fatal condition holds. close_connection() would
	 * otherwise fall back to "waiting", which reads as "open the app" and is
	 * the wrong advice for a version mismatch or a busy phone. */
	link_state fatal_state = link_state::waiting;
	/* Last accepted CONFIG. A CONFIG that repeats these values does not need a
	 * new decoder session (rebuilding one costs the next keyframe). */
	std::vector<uint8_t> dec_hvcc;
	int dec_width = 0;
	int dec_height = 0;
	int dec_fps = 0;

	/* Audio, worker thread only. audio_requested records what the START of
	 * this connection asked for, so AUDIO arriving after the user switched
	 * audio off is dropped instead of played. */
	iucm_aac_decoder_t *adec = nullptr;
	bool audio_requested = false;
	uint32_t adec_rate = 0;
	uint8_t adec_channels = 0;
	std::vector<uint8_t> adec_asc;
	uint64_t audio_log_deadline_ms = 0;
	/* Non-fatal ERROR frames can repeat as fast as the app retries, so their
	 * log line is rate-limited the same way. 0 = log the first one at once. */
	uint64_t error_log_deadline_ms = 0;

	float color_matrix[16];
	float color_min[3];
	float color_max[3];
};

void set_status(iphone_source *s, link_state st)
{
	std::lock_guard<std::mutex> lock(s->cfg_mutex);
	s->status_state = st;
	if (st != link_state::streaming)
		s->status_measured_fps = 0.0;
}

uint64_t now_ms(void)
{
	return (uint64_t) std::chrono::duration_cast<std::chrono::milliseconds>(
			       std::chrono::steady_clock::now().time_since_epoch())
		.count();
}

uint64_t now_us(void)
{
	return (uint64_t) std::chrono::duration_cast<std::chrono::microseconds>(
			       std::chrono::steady_clock::now().time_since_epoch())
		.count();
}

/* Worker thread only. The socket carries SO_SNDTIMEO (see worker_main), so a
 * stalled peer surfaces as EAGAIN instead of blocking forever — that is what
 * lets us drop the old shutdown()-from-the-UI-thread wakeup. */
bool send_all(iphone_source *s, const uint8_t *buf, size_t len)
{
	size_t off = 0;
	while (off < len) {
		ssize_t n = send(s->fd, buf + off, len - off, 0);
		if (n > 0) {
			off += (size_t) n;
			continue;
		}
		if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
			if (!s->running.load() || s->restart.load())
				return false;
			continue;
		}
		return false;
	}
	return true;
}

/* Callable from any thread. Writing to a full pipe is not possible in practice
 * (the worker drains it) and would only mean "already woken", so EAGAIN on the
 * non-blocking write end is ignored. */
void wake_worker(iphone_source *s)
{
	if (s->wake_w < 0)
		return;
	const uint8_t b = 1;
	ssize_t n;
	do {
		n = write(s->wake_w, &b, 1);
	} while (n < 0 && errno == EINTR);
	(void) n;
}

/* --- connection setup ------------------------------------------------- */

int connect_tcp(const std::string &hostport, int loglevel)
{
	std::string host = hostport;
	std::string port = "7878";
	size_t colon = hostport.rfind(':');
	if (colon != std::string::npos) {
		host = hostport.substr(0, colon);
		port = hostport.substr(colon + 1);
	}
	if (host.empty())
		host = "127.0.0.1";

	struct addrinfo hints = {};
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	struct addrinfo *res = nullptr;
	int rc = getaddrinfo(host.c_str(), port.c_str(), &hints, &res);
	if (rc != 0 || !res) {
		obs_log(loglevel, "[iphone-cam] debug_tcp: cannot resolve %s: %s", hostport.c_str(),
			gai_strerror(rc));
		return -1;
	}
	int fd = -1;
	for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
		fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
		if (fd < 0)
			continue;
		if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0)
			break;
		close(fd);
		fd = -1;
	}
	freeaddrinfo(res);
	return fd;
}

/* out_device_count reports what the ListDevices call in here already saw, so the
 * caller can tell "no cable" from "app not listening" without asking usbmuxd a
 * second time. It is 0 when the query itself failed. */
int connect_usbmux(const std::string &serial, std::string &out_serial, int loglevel, size_t &out_device_count)
{
	struct usbmux_device devices[16];
	size_t count = 0;
	out_device_count = 0;
	int rc = usbmux_list_devices(devices, 16, &count);
	if (rc != USBMUX_OK) {
		obs_log(loglevel, "[iphone-cam] usbmux ListDevices failed: %s", usbmux_strerror(rc));
		return -1;
	}
	out_device_count = count;
	if (count == 0) {
		/* Same throttle idiom as the STATS info line. */
		static uint64_t no_device_log_deadline_ms = 0;
		uint64_t now = now_ms();
		if (now >= no_device_log_deadline_ms) {
			no_device_log_deadline_ms = now + IUCM_NO_DEVICE_LOG_INTERVAL_MS;
			obs_log(LOG_INFO, "[iphone-cam] no USB device attached");
		}
		return -1;
	}
	const struct usbmux_device *pick = nullptr;
	if (serial.empty()) {
		pick = &devices[0];
	} else {
		for (size_t i = 0; i < count; i++) {
			if (serial == devices[i].serial) {
				pick = &devices[i];
				break;
			}
		}
	}
	if (!pick) {
		obs_log(LOG_INFO, "[iphone-cam] device %s not attached", serial.c_str());
		return -1;
	}
	out_serial = pick->serial;

	int result = -1;
	int fd = usbmux_connect(pick->device_id, IUCM_PORT, &result);
	if (fd < 0) {
		obs_log(loglevel, "[iphone-cam] usbmux Connect to %s:%d failed (result %d, errno %d)",
			pick->serial, IUCM_PORT, result, errno);
		return -1;
	}
	return fd;
}

/* --- decoded-frame sink ----------------------------------------------- */

void on_decoded_frame(void *ctx, CVPixelBufferRef pb, uint64_t pts_us)
{
	auto *ctxs = static_cast<iphone_source *>(ctx);
	if (!pb)
		return;
	if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess)
		return;

	struct obs_source_frame2 frame = {};
	frame.width = (uint32_t) CVPixelBufferGetWidth(pb);
	frame.height = (uint32_t) CVPixelBufferGetHeight(pb);
	frame.format = VIDEO_FORMAT_NV12;
	frame.range = VIDEO_RANGE_PARTIAL;
	frame.timestamp = pts_us * 1000ULL;
	memcpy(frame.color_matrix, ctxs->color_matrix, sizeof(frame.color_matrix));
	memcpy(frame.color_range_min, ctxs->color_min, sizeof(frame.color_range_min));
	memcpy(frame.color_range_max, ctxs->color_max, sizeof(frame.color_range_max));

	size_t planes = CVPixelBufferGetPlaneCount(pb);
	if (planes < 2) {
		CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
		return;
	}
	for (size_t i = 0; i < 2; i++) {
		frame.data[i] = (uint8_t *) CVPixelBufferGetBaseAddressOfPlane(pb, i);
		frame.linesize[i] = (uint32_t) CVPixelBufferGetBytesPerRowOfPlane(pb, i);
	}

	obs_source_output_video2(ctxs->source, &frame);
	CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);

	ctxs->frames_since_report++;
}

/* --- protocol handling ------------------------------------------------ */

/* Worker thread only. AUDIO arrives ~47x per second, so anything that can be
 * wrong about it can be wrong 47 times per second; one line per 5 s is enough
 * to see it in the log. */
bool audio_log_due(iphone_source *s)
{
	uint64_t now = now_ms();
	if (now < s->audio_log_deadline_ms)
		return false;
	s->audio_log_deadline_ms = now + IUCM_AUDIO_LOG_INTERVAL_MS;
	return true;
}

/* Worker thread only. Same throttle for the non-fatal ERROR frames: an app that
 * cannot start its encoder may say so on every rebuild attempt. */
bool error_log_due(iphone_source *s)
{
	uint64_t now = now_ms();
	if (now < s->error_log_deadline_ms)
		return false;
	s->error_log_deadline_ms = now + IUCM_AUDIO_LOG_INTERVAL_MS;
	return true;
}

int on_message(void *ctx, const struct iucm_msg *msg)
{
	auto *s = static_cast<iphone_source *>(ctx);
	uint8_t out[64];
	size_t written = 0;

	switch (msg->type) {
	case IUCM_MSG_HELLO: {
		struct iucm_hello hello = {};
		int rc = iucm_parse_hello(msg->payload, msg->length, &hello);
		if (rc != IUCM_OK) {
			obs_log(LOG_WARNING, "[iphone-cam] bad HELLO: %s", iucm_strerror(rc));
			s->fatal = true;
			s->fatal_state = link_state::incompatible;
			return 1;
		}
		if (IUCM_VERSION_MAJOR(hello.version) != 1) {
			obs_log(LOG_WARNING, "[iphone-cam] unsupported protocol major %u — sending ERROR 5",
				(unsigned) IUCM_VERSION_MAJOR(hello.version));
			if (iucm_encode_error(out, sizeof(out), IUCM_ERRCODE_VERSION_UNSUPPORTED, "major", &written) ==
			    IUCM_OK)
				send_all(s, out, written);
			s->fatal = true;
			s->fatal_state = link_state::incompatible;
			return 1;
		}
		obs_log(LOG_INFO, "[iphone-cam] HELLO from '%s' (app %s, proto %u.%u, %u cameras)", hello.name,
			hello.app_version, (unsigned) IUCM_VERSION_MAJOR(hello.version),
			(unsigned) IUCM_VERSION_MINOR(hello.version), (unsigned) hello.camera_count);

		/* Tell the phone who is on the other end so its UI can name us
		 * (PROTOCOL.md 4.11). Optional and one-way: an app that predates 1.2
		 * skips the unknown type, so this is sent unconditionally, after HELLO
		 * and before START. */
		{
			struct iucm_client_info ci = {};
			uint8_t ci_buf[128];
			size_t ci_written = 0;
			ci.kind = IUCM_CLIENT_OBS_PLUGIN;
			snprintf(ci.name, sizeof(ci.name), "%s", "TetherCam OBS plugin");
			snprintf(ci.version, sizeof(ci.version), "%s", PLUGIN_VERSION);
			if (iucm_encode_client_info(ci_buf, sizeof(ci_buf), &ci, &ci_written) != IUCM_OK ||
			    !send_all(s, ci_buf, ci_written)) {
				/* Not fatal: the stream works without an identity. */
				obs_log(LOG_INFO, "[iphone-cam] sending CLIENT_INFO failed, continuing");
			}
		}

		struct iucm_start start = {};
		bool want_audio = false;
		{
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			s->cameras.clear();
			for (uint8_t i = 0; i < hello.camera_count && i < IUCM_MAX_CAMERAS; i++)
				s->cameras.push_back({hello.cameras[i].id, std::string(hello.cameras[i].name)});
			start.camera_id = (uint8_t) s->camera_id;
			start.width = (uint16_t) s->width;
			start.height = (uint16_t) s->height;
			start.fps = (uint16_t) s->fps;
			start.bitrate_kbps = (uint32_t) s->bitrate_kbps;
			want_audio = s->audio;
		}
		/* The flags byte decides the payload length: 12 bytes with the audio
		 * wish, the 1.0-compatible 11 without it (PROTOCOL.md 4.2). A 1.0 app
		 * (App Store 0.1.0) silently drops the 12-byte form and never starts
		 * the camera, so the wish is only sent once HELLO announces 1.1. */
		if (want_audio && IUCM_VERSION_MINOR(hello.version) < 1) {
			obs_log(LOG_INFO,
				"[iphone-cam] app %s speaks protocol 1.%u: audio needs 1.1, "
				"starting video only (update the TetherCam app on the phone)",
				hello.app_version, (unsigned) IUCM_VERSION_MINOR(hello.version));
			want_audio = false;
		}
		start.flags = want_audio ? (uint8_t) IUCM_START_FLAG_AUDIO : (uint8_t) 0;
		if (iucm_encode_start(out, sizeof(out), &start, &written) != IUCM_OK ||
		    !send_all(s, out, written)) {
			obs_log(LOG_WARNING, "[iphone-cam] sending START failed: errno %d (%s)", errno,
				strerror(errno));
			return 1;
		}
		s->started = true;
		s->active_camera_id = start.camera_id;
		s->audio_requested = want_audio;
		obs_log(LOG_INFO, "[iphone-cam] START sent: cam %u, %ux%u@%u, %u kbps, audio %s",
			(unsigned) start.camera_id, (unsigned) start.width, (unsigned) start.height,
			(unsigned) start.fps, (unsigned) start.bitrate_kbps, want_audio ? "on" : "off");
		return 0;
	}
	case IUCM_MSG_CONFIG: {
		struct iucm_config cfg = {};
		int rc = iucm_parse_config(msg->payload, msg->length, &cfg);
		if (rc != IUCM_OK) {
			obs_log(LOG_WARNING, "[iphone-cam] bad CONFIG: %s", iucm_strerror(rc));
			return 1;
		}
		/* A rotation on the phone changes the encoded geometry, so CONFIG can
		 * arrive mid-stream. The decoder is rebuilt when anything changed and
		 * OBS resizes the async source from the next frame's dimensions. */
		obs_log(LOG_INFO, "[iphone-cam] CONFIG received: cam %u, %ux%u@%u, hvcC %u bytes",
			(unsigned) s->active_camera_id, (unsigned) cfg.width, (unsigned) cfg.height,
			(unsigned) cfg.fps, (unsigned) cfg.hvcc_len);
		/* Rebuilding the session costs the wait for the next keyframe, so an
		 * identical CONFIG (the app re-announces after a no-op rotation) keeps
		 * the running decoder. */
		if (s->dec && s->dec_width == (int) cfg.width && s->dec_height == (int) cfg.height &&
		    s->dec_fps == (int) cfg.fps && s->dec_hvcc.size() == (size_t) cfg.hvcc_len &&
		    (cfg.hvcc_len == 0 || memcmp(s->dec_hvcc.data(), cfg.hvcc, cfg.hvcc_len) == 0)) {
			obs_log(LOG_INFO, "[iphone-cam] CONFIG unchanged, keeping decoder");
			return 0;
		}
		if (s->dec) {
			iucm_decoder_destroy(s->dec);
			s->dec = nullptr;
		}
		s->dec = iucm_decoder_create(cfg.hvcc, cfg.hvcc_len, cfg.width, cfg.height, on_decoded_frame, s);
		if (!s->dec) {
			obs_log(LOG_WARNING, "[iphone-cam] decoder setup failed for %ux%u, hvcC %u bytes",
				(unsigned) cfg.width, (unsigned) cfg.height, (unsigned) cfg.hvcc_len);
			s->dec_hvcc.clear();
			s->dec_width = s->dec_height = s->dec_fps = 0;
			return 1;
		}
		s->dec_hvcc.assign(cfg.hvcc, cfg.hvcc + cfg.hvcc_len);
		s->dec_width = (int) cfg.width;
		s->dec_height = (int) cfg.height;
		s->dec_fps = (int) cfg.fps;
		s->config_seen = true;
		{
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			s->status_state = link_state::streaming;
			s->status_width = (int) cfg.width;
			s->status_height = (int) cfg.height;
			s->status_fps = (int) cfg.fps;
		}
		return 0;
	}
	case IUCM_MSG_VIDEO: {
		if (!s->dec)
			return 0; /* no CONFIG yet — drop */
		struct iucm_video_iter it = {};
		int rc = iucm_video_iter_init(&it, msg->payload, msg->length);
		if (rc != IUCM_OK) {
			obs_log(LOG_WARNING, "[iphone-cam] bad VIDEO: %s", iucm_strerror(rc));
			return 1;
		}
		/* Everything after the 8-byte pts is handed to VideoToolbox unchanged. */
		const uint8_t *body = msg->payload + 8;
		uint32_t body_len = msg->length - 8;
		bool keyframe = (msg->flags & IUCM_FLAG_KEYFRAME) != 0;
		s->bytes_since_report += body_len;
		uint64_t before = iucm_decoder_frames(s->dec);
		iucm_decoder_decode(s->dec, body, body_len, it.pts_us, keyframe);
		if (before == 0 && iucm_decoder_frames(s->dec) > 0) {
			obs_log(LOG_INFO, "[iphone-cam] first frame decoded (pts %llu us)",
				(unsigned long long) it.pts_us);
			/* Start the window here: the seconds spent connecting and waiting
			 * for the first keyframe would otherwise be counted as dropped
			 * frames and make the first report look broken. */
			s->frames_since_report = 0;
			s->bytes_since_report = 0;
			s->report_deadline_ms = now_ms() + 5000;
		}
		return 0;
	}
	case IUCM_MSG_AUDIO_CONFIG: {
		/* 8 + asc_len, PROTOCOL.md 4.9. A malformed or unusable config is
		 * never fatal: audio stays off and the video keeps running. */
		if (!s->audio_requested)
			return 0;
		struct iucm_audio_config acfg = {};
		int arc = iucm_parse_audio_config(msg->payload, msg->length, &acfg);
		if (arc != IUCM_OK) {
			obs_log(LOG_WARNING, "[iphone-cam] bad AUDIO_CONFIG (%u bytes): %s",
				(unsigned) msg->length, iucm_strerror(arc));
			return 0;
		}
		uint32_t rate = acfg.sample_rate;
		uint8_t channels = acfg.channels;
		uint8_t codec = acfg.codec;
		uint16_t asc_len = acfg.asc_len;
		if (codec != IUCM_AUDIO_CODEC_AAC_LC) {
			/* Passed through, not refused (PROTOCOL.md 4.9). */
			obs_log(LOG_WARNING, "[iphone-cam] unknown audio codec %u — audio stays off",
				(unsigned) codec);
			return 0;
		}
		const uint8_t *asc = acfg.asc;
		if (asc_len == 0 || !asc) {
			/* Legal framing, unusable for AAC-LC (PROTOCOL.md 4.9): without the
			 * magic cookie no audio path is started. */
			obs_log(LOG_WARNING, "[iphone-cam] AUDIO_CONFIG without AudioSpecificConfig, audio stays off");
			return 0;
		}
		/* Same reasoning as CONFIG: rebuilding costs samples, and the app
		 * re-announces unchanged parameters. */
		if (s->adec && !iucm_aac_decoder_failed(s->adec) && s->adec_rate == rate &&
		    s->adec_channels == channels && s->adec_asc.size() == (size_t) asc_len &&
		    (asc_len == 0 || memcmp(s->adec_asc.data(), asc, asc_len) == 0)) {
			obs_log(LOG_INFO, "[iphone-cam] AUDIO_CONFIG unchanged, keeping audio decoder");
			return 0;
		}
		if (s->adec) {
			iucm_aac_decoder_destroy(s->adec);
			s->adec = nullptr;
		}
		s->adec_asc.clear();
		s->adec_rate = 0;
		s->adec_channels = 0;
		{
			/* The old rate is gone the moment the old decoder is: the status
			 * line must not keep advertising audio that no longer plays. */
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			s->status_audio_rate = 0;
		}
		obs_log(LOG_INFO, "[iphone-cam] AUDIO_CONFIG received: %u Hz, %u ch, codec %u, ASC %u bytes",
			(unsigned) rate, (unsigned) channels, (unsigned) codec, (unsigned) asc_len);
		s->adec = iucm_aac_decoder_create(rate, channels, asc, asc_len);
		if (!s->adec)
			return 0;
		s->adec_asc.assign(asc, asc + asc_len);
		s->adec_rate = rate;
		s->adec_channels = channels;
		{
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			s->status_audio_rate = (int) rate;
		}
		return 0;
	}
	case IUCM_MSG_AUDIO: {
		/* 8-byte pts plus exactly one raw AAC access unit (PROTOCOL.md 4.10). */
		if (!s->audio_requested)
			return 0;
		struct iucm_audio au = {};
		if (iucm_parse_audio(msg->payload, msg->length, &au) != IUCM_OK) {
			if (audio_log_due(s))
				obs_log(LOG_WARNING, "[iphone-cam] short AUDIO (%u bytes)", (unsigned) msg->length);
			return 0;
		}
		if (!s->adec) {
			/* AUDIO without a usable AUDIO_CONFIG: drop, never abort. */
			if (audio_log_due(s))
				obs_log(LOG_INFO, "[iphone-cam] AUDIO without AUDIO_CONFIG — dropping");
			return 0;
		}
		uint64_t pts_us = au.pts_us;
		uint32_t body_len = au.len;
		if (body_len == 0)
			return 0; /* an empty frame is valid and carries nothing */
		s->bytes_since_report += body_len;

		const float *pcm = nullptr;
		uint32_t frames = 0;
		if (!iucm_aac_decoder_decode(s->adec, au.frame, body_len, &pcm, &frames)) {
			if (iucm_aac_decoder_failed(s->adec)) {
				/* The decoder tore its converter down; wait for the
				 * next AUDIO_CONFIG to build a fresh one. */
				iucm_aac_decoder_destroy(s->adec);
				s->adec = nullptr;
				s->adec_asc.clear();
				s->adec_rate = 0;
				s->adec_channels = 0;
				std::lock_guard<std::mutex> lock(s->cfg_mutex);
				s->status_audio_rate = 0;
			}
			return 0;
		}
		if (!pcm || frames == 0)
			return 0;

		struct obs_source_audio audio = {};
		audio.data[0] = (const uint8_t *) pcm;
		audio.frames = frames;
		audio.speakers = s->adec_channels == 2 ? SPEAKERS_STEREO : SPEAKERS_MONO;
		audio.samples_per_sec = s->adec_rate;
		audio.format = AUDIO_FORMAT_FLOAT; /* Float32 interleaved, see aac_decoder.h */
		audio.timestamp = pts_us * 1000ULL; /* same clock as the video frames */
		obs_source_output_audio(s->source, &audio);
		if (iucm_aac_decoder_frames(s->adec) == 1)
			obs_log(LOG_INFO, "[iphone-cam] first audio frame decoded (%u frames, pts %llu us)",
				(unsigned) frames, (unsigned long long) pts_us);
		return 0;
	}
	case IUCM_MSG_STATS: {
		struct iucm_stats st = {};
		if (iucm_parse_stats(msg->payload, msg->length, &st) != IUCM_OK) {
			obs_log(LOG_DEBUG, "[iphone-cam] bad STATS (%u bytes)", (unsigned) msg->length);
			return 0;
		}
		char flags[64];
		snprintf(flags, sizeof(flags), "%s%s%s%s%s%s",
			 (st.flags & IUCM_STATS_FLAG_AUTO) ? "auto," : "",
			 (st.flags & IUCM_STATS_FLAG_LEVEL) ? "level," : "",
			 (st.flags & IUCM_STATS_FLAG_OVERSAMP) ? "oversample," : "",
			 (st.flags & IUCM_STATS_FLAG_FLAT_HOLD) ? "flat-hold," : "",
			 (st.flags & IUCM_STATS_FLAG_AUDIO_ACTIVE) ? "audio_active," : "",
			 (st.flags & IUCM_STATS_FLAG_AUDIO_MUTED) ? "audio_muted," : "");
		size_t fl = strlen(flags);
		if (fl > 0)
			flags[fl - 1] = '\0'; /* drop the trailing comma */
		else
			snprintf(flags, sizeof(flags), "none");

		/* One format string, two levels: every sample at DEBUG, one per 5 s at
		 * INFO so a normal log stays readable but still carries the device state. */
		/* Bits 4 and 5 are informational (PROTOCOL.md 4.8): the mute state only
		 * reaches the properties dialog, it never changes the audio path. */
		{
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			s->status_audio_muted = (st.flags & IUCM_STATS_FLAG_AUDIO_MUTED) != 0;
		}
		uint64_t now = now_ms();
		bool info = now >= s->stats_log_deadline_ms;
		if (info)
			s->stats_log_deadline_ms = now + 5000;
		obs_log(info ? LOG_INFO : LOG_DEBUG,
			"[iphone-cam] stats: angle=%+.1f sector=%u residual=%+.1f m=%.2f leveler=%.1fms drop=%u src=%ux%u out=%ux%u flags=%s cam=%u",
			st.continuous_angle_x10 / 10.0, (unsigned) st.sector, st.residual_x10 / 10.0,
			st.gravity_m_x1000 / 1000.0, st.leveler_ms_x10 / 10.0,
			(unsigned) st.dropped_frames, (unsigned) st.source_width,
			(unsigned) st.source_height, (unsigned) st.output_width,
			(unsigned) st.output_height, flags, (unsigned) st.camera_id);
		return 0;
	}
	case IUCM_MSG_PONG: {
		uint64_t ts = 0;
		if (iucm_parse_timestamp(msg->payload, msg->length, &ts) == IUCM_OK) {
			s->missed_pongs = 0;
		}
		return 0;
	}
	case IUCM_MSG_PING: {
		uint64_t ts = 0;
		if (iucm_parse_timestamp(msg->payload, msg->length, &ts) == IUCM_OK &&
		    iucm_encode_pong(out, sizeof(out), ts, &written) == IUCM_OK)
			send_all(s, out, written);
		return 0;
	}
	case IUCM_MSG_ERROR: {
		struct iucm_error err = {};
		if (iucm_parse_error(msg->payload, msg->length, &err) != IUCM_OK) {
			/* A malformed ERROR says nothing about the session, and the
			 * parser already skipped it. Never a reason to disconnect. */
			if (error_log_due(s))
				obs_log(LOG_WARNING, "[iphone-cam] bad ERROR frame (%u bytes)",
					(unsigned) msg->length);
			return 0;
		}
		/* Only BUSY and VERSION_UNSUPPORTED are fatal (PROTOCOL.md 4.7): the
		 * sender closes after them. Every other code, known or not, leaves the
		 * connection usable, so the receiver holds it. Returning 1 here would
		 * abort the parser, drop the socket and reconnect at once, which for a
		 * repeating cause such as MIC_DENIED is an endless loop without a
		 * picture. */
		if (err.code == IUCM_ERRCODE_BUSY || err.code == IUCM_ERRCODE_VERSION_UNSUPPORTED) {
			obs_log(LOG_WARNING, "[iphone-cam] peer ERROR %u: %s", (unsigned) err.code, err.text);
			s->fatal = true;
			s->fatal_state = err.code == IUCM_ERRCODE_BUSY ? link_state::busy
								      : link_state::incompatible;
			return 1;
		}
		if (err.code == IUCM_ERRCODE_MIC_DENIED) {
			/* The user refused the microphone on the phone. Audio will not
			 * arrive on this connection; the video path is untouched. */
			bool first = false;
			{
				std::lock_guard<std::mutex> lock(s->cfg_mutex);
				first = !s->status_audio_denied;
				s->status_audio_denied = true;
			}
			if (first)
				obs_log(LOG_WARNING,
					"[iphone-cam] peer ERROR 6 MIC_DENIED: %s - audio stays off, video keeps running",
					err.text);
			return 0;
		}
		if (error_log_due(s))
			obs_log(LOG_WARNING, "[iphone-cam] peer ERROR %u (non-fatal): %s", (unsigned) err.code,
				err.text);
		return 0;
	}
	default:
		return 0; /* unknown types are skipped, PROTOCOL.md 2 */
	}
}

/* --- worker thread ---------------------------------------------------- */

void close_connection(iphone_source *s)
{
	if (s->dec) {
		iucm_decoder_destroy(s->dec);
		s->dec = nullptr;
	}
	s->dec_hvcc.clear();
	s->dec_width = s->dec_height = s->dec_fps = 0;
	if (s->adec) {
		iucm_aac_decoder_destroy(s->adec);
		s->adec = nullptr;
	}
	s->adec_asc.clear();
	s->adec_rate = 0;
	s->adec_channels = 0;
	s->audio_requested = false;
	{
		std::lock_guard<std::mutex> lock(s->cfg_mutex);
		s->status_audio_rate = 0;
		s->status_audio_muted = false;
		s->status_audio_denied = false;
	}
	s->audio_log_deadline_ms = 0; /* log the first audio oddity of the next session at once */
	s->error_log_deadline_ms = 0; /* same for the first non-fatal ERROR */
	if (s->fd >= 0) {
		close(s->fd);
		s->fd = -1;
	}
	s->started = false;
	s->config_seen = false;
	s->missed_pongs = 0;
	s->stats_log_deadline_ms = 0; /* log the first STATS of the next session at once */
	/* The device is usually still attached, only the app is gone. The next
	 * failed connect attempt corrects this to no_device if the cable went.
	 * A fatal condition keeps its own state so the dialog does not tell the
	 * user to open an app that is already open. */
	set_status(s, s->fatal ? s->fatal_state : link_state::waiting);
	/* Clear the source so OBS does not keep showing a frozen frame. */
	obs_source_output_video2(s->source, nullptr);
}

void run_session(iphone_source *s, std::vector<uint8_t> &parse_buf)
{
	struct iucm_parser parser;
	iucm_parser_init(&parser, parse_buf.data(), parse_buf.size());

	uint8_t rx[65536];
	uint8_t out[64];
	size_t written = 0;

	s->last_ping_ts = now_ms();
	/* Deadlines for the silent-tunnel cases: usbmux hands out a socket as soon
	 * as the port is open, so a wedged app looks exactly like a healthy one
	 * until the first message arrives. */
	const uint64_t session_start_ms = now_ms();
	uint64_t hello_ms = 0;
	s->report_deadline_ms = now_ms() + 5000;
	s->frames_since_report = 0;
	s->bytes_since_report = 0;

	while (s->running.load() && !s->restart.load() && !s->fatal) {
		struct pollfd pfd[2];
		pfd[0] = {s->fd, POLLIN, 0};
		pfd[1] = {s->wake_r, POLLIN, 0}; /* -1 is ignored by poll() */
		int pr = poll(pfd, 2, 200);
		if (pr < 0) {
			if (errno == EINTR)
				continue;
			obs_log(LOG_WARNING, "[iphone-cam] poll failed: errno %d (%s)", errno, strerror(errno));
			return;
		}
		if (pr > 0 && (pfd[1].revents & POLLIN)) {
			/* Stop or reconfigure requested. Drain the pipe and re-test the
			 * loop condition; the caller closes the socket. */
			uint8_t drain[64];
			while (read(s->wake_r, drain, sizeof(drain)) > 0)
				;
			continue;
		}
		if (pr > 0 && (pfd[0].revents & (POLLIN | POLLHUP | POLLERR))) {
			ssize_t n = recv(s->fd, rx, sizeof(rx), 0);
			if (n == 0) {
				obs_log(LOG_INFO, "[iphone-cam] peer closed the connection");
				s->peer_closed = true;
				return;
			}
			if (n < 0) {
				if (errno == EINTR || errno == EAGAIN)
					continue;
				obs_log(LOG_WARNING, "[iphone-cam] recv failed: errno %d (%s)", errno,
					strerror(errno));
				return;
			}
			int rc = iucm_parser_feed(&parser, rx, (size_t) n, on_message, s);
			if (rc != IUCM_OK) {
				obs_log(LOG_WARNING, "[iphone-cam] framing error: %s — reconnecting",
					iucm_strerror(rc));
				return;
			}
		}

		uint64_t t = now_ms();
		if (!s->started) {
			if (t - session_start_ms >= IUCM_HELLO_TIMEOUT_MS) {
				obs_log(LOG_WARNING, "[iphone-cam] no HELLO within %d ms — reconnecting",
					IUCM_HELLO_TIMEOUT_MS);
				return;
			}
		} else {
			if (hello_ms == 0)
				hello_ms = t;
			if (!s->config_seen && t - hello_ms >= IUCM_CONFIG_TIMEOUT_MS) {
				obs_log(LOG_WARNING, "[iphone-cam] no CONFIG within %d ms — reconnecting",
					IUCM_CONFIG_TIMEOUT_MS);
				return;
			}
		}
		if (s->started && t - s->last_ping_ts >= IUCM_PING_INTERVAL_MS) {
			s->last_ping_ts = t;
			s->missed_pongs++;
			if (s->missed_pongs > IUCM_MAX_MISSED_PONG) {
				obs_log(LOG_WARNING, "[iphone-cam] %d missed PONG — reconnecting",
					s->missed_pongs - 1);
				return;
			}
			if (iucm_encode_ping(out, sizeof(out), now_us(), &written) == IUCM_OK &&
			    !send_all(s, out, written)) {
				obs_log(LOG_WARNING, "[iphone-cam] sending PING failed: errno %d (%s)", errno,
					strerror(errno));
				return;
			}
		}
		if (t >= s->report_deadline_ms) {
			if (s->frames_since_report > 0) {
				double measured = (double) s->frames_since_report * 1000.0 / 5000.0;
				obs_log(LOG_INFO, "[iphone-cam] %.1f frames/s, %.2f Mbit/s", measured,
					(double) s->bytes_since_report * 8.0 / 5.0 / 1e6);
				std::lock_guard<std::mutex> lock(s->cfg_mutex);
				s->status_measured_fps = measured;
			}
			s->frames_since_report = 0;
			s->bytes_since_report = 0;
			s->report_deadline_ms = t + 5000;
		}
	}
}

void worker_main(iphone_source *s)
{
	/* Never emit video from create(); give OBS a moment to finish it. */
	std::this_thread::sleep_for(std::chrono::milliseconds(150));

	std::vector<uint8_t> parse_buf(IUCM_PARSER_CAP);
	int backoff_ms = 1000;

	while (s->running.load()) {
		s->restart.store(false);
		s->fatal = false;

		std::string serial, debug_tcp;
		{
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			serial = s->serial;
			debug_tcp = s->debug_tcp;
		}

		const int loglevel = s->connect_failures >= 5 ? LOG_WARNING : LOG_INFO;
		int fd = -1;
		/* Non-zero only on the usbmux path; debug_tcp never asks usbmuxd. */
		size_t device_count = 0;
		if (!debug_tcp.empty()) {
			fd = connect_tcp(debug_tcp, loglevel);
			if (fd >= 0) {
				obs_log(LOG_INFO, "[iphone-cam] connected via debug_tcp %s", debug_tcp.c_str());
				std::lock_guard<std::mutex> lock(s->cfg_mutex);
				s->status_serial = debug_tcp;
				s->status_state = link_state::starting;
			}
		} else {
			std::string used;
			fd = connect_usbmux(serial, used, loglevel, device_count);
			if (fd >= 0) {
				obs_log(LOG_INFO, "[iphone-cam] connected via usbmux to %s:%d", used.c_str(),
					IUCM_PORT);
				std::lock_guard<std::mutex> lock(s->cfg_mutex);
				s->status_serial = used;
				s->status_state = link_state::starting;
			}
		}

		if (fd < 0) {
			/* Split "cable/phone missing" from "app not in the foreground".
			 * connect_usbmux already listed the devices, so no second query. */
			bool have_device = debug_tcp.empty() ? device_count > 0 : true;
			set_status(s, have_device ? link_state::waiting : link_state::no_device);
			s->connect_failures++;
			obs_log(s->connect_failures >= 5 ? LOG_WARNING : LOG_INFO,
				"[iphone-cam] connect attempt %d failed — retrying in %d ms",
				s->connect_failures, backoff_ms);
			for (int slept = 0; slept < backoff_ms && s->running.load(); slept += 100)
				std::this_thread::sleep_for(std::chrono::milliseconds(100));
			backoff_ms = backoff_ms >= 5000 ? 5000 : backoff_ms + 1000;
			continue;
		}

		int one = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
		/* Bounds a blocking send(): without it a wedged peer would pin the
		 * worker inside send_all() where no flag can reach it. */
		struct timeval sndto = {0, 200 * 1000};
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sndto, sizeof(sndto));
		s->fd = fd;
		backoff_ms = 1000;
		s->connect_failures = 0;

		run_session(s, parse_buf);
		close_connection(s);

		if (s->peer_closed) {
			s->peer_closed = false;
			for (int slept = 0; slept < 250 && s->running.load(); slept += 50)
				std::this_thread::sleep_for(std::chrono::milliseconds(50));
		}

		if (s->fatal && s->running.load()) {
			for (int slept = 0; slept < 5000 && s->running.load(); slept += 100)
				std::this_thread::sleep_for(std::chrono::milliseconds(100));
		}
	}
	close_connection(s);
	obs_log(LOG_INFO, "[iphone-cam] receiver thread stopped");
}

/* --- obs_source_info callbacks ---------------------------------------- */

void read_settings(iphone_source *s, obs_data_t *settings)
{
	std::lock_guard<std::mutex> lock(s->cfg_mutex);
	const char *serial = obs_data_get_string(settings, S_DEVICE);
	const char *tcp = obs_data_get_string(settings, S_DEBUG_TCP);
	const char *res = obs_data_get_string(settings, S_RESOLUTION);
	s->serial = serial ? serial : "";
	s->debug_tcp = tcp ? tcp : "";
	s->camera_id = (int) obs_data_get_int(settings, S_CAMERA);
	s->fps = (int) obs_data_get_int(settings, S_FPS);
	s->bitrate_kbps = (int) obs_data_get_int(settings, S_BITRATE);
	s->rotation = (int) obs_data_get_int(settings, S_ROTATION);
	s->audio = obs_data_get_bool(settings, S_AUDIO);
	int w = 1920, h = 1080;
	if (res && sscanf(res, "%dx%d", &w, &h) == 2 && w > 0 && h > 0) {
		s->width = w;
		s->height = h;
	}
}

const char *source_get_name(void *)
{
	return obs_module_text("iPhoneUsbCamera");
}

void source_get_defaults(obs_data_t *settings)
{
	obs_data_set_default_string(settings, S_DEVICE, "");
	obs_data_set_default_int(settings, S_CAMERA, 0);
	obs_data_set_default_string(settings, S_RESOLUTION, "1920x1080");
	obs_data_set_default_int(settings, S_FPS, 30);
	obs_data_set_default_int(settings, S_BITRATE, 12000);
	obs_data_set_default_string(settings, S_DEBUG_TCP, "");
	obs_data_set_default_int(settings, S_ROTATION, 0);
	obs_data_set_default_bool(settings, S_AUDIO, true);
}

void *source_create(obs_data_t *settings, obs_source_t *source)
{
	auto *s = new iphone_source();
	s->source = source;
	video_format_get_parameters_for_format(VIDEO_CS_709, VIDEO_RANGE_PARTIAL, VIDEO_FORMAT_NV12, s->color_matrix,
					       s->color_min, s->color_max);
	read_settings(s, settings);
	obs_source_set_async_rotation(source, (long) obs_data_get_int(settings, S_ROTATION));

	int wake[2] = {-1, -1};
	if (pipe(wake) == 0) {
		for (int i = 0; i < 2; i++) {
			fcntl(wake[i], F_SETFD, FD_CLOEXEC);
			fcntl(wake[i], F_SETFL, fcntl(wake[i], F_GETFL, 0) | O_NONBLOCK);
		}
		s->wake_r = wake[0];
		s->wake_w = wake[1];
	} else {
		/* Degraded but correct: the worker still notices the flags within the
		 * 200 ms poll timeout. */
		obs_log(LOG_WARNING, "[iphone-cam] pipe() failed: %d — falling back to poll timeout", errno);
	}

	s->running.store(true);
	s->worker = std::thread(worker_main, s);
	obs_log(LOG_INFO, "[iphone-cam] source created");
	return s;
}

void source_destroy(void *data)
{
	auto *s = static_cast<iphone_source *>(data);
	s->running.store(false);
	if (s->worker.joinable()) {
		/* Never touch s->fd from here: the worker may already have closed it
		 * and the number may belong to somebody else. Poke the self-pipe
		 * instead — the worker returns from poll() immediately. */
		wake_worker(s);
		s->worker.join();
	}
	if (s->wake_w >= 0) {
		close(s->wake_w);
		s->wake_w = -1;
	}
	if (s->wake_r >= 0) {
		close(s->wake_r);
		s->wake_r = -1;
	}
	obs_log(LOG_INFO, "[iphone-cam] source destroyed");
	delete s;
}

void source_update(void *data, obs_data_t *settings)
{
	auto *s = static_cast<iphone_source *>(data);
	read_settings(s, settings);
	obs_source_set_async_rotation(s->source, (long) obs_data_get_int(settings, S_ROTATION));
	s->restart.store(true);
	wake_worker(s); /* see source_destroy: s->fd is the worker's, not ours */
	obs_log(LOG_INFO, "[iphone-cam] settings updated — reconnecting");
}

void source_activate(void *)
{
	obs_log(LOG_DEBUG, "[iphone-cam] source activated");
}

void source_deactivate(void *)
{
	obs_log(LOG_DEBUG, "[iphone-cam] source deactivated");
}

obs_properties_t *source_get_properties(void *data)
{
	auto *s = static_cast<iphone_source *>(data);
	obs_properties_t *props = obs_properties_create();

	/* Read-only first line. It answers the only question a first-time user has
	 * when the picture stays black: is it the cable, the app, or the settings?
	 * Refreshed when the dialog is opened, which is when it is read. */
	char status[512];
	{
		link_state st = link_state::no_device;
		std::string serial;
		int w = 0, h = 0, f = 0;
		double measured = 0.0;
		int audio_rate = 0;
		bool audio_muted = false;
		bool audio_denied = false;
		if (s) {
			std::lock_guard<std::mutex> lock(s->cfg_mutex);
			st = s->status_state;
			serial = s->status_serial;
			w = s->status_width;
			h = s->status_height;
			f = s->status_fps;
			measured = s->status_measured_fps;
			audio_rate = s->status_audio_rate;
			audio_muted = s->status_audio_muted;
			audio_denied = s->status_audio_denied;
		}
		switch (st) {
		case link_state::streaming:
/* The format string comes from the locale file, so the compiler cannot check
 * it. The argument list is fixed here and the .ini is shipped with the plugin. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
#pragma clang diagnostic ignored "-Wformat-security"
			snprintf(status, sizeof(status), obs_module_text("Status.Connected"),
				 serial.empty() ? "?" : serial.c_str(), (unsigned) w, (unsigned) h, (unsigned) f,
				 measured);
			/* Audio is optional, so it is appended rather than folded into
			 * the connected line: a stream without it keeps its old text. */
			if (audio_rate > 0) {
				size_t used = strlen(status);
				snprintf(status + used, sizeof(status) - used,
					 obs_module_text(audio_muted ? "Status.AudioMuted" : "Status.Audio"),
					 (unsigned) ((audio_rate + 500) / 1000));
			}
#pragma clang diagnostic pop
			break;
		case link_state::starting:
			snprintf(status, sizeof(status), "%s", obs_module_text("Status.Starting"));
			break;
		case link_state::waiting:
			snprintf(status, sizeof(status), "%s", obs_module_text("Status.Waiting"));
			break;
		case link_state::incompatible:
			snprintf(status, sizeof(status), "%s", obs_module_text("Status.Incompatible"));
			break;
		case link_state::busy:
			snprintf(status, sizeof(status), "%s", obs_module_text("Status.Busy"));
			break;
		default:
			snprintf(status, sizeof(status), "%s", obs_module_text("Status.NoDevice"));
			break;
		}
		/* ERROR 6 leaves the video running, so this is appended to whatever the
		 * link state says instead of replacing it. Fixed English until a
		 * Status.AudioDenied key exists in the locale files. */
		if (audio_denied) {
			size_t used = strlen(status);
			snprintf(status + used, sizeof(status) - used, "%s", obs_module_text("Status.AudioDenied"));
		}
	}
	obs_property_t *status_prop =
		obs_properties_add_text(props, "status_line", obs_module_text("Status"), OBS_TEXT_INFO);
	obs_property_set_description(status_prop, status);

	obs_property_t *devices = obs_properties_add_list(props, S_DEVICE, obs_module_text("Device"),
							  OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
	obs_property_list_add_string(devices, obs_module_text("Device.Auto"), "");
	struct usbmux_device list[16];
	size_t count = 0;
	int rc = usbmux_list_devices(list, 16, &count);
	if (rc == USBMUX_OK) {
		for (size_t i = 0; i < count; i++)
			obs_property_list_add_string(devices, list[i].serial, list[i].serial);
	} else {
		obs_log(LOG_INFO, "[iphone-cam] device list unavailable: %s", usbmux_strerror(rc));
	}

	obs_property_t *cams = obs_properties_add_list(props, S_CAMERA, obs_module_text("Camera"), OBS_COMBO_TYPE_LIST,
						       OBS_COMBO_FORMAT_INT);
	bool have_cached = false;
	if (s) {
		std::lock_guard<std::mutex> lock(s->cfg_mutex);
		for (const auto &c : s->cameras) {
			obs_property_list_add_int(cams, c.name.c_str(), c.id);
			have_cached = true;
		}
	}
	if (!have_cached) {
		obs_property_list_add_int(cams, obs_module_text("Camera.BackWide"), 0);
		obs_property_list_add_int(cams, obs_module_text("Camera.BackUltraWide"), 1);
		obs_property_list_add_int(cams, obs_module_text("Camera.BackTele"), 2);
		obs_property_list_add_int(cams, obs_module_text("Camera.Front"), 3);
	}

	obs_property_t *res = obs_properties_add_list(props, S_RESOLUTION, obs_module_text("Resolution"),
						      OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
	obs_property_list_add_string(res, "1280x720", "1280x720");
	obs_property_list_add_string(res, "1920x1080", "1920x1080");

	obs_property_t *fps = obs_properties_add_list(props, S_FPS, obs_module_text("FPS"), OBS_COMBO_TYPE_LIST,
						      OBS_COMBO_FORMAT_INT);
	obs_property_list_add_int(fps, "30", 30);
	obs_property_list_add_int(fps, "60", 60);

	obs_properties_add_int(props, S_BITRATE, obs_module_text("Bitrate"), 1000, 50000, 500);

	/* Decides whether START carries the audio bit (PROTOCOL.md 4.2). Changing
	 * it goes through source_update() like a resolution change: the worker
	 * restarts the connection and the next START states the new wish. */
	obs_properties_add_bool(props, S_AUDIO, obs_module_text("Audio"));

	/* Manual override. The app rotates to horizon level on its own, so 0 is the
	 * right answer in the normal case; this exists for mounts the phone cannot
	 * sense (mirror rigs, phone lying flat). */
	obs_property_t *rot = obs_properties_add_list(props, S_ROTATION, obs_module_text("Rotation"),
						      OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
	obs_property_list_add_int(rot, "0", 0);
	obs_property_list_add_int(rot, "90", 90);
	obs_property_list_add_int(rot, "180", 180);
	obs_property_list_add_int(rot, "270", 270);

	obs_property_t *tcp = obs_properties_add_text(props, S_DEBUG_TCP, obs_module_text("DebugTcp"), OBS_TEXT_DEFAULT);
	obs_property_set_long_description(tcp, obs_module_text("DebugTcp.Description"));

	/* No clickable link without Qt, so the URL is plain text the user can copy. */
	obs_properties_add_text(props, "help_line", obs_module_text("Help"), OBS_TEXT_INFO);

	return props;
}

} /* namespace */

static struct obs_source_info make_source_info(void)
{
	struct obs_source_info si = {};
	si.id = "iphone_usb_camera";
	si.type = OBS_SOURCE_TYPE_INPUT;
	si.output_flags = OBS_SOURCE_ASYNC_VIDEO | OBS_SOURCE_AUDIO;
	si.get_name = source_get_name;
	si.create = source_create;
	si.destroy = source_destroy;
	si.get_defaults = source_get_defaults;
	si.get_properties = source_get_properties;
	si.update = source_update;
	si.activate = source_activate;
	si.deactivate = source_deactivate;
	si.icon_type = OBS_ICON_TYPE_CAMERA;
	return si;
}

extern "C" struct obs_source_info iucm_iphone_source_info = make_source_info();
