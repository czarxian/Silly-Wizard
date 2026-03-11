/// @description Timeline playhead update

if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) exit;
if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) exit;

if (!global.timeline_cfg.enabled) exit;
if (!global.timeline_state.active) exit;

if (mouse_check_button_pressed(mb_left)) {
	gv_review_handle_click(mouse_x, mouse_y);
}

var review_mode = variable_struct_exists(global.timeline_state, "review_mode") && global.timeline_state.review_mode;
if (review_mode) exit;

var playhead_lag_ms = 0;
if (variable_struct_exists(global.timeline_cfg, "playhead_audio_lag_ms")) {
	playhead_lag_ms = max(0, real(global.timeline_cfg.playhead_audio_lag_ms));
}

if (variable_global_exists("tune_start_real")) {
	global.timeline_state.playhead_ms = max(0, current_time - real(global.tune_start_real) - playhead_lag_ms);
} else {
	if (!variable_struct_exists(global.timeline_state, "start_clock_ms")) {
		global.timeline_state.start_clock_ms = current_time;
	}
	global.timeline_state.playhead_ms = max(0, current_time - real(global.timeline_state.start_clock_ms) - playhead_lag_ms);
}
