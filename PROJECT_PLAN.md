🎯 Vision (End State)
**1. Purpose — Why this exists**
This project is a music‑training tool designed to give bagpipers objective, data‑driven feedback on timing, embellishment execution, and overall musical accuracy. Traditional practice relies heavily on subjective listening and instructor feedback; this tool provides measurable, repeatable analysis similar to rhythm‑game systems, but grounded in real bagpipe technique and musical structure. The goal is to help pipers improve faster, practice more effectively, and understand their playing with unprecedented clarity.

**2. High‑Level Experience**
The finished system allows a player to:
• 	Select a tune from a rich, searchable library
• 	Configure tempo, metronome patterns, parts, and playback options
• 	Create multi tune sets, where each tune options (tempo, metronome, parts, ...) can be customized 
• 	Play along with the tune using a MIDI bagpipe chanter
• 	See real‑time visual feedback (piano‑roll bars, musical score, measure tracker)
• 	Hear synchronized playback of pipes, harmonies, drums, and metronome
• 	Receive detailed post‑play analysis of timing, embellishments, and technique
• 	Track performance trends over time
The experience should feel polished, musical, and intuitive — like a hybrid of a rhythm game and a professional practice tool.

**3. Musical Domain**
The system supports the full structure of pipe band music:
• 	Main bagpipe melody
• 	Additional bagpipe parts (harmonies, seconds, thirds)
• 	Drum corps parts (snare, tenor, bass)
• 	Configurable metronome patterns (beats, accents, subdivisions)
• 	Lead‑ins, pipe band drum rolls, initial E, and transitions
• 	Multi‑tune sets with seamless linking and customized transitions


**4. Tune Pipeline **
Tunes originate from ABC notation, are edited in Excel, and exported as JSON containing metadata and event lists. Embellishments are represented as events and expanded into detailed timing sequences according to user‑configurable rules, which can be customized.
• 	JSON includes metadata, parts, embellishments, and structural events
• 	Embellishments expand according to tune type, user preferences, and style rules
• 	Preprocessing converts musical durations into millisecond‑accurate timestamps
• 	All parts (pipes, drums, metronome, transitions) merge into a unified event stream
This ensures deterministic, real‑time playback with no per‑frame computation overhead.

### Calibration Phase 1 Rollback & Stabilization (2026-05-17)
**Status**: ✅ Complete — Game fully playable with multi-tune sets.

**What was removed:**
- All Phase 1 dual-probe timing calibration logic (click/visual/balanced modes)
- Calibration workflow UI elements and measurement windows
- MIDI tap logging for calibration probes
- Post-playback calibration probes (`timing_calibration_probe_from_current_run()`)
- Draft offset preparation and session acceptance flows

**What was fixed:**
- Removed dead code reading `prof.mode` from saved profiles (caused crash on load)
  - Old profiles still load correctly; `mode` field ignored since calibration disabled
  - Applied principle: **fix root cause (don't need mode), not fallback masking**

**Current state:**
- Timing offsets (audio/visual/input/scoring) persist and load correctly
- Per-device profile storage works (without mode tracking)
- Baseline stable for single-tune and multi-tune set playback
- Ready for manual offset UI or redesigned calibration (Phase 2)

**Process lesson learned:**
- Isolated experimental code was **not** isolated — calibration touched core timing paths
- Need feature-flagging / separate branches for risky rewrites
- All changes must compile cleanly before commit (avoid "works on my machine" dead code)
- See "Development Workflow Hardening" section below for future guidelines

### Loop Runtime Precompute Pass (2026-05-12)
- Added one-time loop runtime cache build in `scr_game_viz` (`gv_build_loop_runtime_cache`) to precompute:
  - loop iteration anchors (`iter1_start_ms`, `iter2_start_ms`, `loop_cycle_ms`)
  - pickup-aligned per-measure starts for a single loop cycle
  - fallback measure duration for score-lane span closure
- Wired cache creation into timeline bind (`gv_bind_timeline_on_tune_start`) for single-tune loop runtime.
- Replaced per-frame loop cycle scans in:
  - current-measure resolver (`gv_get_current_planned_measure`)
  - score-lane draw playhead normalization (`gv_draw_timeline_canvas_overlay`)
- In score-lane draw, use precomputed measure starts when loop cache is valid; keep legacy runtime scan as fallback only.
- Loop reset now clears cached loop runtime data (`scr_button_reset_loop_state`) to avoid stale cross-run timing.

Validation targets:
- Aros Park loop with internal pickup at loop start: no stretched pickup image and stable playhead wrap.
- No behavior change to repeat count, blank measure insertion, or jump-to-selection semantics.



## ⚡ 1-Minute UI Pre-Run Checklist

Before pressing **Run**:

- [ ] `obj_ui_controller` layer registration includes all active UI layers (exact names/case).
- [ ] No UI instance has `ui_layer_num = -1`.
- [ ] Every new UI instance has a unique `ui_num` (within its layer).
- [ ] Every UI element has a stable unique `ui_name` (recommended globally unique).
- [ ] Any renamed layer references in scripts were updated (e.g., old `gameinfo_UI_layer` names removed).
- [ ] New buttons have valid `button_script_index` and required `button_click_value`.
- [ ] New fields have expected defaults (`field_contents`, IDs/targets if used).
- [ ] Launch once and confirm no UI registration errors on Create.


## Refactor Baseline Snapshot (2026-03-23)

Captured from a full playthrough and post-play review run in Room_play.

### Playback baseline (stable window)
- controller_step_interval_ms: p50=2.000, p95=2.000, p99=2.000, max typically 2-4
- draw_ms: p50=0.001, p95=0.002, p99=0.002
- midi_process_ms: p50=0.004-0.005, p95=0.008-0.011
- anchor_draw_ms kind=notebeam: p50 around 0.008-0.011, p95 around 0.65-1.16
- anchor_draw_ms kind=tunestructure: p50 around 0.006-0.008, p95 around 0.009-0.017
- scheduler_late_ms: p50=2.000, p95=2.000, p99=2.000 during active playback

### Post-play / cleanup behavior (expected spikes)
- timeline anchor draw can spike to ~9-12 ms while review history/export cleanup is running
- controller_step_interval_ms can spike into ~12-16 ms during cleanup and export windows
- rare isolated outliers were observed (for example one notebeam anchor max near 57 ms)

### Refactor guardrails
- Treat playback-window metrics as the non-regression baseline for refactor check-ins.
- Cleanup/export spikes are acceptable if they do not bleed into active playback responsiveness.
- Any sustained rise in playback p95 for draw_ms or controller_step_interval_ms above 10 percent triggers rollback/rework of the current batch.

### Check-in Update (2026-03-23, after Batch 2)
- Status: pass (no playback-window regression detected)

Playback window summary:
- controller_step_interval_ms: p50=2.000, p95=2.000-3.000, p99=3.000, max typically 3-4
- draw_ms: p50=0.001, p95=0.001-0.002, p99=0.002-0.003
- midi_process_ms: p50=0.004-0.005, p95=0.006-0.014
- anchor_draw_ms kind=notebeam: p50 around 0.007-0.011, p95 around 0.63-1.00
- anchor_draw_ms kind=tunestructure: p50 around 0.005-0.007, p95 around 0.008-0.014
- scheduler_late_ms: p50=2.000, p95=2.000, p99=2.000-3.000

Post-play / cleanup window summary:
- timeline anchor draw still spikes around 10-12 ms (expected cleanup/export behavior)
- controller_step_interval_ms spikes around 13-16 ms during cleanup windows (expected)
- rare isolated outliers remain possible during cleanup (for example one tunestructure max around 95.9 ms)

Conclusion:
- Active playback remains stable and within guardrails.
- Observed spikes are still concentrated in post-play cleanup/export phases.

### Check-in Update (2026-03-23, after helper consolidations)
- Status: pass (no playback-window regression detected)

Playback window summary:
- controller_step_interval_ms: p50=2.000, p95=2.000-3.000, p99=3.000, max typically 3-4
- draw_ms: p50=0.001, p95=0.001-0.002, p99=0.002-0.003
- midi_process_ms: p50=0.004-0.005, p95=0.007-0.012
- anchor_draw_ms kind=notebeam: p50 around 0.008-0.013, p95 around 0.53-1.09
- anchor_draw_ms kind=tunestructure: p50 around 0.006-0.009, p95 around 0.010-0.022
- scheduler_late_ms: p50 around 2.000, p95 around 2.000-3.000

Post-play / cleanup window summary:
- export and cleanup complete successfully (CSV + summary JSON exported)
- no sustained playback-window regression observed before cleanup transition
- calibration recommendation remained in expected range for this run (11 ms)

Conclusion:
- Refactor helper extractions remain stable under gameplay load.
- Performance profile stays within the same envelope as prior baseline runs.

### Hotfix Update (2026-03-24, back button crash)
- Status: pass (runtime blocker removed)

Fix summary:
- Removed stale `timing_calibration_cancel(...)` call from `scr_goto_mainmenu()` in `scr_button_scripts`.
- Back navigation now safely deactivates calibration state via `global.timing_calibration` when present.

Validation:
- Static error check on `scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 1)
- Status: pass (low-risk obsolete code removed)

Change summary:
- Removed dead legacy toggle initialization `LEGACY_NOTEBEAM_NOWLINE_IN_ANCHOR` from `obj_game_viz` Create.
- Verified symbol usage first: it was defined once and never read anywhere in project scripts/objects.

Validation:
- Static error check on `objects/obj_game_viz/Create_0.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 2)
- Status: pass (low-risk redundant fallback removed)

Change summary:
- In `obj_tune_picker` Step, removed the fallback branch that repopulated the tune list when `scr_tune_picker_refresh_visible_rows()` was unavailable.
- The helper exists in `scr_tune_library` and is part of the active tune picker path, so the fallback was redundant.

Validation:
- Static error check on `objects/obj_tune_picker/Step_0.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 3)
- Status: pass (redundant helper-availability branches removed)

Change summary:
- In `obj_tune_picker` Step, removed defensive `is_undefined(...)` branches around tune-picker helper calls.
- Step now directly uses `scr_tune_picker_get_mouse_gui_x/y`, `scr_tune_picker_handle_click`, `scr_tune_picker_is_pointer_over_list`, `scr_tune_picker_scroll_rows`, and `scr_tune_picker_refresh_visible_rows`.
- Verified helper definitions in `scr_tune_library` before simplification.

Validation:
- Static error check on `objects/obj_tune_picker/Step_0.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 4)
- Status: pass (redundant draw-event helper guard removed)

Change summary:
- In `obj_tune_picker` Draw GUI event, removed the `is_undefined(scr_tune_picker_draw_canvas)` guard and now call `scr_tune_picker_draw_canvas()` directly.
- Verified helper definition exists in `scr_tune_library` before the change.

Validation:
- Static error check on `objects/obj_tune_picker/Draw_64.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 5)
- Status: pass (redundant checkbox compatibility chain removed)

Change summary:
- In `scr_checkbox_click` (`scr_button_scripts`), replaced multi-branch `is_undefined(...)` selection/clear fallbacks with direct calls to the canonical tune-picker helpers:
  - `scr_tune_picker_select_index`
  - `scr_tune_picker_sync_selected_entry_ui`
  - `scr_tune_picker_clear_selection`
  - `scr_tune_picker_refresh_visible_rows`
- Kept existing `picker != noone` guards unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 6)
- Status: pass (additional tune-picker compatibility branches removed)

Change summary:
- In `scr_button_scripts`, removed redundant `is_undefined(...)` branches for tune-picker helper access in:
  - tune selection/load path (`scr_tune_picker_get_selected_entry`, `scr_tune_picker_get_library`, `scr_tune_picker_get_instance_var`)
  - part-channel detection (`scr_tune_picker_collect_player_part_channels`)
  - library regeneration path (`scr_tune_picker_set_instance_var`)
- Replaced with direct calls to canonical helper functions already defined in `scr_tune_library`.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 7)
- Status: pass (redundant rebuild helper guard removed)

Change summary:
- In `scr_load_tune_library` (`scr_tune_library`), removed `is_undefined(scr_build_tune_library)` check before rebuild.
- `scr_build_tune_library` is defined in the same script file and is part of the active library rebuild flow.

Validation:
- Static error check on `scripts/scr_tune_library/scr_tune_library.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 8)
- Status: pass (obsolete commented legacy block removed)

Change summary:
- Removed a stale commented-out legacy playback start block from `scr_button_scripts`.
- Active runtime path and diagnostics remain unchanged; this is source-clarity cleanup only.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 9)
- Status: pass (temporary debug logging pruned)

Change summary:
- Removed temporary timeline debug block in play-start flow from `scr_button_scripts` (`planned_spans` length probe + log).
- Kept behavior and error handling unchanged (`tune_start` success/fail flow is intact).

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 10)
- Status: pass (debug log noise reduced)

Change summary:
- Removed one DEBUG-tagged informational line from `scr_button_scripts` in tune start path:
  - `"DEBUG: Before preprocessing - tune.events length ..."`
- Left non-debug status/error logging in place.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 11)
- Status: pass (redundant playback-ready log removed)

Change summary:
- In `scr_goto_playroom` (`scr_button_scripts`), removed duplicate success logging after merge.
- Kept the detailed merged-count log and all warning/error logs.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 12)
- Status: pass (commented debug scaffolding removed)

Change summary:
- In `scr_uncheck_all` (`scr_button_scripts`), removed obsolete commented debug loops/branches that no longer affected behavior.
- Kept active checkbox uncheck and re-link logic unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 13)
- Status: pass (checkbox log noise reduced)

Change summary:
- In `scr_checkbox_click` (`scr_button_scripts`), removed two non-essential informational logs:
  - `input: ...`
  - `tune selection: ...`
- Selection behavior and UI sync calls are unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 14)
- Status: pass (regeneration log output simplified)

Change summary:
- In `scr_regenerate_tune_library` (`scr_button_scripts`), removed decorative start/end banner logs.
- Kept functional behavior and retained useful tune-count completion log.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Runtime Checkpoint (2026-03-24, user validation after batches 1-14)
- Status: pass (functional + perf envelope stable)

Observed behavior:
- Full flow completed successfully: play room start, tune run, post-play export, cleanup, back to main menu, reopen UI layers, tune reload.
- Prior runtime blocker remains resolved: back-to-main-menu path completed without crash.

Playback-window perf snapshot:
- controller_step_interval_ms remained centered at ~2.000 ms (p95 usually 2.000, occasional 3.000-4.000 max outliers).
- draw_ms remained very low (p50 around 0.001, p95 around 0.001-0.002).
- midi_process_ms remained low (p50 around 0.004, p95 usually around 0.007-0.012, with occasional isolated higher maxima).
- anchor_draw_ms stayed in expected ranges for notebeam/gameviz/tunestructure/timeline during active playback.

Post-play/cleanup window notes:
- Expected review/export/cleanup spikes observed (for example timeline anchor draw p95 around ~5.7 ms and step-interval spikes during cleanup windows).
- Spikes stayed concentrated in post-play phases and did not present as sustained active-playback regression.

Follow-up note:
- `switch 0` / `tune_library_canvas_anchor: No button action set` log spam is still present and can be cleaned in a future low-risk logging pass.

### Cleanup Update (2026-03-24, post-hotfix batch 15)
- Status: pass (expected no-action anchor log spam suppressed)

Change summary:
- In `scr_script_not_set` (`scr_button_scripts`), added an early return for `ui_name == "tune_library_canvas_anchor"`.
- This keeps diagnostics for genuinely unconfigured buttons while suppressing known passive-anchor noise.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 16)
- Status: pass (button dispatcher log noise reduced)

Change summary:
- In `scr_handle_button_click` (`scr_button_scripts`), removed per-case entry logs for known button actions.
- Preserved diagnostic logging for unexpected IDs via default case (`Unknown button script index: ...`).
- Functional dispatch behavior is unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 17)
- Status: pass (micro-consolidation in checkbox picker flow)

Change summary:
- In `scr_checkbox_click` (`scr_button_scripts`), merged two adjacent `picker != noone` checks into a single block.
- Behavior unchanged; selection and UI sync still run only when the picker instance exists.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 18)
- Status: pass (helper extraction in tune OK flow)

Change summary:
- In `scr_button_scripts`, extracted tune-picker selection resolution into `scr_button_resolve_picker_selection()`.
- `scr_tune_OK` now calls the helper for picker/library/entry lookup and fallback-by-index resolution.
- Behavior unchanged; this is structural simplification for maintainability.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 19)
- Status: pass (candidate-path helper extraction in tune OK flow)

Change summary:
- In `scr_button_scripts`, extracted tune load candidate assembly into `scr_button_build_tune_load_candidates(_library, _filename)`.
- `scr_tune_OK` now delegates candidate-path creation to the helper.
- Behavior unchanged; path preference/order remains the same.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 20)
- Status: pass (UI-field mapping helper extraction in tune OK flow)

Change summary:
- In `scr_button_scripts`, extracted set-item override mapping from UI fields into `scr_button_apply_set_item_from_ui_fields(_item)`.
- `scr_tune_OK` now delegates field-to-override mapping to the helper.
- Behavior unchanged; same field names and target set-item keys are applied.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 21)
- Status: pass (global-assignment helper extraction in tune OK flow)

Change summary:
- In `scr_button_scripts`, extracted set-item-to-global assignment into `scr_button_apply_globals_from_set_item(_item)`.
- `scr_tune_OK` now delegates global playback/metronome/count-in/swing/gracenote assignment to the helper.
- Behavior unchanged; same keys/defaults are applied.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 22)
- Status: pass (post-load UI helper extraction in tune OK flow)

Change summary:
- In `scr_button_scripts`, extracted post-load UI updates into `scr_button_apply_post_tune_load_ui(_button_label, _entry)`.
- `scr_tune_OK` now delegates post-load window/title updates to the helper.
- Behavior unchanged; existing window hide and game-info title update path preserved.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 23)
- Status: pass (set-item summary log helper extraction)

Change summary:
- In `scr_button_scripts`, extracted created-set-item summary logging into `scr_button_log_created_set_item(_tryfile, _item)`.
- `scr_tune_OK` now delegates summary log formatting to the helper.
- Behavior unchanged; message content remains equivalent.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Runtime Checkpoint (2026-03-24, user validation after batch 23)
- Status: pass (functional flow intact; active-playback envelope stable)

Observed behavior:
- Tune startup/play/export/cleanup path completed successfully with no functional regressions reported.
- Back/menu flow remained stable; no recurrence of prior runtime crash path.

Playback-window perf snapshot:
- `controller_step_interval_ms` stayed centered around ~2 ms during active playback (mostly 2-3 ms, occasional 4 ms).
- `draw_ms` remained low (p50 ~0.001, p95 ~0.001-0.002).
- `midi_process_ms` remained low with occasional isolated high maxima.
- Anchor draw metrics for notebeam/gameviz/tunestructure/timeline stayed within expected active-play ranges.

Post-play/cleanup and tail-window notes:
- Expected review/export/cleanup spikes appeared again.
- A heavier transient burst was observed in tail windows (`anchor_draw_ms` notebeam peaks into ~70+ ms and elevated step-interval spikes), then metrics recovered back toward baseline.
- Treat this as a separate profiling target from the current structural cleanup track.

### Runtime Checkpoint (2026-03-24, Jig of Slurs control run)
- Status: pass (no clear active-playback regression)

Observed behavior:
- Same-tune control run completed end-to-end (playback, review/export, cleanup) with no functional failures.
- Playback scheduler remained stable through active tune windows.

Active-playback envelope (control-run summary):
- `controller_step_interval_ms`: p50 near 2.000 ms, p95 mostly 3.000 ms.
- `draw_ms`: p50 near 0.001 ms, p95 around 0.001-0.002 ms.
- `midi_process_ms`: low medians with intermittent isolated spikes.
- `anchor_draw_ms` (notebeam/gameviz/tunestructure/timeline): stayed in expected live-play ranges for this tune size.

### Planning Update (2026-04-12, transition authoring standard)
- Status: complete (template added for repeatable transition creation)

Change summary:
- Added `TRANSITION_TUNE_TEMPLATE.md` to standardize transition-tune authoring.
- Document covers:
  - behavior model (`tail_cut_beats` trims previous tune, `head_cut_beats` trims next tune),
  - required metadata fields,
  - set ordering rule (`Tune A -> Transition -> Tune B`),
  - ABC writing patterns (`e2e2`, `e4`, `e2-e2`) and common pitfalls,
  - quick verification and troubleshooting checklist.

Expected impact:
- Faster creation of new transition tunes.
- Lower risk of repeating earlier cut/stitching authoring mistakes.

Post-play/cleanup notes:
- Cleanup window still shows heavier spikes (for example timeline p95 around ~9-11 ms and elevated step-interval p95 into low teens).
- Pattern remains phase-scoped to post-play/tail windows, not sustained across active playback.

Interpretation:
- Current cleanup/refactor batches continue to appear performance-safe for active play.
- Tail-window spike behavior remains an optimization target, but evidence does not currently indicate a broad regression in core playback cadence.

### Cleanup Update (2026-03-24, post-hotfix batch 24)
- Status: pass (candidate load-attempt helper extraction)

Change summary:
- In `scr_button_scripts`, extracted per-candidate tune-load attempt body into `scr_button_try_load_tune_candidate(_tryfile, _entry, _button_label)`.
- `scr_tune_OK` loop now delegates candidate attempt handling to the helper.
- Behavior unchanged; load/apply/log/post-load flow remains equivalent.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 25)
- Status: pass (stale commented legacy block removed)

Change summary:
- Removed obsolete commented legacy tune-load scaffold at the end of `scr_tune_OK` in `scr_button_scripts`.
- Active code path unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 26)
- Status: pass (restore/exit pattern consolidated in tune OK flow)

Change summary:
- In `scr_tune_OK` (`scr_button_scripts`), consolidated repeated button-label restore calls into one final restore point.
- Kept existing messages and load/hide behavior unchanged.

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Cleanup Update (2026-03-24, post-hotfix batch 27)
- Status: pass (final low-value informational tune-load logs removed)

Change summary:
- In `scr_button_scripts`, removed low-value informational logs in the tune OK candidate-load path:
  - `Tune selected: ...`
  - `Attempting to load tune: ...`
  - `Loaded tune: ...`
  - created-set-item summary logging helper + call
- Kept warning/failure diagnostics in place (`No tune selected`, `No tune filename selected`, `Failed to load tune from candidates`, hide-layer warning).

Validation:
- Static error check on `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.

### Freeze Checkpoint (2026-03-24, post-hotfix cleanup wave)
- Status: ready for runtime gate

Checkpoint summary:
- Planned cleanup wave completed through batch 27.
- All touched files in the final batches are static-clean.
- Next gate is one runtime validation pass to reconfirm active-playback envelope remains stable.

### Runtime Gate (2026-03-24, no audio interface / slower MIDI driver)
- Status: pass (cleanup wave remains functionally and performance safe under slower driver)

Observed behavior:
- End-to-end flow succeeded (playback, review export, summary export, scheduled cleanup, all-notes-off, cleanup complete).
- No functional regressions observed in tune start/play/cleanup paths.

Active-playback profile (driver-constrained run):
- `controller_step_interval_ms`: p50 mostly around 3 ms, p95 around 4-6 ms, p99 around 6-7 ms, occasional peaks up to ~9 ms.
- `scheduler_late_ms`: improved during run windows (typically p95 around 3-4 ms late, p99 around 4-5 ms).
- `scheduler_group_proc_ms` and `midi_send_ms`: elevated versus prior audio-interface runs, with p50 around ~1.0 ms and p95 around ~1.9-2.0 ms in later windows.
- `draw_ms` remained very low (p50 around 0.002 ms), and anchor draw metrics stayed within expected notebeam/tunestructure/gameviz envelopes.

Interpretation:
- The dominant shift is consistent with slower MIDI output path overhead rather than rendering or recent cleanup regressions.
- Cleanup/refactor batches continue to look safe; active-play cadence remains stable enough for this driver class.

Follow-up note:
- If needed, keep a separate baseline profile for "slow MIDI driver / no interface" so future regressions are compared within the same driver class.

### Gameplay Controls Update (2026-03-24, notebeam zoom/pan controls wired)
- Status: pass (UI wiring + script handlers connected)

Change summary:
- Verified the six new notebeam controls exist in RoomUI and are mapped to new handlers:
  - zoom: script index `22`
  - pan: script index `23`
- Corrected two minus-button setup mistakes in RoomUI:
  - `ui_name` fixed to `notebeam_zoom_minus`
  - `button_click_value` fixed to `-1`
- Added explicit `ui_layer_num=3` to new controls that were missing it (`notebeam_pan_far_left`, `notebeam_zoom_plus`, `notebeam_zoom_minus`).
- Added button dispatcher cases and handlers in `scr_button_scripts` for indices `22` and `23`.
- Implemented notebeam zoom/pan timeline helpers in `scr_game_viz` and wired mouse wheel pan over the notebeam anchor.
- Pan now applies smooth visual offset in time-domain; zoom updates notebeam time window (`measures_ahead` / `measures_behind`).

Validation:
- `roomui/RoomUI/RoomUI.yy`: no errors found.
- `scripts/scr_button_scripts/scr_button_scripts.gml`: no errors found.
- `scripts/scr_game_viz/scr_game_viz.gml`: pre-existing diagnostics still present; no new diagnostics introduced by this change.

### Gameplay Controls Follow-up (2026-03-24, left-of-now zoom consistency)
- Status: pass (cache invalidation adjusted)

Change summary:
- Fixed asymmetry where historical player spans (left of now-line) could appear unscaled after zoom changes.
- Root cause was live player-surface cache not invalidating on window changes.
- Live player cache now invalidates when any of these change:
  - `ms_behind`
  - `ms_ahead`
  - `now_ratio`

Expected result:
- Zoom now rescales both past (left) and future (right) regions consistently during playback.



**5. Gameplay Loop**
1. 	Select tune from a scrollable, sortable, filterable library
2. 	Configure tune options (tempo, metronome, parts, embellishment rules, transitions)
3. 	Preprocess into a unified play array
4. 	Enter Play Room
5. 	Play along with real‑time visual and audio feedback
6. 	Log MIDI input from player for scoring and analysis
7. 	Review results in a post‑play analysis window
8. 	Track progress over time

**6. Key Gameplay Data and Visualization Workflow** (in development)

**6.1 Play Event Workflow (during playback)**
During playback, runtime behavior is driven by two primary data sources:
1. Tune data (planned and played)
  a. Tune as planned: the expanded event list after preprocessing (main part, harmonies, drums, and backing notes).
  b. Tune as played: runtime execution of planned events; usually the same, but may vary slightly due to timing/output lag.
2. MIDI input (player)
  a. Live MIDI-in events from the player chanter (currently assumed to be one player).


Visual elements using tune data:
1. Score display (Panel B) uses tune as planned to show recent, current, and upcoming measures.
2. Note beams / piano roll (Panel F) use tune as planned for upcoming notes.
3. Text display in Panel B (note names, canntaireachd, lyrics, tips) also uses tune as planned when content exists.
4. At the moment of play, planned visuals can transition to played-state visuals where needed.

Event-driven outputs during runtime (tune as played + player MIDI in):
1. MIDI out is driven by event processing.
2. Basic event log captures tune-as-played events, metronome events, and player MIDI-in events.
3. Log expansion and heavy transforms are deferred to post-processing to minimize live-play lag risk.
4. Played-notes display is updated from both tune-as-played and player MIDI-in events.
5. Live performance effects are derived from tune-as-played vs player MIDI-in data, including calculated cues (for example crossing-noise detection from short MIDI-in durations, e.g., <15 ms or configured threshold).

**6.2 Panel Layout and Responsibilities**
1. Tune info window (Panel A)
2. Score window showing current and upcoming measures (Panel B)
3. Section in Panel B showing selectable text:
  a. note and embellishment names
  b. canntaireachd
  c. lyrics
  d. playing advice
4. Narrow header showing measure and beat information (Panel C)
5. Tune structure window with one box per measure for navigation, feedback color-coding, and practice-loop selection (Panel D)
6. Small settings window for runtime-safe settings (no preprocessing-impact changes) (Panel E)
7. Main performance area (Panel F) showing piano-roll style upcoming notes, play axis, tune/player played notes, and error color-coding cues.

**6.3 Panel Motion and Update Rules**
1. Panels B, C, and F scroll in sync with playback time (right-to-left, faster at higher BPM).
2. Display range is configurable (for example, prior + current + next measure, or wider look-ahead).
3. Other panels (for example Panel D) update during playback but do not time-scroll in sync with tune timing.

**6.4 Canonical Note Normalization (implemented)**
1. Runtime note identity is now split into three fields:
  a. `note_midi_raw`: raw MIDI value received from device input.
  b. `note_canonical`: shared musical note identity used across chanter types (for example G, A, B, =c, c, d, e, =f, f, g, a).
  c. `note_midi`: normalized/output MIDI value resolved from the active chanter profile.
2. Each chanter profile defines:
  a. Canonical-to-MIDI map (used for playback/output mapping).
  b. MIDI-in alias map (used to normalize incoming device-specific note values to canonical identity).
3. Normalization happens at MIDI ingest time to keep downstream systems simple.
4. Canonical data is propagated to timeline/event history so post-play comparison can use canonical identity later without rewriting ingest.

**6.5 Supporting Multiple Chanter Profiles (next steps)**
1. Add one profile entry per chanter in the profile registry:
  a. Profile name.
  b. Canonical-to-MIDI map.
  c. MIDI-in alias map (including any alternate device note numbers).
2. Add profile option to runtime settings (`global.MIDI_chanter_options`) and selection UI.
3. Verify round-trip mapping per profile:
  a. Device MIDI in -> canonical note.
  b. Canonical note -> playback/output MIDI.
4. Track unknown incoming notes during testing and add missing aliases to the relevant profile.
5. Keep scoring/judging logic profile-agnostic by comparing `note_canonical` first, with timing handled separately.

---

**6.6 Notebeam Visual Rendering System (implemented)**

The notebeam panel (Panel F) renders a piano-roll style view of planned and player note spans as horizontal beams. The rendering pipeline lives entirely in `scripts/scr_game_viz/scr_game_viz.gml` (~2200 lines). Configuration lives in `objects/obj_game_viz/Create_0.gml` inside `global.timeline_cfg`.

**6.6.1 Rendering Pipeline Overview**

1. On tune start, `gv_bind_timeline_on_tune_start(_planned_events, _bpm, _meter_text)` is called:
   - Calls `gv_build_planned_spans(_events)` to convert the preprocessed event list into `global.timeline_state.planned_spans[]` — an array of structs with `{start_ms, end_ms, note, channel, is_embellishment}`.
   - Calls `gv_build_emb_groups(_planned_spans)` to precompute embellishment groups into `global.timeline_state.emb_groups[]`. Each group covers a sequence of grace notes + a target note and includes a `note_set{}` struct for O(1) membership testing.
   - Stores BPM and meter for beat-guide and structure-row drawing.

2. Each draw frame, `gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2)` is called:
   - Reads config from `global.timeline_cfg`.
   - Determines the visible time window from playhead position, `measures_ahead`, and `measures_behind`.
   - Draws background, beat guides, and the structure row.
   - Draws planned note beams (grey/blue by default).
   - Draws player note beams from `global.timeline_state.player_in[]` (completed spans) and `global.timeline_state.pending_player{}` (currently held notes).
   - Player beam color and style depend on the active **compare version** (see 6.6.2).

3. Time-to-pixel conversion is done by `gv_time_to_x(_ms, _now_x, _now_ms, _px_per_ms)` — a simple linear mapping.

4. Lane positions come from `gv_lane_y_for_note(_note, _cfg)` which maps canonical note names to vertical pixel positions.

**6.6.2 Compare Versions (notebeam_compare_version)**

The key that controls rendering mode is `notebeam_compare_version` in `global.timeline_cfg`. Set it to 1, 2, or 3.

**Version 1 — Basic overlay (default)**
- Planned spans draw in their planned color.
- Player spans draw on top in a single solid player color.
- No overlap analysis. Simple and reliable baseline.
- Use this to confirm the basic pipeline is working before testing v2/v3.

**Version 2 — Segmented overlap coloring**
- For each player span, `gv_collect_lane_overlap_segments()` is called to find all time segments where the player span overlaps any planned span on the same note lane.
- `gv_draw_split_normal_player_beam()` then draws the player span in two colors:
  - **Green** (configurable: `notebeam_player_segment_match_color`) for portions that overlap a planned span.
  - **Semi-transparent red** (configurable: `notebeam_player_miss_color`, alpha = `notebeam_player_alpha * 0.72`) for portions that fall outside any planned span (started early, held late, or wrong timing).
- Unmatched planned spans remain in their planned color (grey/blue) — notifying the player they missed those notes.
- This mode applies to all notes including those belonging to embellishment groups. In v2, embellishment notes are treated the same as melody notes.

**Version 3 — Segmented + embellishment grace overlay**
- Everything from v2, plus embellishment-aware grace note coloring.
- `gv_classify_player_spans_for_emb()` is called to classify each player span against the precomputed embellishment groups.
- Grace notes (all notes in an embellishment group except the final target note) that were played in the correct order within the embellishment timing window get a special **transparent green overlay** drawn on top of the v2 coloring.
  - Transparency alpha: `notebeam_player_emb_overlay_alpha` (default 0.55).
  - Color: `notebeam_player_emb_match_color`.
- The target note of the embellishment group follows v2 coloring (green overlap / red overhang).
- Only notes that belong to a `note_set{}` of an embellishment group are considered by the emb classifier; all other notes fall through to v2 split-rendering.

**6.6.3 Key Functions and Locations**

All functions are in `scripts/scr_game_viz/scr_game_viz.gml`.

| Function | Approx. Line | Purpose |
|---|---|---|
| `gv_build_planned_spans(_events)` | ~38 | Converts event list → `planned_spans[]` structs |
| `gv_bind_timeline_on_tune_start(...)` | ~119 | Entry point at tune start; builds spans + emb groups |
| `gv_build_emb_groups(_planned_spans)` | ~230 | Builds `emb_groups[]` with grace sequences + `note_set{}` |
| `gv_time_to_x(...)` | ~590 | Linear ms → pixel mapping |
| `gv_player_span_timing_state(...)` | ~595 | Returns 0/1/2 for miss / bleed / exact timing |
| `gv_collect_lane_overlap_segments(...)` | ~645 | Returns sorted merged overlap segments between a player span and all planned spans on the same lane |
| `gv_draw_split_normal_player_beam(...)` | ~709 | Draws a player beam split into green (overlap) + semi-transparent red (overhang) segments |
| `gv_classify_player_spans_for_emb(...)` | ~1030 | Classifies player spans against emb groups; returns `player_states[]`, `pending_states{}`, `player_grace_overlay[]`, `pending_grace_overlay{}` |
| `gv_draw_notebeam_canvas(...)` | ~1720 | Main per-frame draw function |

**Key lines inside `gv_draw_notebeam_canvas`:**
- Mode variables (`compare_version`, `use_segmented_compare`, `use_embellishment_mode`): ~lines 1848–1852
- Overlap gate + emb classify call: ~lines 1894–1920
- Planned spans draw loop: ~lines 1930–1960
- `player_in` draw loop with mode branches: ~lines 1970–2040
- `pending_player` draw loop with mode branches: ~lines 2060–2130

**6.6.4 Embellishment Group Structure**

`global.timeline_state.emb_groups[]` is an array of structs built by `gv_build_emb_groups`. Each struct has:
```
{
  note_set: {},          // struct used as a set — keys are note names; O(1) membership test
  spans: [],             // array of planned_span structs in group order (grace notes first, target last)
  window_start_ms: real, // start of allowable timing window (start of first grace note span)
  window_end_ms: real    // end of allowable timing window (end of target note span)
}
```
The last span in `spans[]` is always the target note; all preceding spans are grace notes.

**6.6.5 Config Keys Reference**

All keys live in `global.timeline_cfg` set in `objects/obj_game_viz/Create_0.gml`.

| Key | Default | Description |
|---|---|---|
| `notebeam_compare_version` | `1` | Rendering mode: 1=basic overlay, 2=segmented green/red, 3=+embellishment grace overlay |
| `notebeam_player_overlap_colorize` | `true` | Master enable for any player-vs-planned color comparison (v2/v3 require this true) |
| `notebeam_player_segment_match_color` | green (60,155,70) | Color for overlapping portion of player beam in v2/v3 |
| `notebeam_player_miss_color` | dark red (112,46,46) | Color for non-overlapping (early/late) portion of player beam |
| `notebeam_player_alpha` | `0.88` | Base alpha for player beams (red overhang drawn at `* 0.72`) |
| `notebeam_player_emb_match_color` | green (60,155,70) | Color for v3 embellishment grace overlay tint |
| `notebeam_player_emb_overlay_alpha` | `0.55` | Alpha for v3 embellishment grace overlay |
| `notebeam_player_timing_slack_ms` | `50` | Ms tolerance at note boundaries for overlap detection |
| `notebeam_player_color` | light grey | Fallback player beam color (used in v1, or when overlap colorize is off) |
| `notebeam_planned_color` | blue-grey | Planned span beam color |
| `notebeam_planned_alpha` | `0.75` | Planned span alpha |
| `notebeam_player_bleed_alpha` | `0.38` | Alpha for player spans that slightly miss planned timing (v1 timing state "bleed") |
| `notebeam_line_width` | `42` | Beam height in pixels |
| `notebeam_lane_row_height_px` | `42` | Height of each note lane row |
| `notebeam_lane_row_gap_px` | `20` | Vertical gap between note lane rows |

**6.6.6 How to Modify or Extend**

- **Change the overlap color or transparency:** Edit `notebeam_player_segment_match_color`, `notebeam_player_miss_color`, and `notebeam_player_alpha` (red overhang will auto-adjust as `_alpha * 0.72`) in `Create_0.gml`.
- **Add a new rendering version (e.g., v4):** Follow the pattern in `gv_draw_notebeam_canvas` — add a new `use_X_mode` boolean derived from `compare_version`, then add a new branch in the `player_in` and `pending_player` draw loops.
- **Change what counts as a grace note in v3:** Edit `gv_classify_player_spans_for_emb` — the line `var is_grace_overlay = (matched_at >= 0) && (matched_at < (n_exp - 1)) && (state == 2);` controls this. `n_exp - 1` means "all notes except the last (target) note in the group".
- **Adjust embellishment window tolerance:** Modify `window_start_ms` / `window_end_ms` logic in `gv_build_emb_groups`, or add a configurable slack key similar to `notebeam_player_timing_slack_ms`.
- **Debug emb groups at runtime:** After `gv_bind_timeline_on_tune_start`, add `show_debug_message(string(array_length(global.timeline_state.emb_groups)))` to confirm groups are being built.
- **Debug split segments:** Trace `gv_collect_lane_overlap_segments` output for a specific player span to verify overlap ranges are correct.

**6.6.7 Post-Play Alternating Beat Bands (implemented)**

To improve readability over busy background art, the notebeam canvas now supports alternating translucent beat bands in review mode.

Behavior:
- Bands are drawn between consecutive beat markers (one band per beat interval).
- Bands alternate even/odd styling by global beat index.
- Bands render behind planned/player beams so note content remains readable.
- Bands are only drawn when playback is complete (`global.timeline_state.playback_complete == true`).
- During live playback, this feature does not draw and adds no runtime visual cost.

Runtime draw function:
- `gv_draw_notebeam_beat_boxes(...)` in `scripts/scr_game_viz/scr_game_viz.gml`
- Called from `gv_draw_notebeam_canvas(...)` only when `review_split_beams` is enabled.

Config keys (source of truth):
- `notebeam_beat_box_even_color`
- `notebeam_beat_box_odd_color`
- `notebeam_beat_box_even_alpha`
- `notebeam_beat_box_odd_alpha`

These values are defined in `global.timeline_cfg` in `objects/obj_game_viz/Create_0.gml`.
Important: values in `gv_draw_notebeam_beat_boxes` are fallback defaults only and are ignored whenever the config keys above exist.

Current tuned defaults:
- `notebeam_beat_box_even_color: make_color_rgb(245, 245, 245)`
- `notebeam_beat_box_odd_color: make_color_rgb(35, 35, 35)`
- `notebeam_beat_box_even_alpha: 0.12`
- `notebeam_beat_box_odd_alpha: 0.28`

Contrast tuning guidance:
- Increase distinction by widening both color and alpha separation (light even band + dark odd band works best on tartan).
- If bands look washed out by history overlays, lower `notebeam_history_band_alpha` in the same config block.

Master toggle globals:
- `global.show_review_beat_bands` enables/disables the alternating post-play beat bands.
- `global.show_review_emb_boxes` enables/disables the embellishment window highlight boxes.
- These globals are initialized in `objects/obj_game_controller/Create_0.gml`.
- These are master on/off switches intended for future UI wiring.
- Visual style and color tuning still live in `global.timeline_cfg` in `objects/obj_game_viz/Create_0.gml`.

**6.6.8 Post-Play Embellishment Window Boxes (implemented)**

To make planned embellishment groups easier to read, the notebeam canvas now supports a boxed highlight for each full embellishment window.

Behavior:
- Each box covers the full embellishment time window: grace-note start through target-note end.
- Each box expands vertically to include all note lanes used by that embellishment plus its target note.
- Boxes render over beat bands but under planned/player note beams.
- Boxes only render for groups with a confirmed target note.
- Boxes can be limited to review mode and can also be master-toggled off globally.

Runtime draw function:
- `gv_draw_notebeam_emb_group_boxes(...)` in `scripts/scr_game_viz/scr_game_viz.gml`

Config keys:
- `notebeam_emb_box_enabled`
- `notebeam_emb_box_review_only`
- `notebeam_emb_box_fill_color`
- `notebeam_emb_box_fill_alpha`
- `notebeam_emb_box_border_color`
- `notebeam_emb_box_border_alpha`
- `notebeam_emb_box_lane_padding_px`
- `notebeam_emb_box_time_padding_ms`

**6.6.9 Centralized Visual Tuning Controls (implemented)**

Visual tuning for both notebeam history markers and tune-structure measure boxes is now centralized in one place:
- `objects/obj_game_viz/Create_0.gml` (inside `global.timeline_cfg`)

This means color/alpha adjustments no longer require editing draw logic in multiple functions.

Notebeam prior run marker controls (start/end yellow markers):
- `notebeam_history_start_color`
- `notebeam_history_end_color`
- `notebeam_history_start_alpha`
- `notebeam_history_end_alpha`

Current tuned defaults:
- `notebeam_history_start_color: make_color_rgb(255, 235, 70)`
- `notebeam_history_end_color: make_color_rgb(255, 218, 40)`
- `notebeam_history_start_alpha: 0.52`
- `notebeam_history_end_alpha: 0.95`

Tune-structure panel controls (measure boxes + separator line):
- `tune_structure_current_base_color`
- `tune_structure_current_base_alpha`
- `tune_structure_current_overlay_color`
- `tune_structure_current_overlay_alpha`
- `tune_structure_played_fill_color`
- `tune_structure_played_fill_alpha`
- `tune_structure_border_color`
- `tune_structure_border_alpha`
- `tune_structure_current_border_color`
- `tune_structure_current_border_alpha`
- `tune_structure_part_separator_color`
- `tune_structure_part_separator_alpha`

Current tuned defaults:
- `tune_structure_played_fill_alpha: 0.72` (played dark boxes more visible)
- `tune_structure_border_alpha: 0.58`
- `tune_structure_current_base_alpha: 0.55`
- `tune_structure_current_overlay_alpha: 0.35`

Implementation note:
- `scripts/scr_game_viz/scr_game_viz.gml` now reads these values from `global.timeline_cfg` inside `gv_draw_tune_structure_panel(...)`.
- Hardcoded visual constants were replaced with config lookups + fallback defaults.
- Result: one-stop runtime tuning for gameviz appearance.

---

**7. Post Gameplay Analytics**
1. After playback, the player can scroll forward/back in time or select a measure in Panel D to jump to that point.
2. Review mode shows tune-as-played and player performance (MIDI in), impacting note beams, score, and event log views.
3. Events and performance include additional cues, such as color coding.
4. Post-processing expands runtime events into a performance log exported as JSON.
5. Additional analysis is currently done in Excel as a prototype for future in-game analysis.
6. Future state: show current performance against prior performances and averages.

**8. Final Architecture Overview**
Core Systems
• 	Tune ingestion pipeline (ABC → Excel → JSON)
• 	Tune loader + metadata manager
• 	Preprocessing engine (play array builder)


⚠️ **Important architectural constraint:** Do NOT use ds_maps, ds_lists, or other GameMaker data structures. Use arrays and structs only. This keeps the code simpler, avoids memory management complexity, and makes the code more predictable.
• 	Playback engine (time‑source driven)
• 	MIDI input manager
• 	MIDI output manager
• 	Canonical note normalization + chanter profile mapping (see Sections 6.4 and 6.5)
• 	Scoring engine (real‑time + post‑play judges)
• 	Analysis engine (trend tracking, detailed breakdowns)
• 	Data persistence (settings, history, preferences)
UI Architecture
• 	Modular window system using GameMaker UI layers
• 	Flex‑panel layout engine for dynamic UI
• 	Windows for:
• 	Main menu
• 	Tune picker
• 	Settings
• 	Metronome
• 	Parts selection
• 	Play Room
• 	Analysis
Controllers
• 	 — tune data model
• 	 — playback engine
• 	 — MIDI I/O
• 	 — window + layout controller
• 	 — scoring + judge orchestration

**9. Scoring & Analysis Vision**
Real‑Time Scoring
• 	Basic correctness (right note near the right time)
• 	Immediate feedback indicators
Post‑Play Judges
Each judge focuses on a single musical dimension:
• 	Phantom notes / false fingering
• 	Embellishment timing accuracy
• 	Millisecond‑level note correctness
• 	Beat‑level timing consistency
• 	Phrase‑level rhythmic shape
• 	Overall tune accuracy score
Long‑Term Tracking
• 	Store play logs
• 	Track trends across sessions
• 	Identify strengths and weaknesses
• 	Provide practice recommendations (future)

10. Long‑Term Extensibility
The system is designed to support future enhancements:
• 	Additional instruments
• 	Custom scoring profiles
• 	Cloud sync of player history
• 	Exportable analysis reports
• 	Multiplayer / ensemble mode
• 	Backing tracks with other instruments
• 	AI‑assisted practice suggestions

11. Definition of Done
The project is “complete” when a player can:
• 	Load any tune from the library
• 	Configure all relevant musical and playback options
• 	Play along with synchronized audio and visual feedback
• 	Receive detailed, accurate scoring and analysis
• 	Track improvement over time
• 	Use the tool as a reliable, enjoyable part of their practice routine

## Active Calibration Plan

This is the active plan for the current thread. If work gets interrupted, resume here first.

1) Timing architecture and instrumentation
- Define canonical timeline ownership.
- Log timestamp points for schedule, play, render, capture, and score.
- Compute P50, P95, and jitter per path.

2) Separate calibration domains
- Keep audio alignment, visual alignment, and input/scoring as separate offsets.
- Do not re-bundle them into one shared number.

3) Reference-mode calibration UX
- Offer calibrate-to-click, calibrate-to-visual, or balanced modes.
- Save per-player profiles and per-device baselines.

4) Audio scheduling upgrade
- Implement lookahead scheduling for metronome and backing track first.
- Validate stability under load.

5) Runtime jitter management
- Detect transient frame/audio jitter.
- Apply guarded mitigations for visual smoothing, scoring tolerance, and quality warnings.

6) Evaluate audio-stem migration
- Pilot one tune or set with stem playback.
- Compare latency stability and CPU load before any wider migration.

Success criteria
- Players who calibrate to click score correctly when following click.
- Players who calibrate to visual score correctly when following visual line.
- Stable P95 timing error at target BPM range.
- Minimal drift over a full tune or set.
- Clear diagnostics when environment quality degrades.

📋 Roadmap
This roadmap is divided into Backlog, In Progress, and Done.
Move items between sections as development progresses.

Near-Term Priority Queue (2026-04-23)
Ordered to reduce integration risk and unblock downstream features.

1) Tune data + score image pipeline + synced score scrolling
- Scope: tighten ABC -> Excel -> JSON export for score-image references and re-enable beat-synced score-image scrolling in timeline canvas.
- Why first: this is a foundational visual truth source for later text lanes and timing validation.
- Done when:
  - score image assets resolve deterministically from exported tune metadata,
  - timeline score image scrolls in sync with playback beat/time source,
  - no active-playback regression against the refactor baseline envelope.

2) Tune customization workflow verification (including custom timing from Excel)
- Scope: validate and harden per-tune/per-set overrides (tempo, meter, swing, grace timing, custom timing columns).
- Why second: playback/metronome/calibration work depends on reliable tune-level timing inputs.
- Done when:
  - custom timing authored in Excel survives JSON export/load/preprocess,
  - runtime overrides apply in the intended precedence order,
  - at least one verification tune demonstrates end-to-end expected timing behavior.

3) Playback timing calibration expansion + usable calibration UI
- Scope: extend timing calibration beyond current baseline and expose it in a user-facing UI flow.
- Why third: needs stable tune timing inputs and synchronized visual anchors from items 1-2.
- Done when:
  - calibration can be started, adjusted, saved, canceled, and applied from UI,
  - calibration offsets affect both playback and comparison views consistently,
  - calibration state is persisted and restored safely.

4) Time signature coverage expansion
- Scope: expand/verify time-signature handling for likely tune meters and ensure quarter-BPM normalization behaves correctly.
- Why fourth: this formalizes assumptions needed for metronome pattern expansion.
- Done when:
  - preprocess, metronome, beat guides, and scroll math agree for supported signatures,
  - unsupported signatures fail safely with clear diagnostics.

5) Metronome rebuild: sound sets, pattern expansion, and cycle crash fix
- Scope: add differentiated click sounds, broaden drum/click pattern options, and fix the known crash when cycling patterns/options.
- Why fifth: depends on validated timing, meter normalization, and calibration paths.
- Done when:
  - users can select distinct click/accent/optional subdivision sounds,
  - pattern set includes practical defaults per common meter/tune type,
  - cycle interaction no longer crashes in stress testing.

6) Embellishment system scale-up (bulk, data-driven)
- Scope: move from one-by-one additions to grouped/data-driven embellishment definitions and expansion behavior.
- Why sixth: best done after timing and metronome baselines are stabilized to avoid confounded debugging.
- Done when:
  - embellishment families can be added/adjusted through shared rules,
  - preprocess expansion remains deterministic across supported tune types,
  - notebeam/analysis views stay aligned with expanded events.

7) Timeline text lanes: canntaireachd, lyrics, advice
- Scope: add/restore synchronized text lanes in timeline canvas sourced from tune metadata/content.
- Why seventh: depends on stable scroll/sync mechanics from item 1 and validated timing from items 2-4.
- Done when:
  - each lane can be toggled and rendered without harming frame stability,
  - lane content tracks current playback position and measure context,
  - missing content fails gracefully (blank lane, no crashes/noise logs).

Coverage map for requested features
- Covered by queue item 1: ABC->score image refinement + beat-synced timeline score scrolling.
- Covered by queue item 6: embellishment build-out at scale.
- Covered by queue item 2: tune customization workflow vetting (including custom timing in Excel).
- Covered by queue item 3: playback timing refinement via expanded calibration + UI.
- Covered by queue item 4: time signature support expansion.
- Covered by queue item 5: metronome sound/pattern work + cycle crash fix.
- Covered by queue item 7: canntaireachd/lyrics/advice timeline lanes.

### Implementation Update (2026-05-03, score beat-anchor runtime wiring)
- Added `scr_score_manifest_normalize_image_meta(_image_meta, _beats_per_measure)` in `scr_tune_load.gml` and applied it in both base manifest load and transition override bundle load so `image_meta.beat_anchors` arrays are normalized to fixed beat-length per measure.
- Extended score-lane draw in `scr_game_viz.gml` to optionally render beat-anchor guide lines from `image_meta.beat_anchors` (scaled to current score-sprite draw transform).
- Added `global.timeline_cfg` defaults in `gv_ensure_timeline_cfg_defaults()` for anchor guides:
  - `score_lane_anchor_guides_enabled` (bool)
  - `score_lane_anchor_guide_color` (color)
  - `score_lane_anchor_guide_alpha` (real 0..1)
  - `score_lane_anchor_guide_width` (real)
- Data/export validation completed:
  - Re-exported representative tune score manifests with the abcjs pipeline and verified `score_images.json` includes populated `image_meta[*].beat_anchors` arrays.
- Runtime gate status:
  - In-engine single-vs-set parity validation for internal pickups and highlight/measure-label continuity is still pending manual playthrough in Room_play.

### Implementation Update (set-mode pickup measure detection fix)
- Root cause: `gv_build_measure_nav_map` had a `!_set_mode` guard that prevented it from using `global.score_snippet_durations` in set mode, causing the event-scan fallback path to run which cannot detect opening pickup measures.
- Fixes applied in `scr_game_viz.gml`:
  1. Removed `!_set_mode` guard from `_durations` assignment in `gv_build_measure_nav_map` so set mode also uses snippet durations for authoritative measure/pickup detection.
  2. Added per-segment snippet-duration restore to `gv_rebuild_measure_nav_for_segment`: before calling `gv_build_measure_nav_map`, it now restores `global.score_snippet_durations` and `global.score_units_per_measure` from `global.score_segments_sprites[_seg_idx]`. This fixes all three segment-transition call sites (playhead advance, manual seg_prev/seg_next, and playhead jump) in one place.
  3. Kept the score-canvas structural-duration path in set mode on marker-timing (the attempted set-mode structural override was reverted after it regressed pre-roll visibility and stretched image spans).
- Note: `score_segments_sprites[i].durations` is already populated during set preload in `scr_button_scripts` (was present before this fix). User smoke test on Simon Fraser -> Jig of Slurs indicates the reverted canvas path plus retained nav fixes restored expected behavior.

### Implementation Update (set segment cache restore hardening)
- Refactored duplicated segment-switch cache restore code in `scr_game_viz.gml` into a single helper: `gv_restore_score_segment_cache(_seg_idx, _restore_media)`.
- The helper restores structural metadata (`score_snippet_durations`, `score_units_per_measure`) and optionally draw-time arrays (`score_lane_sprites`, `score_playback_map`, `score_lane_meta`).
- Updated all set segment-switch paths to call the helper (auto-advance, now-line sync jump, and manual seg_prev/seg_next navigation), reducing drift risk between call sites without changing intended behavior.

### Implementation Update (pickup flag architecture — single-tune and set-mode fix)
**Context:** Tunes with an opening pickup bar (e.g. Wings, Rowan Tree) were displaying the pickup as M1 in single-tune mode and throughout sets.

**Root cause chain (in order discovered):**
1. `_measure_starts` builder in `gv_build_measure_nav_map` single-tune path used `_em < 0` to exclude pickup markers — but pickup markers have `measure = 0`, not `< 0`, so they were admitted. This caused `_marker_measure_ms` to be calculated from the tiny pickup duration (~250 ms) instead of a full bar (~2000 ms), producing a wildly wrong `_ms_per_unit` and corrupting the entire structural-duration path.
2. `gv_build_measure_nav_map` snippet path anchored `_t` to the M1 event time without stepping back for the pickup duration — so the pickup snippet was assigned M1's timestamp.
3. `global.score_snippet_durations` was always empty because `scr_score_sprites_load` checked `manifest.snippet_durations` (a flat field that never existed in the JSON) instead of `manifest.snippets[]`.
4. **Root cause:** `scr_score_manifest_read` read only `score/score_images.json`, which has no `has_pickup` or `snippets` fields. The sibling `<TuneName>.score_snippets.json` (which contains both) was never loaded anywhere in GML.

**Fixes applied:**
- **VBA (`Excel - Parse_ABC.txt`):** Both export paths (`ExportEventsToJSON`, `ExportEventsToJSON_ToFile`) now write `has_pickup`, `pickup_offset_units`, `units_per_measure`, `beats_per_measure` into the tune JSON `"tune"` block. `BuildSnippetBundleJSON` writes `has_pickup` at the bundle level.
- **`scr_tune_load.gml` — `scr_score_manifest_read`:** After reading `score/score_images.json`, now opens the sibling `<TuneName>.score_snippets.json`, parses it, and merges `has_pickup`, `snippets[]`, and `units_per_measure` onto the manifest struct. This is the definitive fix.
- **`scr_tune_load.gml` — `scr_score_sprites_load`:** Now reads `manifest.snippets[]` (not `manifest.snippet_durations`) to populate `global.score_snippet_durations` from `snippets[i].duration_units`. Also sets `global.score_has_pickup = bool(manifest.has_pickup) ?? false`.
- **`scr_game_viz.gml` — `gv_build_measure_nav_map` (single-tune path):** Changed `_em < 0` to `_em <= 0` in the `_measure_starts` builder so pickup bar markers (`measure=0`) are excluded.
- **`scr_game_viz.gml` — `gv_build_measure_nav_map` (snippet path):** Pickup detection now reads `global.score_has_pickup` (was a duration heuristic). Time offset applied: when `score_has_pickup` and `_observed_first_measure >= 1`, steps `_t` back by the pickup snippet duration before the loop.
- **`scr_game_viz.gml` — `gv_restore_score_segment_cache`:** Now restores `global.score_has_pickup` from the segment cache struct.
- **`scr_game_viz.gml` — `gv_build_set_measure_nav_all`:** Snapshots and per-segment restores `global.score_has_pickup` from `cache[$ "has_pickup"]`.
- **`scr_game_viz.gml` — score-lane single-tune path:** `_first_is_pickup` reads `global.score_has_pickup`.
- **`scr_game_viz.gml` — score-lane set-mode path:** `_first_is_pickup` reads `_seg_cache_for_dur[$ "has_pickup"]` directly from segment cache struct.
- **`scr_button_scripts.gml`:** Segment cache struct now includes `has_pickup: global.score_has_pickup`. Segment 0 restore also restores `global.score_has_pickup`.

**New global added:** `global.score_has_pickup` (bool) — owner: `scr_tune_load / scr_score_sprites_load`. Documented in WORKSPACE_MAP.md Global State Inventory.

**Confirmed working (smoke tested):**
- Scotland the Brave / Wings / Rowan Tree set of 3 — correct measure numbering throughout.
- Wings single-tune — correct pickup and full-bar numbering.
- Rowan Tree single-tune — correct pickup and full-bar numbering.

**Still pending:**
- Transition tunes (`Dalnahasaig to Strathan Reel` etc.) — `has_pickup` interaction with prior_replace/bridge/follow_replace snippet groups not yet validated.
- Pickup tunes that are not the first tune in a set — `score_segments_sprites[si].has_pickup` must be confirmed correct for each segment; mid-set restore path (`gv_restore_score_segment_cache`) must be exercised.

### Implementation Update (2026-05-26, Dreams Reprise grouped score export + picker sidecar filtering) — COMPLETE

**Root issues addressed:**
- Grouped score-image sidecar export for harmony parts was coupled to `V:` header presence in combined ABC, so some tunes did not emit per-part score bundles.
- Tune library scanner treated generated score sidecars as playable tune JSONs, producing duplicate picker entries with incorrect metadata/part controls.

**Fixes applied:**
- **VBA (`scripts/Excel - Parse_ABC.txt`):** `BuildScoreImageGroupsJSON` now builds per-part score bundles directly from parts-table rows instead of requiring `V:` headers in merged ABC content.
- **VBA (`scripts/Excel - Parse_ABC.txt`):** Added `ResolveScoreGroupPartChannel` mapping `melody -> 2`, `harmony1 -> 3`, `harmony2 -> 4`, `harmony3 -> 5` for deterministic per-part export routing.
- **GML (`scripts/scr_tune_library/scr_tune_library.gml`):** `scr_tune_scan_dir` now excludes score sidecar files `*.score_groups.json` and `*.score_part*.json` in addition to existing `*.score_snippets.json` exclusion.
- **Index cleanup:** Removed stale sidecar entries from `datafiles/tunes/tune_library.json` so existing duplicate picker rows disappear immediately.

**Verification status:**
- Export artifacts for Dreams Reprise are present as expected (`.score_groups.json` plus per-part score subfolders/manifests).
- Tune picker now resolves Dreams Reprise as a single canonical entry (no extra sidecar-derived rows).
- Visual check passed: score images look correct after re-export.
- Scoring behavior remains a runtime playthrough validation item.

**Next-session QA focus:**
- Playthrough sweep for scoring regressions (single tunes + sets).
- Existing pending pickup validations above remain in scope.

### Implementation Update (2026-05-28, timeline score-lane visibility toggle in game info window) — COMPLETE

**Goal:**
- Add a game-info-window control to hide timeline score images while keeping beat/measure marker lanes active.
- Keep control non-interactive during live playback to avoid runtime input overhead and accidental state changes.

**Changes applied:**
- **GML (`scripts/scr_game_viz/scr_game_viz.gml`):** Added `global.timeline_cfg.timeline_score_visibility_mode` default (`0=score+markers`, `1=markers-only`) in `gv_ensure_timeline_cfg_defaults()`.
- **GML (`scripts/scr_game_viz/scr_game_viz.gml`):** Added helper/getter/cycle functions and new UI handlers:
  - `gv_get_timeline_score_visibility_mode()`
  - `gv_should_draw_timeline_score_images()`
  - `gv_cycle_timeline_score_visibility_mode()`
  - `gv_draw_gameinfo_timeline_visibility_panel(...)`
  - `gv_handle_gameinfo_timeline_visibility_click(...)`
- **GML (`scripts/scr_game_viz/scr_game_viz.gml`):** Gated score-image rendering in `gv_draw_timeline_canvas_overlay(...)` using `gv_should_draw_timeline_score_images()`, preserving beat-lane guides/markers and now-line behavior.
- **RoomUI (`roomui/RoomUI/RoomUI.yy`):** Added `gameinfo_timeline_visibility_anchor` instance under `fp_gameinfo_window -> fp_window_body`.
- **Input/draw routing (`objects/obj_field_base/Draw_0.gml`, `objects/obj_field_base/Mouse_7.gml`):** Wired draw and click handling for the new anchor.

**Behavior contract:**
- Button is enabled before playback and in post-play review mode.
- Button is disabled during live playback.
- Score images can be hidden without affecting beat/measure marker rendering.

### Implementation Update (2026-05-28, Phase 1 per-player per-tune notebeam zoom persistence) — COMPLETE

**Goal:**
- Persist and restore notebeam zoom per player per tune for single-tune mode, reusing existing `tune_overrides.json` flow.
- Explicitly leave set mode unchanged in Phase 1.

**Changes applied:**
- **GML (`scripts/scr_scoring/scr_scoring.gml`):** Extended tune override payload read/write to include:
  - `notebeam_measures_ahead`
  - `notebeam_measures_behind`
- **GML (`scripts/scr_scoring/scr_scoring.gml`):** `scoring_tune_override_apply_current(...)` now applies notebeam zoom fields into `global.timeline_cfg` and syncs timeline window via `gv_notebeam_sync_window_from_cfg()`.
- **GML (`scripts/scr_scoring/scr_scoring.gml`):** `scoring_tune_override_save_current(...)` now captures current `global.timeline_cfg.measures_ahead/measures_behind` into tune overrides.
- **GML (`scripts/scr_button_scripts/scr_button_scripts.gml`):** `scr_notebeam_zoom_change(...)` now saves tune overrides after zoom changes when not in set mode.

**Behavior contract:**
- Single tune mode:
  - Zoom changes are saved per tune for the active player.
  - Loading the same tune for that player restores last saved zoom.
- Set mode:
  - No new per-tune zoom save/apply behavior added in this phase.

### Implementation Plan (2026-05-28, beta EXE readiness for zipped-folder distribution)

**Distribution decision:**
- Beta will be distributed as a zipped Windows build folder (Steam-compatible packaging workflow).

**Primary release blocker identified:**
- Runtime path handling still contains developer-machine absolute paths in startup/rebuild/load/log call sites.

**Plan of record:**
- Added dedicated execution doc: `BETA_RELEASE_PLAN.md`.
- Execute in this order:
  1. Path hardening (remove hardcoded dev absolute paths; keep resolver/fallback behavior)
  2. Packaging validation from zipped build on a clean machine/profile
  3. QA gate pass (pending scoring/pickup/transition validations)
  4. RC metadata polish + beta packaging notes

**Start-now task list:**
- Replace startup hardcoded tune root with resolver path.
- Replace manual regenerate hardcoded tune root with resolver path.
- Remove hardcoded absolute tune_library candidate in loader.
- Replace hardcoded absolute `bpm_trace.log` location with resolver path.
- Run zipped-folder smoke test end-to-end.

**Status update (2026-05-28):**
- Completed: first four path-hardening items above (startup, regenerate, loader candidate, bpm trace path).
- Next gate: build + zipped-folder smoke test on clean profile/machine.

**Follow-up fix (2026-05-28):**
- Added `global.tune_library_root_override` (default blank) as a single explicit path override knob for dev/compiler runs.
- Updated `scr_tune_library_get_runtime_root()` to auto-select the first usable root from override + runtime candidates (`datafiles`, `program_directory`, `working_directory`, `tunes`).
- Purpose: preserve machine-agnostic beta behavior while restoring tune visibility when runtime-relative roots are empty in IDE runs.

### Implementation Update (2026-05-04, Option 2 fallback boundary lead-in) — COMPLETE

**Phase 1 & 2 (Cases 1 & 3) DONE:**
- Case 1: T2 no pickup → direct handoff (BPM/meter change on beat 1, no lead-in)
- Case 3: T2 has pickup, T1 ends at measure boundary → hold 1 full T2 measure (T2 tempo/meter)
- Authored transition tune always overrides fallback
- Explicit `gap` transition in set JSON overrides fallback

**Phase 3 (Cases 2 & 4) DONE:**
- Case 2: T2 no pickup, T1 ends mid-measure → direct handoff (T1 may already have been deferred; no case currently in tunes)
- Case 4: T2 has pickup, T1 ends mid-measure → hold T1's note to complete T1's measure (at T1's tempo), then T2's pickup aligns to next measure boundary

**Implementation details:**
- `scr_set_compute_boundary_lead_in()` — detects if T1 ends mid-measure; computes hold duration for Cases 2 & 4; generates appropriate countin (or none for Case 4).
- Metronome: Case 3 generates 1-measure count-in at T2's tempo; Case 4 generates no count-in (partial hold in T1 tempo).
- Score image capping: uses `content_end_ms` (tune end before hold) so images don't stretch into the hold window.

**VBA change (`scripts/Excel - Parse_ABC.txt`):**
- Added `measure_count` (= `DownbeatBarCount`) to `tune{}` in both export paths (not actively used yet in GML, but data is present).

**GML changes (`scripts/scr_set_scripts/scr_set_scripts.gml`):**
- `scr_set_compute_boundary_lead_in(_t1_struct, _t1_events, _t2_struct, _t1_bpm, _t2_entry)` — cases 1–4 implemented: detects mid-measure boundaries, returns case-specific hold durations and metronome settings.
- `scr_set_extend_last_note_off(_events, _ms)` — extends last note_off event by _ms.
- `scr_set_preprocess_and_build_playback()` — computes boundary lead-in for all non-transition tune boundaries; extends notes; generates metronome; updates segments with `content_end_ms`.
- `scr_playback_context_build_for_set()` — forwards `content_end_ms` through segment struct copying.

**GML changes (`scripts/scr_game_viz/scr_game_viz.gml`):**
- Duration-based score image layout: uses `content_end_ms` instead of `end_ms` so images cap at tune content boundary, not hold boundary.
- Marker-derived path: adds `seg_content_end_ms` to measure_starts entries.
- Draw loop: caps last image's `_t_end` to `seg_content_end_ms` instead of `seg_end_ms`.

**Bug fixes applied after initial implementation:**
- Case 3 was a separate early-return that inserted a full T2 measure without subtracting the pickup. Removed; Cases 3 & 4 now share the unified formula `hold = remaining - pickup`.
- Pickup phase correction: Scotland the Brave ends at unit 128 (= 16 × 8), which naively modded to 0 (boundary). Added `t1_pickup_ms` subtraction before modulo so the phase is relative to the first downbeat. Result: Scotland→Wings correctly computes hold = 0 (direct handoff).
- Guard added: `max(0, t1_tune_end_ms - t1_pickup_ms)` prevents negative modulo on malformed data.

**Validation scenarios confirmed:**
- Set of 3: tune 1 (no pickup) → tune 2 (no pickup) — Case 1, no lead-in ✓
- Set of 3: tune 1 (no pickup) → tune 2 (has pickup) — Case 3, 1-measure hold ✓
- Scotland → Wings: pickup phase correction → Case 3, hold = 0, direct handoff ✓
- Set with authored gap — fallback should NOT fire ✓
- Set with transition tune — fallback should NOT fire ✓
- 4/4 March set: metronome/score/music aligned across all tunes ✓

### Implementation Update (2026-05-10, latency model kickoff) - IN PROGRESS

Problem statement:
- A single offset is currently carrying multiple latency domains (audio output, visual alignment, input capture, and scoring comparison), which makes calibration drift between play-to-click, play-to-visual, and scoring views.

Architecture rule:
- Keep one canonical timeline for tune events.
- Apply domain offsets only at domain boundaries.

Offset taxonomy (runtime fields):
- `audio_output_offset_ms`: shifts scheduled audio target time.
- `visual_alignment_offset_ms`: shifts visual target time for timeline/notebeam presentation.
- `input_capture_offset_ms`: aligns player input timestamps into canonical timeline time.
- `scoring_compare_offset_ms`: analysis-only comparison offset.

Phase 1 changes completed in code:
- `timing_calibration_ensure_state()` in `scr_tune_scripts.gml` now initializes split offsets and a `jitter_summary` struct.
- `gv_ensure_timeline_cfg_defaults()` in `scr_game_viz.gml` now provides defaults for all split offsets with legacy `player_time_offset_ms` compatibility.
- Event history payloads now carry domain timing fields in both paths:
  - game event path (`tune_scheduler_process_deferred`)
  - player input path (`MIDI_process_messages`)
- End-of-tune cleanup now snapshots RT diagnostics into `global.timing_calibration.jitter_summary` via `timing_calibration_capture_jitter_summary()`.

Phase 1 validation targets (next):
- Confirm no regressions in playback behavior with all offsets at 0.
- Verify event exports include split offset fields for both `source=game` and `source=player`. ✅ Done (2026-05-10)
  - Validated on fresh single-tune and set-mode runs via newest exported CSV + summary JSON artifacts.
  - Confirmed CSV fields: canonical_time_ms, audio_target_time_ms, visual_target_time_ms, input_aligned_time_ms, audio_offset_ms, visual_offset_ms, input_offset_ms, score_offset_ms.
  - Confirmed summary keys: audio_offset_ms, visual_offset_ms, input_offset_ms, score_offset_ms, timing_sample_game, timing_sample_player, has_timing_sample_game, has_timing_sample_player.

Implementation update (2026-05-10, no-legacy policy):
- Team decision: remove legacy offset compatibility and run new split-offset model only.
- Removed `player_time_offset_ms` dependency from runtime calibration/input paths.
- Added `timing_calibration_apply_offsets(...)` as the single apply entrypoint for split offsets.
- Player app settings now persist and restore:
  - `audio_output_offset_ms`
  - `visual_alignment_offset_ms`
  - `input_capture_offset_ms`
  - `scoring_compare_offset_ms`

Implementation update (2026-05-10, calibration bones before UI):
- Added calibration mode/session APIs in `scr_tune_scripts.gml`:
  - `timing_calibration_start_session(...)`
  - `timing_calibration_prepare_draft_from_probe(...)`
  - `timing_calibration_accept_session()`
  - `timing_calibration_cancel_session()`
- Added per-device calibration profile support in state/settings:
  - `timing_calibration_get_device_key()`
  - `timing_calibration_store_current_device_profile(...)`
  - `timing_calibration_apply_profile_for_current_device()`
  - `timing_calibration_build_settings_payload()` / `timing_calibration_hydrate_from_settings(...)`
- `scoring_player_settings_build_payload/load_for_player` now saves/loads `settings.timing_calibration` for per-player persistence.
- Audio scheduling now applies `audio_output_offset_ms` in scheduler due-time computation (timesource + step modes).

Resume checkpoint (2026-05-23, calibration UI prototype wired)
- Settings window now includes a calibration entrypoint button (`obj_settings_calibration_button`) opening `calibration_window_layer`.
- `calibration_window_layer` is present in `RoomUI.yy` with mode/audio/visual rows and summary/status fields:
  - `calibration_mode_field`
  - `setting_field_cal_audio`
  - `setting_field_cal_visual`
  - `calibration_summary_field`
  - `calibration_status_field`
- Calibration dispatcher cases are now active in `scr_button_scripts.gml` for IDs 31/33/34/35/36, and calibration field refresh runs when the calibration layer opens.

Immediate next tasks (Step 3 UI completion + validation)
1. Add and wire remaining calibration action buttons in the calibration window UI:
  - Test preview (`case 33`)
  - Reset defaults (`case 34`)
  - Save profile (`case 35`)
  - Toggle advanced (`case 36`)
  - Apply current-device profile (`case 37`)
2. Do first manual runtime validation pass in Room_play:
  - Open/close calibration window from settings.
  - Verify mode cycling updates text.
  - Verify audio/visual +/- rows update offsets and persist.
3. Verify per-player reload applies saved device profile after restart.

Backlog (Planned but Not Started)
Tune & Data Pipeline
• 	Full metadata support in JSON
• 	Ornament expansion rules (default + tune‑type + user preferences)
• 	Multi‑tune set support
• 	Transition events (rolls, initial E, tune linking)
UI
• 	Scrollable tune picker
• 	Tune filtering, sorting, and tabs
• 	Parts selection window
• 	Metronome configuration window
• 	Analysis window
• 	UI theme system
• 	Dynamic flex‑panel improvements (scrolling, resizing)
Playback & Audio
• 	Multi‑part playback (pipes, harmonies, drums)
• 	Backing tracks
• 	Per‑part mute/solo controls
Scoring & Analysis
• 	Phantom note judge
• 	Embellishment timing judge
• 	Millisecond correctness judge
• 	Phrase‑level rhythm judge
• 	Trend tracking
• 	Exportable analysis reports
Persistence
• 	Save/load user settings
• 	Save play logs
• 	Save scoring history

In Progress
• 	JSON loader rewrite
• 	Play array design
• 	UI flex panel improvements
• 	Tune picker refactor
• 	Controller architecture cleanup

Done
• 	Git workflow fixed
• 	Workspace map created
• 	Controller architecture documented
• 	Basic tune loader working
• 	Project plan vision drafted

🔗 Integration Notes
These notes ensure new systems integrate cleanly with the existing architecture.
Tune Loader
• 	Must normalize events before preprocessing
• 	Must support metadata wrapper in future
• 	Must validate event structure
Preprocessing
• 	Must output a stable  schema
• 	Must handle all parts (pipes, drums, metronome, transitions)
• 	Must precompute all timing and note‑off events
Playback Engine
• 	Must be decoupled from UI
• 	Must use a deterministic time‑source
• 	Must support multiple tracks
UI
• 	All windows must use flex panels
• 	UI logic must be centralized in button scripts or a UI manager
• 	Windows should be modular and independent
Scoring
• 	Judges must operate on logged events, not raw MIDI
• 	Judges must be modular and pluggable
• 	Scoring output must be structured for visualization

🧱 Guiding Principles
• 	Data‑driven: tunes, embellishments, and scoring rules live in external data
• 	Modular controllers: tune, player, UI, MIDI, scoring are separate
• 	Deterministic playback: preprocessing ensures millisecond‑accurate timing
• 	Extensible: new tune types, embellishments, or judges can be added easily
• 	UI consistency: all windows use flex panels and shared components
• 	Maintainability: scripts and objects follow clear naming and separation

🎉 End of Project Plan
This document defines the destination, the architecture, and the path forward.
Your  now becomes the “current state,” while this plan becomes the “future state.”

## Scoring Implementation Checkpoints (2026-03-29)

Checkpoint 1 (complete)
- Added script: scripts/scr_scoring/scr_scoring.gml
- Added objective judge: ms overlap by measure and overall score (0-100)
- Added player_id support (default: "default")
- Added context keying (tune_id + player_id + bpm + swing + part_key)
- Added summary export block: performance_summary.scoring
- Added tune-structure completed tile tint from selected judge measure scores

Checkpoint 2 (complete)
- Added UI helper functions for overview and popup rows:
- scoring_get_ui_overview_rows()
- scoring_get_measure_popup_rows(measure_num)

Checkpoint 3 (next)
- Build scoring panel container adjacent to fp_gameviz_controls + fp_tune_structure
- Top 20 percent = judge overview and selected judge score
- Bottom 80 percent = scrollable judge list with columns: score, best, average
- Click row to expand component metrics and show popup text from scoring helpers

UI Wiring Instructions (next session)
- Panel overview source: scoring_get_ui_overview_rows()
- Measure popup source: scoring_get_measure_popup_rows(measure_num)
- Use selected judge id in timeline_state.score_selected_judge (currently ms_overlap)
- For tune-structure popups: on measure tile click, read measure number from measure_nav_tile_hitboxes and query popup rows
- For judge list rows:
- score = current run score
- best = from tune_history_index contexts[] where context id matches selected run context
- average = running average over matching contexts[] plays
- Keep panel read-only in first pass (no editing controls)

Validation Steps After UI Hookup
- Play one tune fully, wait for review mode, confirm completed tiles are color-tinted by score
- Export history and verify summary JSON includes scoring and player_id fields
- Re-run same tune/context and verify history index context plays_count increments
- Click at least 3 measures and verify popup strings are stable and non-empty

---

## Set System Spec (2026-04-05)

### What is a Set
A set combines multiple tunes into a continuous playback session. Sets are used both for game variety and to practice competition sets as played on bagpipes. Duration is typically 3–8 minutes. Each tune may have individual settings (BPM, swing, gracenote timing). Tunes flow smoothly from one to the next.

### JSON Format
Sets live in `datafiles/sets/`, one JSON per set, filename = set slug. Sets are shared across all players (not per-player). Current schema:

```json
{
  "set": {
    "title": "March Strathspey Reel",
    "id": "example_msr",
    "description": "...",
    "playback_overrides": { "bpm_percent": 1.0, "gracenote_override_ms": null }
  },
  "tunes": [
    {
      "filename": "Scotland_The_Brave.json",
      "bpm": 88,
      "swing": "1.0",
      "transition": { "type": "gap", "beats": 4 }
    },
    ...
  ],
  "ending": { "type": "none" }
}
```

### Repeats
No dedicated `repeats` field. To repeat a tune, add it multiple times in the `tunes` array.

### Player BPM/Swing/Gracenote Overrides
Sets define defaults per tune. At runtime the player can override BPM, swing, and gracenote timing per tune before starting. These overrides are applied on top of the set defaults but are not saved back to the set JSON.

### Preprocessing Strategy
Preprocess all tunes and transitions before play starts (Strategy A — offset-and-stitch). Each tune is preprocessed independently at 0-based time; timestamps are then shifted by `previous_tune_end_ms + transition_duration_ms` and merged into a single event stream stored at `global.playback_events`. This happens at set-load time, before entering the playroom, with a loading indicator if needed.

### Transition Types
Each tune entry carries a `transition` field controlling what happens after that tune ends:

| Type | Description |
|---|---|
| `direct` | Next tune starts immediately |
| `gap` | Empty metronome gap of N beats at the next tune's BPM/meter |
| `mini_tune` | A short clip (external JSON fragment, same format as tune events) is inserted; has its own BPM/meter |
| `alt_ending` | Replace the last measure(s) of the current tune before the transition |

`alt_ending` works by: loading the alt-ending JSON fragment, locating the `last_measure_marker` / last measure with bagpipe notes in the main tune event array, and splicing the replacement events in before stitching. If a tune has trailing blank measures/beats (no bagpipe notes) those are stripped first.

A transition may combine options, e.g. alt_ending + gap + mini_tune.

### Ending
The `ending` field controls what happens after the last tune. `"type": "none"` means nothing. Future types: `gap`, `mini_tune`, `alt_ending`.

### Beat Continuity
When BPM and meter are identical across a `direct` transition, the metronome beat count continues without reset. No beat-1 accent or visual flicker at the boundary. The transition gap (when present) communicates rhythm changes via the metronome during that space.

### Performance History
- Individual tune summaries are written as normal (keyed per tune + player + BPM + swing).
- A `set_summary.json` is written to `datafiles/config/players/{player_id}/sets/` after a **full** set completion, aggregating per-tune scores.
- Each tune summary written during a set includes a `set_id` field so all performances of a set can be filtered from history.
- Mid-set abandon: completed tunes score independently; the set-level summary is **not** written unless the full set is completed.

---

## Set System — Implementation Status (2026-04-05)

### Done
- Set JSON format (`datafiles/sets/`, `example_msr.json`)
- `scr_set_preprocess_and_build_playback()` — offset-and-stitch preprocessing at load time
- `scr_playback_context_build_for_set()` — populates `global.playback_context` with segment data; all `bar_events` shifted to absolute time with all time fields (`time`, `time_ms`, `timestamp_ms`, `expected_ms`) synced
- `global.playback_context` architecture (`mode`, `segments[]`, `active_segment`) — single tune = set of 1
- Transition types: `direct` and `gap` implemented
- Tune structure panel: shows one segment at a time with title strip and prev/next arrows
- Segment auto-advance during playback
- Segment-aware scoring: `scoring_build_ms_overlap_summary` scores each segment independently, stores `score_by_segment[]` in `timeline_state`
- Segment-aware tile colours (`scoring_get_measure_visual_style`)
- Segment-aware judge panel / popup (`scoring_get_panel_focus`, `scoring_find_measure_result`, `scoring_get_detail_popup_rows`)
- Measure gap fix: `seg_bar_events` now includes all events with `measure >= 1`, not just bar/beat markers

### Done (updated 2026-05-03)
- `gv_get_current_planned_measure` — Priority 1 path uses `measure_nav_entries` (set-aware); fallback full-scan only triggers when nav entries are absent. Acceptable.
- `gv_review_jump_to_measure` — uses `measure_nav_entries` for target lookup (set-aware); `measure_ms` only used for scroll-offset math, acceptable for single-tempo sets.
- **Set picker UI** — `view_mode = "sets"` toggle live in `scr_tune_library`; left pane = filtered tune list, right pane = set builder slots; "Sets →" button switches modes. Set builder in `scr_set_scripts` handles add/remove/reorder.
- **Set name / current tune name in gameinfo window** — `scr_gameinfo_update_title(_seg_index)` in `scr_set_scripts` formats "Set Title — Tune Title" in set mode and pushes to `global.gameinfo_title[0]`. Called on segment auto-advance and now-line sync.

### In Progress / Deferred
- **Score canvas set-mode measure-count reconciliation** — The "too many / too few starts" adjustment pass runs only in `!_set_mode`. Per-segment snippet-duration primary path produces exact count when cache is populated; fallback (event-marker scan, no reconciliation) still possible for segments missing duration data — pickup miscount on canvas possible in that case.
- **Beat-anchor guide line validation** — `score_lane_anchor_guides_enabled` draw path implemented in `scr_game_viz` and normalized in `scr_tune_load`; not yet validated in-engine (runtime rendering not smoke-tested).
- **`gv_review_jump_to_measure` offset for mixed-tempo sets** — scroll-offset calc uses single-tune `measure_ms`; view may land slightly off-center for wide tempo-spread sets. Low priority.

### Not Yet Started

**Per-tune runtime overrides UI**
- When a set is selected, player can adjust BPM %, swing, gracenote per tune before pressing Play.
- These are applied at preprocess time and not persisted to the set JSON.

**Transition types: `mini_tune`, `alt_ending`**
- `mini_tune`: load a small event JSON, preprocess it, offset-and-stitch between tunes.
- `alt_ending`: strip trailing blank measures from main tune events, splice in alt-ending events.
- Both require external authoring of the event fragments (ABC/Excel export pipeline) for now; in-game authoring is future scope.

**Judge scope toggle (set overall vs per-tune)**
- The judge panel shows per-segment scores when switching segments.
- Need an explicit toggle: "Set overall" vs "Tune N" so the player can compare aggregate vs per-tune performance without navigating the structure panel.

**Performance history — set-level summary**
- Write `set_summary.json` on full-set completion.
- Tag individual tune summaries with `set_id`.
- Mid-set abandon: write completed tune summaries without set summary.

**Set library index**
- Analogous to `tune_library.json` — a `set_library.json` index scanned at startup from `datafiles/sets/`.
- Enables filtering, sorting, and display in the picker without re-reading every set JSON at runtime.



## Cleanup Backlog

Observations collected during full-codebase annotation (annotation pass, 2025).

1. **Duplicate thin wrappers � metronome:** metronome_normalize_time_sig and metronome_get_effective_quarter_bpm in scr_metronome.gml are direct passthroughs to identically-named functions in scr_timing_utils.gml. Consolidation candidate � consider inlining or removing the wrapper layer.

2. **Another wrapper chain:** 	une_get_effective_quarter_bpm in scr_preprocess_tune.gml delegates directly to 	iming_get_effective_quarter_bpm. Same consolidation candidate.

3. **Empty stub file:** ~~scr_tune_preprocess.gml contains no functions.~~ **RESOLVED:** `scripts/scr_tune_preprocess/` deleted (April 2026).

4. **Dead code block in scr_tune_scripts.gml:** ~~tune_metronome_build_pattern, tune_get_total_ms, and tune_build_events inside a /* */ block comment.~~ **RESOLVED:** Entire unclosed block comment (lines 1615–1743) removed (April 2026). All three were dead — inside an unclosed `/*` with no callers outside the comment.

5. **old_scr_tune_library:** ~~The file holds hardcoded tune data predating the JSON library.~~ **RESOLVED:** `scripts/old_scr_tune_library/` deleted; removed from .yyp and resource_order (April 2026).

### Loop Pickup Timing Update (2026-05-12)

- Fixed single-tune loop template construction in `scr_button_loop_build_playback_events` so pre-bar pickup events attached to selected measures are repeated inside each loop iteration (not only in the one-time prefix).
- Loop cycle timing is now pickup-aware: iteration window starts at pickup time when present, so the loop naturally includes required spacer time before the next downbeat when needed.
- Added debug field `pickup_lead_ms` in the loop build log line for quick verification during regression runs.
- Validation target for next QA pass:
  - Initial pickup loops: pickup should repeat every iteration with no visual/audio stretch.
  - Internal pickup loops: if a selected measure has pre-bar pickup content, it should repeat per cycle with stable measure alignment.

### Loop Score-Lane Pickup Alignment (2026-05-12)

- Updated single-tune loop-runtime score-lane timing in `scr_game_viz` so each rendered measure can start at the earliest pre-boundary event tagged to that same measure.
- This keeps loop visual lead-ins attached to their intended measure image without changing event scheduling, marker generation, or playback callbacks.
- Scope is intentionally narrow for runtime cost control:
  - runs only in single-tune loop runtime (`!set_mode && loop_runtime_active`),
  - uses existing in-memory planned events,
  - no new globals, caches, file IO, or per-frame allocations outside existing arrays.
- Validation target for next QA pass:
  - Loop subset not starting at measure 1 (e.g. Aros Park 9-12): opening lead-in should render as part of loop entry instead of disappearing/stretching.
  - In-loop pre-bar lead-ins should render with their attached measure image.

---

## Calibration/Latency: Future Consideration (2026-05-13)
- Current calibration probe measures total round-trip latency (audio output, visual, input capture, human delay).
- Scheduler compensates for audio output latency using `audio_output_offset_ms` as measured by the probe.
- If human delay is inconsistent, an independent audio output latency measurement (e.g., by routing audio out to audio in and logging trigger/detect delta) could provide a strong, stable baseline for prescheduling.
- For now, continue with probe-based approach, but revisit the value of separate audio latency measurement after further user testing.
- If implemented, set `audio_output_offset_ms` directly from measured value, and use probe to focus on visual/input lag only.
- Add a project review item: **Reconsider separate audio latency measurement for improved baseline and compensation accuracy.**

---

## Development Workflow Hardening (Lesson from Phase 1 Calibration)

**Problem**: Phase 1 calibration refactor touched core timing/offset paths and accumulated dead code that wasn't fully rolled back, causing a crash on fresh save load.

### Guidelines for Future Major Refactors

#### 1. **Feature-flag risky changes, don't merge to main until proven**
- Use a dedicated \eature/\ branch for experiments that rewire core systems
- Require explicit feature flag to activate  
- All code paths must compile cleanly and pass tests
- Do not commit dead code (commented-out sections, unreachable paths)

#### 2. **Version checkpoints frequently**
- After every 2�3 working hours on a risky refactor, create a temporary commit and test end-to-end
- Test: launch game, play a tune, close cleanly
- Never let uncommitted work pile up

#### 3. **Separate concerns**
- Timing offsets are **core** � touch only in isolation
- Calibration logic is **experimental** � keep in separate functions
- Do not weave calibration into scoring/MIDI/event paths
- Make calibration-aware behavior optional via parameters, not embedded

#### 4. **Compilation validation before every commit**
- Run full project compile
- Zero errors before committing � fix warnings about unreachable code immediately
- Use documentation tags (\@reads\, \@writes\, \@callers\) to make dependencies explicit

#### 5. **Rollback checkpoints**
- Tag stable releases: \_stable_precompile\, \_before_calibration_experiment\, etc.
- If refactor fails (>2 hours rework), revert to the last tag
- Document the reset in PROJECT_PLAN.md

#### 6. **Per-feature testing checklist**
Before declaring a refactor done:
- [ ] Game launches (main menu visible)
- [ ] Single-tune playback (load, play, stop, review)
- [ ] Multi-tune set playback
- [ ] Settings persist across restart
- [ ] Event export works (CSV/JSON in datafiles/performances/)
- [ ] No stale profiles break new profiles

#### 7. **Code review before merge**
- For changes >100 lines touching core systems, require second review
- Check for dead code, proper documentation, redundancy

---

## Next Steps (Phase 2: Calibration Redesign)

**Current state**: Timing offsets work, profiles persist, baseline stable (2026-05-17).

**Option A: Manual Offset Editing** (faster, lower risk)
- Add +/- buttons for audio/visual/input offsets in settings
- User tweaks by ear while playing reference tune
- Persist immediately

**Option B: Flash/Click Subtraction** (higher complexity, better UX)
- Visual test: tap when you see flash (V+I+R)
- Audio test: tap when you hear click (A+I+R)
- Derive audio offset via subtraction (reaction cancels out)
- Requires MIDI loopback or external hardware

**Recommendation**: Start with **Option A**, move to **Option B** if needed.
