/// obj_flex_button Create Event

// Basic layout
width  = sprite_width;
height = sprite_height;
clickable = true;
hovered = false;

// Style and label
style_id = "default"; // Can be "menu", "round", etc.
label = "Click Me";

// Action binding
callback = function() {
    show_debug_message("Button clicked: " + string(label));
};

// Register with UI manager
array_push(global.ui_elements, id);

switch (style_id) {
    case "menu": sprite_index = spr_button_menu; break;
    case "round": sprite_index = spr_button_round; break;
    default: sprite_index = spr_button_default;
}