
if (!global.ui_manager_draws) exit;

if (background_sprite != -1) {
    draw_sprite(background_sprite, 0, x, y);
} else {
    draw_set_color(c_dkgray);
    draw_rectangle(x, y, x + width, y + height, false);
}



