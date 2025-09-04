//UI_Manager Step event
global.ui_mouse_x = device_mouse_x_to_gui(0);
global.ui_mouse_y = device_mouse_y_to_gui(0);

for (var i = array_length(global.ui_elements) - 1; i >= 0; i--) {
    global.ui_elements[i].HandleMouse(global.ui_mouse_x, global.ui_mouse_y);
}

