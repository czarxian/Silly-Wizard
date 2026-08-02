// Timeline tick ownership moved to obj_game_controller Step.
// Keep this event intentionally empty so anchor activity does not affect timing.

var _ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
	_ui_name_value = string(variable_instance_get(id, "ui_name"));
}

// --- judge_list_canvas scroll ---
if (_ui_name_value == "judge_list_canvas") {
	if (room_get_name(room) != "Room_main_menu") exit;
	var _judge_layer_id = layer_get_id("judge_settings_layer");
	if (_judge_layer_id == -1 || !layer_get_visible(_judge_layer_id)) exit;

	var _scroll_delta = 0;
	if (mouse_wheel_up()) _scroll_delta = -1;
	if (mouse_wheel_down()) _scroll_delta = 1;
	if (_scroll_delta == 0) exit;

	var _scroll_idx = asset_get_index("scoring_judge_settings_handle_list_scroll");
	if (!script_exists(_scroll_idx)) exit;
	script_execute(_scroll_idx, _scroll_delta, mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

// --- loop_score_matrix_canvas scroll ---
if (_ui_name_value == "loop_score_matrix_canvas") {
	var _loop_layer_id = layer_get_id("loop_score_overview_layer");
	if (_loop_layer_id == -1 || !layer_get_visible(_loop_layer_id)) exit;

	if (mouse_check_button_pressed(mb_left)) {
		var _loop_click_idx = asset_get_index("scoring_loop_overview_handle_click");
		if (script_exists(_loop_click_idx)) {
			script_execute(_loop_click_idx, mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
		}
	}

	var _scroll_delta = 0;
	if (mouse_wheel_up()) _scroll_delta = -1;
	if (mouse_wheel_down()) _scroll_delta = 1;
	if (_scroll_delta == 0) exit;

	var _loop_scroll_idx = asset_get_index("scoring_loop_overview_handle_scroll");
	if (!script_exists(_loop_scroll_idx)) exit;
	script_execute(_loop_scroll_idx, _scroll_delta, mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}
