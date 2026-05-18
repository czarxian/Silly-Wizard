// scr_scoring - objective scoring utilities
// Phase 1 judge: millisecond overlap between planned tune spans and player spans.

if (!variable_global_exists("current_player_id")) {
    global.current_player_id = "player_1";
}
if (!variable_global_exists("scoring_last_run")) {
    global.scoring_last_run = undefined;
}

/// @function scoring_get_player_id()
/// @description Return the active player ID, reading global.current_player_id and sanitizing to a non-empty string.
/// @returns {string}  Player key (e.g. "player_1")
/// @reads   global.current_player_id
function scoring_get_player_id() {
    var player_key = "player_1";
    if (variable_global_exists("current_player_id")) {
        player_key = string_trim(string(global.current_player_id));
    }
    if (player_key == "") player_key = "player_1";
    return player_key;
}

/// @function scoring_calibration_debug_log(_line)
/// @description Write calibration diagnostic to calibration_debug.log file in datafiles/debug.
/// @param {string} _line Text line to log
function scoring_calibration_debug_log(_line) {
    var _msg = string(_line);
    show_debug_message("[CALIB_LOG] " + _msg);  // Always show in output for visibility
    
    // Write to relative path (GameMaker resolves relative to working_directory which is C:\Users\xian\AppData\Local\Silly_Wizard\)
    var _log_path = "datafiles/debug/calibration_debug.log";
    var _f = file_text_open_append(_log_path);
    if (_f != -1) {
        file_text_write_string(_f, _msg + "\n");
        file_text_close(_f);
    }
}

/// @function scoring_get_context_key(_tune_id, _player_id, _bpm, _swing, _part_key)
/// @description Build a canonical context key string for keying scoring history records.
/// @param {string} _tune_id    Tune identifier
/// @param {string} _player_id  Player identifier
/// @param {real}   _bpm        Tempo in BPM
/// @param {string} _swing      Swing multiplier string
/// @param {string} [_part_key] Part filter (default "all")
/// @returns {string}  Pipe-delimited lowercase context key
function scoring_get_context_key(_tune_id, _player_id, _bpm, _swing, _part_key = "all") {
    return string_lower(string(_tune_id))
        + "|" + string_lower(string(_player_id))
        + "|" + string(real(_bpm))
        + "|" + string(_swing)
        + "|" + string(_part_key);
}

/// @function scoring_measure_entries_from_timeline()
/// @description Return the measure_nav_entries array from global.timeline_state, or [] if unavailable.
/// @returns {array}  Array of measure entry structs {measure, start_ms, end_ms, part}
/// @reads   global.timeline_state
function scoring_measure_entries_from_timeline() {
    var entries = [];
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return entries;

    if (variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(variable_struct_get(global.timeline_state, "measure_nav_entries"))
        && array_length(variable_struct_get(global.timeline_state, "measure_nav_entries")) > 0) {
        return variable_struct_get(global.timeline_state, "measure_nav_entries");
    }

    return entries;
}

/// @function scoring_filter_spans_in_window(_spans, _start_ms, _end_ms)
/// @description Return only the spans from _spans that overlap the time window [_start_ms, _end_ms).
/// @param {array} _spans     Array of span structs {start_ms, end_ms, lane_idx}
/// @param {real}  _start_ms  Window start in ms
/// @param {real}  _end_ms    Window end in ms
/// @returns {array}  Filtered span array
function scoring_filter_spans_in_window(_spans, _start_ms, _end_ms) {
    var filtered = [];
    if (!is_array(_spans)) return filtered;

    var n = array_length(_spans);
    for (var i = 0; i < n; i++) {
        var s = _spans[i];
        if (!is_struct(s)) continue;

        var a1 = min(real(s.start_ms ?? 0), real(s.end_ms ?? 0));
        var a2 = max(real(s.start_ms ?? 0), real(s.end_ms ?? 0));
        if (a2 <= _start_ms || a1 >= _end_ms) continue;

        // Clip span to window boundary so partial-overlap spans don't inflate expected_active_ms
        var clipped_start = max(a1, _start_ms);
        var clipped_end   = min(a2, _end_ms);
        if (clipped_start == a1 && clipped_end == a2) {
            array_push(filtered, s);
        } else {
            var keys = struct_get_names(s);
            var copy = {};
            for (var _ki = 0; _ki < array_length(keys); _ki++) {
                copy[$ keys[_ki]] = s[$ keys[_ki]];
            }
            copy.start_ms = clipped_start;
            copy.end_ms   = clipped_end;
            array_push(filtered, copy);
        }
    }

    return filtered;
}

/// @function scoring_boundaries_add_unique(_arr, _value)
/// @description Append _value to _arr only if not already present within 0.0001 tolerance. Returns modified array.
/// @param {array} _arr    Sorted boundary array (modified in-place)
/// @param {real}  _value  Millisecond boundary to insert
/// @returns {array}  The array (same reference)
function scoring_boundaries_add_unique(_arr, _value) {
    var v = real(_value);
    for (var i = 0; i < array_length(_arr); i++) {
        if (abs(real(_arr[i]) - v) <= 0.0001) return _arr;
    }
    array_push(_arr, v);
    return _arr;
}

/// @function scoring_lane_key_at_time(_spans, _t_ms)
/// @description Return a comma-separated sorted lane index key for all spans active at time _t_ms.
/// @param {array} _spans  Span array {start_ms, end_ms, lane_idx}
/// @param {real}  _t_ms   Sample time in ms
/// @returns {string}  Key like "2" or "0,2" or "" (for silence)
function scoring_lane_key_at_time(_spans, _t_ms) {
    if (!is_array(_spans) || array_length(_spans) <= 0) return "";

    var lanes = [];
    var n = array_length(_spans);
    for (var i = 0; i < n; i++) {
        var s = _spans[i];
        if (!is_struct(s)) continue;

        var a1 = min(real(s.start_ms ?? 0), real(s.end_ms ?? 0));
        var a2 = max(real(s.start_ms ?? 0), real(s.end_ms ?? 0));
        if (_t_ms < a1 || _t_ms >= a2) continue;

        var lane = floor(real(s.lane_idx ?? -1));
        if (lane < 0) continue;

        var already = false;
        for (var li = 0; li < array_length(lanes); li++) {
            if (real(lanes[li]) == lane) {
                already = true;
                break;
            }
        }
        if (!already) array_push(lanes, lane);
    }

    if (array_length(lanes) <= 0) return "";

    if (array_length(lanes) > 1) {
        array_sort(lanes, function(_a, _b) {
            return real(_a) - real(_b);
        });
    }

    var key = "";
    for (var k = 0; k < array_length(lanes); k++) {
        if (k > 0) key += ",";
        key += string(floor(real(lanes[k])));
    }
    return key;
}

/// @function scoring_score_measure_ms_overlap(_measure_entry, _planned_spans, _player_spans, _settings)
/// @description Score a single measure by comparing planned and player lane activity in the measure's time window. Returns a struct with matching_ms, mismatch_ms, expected_active_ms, player_active_ms, and score (0–100).
/// @param {struct} _measure_entry  {measure, start_ms, end_ms, part}
/// @param {array}  _planned_spans  Planned note spans for the measure window
/// @param {array}  _player_spans   Player MIDI spans for the measure window
/// @param {struct} [_settings]     Optional scoring settings from scoring_ms_overlap_get_effective_settings
/// @returns {struct}  Scoring result {measure, start_ms, end_ms, total_ms, matching_ms, mismatch_ms, expected_active_ms, player_active_ms, score}
function scoring_score_measure_ms_overlap(_measure_entry, _planned_spans, _player_spans, _settings = undefined) {
    var measure_num = floor(real(_measure_entry.measure ?? -1));
    var start_ms = real(_measure_entry.start_ms ?? 0);
    var end_ms = max(start_ms, real(_measure_entry.end_ms ?? start_ms));
    var total_ms = max(0, end_ms - start_ms);

    var result = {
        measure: measure_num,
        part: floor(real(_measure_entry.part ?? 1)),
        start_ms: start_ms,
        end_ms: end_ms,
        total_ms: total_ms,
        matching_ms: 0,
        mismatch_ms: total_ms,
        expected_active_ms: 0,
        player_active_ms: 0,
        score: 0
    };

    if (total_ms <= 0.001) {
        return result;
    }

    var planned = scoring_filter_spans_in_window(_planned_spans, start_ms, end_ms);
    var player = scoring_filter_spans_in_window(_player_spans, start_ms, end_ms);

    var boundaries = [start_ms, end_ms];

    for (var i = 0; i < array_length(planned); i++) {
        var ps = planned[i];
        boundaries = scoring_boundaries_add_unique(boundaries, clamp(real(ps.start_ms ?? start_ms), start_ms, end_ms));
        boundaries = scoring_boundaries_add_unique(boundaries, clamp(real(ps.end_ms ?? end_ms), start_ms, end_ms));
    }
    for (var j = 0; j < array_length(player); j++) {
        var us = player[j];
        boundaries = scoring_boundaries_add_unique(boundaries, clamp(real(us.start_ms ?? start_ms), start_ms, end_ms));
        boundaries = scoring_boundaries_add_unique(boundaries, clamp(real(us.end_ms ?? end_ms), start_ms, end_ms));
    }

    if (array_length(boundaries) > 1) {
        array_sort(boundaries, function(_a, _b) {
            return real(_a) - real(_b);
        });
    }

    var matching_ms = 0;
    var expected_active_ms = 0;
    var player_active_ms = 0;

    var _count_rests  = is_struct(_settings) && variable_struct_exists(_settings, "count_rests")
        ? bool(_settings[$ "count_rests"]) : false;

    for (var bi = 0; bi < array_length(boundaries) - 1; bi++) {
        var seg_a = real(boundaries[bi]);
        var seg_b = real(boundaries[bi + 1]);
        var seg_ms = max(0, seg_b - seg_a);
        if (seg_ms <= 0.0001) continue;

        var sample_t = seg_a + (seg_ms * 0.5);
        var planned_key = scoring_lane_key_at_time(planned, sample_t);
        var player_key  = scoring_lane_key_at_time(player,  sample_t);

        if (_count_rests) {
            // Count rests: rest-vs-rest matches count; use full window as denominator.
            if (planned_key == player_key) matching_ms += seg_ms;
            if (planned_key != "") expected_active_ms += seg_ms;
        } else {
            // Exclude rests: only score time where the tune expects a note.
            if (planned_key != "") {
                if (planned_key == player_key) matching_ms += seg_ms;
                expected_active_ms += seg_ms;
            }
        }
        if (player_key != "") player_active_ms += seg_ms;
    }

    var _denom = _count_rests ? total_ms : max(1, expected_active_ms);
    result.matching_ms = matching_ms;
    result.mismatch_ms = max(0, _denom - matching_ms);
    result.expected_active_ms = expected_active_ms;
    result.player_active_ms = player_active_ms;
    result.score = clamp((matching_ms / _denom) * 100, 0, 100);

    return result;
}

/// @function scoring_measure_results_to_map(_measure_results)
/// @description Convert an array of measure score results to a struct keyed by measure number string.
/// @param {array} _measure_results  Array of {measure, score, ...} structs
/// @returns {struct}  {"1": 85.2, "2": 90.0, ...}
function scoring_measure_results_to_map(_measure_results) {
    var out = {};
    if (!is_array(_measure_results)) return out;

    for (var i = 0; i < array_length(_measure_results); i++) {
        var m = _measure_results[i];
        if (!is_struct(m)) continue;
        var measure_num = floor(real(m.measure ?? -1));
        if (measure_num < 1) continue;
        out[$ string(measure_num)] = real(m.score ?? 0);
    }

    return out;
}

/// @function scoring_apply_run_to_runtime(_run_summary)
/// @description Store a scoring run summary into all runtime globals and update timeline_state maps. Called at the end of scoring_build_ms_overlap_summary.
/// @param {struct} _run_summary  Scoring summary struct from scoring_build_ms_overlap_summary
/// @param {bool} [_promote_selected]  When true, also promote this run to global top-level score fields and selected judge
/// @reads   global.timeline_state
/// @writes  global.scoring_last_run, global.performance_score, global.last_score, global.run_score, global.final_score, global.overall_score, global.timeline_state.score_selected_judge, global.timeline_state.score_measure_maps, global.timeline_state.score_overall_by_judge, global.timeline_state.score_raw_by_judge, global.timeline_state.score_measure_results_by_judge, global.timeline_state.score_by_segment
/// @objects none
/// @callers scoring_build_ms_overlap_summary
function scoring_apply_run_to_runtime(_run_summary, _promote_selected = true) {
    if (!is_struct(_run_summary)) return;

    var promote_selected = bool(_promote_selected);
    var overall = real(_run_summary.overall_score ?? 0);

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        if (promote_selected) {
            global.scoring_last_run = _run_summary;
            global.performance_score = overall;
            global.last_score = overall;
            global.run_score = overall;
            global.final_score = overall;
            global.overall_score = overall;
        }
        return;
    }

    var judge_id = string(_run_summary.judge_id ?? _run_summary.selected_judge_id ?? "ms_overlap");
    var measure_results = variable_struct_exists(_run_summary, "measure_scores")
        ? _run_summary.measure_scores
        : [];
    var map = scoring_measure_results_to_map(measure_results);

    if (!variable_struct_exists(global.timeline_state, "score_measure_maps") || !is_struct(global.timeline_state.score_measure_maps)) {
        variable_struct_set(global.timeline_state, "score_measure_maps", {});
    }
    var maps = variable_struct_get(global.timeline_state, "score_measure_maps");
    maps[$ judge_id] = map;
    variable_struct_set(global.timeline_state, "score_measure_maps", maps);

    if (!variable_struct_exists(global.timeline_state, "score_overall_by_judge") || !is_struct(global.timeline_state.score_overall_by_judge)) {
        variable_struct_set(global.timeline_state, "score_overall_by_judge", {});
    }
    var overall_map = variable_struct_get(global.timeline_state, "score_overall_by_judge");
    overall_map[$ judge_id] = overall;
    variable_struct_set(global.timeline_state, "score_overall_by_judge", overall_map);

    if (!variable_struct_exists(global.timeline_state, "score_raw_by_judge") || !is_struct(global.timeline_state.score_raw_by_judge)) {
        variable_struct_set(global.timeline_state, "score_raw_by_judge", {});
    }
    var raw_map = variable_struct_get(global.timeline_state, "score_raw_by_judge");
    raw_map[$ judge_id] = variable_struct_exists(_run_summary, "raw") ? _run_summary.raw : {};
    variable_struct_set(global.timeline_state, "score_raw_by_judge", raw_map);

    if (!variable_struct_exists(global.timeline_state, "score_measure_results_by_judge") || !is_struct(global.timeline_state.score_measure_results_by_judge)) {
        variable_struct_set(global.timeline_state, "score_measure_results_by_judge", {});
    }
    var results_map = variable_struct_get(global.timeline_state, "score_measure_results_by_judge");
    results_map[$ judge_id] = measure_results;
    variable_struct_set(global.timeline_state, "score_measure_results_by_judge", results_map);

    if (variable_struct_exists(_run_summary, "score_by_segment") && is_array(_run_summary.score_by_segment)) {
        var incoming = _run_summary.score_by_segment;
        var merged = (variable_struct_exists(global.timeline_state, "score_by_segment") && is_array(global.timeline_state.score_by_segment))
            ? global.timeline_state.score_by_segment
            : [];

        var n_in = array_length(incoming);
        if (!is_array(merged) || array_length(merged) < n_in) {
            var resized = array_create(n_in, undefined);
            for (var ri = 0; ri < array_length(merged); ri++) resized[ri] = merged[ri];
            merged = resized;
        }

        for (var si = 0; si < n_in; si++) {
            var src_seg = incoming[si];
            if (!is_struct(src_seg)) continue;

            var dst_seg = merged[si];
            if (!is_struct(dst_seg)) dst_seg = {};

            var src_maps = variable_struct_exists(src_seg, "score_measure_maps") && is_struct(src_seg.score_measure_maps)
                ? src_seg.score_measure_maps
                : {};
            var dst_maps = variable_struct_exists(dst_seg, "score_measure_maps") && is_struct(dst_seg.score_measure_maps)
                ? dst_seg.score_measure_maps
                : {};
            dst_maps[$ judge_id] = variable_struct_exists(src_maps, judge_id) ? src_maps[$ judge_id] : scoring_measure_results_to_map(src_seg.measure_scores ?? []);
            dst_seg.score_measure_maps = dst_maps;

            var dst_results_by_judge = variable_struct_exists(dst_seg, "measure_results_by_judge") && is_struct(dst_seg.measure_results_by_judge)
                ? dst_seg.measure_results_by_judge
                : {};
            dst_results_by_judge[$ judge_id] = variable_struct_exists(src_seg, "measure_scores") ? src_seg.measure_scores : [];
            dst_seg.measure_results_by_judge = dst_results_by_judge;

            var dst_overall_by_judge = variable_struct_exists(dst_seg, "overall_by_judge") && is_struct(dst_seg.overall_by_judge)
                ? dst_seg.overall_by_judge
                : {};
            dst_overall_by_judge[$ judge_id] = real(src_seg.overall_score ?? 0);
            dst_seg.overall_by_judge = dst_overall_by_judge;

            var dst_raw_by_judge = variable_struct_exists(dst_seg, "raw_by_judge") && is_struct(dst_seg.raw_by_judge)
                ? dst_seg.raw_by_judge
                : {};
            dst_raw_by_judge[$ judge_id] = variable_struct_exists(src_seg, "raw") ? src_seg.raw : {};
            dst_seg.raw_by_judge = dst_raw_by_judge;

            if (promote_selected) {
                dst_seg.measure_scores = variable_struct_exists(src_seg, "measure_scores") ? src_seg.measure_scores : [];
                dst_seg.overall_score = real(src_seg.overall_score ?? 0);
                dst_seg.raw = variable_struct_exists(src_seg, "raw") ? src_seg.raw : {};
                dst_seg.score_selected_judge = judge_id;
            } else if (!variable_struct_exists(dst_seg, "score_selected_judge")) {
                var seg_default_judge = variable_struct_exists(global.timeline_state, "score_selected_judge")
                    ? string(global.timeline_state.score_selected_judge)
                    : "ms_overlap";
                if (seg_default_judge == "") seg_default_judge = "ms_overlap";
                dst_seg.score_selected_judge = seg_default_judge;
            }

            merged[si] = dst_seg;
        }

        variable_struct_set(global.timeline_state, "score_by_segment", merged);
    }

    if (promote_selected) {
        global.scoring_last_run = _run_summary;
        global.performance_score = overall;
        global.last_score = overall;
        global.run_score = overall;
        global.final_score = overall;
        global.overall_score = overall;
        variable_struct_set(global.timeline_state, "score_selected_judge", judge_id);
    }
}

/// @function scoring_shift_player_spans(_spans, _offset_ms)
/// @description Return a copy of a player span array with all timestamps shifted by _offset_ms. Used to apply scoring_compare_offset_ms before comparison.
/// @param {array} _spans      Source span array {start_ms, end_ms, lane_idx, ...}
/// @param {real}  _offset_ms  Millisecond shift (positive = shift later, negative = shift earlier)
/// @returns {array}  New shifted span array (shallow field copy + adjusted timestamps)
function scoring_shift_player_spans(_spans, _offset_ms) {
    var out = [];
    if (!is_array(_spans)) return out;
    var n = array_length(_spans);
    for (var i = 0; i < n; i++) {
        var s = _spans[i];
        if (!is_struct(s)) continue;
        var keys = struct_get_names(s);
        var copy = {};
        for (var ki = 0; ki < array_length(keys); ki++) {
            copy[$ keys[ki]] = s[$ keys[ki]];
        }
        copy.start_ms = real(s.start_ms ?? 0) + _offset_ms;
        copy.end_ms   = real(s.end_ms   ?? 0) + _offset_ms;
        array_push(out, copy);
    }
    return out;
}

/// @function scoring_build_ms_overlap_summary(_export_info, _judge_id, _score_compare_offset_override_ms, _apply_to_runtime)
/// @description Run full ms_overlap scoring across all measures (tune or set mode), accumulate per-segment and overall scores, call scoring_apply_run_to_runtime, and return the summary struct.
/// @param {struct|undefined} [_export_info]  Optional {tune_id, bpm, swing} for context key generation
/// @param {string} [_judge_id]  Judge id to stamp on the summary (default "ms_overlap")
/// @param {real|undefined} [_score_compare_offset_override_ms]  Optional override for scoring compare offset; undefined uses timeline_cfg
/// @param {bool} [_apply_to_runtime]  True to promote this summary as active runtime score, false to cache only
/// @returns {struct}  Full scoring summary: {schema_version, judge_id, overall_score, measure_scores, raw, ...}
/// @reads   global.timeline_state (planned_spans, review_full_trace, player_in, measure_nav_entries, score_by_segment), global.playback_context, global.current_bpm, global.swing_mult, global.score_segments_sprites, global.score_snippet_durations, global.score_units_per_measure, global.score_has_pickup
/// @writes  global.scoring_last_run, global.performance_score, global.last_score, global.run_score, global.final_score, global.overall_score, global.timeline_state (via scoring_apply_run_to_runtime + score_by_segment), global.score_snippet_durations, global.score_units_per_measure, global.score_has_pickup
/// @objects none
/// @callers scr_button_scripts (end-of-tune path), obj_game_controller
function scoring_build_ms_overlap_summary(_export_info = undefined, _judge_id = "ms_overlap", _score_compare_offset_override_ms = undefined, _apply_to_runtime = true) {
    var tune_id = "";
    var bpm = variable_global_exists("current_bpm") ? real(global.current_bpm) : 0;
    var swing = variable_global_exists("swing_mult") ? string(global.swing_mult) : "";
    if (is_struct(_export_info)) {
        if (variable_struct_exists(_export_info, "tune_id")) tune_id = string(variable_struct_get(_export_info, "tune_id"));
        if (variable_struct_exists(_export_info, "bpm")) bpm = real(variable_struct_get(_export_info, "bpm"));
        if (variable_struct_exists(_export_info, "swing")) swing = string(variable_struct_get(_export_info, "swing"));
    }
    var player_key = scoring_get_player_id();

    var planned_spans = [];
    var player_spans = [];

    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        if (variable_struct_exists(global.timeline_state, "planned_spans") && is_array(variable_struct_get(global.timeline_state, "planned_spans"))) {
            planned_spans = variable_struct_get(global.timeline_state, "planned_spans");
        }
        if (variable_struct_exists(global.timeline_state, "review_full_trace")
            && is_array(variable_struct_get(global.timeline_state, "review_full_trace"))
            && array_length(variable_struct_get(global.timeline_state, "review_full_trace")) > 0) {
            player_spans = variable_struct_get(global.timeline_state, "review_full_trace");
        } else if (variable_struct_exists(global.timeline_state, "player_in") && is_array(variable_struct_get(global.timeline_state, "player_in"))) {
            player_spans = variable_struct_get(global.timeline_state, "player_in");
        }
    }

    // Scoring compare offset removed from calibration model (must keep feedback honest)
    if (!is_undefined(_score_compare_offset_override_ms)) {
        scoring_calibration_debug_log("[JUDGE_BUILD] " + string(_judge_id) + " | override=" + string(_score_compare_offset_override_ms) + " [IGNORED]");
    }

    var _settings = scoring_ms_overlap_get_effective_settings();
    var _count_rests = bool(_settings.count_rests);
    var judge_id = string(_judge_id);
    if (judge_id == "") judge_id = "ms_overlap";
    var judge_name = (judge_id == "ms_overlap_uncal") ? "Matching time (Uncalibrated)" : "Matching time (Calibrated)";

    // Overall accumulators (aggregated across all scored measures)
    var measures_out = [];
    var total_ms = 0;
    var matching_ms = 0;
    var expected_active_ms = 0;
    var player_active_ms = 0;

    // --- Set mode: score each segment independently using its own nav entries ---
    var _is_set = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";

    if (_is_set) {
        var _segs = global.playback_context[$ "segments"];
        if (!is_array(_segs)) _segs = [];
        var _seg_count = array_length(_segs);
        var _score_by_seg = array_create(_seg_count, undefined);
        var _seg_score_cache = variable_global_exists("score_segments_sprites")
            ? global.score_segments_sprites
            : [];

        // Preserve active segment score metadata so this scoring pass does not
        // leave global score state pointing at an arbitrary segment.
        var _saved_durations = variable_global_exists("score_snippet_durations")
            ? global.score_snippet_durations
            : [];
        var _saved_units_per_measure = variable_global_exists("score_units_per_measure")
            ? real(global.score_units_per_measure)
            : 0;
        var _saved_has_pickup = variable_global_exists("score_has_pickup")
            ? bool(global.score_has_pickup)
            : false;

        for (var _si = 0; _si < _seg_count; _si++) {
            var _seg = _segs[_si];
            if (!is_struct(_seg)) { _score_by_seg[_si] = undefined; continue; }

            // Ensure nav-building uses this segment's exported snippet metadata.
            // Without this, all segments inherit whichever tune bundle is
            // currently loaded globally (often the final segment in the set).
            var _seg_cache_ok = is_array(_seg_score_cache)
                && _si >= 0
                && _si < array_length(_seg_score_cache)
                && is_struct(_seg_score_cache[_si]);
            if (_seg_cache_ok) {
                var _seg_cache = _seg_score_cache[_si];
                if (variable_global_exists("score_snippet_durations")) {
                    global.score_snippet_durations = _seg_cache[$ "durations"] ?? [];
                }
                if (variable_global_exists("score_units_per_measure")) {
                    global.score_units_per_measure = real(_seg_cache[$ "units_per_measure"] ?? 0);
                }
                if (variable_global_exists("score_has_pickup")) {
                    global.score_has_pickup = bool(_seg_cache[$ "has_pickup"] ?? false);
                }
            }

            // Build nav from bar_events.
            // bar_events in playback_context have absolute times (scr_playback_context_build_for_set
            // deep-copies them and syncs all time fields to the offset-mutated value).
            var _bar_evts = _seg[$ "bar_events"] ?? [];
            var _nav = gv_build_measure_nav_map(_bar_evts);
            var _seg_start_ms = real(_seg[$ "start_ms"] ?? 0);
            var _seg_end_ms   = real(_seg[$ "end_ms"]   ?? 0);
            // Clamp the last entry's end_ms to the segment boundary (gv_build_measure_nav_map
            // may set it to gv_get_planned_end_ms() — the total set duration, not segment end).
            if (_seg_end_ms > 0 && is_array(_nav.entries) && array_length(_nav.entries) > 0) {
                _nav.entries[array_length(_nav.entries) - 1].end_ms = _seg_end_ms;
            }

            // Clip spans to this segment's time window.
            var _seg_planned = scoring_filter_spans_in_window(planned_spans, _seg_start_ms, _seg_end_ms);
            var _seg_player  = scoring_filter_spans_in_window(player_spans,  _seg_start_ms, _seg_end_ms);

            var _seg_measures = [];
            var _seg_n = is_array(_nav.entries) ? array_length(_nav.entries) : 0;
            for (var _mi = 0; _mi < _seg_n; _mi++) {
                var e = _nav.entries[_mi];
                if (!is_struct(e)) continue;
                if (floor(real(e.measure ?? -1)) < 1) continue;
                var scored = scoring_score_measure_ms_overlap(e, _seg_planned, _seg_player, _settings);
                if (real(scored.expected_active_ms ?? 0) < 1) continue;
                array_push(_seg_measures, scored);
                array_push(measures_out, scored);
                total_ms           += real(scored.total_ms ?? 0);
                matching_ms        += real(scored.matching_ms ?? 0);
                expected_active_ms += real(scored.expected_active_ms ?? 0);
                player_active_ms   += real(scored.player_active_ms ?? 0);
            }

            // Compute per-segment overall score.
            var _seg_match_ms = 0; var _seg_exp_ms = 0; var _seg_tot_ms = 0; var _seg_play_ms = 0;
            for (var _smi = 0; _smi < array_length(_seg_measures); _smi++) {
                var _sm = _seg_measures[_smi];
                _seg_match_ms += real(_sm.matching_ms        ?? 0);
                _seg_exp_ms   += real(_sm.expected_active_ms ?? 0);
                _seg_tot_ms   += real(_sm.total_ms           ?? 0);
                _seg_play_ms  += real(_sm.player_active_ms   ?? 0);
            }
            var _seg_denom   = _count_rests ? _seg_tot_ms : max(1, _seg_exp_ms);
            var _seg_overall = (_seg_denom > 0) ? clamp((_seg_match_ms / _seg_denom) * 100, 0, 100) : 0;
            var _seg_raw = {
                total_ms: _seg_tot_ms, matching_ms: _seg_match_ms,
                mismatch_ms: max(0, _seg_denom - _seg_match_ms),
                expected_active_ms: _seg_exp_ms, player_active_ms: _seg_play_ms,
                match_ratio: (_seg_denom > 0) ? (_seg_match_ms / _seg_denom) : 0
            };
            // Store per-segment score map keyed by judge_id.
            var _seg_map  = scoring_measure_results_to_map(_seg_measures);
            var _seg_maps = {};
            _seg_maps[$ judge_id] = _seg_map;
            var _seg_results_by_judge = {};
            _seg_results_by_judge[$ judge_id] = _seg_measures;
            var _seg_overall_by_judge = {};
            _seg_overall_by_judge[$ judge_id] = _seg_overall;
            var _seg_raw_by_judge = {};
            _seg_raw_by_judge[$ judge_id] = _seg_raw;
            _score_by_seg[_si] = {
                score_measure_maps:   _seg_maps,
                score_selected_judge: judge_id,
                measure_scores:       _seg_measures,
                measure_results_by_judge: _seg_results_by_judge,
                overall_by_judge: _seg_overall_by_judge,
                raw_by_judge: _seg_raw_by_judge,
                overall_score:        _seg_overall,
                raw:                  _seg_raw
            };
        }

        if (variable_global_exists("score_snippet_durations")) {
            global.score_snippet_durations = _saved_durations;
        }
        if (variable_global_exists("score_units_per_measure")) {
            global.score_units_per_measure = _saved_units_per_measure;
        }
        if (variable_global_exists("score_has_pickup")) {
            global.score_has_pickup = _saved_has_pickup;
        }

    } else {
        // --- Tune mode: score using current timeline measure entries ---
        var measure_entries = scoring_measure_entries_from_timeline();
        var scored_entry_count = array_length(measure_entries);
        for (var i = 0; i < scored_entry_count; i++) {
            var e = measure_entries[i];
            if (!is_struct(e)) continue;
            if (floor(real(e.measure ?? -1)) < 1) continue;
            var scored = scoring_score_measure_ms_overlap(e, planned_spans, player_spans, _settings);
            if (real(scored.expected_active_ms ?? 0) < 1) continue;
            array_push(measures_out, scored);
            total_ms           += real(scored.total_ms ?? 0);
            matching_ms        += real(scored.matching_ms ?? 0);
            expected_active_ms += real(scored.expected_active_ms ?? 0);
            player_active_ms   += real(scored.player_active_ms ?? 0);
        }
    }

    var _overall_denom = _count_rests ? total_ms : max(1, expected_active_ms);
    var overall_score = (_overall_denom > 0) ? clamp((matching_ms / _overall_denom) * 100, 0, 100) : 0;
    var raw = {
        total_ms: total_ms,
        matching_ms: matching_ms,
        mismatch_ms: max(0, _overall_denom - matching_ms),
        expected_active_ms: expected_active_ms,
        player_active_ms: player_active_ms,
        match_ratio: (_overall_denom > 0) ? (matching_ms / _overall_denom) : 0
    };

    var summary = {
        schema_version: 1,
        judge_id: judge_id,
        judge_name: judge_name,
        score_version: "v1",
        player_id: player_key,
        tune_id: tune_id,
        bpm: bpm,
        swing: swing,
        part_key: "all",
        context_key: scoring_get_context_key(tune_id, player_key, bpm, swing, "all"),
        selected_judge_id: judge_id,
        overall_score: overall_score,
        measure_scores: measures_out,
        raw: raw,
        score_by_segment: _is_set ? _score_by_seg : []
    };

    scoring_apply_run_to_runtime(summary, bool(_apply_to_runtime));
    return summary;
}

/// @function scoring_score_to_color(_score)
/// @description Map a 0–100 score to a grade-band RGB color (A=green, F=red).
/// @param {real} _score  Score value 0–100
/// @returns {real}  GameMaker color value
function scoring_score_to_color(_score) {
    var s = clamp(real(_score), 0, 100);
    if (s >= 90) return make_color_rgb(54, 122, 68);    // A
    if (s >= 80) return make_color_rgb(108, 148, 64);   // B
    if (s >= 70) return make_color_rgb(188, 156, 52);   // C
    if (s >= 60) return make_color_rgb(194, 112, 48);   // D
    return make_color_rgb(210, 80, 80);                 // F
}

/// @function scoring_score_to_grade(_score)
/// @description Convert a 0–100 score to a letter grade (A–F) using thresholds from scoring settings.
/// @param {real} _score  Score value 0–100
/// @returns {string}  Letter grade "A".."F"
/// @reads   global.judge_settings_store (via scoring_ms_overlap_get_effective_settings)
function scoring_score_to_grade(_score) {
    var s = clamp(real(_score), 0, 100);
    var cfg = scoring_ms_overlap_get_effective_settings();
    if (s >= real(cfg.grade_a)) return "A";
    if (s >= real(cfg.grade_b)) return "B";
    if (s >= real(cfg.grade_c)) return "C";
    if (s >= real(cfg.grade_d)) return "D";
    return "F";
}

/// @function scoring_get_measure_visual_style(_measure, _default_color, _default_alpha)
/// @description Return a visual style struct for a measure based on its last scoring run. Returns default style if no data. Set-mode aware: reads active segment's score map.
/// @param {real} _measure        Measure number (1-based)
/// @param {real} _default_color  Fallback color
/// @param {real} _default_alpha  Fallback alpha
/// @returns {struct}  {has_score: bool, color, alpha, score}
/// @reads   global.timeline_state (score_selected_judge, score_measure_maps, score_by_segment), global.playback_context
/// @callers scr_game_viz (draw path)
function scoring_get_measure_visual_style(_measure, _default_color, _default_alpha) {
    var out = {
        has_score: false,
        color: _default_color,
        alpha: _default_alpha,
        score: -1
    };

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;

    var judge_id = variable_struct_exists(global.timeline_state, "score_selected_judge")
        ? string(global.timeline_state.score_selected_judge)
        : "ms_overlap";

    // In set mode, read from the per-segment score data so measure numbers 1-N
    // resolve correctly for each tune rather than colliding across segments.
    var score_maps = undefined;
    var _is_set = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";

    if (_is_set
        && variable_struct_exists(global.timeline_state, "score_by_segment")
        && is_array(global.timeline_state.score_by_segment)) {
        var _active_seg = floor(real(global.playback_context[$ "active_segment"] ?? 0));
        var _by_seg = global.timeline_state.score_by_segment;
        var _seg_count = array_length(_by_seg);
        if (_seg_count > 0) {
            _active_seg = clamp(_active_seg, 0, _seg_count - 1);
            var _seg_data = _by_seg[_active_seg];
            if (is_struct(_seg_data) && variable_struct_exists(_seg_data, "score_measure_maps")) {
                score_maps = _seg_data.score_measure_maps;
            }
        }
    } else {
        if (variable_struct_exists(global.timeline_state, "score_measure_maps")
            && is_struct(global.timeline_state.score_measure_maps)) {
            score_maps = global.timeline_state.score_measure_maps;
        }
    }

    if (!is_struct(score_maps)) return out;
    if (!variable_struct_exists(score_maps, judge_id) || !is_struct(score_maps[$ judge_id])) return out;

    var measure_map = score_maps[$ judge_id];
    var measure_key = string(floor(real(_measure)));
    if (!variable_struct_exists(measure_map, measure_key)) return out;

    var measure_score = clamp(real(measure_map[$ measure_key]), 0, 100);
    out.has_score = true;
    out.score = measure_score;
    out.color = scoring_score_to_color(measure_score);
    out.alpha = clamp(0.72 + ((measure_score / 100) * 0.18), 0.68, 0.92);
    return out;
}

/// @function scoring_get_last_run_summary()
/// @description Return the most recent scoring run summary struct, or undefined if none yet.
/// @returns {struct|undefined}  Last run summary from scoring_build_ms_overlap_summary
/// @reads   global.scoring_last_run
/// @callers scoring_find_measure_result, scoring_get_ui_overview_rows, scoring_get_judge_table_rows, etc.
function scoring_get_last_run_summary() {
    if (variable_global_exists("scoring_last_run") && is_struct(global.scoring_last_run)) {
        return global.scoring_last_run;
    }
    return undefined;
}

/// @function scoring_find_measure_result(_measure_num, _judge_id)
/// @description Find and return the measure result struct for the given measure number and judge.
/// @param {real} _measure_num  Measure number (1-based)
/// @param {string} [_judge_id] Judge id (default "ms_overlap")
/// @returns {struct|undefined}  Measure result {measure, score, matching_ms, ...} or undefined
/// @reads   global.scoring_last_run, global.timeline_state (score_by_segment), global.playback_context
/// @callers scr_game_viz, scoring_get_detail_popup_rows, scoring_get_panel_focus
function scoring_find_measure_result(_measure_num, _judge_id = "ms_overlap") {
    var judge_id = string(_judge_id);
    if (judge_id == "") judge_id = "ms_overlap";

    // In set mode, look in the active segment's data so measure numbers 1-N
    // resolve to the correct tune instead of always matching tune 1.
    var _is_set = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    if (_is_set
        && variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_by_segment")
        && is_array(global.timeline_state.score_by_segment)) {
        var _active = floor(real(global.playback_context[$ "active_segment"] ?? 0));
        var _by_seg = global.timeline_state.score_by_segment;
        var _seg_count = array_length(_by_seg);
        if (_seg_count > 0) {
            _active = clamp(_active, 0, _seg_count - 1);
            var _seg_data = _by_seg[_active];
            if (is_struct(_seg_data)) {
                var arr = [];
                if (variable_struct_exists(_seg_data, "measure_results_by_judge")
                    && is_struct(_seg_data.measure_results_by_judge)
                    && variable_struct_exists(_seg_data.measure_results_by_judge, judge_id)
                    && is_array(_seg_data.measure_results_by_judge[$ judge_id])) {
                    arr = _seg_data.measure_results_by_judge[$ judge_id];
                } else if (variable_struct_exists(_seg_data, "measure_scores") && is_array(_seg_data.measure_scores)) {
                    arr = _seg_data.measure_scores;
                }

                var target = floor(real(_measure_num));
                for (var i = 0; i < array_length(arr); i++) {
                    var m = arr[i];
                    if (!is_struct(m)) continue;
                    if (floor(real(m.measure ?? -1)) == target) return m;
                }
                return undefined;
            }
        }
    }

    var summary = scoring_get_last_run_summary();
    var arr = [];
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_measure_results_by_judge")
        && is_struct(global.timeline_state.score_measure_results_by_judge)
        && variable_struct_exists(global.timeline_state.score_measure_results_by_judge, judge_id)
        && is_array(global.timeline_state.score_measure_results_by_judge[$ judge_id])) {
        arr = global.timeline_state.score_measure_results_by_judge[$ judge_id];
    } else {
        if (!is_struct(summary)) return undefined;
        if (!variable_struct_exists(summary, "measure_scores") || !is_array(variable_struct_get(summary, "measure_scores"))) return undefined;
        arr = variable_struct_get(summary, "measure_scores");
    }

    var target = floor(real(_measure_num));
    for (var i = 0; i < array_length(arr); i++) {
        var m = arr[i];
        if (!is_struct(m)) continue;
        if (floor(real(m.measure ?? -1)) == target) return m;
    }
    return undefined;
}

/// @function scoring_get_ui_overview_rows()
/// @description Build a string array of overview scoring rows for display in the post-tune result panel.
/// @returns {array}  String rows like ["Judge: MS Overlap", "Score: 85.5% (B)", ...]
function scoring_get_ui_overview_rows() {
    var rows = [];
    var summary = scoring_get_last_run_summary();
    if (!is_struct(summary)) return rows;

    var raw = variable_struct_exists(summary, "raw") ? variable_struct_get(summary, "raw") : {};
    var overall_value = variable_struct_exists(summary, "overall_score") ? real(variable_struct_get(summary, "overall_score")) : 0;
    var match_ratio = variable_struct_exists(raw, "match_ratio") ? (real(variable_struct_get(raw, "match_ratio")) * 100) : 0;
    var matching_ms = variable_struct_exists(raw, "matching_ms") ? real(variable_struct_get(raw, "matching_ms")) : 0;
    var total_ms = variable_struct_exists(raw, "total_ms") ? real(variable_struct_get(raw, "total_ms")) : 0;
    var grade = scoring_score_to_grade(overall_value);

    array_push(rows, "Judge: MS Overlap");
    array_push(rows, "Score: " + string_format(overall_value, 0, 2) + "% (" + grade + ")");
    array_push(rows, "Matched: " + string(round(matching_ms)) + " / " + string(round(total_ms)) + " ms");
    array_push(rows, "Ratio: " + string_format(match_ratio, 0, 2) + "%");
    return rows;
}

/// @function scoring_get_current_context_stats()
/// @description Build play history stats (play count, best/avg score) for the current tune and context.
/// Uses dynamic script_execute to read from event_history. Returns a default zero struct if unavailable.
/// @returns {struct}  {has_context, plays_count, best_score, avg_score}
function scoring_get_current_context_stats() {
    var out = {
        plays_count: 0,
        best_score: "-",
        avg_score: "-",
        has_context: false
    };

    var export_info_idx = asset_get_index("event_history_get_export_info");
    var load_index_idx = asset_get_index("event_history_load_tune_history_index");
    if (!script_exists(export_info_idx) || !script_exists(load_index_idx)) {
        return out;
    }

    var info = script_execute(export_info_idx);
    if (!is_struct(info)) return out;

    var tune_id = string(variable_struct_exists(info, "tune_id") ? variable_struct_get(info, "tune_id") : "");
    var player_key = string(variable_struct_exists(info, "player_id") ? variable_struct_get(info, "player_id") : "default");
    var part_key = string(variable_struct_exists(info, "part_key") ? variable_struct_get(info, "part_key") : "all");
    var bpm_key = real(variable_struct_exists(info, "bpm") ? variable_struct_get(info, "bpm") : 0);
    var swing_key = string(variable_struct_exists(info, "swing") ? variable_struct_get(info, "swing") : "");
    var context_id = tune_id + "|" + string_lower(player_key) + "|" + string(bpm_key) + "|" + swing_key + "|" + part_key;

    var history_index = script_execute(load_index_idx);
    var tunes = is_struct(history_index) && variable_struct_exists(history_index, "tunes")
        ? variable_struct_get(history_index, "tunes")
        : [];
    if (!is_array(tunes)) return out;

    for (var i = 0; i < array_length(tunes); i++) {
        var tune_entry = tunes[i];
        if (!is_struct(tune_entry)) continue;
        if (string(variable_struct_exists(tune_entry, "id") ? variable_struct_get(tune_entry, "id") : "") != tune_id) continue;

        var contexts = variable_struct_exists(tune_entry, "contexts") ? variable_struct_get(tune_entry, "contexts") : [];
        if (!is_array(contexts)) return out;

        for (var j = 0; j < array_length(contexts); j++) {
            var ctx = contexts[j];
            if (!is_struct(ctx)) continue;
            if (string(variable_struct_exists(ctx, "id") ? variable_struct_get(ctx, "id") : "") != context_id) continue;

            out.has_context = true;
            out.plays_count = max(0, floor(real(variable_struct_exists(ctx, "plays_count") ? variable_struct_get(ctx, "plays_count") : 0)));
            out.best_score = string(variable_struct_exists(ctx, "best_score") ? variable_struct_get(ctx, "best_score") : "-");

            var avg_raw = string(variable_struct_exists(ctx, "avg_score") ? variable_struct_get(ctx, "avg_score") : "");
            if (avg_raw == "") {
                var avg_real = real(variable_struct_exists(ctx, "avg_score_real") ? variable_struct_get(ctx, "avg_score_real") : -1);
                if (avg_real >= 0) avg_raw = string_format(avg_real, 0, 2);
            }
            out.avg_score = (avg_raw == "") ? "-" : avg_raw;
            return out;
        }

        return out;
    }

    return out;
}

/// @function scoring_format_optional_percent(_v)
/// @description Format optional numeric score values as integer percent text, preserving "-" for missing values.
/// @param _v Value from history stats
/// @returns {string} Formatted percent or "-"
function scoring_format_optional_percent(_v) {
    if (!is_numeric(_v) && (string(_v) == "-" || string(_v) == "")) return "-";
    var _r = real(_v);
    return (_r > 0 || string(_v) == "0") ? string(floor(clamp(_r, 0, 100))) + "%" : "-";
}

/// @function scoring_get_judge_table_rows(_measure_num, _judge_id)
/// @description Build row data for the judge results table in the scoring UI. Returns one row per active judge with score/grade/best/avg/plays fields.
/// @param {real}   [_measure_num]  Measure to focus on (-1 = overall)
/// @param {string} [_judge_id]     Judge ID (default "ms_overlap")
/// @returns {array}  Array of judge row structs {judge_id, judge_name, score, grade, best, avg, plays}
/// @reads   global.scoring_last_run (via helpers), global.timeline_state (via scoring_find_measure_result)
function scoring_get_judge_table_rows(_measure_num = -1, _judge_id = "") {
    var rows = [];
    var summary = scoring_get_last_run_summary();
    var context_stats = scoring_get_current_context_stats();
    if (!is_struct(summary)) return rows;

    var judge_filter = string(_judge_id);
    var registry = scoring_judge_settings_get_registry();
    if (!is_array(registry)) registry = [];

    var overall_by_judge = (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_overall_by_judge")
        && is_struct(global.timeline_state.score_overall_by_judge))
        ? global.timeline_state.score_overall_by_judge
        : {};

    var measure_num = floor(real(_measure_num));
    var plays_text = string(variable_struct_exists(context_stats, "plays_count") ? variable_struct_get(context_stats, "plays_count") : 0);

    for (var ri = 0; ri < array_length(registry); ri++) {
        var r = registry[ri];
        if (!is_struct(r)) continue;
        if (!bool(r.enabled ?? true)) continue;

        var rid = string(r.id ?? "");
        if (rid == "") continue;
        if (judge_filter != "" && judge_filter != rid) continue;

        var run_score = variable_struct_exists(overall_by_judge, rid)
            ? real(overall_by_judge[$ rid])
            : (rid == string(summary.judge_id ?? "") ? real(summary.overall_score ?? 0) : 0);
        var display_score = run_score;
        if (measure_num >= 1) {
            var m_result = scoring_find_measure_result(measure_num, rid);
            if (is_struct(m_result)) {
                display_score = real(variable_struct_exists(m_result, "score") ? variable_struct_get(m_result, "score") : run_score);
            }
        }

        var run_score_text = string(floor(clamp(display_score, 0, 100))) + "%";
        var grade = scoring_score_to_grade(display_score);

        array_push(rows, {
            judge_id: rid,
            judge_name: string(r.name ?? rid),
            score: run_score_text,
            grade: grade,
            best: scoring_format_optional_percent(variable_struct_exists(context_stats, "best_score") ? variable_struct_get(context_stats, "best_score") : "-"),
            avg: scoring_format_optional_percent(variable_struct_exists(context_stats, "avg_score") ? variable_struct_get(context_stats, "avg_score") : "-"),
            plays: plays_text
        });
    }

    return rows;
}

/// @function scoring_get_detail_popup_rows(_measure_num, _judge_id)
/// @description Build string rows for the per-measure (or overall) scoring detail popup.
/// @param {real}   [_measure_num]  Measure to report on (-1 = overall)
/// @param {string} [_judge_id]     Judge ID (default "ms_overlap")
/// @returns {array}  String rows for display
/// @reads   global.scoring_last_run, global.timeline_state (score_by_segment), global.playback_context
function scoring_get_detail_popup_rows(_measure_num = -1, _judge_id = "ms_overlap") {
    var rows = [];
    var judge_id = string(_judge_id);
    if (judge_id == "") judge_id = "ms_overlap";
    var judge_name = (judge_id == "ms_overlap_uncal") ? "Matching time (Uncalibrated)" : "Matching time (Calibrated)";

    var summary = scoring_get_last_run_summary();

    // In set mode, use the active segment's data as the default scope.
    var _is_set = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _seg_data = undefined;
    if (_is_set
        && variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_by_segment")
        && is_array(global.timeline_state.score_by_segment)) {
        var _active = floor(real(global.playback_context[$ "active_segment"] ?? 0));
        var _by_seg = global.timeline_state.score_by_segment;
        var _seg_count = array_length(_by_seg);
        if (_seg_count > 0) {
            _active = clamp(_active, 0, _seg_count - 1);
            _seg_data = _by_seg[_active];
        }
    }

    if (!is_struct(summary) && !is_struct(_seg_data)) {
        array_push(rows, "No scoring data available.");
        return rows;
    }

    // Default overall stats from segment (set mode) or flat summary (tune mode).
    var raw = {};
    var score_value = 0;
    if (is_struct(_seg_data)) {
        var _seg_raw_by_judge = variable_struct_exists(_seg_data, "raw_by_judge")
            ? variable_struct_get(_seg_data, "raw_by_judge")
            : {};
        if (is_struct(_seg_raw_by_judge) && variable_struct_exists(_seg_raw_by_judge, judge_id)) {
            raw = _seg_raw_by_judge[$ judge_id];
        } else {
            raw = _seg_data[$ "raw"] ?? {};
        }
        var _seg_overall_by_judge = variable_struct_exists(_seg_data, "overall_by_judge")
            ? variable_struct_get(_seg_data, "overall_by_judge")
            : {};
        if (is_struct(_seg_overall_by_judge) && variable_struct_exists(_seg_overall_by_judge, judge_id)) {
            score_value = real(_seg_overall_by_judge[$ judge_id]);
        } else {
            score_value = real(_seg_data[$ "overall_score"] ?? 0);
        }
    } else if (is_struct(summary)) {
        raw = variable_struct_exists(summary, "raw") ? variable_struct_get(summary, "raw") : {};
        score_value = real(variable_struct_exists(summary, "overall_score") ? variable_struct_get(summary, "overall_score") : 0);
        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "score_raw_by_judge")
            && is_struct(global.timeline_state.score_raw_by_judge)
            && variable_struct_exists(global.timeline_state.score_raw_by_judge, judge_id)) {
            raw = global.timeline_state.score_raw_by_judge[$ judge_id];
        }
        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "score_overall_by_judge")
            && is_struct(global.timeline_state.score_overall_by_judge)
            && variable_struct_exists(global.timeline_state.score_overall_by_judge, judge_id)) {
            score_value = real(global.timeline_state.score_overall_by_judge[$ judge_id]);
        }
    }
    var matching_ms = real(variable_struct_exists(raw, "matching_ms") ? variable_struct_get(raw, "matching_ms") : 0);
    var total_ms = max(1, real(variable_struct_exists(raw, "total_ms") ? variable_struct_get(raw, "total_ms") : 0));
    var expected_active_ms = real(variable_struct_exists(raw, "expected_active_ms") ? variable_struct_get(raw, "expected_active_ms") : total_ms);
    var player_active_ms = real(variable_struct_exists(raw, "player_active_ms") ? variable_struct_get(raw, "player_active_ms") : matching_ms);

    var measure_num = floor(real(_measure_num));
    var detail_scope = "overall";

    if (measure_num >= 1) {
        var m = scoring_find_measure_result(measure_num, judge_id);
        if (is_struct(m)) {
            score_value = real(variable_struct_exists(m, "score") ? variable_struct_get(m, "score") : score_value);
            matching_ms = real(variable_struct_exists(m, "matching_ms") ? variable_struct_get(m, "matching_ms") : matching_ms);
            total_ms = max(1, real(variable_struct_exists(m, "total_ms") ? variable_struct_get(m, "total_ms") : total_ms));
            expected_active_ms = real(variable_struct_exists(m, "expected_active_ms") ? variable_struct_get(m, "expected_active_ms") : expected_active_ms);
            player_active_ms = real(variable_struct_exists(m, "player_active_ms") ? variable_struct_get(m, "player_active_ms") : player_active_ms);
            detail_scope = "measure " + string(measure_num);
        }
    }

    var mismatch_ms = max(0, total_ms - matching_ms);

    array_push(rows, "Judge: " + judge_name);
    array_push(rows, "Scope: " + detail_scope);
    array_push(rows, "Score: " + string(round(clamp(score_value, 0, 100))) + "%");
    array_push(rows, "Matching ms: " + string(round(matching_ms)));
    array_push(rows, "Total ms: " + string(round(total_ms)));
    array_push(rows, "Mismatch ms: " + string(round(mismatch_ms)));
    array_push(rows, "Expected active: " + string(round(expected_active_ms)) + " ms");
    array_push(rows, "Player active: " + string(round(player_active_ms)) + " ms");

    return rows;
}

/// @function scoring_get_measure_popup_rows(_measure_num)
/// @description Delegates to scoring_get_detail_popup_rows for measure-specific popup.
/// @param {real} _measure_num  Measure number (1-based)
/// @returns {array}  String rows
function scoring_get_measure_popup_rows(_measure_num) {
    var judge_id = (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_selected_judge"))
        ? string(global.timeline_state.score_selected_judge)
        : "ms_overlap";
    return scoring_get_detail_popup_rows(_measure_num, judge_id);
}

/// @function scoring_get_panel_focus(_measure_num, _judge_id)
/// @description Build a panel focus struct for the scoring panel header (judge name, score %, subtitle).
/// @param {real}   [_measure_num]  Focused measure (-1 = overall)
/// @param {string} [_judge_id]     Judge ID (default "ms_overlap")
/// @returns {struct}  {judge_id, judge_name, score_value, score_percent_text, subtitle}
/// @reads   global.scoring_last_run, global.timeline_state (score_by_segment), global.playback_context
function scoring_get_panel_focus(_measure_num = -1, _judge_id = "ms_overlap") {
    var summary = scoring_get_last_run_summary();
    var judge_id = is_string(_judge_id) && string_length(_judge_id) > 0 ? string(_judge_id) : "ms_overlap";
    var judge_name = (judge_id == "ms_overlap_uncal") ? "Matching time (Uncalibrated)" : "Matching time (Calibrated)";
    var score_value = 0;
    var subtitle = "overall";

    // In set mode use the active segment's overall score for the panel default,
    // so the displayed % matches the current tune rather than the full set aggregate.
    var _is_set = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _seg_data = undefined;
    if (_is_set
        && variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "score_by_segment")
        && is_array(global.timeline_state.score_by_segment)) {
        var _active = floor(real(global.playback_context[$ "active_segment"] ?? 0));
        var _by_seg = global.timeline_state.score_by_segment;
        var _seg_count = array_length(_by_seg);
        if (_seg_count > 0) {
            _active = clamp(_active, 0, _seg_count - 1);
            _seg_data = _by_seg[_active];
        }
    }

    if (is_struct(_seg_data)) {
        var _focus_overall_by_judge = variable_struct_exists(_seg_data, "overall_by_judge")
            ? variable_struct_get(_seg_data, "overall_by_judge")
            : {};
        if (is_struct(_focus_overall_by_judge) && variable_struct_exists(_focus_overall_by_judge, judge_id)) {
            score_value = real(_focus_overall_by_judge[$ judge_id]);
        } else {
            score_value = real(_seg_data[$ "overall_score"] ?? 0);
        }
    } else if (is_struct(summary)) {
        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "score_overall_by_judge")
            && is_struct(global.timeline_state.score_overall_by_judge)
            && variable_struct_exists(global.timeline_state.score_overall_by_judge, judge_id)) {
            score_value = real(global.timeline_state.score_overall_by_judge[$ judge_id]);
        } else {
            score_value = real(variable_struct_exists(summary, "overall_score") ? variable_struct_get(summary, "overall_score") : 0);
        }
    }

    if (is_struct(summary) || is_struct(_seg_data)) {
        var measure_num = floor(real(_measure_num));
        if (measure_num >= 1) {
            var m = scoring_find_measure_result(measure_num, judge_id);
            if (is_struct(m)) {
                score_value = real(variable_struct_exists(m, "score") ? variable_struct_get(m, "score") : score_value);
                subtitle = "measure " + string(measure_num);
            }
        }
    }

    return {
        judge_id: judge_id,
        judge_name: judge_name,
        score_value: score_value,
        score_percent_text: string(round(clamp(score_value, 0, 100))) + "%",
        subtitle: subtitle
    };
}

/// @function scoring_profile_get_player_id(_player_id)
/// @description Resolve and sanitize player ID (alphanumeric + _ -) for use as a file path component. Falls back to global.current_player_id then "player_1".
/// @param {string} [_player_id]  Explicit player ID or undefined
/// @returns {string}  Lowercase sanitized player ID
/// @reads   global.current_player_id
function scoring_profile_get_player_id(_player_id = undefined) {
    var pid = "player_1";
    if (!is_undefined(_player_id)) pid = string(_player_id);
    else if (variable_global_exists("current_player_id")) pid = string(global.current_player_id);

    pid = string_trim(pid);
    if (pid == "") pid = "player_1";

    var safe = "";
    var n = string_length(pid);
    for (var i = 1; i <= n; i++) {
        var ch = string_copy(pid, i, 1);
        var code = ord(ch);
        var is_num = (code >= 48 && code <= 57);
        var is_upper = (code >= 65 && code <= 90);
        var is_lower = (code >= 97 && code <= 122);
        var is_ok = is_num || is_upper || is_lower || ch == "_" || ch == "-";
        safe += is_ok ? ch : "_";
    }

    if (safe == "") safe = "player_1";
    return string_lower(safe);
}

/// @function scoring_profile_get_root_folder()
/// @description Return the root config directory path ("datafiles/config").
/// @returns {string}  Root folder path
function scoring_profile_get_root_folder() {
    return "datafiles/config";
}

/// @function scoring_profile_get_player_folder(_player_id)
/// @description Return the per-player config directory path.
/// @returns {string}  Path: "datafiles/config/players/{id}"
function scoring_profile_get_player_folder(_player_id = undefined) {
    return scoring_profile_get_root_folder() + "/players/" + scoring_profile_get_player_id(_player_id);
}

/// @function scoring_profile_get_judge_settings_path(_player_id)
/// @description Return the full path to the judge_settings.json for a player.
/// @returns {string}  File path
function scoring_profile_get_judge_settings_path(_player_id = undefined) {
    return scoring_profile_get_player_folder(_player_id) + "/judge_settings.json";
}

/// @function scoring_profile_ensure_player_folder(_player_id)
/// @description Create datafiles/config, players/, and per-player directories if they don't exist.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {string}  The player folder path
function scoring_profile_ensure_player_folder(_player_id = undefined) {
    var root = scoring_profile_get_root_folder();
    if (!directory_exists(root)) directory_create(root);

    var players = root + "/players";
    if (!directory_exists(players)) directory_create(players);

    var folder = scoring_profile_get_player_folder(_player_id);
    if (!directory_exists(folder)) directory_create(folder);
    return folder;
}

/// @function scoring_json_read_struct(_filepath, _fallback)
/// @description Read and parse a JSON file from disk. Returns _fallback if file not found, empty, or invalid JSON.
/// @param {string} _filepath  File path relative to working_directory
/// @param {struct} _fallback  Return value on failure
/// @returns {struct}  Parsed struct, or _fallback
function scoring_json_read_struct(_filepath, _fallback) {
    var f = file_text_open_read(_filepath);
    if (f < 0) return _fallback;

    var raw = "";
    while (!file_text_eof(f)) {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }
    file_text_close(f);

    if (string_trim(raw) == "") return _fallback;

    var parsed = undefined;
    try {
        parsed = json_parse(raw);
    } catch (e) {
        show_debug_message("WARNING: Failed to parse JSON: " + _filepath + " - " + string(e));
        return _fallback;
    }

    if (!is_struct(parsed)) return _fallback;
    return parsed;
}

/// @function scoring_json_write_struct(_filepath, _payload)
/// @description Serialize _payload to JSON and write to disk. Returns true on success.
/// @param {string} _filepath  Destination file path
/// @param {struct} _payload   Struct to serialize
/// @returns {bool}  true if write succeeded
function scoring_json_write_struct(_filepath, _payload) {
    var f = file_text_open_write(_filepath);
    if (f < 0) {
        show_debug_message("ERROR: Could not open for write: " + _filepath);
        return false;
    }
    file_text_write_string(f, json_stringify(_payload));
    file_text_close(f);
    return true;
}

/// @function scoring_judge_settings_get_store()
/// @description Return (or lazily create) global.judge_settings_store with default structure.
/// @returns {struct}  {selected_judge_id, judges: {}}
/// @reads   global.judge_settings_store
/// @writes  global.judge_settings_store (if not yet initialized)
function scoring_judge_settings_get_store() {
    if (!variable_global_exists("judge_settings_store") || !is_struct(global.judge_settings_store)) {
        global.judge_settings_store = {
            selected_judge_id: "ms_overlap",
            judges: {}
        };
    }
    if (!variable_struct_exists(global.judge_settings_store, "selected_judge_id")) {
        global.judge_settings_store.selected_judge_id = "ms_overlap";
    }
    if (!variable_struct_exists(global.judge_settings_store, "judges") || !is_struct(global.judge_settings_store.judges)) {
        global.judge_settings_store.judges = {};
    }
    return global.judge_settings_store;
}

/// @function scoring_judge_settings_get_registry()
/// @description Build the list of available judges with current settings merged from the store.
/// @returns {array}  Array of {id, name, description, enabled, settings} judge descriptors
/// @reads   global.judge_settings_store (via get_store)
function scoring_judge_settings_get_registry() {
    var store = scoring_judge_settings_get_store();
    var enabled = true;
    var enabled_uncal = true;
    var settings_obj = {
        count_rests:     false,
        grade_a:         90,
        grade_b:         80,
        grade_c:         70,
        grade_d:         60
    };
    if (is_struct(store.judges) && variable_struct_exists(store.judges, "ms_overlap")) {
        var entry = store.judges[$ "ms_overlap"];
        if (is_struct(entry)) {
            if (variable_struct_exists(entry, "enabled")) {
                enabled = bool(variable_struct_get(entry, "enabled"));
            }
            if (variable_struct_exists(entry, "settings") && is_struct(entry.settings)) {
                var _s = entry.settings;
                if (variable_struct_exists(_s, "count_rests"))     settings_obj.count_rests     = bool(_s[$ "count_rests"]);
                if (variable_struct_exists(_s, "grade_a"))         settings_obj.grade_a         = clamp(real(_s[$ "grade_a"]),         51, 100);
                if (variable_struct_exists(_s, "grade_b"))         settings_obj.grade_b         = clamp(real(_s[$ "grade_b"]),         41,  99);
                if (variable_struct_exists(_s, "grade_c"))         settings_obj.grade_c         = clamp(real(_s[$ "grade_c"]),         31,  99);
                if (variable_struct_exists(_s, "grade_d"))         settings_obj.grade_d         = clamp(real(_s[$ "grade_d"]),         21,  99);
            }
        }
    }
    if (is_struct(store.judges) && variable_struct_exists(store.judges, "ms_overlap_uncal")) {
        var entry_uncal = store.judges[$ "ms_overlap_uncal"];
        if (is_struct(entry_uncal) && variable_struct_exists(entry_uncal, "enabled")) {
            enabled_uncal = bool(variable_struct_get(entry_uncal, "enabled"));
        }
    }
    return [{
        id: "ms_overlap",
        name: "Matching time (Calibrated)",
        description: "Percent of measure milliseconds where tune and player match after scoring calibration offset.",
        enabled: enabled,
        settings: settings_obj
    }, {
        id: "ms_overlap_uncal",
        name: "Matching time (Uncalibrated)",
        description: "Percent of measure milliseconds where tune and player match with no scoring calibration offset.",
        enabled: enabled_uncal,
        settings: settings_obj
    }];
}

/// @function scoring_ms_overlap_get_effective_settings()
/// @description Return the active ms_overlap scoring settings struct (count_rests, grade_a/b/c/d) from the registry.
/// @returns {struct}  {count_rests, grade_a, grade_b, grade_c, grade_d}
/// @reads   global.judge_settings_store (via scoring_judge_settings_get_registry)
function scoring_ms_overlap_get_effective_settings() {
    var reg = scoring_judge_settings_get_registry();
    if (array_length(reg) > 0 && is_struct(reg[0]) && variable_struct_exists(reg[0], "settings")) {
        return reg[0].settings;
    }
    return { count_rests: false, grade_a: 90, grade_b: 80, grade_c: 70, grade_d: 60 };
}

/// @function scoring_judge_settings_build_payload(_player_id)
/// @description Build a serializable judge_settings payload struct from current store + registry for disk export.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {struct}  {schema_version, export_type, player_id, selected_judge_id, judges: [...]}
/// @reads   global.judge_settings_store (via get_store, get_registry)
function scoring_judge_settings_build_payload(_player_id = undefined) {
    var store = scoring_judge_settings_get_store();
    var judges = scoring_judge_settings_get_registry();
    var judge_entries = [];

    for (var i = 0; i < array_length(judges); i++) {
        var j = judges[i];
        if (!is_struct(j)) continue;
        var jid = string(variable_struct_exists(j, "id") ? variable_struct_get(j, "id") : "");
        if (jid == "") continue;

        var enabled = bool(variable_struct_exists(j, "enabled") ? variable_struct_get(j, "enabled") : true);
        var settings_obj = {};

        if (is_struct(store.judges) && variable_struct_exists(store.judges, jid)) {
            var saved = store.judges[$ jid];
            if (is_struct(saved)) {
                if (variable_struct_exists(saved, "enabled")) enabled = bool(variable_struct_get(saved, "enabled"));
                if (variable_struct_exists(saved, "settings") && is_struct(variable_struct_get(saved, "settings"))) {
                    settings_obj = variable_struct_get(saved, "settings");
                }
            }
        }

        array_push(judge_entries, {
            id: jid,
            name: string(variable_struct_exists(j, "name") ? variable_struct_get(j, "name") : jid),
            enabled: enabled,
            settings: settings_obj
        });
    }

    return {
        schema_version: 1,
        export_type: "judge_settings",
        player_id: scoring_profile_get_player_id(_player_id),
        selected_judge_id: string(variable_struct_exists(store, "selected_judge_id") ? variable_struct_get(store, "selected_judge_id") : "ms_overlap"),
        judges: judge_entries
    };
}

/// @function scoring_judge_settings_save_for_player(_player_id)
/// @description Ensure player folder exists and write judge_settings.json to disk.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {bool}  True if write succeeded
function scoring_judge_settings_save_for_player(_player_id = undefined) {
    scoring_profile_ensure_player_folder(_player_id);
    var path = scoring_profile_get_judge_settings_path(_player_id);
    var payload = scoring_judge_settings_build_payload(_player_id);
    return scoring_json_write_struct(path, payload);
}

/// @function scoring_judge_settings_load_for_player(_player_id)
/// @description Load judge_settings.json from disk and populate global.judge_settings_store.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {struct}  The updated judge_settings_store
/// @writes  global.judge_settings_store
function scoring_judge_settings_load_for_player(_player_id = undefined) {
    var fallback = {
        schema_version: 1,
        export_type: "judge_settings",
        player_id: scoring_profile_get_player_id(_player_id),
        selected_judge_id: "ms_overlap",
        judges: []
    };

    var path = scoring_profile_get_judge_settings_path(_player_id);
    var data = scoring_json_read_struct(path, fallback);

    var store = scoring_judge_settings_get_store();
    store.selected_judge_id = string(variable_struct_exists(data, "selected_judge_id") ? variable_struct_get(data, "selected_judge_id") : "ms_overlap");
    store.judges = {};

    var judges = variable_struct_exists(data, "judges") ? variable_struct_get(data, "judges") : [];
    if (is_array(judges)) {
        for (var i = 0; i < array_length(judges); i++) {
            var j = judges[i];
            if (!is_struct(j)) continue;
            var jid = string(variable_struct_exists(j, "id") ? variable_struct_get(j, "id") : "");
            if (jid == "") continue;

            var enabled = bool(variable_struct_exists(j, "enabled") ? variable_struct_get(j, "enabled") : true);
            var settings_obj = {};
            if (variable_struct_exists(j, "settings") && is_struct(variable_struct_get(j, "settings"))) {
                settings_obj = variable_struct_get(j, "settings");
            }

            store.judges[$ jid] = {
                enabled: enabled,
                settings: settings_obj
            };
        }
    }

    global.judge_settings_store = store;
    return store;
}

/// @function scoring_profile_get_app_settings_path(_player_id)
/// @description Return path to app_settings.json for the given player.
/// @returns {string}  File path
function scoring_profile_get_app_settings_path(_player_id = undefined) {
    return scoring_profile_get_player_folder(_player_id) + "/app_settings.json";
}

/// @function scoring_profile_get_tune_overrides_path(_player_id)
/// @description Return path to tune_overrides.json for the given player.
/// @returns {string}  File path
function scoring_profile_get_tune_overrides_path(_player_id = undefined) {
    return scoring_profile_get_player_folder(_player_id) + "/tune_overrides.json";
}

/// @function scoring_player_settings_build_payload(_player_id)
/// @description Build a serializable player app settings payload from current globals (MIDI devices, chanter, metronome, notebeam config).
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {struct}  {schema_version, export_type, player_id, settings: {...}}
/// @reads   global.midi_input_device, global.midi_input_device_name, global.midi_input_channel, global.midi_output_device, global.midi_output_device_name, global.midi_ouput_channel, global.MIDI_chanter, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.timeline_cfg
function scoring_player_settings_build_payload(_player_id = undefined) {
    var settings = {
        midi_input_device:       variable_global_exists("midi_input_device") ? real(global.midi_input_device) : 0,
        midi_input_device_name:  variable_global_exists("midi_input_device_name") ? string(global.midi_input_device_name) : "",
        midi_input_channel:      variable_global_exists("midi_input_channel") ? real(global.midi_input_channel) : 0,
        midi_output_device:      variable_global_exists("midi_output_device") ? real(global.midi_output_device) : 0,
        midi_output_device_name: variable_global_exists("midi_output_device_name") ? string(global.midi_output_device_name) : "",
        midi_output_channel:     variable_global_exists("midi_ouput_channel") ? real(global.midi_ouput_channel) : 0,
        MIDI_chanter:            variable_global_exists("MIDI_chanter") ? string(global.MIDI_chanter) : "blair",
        metronome_mode:          variable_global_exists("metronome_mode") ? real(global.metronome_mode) : 2,
        metronome_pattern:       variable_global_exists("metronome_pattern_selection") ? real(global.metronome_pattern_selection) : 0,
        metronome_volume:        variable_global_exists("metronome_volume") ? real(global.metronome_volume) : 100,
        set_bpm_percent:         variable_global_exists("player_set_bpm_percent") ? real(global.player_set_bpm_percent) : 1.0,
        notebeam_measures_ahead:  (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "measures_ahead")) ? real(global.timeline_cfg.measures_ahead) : 2.0,
        notebeam_measures_behind: (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "measures_behind")) ? real(global.timeline_cfg.measures_behind) : 1.0,
        audio_output_offset_ms: (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) ? real(global.timeline_cfg.audio_output_offset_ms) : 0,
        visual_alignment_offset_ms: (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "visual_alignment_offset_ms")) ? real(global.timeline_cfg.visual_alignment_offset_ms) : 0,
        input_capture_offset_ms: (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")) ? real(global.timeline_cfg.input_capture_offset_ms) : 0
    };

    if (script_exists(asset_get_index("timing_calibration_build_settings_payload"))) {
        settings.timing_calibration = timing_calibration_build_settings_payload();
    }

    return {
        schema_version: 1,
        export_type: "player_app_settings",
        player_id: scoring_profile_get_player_id(_player_id),
        settings: settings
    };
}

/// @function scoring_player_settings_save_for_player(_player_id)
/// @description Build and write app_settings.json for the given player.
/// @returns {bool}  True if write succeeded
function scoring_player_settings_save_for_player(_player_id = undefined) {
    scoring_profile_ensure_player_folder(_player_id);
    var path = scoring_profile_get_app_settings_path(_player_id);
    var payload = scoring_player_settings_build_payload(_player_id);
    
    scoring_calibration_debug_log("[SAVE] path=" + path);

/// @function scoring_player_settings_resolve_midi_input_index(_saved_name, _saved_index)
/// @description Find the current MIDI input device index by matching saved device name; falls back to saved index.
/// @returns {real}  Resolved device index (0-based, clamped to available count)
function scoring_player_settings_resolve_midi_input_index(_saved_name, _saved_index) {
    var count = midi_input_device_count();
    if (count <= 0) return 0;

    var wanted = string_trim(string(_saved_name));
    if (wanted != "") {
        for (var i = 0; i < count; i++) {
            if (string(midi_input_device_name(i)) == wanted) return i;
        }
    }

    return clamp(floor(real(_saved_index)), 0, count - 1);
}

/// @function scoring_player_settings_resolve_midi_output_index(_saved_name, _saved_index)
/// @description Find the current MIDI output device index by matching saved device name; falls back to saved index.
/// @returns {real}  Resolved device index (0-based, clamped to available count)
function scoring_player_settings_resolve_midi_output_index(_saved_name, _saved_index) {
    var count = midi_output_device_count();
    if (count <= 0) return 0;

    var wanted = string_trim(string(_saved_name));
    if (wanted != "") {
        for (var i = 0; i < count; i++) {
            if (string(midi_output_device_name(i)) == wanted) return i;
        }
    }

    return clamp(floor(real(_saved_index)), 0, count - 1);
}

/// @function scoring_player_settings_load_for_player(_player_id)
/// @description Load app_settings.json and write all player settings to globals (MIDI devices, chanter, metronome, notebeam). Returns true on success.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {bool}  true
/// @writes  global.midi_input_device, global.midi_input_device_name, global.midi_output_device, global.midi_output_device_name, global.midi_input_channel, global.midi_ouput_channel, global.MIDI_chanter, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.timeline_cfg
/// @callers obj_game_controller Create
function scoring_player_settings_load_for_player(_player_id = undefined) {
    var fallback = {
        schema_version: 1,
        export_type: "player_app_settings",
        player_id: scoring_profile_get_player_id(_player_id),
        settings: {}
    };

    var path = scoring_profile_get_app_settings_path(_player_id);
    var data = scoring_json_read_struct(path, fallback);
    var s = variable_struct_exists(data, "settings") && is_struct(data.settings) ? data.settings : {};

    var in_idx_saved = real(variable_struct_exists(s, "midi_input_device") ? s[$ "midi_input_device"] : (variable_global_exists("midi_input_device") ? global.midi_input_device : 0));
    var in_name_saved = string(variable_struct_exists(s, "midi_input_device_name") ? s[$ "midi_input_device_name"] : "");
    var out_idx_saved = real(variable_struct_exists(s, "midi_output_device") ? s[$ "midi_output_device"] : (variable_global_exists("midi_output_device") ? global.midi_output_device : 0));
    var out_name_saved = string(variable_struct_exists(s, "midi_output_device_name") ? s[$ "midi_output_device_name"] : "");
    
    scoring_calibration_debug_log("[LOAD_MIDI] Saved: in='" + in_name_saved + "' out='" + out_name_saved + "'");

    if (midi_input_device_count() > 0) {
        global.midi_input_device = scoring_player_settings_resolve_midi_input_index(in_name_saved, in_idx_saved);
        global.midi_input_device_name = midi_input_device_name(global.midi_input_device);
    } else {
        global.midi_input_device = 0;
        global.midi_input_device_name = "no MIDI input devices found";
    }

    if (midi_output_device_count() > 0) {
        global.midi_output_device = scoring_player_settings_resolve_midi_output_index(out_name_saved, out_idx_saved);
        global.midi_output_device_name = midi_output_device_name(global.midi_output_device);
    } else {
        global.midi_output_device = 0;
        global.midi_output_device_name = "no MIDI output devices found";
    }
    
    scoring_calibration_debug_log("[LOAD_MIDI] Resolved: in='" + global.midi_input_device_name + "' out='" + global.midi_output_device_name + "'");
    scoring_calibration_debug_log("[LOAD_MIDI] MIDI_chanter='" + (global.MIDI_chanter ?? "MISSING") + "'");

    global.midi_input_channel = real(variable_struct_exists(s, "midi_input_channel") ? s[$ "midi_input_channel"] : (variable_global_exists("midi_input_channel") ? global.midi_input_channel : 0));
    global.midi_ouput_channel = real(variable_struct_exists(s, "midi_output_channel") ? s[$ "midi_output_channel"] : (variable_global_exists("midi_ouput_channel") ? global.midi_ouput_channel : 0));
    global.metronome_mode = floor(real(variable_struct_exists(s, "metronome_mode") ? s[$ "metronome_mode"] : (variable_global_exists("metronome_mode") ? global.metronome_mode : 2)));
    global.metronome_pattern_selection = floor(real(variable_struct_exists(s, "metronome_pattern") ? s[$ "metronome_pattern"] : (variable_global_exists("metronome_pattern_selection") ? global.metronome_pattern_selection : 0)));
    global.metronome_volume = floor(real(variable_struct_exists(s, "metronome_volume") ? s[$ "metronome_volume"] : (variable_global_exists("metronome_volume") ? global.metronome_volume : 100)));
    global.player_set_bpm_percent = clamp(real(variable_struct_exists(s, "set_bpm_percent") ? s[$ "set_bpm_percent"] : (variable_global_exists("player_set_bpm_percent") ? global.player_set_bpm_percent : 1.0)), 0.5, 2.0);

    if (variable_struct_exists(s, "MIDI_chanter")) {
        global.MIDI_chanter = string(s[$ "MIDI_chanter"]);
    }

    if (script_exists(asset_get_index("gv_ensure_timeline_cfg_defaults"))) {
        var _cfg = gv_ensure_timeline_cfg_defaults();
        if (variable_struct_exists(s, "notebeam_measures_ahead"))  variable_struct_set(_cfg, "measures_ahead",  max(0.25, real(s[$ "notebeam_measures_ahead"])));
        if (variable_struct_exists(s, "notebeam_measures_behind")) variable_struct_set(_cfg, "measures_behind", max(0.25, real(s[$ "notebeam_measures_behind"])));
        // NOTE: Do NOT set timing offsets from top-level fields here — let timing_calibration_hydrate_from_settings() be the authoritative source
        // if (variable_struct_exists(s, "audio_output_offset_ms")) variable_struct_set(_cfg, "audio_output_offset_ms", real(s[$ "audio_output_offset_ms"]));
        // if (variable_struct_exists(s, "visual_alignment_offset_ms")) variable_struct_set(_cfg, "visual_alignment_offset_ms", real(s[$ "visual_alignment_offset_ms"]));
        // if (variable_struct_exists(s, "input_capture_offset_ms")) variable_struct_set(_cfg, "input_capture_offset_ms", real(s[$ "input_capture_offset_ms"]));
        // if (variable_struct_exists(s, "scoring_compare_offset_ms")) variable_struct_set(_cfg, "scoring_compare_offset_ms", real(s[$ "scoring_compare_offset_ms"]));
    }

    if (script_exists(asset_get_index("timing_calibration_hydrate_from_settings"))) {
        var _hydrate_ok = timing_calibration_hydrate_from_settings(s);
        scoring_calibration_debug_log("[STARTUP_RESULT] hydrate returned " + string(_hydrate_ok));
    }

    var picker = instance_find(obj_tune_picker, 0);
    if (picker != noone) {
        scr_tune_picker_set_instance_var(picker, "_sb_set_bpm_percent", global.player_set_bpm_percent);
    }

    return true;
}

/// @function scoring_tune_override_key(_tune_filename)
/// @description Derive a canonical tune override key from path (basename, lowercase). Reads global.current_tune_filename or global.current_set if filename not provided.
/// @param {string} [_tune_filename]  Optional explicit path; falls back to current tune/set
/// @returns {string}  Lowercase filename key (e.g. "scotland_the_brave.json") or ""
/// @reads   global.current_tune_filename, global.current_set, global.current_set_item_index
function scoring_tune_override_key(_tune_filename = undefined) {
    var source = "";
    if (!is_undefined(_tune_filename)) {
        source = string(_tune_filename);
    } else if (variable_global_exists("current_tune_filename")) {
        source = string(global.current_tune_filename);
    } else if (variable_global_exists("current_set") && is_array(global.current_set)) {
        var idx = variable_global_exists("current_set_item_index") ? floor(real(global.current_set_item_index)) : -1;
        if (idx >= 0 && idx < array_length(global.current_set) && is_struct(global.current_set[idx])) {
            source = string(global.current_set[idx][$ "tune_filename"] ?? "");
        }
    }

    source = string_trim(source);
    if (source == "") return "";

    source = string_replace_all(source, "\\", "/");
    var last_sep = 0;
    var n = string_length(source);
    for (var i = 1; i <= n; i++) {
        if (string_copy(source, i, 1) == "/") last_sep = i;
    }
    if (last_sep > 0 && last_sep < n) source = string_copy(source, last_sep + 1, n - last_sep);

    return string_lower(source);
}

/// @function scoring_tune_overrides_get_store()
/// @description Return (or lazily create) global.player_tune_overrides.
/// @returns {struct}  Map of tune_key → {bpm, swing_mult, gracenote_override_ms}
/// @reads   global.player_tune_overrides
/// @writes  global.player_tune_overrides (if not initialized)
function scoring_tune_overrides_get_store() {
    if (!variable_global_exists("player_tune_overrides") || !is_struct(global.player_tune_overrides)) {
        global.player_tune_overrides = {};
    }
    return global.player_tune_overrides;
}

/// @function scoring_tune_overrides_save_for_player(_player_id)
/// @description Write current tune override store to tune_overrides.json for the given player.
/// @returns {bool}  True if write succeeded
function scoring_tune_overrides_save_for_player(_player_id = undefined) {
    scoring_profile_ensure_player_folder(_player_id);
    var path = scoring_profile_get_tune_overrides_path(_player_id);
    var store = scoring_tune_overrides_get_store();

    var overrides = [];
    var keys = variable_struct_get_names(store);
    for (var i = 0; i < array_length(keys); i++) {
        var key = string(keys[i]);
        if (!variable_struct_exists(store, key)) continue;
        var ov = store[$ key];
        if (!is_struct(ov)) continue;

        array_push(overrides, {
            tune_key: key,
            bpm: real(ov[$ "bpm"] ?? 120),
            swing_mult: real(ov[$ "swing_mult"] ?? 0),
            gracenote_override_ms: real(ov[$ "gracenote_override_ms"] ?? 0)
        });
    }

    var payload = {
        schema_version: 1,
        export_type: "tune_overrides",
        player_id: scoring_profile_get_player_id(_player_id),
        overrides: overrides
    };

    return scoring_json_write_struct(path, payload);
}

/// @function scoring_tune_overrides_load_for_player(_player_id)
/// @description Load tune_overrides.json for the player and populate global.player_tune_overrides.
/// @param {string} [_player_id]  Player ID or undefined
/// @returns {struct}  The updated player_tune_overrides store
/// @writes  global.player_tune_overrides
function scoring_tune_overrides_load_for_player(_player_id = undefined) {
    var fallback = {
        schema_version: 1,
        export_type: "tune_overrides",
        player_id: scoring_profile_get_player_id(_player_id),
        overrides: []
    };

    var path = scoring_profile_get_tune_overrides_path(_player_id);
    var data = scoring_json_read_struct(path, fallback);

    var store = {};
    var list = variable_struct_exists(data, "overrides") ? data[$ "overrides"] : [];
    if (is_array(list)) {
        for (var i = 0; i < array_length(list); i++) {
            var ov = list[i];
            if (!is_struct(ov)) continue;
            var key = scoring_tune_override_key(string(ov[$ "tune_key"] ?? ""));
            if (key == "") continue;
            store[$ key] = {
                bpm: real(ov[$ "bpm"] ?? 120),
                swing_mult: real(ov[$ "swing_mult"] ?? 0),
                gracenote_override_ms: real(ov[$ "gracenote_override_ms"] ?? 0)
            };
        }
    }

    global.player_tune_overrides = store;
    return store;
}

/// @function scoring_tune_override_apply_current(_tune_filename)
/// @description Apply the stored per-tune override (bpm/swing/gracenote) for the given tune to runtime globals.
/// @param {string} [_tune_filename]  Tune path; falls back to current tune
/// @returns {bool}  true if override found and applied, false if not found
/// @reads   global.player_tune_overrides (via get_store)
/// @writes  global.current_tune_filename, global.current_bpm, global.swing_mult, global.gracenote_override_ms
function scoring_tune_override_apply_current(_tune_filename = undefined) {
    var key = scoring_tune_override_key(_tune_filename);
    if (key == "") return false;

    global.current_tune_filename = key;

    var store = scoring_tune_overrides_get_store();
    if (!variable_struct_exists(store, key)) return false;

    var ov = store[$ key];
    if (!is_struct(ov)) return false;

    if (variable_struct_exists(ov, "bpm")) global.current_bpm = real(ov[$ "bpm"]);
    if (variable_struct_exists(ov, "swing_mult")) global.swing_mult = real(ov[$ "swing_mult"]);
    if (variable_struct_exists(ov, "gracenote_override_ms")) global.gracenote_override_ms = real(ov[$ "gracenote_override_ms"]);

    return true;
}

/// @function scoring_tune_override_save_current(_tune_filename)
/// @description Save current runtime bpm/swing/gracenote globals into the tune override store and write to disk.
/// @param {string} [_tune_filename]  Tune path; falls back to current tune
/// @returns {bool}  true if saved successfully
/// @reads   global.current_bpm, global.swing_mult, global.gracenote_override_ms
/// @writes  global.current_tune_filename, global.player_tune_overrides (via store)
function scoring_tune_override_save_current(_tune_filename = undefined) {
    var key = scoring_tune_override_key(_tune_filename);
    if (key == "") return false;

    global.current_tune_filename = key;

    var store = scoring_tune_overrides_get_store();
    store[$ key] = {
        bpm: variable_global_exists("current_bpm") ? real(global.current_bpm) : 120,
        swing_mult: variable_global_exists("swing_mult") ? real(global.swing_mult) : 0,
        gracenote_override_ms: variable_global_exists("gracenote_override_ms") ? real(global.gracenote_override_ms) : 0
    };
    global.player_tune_overrides = store;
    return scoring_tune_overrides_save_for_player();
}

/// @function scoring_judge_settings_ensure_state()
/// @description Lazily initialize global.judge_settings_ui_state and sync selected_judge_id from store.
/// @reads   global.judge_settings_store (via get_store)
/// @writes  global.judge_settings_ui_state
function scoring_judge_settings_ensure_state() {
    if (!variable_global_exists("judge_settings_ui_state") || !is_struct(global.judge_settings_ui_state)) {
        global.judge_settings_ui_state = {
            selected_index: 0,
            hover_index: -1,
            selected_measure: -1,
            selected_judge_id: "ms_overlap"
        };
    }

    if (!variable_struct_exists(global.judge_settings_ui_state, "selected_index")) {
        global.judge_settings_ui_state.selected_index = 0;
    }
    if (!variable_struct_exists(global.judge_settings_ui_state, "hover_index")) {
        global.judge_settings_ui_state.hover_index = -1;
    }
    if (!variable_struct_exists(global.judge_settings_ui_state, "selected_measure")) {
        global.judge_settings_ui_state.selected_measure = -1;
    }
    if (!variable_struct_exists(global.judge_settings_ui_state, "selected_judge_id")) {
        global.judge_settings_ui_state.selected_judge_id = "ms_overlap";
    }

    var _rows = scoring_judge_settings_get_ui_rows();
    var _store = scoring_judge_settings_get_store();

    if (is_struct(_store) && variable_struct_exists(_store, "selected_judge_id")) {
        global.judge_settings_ui_state.selected_judge_id = string(_store.selected_judge_id);
    }

    if (array_length(_rows) > 0) {
        var _selected_id = string(global.judge_settings_ui_state.selected_judge_id);
        var _match_index = -1;
        for (var i = 0; i < array_length(_rows); i++) {
            var _row = _rows[i];
            if (!is_struct(_row)) continue;
            if (string(variable_struct_get(_row, "judge_id")) == _selected_id) {
                _match_index = i;
                break;
            }
        }

        if (_match_index < 0) {
            _match_index = clamp(floor(real(global.judge_settings_ui_state.selected_index)), 0, array_length(_rows) - 1);
        }

        global.judge_settings_ui_state.selected_index = _match_index;
        global.judge_settings_ui_state.selected_judge_id = string(variable_struct_get(_rows[_match_index], "judge_id"));
        _store.selected_judge_id = global.judge_settings_ui_state.selected_judge_id;
    } else if (string(global.judge_settings_ui_state.selected_judge_id) == "") {
        global.judge_settings_ui_state.selected_judge_id = "ms_overlap";
    }

    return global.judge_settings_ui_state;
}

function scoring_judge_settings_get_ui_rows() {
    var _rows = [];
    var _registry = scoring_judge_settings_get_registry();
    if (!is_array(_registry)) return _rows;

    for (var i = 0; i < array_length(_registry); i++) {
        var _j = _registry[i];
        if (!is_struct(_j)) continue;

        var _jid = string(variable_struct_exists(_j, "id") ? variable_struct_get(_j, "id") : "");
        if (_jid == "") continue;

        var _jname = string(variable_struct_exists(_j, "name") ? variable_struct_get(_j, "name") : _jid);
        var _desc = string(variable_struct_exists(_j, "description") ? variable_struct_get(_j, "description") : "");
        var _enabled = bool(variable_struct_exists(_j, "enabled") ? variable_struct_get(_j, "enabled") : true);
        var _settings = (variable_struct_exists(_j, "settings") && is_struct(variable_struct_get(_j, "settings")))
            ? variable_struct_get(_j, "settings")
            : {};

        array_push(_rows, {
            judge_id: _jid,
            judge_name: _jname,
            description: _desc,
            enabled: _enabled,
            settings: _settings
        });
    }

    return _rows;
}

/// @function scoring_judge_settings_draw_list_canvas(_x1, _y1, _x2, _y2)
/// @description Draw the judge settings list panel (judge tiles with name, description, enabled toggle) within the given canvas bounds.
/// @param {real} _x1  Left edge
/// @param {real} _y1  Top edge
/// @param {real} _x2  Right edge
/// @param {real} _y2  Bottom edge
/// @reads   global.judge_settings_ui_state (via scoring_judge_settings_ensure_state)
function scoring_judge_settings_draw_list_canvas(_x1, _y1, _x2, _y2) {
    var _state = scoring_judge_settings_ensure_state();
    var _rows = scoring_judge_settings_get_ui_rows();

    var _w = max(1, _x2 - _x1);
    var _h = max(1, _y2 - _y1);
    var _pad = 8;
    var _title_scale = 0.84;
    var _body_scale = 0.66;

    var _prev_font = draw_get_font();
    var _prev_col = draw_get_color();
    var _prev_alpha = draw_get_alpha();
    var _prev_halign = draw_get_halign();
    var _prev_valign = draw_get_valign();

    draw_set_alpha(0.90);
    draw_set_color(make_color_rgb(26, 33, 42));
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(236, 236, 236));
    draw_set_font(fnt_setting);
    draw_text_transformed(_x1 + _pad, _y1 + _pad, "Judges", _title_scale, _title_scale, 0);

    var _body_line_h = max(9, floor(string_height("Ag") * _body_scale) + 2);
    var _row_h = max(16, _body_line_h + 6);
    var _rows_y0 = _y1 + _pad + max(18, floor(string_height("Judges") * _title_scale)) + 4;

    if (!is_array(_rows) || array_length(_rows) <= 0) {
        draw_set_color(make_color_rgb(196, 196, 196));
        draw_text_transformed(_x1 + _pad, _rows_y0, "No judges configured.", _body_scale, _body_scale, 0);
        draw_set_font(_prev_font);
        draw_set_color(_prev_col);
        draw_set_alpha(_prev_alpha);
        draw_set_halign(_prev_halign);
        draw_set_valign(_prev_valign);
        return;
    }

    var _selected = clamp(floor(real(_state.selected_index)), 0, array_length(_rows) - 1);
    _state.selected_index = _selected;

    for (var i = 0; i < array_length(_rows); i++) {
        var _row = _rows[i];
        if (!is_struct(_row)) continue;

        var _ry = _rows_y0 + (i * _row_h);
        if (_ry + _row_h > _y1 + _h - _pad) break;

        if (i == _selected) {
            draw_set_alpha(0.65);
            draw_set_color(make_color_rgb(68, 102, 148));
            draw_rectangle(_x1 + 4, _ry - 2, _x2 - 4, _ry + _row_h - 4, false);
            draw_set_alpha(1);
        }

        draw_set_color(make_color_rgb(236, 236, 236));
        var _name = string(variable_struct_exists(_row, "judge_name") ? variable_struct_get(_row, "judge_name") : "Judge");
        var _status = bool(variable_struct_exists(_row, "enabled") ? variable_struct_get(_row, "enabled") : true)
            ? "On"
            : "Off";
        var _text_y = _ry + max(2, floor((_row_h - _body_line_h) * 0.5));
        draw_text_transformed(_x1 + _pad, _text_y, _name, _body_scale, _body_scale, 0);
        var _status_w = string_width(_status) * _body_scale;
        draw_text_transformed((_x1 + _w - _pad) - _status_w, _text_y, _status, _body_scale, _body_scale, 0);
    }

    var _selected_row = _rows[_selected];
    if (is_struct(_selected_row) && variable_struct_exists(_selected_row, "judge_id")) {
        _state.selected_judge_id = string(variable_struct_get(_selected_row, "judge_id"));
    }

    draw_set_font(_prev_font);
    draw_set_color(_prev_col);
    draw_set_alpha(_prev_alpha);
    draw_set_halign(_prev_halign);
    draw_set_valign(_prev_valign);
}

/// @function scoring_judge_settings_draw_detail_canvas(_x1, _y1, _x2, _y2)
/// @description Draw the detail panel for the selected judge (settings fields, save button, current context stats).
/// @param {real} _x1  Left edge
/// @param {real} _y1  Top edge
/// @param {real} _x2  Right edge
/// @param {real} _y2  Bottom edge
/// @reads   global.judge_settings_ui_state (via scoring_judge_settings_ensure_state), global.judge_settings_store
function scoring_judge_settings_draw_detail_canvas(_x1, _y1, _x2, _y2) {
    var _state = scoring_judge_settings_ensure_state();
    var _rows = scoring_judge_settings_get_ui_rows();

    var _prev_font = draw_get_font();
    var _prev_col = draw_get_color();
    var _prev_alpha = draw_get_alpha();
    var _prev_halign = draw_get_halign();
    var _prev_valign = draw_get_valign();

    var _title_scale = 0.84;
    var _body_scale = 0.66;

    draw_set_alpha(0.90);
    draw_set_color(make_color_rgb(24, 28, 34));
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    var _pad = 8;
    var _line_h = max(9, floor(string_height("Ag") * _body_scale) + 2);
    var _y = _y1 + _pad;

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_font(fnt_setting);
    draw_set_color(make_color_rgb(236, 236, 236));
    draw_text_transformed(_x1 + _pad, _y, "Judge Details", _title_scale, _title_scale, 0);
    _y += max(18, floor(string_height("Judge Details") * _title_scale)) + 4;

    if (!is_array(_rows) || array_length(_rows) <= 0) {
        draw_set_color(make_color_rgb(196, 196, 196));
        draw_text_transformed(_x1 + _pad, _y, "No judge selected.", _body_scale, _body_scale, 0);
    } else {
        var _selected = clamp(floor(real(_state.selected_index)), 0, array_length(_rows) - 1);
        var _row = _rows[_selected];

        var _name = string(variable_struct_exists(_row, "judge_name") ? variable_struct_get(_row, "judge_name") : "Judge");
        var _desc = string(variable_struct_exists(_row, "description") ? variable_struct_get(_row, "description") : "");
        var _settings = (variable_struct_exists(_row, "settings") && is_struct(variable_struct_get(_row, "settings")))
            ? variable_struct_get(_row, "settings")
            : {};

        draw_set_color(make_color_rgb(236, 236, 236));
        draw_text_transformed(_x1 + _pad, _y, _name, _title_scale, _title_scale, 0);
        _y += max(16, floor(string_height(_name) * _title_scale)) + 4;

        draw_set_color(make_color_rgb(200, 200, 200));
        var _wrap_w = max(40, (_x2 - _x1) - (_pad * 2));
        draw_text_ext_transformed(_x1 + _pad, _y, _desc, _line_h + 1, _wrap_w / _body_scale, _body_scale, _body_scale, 0);
        var _desc_h = string_height_ext(_desc, _line_h + 1, _wrap_w / _body_scale) * _body_scale;
        _y += max(24, floor(_desc_h)) + 6;

        draw_set_color(make_color_rgb(90, 100, 114));
        draw_line(_x1 + _pad, _y, _x2 - _pad, _y);
        _y += 10;

        draw_set_color(make_color_rgb(236, 236, 236));
        draw_text_transformed(_x1 + _pad, _y, "Settings", _title_scale, _title_scale, 0);
        _y += max(16, floor(string_height("Settings") * _title_scale)) + 4;

        // Rebuild setting hitboxes each draw call.
        if (!variable_struct_exists(_state, "setting_hitboxes")) _state.setting_hitboxes = [];
        _state.setting_hitboxes = [];

        // Read live effective settings (store values merged with defaults).
        var _cfg = scoring_ms_overlap_get_effective_settings();

        var _setting_defs = [
            { key: "count_rests",     label: "Count rests",  type: "bool", step:  1, min:   0, max:   1 },
            { key: "grade_a",         label: "Grade A >=",   type: "int",  step:  5, min:  51, max: 100 },
            { key: "grade_b",         label: "Grade B >=",   type: "int",  step:  5, min:  41, max:  99 },
            { key: "grade_c",         label: "Grade C >=",   type: "int",  step:  5, min:  31, max:  99 },
            { key: "grade_d",         label: "Grade D >=",   type: "int",  step:  5, min:  21, max:  99 },

        ];

        var _row_h = max(22, _line_h + 8);
        var _ctrl_w = 90;
        var _cx     = _x2 - _pad - _ctrl_w;

        for (var si = 0; si < array_length(_setting_defs); si++) {
            var _def  = _setting_defs[si];
            var _key  = string(_def[$ "key"]);
            var _lbl  = string(_def[$ "label"]);
            var _type = string(_def[$ "type"]);
            var _step = real(_def[$ "step"]);
            var _val  = _cfg[$ _key];

            if (_y + _row_h > _y2 - _pad) break;

            var _row_y = _y + (_row_h - floor(string_height("Ag") * _body_scale)) * 0.5;
            var _by1   = _y + 3;
            var _by2   = _y + _row_h - 3;
            var _bmy   = (_by1 + _by2) * 0.5;

            draw_set_valign(fa_top);
            draw_set_color(make_color_rgb(216, 216, 216));
            draw_text_transformed(_x1 + _pad, _row_y, _lbl, _body_scale, _body_scale, 0);

            if (_type == "bool") {
                var _bx1  = _cx;
                var _bx2  = _x2 - _pad;
                var _is_on = bool(_val);
                draw_set_color(_is_on ? make_color_rgb(66, 148, 82) : make_color_rgb(72, 72, 90));
                draw_rectangle(_bx1, _by1, _bx2, _by2, false);
                draw_set_color(make_color_rgb(180, 190, 200));
                draw_rectangle(_bx1, _by1, _bx2, _by2, true);
                draw_set_color(c_white);
                draw_set_halign(fa_center);
                draw_text_transformed((_bx1 + _bx2) * 0.5, _bmy - floor(string_height("Ag") * _body_scale) * 0.5,
                    _is_on ? "On" : "Off", _body_scale, _body_scale, 0);
                draw_set_halign(fa_left);

                array_push(_state.setting_hitboxes, { x1: _bx1, y1: _by1, x2: _bx2, y2: _by2, action: "toggle", key: _key, step: _step });

            } else {
                var _bw      = 16;
                var _ddec_x1 = _cx;
                var _ddec_x2 = _cx + _bw;
                var _dec_x1  = _cx + _bw;
                var _dec_x2  = _cx + _bw * 2;
                var _inc_x1  = _x2 - _pad - _bw * 2;
                var _inc_x2  = _x2 - _pad - _bw;
                var _iinc_x1 = _x2 - _pad - _bw;
                var _iinc_x2 = _x2 - _pad;

                // Outer double-left (<<) — big step: same sprite as inner, adjacent pair forms <<
                draw_sprite_stretched_ext(spr_arrow_left, 0, _ddec_x1 + 2, _by1 + 2, (_ddec_x2 - _ddec_x1) - 4, (_by2 - _by1) - 4, c_white, 1);

                // Inner single-left (<) — step 1
                draw_sprite_stretched_ext(spr_arrow_left, 0, _dec_x1 + 2, _by1 + 2, (_dec_x2 - _dec_x1) - 4, (_by2 - _by1) - 4, c_white, 1);

                // Value
                var _ty = _bmy - floor(string_height("Ag") * _body_scale) * 0.5;
                draw_set_color(make_color_rgb(236, 236, 236));
                draw_set_halign(fa_center);
                draw_text_transformed((_dec_x2 + _inc_x1) * 0.5, _ty, string(floor(real(_val))), _body_scale, _body_scale, 0);
                draw_set_halign(fa_left);

                // Inner single-right (>) — step 1
                draw_sprite_stretched_ext(spr_arrow_right, 0, _inc_x1 + 2, _by1 + 2, (_inc_x2 - _inc_x1) - 4, (_by2 - _by1) - 4, c_white, 1);

                // Outer double-right (>>) — big step: same sprite as inner, adjacent pair forms >>
                draw_sprite_stretched_ext(spr_arrow_right, 0, _iinc_x1 + 2, _by1 + 2, (_iinc_x2 - _iinc_x1) - 4, (_by2 - _by1) - 4, c_white, 1);

                array_push(_state.setting_hitboxes, { x1: _ddec_x1, y1: _by1, x2: _ddec_x2, y2: _by2, action: "dec", key: _key, step: _step });
                array_push(_state.setting_hitboxes, { x1: _dec_x1,  y1: _by1, x2: _dec_x2,  y2: _by2, action: "dec", key: _key, step: 1 });
                array_push(_state.setting_hitboxes, { x1: _inc_x1,  y1: _by1, x2: _inc_x2,  y2: _by2, action: "inc", key: _key, step: 1 });
                array_push(_state.setting_hitboxes, { x1: _iinc_x1, y1: _by1, x2: _iinc_x2, y2: _by2, action: "inc", key: _key, step: _step });
            }

            _y += _row_h;
        }
    }

    draw_set_font(_prev_font);
    draw_set_color(_prev_col);
    draw_set_alpha(_prev_alpha);
    draw_set_halign(_prev_halign);
    draw_set_valign(_prev_valign);
}

/// @function scoring_judge_settings_handle_list_click(_mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle mouse click on the judge settings list panel. Updates selected judge in global.judge_settings_ui_state and global.judge_settings_store.
/// @param {real} _mx,_my  Mouse coordinates
/// @param {real} _x1,_y1,_x2,_y2  Canvas bounds
/// @returns {bool}  true if a hit was detected
/// @reads   global.judge_settings_ui_state
/// @writes  global.judge_settings_ui_state, global.judge_settings_store (selected_judge_id)
function scoring_judge_settings_handle_list_click(_mx, _my, _x1, _y1, _x2, _y2) {
    var _state = scoring_judge_settings_ensure_state();
    var _rows = scoring_judge_settings_get_ui_rows();
    if (!is_array(_rows) || array_length(_rows) <= 0) return false;

    if (_mx < _x1 || _mx > _x2 || _my < _y1 || _my > _y2) return false;

    var _pad = 8;
    var _row_h = 26;
    var _header_h = 28;
    var _list_top = _y1 + _pad + _header_h;
    if (_my < _list_top) return false;

    var _row_idx = floor((_my - _list_top) / _row_h);
    if (_row_idx < 0 || _row_idx >= array_length(_rows)) return false;

    _state.selected_index = _row_idx;
    var _row = _rows[_row_idx];
    if (is_struct(_row) && variable_struct_exists(_row, "judge_id")) {
        _state.selected_judge_id = string(variable_struct_get(_row, "judge_id"));
    }

    var _store = scoring_judge_settings_get_store();
    if (is_struct(_store)) {
        _store.selected_judge_id = _state.selected_judge_id;
        global.judge_settings_store = _store;
    }

    return true;
}

/// @function scoring_judge_settings_handle_list_scroll(_delta, _mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle mouse scroll on the judge settings list. Scrolls list view if pointer is within canvas bounds.
/// @param {real} _delta  Scroll delta
/// @param {real} _mx,_my  Mouse coordinates
/// @param {real} _x1,_y1,_x2,_y2  Canvas bounds
/// @returns {bool}  true if scroll consumed
function scoring_judge_settings_handle_list_scroll(_delta, _mx, _my, _x1, _y1, _x2, _y2) {
    var _rows = scoring_judge_settings_get_ui_rows();
    if (!is_array(_rows) || array_length(_rows) <= 0) return false;
    if (_mx < _x1 || _mx > _x2 || _my < _y1 || _my > _y2) return false;

    var _state = scoring_judge_settings_ensure_state();
    var _step = 0;
    if (_delta < 0) _step = -1;
    if (_delta > 0) _step = 1;
    if (_step == 0) return false;

    var _cur = clamp(floor(real(_state.selected_index)), 0, array_length(_rows) - 1);
    var _next = clamp(_cur + _step, 0, array_length(_rows) - 1);
    if (_next == _cur) return false;

    _state.selected_index = _next;
    var _row = _rows[_next];
    if (is_struct(_row) && variable_struct_exists(_row, "judge_id")) {
        _state.selected_judge_id = string(variable_struct_get(_row, "judge_id"));
    }

    var _store = scoring_judge_settings_get_store();
    if (is_struct(_store)) {
        _store.selected_judge_id = _state.selected_judge_id;
        global.judge_settings_store = _store;
    }

    return true;
}

function scoring_judge_settings_handle_detail_click(_mx, _my, _x1, _y1, _x2, _y2) {
    if (_mx < _x1 || _mx > _x2 || _my < _y1 || _my > _y2) return false;
    var _state = scoring_judge_settings_ensure_state();
    if (!variable_struct_exists(_state, "setting_hitboxes") || !is_array(_state.setting_hitboxes)
        || array_length(_state.setting_hitboxes) == 0) return true;

    for (var i = 0; i < array_length(_state.setting_hitboxes); i++) {
        var _hb = _state.setting_hitboxes[i];
        if (_mx < real(_hb.x1) || _mx > real(_hb.x2) || _my < real(_hb.y1) || _my > real(_hb.y2)) continue;

        var _action = string(_hb[$ "action"]);
        var _key    = string(_hb[$ "key"]);
        var _step   = real(_hb[$ "step"]);

        var _store = scoring_judge_settings_get_store();
        if (!is_struct(_store)) return true;
        if (!variable_struct_exists(_store, "judges") || !is_struct(_store.judges)) _store.judges = {};
        if (!variable_struct_exists(_store.judges, "ms_overlap")) {
            _store.judges[$ "ms_overlap"] = { enabled: true, settings: {} };
        }
        var _judge = _store.judges[$ "ms_overlap"];
        if (!variable_struct_exists(_judge, "settings") || !is_struct(_judge.settings)) _judge.settings = {};
        var _s = _judge.settings;

        // Read current effective value (defaults merged in).
        var _cfg = scoring_ms_overlap_get_effective_settings();
        var _cur = _cfg[$ _key];
        var _new_val = _cur;

        switch (_action) {
            case "toggle": _new_val = !bool(_cur); break;
            case "dec":    _new_val = real(_cur) - _step; break;
            case "inc":    _new_val = real(_cur) + _step; break;
        }

        // Clamp and enforce grade ordering (A > B > C > D > 0).
        switch (_key) {
            case "count_rests":
                _new_val = bool(_new_val);
                break;
            case "grade_a":
                _new_val = clamp(floor(real(_new_val)), real(_cfg.grade_b) + 1, 100);
                break;
            case "grade_b":
                _new_val = clamp(floor(real(_new_val)), real(_cfg.grade_c) + 1, real(_cfg.grade_a) - 1);
                break;
            case "grade_c":
                _new_val = clamp(floor(real(_new_val)), real(_cfg.grade_d) + 1, real(_cfg.grade_b) - 1);
                break;
            case "grade_d":
                _new_val = clamp(floor(real(_new_val)), 1, real(_cfg.grade_c) - 1);
                break;
        }

        _s[$ _key] = _new_val;
        global.judge_settings_store = _store;
        scoring_judge_settings_save_for_player();
        return true;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Loop Session Scoring Overview
// ---------------------------------------------------------------------------

/// @function scoring_loop_overview_ensure_state()
/// @description Return (and lazily initialise) the loop score overview UI state struct.
/// @returns {struct}  {scroll_row: real}
/// @reads   global.loop_score_overview_ui_state
/// @writes  global.loop_score_overview_ui_state
function scoring_loop_overview_ensure_state() {
    if (!variable_global_exists("loop_score_overview_ui_state")
        || !is_struct(global.loop_score_overview_ui_state)) {
        global.loop_score_overview_ui_state = { scroll_row: 0 };
    }
    if (!variable_struct_exists(global.loop_score_overview_ui_state, "scroll_row")) {
        global.loop_score_overview_ui_state.scroll_row = 0;
    }
    return global.loop_score_overview_ui_state;
}

/// @function scoring_build_loop_iteration_scores()
/// @description Compute a per-loop-iteration overall score from EVENT_HISTORY + timeline_state spans.
///              Stores results in global.timeline_state.loop_iteration_scores.
/// @returns {array}  Array of {iteration, score, grade, start_ms, end_ms} structs
/// @reads   global.EVENT_HISTORY, global.timeline_state (planned_spans, review_full_trace, player_in, measure_nav_entries)
/// @writes  global.timeline_state.loop_iteration_scores
function scoring_build_loop_iteration_scores() {
    var out = [];

    if (!variable_global_exists("EVENT_HISTORY") || !is_array(global.EVENT_HISTORY)) return out;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;

    // --- Build per-iteration time windows from game events ---
    var win_map    = {};  // key = string(iter) -> {start_ms, end_ms}
    var iter_order = [];

    var _hist = global.EVENT_HISTORY;
    var _hn   = array_length(_hist);
    for (var i = 0; i < _hn; i++) {
        var ev = _hist[i];
        if (!is_struct(ev)) continue;
        var _iter = floor(real(variable_struct_exists(ev, "loop_iteration") ? ev[$ "loop_iteration"] : 0));
        if (_iter <= 0) continue;
        var _src = string(variable_struct_exists(ev, "source") ? ev[$ "source"] : "");
        if (_src != "game") continue;
        var _exp = real(variable_struct_exists(ev, "expected_time_ms") ? ev[$ "expected_time_ms"] : 0);

        var _k = string(_iter);
        if (!variable_struct_exists(win_map, _k)) {
            win_map[$ _k] = { start_ms: _exp, end_ms: _exp };
            array_push(iter_order, _iter);
        } else {
            var _w = win_map[$ _k];
            if (_exp < _w.start_ms) _w.start_ms = _exp;
            if (_exp > _w.end_ms)   _w.end_ms   = _exp;
        }
    }

    if (array_length(iter_order) <= 0) {
        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
            global.timeline_state.loop_iteration_scores = out;
        }
        return out;
    }

    // Sort iterations ascending
    array_sort(iter_order, function(_a, _b) { return _a - _b; });

    // --- Get shared spans and settings ---
    var planned_spans = variable_struct_exists(global.timeline_state, "planned_spans")
        ? variable_struct_get(global.timeline_state, "planned_spans") : [];
    var player_spans  = [];
    if (variable_struct_exists(global.timeline_state, "review_full_trace")
        && is_array(variable_struct_get(global.timeline_state, "review_full_trace"))
        && array_length(variable_struct_get(global.timeline_state, "review_full_trace")) > 0) {
        player_spans = variable_struct_get(global.timeline_state, "review_full_trace");
    } else if (variable_struct_exists(global.timeline_state, "player_in")
        && is_array(variable_struct_get(global.timeline_state, "player_in"))) {
        player_spans = variable_struct_get(global.timeline_state, "player_in");
    }

    // Scoring offset removed from calibration model (must keep feedback honest)

    var _settings = scoring_ms_overlap_get_effective_settings();
    var _count_rests = bool(_settings.count_rests);
    var all_measures = scoring_measure_entries_from_timeline();

    // --- Score each iteration ---
    for (var ii = 0; ii < array_length(iter_order); ii++) {
        var _iter = iter_order[ii];
        var _k = string(_iter);
        if (!variable_struct_exists(win_map, _k)) continue;
        var _win = win_map[$ _k];
        var _s_ms = real(_win.start_ms);
        var _e_ms = real(_win.end_ms);
        if (_e_ms <= _s_ms + 1) continue;

        var _planned = scoring_filter_spans_in_window(planned_spans, _s_ms, _e_ms);
        var _player  = scoring_filter_spans_in_window(player_spans,  _s_ms, _e_ms);

        // Filter measure entries to this iteration's time window
        var _iter_measures = [];
        for (var mi = 0; mi < array_length(all_measures); mi++) {
            var me = all_measures[mi];
            if (!is_struct(me)) continue;
            var me_s = real(me[$ "start_ms"] ?? 0);
            var me_e = real(me[$ "end_ms"]   ?? me_s);
            // Include measure if it overlaps the iteration window
            if (me_e > _s_ms && me_s < _e_ms) {
                // Clamp the entry to the iteration window
                var me_clamped = {
                    measure:   me[$ "measure"]  ?? -1,
                    part:      me[$ "part"]     ?? 1,
                    start_ms:  max(me_s, _s_ms),
                    end_ms:    min(me_e, _e_ms)
                };
                array_push(_iter_measures, me_clamped);
            }
        }

        var _total = 0;
        var _match = 0;
        var _exp   = 0;

        if (array_length(_iter_measures) > 0) {
            for (var _mj = 0; _mj < array_length(_iter_measures); _mj++) {
                var _me2 = _iter_measures[_mj];
                var _ms2 = scoring_score_measure_ms_overlap(_me2, _planned, _player, _settings);
                _total += real(_ms2[$ "total_ms"]            ?? 0);
                _match += real(_ms2[$ "matching_ms"]         ?? 0);
                _exp   += real(_ms2[$ "expected_active_ms"]  ?? 0);
            }
        } else {
            // Fallback: raw window overlap (no measure boundaries available)
            var _raw_total = _e_ms - _s_ms;
            var _raw_match = 0;
            // Accumulate player time that overlaps planned spans in window
            for (var _fpi = 0; _fpi < array_length(_player); _fpi++) {
                var _fps = _player[_fpi];
                if (!is_struct(_fps)) continue;
                var _fps1 = max(real(_fps[$ "start_ms"] ?? 0), _s_ms);
                var _fps2 = min(real(_fps[$ "end_ms"]   ?? _fps1), _e_ms);
                for (var _fqi = 0; _fqi < array_length(_planned); _fqi++) {
                    var _fpl = _planned[_fqi];
                    if (!is_struct(_fpl)) continue;
                    var _fpl1 = max(real(_fpl[$ "start_ms"] ?? 0), _s_ms);
                    var _fpl2 = min(real(_fpl[$ "end_ms"]   ?? _fpl1), _e_ms);
                    if (real(_fpl[$ "lane_idx"] ?? -999) != real(_fps[$ "lane_idx"] ?? -998)) continue;
                    var _fov = max(0, min(_fps2, _fpl2) - max(_fps1, _fpl1));
                    _raw_match += _fov;
                }
            }
            _total = _raw_total;
            _match = _raw_match;
            _exp   = _raw_total;
        }

        var _denom = _count_rests ? max(1, _total) : max(1, _exp);
        var _score = clamp((_match / _denom) * 100, 0, 100);
        var _grade = scoring_score_to_grade(_score);

        array_push(out, {
            iteration: _iter,
            score:     _score,
            grade:     _grade,
            start_ms:  _s_ms,
            end_ms:    _e_ms
        });
    }

    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.loop_iteration_scores = out;
    }
    return out;
}

/// @function scoring_loop_overview_handle_scroll(_delta, _mx, _my, _bx1, _by1, _bx2, _by2)
/// @description Handle mouse-wheel scroll inside the loop score overview canvas. Advances scroll_row.
/// @param {real} _delta   +1 = scroll down, -1 = scroll up
/// @param {real} _mx      Mouse X (unused but reserved for bounds check)
/// @param {real} _my      Mouse Y
/// @param {real} _bx1     Canvas bbox left
/// @param {real} _by1     Canvas bbox top
/// @param {real} _bx2     Canvas bbox right
/// @param {real} _by2     Canvas bbox bottom
/// @reads   global.timeline_state.loop_iteration_scores
/// @writes  global.loop_score_overview_ui_state.scroll_row
function scoring_loop_overview_handle_scroll(_delta, _mx, _my, _bx1, _by1, _bx2, _by2) {
    if (_mx < _bx1 || _mx > _bx2 || _my < _by1 || _my > _by2) return;

    var _state = scoring_loop_overview_ensure_state();
    var _scores = (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "loop_iteration_scores"))
        ? global.timeline_state.loop_iteration_scores : [];
    var _n_rows = is_array(_scores) ? array_length(_scores) : 0;

    var _row_h = 22;
    var _view_h = max(1, _by2 - _by1) - 48;  // approx header height
    var _visible = max(1, floor(_view_h / _row_h));
    var _max_scroll = max(0, _n_rows - _visible);

    _state.scroll_row = clamp(floor(real(_state.scroll_row)) + _delta, 0, _max_scroll);
}

/// @function scoring_loop_overview_draw_canvas(_x1, _y1, _x2, _y2)
/// @description Draw the loop score overview matrix: rows = loop iterations, columns = judges.
/// @param {real} _x1  Canvas left
/// @param {real} _y1  Canvas top
/// @param {real} _x2  Canvas right
/// @param {real} _y2  Canvas bottom
/// @reads   global.timeline_state.loop_iteration_scores, global.loop_score_overview_ui_state
function scoring_loop_overview_draw_canvas(_x1, _y1, _x2, _y2) {
    var _prev_font   = draw_get_font();
    var _prev_col    = draw_get_color();
    var _prev_alpha  = draw_get_alpha();
    var _prev_halign = draw_get_halign();
    var _prev_valign = draw_get_valign();

    var _w = max(1, _x2 - _x1);
    var _h = max(1, _y2 - _y1);
    var _pad   = 8;
    var _t_scl = 0.84;   // title scale
    var _b_scl = 0.70;   // body scale

    draw_set_alpha(0.92);
    draw_set_color(make_color_rgb(20, 24, 30));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_alpha(1);

    draw_set_font(fnt_setting);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var _state = scoring_loop_overview_ensure_state();

    // Fetch loop iteration scores
    var _scores = [];
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "loop_iteration_scores")) {
        _scores = global.timeline_state.loop_iteration_scores;
    }
    if (!is_array(_scores)) _scores = [];
    var _n_iters = array_length(_scores);

    // Column definitions: keep judge naming consistent with the scoring table window.
    var _judge_name = "MS Overlap";
    if (is_undefined(scoring_get_judge_table_rows) == false) {
        var _judge_rows = scoring_get_judge_table_rows(-1, "ms_overlap");
        if (is_array(_judge_rows) && array_length(_judge_rows) > 0 && is_struct(_judge_rows[0])) {
            var _row_name = string(_judge_rows[0][$ "judge_name"] ?? "");
            if (string_length(_row_name) > 0) _judge_name = _row_name;
        }
    }
    var _judges = [{ id: "ms_overlap", name: _judge_name }];
    var _n_judges = array_length(_judges);

    // Layout
    var _title_h   = max(18, floor(string_height("Ag") * _t_scl)) + 4;
    var _header_h  = max(14, floor(string_height("Ag") * _b_scl)) + 4;
    var _row_h     = max(18, floor(string_height("Ag") * _b_scl)) + 6;
    var _loop_col_w = 52;   // width of "Loop #" column
    var _judge_col_w = max(80, floor((_w - _loop_col_w - _pad * 2) / _n_judges));

    var _content_y0 = _y1 + _pad + _title_h + _header_h;

    var _visible_rows = max(1, floor((_y2 - _content_y0 - _pad) / _row_h));
    var _max_scroll   = max(0, _n_iters - _visible_rows);
    _state.scroll_row = clamp(floor(real(_state.scroll_row)), 0, _max_scroll);
    var _scroll = _state.scroll_row;

    // --- Title ---
    draw_set_color(make_color_rgb(236, 236, 236));
    draw_text_transformed(_x1 + _pad, _y1 + _pad, "Loop Scores", _t_scl, _t_scl, 0);

    if (_n_iters <= 0) {
        draw_set_color(make_color_rgb(160, 160, 160));
        draw_text_transformed(_x1 + _pad, _y1 + _pad + _title_h + 4, "No loop data yet.", _b_scl, _b_scl, 0);
        draw_set_font(_prev_font); draw_set_color(_prev_col);
        draw_set_alpha(_prev_alpha); draw_set_halign(_prev_halign);
        draw_set_valign(_prev_valign);
        return;
    }

    // --- Column header row ---
    var _hdr_y = _y1 + _pad + _title_h;
    draw_set_color(make_color_rgb(56, 62, 72));
    draw_rectangle(_x1 + _pad, _hdr_y, _x2 - _pad, _hdr_y + _header_h, false);

    draw_set_color(make_color_rgb(190, 190, 190));
    draw_text_transformed(_x1 + _pad + 2, _hdr_y + 2, "Loop", _b_scl, _b_scl, 0);
    for (var ji = 0; ji < _n_judges; ji++) {
        var _jx = _x1 + _pad + _loop_col_w + ji * _judge_col_w;
        draw_set_halign(fa_center);
        draw_text_transformed(_jx + floor(_judge_col_w * 0.5), _hdr_y + 2, string(_judges[ji].name), _b_scl, _b_scl, 0);
        draw_set_halign(fa_left);
    }

    // Divider
    draw_set_color(make_color_rgb(74, 74, 82));
    draw_line(_x1 + _pad, _hdr_y + _header_h, _x2 - _pad, _hdr_y + _header_h);

    // --- Data rows ---
    for (var ri = 0; ri < _visible_rows; ri++) {
        var _data_idx = ri + _scroll;
        if (_data_idx >= _n_iters) break;

        var _entry = _scores[_data_idx];
        if (!is_struct(_entry)) continue;
        var _score_val = real(_entry[$ "score"] ?? 0);
        var _grade_str = string(_entry[$ "grade"] ?? "-");
        var _iter_num  = floor(real(_entry[$ "iteration"] ?? (_data_idx + 1)));

        var _row_y = _content_y0 + ri * _row_h;
        var _row_bg = (_data_idx mod 2 == 0)
            ? make_color_rgb(28, 33, 40)
            : make_color_rgb(34, 39, 48);
        draw_set_alpha(0.80);
        draw_set_color(_row_bg);
        draw_rectangle(_x1 + _pad, _row_y, _x2 - _pad, _row_y + _row_h - 1, false);
        draw_set_alpha(1);

        // Loop # label
        draw_set_color(make_color_rgb(190, 190, 190));
        draw_text_transformed(_x1 + _pad + 2, _row_y + 2, string(_iter_num), _b_scl, _b_scl, 0);

        // Score cell (one per judge — currently just ms_overlap)
        for (var ji = 0; ji < _n_judges; ji++) {
            var _jx = _x1 + _pad + _loop_col_w + ji * _judge_col_w;
            var _score_color = scoring_score_to_color(_score_val);
            var _cell_text   = string(floor(_score_val)) + "% " + _grade_str;
            draw_set_halign(fa_center);
            draw_set_color(_score_color);
            draw_text_transformed(_jx + floor(_judge_col_w * 0.5), _row_y + 2, _cell_text, _b_scl, _b_scl, 0);
            draw_set_halign(fa_left);
        }
    }

    // --- Scroll indicator (thin bar on right edge) ---
    if (_n_iters > _visible_rows) {
        var _bar_x = _x2 - _pad - 4;
        var _bar_h = max(1, _y2 - _content_y0 - _pad);
        var _thumb_h = max(12, floor(_bar_h * (_visible_rows / _n_iters)));
        var _thumb_y = _content_y0 + floor((_scroll / max(1, _max_scroll)) * (_bar_h - _thumb_h));
        draw_set_alpha(0.30);
        draw_set_color(c_gray);
        draw_rectangle(_bar_x, _content_y0, _bar_x + 4, _y2 - _pad, false);
        draw_set_alpha(0.70);
        draw_set_color(c_ltgray);
        draw_rectangle(_bar_x, _thumb_y, _bar_x + 4, _thumb_y + _thumb_h, false);
        draw_set_alpha(1);
    }

    draw_set_font(_prev_font);
    draw_set_color(_prev_col);
    draw_set_alpha(_prev_alpha);
    draw_set_halign(_prev_halign);
    draw_set_valign(_prev_valign);
}
