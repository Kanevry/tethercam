/*
obs-iphone-usb-cam — AAC decoder (AudioToolbox)
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
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Decoder for the AUDIO stream (PROTOCOL.md 4.9/4.10): one raw AAC-LC access
 * unit in, Float32 interleaved PCM out. The AudioSpecificConfig from
 * AUDIO_CONFIG is handed to the converter unchanged as its magic cookie. */
typedef struct iucm_aac_decoder iucm_aac_decoder_t;

/* Returns NULL when the parameters or the magic cookie are unusable. asc is
 * copied; the caller keeps ownership of its buffer. */
iucm_aac_decoder_t *iucm_aac_decoder_create(uint32_t sample_rate, uint8_t channels, const uint8_t *asc,
					    uint16_t asc_len);

void iucm_aac_decoder_destroy(iucm_aac_decoder_t *dec);

/* Decodes exactly one AAC access unit (no ADTS header, no length prefix).
 * On success *out_pcm points at Float32 interleaved samples owned by the
 * decoder — valid until the next decode() or destroy() — and *out_frames holds
 * the sample count per channel (1024 for AAC-LC).
 * Returns false on a decode error; the converter is then torn down and this
 * decoder stays failed, so the caller drops it and rebuilds on the next
 * AUDIO_CONFIG (same contract as the HEVC decoder's session rebuild). */
bool iucm_aac_decoder_decode(iucm_aac_decoder_t *dec, const uint8_t *frame, uint32_t len, const float **out_pcm,
			     uint32_t *out_frames);

/* True once a decode error tore the converter down. */
bool iucm_aac_decoder_failed(const iucm_aac_decoder_t *dec);

uint32_t iucm_aac_decoder_sample_rate(const iucm_aac_decoder_t *dec);
uint8_t iucm_aac_decoder_channels(const iucm_aac_decoder_t *dec);

/* Number of access units handed back as PCM so far. */
uint64_t iucm_aac_decoder_frames(const iucm_aac_decoder_t *dec);

#ifdef __cplusplus
}
#endif
