/// obj_UI_manager Step Event

// Update mouse position
global.ui_mouse_x = device_mouse_x_to_gui(0);
global.ui_mouse_y = device_mouse_y_to_gui(0);


// Loop through all registered UI elements
for (var i = 0; i < array_length(global.ui_elements); i++) {
    var inst = global.ui_elements[i];

    // Skip invalid or destroyed instances
    if (!instance_exists(inst)) continue;

    // Check if instance is interactive
    if (inst.clickable) {
        var bounds_x1 = inst.x;
        var bounds_y1 = inst.y;
        var bounds_x2 = inst.x + inst.width;
        var bounds_y2 = inst.y + inst.height;

        var is_hovered = point_in_rectangle(global.ui_mouse_x, global.ui_mouse_y, bounds_x1, bounds_y1, bounds_x2, bounds_y2);
        inst.hovered = is_hovered;

        // Handle click
        if (is_hovered && mouse_check_button_pressed(mb_left)) {
            if (is_callable(inst.action)) {
                inst.action(); // Execute bound action
            }
        }
    }
}