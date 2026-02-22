
// scr_event_log — Playback event history logging & analysis
// Purpose: Track all MIDI events during playback (game, player, metronome) for debugging and analysis.
// Stores expected vs actual timing, beat context, and embellishment metadata.
// Key functions:
//   - event_history_add(_event_struct) — Log a new event
//   - event_history_clear() — Clear all history (call before each tune)
//   - event_history_get_recent(_count) — Get last N events (for UI display)
//   - event_history_export_csv(_filename) — Export history to CSV for analysis

/// ============ EVENT HISTORY GLOBAL INITIALIZATION ============
/// Unbounded array that grows during playback. Will be replaced with circular buffer if needed.
if (!variable_global_exists("EVENT_HISTORY")) {
    global.EVENT_HISTORY = array_create(0);
}
if (!variable_global_exists("EVENT_HISTORY_ENABLED")) {
    global.EVENT_HISTORY_ENABLED = true;
}
if (!variable_global_exists("EVENT_HISTORY_AUTO_EXPORT")) {
    global.EVENT_HISTORY_AUTO_EXPORT = true;
}
if (!variable_global_exists("EVENT_HISTORY_EXPORTED")) {
    global.EVENT_HISTORY_EXPORTED = false;
}

/// @function event_history_add(_event_struct)
/// @description Add a new event to the history log.
/// @param _event_struct Struct with timing, note, source, and context data
/// @returns (none)
/// 
/// Expected struct format:
/// {
///     timestamp_ms, expected_time_ms, actual_time_ms, delta_ms,
///     measure, beat, beat_fraction,
///     event_type, source,
///     note_midi, note_letter, velocity, channel,
///     tune_name, event_id, is_embellishment, embellishment_name,
///     timing_quality
/// }

function event_history_add(_event_struct) {
    if (variable_global_exists("EVENT_HISTORY_ENABLED") && !global.EVENT_HISTORY_ENABLED) {
        return;
    }
    array_push(global.EVENT_HISTORY, _event_struct);
    
    // Optional: Log to debug output if needed for real-time monitoring
    // show_debug_message("EVENT_LOG: " + string(_event_struct));
}

/// @function event_history_clear()
/// @description Clear all logged events. Call before starting a new tune playback.

function event_history_clear() {
    global.EVENT_HISTORY = array_create(0);
    global.EVENT_HISTORY_EXPORTED = false;
    show_debug_message("✓ Event history cleared");
}

/// @function event_history_get_recent(_count)
/// @description Retrieve the most recent N events from history.
/// @param _count Number of events to retrieve (e.g., 10 for last 10 events)
/// @returns Array of event structs (or empty array if history is shorter than _count)

function event_history_get_recent(_count) {
    var history_length = array_length(global.EVENT_HISTORY);
    var start_index = max(0, history_length - _count);
    var recent = array_create(0);
    
    for (var i = start_index; i < history_length; i++) {
        array_push(recent, global.EVENT_HISTORY[i]);
    }
    
    return recent;
}

/// @function event_history_pad2(_value)
/// @description Zero-pad a number to two digits.
function event_history_pad2(_value) {
    var s = string(_value);
    return (string_length(s) < 2) ? ("0" + s) : s;
}

/// @function event_history_format_timestamp()
/// @description Return a YYYYMMDD-HHMMSS timestamp string.
function event_history_format_timestamp() {
    var dt = date_current_datetime();
    var year_str = string(date_get_year(dt));
    var month_str = event_history_pad2(date_get_month(dt));
    var day_str = event_history_pad2(date_get_day(dt));
    var hour_str = event_history_pad2(date_get_hour(dt));
    var minute_str = event_history_pad2(date_get_minute(dt));
    var second_str = event_history_pad2(date_get_second(dt));
    return year_str + month_str + day_str + "-" + hour_str + minute_str + second_str;
}

/// @function event_history_sanitize_name(_name)
/// @description Replace characters not safe for filenames with underscores.
function event_history_sanitize_name(_name) {
    var safe = string(_name);
    safe = string_replace_all(safe, " ", "_");
    safe = string_replace_all(safe, "/", "_");
    safe = string_replace_all(safe, "\\", "_");
    safe = string_replace_all(safe, ":", "_");
    safe = string_replace_all(safe, "*", "_");
    safe = string_replace_all(safe, "?", "_");
    safe = string_replace_all(safe, "\"", "_");
    safe = string_replace_all(safe, "<", "_");
    safe = string_replace_all(safe, ">", "_");
    safe = string_replace_all(safe, "|", "_");
    return safe;
}

/// @function event_history_get_tune_title()
/// @description Resolve the tune title from metadata when available.
function event_history_get_tune_title() {
    var title = "";
    if (instance_exists(obj_tune)) {
        var tune_data = obj_tune.tune_data;
        if (is_struct(tune_data) && variable_struct_exists(tune_data, "tune_metadata")) {
            var meta = tune_data.tune_metadata;
            if (is_struct(meta) && variable_struct_exists(meta, "title") && meta.title != "") {
                title = meta.title;
            }
        }
        if (title == "" && is_struct(tune_data) && variable_struct_exists(tune_data, "filename")) {
            title = tune_data.filename;
        }
    }
    if (title == "" && variable_global_exists("current_tune_name")) {
        title = string(global.current_tune_name);
    }
    if (title == "") {
        title = "unknown";
    }
    return title;
}

/// @function event_history_clean_tune_name(_title)
/// @description Clean a tune title for folder naming.
function event_history_clean_tune_name(_title) {
    var result = string(_title);
    var invalid_chars = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"];
    for (var i = 0; i < array_length(invalid_chars); i++) {
        result = string_replace_all(result, invalid_chars[i], "");
    }
    result = string_replace_all(result, " ", "");
    if (string_length(result) >= 3) {
        var lower = string_lower(result);
        if (string_copy(lower, 1, 3) == "the") {
            result = string_delete(result, 1, 3);
        }
    }
    return result;
}

/// @function event_history_enrich(_events)
/// @description Create a derived copy of events with enrichment (note letters, measure/beat forward-fill, etc.)
/// @param {array} _events Raw event history array
/// @returns Array of enriched event structs

function event_history_enrich(_events) {
    var enriched = array_create(0);
    var current_measure = 0;
    var current_beat = 0;
    var current_beat_fraction = 0;
    
    for (var i = 0; i < array_length(_events); i++) {
        var ev = _events[i];
        var ev_type = struct_get(ev, "event_type") ?? "unknown";
        var is_marker = (ev_type == "marker" || string_pos("marker_", string(ev_type)) == 1);
        var ev_source = struct_get(ev, "source") ?? "unknown";
        
        // Track measure/beat context from markers (ignore count-in markers)
        if (is_marker) {
            var marker_type = struct_get(ev, "marker_type") ?? "";
            if (marker_type != "countin_beat") {
                var m = struct_get(ev, "measure") ?? 0;
                var b = struct_get(ev, "beat") ?? 0;
                var bf = struct_get(ev, "beat_fraction") ?? 0;
                if (m != 0) current_measure = m;
                if (b != 0) current_beat = b;
                if (bf != 0) current_beat_fraction = bf;
            }
        }
        
        // Forward-fill measure/beat from most recent marker
        var measure = struct_get(ev, "measure") ?? 0;
        var beat = struct_get(ev, "beat") ?? 0;
        var beat_fraction = struct_get(ev, "beat_fraction") ?? 0;
        if (measure == 0 && current_measure != 0) measure = current_measure;
        if (beat == 0 && current_beat != 0) beat = current_beat;
        if (beat_fraction == 0 && current_beat_fraction != 0) beat_fraction = current_beat_fraction;
        
        // Derive note_letter from note_midi
        var note_midi = struct_get(ev, "note_midi") ?? 0;
        var note_channel = struct_get(ev, "channel") ?? -1;
        var note_letter = "";
        if (note_midi > 0) {
            note_letter = midi_to_letter(note_midi, note_channel);
        }
        
        // Derive timing_quality based on source
        var timing_quality = (ev_source == "game") ? "on_time" : "n/a";
        
        var enriched_ev = event_history_create_event(
            struct_get(ev, "timestamp_ms") ?? 0,
            struct_get(ev, "expected_time_ms") ?? 0,
            struct_get(ev, "actual_time_ms") ?? 0,
            struct_get(ev, "delta_ms") ?? 0,
            measure,
            beat,
            beat_fraction,
            ev_type,
            ev_source,
            note_midi,
            note_letter,
            struct_get(ev, "velocity") ?? 0,
            struct_get(ev, "channel") ?? 0,
            struct_get(ev, "tune_name") ?? "unknown",
            struct_get(ev, "event_id") ?? 0,
            false,  // is_embellishment (not tracked in raw log yet)
            "",     // embellishment_name (not tracked in raw log yet)
            timing_quality
        );
        
        array_push(enriched, enriched_ev);
    }
    
    return enriched;
}

/// @function event_history_export_csv(_filename_or_path)
/// @description Write entire event history to a CSV file.
/// @param _filename_or_path Filename ("event_history.csv") or full path ("datafiles/...")
/// @returns (none)

function event_history_export_csv(_filename_or_path) {
    var filepath = _filename_or_path;
    if (string_pos("datafiles/", filepath) != 1) {
        filepath = "datafiles/" + filepath;
    }
    var file = file_text_open_write(filepath);
    
    if (file == -1) {
        show_debug_message("ERROR: Could not open file for writing: " + filepath);
        return;
    }
    
    // Write header
	file_text_write_string(file, "timestamp_ms,expected_ms,actual_ms,delta_ms,measure,beat,beat_frac,type,source,note_midi,note_letter,velocity,channel,tune,event_id,is_embellishment,embellishment,timing_quality\n");
    // Enrich events before export (derive note_letter, forward-fill measure/beat)
    var export_events = event_history_enrich(global.EVENT_HISTORY);
    var event_count = array_length(export_events);
    
    // Find the first note_on from the game channel (channel 2 for chanter)
    // This is the actual start of the tune being performed
    var first_game_note_time = -1;
    for (var i = 0; i < event_count; i++) {
        var ev = export_events[i];
        var ev_type = struct_get(ev, "event_type");
        var ev_channel = struct_get(ev, "channel");
        var ev_timestamp = struct_get(ev, "timestamp_ms");
        
        // Found first game note_on on chanter channel
        if (ev_type == "note_on" && ev_channel == 2) {
            first_game_note_time = ev_timestamp;
            show_debug_message("✓ Found first game note at timestamp " + string(first_game_note_time) + "ms");
            break;
        }
    }
    
    // Calculate start point: include 100ms buffer before first game note (for early player attempts)
    var buffer_ms = 100;
    var export_start_time = (first_game_note_time >= 0) ? (first_game_note_time - buffer_ms) : 0;
    
    // Find the first event at or after this start time
    var start_index = 0;
    for (var i = 0; i < event_count; i++) {
        var ev = export_events[i];
        var ev_timestamp = struct_get(ev, "timestamp_ms");
        if (ev_timestamp >= export_start_time) {
            start_index = i;
            show_debug_message("✓ Export: Starting from index " + string(start_index) + " (timestamp " + string(ev_timestamp) + "ms, " + string(buffer_ms) + "ms before first game note)");
            break;
        }
    }
    
    for (var i = start_index; i < event_count; i++) {
        var ev = export_events[i];
        
        // Skip count-in markers (negative measures only)
        var measure = struct_get(ev, "measure");
        if (measure < 0) { continue; }

        var timestamp_ms = struct_get(ev, "timestamp_ms");
        var expected_time_ms = struct_get(ev, "expected_time_ms");
        var actual_time_ms = struct_get(ev, "actual_time_ms");
        var delta_ms = struct_get(ev, "delta_ms");
        var beat = struct_get(ev, "beat");
        var beat_fraction = struct_get(ev, "beat_fraction");
        var ev_type = struct_get(ev, "event_type");
        var ev_source = struct_get(ev, "source");
        var note_midi = struct_get(ev, "note_midi");
        var note_letter = struct_get(ev, "note_letter");
        var velocity = struct_get(ev, "velocity");
        var ev_channel = struct_get(ev, "channel");
        var tune_name = struct_get(ev, "tune_name");
        var event_id = struct_get(ev, "event_id");
        var is_embellishment = struct_get(ev, "is_embellishment");
        var embellishment_name = struct_get(ev, "embellishment_name");
        var timing_quality = struct_get(ev, "timing_quality");
        
        var line = string(timestamp_ms) + ","
            + string(expected_time_ms) + ","
            + string(actual_time_ms) + ","
            + string(delta_ms) + ","
            + string(measure) + ","
            + string(beat) + ","
            + string(beat_fraction) + ","
            + string(ev_type) + ","
            + string(ev_source) + ","
            + string(note_midi) + ","
            + string(note_letter) + ","
            + string(velocity) + ","
            + string(ev_channel) + ","
            + string(tune_name) + ","
            + string(event_id) + ","
            + string(is_embellishment) + ","
            + string(embellishment_name) + ","
            + string(timing_quality);
        
        file_text_write_string(file, line + "\n");
    }
    
    file_text_close(file);
    show_debug_message("✓ Exported " + string(event_count) + " events to: " + filepath);
}

/// @function event_history_create_event(...)
/// @description Helper to build a properly-structured event. Used by callbacks.
/// @returns Struct with all 17 required fields

function event_history_create_event(
    _timestamp_ms, _expected_time_ms, _actual_time_ms, _delta_ms,
    _measure, _beat, _beat_fraction,
    _event_type, _source,
    _note_midi, _note_letter, _velocity, _channel,
    _tune_name, _event_id, _is_embellishment, _embellishment_name,
    _timing_quality
) {
    return {
        timestamp_ms: _timestamp_ms,
        expected_time_ms: _expected_time_ms,
        actual_time_ms: _actual_time_ms,
        delta_ms: _delta_ms,
        measure: _measure,
        beat: _beat,
        beat_fraction: _beat_fraction,
        event_type: _event_type,
        source: _source,
        note_midi: _note_midi,
        note_letter: _note_letter,
        velocity: _velocity,
        channel: _channel,
        tune_name: _tune_name,
        event_id: _event_id,
        is_embellishment: _is_embellishment,
        embellishment_name: _embellishment_name,
        timing_quality: _timing_quality
    };
}