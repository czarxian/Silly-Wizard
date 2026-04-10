var ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
	ui_name_value = string(variable_instance_get(id, "ui_name"));
}

var diag_disable_timeline_draw = variable_global_exists("DIAG_DISABLE_TIMELINE_DRAW")
	&& global.DIAG_DISABLE_TIMELINE_DRAW;
var use_visual_cache = variable_global_exists("GV_VISUAL_CACHE_ENABLED")
	&& global.GV_VISUAL_CACHE_ENABLED;
var cache_refresh_ms = variable_global_exists("GV_VISUAL_CACHE_REFRESH_MS")
	? max(1, real(global.GV_VISUAL_CACHE_REFRESH_MS)) : 16;

if (use_visual_cache && (!variable_global_exists("timeline_anchor_surface_cache") || !is_struct(global.timeline_anchor_surface_cache))) {
	global.timeline_anchor_surface_cache = {};
}

if (ui_name_value == "timeline_canvas_anchor") {
	var _anchor_t0_us = get_timer();
	var diag_disable_timeline_anchor = variable_global_exists("DIAG_DISABLE_TIMELINE_ANCHOR")
		&& global.DIAG_DISABLE_TIMELINE_ANCHOR;
	var timeline_hide_during_play = variable_global_exists("TIMELINE_HIDE_DURING_PLAY")
		&& global.TIMELINE_HIDE_DURING_PLAY;
	var playback_complete = variable_global_exists("timeline_state")
		&& is_struct(global.timeline_state)
		&& variable_struct_exists(global.timeline_state, "playback_complete")
		&& global.timeline_state.playback_complete;
	var suppress_timeline_anchor = diag_disable_timeline_anchor
		|| (timeline_hide_during_play
			&& variable_global_exists("timeline_state")
			&& is_struct(global.timeline_state)
			&& global.timeline_state.active
			&& !playback_complete);
	if (diag_disable_timeline_draw) exit;
	if (suppress_timeline_anchor) {
		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state) && global.timeline_state.active) {
			gv_timeline_step_tick();
		}
		tune_rt_budget_diag_record_anchor_draw_ms("timeline", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}
	if (!use_visual_cache) {
		gv_draw_timeline_canvas(bbox_left, bbox_top, bbox_right, bbox_bottom);
		tune_rt_budget_diag_record_anchor_draw_ms("timeline", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}

	var _key = "timeline_" + string(id);
	var _w = max(1, bbox_right - bbox_left + 1);
	var _h = max(1, bbox_bottom - bbox_top + 1);
	var _cache = gv_anchor_cache_get_or_create(_key, _w, _h);
	var _cache_last_ms = real(variable_struct_get(_cache, "last_ms"));
	var _cache_surf = variable_struct_get(_cache, "surf");
	var _now_ms = timing_get_engine_now_ms();
	if ((_now_ms - _cache_last_ms) >= cache_refresh_ms) {
		surface_set_target(_cache_surf);
		draw_clear_alpha(c_black, 0);
		gv_draw_timeline_canvas(0, 0, _w - 1, _h - 1);
		surface_reset_target();
		variable_struct_set(_cache, "last_ms", _now_ms);
	}
	draw_surface(_cache_surf, bbox_left, bbox_top);
	gv_anchor_cache_store(_key, _cache);
	tune_rt_budget_diag_record_anchor_draw_ms("timeline", (get_timer() - _anchor_t0_us) / 1000);
	exit;
}

if (ui_name_value == "notebeam_canvas_anchor") {
	var _anchor_t0_us = get_timer();
	// Draw order for notebeam is controlled from obj_game_viz Draw GUI so it can
	// be layered above chanter graphics but below now-line and labels.

	tune_rt_budget_diag_record_anchor_draw_ms("notebeam", (get_timer() - _anchor_t0_us) / 1000);
	exit;
}

if (ui_name_value == "tunestructure_canvas_anchor") {
	var _anchor_t0_us = get_timer();
	if (!use_visual_cache) {
		gv_draw_tune_structure_panel(bbox_left, bbox_top, bbox_right, bbox_bottom);
		tune_rt_budget_diag_record_anchor_draw_ms("tunestructure", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}

	var _key = "tunestructure_" + string(id);
	var _w = max(1, bbox_right - bbox_left + 1);
	var _h = max(1, bbox_bottom - bbox_top + 1);
	var _cache = gv_anchor_cache_get_or_create(_key, _w, _h);
	var _cache_last_ms = real(variable_struct_get(_cache, "last_ms"));
	var _cache_surf = variable_struct_get(_cache, "surf");
	var _playing_active = false;
	var _playing_complete = false;
	var _current_scroll = 0;
	var _structure_refresh_ms = cache_refresh_ms;
	if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
		_playing_active = variable_struct_exists(global.timeline_state, "active") && global.timeline_state.active;
		_playing_complete = variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete;
		_current_scroll = variable_struct_exists(global.timeline_state, "measure_nav_scroll_row")
			? floor(real(global.timeline_state.measure_nav_scroll_row))
			: 0;
		if (_playing_active && !_playing_complete && variable_global_exists("GV_TUNESTRUCTURE_PLAY_REFRESH_MS")) {
			_structure_refresh_ms = max(cache_refresh_ms, real(global.GV_TUNESTRUCTURE_PLAY_REFRESH_MS));
		}
	}
	var _current_seg = (variable_global_exists("playback_context") && is_struct(global.playback_context))
		? floor(real(global.playback_context[$ "active_segment"] ?? 0))
		: 0;
	var _now_ms = timing_get_engine_now_ms();
	var _structure_needs_redraw = (_cache_last_ms <= -999999999);
	var _cached_play_state = variable_struct_exists(_cache, "play_state_active")
		? (variable_struct_get(_cache, "play_state_active") == true)
		: false;
	var _cached_scroll = variable_struct_exists(_cache, "scroll_row")
		? floor(real(variable_struct_get(_cache, "scroll_row")))
		: -999999;
	var _cached_seg = variable_struct_exists(_cache, "active_segment")
		? floor(real(variable_struct_get(_cache, "active_segment")))
		: -999999;
	var _playing_state_now = _playing_active && !_playing_complete;
	if (!_structure_needs_redraw) {
		if (_playing_state_now) {
			_structure_needs_redraw = (_cached_play_state != true) || (_current_scroll != _cached_scroll) || (_current_seg != _cached_seg);
		} else {
			_structure_needs_redraw = (_cached_play_state != _playing_state_now)
				|| (_current_seg != _cached_seg)
				|| ((_now_ms - _cache_last_ms) >= _structure_refresh_ms);
		}
	}
	if (_structure_needs_redraw) {
		// Match notebeam behavior: set anchor offsets during cached render so
		// tune-structure hitboxes are stored in global screen coordinates.
		global.GV_ANCHOR_RECT_X_OFFSET = -bbox_left;
		global.GV_ANCHOR_RECT_Y_OFFSET = -bbox_top;
		var _static_gameplay_flag_prev = variable_global_exists("GV_TUNESTRUCTURE_GAMEPLAY_STATIC")
			? global.GV_TUNESTRUCTURE_GAMEPLAY_STATIC
			: false;
		global.GV_TUNESTRUCTURE_GAMEPLAY_STATIC = _playing_state_now;
		surface_set_target(_cache_surf);
		draw_clear_alpha(c_black, 0);
		gv_draw_tune_structure_panel(0, 0, _w - 1, _h - 1);
		surface_reset_target();
		global.GV_TUNESTRUCTURE_GAMEPLAY_STATIC = _static_gameplay_flag_prev;
		global.GV_ANCHOR_RECT_X_OFFSET = 0;
		global.GV_ANCHOR_RECT_Y_OFFSET = 0;
		variable_struct_set(_cache, "last_ms", _now_ms);
		variable_struct_set(_cache, "scroll_row", _current_scroll);
		variable_struct_set(_cache, "active_segment", _current_seg);
		variable_struct_set(_cache, "play_state_active", _playing_state_now);
	}
	draw_surface(_cache_surf, bbox_left, bbox_top);
	
	// Draw current-measure overlay.
	// During active play: highlights the in-progress tile.
	// Post-play review: highlights the tile at the current playhead (after click-to-jump).
	// Overlay is cheap – only re-rendered when the measure or segment changes.
	var _need_overlay = _playing_state_now;
	if (_need_overlay) {
		var _playhead_ms = (variable_global_exists("timeline_state") && is_struct(global.timeline_state))
			? real(global.timeline_state.playhead_ms ?? 0)
			: -1;
		var _cached_measure = variable_struct_exists(_cache, "overlay_current_measure")
			? floor(real(variable_struct_get(_cache, "overlay_current_measure")))
			: -999999;
		var _cached_overlay_seg = variable_struct_exists(_cache, "overlay_seg")
			? floor(real(variable_struct_get(_cache, "overlay_seg")))
			: -999999;
		
		// Fast path: read current measure cached by scheduler/parser.
		var _current_measure = (variable_global_exists("timeline_state")
			&& is_struct(global.timeline_state)
			&& variable_struct_exists(global.timeline_state, "current_measure"))
			? floor(real(global.timeline_state.current_measure))
			: -1;

		// Fallback: derive from playhead.
		if (_current_measure < 1 && _playhead_ms >= 0) {
			_current_measure = gv_get_current_planned_measure(_playhead_ms);
		}
		
		// Redraw overlay if measure changed OR if segment changed (tile positions moved).
		if (_current_measure != _cached_measure || _current_seg != _cached_overlay_seg) {
			var _overlay_surf = variable_struct_exists(_cache, "overlay_surf")
				? variable_struct_get(_cache, "overlay_surf")
				: -1;
			
			if (!surface_exists(_overlay_surf)) {
				_overlay_surf = surface_create(_w, _h);
				variable_struct_set(_cache, "overlay_surf", _overlay_surf);
			}
			
			global.GV_ANCHOR_RECT_X_OFFSET = -bbox_left;
			global.GV_ANCHOR_RECT_Y_OFFSET = -bbox_top;
			surface_set_target(_overlay_surf);
			draw_clear_alpha(c_black, 0);
			gv_draw_tune_structure_current_overlay_to_surface(0, 0, _w - 1, _h - 1, _current_measure);
			surface_reset_target();
			global.GV_ANCHOR_RECT_X_OFFSET = 0;
			global.GV_ANCHOR_RECT_Y_OFFSET = 0;
			
			variable_struct_set(_cache, "overlay_current_measure", _current_measure);
			variable_struct_set(_cache, "overlay_seg", _current_seg);
		}
		
		var _overlay_surf = variable_struct_exists(_cache, "overlay_surf")
			? variable_struct_get(_cache, "overlay_surf")
			: -1;
		if (surface_exists(_overlay_surf)) {
			draw_surface(_overlay_surf, bbox_left, bbox_top);
		}
	}
	
	gv_anchor_cache_store(_key, _cache);
	tune_rt_budget_diag_record_anchor_draw_ms("tunestructure", (get_timer() - _anchor_t0_us) / 1000);
	exit;
}


if (ui_name_value == "gameviz_canvas_anchor") {
	var _anchor_t0_us = get_timer();
	if (sprite_index == noone) {
		sprite_index = spr_field_item;
		mask_index = spr_field_item;
	}
	if (!use_visual_cache) {
		gv_draw_gameviz_controls_panel(bbox_left, bbox_top, bbox_right, bbox_bottom);
		tune_rt_budget_diag_record_anchor_draw_ms("gameviz", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}
	var _key = "gameviz_" + string(id);
	var _w = max(1, bbox_right - bbox_left + 1);
	var _h = max(1, bbox_bottom - bbox_top + 1);
	var _cache = gv_anchor_cache_get_or_create(_key, _w, _h);
	var _cache_last_ms = real(variable_struct_get(_cache, "last_ms"));
	var _cache_surf = variable_struct_get(_cache, "surf");
	var _now_ms = timing_get_engine_now_ms();
	if ((_now_ms - _cache_last_ms) >= cache_refresh_ms) {
		surface_set_target(_cache_surf);
		draw_clear_alpha(c_black, 0);
		gv_draw_gameviz_controls_panel(0, 0, _w - 1, _h - 1);
		surface_reset_target();
		variable_struct_set(_cache, "last_ms", _now_ms);
	}
	draw_surface(_cache_surf, bbox_left, bbox_top);
	gv_anchor_cache_store(_key, _cache);
	tune_rt_budget_diag_record_anchor_draw_ms("gameviz", (get_timer() - _anchor_t0_us) / 1000);
	exit;
}

if (ui_name_value == "gameviz_structure_anchor") {
	var _anchor_t0_us = get_timer();
	var _show_loop_structure = variable_global_exists("loop_mode_enabled") && global.loop_mode_enabled;
	if (!_show_loop_structure) {
		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
			&& variable_struct_exists(global.timeline_state, "measure_nav_controls")
			&& is_struct(global.timeline_state.measure_nav_controls)) {
			var _ctrls = global.timeline_state.measure_nav_controls;
			_ctrls.left = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
			_ctrls.right = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
			_ctrls.blank = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
			_ctrls.jump = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
			global.timeline_state.measure_nav_controls = _ctrls;
		}
		tune_rt_budget_diag_record_anchor_draw_ms("gameviz_structure", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}
	if (sprite_index == noone) {
		sprite_index = spr_field_item;
		mask_index = spr_field_item;
	}
	if (!use_visual_cache) {
		gv_draw_gameviz_structure_panel(bbox_left, bbox_top, bbox_right, bbox_bottom);
		tune_rt_budget_diag_record_anchor_draw_ms("gameviz_structure", (get_timer() - _anchor_t0_us) / 1000);
		exit;
	}
	var _key = "gameviz_structure_" + string(id);
	var _w = max(1, bbox_right - bbox_left + 1);
	var _h = max(1, bbox_bottom - bbox_top + 1);
	var _cache = gv_anchor_cache_get_or_create(_key, _w, _h);
	var _cache_last_ms = real(variable_struct_get(_cache, "last_ms"));
	var _cache_surf = variable_struct_get(_cache, "surf");
	var _now_ms = timing_get_engine_now_ms();
	if ((_now_ms - _cache_last_ms) >= cache_refresh_ms) {
		global.GV_ANCHOR_RECT_X_OFFSET = -bbox_left;
		global.GV_ANCHOR_RECT_Y_OFFSET = -bbox_top;
		surface_set_target(_cache_surf);
		draw_clear_alpha(c_black, 0);
		gv_draw_gameviz_structure_panel(0, 0, _w - 1, _h - 1);
		surface_reset_target();
		global.GV_ANCHOR_RECT_X_OFFSET = 0;
		global.GV_ANCHOR_RECT_Y_OFFSET = 0;
		variable_struct_set(_cache, "last_ms", _now_ms);
	}
	draw_surface(_cache_surf, bbox_left, bbox_top);
	gv_anchor_cache_store(_key, _cache);
	tune_rt_budget_diag_record_anchor_draw_ms("gameviz_structure", (get_timer() - _anchor_t0_us) / 1000);
	exit;
}

if (ui_name_value == "judge_list_canvas" || ui_name_value == "judge_detail_canvas") {
	if (room_get_name(room) != "Room_main_menu") exit;

	var _judge_layer_id = layer_get_id("judge_settings_layer");
	if (_judge_layer_id == -1 || !layer_get_visible(_judge_layer_id)) exit;

	var _ensure_idx = asset_get_index("scoring_judge_settings_ensure_state");
	if (script_exists(_ensure_idx)) {
		script_execute(_ensure_idx);
	}

	if (ui_name_value == "judge_list_canvas") {
		var _list_idx = asset_get_index("scoring_judge_settings_draw_list_canvas");
		if (script_exists(_list_idx)) {
			script_execute(_list_idx, bbox_left, bbox_top, bbox_right, bbox_bottom);
		}
		exit;
	}

	var _detail_idx = asset_get_index("scoring_judge_settings_draw_detail_canvas");
	if (script_exists(_detail_idx)) {
		script_execute(_detail_idx, bbox_left, bbox_top, bbox_right, bbox_bottom);
	}
	exit;
}

var _ui_name_len = string_length(ui_name_value);
var _is_notebeam_label_anchor = (_ui_name_len > 13)
	&& (string_copy(ui_name_value, 1, 6) == "label_")
	&& (string_copy(ui_name_value, _ui_name_len - 6, 7) == "_anchor");
if (_is_notebeam_label_anchor) {
	// Label anchors are composited from Draw GUI to keep them above notebeam.
	exit;
}

draw_self();

var display_text = "";
if (variable_instance_exists(id, "field_contents")) {
	display_text = string(variable_instance_get(id, "field_contents"));
}
// gameinfo title reads directly from global — no field_target setup required
if (ui_name_value == "gameinfo_win_title"
	&& variable_global_exists("gameinfo_title")
	&& is_array(global.gameinfo_title)
	&& array_length(global.gameinfo_title) > 0) {
	display_text = string(global.gameinfo_title[0]);
}
var draw_x = x + 10;
var draw_y = y;

var is_current_note_field = false;
is_current_note_field = (ui_name_value == "obj_last_measure_tune_notes"
	|| ui_name_value == "obj_current_measure_tune_notes"
	|| ui_name_value == "obj_next_measure_tune_notes"
	|| ui_name_value == "obj_last_measure_player_notes"
	|| ui_name_value == "obj_current_measure_player_notes"
	|| ui_name_value == "obj_next_measure_player_notes");

if (is_current_note_field) draw_set_font(fnt_measure);
else draw_set_font(fnt_setting);

if (!is_current_note_field) {
	draw_set_colour(c_ltgray);
	draw_text(draw_x, draw_y, display_text);
	draw_set_colour(c_white);
	return;
}

var marker = "^";
if (variable_global_exists("current_note_panel") && is_struct(global.current_note_panel)) {
	marker = string(global.current_note_panel.filter_marker_symbol ?? "^");
	if (string_length(marker) <= 0) marker = "^";
}

var has_token_map = false;
var token_list = [];
if (is_current_note_field && variable_global_exists("current_note_panel") && is_struct(global.current_note_panel)) {
	if (is_struct(global.current_note_panel.render_tokens)) {
		token_list = global.current_note_panel.render_tokens[$ ui_name_value];
		has_token_map = is_array(token_list);
	}
}

if (has_token_map) {
	for (var t = 0; t < array_length(token_list); t++) {
		var token = token_list[t];
		var token_text = string(token.text ?? "");
		var token_class = string(token.class ?? "normal");
		switch (token_class) {
			case "filtered_noise": draw_set_colour(c_red); break;
			case "short_noncore": draw_set_colour(c_yellow); break;
			default: draw_set_colour(c_ltgray); break;
		}
		draw_text(draw_x, draw_y, token_text);
		draw_x += string_width(token_text);
	}
	draw_set_colour(c_white);
	return;
}

for (var i = 1; i <= string_length(display_text); i++) {
	var ch = string_char_at(display_text, i);
	if (ch == marker) draw_set_colour(c_red);
	else draw_set_colour(c_ltgray);
	draw_text(draw_x, draw_y, ch);
	draw_x += string_width(ch);
}

draw_set_colour(c_white);