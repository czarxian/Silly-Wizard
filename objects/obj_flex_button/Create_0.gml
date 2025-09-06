width  = sprite_width;
height = sprite_height;
clickable = true;
hovered = false;

style_id = "menu"; // or "settings", "round", etc.
label = "Click Me";

callback = function() {
    show_debug_message("Clicked: " + label);
};

sprite_index = get_button_sprite(style_id); // Optional style registry
array_push(global.ui_elements, id);