image_index = 1; // Return to hover after click

if (gv_is_gameviz_anchor(id)) {
	gv_handle_gameviz_controls_click(mouse_x, mouse_y, bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

//if (button_action != noone) {
var _field_script_index = variable_instance_exists(id, "field_script_index") ? variable_instance_get(id, "field_script_index") : -1;
scr_handle_button_click(_field_script_index, id);
//}
