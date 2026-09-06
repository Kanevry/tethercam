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

#include "aac_decoder.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <obs-module.h>
#include <plugin-support.h>

#include <vector>

/* AAC-LC delivers 1024 frames per access unit; the headroom covers an SBR
 * variant that would hand back 2048 without overrunning the buffer. */
#define IUCM_AAC_MAX_FRAMES 4096
#define IUCM_AAC_MAX_CHANNELS 2

struct iucm_aac_decoder {
	AudioConverterRef converter = nullptr;
	AudioStreamBasicDescription in_asbd = {};
	AudioStreamBasicDescription out_asbd = {};
	std::vector<uint8_t> asc;
	std::vector<float> pcm;
	uint32_t sample_rate = 0;
	uint8_t channels = 0;
	bool failed = false;
	uint64_t frames = 0;
};

/* One access unit per call. The converter asks for input until it has enough
 * for the requested output; the second ask returns 0 packets, which ends the
 * conversion cleanly instead of looking like an error. */
struct iucm_aac_input {
	const uint8_t *data;
	uint32_t len;
	bool consumed;
	AudioStreamPacketDescription desc;
};

static OSStatus iucm_aac_input_proc(AudioConverterRef /*converter*/, UInt32 *io_packets, AudioBufferList *io_data,
				    AudioStreamPacketDescription **out_desc, void *user_data)
{
	auto *in = static_cast<iucm_aac_input *>(user_data);
	if (in->consumed) {
		*io_packets = 0;
		if (out_desc)
			*out_desc = nullptr;
		return noErr;
	}

	in->consumed = true;
	in->desc.mStartOffset = 0;
	in->desc.mVariableFramesInPacket = 0;
	in->desc.mDataByteSize = in->len;

	io_data->mNumberBuffers = 1;
	io_data->mBuffers[0].mNumberChannels = 0; /* compressed: not meaningful */
	io_data->mBuffers[0].mDataByteSize = in->len;
	io_data->mBuffers[0].mData = const_cast<uint8_t *>(in->data);

	*io_packets = 1;
	if (out_desc)
		*out_desc = &in->desc;
	return noErr;
}

/* Tears the converter down but keeps the object: the caller reads
 * iucm_aac_decoder_failed() and rebuilds on the next AUDIO_CONFIG. */
static void iucm_aac_decoder_close(iucm_aac_decoder_t *dec)
{
	if (dec->converter) {
		AudioConverterDispose(dec->converter);
		dec->converter = nullptr;
	}
}

iucm_aac_decoder_t *iucm_aac_decoder_create(uint32_t sample_rate, uint8_t channels, const uint8_t *asc,
					    uint16_t asc_len)
{
	if (sample_rate == 0 || channels == 0 || channels > IUCM_AAC_MAX_CHANNELS) {
		obs_log(LOG_WARNING, "[iphone-cam] audio config unusable: %u Hz, %u channels", (unsigned) sample_rate,
			(unsigned) channels);
		return nullptr;
	}
	/* PROTOCOL.md 4.9: asc_len = 0 is valid on the wire but unusable for
	 * AAC-LC — no cookie, no audio path. */
	if (!asc || asc_len == 0) {
		obs_log(LOG_WARNING, "[iphone-cam] AUDIO_CONFIG without AudioSpecificConfig — audio stays off");
		return nullptr;
	}

	auto *dec = new iucm_aac_decoder();
	dec->sample_rate = sample_rate;
	dec->channels = channels;
	dec->asc.assign(asc, asc + asc_len);

	dec->in_asbd.mSampleRate = (Float64) sample_rate;
	dec->in_asbd.mFormatID = kAudioFormatMPEG4AAC;
	dec->in_asbd.mChannelsPerFrame = channels;
	dec->in_asbd.mFramesPerPacket = 1024;

	dec->out_asbd.mSampleRate = (Float64) sample_rate;
	dec->out_asbd.mFormatID = kAudioFormatLinearPCM;
	dec->out_asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
	dec->out_asbd.mChannelsPerFrame = channels;
	dec->out_asbd.mFramesPerPacket = 1;
	dec->out_asbd.mBitsPerChannel = 32;
	dec->out_asbd.mBytesPerFrame = 4 * channels;
	dec->out_asbd.mBytesPerPacket = dec->out_asbd.mBytesPerFrame;

	OSStatus st = AudioConverterNew(&dec->in_asbd, &dec->out_asbd, &dec->converter);
	if (st != noErr || !dec->converter) {
		obs_log(LOG_WARNING, "[iphone-cam] AudioConverterNew failed: %d", (int) st);
		delete dec;
		return nullptr;
	}

	st = AudioConverterSetProperty(dec->converter, kAudioConverterDecompressionMagicCookie,
				       (UInt32) dec->asc.size(), dec->asc.data());
	if (st != noErr) {
		obs_log(LOG_WARNING, "[iphone-cam] AAC magic cookie rejected: %d (%u bytes)", (int) st,
			(unsigned) dec->asc.size());
		iucm_aac_decoder_close(dec);
		delete dec;
		return nullptr;
	}

	dec->pcm.resize((size_t) IUCM_AAC_MAX_FRAMES * channels);
	obs_log(LOG_INFO, "[iphone-cam] audio decoder ready: AAC-LC %u Hz, %u ch, ASC %u bytes",
		(unsigned) sample_rate, (unsigned) channels, (unsigned) asc_len);
	return dec;
}

void iucm_aac_decoder_destroy(iucm_aac_decoder_t *dec)
{
	if (!dec)
		return;
	iucm_aac_decoder_close(dec);
	delete dec;
}

bool iucm_aac_decoder_failed(const iucm_aac_decoder_t *dec)
{
	return dec ? dec->failed : true;
}

uint32_t iucm_aac_decoder_sample_rate(const iucm_aac_decoder_t *dec)
{
	return dec ? dec->sample_rate : 0;
}

uint8_t iucm_aac_decoder_channels(const iucm_aac_decoder_t *dec)
{
	return dec ? dec->channels : 0;
}

uint64_t iucm_aac_decoder_frames(const iucm_aac_decoder_t *dec)
{
	return dec ? dec->frames : 0;
}

bool iucm_aac_decoder_decode(iucm_aac_decoder_t *dec, const uint8_t *frame, uint32_t len, const float **out_pcm,
			     uint32_t *out_frames)
{
	if (!dec || !frame || len == 0 || !out_pcm || !out_frames)
		return false;
	*out_pcm = nullptr;
	*out_frames = 0;
	if (!dec->converter || dec->failed)
		return false;

	iucm_aac_input input = {};
	input.data = frame;
	input.len = len;

	AudioBufferList out_list = {};
	out_list.mNumberBuffers = 1;
	out_list.mBuffers[0].mNumberChannels = dec->channels;
	out_list.mBuffers[0].mDataByteSize = (UInt32) (dec->pcm.size() * sizeof(float));
	out_list.mBuffers[0].mData = dec->pcm.data();

	/* PCM output: one packet is one frame, so the packet count is the frame
	 * count both on the way in and on the way back. */
	UInt32 packets = IUCM_AAC_MAX_FRAMES;
	OSStatus st = AudioConverterFillComplexBuffer(dec->converter, iucm_aac_input_proc, &input, &packets, &out_list,
						      nullptr);
	if (st != noErr) {
		obs_log(LOG_WARNING, "[iphone-cam] AAC decode error %d — dropping the audio decoder", (int) st);
		iucm_aac_decoder_close(dec);
		dec->failed = true;
		return false;
	}
	if (packets == 0)
		return false; /* converter needed more input than one access unit */

	dec->frames++;
	*out_pcm = dec->pcm.data();
	*out_frames = (uint32_t) packets;
	return true;
}
