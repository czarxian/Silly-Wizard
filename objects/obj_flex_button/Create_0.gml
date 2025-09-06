width  = sprite_width;
height = sprite_height;
clickable = true;
hovered = false;
selected = false;


style_id = "menu"; // or "settings", "round", etc.
label = "Click Me";

action = function() {
    show_debug_message("Clicked: " + label);
};


// Sizing and style
sprite_index = get_button_sprite(style_id);
ui_auto_size_to_sprite(id);

// Layering
z_index = 1; // draw above panels

// Register
show_debug_message("Registering UI element: " + string(id));
array_push(global.ui_elements, id);
show_debug_message("ui_elements after push: " + typeof(global.ui_elements));

