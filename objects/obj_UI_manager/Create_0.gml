//UI_Manager create event
global.ui_mouse_x = 0;
global.ui_mouse_y = 0;

global.ui_manager_draws = true;

global.ui_elements = [];
//instance_create_layer(0, 0, "Instances", obj_main_menu);

instance_create_layer(display_get_gui_width() / 2, display_get_gui_height() / 2, "Instances", obj_flex_panel, {
    panel_style: "main_menu"
});