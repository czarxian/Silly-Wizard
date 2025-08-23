/// @description Insert description here
// You can write your code in this editor

//draw button sprite
	draw_self();

//draw button text
	draw_set_font(fnt_button);
	draw_set_halign(fa_left);
	draw_set_valign(fa_middle);
	draw_set_color(c_ltgrey);
//	draw_text(x, y, button_text);
//	draw_text_transformed(x + label_offset_x, y + label_offset_y, field_label,field_scale,field_scale,0);
//	draw_text_transformed(x + text_offset_x, y + text_offset_y, field_text, field_scale,field_scale,0);
	draw_text_transformed(x+10, y+(sprite_height/2), field_label,.4, .4, 0);
	draw_text_transformed(x-(sprite_width/3)+10, y+(sprite_height/2), field_text, field_scale, field_scale, 0);