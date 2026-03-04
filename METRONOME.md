# METRONOME.md

## Purpose

This document describes the current metronome runtime behavior and integration points.

---

## Current architecture

- Source script: `scripts/scr_metronome/scr_metronome.gml`
- Core config struct: `global.METRONOME_CONFIG`
- Modes (via `global.metronome_mode_options`):
	- `None`
	- `Click`
	- `Drums`
- Pattern storage shape:

```gml
global.METRONOME_CONFIG.patterns[mode][time_signature][variant] = [
	{ beat_position, drum_notes, emphasis, light? },
	...
]
```

Each pattern beat can map to one or more drum sounds. Sounds can be raw MIDI note values or named keys resolved through `global.METRONOME_CONFIG.drums`.

---

## Event generation

### tune metronome

- Function: `metronome_generate_events(_tune, _settings)`
- Produces:
	- marker events (`type: "marker"`, `marker_type: "beat"`, measure/beat context)
	- MIDI drum events (`note_on` + short `note_off`)
- Timing basis:
	- reads tune meter (`tune_metadata.meter`)
	- reads tune tempo (`tune_metadata.tempo_default`) unless overridden
	- uses `timing_get_effective_quarter_bpm()` via `metronome_get_effective_quarter_bpm()`

### count-in metronome

- Function: `metronome_generate_countin_events(_tune, _settings, _count_in_measures)`
- Produces negative-measure marker context for count-in (e.g., `-1`, `-2`)
- Uses same mode/pattern/volume and BPM override logic as tune generation

---

## Runtime controls and UI wiring

- Mode field updates:
	- `scr_metronome_mode_change()`
	- updates `global.metronome_mode`
	- refreshes pattern options via `metronome_update_pattern_list(time_sig)`
- Pattern field updates:
	- `scr_metronome_pattern_change()`
	- updates `global.metronome_pattern_selection`
- Volume field updates:
	- controls `global.metronome_volume`
	- mapped to velocity levels:
		- emphasis = `volume`
		- normal = `floor(volume * 0.7)`
		- light = `floor(volume * 0.4)`

Per-set overrides are supported through optional `_settings` on generation functions:
- `bpm`
- `metronome_mode`
- `metronome_pattern`
- `metronome_volume`

---

## Helper APIs

- `metronome_normalize_time_sig(_time_sig)`
- `metronome_get_effective_quarter_bpm(_bpm, _time_sig)`
- `metronome_update_pattern_list(_time_sig)`
- `metronome_set_pattern(_time_sig, _variant_name)`
- `metronome_list_patterns()`
- `metronome_pattern_to_symbols(_pattern)`
- `metronome_toggle(_enabled)`

---

## Logging behavior

- Metronome beat markers are kept in event history context.
- Raw metronome MIDI `note_on`/`note_off` events on the metronome channel are filtered out before final event history insertion in playback callback.

This keeps beat/measure timing context without flooding exports with percussion note rows.

