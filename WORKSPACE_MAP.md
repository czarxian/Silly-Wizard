# WORKSPACE_MAP.md

**Purpose:** Short, navigable map of the project to help contributors understand the current architecture and where to look for functionality.

---

## Project overview (current state)

- **What it does today:** The game loads tune data (JSON/CSV) and plays scheduled MIDI events. Playback events are sent via Giavapps MIDI. The UI uses GameMaker layers and a set of UI objects (buttons, fields) to control playback and settings.

- **Current workflow:** The game starts in `Room_main_menu` with `main_menu_layer` visible. From there:
  - **Play** navigates to `Room_play` and starts playback.
  - **Settings** lets the user pick MIDI input/output devices (via `scr_button_scripts` and `scr_MIDI` helpers).
  - **Tune** opens the tune picker; visible rows are populated from `global.tune_library` and the selection is stored in `global.tune_selection`. Pressing the tune OK button triggers `scr_tune_load_json()` and the build → start playback flow.

- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order`
- **Major folders:**
  - `scripts/` — game logic scripts (UI, tune loading, midi, etc.)
  - `objects/` — GameMaker objects with events and instance scripts
  - `roomui/` — UI layouts and layers (in-game windows)
  - `datafiles/` — external content (`tunes/` JSON/CSV files)
  - `extensions/` — third-party integrations (`GiavappsMIDI`)

---

---

## Important Architectural Constraints

⚠️ **No GameMaker data structures (ds_maps, ds_lists, ds_grids, etc.)**
- Use **structs** for key-value lookup and complex data
- Use **arrays** for sequences and lists
- Avoid all `ds_*` functions — they introduce unnecessary memory management overhead and complexity
- This keeps code simpler, more predictable, and easier to debug

---

## Key scripts (current responsibilities)

- **`scripts/scr_button_scripts/`** — UI button dispatcher and handlers (window toggles, settings changes, tune OK, start play).
- **`scripts/scr_MIDI/`** — MIDI device scanning/opening and message utilities; processes input messages and provides helper functions for playback.
- **`scripts/scr_tune_library/`** — Loads `tunes/tune_library.json` and populates tune picker rows.
- **`scripts/scr_tune_load/`** — Loads and validates tune JSON files into the `obj_tune` instance.
- **`scripts/scr_tune_scripts/`** — Merges tune events and metronome events, starts playback using a `time_source`, and implements the playback callback `script_tune_callback()` that sends MIDI and logs events.
- **`scripts/scr_event_log/`** — Event history logging system. Tracks all playback events (timing, note, source) for analysis. Exports to CSV for performance debugging and player feedback.
- **`scripts/scr_UI_scripts/`** — UI layer helpers (`GetLayerNameFromIndex`, `scr_update_fields`, `scr_ui_refresh`).

---

## Playback Callback Flow (Detailed)

This describes how a tune is triggered and how events flow through the system:

### 1. **User Action → Button Press**
- User clicks "Play" button in tune picker or main menu
- Button handler calls function from `scr_button_scripts.gml`

### 2. **Tune Selection & Loading**
- Button handler → `scr_tune_load_json()` (from `scr_tune_load.gml`)
- Loads tune JSON file and validates structure
- Populates `obj_tune.tune_data` with `tune_metadata`, `performance`, and `events[]`

### 3. **Preprocessing**
- `scr_preprocess_tune()` (from `scr_preprocess_tune.gml`)
- Converts tune JSON events into a playable MIDI event array
- Each event includes: `time_ms`, `type` ("note_on"/"note_off"), `note` (MIDI), `velocity`, `channel`
- Handles embellishment expansion, gracenote timing, and unit-to-millisecond conversion

### 4. **Playback Start**
- `tune_start()` (from `scr_tune_scripts.gml`)
- Creates a `time_source` that fires at millisecond intervals
- Iterates through the preprocessed playable events array
- **Callback function:** `script_tune_callback()` fires whenever an event's `time_ms` is reached

### 5. **Event Playback & Logging**
- `script_tune_callback()` executes:
  1. Sends MIDI note via `midi_output_message_send_short()` (Giavapps MIDI)
  2. Updates display: `obj_currentnote_field_1.note_text = letter` 
  3. **Logs event to history:** `event_history_add()` (from `scr_event_log.gml`)
  
### 6. **Event History Storage**
- `event_history_add()` logs the event with:
  - Timing data: `expected_time_ms`, `actual_time_ms`, `delta_ms`
  - Beat context: `measure`, `beat`, `beat_fraction` (0 for now, populated when metronome added)
  - Event data: `event_type`, `source` ("game"), `note_midi`, `note_letter`, etc.
  - Context: `tune_name`, `is_embellishment`, etc.
  
### 7. **Analysis & Export**
- After playback ends, user can export history:
  - `event_history_export_csv("tune_name")` 
  - Generates `datafiles/event_history_tune_name.csv`
  - Columns include timing, beat, MIDI notes, and quality metrics
  - Import into Excel for analysis

### 8. **Player Input & Metronome Context**
- Player MIDI input logging remains an active enhancement target (`source: "player"`, actual timing from input device)
- Metronome generation is currently implemented and contributes beat/measure marker context during playback
- CSV/export analysis is designed to compare expected/game/player timing as player-input logging expands

---

## Core controller objects (current state)

- **`obj_game_controller`**
  - Location: `objects/obj_game_controller/Create_0.gml`
  - Role: Initializes global IDs and MIDI/game defaults (calls `old_scr_tune_library()` on create). Holds `global.*` vars used across the app.

- **`obj_player`**
  - Location: `objects/obj_player/Create_0.gml`
  - Role: Tracks live player input state (note on/off arrays, current note) used by UI and logging.

- **`obj_tune`**
  - Location: `objects/obj_tune/Create_0.gml`
  - Role: Data model instance for the currently loaded tune (`tune_metadata`, `events[]`, `event_count`, `filename`, `is_loaded`). Populated by `scr_tune_load_json()`.

- **`obj_tune_picker`**
  - Location: `objects/obj_tune_picker/Create_0.gml`
  - Role: Tune picker UI controller; maintains `selected_index` and references the library used to populate rows.

- **`obj_ui_controller`**
  - Location: `objects/obj_ui_controller/Create_0.gml`
  - Role: Registers UI layers, assets and fields (`global.ui_layer_names`, `global.ui_assets`, `global.ui_fields`) and holds basic tune library defaults used by the UI.

> Short notes about ongoing improvements are tracked in `PROJECT_PLAN.md` (stable documentation and design proposals live there).

---

## UI architecture (current state)

- **UI Layers:** `main_menu_layer`, `settings_window_layer`, `tune_window_layer` (each layer contains backgrounds, flex panels and instances such as buttons and fields).
- **Flex panels:** Used for layout and row stacking in tune window and other panels.
- **UI Script Flow:** `scripts/scr_button_scripts/` centralizes button actions and toggles windows; it calls `scr_ui_refresh()` / `scr_update_fields()` as needed.

---

## UI system details (how it works)

This section documents the concrete runtime UI architecture and how UI instances are configured and wired together.

### Base UI objects
- `obj_UI_parent` — Base class for all UI instances.
  - Registers every instance in `global.ui_assets` during Create (stores pairs `[ui_num, id]` indexed by layer number). This allows `scr_ui_refresh()` to repair or re-link instances if IDs change.
  - Stores `ui_name`, `ui_layer`, `ui_layer_num`, `ui_group`, `ui_num` and common visual properties (`ui_sprite`, `ui_sprite_frame`).
- `obj_btn_base` — Button base object (inherits `obj_UI_parent`).
  - Key properties: `button_ID`, `button_label`, `button_target`, `button_click_value`, `button_script_index`.
  - Mouse click calls `scr_handle_button_click(self.button_script_index)` (see `scripts/scr_button_scripts/`) so the button's `button_script_index` drives which action runs. `button_target` and `button_click_value` are used by handlers (e.g., `scr_checkbox_click`, `scr_open_window`, or settings handlers).
- `obj_field_base` — Field / text label (inherits `obj_UI_parent`).
  - Key properties: `field_ID`, `field_target`, `field_value`, `field_contents`.
  - `scr_update_fields(_layer)` reads `field_target` (string name or array) and updates `field_contents` from `field_value`.

### Registration & refresh
- Instances are placed manually in the Room UI (`roomui/RoomUI/RoomUI.yy`). The Create event of `obj_UI_parent` registers each instance into `global.ui_assets[layer_num]` as `[ui_num, id]`.
- `scr_ui_refresh(layer)` inspects `global.ui_assets[layer]` and if an ID is missing, it finds a matching `obj_UI_parent` with the same `ui_num` and re-links the pair.

### Buttons & interactions
- Buttons are fully configured in the Room UI editor by overriding properties on instances (see `RoomUI.yy` for examples). Typical configuration sets `button_script_index` and `button_click_value` (and sometimes `button_target`).
- `scr_handle_button_click(index)` maps indices to high-level actions (open window, start play, save settings, etc.). Handlers use `self` (the button instance) to read `button_target` / `button_click_value` where needed.
- Checkboxes are `obj_btn_check` + `scr_checkbox_click()` which sets global state (e.g., `global.tune_selection`) and unchecks other boxes as needed using `scr_uncheck_all()`.

### Fields & dynamic text
- Fields use `field_target` to reference either a global array (like `tune_library`) or a global variable name (string). `scr_update_fields()` pulls the value and fills `field_contents` to change the visible label.
- Fields also have `field_script_index` to allow scripted actions when interacted with.

### Tune picker specifics (tune_window_layer)
- The tune window contains six manual rows `fp_tune_row_1..fp_tune_row_6`. Each row contains:
  - `obj_btn_check` instances (radio/checkbox) with `button_script_index` set to the checkbox handler and `button_click_value` equal to the row index (used to set `global.tune_selection`).
  - `obj_field_base` instances with `field_target` set to `tune_library` and `field_value` set to the index; `scr_tune_picker_populate()` (in `scr_tune_library/`) updates the visible rows and associated text when a library is loaded.

  Note: The population routine **pairs** each field and checkbox **preferentially by explicit editor-assigned IDs** (use `field_ID` on fields and `button_ID` on checkboxes — e.g., 1..10). If those are not set it falls back to `ui_num` (the runtime registration number), and as a last resort it pairs by on-screen order (sorted by Y). This lets you safely add rows (7–10) and control their mapping via the `field_ID`/`button_ID` properties.
- The `obj_tune_ok_button` calls `scr_handle_button_click` with its `button_script_index` (mapped to `scr_tune_OK`) which loads the selected tune and initiates build→start playback flow.

### Per-layer summaries (current content)
Below are the actual UI layers and the important instances placed on each (based on `roomui/RoomUI/RoomUI.yy`). All instances are manually placed in the Room UI editor and configured by overriding object properties there.

- `settings_window_layer` — Settings window
  - Title: `fp_Title_text` (text "Settings").
  - Close: `obj_settings_win_close_button` (instance of `obj_btn_winClose`, often with `button_ID = 3`).
  - MIDI In row: `setting_Lbutton_1` (left arrow `obj_btn_fieldL`), `setting_field_1` (`obj_field_base`) — field for MIDI IN device.
  - MIDI Out row: `setting_Lbutton_2`/`setting_Rbutton_2`, `setting_field_2` (`obj_field_base`) — field for MIDI OUT device.
  - OK: `obj_setting_ok_button` (`obj_btn_main`) — typically configured to run the settings OK handler (`scr_settings_OK`).

- `tune_window_layer` — Tune picker window
  - Title: `fp_Title_text` (text "Tune Library").
  - Close: `obj_tune_win_close_button` (`obj_btn_winClose`).
  - Tune rows (1..6): each row has a checkbox and a field:
    - `obj_tune_checkbox_1..obj_tune_checkbox_6` (instances of `obj_btn_check`) — configured with `button_script_index = 2` (checkbox handler), `button_target = global.tune_selection`, and `button_click_value = row index`.
    - `obj_tune_field_1..obj_tune_field_6` (instances of `obj_field_base`) — set with `field_target = tune_library` and `field_value = row index`; populated at runtime by `scr_tune_picker_populate()`.
  - OK: `obj_tune_ok_button` (`obj_btn_main`) — typically configured to `scr_tune_OK()` (loads the selected tune).

- `gameinfo_window_layer` — Informational window
  - Title field: `obj_gameinfo_win_title` (`obj_field_base`) — shows selected tune or status (default: "No tune selected").
  - Back / OK buttons: `obj_gameinfo_back_button`, `obj_gameinfo_ok_button` (`obj_btn_main`) with appropriate `button_script_index` values for navigation.

- `current_note_layer` — Current note display
  - `obj_currentnote_field_1` (`obj_field_base`) — updated at runtime by `script_tune_callback()` to show the currently played note.

- `main_menu_layer` — Main menu
  - Buttons: `obj_button_play` (`obj_btn_main`, `button_script_index = 1`), `obj_button_settings` (`obj_btn_main`, `button_script_index = 3`, `button_target = settings_window_layer`), `obj_button_tune` (`obj_btn_main`, `button_script_index = 3`, `button_target = tune_window_layer`), plus exit/back buttons.

> Note: For all UI instances the important configuration is done in the Room UI editor via overridden properties (e.g., `button_script_index`, `button_target`, `field_target`, `field_value`). `obj_UI_parent` registers each instance into `global.ui_assets` so scripts can refresh or re-link instances at runtime.


---

If you'd like, I can also:
- Add a short example for how to configure a new UI instance (a checklist with the minimal overridden properties to set in `RoomUI`), or
- Generate a per-object 
---

## Tune subsystem (current state)

### File Organization
- **Source:** `datafiles/tunes/` contains tune JSON files (e.g., `Jig_of_Slurs.json`, `Scotland_the_Brave.json`).
- **Runtime:** Files must be marked as **Included Files** in the GameMaker project so they're copied to the runtime directory (`tunes/` at game runtime, not `datafiles/tunes/`).

### Library Building & Loading
- **Build process:** `scr_build_tune_library(_folder)` scans a folder recursively for `*.json` files (excluding `tune_library.json` itself), parses tune metadata, and writes an index file `tune_library.json` containing all discovered tunes.
  - Called automatically from `obj_game_controller` Create event on startup.
  - Also callable manually via button case 12 (regenerate button in settings panel) for debugging/testing.
  - Handles multiple tune JSON formats: flat structure (`{"tune": {...}}`) or array-only (`[...]`).
  - Skips empty files and logs warnings for invalid JSON (uses try-catch for robustness).
  
- **Library loading:** `scr_tune_picker_populate()` reads the generated `tune_library.json` index and populates the UI rows with tune titles, composers, and rhythms for the picker.

### Tune JSON Format
Each tune file should have a flat structure with `"tune"` at the root:
```json
{
  "tune": {
    "title": "Scotland the Brave",
    "composer": "trad.",
    "rhythm": "March",
    "reference number": "1",
    ...metadata fields...
  },
  "metronome": { ... },
  "performance": { ... },
  "info": { ... },
  "events": [ ... ]
}
```
The nested `"metadata"` wrapper structure is **not supported** and will cause the tune to be skipped.

### Tune Loader
- `scr_tune_load_json(_filename)` parses a tune JSON file and populates the `obj_tune` instance with metadata, events, and state flags.

### Playback
- `tune_build_events()` prepares events for scheduling.
- `tune_start()` initiates playback using a GameMaker `time_source`.
- `script_tune_callback()` is the playback callback that sends MIDI events at runtime.

### UI Integration
- `roomui/RoomUI/` provides the tune picker window with up to 10 rows.
- `scr_tune_picker_populate()` populates the UI rows from `global.tune_library`.

### Debugging
- Use the **Regenerate Tune Library button** (button case 12, placed in settings panel) to manually trigger library rebuild and see debug output like:
  ```
  scr_build_tune_library: wrote tunes/tune_library.json (2 tunes)
  ```
  This helps isolate timing and scope of the build process without restarting the game.

---

## Playback preprocessing (note)
- A playback preprocessing / "play array" design exists in `PROJECT_PLAN.md`. That file contains design notes and implementation suggestions for normalizing and optimizing event lists for runtime use.

---

## MIDI & extensions
- `extensions/GiavappsMIDI/` provides MIDI utilities used by playback and input code.
- MIDI device selection is exposed through the settings UI and tracked in global variables (e.g., `global.midi_input_device`, `global.midi_output_device`).

---

## Other systems
- UI components live under `objects/obj_btn_*`, `objects/obj_field_base`, `objects/obj_UI_parent`.
- Main rooms: `rooms/Room_main_menu`, `rooms/Room_play`.

---

## Known issues (current)
- **Path resolution:** At runtime, GameMaker uses a temp directory as the working directory (e.g., `C:\Users\...\GMS2TEMP\Silly-Wizard_*_VM\tunes\`). Tune files must be included as **Included Files** and the scanner must point to the correct runtime path (`tunes/`, not `datafiles/tunes/`).

---

*Created by GitHub Copilot (Raptor mini (Preview)).*
