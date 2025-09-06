
//debug
show_debug_message("UI Manager sees " + string(array_length(global.ui_elements)) + " elements.");
//end debug


/// obj_UI_manager Draw GUI Event
global.ui_manager_draws = true;

for (var i = 0; i < array_length(global.ui_elements); i++) {
    var inst = global.ui_elements[i];
    if (instance_exists(inst)) {
        with (inst) {
			// Draw GUI is a Draw sub-event: 64
			event_perform(ev_draw, 64);

        }
    }
}
global.ui_manager_draws = false;

