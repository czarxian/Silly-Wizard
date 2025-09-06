
//debug
show_debug_message("UI Manager sees " + string(array_length(global.ui_elements)) + " elements.");
//end debug

/// obj_UI_manager Draw GUI Event
global.ui_manager_draws = true;

// Sort by z_index ascending (lower draws first)
if (is_array(global.ui_elements)) {
    global.ui_elements = array_sort(global.ui_elements, function(a, b) {
        if (!instance_exists(a)) return false;
        if (!instance_exists(b)) return true;
        return a.z_index < b.z_index;
    });
} else {
//    show_debug_message("global.ui_elements is not an array!");
}


// Draw in sorted order
for (var i = 0; i < array_length(global.ui_elements); i++) {
    var inst = global.ui_elements[i];
    if (instance_exists(inst)) {
        with (inst) {
            event_perform(ev_draw, 64);
        }
    }
}

global.ui_manager_draws = false;




//for (var i = 0; i < array_length(global.ui_elements); i++) {
//    var inst = global.ui_elements[i];
//    if (instance_exists(inst)) {
//        with (inst) {
//			// Draw GUI is a Draw sub-event: 64
//			event_perform(ev_draw, 64);
//
//        }
//    }
//}
//global.ui_manager_draws = false;

