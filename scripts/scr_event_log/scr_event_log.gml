
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
    array_push(global.EVENT_HISTORY, _event_struct);
    
    // Optional: Log to debug output if needed for real-time monitoring
    // show_debug_message("EVENT_LOG: " + string(_event_struct));
}

/// @function event_history_clear()
/// @description Clear all logged events. Call before starting a new tune playback.

function event_history_clear() {
    global.EVENT_HISTORY = array_create(0);
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

/// @function event_history_export_csv(_filename)
/// @description Write entire event history to a CSV file in datafiles folder.
/// @param _filename Filename (e.g., "event_history_test.csv")
/// @returns (none) — Writes to C:\...\datafiles\{_filename}

function event_history_export_csv(_filename) {
    var file = file_text_open_write("datafiles/" + _filename);
    
    if (file == -1) {
        show_debug_message("ERROR: Could not open file for writing: " + _filename);
        return;
    }
    
    // Write header
	file_text_write_string(file, "timestamp_ms,expected_ms,actual_ms,delta_ms,measure,beat,beat_frac,type,source,note_midi,note_letter,velocity,channel,tune,event_id,is_embellishment,embellishment,timing_quality\n");
    // Write events
    var event_count = array_length(global.EVENT_HISTORY);
    for (var i = 0; i < event_count; i++) {
        var ev = global.EVENT_HISTORY[i];
        
        var line = string(ev.timestamp_ms) + ","
            + string(ev.expected_time_ms) + ","
            + string(ev.actual_time_ms) + ","
            + string(ev.delta_ms) + ","
            + string(ev.measure) + ","
            + string(ev.beat) + ","
            + string(ev.beat_fraction) + ","
            + ev.event_type + ","
            + ev.source + ","
            + string(ev.note_midi) + ","
            + ev.note_letter + ","
            + string(ev.velocity) + ","
            + string(ev.channel) + ","
            + ev.tune_name + ","
            + string(ev.event_id) + ","
            + string(ev.is_embellishment) + ","
            + ev.embellishment_name + ","
            + ev.timing_quality;
        
        file_text_write_string(file, line + "\n");
    }
    
    file_text_close(file);
    show_debug_message("✓ Exported " + string(event_count) + " events to: datafiles/" + _filename);
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