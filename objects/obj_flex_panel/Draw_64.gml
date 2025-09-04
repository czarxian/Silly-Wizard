/// @desc Draw panel with optional sprite (preserve aspect ratio), then children

if (sprite_index != -1) {
    var sw = sprite_width;
    var sh = sprite_height;
    var scale = min(width / sw, height / sh);
    var draw_w = sw * scale;
    var draw_h = sh * scale;
    var draw_x = x + (width - draw_w) * 0.5;
    var draw_y = y + (height - draw_h) * 0.5;

    draw_sprite_ext(sprite_index, 0, draw_x, draw_y, scale, scale, 0, c_white, 1);
}

// Draw children
var len = array_length(children);
for (var i = 0; i < len; i++) {
    var child = children[i];
    if (instance_exists(child)) {
        with (child) event_perform(ev_draw, ev_draw_gui);
    }
}