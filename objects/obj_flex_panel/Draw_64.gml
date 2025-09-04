/// @desc Draw panel with optional sprite, then children
// Draw background sprite if set
if (sprite_index != -1) {
    // Scale sprite to panel size
    var sx = width  / sprite_width;
    var sy = height / sprite_height;
    draw_sprite_ext(sprite_index, 0, x, y, sx, sy, 0, c_white, 1);
}

// Draw children
var len = array_length(children);
for (var i = 0; i < len; i++) {
    var child = children[i];
    if (instance_exists(child)) {
        if (is_undefined(child.draw_self)) {
            child.draw_self();
        } else {
            // If child has its own draw event, let it handle it
            with (child) event_perform(ev_draw, ev_draw_gui);
        }
    }
}