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
        velocity_light: 40,      // Calculated as 40% of emphasis
        current_variant: "default",  // Default pattern
        
        // Drum sound definitions (MIDI note numbers - General MIDI percussion)
        //drums: {
        //    kick: 35,           // Acoustic Bass Drum (emphasis beat)
        //    snare: 38,          // Acoustic Snare (normal beat)
        //    hi_hat: 42,         // Closed Hi-Hat (optional accent emphasis)
        //    side_stick: 37,     // Side Stick (for click mode)
        //    cowbell: 56         // Cowbell (alternative click sound)
        //},
		// Alternate for Drumlines via Cantabile
		    drums: {
            kick: 41,           // Acoustic Bass Drum (emphasis beat)
            snare: 60,          // Acoustic Snare (normal beat)
            hi_hat: 63,         // Closed Hi-Hat (optional accent emphasis)
            low_tenor: 53 ,     // Side Stick (for click mode)
            tenor: 57          // Cowbell (alternative click sound)
        },
		
		
        
        // Pattern templates by MODE and time signature
        // "Click" mode = simple single-note patterns
        // "Drums" mode = full drum kit patterns
        patterns: {
            "Click": {
                "4/4": {
                    "default": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},   // Beat 1: cowbell
                        {beat_position: 1, drum_notes: [37], emphasis: false},  // Beat 2: side stick
                        {beat_position: 2, drum_notes: [37], emphasis: false},  // Beat 3: side stick
                        {beat_position: 3, drum_notes: [37], emphasis: false}   // Beat 4: side stick
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: [37], emphasis: false},
                        {beat_position: 2.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: [37], emphasis: false},
                        {beat_position: 3.5, drum_notes: [37], emphasis: false, light: true}
                    ]
                },
                "3/4": {
                    "default": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false},
                        {beat_position: 2, drum_notes: [37], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: [37], emphasis: false},
                        {beat_position: 2.5, drum_notes: [37], emphasis: false, light: true}
                    ]
                },
                "2/4": {
                    "default": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true}
                    ]
                },
                "6/8": {
                    "default": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false},
                        {beat_position: 2, drum_notes: [37], emphasis: false},
                        {beat_position: 3, drum_notes: [37], emphasis: false},
                        {beat_position: 4, drum_notes: [37], emphasis: false},
                        {beat_position: 5, drum_notes: [37], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: [37], emphasis: false},
                        {beat_position: 2.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: [37], emphasis: false},
                        {beat_position: 3.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 4.0, drum_notes: [37], emphasis: false},
                        {beat_position: 4.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 5.0, drum_notes: [37], emphasis: false},
                        {beat_position: 5.5, drum_notes: [37], emphasis: false, light: true}
                    ],
                    "six_eight_emphasis_4": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 2, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 3, drum_notes: [37], emphasis: false},
                        {beat_position: 4, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 5, drum_notes: [37], emphasis: false, light: true}
                    ]
                },
                "2/2": {
                    "default": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false},
                        {beat_position: 1.0, drum_notes: [56], emphasis: true},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true}
                    ]
                },
                "7/4": {
                    "default": [
                        {beat_position: 0, drum_notes: [56], emphasis: true},
                        {beat_position: 1, drum_notes: [37], emphasis: false},
                        {beat_position: 2, drum_notes: [37], emphasis: false},
                        {beat_position: 3, drum_notes: [37], emphasis: false},
                        {beat_position: 4, drum_notes: [37], emphasis: false},
                        {beat_position: 5, drum_notes: [37], emphasis: false},
                        {beat_position: 6, drum_notes: [37], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: [56], emphasis: true},
                        {beat_position: 0.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: [37], emphasis: false},
                        {beat_position: 1.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: [37], emphasis: false},
                        {beat_position: 2.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: [37], emphasis: false},
                        {beat_position: 3.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 4.0, drum_notes: [37], emphasis: false},
                        {beat_position: 4.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 5.0, drum_notes: [37], emphasis: false},
                        {beat_position: 5.5, drum_notes: [37], emphasis: false, light: true},
                        {beat_position: 6.0, drum_notes: [37], emphasis: false},
                        {beat_position: 6.5, drum_notes: [37], emphasis: false, light: true}
                    ]
                }
            },
            "Drums": {
                "4/4": {
                    "default": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},   // Beat 1: kick + hi-hat
                        {beat_position: 1, drum_notes: ["snare"],    emphasis: false},         // Beat 2: snare
                        {beat_position: 2, drum_notes: ["snare"],    emphasis: false},         // Beat 3: snare
                        {beat_position: 3, drum_notes: ["snare"],    emphasis: false}          // Beat 4: snare
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 2.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 3.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ],
                    "rock_beat_1": [
                        {beat_position: 0.0, drum_notes: ["hi_hat"],    emphasis: false, light: false},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["hi_hat"],    emphasis: false, light: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: ["kick", "hi_hat"], emphasis: true, light: false},
                        {beat_position: 2.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: ["hi_hat"],    emphasis: false, light: false},
                        {beat_position: 3.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                },
                "3/4": {
                    "default": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 2, drum_notes: ["snare"], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 2.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                },
                "2/4": {
                    "default": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1, drum_notes: ["snare"], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                },
                "6/8": {
                    "default": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 2, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 3, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 4, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 5, drum_notes: ["snare"],    emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 2.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 3.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 4.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 4.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 5.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 5.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ],
                    "six_eight_emphasis_4": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 3, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 4, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                },
                "2/2": {
                    "default": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["snare"],    emphasis: false},
                        {beat_position: 1.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1.5, drum_notes: ["snare"],    emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                },
                "7/4": {
                    "default": [
                        {beat_position: 0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 1, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 2, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 3, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 4, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 5, drum_notes: ["snare"], emphasis: false},
                        {beat_position: 6, drum_notes: ["snare"], emphasis: false}
                    ],
                    "half_beat": [
                        {beat_position: 0.0, drum_notes: ["kick", "hi_hat"], emphasis: true},
                        {beat_position: 0.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 1.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 1.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 2.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 2.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 3.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 3.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 4.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 4.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 5.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 5.5, drum_notes: ["hi_hat"],    emphasis: false, light: true},
                        {beat_position: 6.0, drum_notes: ["snare"],     emphasis: false},
                        {beat_position: 6.5, drum_notes: ["hi_hat"],    emphasis: false, light: true}
                    ]
                }
            }
        },
        
        // Current user selection
        current_pattern: "4/4",
        current_variant: "emphasis_beat_beat_beat"
    };
}

/// @function metronome_normalize_time_sig(_time_sig)
/// @description Normalize common time symbols and missing meters to a canonical "n/d" string. Delegates to timing_normalize_time_sig.
/// @param {string} _time_sig  Raw time signature (e.g. "C", "C|", "6/8", "")
/// @returns {string}  Canonical time signature e.g. "4/4"
/// @reads   none
/// @writes  none
/// @objects none
/// @callers metronome_generate_events, metronome_set_pattern, metronome_update_pattern_list, scr_set_scripts

function metronome_normalize_time_sig(_time_sig) {
    return timing_normalize_time_sig(_time_sig);
}

/// @function metronome_get_effective_quarter_bpm(_bpm, _time_sig)
/// @description Convert displayed BPM to quarter-note BPM used for timing. In cut time (2/2), BPM is interpreted as half-note BPM. Delegates to timing_get_effective_quarter_bpm.
/// @param {real} _bpm  Displayed tempo from tune metadata
/// @param {string} _time_sig  Canonical time signature string
/// @returns {real}  Quarter-note BPM for ms-per-beat calculations
/// @reads   none
/// @writes  none
/// @objects none
/// @callers metronome_generate_events, metronome_generate_countin_events

function metronome_get_effective_quarter_bpm(_bpm, _time_sig) {
    return timing_get_effective_quarter_bpm(_bpm, _time_sig);
}

/// @function metronome_generate_events(_tune, _settings)
/// @description Generate metronome MIDI events for all beats in a tune. Settings override the current globals per-call.
/// @param {struct} _tune  Tune struct (obj_tune instance or equivalent) with .tune_data.tune_metadata
/// @param {struct} _settings  Optional per-call overrides: {bpm, metronome_mode, metronome_pattern, metronome_volume}
/// @returns {array}  Array of MIDI event structs for all metronome beats in the tune
/// @reads   global.METRONOME_CONFIG, global.metronome_mode, global.metronome_mode_options, global.metronome_pattern_selection, global.metronome_pattern_options, global.metronome_volume
/// @writes  global.METRONOME_CONFIG (velocity fields synced from volume on each call)
/// @objects none
/// @callers scr_tune_scripts tune_build_events, scr_button_scripts, scr_set_scripts

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
    config.velocity_light = floor(volume * 0.4);
	
    // Get mode name from index
    var mode = global.metronome_mode_options[mode_index];
    config.mode = mode;
    
    // Extract metadata the same way scr_preprocess_tune does
    var meta = _tune.tune_data.tune_metadata;
    
    // Get time signature and tempo with fallbacks
    var time_sig = metronome_normalize_time_sig(meta.meter ?? "4/4");
    var tempo_str = string(meta.tempo_default ?? "");
    var bpm = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
    if (!is_undefined(bpm_override)) {
        bpm = real(bpm_override);
    }
    
    // Calculate ms_per_quarter from effective quarter BPM
    var effective_quarter_bpm = metronome_get_effective_quarter_bpm(bpm, time_sig);
    var ms_per_quarter = 60000 / effective_quarter_bpm;
    
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
    
    var preprocessed = _tune.events;  // These have the calculated .time field

    // Calculate total tune duration
    var tune_length_ms = 0;
    for (var i = 0; i < array_length(preprocessed); i++) {
        if (preprocessed[i].time > tune_length_ms) {
            tune_length_ms = preprocessed[i].time;
        }
    }

    // Calculate measure duration from time signature
    var time_sig_parts = string_split(time_sig, "/");
    var beats_per_measure = real(time_sig_parts[0]);  // e.g., 4 in "4/4"
    var denom = real(time_sig_parts[1]);
    var beat_unit_ms = ms_per_quarter * (4 / denom);
    var measure_duration_ms = beats_per_measure * beat_unit_ms;

    // Prefer explicit beat markers from preprocessing.
    // This preserves pickup alignment, so accents follow the real beat phase.
    var beat_markers = [];
    for (var i = 0; i < array_length(preprocessed); i++) {
        var ev = preprocessed[i];
        if (!is_struct(ev)) continue;
        if ((ev.type ?? "") != "marker") continue;
        if ((ev.marker_type ?? "") != "beat") continue;
        if (real(ev.measure ?? 0) < 1) continue;
        array_push(beat_markers, ev);
    }

    // Map measure:beat -> earliest note_on onset in that beat.
    // This lets beat clicks align with opening gracenotes when they precede
    // the principal melody note at beat start.
    var earliest_note_on_by_beat = {};
    for (var i = 0; i < array_length(preprocessed); i++) {
        var nev = preprocessed[i];
        if (!is_struct(nev)) continue;
        if ((nev.type ?? "") != "note_on") continue;
        var n_measure = floor(real(nev.measure ?? 0));
        var n_beat = floor(real(nev.beat ?? 0));
        if (n_measure < 1 || n_beat < 1) continue;
        var n_time = real(nev.time ?? 0);
        var beat_key = string(n_measure) + ":" + string(n_beat);
        if (!variable_struct_exists(earliest_note_on_by_beat, beat_key)
            || n_time < real(earliest_note_on_by_beat[$ beat_key])) {
            earliest_note_on_by_beat[$ beat_key] = n_time;
        }
    }

    var metro_events = [];

    if (array_length(beat_markers) > 0) {
        for (var bmi = 0; bmi < array_length(beat_markers); bmi++) {
            var bmk = beat_markers[bmi];
            var beat_time_ms = real(bmk.time ?? 0);
            var beat_number = max(1, floor(real(bmk.beat ?? 1)));
            var beat_fraction = real(bmk.beat_fraction ?? 0);
            var measure_number = max(1, floor(real(bmk.measure ?? 1)));

            // Allow the click to lead to the first note_on in the same beat
            // (commonly a gracenote cluster), but cap the shift to avoid
            // unintended jumps from unrelated early events.
            var marker_key = string(measure_number) + ":" + string(beat_number);
            if (variable_struct_exists(earliest_note_on_by_beat, marker_key)) {
                var candidate_time = real(earliest_note_on_by_beat[$ marker_key]);
                var lead_ms = beat_time_ms - candidate_time;
                if (lead_ms > 0 && lead_ms <= 300) {
                    beat_time_ms = candidate_time;
                }
            }

            array_push(metro_events, {
                time: beat_time_ms,
                type: "marker",
                marker_type: "beat",
                measure: measure_number,
                beat: beat_number,
                beat_fraction: beat_fraction,
                event_id: 0
            });

            var beat_defs = [];
            for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
                var beat_def = pattern[beat_idx];
                var beat_pos = real(beat_def.beat_position ?? 0);
                var pat_beat_number = floor(beat_pos) + 1;
                var pat_beat_fraction = beat_pos - floor(beat_pos);
                if (pat_beat_number == beat_number && abs(pat_beat_fraction - beat_fraction) <= 0.001) {
                    array_push(beat_defs, beat_def);
                }
            }

            if (array_length(beat_defs) <= 0) {
                for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
                    var beat_def_fallback = pattern[beat_idx];
                    var beat_pos_fallback = real(beat_def_fallback.beat_position ?? 0);
                    if ((floor(beat_pos_fallback) + 1) == beat_number) {
                        array_push(beat_defs, beat_def_fallback);
                        break;
                    }
                }
            }

            if (array_length(beat_defs) <= 0 && array_length(pattern) > 0) {
                array_push(beat_defs, pattern[0]);
            }

            for (var bdi = 0; bdi < array_length(beat_defs); bdi++) {
                var use_def = beat_defs[bdi];
                for (var sound_idx = 0; sound_idx < array_length(use_def.drum_notes); sound_idx++) {
                    var note_key = use_def.drum_notes[sound_idx];
                    var note = note_key;
                    if (is_string(note_key)) {
                        if (variable_struct_exists(config.drums, note_key)) {
                            note = config.drums[$ note_key];
                        } else {
                            continue;
                        }
                    }
                    var is_light = (variable_struct_exists(use_def, "light") && use_def.light);
                    var velocity = use_def.emphasis ? config.velocity_emphasis : (is_light ? config.velocity_light : config.velocity_normal);

                    array_push(metro_events, {
                        time: beat_time_ms,
                        type: "note_on",
                        channel: config.channel,
                        note: note,
                        velocity: velocity
                    });
                    array_push(metro_events, {
                        time: beat_time_ms + 50,
                        type: "note_off",
                        channel: config.channel,
                        note: note,
                        velocity: 0
                    });
                }
            }
        }
    } else {
        // Fallback for tunes that do not provide beat markers.
        var measure_1_start_ms = 0;
        for (var i = 0; i < array_length(preprocessed); i++) {
            var ev = preprocessed[i];
            if (!is_struct(ev)) continue;
            if (ev.type == "marker"
                && (ev.marker_type ?? "") == "bar"
                && real(ev.measure ?? 0) == 1) {
                measure_1_start_ms = ev.time;
                break;
            }
        }
        if (measure_1_start_ms == 0) {
            for (var i = 0; i < array_length(preprocessed); i++) {
                var ev = preprocessed[i];
                if (!is_struct(ev)) continue;
                if (ev.type == "note_on" && real(ev.measure ?? 0) >= 1) {
                    measure_1_start_ms = ev.time;
                    break;
                }
            }
        }

        var current_measure = 1;
        var current_time_ms = measure_1_start_ms;
        while (current_time_ms < tune_length_ms) {
            for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
                var beat_def = pattern[beat_idx];
                var beat_time_ms = current_time_ms + (beat_def.beat_position * beat_unit_ms);

                var beat_number = floor(beat_def.beat_position) + 1;
                var beat_fraction = beat_def.beat_position - floor(beat_def.beat_position);
                array_push(metro_events, {
                    time: beat_time_ms,
                    type: "marker",
                    marker_type: "beat",
                    measure: current_measure,
                    beat: beat_number,
                    beat_fraction: beat_fraction,
                    event_id: 0
                });

                for (var sound_idx = 0; sound_idx < array_length(beat_def.drum_notes); sound_idx++) {
                    var note_key = beat_def.drum_notes[sound_idx];
                    var note = note_key;
                    if (is_string(note_key)) {
                        if (variable_struct_exists(config.drums, note_key)) {
                            note = config.drums[$ note_key];
                        } else {
                            continue;
                        }
                    }
                    var is_light = (variable_struct_exists(beat_def, "light") && beat_def.light);
                    var velocity = beat_def.emphasis ? config.velocity_emphasis : (is_light ? config.velocity_light : config.velocity_normal);

                    array_push(metro_events, {
                        time: beat_time_ms,
                        type: "note_on",
                        channel: config.channel,
                        note: note,
                        velocity: velocity
                    });
                    array_push(metro_events, {
                        time: beat_time_ms + 50,
                        type: "note_off",
                        channel: config.channel,
                        note: note,
                        velocity: 0
                    });
                }
            }

            current_measure++;
            current_time_ms += measure_duration_ms;
        }
    }

    array_sort(metro_events, function(a, b) {
        return real(a[$ "time"] ?? 0) - real(b[$ "time"] ?? 0);
    });
    
    show_debug_message("✓ Metronome: Generated " + string(array_length(metro_events)) + " events for " + time_sig + " at " + string(bpm) + " BPM (effective quarter BPM " + string(effective_quarter_bpm) + ")");
    return metro_events;
}

/// @function metronome_set_pattern(_time_sig, _variant_name)
/// @description Set the active metronome pattern by time signature and variant name. Updates global.metronome_pattern_selection.
/// @param {string} _time_sig  Time signature (e.g. "4/4")
/// @param {string} _variant_name  Pattern variant name (e.g. "emphasis_beat_beat_beat")
/// @returns {bool}  true on success, false if pattern not found
/// @reads   global.METRONOME_CONFIG, global.metronome_mode, global.metronome_mode_options, global.metronome_pattern_options
/// @writes  global.METRONOME_CONFIG.current_pattern, global.METRONOME_CONFIG.current_variant, global.metronome_pattern_selection
/// @objects none
/// @callers scr_button_scripts

function metronome_set_pattern(_time_sig, _variant_name) {
    var config = global.METRONOME_CONFIG;
    var time_sig = metronome_normalize_time_sig(_time_sig);
    var mode_count = array_length(global.metronome_mode_options);
    if (mode_count <= 0) {
        show_debug_message("ERROR: Metronome mode options are not initialized");
        return false;
    }
    var mode_index = clamp(real(global.metronome_mode), 0, mode_count - 1);
    if (mode_index == 0) {
        show_debug_message("ERROR: Cannot set metronome pattern while mode is None");
        return false;
    }
    var mode = global.metronome_mode_options[mode_index];
    var mode_patterns = config.patterns[$ mode];
    if (mode_patterns == undefined) {
        show_debug_message("ERROR: Mode not supported in pattern config: " + string(mode));
        return false;
    }
    var time_sig_patterns = mode_patterns[$ time_sig];
    if (time_sig_patterns == undefined) {
        show_debug_message("ERROR: Time signature not supported for mode " + string(mode) + ": " + string(time_sig));
        return false;
    }
    
    if (time_sig_patterns[$ _variant_name] == undefined) {
        show_debug_message("ERROR: Pattern variant not found: " + string(mode) + " / " + string(time_sig) + " / " + string(_variant_name));
        return false;
    }
    
    config.current_pattern = time_sig;
    config.current_variant = _variant_name;

    if (variable_global_exists("metronome_pattern_options") && is_array(global.metronome_pattern_options)) {
        for (var i = 0; i < array_length(global.metronome_pattern_options); i++) {
            if (global.metronome_pattern_options[i] == _variant_name) {
                global.metronome_pattern_selection = i;
                break;
            }
        }
    }

    show_debug_message("✓ Metronome pattern set to: " + string(mode) + " / " + string(time_sig) + " / " + string(_variant_name));
    return true;
}

/// @function metronome_toggle(_enabled)
/// @description Enable or disable the metronome globally.
/// @param {bool} _enabled  true = enabled, false = disabled
/// @reads   none
/// @writes  global.METRONOME_CONFIG.enabled
/// @objects none
/// @callers scr_button_scripts

function metronome_toggle(_enabled) {
    global.METRONOME_CONFIG.enabled = _enabled;
    show_debug_message("Metronome " + (_enabled ? "enabled" : "disabled"));
}

/// @function metronome_list_patterns()
/// @description Return all available patterns organized by mode and time signature. Useful for UI population and debug.
/// @returns {struct}  Nested struct: {mode: {time_sig: [variant_name, ...]}}
/// @reads   global.METRONOME_CONFIG.patterns
/// @writes  none
/// @objects none
/// @callers debug / UI population

function metronome_list_patterns() {
    var result = {};
    var patterns = global.METRONOME_CONFIG.patterns;

    var modes = struct_get_names(patterns);
    for (var i = 0; i < array_length(modes); i++) {
        var mode = modes[i];
        var by_sig = {};
        var sig_names = struct_get_names(patterns[$ mode]);
        for (var s = 0; s < array_length(sig_names); s++) {
            var sig = sig_names[s];
            by_sig[$ sig] = struct_get_names(patterns[$ mode][$ sig]);
        }
        result[$ mode] = by_sig;
    }
    
    return result;
}

/// @function metronome_pattern_to_symbols(_pattern)
/// @description Convert a beat pattern definition to a symbolic display string using ●, ○, · characters.
/// @param {array} _pattern  Array of beat definition structs: [{beat_position, drum_notes[], emphasis, light?}]
/// @returns {string}  Symbol string e.g. "●○○○"
/// @reads   none
/// @writes  none
/// @objects none
/// @callers scr_UI_scripts (pattern display), debug

function metronome_pattern_to_symbols(_pattern) {
    var symbols = "";
    
    for (var i = 0; i < array_length(_pattern); i++) {
        var beat = _pattern[i];
        
        // Check for light beats first (defaults to false if not defined)
        var is_light = (variable_struct_exists(beat, "light") && beat.light);
        if (is_light) {
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
/// @description Rebuild global.metronome_pattern_options for the current mode and given time signature. Resets selection to Auto if current selection is out of range.
/// @param {string} _time_sig  Time signature of current tune (e.g. "4/4"), or undefined to default to 4/4
/// @reads   global.METRONOME_CONFIG.patterns, global.metronome_mode, global.metronome_mode_options, global.metronome_pattern_selection
/// @writes  global.metronome_pattern_options, global.metronome_pattern_selection
/// @objects none
/// @callers scr_button_scripts (on tune select/mode change), scr_tune_library (after library load)

function metronome_update_pattern_list(_time_sig) {
    // Default to 4/4 if no tune loaded
    _time_sig = metronome_normalize_time_sig(_time_sig);
    
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
/// @description Generate metronome MIDI events for a count-in period before the tune starts. Events have negative time_ms values so they precede time 0.
/// @param {struct} _tune  Tune struct with .tune_data.tune_metadata (used for BPM and time sig)
/// @param {struct} _settings  Optional per-call overrides: {bpm, metronome_mode, metronome_pattern, metronome_volume}
/// @param {real} _count_in_measures  Number of measures to count in; returns [] if <= 0
/// @returns {array}  Array of MIDI event structs with time_ms < 0
/// @reads   global.METRONOME_CONFIG, global.metronome_mode, global.metronome_mode_options, global.metronome_pattern_selection, global.metronome_pattern_options, global.metronome_volume
/// @writes  global.METRONOME_CONFIG (velocity fields synced from volume on each call)
/// @objects none
/// @callers scr_set_scripts, scr_button_scripts

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
    var time_sig = metronome_normalize_time_sig(meta.meter ?? "4/4");
    var tempo_str = string(meta.tempo_default ?? "");
    var bpm = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
    if (!is_undefined(bpm_override)) bpm = real(bpm_override);
    var effective_quarter_bpm = metronome_get_effective_quarter_bpm(bpm, time_sig);
    var ms_per_quarter = 60000 / effective_quarter_bpm;
	
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
    var denom = real(time_sig_parts[1]);
    var beat_unit_ms = ms_per_quarter * (4 / denom);
    var measure_duration_ms = beats_per_measure * beat_unit_ms;
	
    var events = [];
    var current_time_ms = 0;
    for (var m = 0; m < _count_in_measures; m++) {
        for (var beat_idx = 0; beat_idx < array_length(pattern); beat_idx++) {
            var beat_def = pattern[beat_idx];
            var beat_time_ms = current_time_ms + (beat_def.beat_position * beat_unit_ms);
            
            // Add a beat marker event (for logging, separate from MIDI)
            var beat_number = floor(beat_def.beat_position) + 1;  // 1-based beat number
            var beat_fraction = beat_def.beat_position - floor(beat_def.beat_position);
            var countin_measure = m - _count_in_measures;  // -1 for one bar, -2/-1 for two bars
            array_push(events, {
                time: beat_time_ms,
                type: "marker",
                marker_type: "countin_beat",
                measure: countin_measure,
                beat: beat_number,
                beat_fraction: beat_fraction,
                event_id: 0
            });
            
            for (var sound_idx = 0; sound_idx < array_length(beat_def.drum_notes); sound_idx++) {
                var note_key = beat_def.drum_notes[sound_idx];
                var note = note_key;
                if (is_string(note_key)) {
                    if (variable_struct_exists(config.drums, note_key)) {
                        note = config.drums[$ note_key];
                    } else {
                        continue;
                    }
                }
                var is_light = (variable_struct_exists(beat_def, "light") && beat_def.light);
                var velocity = beat_def.emphasis ? config.velocity_emphasis : (is_light ? config.velocity_light : config.velocity_normal);
                array_push(events, { time: beat_time_ms, type: "note_on", channel: config.channel, note: note, velocity: velocity });
                array_push(events, { time: beat_time_ms + 50, type: "note_off", channel: config.channel, note: note, velocity: 0 });
            }
        }
        current_time_ms += measure_duration_ms;
    }
	
    return events;
}