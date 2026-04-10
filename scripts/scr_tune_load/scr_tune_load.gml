// scr_tune_load — Tune JSON loader with validation and remediation
// Purpose: Read, validate, and remediate tune JSON files, then populate `obj_tune`.
// 
// Expected JSON structure:
// {
//   "tune": { title, tempo_default, default_unit_ms, ... },
//   "performance": { channel, instrument_midi_note_base, ... },
//   "metronome": { enabled, beats_per_bar, ... },
//   "events": [ { type, letter, total_units, ... }, ... ]
// }

/// @function scr_tune_load_json(_filename)
/// @description Main entry point: Parse, validate, remediate, and load a tune.
/// @returns bool - true if load successful, false otherwise

function scr_tune_load_json(_filename) {
    show_debug_message("=== Loading tune: " + string(_filename) + " ===");
    
    // Step 1: Parse JSON file
    var raw_data = scr_tune_parse_json_file(_filename);
    if (raw_data == undefined) {
        return false;
    }
    
    // Step 2: Validate and remediate structure
    var validation = scr_tune_validate_and_remediate(raw_data, _filename);
    if (!validation.valid) {
        show_debug_message("ERROR: Tune validation failed");
        for (var i = 0; i < array_length(validation.errors); i++) {
            show_debug_message("  - " + validation.errors[i]);
        }
        return false;
    }
    
    // Step 3: Load into global.tune
    scr_tune_load_into_global(validation.data, _filename);
    show_debug_message("Tune loaded successfully");
    return true;
}

/// @function scr_tune_parse_json_file(_filename)
/// @description Parse JSON file and return the parsed data struct.
/// @returns struct or undefined if file cannot be read

function scr_tune_parse_json_file(_filename) {
    var f = file_text_open_read(_filename);
    if (f < 0) {
        show_debug_message("ERROR: Failed to open file: " + string(_filename));
        return undefined;
    }
    
    var raw = "";
    while (!file_text_eof(f)) {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }
    file_text_close(f);
    
    var data = json_parse(raw);
    if (data == undefined) {
        show_debug_message("ERROR: JSON parse failed for: " + string(_filename));
        return undefined;
    }
    
    return data;
}

/// @function scr_tune_validate_and_remediate(_data, _filename)
/// @description Validate tune structure and remediate trivial errors.
/// @returns struct with fields: valid (bool), errors (array), data (remediated tune struct)

function scr_tune_validate_and_remediate(_data, _filename) {
    var result = {
        valid: false,
        errors: array_create(0),
        data: undefined
    };
    
    // Check if data is a struct
    if (!is_struct(_data)) {
        array_push(result.errors, "Root JSON must be a struct, not an array");
        return result;
    }
    
    // Extract top-level fields
    var tune_meta = _data[$ "tune"] ?? undefined;
    var events = _data[$ "events"] ?? undefined;
    var perf = _data[$ "performance"] ?? undefined;
    var metronome = _data[$ "metronome"] ?? undefined;
    
    // Validate required fields
    if (tune_meta == undefined || !is_struct(tune_meta)) {
        array_push(result.errors, "Missing or invalid 'tune' struct");
    }
    if (events == undefined || !is_array(events)) {
        array_push(result.errors, "Missing or invalid 'events' array");
    }
    if (perf == undefined || !is_struct(perf)) {
        array_push(result.errors, "Missing or invalid 'performance' struct");
    }
    
    if (array_length(result.errors) > 0) {
        return result;
    }
    
    // Remediate trivial issues
    // If title is missing, derive from filename
    if (!variable_struct_exists(tune_meta, "title") || tune_meta.title == "") {
        var title = scr_tune_extract_filename_base(_filename);
        tune_meta.title = title;
        show_debug_message("  Remediated: Derived title from filename = '" + title + "'");
    }
    
    // Return validated and remediated data
    result.valid = true;
    result.data = {
        tune_metadata: tune_meta,
        performance: perf,
        metronome: metronome ?? {},  // Optional, default to empty struct
        events: events
    };
    
    show_debug_message("  Validation passed: " + string(array_length(events)) + " events, title '" + tune_meta.title + "'");
    return result;
}

/// @function scr_tune_load_into_global(_tune_data, _filename)
/// @description Store validated tune data into global.tune instance.

function scr_tune_load_into_global(_tune_data, _filename) {
    if (!instance_exists(global.tune)) {
        show_debug_message("ERROR: obj_tune instance does not exist!");
        return;
    }
    
    global.tune.tune_data.tune_metadata = _tune_data.tune_metadata;
    global.tune.tune_data.performance = _tune_data.performance;
    global.tune.tune_data.metronome = _tune_data.metronome;
    global.tune.tune_data.events = _tune_data.events;
    global.tune.tune_data.event_count = array_length(_tune_data.events);
    global.tune.tune_data.is_loaded = true;
    global.tune.tune_data.filename = _filename;
    
    show_debug_message("  Stored into obj_tune:");
    show_debug_message("    Events: " + string(array_length(global.tune.tune_data.events)));
    show_debug_message("    Title: " + string(global.tune.tune_data.tune_metadata.title));
}

/// @function scr_tune_extract_filename_base(_filepath)
/// @description Extract filename without path and extension.
/// @returns string

function scr_tune_extract_filename_base(_filepath) {
    var lastSlash = 1;
    for (var i = 1; i <= string_length(_filepath); i++) {
        if (string_copy(_filepath, i, 1) == "/" || string_copy(_filepath, i, 1) == "\\") {
            lastSlash = i + 1;
        }
    }
    var base = string_copy(_filepath, lastSlash, string_length(_filepath) - lastSlash + 1);
    return string_replace(base, ".json", "");
}

/// @function scr_tune_load_to_struct(_filename)
/// @description Load and validate a tune JSON file, returning a lightweight struct
///              compatible with scr_preprocess_tune and metronome_generate_events.
///              Does NOT write to global.tune — safe to call for multiple tunes.
/// @param _filename  Path to tune JSON (e.g. "tunes/Scotland_The_Brave.json")
/// @returns struct { tune_data: { tune_metadata, performance, metronome, events, event_count, is_loaded, filename } }
///          or undefined on failure.

function scr_tune_load_to_struct(_filename) {
    show_debug_message("=== scr_tune_load_to_struct: " + string(_filename) + " ===");

    var raw_data = scr_tune_parse_json_file(_filename);
    if (is_undefined(raw_data)) {
        show_debug_message("  ERROR: Could not parse file");
        return undefined;
    }

    var validation = scr_tune_validate_and_remediate(raw_data, _filename);
    if (!validation.valid) {
        show_debug_message("  ERROR: Validation failed");
        for (var i = 0; i < array_length(validation.errors); i++) {
            show_debug_message("    - " + validation.errors[i]);
        }
        return undefined;
    }

    var d = validation.data;
    return {
        tune_data: {
            tune_metadata: d.tune_metadata,
            performance:   d.performance,
            metronome:     d.metronome,
            events:        d.events,
            event_count:   array_length(d.events),
            is_loaded:     true,
            filename:      _filename
        }
    };
}
