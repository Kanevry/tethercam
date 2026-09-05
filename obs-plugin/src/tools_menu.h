/*
obs-iphone-usb-cam — Tools menu entry and first-run hint (obs-frontend-api).
Copyright (C) 2026 Bernhard Goetzendorfer <venturestudio@ai-at.eu>
SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Registers the Tools menu item and the frontend event callback. Called from
 * obs_module_post_load(), because the frontend is not up during
 * obs_module_load(). No-op build when ENABLE_FRONTEND_API is OFF. */
void iucm_tools_menu_init(void);
void iucm_tools_menu_shutdown(void);

#ifdef __cplusplus
}
#endif
