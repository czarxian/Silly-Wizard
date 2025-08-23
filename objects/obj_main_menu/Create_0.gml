/// obj_Main_Menu Create Event
if (!variable_global_exists("panel_list")) {
    global.panel_list = [];
}

// Create the main menu panel
var panel = instance_create_layer(640, 360, "GUI", obj_flex_panel);
panel.layout_type = "vertical";
panel.align_x = 0.5;
panel.align_y = 0.5;
panel.padding = 32;
panel.spacing = 24;


// Create buttons
var btn_play    = instance_create_layer(0, 0, "GUI", obj_flex_button);
btn_play.sprite_index = spr_button_main_menu; // normal button sprite
btn_play.image_index  = 0;          // start in normal state
btn_play.label  = "Play";
btn_play.action = function() {
    ui_clear_panels();
    room_goto(Room_play);
};

var btn_tune    = instance_create_layer(0, 0, "GUI", obj_flex_button);
btn_tune.sprite_index = spr_button_main_menu; // normal button sprite
btn_tune.image_index  = 0;          // start in normal state
btn_tune.label  = "Select Tune";
btn_tune.action = function() {
    show_debug_message("Tune selection not yet implemented.");
};

var btn_settings = instance_create_layer(0, 0, "GUI", obj_flex_button);
btn_settings.sprite_index = spr_button_main_menu; // normal button sprite
btn_settings.image_index  = 0;          // start in normal state
btn_settings.label = "Settings";
btn_settings.action = function() {
    show_debug_message("Settings window not yet implemented.");
};

var btn_exit    = instance_create_layer(0, 0, "GUI", obj_flex_button);
btn_exit.sprite_index = spr_button_main_menu; // normal button sprite
btn_exit.image_index  = 0;          // start in normal state
btn_exit.label  = "Exit";
btn_exit.action = function() {
    game_end();
};

// Add buttons to panel
array_push(panel.children, btn_play);
array_push(panel.children, btn_tune);
array_push(panel.children, btn_settings);
array_push(panel.children, btn_exit);

// Trigger layout refresh
panel.panel_redraw_needed = true;
