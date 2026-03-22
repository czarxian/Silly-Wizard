/// @description Timeline initial draw pass (planned row + now bar)

var _draw_t0_us = get_timer();
if (variable_global_exists("GV_ANCHOR_RENDER_ONLY") && global.GV_ANCHOR_RENDER_ONLY) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }
if (variable_global_exists("DIAG_DISABLE_TIMELINE_DRAW") && global.DIAG_DISABLE_TIMELINE_DRAW) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }
if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }
if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }
if (!variable_struct_exists(global.timeline_cfg, "enabled") || !global.timeline_cfg.enabled) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }
if (!global.timeline_state.active) { tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000); exit; }

var rect = gv_get_timeline_anchor_rect();
if (is_struct(rect)) {
	var pad = variable_struct_exists(global.timeline_cfg, "padding_px") ? real(global.timeline_cfg.padding_px) : 8;
	var gap = variable_struct_exists(global.timeline_cfg, "row_gap_px") ? real(global.timeline_cfg.row_gap_px) : 20;
	var now_ratio = variable_struct_exists(global.timeline_cfg, "now_ratio") ? real(global.timeline_cfg.now_ratio) : 0.33;
	now_ratio = clamp(now_ratio, 0.05, 0.95);

	var x1 = rect.x1 + pad;
	var y1 = rect.y1 + pad;
	var x2 = rect.x2 - pad;
	var y2 = rect.y2 - pad;
	if (x2 > x1 && y2 > y1) {
		var h = y2 - y1;
		var row_h = floor((h - gap) * 0.5);
		row_h = max(10, row_h);

		var tune_top = y1;
		var tune_bottom = min(y2, tune_top + row_h);
		var player_top = min(y2, tune_bottom + gap);
		var player_bottom = y2;

		// background + rows
		draw_set_alpha(0.90);
		draw_set_color(c_black);
		draw_rectangle(x1, y1, x2, y2, false);

		draw_set_color(c_dkgray);
		draw_rectangle(x1, tune_top, x2, tune_bottom, false);
		draw_rectangle(x1, player_top, x2, player_bottom, false);
		draw_set_alpha(1);

		// now bar
		var now_x = x1 + ((x2 - x1) * now_ratio);
		draw_set_color(c_yellow);
		draw_line_width(now_x, y1, now_x, y2, 2);

		// tune planned row (top)
		gv_draw_planned_row(x1, tune_top, x2, tune_bottom, global.timeline_state.playhead_ms);

		// labels
		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_color(c_white);
		draw_text(x1 + 4, tune_top + 2, "Tune Planned");
		draw_text(x1 + 4, player_top + 2, "Player MIDI In");
	}
}

// Fallback for rooms that don't instantiate the tune-structure anchor.
// Keep panel visible during active playback/review even without RoomUI anchor instances.
var ts_rect = gv_get_anchor_rect_by_name("tunestructure_canvas_anchor");
var ts_ok = false;
if (is_struct(ts_rect)) {
	var ts_w = real(ts_rect.w ?? 0);
	var ts_h = real(ts_rect.h ?? 0);
	ts_ok = (ts_w >= 96 && ts_h >= 96);
}
if (!ts_ok) {
	var panel_x1 = 16;
	var panel_x2 = max(panel_x1 + 140, floor(room_width * 0.22));
	var panel_y1 = floor(room_height * 0.22);
	var panel_y2 = floor(room_height * 0.90);
	if (panel_x2 > panel_x1 && panel_y2 > panel_y1) {
		gv_draw_tune_structure_panel(panel_x1, panel_y1, panel_x2, panel_y2);
	}
}

tune_rt_budget_diag_record_draw_ms((get_timer() - _draw_t0_us) / 1000);
