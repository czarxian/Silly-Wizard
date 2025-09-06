/// obj_flex_button Draw Event

draw_sprite(sprite_index, 0, x, y);

if (hovered) {
    draw_set_alpha(0.2);
    draw_rectangle(x, y, x + width, y + height, false);
    draw_set_alpha(1);
}

draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_text(x + width / 2, y + height / 2, label);