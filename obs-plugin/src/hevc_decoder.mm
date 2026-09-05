/*
obs-iphone-usb-cam — HEVC decoder (VideoToolbox)
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

#include "hevc_decoder.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VideoToolbox.h>

#include <obs-module.h>
#include <plugin-support.h>

#include <vector>

#define IUCM_MAX_DECODE_ERRORS 3

struct iucm_decoder {
	CMVideoFormatDescriptionRef format = nullptr;
	VTDecompressionSessionRef session = nullptr;
	std::vector<uint8_t> hvcc;
	uint16_t width = 0;
	uint16_t height = 0;
	iucm_decoder_frame_cb cb = nullptr;
	void *cb_ctx = nullptr;
	int consecutive_errors = 0;
	bool need_keyframe = true;
	uint64_t frames = 0;
};

static void iucm_decoder_output(void *decompressionOutputRefCon, void * /*sourceFrameRefCon*/, OSStatus status,
				VTDecodeInfoFlags /*infoFlags*/, CVImageBufferRef imageBuffer, CMTime pts,
				CMTime /*duration*/)
{
	auto *dec = static_cast<iucm_decoder *>(decompressionOutputRefCon);
	if (status != noErr || imageBuffer == nullptr)
		return;

	uint64_t pts_us = 0;
	if (CMTIME_IS_VALID(pts)) {
		CMTime us = CMTimeConvertScale(pts, 1000000, kCMTimeRoundingMethod_Default);
		if (us.value > 0)
			pts_us = (uint64_t) us.value;
	}

	dec->frames++;
	if (dec->cb)
		dec->cb(dec->cb_ctx, imageBuffer, pts_us);
}

/* Builds the CMVideoFormatDescription from the hvcC record (PROTOCOL.md 4.5). */
static CMVideoFormatDescriptionRef iucm_format_from_hvcc(const uint8_t *hvcc, uint32_t hvcc_len, uint16_t width,
							 uint16_t height)
{
	CFDataRef hvcc_data = CFDataCreate(kCFAllocatorDefault, hvcc, (CFIndex) hvcc_len);
	if (!hvcc_data)
		return nullptr;

	const void *atom_keys[] = {CFSTR("hvcC")};
	const void *atom_values[] = {hvcc_data};
	CFDictionaryRef atoms = CFDictionaryCreate(kCFAllocatorDefault, atom_keys, atom_values, 1,
						   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(hvcc_data);
	if (!atoms)
		return nullptr;

	const void *ext_keys[] = {kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
	const void *ext_values[] = {atoms};
	CFDictionaryRef extensions = CFDictionaryCreate(kCFAllocatorDefault, ext_keys, ext_values, 1,
							&kCFTypeDictionaryKeyCallBacks,
							&kCFTypeDictionaryValueCallBacks);
	CFRelease(atoms);
	if (!extensions)
		return nullptr;

	CMVideoFormatDescriptionRef fmt = nullptr;
	OSStatus st = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_HEVC, width, height,
						     extensions, &fmt);
	CFRelease(extensions);
	if (st != noErr) {
		obs_log(LOG_WARNING, "[iphone-cam] CMVideoFormatDescriptionCreate failed: %d", (int) st);
		return nullptr;
	}
	return fmt;
}

static bool iucm_decoder_open_session(iucm_decoder_t *dec)
{
	if (dec->session) {
		VTDecompressionSessionWaitForAsynchronousFrames(dec->session);
		VTDecompressionSessionInvalidate(dec->session);
		CFRelease(dec->session);
		dec->session = nullptr;
	}
	if (dec->format) {
		CFRelease(dec->format);
		dec->format = nullptr;
	}

	dec->format = iucm_format_from_hvcc(dec->hvcc.data(), (uint32_t) dec->hvcc.size(), dec->width, dec->height);
	if (!dec->format)
		return false;

	const void *dec_keys[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferOpenGLCompatibilityKey};
	int32_t pixfmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
	CFNumberRef pixfmt_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pixfmt);
	const void *dec_values[] = {pixfmt_num, kCFBooleanFalse};
	CFDictionaryRef attrs = CFDictionaryCreate(kCFAllocatorDefault, dec_keys, dec_values, 2,
						   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(pixfmt_num);

	VTDecompressionOutputCallbackRecord record = {};
	record.decompressionOutputCallback = iucm_decoder_output;
	record.decompressionOutputRefCon = dec;

	OSStatus st = VTDecompressionSessionCreate(kCFAllocatorDefault, dec->format, nullptr, attrs, &record,
						   &dec->session);
	if (attrs)
		CFRelease(attrs);
	if (st != noErr) {
		obs_log(LOG_WARNING, "[iphone-cam] VTDecompressionSessionCreate failed: %d", (int) st);
		CFRelease(dec->format);
		dec->format = nullptr;
		dec->session = nullptr;
		return false;
	}

	dec->consecutive_errors = 0;
	dec->need_keyframe = true;
	return true;
}

iucm_decoder_t *iucm_decoder_create(const uint8_t *hvcc, uint32_t hvcc_len, uint16_t width, uint16_t height,
				    iucm_decoder_frame_cb cb, void *cb_ctx)
{
	if (!hvcc || hvcc_len == 0 || width == 0 || height == 0)
		return nullptr;

	auto *dec = new iucm_decoder();
	dec->hvcc.assign(hvcc, hvcc + hvcc_len);
	dec->width = width;
	dec->height = height;
	dec->cb = cb;
	dec->cb_ctx = cb_ctx;

	if (!iucm_decoder_open_session(dec)) {
		delete dec;
		return nullptr;
	}
	obs_log(LOG_INFO, "[iphone-cam] decoder ready: %ux%u, hvcC %u bytes", (unsigned) width, (unsigned) height,
		(unsigned) hvcc_len);
	return dec;
}

void iucm_decoder_destroy(iucm_decoder_t *dec)
{
	if (!dec)
		return;
	if (dec->session) {
		VTDecompressionSessionWaitForAsynchronousFrames(dec->session);
		VTDecompressionSessionInvalidate(dec->session);
		CFRelease(dec->session);
	}
	if (dec->format)
		CFRelease(dec->format);
	delete dec;
}

uint64_t iucm_decoder_frames(const iucm_decoder_t *dec)
{
	return dec ? dec->frames : 0;
}

bool iucm_decoder_decode(iucm_decoder_t *dec, const uint8_t *nalus, uint32_t nalus_len, uint64_t pts_us,
			 bool keyframe)
{
	if (!dec || !nalus || nalus_len == 0)
		return false;

	if (dec->need_keyframe) {
		if (!keyframe)
			return false;
		dec->need_keyframe = false;
	}
	if (!dec->session && !iucm_decoder_open_session(dec))
		return false;

	CMBlockBufferRef block = nullptr;
	OSStatus st = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, nullptr, nalus_len, kCFAllocatorDefault,
							 nullptr, 0, nalus_len, kCMBlockBufferAssureMemoryNowFlag,
							 &block);
	if (st != noErr || !block)
		return false;
	st = CMBlockBufferReplaceDataBytes(nalus, block, 0, nalus_len);
	if (st != noErr) {
		CFRelease(block);
		return false;
	}

	CMSampleTimingInfo timing = {};
	timing.duration = kCMTimeInvalid;
	timing.presentationTimeStamp = CMTimeMake((int64_t) pts_us, 1000000);
	timing.decodeTimeStamp = kCMTimeInvalid;
	size_t sample_size = nalus_len;

	CMSampleBufferRef sample = nullptr;
	st = CMSampleBufferCreateReady(kCFAllocatorDefault, block, dec->format, 1, 1, &timing, 1, &sample_size,
				       &sample);
	CFRelease(block);
	if (st != noErr || !sample)
		return false;

	VTDecodeInfoFlags info = 0;
	st = VTDecompressionSessionDecodeFrame(dec->session, sample, kVTDecodeFrame_1xRealTimePlayback, nullptr,
					       &info);
	CFRelease(sample);

	if (st != noErr) {
		dec->consecutive_errors++;
		obs_log(LOG_WARNING, "[iphone-cam] decode error %d (%d consecutive)", (int) st,
			dec->consecutive_errors);
		if (dec->consecutive_errors >= IUCM_MAX_DECODE_ERRORS) {
			obs_log(LOG_WARNING, "[iphone-cam] rebuilding decoder after %d errors, waiting for keyframe",
				dec->consecutive_errors);
			iucm_decoder_open_session(dec);
		}
		return false;
	}

	dec->consecutive_errors = 0;
	return true;
}
