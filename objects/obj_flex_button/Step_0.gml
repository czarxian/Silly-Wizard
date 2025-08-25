//obj_flex_button
//Step Event

var _x1 = x - sprite_get_xoffset(sprite_index);
var _y1 = y - sprite_get_yoffset(sprite_index);
var _x2 = _x1 + button_width;
var _y2 = _y1 + button_height;

hovered = point_in_rectangle(mx, my, _x1, _y1, _x2, _y2);

if (hovered) image_index = 1; else image_index = 0;


if (hovered && mouse_check_button_pressed(mb_left)) {
    clicked = true;
    if (is_callable(button_script)) {
        script_execute(button_script);
    }
} else {
    clicked = false;
}


