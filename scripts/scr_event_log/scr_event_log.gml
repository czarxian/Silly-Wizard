
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
if (!variable_global_exists("EVENT_HISTORY_LIBRARY_UPDATED")) {
    global.EVENT_HISTORY_LIBRARY_UPDATED = false;
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
    global.EVENT_HISTORY_LIBRARY_UPDATED = false;
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
    return "datafiles/performances/tune_history_index.json";
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

    var folder = "datafiles/performances";
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
function event_history_get_export_score(_export_info = undefined) {
    if (is_struct(_export_info)) {
        if (variable_struct_exists(_export_info, "score")) return variable_struct_get(_export_info, "score");
        if (variable_struct_exists(_export_info, "last_score")) return variable_struct_get(_export_info, "last_score");
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

    var timestamp = string(_timestamp);
    if (timestamp == "") {
        timestamp = event_history_format_timestamp();
    }

    var folder = "datafiles/performances/" + clean_tune;
    var base_name = clean_tune + "_" + timestamp + "_" + string(bpm) + "_" + swing + "_" + string(grace_override_ms);

    return {
        tune_name: tune_name,
        tune_filename: tune_filename,
        tune_id: event_history_make_tune_history_id((tune_filename != "") ? tune_filename : tune_name),
        tune_title: tune_title,
        clean_tune: clean_tune,
        timestamp: timestamp,
        bpm: bpm,
        swing: swing,
        grace_override_ms: grace_override_ms,
        folder: folder,
        base_name: base_name,
        csv_path: folder + "/" + base_name + ".csv",
        summary_path: folder + "/" + base_name + "_summary.json"
    };
}

/// @function event_history_update_tune_history_index(_export_info)
/// @description Update the persistent tune-library history index using the current run export metadata.
function event_history_update_tune_history_index(_export_info = undefined) {
    if (!variable_global_exists("EVENT_HISTORY") || array_length(global.EVENT_HISTORY) <= 0) {
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
    }

    tunes[match_idx] = history_entry;
    variable_struct_set(history_index, "tunes", tunes);
    variable_struct_set(history_index, "updated_at", event_history_format_timestamp());
    return event_history_store_tune_history_index(history_index);
}

/// @function event_history_build_summary_player_spans()
/// @description Build a compact per-note span array for review overlays.
function event_history_build_summary_player_spans() {
    var spans_out = array_create(0);

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        return spans_out;
    }
    if (!variable_struct_exists(global.timeline_state, "player_in") || !is_array(global.timeline_state.player_in)) {
        return spans_out;
    }

    var player_spans = global.timeline_state.player_in;
    var n_spans = array_length(player_spans);
    for (var i = 0; i < n_spans; i++) {
        var span = player_spans[i];
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

/// @function event_history_export_summary_json(_filename_or_path, _export_info)
/// @description Write a compact per-run summary JSON for review overlays.
function event_history_export_summary_json(_filename_or_path, _export_info = undefined) {
    var filepath = _filename_or_path;
    if (string_pos("datafiles/", filepath) != 1) {
        filepath = "datafiles/" + filepath;
    }

    var export_info = is_struct(_export_info)
        ? _export_info
        : event_history_get_export_info();
    var export_folder = string(event_history_struct_get(export_info, "folder", ""));
    if (export_folder != "" && !directory_exists(export_folder)) {
        directory_create(export_folder);
    }

    var player_spans = event_history_build_summary_player_spans();
    if (array_length(player_spans) <= 0) {
        show_debug_message("[REVIEW_HISTORY] Skipping summary export because no player spans were captured.");
        return false;
    }

    var payload = {
        schema_version: 1,
        export_type: "performance_summary",
        tune_name: event_history_struct_get(export_info, "tune_name", ""),
        tune_title: event_history_struct_get(export_info, "tune_title", ""),
        clean_tune: event_history_struct_get(export_info, "clean_tune", ""),
        timestamp: event_history_struct_get(export_info, "timestamp", ""),
        bpm: event_history_struct_get(export_info, "bpm", 0),
        swing: event_history_struct_get(export_info, "swing", ""),
        grace_override_ms: event_history_struct_get(export_info, "grace_override_ms", 0),
        player_spans: player_spans
    };
    variable_struct_set(payload, "player_span_count", array_length(event_history_struct_get(payload, "player_spans", [])));

    var file = file_text_open_write(filepath);
    if (file == -1) {
        show_debug_message("ERROR: Could not open summary file for writing: " + filepath);
        return false;
    }

    file_text_write_string(file, json_stringify(payload));
    file_text_close(file);
    show_debug_message("✓ Exported review summary to: " + filepath);
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

/// @function event_history_load_recent_summaries(_clean_tune, _bpm, _swing, _max_count, _match_bpm, _match_swing)
/// @description Load recent matching summary JSON files for review overlays.
function event_history_load_recent_summaries(_clean_tune, _bpm, _swing, _max_count, _match_bpm = true, _match_swing = true) {
    var results = array_create(0);
    var clean_tune = string(_clean_tune ?? "");
    var max_count = max(0, floor(real(_max_count)));
    if (clean_tune == "" || max_count <= 0) {
        return results;
    }

    var folder = "datafiles/performances/" + clean_tune;
    if (!directory_exists(folder)) {
        return results;
    }
    if (string_copy(folder, string_length(folder), 1) != "/") {
        folder += "/";
    }

    var target_bpm = real(_bpm);
    var target_swing = string(_swing ?? "");

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
                    if (bpm_ok && swing_ok) {
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