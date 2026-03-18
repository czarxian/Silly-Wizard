// Update current note display if this is the current note field
// Check by object name/id
var ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
    ui_name_value = string(variable_instance_get(id, "ui_name"));
}

if (ui_name_value == "timeline_canvas_anchor") {
    gv_timeline_step_tick();
}

if (variable_global_exists("current_note_display")) {
    var current_note_obj = asset_get_index("obj_currentnote_field_1");
    if (current_note_obj != -1 && instance_exists(current_note_obj)) {
        var current_note_inst = instance_find(current_note_obj, 0);
        if (current_note_inst != noone && id == current_note_inst.id) {
            field_contents = global.current_note_display;
        }
    }
}
