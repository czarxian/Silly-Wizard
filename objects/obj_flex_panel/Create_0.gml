/// @desc Initialize flex panel properties
layout_type = "vertical"; // or "horizontal"
align_x     = 0;          // 0 = left, 0.5 = center, 1 = right
align_y     = 0;          // 0 = top, 0.5 = middle, 1 = bottom
padding     = 0;
spacing     = 0;

width  = 100;
height = 100;

children = [];            // Array of child UI elements
sprite_index = -1;        // Optional background sprite

// Optional min/max constraints
min_width  = noone;
max_width  = noone;
min_height = noone;
max_height = noone;