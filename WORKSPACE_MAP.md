# WORKSPACE_MAP.md

**Purpose:** Create a short, navigable map of the project to help new contributors (or me) understand architecture, responsibilities and where to look for functionality.

---

## Project overview ✅

- **Project goals:** This project is a GameMaker project. It will process bagpipe tunes while a player provides MIDI input to play along with the tunes. The tunes will be loaded from JSON files, merged with multiple parts (harmonies, drums, and backing tracks). The play will create log which will be used to assess the performance. The events will trigger MIDI output (for audio), a visual music score, bars in the style of a piano roll for gameplay, and an event log to allow analysis. The ultimate thing that will be played will combine a tune, multiple parts (drums, harmonies), a metronome with configurable click patterns, a lead in, a leading drum roll and possibly others.

Tunes will come from ABC. I have an Excel sheet which imports the ABC, allows human editing, and creates a JSON. The structure is event driven. Each note is an event, embellishments are events. Some structural things are events. These will be used to create a MIDI style event roster that would include Note_on and Note_off, etc.    

I am using GameMakers UI Layers and flex panels for much of the UI. I am using Giavapps Midi 2 for the MIDI processing. This will work with a MIDI chanter such as the Blair Digital Chanter. I am new to programming and building this one component at a time.   

- **Project workflow:** The game starts in Room_main_menu, with the main_menu_layer visible. Buttons open settings (by making setting_window_layer visible), tune selection (making tune_window_layer visible), Exit the Game, or go to the Room_play. 
 - Settings currently allows choosing a MIDI in and MIDI out. It will be expanded. 
 - Tune currently has a fixed number of rows, each with a radio button and field. The field global.tune_library poplates the fields and the selection is saved as a number in global.tune_selection. 
 
 This is a placeholder for a system which loads tune metadata and lets the user select a tune, scrollng or tabbing through the window. Selecting OK should load the tune into the tune object. 

- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order` (GameMaker project and loading order)
- **Major folders:**
  - `scripts/` — game logic scripts (UI, tune loading, midi, etc.)
  - `objects/` — GameMaker objects with events and instance scripts
  - `roomui/` — UI layouts and layers (the in-game windows)
  - `datafiles/` — external content (e.g., `tunes/` JSON/CSV files)
  - `extensions/` — third-party integrations (e.g., `GiavappsMIDI`)

---
**Core controller objects (high‑level architecture)**
These objects form the backbone of runtime behavior. They coordinate tune loading, playback, UI state, and MIDI I/O.
`obj_tune` — Tune data container (model)
- Created in Room_play (or globally if needed).
- Registers itself as global.tune in Create event.
- Holds:
- events[] — canonical event list loaded from JSON
- tune_metadata — optional metadata struct
- event_count, is_loaded, filename
- Does not handle playback logic; it is a pure data model.
`obj_player` — Playback engine (controller)
- Reads from global.tune.events.
- Maintains playback state:
- current time
- next event index
- tempo / metronome settings
- MIDI channel assignments
- Calls script_tune_callback() to send MIDI messages.
- Responsible for:
- advancing through events
- triggering note_on / note_off
- updating UI elements (score, piano roll, etc.)
`obj_UI_parent` — Base class for UI elements
- Provides shared behavior for:
- mouse interaction
- focus
- enabling/disabling
- layout helpers
- All UI components inherit from this.
`obj_btn_ (buttons)` — UI interaction controllers
- Each button instance calls into scr_button_scripts.
- Buttons do not contain logic; they dispatch actions.
`obj_field_base` — Text/label/field controller
- Used for displaying tune names, settings values, etc.
- Works with flex panels for layout.
`obj_tune_row` — Tune selection row controller
- Contains:
- a radio button
- a text field
- Stores:
- tune_filename
- tune_title
- Used by the tune picker window.

**UI architecture (UI layers + flex panels)**
`UI Layers`
GameMaker’s UI layers are used as “windows” or “panels” that can be shown/hidden:
- main_menu_layer
- settings_window_layer
- tune_window_layer
- (future) metronome_window_layer, parts_window_layer, etc.
Each layer contains:
- background/window sprites
- flex panels
- UI objects (buttons, fields, rows)
Visibility is controlled by button scripts.
`Flex Panels`
Flex panels are the layout engine. They:
- auto‑position children
- support vertical/horizontal stacking
- allow dynamic resizing
- make it easy to add/remove rows later (e.g., scrolling tune list)
Each flex panel is an object instance with:
- a list of child UI objects
- layout rules (direction, spacing, padding)
- optional scroll behavior (future)
`UI Script Flow`
All UI actions route through:
scripts/scr_button_scripts/

This script:
- identifies which button was pressed
- performs the appropriate action
- toggles UI layers
- calls tune loader scripts
- updates global settings
This keeps UI logic centralized and prevents duplication.

---


## Tune subsystem (primary focus) 🔧
- **Datafiles:** `datafiles/tunes/` contains tune JSON and CSV files (e.g., `ScotlandTheBrave.json`).
- **Library loader:** `scripts/scr_tune_library/scr_load_tune_library()` loads `tunes/tune_library.json` and exposes `global.tune_library`.
- **Tune loader:** `scripts/scr_tune_load/scr_tune_load_json(_filename)` reads a JSON tune file, validates fields (`tune` and `events`), and populates `obj_tune` instance fields (`tune_metadata`, `events`, `is_loaded`, etc.).
- **Playback & events:** `scripts/scr_tune_scripts/` contains `tune_build_events`, `tune_generate_metronome`, `tune_start` and the time-source callback `script_tune_callback` which sends MIDI via `midi_output_message_send_short`.
- **UI integration:** `roomui/RoomUI/` contains `tune_window_layer` and instances like `obj_tune_row`, `obj_tune_checkbox_*`, `obj_tune_ok_button` and `obj_button_tune`.
- **UI scripts:** `scripts/scr_button_scripts/scr_tune_OK()` wires the picker -> `scr_tune_load_json()` -> `tune_build_events()` -> `tune_start()` flow.
- **Object state:** `objects/obj_tune/Create_0.gml` initializes `global.tune` and storage fields used by the loader and playback.

---

## Play array / preprocessing ▶️
- **Purpose:** Convert canonical JSON (`tune` + `events`), metadata, and user preferences into a runtime-efficient 2D "play array" used directly by playback and UI systems. This preprocess step expands ornaments, applies tempo/part/metronome selections, applies user timing preferences (gracenote/embellishment timing, swing/humanize), precalculates durations and note-off events, and sorts/indexes events for very fast iteration during playback and rendering.

- **Inputs:** `tune` metadata, `events[]` from the JSON, metronome options, selected parts, and user preferences (grace note timing, embellishment timing, humanize offsets, swing settings).

- **Processing steps (high level):**
  - Expand embellishments/ornaments into discrete events and map `start_time_ms` → `time` (ms) if necessary.
  - Apply tempo adjustments, compute real-time timestamps, and generate metronome events based on metronome settings.
  - Merge events from all parts and generated metronome events into a single working array.
  - Pre-calculate note-off events, durations, and any display-related values (bar/beat indices, piano-roll columns).
  - Apply user preferences (e.g., gracenote offsets, embellishment alignment, swing/humanize jitter).
  - Sort final events by `time` and build a 2D indexing structure (e.g., tracks × time-slices or time-indexed buckets) optimized for the playback loop.

- **Output / schema suggestion:** either return a structured array from a script (e.g., `scr_build_play_array(_tune, _options)`) or store as `global.play_array`. Each play-event struct should include:
  - `time` (ms), `type` (numeric), `channel`, `note`, `velocity`, `duration_ms`, `source_part`, `is_embellishment`, `orig_event_id`, plus any precomputed UI values.
  - Top-level structure: array of tracks or a compact time-sorted array with optional indices for quick seeking.

- **Implementation location:** suggested new script(s) under `scripts/scr_tune_preprocess/` (e.g., `scr_build_play_array`, `scr_validate_tune`, `scr_expand_ornaments`). Also integrate validation into `scr_tune_load_json` so the tune is normalized on load.

- **Tests & QA:** include a `Room_tune_test` that exercises different combinations (metronome on/off, multiple parts, embellishments, tempo changes) and compares expected vs. computed timings.

- **Why this matters:** Preprocessing into a play array ensures playback and UI loops execute with minimal per-frame computation, improving reliability and enabling future features such as precise scoring and real-time analysis.

---

## MIDI & extensions ⚙️
- Extension: `extensions/GiavappsMIDI/` provides MIDI utilities used by playback scripts.
- Global MIDI device variable: `global.midi_output_device` used by `script_tune_callback`.

---

## Other systems to note 🔎
- **UI components:** `objects/obj_btn_*`, `objects/obj_field_base`, `objects/obj_UI_parent` - used for windows, labels, and interactivity.
- **Main rooms:** `rooms/Room_main_menu` and `rooms/Room_play` hold primary game flow and room-specific instances.

---

## Open questions & actionable TODOs ❓
1. **Missing `tune_library.json`:** `scripts/scr_tune_library` expects `tunes/tune_library.json`, but `datafiles/tunes/` currently contains only `ScotlandTheBrave.json` and `ScotlandTheBrave.csv`.
   - Action: add `tunes/tune_library.json` or add a generator script that builds it from `datafiles/tunes/` or the CSVs.

2. **Add an example `tune_library.json` and docs for adding tunes:** include a minimal example and a short doc snippet describing required fields (`filename`, `title`, metadata convention).

3. **Tests for tune loader/playback:** add unit/integration tests (or a manual test scene) for `scr_tune_load_json`, `tune_build_events`, `tune_start` and metronome generation.

4. **MIDI device preferences & initialization:** the project uses `global.midi_output_device` (set via UI). Confirm desired persistence (save to settings file) and add a small doc describing how to select/scan output devices (`scripts/scr_MIDI/*`).

5. **Playback reliability:** consider edge-case handling (empty tune, missing events, malformed timestamp) and add defensive checks where appropriate (e.g., `tune_start` asserts non-empty event list).

6. **Documentation depth:** confirm whether you want (a) this high-level map only, (b) per-file summaries (I can auto-generate), or (c) in-code docblocks/README per subsystem.

---

*Created by GitHub Copilot (Raptor mini (Preview)).*