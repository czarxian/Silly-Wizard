// obj_ui_controller - Room Start Event

show_debug_message("Room Start: UI controller active");

// Get the layer ID
var layer_id = layer_get_id("main_menu_layer");

// Use flexlayer_get_node to get the node inside that layer
var panel = flexlayer_get_node(layer_id, "fp_main_menu");

if (panel == undefined) {
    show_debug_message("⚠️ Node not found: fp_main_menu in main_menu_layer");
} else {
    show_debug_message("✅ Node found: fp_main_menu in main_menu_layer");

    // Assign and configure
    fp_main_menu = panel;
    fp_main_menu.x = room_width * 0.25;
    fp_main_menu.y = 0;
    fp_main_menu.width = room_width * 0.75;
    fp_main_menu.height = room_height;
}
