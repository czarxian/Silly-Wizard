// obj_tune_picker Step
// Allow mouse-wheel scrolling through the virtualized tune list while the tune window is open.

var tune_layer_id = layer_get_id("tune_window_layer");
if (tune_layer_id == -1) exit;
if (!layer_get_visible(tune_layer_id)) exit;

// Capture keyboard input for set name editing
if (variable_instance_exists(id, "set_name_editing") && set_name_editing) {
    var _ks = keyboard_string;
    if (string_length(_ks) > 0) {
        set_name_text = set_name_text + _ks;
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_backspace) && string_length(set_name_text) > 0) {
        set_name_text = string_delete(set_name_text, string_length(set_name_text), 1);
    }
    if (keyboard_check_pressed(vk_return) || keyboard_check_pressed(vk_escape)) {
        set_name_editing = false;
        keyboard_string = "";
    }
}

var gui_x = scr_tune_picker_get_mouse_gui_x();
var gui_y = scr_tune_picker_get_mouse_gui_y();

if (mouse_check_button_pressed(mb_left)) {
    scr_tune_picker_handle_click(gui_x, gui_y);
}

var scroll_delta = 0;
if (mouse_wheel_up()) scroll_delta -= 1;
if (mouse_wheel_down()) scroll_delta += 1;

var pointer_over_list = scr_tune_picker_is_pointer_over_list(gui_x, gui_y);

if (scroll_delta != 0 && pointer_over_list) {
    scr_tune_picker_scroll_rows(scroll_delta);
    scr_tune_picker_refresh_visible_rows();
}
