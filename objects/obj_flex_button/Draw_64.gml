/// @desc Draw button sprite with aspect ratio preserved, plus label
var frame = 0;
if (hovered) frame = 1;
if (selected) frame = 2;

if (sprite_index != -1) {
    var sw = sprite_width;
    var sh = sprite_height;
    var scale = min(width / sw, height / sh);
    var draw_w = sw * scale;
    var draw_h = sh * scale;
    var draw_x = x + (width - draw_w) * 0.5;
    var draw_y = y + (height - draw_h) * 0.5;

    draw_sprite_ext(sprite_index, frame, draw_x, draw_y, scale, scale, 0, c_white, 1);
} else {
    draw_set_color(hovered ? c_ltgray : c_white);
    draw_rectangle(x, y, x + width, y + height, false);
}

// Draw label text centered
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_set_color(c_white);
draw_text(x + width * 0.5, y + height * 0.5, label);

// Reset alignment
draw_set_halign(fa_left);
draw_set_valign(fa_top);