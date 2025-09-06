width  = 300;
height = 200;
padding = 8;
spacing = 4;

if (!variable_instance_exists(id, "panel_style")) {
    panel_style = "default";
}
background_sprite = get_panel_sprite(panel_style);

// Size to sprite so layout uses correct bounds
width  = sprite_get_width(background_sprite);
height = sprite_get_height(background_sprite);

// Layering
z_index = 0; // background first

clickable = false;
hovered = false;

children = [];

// Register
show_debug_message("Registering UI element: " + string(id));
array_push(global.ui_elements, id);
show_debug_message("Panel sprite: " + string(background_sprite));
show_debug_message("ui_elements after push: " + typeof(global.ui_elements));
show_debug_message("Panel registered: " + string(id));

