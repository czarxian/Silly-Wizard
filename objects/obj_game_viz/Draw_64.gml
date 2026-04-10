/// @description Draw GUI overlay hooks

// Draw notebeam in GUI-space composition order:
// chanter graphics (world/UI layer) < notebeam < now-line/labels/popup.
var _nb_anchor = gv_find_anchor_id_by_name("notebeam_canvas_anchor");
var _x1 = 0, _y1 = 0, _x2 = 0, _y2 = 0;
if (_nb_anchor != noone && instance_exists(_nb_anchor)) {
	_x1 = _nb_anchor.bbox_left;
	_y1 = _nb_anchor.bbox_top;
	_x2 = _nb_anchor.bbox_right;
	_y2 = _nb_anchor.bbox_bottom;
	var _w = max(1, _x2 - _x1 + 1);
	var _h = max(1, _y2 - _y1 + 1);

	var _use_visual_cache = variable_global_exists("GV_VISUAL_CACHE_ENABLED")
		&& global.GV_VISUAL_CACHE_ENABLED;
	var _cache_refresh_ms = variable_global_exists("GV_VISUAL_CACHE_REFRESH_MS")
		? max(1, real(global.GV_VISUAL_CACHE_REFRESH_MS)) : 16;

	if (_use_visual_cache) {
		var _key = "notebeam_" + string(_nb_anchor);
		var _cache = gv_anchor_cache_get_or_create(_key, _w, _h);
		var _cache_last_ms = real(variable_struct_get(_cache, "last_ms"));
		var _cache_surf = variable_struct_get(_cache, "surf");
		var _now_ms = timing_get_engine_now_ms();
		if ((_now_ms - _cache_last_ms) >= _cache_refresh_ms) {
			global.GV_ANCHOR_RECT_X_OFFSET = -_x1;
			global.GV_ANCHOR_RECT_Y_OFFSET = -_y1;
			surface_set_target(_cache_surf);
			draw_clear_alpha(c_black, 0);
			gv_draw_notebeam_canvas_core(0, 0, _w - 1, _h - 1);
			surface_reset_target();
			global.GV_ANCHOR_RECT_X_OFFSET = 0;
			global.GV_ANCHOR_RECT_Y_OFFSET = 0;
			variable_struct_set(_cache, "last_ms", _now_ms);
			// Record the playhead at render time for scroll compensation
			var _rph = (variable_global_exists("timeline_state") && is_struct(global.timeline_state))
				? real(global.timeline_state.playhead_ms ?? 0) : 0;
			variable_struct_set(_cache, "render_playhead_ms", _rph);
		}
		// Scroll compensation: shift blit left by how far the playhead has advanced
		// since the surface was rendered, so notes appear to move smoothly every frame
		// rather than jumping each time the surface refreshes.
		var _offset_px = 0;
		var _rph = variable_struct_exists(_cache, "render_playhead_ms")
			? real(variable_struct_get(_cache, "render_playhead_ms")) : -1;
		if (_rph >= 0
			&& variable_global_exists("timeline_state") && is_struct(global.timeline_state)
			&& variable_struct_exists(global.timeline_state, "playhead_ms")
			&& variable_struct_exists(global.timeline_state, "ms_ahead")
			&& variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
			var _cur_ph    = real(global.timeline_state.playhead_ms ?? 0);
			var _ms_ahead  = max(1, real(global.timeline_state.ms_ahead));
			var _now_ratio = variable_struct_exists(global.timeline_cfg, "notebeam_now_ratio")
				? real(global.timeline_cfg.notebeam_now_ratio)
				: (variable_struct_exists(global.timeline_cfg, "now_ratio") ? real(global.timeline_cfg.now_ratio) : 0.33);
			_now_ratio = clamp(_now_ratio, 0.05, 0.95);
			var _right_w   = max(1, _w * (1.0 - _now_ratio));
			var _delta_ms  = max(0, _cur_ph - _rph);
			_offset_px     = clamp(floor(_delta_ms * _right_w / _ms_ahead), 0, _w - 1);
		}
		if (_offset_px > 0) {
			// Show the surface shifted left: skip the first _offset_px columns and
			// place the remainder at _x1. Fill the exposed right gap with black.
			draw_surface_part(_cache_surf, _offset_px, 0, _w - _offset_px, _h, _x1, _y1);
			draw_set_color(c_black);
			draw_set_alpha(0.9);
			draw_rectangle(_x1 + (_w - _offset_px), _y1, _x2, _y2, false);
			draw_set_alpha(1);
		} else {
			draw_surface(_cache_surf, _x1, _y1);
		}
		gv_anchor_cache_store(_key, _cache);
	} else {
		gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2);
	}
}

gv_draw_notebeam_nowline_overlay_gui();
gv_draw_notebeam_lane_labels_overlay_gui();

// Draw note popup in GUI so it appears above notebeam world-space layers.
if (_nb_anchor != noone && instance_exists(_nb_anchor)) {
	gv_draw_notebeam_scoring_panel(_x1, _y1, _x2, _y2);
	gv_draw_notebeam_note_popup(_x1, _y1, _x2, _y2);
}
