// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

function truncate(input_string, length, suffix_string){
	if (string_length(input_string) > length) {
		return(string_copy(input_string, 1, length)+suffix_string);
	}
	else return(input_string);
}

function ui_auto_size_to_sprite(inst) {
    if (sprite_exists(inst.sprite_index)) {
        inst.width  = sprite_get_width(inst.sprite_index);
        inst.height = sprite_get_height(inst.sprite_index);
    }
}


function ui_add_child(parent_inst, child_inst) {
    if (instance_exists(parent_inst) && instance_exists(child_inst)) {
        if (!is_array(parent_inst.children)) {
            parent_inst.children = [];
        }
        array_push(parent_inst.children, child_inst);
    }
}

function get_button_sprite(style_id) {
    switch (style_id) {
        case "menu":     return spr_button_main_menu;
        case "settings": return spr_button_settings;
        case "round":    return spr_button_round;
        case "plus":     return spr_button_plus;
        case "minus":    return spr_button_minus;
        case "long":     return spr_button_long;
        default:         return spr_button_main_menu;
    }
}