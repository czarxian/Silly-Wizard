/// @description Insert description here
// You can write your code in this editor

//draw button sprite
	draw_self();

//draw button text
	draw_set_font(fnt_button);
	draw_set_halign(fa_left);
	draw_set_valign(fa_middle);
	draw_set_color(c_ltgrey);

	draw_text_transformed(title_x, title_y, window_title_text,window_title_scale, window_title_scale, 0);
