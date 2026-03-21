var ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
    ui_name_value = string(variable_instance_get(id, "ui_name"));
}

if (ui_name_value == "timeline_canvas_anchor") {
    gv_timeline_step_tick();
}
