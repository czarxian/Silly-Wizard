/// @description Insert description here
// You can write your code in this editor

//draw button sprite
	draw_self();

//draw button text
	draw_set_font(fnt_button);
	draw_set_halign(fa_center);
	draw_set_valign(fa_middle);
	draw_set_color(c_ltgrey);
//	draw_text(x, y, button_text);
	draw_text_transformed(x, y, button_text,button_scale,button_scale,0)