function draw_panel() {
    var x_cursor = x + padding;
    var y_cursor = y + padding;

    for (var i = 0; i < array_length(children); i++) {
        var child = children[i];
        if (!instance_exists(child)) continue;

        // Position child relative to panel
        child.x = x_cursor;
        child.y = y_cursor;

        // Draw child with label
        ui_draw_element(child, child.label, c_white);

        // Advance cursor
        if (layout_type == "vertical") {
            y_cursor += child.button_height + spacing;
        } else if (layout_type == "horizontal") {
            x_cursor += child.button_width + spacing;
        }
    }
}
