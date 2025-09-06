/// obj_flex_panel Create Event

width  = 300;
height = 200;
padding = 8;
spacing = 4;

panel_role = "menu"; // or "settings", "modal"
background_sprite = spr_panel_bg;

clickable = false; // Panels don’t receive direct input
hovered = false;

// Register with UI manager for draw batching
array_push(global.ui_elements, id);