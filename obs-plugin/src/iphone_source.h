/*
obs-iphone-usb-cam — OBS source registration
Copyright (C) 2026 Bernhard Goetzendorfer <venturestudio@ai-at.eu>
SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <obs-module.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Registered by obs_module_load(). Source id: "iphone_usb_camera". */
extern struct obs_source_info iucm_iphone_source_info;

#ifdef __cplusplus
}
#endif
