Last reviewed: 2026-05-23
Status: Continuous two-mode calibration workflow active. Audio is the primary measured compensation; Visual and MIDI In are advanced trims (MIDI In usually stays 0).

## 1. Purpose
Calibration now manages only persistent split timing offsets for manual adjustment.

Supported behavior:
- Persistent per-device profiles
- Startup hydration from player settings
- Manual offset nudging in settings
- Offset apply for playback, input alignment, scoring, and visual timing paths

Core implementation lives in `scr_tune_scripts.gml`.

## 2. Active Offset Domains
- `audio_output_offset_ms` — output-chain audio compensation (primary calibration target)
- `visual_alignment_offset_ms` — display alignment trim (perceptual, optional)
- `input_capture_offset_ms` — MIDI input capture trim (advanced; usually keep at 0)

Removed:
- `scoring_compare_offset_ms` — removed to ensure player feedback remains honest (offset should not mask timing issues)

Single apply entrypoint: `scr_tune_scripts.gml` `timing_calibration_apply_offsets(audio_ms, visual_ms, source_label)`

## 3. Core State Model
Primary state struct: `global.timing_calibration`

Retained fields:
- `active`
- `status`
- `active_device_key`
- `device_profiles`
- `audio_offset_ms`
- `visual_offset_ms`
- `input_offset_ms` (advanced; default 0)
- `last_message`
- `jitter_summary`

Removed fields:
- `scoring_offset_ms`
- Probe/session-related fields

## 4. Startup Load and Hydration
Startup caller:
- `obj_game_controller/Create_0.gml`

Player settings loader:
- `scr_scoring.gml` `scoring_player_settings_load_for_player(...)`

Hydration path:
- `timing_calibration_hydrate_from_settings(...)`
- `timing_calibration_apply_profile_for_current_device()`

Device key source:
- `midi_input_device_name | midi_output_device_name | MIDI_chanter`

## 5. Persistence Model
Settings save payload includes:
- `active_device_key`
- `device_profiles`

Stored per-device profile fields:
- `audio_output_offset_ms`
- `visual_alignment_offset_ms`

Runtime-only advanced field:
- `input_capture_offset_ms` (edited in UI, default 0; not currently written into per-device profile payload)

Removed from payload/profile:
- `scoring_compare_offset_ms` (player feedback must remain honest)

## 6. UI Wiring
Calibration buttons active in dispatcher:
- `31` mode change
- `32` manual offset nudge (audio/visual/MIDI in)
- `33` start/stop continuous calibration test loop (button text: `Start`)
- `34` reset to system defaults
- `35` OK (save profile + close)
- `36` toggle advanced panel state (button text: `Adv`)
- `37` Cancel (close + restore pre-session snapshot)

Current manual nudge behavior:
-- Script supports three field names:
	- `setting_field_cal_audio`
	- `setting_field_cal_visual`
	- `setting_field_cal_input`
- Nudge applies immediately
- Audio/visual persist to current device profile and player settings
- UI refresh updates mode, audio/visual/input offsets, summary canvas, and status field

Current session behavior:
- Opening calibration captures a session snapshot of current audio/visual/input offsets.
- `Start` runs a continuous repeating click loop for live vetting (same button stops when active).
- Mode changes can be made while the loop is running.
- `OK` commits current values, saves device profile, and closes.
- `Cancel` closes and restores offsets from the session snapshot.
- Closing the window with the close button behaves as Cancel.

Calibration window layout currently includes:
- launcher in settings window
- dedicated `calibration_window_layer`
- mode/MIDI In/audio/visual/summary/status rows
- action footer buttons: Start, Reset, OK, Adv, Cancel

## 7. Removed Workflow
Removed concepts:
- Calibration mode UI
- Recommendation splitting
- Probe analysis workflow
- Draft/accept/cancel session workflow
- End-of-play auto probe hook
- Probe config defaults (`timing_calibration_match_window_ms`, `timing_calibration_min_matches`)

## 8. What Still Matters Functionally
Already wired and retained:
- Audio scheduling uses `audio_output_offset_ms`
- Visual timing paths read `visual_alignment_offset_ms`
- Event history/export records both offsets

No longer used:
- Scoring compare offset (removed to preserve honest feedback)

## 9. Diagnostics
`jitter_summary` remains, but `updated_at_ms` metadata was removed.

## 10. Current Assessment
Stable retained baseline:

Open follow-up work:
- Manual validation pass for all calibration button handlers in-room (preview click cadence, reset/save/apply state transitions).
- Optional: restore external audio sample capture hook once a reliable input path is available.

## 12. Staged Calibration Workflow (In Progress)

Calibration now uses a user-vetting-first workflow:

1) Manual vetting with continuous loop (active)
- Goal: let the user align click timing and visuals by ear/eye.
- Modes: `Bouncing Ball`, `Converging Beams`.
- Trigger: `Start` button in the calibration window.
- Output: user-adjusted `audio_output_offset_ms`, optional `visual_alignment_offset_ms`, optional `input_capture_offset_ms`.

2) Internal MIDI loopback seed (optional)
- Goal: provide a baseline suggestion before manual refinement.
- Trigger: `L` key (dev path) from main menu/settings.
- Output: `midi_internal_offset_ms`, `jitter_midi_ms`.

3) External audio loopback (optional scaffold)
- Goal: provide an optional measured seed for external audio path.
- Trigger: `O` key (dev path) from main menu/settings.
- Status: available as scaffold, not required for user calibration workflow.

## 11. Change Log
2026-05-23
- Re-enabled staged calibration controls (mode/test/reset/save/advanced/apply) in button dispatcher and room UI.
- Added calibration window footer action buttons in `RoomUI.yy` and wired to button IDs `33`-`37`.

2026-05-23 (continuous vetting update)
- Reduced mode set to two user-vetting modes: `Bouncing Ball` and `Converging Beams`.
- Updated Test to a continuous start/stop loop instead of one-shot click (UI label now `Start`).
- Added calibration session snapshot behavior: open captures snapshot, Cancel/close restores snapshot.
- Mapped `OK` to save+close and `Cancel` to close with no change.

2026-05-23 (advanced offset and labels)
- Added dedicated MIDI In row and nudge controls in calibration UI.
- Kept MIDI In as advanced default-0 trim rather than a primary calibration target.
- Shortened advanced footer label from `Advanced` to `Adv`.

2026-05-17 (phase 2)
- Simplified to two active offsets: audio and visual only.
- Marked input_capture_offset_ms as reserved for future MIDI timestamp work.
- Removed scoring_compare_offset_ms to ensure player feedback remains honest.
- Updated UI to support audio/visual manual nudging only.
- Updated all apply/store/hydrate paths to match.

2026-05-17 (phase 1)
- Removed calibration mode, mode UI, recommendation splitting, probe/draft/accept workflow, and metadata timestamps.
- Kept manual split-offset persistence/apply baseline.