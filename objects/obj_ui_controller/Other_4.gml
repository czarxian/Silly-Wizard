// obj_ui_controller - Room Start Event

show_debug_message("Room Start: UI controller active");

fp_main_menu = layer_get_flexpanel_node("fp_main_menu");

if (fp_main_menu != undefined) {
    fp_main_menu.x = room_width * 0.25;
    fp_main_menu.y = 0;
    fp_main_menu.width = room_width * 0.75;
    fp_main_menu.height = room_height;
} else {
    show_debug_message("⚠️ fp_main_menu not found at Room Start");
}