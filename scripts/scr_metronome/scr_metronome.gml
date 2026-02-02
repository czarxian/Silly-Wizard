// scr_metronome — Metronome event generation and configuration
// Purpose: Generate MIDI percussion events for metronome clicks based on tune BPM and time signature
// Key functions: metronome_generate_events, metronome_set_pattern

/// ============ METRONOME GLOBAL CONFIGURATION ============
/// Drum kit definition and pattern templates

if (!variable_global_exists("METRONOME_CONFIG")) {
    global.METRONOME_CONFIG = {
        enabled: true,
        mode: "Drums",  // "None", "Click", or "Drums" (synced with global.metronome_mode)
        channel: 9,  // MIDI channel 10 (0-indexed, so add 1 for actual MIDI)
        velocity_emphasis: 100,  // Synced with global.metronome_volume
        velocity_normal: 70,     // Calculated as 70% of emphasis
        current_variant: "emphasis_beat_beat_beat",  // Default pattern
        
        // Drum sound definitions (MIDI note numbers - General MIDI percussion)
        drums: {
            kick: 35,           // Acoustic Bass Drum (emphasis beat)
            snare: 38,          // Acoustic Snare (normal beat)
            hi_hat: 42,         // Closed Hi-Hat (optional accent emphasis)
            side_stick: 37,     // Side Stick (for click mode)
            cowbell: 56         // Cowbell (alternative click sound)
        },
        
        // Pattern templates by MODE and time signature
        // "Click" mode = simple single-note patterns
        // "Drums" mode = full drum kit patterns
        patterns: {
            "Click": {
                "4/4": {
                    "simple": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},   // Beat 1: cowbell
                        {beat_position: 1, drum_notes: [37], emphasis: false},  // Beat 2: side stick
                        {beat_position: 2, drum_notes: [37], emphasis: false},  // Beat 3: side stick
                        {beat_position: 3, drum_notes: [37], emphasis: false}   // Beat 4: side stick
                    ]
                },
                "3/4": {
                    "simple": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false},
                        {beat_position: 2, drum_notes: [37], emphasis: false}
                    ]
                },
                "6/8": {
                    "simple": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false},
                        {beat_position: 2, drum_notes: [37], emphasis: false},
                        {beat_position: 3, drum_notes: [56], emphasis: true},
                        {beat_position: 4, drum_notes: [37], emphasis: false},
                        {beat_position: 5, drum_notes: [37], emphasis: false}
                    ]
                }
            },
            "Drums": {
                "4/4": {
                    // Pattern 1: Emphasis on 1, normal on 2-4
                    "emphasis_beat_beat_beat": [
                        {beat_position: 0, drum_notes: [35, 42], emphasis: true},   // Beat 1: kick + hi-hat
                        {beat_position: 1, drum_notes: [38],    emphasis: false},   // Beat 2: snare
                        {beat_position: 2, drum_notes: [38],    emphasis: false},   // Beat 3: snare
                        {beat_position: 3, drum_notes: [38],    emphasis: false}    // Beat 4: snare
                    ],
                    // Pattern 2: Two-feel - emphasis on 1 and 3
                    "two_feel": [
                        {beat_position: 0, drum_notes: [35, 42], emphasis: true},   // Beat 1: kick + hi-hat (emphasis)
                        {beat_position: 1, drum_notes: [42],    emphasis: false},   // Beat 2: hi-hat only
                        {beat_position: 2, drum_notes: [35, 42], emphasis: true},   // Beat 3: kick + hi-hat (emphasis)
                        {beat_position: 3, drum_notes: [42],    emphasis: false}    // Beat 4: hi-hat only
                    ],
                    // Pattern 3: Rock beat - hi-hat/snare on 0, kick on 2
                    "rock_beat_1": [
                        {beat_position: 0, drum_notes: [42, 38], emphasis: true, light: false},   // Beat 1: hi-hat + snare (emphasis)
                        {beat_position: 1, drum_notes: [42],    emphasis: false, light: true},    // Beat 2: hi-hat only (light)
                        {beat_position: 2, drum_notes: [35, 42], emphasis: true, light: false},   // Beat 3: kick + hi-hat (emphasis)
                        {beat_position: 3, drum_notes: [42],    emphasis: false, light: true}     // Beat 4: hi-hat only (light)
                    ],
                    // Pattern 4: Eighth notes with light upbeats
                    "eighth_notes_light": [
                        {beat_position: 0.0, drum_notes: [42, 38], emphasis: true, light: false},   // Beat 1: snare (emphasis)
                        {beat_position: 0.5, drum_notes: [42],    emphasis: false, light: true},    // Upbeat: hi-hat (light)
                        {beat_position: 1.0, drum_notes: [38],    emphasis: false, light: false},   // Beat 2: snare
                        {beat_position: 1.5, drum_notes: [42],    emphasis: false, light: true},    // Upbeat: hi-hat (light)
                        {beat_position: 2.0, drum_notes: [38],    emphasis: false, light: false},   // Beat 3: snare
                        {beat_position: 2.5, drum_notes: [42],    emphasis: false, light: true},    // Upbeat: hi-hat (light)
                        {beat_position: 3.0, drum_notes: [38],    emphasis: false, light: false},   // Beat 4: snare
                        {beat_position: 3.5, drum_notes: [42],    emphasis: false, light: true}     // Upbeat: hi-hat (light)
                    ]
                },
                "3/4": {
                    "waltz": [
                        {beat_position: 0, drum_notes: [35], emphasis: true},
                        {beat_position: 1, drum_notes: [42], emphasis: false},
                        {beat_position: 2, drum_notes: [42], emphasis: false}
                    ]
                },
                "6/8": {
                    "compound": [
                        {beat_position: 0, drum_notes: [35, 42], emphasis: true},
                        {beat_position: 1, drum_notes: [42],    emphasis: false},
                        {beat_position: 2, drum_notes: [42],    emphasis: false},
                        {beat_position: 3, drum_notes: [38, 42], emphasis: true},
                        {beat_position: 4, drum_notes: [42],    emphasis: false},
                        {beat_position: 5, drum_notes: [42],    emphasis: false}
                    ]
                }
            }
        },
        
        // Current user selection
        current_pattern: "4/4",
        current_variant: "emphasis_beat_beat_beat"
    };
}

/// @function metronome_generate_events(_tune)
/// @description Generate metronome MIDI events based on tune BPM and time signature
/// @param _tune Tune struct with .bpm, .time_signature, and event timing
/// @returns Array of MIDI event objects for metronome beats

function metronome_generate_events(_tune, _settings) {
    // Apply optional overrides (from set item)
    var mode_index = global.metronome_mode;
    var pattern_selection = global.metronome_pattern_selection;
    var volume = global.metronome_volume;
    var bpm_override = undefined;
    if (argument_count > 1 && is_struct(_settings)) {
        if (!is_undefined(_settings.metronome_mode)) mode_index = _settings.metronome_mode;
        if (!is_undefined(_settings.metronome_pattern)) pattern_selection = _settings.metronome_pattern;
        if (!is_undefined(_settings.metronome_volume)) volume = _settings.metronome_volume;
        if (!is_undefined(_settings.bpm)) bpm_override = _settings.bpm;
    }
	
    var mode_count = array_length(global.metronome_mode_options);
    if (mode_count <= 0) {
        return [];
    }
    mode_index = clamp(real(mode_index), 0, mode_count - 1);
	
    // Check metronome mode first
    if (mode_index == 0) {
        return []; // Mode is "None"
    }
	
    if (!global.METRONOME_CONFIG.enabled) {
        return [];
    }
	
    var config = global.METRONOME_CONFIG;
	
    // Sync velocities from volume
    config.velocity_emphasis = volume;
    config.velocity_normal = floor(volume * 0.7);
	
    // Get mode name from index
    var mode = global.metronome_mode_options[mode_index];
    config.mode = mode;
    
    // Extract metadata the same way scr_preprocess_tune does
    var meta = _tune.tune_data.tune_metadata;
    
    // Get time signature and tempo with fallbacks
    var time_sig = string(meta.meter ?? "4/4");
    var tempo_str = string(meta.tempo_default ?? "");
    var bpm = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
    if (!is_undefined(bpm_override)) {
        bpm = real(bpm_override);
    }
    
    // Calculate ms_per_beat from BPM (same calculation as tune preprocessing)
    // BPM is quarter notes per minute
    var ms_per_beat = 60000 / bpm;
    
    // BPM-based timing calculated
    
    // Get the pattern for this MODE and time signature
    var mode_patterns = config.patterns[$ mode];
    if (mode_patterns == undefined) {
        show_debug_message("WARNING: No patterns defined for mode: " + mode);
        return [];
    }
    
    var time_sig_patterns = mode_patterns[$ time_sig];
    if (time_sig_patterns == undefined) {
        show_debug_message("WARNING: No patterns for " + mode + " mode at " + time_sig);
        return [];
    }
    
    // Use "Auto" selection or specific pattern
    var pattern;
    if (pattern_selection == 0) {
        // Auto mode - use first available pattern for this time signature
        var pattern_names = struct_get_names(time_sig_patterns);
        if (array_length(pattern_names) > 0) {
            pattern = time_sig_patterns[$ pattern_names[0]];
            config.current_variant = pattern_names[0];
        }
    } else {
        // User selected specific pattern - use name directly from options
        var selected_pattern_name = global.metronome_pattern_options[pattern_selection];
        pattern = time_sig_patterns[$ selected_pattern_name];
        if (pattern != undefined) {
            config.current_variant = selected_pattern_name;
        }
    }
    
    if (pattern == undefined) {
        show_debug_message("WARNING: Could not find pattern for " + mode + " / " + time_sig);
        return [];
    }
    
    // Find where measure 1, beat 1 starts (skip any pickup measures)
    // Look in the PREPROCESSED events (_tune.events), not the raw JSON
    var measure_1_start_ms = 0;
    var preprocessed = _tune.events;  // These have the calculated .time field
    
    // Find first event with non-zero timestamp (skips pickup measure at time 0)
    for (var i = 0; i < array_length(preprocessed); i++) {
        var ev = preprocessed[i];
        if (ev.type == "note_on" && ev.time > 0) {
            measure_1_start_ms = ev.time;
            show_debug_message("Found first note_on after pickup at time " + string(measure_1_start_ms) + " ms");
            break;
        }
    }
    
    // Calculate total tune duration
    var tune_length_ms = 0;
    for (var i = 0; i < array_length(_tune.events); i++) {
        if (_tune.events[i].time > tune_length_ms) {
            tune_length_ms = _tune.events[i].time;
        }
    }
    
    // Calculate measure duration from time signature
    var time_sig_parts = string_split(time_sig, "/");
    var beats_per_measure = real(time_sig_parts[0]);  // e.g., 4 in "4/4"
    var measure_duration_ms = beats_per_measure * ms_per_beat;
    
    // Generate metronome events for entire tune duration
    var metro_events = [];
    var current_measure = 1;  // Start at measure 1
    var current_time_ms = measure_1_start_ms;  // Start where measure 1 begins
    
    while (current_time_ms < tune_length_ms) {
        // Play each beat in the pattern for this measure
        for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
            var beat_def = pattern[beat_idx];
            var beat_time_ms = current_time_ms + (beat_def.beat_position * ms_per_beat);
            
            // Create a MIDI note_on event for each drum sound in this beat
            for (var sound_idx = 0; sound_idx < array_length(beat_def.drum_notes); sound_idx++) {
                var note = beat_def.drum_notes[sound_idx];
                var velocity = beat_def.emphasis ? config.velocity_emphasis : config.velocity_normal;
                
                array_push(metro_events, {
                    time: beat_time_ms,
                    type: "note_on",
                    channel: config.channel,
                    note: note,
                    velocity: velocity
                });
                
                // Also add note_off event shortly after (50ms duration)
                array_push(metro_events, {
                    time: beat_time_ms + 50,
                    type: "note_off",
                    channel: config.channel,
                    note: note,
                    velocity: 0
                });
            }
        }
        
        // Move to next measure
        current_measure++;
        current_time_ms += measure_duration_ms;
    }
    
    show_debug_message("✓ Metronome: Generated " + string(array_length(metro_events)) + " events for " + time_sig + " at " + string(bpm) + " BPM");
    return metro_events;
}

/// @function metronome_set_pattern(_time_sig, _variant_name)
/// @description Set the active metronome pattern
/// @param _time_sig Time signature (e.g., "4/4")
/// @param _variant_name Pattern variant name (e.g., "emphasis_beat_beat_beat")

function metronome_set_pattern(_time_sig, _variant_name) {
    var config = global.METRONOME_CONFIG;
    
    if (config.patterns[$ _time_sig] == undefined) {
        show_debug_message("ERROR: Time signature not supported: " + _time_sig);
        return false;
    }
    
    if (config.patterns[$ _time_sig][$ _variant_name] == undefined) {
        show_debug_message("ERROR: Pattern variant not found: " + _time_sig + " / " + _variant_name);
        return false;
    }
    
    config.current_pattern = _time_sig;
    config.current_variant = _variant_name;
    show_debug_message("✓ Metronome pattern set to: " + _time_sig + " / " + _variant_name);
    return true;
}

/// @function metronome_toggle(_enabled)
/// @description Enable or disable metronome
/// @param _enabled Boolean

function metronome_toggle(_enabled) {
    global.METRONOME_CONFIG.enabled = _enabled;
    show_debug_message("Metronome " + (_enabled ? "enabled" : "disabled"));
}

/// @function metronome_list_patterns()
/// @description Return list of available patterns
/// @returns Struct with available time signatures and variants

function metronome_list_patterns() {
    var result = {};
    var patterns = global.METRONOME_CONFIG.patterns;
    
    var keys = struct_get_names(patterns);
    for (var i = 0; i < array_length(keys); i++) {
        var time_sig = keys[i];
        var variants = struct_get_names(patterns[$ time_sig]);
        result[$ time_sig] = variants;
    }
    
    return result;
}

/// @function metronome_pattern_to_symbols(_pattern)
/// @description Convert a pattern definition to symbolic notation for display
/// @param _pattern Array of beat definitions {beat_position, drum_notes[], emphasis, light (optional)}
/// @returns String using ● (emphasis), ○ (normal), · (light)

function metronome_pattern_to_symbols(_pattern) {
    var symbols = "";
    
    for (var i = 0; i < array_length(_pattern); i++) {
        var beat = _pattern[i];
        
        // Check for light beats first (defaults to false if not defined)
        if (beat.light ?? false) {
            symbols += "·";  // U+00B7 Middle Dot - light beat
        } else if (beat.emphasis) {
            symbols += "●";  // U+25CF Black Circle - strong beat
        } else {
            symbols += "○";  // U+25CB White Circle - regular beat
        }
    }
    
    return symbols;
}

/// @function metronome_update_pattern_list(_time_sig)
/// @description Update global.metronome_pattern_options based on current tune's time signature and mode
/// @param _time_sig Time signature of current tune (e.g., "4/4"), or undefined to use default

function metronome_update_pattern_list(_time_sig) {
    // Default to 4/4 if no tune loaded
    if (_time_sig == undefined || _time_sig == "") {
        _time_sig = "4/4";
    }
    
    // Get current mode
    var mode = global.metronome_mode_options[global.metronome_mode];
    
    // Get patterns for this mode and time signature
    var mode_patterns = global.METRONOME_CONFIG.patterns[$ mode];
    
    if (mode_patterns == undefined) {
        show_debug_message("WARNING: No patterns for mode: " + mode);
        global.metronome_pattern_options = ["Auto"];
        return;
    }
    
    var time_sig_patterns = mode_patterns[$ _time_sig];
    
    if (time_sig_patterns == undefined) {
        show_debug_message("WARNING: No patterns for " + mode + " / " + _time_sig);
        global.metronome_pattern_options = ["Auto"];
        return;
    }
    
    // Build pattern options: "Auto" + pattern names
    var pattern_names = struct_get_names(time_sig_patterns);
    var options = ["Auto"];
    
    for (var i = 0; i < array_length(pattern_names); i++) {
        array_push(options, pattern_names[i]);
    }
    
    global.metronome_pattern_options = options;
    
    // Reset selection to Auto if current selection is out of range
    if (global.metronome_pattern_selection >= array_length(options)) {
        global.metronome_pattern_selection = 0;
    }
    
    show_debug_message("Updated pattern list for " + mode + " / " + _time_sig + ": " + string(array_length(options)) + " options");
}

/// @function metronome_generate_countin_events(_tune, _settings, _count_in_measures)
/// @description Generate metronome events for a count-in before the tune starts
/// @param _tune Tune struct with .tune_data metadata
/// @param _settings Optional overrides (bpm, metronome_mode, metronome_pattern, metronome_volume)
/// @param _count_in_measures Number of measures to count in
/// @returns Array of MIDI event objects for count-in beats

function metronome_generate_countin_events(_tune, _settings, _count_in_measures) {
    if (_count_in_measures <= 0) return [];
	
    // Apply optional overrides (from set item)
    var mode_index = global.metronome_mode;
    var pattern_selection = global.metronome_pattern_selection;
    var volume = global.metronome_volume;
    var bpm_override = undefined;
    if (argument_count > 1 && is_struct(_settings)) {
        if (!is_undefined(_settings.metronome_mode)) mode_index = _settings.metronome_mode;
        if (!is_undefined(_settings.metronome_pattern)) pattern_selection = _settings.metronome_pattern;
        if (!is_undefined(_settings.metronome_volume)) volume = _settings.metronome_volume;
        if (!is_undefined(_settings.bpm)) bpm_override = _settings.bpm;
    }
	
    var mode_count = array_length(global.metronome_mode_options);
    if (mode_count <= 0) return [];
    mode_index = clamp(real(mode_index), 0, mode_count - 1);
    if (mode_index == 0) return []; // None
    if (!global.METRONOME_CONFIG.enabled) return [];
	
    var config = global.METRONOME_CONFIG;
    config.velocity_emphasis = volume;
    config.velocity_normal = floor(volume * 0.7);
	
    var mode = global.metronome_mode_options[mode_index];
    config.mode = mode;
	
    var meta = _tune.tune_data.tune_metadata;
    var time_sig = string(meta.meter ?? "4/4");
    var tempo_str = string(meta.tempo_default ?? "");
    var bpm = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
    if (!is_undefined(bpm_override)) bpm = real(bpm_override);
    var ms_per_beat = 60000 / bpm;
	
    // Get pattern for this mode/time signature
    var mode_patterns = config.patterns[$ mode];
    if (mode_patterns == undefined) return [];
    var time_sig_patterns = mode_patterns[$ time_sig];
    if (time_sig_patterns == undefined) return [];
	
    var pattern;
    if (pattern_selection == 0) {
        var pattern_names = struct_get_names(time_sig_patterns);
        if (array_length(pattern_names) > 0) {
            pattern = time_sig_patterns[$ pattern_names[0]];
            config.current_variant = pattern_names[0];
        }
    } else {
        var selected_pattern_name = global.metronome_pattern_options[pattern_selection];
        pattern = time_sig_patterns[$ selected_pattern_name];
        if (pattern != undefined) config.current_variant = selected_pattern_name;
    }
    if (pattern == undefined) return [];
	
    var time_sig_parts = string_split(time_sig, "/");
    var beats_per_measure = real(time_sig_parts[0]);
    var measure_duration_ms = beats_per_measure * ms_per_beat;
	
    var events = [];
    var current_time_ms = 0;
    for (var m = 0; m < _count_in_measures; m++) {
        for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
            var beat_def = pattern[beat_idx];
            var beat_time_ms = current_time_ms + (beat_def.beat_position * ms_per_beat);
            for (var sound_idx = 0; sound_idx < array_length(beat_def.drum_notes); sound_idx++) {
                var note = beat_def.drum_notes[sound_idx];
                var velocity = beat_def.emphasis ? config.velocity_emphasis : config.velocity_normal;
                array_push(events, { time: beat_time_ms, type: "note_on", channel: config.channel, note: note, velocity: velocity });
                array_push(events, { time: beat_time_ms + 50, type: "note_off", channel: config.channel, note: note, velocity: 0 });
            }
        }
        current_time_ms += measure_duration_ms;
    }
	
    return events;
}