/// Create a centered main menu panel
if (!variable_global_exists("ui_elements")) {
    global.ui_elements = [];
}

panel = new UIFlexPanel(
    640, 360,          // Anchor position (center of screen)
    "vertical",        // Layout type
    0.5, 0.5,          // Align X/Y (centered)
    32, 24,            // Padding / spacing
    300, noone,        // Fixed width (300px), auto height
    300, 600,          // Min width, max width
    noone, 400         // Min height, max height
);

panel.sprite_index = spr_Main_Menu;
ui_auto_size_to_sprite(panel);

// Helper to add a button to this panel
add_menu_button = function(_text, _action) {
    // Width=1 means 100% of panel width minus padding
    var btn = new UIButton(0, 0, 1, 64, _text, _action, spr_button_main_menu);
	btn.sprite_index = spr_button_main_menu;
	ui_auto_size_to_sprite(btn);
    panel.AddChild(btn);
};

// Menu buttons
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

// Register the panel with the UI Manager
array_push(global.ui_elements, panel);