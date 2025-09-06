/// @desc Handle hover/click state and trigger redraw when needed
var was_hovered  = hovered;
var was_selected = selected;

// Mouse position in GUI space
var mx = global.ui_mouse_x;
var my = global.ui_mouse_y;

// Hover detection
hovered = point_in_rectangle(mx, my, x, y, x + width, y + height);

// Click detection
if (hovered && mouse_check_button_pressed(mb_left)) {
    if (is_callable(callback)) callback();
    selected = true; // or toggle if needed
} else {
    selected = false;
}

// Trigger redraw if state changed
if (hovered != was_hovered || selected != was_selected) {
    ui_surface_needs_redraw = true;
}