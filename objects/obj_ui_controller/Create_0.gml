// Obj_ui_controller Create Event

// Initialize layer names only once
if (!variable_global_exists("ui_layer_names")) {
    global.ui_layer_names = [];
    global.ui_layer_names[0] = "main_menu_layer";
    global.ui_layer_names[1] = "settings_window_layer";
    global.ui_layer_names[2] = "tune_window_layer";
    global.ui_layer_names[3] = "gameinfo_window_layer";
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
	global.tune_library = array_create(5);
	global.tune_library[0]="Tune Not Set";
	global.tune_library[1]="Tune 1";
	global.tune_library[2]="Tune 2";
	global.tune_library[3]="Tune 3";
	global.tune_library[4]="Tune 4";
	global.tune_library[5]="It's Sheffield Wednesday and I'm in Love";
	global.tune_library[6]="Not set";

//global.tune_library = ["Tune A", "Tune B", "Tune C", "Tune D", "Tune E", "Tune F","Tune G"];
global.tune_page = 0;
global.tunes_per_page = 6;