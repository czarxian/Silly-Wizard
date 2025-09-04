/// @desc Layout-aware, responsive container for UI elements (with min/max constraints)
/// @param _x           Anchor X position
/// @param _y           Anchor Y position
/// @param _layout_type "vertical" or "horizontal"
/// @param _align_x     0 = left, 0.5 = center, 1 = right
/// @param _align_y     0 = top, 0.5 = middle, 1 = bottom
/// @param _padding     Outer padding (px)
/// @param _spacing     Space between children (px)
/// @param _fixed_w     Fixed panel width (px) or noone for auto
/// @param _fixed_h     Fixed panel height (px) or noone for auto
/// @param _min_w       Min panel width (px) or noone
/// @param _max_w       Max panel width (px) or noone
/// @param _min_h       Min panel height (px) or noone
/// @param _max_h       Max panel height (px) or noone
function UIFlexPanel(
    _x, _y,
    _layout_type,
    _align_x, _align_y,
    _padding, _spacing,
    _fixed_w = noone, _fixed_h = noone,
    _min_w = noone, _max_w = noone,
    _min_h = noone, _max_h = noone
) : UIElement(_x, _y, 0, 0) constructor {

    layout_type = _layout_type;
    align_x     = _align_x;
    align_y     = _align_y;
    padding     = _padding;
    spacing     = _spacing;
    fixed_w     = _fixed_w;
    fixed_h     = _fixed_h;
    min_w       = _min_w;
    max_w       = _max_w;
    min_h       = _min_h;
    max_h       = _max_h;
    children    = [];

    AddChild = function(child) {
        array_push(children, child);
        Reflow();
    };

    Reflow = function() {
        var total_w = 0;
        var total_h = 0;

        // First pass: measure content size & resolve percentage sizing
        for (var i = 0; i < array_length(children); i++) {
            var c = children[i];

            if (fixed_w != noone && c.w > 0 && c.w <= 1) c.w = fixed_w * c.w;
            if (fixed_h != noone && c.h > 0 && c.h <= 1) c.h = fixed_h * c.h;

            if (layout_type == "vertical") {
                total_w = max(total_w, c.w);
                total_h += c.h;
                if (i < array_length(children) - 1) total_h += spacing;
            } else {
                total_h = max(total_h, c.h);
                total_w += c.w;
                if (i < array_length(children) - 1) total_w += spacing;
            }
        }

        // Base panel size
        w = (fixed_w != noone) ? fixed_w : total_w + padding * 2;
        h = (fixed_h != noone) ? fixed_h : total_h + padding * 2;

        // Apply min/max constraints to panel
        if (min_w != noone) w = max(w, min_w);
        if (max_w != noone) w = min(w, max_w);
        if (min_h != noone) h = max(h, min_h);
        if (max_h != noone) h = min(h, max_h);

        // Offset for panel alignment
        var offset_x = -(w * align_x);
        var offset_y = -(h * align_y);

        // Second pass: position children with alignment
        var current_x = x + padding + offset_x;
        var current_y = y + padding + offset_y;

        for (var i = 0; i < array_length(children); i++) {
            var c = children[i];

            if (layout_type == "vertical") {
                // Keep children within min/max of panel’s inner width
                var child_w = clamp(c.w, 0, w - padding * 2);
                var child_offset_x = (w - padding * 2 - child_w) * align_x;
                c.x = x + padding + offset_x + child_offset_x;
                c.y = current_y;
                c.w = child_w;

                current_y += c.h + spacing;
            } else {
                var child_h = clamp(c.h, 0, h - padding * 2);
                var child_offset_y = (h - padding * 2 - child_h) * align_y;
                c.x = current_x;
                c.y = y + padding + offset_y + child_offset_y;
                c.h = child_h;

                current_x += c.w + spacing;
            }
        }
    };

    Draw = function() {
        draw_set_color(c_dkgray);
        draw_rectangle(
            x - w * align_x, y - h * align_y,
            x - w * align_x + w, y - h * align_y + h, false
        );


		show_debug_message("Children count: " + string(array_length(children)));
        for (var i = 0; i < array_length(children); i++) {
            children[i].Draw();
        }
    };

    HandleMouse = function(mx, my) {
        for (var i = array_length(children) - 1; i >= 0; i--) {
            if (children[i].HandleMouse(mx, my)) return true;
        }
        return false;
    };
}