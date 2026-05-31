# WORKSPACE_MAP.md

**Purpose:** Structured navigation guide for AI coding agents. Read this before planning any change. Prefer existing globals, structs, and functions documented here over creating new ones.

**Maintenance rule:** When adding or changing any function — update its `/// @` header block in code AND update its row in the Script Registry below.

## Script Registry (Scoring Addendum)

| Script | Function | Purpose | Reads | Writes | Callers |
|---|---|---|---|---|---|
| `scr_scoring.gml` | `scoring_judge_profile_get(_judge_id)` | Returns judge profile metadata (name, description, variable list, compact row order) for detail popup rendering. | none | none | `scoring_get_detail_popup_rows` |
| `scr_scoring.gml` | `scoring_detail_metric_format(_label, _value, _format)` | Formats detail metric values for popup row text output. | none | none | `scoring_get_detail_popup_rows` |
| `scr_scoring.gml` | `scoring_get_detail_popup_rows(_measure_num, _judge_id)` | Builds profile-driven detail popup rows for selected judge and scope. | `global.scoring_last_run`, `global.timeline_state`, `global.playback_context` | none | scoring detail popup UI |
| `scr_event_log.gml` | `event_history_get_export_info(_timestamp)` | Builds shared export metadata and benchmark context (device names, scheduler mode, manual run labels) for CSV/summary exports. | `global.current_tune_name`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.current_player_id`, `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS`, `global.PERF_BENCHMARK_*`, MIDI device globals | none | `event_history_export_csv`, `event_history_export_summary_json`, `event_history_export_loop_session_json` |
| `scr_event_log.gml` | `event_history_export_csv(_filename_or_path)` | Exports event history CSV with optional export-time filter to omit planned `source=game` rows. | `global.EVENT_HISTORY`, `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS` | CSV file output | manual export / end-of-tune export |
| `scr_event_log.gml` | `event_history_export_summary_json(_filename_or_path, _export_info)` | Exports summary JSON including `export_filter` and `benchmark_context` metadata for objective run comparisons. | `global.EVENT_HISTORY`, `global.timeline_state`, export info fields | summary JSON file output | end-of-tune export |
| `scr_game_viz.gml` | `gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2)` | Draws tune-structure grid and drives playback auto-follow scroll from local measure-nav entry time windows (single source of truth) into paged/continuous follow modes; emits `page_turn` log entries when follow changes rows. | `global.timeline_state.*`, `global.playback_context`, `global.timeline_cfg` | `global.timeline_state.measure_nav_scroll_row`, `global.timeline_state.measure_nav_total_rows`, `global.timeline_state.measure_nav_view_rows`, `global.timeline_state.measure_nav_tile_hitboxes`, `global.timeline_state.measure_nav_controls`, `global.timeline_state.measure_nav_auto_follow_last_ms` | gameviz panel draw pipeline |
| `scr_game_viz.gml` | `gv_log_measure_nav_page_turn(_playhead_ms, _measure_num, _from_scroll, _to_scroll, _target_row, _view_rows, _page_rows, _follow_mode)` | Records tune-structure follow row/page changes as structured `page_turn` events in `EVENT_HISTORY` and debug output. | `global.EVENT_HISTORY_ENABLED`, `global.current_tune_name`, `global.playback_context` | `global.EVENT_HISTORY` | `gv_draw_tune_structure_panel` |
| `scr_game_viz.gml` | `gv_measure_nav_find_local_idx(_ms, _measure_num)` | Resolves a panel-local measure-nav index for a wall-clock time and measure number; used to keep highlight indices in the same namespace as `measure_nav_entries`. | `global.timeline_state.measure_nav_entries` | none | `gv_get_current_planned_measure` |
| `scr_game_viz.gml` | `gv_get_current_planned_measure(_playhead_ms)` | Resolves active measure from playhead time; in set mode converts flat set-nav resolution into segment-local panel nav index and fails closed on namespace mismatch. | `global.timeline_state`, `global.playback_set_measure_nav_all`, `global.playback_context`, `global.timeline_cfg` | `global.timeline_state.measure_highlight_last_measure`, `global.timeline_state.measure_highlight_last_nav_idx`, `global.timeline_state.current_measure` | tune-structure panel draw/overlay, score sync |
| `scr_game_viz.gml` | `gv_draw_timeline_canvas_overlay(_x1, _y1, _x2, _y2)` | Draws active timeline overlays and score lane. Score-image time mapping must use per-image content bounds (`score_lane_meta[].content_left_px/right_px`) rather than full sprite width, otherwise variable exported whitespace causes apparent scrolling jumps and inconsistent image framing. | `global.timeline_cfg`, `global.timeline_state`, `global.playback_context`, `global.score_lane_sprites`, `global.score_playback_map`, `global.score_measure_map`, `global.score_lane_meta` | none | `obj_game_viz` Draw pipeline |
| `scr_game_viz.gml` | `gv_perf_summary_get_latest(_force_refresh)` | Loads and caches the latest JSONL run summary from `performances/run_summaries.jsonl` for the in-game status tile. | `scr_data_paths_get_category_root` (optional), local static cache | none | `gv_draw_gameviz_controls_panel`, `gv_handle_gameviz_controls_click` |
| `scr_game_viz.gml` | `gv_perf_summary_is_warn(_summary)` | Applies conservative warn thresholds to latest summary (`controller p95`, `scheduler p95`, `spike_count`) for status color. | summary struct fields | none | `gv_gameviz_draw_perf_summary_button` |
| `scr_game_viz.gml` | `gv_gameviz_draw_perf_summary_button(_rect, _summary, _enabled)` | Draws phase-1 "Perf: OK/WARN" tile with compact c95/s95/spike metrics in gameviz controls panel. | summary struct fields | none | `gv_draw_gameviz_controls_panel` |
| `scr_scoring.gml` | `scoring_tune_override_apply_current(_tune_filename)` | Applies per-player tune override values for single-tune runtime (bpm, swing, gracenote override, notebeam zoom ahead/behind) and syncs timeline notebeam window from cfg. | `global.player_tune_overrides`, `global.timeline_cfg` | `global.current_tune_filename`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.timeline_cfg.measures_ahead`, `global.timeline_cfg.measures_behind` | single-tune load flow (`scr_button_try_load_tune_candidate`), player switch (`scr_select_player`) |
| `scr_scoring.gml` | `scoring_tune_override_save_current(_tune_filename)` | Saves current single-tune runtime values (bpm, swing, gracenote override, notebeam zoom ahead/behind) into per-player tune overrides and persists to disk. | `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.timeline_cfg.measures_ahead`, `global.timeline_cfg.measures_behind` | `global.current_tune_filename`, `global.player_tune_overrides` | tune settings +/- handlers, notebeam zoom button |
| `scr_tune_library.gml` | `scr_data_paths_get_user_data_root()` | Resolves canonical writable runtime data root (AUTO path for sets/config/debug/performances). | none | none | `scr_data_paths_get_primary_root`, `scr_data_paths_get_category_root`, config save |
| `scr_tune_library.gml` | `scr_data_paths_get_content_root()` | Resolves tune content root from optional override, then AUTO candidates (`working_directory`, `program_directory`, project-relative fallback). | `global.primary_data_root_override`, `global.tune_library_root_override` | none | `scr_data_paths_get_category_root`, `scr_tune_library_get_runtime_root`, settings UI |
| `scr_tune_library.gml` | `scr_data_paths_load_primary_root_from_config()` | Loads optional tune content root override from runtime paths config; canonical runtime config is checked first, legacy mirrors are fallback-only. | `working_directory/datafiles/config/runtime_paths.json` (+ legacy mirrors) | none | `obj_game_controller` Create |
| `scr_tune_library.gml` | `scr_data_paths_save_primary_root_to_config(_root)` | Persists tune content root override to canonical runtime config (`<user_data_root>/config/runtime_paths.json`). | none | canonical runtime paths JSON | settings UI handlers (`scr_settings_data_root_set`, `scr_settings_data_root_reset_auto`) |
| `scr_tune_library.gml` | `scr_tune_library_get_runtime_root()` | Resolves the tune-library root from category path `tunes/` (content root) with fallback probe. | `global.primary_data_root_override` | none | `scr_load_tune_library`, `obj_game_controller` Create, `scr_regenerate_tune_library` |
| `scr_tune_library.gml` | `scr_load_tune_library()` | Loads `tune_library.json` from runtime root candidate(s) and returns library struct with merged history stats. | `global.current_player_id` (via history merge) | none | `obj_ui_controller` Create, `scr_regenerate_tune_library` |
| `scr_button_scripts.gml` | `scr_regenerate_tune_library()` | Rebuilds tune library from runtime root, reloads global library, and refreshes picker rows. | none | `global.tune_library` | button index 12 (`scr_handle_button_click`) |
| `scr_button_scripts.gml` | `scr_button_bpm_debug_log(_line)` | Writes BPM diagnostics to debug output and runtime-relative `datafiles/debug/bpm_trace.log`. | none | `datafiles/debug/bpm_trace.log` | BPM change + start-play diagnostics |
| `scr_tune_scripts.gml` | `diag_log_get_debug_root()` | Resolves and creates the runtime debug directory with a normalized trailing slash path for all diagnostics. | none | filesystem (debug directory) | `diag_log_append_line`, `perf_diag_emit` |
| `scr_tune_scripts.gml` | `diag_log_detect_channel(_file_name)` | Infers a diagnostic channel label from log filename for structured JSONL records. | none | none | `diag_log_build_record` |
| `scr_tune_scripts.gml` | `diag_log_detect_event(_msg)` | Infers coarse event tags (play start/stop, RT budget, BPM, calibration) from message text for structured logs. | none | none | `diag_log_build_record` |
| `scr_tune_scripts.gml` | `diag_log_build_record(_line, _file_name)` | Builds structured diagnostic records with timestamp, channel, event, tune/config metadata, and message text. | `global.current_tune_name`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.playback_run_id` | none | `diag_log_append_line`, `perf_diag_emit` |
| `scr_tune_scripts.gml` | `diag_log_get_max_lines()` | Resolves max retained lines per diagnostic log before rollover from global override/default. | `global.DIAG_LOG_MAX_LINES` | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_get_max_backups()` | Resolves retained backup generation count per diagnostic log from global override/default. | `global.DIAG_LOG_MAX_BACKUPS` | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_count_lines_upto(_path, _stop_after)` | Counts log lines with early stop for rollover checks. | none | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_rotate_if_needed(_log_path)` | Performs line-count-based log rollover to numbered backups (`.1`, `.2`, ...). | `global.DIAG_LOG_MAX_LINES`, `global.DIAG_LOG_MAX_BACKUPS` | diagnostic log files and backups | `diag_log_append_line` |
| `scr_tune_scripts.gml` | `diag_log_append_line(_line, _file_name, _mirror_output, _output_prefix)` | Shared append writer used by perf/BPM/calibration diagnostics; writes one JSON object per line (JSONL). | none | `datafiles/debug/*.log` | `perf_diag_emit`, `scr_button_bpm_debug_log`, `scoring_calibration_debug_log` |
| `scr_tune_scripts.gml` | `perf_run_summary_get_performances_root()` | Resolves and creates the performances folder used for compact run summary output. | none | `datafiles/performances/` (directory create) | `perf_run_summary_append_latest` |
| `scr_tune_scripts.gml` | `perf_run_summary_append_latest(_jitter_summary)` | Appends one JSONL record per completed run to `run_summaries.jsonl` with mode/title, elapsed, jitter stats, and spike count. | `global.playback_context`, `global.current_tune_name`, `global.playback_run_id`, `global.timing_calibration`, `global.perf_run_last_*`, `global.rt_budget_sched_spike_count` | `datafiles/performances/run_summaries.jsonl`, `global.perf_run_summary_last_written_play_id` | `tune_cleanup_after_finish` |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_controller_phase_ms(_phase_kind, _phase_ms)` | Records keyed per-phase controller-step timings (`scheduler_tick`, `timeline_tick`, `deferred_tick`) and emits `[RT_BUDGET] controller_phase_ms` summaries for bottleneck isolation. | `global.RT_BUDGET_DIAG_ENABLED`, `global.RT_BUDGET_DIAG_LOG_INTERVAL_MS`, `global.RT_BUDGET_SCHED_WARMUP_MS`, `global.tune_start_real` | `global.rt_budget_controller_phase_stats` | `obj_game_controller` Step event |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_draw_interval_ms(_draw_dt_ms)` | Records draw-to-draw frame interval timing (`[RT_BUDGET] draw_interval_ms`) to separate frame pacing jitter from draw runtime cost. | `global.RT_BUDGET_DIAG_ENABLED`, `global.RT_BUDGET_DIAG_LOG_INTERVAL_MS`, `global.RT_BUDGET_SCHED_WARMUP_MS`, `global.tune_start_real` | `global.rt_budget_draw_dt_buf/head/count/last_log_ms` | `obj_game_viz` Draw event |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_trace_scheduler_spike(_late_ms, _real_elapsed, _scheduled_elapsed)` | Emits cooldown-limited `[SCHED_SPIKE]` traces with scheduler/deferred/segment context when lateness crosses threshold, to correlate spike moments with runtime state. | `global.RT_BUDGET_DIAG_ENABLED`, `global.tune_group_index`, `global.tune_event_groups`, `global.tune_deferred_queue`, `global.tune_deferred_head`, `global.PLAYBACK_SCHEDULER_*`, `global.playback_context`, `global.timeline_state` | `global.rt_budget_sched_spike_last_log_ms`, `global.rt_budget_sched_spike_count` | `script_tune_callback_batched` |
| `scr_button_scripts.gml` | `scr_settings_data_root_set(_ctx)` | Captures a custom tune content root, validates `<root>/tunes`, persists canonical runtime config, regenerates library, and refreshes settings field display. | `global.primary_data_root_override` | `global.primary_data_root_override`, `global.tune_library` | button index 38 (`scr_handle_button_click`) |
| `scr_button_scripts.gml` | `scr_settings_data_root_reset_auto(_ctx)` | Clears custom tune content root override, persists AUTO mode to canonical runtime config, regenerates library, and refreshes settings field display. | `global.primary_data_root_override` | `global.primary_data_root_override`, `global.tune_library` | button index 39 (`scr_handle_button_click`) |
| `scr_game_viz.gml` | `gv_draw_gameinfo_timeline_visibility_panel(_x1, _y1, _x2, _y2)` | Draws the game-info toggle for timeline score-lane visibility (`Score` vs `Markers`) and disables interaction during live playback. | `global.timeline_cfg.timeline_score_visibility_mode`, `global.timeline_state.active`, `global.timeline_state.review_mode` | none | `obj_field_base` draw branch (`gameinfo_timeline_visibility_anchor`) |

**Last full review:** 2026-04-15

---

## Export File Locations (Quick Reference)

When a tune playback completes, exports are written to:
- **CSV (event history):** `datafiles/performances/{clean_tune_name}/{clean_tune_name}_{timestamp}_{bpm}_{swing}_{grace_override_ms}.csv`
- **Summary JSON:** `datafiles/performances/{clean_tune_name}/{clean_tune_name}_{timestamp}_{bpm}_{swing}_{grace_override_ms}_summary.json`

Example for "Jock Wilson's Ball" (90 BPM, 0 swing, 30ms grace):
- `datafiles/performances/Jock Wilsons Ball/Jock Wilsons Ball_20260510-183441_90_0_30.csv`
- `datafiles/performances/Jock Wilsons Ball/Jock Wilsons Ball_20260510-183441_90_0_30_summary.json`

**Entry point:** `event_history_get_export_info()` in `scr_event_log.gml` builds the paths. Trigger: `export_event_history()` (button 13) or auto-export on playback completion if `global.EVENT_HISTORY_AUTO_EXPORT` is true.

**Phase-1 experimental toggle:** `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS`
- `true` (default): CSV export includes planned `source="game"` and player rows.
- `false`: CSV export omits planned `source="game"` rows while live history ingestion remains unchanged for scoring correctness.

**Benchmark run metadata:** summary export includes `benchmark_context` (manual power-mode/MIDI-activity labels, notes, MIDI device names, scheduler mode, FPS) and `export_filter` state for each run.

---

## Documentation Index

| File | Purpose |
|---|---|
| `WORKSPACE_MAP.md` | **This file.** Script registry, globals, struct schemas, UI architecture, playback flow. |
| `PROJECT_PLAN.md` | Implementation log, cleanup batches, pending work items. |
| `BETA_RELEASE_PLAN.md` | Beta packaging hardening plan for zipped Windows distribution (Steam-compatible workflow). |
| `EXCEL_VBA_MAP.md` | VBA module reference: pipeline stages, entry points, 23-column constants, sheet conventions, output paths, config. |
| `TUNE STRUCTURE JSON.md` | `tune.json` schema consumed by `scr_tune_load_json`. |
| `TUNE STRUCTURE EXCEL.md` | 23-column event grid layout inside the Excel workbook. |
| `TRANSITION_TUNE_TEMPLATE.md` | How to author transition tunes (ABC patterns, set ordering, verification checklist). |
| `METRONOME.md` | Metronome scheduling design and implementation notes. |
| `UI_SETUP_HOWTO.md` | How to wire up new UI layers and instances. |
| `Giavapps MIDI documentation.md` | API reference for the `midi_*` extension functions. |
| `TUNE GAMEPLAY VISUALS.md` | Notebeam / game-viz visual design notes. |
| `scripts/Excel - Parse_ABC.txt` | Read-only VBA mirror: `modParseABC` (ABC → event grid pipeline). |
| `scripts/Excel - TuneExport.txt` | Read-only VBA mirror: `modTuneExport` (tune metadata export). |
| `scripts/Excel - Performance_Analysis.txt` | Read-only VBA mirror: `modTuneLoader` (post-session analysis). |

Performance runtime note:
- Timeline overlay redraw cadence can be throttled independently from step rate via `global.GV_TIMELINE_OVERLAY_REFRESH_MS` (default 11 ms, ~90 Hz). `obj_field_base` timeline anchor caches base and overlay surfaces separately and blits cached overlay each frame.

---

## Function annotation template

All functions use `/// @` headers (GameMaker IDE renders these as tooltips). Four custom tags (`@reads`, `@writes`, `@objects`, `@callers`) are not rendered by the IDE but are greppable for cross-system navigation.

**Full template** (any function that touches globals, objects, or is a cross-system integration point):
```gml
/// @function function_name(_param1, _param2)
/// @description One-line description.
/// @param {type} _param1  Description
/// @param {type} _param2  Description
/// @returns {type}  Description   (omit tag if void)
/// @reads   global.var_name, global.other_var   (or "none")
/// @writes  global.var_name                     (or "none")
/// @objects obj_name (read|write), obj_other    (or "none")
/// @callers caller_function, other_caller
```

**Minimal template** (pure utility — no globals, no objects touched):
```gml
/// @function function_name(_param)
/// @description One-line description.
/// @param {type} _param  Description
/// @returns {type}  Description
```

---

---

## Project overview (current state)

- **What it does today:** The game loads tune data (JSON/CSV) and plays scheduled MIDI events. Playback events are sent via Giavapps MIDI. The UI uses GameMaker layers and a set of UI objects (buttons, fields) to control playback and settings.

- **Current workflow:** The game starts in `Room_main_menu` with `main_menu_layer` visible. From there:
  - **Play** navigates to `Room_play` and starts playback.
  - **Settings** lets the user pick MIDI input/output devices (via `scr_button_scripts` and `scr_MIDI` helpers).
  - **Tune** opens the tune picker; visible rows are populated from `global.tune_library` and the selection is stored in `global.tune_selection`. Pressing the tune OK button triggers `scr_tune_load_json()` and the build → start playback flow.

- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order`
- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order`
- **Documentation highlights:**
  - `PROJECT_PLAN.md` — implementation log, cleanup batches, and planning updates.
  - `EXCEL_VBA_MAP.md` — VBA module reference: pipeline stages, entry points, column constants, sheet conventions, output paths, config surface.
  - `TUNE STRUCTURE JSON.md` — `tune.json` schema consumed by `scr_tune_load_json`.
  - `TUNE STRUCTURE EXCEL.md` — 23-column event grid layout used inside the Excel workbook.
  - `TRANSITION_TUNE_TEMPLATE.md` — standard transition-tune authoring guide (metadata, ABC patterns, set ordering, verification checklist).
  - `METRONOME.md` — metronome scheduling design and implementation notes.
  - `UI_SETUP_HOWTO.md` — how to wire up new UI layers and instances.
- **Major folders:**
  - `scripts/` — game logic scripts (UI, tune loading, midi, etc.)
  - `objects/` — GameMaker objects with events and instance scripts
  - `roomui/` — UI layouts and layers (in-game windows)
  - `datafiles/` — external content (`tunes/` JSON/CSV files — **generated by Excel VBA pipeline, not hand-authored**)
  - `extensions/` — third-party integrations (`GiavappsMIDI`)
  - `scripts/Excel - *.txt` — read-only VBA source mirrors for the Excel workbook (`Silly Wizard Work.xlsm`); see `EXCEL_VBA_MAP.md`

---

---

## Important Architectural Constraints

⚠️ **No GameMaker data structures (ds_maps, ds_lists, ds_grids, etc.)**
- Use **structs** for key-value lookup and complex data
- Use **arrays** for sequences and lists
- Avoid all `ds_*` functions — they introduce unnecessary memory management overhead and complexity
- This keeps code simpler, more predictable, and easier to debug

⚠️ **Score image export invariant (do not regress)**
- Export pipeline must produce **one score image per playback measure**.
- Do **not** deduplicate repeated/identical-looking measures during score snippet generation.
- `playback_to_image` must be an identity map for normal bundles (`[0, 1, 2, ...]`) so score-lane `seq` aligns directly to sprite index.

⚠️ **Transition metadata must fail loudly (no silent runtime fallback)**
- Authoring mismatches (for example transition tail/head content present but cut metadata missing, or vice versa) must be surfaced by validation/export warnings in the VBA pipeline.
- Runtime GML should consume explicit metadata and avoid heuristic fallbacks that can mask bad workbook/source data.

⚠️ **Fix root causes, keep runtime logic lightweight**
- When an issue is found, prefer identifying and fixing the underlying source/data/logic mismatch over adding special-case runtime workarounds for one instance.
- Keep fixes small, readable, and reusable so behavior is understandable and maintainable across all tunes/sets.

---

## Key scripts (current responsibilities)

- **`scripts/scr_button_scripts/`** — UI button dispatcher and handlers (window toggles, settings changes, tune OK, start play).
- **`scripts/scr_MIDI/`** — MIDI device scanning/opening and message utilities; processes input messages and provides helper functions for playback.
- **`scripts/scr_tune_library/`** — Loads `tunes/tune_library.json` and populates tune picker rows.
- **`scripts/scr_tune_load/`** — Loads and validates tune JSON files into the `obj_tune` instance; loads score manifests/sprites and normalizes `image_meta.beat_anchors` for runtime score-lane consumption.
- **`scripts/scr_preprocess_tune/`** — Converts raw tune events into playable timelines (embellishments, swing, timing) and normalizes legacy pickup structure so measure 1 starts after any anacrusis.
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

### Calibration Handoff (Current)
- Split timing domains (two active): `audio_output_offset_ms`, `visual_alignment_offset_ms` (reserved for future: `input_capture_offset_ms`).
- Scoring offset removed to keep player feedback honest.
- Calibration APIs in `scr_tune_scripts.gml` (per-device profile hydrate/store and offset apply).
- Player settings persist `settings.timing_calibration` via `scr_scoring.gml` save/load.
- Scheduler timing applies `audio_output_offset_ms` in both timesource and step scheduler paths.
- Script dispatcher keeps calibration hooks at cases `32` (manual nudge audio/visual) and `37` (apply saved profile); cases `31/33/34/35/36` are intentionally inactive.

---

## BPM Authority & Propagation Path

`global.current_bpm` is the authoritative runtime BPM. It is written by UI controls and must flow through every downstream consumer consistently.

### BPM sources (precedence order at play time)
1. **Live BPM field value** — resolved from the BPM +/- bound field in `scr_button_get_bpm_from_bound_field()` (highest priority)
2. **Active settings segment bpm** — `set_item.bpm` in set mode, or the single-tune virtual set item (`global.current_set[0].bpm`) in single-tune mode
3. **`global.current_bpm`** — runtime mirror/fallback when field and segment value are unavailable
4. **`tune_metadata.tempo_default`** — value from `tune.json`; used as fallback only (lowest priority)

### VBA / Excel pipeline
`RecalculatePositions` bakes `start_time_ms`, `end_time_ms`, and `tempo_bpm` into the event grid using the ABC `Q:` header BPM. These values are exported to `tune.json` and stored as `tune_metadata.tempo_default`. At runtime, **`scr_preprocess_tune` recalculates all timing from scratch** and ignores the stored ms values — so the VBA pipeline is BPM-neutral at runtime.

### Single-tune mode BPM lifecycle
| Step | Location | Notes |
|------|----------|-------|
| Tune selected | `scr_goto_playroom()` | Reads `global.current_bpm`; calls `scr_preprocess_tune` with that override |
| Virtual 1-tune set initialized | `scr_button_try_load_tune_candidate()` | Single-tune load creates/updates `global.current_set[0]` (virtual set item), then mirrors it into `playback_context.segments[0]` |
| User changes settings (BPM/swing/grace/metro) | `scr_tune_bpm_change()` and related handlers in `scr_button_scripts` | Writes globals + active virtual set item, then rebuilds single-tune playback events immediately |
| Effective settings resolved | `scr_button_resolve_effective_settings()` | Central authority resolver used by single-tune preprocess/play; overlays live field values and syncs mirrors |
| User presses Play | `start_play()` | Reads effective settings through resolver, rebuilds `global.playback_events`, then binds timeline timing |

> **Critical:** `playback_context` can be rebuilt from tune metadata and become stale; single-tune runtime settings remain authoritative in the virtual set item (`global.current_set[0]`) and are mirrored back into `playback_context.segments[0]` before play.

### Set mode BPM lifecycle
In set mode, `scr_set_preprocess_and_build_playback()` reads BPM from each `active_set.segments[].bpm` which is populated fresh from the current override state at room entry. `scr_playback_context_build_for_set()` then copies those segment BPMs into `playback_context`, so the context is always current — no separate override needed.

---

## Core controller objects (current state)

- **`obj_game_controller`**
  - Location: `objects/obj_game_controller/Create_0.gml`
  - Role: Initializes global IDs and MIDI/game defaults. Holds `global.*` vars used across the app.

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

- **UI Layers:** `main_menu_layer`, `settings_window_layer`, `tune_window_layer`, `calibration_window_layer` (each layer contains backgrounds, flex panels and instances such as buttons and fields).
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
- Passive tune-picker canvas anchor clicks can route through the no-action path (`scr_script_not_set`); `tune_library_canvas_anchor` is intentionally treated as no-op noise and exits early without logging.

### Timeline/notebeam anchor runtime contract
- Anchor rendering and click routing are split by coordinate space:
  - GUI-space clicks: gameviz/notebeam handlers (`obj_field_base` Mouse_7 -> `gv_handle_gameviz_controls_click` / `gv_handle_notebeam_click`).
  - Room/screen-space clicks: tune-structure handler (`obj_field_base` Mouse_7 -> `gv_measure_nav_handle_click(mouse_x, mouse_y)`).
- Anchor cache setup/storage is centralized via `gv_anchor_cache_get_or_create()` and `gv_anchor_cache_store()` in `scr_game_viz` and reused by timeline/notebeam/tune-structure anchor draw paths.
- Synthetic measure navigation fallback is centralized via `gv_build_synthetic_measure_nav_map()` so both bind-time and panel bootstrap paths share identical fallback measure grid behavior.
- Measure-nav state wiring is centralized via `gv_measure_nav_apply_to_timeline_state()` and `gv_measure_nav_ensure_state_defaults()` so bind-time and lazy panel bootstrap use the same state shape.
- Measure-nav source event selection/flattening is centralized via `gv_measure_nav_resolve_source_events()` to keep bootstrap behavior consistent when falling back from planned arrays to scheduler group events.
- Measure-nav fallback end-time selection is centralized via `gv_measure_nav_resolve_end_ms_from_events()` and `gv_measure_nav_resolve_end_ms_from_state()` to keep synthetic-map sizing consistent across paths.
- Set segment score-cache restoration is centralized via `gv_restore_score_segment_cache()` so all segment-switch paths reuse the same restore logic for structural metadata (`score_snippet_durations`, `score_units_per_measure`, `score_has_pickup`) and score-lane draw arrays.
- Per-segment measure-nav rebuild (`gv_rebuild_measure_nav_for_segment`) is set-mode only; single-tune playback keeps bind-time nav built from active playback events so loop-runtime structure tiles stay aligned with looped audio/notebeam timing.
- Set-mode measure tracking uses a prebuilt flat table (`global.playback_set_measure_nav_all`) rather than per-segment rebuild so `gv_get_current_planned_measure()` is never stale at segment boundaries. Built once by `gv_build_set_measure_nav_all()` after sprite cache population; per-segment `measure_nav_entries` continues to serve the structure-panel UI display only. Pickup entries (`measure=0`) remain authoritative no-highlight windows, so later pickup segments do not inherit the previous segment's measure number.
- Single-tune loop score-lane rendering normalizes playhead time to the loop-cycle window (derived from loop iteration marker boundaries) before score image range tests, so measure-window clipping and `playback_to_image` lookup stay stable across loop restarts.
- Score-lane image mapping uses manifest `image_meta[].content_left_px` / `content_right_px` as the authoritative drawable content window. Do not scale time across the full PNG width: exported measures can carry different left/right whitespace, and using full-sprite width causes apparent traveling jitter even when playhead timing is smooth.
- **Pickup data flow (authoritative source):** `has_pickup` is computed by the VBA ABC parser (`PickupDetected`) and written into `<TuneName>.score_snippets.json` at export time. At runtime, `scr_score_manifest_read()` reads `score/score_images.json` then merges `has_pickup` and `snippets[]` from the sibling `.score_snippets.json` onto the manifest struct. `scr_score_sprites_load()` extracts `snippets[].duration_units` into the flat `global.score_snippet_durations` array and sets `global.score_has_pickup`. All measure-numbering paths consume these globals — no runtime heuristics from duration arithmetic.
- **score_images.json vs score_snippets.json:** `score/score_images.json` holds sprite filenames, `image_meta`, `beats_per_measure`, `units_per_measure`. `<TuneName>.score_snippets.json` (sibling to the tune JSON, not in score/) holds `has_pickup`, per-snippet `duration_units`, `is_pickup`, and `playback_to_image`. Always check both files when debugging pickup or measure-numbering issues.
- Tune-structure panel rendering is anchor-driven (`tunestructure_canvas_anchor` in `obj_field_base` Draw_0); the legacy Draw_0 fallback panel path in `obj_game_viz` is retired.
- Cached anchor rendering (`obj_field_base` Draw_0) sets `global.GV_ANCHOR_RECT_X_OFFSET/Y_OFFSET` to `-bbox_left/-bbox_top` while drawing notebeam and tune-structure into local surfaces.
- `scr_game_viz` hitbox writes use those offsets (via hitbox bias) so stored hitboxes remain in global screen space and align with click tests.
- Notebeam popup draws in GUI (`obj_game_viz` Draw_64) to ensure it stays above world-space notebeam/chanter visuals.

### Fields & dynamic text
- Fields use `field_target` to reference either a global array (like `tune_library`) or a global variable name (string). `scr_update_fields()` pulls the value and fills `field_contents` to change the visible label.
- Fields also have `field_script_index` to allow scripted actions when interacted with.

### Tune picker specifics (tune_window_layer)
- The tune window contains six manual rows `fp_tune_row_1..fp_tune_row_6`. Each row contains:
  - `obj_btn_check` instances (radio/checkbox) with `button_script_index` set to the checkbox handler and `button_click_value` equal to the row index (used to set `global.tune_selection`).
  - `obj_field_base` instances with `field_target` set to `tune_library` and `field_value` set to the index; `scr_tune_picker_populate()` (in `scr_tune_library/`) updates the visible rows and associated text when a library is loaded.

  Note: The population routine **pairs** each field and checkbox **preferentially by explicit editor-assigned IDs** (use `field_ID` on fields and `button_ID` on checkboxes — e.g., 1..10). If those are not set it falls back to `ui_num` (the runtime registration number), and as a last resort it pairs by on-screen order (sorted by Y). This lets you safely add rows (7–10) and control their mapping via the `field_ID`/`button_ID` properties.
- The `obj_tune_ok_button` calls `scr_handle_button_click` with its `button_script_index` (mapped to `scr_tune_OK`) which loads the selected tune and initiates build→start playback flow.
  - `scr_tune_OK` now resolves picker/library/entry state through `scr_button_resolve_picker_selection()` before loading candidate tune paths.
  - Candidate tune paths are assembled via `scr_button_build_tune_load_candidates()`.
  - Each candidate load/apply attempt runs through `scr_button_try_load_tune_candidate()`.
  - Runtime per-tune overrides from UI fields are applied via `scr_button_apply_set_item_from_ui_fields()`.
  - Runtime globals for playback/metronome/count-in/swing/gracenote are applied via `scr_button_apply_globals_from_set_item()`.
  - Post-load UI updates (window visibility + game info title) are applied via `scr_button_apply_post_tune_load_ui()`.
  - Created-set summary logging is emitted via `scr_button_log_created_set_item()`.
  - The tune button label is restored once at the end of `scr_tune_OK` (single restore point).

### Per-layer summaries (current content)
Below are the actual UI layers and the important instances placed on each (based on `roomui/RoomUI/RoomUI.yy`). All instances are manually placed in the Room UI editor and configured by overriding object properties there.

- `settings_window_layer` — Settings window
  - Title: `fp_Title_text` (text "Settings").
  - Close: `obj_settings_win_close_button` (instance of `obj_btn_winClose`, often with `button_ID = 3`).
  - MIDI In row: `setting_Lbutton_1` (left arrow `obj_btn_fieldL`), `setting_field_1` (`obj_field_base`) — field for MIDI IN device.
  - MIDI Out row: `setting_Lbutton_2`/`setting_Rbutton_2`, `setting_field_2` (`obj_field_base`) — field for MIDI OUT device.
  - Logs row: `setting_Lbutton_logs`/`setting_Rbutton_logs`, `setting_field_logs` (`obj_field_base`) — OFF/ON toggle for runtime score-lane debug logging.
  - Calibration launcher: `obj_settings_calibration_button` (`obj_btn_main`) — opens `calibration_window_layer` via `scr_open_window` (layer index 8).
  - OK: `obj_setting_ok_button` (`obj_btn_main`) — typically configured to run the settings OK handler (`scr_settings_OK`).

- `calibration_window_layer` — Calibration prototype window
  - Title: `text_calibration_title` (text "Calibration").
  - Close: `obj_calibration_win_close_button` (`obj_btn_winClose`).
  - Mode row: `calibration_mode_left_button`, `calibration_mode_field`, `calibration_mode_right_button` (button ID/script index 31).
  - Audio row: `calibration_audio_left_button`, `setting_field_cal_audio`, `calibration_audio_right_button` (button ID/script index 32).
  - Visual row: `calibration_visual_left_button`, `setting_field_cal_visual`, `calibration_visual_right_button` (button ID/script index 32).
  - Status rows: `calibration_summary_field`, `calibration_status_field` populated by `scr_button_calibration_refresh_ui()`.

- `tune_window_layer` — Tune picker window
  - Title: `fp_Title_text` (text "Tune Library").
  - Close: `obj_tune_win_close_button` (`obj_btn_winClose`).
  - Tune rows (1..6): each row has a checkbox and a field:
    - `obj_tune_checkbox_1..obj_tune_checkbox_6` (instances of `obj_btn_check`) — configured with `button_script_index = 2` (checkbox handler), `button_target = global.tune_selection`, and `button_click_value = row index`.
    - `obj_tune_field_1..obj_tune_field_6` (instances of `obj_field_base`) — set with `field_target = tune_library` and `field_value = row index`; populated at runtime by `scr_tune_picker_populate()`.
  - OK: `obj_tune_ok_button` (`obj_btn_main`) — typically configured to `scr_tune_OK()` (loads the selected tune).

- `loop_score_overview_layer` — Post-loop scoring overview panel
  - Title: `loop_score_title_text` (text "Loop Scores").
  - Close: `obj_loop_score_win_close_button` (`obj_btn_winClose`, `button_script_index = 29` → `scr_toggle_loop_score_overview`).
  - Canvas: `loop_score_matrix_canvas_anchor` (`obj_field_base`, `ui_name = "loop_score_matrix_canvas"`) — draws the loop×judge matrix via `scoring_loop_overview_draw_canvas()`.
  - Positioned at `positionLeft = 57%`, `width = 35%`, `height = 80%` (to the right of `judge_settings_layer`).
  - Toggle button `obj_button_loop_scores` on `main_menu_layer` (inside `fp_loop_scores_button`, `button_script_index = 29`).

- `gameinfo_window_layer` — Informational window
  - Title field: `obj_gameinfo_win_title` (`obj_field_base`) — shows selected tune or status (default: "No tune selected").
  - Back / OK buttons: `obj_gameinfo_back_button`, `obj_gameinfo_ok_button` (`obj_btn_main`) with appropriate `button_script_index` values for navigation.

- `current_note_layer` — Current note display
  - `obj_currentnote_field_1` (`obj_field_base`) — updated at runtime by `script_tune_callback()` to show the currently played note.

- `main_menu_layer` — Main menu
  - Buttons: `obj_button_play` (`obj_btn_main`, `button_script_index = 1`), `obj_button_settings` (`obj_btn_main`, `button_script_index = 3`, `button_target = settings_window_layer`), `obj_button_tune` (`obj_btn_main`, `button_script_index = 3`, `button_target = tune_window_layer`), plus exit/back buttons.

> Note: For all UI instances the important configuration is done in the Room UI editor via overridden properties (e.g., `button_script_index`, `button_target`, `field_target`, `field_value`). `obj_UI_parent` registers each instance into `global.ui_assets` so scripts can refresh or re-link instances at runtime.

---

## Global State Inventory

All globals are initialized by the owning script/object at startup. **Do not create new globals without adding a row here.**

| Global | Type | Shape summary | Owner (initialized in) | Key consumers |
|--------|------|---------------|------------------------|---------------|
| `global.emb_library` | array | `[{emb_id, emb_name, pattern, target_note, notes, timing, anchor_index, category}]` | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_embellishments` |
| `global.EMBELLISHMENT_CONFIG` | struct | BPM-aware gracenote timing constants — see struct schema below | `obj_game_controller` Create | `scr_embellishments` `embellishment_to_notes()` |
| `global.METRONOME_DRUM_PROFILES` | struct | Named drum note-mapping profiles: `{"General MIDI": {kick, snare, hi_hat, …}}` | `obj_game_controller` Create | `scr_metronome` |
| `global.current_metronome_drum_profile` | string | Active profile key (e.g. `"General MIDI"`) | `obj_game_controller` Create | `scr_metronome` |
| `global.timeline_cfg` | struct | Viz/timing config: `{enabled, tune_channel, tune_show_other_parts_ghost, tune_other_parts_alpha, timeline_score_visibility_mode, audio_output_offset_ms, visual_alignment_offset_ms, input_capture_offset_ms, scoring_compare_offset_ms, score_lane_debug_log, score_lane_debug_boundary_window_ms, score_lane_debug_focus_title, score_lane_debug_file_log, score_lane_debug_file_path, score_lane_anchor_guides_enabled, score_lane_anchor_guide_color, score_lane_anchor_guide_alpha, score_lane_anchor_guide_width, ...}` | `obj_game_controller` Create | `scr_game_viz` |
| `global.timeline_state` | struct | Full runtime playback/viz state — see struct schema below | `obj_game_viz` Create | `scr_game_viz`, `scr_scoring`, `scr_tune_scripts` |
| `global.active_set` | struct | Loaded set metadata + segments + score override plan — see struct schema below | `scr_set_scripts` `scr_set_init_global()` | `scr_set_scripts`, `scr_button_scripts`, `scr_scoring` |
| `global.playback_events` | array | Stitched MIDI + marker event array (shared by single-tune and set paths) | `scr_set_scripts` / `scr_button_scripts` | `scr_tune_scripts`, `scr_game_viz`, `scr_scoring` |
| `global.playback_context` | struct | Thin navigation wrapper: `{mode, display_title, active_segment, segments[], score_override_plan[]}` | `scr_set_scripts` `scr_playback_context_init()` | `scr_game_viz`, `scr_scoring`, event export |
| `global.current_set` | array | Array of `set_item` structs (playlist for current session) | `obj_game_controller` Create | `scr_button_scripts`, `scr_set_scripts` |
| `global.current_set_item_index` | real | Index into `global.current_set`; -1 = none | `obj_game_controller` Create | `scr_button_scripts` |
| `global.tune` | instance id | The `obj_tune` instance (single tune data model) | `obj_game_controller` Create | `scr_tune_load`, `scr_tune_scripts`, `scr_button_scripts` |
| `global.tune_library` | struct | `{tunes: [{filename, title, …}]}` | `obj_ui_controller` Create | `scr_tune_library`, tune picker UI |
| `global.primary_data_root_override` | string | Optional absolute/relative tune content root override (`.../datafiles/` style); loaded from runtime paths JSON at startup; blank = AUTO content-root detection while user-data stays runtime-writable | `obj_game_controller` Create | `scr_data_paths_get_content_root`, category path helpers, startup/rebuild flows |
| `global.tune_selection` | real | Index of selected tune in picker; -1 = none | `obj_ui_controller` Create | `scr_button_scripts`, checkboxes |
| `global.selected_tune_time_sig` | string | Time-sig string of tune highlighted in picker (before OK) | `obj_ui_controller` Create | `scr_button_scripts` |
| `global.score_transition_images` | struct | Current tune transition score groups from `score_images.json`: `{prior_replace?, bridge?, follow_replace?}` | `scr_tune_load` `scr_score_sprites_load()` | future score override planning / score-lane runtime |
| `global.score_has_pickup` | bool | True when the current tune's first snippet is an opening pickup bar | `scr_tune_load` `scr_score_sprites_load()` | `gv_build_measure_nav_map`, score-lane structural path, `gv_restore_score_segment_cache` |
| `global.score_segments_sprites` | array | Per-segment sprite cache: `[{sprites, pbmap, meta, durations, units_per_measure, has_pickup}]`, one entry per set segment | `scr_set_scripts` `scr_set_init_global()` | `scr_button_scripts` (populate), `gv_restore_score_segment_cache`, `gv_build_set_measure_nav_all` |
| `global.playback_set_measure_nav_all` | array | Flat sorted measure-nav table across all set segments: `[{measure, part, start_ms, end_ms, status, segment_idx}]`; built once at load time | `scr_set_scripts` `scr_set_init_global()` | `gv_get_current_planned_measure` (Priority 0 in set mode), `gv_build_set_measure_nav_all` |
| `global.EVENT_HISTORY` | array | Append-only event log during playback — see struct schema below | `scr_event_log` (lazy init) | `scr_event_log`, export functions |
| `global.EVENT_HISTORY_ENABLED` | bool | Master on/off for event logging | `scr_event_log` (lazy init) | `scr_event_log` |
| `global.EVENT_HISTORY_AUTO_EXPORT` | bool | Auto-export CSV after playback ends | `scr_event_log` (lazy init) | `scr_event_log` |
| `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS` | bool | Export-time filter toggle for planned `source="game"` rows (live history unchanged) | `scr_event_log` (lazy init) | `event_history_export_csv`, `event_history_export_summary_json` |
| `global.PERF_BENCHMARK_POWER_MODE_LABEL` | string | Manual benchmark tag for power plan (`balanced`, `high_performance`, etc.) | `scr_event_log` (lazy init) | export metadata |
| `global.PERF_BENCHMARK_MIDI_ACTIVITY_LABEL` | string | Manual benchmark tag for input activity (`idle`, `active_input`, etc.) | `scr_event_log` (lazy init) | export metadata |
| `global.PERF_BENCHMARK_NOTES` | string | Freeform benchmark notes attached to summary exports | `scr_event_log` (lazy init) | export metadata |
| `global.perf_run_last_elapsed_ms` | real | Most recent run elapsed time captured at PLAY_STOP for compact performance summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.perf_run_last_groups_total` | real | Most recent run event-group count captured for compact summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.perf_run_last_events_total` | real | Most recent run event count captured for compact summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.rt_budget_sched_spike_count` | real | Count of emitted scheduler spike traces for the current run | `scr_tune_scripts` `tune_start`/`tune_rt_budget_diag_trace_scheduler_spike` | `perf_run_summary_append_latest` |
| `global.perf_run_summary_last_written_play_id` | real | Last play ID written to `run_summaries.jsonl`, used to avoid duplicate append on cleanup reentry | `scr_tune_scripts` `perf_run_summary_append_latest` | `perf_run_summary_append_latest` |
| `global.scoring_last_run` | struct\|undefined | Result of most recent scoring run; undefined until first run | `scr_scoring` (lazy init) | `scr_scoring`, UI display |
| `global.timing_calibration` | struct | Two-offset calibration state: `{active, status, active_device_key, device_profiles, audio_offset_ms, visual_offset_ms, input_offset_ms (reserved), last_message, jitter_summary, calibration_mode_index, calibration_advanced_open, calibration_preview, calibration_logs, calibration_result}` | `scr_tune_scripts` (lazy init) | `scr_tune_scripts` timing calibration functions, `scr_button_scripts` calibration UI refresh/actions |
| `global.metronome_mode` | real | 0=None 1=Click 2=Drums | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts`, `scr_scoring` |
| `global.metronome_pattern_selection` | real | Index into `global.metronome_pattern_options` | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts` |
| `global.metronome_volume` | real | MIDI velocity 0–127 | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts` |
| `global.single_tune_runtime_bpm` | real | Single-tune authoritative BPM mirror used when UI field binding is unavailable at play time | `scr_button_scripts` (lazy set in tune load/BPM changes) | `scr_button_scripts` |
| `global.swing_mult` | real | Swing multiplier; 0 = use default | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_button_scripts` |
| `global.gracenote_override_ms` | real | Gracenote duration override; 0 = BPM-derived | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_embellishments` |
| `global.MIDI_chanter` | string | Chanter mapping preset (`"default"` or `"blair"`) | `obj_game_controller` Create | `scr_MIDI`, `scr_scoring` |
| `global.midi_input_device` | real | Device index for MIDI input | `obj_game_controller` Create | `scr_MIDI`, `scr_button_scripts` |
| `global.midi_output_device` | real | Device index for MIDI output | `obj_game_controller` Create | `scr_MIDI`, `scr_button_scripts` |
| `global.GAME_STEP_FPS` | real | Game step rate (game_set_speed); higher = less scheduler jitter | `obj_game_controller` Create | `obj_game_controller` only |
| `global.PLAYBACK_SCHEDULER_MODE` | string | `"timesource"` or `"step"` | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_DRAIN_MS` | real | Time-source startup slack used to inline the first near-due group instead of arming a late first callback | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_ARM_DELAY_MS` | real | Extra startup delay applied only to the first time-source arm; tune start is re-anchored so scheduler timing stays aligned | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_SPIKE_GRACE_MS` | real | Startup grace window that suppresses scheduler spike trace emission near tune start | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.game_state` | string | `"menu"` \| `"playing"` \| …  | `obj_game_controller` Create | `scr_button_scripts`, various |
| `global.ID_game_handler` | instance id | Self-reference for `obj_game_controller` | `obj_game_controller` Create | global access |
| `global.ui_assets` | array | UI instance registry by layer: `[[ui_num, id], …]` per layer index | `obj_ui_controller` Create | `obj_UI_parent`, `scr_UI_scripts` |
| `global.ui_fields` | array | Registered field instances per layer | `obj_ui_controller` Create | `scr_UI_scripts` |
| `global.ui_layer_names` | array | Layer name strings indexed by layer num | `obj_ui_controller` Create | `scr_UI_scripts` |
| `global.show_review_beat_bands` | bool | Overlay toggle: beat bands in post-play review | `obj_game_controller` Create | `scr_game_viz` |
| `global.show_review_emb_boxes` | bool | Overlay toggle: embellishment boxes in post-play review | `obj_game_controller` Create | `scr_game_viz` |
| `global.loop_mode_enabled` | bool | Loop playback on/off | `obj_game_controller` Create | `scr_tune_scripts`, `scr_button_scripts` |
| `global.loop_repeat_total` | real | How many times to loop | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.loop_score_overview_ui_state` | struct | UI scroll state for loop score overview panel: `{scroll_row}` | `scr_scoring` (lazy init via `scoring_loop_overview_ensure_state`) | `scr_scoring` draw/scroll helpers |
| `global.timeline_state.loop_iteration_scores` | array | Per-iteration score results from last loop session: `[{iteration, score, grade, start_ms, end_ms}]` — field on `timeline_state` | `scr_scoring` `scoring_build_loop_iteration_scores()` | `scoring_loop_overview_draw_canvas`, overview panel |

---

## Key Struct Schemas

These are the shared data "vocabulary" of the codebase. When reading/writing these structs, match these field names exactly.

### `set_item` — single tune entry in a set/playlist
Created by `create_set_item()` in `scr_tune_scripts`.
```
{
    tune_filename:         string,   // relative path e.g. "tunes/Foo/Foo.json"
    bpm:                   real|undefined,  // undefined = use tune metadata default
    metronome_mode:        real,     // 0=None 1=Click 2=Drums
    metronome_pattern:     real,     // index into pattern_options
    metronome_volume:      real,     // 0-127
    count_in_measures:     real,     // number of count-in bars before tune
    loop_jump_to_selection: bool,
    include_drum_roll:     bool,
    drum_roll_variant:     string|undefined
}
```

### `tune_data` — loaded tune (on `obj_tune` instance)
Populated by `scr_tune_load_json()`.
```
{
    tune_metadata:  struct,   // title, tempo_default, meter, part, …
  score_manifest: struct,   // parsed score/score_images.json (flat or transition-grouped)
    events:         array,    // raw ABC/JSON event structs
    performance:    struct,   // performance-level settings from JSON
    event_count:    real,
    is_loaded:      bool,
    filename:       string
}
```

### `timeline_state` — runtime playback + visualization state
Initialized in `obj_game_viz` Create. Owns the live playhead and all span arrays.
```
{
    active:             bool,
    playhead_ms:        real,
    start_clock_ms:     real,
    bpm:                real,
    meter_num:          real,
    meter_den:          real,
    measure_ms:         real,
    ms_ahead:           real,    // lookahead window for notebeam
    ms_behind:          real,    // lookbehind window for notebeam
    planned_events:     array,   // ref to preprocessed event array
    planned_spans:      array,   // [{start_ms, end_ms, note, channel, is_embellishment}]
    tune_played:        array,   // append-only game note_on/off events
    player_in:          array,   // append-only player note_on/off events
    pending_tune:       struct,  // open note_on pairs awaiting note_off (keyed by "ch:note")
    pending_player:     struct,
    planned_i0:         real,    // cached visible window start index into planned_events
    planned_i1:         real,    // cached visible window end index
    planned_span_i0:    real,
    planned_span_i1:    real,
    measure_nav_entries:    array,
    measure_nav_parts:      array,
    measure_nav_tile_hitboxes: array,
    measure_nav_scroll_row: real,
    measure_nav_total_rows: real,
    measure_nav_view_rows:  real,
    measure_nav_controls:   struct,
    anchor_id:          noone|instance_id
}
```

### `planned_span` — one note span for visualization
Elements of `global.timeline_state.planned_spans[]`. Created by `gv_build_planned_spans()`.
```
{
    source:           string,  // "tune_planned"
    start_ms:         real,
    end_ms:           real,
    dur_ms:           real,
    note_midi:        real,
    note_canonical:   string,
    note_letter:      string,
    lane_idx:         real,
    channel:          real,
    is_embellishment: bool,
    measure:          real,
    beat:             real,
    beat_fraction:    real,
    event_id:         any
}
```
**Important:** `planned_spans` contains spans for the *entire set* (all tunes), including transition tunes. Spans are NOT pre-clipped to segment boundaries. When computing per-segment scores or overlays, always pass spans through `scoring_filter_spans_in_window()` which clips `start_ms`/`end_ms` to the window — a span that merely overlaps the window boundary is returned with its times clamped, not its original full length.

### `active_set` — loaded musical set metadata
Initialized by `scr_set_init_global()`, populated by `scr_set_load_json()`.
```
{
    is_loaded:       bool,
    filename:        string,
    title:           string,
    id:              string,
    description:     string,
    tunes:           array,   // raw tune entries from JSON
    segments:        array,   // preprocessed segment structs (end_ms includes boundary lead-in)
  score_override_plan: array, // per-segment tail/bridge/head score override metadata
  boundary_plan:       array, // transition-authoritative boundary plan (scr_set_build_boundary_plan)
    active_segment_index: real,
    first_bpm:       real,
    first_meter:     string,
    set_bpm_percent:           real,      // 1.0 = normal speed
    set_gracenote_override_ms: real|undefined,
    set_count_in_measures:     real
}
```
**Boundary lead-in note:** `segments[i].end_ms` now includes any fallback lead-in duration appended to tune i's content (Option 2 model). The next segment's `start_ms` equals the previous `end_ms`, so the hold window is attributed to the tune whose note is held.

### `playback_context` — thin navigation wrapper for viz/scoring/export
```
{
    mode:           string,   // "none" | "tune" | "set"
    display_title:  string,
    active_segment: real,
  score_override_plan: array,
    segments: [{
        tune_index:  real,
        filename:    string,
        title:       string,
        bpm:         real,
        meter:       string,
        start_ms:    real,
        end_ms:      real,
    bar_events:  array,   // marker events with type "bar"|"beat"
    score_manifest: struct|undefined
    }]
}
```

### `EVENT_HISTORY` entry — one logged playback event
Elements of `global.EVENT_HISTORY[]`. Appended by `event_history_add()`.
```
{
    timestamp_ms:      real,
    expected_time_ms:  real,
    actual_time_ms:    real,
    delta_ms:          real,
    measure:           real,
    beat:              real,
    beat_fraction:     real,
    event_type:        string,   // "note_on" | "note_off"
    source:            string,   // "game" | "player" | "metronome"
    note_midi:         real,
    note_letter:       string,
    tune_name:         string,
    is_embellishment:  bool
}
```

### `EMBELLISHMENT_CONFIG` — gracenote timing constants
```
{
    gracenote_unit_ms_base:     real,   // base unit at reference_bpm
    min_gracenote_ms:           real,
    max_gracenote_ms:           real,
    bpm_scaling_factor:         real,   // ms per BPM increase (negative)
    reference_bpm:              real,
    max_emb_percent:            real,   // max fraction of target note stolen
    fallback_min_ms:            real,
    fallback_max_ms:            real,
    fallback_fast_bpm_threshold: real,
    fallback_slow_bpm_threshold: real
}
```

---

## Tune subsystem (current state)

### File Organization
- **Source:** `datafiles/tunes/` contains tune JSON files (e.g., `Jig_of_Slurs.json`, `Scotland_the_Brave.json`).
- **Runtime:** Files must be marked as **Included Files** in the GameMaker project so they're copied to the runtime directory (`tunes/` at game runtime, not `datafiles/tunes/`).

### Library Building & Loading
- **Build process:** `scr_build_tune_library(_folder)` scans a folder recursively for `*.json` files (excluding `tune_library.json`, `score_images.json`, and score sidecar files `*.score_snippets.json`, `*.score_groups.json`, `*.score_part*.json`), parses tune metadata, and writes an index file `tune_library.json` containing all discovered tunes.
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

### Log locations (runtime)
- **General debug stream (`show_debug_message`)**:
  - Goes to the GameMaker/IDE Output stream.
  - Includes BPM diagnostics such as `[BPM-CHANGE]`, `[BPM-REBUILD]`, `[START-PLAY]`, and `[START-PLAY-BPM]`.
  - When Logs is ON, these BPM lines are mirrored to the score-lane debug file by `scr_button_bpm_debug_log`.
- **Settings > Logs toggle (`setting_field_logs`)**:
  - Enables `global.timeline_cfg.score_lane_debug_log` and `global.timeline_cfg.score_lane_debug_file_log`.
  - This is specifically for score-lane diagnostics in `scr_game_viz`, not a global redirect of all `show_debug_message` output.
- **Score-lane debug file path**:
  - Config key: `global.timeline_cfg.score_lane_debug_file_path`.
  - Default fallback in code: `score_lane_debug.log` (relative to GameMaker `working_directory`).
  - Current workspace example file: `datafiles/debug/score_lane_debug.latest.log`.
- **Event history and performance exports**:
  - Event CSV export writes under `datafiles/` via `event_history_export_csv` and includes split timing columns (`canonical_time_ms`, `audio_target_time_ms`, `visual_target_time_ms`, `input_aligned_time_ms`, plus offset columns).
  - Session/performance artifacts write under `datafiles/performances/`.

Troubleshooting tip: for BPM issues you can use either Output or the score-lane log file (Logs ON). For score/image mapping issues, use the score-lane file log.

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

---

## Notebeam draw architecture

The notebeam canvas is rendered frame-by-frame inside `scr_game_viz.gml` (the main draw function called from `obj_game_viz` Draw event). There are **three distinct note-beam categories**, each drawn separately:

### 1. Planned spans (tune as written)
- Source: `global.timeline_state.planned_spans` (full set, built by `gv_build_planned_spans` at `gv_bind_timeline_on_tune_start`).
- Drawn by: `gv_draw_planned_row()` (row view) and `gv_draw_notebeam_underlay_layers()` (lane view).
- Colour: `planned_bar_color` / `timeline_cfg.planned_bar_color` (default aqua).
- **Dangling tail rule:** unmatched `note_on` events (e.g. transition tune's last note) get a 90 ms synthetic tail — NOT extended to the last event in the set. See `_dangling_tail_ms = 90` in `gv_build_planned_spans`.

### 2. Completed player spans (`player_in`)
- Source: `global.timeline_state.player_in` (committed after note_off) or `review_full_trace` in review mode.
- Drawn by: `gv_render_notebeam_live_player_surface()` (cached; live mode only) or the main per-span loop.
- Colour during live play (non-review, non-overlay): `player_beam_render_color` = `live_player_beam_color` when `review_mode_active`, else `player_beam_color`.
- Colour in review mode with `postplay_overlay_mode==1`: coloured green/red/split by `review_match_state` (pre-classified in `gv_on_tune_playback_finished`).

### 3. Pending (in-progress) player span
- Source: `global.timeline_state.pending_player` — a struct keyed by note key; one entry per currently-held note.
- Drawn by: the `pending_player` loop at end of main draw step (`draw_line_width` directly to canvas).
- Colour: **always `live_player_beam_color`** (the same blue as completed beams) — do NOT change this to `player_beam_render_color`, which is grey during live play.
- `overlay_mode==1` path: uses `gv_player_span_classify_and_draw()` same as completed spans.

### `player_beam_render_color` gotcha
`player_beam_render_color = use_live_blue_beams ? live_player_beam_color : player_beam_color`  
where `use_live_blue_beams = review_mode_active && (postplay_overlay_mode != 1)`.  
This means `player_beam_render_color` is **grey** (`player_beam_color`) during live play. Do not use it for the pending span — use `live_player_beam_color` directly.

### Pre-classification (`review_match_state`)
Computed once in `gv_on_tune_playback_finished` after scoring. Stored on each span in `review_full_trace`. Values: 0=miss, 1=bleed (partial overlap), 2=match. Used by the draw loop to avoid O(N×M) comparison per frame. Only valid when `can_compare_overlap` is true (requires `postplay_overlay_mode==1`).


---

## How To Do X � Integration Patterns Cookbook

Recurring patterns for extending the project. Read the relevant pattern before adding new code.

---

### Pattern 1: Adding a new button

**Use case:** A new clickable button in any UI window/layer.

**Steps:**

1. **Place the instance in RoomUI** (Room UI editor ? target layer ? drag in `obj_btn_main` or another button object). Set these override properties:
   - `button_script_index` � the index in the `button_scripts[]` dispatch array (see step 2).
   - `button_target` � layer name or value passed to the handler (optional; set to `""` if unused).
   - `button_ID` � unique integer in the layer (used for stable pairing; avoids reliance on runtime registration order).

2. **Register the handler** in `scr_button_scripts.gml` ? `scr_handle_button_click()` dispatch array. Add a new `case` for the index you chose, or append a new entry to the `button_scripts` array at initialization.

3. **Write the handler function** in `scr_button_scripts.gml`. Follow the naming convention `scr_<action>()`. Annotate with the full `/// @` template (include `@reads`, `@writes`, and `@callers`).

4. **Update WORKSPACE_MAP.md** � add a row to the `scr_button_scripts` function table.

**Key functions:** `scr_handle_button_click()`, `scr_button_scripts` dispatch table.  
**Key globals:** `global.ui_assets` (registered at runtime by `obj_UI_parent`).

---

### Pattern 2: Adding a new global variable

**Use case:** A new piece of shared runtime state needed by more than one script.

**Rules:**
- Globals are **owned by one script** (the one that initializes them). Document the owner in `@writes`.
- Prefer a **struct field** on an existing global struct (`global.timeline_cfg`, `global.timeline_state`, `global.playback_context`) over a new top-level global wherever the new value is conceptually part of that system.
- Use a **top-level global scalar** only for system-wide flags, caches, or values that belong to no existing struct.
- Never use `ds_map` / `ds_list` � use structs and arrays.

**Steps:**

1. **Choose ownership:** decide which script initializes it (Create event of an object, or a `scr_*_init` / `gv_ensure_*_defaults` function).
2. **Initialize defensively:** use `if (!variable_global_exists("my_var")) global.my_var = <default>` at the top of the owning function, or declare it in the object's Create event.
3. **Check existence before reading** in non-owning scripts: `if (variable_global_exists("my_var") && ...)`.
4. **Annotate:** every function that reads it gets `@reads global.my_var`; every function that writes it gets `@writes global.my_var`.
5. **Add to the Global State Inventory table** in this file.

**Avoid:** writing to globals inside pure-utility or drawing functions � route writes through a dedicated setter or the owning init function.

---

### Pattern 3: Adding a new tune event type

**Use case:** A new kind of event that appears in a tune's event list and needs to trigger behavior during playback.

The pipeline has four stages. Touch all four.

**Stage 1 � Preprocess (`scr_preprocess_tune.gml`)**
- Open `preprocess_tune()` and add a new `case` (or condition) for your event type string.
- Compute any derived fields (e.g., `time_ms`, canonical note name) and store them in the event struct.
- Add a `@reads`/`@writes` annotation update if you touch new globals.

**Stage 2 � Playback callback (`scr_tune_scripts.gml` ? `script_tune_callback()`)**
- Add a new `case` in the callback's event-type dispatch.
- Call the appropriate action: send MIDI via `midi_send_*()`, update a global, call a viz binding function like `gv_on_player_note_on()`.
- Keep the callback fast � defer any heavy work to the post-play or step phases.

**Stage 3 � Event log (`scr_event_log.gml`)**
- If the event should appear in the performance history (for CSV export or review overlay), add it to `event_history_log_entry()` or call `event_history_append()` with an appropriate struct.
- Follow the existing `event_history_entry` shape: `{ time_ms, beat_fraction, event_type, source, note_midi, note_letter, tune_name, is_embellishment }`.

**Stage 4 � Visualization (optional, `scr_game_viz.gml`)**
- If the event needs a visual representation in the notebeam or timeline canvas, add it to `gv_get_planned_events_for_viz()` (filter) and/or `gv_build_planned_spans()` (span conversion).
- For a new overlay element, follow the pattern of `gv_draw_notebeam_emb_group_boxes()` � build a data array at bind time, draw from it each frame.
- Structure-row measure labels in `gv_draw_structure_row()` use `marker_type="bar"` as the authoritative source; `marker_type="beat"` labels are fallback-only when bar markers are unavailable.

---

### Pattern 4: Adding a new UI window or layer

**Use case:** A new modal panel or persistent overlay (e.g., a help screen, a new settings group, a score summary window).

**Steps:**

1. **Create the layer in RoomUI** (Room UI editor ? add layer ? name it `<name>_layer` by convention). Set initial visibility to hidden (`layer_set_visible(layer, false)` or unchecked in editor).

2. **Populate the layer** with the relevant `obj_field_base`, `obj_btn_main`, `obj_btn_winClose`, etc. instances. Set `button_ID` / `field_ID` overrides for stable registration ordering.

3. **Add a close button** (`obj_btn_winClose` with `button_script_index` mapped to `scr_toggle_window_visibility` or a dedicated close handler). The close handler typically calls `layer_set_visible(layer_name, false)`.

4. **Add an open trigger** � usually a new button on an existing layer (see Pattern 1) with `button_target` = `"<name>_layer"` and `button_script_index` mapped to `scr_toggle_window_visibility` (the generic show/hide handler in `scr_button_scripts`).

5. **Register any fields** that need runtime data via `scr_update_fields()`. If the window shows tune or set data, hook into the post-load flow via `scr_button_apply_post_tune_load_ui()` or call `scr_ui_refresh()` from the opener.

6. **Document the layer** in the "Per-layer summaries" section of this file.

**Key functions:** `scr_toggle_window_visibility()`, `scr_ui_refresh()`, `scr_update_fields()`.  
**Key globals:** `global.ui_assets` (all registered UI instances), layer functions `layer_set_visible()`.
