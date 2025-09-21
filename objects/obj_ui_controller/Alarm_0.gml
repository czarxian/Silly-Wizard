//Alarm[0] to allow time for the UI to initialize.
show_debug_message("Create: UI Alarm[0] event activated");

// obj_ui_controller → Alarm[0] Event

var layer_id = layer_ui_get_id("main_menu_layer");
if (layer_id == noone) {
    show_debug_message("ERROR: main_menu_layer not found.");
    exit;
}

// Attempt to get each button panel node
var fp_play_button     = flexlayer_get_node(layer_id, "fp_play_button");
var fp_settings_button = flexlayer_get_node(layer_id, "fp_settings_button");
var fp_tune_button     = flexlayer_get_node(layer_id, "fp_tune_button");
var fp_exit_button     = flexlayer_get_node(layer_id, "fp_exit_button");

// Validate each node before assigning
if (fp_play_button != undefined) {
    fp_play_button.button_action = scr_goto_playroom;
    fp_play_button.button_ID = "play";
} else {
    show_debug_message("ERROR: fp_play_button not found.");
}

if (fp_settings_button != undefined) {
    fp_settings_button.button_action = scr_open_settings;
    fp_settings_button.button_ID = "settings";
} else {
    show_debug_message("ERROR: fp_settings_button not found.");
}

if (fp_tune_button != undefined) {
    fp_tune_button.button_action = scr_open_tune;
    fp_tune_button.button_ID = "tune";
} else {
    show_debug_message("ERROR: fp_tune_button not found.");
}

if (fp_exit_button != undefined) {
    fp_exit_button.button_action = scr_exit_game;
    fp_exit_button.button_ID = "exit";
} else {
    show_debug_message("ERROR: fp_exit_button not found.");
}