/// @desc Clickable UI button with sprite states
/// @param _x         X position (set by panel)
/// @param _y         Y position (set by panel)
/// @param _w         Width  (can be % if used in UIFlexPanel)
/// @param _h         Height (pixels)
/// @param _label     Text label
/// @param _callback  Function to call when clicked
/// @param _sprite    Sprite asset for button (3 frames: normal=0, hover=1, pressed=2)
function UIButton(_x, _y, _w, _h, _label, _callback, _sprite) : UIElement(_x, _y, _w, _h) constructor {
    
    // Properties
    label      = _label;
    callback   = _callback;
    button_spr = _sprite; // store sprite reference here

    Draw = function() {
        var hovered = Contains(global.ui_mouse_x, global.ui_mouse_y);
        var pressed = hovered && mouse_check_button(mb_left);

        // Select sprite frame based on state
        var frame = 0;
        if (pressed) {
            frame = 2;
        } else if (hovered) {
            frame = 1;
        }

        // Draw button sprite stretched to current size
        draw_sprite_stretched(button_spr, frame, x, y, w, h);

        // Draw text centered on button
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(x + w * 0.5, y + h * 0.5, label);

        // Reset alignment
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    };

    HandleMouse = function(mx, my) {
        if (Contains(mx, my) && mouse_check_button_pressed(mb_left)) {
            if (is_callable(callback)) callback();
            return true;
        }
        return false;
    };
}