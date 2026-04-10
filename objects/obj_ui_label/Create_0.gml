// obj_ui_label — Create Event
// Inherits ui_name, ui_num, ui_layer_num registration from obj_UI_parent.
event_inherited();
sprite_index = blank; // parent sets sprite_index = ui_sprite (noone) — restore ours

// Self-register into global.ui_text_refs keyed by ui_name
if (!variable_global_exists("ui_text_refs")) {
    global.ui_text_refs = {};
}
global.ui_text_refs[$ string(ui_name)] = id;
