/// @function load_embellishment_library(filepath)
/// @description Loads embellishment library from JSON file into array of structs
/// @param {string} filepath - Path to embellishments.json
/// @returns {array} Array of embellishment structs

function load_embellishment_library(filepath) {
    var json_string = "";
    
    show_debug_message("load_embellishment_library: Attempting to load from: " + filepath);
    show_debug_message("  working_directory: " + working_directory);
    show_debug_message("  file_exists: " + string(file_exists(filepath)));
    
    // Read file
    if (file_exists(filepath)) {
        show_debug_message("  → File found, reading...");
        
        // Use buffer to read entire file at once (more reliable than file_text_*)
        var buffer = buffer_load(filepath);
        json_string = buffer_read(buffer, buffer_string);
        buffer_delete(buffer);
        
        show_debug_message("  → JSON string length: " + string(string_length(json_string)));
        
        // Parse JSON - returns array of structs
        var emb_library = json_parse(json_string);
        show_debug_message("  → Parsed " + string(array_length(emb_library)) + " embellishments");
        
        return emb_library;
    } else {
        show_debug_message("  ✗ File not found! Embellishment library will be empty.");
        show_debug_message("  Tried path: " + filepath);
        // Return empty array - game continues without embellishments
        return array_create(0);
    }
}

/// @function find_embellishment(library, pattern, target_note, alt_anchor, alt_timing)
/// @description Finds embellishment in library by pattern and optional target note, with optional overrides
/// @param {array} library - Array of embellishment structs
/// @param {string} pattern - Pattern to match (e.g., "gBd")
/// @param {string} target_note - Target note (e.g., "B"), can be ""
/// @param {real} alt_anchor - Optional anchor override (0 = use library default)
/// @param {string} alt_timing - Optional timing replacement string (e.g., "1,4,1", "" = use library default)
/// @returns {struct} Embellishment struct or undefined if not found

function find_embellishment(library, pattern, target_note, alt_anchor = 0, alt_timing = "") {
    for (var i = 0; i < array_length(library); i++) {
        var emb = library[i];
        
        // Match pattern first
        if (emb.pattern == pattern) {
            
            // If embellishment has no target_note requirement (blank), it matches
            if (emb.target_note == "") {
                return apply_embellishment_overrides(emb, alt_anchor, alt_timing);
            }
            
            // If embellishment requires specific target, check it matches
            if (emb.target_note == target_note) {
                return apply_embellishment_overrides(emb, alt_anchor, alt_timing);
            }
        }
    }
    
    return undefined;  // No match found
}

/// @function apply_embellishment_overrides(emb, alt_anchor, alt_timing)
/// @description Applies per-instance overrides to an embellishment struct (creates a copy)
/// @param {struct} emb - Base embellishment struct
/// @param {real} alt_anchor - Anchor override (0 = no override)
/// @param {string} alt_timing - Timing string override ("" = no override)
/// @returns {struct} New embellishment struct with overrides applied

function apply_embellishment_overrides(emb, alt_anchor, alt_timing) {
    // Create a copy so we don't modify the library
    var result = {
        emb_id: emb.emb_id,
        emb_name: emb.emb_name,
        pattern: emb.pattern,
        target_note: emb.target_note,
        notes: emb.notes,
        timing: emb.timing,
        anchor_index: emb.anchor_index,
        category: emb.category
    };
    
    // Apply anchor override if present
    if (alt_anchor > 0) {
        result.anchor_index = alt_anchor;
    }
    
    // Apply timing override if present and valid
    if (alt_timing != "" && alt_timing != undefined) {
        var lib_timing_array = string_split(emb.timing, ",");
        var alt_timing_array = string_split(alt_timing, ",");
        
        // Only use override if element count matches
        if (array_length(alt_timing_array) == array_length(lib_timing_array)) {
            result.timing = alt_timing;
        }
        // Otherwise keep library default (silent fallback)
    }
    
    return result;
}

/// @function embellishment_to_notes(emb_def, target_duration_ms, preceding_duration_ms, bpm)
/// @description Expands embellishment definition into individual note timings with BPM scaling & constraints
/// @param {struct} emb_def - Embellishment struct from library
/// @param {real} target_duration_ms - Duration of target note in milliseconds
/// @param {real} preceding_duration_ms - Duration of preceding note in milliseconds
/// @param {real} bpm - Tempo in beats per minute (for gracenote unit scaling)
/// @returns {array} Array of note structs with {note, duration_ms}

function embellishment_to_notes(emb_def, target_duration_ms, preceding_duration_ms, bpm) {
    
    var notes_array = string_split(emb_def.notes, ",");
    var timing_array = string_split(emb_def.timing, ",");
    var anchor_index = emb_def.anchor_index - 1;  // Convert to 0-based
    
    // Semantics:
    // - anchor_index < 0  → all notes steal from target
    // - 0 ≤ anchor_index < count → notes before anchor steal from preceding; anchor and after steal from target
    // - anchor_index ≥ count → all notes steal from preceding
    
    var result = array_create(array_length(notes_array));
    
    // ============ CONSTRAINT CASCADE: BPM-SCALED UNIT + FIT TO PRECEDING/TARGET ============
    
    var cfg = global.EMBELLISHMENT_CONFIG;
    var bpm_delta = bpm - cfg.reference_bpm;
    var gracenote_unit_ms = cfg.gracenote_unit_ms_base + (bpm_delta * cfg.bpm_scaling_factor);
    gracenote_unit_ms = clamp(gracenote_unit_ms, cfg.min_gracenote_ms, cfg.max_gracenote_ms);
    
    // Sum timing units before and at/after anchor
    var before_timing_sum = 0;
    var after_timing_sum = 0;
    var count_notes = array_length(timing_array);
    for (var i = 0; i < count_notes; i++) {
        var tval = real(timing_array[i]);
        if (anchor_index < 0) {
            // All notes steal from target
            after_timing_sum += tval;
        } else if (anchor_index >= count_notes) {
            // All notes steal from preceding
            before_timing_sum += tval;
        } else if (i < anchor_index) {
            before_timing_sum += tval;
        } else {
            after_timing_sum += tval;
        }
    }
    
    // Fit unit to available preceding duration
    if (before_timing_sum > 0 && preceding_duration_ms > 0) {
        var required_before_ms = before_timing_sum * gracenote_unit_ms;
        if (required_before_ms > preceding_duration_ms) {
            gracenote_unit_ms = preceding_duration_ms / before_timing_sum;
        }
    }
    
    // Fit unit to available target duration (with optional max percent cap)
    if (after_timing_sum > 0 && target_duration_ms > 0) {
        var required_after_ms = after_timing_sum * gracenote_unit_ms;
        var max_after_ms = cfg.max_emb_percent * target_duration_ms;
        if (required_after_ms > target_duration_ms) {
            gracenote_unit_ms = target_duration_ms / after_timing_sum;
        }
        if (required_after_ms > max_after_ms) {
            gracenote_unit_ms = min(gracenote_unit_ms, max_after_ms / after_timing_sum);
        }
    }
    
    // Build result durations: each note gets timing_val * unit
    for (var i = 0; i < array_length(notes_array); i++) {
        var note = string_trim(notes_array[i]);
        var timing_val = real(timing_array[i]);
        var duration = timing_val * gracenote_unit_ms;
        result[i] = { note: note, duration_ms: duration };
    }
    
    return result;
}