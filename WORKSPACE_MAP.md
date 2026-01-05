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

## Key scripts (current responsibilities)

- **`scripts/scr_button_scripts/`** — UI button dispatcher and handlers (window toggles, settings changes, tune OK, start play).
- **`scripts/scr_MIDI/`** — MIDI device scanning/opening and message utilities; processes input messages and provides helper functions for playback.
- **`scripts/scr_tune_library/`** — Loads `tunes/tune_library.json` and populates tune picker rows.
- **`scripts/scr_tune_load/`** — Loads and validates tune JSON files into the `obj_tune` instance.
- **`scripts/scr_tune_scripts/`** — Merges tune events and metronome events, starts playback using a `time_source`, and implements the playback callback that sends MIDI.
- **`scripts/scr_UI_scripts/`** — UI layer helpers (`GetLayerNameFromIndex`, `scr_update_fields`, `scr_ui_refresh`).

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

- **Datafiles:** `datafiles/tunes/` (e.g., `ScotlandTheBrave.json`, `ScotlandTheBrave.csv`).
- **Library loader:** `scr_load_tune_library()` reads a tune library JSON (if present) and returns its parsed structure.
- **Tune loader:** `scr_tune_load_json(_filename)` parses and validates tune JSON and stores it in the `obj_tune` instance.
- **Playback:** `tune_build_events()` and `tune_start()` prepare and schedule events; `script_tune_callback()` sends MIDI events at runtime.
- **UI integration:** `roomui/RoomUI/` provides the tune window and rows used by the picker; `scr_tune_picker_populate()` populates UI rows from the library.

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
- `tunes/tune_library.json` is expected by `scr_tune_library` but is not present in `datafiles/tunes/` (only `ScotlandTheBrave.json`/`.csv` found).

---

*Created by GitHub Copilot (Raptor mini (Preview)).*
