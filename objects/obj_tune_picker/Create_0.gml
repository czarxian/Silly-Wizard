// obj_tune_picker — Tune selection UI controller
// Purpose: Manages tune selection UI, holds current selection index and references to the tune library.
// Key responsibilities:
//  - Registers global.tune_picker
//  - Tracks selected_index and exposes library for UI rows
// Related scripts: scripts/scr_tune_library/ (scr_tune_picker_populate), scripts/scr_button_scripts/ (scr_tune_OK)

/// obj_tune_picker Create

global.tune_picker=id;

//library = scr_load_tune_library();
selected_index = -1;