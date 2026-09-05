/*
obs-iphone-usb-cam — Tools menu entry and first-run hint.
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

#include "tools_menu.h"

#include <obs-module.h>
#include <obs-frontend-api.h>
#include <plugin-support.h>
#include <util/platform.h>

#include <string.h>

#define IUCM_SOURCE_ID "iphone_usb_camera"
/* Not localised on purpose: this is the scene item name the user sees in the
 * source list and later refers to in guides and screenshots. */
#define IUCM_DEFAULT_SOURCE_NAME "TetherCam iPhone"
#define IUCM_HINT_FILE "first-run.json"

/* --- helpers ---------------------------------------------------------- */

static bool scene_item_is_tethercam(obs_scene_t *scene, obs_sceneitem_t *item, void *param)
{
	UNUSED_PARAMETER(scene);
	bool *found = param;

	obs_source_t *src = obs_sceneitem_get_source(item);
	if (src) {
		const char *id = obs_source_get_id(src);
		if (id && strcmp(id, IUCM_SOURCE_ID) == 0) {
			*found = true;
			return false; /* stop the walk */
		}
	}
	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, scene_item_is_tethercam, param);

	return !*found;
}

static bool scene_has_tethercam(obs_scene_t *scene)
{
	bool found = false;
	if (scene)
		obs_scene_enum_items(scene, scene_item_is_tethercam, &found);
	return found;
}

static bool collection_has_tethercam(void)
{
	struct obs_frontend_source_list scenes = {0};
	bool found = false;

	obs_frontend_get_scenes(&scenes);
	for (size_t i = 0; i < scenes.sources.num && !found; i++)
		found = scene_has_tethercam(obs_scene_from_source(scenes.sources.array[i]));
	obs_frontend_source_list_free(&scenes);

	return found;
}

/* --- Tools menu item -------------------------------------------------- */

static void add_source_to_current_scene(void *private_data)
{
	UNUSED_PARAMETER(private_data);

	obs_source_t *scene_source = obs_frontend_get_current_scene();
	if (!scene_source) {
		obs_log(LOG_WARNING, "[iphone-cam] no current scene — nothing to add to");
		return;
	}

	obs_scene_t *scene = obs_scene_from_source(scene_source);
	if (!scene) {
		/* The frontend may have a group or a transition selected. */
		obs_log(LOG_WARNING, "[iphone-cam] current selection is not a scene — select a scene first");
		obs_source_release(scene_source);
		return;
	}

	if (scene_has_tethercam(scene)) {
		obs_log(LOG_INFO, "[iphone-cam] scene '%s' already has a TetherCam source — nothing added",
			obs_source_get_name(scene_source));
		obs_source_release(scene_source);
		return;
	}

	obs_source_t *src = obs_source_create(IUCM_SOURCE_ID, IUCM_DEFAULT_SOURCE_NAME, NULL, NULL);
	if (!src) {
		obs_log(LOG_WARNING, "[iphone-cam] obs_source_create(%s) failed", IUCM_SOURCE_ID);
		obs_source_release(scene_source);
		return;
	}

	/* obs_scene_add hands back a borrowed reference — the scene owns it. */
	obs_sceneitem_t *item = obs_scene_add(scene, src);
	if (item) {
		struct obs_video_info ovi;
		if (obs_get_video_info(&ovi)) {
			/* SCALE_INNER keeps the aspect ratio and fits the canvas, so the
			 * first frame is framed correctly without the user touching the
			 * transform box. */
			struct vec2 bounds;
			vec2_set(&bounds, (float) ovi.base_width, (float) ovi.base_height);
			obs_sceneitem_set_bounds_type(item, OBS_BOUNDS_SCALE_INNER);
			obs_sceneitem_set_bounds_alignment(item, OBS_ALIGN_CENTER);
			obs_sceneitem_set_bounds(item, &bounds);
			obs_log(LOG_INFO, "[iphone-cam] added '%s' to scene '%s', fitted to %ux%u",
				IUCM_DEFAULT_SOURCE_NAME, obs_source_get_name(scene_source),
				(unsigned) ovi.base_width, (unsigned) ovi.base_height);
		} else {
			obs_log(LOG_INFO, "[iphone-cam] added '%s' to scene '%s' (canvas size unknown)",
				IUCM_DEFAULT_SOURCE_NAME, obs_source_get_name(scene_source));
		}
	} else {
		obs_log(LOG_WARNING, "[iphone-cam] obs_scene_add failed");
	}

	obs_source_release(src);
	obs_source_release(scene_source);
}

/* --- first-run hint --------------------------------------------------- */

/* One flag per scene collection. A user who keeps a streaming collection and a
 * scratch collection should be told once per collection, not once per install. */
static void hint_if_no_source(void)
{
	if (collection_has_tethercam())
		return;

	char *collection = obs_frontend_get_current_scene_collection();
	const char *key = (collection && *collection) ? collection : "default";
	char *path = obs_module_config_path(IUCM_HINT_FILE);

	obs_data_t *cfg = path ? obs_data_create_from_json_file(path) : NULL;
	if (!cfg)
		cfg = obs_data_create();

	if (!obs_data_get_bool(cfg, key)) {
		obs_log(LOG_INFO,
			"[iphone-cam] no TetherCam source in scene collection '%s'. Use Tools -> \"%s\", then open TetherCam on the iPhone. Guide: https://github.com/Kanevry/tethercam#quick-start",
			key, obs_module_text("ToolsMenu.AddSource"));
		obs_data_set_bool(cfg, key, true);
		if (path) {
			char *dir = obs_module_config_path("");
			if (dir) {
				os_mkdirs(dir);
				bfree(dir);
			}
			/* Best effort: a failed write only means the hint repeats. */
			obs_data_save_json_safe(cfg, path, "tmp", "bak");
		}
	}

	obs_data_release(cfg);
	bfree(path);
	bfree(collection);
}

static void frontend_event(enum obs_frontend_event event, void *private_data)
{
	UNUSED_PARAMETER(private_data);
	if (event == OBS_FRONTEND_EVENT_FINISHED_LOADING)
		hint_if_no_source();
}

/* --- lifecycle -------------------------------------------------------- */

void iucm_tools_menu_init(void)
{
	obs_frontend_add_tools_menu_item(obs_module_text("ToolsMenu.AddSource"), add_source_to_current_scene, NULL);
	obs_frontend_add_event_callback(frontend_event, NULL);
	obs_log(LOG_INFO, "[iphone-cam] tools menu item registered: \"%s\"", obs_module_text("ToolsMenu.AddSource"));
}

void iucm_tools_menu_shutdown(void)
{
	obs_frontend_remove_event_callback(frontend_event, NULL);
}
