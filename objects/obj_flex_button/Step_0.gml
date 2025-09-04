var was_hovered = hovered;
var was_selected = selected;

// Hitbox
var _x1 = x - sprite_get_xoffset(sprite_index);
var _y1 = y - sprite_get_yoffset(sprite_index);
var _x2 = _x1 + width;
var _y2 = _y1 + height;

// Hover detection
hovered = point_in_rectangle(mx, my, _x1, _y1, _x2, _y2);

// Click detection
if (hovered && mouse_check_button_pressed(mb_left)) {
    if (is_callable(action)) action();
    selected = true; // or toggle if needed
} else {
    selected = false;
}

// Trigger redraw if state changed
if (hovered != was_hovered || selected != was_selected) {
    ui_surface_needs_redraw = true;
}