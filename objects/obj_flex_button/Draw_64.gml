/// @desc Draw button with sprite frames for normal/hover/selected
var frame = 0;
if (hovered) frame = 1;
if (selected) frame = 2;

// Draw sprite if set
if (sprite_index != -1) {
    var sx = width  / sprite_width;
    var sy = height / sprite_height;
    draw_sprite_ext(sprite_index, frame, x, y, sx, sy, 0, c_white, 1);
} else {
    // Fallback: simple rectangle
    draw_set_color(hovered ? c_ltgray : c_white);
    draw_rectangle(x, y, x + width, y + height, false);
}

// Draw label text centered
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_color(c_black);
draw_text(x + width * 0.5, y + height * 0.5, label);