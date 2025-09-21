// obj_ui_controller - Create Event
show_debug_message("Create: UI controller active");


// Create Event
//alarm[0] = 10;


//// Get the layer ID
//var layer_id = layer_ui_get_id("main_menu_layer");
//if (layer_id == noone) {
//    show_debug_message("main_menu_layer not found!");
//    exit;
//}
////list all nodes (to debug)
//var nodes = flexlayer_get_all_nodes(layer_id);
//for (var i = 0; i < array_length(nodes); i++) {
//    show_debug_message("Node found: " + nodes[i]);
//}
//
//// Use flexlayer_get_node to get the node inside that layer
//var panel = flexlayer_get_node(layer_id, "fp_main_menu");
//
//if (panel == undefined) {
//    show_debug_message("⚠ Node not found: fp_main_menu in main_menu_layer");
//} else {
//    show_debug_message("✅ Node found: fp_main_menu in main_menu_layer");
//
//    // Assign and configure
//    fp_main_menu = panel;
//    fp_main_menu.x = room_width * 0.25;
//    fp_main_menu.y = 0;
//    fp_main_menu.width = room_width * 0.75;
//    fp_main_menu.height = room_height;
//}
