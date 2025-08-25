/// draw_panel()
var _cursor_x = x + padding;
var _cursor_y = y + padding;

for (var i = 0; i < array_length(children); i++) {
    var child = children[i];

    if (!instance_exists(child)) continue;

    // Apply origin offsets so visual + click area match
    var spr_xoff = sprite_get_xoffset(child.sprite_index);
    var spr_yoff = sprite_get_yoffset(child.sprite_index);

    child.x = _cursor_x + spr_xoff;
    child.y = _cursor_y + spr_yoff;

    // Draw the child
    with (child) {
        draw_self();
    }

    // Advance cursor based on layout direction
    if (layout_dir == UI_LAYOUT_VERTICAL) {
        _cursor_y += child.button_height + spacing;
    } else { // horizontal
        _cursor_x += child.button_width + spacing;
    }
}
