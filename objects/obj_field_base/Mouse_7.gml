image_index = 1; // Return to hover after click

// Coordinate-space contract:
// - gameviz/notebeam click handlers consume GUI-space positions.
// - tune-structure click handler consumes room/screen-space positions.
var _mx_gui = (is_undefined(device_mouse_x_to_gui) == false)
	? device_mouse_x_to_gui(0)
	: mouse_x;
var _my_gui = (is_undefined(device_mouse_y_to_gui) == false)
	? device_mouse_y_to_gui(0)
	: mouse_y;

if (gv_is_gameviz_anchor(id)) {
	gv_handle_gameviz_controls_click(_mx_gui, _my_gui, bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

if (gv_is_notebeam_anchor(id)) {
	gv_handle_notebeam_click(_mx_gui, _my_gui, bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

var _ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
	_ui_name_value = string(variable_instance_get(id, "ui_name"));
}
if (_ui_name_value == "tunestructure_canvas_anchor") {
	// During post-play review, measure selection is handled on mouse-press via
	// gv_review_handle_click in gv_timeline_step_tick. Skip the release event
	// to avoid double-firing the toggle.
	if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
		&& variable_struct_exists(global.timeline_state, "playback_complete")
		&& global.timeline_state.playback_complete) exit;
	// During active play: Tune-structure hitboxes are tracked in room/screen space.
	gv_measure_nav_handle_click(mouse_x, mouse_y);
	exit;
}

if (_ui_name_value == "gameviz_structure_anchor") {
	// Loop controls above tune structure also use room/screen-space hitboxes.
	if (!(variable_global_exists("loop_mode_enabled") && global.loop_mode_enabled)) exit;
	gv_measure_nav_handle_click(mouse_x, mouse_y);
	exit;
}

if (_ui_name_value == "judge_list_canvas" || _ui_name_value == "judge_detail_canvas") {
	if (room_get_name(room) != "Room_main_menu") exit;

	var _judge_layer_id = layer_get_id("judge_settings_layer");
	if (_judge_layer_id == -1 || !layer_get_visible(_judge_layer_id)) exit;

	if (_ui_name_value == "judge_list_canvas") {
		var _list_click_idx = asset_get_index("scoring_judge_settings_handle_list_click");
		if (script_exists(_list_click_idx)) {
			script_execute(_list_click_idx, mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
		}
		exit;
	}

	var _detail_click_idx = asset_get_index("scoring_judge_settings_handle_detail_click");
	if (script_exists(_detail_click_idx)) {
		script_execute(_detail_click_idx, mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
	}
	exit;
}

//if (button_action != noone) {
var _field_script_index = variable_instance_exists(id, "field_script_index") ? variable_instance_get(id, "field_script_index") : -1;
scr_handle_button_click(_field_script_index, id);
//}
