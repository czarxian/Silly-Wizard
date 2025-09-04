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