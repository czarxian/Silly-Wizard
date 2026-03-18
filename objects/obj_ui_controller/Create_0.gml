// obj_ui_controller — UI registry & layer manager
// Purpose: Central registry for UI layers, assets and field synchronization.
// Key responsibilities:
//  - Initializes global.ui_layer_names, global.ui_assets, global.ui_fields and numbering
//  - Stores tune selection defaults (global.tune_library, global.tune_selection, pagination)
// Related scripts: scripts/scr_UI_scripts/ (GetLayerNameFromIndex, scr_update_fields, scr_ui_refresh), scripts/scr_button_scripts/

// Obj_ui_controller Create Event

// Initialize layer names only once
if (!variable_global_exists("ui_layer_names")) {
    global.ui_layer_names = [];
    global.ui_layer_names[0] = "main_menu_layer";
    global.ui_layer_names[1] = "settings_window_layer";
    global.ui_layer_names[2] = "tune_window_layer";
    global.ui_layer_names[3] = "gameplay_layer";
	global.ui_layer_names[4] = "current_note_layer";
}

// Initialize ui_assets only once
if (!variable_global_exists("ui_assets")) {
    global.ui_assets = [];
    for (var i = 0; i < array_length(global.ui_layer_names); i++) {
        global.ui_assets[i] = [];
    }
}

// Initialize numbering only once
if (!variable_global_exists("next_ui_number")) {
    global.next_ui_number = 0;
}

// Initialize fields list only once
if (!variable_global_exists("ui_fields")) {
    global.ui_fields = [];
}
//Tune variables
	global.tune_selection = -1;
	global.selected_tune_time_sig = ""; // Time signature of tune currently selected in picker (before OK clicked)
	global.tune_library = { tunes: [] };

//global.tune_library = ["Tune A", "Tune B", "Tune C", "Tune D", "Tune E", "Tune F","Tune G"];
global.tune_page = 0;
global.tunes_per_page = 6;
