/// --- obj_button : Create Event ---

// Display properties
button_text           = "";      // Set by create_menu_button()
button_script         = noone;   // Callback function
button_script_number  = -1;      // Menu index or ID

// Interaction state
is_hovered            = false;   // Updated by UI Manager each Step

// Visual control
image_index           = 0;       // 0=normal, 1=hover, 2=click
image_speed           = 0;       // Stop auto-animation

// Coordinate space hint
// true = button drawn in Draw GUI space (GUI coords),
// false = button drawn in room space
is_gui_space          = true;