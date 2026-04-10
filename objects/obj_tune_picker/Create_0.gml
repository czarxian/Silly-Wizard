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
selected_tune_id = "";
selected_tune_filename = "";
selected_part_channel = -1;
library = { tunes: [] };

// 2A view-model state for filtered/scrolled tune list rendering.
view_filter_rhythm = "all";
view_sort_mode = "title_asc";
view_scroll_offset = 0;
view_visible_rows = 14;
view_filtered_indices = [];
view_rhythm_options = ["all"];
view_layout = undefined;
view_row_height = 56;
view_row_gap = 6;

// Set builder state
view_mode = "tunes";            // "tunes" | "sets"
set_builder_slots = [];         // array of { filename, bpm, swing, title }
set_builder_sel_slot = -1;      // selected slot index (-1 = none)
set_name_text = "New Set";
set_name_editing = false;
set_confirm_overwrite = false;