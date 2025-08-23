///obj_flex_panel Step Event

// Pass stored mouse position to children
for (var i = 0; i < array_length(children); i++) {
    var child = children[i];
    if (instance_exists(child)) {
        child.mx = mx;
        child.my = my;
        child.panel_redraw_needed = true;
    }
}


