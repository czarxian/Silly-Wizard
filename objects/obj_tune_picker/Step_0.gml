// obj_tune_picker Step
// Allow mouse-wheel scrolling through the virtualized tune list while the tune window is open.

var tune_layer_id = layer_get_id("tune_window_layer");
if (tune_layer_id == -1) exit;
if (!layer_get_visible(tune_layer_id)) exit;

var gui_x = display_mouse_get_x();
var gui_y = display_mouse_get_y();
if (is_undefined(scr_tune_picker_get_mouse_gui_x) == false) gui_x = scr_tune_picker_get_mouse_gui_x();
if (is_undefined(scr_tune_picker_get_mouse_gui_y) == false) gui_y = scr_tune_picker_get_mouse_gui_y();

if (mouse_check_button_pressed(mb_left)) {
    if (is_undefined(scr_tune_picker_handle_click) == false) {
        scr_tune_picker_handle_click(gui_x, gui_y);
    }
}

var scroll_delta = 0;
if (mouse_wheel_up()) scroll_delta -= 1;
if (mouse_wheel_down()) scroll_delta += 1;

var pointer_over_list = true;
if (is_undefined(scr_tune_picker_is_pointer_over_list) == false) {
    pointer_over_list = scr_tune_picker_is_pointer_over_list(gui_x, gui_y);
}

if (scroll_delta != 0 && pointer_over_list) {
    if (is_undefined(scr_tune_picker_scroll_rows) == false) {
        scr_tune_picker_scroll_rows(scroll_delta);
    } else {
        view_scroll_offset += scroll_delta;
    }

    if (is_undefined(scr_tune_picker_refresh_visible_rows) == false) {
        scr_tune_picker_refresh_visible_rows();
    } else if (is_undefined(scr_tune_picker_populate) == false) {
        // Fallback path if helper is unavailable.
        scr_tune_picker_populate();
    }
}
