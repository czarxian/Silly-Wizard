//obj_flex_button
//Step Event

hovered = point_in_rectangle(mx, my, x - sprite_xoffset, y - sprite_yoffset, x - sprite_xoffset + button_width, y - sprite_yoffset + button_height);

if (hovered) {
    if (mouse_check_button(mb_left)) {
        image_index = 2; // click
        clicked = true;
    } else {
        image_index = 1; // hover
    }
} else {
    image_index = 0;
    clicked = false;
}

if (hovered && mouse_check_button_pressed(mb_left)) {
    if (is_callable(button_script)) {
        script_execute(button_script, button_script_number);
    }
}
