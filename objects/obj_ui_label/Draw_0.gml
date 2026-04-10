// obj_ui_label — Draw Event
draw_set_font(label_font);
draw_set_colour(label_colour);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
var _cx = x + sprite_get_width(sprite_index) * image_xscale * 0.5;
var _cy = y + sprite_get_height(sprite_index) * image_yscale * 0.5;
draw_text(_cx, _cy, label_text);
draw_set_colour(c_white);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
