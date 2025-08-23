// Ensure global panel list exists
if (!variable_global_exists("panel_list")) {
    global.panel_list = [];
}

// UI surface setup
ui_surface = -1;
ui_surface_needs_redraw = true;
