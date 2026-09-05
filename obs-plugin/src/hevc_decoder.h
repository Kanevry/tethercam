/*
obs-iphone-usb-cam — HEVC decoder (VideoToolbox)
Copyright (C) 2026 Bernhard Goetzendorfer <venturestudio@ai-at.eu>

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
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <CoreVideo/CoreVideo.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Decoder built from an hvcC record (PROTOCOL.md 4.5). Output is NV12
 * video-range (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange). */
typedef struct iucm_decoder iucm_decoder_t;

/* Called once per decoded frame, on the VideoToolbox output callback thread.
 * The pixel buffer is only valid for the duration of the call. */
typedef void (*iucm_decoder_frame_cb)(void *ctx, CVPixelBufferRef pixel_buffer, uint64_t pts_us);

/* Returns NULL when the hvcC record or the session cannot be built. */
iucm_decoder_t *iucm_decoder_create(const uint8_t *hvcc, uint32_t hvcc_len, uint16_t width, uint16_t height,
				    iucm_decoder_frame_cb cb, void *cb_ctx);

void iucm_decoder_destroy(iucm_decoder_t *dec);

/* Feeds one VIDEO payload body (everything after the 8-byte pts field): a run of
 * 4-byte big-endian length-prefixed VCL NALs, handed to VideoToolbox unchanged.
 * Returns true when the frame was submitted, false on a decode error.
 * After 3 consecutive errors the session is rebuilt and non-keyframes are
 * dropped until the next keyframe arrives. */
bool iucm_decoder_decode(iucm_decoder_t *dec, const uint8_t *nalus, uint32_t nalus_len, uint64_t pts_us,
			 bool keyframe);

/* Number of frames handed to the callback so far. */
uint64_t iucm_decoder_frames(const iucm_decoder_t *dec);

#ifdef __cplusplus
}
#endif
