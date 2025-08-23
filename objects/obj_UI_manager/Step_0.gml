// Get mouse position in GUI space once per frame
var _mx = device_mouse_x_to_gui(0);
var _my = device_mouse_y_to_gui(0);

// Pass to all panels
for (var i = 0; i < array_length(global.panel_list); i++) {
    var panel = global.panel_list[i];
    if (instance_exists(panel)) {
        panel.mx = _mx;
        panel.my = _my;
    }
}
