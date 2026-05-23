Last reviewed: 2026-05-17
Status: Manual-offset baseline. Split offsets persist and apply on startup; probe and mode workflow removed.

## 1. Purpose
Calibration now manages only persistent split timing offsets for manual adjustment.

Supported behavior:
- Persistent per-device profiles
- Startup hydration from player settings
- Manual offset nudging in settings
- Offset apply for playback, input alignment, scoring, and visual timing paths

Core implementation lives in `scr_tune_scripts.gml`.

## 2. Active Offset Domains
- `audio_output_offset_ms` — audio playback scheduling offset
- `visual_alignment_offset_ms` — planned notebeam/visual timeline offset

Reserved (not currently used):
- `input_capture_offset_ms` — reserved for future use if true MIDI device timestamps become available

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
- `input_offset_ms` (reserved; always 0)
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

Removed from payload/profile:
- `scoring_compare_offset_ms` (player feedback must remain honest)

## 6. UI Wiring
Calibration buttons active in dispatcher:
- `32` manual offset nudge (audio/visual only)
- `37` apply saved profile

Disabled/removed workflow buttons:
- `31` mode change
- `33` start run
- `34` prepare probe draft
- `35` accept
- `36` cancel

Current manual nudge behavior:
- Script supports two field names:
	- `setting_field_cal_audio`
	- `setting_field_cal_visual`
- Nudge applies immediately
- Nudge persists immediately to current device profile and player settings
- UI refresh updates only audio and visual offset fields

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
- Input capture offset (reserved for future MIDI timestamp work)
- Scoring compare offset (removed to preserve honest feedback)

## 9. Diagnostics
`jitter_summary` remains, but `updated_at_ms` metadata was removed.

## 10. Current Assessment
Stable retained baseline:

Open follow-up work:

## 12. Staged Calibration Workflow (In Progress)

Calibration now moves toward a 3-stage workflow:

1) Internal MIDI loopback (implemented)
- Goal: measure internal MIDI path timing.
- Trigger: `L` key (dev path) from main menu/settings.
- Output: `midi_internal_offset_ms`, `jitter_midi_ms`.

2) External audio loopback (scaffold implemented)
- Goal: measure external audio chain timing (interface/driver/render/output path).
- Trigger: `O` key (dev path) from main menu/settings.
- Current behavior:
	- emits timed pulse trials via MIDI output
	- records send timing
	- exposes sample registration hook `timing_calibration_external_audio_register_sample(_latency_ms)`
	- computes/stores `audio_output_offset_ms` and `jitter_audio_ms` once samples are registered
- Note: automatic audio-input capture hook is the next integration step.

3) User perceptual dial (planned)
- Goal: final ear-based trim after measured offsets are applied.
- Status: not implemented yet.

## 11. Change Log
2026-05-17 (phase 2)
- Simplified to two active offsets: audio and visual only.
- Marked input_capture_offset_ms as reserved for future MIDI timestamp work.
- Removed scoring_compare_offset_ms to ensure player feedback remains honest.
- Updated UI to support audio/visual manual nudging only.
- Updated all apply/store/hydrate paths to match.

2026-05-17 (phase 1)
- Removed calibration mode, mode UI, recommendation splitting, probe/draft/accept workflow, and metadata timestamps.
- Kept manual split-offset persistence/apply baseline.