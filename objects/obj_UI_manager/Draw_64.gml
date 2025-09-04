//UI Manager Draw GUI Event

// Draw GUI
//for (var i = 0; i < array_length(global.ui_elements); i++) {
//    global.ui_elements[i].Draw();
//}

//debug
show_debug_message("UI Manager sees " + string(array_length(global.ui_elements)) + " elements.");
//end debug


for (var i = 0; i < array_length(global.ui_elements); i++) {
    var e = global.ui_elements[i];
    show_debug_message("Drawing: " + string(i) + " - " + string(typeof( e)));
    e.Draw();
}
