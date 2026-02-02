// scr_tune_preprocess — Tune preprocessing & play array builder
// Purpose: Convert raw tune JSON (with unit-based timings and embellishments) into a playable MIDI event array.
// Key functions: 
//   - scr_preprocess_tune(_tune) — Main entry point; returns playable event array
//   - tune_units_to_ms(_units, _tempo_bpm, _unit_ms) — Unit → millisecond conversion
//   - tune_note_letter_to_midi(_letter, _base_midi) — Resolve note letter to MIDI value
//   - tune_expand_embellishment(_emb_name, _base_midi) — Expand embellishment notation into note sequence
//   - tune_build_playable_events(_tune) — Filter and convert raw events to MIDI format

/// ============ USER-CONFIGURABLE GRACENOTE TIMING ============
/// Adjust these values to control how gracenote duration varies with tempo
/// Stored globally so any script can access without needing an instance variable.
if (!variable_global_exists("GRACENOTE_CONFIG")) {
	global.GRACENOTE_CONFIG = {
		min_ms: 20,                 // Duration at fast tempo (120+ BPM)
		max_ms: 80,                 // Duration at slow tempo (50-60 BPM)
		fast_bpm_threshold: 120,    // BPM above which uses min_ms
		slow_bpm_threshold: 60      // BPM below which uses max_ms
	};
}

function scr_preprocess_tune(_tune, _override_bpm) {
	if (!_tune.tune_data.is_loaded) {
		show_debug_message("ERROR: scr_preprocess_tune called on unloaded tune");
		return array_create(0);
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
	if (!is_undefined(_override_bpm)) {
		tempo_bpm = real(_override_bpm);
	}
	
	// Calculate unit_ms from BPM and unit note length
	// BPM is quarter notes per minute, so ms_per_quarter = 60000 / BPM
	var ms_per_quarter = 60000 / tempo_bpm;
	
	// Check what the unit note is (defaults to eighth note if not specified)
	var unit_note = string(meta.unit_note_length ?? "1/8");
	var unit_ms = ms_per_quarter / 2;  // Assuming 1/8 notes for now
	// TODO: Parse unit_note to handle other note values (1/16, 1/4, etc.)
	
	show_debug_message("  Tempo: " + string(tempo_bpm) + " BPM -> " + string(ms_per_quarter) + "ms per beat");
	show_debug_message("  Calculated unit_ms: " + string(unit_ms) + " (for " + unit_note + " notes)");
	
	var base_str = string(perf.instrument_midi_note_base ?? "");
	var base_midi = (string_length(base_str) > 0) ? real(base_str) : 55;
	
	var channel_str = string(perf.channel ?? "");
	var channel = (string_length(channel_str) > 0) ? real(channel_str) : 0;
	
	show_debug_message("  Tempo: " + string(tempo_bpm) + " BPM -> " + string(ms_per_quarter) + "ms per beat");
	show_debug_message("  Calculated unit_ms: " + string(unit_ms) + " (for " + unit_note + " notes)");
	show_debug_message("  Base MIDI: " + string(base_midi));
	
	// Build playable events
	var playable = tune_build_playable_events(_tune, tempo_bpm, unit_ms, base_midi, channel, events);
	
	show_debug_message("  → Generated " + string(array_length(playable)) + " playable events");
	
	// Debug: Export playable events to CSV for inspection
	tune_export_playable_events_csv(playable, _tune.tune_data.filename);
	
	return playable;
}

/// @function tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events)
/// @description Iterate through tune events and convert to MIDI format.

function tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events) {
	var events = _events;  // Use the passed events array instead of trying to read from _tune
	var playable = array_create(0);
	var note_off_queue = array_create(0); // Store pending note-offs
	var target_note_delay_ms = 0;  // Track delay from embellishments stealing from target
	
	show_debug_message("  tune_build_playable_events: Processing " + string(array_length(events)) + " events");
	
	for (var i = 0; i < array_length(events); i++) {
		var ev = events[i];
		var time_ms = tune_units_to_ms(ev.total_units, _tempo, _unit_ms);
		
		// Skip structure events (bars, divisions)
		if (ev.type == "structure") {
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
				channel: _channel
			});
			
			// Calculate note off time - shorten duration by stolen time from embellishment
			var duration_ms = (real(ev.adjusted ?? 1)) * _unit_ms - target_note_delay_ms;
			var note_off_time = actual_start_time + duration_ms;
			target_note_delay_ms = 0;  // Reset after using
			
			array_push(note_off_queue, {
				time: note_off_time,
				note: midi_note,
				channel: _channel
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
				var expanded_notes = embellishment_to_notes(emb_found, target_duration_ms, preceding_duration_ms, _tempo);
				
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
						channel: _channel
					});
					
					// Note off
					array_push(note_off_queue, {
						time: current_emb_time + note_duration,
						note: midi_from_letter,
						channel: _channel
					});
					
					current_emb_time += note_duration;
				}
			} else {
				// Fallback: embellishment not found in library, use old literal expansion
				show_debug_message("    → Embellishment not found in library, using fallback expansion");
				var emb_notes = tune_expand_embellishment(ev.emb_literal, _base_midi);
				
				// Use tempo-based duration for single-note
				if (array_length(emb_notes) == 1) {
					var gracenote_ms = tune_get_gracenote_timing(_tempo);
					array_push(playable, {
						time: time_ms,
						type: "note_on",
						note: emb_notes[0],
						velocity: 70,
						channel: _channel
					});
					array_push(note_off_queue, {
						time: time_ms + gracenote_ms,
						note: emb_notes[0],
						channel: _channel
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
							channel: _channel
						});
						array_push(note_off_queue, {
							time: emb_time + (time_per_note * 0.8),
							note: emb_notes[j],
							channel: _channel
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
			channel: note_off.channel
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

/// @function tune_get_gracenote_timing(_tempo_bpm)
/// @description Calculate gracenote duration based on tempo.
/// Uses GRACENOTE_CONFIG for user-configurable parameters.
/// @param _tempo_bpm  Tempo in beats per minute
/// @returns Duration in milliseconds

function tune_get_gracenote_timing(_tempo_bpm) {
	var config = global.GRACENOTE_CONFIG;
	var gracenote_ms;
	
	if (_tempo_bpm <= config.slow_bpm_threshold) {
		// At or below slow threshold: use maximum gracenote duration
		gracenote_ms = config.max_ms;
	} else if (_tempo_bpm >= config.fast_bpm_threshold) {
		// At or above fast threshold: use minimum gracenote duration
		gracenote_ms = config.min_ms;
	} else {
		// Linear interpolation between thresholds
		var ratio = (_tempo_bpm - config.slow_bpm_threshold) / (config.fast_bpm_threshold - config.slow_bpm_threshold);
		gracenote_ms = config.max_ms - (config.max_ms - config.min_ms) * ratio;
	}
	
	return gracenote_ms;
}

/// @function tune_note_letter_to_midi(_letter, _base_midi)
/// @description Resolve a note letter (A, B, c, d, e, f, g) to MIDI value.
/// @param _letter     Note letter from JSON
/// @param _base_midi  Not used (replaced by exact MIDI lookup)
/// @returns MIDI note number

function tune_note_letter_to_midi(_letter, _base_midi) {
	// Bagpipe chanter MIDI note mapping (exact from Excel reference)
	// Bagpipe uses C# and F# as standard notes
	// Using struct instead of ds_map for simplicity and memory efficiency
	var note_map = {
		G: 55,    // Low G
		A: 57,    // Low A
		B: 59,    // B
		c: 61,    // C# (C sharp, C#4)
		d: 62,    // D
		e: 64,    // E
		f: 66,    // F# (F sharp, F#4)
		g: 67,    // High G
		a: 69,    // High A
		_cnat: 60,  // Cnat (C natural, C4) — prefixed with _ since =c is not a valid struct key
		_fnat: 65   // Fnat (F natural, F4)
	};
	
	// Handle special note names
	var midi;
	if (_letter == "=c") {
		midi = note_map._cnat;
	} else if (_letter == "=f") {
		midi = note_map._fnat;
	} else {
		midi = note_map[$ _letter] ?? undefined;
	}
	
	if (midi == undefined) {
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
		var row = string(ev.time) + "," + 
		          string(ev.type) + "," + 
		          string(ev.note ?? "") + "," + 
		          string(ev.velocity ?? "") + "," + 
		          string(ev.channel ?? "");
		file_text_write_string(file, row + chr(10));
	}
	
	file_text_close(file);
	show_debug_message("✓ Exported playable events to: " + filepath + " (" + string(array_length(_playable_array)) + " events)");
}
