// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

function truncate(input_string, length, suffix_string){
	if (string_length(input_string) > length) {
		return(string_copy(input_string, 1, length)+suffix_string);
	}
	else return(input_string);
}



/// @function ui_draw_element(inst, text, [text_col])
/// @desc Draws a sprite + centered text for any sprite-based UI element.
/// @param inst      The instance to draw (must have sprite_index set)
/// @param text      String to draw centered on the sprite
/// @param [text_col]Optional color for text (defaults to c_white)
function ui_draw_element(_inst, _txt, _col)
{
    if (!instance_exists(_inst)) return;

    // Sprite dimensions + origin adjustments
    var sw = sprite_get_width(_inst.sprite_index) * _inst.image_xscale;
    var sh = sprite_get_height(_inst.sprite_index) * _inst.image_yscale;
    var xo = sprite_get_xoffset(_inst.sprite_index) * _inst.image_xscale;
    var yo = sprite_get_yoffset(_inst.sprite_index) * _inst.image_yscale;

    // --- 1. Draw sprite ---
    draw_sprite_ext(
        _inst.sprite_index,
        _inst.image_index,
        _inst.x,
        _inst.y,
        _inst.image_xscale,
        _inst.image_yscale,
        _inst.image_angle,
        c_white,
        1
    );

    // --- 2. Draw text centered on sprite's visual bounds ---
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_color(argument_count > 2 ? _col : c_white);
	draw_set_alpha(1);

    draw_text(
        _inst.x - xo + sw / 2,
        _inst.y - yo + sh / 2,
        _txt
    );
}

//Flex Panel script
function ui_clear_panels() {
    for (var i = 0; i < array_length(global.panel_list); i++) {
        var panel = global.panel_list[i];
        if (instance_exists(panel)) {
            instance_destroy(panel);
        }
    }
    global.panel_list = [];
}
