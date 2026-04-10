// scr_scoring - objective scoring utilities
// Phase 1 judge: millisecond overlap between planned tune spans and player spans.

if (!variable_global_exists("current_player_id")) {
    global.current_player_id = "player_1";
}
if (!variable_global_exists("scoring_last_run")) {
    global.scoring_last_run = undefined;
}

function scoring_get_player_id() {
    var player_key = "player_1";
    if (variable_global_exists("current_player_id")) {
        player_key = string_trim(string(global.current_player_id));
    }
    if (player_key == "") player_key = "player_1";
    return player_key;
}

function scoring_get_context_key(_tune_id, _player_id, _bpm, _swing, _part_key = "all") {
    return string_lower(string(_tune_id))
        + "|" + string_lower(string(_player_id))
        + "|" + string(real(_bpm))
        + "|" + string(_swing)
        + "|" + string(_part_key);
}

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

        array_push(filtered, s);
    }

    return filtered;
}

function scoring_boundaries_add_unique(_arr, _value) {
    var v = real(_value);
    for (var i = 0; i < array_length(_arr); i++) {
        if (abs(real(_arr[i]) - v) <= 0.0001) return _arr;
    }
    array_push(_arr, v);
    return _arr;
}

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

function scoring_apply_run_to_runtime(_run_summary) {
    if (!is_struct(_run_summary)) return;

    global.scoring_last_run = _run_summary;

    var overall = real(_run_summary.overall_score ?? 0);
    global.performance_score = overall;
    global.last_score = overall;
    global.run_score = overall;
    global.final_score = overall;
    global.overall_score = overall;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        return;
    }

    var judge_id = string(_run_summary.selected_judge_id ?? "ms_overlap");
    var measure_results = variable_struct_exists(_run_summary, "measure_scores")
        ? _run_summary.measure_scores
        : [];
    var map = scoring_measure_results_to_map(measure_results);

    variable_struct_set(global.timeline_state, "score_selected_judge", judge_id);
    if (!variable_struct_exists(global.timeline_state, "score_measure_maps") || !is_struct(global.timeline_state.score_measure_maps)) {
        variable_struct_set(global.timeline_state, "score_measure_maps", {});
    }
    var maps = variable_struct_get(global.timeline_state, "score_measure_maps");
    maps[$ judge_id] = map;
    variable_struct_set(global.timeline_state, "score_measure_maps", maps);
}

function scoring_build_ms_overlap_summary(_export_info = undefined) {
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

    var _settings = scoring_ms_overlap_get_effective_settings();
    var _count_rests = bool(_settings.count_rests);
    var judge_id = "ms_overlap";

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

        for (var _si = 0; _si < _seg_count; _si++) {
            var _seg = _segs[_si];
            if (!is_struct(_seg)) { _score_by_seg[_si] = undefined; continue; }

            // Build nav from bar_events (stored pre-offset) and apply absolute offset.
            var _bar_evts = _seg[$ "bar_events"] ?? [];
            var _nav = gv_build_measure_nav_map(_bar_evts);
            var _seg_start_ms = real(_seg[$ "start_ms"] ?? 0);
            var _seg_end_ms   = real(_seg[$ "end_ms"]   ?? 0);
            // bar_events in playback_context already have absolute times — no offset loop.
            // Only fix the last entry's end_ms, which gv_build_measure_nav_map always
            // sets to gv_get_planned_end_ms() (total set duration, not segment end).
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
            _score_by_seg[_si] = {
                score_measure_maps:   _seg_maps,
                score_selected_judge: judge_id,
                measure_scores:       _seg_measures,
                overall_score:        _seg_overall,
                raw:                  _seg_raw
            };
        }

        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
            global.timeline_state.score_by_segment = _score_by_seg;
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
        judge_id: "ms_overlap",
        judge_name: "MS Overlap (Objective)",
        score_version: "v1",
        player_id: player_key,
        tune_id: tune_id,
        bpm: bpm,
        swing: swing,
        part_key: "all",
        context_key: scoring_get_context_key(tune_id, player_key, bpm, swing, "all"),
        selected_judge_id: "ms_overlap",
        overall_score: overall_score,
        measure_scores: measures_out,
        raw: raw
    };

    scoring_apply_run_to_runtime(summary);
    return summary;
}

function scoring_score_to_color(_score) {
    var s = clamp(real(_score), 0, 100);
    if (s >= 90) return make_color_rgb(54, 122, 68);    // A
    if (s >= 80) return make_color_rgb(108, 148, 64);   // B
    if (s >= 70) return make_color_rgb(188, 156, 52);   // C
    if (s >= 60) return make_color_rgb(194, 112, 48);   // D
    return make_color_rgb(178, 72, 72);                 // F
}

function scoring_score_to_grade(_score) {
    var s = clamp(real(_score), 0, 100);
    var cfg = scoring_ms_overlap_get_effective_settings();
    if (s >= real(cfg.grade_a)) return "A";
    if (s >= real(cfg.grade_b)) return "B";
    if (s >= real(cfg.grade_c)) return "C";
    if (s >= real(cfg.grade_d)) return "D";
    return "F";
}

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
        _active_seg = clamp(_active_seg, 0, max(0, array_length(_by_seg) - 1));
        var _seg_data = _by_seg[_active_seg];
        if (is_struct(_seg_data) && variable_struct_exists(_seg_data, "score_measure_maps")) {
            score_maps = _seg_data.score_measure_maps;
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
    out.alpha = clamp(0.48 + ((measure_score / 100) * 0.30), 0.40, 0.90);
    return out;
}

function scoring_get_last_run_summary() {
    if (variable_global_exists("scoring_last_run") && is_struct(global.scoring_last_run)) {
        return global.scoring_last_run;
    }
    return undefined;
}

function scoring_find_measure_result(_measure_num) {
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
        _active = clamp(_active, 0, max(0, array_length(_by_seg) - 1));
        var _seg_data = _by_seg[_active];
        if (is_struct(_seg_data) && variable_struct_exists(_seg_data, "measure_scores")
            && is_array(_seg_data.measure_scores)) {
            var target = floor(real(_measure_num));
            var arr = _seg_data.measure_scores;
            for (var i = 0; i < array_length(arr); i++) {
                var m = arr[i];
                if (!is_struct(m)) continue;
                if (floor(real(m.measure ?? -1)) == target) return m;
            }
            return undefined;
        }
    }

    var summary = scoring_get_last_run_summary();
    if (!is_struct(summary)) return undefined;
    if (!variable_struct_exists(summary, "measure_scores") || !is_array(variable_struct_get(summary, "measure_scores"))) return undefined;

    var target = floor(real(_measure_num));
    var arr = variable_struct_get(summary, "measure_scores");
    for (var i = 0; i < array_length(arr); i++) {
        var m = arr[i];
        if (!is_struct(m)) continue;
        if (floor(real(m.measure ?? -1)) == target) return m;
    }
    return undefined;
}

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

function scoring_get_judge_table_rows(_measure_num = -1, _judge_id = "ms_overlap") {
    var rows = [];
    var summary = scoring_get_last_run_summary();
    var context_stats = scoring_get_current_context_stats();
    if (!is_struct(summary)) return rows;

    var run_score = real(variable_struct_exists(summary, "overall_score") ? variable_struct_get(summary, "overall_score") : 0);
    var display_score = run_score;
    var measure_num = floor(real(_measure_num));
    if (measure_num >= 1) {
        var m_result = scoring_find_measure_result(measure_num);
        if (is_struct(m_result)) {
            display_score = real(variable_struct_exists(m_result, "score") ? variable_struct_get(m_result, "score") : run_score);
        }
    }
    var run_score_text = string(floor(clamp(display_score, 0, 100))) + "%";
    var grade = scoring_score_to_grade(display_score);
    var plays_text = string(variable_struct_exists(context_stats, "plays_count") ? variable_struct_get(context_stats, "plays_count") : 0);

    array_push(rows, {
        judge_id: "ms_overlap",
        judge_name: "MS Overlap",
        score: run_score_text,
        grade: grade,
        best: (function(_v) {
                if (!is_numeric(_v) && (string(_v) == "-" || string(_v) == "")) return "-";
                var _r = real(_v);
                return (_r > 0 || string(_v) == "0") ? string(floor(clamp(_r, 0, 100))) + "%" : "-";
            })(variable_struct_exists(context_stats, "best_score") ? variable_struct_get(context_stats, "best_score") : "-"),
        avg: (function(_v) {
                if (!is_numeric(_v) && (string(_v) == "-" || string(_v) == "")) return "-";
                var _r = real(_v);
                return (_r > 0 || string(_v) == "0") ? string(floor(clamp(_r, 0, 100))) + "%" : "-";
            })(variable_struct_exists(context_stats, "avg_score") ? variable_struct_get(context_stats, "avg_score") : "-"),
        plays: plays_text
    });

    return rows;
}

function scoring_get_detail_popup_rows(_measure_num = -1, _judge_id = "ms_overlap") {
    var rows = [];
    var judge_id = string(_judge_id);
    if (judge_id == "") judge_id = "ms_overlap";

    if (judge_id != "ms_overlap") {
        array_push(rows, "Judge: " + judge_id);
        array_push(rows, "No detail formatter yet.");
        return rows;
    }

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
        _active = clamp(_active, 0, max(0, array_length(_by_seg) - 1));
        _seg_data = _by_seg[_active];
    }

    if (!is_struct(summary) && !is_struct(_seg_data)) {
        array_push(rows, "No scoring data available.");
        return rows;
    }

    // Default overall stats from segment (set mode) or flat summary (tune mode).
    var raw = {};
    var score_value = 0;
    if (is_struct(_seg_data)) {
        raw = _seg_data[$ "raw"] ?? {};
        score_value = real(_seg_data[$ "overall_score"] ?? 0);
    } else if (is_struct(summary)) {
        raw = variable_struct_exists(summary, "raw") ? variable_struct_get(summary, "raw") : {};
        score_value = real(variable_struct_exists(summary, "overall_score") ? variable_struct_get(summary, "overall_score") : 0);
    }
    var matching_ms = real(variable_struct_exists(raw, "matching_ms") ? variable_struct_get(raw, "matching_ms") : 0);
    var total_ms = max(1, real(variable_struct_exists(raw, "total_ms") ? variable_struct_get(raw, "total_ms") : 0));
    var expected_active_ms = real(variable_struct_exists(raw, "expected_active_ms") ? variable_struct_get(raw, "expected_active_ms") : total_ms);
    var player_active_ms = real(variable_struct_exists(raw, "player_active_ms") ? variable_struct_get(raw, "player_active_ms") : matching_ms);

    var measure_num = floor(real(_measure_num));
    var detail_scope = "overall";

    if (measure_num >= 1) {
        var m = scoring_find_measure_result(measure_num);
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

    array_push(rows, "Judge: Matching time");
    array_push(rows, "Scope: " + detail_scope);
    array_push(rows, "Score: " + string(round(clamp(score_value, 0, 100))) + "%");
    array_push(rows, "Matching ms: " + string(round(matching_ms)));
    array_push(rows, "Total ms: " + string(round(total_ms)));
    array_push(rows, "Mismatch ms: " + string(round(mismatch_ms)));
    array_push(rows, "Expected active: " + string(round(expected_active_ms)) + " ms");
    array_push(rows, "Player active: " + string(round(player_active_ms)) + " ms");

    return rows;
}

function scoring_get_measure_popup_rows(_measure_num) {
    return scoring_get_detail_popup_rows(_measure_num, "ms_overlap");
}

function scoring_get_panel_focus(_measure_num = -1, _judge_id = "ms_overlap") {
    var summary = scoring_get_last_run_summary();
    var judge_id = is_string(_judge_id) && string_length(_judge_id) > 0 ? string(_judge_id) : "ms_overlap";
    var judge_name = "Matching time";
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
        _active = clamp(_active, 0, max(0, array_length(_by_seg) - 1));
        _seg_data = _by_seg[_active];
    }

    if (is_struct(_seg_data)) {
        score_value = real(_seg_data[$ "overall_score"] ?? 0);
    } else if (is_struct(summary)) {
        score_value = real(variable_struct_exists(summary, "overall_score") ? variable_struct_get(summary, "overall_score") : 0);
    }

    if (is_struct(summary) || is_struct(_seg_data)) {
        var measure_num = floor(real(_measure_num));
        if (measure_num >= 1) {
            var m = scoring_find_measure_result(measure_num);
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

function scoring_profile_get_player_id(_player_id = undefined) {
    var pid = "default";
    if (!is_undefined(_player_id)) pid = string(_player_id);
    else if (variable_global_exists("current_player_id")) pid = string(global.current_player_id);

    pid = string_trim(pid);
    if (pid == "") pid = "default";

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

    if (safe == "") safe = "default";
    return string_lower(safe);
}

function scoring_profile_get_root_folder() {
    return "datafiles/config";
}

function scoring_profile_get_player_folder(_player_id = undefined) {
    return scoring_profile_get_root_folder() + "/players/" + scoring_profile_get_player_id(_player_id);
}

function scoring_profile_get_judge_settings_path(_player_id = undefined) {
    return scoring_profile_get_player_folder(_player_id) + "/judge_settings.json";
}

function scoring_profile_ensure_player_folder(_player_id = undefined) {
    var root = scoring_profile_get_root_folder();
    if (!directory_exists(root)) directory_create(root);

    var players = root + "/players";
    if (!directory_exists(players)) directory_create(players);

    var folder = scoring_profile_get_player_folder(_player_id);
    if (!directory_exists(folder)) directory_create(folder);
    return folder;
}

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

function scoring_judge_settings_get_registry() {
    var store = scoring_judge_settings_get_store();
    var enabled = true;
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
    return [{
        id: "ms_overlap",
        name: "Matching time",
        description: "Percent of measure milliseconds where tune and player match.",
        enabled: enabled,
        settings: settings_obj
    }];
}

// Returns the effective ms_overlap settings merged with defaults.
function scoring_ms_overlap_get_effective_settings() {
    var reg = scoring_judge_settings_get_registry();
    if (array_length(reg) > 0 && is_struct(reg[0]) && variable_struct_exists(reg[0], "settings")) {
        return reg[0].settings;
    }
    return { count_rests: false, grade_a: 90, grade_b: 80, grade_c: 70, grade_d: 60 };
}

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

function scoring_judge_settings_save_for_player(_player_id = undefined) {
    scoring_profile_ensure_player_folder(_player_id);
    var path = scoring_profile_get_judge_settings_path(_player_id);
    var payload = scoring_judge_settings_build_payload(_player_id);
    return scoring_json_write_struct(path, payload);
}

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
