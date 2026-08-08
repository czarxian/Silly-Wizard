// scr_tune_preprocess — Tune preprocessing & play array builder
// Purpose: Convert raw tune JSON (with unit-based timings and embellishments) into a playable MIDI event array.
// Key functions: 
//   - scr_preprocess_tune(_tune) — Main entry point; returns playable event array
//   - tune_units_to_ms(_units, _tempo_bpm, _unit_ms) — Unit → millisecond conversion
//   - tune_note_letter_to_midi(_letter, _base_midi) — Resolve note letter to MIDI value
//   - tune_expand_embellishment(_emb_name, _base_midi) — Expand embellishment notation into note sequence
//   - tune_build_playable_events(_tune) — Filter and convert raw events to MIDI format

/// @function scr_preprocess_tune(_tune, _overrides)
/// @description Main preprocessing entry point. Resolves a canonical tune_data struct from loaded tune data, a wrapper struct, or obj_tune; builds a sorted playable MIDI event array with tempo, gracenote, swing, and cut overrides.
/// @param {struct|Id.Instance} _tune  Loaded tune_data struct, wrapper with tune_data, or obj_tune instance
/// @param {struct|real|undefined} _overrides  Override struct ({bpm, swing_mult, gracenote_override_ms, head_cut_beats, tail_cut_beats}) or bare BPM real
/// @returns {array}  Playable MIDI event array sorted by time (ms)
/// @reads   global.emb_library, global.EMBELLISHMENT_CONFIG, global.MIDI_chanter (via chanter functions)
/// @writes  global.CHANTER_PROFILE_CACHE (lazily, via chanter_get_profile on first use)
/// @objects none
/// @callers scr_tune_scripts (play path), scr_set_scripts (set play path)
function scr_preprocess_tune(_tune, _overrides) {
	var tune_data = undefined;
	if (is_struct(_tune)) {
		if (variable_struct_exists(_tune, "tune_data")) {
			tune_data = variable_struct_get(_tune, "tune_data");
		} else if (variable_struct_exists(_tune, "tune_metadata")
			|| variable_struct_exists(_tune, "performance")
			|| variable_struct_exists(_tune, "events")) {
			tune_data = _tune;
		}
	} else if (instance_exists(_tune) && variable_instance_exists(_tune, "tune_data")) {
		tune_data = variable_instance_get(_tune, "tune_data");
	}
	if (!is_struct(tune_data) || !variable_struct_exists(tune_data, "is_loaded") || !bool(variable_struct_get(tune_data, "is_loaded"))) {
		show_debug_message("ERROR: scr_preprocess_tune called on unloaded tune");
		return array_create(0);
	}

	var override_bpm = undefined;
	var override_swing = undefined;
	var override_grace_ms = undefined;
	if (is_struct(_overrides)) {
		if (variable_struct_exists(_overrides, "bpm") && !is_undefined(variable_struct_get(_overrides, "bpm"))) {
			override_bpm = variable_struct_get(_overrides, "bpm");
		}
		if (variable_struct_exists(_overrides, "swing_mult") && !is_undefined(variable_struct_get(_overrides, "swing_mult"))) {
			override_swing = variable_struct_get(_overrides, "swing_mult");
		} else if (variable_struct_exists(_overrides, "swing") && !is_undefined(variable_struct_get(_overrides, "swing"))) {
			override_swing = variable_struct_get(_overrides, "swing");
		}
		if (variable_struct_exists(_overrides, "gracenote_override_ms") && !is_undefined(variable_struct_get(_overrides, "gracenote_override_ms"))) {
			override_grace_ms = variable_struct_get(_overrides, "gracenote_override_ms");
		} else if (variable_struct_exists(_overrides, "gracenote_ms") && !is_undefined(variable_struct_get(_overrides, "gracenote_ms"))) {
			override_grace_ms = variable_struct_get(_overrides, "gracenote_ms");
		}
	} else if (!is_undefined(_overrides)) {
		override_bpm = _overrides;
	}

	show_debug_message("=== Preprocessing tune: " + string(variable_struct_get(tune_data, "filename")) + " ===");
	
	// Extract metadata and events from the struct
	var meta = variable_struct_get(tune_data, "tune_metadata");
	var perf = variable_struct_get(tune_data, "performance");
	var events = variable_struct_get(tune_data, "events");
	events = tune_normalize_pickup_positions(events, meta);
	
	// Debug: Check what's in the tune object
	show_debug_message("  _tune.tune_data contents:");
	show_debug_message("    tune_metadata type: " + string(typeof(meta)));
	show_debug_message("    events length: " + string(array_length(events)));
	show_debug_message("    performance type: " + string(typeof(perf)));
	show_debug_message("    is_loaded: " + string(variable_struct_get(tune_data, "is_loaded")));
	show_debug_message("    filename: " + string(variable_struct_get(tune_data, "filename")));
	
	// Tempo & timing - handle empty strings with fallback defaults
	var tempo_str = string(meta.tempo_default ?? "");
	var tempo_bpm = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
	if (!is_undefined(override_bpm)) {
		tempo_bpm = real(override_bpm);
	}
	var effective_quarter_bpm = tune_get_effective_quarter_bpm(tempo_bpm, meta.meter ?? "4/4");
	
	// Calculate unit_ms from BPM and unit note length
	// BPM is quarter notes per minute, so ms_per_quarter = 60000 / BPM
	var ms_per_quarter = 60000 / effective_quarter_bpm;
	
	// Check what the unit note is (defaults to eighth note if not specified)
	var unit_note = string(meta.unit_note_length ?? "1/8");
	var unit_multiplier = tune_note_fraction_to_quarter_multiplier(unit_note);
	var unit_ms = ms_per_quarter * unit_multiplier;
	
	show_debug_message("  Tempo: " + string(tempo_bpm) + " BPM (effective quarter BPM " + string(effective_quarter_bpm) + ") -> " + string(ms_per_quarter) + "ms per beat");
	show_debug_message("  Calculated unit_ms: " + string(unit_ms) + " (for " + unit_note + " notes, multiplier=" + string(unit_multiplier) + ")");
	
	var base_str = string(is_struct(perf) && variable_struct_exists(perf, "instrument_midi_note_base") ? variable_struct_get(perf, "instrument_midi_note_base") : "");
	var base_midi = (string_length(base_str) > 0) ? real(base_str) : 55;
	
	// Tune output channels (0-based): default tune pipes = 2; channel 1 reserved.
	var channel = 2;
	
	show_debug_message("  Tempo: " + string(tempo_bpm) + " BPM (effective quarter BPM " + string(effective_quarter_bpm) + ") -> " + string(ms_per_quarter) + "ms per beat");
	show_debug_message("  Calculated unit_ms: " + string(unit_ms) + " (for " + unit_note + " notes, multiplier=" + string(unit_multiplier) + ")");
	show_debug_message("  Base MIDI: " + string(base_midi));
	
	// Apply swing overrides before building playable events
	var perf_swing = is_struct(perf) && variable_struct_exists(perf, "swing") ? variable_struct_get(perf, "swing") : "";
	var meta_swing = is_struct(meta) && variable_struct_exists(meta, "swing") ? variable_struct_get(meta, "swing") : "";
	var meta_grace_override = is_struct(meta) && variable_struct_exists(meta, "gracenote_override_ms") ? variable_struct_get(meta, "gracenote_override_ms") : undefined;
	var meta_grace_ms = is_struct(meta) && variable_struct_exists(meta, "gracenote_ms") ? variable_struct_get(meta, "gracenote_ms") : undefined;
	var swing_value = !is_undefined(override_swing) ? override_swing : (meta_swing ?? perf_swing ?? "");
	var swing_mult = tune_parse_swing_multiplier(swing_value);
	var grace_override_ms = !is_undefined(override_grace_ms) ? override_grace_ms : (meta_grace_override ?? meta_grace_ms ?? undefined);
	if (swing_mult > 0) {
		events = tune_apply_swing_to_events(events, tempo_bpm, unit_ms, swing_mult, grace_override_ms);
	}

	// Build playable events
	var playable = tune_build_playable_events(_tune, tempo_bpm, unit_ms, base_midi, channel, events, grace_override_ms);

	// Apply optional head/tail cuts from tune metadata (or explicit overrides).
	// New transition schema uses *_cut_measures; convert to beats when beat fields are absent.
	var head_cut_beats = tune_parse_cut_beats(meta[$ "head_cut_beats"] ?? "");
	var tail_cut_beats = tune_parse_cut_beats(meta[$ "tail_cut_beats"] ?? "");
	if (head_cut_beats <= 0) {
		head_cut_beats = tune_parse_cut_measures_as_beats(meta[$ "head_cut_measures"] ?? "", string(meta[$ "meter"] ?? "4/4"));
	}
	if (tail_cut_beats <= 0) {
		tail_cut_beats = tune_parse_cut_measures_as_beats(meta[$ "tail_cut_measures"] ?? "", string(meta[$ "meter"] ?? "4/4"));
	}
	if (is_struct(_overrides)) {
		if (variable_struct_exists(_overrides, "head_cut_beats") && !is_undefined(variable_struct_get(_overrides, "head_cut_beats"))) {
			head_cut_beats = tune_parse_cut_beats(variable_struct_get(_overrides, "head_cut_beats"));
		}
		if (variable_struct_exists(_overrides, "tail_cut_beats") && !is_undefined(variable_struct_get(_overrides, "tail_cut_beats"))) {
			tail_cut_beats = tune_parse_cut_beats(variable_struct_get(_overrides, "tail_cut_beats"));
		}
	}
	if (head_cut_beats > 0 || tail_cut_beats > 0) {
		playable = tune_apply_head_tail_cuts(playable, tempo_bpm, string(meta[$ "meter"] ?? "4/4"), head_cut_beats, tail_cut_beats);
	}
	
	show_debug_message("  → Generated " + string(array_length(playable)) + " playable events");
	
	// Debug: Export playable events to CSV for inspection
	var tune_filename = is_struct(tune_data) && variable_struct_exists(tune_data, "filename")
		? string(variable_struct_get(tune_data, "filename"))
		: "";
	tune_export_playable_events_csv(playable, tune_filename);
	
	return playable;
}

/// @function tune_parse_cut_beats(_raw)
/// @description Parse cut beats from metadata/override value; returns non-negative real.
function tune_parse_cut_beats(_raw) {
	var s = string_trim(string(_raw ?? ""));
	if (string_length(s) <= 0) return 0;
	var v = real(s);
	if (v < 0) v = 0;
	return v;
}

/// @function tune_parse_cut_measures_as_beats(_raw_measures, _meter)
/// @description Convert a cut-measure value to beats using the meter numerator.
function tune_parse_cut_measures_as_beats(_raw_measures, _meter) {
	var measures = tune_parse_cut_beats(_raw_measures);
	if (measures <= 0) return 0;
	var meter_norm = timing_normalize_time_sig(string(_meter));
	var parts = string_split(meter_norm, "/");
	var beats_per_measure = (array_length(parts) >= 1) ? real(parts[0]) : 4;
	if (beats_per_measure <= 0) beats_per_measure = 4;
	return measures * beats_per_measure;
}

/// @function tune_normalize_pickup_positions(_events, _meta)
/// @description Detect and correct legacy pickup encoding where an initial zero-unit bar causes pickup notes to be labeled as measure 1. Recomputes measure/beat/division from total_units so measure 1 starts at the first full downbeat.
/// @param {array} _events  Raw tune events array
/// @param {struct} _meta   Tune metadata struct (meter, unit_note_length)
/// @returns {array} Events with normalized measure/beat/division when a pickup is detected
/// @reads   none
/// @writes  none
/// @objects none
/// @callers scr_preprocess_tune
function tune_normalize_pickup_positions(_events, _meta) {
	if (!is_array(_events) || array_length(_events) <= 0) return _events;

	var meter = timing_normalize_time_sig(string(_meta[$ "meter"] ?? "4/4"));
	var meter_parts = string_split(meter, "/");
	var beats_per_measure = (array_length(meter_parts) >= 1) ? real(meter_parts[0]) : 4;
	var beat_denom = (array_length(meter_parts) >= 2) ? real(meter_parts[1]) : 4;
	if (beats_per_measure <= 0) beats_per_measure = 4;
	if (beat_denom <= 0) beat_denom = 4;

	var unit_note = string(_meta[$ "unit_note_length"] ?? "1/8");
	var unit_multiplier = tune_note_fraction_to_quarter_multiplier(unit_note);
	if (unit_multiplier <= 0) unit_multiplier = 0.5;

	var units_per_beat = (4 / beat_denom) / unit_multiplier;
	if (units_per_beat <= 0) return _events;
	var units_per_measure = units_per_beat * beats_per_measure;

	var eps = 0.0001;
	var first_bar_units = -1;
	var second_bar_units = -1;

	for (var i = 0; i < array_length(_events); i++) {
		var bar_ev = _events[i];
		if (!is_struct(bar_ev)) continue;
		if (string(bar_ev[$ "type"] ?? "") != "structure") continue;
		if (string(bar_ev[$ "structure"] ?? "") != "bar") continue;

		var bar_units = real(bar_ev[$ "total_units"] ?? 0);
		if (bar_units <= eps) continue; // Ignore startup bars like "||" at unit 0.

		if (first_bar_units < 0) {
			first_bar_units = bar_units;
		} else if (bar_units > first_bar_units + eps) {
			second_bar_units = bar_units;
			break;
		}
	}

	if (first_bar_units <= eps) return _events;

	var effective_measure_units = units_per_measure;
	if (second_bar_units > first_bar_units + eps) {
		var inferred_units = second_bar_units - first_bar_units;
		if (inferred_units > eps) {
			effective_measure_units = inferred_units;
		}
	}

	if (!(first_bar_units < (effective_measure_units - eps))) return _events;

	var pickup_units = first_bar_units;
	var out = array_create(array_length(_events));

	for (var j = 0; j < array_length(_events); j++) {
		var ev = _events[j];
		if (!is_struct(ev)) {
			out[j] = ev;
			continue;
		}

		var total_units = real(ev[$ "total_units"] ?? 0);
		var measure = 1;
		var beat = 1;
		var division = 0;

		if (total_units < pickup_units - eps) {
			measure = 0;
			beat = floor(total_units / units_per_beat) + 1;
			var units_into_pickup_beat = total_units - (beat - 1) * units_per_beat;
			division = units_into_pickup_beat / units_per_beat;
		} else {
			var shifted_units = total_units - pickup_units;
			measure = floor(shifted_units / effective_measure_units) + 1;
			var units_into_measure = shifted_units - (measure - 1) * effective_measure_units;
			beat = floor(units_into_measure / units_per_beat) + 1;
			var units_into_beat = units_into_measure - (beat - 1) * units_per_beat;
			division = units_into_beat / units_per_beat;
		}

		ev[$ "measure"] = measure;
		ev[$ "beat"] = beat;
		ev[$ "division"] = division;
		out[j] = ev;
	}

	show_debug_message("  Applied pickup normalization: pickup_units=" + string_format(pickup_units, 0, 4)
		+ ", measure_units=" + string_format(effective_measure_units, 0, 4));

	return out;
}

/// @function tune_apply_head_tail_cuts(_events, _tempo_bpm, _meter, _head_cut_beats, _tail_cut_beats)
/// @description Trim playable events by beat amounts at head/tail and rebase time to 0.
function tune_apply_head_tail_cuts(_events, _tempo_bpm, _meter, _head_cut_beats, _tail_cut_beats) {
	if (!is_array(_events) || array_length(_events) <= 0) return _events;

	var meter = timing_normalize_time_sig(_meter);
	var parts = string_split(meter, "/");
	var denom = (array_length(parts) >= 2) ? real(parts[1]) : 4;
	if (denom <= 0) denom = 4;

	var quarter_bpm = tune_get_effective_quarter_bpm(_tempo_bpm, meter);
	if (quarter_bpm <= 0) quarter_bpm = 120;
	var ms_per_quarter = 60000 / quarter_bpm;
	var beat_ms = ms_per_quarter * (4 / denom);

	var head_ms = max(0, _head_cut_beats) * beat_ms;
	var tail_ms = max(0, _tail_cut_beats) * beat_ms;

	var max_time = 0;
	for (var i = 0; i < array_length(_events); i++) {
		var t = real(_events[i][$ "time"] ?? 0);
		if (t > max_time) max_time = t;
	}

	var keep_start = head_ms;
	var keep_end = max_time - tail_ms;
	if (keep_end <= keep_start) {
		show_debug_message("  Cut beats removed full tune (head=" + string(_head_cut_beats) + ", tail=" + string(_tail_cut_beats) + ")");
		return array_create(0);
	}

	var out = [];
	var active_counts = {};
	var active_note = {};
	var active_chan = {};

	for (var j = 0; j < array_length(_events); j++) {
		var ev = _events[j];
		if (!is_struct(ev)) continue;
		var et = real(ev[$ "time"] ?? 0);
		var ev_type = string(ev[$ "type"] ?? "");

		if (ev_type == "note_on") {
			if (et < keep_start || et > keep_end) continue;
			var note_on = floor(real(ev[$ "note"] ?? -1));
			var chan_on = floor(real(ev[$ "channel"] ?? 0));
			var key_on = string(chan_on) + "|" + string(note_on);
			var c_on = variable_struct_exists(active_counts, key_on) ? real(active_counts[$ key_on]) : 0;
			active_counts[$ key_on] = c_on + 1;
			active_note[$ key_on] = note_on;
			active_chan[$ key_on] = chan_on;
			ev[$ "time"] = et - keep_start;
			array_push(out, ev);
			continue;
		}

		if (ev_type == "note_off") {
			if (et < keep_start) continue;
			var note_off = floor(real(ev[$ "note"] ?? -1));
			var chan_off = floor(real(ev[$ "channel"] ?? 0));
			var key_off = string(chan_off) + "|" + string(note_off);
			var c_off = variable_struct_exists(active_counts, key_off) ? real(active_counts[$ key_off]) : 0;
			if (c_off <= 0) continue;
			if (et > keep_end) et = keep_end;
			active_counts[$ key_off] = c_off - 1;
			ev[$ "time"] = et - keep_start;
			array_push(out, ev);
			continue;
		}

		if (et < keep_start) continue;
		if (et > keep_end) continue;
		ev[$ "time"] = et - keep_start;
		array_push(out, ev);
	}

	// Safety: close any notes still active at the trim boundary.
	var close_t = keep_end - keep_start;
	var keys = struct_get_names(active_counts);
	for (var ki = 0; ki < array_length(keys); ki++) {
		var k = keys[ki];
		var c = real(active_counts[$ k] ?? 0);
		if (c <= 0) continue;
		var n = floor(real(active_note[$ k] ?? -1));
		var ch = floor(real(active_chan[$ k] ?? 0));
		for (var ci = 0; ci < c; ci++) {
			array_push(out, {
				time: close_t,
				type: "note_off",
				note: n,
				velocity: 0,
				channel: ch,
				measure: 0,
				beat: 0,
				beat_fraction: 0,
				is_embellishment: false,
				event_id: 0
			});
		}
	}

	array_sort(out, function(a, b) { return real(a[$ "time"] ?? 0) - real(b[$ "time"] ?? 0); });

	// Only remap measure numbering when cuts are actually applied.
	// Keeping original measure fields for uncut tunes avoids corrupting pickup/repeat layouts.
	var out_len = array_length(out);
	var had_cuts = (head_ms > 0) || (tail_ms > 0);
	var remapped_max_measure = 0;
	if (had_cuts) {
		var measure_map = {};
		var next_measure = 1;
		for (var ri = 0; ri < out_len; ri++) {
			var e = out[ri];
			if (!is_struct(e)) continue;

			var old_m = floor(real(e[$ "measure"] ?? 0));
			if (old_m <= 0) {
				// Preserve pickup/unanchored events as measure 0.
				e[$ "measure"] = 0;
				continue;
			}

			var old_key = string(old_m);
			if (!variable_struct_exists(measure_map, old_key)) {
				measure_map[$ old_key] = next_measure;
				next_measure += 1;
			}
			var new_m = floor(real(measure_map[$ old_key]));
			e[$ "measure"] = new_m;
			if (new_m > remapped_max_measure) remapped_max_measure = new_m;
		}
	}

	show_debug_message("  Applied cuts: head=" + string(_head_cut_beats) + " beats, tail=" + string(_tail_cut_beats)
		+ " beats (keep " + string_format(keep_start, 0, 2) + ".." + string_format(keep_end, 0, 2) + "ms)"
		+ (had_cuts
			? ", remapped measures to 1.." + string(remapped_max_measure)
			: ", kept original measure numbering"));
	return out;
}

/// @function tune_voice_to_channel(_voice, _default_channel)
/// @description Map voice labels to MIDI channels (0-based). pipes_melody→2, pipes_harmony1-3→3-5, support1-4→10-13, drums→9.
/// @param {string} _voice            Voice label ("pipes_melody", "pipes_harmony1", "support1", "drums", etc.)
/// @param {real}   _default_channel  Fallback channel if voice is missing or unknown
/// @returns {real}  0-based MIDI channel number

function tune_voice_to_channel(_voice, _default_channel) {
	var v = string_lower(string(_voice ?? ""));
	switch (v) {
		case "pipes_melody":   return 2;
		case "pipes_harmony1": return 3;
		case "pipes_harmony2": return 4;
		case "pipes_harmony3": return 5;
		case "support1": return 10; // MIDI channel 11 (1-based)
		case "support2": return 11; // MIDI channel 12 (1-based)
		case "support3": return 12; // MIDI channel 13 (1-based)
		case "support4": return 13; // MIDI channel 14 (1-based)
		case "drums": return 9;     // MIDI channel 10 (1-based)
		// DEPRECATED — remove after re-exporting all tunes
		case "pipes":    return 2;
		case "harmony1": return 3;
		case "harmony2": return 4;
		case "harmony3": return 5;
		default: return _default_channel;
	}
}

/// @function tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events, _grace_override_ms)
/// @description Iterate raw tune events and convert each to playable MIDI format. Expands embellishments via global.emb_library with stolen-time logic; falls back to literal expansion if embellishment not found. Returns time-sorted event array.
/// @param {struct} _tune              Loaded tune struct (used for is_loaded guard)
/// @param {real}   _tempo             Tempo in BPM
/// @param {real}   _unit_ms           Duration of 1 unit in ms
/// @param {real}   _base_midi         Base MIDI note (fallback for literal expansion)
/// @param {real}   _channel           Default MIDI channel (0-based)
/// @param {array}  _events            Raw (or swing-modified) event array
/// @param {real|undefined} _grace_override_ms  Optional gracenote duration override
/// @returns {array}  Sorted playable MIDI event array
/// @reads   global.emb_library, global.EMBELLISHMENT_CONFIG (via tune_get_gracenote_timing)
/// @writes  none
/// @objects none
/// @callers scr_preprocess_tune
function tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events, _grace_override_ms) {
	var events = _events;  // Use the passed events array instead of trying to read from _tune
	var playable = array_create(0);
	var note_off_queue = array_create(0); // Store pending note-offs
	var target_note_delay_ms = 0;  // Track delay from embellishments stealing from target
	
	show_debug_message("  tune_build_playable_events: Processing " + string(array_length(events)) + " events");
	
	for (var i = 0; i < array_length(events); i++) {
		var ev = events[i];
		var time_ms = tune_units_to_ms(ev.total_units, _tempo, _unit_ms);
		var ev_voice = struct_exists(ev, "voice") ? ev.voice : "";
		var ev_channel = tune_voice_to_channel(ev_voice, _channel);
		
		// Skip structure events (bars, divisions)
		if (ev.type == "structure") {
			var _marker_kind = string(ev.structure ?? "structure");
			var _anchor_uid = string(ev.event_id ?? "") + "|" + string(ev.part ?? 1) + "|" + string(ev.measure ?? 0);
			array_push(playable, {
				time: time_ms,
				type: "marker",
				marker_type: _marker_kind,
				nav_anchor_uid: _anchor_uid,
				nav_anchor_is_bar: (_marker_kind == "bar"),
				part: ev.part ?? 1,
				measure: ev.measure ?? 0,
				beat: ev.beat ?? 0,
				beat_fraction: ev.division ?? 0,
				event_id: ev.event_id ?? 0
			});
			continue;
		}
		
		// Handle note events
		if (ev.type == "note" && ev.letter != "" && ev.letter != undefined) {
			show_debug_message("    Note event: letter=" + string(ev.letter) + ", adjusted=" + string(ev.adjusted));
			var midi_note = tune_note_letter_to_midi(ev.letter, _base_midi);
			var velocity = real(ev.adjusted ?? 1) > 0 ? 80 : 0; // Placeholder; adjust as needed
			
			// Apply any delay from embellishments that stole from this note
			var actual_start_time = time_ms + target_note_delay_ms;
			
			// Note on
			array_push(playable, {
				time: actual_start_time,
				type: "note_on",
				note: midi_note,
				velocity: velocity,
                channel: ev_channel,
                part: ev.part ?? 1,
                measure: ev.measure ?? 0,
                beat: ev.beat ?? 0,
                beat_fraction: ev.division ?? 0,
				is_embellishment: false,
                event_id: ev.event_id ?? 0
			});
			
			// Calculate note off time - shorten duration by stolen time from embellishment
			var duration_ms = (real(ev.adjusted ?? 1)) * _unit_ms - target_note_delay_ms;
			var note_off_time = actual_start_time + duration_ms;
			target_note_delay_ms = 0;  // Reset after using
			
			array_push(note_off_queue, {
				time: note_off_time,
				note: midi_note,
				channel: ev_channel,
				part: ev.part ?? 1,
				measure: ev.measure ?? 0,
				beat: ev.beat ?? 0,
				beat_fraction: ev.division ?? 0,
				is_embellishment: false,
				event_id: ev.event_id ?? 0
			});
		}
		
		// Handle embellishments using library lookup
		if (ev.type == "embellishment" && ev.emb_literal != "" && ev.emb_literal != undefined) {
			show_debug_message("    Embellishment event: literal=" + string(ev.emb_literal) + ", target=" + string(ev.emb_target));
			
			// Strip braces from literal to get pattern
			var pattern = string_replace(ev.emb_literal, "{", "");
			pattern = string_replace(pattern, "}", "");
			
			// Find target note letter (next note event) for library lookup
			var target_note_letter = "";
			var target_duration_ms = _unit_ms;  // Default fallback
			for (var k = i + 1; k < array_length(events); k++) {
				if (events[k].type == "note") {
					target_note_letter = events[k].letter;
					target_duration_ms = (real(events[k].adjusted ?? 1)) * _unit_ms;
					break;
				}
			}
			
			// Look up embellishment in library using pattern + target note, with optional overrides
			var alt_anchor = 0;
			var alt_timing = "";
			if (struct_exists(ev, "emb_alt_anchor")) {
				alt_anchor = real(ev.emb_alt_anchor ?? 0);
			}
			if (struct_exists(ev, "emb_alt_timing")) {
				alt_timing = string(ev.emb_alt_timing ?? "");
			}
			var emb_found = find_embellishment(global.emb_library, pattern, target_note_letter, alt_anchor, alt_timing);
			
			if (emb_found != undefined) {
				var emb_name = is_struct(emb_found) && variable_struct_exists(emb_found, "emb_name")
					? string(variable_struct_get(emb_found, "emb_name"))
					: "";
				show_debug_message("    → Found embellishment: " + emb_name + " (pattern=" + pattern + ", target=" + target_note_letter + ")");
				
				// Find preceding note duration (previous note event)
				var preceding_duration_ms = _unit_ms;  // Default fallback
				for (var k = i - 1; k >= 0; k--) {
					if (events[k].type == "note") {
						preceding_duration_ms = (real(events[k].adjusted ?? 1)) * _unit_ms;
						break;
					}
				}
				
				// Expand embellishment into notes (with BPM scaling & constraints)
				var expanded_notes = embellishment_to_notes(emb_found, target_duration_ms, preceding_duration_ms, _tempo, _grace_override_ms);
				
				// Calculate embellishment start time based on anchor semantics
				var emb_anchor_index = is_struct(emb_found) && variable_struct_exists(emb_found, "anchor_index")
					? real(variable_struct_get(emb_found, "anchor_index"))
					: 0;
				var anchor_index = emb_anchor_index - 1;  // 0-based
				var count_notes = array_length(expanded_notes);
				var current_emb_time = time_ms;
				var time_stolen_from_preceding = 0;
				var time_stolen_from_target = 0;
				
				if (anchor_index >= count_notes) {
					// All notes steal from preceding → shift start time backward and shorten preceding note
					for (var k = 0; k < count_notes; k++) {
						time_stolen_from_preceding += expanded_notes[k].duration_ms;
					}
					current_emb_time = time_ms - time_stolen_from_preceding;
				} else if (anchor_index >= 0) {
					// Split: notes before anchor steal from preceding, notes at/after anchor steal from target
					for (var k = 0; k < anchor_index; k++) {
						time_stolen_from_preceding += expanded_notes[k].duration_ms;
					}
					for (var k = anchor_index; k < count_notes; k++) {
						time_stolen_from_target += expanded_notes[k].duration_ms;
					}
				} else {
					// anchor_index < 0: all notes steal from target
					for (var k = 0; k < count_notes; k++) {
						time_stolen_from_target += expanded_notes[k].duration_ms;
					}
				}
				
				// Shorten preceding note's note_off time if time was stolen from it
				if (time_stolen_from_preceding > 0) {
					// Find the most recent note_off event and reduce its time
					for (var k = array_length(playable) - 1; k >= 0; k--) {
						var note_off_ev = playable[k];
						if (is_struct(note_off_ev) && string(variable_struct_get(note_off_ev, "type") ?? "") == "note_off") {
							variable_struct_set(note_off_ev, "time", real(variable_struct_get(note_off_ev, "time") ?? 0) - time_stolen_from_preceding);
							break;
						}
					}
				}
				
				// Store time stolen from target to delay and shorten the next note
				target_note_delay_ms = time_stolen_from_target;
				
				// Play each note in the embellishment
				for (var j = 0; j < array_length(expanded_notes); j++) {
					var emb_note = expanded_notes[j];
					var midi_from_letter = tune_note_letter_to_midi(emb_note.note, _base_midi);
					var note_duration = emb_note.duration_ms;
					
					// Note on
					array_push(playable, {
						time: current_emb_time,
						type: "note_on",
						note: midi_from_letter,
						velocity: 70,
						channel: ev_channel,
						part: ev.part ?? 1,
						measure: ev.measure ?? 0,
						beat: ev.beat ?? 0,
						beat_fraction: ev.division ?? 0,
						is_embellishment: true,
						event_id: ev.event_id ?? 0
					});
					
					// Note off
					array_push(note_off_queue, {
						time: current_emb_time + note_duration,
						note: midi_from_letter,
						channel: ev_channel,
						part: ev.part ?? 1,
						measure: ev.measure ?? 0,
						beat: ev.beat ?? 0,
						beat_fraction: ev.division ?? 0,
						is_embellishment: true,
						event_id: ev.event_id ?? 0
					});
					
					current_emb_time += note_duration;
				}
			} else {
				// Fallback: embellishment not found in library, use old literal expansion
				show_debug_message("    → Embellishment not found in library, using fallback expansion");
				var emb_notes = tune_expand_embellishment(ev.emb_literal, _base_midi);
				
				// Use tempo-based duration for single-note
				if (array_length(emb_notes) == 1) {
					var gracenote_ms = tune_get_gracenote_timing(_tempo, _grace_override_ms);
					array_push(playable, {
						time: time_ms,
						type: "note_on",
						note: emb_notes[0],
						velocity: 70,
						channel: ev_channel,
						part: ev.part ?? 1,
						measure: ev.measure ?? 0,
						beat: ev.beat ?? 0,
						beat_fraction: ev.division ?? 0,
						is_embellishment: true,
						event_id: ev.event_id ?? 0
					});
					array_push(note_off_queue, {
						time: time_ms + gracenote_ms,
						note: emb_notes[0],
						channel: ev_channel,
						part: ev.part ?? 1,
						measure: ev.measure ?? 0,
						beat: ev.beat ?? 0,
						beat_fraction: ev.division ?? 0,
						is_embellishment: true,
						event_id: ev.event_id ?? 0
					});
				} else {
					// Multi-note: distribute evenly
					var emb_duration = _unit_ms * 0.25;
					var time_per_note = emb_duration / array_length(emb_notes);
					for (var j = 0; j < array_length(emb_notes); j++) {
						var emb_time = time_ms + (j * time_per_note);
						array_push(playable, {
							time: emb_time,
							type: "note_on",
							note: emb_notes[j],
							velocity: 70,
							channel: ev_channel,
							part: ev.part ?? 1,
							measure: ev.measure ?? 0,
							beat: ev.beat ?? 0,
							beat_fraction: ev.division ?? 0,
							is_embellishment: true,
							event_id: ev.event_id ?? 0
						});
						array_push(note_off_queue, {
							time: emb_time + (time_per_note * 0.8),
							note: emb_notes[j],
							channel: ev_channel,
							part: ev.part ?? 1,
							measure: ev.measure ?? 0,
							beat: ev.beat ?? 0,
							beat_fraction: ev.division ?? 0,
							is_embellishment: true,
							event_id: ev.event_id ?? 0
						});
					}
				}
			}
		}
	}
	
	// Add all note-offs
	for (var i = 0; i < array_length(note_off_queue); i++) {
		var note_off = note_off_queue[i];
		var note_off_time = is_struct(note_off) ? real(variable_struct_get(note_off, "time")) : 0;
		var note_off_note = is_struct(note_off) ? variable_struct_get(note_off, "note") : 0;
		var note_off_channel = is_struct(note_off) ? variable_struct_get(note_off, "channel") : 0;
		var note_off_part = is_struct(note_off) ? variable_struct_get(note_off, "part") : 1;
		var note_off_measure = is_struct(note_off) ? variable_struct_get(note_off, "measure") : 0;
		var note_off_beat = is_struct(note_off) ? variable_struct_get(note_off, "beat") : 0;
		var note_off_beat_fraction = is_struct(note_off) ? variable_struct_get(note_off, "beat_fraction") : 0;
		var note_off_is_embellishment = is_struct(note_off) ? variable_struct_get(note_off, "is_embellishment") : false;
		var note_off_event_id = is_struct(note_off) ? variable_struct_get(note_off, "event_id") : 0;
		array_push(playable, {
			time: note_off_time,
			type: "note_off",
			note: note_off_note,
			velocity: 0,
			channel: note_off_channel,
			part: note_off_part ?? 1,
			measure: note_off_measure ?? 0,
			beat: note_off_beat ?? 0,
			beat_fraction: note_off_beat_fraction ?? 0,
			is_embellishment: note_off_is_embellishment ?? false,
			event_id: note_off_event_id ?? 0
		});
	}
	
	// Sort by time
	array_sort(playable, function(a, b) { return a.time - b.time; });
	
	return playable;
}

/// @function tune_units_to_ms(_units, _tempo_bpm, _unit_ms)
/// @description Convert tune units to milliseconds based on tempo and unit duration.
/// @param _units       Total units (cumulative count from JSON)
/// @param _tempo_bpm   Tempo in BPM
/// @param _unit_ms     Duration of 1 unit in milliseconds (from tune metadata)
/// @returns Milliseconds

function tune_units_to_ms(_units, _tempo_bpm, _unit_ms) {
	// Simple linear conversion; tempo adjustment can be added later if needed
	return _units * _unit_ms;
}

/// @function tune_get_effective_quarter_bpm(_tempo_bpm, _meter)
/// @description Convert metadata BPM to quarter-note BPM used by runtime timing.
/// In cut time (2/2 or C|), BPM is interpreted as half-note BPM.

function tune_get_effective_quarter_bpm(_tempo_bpm, _meter) {
	return timing_get_effective_quarter_bpm(_tempo_bpm, _meter);
}

/// @function tune_note_fraction_to_quarter_multiplier(_note_fraction)
/// @description Convert a note fraction string (e.g., "1/8", "1/4", "3/16")
/// to a multiplier of quarter-note duration.
/// @param _note_fraction String note length fraction
/// @returns Quarter-note multiplier (fallback 0.5 = 1/8)

function tune_note_fraction_to_quarter_multiplier(_note_fraction) {
	var fraction = string_trim(string(_note_fraction ?? ""));
	if (fraction == "") return 0.5;

	var parts = string_split(fraction, "/");
	if (array_length(parts) != 2) return 0.5;

	var numer = real(parts[0]);
	var denom = real(parts[1]);
	if (denom <= 0 || numer <= 0) return 0.5;

	// Relative to quarter note (1/4): (numer/denom) / (1/4) = 4*numer/denom
	return (4 * numer) / denom;
}

/// @function tune_get_gracenote_timing(_tempo_bpm, _override_ms)
/// @description Calculate gracenote duration based on tempo, with optional override. Uses fallback thresholds and linear interpolation from EMBELLISHMENT_CONFIG.
/// @param {real} _tempo_bpm             Tempo in beats per minute
/// @param {real|undefined} _override_ms  Explicit duration override; if >0, returned directly
/// @returns {real}  Gracenote duration in milliseconds
/// @reads   global.EMBELLISHMENT_CONFIG
/// @callers tune_build_playable_events (fallback expansion path)

function tune_get_gracenote_timing(_tempo_bpm, _override_ms) {
	var config = global.EMBELLISHMENT_CONFIG;
	var gracenote_ms;
	if (!is_undefined(_override_ms) && real(_override_ms) > 0) {
		return real(_override_ms);
	}
	
	if (_tempo_bpm <= config.fallback_slow_bpm_threshold) {
		// At or below slow threshold: use maximum gracenote duration
		gracenote_ms = config.fallback_max_ms;
	} else if (_tempo_bpm >= config.fallback_fast_bpm_threshold) {
		// At or above fast threshold: use minimum gracenote duration
		gracenote_ms = config.fallback_min_ms;
	} else {
		// Linear interpolation between thresholds
		var ratio = (_tempo_bpm - config.fallback_slow_bpm_threshold) / (config.fallback_fast_bpm_threshold - config.fallback_slow_bpm_threshold);
		gracenote_ms = config.fallback_max_ms - (config.fallback_max_ms - config.fallback_min_ms) * ratio;
	}
	
	return gracenote_ms;
}

/// @function tune_parse_swing_multiplier(_swing_value)
/// @description Parse swing multiplier from metadata or override (0 or empty = default)

function tune_parse_swing_multiplier(_swing_value) {
	var s = string(_swing_value ?? "");
	if (string_length(s) == 0) return 0;
	return real(s);
}

/// @function tune_get_gracenote_unit_ms(_tempo_bpm, _override_ms)
/// @description Get BPM-scaled gracenote unit duration using linear interpolation around reference_bpm; clamped to EMBELLISHMENT_CONFIG min/max.
/// @param {real} _tempo_bpm             Current tempo in BPM
/// @param {real|undefined} _override_ms  Optional explicit override duration in ms; returned directly if >0
/// @returns {real}  Gracenote unit duration in ms
/// @reads   global.EMBELLISHMENT_CONFIG
/// @callers tune_apply_swing_to_events

function tune_get_gracenote_unit_ms(_tempo_bpm, _override_ms) {
	var cfg = global.EMBELLISHMENT_CONFIG;
	if (!is_undefined(_override_ms) && real(_override_ms) > 0) {
		return real(_override_ms);
	}
	var bpm_delta = _tempo_bpm - cfg.reference_bpm;
	var unit_ms = cfg.gracenote_unit_ms_base + (bpm_delta * cfg.bpm_scaling_factor);
	return clamp(unit_ms, cfg.min_gracenote_ms, cfg.max_gracenote_ms);
}

/// @function tune_get_broken_dir(_ev, _next_ev)
/// @description Determine broken rhythm direction from explicit markers.

function tune_get_broken_dir(_ev, _next_ev) {
	var broken = "";
	if (struct_exists(_ev, "broken_dir")) broken = string(_ev.broken_dir);
	if (broken == "" && struct_exists(_ev, "emb_reserved")) broken = string(_ev.emb_reserved);

	broken = string_lower(string_trim(broken));
	if (broken == "" || broken == "none") return "";
	if (broken == "dotcut" || broken == "cutdot") return broken;

	return "";
}

/// @function tune_apply_swing_to_events(_events, _tempo_bpm, _unit_ms, _swing_mult, _grace_override_ms)
/// @description Apply swing rules to broken rhythm pairs without flattening multi-voice timing.

function tune_apply_swing_to_events(_events, _tempo_bpm, _unit_ms, _swing_mult, _grace_override_ms) {
	var count = array_length(_events);
	var out = array_create(count);
	var grace_ms = tune_get_gracenote_unit_ms(_tempo_bpm, _grace_override_ms);
	var grace_units = grace_ms / _unit_ms;
	var i = 0;
	while (i < count) {
		var ev = _events[i];
		if (ev.type == "note") {
			var next_ev = (i + 1 < count) ? _events[i + 1] : undefined;
			var ev_voice = struct_exists(ev, "voice") ? string_lower(string(ev.voice)) : "pipes_melody";
			var next_is_note = false;
			var next_voice = "pipes_melody";
			var next_written = 0;
			var next_adjusted = 0;
			if (next_ev != undefined && is_struct(next_ev)) {
				next_is_note = (string(variable_struct_get(next_ev, "type")) == "note");
				if (variable_struct_exists(next_ev, "voice")) {
					next_voice = string_lower(string(variable_struct_get(next_ev, "voice")));
				}
				if (variable_struct_exists(next_ev, "written")) {
					next_written = real(variable_struct_get(next_ev, "written"));
				}
				if (variable_struct_exists(next_ev, "adjusted")) {
					next_adjusted = real(variable_struct_get(next_ev, "adjusted"));
				}
			}
			var broken_dir = tune_get_broken_dir(ev, next_ev);
			if (broken_dir != "" && next_is_note && ev_voice == next_voice) {
				var w1 = real(ev.written ?? ev.adjusted ?? 0);
				var w2 = next_written;
				if (w2 <= 0) w2 = next_adjusted;
				var pair_units = w1 + w2;
				if (pair_units > 0) {
					var default_cut_units = (broken_dir == "dotcut") ? (w2 * 0.5) : (w1 * 0.5);
					var cut_units = _swing_mult * grace_units;
					if (cut_units < 0) cut_units = 0;
					if (cut_units > pair_units - 0.0001) cut_units = pair_units - 0.0001;
					var dot_units = pair_units - cut_units;
					if (broken_dir == "dotcut") {
						ev.adjusted = dot_units;
						variable_struct_set(next_ev, "adjusted", cut_units);
					} else {
						ev.adjusted = cut_units;
						variable_struct_set(next_ev, "adjusted", dot_units);
					}
					var pair_start_units = real(ev.total_units ?? 0);
					ev.total_units = pair_start_units;
					variable_struct_set(next_ev, "total_units", pair_start_units + real(ev.adjusted));
					out[i] = ev;
					out[i + 1] = next_ev;
					i += 2;
					continue;
				}
			}
		}
		out[i] = ev;
		i += 1;
	}
	return out;
}

/// @function chanter_resolve_name(_chanter)
/// @description Resolve chanter name from optional parameter; falls back to global.MIDI_chanter; returns "default" if neither is set.
/// @param {string} [_chanter]  Explicit chanter name override, or undefined to read global
/// @returns {string}  Lowercase resolved chanter name ("default" | "blair" | ...)
/// @reads   global.MIDI_chanter
/// @callers chanter_get_profile
function chanter_resolve_name(_chanter = undefined) {
	var name = "";
	if (!is_undefined(_chanter)) {
		name = string(_chanter);
	}
	if (name == "" && variable_global_exists("MIDI_chanter")) {
		name = string(global.MIDI_chanter);
	}
	if (name == "") {
		name = "default";
	}
	return string_lower(name);
}

/// @function chanter_build_profile(_chanter_name)
/// @description Build a chanter MIDI mapping profile struct for the named chanter. Returns bidirectional maps between canonical note names and MIDI numbers.
/// @param {string} _chanter_name  Chanter name ("default" or "blair")
/// @returns {struct}  {name, canonical_to_midi, input_aliases, input_midi_to_canonical}
/// @callers chanter_get_profile
function chanter_build_profile(_chanter_name) {
	var canonical_to_midi = {};
	var input_aliases = {};

	if (_chanter_name == "blair") {
		// Blair Digital Chanter profile (canonical note -> playback/output MIDI)
		canonical_to_midi[$ "G"] = 56;
		canonical_to_midi[$ "A"] = 58;
		canonical_to_midi[$ "B"] = 60;
		canonical_to_midi[$ "=c"] = 61;
		canonical_to_midi[$ "c"] = 62;
		canonical_to_midi[$ "d"] = 63;
		canonical_to_midi[$ "e"] = 65;
		canonical_to_midi[$ "=f"] = 66;
		canonical_to_midi[$ "f"] = 67;
		canonical_to_midi[$ "g"] = 68;
		canonical_to_midi[$ "a"] = 70;

		// Input aliases seen from some Blair MIDI streams (player input normalization).
		input_aliases[$ "56"] = "G";
		input_aliases[$ "58"] = "A";
		input_aliases[$ "60"] = "B";
		input_aliases[$ "62"] = "c";
		input_aliases[$ "63"] = "d";
		input_aliases[$ "65"] = "e";
		input_aliases[$ "66"] = "=f";
		input_aliases[$ "67"] = "f";
		input_aliases[$ "68"] = "g";
		input_aliases[$ "79"] = "a";
	} else {
		// Default bagpipe profile (canonical note -> playback/output MIDI)
		canonical_to_midi[$ "G"] = 55;
		canonical_to_midi[$ "A"] = 57;
		canonical_to_midi[$ "B"] = 59;
		canonical_to_midi[$ "=c"] = 60;
		canonical_to_midi[$ "c"] = 61;
		canonical_to_midi[$ "d"] = 62;
		canonical_to_midi[$ "e"] = 64;
		canonical_to_midi[$ "=f"] = 65;
		canonical_to_midi[$ "f"] = 66;
		canonical_to_midi[$ "g"] = 67;
		canonical_to_midi[$ "a"] = 69;
	}

	var input_midi_to_canonical = {};
	var names = variable_struct_get_names(canonical_to_midi);
	for (var i = 0; i < array_length(names); i++) {
		var canonical = names[i];
		var midi = floor(real(canonical_to_midi[$ canonical]));
		input_midi_to_canonical[$ string(midi)] = canonical;
	}

	var alias_keys = variable_struct_get_names(input_aliases);
	for (var j = 0; j < array_length(alias_keys); j++) {
		var midi_key = alias_keys[j];
		input_midi_to_canonical[$ midi_key] = string(input_aliases[$ midi_key]);
	}

	return {
		name: _chanter_name,
		canonical_to_midi: canonical_to_midi,
		input_aliases: input_aliases,
		input_midi_to_canonical: input_midi_to_canonical
	};
}

/// @function chanter_get_profile(_chanter)
/// @description Return (or build and cache) a chanter profile struct. Profiles are keyed by resolved name in global.CHANTER_PROFILE_CACHE.
/// @param {string} [_chanter]  Chanter name, or undefined to resolve from global.MIDI_chanter
/// @returns {struct}  Chanter profile with canonical_to_midi and input_midi_to_canonical maps
/// @reads   global.CHANTER_PROFILE_CACHE
/// @writes  global.CHANTER_PROFILE_CACHE (on first access for a given name)
/// @callers chanter_midi_to_canonical, chanter_canonical_to_midi, chanter_midi_to_display, tune_get_note_map, tune_get_midi_to_letter_alias_map, tune_note_letter_to_midi
function chanter_get_profile(_chanter = undefined) {
	var name = chanter_resolve_name(_chanter);

	if (!variable_global_exists("CHANTER_PROFILE_CACHE") || !is_struct(global.CHANTER_PROFILE_CACHE)) {
		global.CHANTER_PROFILE_CACHE = {};
	}

	var profile = global.CHANTER_PROFILE_CACHE[$ name];
	if (is_undefined(profile) || !is_struct(profile)) {
		profile = chanter_build_profile(name);
		global.CHANTER_PROFILE_CACHE[$ name] = profile;
	}

	return profile;
}

/// @function chanter_canonical_to_display(_canonical_note)
/// @description Convert a canonical note string to human-readable display form. Normalizes internal aliases (_cnat→=c, _fnat→=f). Returns "?" for empty input.
/// @param {string} _canonical_note  Canonical note name (may include internal aliases)
/// @returns {string}  Display-form note name, or "?"
/// @callers chanter_midi_to_display, tune_get_midi_to_letter_alias_map
function chanter_canonical_to_display(_canonical_note) {
	var note = string(_canonical_note ?? "");
	if (note == "_cnat") note = "=c";
	if (note == "_fnat") note = "=f";
	if (note == "") return "?";
	return note;
}

/// @function chanter_midi_to_canonical(_midi_note, _chanter, _channel)
/// @description Convert a MIDI note number to canonical chanter note name via profile reverse lookup. Returns "" for percussion channel 9, unknown MIDI, or out-of-range values.
/// @param {real}   _midi_note  MIDI note number (0–127)
/// @param {string} [_chanter]  Chanter name, or undefined for global.MIDI_chanter
/// @param {real}   [_channel]  MIDI channel (0-based); channel 9 = percussion, returns ""
/// @returns {string}  Canonical note name, or "" if not mappable
/// @callers chanter_midi_to_display, scr_MIDI (player input), scr_scoring
function chanter_midi_to_canonical(_midi_note, _chanter = undefined, _channel = -1) {
	// Channel 10 percussion (0-based channel 9) is not part of chanter canonicalization.
	if (real(_channel) == 9) return "";

	var midi = floor(real(_midi_note));
	if (midi < 0 || midi > 127) return "";

	var profile = chanter_get_profile(_chanter);
	var input_map = is_struct(profile) && variable_struct_exists(profile, "input_midi_to_canonical")
		? variable_struct_get(profile, "input_midi_to_canonical")
		: undefined;
	var canonical = is_struct(input_map) ? string(input_map[$ string(midi)]) : "";
	if (is_undefined(canonical)) return "";

	return string(canonical);
}

/// @function chanter_canonical_to_midi(_canonical_note, _chanter)
/// @description Convert a canonical note name to its MIDI note number using the chanter profile. Returns undefined if not found.
/// @param {string} _canonical_note  Canonical note name (e.g. "A", "c", "=c")
/// @param {string} [_chanter]       Chanter name, or undefined for global.MIDI_chanter
/// @returns {real|undefined}  MIDI note number, or undefined if unmapped
/// @callers tune_note_letter_to_midi
function chanter_canonical_to_midi(_canonical_note, _chanter = undefined) {
	var canonical = string(_canonical_note ?? "");
	if (canonical == "_cnat") canonical = "=c";
	if (canonical == "_fnat") canonical = "=f";

	var profile = chanter_get_profile(_chanter);
	var midi_map = is_struct(profile) && variable_struct_exists(profile, "canonical_to_midi")
		? variable_struct_get(profile, "canonical_to_midi")
		: undefined;
	var midi = is_struct(midi_map) ? midi_map[$ canonical] : undefined;
	if (is_undefined(midi)) return undefined;

	return floor(real(midi));
}

/// @function chanter_midi_to_display(_midi_note, _channel, _chanter)
/// @description Convert a MIDI note + channel to a human-readable label. Channel 9 returns drum type names; otherwise delegates to canonical→display lookup.
/// @param {real}   _midi_note  MIDI note number (0–127)
/// @param {real}   [_channel]  MIDI channel (0-based); -1 = chanter path; 9 = percussion path
/// @param {string} [_chanter]  Chanter name, or undefined for global.MIDI_chanter
/// @returns {string}  Display label (e.g. "A", "=c", "kick", "?")
/// @callers scr_game_viz, scr_scoring
function chanter_midi_to_display(_midi_note, _channel = -1, _chanter = undefined) {
	// Percussion/drums on channel 9 (MIDI channel 10)
	if (real(_channel) == 9) {
		switch (_midi_note) {
			case 35: return "kick";
			case 36: return "kick";
			case 38: return "snare";
			case 40: return "snare";
			case 42: return "hi-hat";
			case 44: return "hi-hat";
			case 46: return "hi-hat";
			case 49: return "crash";
			case 51: return "ride";
			default: return "drum" + string(_midi_note);
		}
	}

	var canonical = chanter_midi_to_canonical(_midi_note, _chanter, _channel);
	if (string_length(canonical) <= 0) return "?";

	return chanter_canonical_to_display(canonical);
}

/// @function tune_get_note_map(_chanter, _base_midi)
/// @description Build a legacy-compatible note→MIDI map from a chanter profile. Keys use legacy aliases (_cnat for =c, _fnat for =f).
/// @param {string} _chanter         Chanter name (or undefined for global.MIDI_chanter)
/// @param {real}   [_base_midi]     Unused legacy parameter (kept for signature compat)
/// @returns {struct}  Map of legacy note letter → MIDI number
/// @callers scr_scoring, scr_game_viz
function tune_get_note_map(_chanter, _base_midi = undefined) {
	var profile = chanter_get_profile(_chanter);
	var out = {};
	var midi_map = is_struct(profile) && variable_struct_exists(profile, "canonical_to_midi")
		? variable_struct_get(profile, "canonical_to_midi")
		: undefined;
	var names = is_struct(midi_map) ? variable_struct_get_names(midi_map) : [];

	for (var i = 0; i < array_length(names); i++) {
		var canonical = names[i];
		var midi = is_struct(midi_map) ? midi_map[$ canonical] : undefined;
		var legacy_key = canonical;
		if (canonical == "=c") legacy_key = "_cnat";
		if (canonical == "=f") legacy_key = "_fnat";
		out[$ legacy_key] = midi;
	}

	return out;
}

/// @function tune_build_midi_to_letter_map(_note_map)
/// @description Invert a note→MIDI map (from tune_get_note_map) to MIDI-number-string → display letter. Normalizes _cnat→=c and _fnat→=f.
/// @param {struct} _note_map  Map of note letter → MIDI number
/// @returns {struct}  Map of MIDI-number-string → display letter
/// @callers scr_game_viz (note label rendering), scr_MIDI
function tune_build_midi_to_letter_map(_note_map) {
	var out = {};
	var names = variable_struct_get_names(_note_map);
	for (var i = 0; i < array_length(names); i++) {
		var key = names[i];
		var midi = _note_map[$ key];
		var letter = key;
		if (key == "_cnat") {
			letter = "=c";
		} else if (key == "_fnat") {
			letter = "=f";
		}
		out[$ string(midi)] = letter;
	}
	return out;
}

/// @function tune_get_midi_to_letter_alias_map(_chanter)
/// @description Return the input_aliases map from a chanter profile as MIDI-key → display-letter. Used for normalizing non-standard MIDI input streams.
/// @param {string} _chanter  Chanter name (or undefined for global.MIDI_chanter)
/// @returns {struct}  Map of MIDI-number-string → display letter (input alias variants)
/// @callers scr_MIDI (input normalization)
function tune_get_midi_to_letter_alias_map(_chanter) {
	var profile = chanter_get_profile(_chanter);
	var aliases = {};
	var input_aliases = is_struct(profile) && variable_struct_exists(profile, "input_aliases")
		? variable_struct_get(profile, "input_aliases")
		: undefined;
	var names = is_struct(input_aliases) ? variable_struct_get_names(input_aliases) : [];

	for (var i = 0; i < array_length(names); i++) {
		var midi_key = names[i];
		var canonical = string(is_struct(input_aliases) ? input_aliases[$ midi_key] : "");
		aliases[$ midi_key] = chanter_canonical_to_display(canonical);
	}

	return aliases;
}

/// @function tune_note_letter_to_midi(_letter, _base_midi)
/// @description Resolve a note letter (canonical or legacy alias like "_cnat") to MIDI number via chanter profile. Falls back to 55 (G) if unmapped.
/// @param {string} _letter    Note letter from JSON (canonical or legacy alias)
/// @param {real}   _base_midi Unused legacy parameter (kept for signature compat)
/// @returns {real}  MIDI note number (55 if unmapped)
/// @reads   global.MIDI_chanter (via chanter_resolve_name → chanter_get_profile)
/// @callers tune_build_playable_events, tune_expand_embellishment
function tune_note_letter_to_midi(_letter, _base_midi) {
	var canonical = string(_letter ?? "");
	if (canonical == "_cnat") canonical = "=c";
	if (canonical == "_fnat") canonical = "=f";

	var midi = chanter_canonical_to_midi(canonical, global.MIDI_chanter ?? "default");
	if (is_undefined(midi)) {
		show_debug_message("WARNING: Unknown note letter '" + string(_letter) + "', defaulting to 55");
		midi = 55;
	}

	return midi;
}

/// @function tune_expand_embellishment(_emb_name, _base_midi)
/// @description Expand embellishment notation (e.g., "{gde}") into a sequence of MIDI notes.
/// @param _emb_name   Embellishment name from JSON (e.g., "{g}", "{gde}")
/// @param _base_midi  MIDI base for note resolution
/// @returns Array of MIDI note numbers

function tune_expand_embellishment(_emb_name, _base_midi) {
	var notes = array_create(0);
	
	// Remove curly braces
	var clean = string_replace(_emb_name, "{", "");
	clean = string_replace(clean, "}", "");
	
	// Split into individual note letters
	for (var i = 1; i <= string_length(clean); i++) {
		var letter = string_char_at(clean, i);
		var midi = tune_note_letter_to_midi(letter, _base_midi);
		array_push(notes, midi);
	}
	
	return notes;
}

/// @function tune_get_event_info(_tune)
/// @description Debug: Print summary of tune events and structure.

function tune_get_event_info(_tune) {
	var events = is_struct(_tune) && variable_struct_exists(_tune, "events") ? variable_struct_get(_tune, "events") : [];
	var note_count = 0, emb_count = 0, struct_count = 0;
	
	for (var i = 0; i < array_length(events); i++) {
		var ev = events[i];
		if (ev.type == "note") note_count++;
		else if (ev.type == "embellishment") emb_count++;
		else if (ev.type == "structure") struct_count++;
	}
	
	show_debug_message("Tune event summary:");
	show_debug_message("  Notes: " + string(note_count));
	show_debug_message("  Embellishments: " + string(emb_count));
	show_debug_message("  Structure markers: " + string(struct_count));
}

/// @function tune_export_playable_events_csv(_playable_array, _tune_filename)
/// @description Export playable MIDI events to CSV file for debugging
/// @param {array} _playable_array - Array of MIDI event structs
/// @param {string} _tune_filename - Tune filename (used for naming output file)

function tune_export_playable_events_csv(_playable_array, _tune_filename) {
	var filename = string(_tune_filename);  // Ensure it's a string
	
	// Remove .json extension if present using simpler method
	if (string_pos(".json", filename) > 0) {
		filename = string_replace(filename, ".json", "");
	}
	filename = "playable_events_" + filename + ".csv";
	
	// Save under the primary runtime data root.
	var data_root = script_exists(asset_get_index("scr_data_paths_get_primary_root"))
		? scr_data_paths_get_primary_root()
		: "datafiles/";
	var filepath = data_root + filename;
	
	// Open file for writing
	var file = file_text_open_write(filepath);
	
	if (file == -1) {
		show_debug_message("✗ ERROR: Could not open file for writing: " + filepath);
		show_debug_message("  Working directory: " + working_directory);
		return;
	}
	
	// Write header
	file_text_write_string(file, "time_ms,type,note,velocity,channel" + chr(10));
	
	// Write each event
	for (var i = 0; i < array_length(_playable_array); i++) {
		var ev = _playable_array[i];
		var ev_note = struct_exists(ev, "note") ? ev.note : "";
		var ev_velocity = struct_exists(ev, "velocity") ? ev.velocity : "";
		var ev_channel = struct_exists(ev, "channel") ? ev.channel : "";
		var row = string(ev.time) + "," + 
		          string(ev.type) + "," + 
		          string(ev_note) + "," + 
		          string(ev_velocity) + "," + 
		          string(ev_channel);
		file_text_write_string(file, row + chr(10));
	}
	
	file_text_close(file);
	show_debug_message("✓ Exported playable events to: " + filepath + " (" + string(array_length(_playable_array)) + " events)");
}
