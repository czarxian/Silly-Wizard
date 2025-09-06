/// obj_flex_panel Draw Event

draw_sprite(background_sprite, 0, x, y);

// Optional: draw title or border
draw_set_color(c_white);
draw_rectangle(x, y, x + width, y + height, false);