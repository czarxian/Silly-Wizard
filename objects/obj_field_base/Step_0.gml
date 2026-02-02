// Update current note display if this is the current note field
// Check by object name/id
if (variable_global_exists("current_note_display") && instance_exists(obj_currentnote_field_1)) {
    if (id == obj_currentnote_field_1.id) {
        field_contents = global.current_note_display;
    }
}
