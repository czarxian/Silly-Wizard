if (!variable_global_exists("ui_elements")) {
    global.ui_elements = [];
}

panel = new UIFlexPanel(
    640, 360,
    "vertical",
    0.5, 0.5,
    32, 24,
    noone, noone,   // Let sprite dictate size
    300, 600,
    noone, 400
);

// ✅ Assign background sprite and auto‑size to match it
panel.sprite_index = spr_Main_Menu;
ui_auto_size_to_sprite(panel);

add_menu_button = function(_text, _action) {
    var btn = new UIButton(0, 0, 1, noone, _text, _action, spr_button_main_menu);
    btn.sprite_index = spr_button_main_menu;
    ui_auto_size_to_sprite(btn);
    panel.AddChild(btn);
};

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

array_push(global.ui_elements, panel);
ui_surface_needs_redraw = true;