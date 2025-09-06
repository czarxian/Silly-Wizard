//obj_flex_button
/// @desc Initialize button properties
label       = "";
callback    = noone;       // Function to call when clicked
sprite_index = -1;         // Button sprite (3 frames: normal=0, hover=1, pressed=2)
hovered     = false;
selected    = false;

// Default size — will be overridden by ui_auto_size_to_sprite()
width  = 100;
height = 40;
