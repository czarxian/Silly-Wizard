
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
if (!variable_global_exists("EVENT_RUNTIME_PLAYER")) {
    global.EVENT_RUNTIME_PLAYER = array_create(0);
}
if (!variable_global_exists("EVENT_RUNTIME_PLANNED")) {
    global.EVENT_RUNTIME_PLANNED = array_create(0);
}
if (!variable_global_exists("EVENT_HISTORY_ENABLED")) {
    global.EVENT_HISTORY_ENABLED = true;
}
if (!variable_global_exists("EVENT_RUNTIME_CAPTURE_ENABLED")) {
    global.EVENT_RUNTIME_CAPTURE_ENABLED = true;
}
if (!variable_global_exists("EVENT_HISTORY_AUTO_EXPORT")) {
    global.EVENT_HISTORY_AUTO_EXPORT = false;
}
if (!variable_global_exists("EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS")) {
    global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS = true;
}
if (!variable_global_exists("EVENT_HISTORY_EXPORTED")) {
    global.EVENT_HISTORY_EXPORTED = false;
}
if (!variable_global_exists("EVENT_HISTORY_LIBRARY_UPDATED")) {
    global.EVENT_HISTORY_LIBRARY_UPDATED = false;
}
if (!variable_global_exists("current_player_id")) {
    global.current_player_id = "player_1";
}
if (!variable_global_exists("PERF_BENCHMARK_POWER_MODE_LABEL")) {
    global.PERF_BENCHMARK_POWER_MODE_LABEL = "unspecified";
}
if (!variable_global_exists("PERF_BENCHMARK_MIDI_ACTIVITY_LABEL")) {
    global.PERF_BENCHMARK_MIDI_ACTIVITY_LABEL = "unknown";
}
if (!variable_global_exists("PERF_BENCHMARK_NOTES")) {
    global.PERF_BENCHMARK_NOTES = "";
}

/// @function event_history_add(_event_struct)
/// @description Add a new event to the history log.
/// @param _event_struct Struct with timing, note, source, and context data
/// @returns (none)
/// @reads global.EVENT_HISTORY_ENABLED, global.loop_runtime_active, global.loop_runtime_current_iteration
/// @writes global.EVENT_HISTORY
/// @callers MIDI_process_messages
/// 
/// Expected struct format:
/// {
///     timestamp_ms, expected_time_ms, actual_time_ms, delta_ms,
///     measure, beat, beat_fraction,
///     event_type, source,
///     note_midi, note_letter, velocity, channel,
///     tune_name, event_id, is_embellishment, embellishment_name,
///     timing_quality,
///     canonical_time_ms, audio_target_time_ms, visual_target_time_ms, input_aligned_time_ms,
///     audio_offset_ms, visual_offset_ms, input_offset_ms, score_offset_ms
/// }

function event_history_add(_event_struct) {
    if (variable_global_exists("EVENT_HISTORY_ENABLED") && !global.EVENT_HISTORY_ENABLED) {
        return;
    }

    if (is_struct(_event_struct)
        && !variable_struct_exists(_event_struct, "loop_iteration")
        && variable_global_exists("loop_runtime_active")
        && global.loop_runtime_active) {
        var loop_iter = variable_global_exists("loop_runtime_current_iteration")
            ? floor(real(global.loop_runtime_current_iteration))
            : 0;
        variable_struct_set(_event_struct, "loop_iteration", max(0, loop_iter));
    }

    array_push(global.EVENT_HISTORY, _event_struct);
    
    // Optional: Log to debug output if needed for real-time monitoring
    // show_debug_message("EVENT_LOG: " + string(_event_struct));
}

/// @function event_runtime_clear()
/// @description Clear the minimal runtime player/planned event sidecar stores.
/// @reads global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED
/// @writes global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED
/// @callers event_history_clear
function event_runtime_clear() {
    global.EVENT_RUNTIME_PLAYER = array_create(0);
    global.EVENT_RUNTIME_PLANNED = array_create(0);
}

/// @function event_runtime_capture_player(_event_type, _timestamp_ms, _note_midi, _channel, _velocity, _loop_iteration)
/// @description Append a minimal player-input event record for later legacy history reconstruction/export.
/// @param {string} _event_type Player MIDI event type.
/// @param {real} _timestamp_ms Normalized capture timestamp.
/// @param {real} _note_midi Normalized MIDI note value.
/// @param {real} _channel MIDI channel.
/// @param {real} _velocity MIDI velocity.
/// @param {real} [_loop_iteration] Optional loop iteration override.
/// @reads global.EVENT_RUNTIME_CAPTURE_ENABLED, global.loop_runtime_active, global.loop_runtime_current_iteration
/// @writes global.EVENT_RUNTIME_PLAYER
/// @callers MIDI_process_messages
function event_runtime_capture_player(_event_type, _timestamp_ms, _note_midi, _channel, _velocity, _loop_iteration = undefined) {
    if (variable_global_exists("EVENT_RUNTIME_CAPTURE_ENABLED") && !global.EVENT_RUNTIME_CAPTURE_ENABLED) {
        return;
    }

    var loop_iteration = is_undefined(_loop_iteration)
        ? ((variable_global_exists("loop_runtime_active") && global.loop_runtime_active)
            ? floor(real(global.loop_runtime_current_iteration ?? 0))
            : 0)
        : floor(real(_loop_iteration));

    array_push(global.EVENT_RUNTIME_PLAYER, {
        event_type: string(_event_type ?? "unknown"),
        timestamp_ms: real(_timestamp_ms),
        note_midi: real(_note_midi),
        channel: real(_channel),
        velocity: real(_velocity),
        loop_iteration: max(0, loop_iteration)
    });
}

/// @function event_runtime_capture_planned(_event_id, _actual_time_ms, _loop_iteration)
/// @description Append a minimal planned-event dispatch record for later legacy history reconstruction/export.
/// @param {real} _event_id Stable playback event identifier.
/// @param {real} _actual_time_ms Actual dispatch timestamp.
/// @param {real} [_loop_iteration] Optional loop iteration override.
/// @reads global.EVENT_RUNTIME_CAPTURE_ENABLED, global.loop_runtime_active, global.loop_runtime_current_iteration
/// @writes global.EVENT_RUNTIME_PLANNED
/// @callers tune_scheduler_process_deferred
function event_runtime_capture_planned(_event_id, _actual_time_ms, _loop_iteration = undefined) {
    if (variable_global_exists("EVENT_RUNTIME_CAPTURE_ENABLED") && !global.EVENT_RUNTIME_CAPTURE_ENABLED) {
        return;
    }

    var loop_iteration = is_undefined(_loop_iteration)
        ? ((variable_global_exists("loop_runtime_active") && global.loop_runtime_active)
            ? floor(real(global.loop_runtime_current_iteration ?? 0))
            : 0)
        : floor(real(_loop_iteration));

    array_push(global.EVENT_RUNTIME_PLANNED, {
        event_id: real(_event_id),
        actual_time_ms: real(_actual_time_ms),
        loop_iteration: max(0, loop_iteration)
    });
}

/// @function event_runtime_playback_key(_event_id, _loop_iteration)
/// @description Build a stable composite key for planned runtime records and playback-event lookups.
/// @param {real} _event_id Playback event id.
/// @param {real} _loop_iteration Loop iteration number.
/// @returns {string} Composite lookup key.
function event_runtime_playback_key(_event_id, _loop_iteration) {
    return string(floor(real(_loop_iteration))) + ":" + string(floor(real(_event_id)));
}

/// @function event_runtime_get_planned_source_events()
/// @description Resolve the active playback-event table used for planned-event reconstruction.
/// @returns {array} Playback events array or empty array.
/// @reads global.playback_events_active, global.playback_events
function event_runtime_get_planned_source_events() {
    if (variable_global_exists("playback_events_active")
        && is_array(global.playback_events_active)
        && array_length(global.playback_events_active) > 0) {
        return global.playback_events_active;
    }
    if (variable_global_exists("playback_events")
        && is_array(global.playback_events)
        && array_length(global.playback_events) > 0) {
        return global.playback_events;
    }
    return array_create(0);
}

/// @function event_history_build_from_runtime()
/// @description Rebuild a legacy-style event history array from minimal runtime player/planned sidecar stores.
/// @returns {array} Legacy event-history style array sorted by timestamp.
/// @reads global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED, global.current_tune_name, global.timeline_cfg, global.MIDI_chanter, global.METRONOME_CONFIG, global.playback_events_active, global.playback_events
/// @callers future export/scoring compatibility path
function event_history_build_from_runtime() {
    var rebuilt_events = array_create(0);

    var audio_offset_ms = 0;
    var visual_offset_ms = 0;
    var input_offset_ms = 0;
    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        audio_offset_ms = variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")
            ? real(variable_struct_get(global.timeline_cfg, "audio_output_offset_ms"))
            : 0;
        visual_offset_ms = variable_struct_exists(global.timeline_cfg, "visual_alignment_offset_ms")
            ? real(variable_struct_get(global.timeline_cfg, "visual_alignment_offset_ms"))
            : 0;
        input_offset_ms = variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")
            ? real(variable_struct_get(global.timeline_cfg, "input_capture_offset_ms"))
            : 0;
    }

    var tune_name_local = variable_global_exists("current_tune_name") ? string(global.current_tune_name) : "unknown";
    var met_ch = (variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG))
        ? real(global.METRONOME_CONFIG.channel ?? 9)
        : 9;

    var planned_index = {};
    var planned_cursor = {};
    var planned_events = event_runtime_get_planned_source_events();
    var planned_count = array_length(planned_events);
    for (var i = 0; i < planned_count; i++) {
        var ev = planned_events[i];
        if (!is_struct(ev)) continue;
        var loop_iteration = floor(real(ev[$ "loop_iteration"] ?? 0));
        var event_id = floor(real(ev[$ "event_id"] ?? 0));
        var lookup_key = event_runtime_playback_key(event_id, loop_iteration);
        if (!variable_struct_exists(planned_index, lookup_key) || !is_array(planned_index[$ lookup_key])) {
            planned_index[$ lookup_key] = [];
            planned_cursor[$ lookup_key] = 0;
        }
        var bucket = planned_index[$ lookup_key];
        array_push(bucket, ev);
        planned_index[$ lookup_key] = bucket;
    }

    if (variable_global_exists("EVENT_RUNTIME_PLANNED") && is_array(global.EVENT_RUNTIME_PLANNED)) {
        var runtime_planned = global.EVENT_RUNTIME_PLANNED;
        var runtime_planned_n = array_length(runtime_planned);
        for (var planned_i = 0; planned_i < runtime_planned_n; planned_i++) {
            var rec = runtime_planned[planned_i];
            if (!is_struct(rec)) continue;

            var loop_iteration = floor(real(rec[$ "loop_iteration"] ?? 0));
            var event_id = floor(real(rec[$ "event_id"] ?? 0));
            var lookup_key = event_runtime_playback_key(event_id, loop_iteration);
            if (!variable_struct_exists(planned_index, lookup_key)
                || !is_array(planned_index[$ lookup_key])
                || array_length(planned_index[$ lookup_key]) <= 0) {
                lookup_key = event_runtime_playback_key(event_id, 0);
            }
            if (!variable_struct_exists(planned_index, lookup_key)
                || !is_array(planned_index[$ lookup_key])
                || array_length(planned_index[$ lookup_key]) <= 0) {
                continue;
            }

            var bucket = planned_index[$ lookup_key];
            var cursor = variable_struct_exists(planned_cursor, lookup_key)
                ? floor(real(planned_cursor[$ lookup_key]))
                : 0;
            var src_idx = clamp(cursor, 0, max(0, array_length(bucket) - 1));
            var src = bucket[src_idx];
            planned_cursor[$ lookup_key] = cursor + 1;
            var ev_type = string(src[$ "type"] ?? "unknown");
            var marker_type = "";
            if (ev_type == "marker") {
                marker_type = string(src[$ "marker_type"] ?? "");
                ev_type = "marker_" + marker_type;
            }

            var note_midi = real(src[$ "note"] ?? 0);
            var channel = real(src[$ "channel"] ?? 0);
            var note_canonical = ((string(src[$ "type"] ?? "") == "note_on") || (string(src[$ "type"] ?? "") == "note_off"))
                ? chanter_midi_to_canonical(note_midi, global.MIDI_chanter ?? "default", channel)
                : "";

            var expected_time_ms = real(src[$ "time"] ?? 0);
            var actual_time_ms = real(rec[$ "actual_time_ms"] ?? expected_time_ms);
            var is_embellishment = bool(src[$ "is_embellishment"] ?? false);
            var embellishment_name = string(src[$ "embellishment_name"] ?? "");
            if (embellishment_name == "") embellishment_name = string(src[$ "embellishment"] ?? "");
            if (embellishment_name == "" && is_embellishment) {
                var emb_literal = string(src[$ "emb_literal"] ?? "");
                embellishment_name = (emb_literal != "") ? emb_literal : "embellishment";
            }

            array_push(rebuilt_events, {
                timestamp_ms: actual_time_ms,
                expected_time_ms: expected_time_ms,
                actual_time_ms: actual_time_ms,
                delta_ms: actual_time_ms - expected_time_ms,
                canonical_time_ms: expected_time_ms,
                audio_target_time_ms: expected_time_ms + audio_offset_ms,
                visual_target_time_ms: expected_time_ms + visual_offset_ms,
                input_aligned_time_ms: actual_time_ms + input_offset_ms,
                event_type: ev_type,
                source: (channel == met_ch && (string(src[$ "type"] ?? "") == "note_on" || string(src[$ "type"] ?? "") == "note_off")) ? "metronome" : "game",
                note_midi: note_midi,
                note_midi_raw: note_midi,
                note_canonical: note_canonical,
                velocity: real(src[$ "velocity"] ?? 0),
                channel: channel,
                tune_name: tune_name_local,
                event_id: event_id,
                is_embellishment: is_embellishment,
                embellishment_name: embellishment_name,
                marker_type: marker_type,
                measure: real(src[$ "measure"] ?? 0),
                beat: real(src[$ "beat"] ?? 0),
                beat_fraction: real(src[$ "beat_fraction"] ?? (src[$ "division"] ?? 0)),
                audio_output_offset_ms: audio_offset_ms,
                visual_alignment_offset_ms: visual_offset_ms,
                input_capture_offset_ms: input_offset_ms,
                loop_iteration: loop_iteration
            });
        }
    }

    if (variable_global_exists("EVENT_RUNTIME_PLAYER") && is_array(global.EVENT_RUNTIME_PLAYER)) {
        var runtime_player = global.EVENT_RUNTIME_PLAYER;
        var runtime_player_n = array_length(runtime_player);
        for (var player_i = 0; player_i < runtime_player_n; player_i++) {
            var rec = runtime_player[player_i];
            if (!is_struct(rec)) continue;

            var timestamp_ms = real(rec[$ "timestamp_ms"] ?? 0);
            var note_midi = real(rec[$ "note_midi"] ?? 0);
            var channel = real(rec[$ "channel"] ?? 0);
            var note_canonical = chanter_midi_to_canonical(note_midi, global.MIDI_chanter ?? "default", channel);

            array_push(rebuilt_events, {
                timestamp_ms: timestamp_ms,
                raw_timestamp_ms: timestamp_ms,
                normalized_time_ms: timestamp_ms,
                processing_delay_ms: 0,
                clock_source: "runtime_capture",
                expected_time_ms: 0,
                actual_time_ms: timestamp_ms,
                delta_ms: 0,
                canonical_time_ms: timestamp_ms + input_offset_ms,
                audio_target_time_ms: timestamp_ms + audio_offset_ms,
                visual_target_time_ms: timestamp_ms + visual_offset_ms,
                input_aligned_time_ms: timestamp_ms + input_offset_ms,
                event_type: string(rec[$ "event_type"] ?? "unknown"),
                source: "player",
                note_midi: note_midi,
                note_midi_raw: note_midi,
                note_canonical: note_canonical,
                velocity: real(rec[$ "velocity"] ?? 0),
                channel: channel,
                tune_name: tune_name_local,
                event_id: 0,
                is_embellishment: false,
                embellishment_name: "",
                marker_type: "",
                measure: 0,
                beat: 0,
                beat_fraction: 0,
                audio_output_offset_ms: audio_offset_ms,
                visual_alignment_offset_ms: visual_offset_ms,
                input_capture_offset_ms: input_offset_ms,
                loop_iteration: floor(real(rec[$ "loop_iteration"] ?? 0))
            });
        }
    }

    array_sort(rebuilt_events, function(a, b) {
        return real((a[$ "timestamp_ms"] ?? 0)) - real((b[$ "timestamp_ms"] ?? 0));
    });
    return rebuilt_events;
}

/// @function event_history_get_effective_events()
/// @description Return the export/scoring event stream, preferring runtime sidecar reconstruction and preserving non-runtime legacy rows.
/// @returns {array} Effective event history array.
/// @reads global.EVENT_HISTORY, global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED
/// @callers event_history_update_tune_history_index, event_history_export_summary_json, event_history_export_loop_session_json, event_history_export_csv, scoring_build_loop_iteration_scores
function event_history_get_effective_events() {
    var legacy_events = variable_global_exists("EVENT_HISTORY") && is_array(global.EVENT_HISTORY)
        ? global.EVENT_HISTORY
        : array_create(0);

    var has_runtime_player = variable_global_exists("EVENT_RUNTIME_PLAYER")
        && is_array(global.EVENT_RUNTIME_PLAYER)
        && array_length(global.EVENT_RUNTIME_PLAYER) > 0;
    var has_runtime_planned = variable_global_exists("EVENT_RUNTIME_PLANNED")
        && is_array(global.EVENT_RUNTIME_PLANNED)
        && array_length(global.EVENT_RUNTIME_PLANNED) > 0;

    if (!has_runtime_player && !has_runtime_planned) {
        return legacy_events;
    }

    var effective_events = event_history_build_from_runtime();
    for (var i = 0; i < array_length(legacy_events); i++) {
        var ev = legacy_events[i];
        if (!is_struct(ev)) continue;

        var ev_source = string(event_history_struct_get(ev, "source", ""));
        if (ev_source == "player" || ev_source == "game" || ev_source == "metronome") {
            continue;
        }

        array_push(effective_events, ev);
    }

    array_sort(effective_events, function(a, b) {
        return real((a[$ "timestamp_ms"] ?? 0)) - real((b[$ "timestamp_ms"] ?? 0));
    });
    return effective_events;
}

/// @function event_history_clear()
/// @description Clear all logged events. Call before starting a new tune playback.
/// @writes global.EVENT_HISTORY, global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED, global.EVENT_HISTORY_EXPORTED, global.EVENT_HISTORY_LIBRARY_UPDATED
/// @callers scr_button_scripts (before tune start)

function event_history_clear() {
    global.EVENT_HISTORY = array_create(0);
    event_runtime_clear();
    global.EVENT_HISTORY_EXPORTED = false;
    global.EVENT_HISTORY_LIBRARY_UPDATED = false;
    show_debug_message("✓ Event history cleared");
}

/// @function event_history_get_recent(_count)
/// @description Retrieve the most recent N events from history.
/// @param _count Number of events to retrieve (e.g., 10 for last 10 events)
/// @returns Array of event structs (or empty array if history is shorter than _count)
/// @reads global.EVENT_HISTORY
/// @callers scr_UI_scripts (event log panel display)

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
/// @reads global.current_tune_name
/// @objects obj_tune (reads tune_data.tune_metadata and tune_data.filename)
/// @callers event_history_get_export_info
function event_history_get_tune_title() {
    var title = "";
    if (instance_exists(obj_tune)) {
        var tune_data = obj_tune.tune_data;
        if (is_struct(tune_data) && variable_struct_exists(tune_data, "tune_metadata")) {
            var meta = tune_data.tune_metadata;
            var meta_title = event_history_struct_get(meta, "title", "");
            if (string(meta_title) != "") {
                title = string(meta_title);
            }
        }
        if (title == "" && is_struct(tune_data) && variable_struct_exists(tune_data, "filename")) {
            title = string(variable_struct_get(tune_data, "filename"));
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

/// @function event_history_struct_get(_struct, _key, _default)
/// @description Safely read a value from a dynamic struct.
function event_history_struct_get(_struct, _key, _default = undefined) {
    if (!is_struct(_struct)) return _default;
    if (!variable_struct_exists(_struct, _key)) return _default;
    return variable_struct_get(_struct, _key);
}

/// @function event_history_normalize_tune_filename(_filename_or_path)
/// @description Normalize a tune path to the library-relative filename when possible.
function event_history_normalize_tune_filename(_filename_or_path) {
    var path = string_trim(string(_filename_or_path ?? ""));
    if (string_length(path) <= 0) return "";

    path = string_replace_all(path, "\\", "/");
    var lower = string_lower(path);
    var markers = ["datafiles/tunes/", "tunes/"];
    if (script_exists(asset_get_index("scr_data_paths_get_category_root"))) {
        array_push(markers, string_lower(scr_data_paths_get_category_root("tunes")));
    }

    for (var i = 0; i < array_length(markers); i++) {
        var marker = markers[i];
        var pos = string_pos(marker, lower);
        if (pos > 0) {
            var start_at = pos + string_length(marker);
            return string_copy(path, start_at, string_length(path) - start_at + 1);
        }
    }

    var last_slash = 0;
    for (var j = 1; j <= string_length(path); j++) {
        if (string_copy(path, j, 1) == "/") {
            last_slash = j;
        }
    }

    if (last_slash > 0) {
        return string_copy(path, last_slash + 1, string_length(path) - last_slash);
    }

    return path;
}

/// @function event_history_make_tune_history_id(_filename_or_path)
/// @description Build a stable ID for tune-library history entries.
function event_history_make_tune_history_id(_filename_or_path) {
    var filename = event_history_normalize_tune_filename(_filename_or_path);
    if (string_length(filename) <= 0) {
        filename = string_trim(string(_filename_or_path ?? ""));
    }
    return string_lower(string_trim(filename));
}

/// @function event_history_format_play_date(_stamp)
/// @description Convert YYYYMMDD-HHMMSS timestamps into YYYY-MM-DD labels.
function event_history_format_play_date(_stamp) {
    var stamp = string_trim(string(_stamp ?? ""));
    if (string_length(stamp) >= 8 && string_pos("-", stamp) == 0) {
        return string_copy(stamp, 1, 4) + "-" + string_copy(stamp, 5, 2) + "-" + string_copy(stamp, 7, 2);
    }
    return stamp;
}

/// @function event_history_get_tune_history_index_path()
/// @description Path for the persistent tune-library history index.
function event_history_get_tune_history_index_path() {
    var perf_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
        ? scr_data_paths_get_category_root("performances")
        : "datafiles/performances/";
    return perf_root + "tune_history_index.json";
}

/// @function event_history_default_tune_history_index()
/// @description Create a default empty history index payload.
function event_history_default_tune_history_index() {
    return {
        schema_version: 1,
        export_type: "tune_history_index",
        updated_at: "",
        tunes: []
    };
}

/// @function event_history_load_tune_history_index()
/// @description Read the persistent tune-library history index if it exists.
function event_history_load_tune_history_index() {
    var filepath = event_history_get_tune_history_index_path();
    var file = file_text_open_read(filepath);
    if (file < 0) {
        return event_history_default_tune_history_index();
    }

    var raw = "";
    while (!file_text_eof(file)) {
        raw += file_text_read_string(file);
        file_text_readln(file);
    }
    file_text_close(file);

    if (string_trim(raw) == "") {
        return event_history_default_tune_history_index();
    }

    var data = undefined;
    try {
        data = json_parse(raw);
    } catch (e) {
        show_debug_message("WARNING: Could not parse tune history index: " + filepath + " - " + string(e));
        return event_history_default_tune_history_index();
    }

    var data_tunes = event_history_struct_get(data, "tunes", undefined);
    if (!is_struct(data) || !is_array(data_tunes)) {
        return event_history_default_tune_history_index();
    }

    if (!variable_struct_exists(data, "schema_version")) variable_struct_set(data, "schema_version", 1);
    if (!variable_struct_exists(data, "export_type")) variable_struct_set(data, "export_type", "tune_history_index");
    if (!variable_struct_exists(data, "updated_at")) variable_struct_set(data, "updated_at", "");
    return data;
}

/// @function event_history_store_tune_history_index(_index)
/// @description Persist the tune-library history index to disk.
function event_history_store_tune_history_index(_index) {
    if (!is_struct(_index)) return false;

    var folder = script_exists(asset_get_index("scr_data_paths_get_category_root"))
        ? scr_data_paths_get_category_root("performances")
        : "datafiles/performances/";
    if (string_copy(folder, string_length(folder), 1) == "/") {
        folder = string_copy(folder, 1, string_length(folder) - 1);
    }
    if (!directory_exists(folder)) {
        directory_create(folder);
    }

    var filepath = event_history_get_tune_history_index_path();
    var file = file_text_open_write(filepath);
    if (file < 0) {
        show_debug_message("ERROR: Could not open tune history index for writing: " + filepath);
        return false;
    }

    file_text_write_string(file, json_stringify(_index));
    file_text_close(file);
    return true;
}

/// @function event_history_is_numeric_text(_text)
/// @description Return true when text can be safely parsed as a simple real number.
function event_history_is_numeric_text(_text) {
    var text = string_trim(string(_text ?? ""));
    if (string_length(text) <= 0) return false;

    var has_digit = false;
    var dot_count = 0;
    for (var i = 1; i <= string_length(text); i++) {
        var ch = string_char_at(text, i);
        if (ch >= "0" && ch <= "9") {
            has_digit = true;
            continue;
        }
        if (ch == "." && dot_count == 0) {
            dot_count += 1;
            continue;
        }
        if (i == 1 && ch == "-") {
            continue;
        }
        return false;
    }

    return has_digit;
}

/// @function event_history_try_score_real(_value)
/// @description Parse numeric score values when possible, otherwise return undefined.
function event_history_try_score_real(_value) {
    if (is_real(_value)) {
        return real(_value);
    }

    var text = string_trim(string(_value ?? ""));
    if (!event_history_is_numeric_text(text)) {
        return undefined;
    }

    return real(text);
}

/// @function event_history_get_export_score(_export_info)
/// @description Resolve an optional score value from export metadata or future globals.
/// @reads global.scoring_last_run, global.last_score, global.run_score, global.performance_score, global.final_score, global.overall_score (first match wins)
/// @callers event_history_get_export_info, event_history_update_tune_history_index
function event_history_get_export_score(_export_info = undefined) {
    if (is_struct(_export_info)) {
        if (variable_struct_exists(_export_info, "score")) return variable_struct_get(_export_info, "score");
        if (variable_struct_exists(_export_info, "last_score")) return variable_struct_get(_export_info, "last_score");
    }

    if (variable_global_exists("scoring_last_run") && is_struct(global.scoring_last_run)) {
        if (variable_struct_exists(global.scoring_last_run, "overall_score")) {
            return real(variable_struct_get(global.scoring_last_run, "overall_score"));
        }
    }

    var global_keys = [
        "last_score",
        "run_score",
        "performance_score",
        "final_score",
        "overall_score"
    ];

    for (var i = 0; i < array_length(global_keys); i++) {
        var key = global_keys[i];
        if (variable_global_exists(key)) {
            return variable_global_get(key);
        }
    }

    return undefined;
}

/// @function event_history_get_export_info(_timestamp)
/// @description Build shared metadata for CSV and summary exports.
/// @reads global.current_tune_name, global.current_bpm, global.swing_mult, global.gracenote_override_ms, global.current_player_id, global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS, global.PERF_BENCHMARK_POWER_MODE_LABEL, global.PERF_BENCHMARK_MIDI_ACTIVITY_LABEL, global.PERF_BENCHMARK_NOTES
/// @callers event_history_export_csv, event_history_export_summary_json, event_history_export_loop_session_json
function event_history_get_export_info(_timestamp = "") {
    var tune_name = variable_global_exists("current_tune_name")
        ? string(global.current_tune_name)
        : "unknown";
    var tune_filename = event_history_normalize_tune_filename(tune_name);
    var tune_title = event_history_get_tune_title();
    var clean_tune = event_history_clean_tune_name(tune_title);
    if (clean_tune == "") {
        clean_tune = "unknown";
    }

    var bpm = variable_global_exists("current_bpm")
        ? real(global.current_bpm)
        : 120;
    var swing = variable_global_exists("swing_mult")
        ? string(global.swing_mult)
        : "0";
    var grace_override_ms = variable_global_exists("gracenote_override_ms")
        ? real(global.gracenote_override_ms)
        : 0;
    var player_key = variable_global_exists("current_player_id")
        ? string_trim(string(global.current_player_id))
        : "default";
    if (player_key == "") player_key = "default";

    var timestamp = string(_timestamp);
    if (timestamp == "") {
        timestamp = event_history_format_timestamp();
    }

    var perf_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
        ? scr_data_paths_get_category_root("performances")
        : "datafiles/performances/";
    var folder = perf_root + clean_tune;
    var base_name = clean_tune + "_" + timestamp + "_" + string(bpm) + "_" + swing + "_" + string(grace_override_ms);
    var export_include_game_events = variable_global_exists("EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS")
        ? (global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS == true)
        : true;
    var benchmark_power_mode_label = variable_global_exists("PERF_BENCHMARK_POWER_MODE_LABEL")
        ? string(global.PERF_BENCHMARK_POWER_MODE_LABEL)
        : "unspecified";
    var benchmark_midi_activity_label = variable_global_exists("PERF_BENCHMARK_MIDI_ACTIVITY_LABEL")
        ? string(global.PERF_BENCHMARK_MIDI_ACTIVITY_LABEL)
        : "unknown";
    var benchmark_notes = variable_global_exists("PERF_BENCHMARK_NOTES")
        ? string(global.PERF_BENCHMARK_NOTES)
        : "";

    return {
        tune_name: tune_name,
        tune_filename: tune_filename,
        tune_id: event_history_make_tune_history_id((tune_filename != "") ? tune_filename : tune_name),
        player_id: player_key,
        part_key: "all",
        tune_title: tune_title,
        clean_tune: clean_tune,
        timestamp: timestamp,
        bpm: bpm,
        swing: swing,
        grace_override_ms: grace_override_ms,
        export_include_game_events: export_include_game_events,
        benchmark_power_mode_label: benchmark_power_mode_label,
        benchmark_midi_activity_label: benchmark_midi_activity_label,
        benchmark_notes: benchmark_notes,
        midi_input_device_name: variable_global_exists("midi_input_device_name") ? string(global.midi_input_device_name) : "not selected",
        midi_output_device_name: variable_global_exists("midi_output_device_name") ? string(global.midi_output_device_name) : "not selected",
        midi_output_drum_device_name: variable_global_exists("midi_output_drum_name") ? string(global.midi_output_drum_name) : "not selected",
        playback_scheduler_mode: variable_global_exists("PLAYBACK_SCHEDULER_MODE") ? string(global.PLAYBACK_SCHEDULER_MODE) : "timesource",
        game_step_fps: variable_global_exists("GAME_STEP_FPS") ? real(global.GAME_STEP_FPS) : 0,
        folder: folder,
        base_name: base_name,
        csv_path: folder + "/" + base_name + ".csv",
        summary_path: folder + "/" + base_name + "_summary.json"
    };
}

/// @function event_history_update_tune_history_index(_export_info)
/// @description Update the persistent tune-library history index using the current run export metadata.
/// @reads global.EVENT_HISTORY (checks length before proceeding)
/// @callers scr_button_scripts (export at end of tune)
function event_history_update_tune_history_index(_export_info = undefined) {
    var effective_events = event_history_get_effective_events();
    if (array_length(effective_events) <= 0) {
        return false;
    }

    var export_info = is_struct(_export_info)
        ? _export_info
        : event_history_get_export_info();

    var tune_filename = string(event_history_struct_get(export_info, "tune_filename", ""));
    if (string_length(tune_filename) <= 0) {
        tune_filename = event_history_normalize_tune_filename(event_history_struct_get(export_info, "tune_name", ""));
    }

    var tune_id = string(event_history_struct_get(export_info, "tune_id", ""));
    if (string_length(tune_id) <= 0) {
        tune_id = event_history_make_tune_history_id((tune_filename != "") ? tune_filename : event_history_struct_get(export_info, "tune_name", ""));
    }

    if (string_length(tune_id) <= 0) {
        return false;
    }

    var history_index = event_history_load_tune_history_index();
    var tunes = event_history_struct_get(history_index, "tunes", []);
    var match_idx = -1;

    for (var i = 0; i < array_length(tunes); i++) {
        var entry = tunes[i];
        if (!is_struct(entry)) continue;

        var entry_id = string_lower(string_trim(string(event_history_struct_get(entry, "id", ""))));
        if (entry_id == tune_id) {
            match_idx = i;
            break;
        }

        var entry_filename = event_history_make_tune_history_id(event_history_struct_get(entry, "filename", ""));
        if (string_length(entry_filename) > 0 && entry_filename == tune_id) {
            match_idx = i;
            break;
        }
    }

    if (match_idx < 0) {
        array_push(tunes, {
            id: tune_id,
            filename: tune_filename,
            title: string(event_history_struct_get(export_info, "tune_title", "")),
            plays_count: 0,
            last_played_utc: "",
            last_play_date: "",
            last_score: "",
            best_score: "",
            last_bpm: 0,
            last_swing: "",
            last_grace_override_ms: 0,
            last_export_base_name: ""
        });
        match_idx = array_length(tunes) - 1;
    }

    var history_entry = tunes[match_idx];

    variable_struct_set(history_entry, "id", tune_id);
    if (string_length(tune_filename) > 0) variable_struct_set(history_entry, "filename", tune_filename);

    var tune_title = string_trim(string(event_history_struct_get(export_info, "tune_title", "")));
    if (string_length(tune_title) > 0) {
        variable_struct_set(history_entry, "title", tune_title);
    }

    variable_struct_set(history_entry, "plays_count", floor(max(0, real(event_history_struct_get(history_entry, "plays_count", 0)))) + 1);
    variable_struct_set(history_entry, "last_played_utc", string(event_history_struct_get(export_info, "timestamp", "")));
    variable_struct_set(history_entry, "last_play_date", event_history_format_play_date(event_history_struct_get(history_entry, "last_played_utc", "")));
    variable_struct_set(history_entry, "last_bpm", real(event_history_struct_get(export_info, "bpm", 0)));
    variable_struct_set(history_entry, "last_swing", string(event_history_struct_get(export_info, "swing", "")));
    variable_struct_set(history_entry, "last_grace_override_ms", real(event_history_struct_get(export_info, "grace_override_ms", 0)));
    variable_struct_set(history_entry, "last_export_base_name", string(event_history_struct_get(export_info, "base_name", "")));
    variable_struct_set(history_entry, "tune_name", string(event_history_struct_get(export_info, "tune_name", "")));
    variable_struct_set(history_entry, "last_player_id", string(event_history_struct_get(export_info, "player_id", "default")));

    var score_value = event_history_get_export_score(export_info);
    var score_text = string_trim(string(score_value ?? ""));
    if (string_length(score_text) > 0) {
        variable_struct_set(history_entry, "last_score", score_text);

        var score_real = event_history_try_score_real(score_value);
        var best_real = event_history_try_score_real(event_history_struct_get(history_entry, "best_score", undefined));
        if (!is_undefined(score_real)) {
            if (is_undefined(best_real) || score_real > best_real) {
                variable_struct_set(history_entry, "best_score", score_text);
            }
        } else if (string_length(string_trim(string(event_history_struct_get(history_entry, "best_score", "")))) <= 0) {
            variable_struct_set(history_entry, "best_score", score_text);
        }

        var player_key = string(event_history_struct_get(export_info, "player_id", "default"));
        var part_key = string(event_history_struct_get(export_info, "part_key", "all"));
        var bpm_key = real(event_history_struct_get(export_info, "bpm", 0));
        var swing_key = string(event_history_struct_get(export_info, "swing", ""));
        var context_key = string(tune_id) + "|" + string_lower(player_key) + "|" + string(bpm_key) + "|" + swing_key + "|" + part_key;

        var contexts = event_history_struct_get(history_entry, "contexts", []);
        if (!is_array(contexts)) contexts = [];
        var ctx_idx = -1;
        for (var ci = 0; ci < array_length(contexts); ci++) {
            var ctx = contexts[ci];
            if (!is_struct(ctx)) continue;
            if (string(event_history_struct_get(ctx, "id", "")) == context_key) {
                ctx_idx = ci;
                break;
            }
        }

        if (ctx_idx < 0) {
            array_push(contexts, {
                id: context_key,
                player_id: player_key,
                bpm: bpm_key,
                swing: swing_key,
                part_key: part_key,
                plays_count: 0,
                last_played_utc: "",
                last_score: "",
                best_score: "",
                score_sum: 0,
                avg_score: ""
            });
            ctx_idx = array_length(contexts) - 1;
        }

        var ctx_entry = contexts[ctx_idx];
        variable_struct_set(ctx_entry, "plays_count", floor(max(0, real(event_history_struct_get(ctx_entry, "plays_count", 0)))) + 1);
        variable_struct_set(ctx_entry, "last_played_utc", string(event_history_struct_get(export_info, "timestamp", "")));
        variable_struct_set(ctx_entry, "last_score", score_text);

        var ctx_score_real = event_history_try_score_real(score_value);
        var ctx_best_real = event_history_try_score_real(event_history_struct_get(ctx_entry, "best_score", undefined));
        if (!is_undefined(ctx_score_real)) {
            var prev_sum = real(event_history_struct_get(ctx_entry, "score_sum", 0));
            var next_sum = prev_sum + ctx_score_real;
            var next_count = max(1, real(event_history_struct_get(ctx_entry, "plays_count", 1)));
            variable_struct_set(ctx_entry, "score_sum", next_sum);
            variable_struct_set(ctx_entry, "avg_score", string_format(next_sum / next_count, 0, 2));

            if (is_undefined(ctx_best_real) || ctx_score_real > ctx_best_real) {
                variable_struct_set(ctx_entry, "best_score", score_text);
            }
        } else if (string_length(string_trim(string(event_history_struct_get(ctx_entry, "best_score", "")))) <= 0) {
            variable_struct_set(ctx_entry, "best_score", score_text);
        }

        contexts[ctx_idx] = ctx_entry;
        variable_struct_set(history_entry, "contexts", contexts);
    }

    tunes[match_idx] = history_entry;
    variable_struct_set(history_index, "tunes", tunes);
    variable_struct_set(history_index, "updated_at", event_history_format_timestamp());
    return event_history_store_tune_history_index(history_index);
}

/// @function event_history_build_summary_player_spans()
/// @description Build a compact per-note span array for review overlays.
/// @reads global.timeline_state (review_full_trace or player_in span arrays)
/// @callers event_history_export_summary_json
function event_history_build_summary_player_spans() {
    var spans_out = array_create(0);

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        return spans_out;
    }
    var source_spans = [];
    if (variable_struct_exists(global.timeline_state, "review_full_trace") && is_array(global.timeline_state.review_full_trace)
        && array_length(global.timeline_state.review_full_trace) > 0) {
        source_spans = global.timeline_state.review_full_trace;
    } else if (variable_struct_exists(global.timeline_state, "player_in") && is_array(global.timeline_state.player_in)) {
        source_spans = global.timeline_state.player_in;
    } else {
        return spans_out;
    }

    var n_spans = array_length(source_spans);
    for (var i = 0; i < n_spans; i++) {
        var span = source_spans[i];
        if (!is_struct(span)) continue;

        var start_ms = real(span.start_ms ?? 0);
        var end_ms = max(start_ms, real(span.end_ms ?? start_ms));
        var note_canonical = string(span.note_canonical ?? "");
        var note_midi = real(span.note_midi ?? -1);
        var channel = real(span.channel ?? -1);
        var lane_idx = gv_note_to_lane_index(note_canonical, note_midi, channel);
        if (lane_idx < 0) continue;

        array_push(spans_out, {
            start_ms: start_ms,
            end_ms: end_ms,
            dur_ms: max(0, real(span.dur_ms ?? (end_ms - start_ms))),
            note_canonical: note_canonical,
            note_midi: note_midi,
            channel: channel,
            lane_idx: lane_idx
        });
    }

    return spans_out;
}

/// @function event_history_build_structure_debug_snapshot(_entry_limit, _beat_limit)
/// @description Capture timeline structure state (measure nav, structural starts, beat labels) for troubleshooting and include it in run summary exports.
/// @param {real} _entry_limit  Max number of nav/structure entries to record.
/// @param {real} _beat_limit   Max number of beat-lane entries to record.
/// @returns {struct}  Snapshot struct safe for JSON export.
/// @reads  global.timeline_state.measure_nav_entries, global.timeline_state.structural_measure_starts, global.timeline_beat_positions, global.playback_context
function event_history_build_structure_debug_snapshot(_entry_limit = 80, _beat_limit = 120) {
    var entry_limit = max(1, floor(real(_entry_limit)));
    var beat_limit = max(1, floor(real(_beat_limit)));

    var out = {
        created_at: event_history_format_timestamp(),
        has_timeline_state: false,
        playback_context_mode: "",
        playback_context_active_segment: -1,
        playback_context_segment_count: 0,
        measure_nav_count: 0,
        structural_start_count: 0,
        beat_positions_count: 0,
        measure_nav_entries_head: [],
        structural_measure_starts_head: [],
        beat_positions_head: [],
        beat_labels_head: []
    };

    if (variable_global_exists("playback_context") && is_struct(global.playback_context)) {
        out.playback_context_mode = string(event_history_struct_get(global.playback_context, "mode", ""));
        out.playback_context_active_segment = floor(real(event_history_struct_get(global.playback_context, "active_segment", -1)));
        var segs = event_history_struct_get(global.playback_context, "segments", []);
        out.playback_context_segment_count = is_array(segs) ? array_length(segs) : 0;
    }

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        return out;
    }

    out.has_timeline_state = true;

    var nav_entries = event_history_struct_get(global.timeline_state, "measure_nav_entries", []);
    if (is_array(nav_entries)) {
        out.measure_nav_count = array_length(nav_entries);
        var nav_n = min(entry_limit, out.measure_nav_count);
        for (var i = 0; i < nav_n; i++) {
            var e = nav_entries[i];
            if (!is_struct(e)) continue;
            array_push(out.measure_nav_entries_head, {
                i: i,
                measure: floor(real(event_history_struct_get(e, "measure", -1))),
                part: floor(real(event_history_struct_get(e, "part", -1))),
                start_ms: real(event_history_struct_get(e, "start_ms", 0)),
                end_ms: real(event_history_struct_get(e, "end_ms", 0))
            });
        }
    }

    var structural = event_history_struct_get(global.timeline_state, "structural_measure_starts", []);
    if (is_array(structural)) {
        out.structural_start_count = array_length(structural);
        var st_n = min(entry_limit, out.structural_start_count);
        for (var s = 0; s < st_n; s++) {
            var st = structural[s];
            if (!is_struct(st)) continue;
            array_push(out.structural_measure_starts_head, {
                i: s,
                m: floor(real(event_history_struct_get(st, "m", -1))),
                t: real(event_history_struct_get(st, "t", 0)),
                seq: floor(real(event_history_struct_get(st, "seq", -1)))
            });
        }
    }

    if (variable_global_exists("timeline_beat_positions") && is_array(global.timeline_beat_positions)) {
        var beats = global.timeline_beat_positions;
        out.beat_positions_count = array_length(beats);
        var beat_n = min(beat_limit, out.beat_positions_count);
        for (var b = 0; b < beat_n; b++) {
            var bp = beats[b];
            if (!is_struct(bp)) continue;
            var label = string(event_history_struct_get(bp, "label", ""));
            var rec = {
                i: b,
                time_ms: real(event_history_struct_get(bp, "time_ms", 0)),
                is_major: event_history_struct_get(bp, "is_major", false),
                label: label
            };
            array_push(out.beat_positions_head, rec);
            if (string_length(label) > 0) {
                array_push(out.beat_labels_head, rec);
            }
        }
    }

    return out;
}

/// @function event_history_export_summary_json(_filename_or_path, _export_info)
/// @description Write a compact per-run summary JSON for review overlays.
/// @reads global.timeline_state (via event_history_build_summary_player_spans)
/// @callers scr_button_scripts or scr_tune_scripts (end-of-tune export)
function event_history_export_summary_json(_filename_or_path, _export_info = undefined) {
    var filepath = _filename_or_path;
    if (script_exists(asset_get_index("scr_data_paths_resolve_datafiles_path"))) {
        filepath = scr_data_paths_resolve_datafiles_path(filepath);
    }
    if (string_pos("datafiles/", filepath) != 1 && string_pos("/", filepath) == 0) {
        var base_root = script_exists(asset_get_index("scr_data_paths_get_primary_root"))
            ? scr_data_paths_get_primary_root()
            : "datafiles/";
        filepath = base_root + filepath;
    }

    var export_info = is_struct(_export_info)
        ? _export_info
        : event_history_get_export_info();
    var export_folder = string(event_history_struct_get(export_info, "folder", ""));
    if (export_folder != "" && !directory_exists(export_folder)) {
        directory_create(export_folder);
    }

    var effective_events = event_history_get_effective_events();

    var player_spans = event_history_build_summary_player_spans();
    var has_player_spans = array_length(player_spans) > 0;
    if (!has_player_spans) {
        show_debug_message("[REVIEW_HISTORY] No player spans captured; exporting summary with debug_structure only.");
    }

    var scoring_summary = undefined;
    var scoring_builder_idx = asset_get_index("scoring_build_ms_overlap_summary");
    if (script_exists(scoring_builder_idx)) {
        scoring_summary = script_execute(scoring_builder_idx, export_info);
    }

    var audio_offset_ms = real(event_history_struct_get(export_info, "audio_output_offset_ms", event_history_struct_get(export_info, "audio_offset_ms", 0)));
    var visual_offset_ms = real(event_history_struct_get(export_info, "visual_alignment_offset_ms", event_history_struct_get(export_info, "visual_offset_ms", 0)));
    var input_offset_ms = real(event_history_struct_get(export_info, "input_capture_offset_ms", event_history_struct_get(export_info, "input_offset_ms", 0)));
    var score_offset_ms = real(event_history_struct_get(export_info, "scoring_compare_offset_ms", event_history_struct_get(export_info, "score_offset_ms", 0)));

    var timing_sample_game = {};
    var timing_sample_player = {};
    var has_timing_sample_game = false;
    var has_timing_sample_player = false;
    if (array_length(effective_events) > 0) {
        for (var i = 0; i < array_length(effective_events); i++) {
            var ev = effective_events[i];
            if (!is_struct(ev)) continue;

            var ev_source = string(event_history_struct_get(ev, "source", ""));
            if (ev_source == "game" && !has_timing_sample_game) {
                timing_sample_game = {
                    canonical_time_ms: real(event_history_struct_get(ev, "canonical_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    audio_target_time_ms: real(event_history_struct_get(ev, "audio_target_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    visual_target_time_ms: real(event_history_struct_get(ev, "visual_target_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    input_aligned_time_ms: real(event_history_struct_get(ev, "input_aligned_time_ms", event_history_struct_get(ev, "actual_time_ms", 0))),
                    audio_offset_ms: real(event_history_struct_get(ev, "audio_offset_ms", audio_offset_ms)),
                    visual_offset_ms: real(event_history_struct_get(ev, "visual_offset_ms", visual_offset_ms)),
                    input_offset_ms: real(event_history_struct_get(ev, "input_offset_ms", input_offset_ms)),
                    score_offset_ms: real(event_history_struct_get(ev, "score_offset_ms", score_offset_ms))
                };
                has_timing_sample_game = true;
            } else if (ev_source == "player" && !has_timing_sample_player) {
                timing_sample_player = {
                    canonical_time_ms: real(event_history_struct_get(ev, "canonical_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    audio_target_time_ms: real(event_history_struct_get(ev, "audio_target_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    visual_target_time_ms: real(event_history_struct_get(ev, "visual_target_time_ms", event_history_struct_get(ev, "expected_time_ms", 0))),
                    input_aligned_time_ms: real(event_history_struct_get(ev, "input_aligned_time_ms", event_history_struct_get(ev, "actual_time_ms", 0))),
                    audio_offset_ms: real(event_history_struct_get(ev, "audio_offset_ms", audio_offset_ms)),
                    visual_offset_ms: real(event_history_struct_get(ev, "visual_offset_ms", visual_offset_ms)),
                    input_offset_ms: real(event_history_struct_get(ev, "input_offset_ms", input_offset_ms)),
                    score_offset_ms: real(event_history_struct_get(ev, "score_offset_ms", score_offset_ms))
                };
                has_timing_sample_player = true;
            }

            if (has_timing_sample_game && has_timing_sample_player) break;
        }
    }

    var payload = {
        schema_version: 1,
        export_type: "performance_summary",
        tune_name: event_history_struct_get(export_info, "tune_name", ""),
        tune_id: event_history_struct_get(export_info, "tune_id", ""),
        player_id: event_history_struct_get(export_info, "player_id", "default"),
        tune_title: event_history_struct_get(export_info, "tune_title", ""),
        clean_tune: event_history_struct_get(export_info, "clean_tune", ""),
        timestamp: event_history_struct_get(export_info, "timestamp", ""),
        bpm: event_history_struct_get(export_info, "bpm", 0),
        swing: event_history_struct_get(export_info, "swing", ""),
        grace_override_ms: event_history_struct_get(export_info, "grace_override_ms", 0),
        audio_offset_ms: audio_offset_ms,
        visual_offset_ms: visual_offset_ms,
        input_offset_ms: input_offset_ms,
        score_offset_ms: score_offset_ms,
        player_spans: player_spans
    };
    variable_struct_set(payload, "export_filter", {
        include_game_events: event_history_struct_get(export_info, "export_include_game_events", true)
    });
    variable_struct_set(payload, "benchmark_context", {
        power_mode_label: event_history_struct_get(export_info, "benchmark_power_mode_label", "unspecified"),
        midi_activity_label: event_history_struct_get(export_info, "benchmark_midi_activity_label", "unknown"),
        notes: event_history_struct_get(export_info, "benchmark_notes", ""),
        midi_input_device_name: event_history_struct_get(export_info, "midi_input_device_name", "not selected"),
        midi_output_device_name: event_history_struct_get(export_info, "midi_output_device_name", "not selected"),
        midi_output_drum_device_name: event_history_struct_get(export_info, "midi_output_drum_device_name", "not selected"),
        playback_scheduler_mode: event_history_struct_get(export_info, "playback_scheduler_mode", "timesource"),
        game_step_fps: event_history_struct_get(export_info, "game_step_fps", 0)
    });
    variable_struct_set(payload, "has_player_spans", has_player_spans);
    variable_struct_set(payload, "debug_structure", event_history_build_structure_debug_snapshot(120, 200));
    variable_struct_set(payload, "has_timing_sample_game", has_timing_sample_game);
    variable_struct_set(payload, "has_timing_sample_player", has_timing_sample_player);
    variable_struct_set(payload, "timing_sample_game", timing_sample_game);
    variable_struct_set(payload, "timing_sample_player", timing_sample_player);
    if (is_struct(scoring_summary)) {
        variable_struct_set(payload, "scoring", scoring_summary);
    }

    var scoring_judges = {
        selected_judge: "",
        overall_by_judge: {},
        raw_by_judge: {},
        measure_map_by_key_by_judge: {}
    };
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        if (variable_struct_exists(global.timeline_state, "score_selected_judge")) {
            scoring_judges.selected_judge = string(variable_struct_get(global.timeline_state, "score_selected_judge"));
        }
        if (variable_struct_exists(global.timeline_state, "score_overall_by_judge")
            && is_struct(variable_struct_get(global.timeline_state, "score_overall_by_judge"))) {
            scoring_judges.overall_by_judge = variable_struct_get(global.timeline_state, "score_overall_by_judge");
        }
        if (variable_struct_exists(global.timeline_state, "score_raw_by_judge")
            && is_struct(variable_struct_get(global.timeline_state, "score_raw_by_judge"))) {
            scoring_judges.raw_by_judge = variable_struct_get(global.timeline_state, "score_raw_by_judge");
        }
        if (variable_struct_exists(global.timeline_state, "score_measure_maps_by_key")
            && is_struct(variable_struct_get(global.timeline_state, "score_measure_maps_by_key"))) {
            scoring_judges.measure_map_by_key_by_judge = variable_struct_get(global.timeline_state, "score_measure_maps_by_key");
        }
    }
    variable_struct_set(payload, "scoring_judges", scoring_judges);

    variable_struct_set(payload, "player_span_count", array_length(event_history_struct_get(payload, "player_spans", [])));

    var file = file_text_open_write(filepath);
    if (file == -1) {
        show_debug_message("ERROR: Could not open summary file for writing: " + filepath);
        return false;
    }

    file_text_write_string(file, json_stringify(payload));
    file_text_close(file);

    var resolved_path = filepath;
    if (string_pos("datafiles/", filepath) == 1) {
        resolved_path = working_directory + filepath;
    }
    show_debug_message("✓ Exported review summary to: " + resolved_path);
    return true;
}

/// @function event_history_export_loop_session_json(_export_info)
/// @description Export one loop-session JSON with each loop iteration grouped separately.
/// @reads global.loop_runtime_active, global.EVENT_HISTORY, global.loop_runtime_repeat_total, global.loop_runtime_blank_measure, global.timeline_state
/// @writes global.timeline_state.loop_session_runs
/// @callers scr_button_scripts or scr_tune_scripts (end-of-loop export)
function event_history_export_loop_session_json(_export_info = undefined) {
    if (!variable_global_exists("loop_runtime_active") || !global.loop_runtime_active) {
        return false;
    }
    var effective_events = event_history_get_effective_events();
    if (array_length(effective_events) <= 0) {
        return false;
    }

    var export_info = is_struct(_export_info)
        ? _export_info
        : event_history_get_export_info();
    var export_folder = string(event_history_struct_get(export_info, "folder", ""));
    if (export_folder == "") {
        return false;
    }
    if (!directory_exists(export_folder)) {
        directory_create(export_folder);
    }

    var selected_measures = [];
    if (is_undefined(gv_loop_get_selected_measures) == false) {
        selected_measures = gv_loop_get_selected_measures();
    }

    var run_map = {};
    var run_order = [];
    for (var i = 0; i < array_length(effective_events); i++) {
        var ev = effective_events[i];
        if (!is_struct(ev)) continue;

        var loop_iteration = floor(real(event_history_struct_get(ev, "loop_iteration", 0)));
        if (loop_iteration <= 0) continue;
        var run_key = string(loop_iteration);

        if (!variable_struct_exists(run_map, run_key) || !is_struct(run_map[$ run_key])) {
            run_map[$ run_key] = {
                iteration: loop_iteration,
                event_count: 0,
                player_event_count: 0,
                first_timestamp_ms: -1,
                last_timestamp_ms: -1
            };
            array_push(run_order, loop_iteration);
        }

        var run = run_map[$ run_key];
        run.event_count += 1;

        var ev_source = string(event_history_struct_get(ev, "source", ""));
        if (ev_source == "player") {
            run.player_event_count += 1;
        }

        var ev_time = real(event_history_struct_get(ev, "timestamp_ms", 0));
        if (run.first_timestamp_ms < 0 || ev_time < run.first_timestamp_ms) {
            run.first_timestamp_ms = ev_time;
        }
        if (run.last_timestamp_ms < 0 || ev_time > run.last_timestamp_ms) {
            run.last_timestamp_ms = ev_time;
        }

        run_map[$ run_key] = run;
    }

    if (array_length(run_order) <= 0) {
        return false;
    }

    for (var a = 1; a < array_length(run_order); a++) {
        var v = run_order[a];
        var b = a - 1;
        while (b >= 0 && run_order[b] > v) {
            run_order[b + 1] = run_order[b];
            b--;
        }
        run_order[b + 1] = v;
    }

    var runs = [];
    for (var r = 0; r < array_length(run_order); r++) {
        var run_key = string(run_order[r]);
        if (!variable_struct_exists(run_map, run_key)) continue;
        var run = run_map[$ run_key];
        run.duration_ms = max(0, real(run.last_timestamp_ms) - real(run.first_timestamp_ms));
        array_push(runs, run);
    }

    var payload = {
        schema_version: 1,
        export_type: "loop_session",
        tune_name: event_history_struct_get(export_info, "tune_name", ""),
        tune_title: event_history_struct_get(export_info, "tune_title", ""),
        clean_tune: event_history_struct_get(export_info, "clean_tune", ""),
        timestamp: event_history_struct_get(export_info, "timestamp", ""),
        bpm: event_history_struct_get(export_info, "bpm", 0),
        swing: event_history_struct_get(export_info, "swing", ""),
        loop_repeat_total: variable_global_exists("loop_runtime_repeat_total") ? real(global.loop_runtime_repeat_total) : array_length(runs),
        loop_blank_measure: variable_global_exists("loop_runtime_blank_measure") ? (global.loop_runtime_blank_measure == true) : false,
        selected_measures: selected_measures,
        runs: runs
    };
    variable_struct_set(payload, "run_count", array_length(runs));

    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.loop_session_runs = runs;
    }

    var base_name = string(event_history_struct_get(export_info, "base_name", "session"));
    var filepath = export_folder + "/" + base_name + "_loop_session.json";
    var file = file_text_open_write(filepath);
    if (file < 0) {
        show_debug_message("ERROR: Could not open loop session file for writing: " + filepath);
        return false;
    }

    file_text_write_string(file, json_stringify(payload));
    file_text_close(file);
    show_debug_message("✓ Exported loop session to: " + filepath);
    return true;
}

/// @function event_history_summary_timestamp_key(_summary)
/// @description Convert summary timestamps into sortable numeric keys.
function event_history_summary_timestamp_key(_summary) {
    if (!is_struct(_summary)) return 0;

    var stamp = string(event_history_struct_get(_summary, "timestamp", "0"));
    stamp = string_replace_all(stamp, "-", "");
    if (stamp == "") return 0;

    return real(stamp);
}

/// @function event_history_sort_summaries_desc(_summaries)
/// @description Return summaries sorted newest-first by export timestamp.
function event_history_sort_summaries_desc(_summaries) {
    if (!is_array(_summaries)) return array_create(0);

    var sorted = array_create(0);
    for (var i = 0; i < array_length(_summaries); i++) {
        array_push(sorted, _summaries[i]);
    }

    var n_sorted = array_length(sorted);
    for (var a = 0; a < n_sorted - 1; a++) {
        var best_idx = a;
        var best_key = event_history_summary_timestamp_key(sorted[a]);
        for (var b = a + 1; b < n_sorted; b++) {
            var scan_key = event_history_summary_timestamp_key(sorted[b]);
            if (scan_key > best_key) {
                best_key = scan_key;
                best_idx = b;
            }
        }

        if (best_idx != a) {
            var swap_item = sorted[a];
            sorted[a] = sorted[best_idx];
            sorted[best_idx] = swap_item;
        }
    }

    return sorted;
}

/// @function event_history_load_recent_summaries(_clean_tune, _bpm, _swing, _max_count, _match_bpm, _match_swing, _player_id, _match_player)
/// @description Load recent matching summary JSON files for review overlays.
/// @callers scr_game_viz (review overlay) or scr_UI_scripts
function event_history_load_recent_summaries(_clean_tune, _bpm, _swing, _max_count, _match_bpm = true, _match_swing = true, _player_id = "", _match_player = true) {
    var results = array_create(0);
    var clean_tune = string(_clean_tune ?? "");
    var max_count = max(0, floor(real(_max_count)));
    if (clean_tune == "" || max_count <= 0) {
        return results;
    }

    var perf_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
        ? scr_data_paths_get_category_root("performances")
        : "datafiles/performances/";
    var folder = perf_root + clean_tune;
    if (!directory_exists(folder)) {
        return results;
    }
    if (string_copy(folder, string_length(folder), 1) != "/") {
        folder += "/";
    }

    var target_bpm = real(_bpm);
    var target_swing = string(_swing ?? "");
    var target_player = string_lower(string_trim(string(_player_id ?? "")));

    var entry = file_find_first(folder + "*_summary.json", 0);
    if (entry == "") {
        return results;
    }

    while (entry != "") {
        if (string_copy(entry, 1, 1) != ".") {
            var filepath = folder + entry;
            if (!directory_exists(filepath)) {
                var summary = scr_tune_parse_json_file(filepath);
                if (is_struct(summary)
                    && variable_struct_exists(summary, "player_spans")
                    && is_array(event_history_struct_get(summary, "player_spans", []))
                    && array_length(event_history_struct_get(summary, "player_spans", [])) > 0) {
                    var bpm_ok = !_match_bpm || abs(real(event_history_struct_get(summary, "bpm", -1)) - target_bpm) <= 0.001;
                    var swing_ok = !_match_swing || string(event_history_struct_get(summary, "swing", "")) == target_swing;
                    var summary_player = string_lower(string_trim(string(event_history_struct_get(summary, "player_id", ""))));
                    var player_ok = !_match_player || target_player == "" || summary_player == target_player;
                    if (bpm_ok && swing_ok && player_ok) {
                        array_push(results, summary);
                    }
                }
            }
        }

        entry = file_find_next();
    }
    file_find_close();

    results = event_history_sort_summaries_desc(results);
    if (array_length(results) <= max_count) {
        return results;
    }

    var trimmed = array_create(0);
    for (var i = 0; i < max_count; i++) {
        array_push(trimmed, results[i]);
    }
    return trimmed;
}

/// @function event_history_enrich(_events)
/// @description Create a derived copy of events with enrichment (note letters, measure/beat forward-fill, etc.)
/// @param {array} _events Raw event history array
/// @returns Array of enriched event structs
/// @reads global.MIDI_chanter (via chanter_midi_to_canonical)
/// @callers event_history_export_csv

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
        var note_midi_raw = struct_get(ev, "note_midi_raw");
        if (is_undefined(note_midi_raw)) {
            note_midi_raw = note_midi;
        }
        var note_channel = struct_get(ev, "channel") ?? -1;
        var note_canonical = string(struct_get(ev, "note_canonical") ?? "");
        var note_letter = "";
        if (note_midi > 0) {
            if (string_length(note_canonical) <= 0) {
                note_canonical = chanter_midi_to_canonical(note_midi, global.MIDI_chanter ?? "default", note_channel);
            }
            if (string_length(note_canonical) > 0) {
                note_letter = chanter_canonical_to_display(note_canonical);
            }
            if (note_letter == "?" || string_length(note_letter) <= 0) {
                note_letter = midi_to_letter(note_midi, note_channel);
            }
        }
        
        // Derive timing_quality based on source
        var timing_quality = (ev_source == "game") ? "on_time" : "n/a";
        var is_embellishment = bool(struct_get(ev, "is_embellishment") ?? false);
        var embellishment_name = string(struct_get(ev, "embellishment_name") ?? "");
        if (embellishment_name == "") {
            embellishment_name = string(struct_get(ev, "embellishment") ?? "");
        }
        
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
            is_embellishment,
            embellishment_name,
            timing_quality
        );

        struct_set(enriched_ev, "note_midi_raw", note_midi_raw);
        struct_set(enriched_ev, "note_canonical", note_canonical);
        
        array_push(enriched, enriched_ev);
    }
    
    return enriched;
}

/// @function event_history_export_csv(_filename_or_path)
/// @description Write entire event history to a CSV file.
/// @param _filename_or_path Filename ("event_history.csv") or full path ("datafiles/...")
/// @returns (none)
/// @reads global.EVENT_HISTORY, global.EVENT_RUNTIME_PLAYER, global.EVENT_RUNTIME_PLANNED, global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS
/// @callers scr_button_scripts (end-of-tune export)

function event_history_export_csv(_filename_or_path) {
    var filepath = _filename_or_path;
    if (script_exists(asset_get_index("scr_data_paths_resolve_datafiles_path"))) {
        filepath = scr_data_paths_resolve_datafiles_path(filepath);
    }
    if (string_pos("datafiles/", filepath) != 1 && string_pos("/", filepath) == 0) {
        var base_root = script_exists(asset_get_index("scr_data_paths_get_primary_root"))
            ? scr_data_paths_get_primary_root()
            : "datafiles/";
        filepath = base_root + filepath;
    }
    var file = file_text_open_write(filepath);
    
    if (file == -1) {
        show_debug_message("ERROR: Could not open file for writing: " + filepath);
        return;
    }
    
    // Write header
    file_text_write_string(file, "timestamp_ms,expected_ms,actual_ms,delta_ms,measure,beat,beat_frac,type,source,note_midi,note_letter,velocity,channel,tune,event_id,is_embellishment,embellishment,timing_quality,canonical_time_ms,audio_target_time_ms,visual_target_time_ms,input_aligned_time_ms,audio_offset_ms,visual_offset_ms,input_offset_ms,score_offset_ms\n");
    // Enrich events before export (derive note_letter, forward-fill measure/beat)
    var export_events = event_history_enrich(event_history_get_effective_events());
    var event_count = array_length(export_events);
    var export_info = event_history_get_export_info();
    var include_game_events = event_history_struct_get(export_info, "export_include_game_events", true);
    var exported_count = 0;
    
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

        var ev_source = struct_get(ev, "source") ?? "";
        if (!include_game_events && ev_source == "game") {
            continue;
        }
        
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
        var note_midi = struct_get(ev, "note_midi");
        var note_letter = struct_get(ev, "note_letter");
        var velocity = struct_get(ev, "velocity");
        var ev_channel = struct_get(ev, "channel");
        var tune_name = struct_get(ev, "tune_name");
        var event_id = struct_get(ev, "event_id");
        var is_embellishment = struct_get(ev, "is_embellishment");
        var embellishment_name = struct_get(ev, "embellishment_name");
        var timing_quality = struct_get(ev, "timing_quality");
        var audio_offset_ms = real(event_history_struct_get(ev, "audio_offset_ms", 0));
        var visual_offset_ms = real(event_history_struct_get(ev, "visual_offset_ms", 0));
        var input_offset_ms = real(event_history_struct_get(ev, "input_offset_ms", 0));
        var score_offset_ms = real(event_history_struct_get(ev, "score_offset_ms", 0));
        var canonical_time_ms = real(event_history_struct_get(ev, "canonical_time_ms", expected_time_ms));
        var audio_target_time_ms = real(event_history_struct_get(ev, "audio_target_time_ms", canonical_time_ms + audio_offset_ms));
        var visual_target_time_ms = real(event_history_struct_get(ev, "visual_target_time_ms", canonical_time_ms + visual_offset_ms));
        var input_aligned_time_ms = real(event_history_struct_get(ev, "input_aligned_time_ms", actual_time_ms + input_offset_ms));
        
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
            + string(timing_quality) + ","
            + string(canonical_time_ms) + ","
            + string(audio_target_time_ms) + ","
            + string(visual_target_time_ms) + ","
            + string(input_aligned_time_ms) + ","
            + string(audio_offset_ms) + ","
            + string(visual_offset_ms) + ","
            + string(input_offset_ms) + ","
            + string(score_offset_ms);
        
        file_text_write_string(file, line + "\n");
        exported_count += 1;
    }
    
    file_text_close(file);
    show_debug_message("✓ Exported " + string(exported_count) + " events to: " + filepath + " (include_game_events=" + string(include_game_events) + ")");
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