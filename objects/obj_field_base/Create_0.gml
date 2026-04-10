// Create Event
event_inherited();

//button_ID = "button"
//button_label = "button";
//button_action = noone;
//sprite_index = spr_btn_main_menu;
image_index = 0;
image_speed = 0;

if (variable_instance_exists(id, "ui_name")) {
	var anchor_name = string(variable_instance_get(id, "ui_name"));
	if (anchor_name == "timeline_canvas_anchor"
		|| anchor_name == "notebeam_canvas_anchor"
		|| anchor_name == "tunestructure_canvas_anchor"
		|| anchor_name == "gameviz_canvas_anchor"
		|| anchor_name == "gameviz_structure_anchor") {
		if (sprite_index == noone) {
			sprite_index = spr_field_item;
			mask_index = spr_field_item;
		}
	}

}

//Adding an index to allow field management, updates, etc.

	// Ensure global.ui_fields exists
	if (!is_array(global.ui_fields)) {
	    global.ui_fields = [];
	}
	
	// Expand array up to ui_layer_num
	if (array_length(global.ui_fields) <= ui_layer_num) {
	    array_resize(global.ui_fields, ui_layer_num + 1);
	}
	
	// Ensure sub-array exists
	if (!is_array(global.ui_fields[ui_layer_num])) {
	    global.ui_fields[ui_layer_num] = [];
	}

	// Assign index based on current count of fields in this layer
	field_index = array_length(global.ui_fields[ui_layer_num]);
	
	// Register into fields registry
	array_push(global.ui_fields[ui_layer_num], id);

	