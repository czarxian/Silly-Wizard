/// obj_main_menu — Create Event
/// Creates a centered main menu panel with sprite background and clickable buttons

// Ensure global UI list exists
if (!variable_global_exists("ui_elements")) {
    global.ui_elements = [];
}

// --- Create the main menu panel ---
panel = instance_create_layer(640, 360, "Instances", obj_flex_panel);
panel.layout_type = "vertical";
panel.align_x     = 0.5;
panel.align_y     = 0.5;
panel.padding     = 32;
panel.spacing     = 24;

// Assign background sprite and auto-size to match it
panel.sprite_index = spr_Main_Menu;
ui_auto_size_to_sprite(panel);

// --- Helper to add a button to this panel ---
add_menu_button = function(_text, _action) {
    var btn = instance_create_layer(0, 0, "Instances", obj_flex_button);
    btn.label        = _text;
    btn.callback     = _action;
    btn.sprite_index = spr_button_main_menu;
    ui_auto_size_to_sprite(btn);
    ui_add_child(panel, btn);
};

// --- Menu buttons ---
add_menu_button("Play", function() {
    ui_clear_panels();
    room_goto(Room_play);
});

add_menu_button("Select Tune", function() {
    show_debug_message("Tune selection not yet implemented.");
});

add_menu_button("Settings", function() {
    show_debug_message("Settings window not yet implemented.");
});

add_menu_button("Exit", function() {
    game_end();
});

// --- Register the panel with the UI Manager ---
array_push(global.ui_elements, panel);

// Force initial redraw so the UI appears immediately
ui_surface_needs_redraw = true;