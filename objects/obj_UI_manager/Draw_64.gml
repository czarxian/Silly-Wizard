// Debug: show number of panels
show_debug_message("UI Manager Draw GUI running; panels = " + string(array_length(global.panel_list)));

// Ensure surface exists at GUI size
if (ui_surface == -1 || surface_get_width(ui_surface) != display_get_gui_width()) {
    if (surface_exists(ui_surface)) surface_free(ui_surface);
    ui_surface = surface_create(display_get_gui_width(), display_get_gui_height());
    ui_surface_needs_redraw = true;
}

// Only redraw when needed
if (ui_surface_needs_redraw) {
    surface_set_target(ui_surface);
    draw_clear_alpha(c_black, 0);

    // Let each panel draw itself
    for (var i = 0; i < array_length(global.panel_list); i++) {
        var panel = global.panel_list[i];
        if (instance_exists(panel)) {
            with (panel) {
                if (function_exists(draw_panel)) {
                    draw_panel();
                } else {
                    draw_self();
                }
            }
        }
    }

    surface_reset_target();
    ui_surface_needs_redraw = false;
}

// Present UI surface
if (surface_exists(ui_surface)) {
    draw_surface(ui_surface, 0, 0);
}
