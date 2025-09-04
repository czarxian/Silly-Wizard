/// @desc Base UI element class
function UIElement(_x, _y, _w, _h) constructor {
    // Position and size
    x = _x;
    y = _y;
    w = _w;
    h = _h;

    // State
    visible = true;
    active  = true;

    // Virtual methods (override in child constructors)
    Draw = function() { };

    HandleMouse = function(mx, my) {
        return false;
    };

    // Helper for hit‑testing
    Contains = function(mx, my) {
        return mx >= x && mx <= x + w &&
               my >= y && my <= y + h;
    };
}