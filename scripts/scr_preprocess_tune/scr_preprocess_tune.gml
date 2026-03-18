// scr_tune_preprocess — Tune preprocessing & play array builder
// Purpose: Convert raw tune JSON (with unit-based timings and embellishments) into a playable MIDI event array.
// Key functions: 
//   - scr_preprocess_tune(_tune) — Main entry point; returns playable event array
//   - tune_units_to_ms(_units, _tempo_bpm, _unit_ms) — Unit → millisecond conversion
//   - tune_note_letter_to_midi(_letter, _base_midi) — Resolve note letter to MIDI value
//   - tune_expand_embellishment(_emb_name, _base_midi) — Expand embellishment notation into note sequence
//   - tune_build_playable_events(_tune) — Filter and convert raw events to MIDI format

function scr_preprocess_tune(_tune, _overrides) {
	if (!_tune.tune_data.is_loaded) {
		show_debug_message("ERROR: scr_preprocess_tune called on unloaded tune");
		return array_create(0);
	}

	var override_bpm = undefined;
	var override_swing = undefined;
	var override_grace_ms = undefined;
	if (is_struct(_overrides)) {
		if (struct_exists(_overrides, "bpm") && !is_undefined(_overrides.bpm)) {
			override_bpm = _overrides.bpm;
		}
		if (struct_exists(_overrides, "swing_mult") && !is_undefined(_overrides.swing_mult)) {
			override_swing = _overrides.swing_mult;
		} else if (struct_exists(_overrides, "swing") && !is_undefined(_overrides.swing)) {
			override_swing = _overrides.swing;
		}
		if (struct_exists(_overrides, "gracenote_override_ms") && !is_undefined(_overrides.gracenote_override_ms)) {
			override_grace_ms = _overrides.gracenote_override_ms;
		} else if (struct_exists(_overrides, "gracenote_ms") && !is_undefined(_overrides.gracenote_ms)) {
			override_grace_ms = _overrides.gracenote_ms;
		}
	} else if (!is_undefined(_overrides)) {
		override_bpm = _overrides;
	}

	show_debug_message("=== Preprocessing tune: " + string(_tune.tune_data.filename) + " ===");
	
	// Extract metadata and events from the struct
	var meta = _tune.tune_data.tune_metadata;
	var perf = _tune.tune_data.performance;
	var events = _tune.tune_data.events;
	
	// Debug: Check what's in the tune object
	show_debug_message("  _tune.tune_data contents:");
	show_debug_message("    tune_metadata type: " + string(typeof(meta)));
	show_debug_message("    events length: " + string(array_length(events)));
	show_debug_message("    performance type: " + string(typeof(perf)));
	show_debug_message("    is_loaded: " + string(_tune.tune_data.is_loaded));
	show_debug_message("    filename: " + string(_tune.tune_data.filename));
	
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
	
	var base_str = string(perf.instrument_midi_note_base ?? "");
	var base_midi = (string_length(base_str) > 0) ? real(base_str) : 55;
	
	// Tune output channels (0-based): default tune pipes = 2; channel 1 reserved.
	var channel = 2;
	
	show_debug_message("  Tempo: " + string(tempo_bpm) + " BPM (effective quarter BPM " + string(effective_quarter_bpm) + ") -> " + string(ms_per_quarter) + "ms per beat");
	show_debug_message("  Calculated unit_ms: " + string(unit_ms) + " (for " + unit_note + " notes, multiplier=" + string(unit_multiplier) + ")");
	show_debug_message("  Base MIDI: " + string(base_midi));
	
	// Apply swing overrides before building playable events
	var perf_swing = perf.swing ?? "";
	var swing_value = !is_undefined(override_swing) ? override_swing : (meta.swing ?? perf_swing ?? "");
	var swing_mult = tune_parse_swing_multiplier(swing_value);
	var grace_override_ms = !is_undefined(override_grace_ms) ? override_grace_ms : (meta.gracenote_override_ms ?? meta.gracenote_ms ?? undefined);
	if (swing_mult > 0) {
		events = tune_apply_swing_to_events(events, tempo_bpm, unit_ms, swing_mult, grace_override_ms);
	}

	// Build playable events
	var playable = tune_build_playable_events(_tune, tempo_bpm, unit_ms, base_midi, channel, events, grace_override_ms);
	
	show_debug_message("  → Generated " + string(array_length(playable)) + " playable events");
	
	// Debug: Export playable events to CSV for inspection
	tune_export_playable_events_csv(playable, _tune.tune_data.filename);
	
	return playable;
}

/// @function tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events)
/// @description Iterate through tune events and convert to MIDI format.

/// @function tune_voice_to_channel(_voice, _default_channel)
/// @description Map voice labels to MIDI channels (0-based).
/// @param _voice Voice label ("pipes", "harmony1", "support1", "drums", etc.)
/// @param _default_channel Fallback channel if voice is missing/unknown

function tune_voice_to_channel(_voice, _default_channel) {
	var v = string_lower(string(_voice ?? ""));
	switch (v) {
		case "pipes": return 2;
		case "harmony1": return 3;
		case "harmony2": return 4;
		case "harmony3": return 5;
		case "support1": return 10; // MIDI channel 11 (1-based)
		case "support2": return 11; // MIDI channel 12 (1-based)
		case "support3": return 12; // MIDI channel 13 (1-based)
		case "support4": return 13; // MIDI channel 14 (1-based)
		case "drums": return 9;     // MIDI channel 10 (1-based)
		default: return _default_channel;
	}
}

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
			array_push(playable, {
				time: time_ms,
				type: "marker",
				marker_type: ev.structure ?? "structure",
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
				show_debug_message("    → Found embellishment: " + string(emb_found.emb_name) + " (pattern=" + pattern + ", target=" + target_note_letter + ")");
				
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
				var anchor_index = emb_found.anchor_index - 1;  // 0-based
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
						if (playable[k].type == "note_off") {
							playable[k].time -= time_stolen_from_preceding;
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
		array_push(playable, {
			time: note_off.time,
			type: "note_off",
			note: note_off.note,
			velocity: 0,
			channel: note_off.channel,
			measure: note_off.measure ?? 0,
			beat: note_off.beat ?? 0,
			beat_fraction: note_off.beat_fraction ?? 0,
			is_embellishment: note_off.is_embellishment ?? false,
			event_id: note_off.event_id ?? 0
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
/// @description Calculate gracenote duration based on tempo, with optional override.
/// Uses fallback gracenote timing from EMBELLISHMENT_CONFIG.
/// @param _tempo_bpm  Tempo in beats per minute
/// @returns Duration in milliseconds

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
/// @description Get BPM-scaled gracenote unit, with optional override.

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
			var ev_voice = struct_exists(ev, "voice") ? string_lower(string(ev.voice)) : "pipes";
			var next_is_note = false;
			var next_voice = "pipes";
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
					if (cut_units < default_cut_units) cut_units = default_cut_units;
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

/// @function tune_note_letter_to_midi(_letter, _base_midi)
/// @description Resolve a note letter (A, B, c, d, e, f, g) to MIDI value.
/// @param _letter     Note letter from JSON
/// @param _base_midi  Not used (replaced by exact MIDI lookup)
/// @returns MIDI note number

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

function chanter_canonical_to_display(_canonical_note) {
	var note = string(_canonical_note ?? "");
	if (note == "_cnat") note = "=c";
	if (note == "_fnat") note = "=f";
	if (note == "") return "?";
	return note;
}

function chanter_midi_to_canonical(_midi_note, _chanter = undefined, _channel = -1) {
	// Channel 10 percussion (0-based channel 9) is not part of chanter canonicalization.
	if (real(_channel) == 9) return "";

	var midi = floor(real(_midi_note));
	if (midi < 0 || midi > 127) return "";

	var profile = chanter_get_profile(_chanter);
	var canonical = profile.input_midi_to_canonical[$ string(midi)];
	if (is_undefined(canonical)) return "";

	return string(canonical);
}

function chanter_canonical_to_midi(_canonical_note, _chanter = undefined) {
	var canonical = string(_canonical_note ?? "");
	if (canonical == "_cnat") canonical = "=c";
	if (canonical == "_fnat") canonical = "=f";

	var profile = chanter_get_profile(_chanter);
	var midi = profile.canonical_to_midi[$ canonical];
	if (is_undefined(midi)) return undefined;

	return floor(real(midi));
}

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

function tune_get_note_map(_chanter, _base_midi = undefined) {
	var profile = chanter_get_profile(_chanter);
	var out = {};
	var names = variable_struct_get_names(profile.canonical_to_midi);

	for (var i = 0; i < array_length(names); i++) {
		var canonical = names[i];
		var midi = profile.canonical_to_midi[$ canonical];
		var legacy_key = canonical;
		if (canonical == "=c") legacy_key = "_cnat";
		if (canonical == "=f") legacy_key = "_fnat";
		out[$ legacy_key] = midi;
	}

	return out;
}

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

function tune_get_midi_to_letter_alias_map(_chanter) {
	var profile = chanter_get_profile(_chanter);
	var aliases = {};
	var names = variable_struct_get_names(profile.input_aliases);

	for (var i = 0; i < array_length(names); i++) {
		var midi_key = names[i];
		var canonical = string(profile.input_aliases[$ midi_key]);
		aliases[$ midi_key] = chanter_canonical_to_display(canonical);
	}

	return aliases;
}

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
	var events = _tune.events;
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
	
	// Save to datafiles folder using relative path (GameMaker sandboxing restriction)
	var filepath = "datafiles/" + filename;
	
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
