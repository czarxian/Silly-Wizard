
// scr_tune_scripts — Playback & event preprocessing
// Purpose: Build runtime event lists (merge tune + metronome), start playback and provide the time-source callback that sends MIDI.
// Key functions: tune_build_events, tune_generate_metronome, tune_start, script_tune_callback

/// @function create_set_item(_tune_filename)
/// @description Create a new set item with default settings
/// @param _tune_filename The tune file path
/// @returns Set item struct

function create_set_item(_tune_filename) {
    return {
        tune_filename: _tune_filename,
        bpm: undefined,  // undefined = use tune metadata
        metronome_mode: global.metronome_mode ?? 2,
        metronome_pattern: global.metronome_pattern_selection,
        metronome_volume: global.metronome_volume ?? 100,
        count_in_measures: 1,
        include_drum_roll: false,
        drum_roll_variant: undefined
    };
}

function timing_calibration_ensure_state() {
    if (!variable_global_exists("timing_calibration") || !is_struct(global.timing_calibration)) {
        global.timing_calibration = {
            active: false,
            status: "idle",
            tune_filename: "tunes/Calibrate.json",
            previous_offset_ms: 0,
            applied_offset_ms: 0,
            last_match_count: 0,
            last_median_delta_ms: 0,
            last_message: "Timing calibration has not been run.",
            requested_at_ms: 0,
            completed_at_ms: 0,
            count_in_measures: 2
        };
    }

    return global.timing_calibration;
}

function timing_calibration_get_status_text() {
    var state = timing_calibration_ensure_state();
    return string(state.last_message ?? "Timing calibration has not been run.");
}

function timing_calibration_is_active() {
    var state = timing_calibration_ensure_state();
    return state.active;
}

function timing_calibration_collect_expected_note_ons() {
    var expected = [];
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return expected;
    if (!variable_struct_exists(global.timeline_state, "planned_events") || !is_array(global.timeline_state.planned_events)) return expected;

    var target_channel = (is_undefined(gv_get_target_tune_channel) == false)
        ? gv_get_target_tune_channel()
        : 2;
    var planned_events = global.timeline_state.planned_events;
    var n_events = array_length(planned_events);
    for (var i = 0; i < n_events; i++) {
        var ev = planned_events[i];
        if (!is_struct(ev)) continue;
        if (string(ev.type ?? "") != "note_on") continue;

        var ev_channel = floor(real(ev.channel ?? -1));
        if (ev_channel != target_channel) continue;

        var note_midi = floor(real(ev.note ?? -1));
        if (note_midi < 0) continue;

        var canonical = chanter_midi_to_canonical(note_midi, global.MIDI_chanter ?? "default", ev_channel);
        if (canonical == "?") canonical = "";

        array_push(expected, {
            expected_ms: gv_evt_time_ms(ev),
            note_midi: note_midi,
            note_canonical: canonical,
            matched: false
        });
    }

    return expected;
}

function timing_calibration_collect_player_note_ons() {
    var actual = [];
    if (!variable_global_exists("EVENT_HISTORY") || !is_array(global.EVENT_HISTORY)) return actual;

    var events = global.EVENT_HISTORY;
    var n_events = array_length(events);
    for (var i = 0; i < n_events; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;
        var ev_source = variable_struct_exists(ev, "source") ? string(variable_struct_get(ev, "source")) : "";
        var ev_type = variable_struct_exists(ev, "event_type") ? string(variable_struct_get(ev, "event_type")) : "";
        if (ev_source != "player") continue;
        if (ev_type != "note_on") continue;

        var note_midi = variable_struct_exists(ev, "note_midi")
            ? floor(real(variable_struct_get(ev, "note_midi")))
            : -1;
        if (note_midi < 0) continue;

        var actual_ms = variable_struct_exists(ev, "actual_time_ms")
            ? real(variable_struct_get(ev, "actual_time_ms"))
            : (variable_struct_exists(ev, "timestamp_ms") ? real(variable_struct_get(ev, "timestamp_ms")) : 0);
        var canonical = variable_struct_exists(ev, "note_canonical")
            ? string(variable_struct_get(ev, "note_canonical"))
            : "";
        if (canonical == "?" || string_length(canonical) <= 0) {
            var ev_channel = variable_struct_exists(ev, "channel") ? real(variable_struct_get(ev, "channel")) : 0;
            canonical = chanter_midi_to_canonical(note_midi, global.MIDI_chanter ?? "default", ev_channel);
            if (canonical == "?") canonical = "";
        }

        array_push(actual, {
            actual_ms: actual_ms,
            note_midi: note_midi,
            note_canonical: canonical
        });
    }

    return actual;
}

function timing_calibration_match_deltas(_expected, _actual, _max_abs_delta_ms) {
    var deltas = [];
    if (!is_array(_expected) || !is_array(_actual)) return deltas;

    var n_actual = array_length(_actual);
    var n_expected = array_length(_expected);
    var max_delta = max(1, real(_max_abs_delta_ms));

    for (var ai = 0; ai < n_actual; ai++) {
        var act = _actual[ai];
        if (!is_struct(act)) continue;

        var best_idx = -1;
        var best_abs_delta = max_delta + 1;
        var act_ms = real(act.actual_ms ?? 0);
        var act_canonical = string(act.note_canonical ?? "");
        var act_midi = floor(real(act.note_midi ?? -1));

        for (var ei = 0; ei < n_expected; ei++) {
            var exp_event = _expected[ei];
            if (!is_struct(exp_event)) continue;
            if (exp_event.matched) continue;

            var exp_canonical = string(exp_event.note_canonical ?? "");
            var exp_midi = floor(real(exp_event.note_midi ?? -1));
            if (string_length(act_canonical) > 0 && string_length(exp_canonical) > 0) {
                if (act_canonical != exp_canonical) continue;
            } else if (act_midi >= 0 && exp_midi >= 0 && act_midi != exp_midi) {
                continue;
            }

            var delta_ms = act_ms - real(exp_event.expected_ms ?? 0);
            var abs_delta = abs(delta_ms);
            if (abs_delta > max_delta) continue;
            if (abs_delta >= best_abs_delta) continue;

            best_abs_delta = abs_delta;
            best_idx = ei;
        }

        if (best_idx >= 0) {
            _expected[best_idx].matched = true;
            array_push(deltas, act_ms - real(_expected[best_idx].expected_ms ?? 0));
        }
    }

    return deltas;
}

function timing_calibration_median(_values) {
    if (!is_array(_values) || array_length(_values) <= 0) return 0;

    var vals = array_create(array_length(_values), 0);
    for (var i = 0; i < array_length(_values); i++) {
        vals[i] = real(_values[i]);
    }
    array_sort(vals, function(a, b) { return real(a) - real(b); });

    var n_vals = array_length(vals);
    var mid = floor(n_vals * 0.5);
    if ((n_vals mod 2) == 1) {
        return real(vals[mid]);
    }

    return (real(vals[mid - 1]) + real(vals[mid])) * 0.5;
}

function timing_calibration_analyze_current_run(_max_delta_ms = 350, _min_matches = 8) {
    var max_delta_ms = max(50, real(_max_delta_ms));
    var min_matches = max(3, floor(real(_min_matches)));

    var expected = timing_calibration_collect_expected_note_ons();
    var actual = timing_calibration_collect_player_note_ons();
    var deltas = timing_calibration_match_deltas(expected, actual, max_delta_ms);
    var match_count = array_length(deltas);

    if (match_count < min_matches) {
        return {
            success: false,
            match_count: match_count,
            median_delta_ms: 0,
            recommended_offset_ms: 0,
            message: "Timing probe incomplete: matched " + string(match_count)
                + " notes, need at least " + string(min_matches) + "."
        };
    }

    var median_delta_ms = timing_calibration_median(deltas);
    var recommended_offset_ms = -median_delta_ms;
    return {
        success: true,
        match_count: match_count,
        median_delta_ms: median_delta_ms,
        recommended_offset_ms: recommended_offset_ms,
        message: "Timing probe: recommended offset " + string_format(recommended_offset_ms, 0, 1)
            + " ms from " + string(match_count)
            + " matches (median delta " + string_format(median_delta_ms, 0, 1) + " ms)."
    };
}

function timing_calibration_probe_from_current_run() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var max_delta_ms = variable_struct_exists(cfg, "timing_calibration_match_window_ms")
        ? max(50, real(variable_struct_get(cfg, "timing_calibration_match_window_ms")))
        : 350;
    var min_matches = variable_struct_exists(cfg, "timing_calibration_min_matches")
        ? max(3, floor(real(variable_struct_get(cfg, "timing_calibration_min_matches"))))
        : 8;

    var result = timing_calibration_analyze_current_run(max_delta_ms, min_matches);
    var state = timing_calibration_ensure_state();
    state.last_match_count = real(result.match_count ?? 0);
    state.last_median_delta_ms = real(result.median_delta_ms ?? 0);
    state.last_message = string(result.message ?? "Timing probe had no result.");

    show_debug_message("[CALIBRATION] " + state.last_message);
    if (variable_global_exists("current_note_display")) {
        global.current_note_display = state.last_message;
    }

    return result;
}



/// @function midi_to_letter(_midi_note)
/// @description Convert MIDI note number to bagpipe letter notation
/// @param _midi_note The MIDI note number
/// @returns String letter notation

function midi_to_letter(_midi_note, _channel = -1) {
    return chanter_midi_to_display(_midi_note, _channel, global.MIDI_chanter ?? "default");
}

function tune_rt_budget_diag_record_scheduler_late_ms(_late_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();
    var warmup_ms = variable_global_exists("RT_BUDGET_SCHED_WARMUP_MS")
        ? max(0, real(global.RT_BUDGET_SCHED_WARMUP_MS))
        : 1000;
    if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
        var since_start_ms = now_ms - real(global.tune_start_real);
        if (since_start_ms < warmup_ms) return;
    }

    if (!variable_global_exists("rt_budget_sched_late_buf") || !is_array(global.rt_budget_sched_late_buf)) {
        global.rt_budget_sched_late_buf = array_create(128, 0);
        global.rt_budget_sched_late_head = 0;
        global.rt_budget_sched_late_count = 0;
        global.rt_budget_diag_last_log_ms = now_ms;
    }

    var buf = global.rt_budget_sched_late_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_sched_late_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = real(_late_ms);

    global.rt_budget_sched_late_buf = buf;
    global.rt_budget_sched_late_head = (head + 1) mod n_buf;
    global.rt_budget_sched_late_count = min(n_buf, floor(real(global.rt_budget_sched_late_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_diag_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_sched_late_count ?? 0));
    if (count < 8) return;

    var vals = array_create(count, 0);
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
    }
    array_sort(vals, function(a, b) { return real(a) - real(b); });

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];

    show_debug_message("[RT_BUDGET] scheduler_late_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " n=" + string(count));

    global.rt_budget_diag_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_scheduler_group(_group_events, _proc_ms, _midi_send_ms = -1, _midi_send_count = -1) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();
    var warmup_ms = variable_global_exists("RT_BUDGET_SCHED_WARMUP_MS")
        ? max(0, real(global.RT_BUDGET_SCHED_WARMUP_MS))
        : 1000;
    if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
        var since_start_ms = now_ms - real(global.tune_start_real);
        if (since_start_ms < warmup_ms) return;
    }

    if (!variable_global_exists("rt_budget_sched_group_proc_buf") || !is_array(global.rt_budget_sched_group_proc_buf)) {
        global.rt_budget_sched_group_proc_buf = array_create(128, 0);
        global.rt_budget_sched_group_events_buf = array_create(128, 0);
        global.rt_budget_sched_group_send_ms_buf = array_create(128, 0);
        global.rt_budget_sched_group_send_count_buf = array_create(128, 0);
        global.rt_budget_sched_group_head = 0;
        global.rt_budget_sched_group_count = 0;
        global.rt_budget_sched_group_last_log_ms = now_ms;
    }

    var proc_buf = global.rt_budget_sched_group_proc_buf;
    var ev_buf = global.rt_budget_sched_group_events_buf;
    var send_ms_buf = global.rt_budget_sched_group_send_ms_buf;
    var send_count_buf = global.rt_budget_sched_group_send_count_buf;
    var n_buf = array_length(proc_buf);
    if (n_buf <= 0 || array_length(ev_buf) != n_buf || array_length(send_ms_buf) != n_buf || array_length(send_count_buf) != n_buf) return;

    var head = floor(real(global.rt_budget_sched_group_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    proc_buf[head] = max(0, real(_proc_ms));
    ev_buf[head] = max(0, floor(real(_group_events)));
    send_ms_buf[head] = max(0, real(_midi_send_ms));
    send_count_buf[head] = max(0, floor(real(_midi_send_count)));

    global.rt_budget_sched_group_proc_buf = proc_buf;
    global.rt_budget_sched_group_events_buf = ev_buf;
    global.rt_budget_sched_group_send_ms_buf = send_ms_buf;
    global.rt_budget_sched_group_send_count_buf = send_count_buf;
    global.rt_budget_sched_group_head = (head + 1) mod n_buf;
    global.rt_budget_sched_group_count = min(n_buf, floor(real(global.rt_budget_sched_group_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_sched_group_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_sched_group_count ?? 0));
    if (count < 8) return;

    var proc_vals = array_create(count, 0);
    var ev_vals = array_create(count, 0);
    var send_ms_vals = array_create(count, 0);
    var sum_proc = 0;
    var sum_events = 0;
    var sum_send_ms = 0;
    var sum_send_count = 0;
    for (var i = 0; i < count; i++) {
        var _proc_sample_ms = real(proc_buf[i]);
        var _ev_sample_n = max(0, real(ev_buf[i]));
        var _send_sample_ms = max(0, real(send_ms_buf[i]));
        var _send_sample_count = max(0, real(send_count_buf[i]));
        proc_vals[i] = _proc_sample_ms;
        ev_vals[i] = _ev_sample_n;
        send_ms_vals[i] = _send_sample_ms;
        sum_proc += _proc_sample_ms;
        sum_events += _ev_sample_n;
        sum_send_ms += _send_sample_ms;
        sum_send_count += _send_sample_count;
    }
    array_sort(proc_vals, true);
    array_sort(ev_vals, true);
    array_sort(send_ms_vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var proc_p50 = proc_vals[i50];
    var proc_p95 = proc_vals[i95];
    var proc_p99 = proc_vals[i99];
    var ev_p50 = ev_vals[i50];
    var ev_p95 = ev_vals[i95];
    var ev_p99 = ev_vals[i99];
    var send_ms_p50 = send_ms_vals[i50];
    var send_ms_p95 = send_ms_vals[i95];
    var send_ms_p99 = send_ms_vals[i99];

    var proc_avg = sum_proc / max(1, count);
    var proc_per_event_us = (sum_proc * 1000) / max(1, sum_events);
    var send_per_event_us = (sum_send_ms * 1000) / max(1, sum_send_count);

    show_debug_message("[RT_BUDGET] scheduler_group_proc_ms p50=" + string_format(proc_p50, 0, 3)
        + " p95=" + string_format(proc_p95, 0, 3)
        + " p99=" + string_format(proc_p99, 0, 3)
        + " avg=" + string_format(proc_avg, 0, 3)
        + " per_event_us=" + string_format(proc_per_event_us, 0, 3)
        + " | midi_send_ms p50=" + string_format(send_ms_p50, 0, 3)
        + " p95=" + string_format(send_ms_p95, 0, 3)
        + " p99=" + string_format(send_ms_p99, 0, 3)
        + " send_per_event_us=" + string_format(send_per_event_us, 0, 3)
        + " | group_events p50=" + string_format(ev_p50, 0, 0)
        + " p95=" + string_format(ev_p95, 0, 0)
        + " p99=" + string_format(ev_p99, 0, 0)
        + " n=" + string(count));

    global.rt_budget_sched_group_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_controller_step_ms(_step_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();
    var warmup_ms = variable_global_exists("RT_BUDGET_SCHED_WARMUP_MS")
        ? max(0, real(global.RT_BUDGET_SCHED_WARMUP_MS))
        : 1000;
    if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
        var since_start_ms = now_ms - real(global.tune_start_real);
        if (since_start_ms < warmup_ms) return;
    }

    if (!variable_global_exists("rt_budget_controller_step_buf") || !is_array(global.rt_budget_controller_step_buf)) {
        global.rt_budget_controller_step_buf = array_create(256, 0);
        global.rt_budget_controller_step_head = 0;
        global.rt_budget_controller_step_count = 0;
        global.rt_budget_controller_step_last_log_ms = now_ms;
    }

    var buf = global.rt_budget_controller_step_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_controller_step_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = max(0, real(_step_ms));

    global.rt_budget_controller_step_buf = buf;
    global.rt_budget_controller_step_head = (head + 1) mod n_buf;
    global.rt_budget_controller_step_count = min(n_buf, floor(real(global.rt_budget_controller_step_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_controller_step_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_controller_step_count ?? 0));
    if (count < 16) return;

    var vals = array_create(count, 0);
    var sum_vals = 0;
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
        sum_vals += vals[i];
    }
    array_sort(vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];
    var pmax = vals[count - 1];
    var avg = sum_vals / max(1, count);

    show_debug_message("[RT_BUDGET] controller_step_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " max=" + string_format(pmax, 0, 3)
        + " avg=" + string_format(avg, 0, 3)
        + " n=" + string(count));

    global.rt_budget_controller_step_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_midi_step_ms(_step_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();

    if (!variable_global_exists("rt_budget_midi_step_buf") || !is_array(global.rt_budget_midi_step_buf)) {
        global.rt_budget_midi_step_buf = array_create(256, 0);
        global.rt_budget_midi_step_head = 0;
        global.rt_budget_midi_step_count = 0;
        global.rt_budget_midi_step_last_log_ms = now_ms;
    }

    var buf = global.rt_budget_midi_step_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_midi_step_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = max(0, real(_step_ms));

    global.rt_budget_midi_step_buf = buf;
    global.rt_budget_midi_step_head = (head + 1) mod n_buf;
    global.rt_budget_midi_step_count = min(n_buf, floor(real(global.rt_budget_midi_step_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_midi_step_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_midi_step_count ?? 0));
    if (count < 16) return;

    var vals = array_create(count, 0);
    var sum_vals = 0;
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
        sum_vals += vals[i];
    }
    array_sort(vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];
    var pmax = vals[count - 1];
    var avg = sum_vals / max(1, count);

    show_debug_message("[RT_BUDGET] midi_process_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " max=" + string_format(pmax, 0, 3)
        + " avg=" + string_format(avg, 0, 3)
        + " n=" + string(count));

    global.rt_budget_midi_step_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_draw_ms(_draw_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();

    if (!variable_global_exists("rt_budget_draw_buf") || !is_array(global.rt_budget_draw_buf)) {
        global.rt_budget_draw_buf = array_create(256, 0);
        global.rt_budget_draw_head = 0;
        global.rt_budget_draw_count = 0;
        global.rt_budget_draw_last_log_ms = now_ms;
    }

    var buf = global.rt_budget_draw_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_draw_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = max(0, real(_draw_ms));

    global.rt_budget_draw_buf = buf;
    global.rt_budget_draw_head = (head + 1) mod n_buf;
    global.rt_budget_draw_count = min(n_buf, floor(real(global.rt_budget_draw_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_draw_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_draw_count ?? 0));
    if (count < 16) return;

    var vals = array_create(count, 0);
    var sum_vals = 0;
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
        sum_vals += vals[i];
    }
    array_sort(vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];
    var pmax = vals[count - 1];
    var avg = sum_vals / max(1, count);

    show_debug_message("[RT_BUDGET] draw_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " max=" + string_format(pmax, 0, 3)
        + " avg=" + string_format(avg, 0, 3)
        + " n=" + string(count));

    global.rt_budget_draw_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_anchor_draw_ms(_anchor_kind, _draw_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var kind = string(_anchor_kind ?? "unknown");
    if (string_length(kind) <= 0) kind = "unknown";
    var now_ms = timing_get_engine_now_ms();

    if (!variable_global_exists("rt_budget_anchor_draw_stats") || !is_struct(global.rt_budget_anchor_draw_stats)) {
        global.rt_budget_anchor_draw_stats = {};
    }

    var stats = variable_struct_exists(global.rt_budget_anchor_draw_stats, kind)
        ? global.rt_budget_anchor_draw_stats[$ kind]
        : {
            buf: array_create(128, 0),
            head: 0,
            count: 0,
            last_log_ms: now_ms
        };

    if (!is_struct(stats) || !variable_struct_exists(stats, "buf") || !is_array(stats.buf)) {
        stats = {
            buf: array_create(128, 0),
            head: 0,
            count: 0,
            last_log_ms: now_ms
        };
    }

    var buf = stats.buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(stats.head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = max(0, real(_draw_ms));

    stats.buf = buf;
    stats.head = (head + 1) mod n_buf;
    stats.count = min(n_buf, floor(real(stats.count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(stats.last_log_ms ?? 0)) < interval_ms) {
        global.rt_budget_anchor_draw_stats[$ kind] = stats;
        return;
    }

    var count = floor(real(stats.count ?? 0));
    if (count < 16) {
        global.rt_budget_anchor_draw_stats[$ kind] = stats;
        return;
    }

    var vals = array_create(count, 0);
    var sum_vals = 0;
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
        sum_vals += vals[i];
    }
    array_sort(vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];
    var pmax = vals[count - 1];
    var avg = sum_vals / max(1, count);

    show_debug_message("[RT_BUDGET] anchor_draw_ms kind=" + kind
        + " p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " max=" + string_format(pmax, 0, 3)
        + " avg=" + string_format(avg, 0, 3)
        + " n=" + string(count));

    stats.last_log_ms = now_ms;
    global.rt_budget_anchor_draw_stats[$ kind] = stats;
}

function tune_rt_budget_diag_record_controller_step_interval_ms(_step_dt_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;
    if (_step_dt_ms <= 0) return;

    var now_ms = timing_get_engine_now_ms();
    var warmup_ms = variable_global_exists("RT_BUDGET_SCHED_WARMUP_MS")
        ? max(0, real(global.RT_BUDGET_SCHED_WARMUP_MS))
        : 1000;
    if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
        var since_start_ms = now_ms - real(global.tune_start_real);
        if (since_start_ms < warmup_ms) return;
    }

    if (!variable_global_exists("rt_budget_controller_step_dt_buf") || !is_array(global.rt_budget_controller_step_dt_buf)) {
        global.rt_budget_controller_step_dt_buf = array_create(256, 0);
        global.rt_budget_controller_step_dt_head = 0;
        global.rt_budget_controller_step_dt_count = 0;
        global.rt_budget_controller_step_dt_last_log_ms = now_ms;
    }

    var buf = global.rt_budget_controller_step_dt_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_controller_step_dt_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = max(0, real(_step_dt_ms));

    global.rt_budget_controller_step_dt_buf = buf;
    global.rt_budget_controller_step_dt_head = (head + 1) mod n_buf;
    global.rt_budget_controller_step_dt_count = min(n_buf, floor(real(global.rt_budget_controller_step_dt_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_controller_step_dt_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_controller_step_dt_count ?? 0));
    if (count < 16) return;

    var vals = array_create(count, 0);
    var sum_vals = 0;
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
        sum_vals += vals[i];
    }
    array_sort(vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];
    var pmax = vals[count - 1];
    var avg = sum_vals / max(1, count);

    show_debug_message("[RT_BUDGET] controller_step_interval_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " max=" + string_format(pmax, 0, 3)
        + " avg=" + string_format(avg, 0, 3)
        + " n=" + string(count));

    global.rt_budget_controller_step_dt_last_log_ms = now_ms;
}

function tune_rt_budget_diag_record_scheduler_step_pump(_dispatched, _max_overdue_ms, _min_overdue_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;

    var now_ms = timing_get_engine_now_ms();
    var warmup_ms = variable_global_exists("RT_BUDGET_SCHED_WARMUP_MS")
        ? max(0, real(global.RT_BUDGET_SCHED_WARMUP_MS))
        : 1000;
    if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
        var since_start_ms = now_ms - real(global.tune_start_real);
        if (since_start_ms < warmup_ms) return;
    }

    if (!variable_global_exists("rt_budget_sched_step_overdue_buf") || !is_array(global.rt_budget_sched_step_overdue_buf)) {
        global.rt_budget_sched_step_overdue_buf = array_create(128, 0);
        global.rt_budget_sched_step_dispatched_buf = array_create(128, 0);
        global.rt_budget_sched_step_early_buf = array_create(128, 0);
        global.rt_budget_sched_step_head = 0;
        global.rt_budget_sched_step_count = 0;
        global.rt_budget_sched_step_last_log_ms = now_ms;
    }

    var overdue_buf = global.rt_budget_sched_step_overdue_buf;
    var dispatched_buf = global.rt_budget_sched_step_dispatched_buf;
    var early_buf = global.rt_budget_sched_step_early_buf;
    var n_buf = array_length(overdue_buf);
    if (n_buf <= 0 || array_length(dispatched_buf) != n_buf || array_length(early_buf) != n_buf) return;

    var head = floor(real(global.rt_budget_sched_step_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    overdue_buf[head] = max(0, real(_max_overdue_ms));
    early_buf[head] = max(0, -real(_min_overdue_ms));
    dispatched_buf[head] = max(0, floor(real(_dispatched)));

    global.rt_budget_sched_step_overdue_buf = overdue_buf;
    global.rt_budget_sched_step_dispatched_buf = dispatched_buf;
    global.rt_budget_sched_step_early_buf = early_buf;
    global.rt_budget_sched_step_head = (head + 1) mod n_buf;
    global.rt_budget_sched_step_count = min(n_buf, floor(real(global.rt_budget_sched_step_count ?? 0)) + 1);

    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_sched_step_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_sched_step_count ?? 0));
    if (count < 8) return;

    var overdue_vals = array_create(count, 0);
    var early_vals = array_create(count, 0);
    var dispatch_vals = array_create(count, 0);
    for (var i = 0; i < count; i++) {
        overdue_vals[i] = real(overdue_buf[i]);
        early_vals[i] = real(early_buf[i]);
        dispatch_vals[i] = real(dispatched_buf[i]);
    }
    array_sort(overdue_vals, true);
    array_sort(early_vals, true);
    array_sort(dispatch_vals, true);

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);

    show_debug_message("[RT_BUDGET] scheduler_step_pump dispatched p50=" + string_format(dispatch_vals[i50], 0, 0)
        + " p95=" + string_format(dispatch_vals[i95], 0, 0)
        + " p99=" + string_format(dispatch_vals[i99], 0, 0)
        + " | overdue_ms p50=" + string_format(overdue_vals[i50], 0, 3)
        + " p95=" + string_format(overdue_vals[i95], 0, 3)
        + " p99=" + string_format(overdue_vals[i99], 0, 3)
        + " | early_ms p50=" + string_format(early_vals[i50], 0, 3)
        + " p95=" + string_format(early_vals[i95], 0, 3)
        + " p99=" + string_format(early_vals[i99], 0, 3)
        + " n=" + string(count));

    global.rt_budget_sched_step_last_log_ms = now_ms;
}

/// @function tune_group_events_by_timestamp(_events)
/// @description Group events by timestamp to batch simultaneous events
/// @param _events Array of event structs with .time property
/// @returns Array of timestamp groups: [{time: ms, events: [...]}, ...]

function tune_group_events_by_timestamp(_events) {
    var groups = [];
    var current_timestamp = -1;
    var current_group = undefined;
    
    // Events are already sorted by time from preprocessing
    for (var i = 0; i < array_length(_events); i++) {
        var ev = _events[i];
        
        if (ev.time != current_timestamp) {
            // New timestamp - start new group
            current_timestamp = ev.time;
            current_group = {
                time: current_timestamp,
                events: []
            };
            array_push(groups, current_group);
        }
        
        // Add event to current group
        array_push(current_group.events, ev);
    }

    // Precompute stable playback order once per group to keep callback hot path minimal.
    for (var g = 0; g < array_length(groups); g++) {
        var grp = groups[g];
        if (!is_struct(grp) || !is_array(grp.events)) continue;

        var n_group_events = array_length(grp.events);
        var ordered_events = array_create(n_group_events, undefined);
        var ordered_count = 0;

        for (var oi = 0; oi < n_group_events; oi++) {
            var oev = grp.events[oi];
            if (oev.type == "note_off") {
                ordered_events[ordered_count] = oev;
                ordered_count += 1;
            }
        }
        for (var oi = 0; oi < n_group_events; oi++) {
            var oev = grp.events[oi];
            if (oev.type == "marker") {
                ordered_events[ordered_count] = oev;
                ordered_count += 1;
            }
        }
        for (var oi = 0; oi < n_group_events; oi++) {
            var oev = grp.events[oi];
            if (oev.type == "note_on") {
                ordered_events[ordered_count] = oev;
                ordered_count += 1;
            }
        }

        grp.ordered_events = ordered_events;
        grp.ordered_count = ordered_count;
        groups[g] = grp;
    }
    
    show_debug_message("✓ Batched " + string(array_length(_events)) + " events into " + string(array_length(groups)) + " timestamp groups");
    return groups;
}

function tune_scheduler_enqueue_deferred(_item) {
    if (!is_struct(_item)) return;
    if (!variable_global_exists("tune_deferred_queue") || !is_array(global.tune_deferred_queue)) {
        global.tune_deferred_queue = [];
        global.tune_deferred_head = 0;
    }
    array_push(global.tune_deferred_queue, _item);
}

function tune_scheduler_process_deferred(_max_items = 128, _max_budget_us = 1200) {
    if (!variable_global_exists("tune_deferred_queue") || !is_array(global.tune_deferred_queue)) return 0;

    var queue = global.tune_deferred_queue;
    var qn = array_length(queue);
    if (qn <= 0) {
        global.tune_deferred_head = 0;
        return 0;
    }

    var head = floor(real(global.tune_deferred_head ?? 0));
    if (head < 0) head = 0;
    if (head >= qn) {
        global.tune_deferred_queue = [];
        global.tune_deferred_head = 0;
        return 0;
    }

    var max_items = max(1, floor(real(_max_items)));
    var max_budget_us = max(0, real(_max_budget_us));
    var start_us = get_timer();
    var processed = 0;

    while (head < qn && processed < max_items) {
        if (max_budget_us > 0 && (get_timer() - start_us) >= max_budget_us) break;

        var item = queue[head];
        head += 1;
        if (!is_struct(item)) {
            processed += 1;
            continue;
        }

        var kind = string(item.kind ?? "");
        if (kind == "panel_note_on") {
            cn_panel_on_tune_note_on(real(item.measure ?? 0), real(item.note ?? 0), real(item.channel ?? 0), real(item.time_ms ?? 0));
        }
        else if (kind == "panel_note_off") {
            cn_panel_on_tune_note_off(real(item.measure ?? 0), real(item.note ?? 0), real(item.channel ?? 0), real(item.time_ms ?? 0));
        }
        else if (kind == "panel_beat") {
            cn_panel_on_beat_marker(real(item.measure ?? 0), real(item.beat ?? 0), (item.countin ?? false));
        }
        else if (kind == "current_note_display") {
            var note_letter = midi_to_letter(real(item.note ?? 0), real(item.channel ?? 0));
            global.current_note_display = note_letter + " (delta: " + string(real(item.delta_ms ?? 0)) + "ms)";
        }
        else if (kind == "history_event") {
            var ev = item.ev;
            if (is_struct(ev)) {
                var ev_type = ev.type;
                var marker_type = "";
                if (ev.type == "marker") {
                    marker_type = struct_exists(ev, "marker_type") ? ev.marker_type : "";
                    ev_type = "marker_" + string(marker_type);
                }

                var ev_note = struct_exists(ev, "note") ? ev.note : 0;
                var ev_velocity = struct_exists(ev, "velocity") ? ev.velocity : 0;
                var ev_channel = struct_exists(ev, "channel") ? ev.channel : 0;
                var ev_note_canonical = "";
                if ((ev.type == "note_on" || ev.type == "note_off") && real(ev_note) > 0) {
                    ev_note_canonical = chanter_midi_to_canonical(ev_note, global.MIDI_chanter ?? "default", ev_channel);
                }
                var ev_measure = struct_exists(ev, "measure") ? ev.measure : 0;
                var ev_beat = struct_exists(ev, "beat") ? ev.beat : 0;
                var ev_beat_fraction = struct_exists(ev, "beat_fraction") ? ev.beat_fraction : 0;
                if (ev_beat_fraction == 0 && struct_exists(ev, "division")) {
                    ev_beat_fraction = ev.division;
                }

                var expected_elapsed = real(item.expected_time_ms ?? 0);
                var actual_elapsed = real(item.actual_time_ms ?? expected_elapsed);
                event_history_add({
                    timestamp_ms: actual_elapsed,
                    expected_time_ms: expected_elapsed,
                    actual_time_ms: actual_elapsed,
                    delta_ms: actual_elapsed - expected_elapsed,
                    event_type: ev_type,
                    source: "game",
                    note_midi: ev_note,
                    note_midi_raw: ev_note,
                    note_canonical: ev_note_canonical,
                    velocity: ev_velocity,
                    channel: ev_channel,
                    tune_name: variable_global_exists("current_tune_name") ? global.current_tune_name : "unknown",
                    event_id: struct_exists(ev, "event_id") ? ev.event_id : 0,
                    marker_type: marker_type,
                    measure: ev_measure,
                    beat: ev_beat,
                    beat_fraction: ev_beat_fraction
                });
            }
        }

        processed += 1;
    }

    if (head > 0) {
        if (head >= qn) {
            global.tune_deferred_queue = [];
            global.tune_deferred_head = 0;
        } else if (head >= 64) {
            var remaining = [];
            for (var ri = head; ri < qn; ri++) array_push(remaining, queue[ri]);
            global.tune_deferred_queue = remaining;
            global.tune_deferred_head = 0;
        } else {
            global.tune_deferred_head = head;
        }
    }

    return processed;
}

function tune_scheduler_flush_deferred_all() {
    var guard = 0;
    while (guard < 100000) {
        var processed = tune_scheduler_process_deferred(4096, 0);
        if (processed <= 0) break;
        guard += processed;
    }
}

/// @function tune_start(tune_events)
/// @param tune_events  The array of events to play

function tune_start(_tune_events) {
    if (!variable_global_exists("enable_current_note_layer") || global.enable_current_note_layer) {
        cn_panel_prepare_tune_plan(_tune_events);
    }

    // Group events by timestamp for batched processing
    global.tune_event_groups = tune_group_events_by_timestamp(_tune_events);
    global.tune_group_index = 0;
    if (array_length(global.tune_event_groups) <= 0) {
        show_debug_message("WARNING: No tune event groups to schedule.");
        return false;
    }
    
    // Cache tune filename for event logging (avoid repeated lookups)
    global.current_tune_name = obj_tune.tune_data.filename ?? "unknown";

    // Initialize event history before playback
    event_history_clear();
    
    // Initialize current note display
    global.current_note_display = "";

    // Optional scheduler correction (absolute-time catch-up)
    if (!variable_global_exists("PLAYBACK_SCHEDULER_CATCHUP")) {
        global.PLAYBACK_SCHEDULER_CATCHUP = true;
    }
    if (!variable_global_exists("PLAYBACK_SCHEDULER_MODE")) {
        global.PLAYBACK_SCHEDULER_MODE = "timesource";
    }
    if (!variable_global_exists("PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS")) {
        global.PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS = 0.0;
    }
    if (!variable_global_exists("PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP")) {
        global.PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP = 8;
    }
    if (!variable_global_exists("PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US")) {
        global.PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US = 1000;
    }
    if (!variable_global_exists("PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP")) {
        global.PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP = 128;
    }
    if (!variable_global_exists("PLAYBACK_DEFERRED_MAX_BUDGET_US")) {
        global.PLAYBACK_DEFERRED_MAX_BUDGET_US = 1200;
    }
    global.tune_deferred_queue = [];
    global.tune_deferred_head = 0;

    var use_step_scheduler = string_lower(string(global.PLAYBACK_SCHEDULER_MODE)) == "step";
    global.tune_scheduler_mode_step = use_step_scheduler;
    global.tune_scheduler_active = true;

    // Anchor real playback start before timer begins
    global.tune_start_real = timing_get_engine_now_ms();

    var first_due_ms = real(global.tune_event_groups[0].time ?? 0);
    show_debug_message("delta_ms " + string(first_due_ms)); //For testing only
    if (use_step_scheduler) {
        global.tune_timer = noone;
        tune_scheduler_step_tick();
    } else {
        // Initialize timer and process immediately-due groups inline to avoid startup skew.
        global.tune_timer = time_source_create(
            time_source_global,
            0.001,
            time_source_units_seconds,
            script_tune_callback_batched,
            [],
            1,
            time_source_expire_after
        );

        if (first_due_ms <= 0.001) {
            script_tune_callback_batched();
        } else {
            time_source_reconfigure(
                global.tune_timer,
                first_due_ms / 1000,
                time_source_units_seconds,
                script_tune_callback_batched,
                [],
                1,
                time_source_expire_after
            );
            time_source_start(global.tune_timer);
        }
    }

    return true;
}

/// @function script_tune_callback_batched()
/// @description Batched callback that processes all events at the same timestamp

function script_tune_callback_batched() {
    if (!variable_global_exists("tune_event_groups") || !is_array(global.tune_event_groups)) return;
    if (!variable_global_exists("tune_group_index")) return;
    if (global.tune_group_index < 0 || global.tune_group_index >= array_length(global.tune_event_groups)) return;

    var group = global.tune_event_groups[global.tune_group_index];
    var real_elapsed = timing_get_engine_now_ms() - global.tune_start_real;
    var expected_elapsed = group.time;
    tune_rt_budget_diag_record_scheduler_late_ms(real_elapsed - expected_elapsed);
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.last_dispatched_expected_ms = real(expected_elapsed);
    }
    var use_current_note_panel = (!variable_global_exists("enable_current_note_layer") || global.enable_current_note_layer);

    var callback_start_us = get_timer();
    var n_group_events = array_length(group.events);
    var ordered_events = variable_struct_exists(group, "ordered_events") && is_array(group.ordered_events)
        ? group.ordered_events : group.events;
    var ordered_count = variable_struct_exists(group, "ordered_count")
        ? floor(real(group.ordered_count))
        : array_length(ordered_events);
    if (ordered_count > array_length(ordered_events)) ordered_count = array_length(ordered_events);
    
    // Temp: log first and last few groups to verify delta calculation
    if ((!variable_global_exists("PLAYBACK_DEBUG_GROUP_TIMING") || global.PLAYBACK_DEBUG_GROUP_TIMING)
        && (global.tune_group_index < 3 || global.tune_group_index > array_length(global.tune_event_groups) - 3)) {
        show_debug_message("Group " + string(global.tune_group_index) + " (" + string(n_group_events) + " events): real=" + string(real_elapsed) + " expected=" + string(expected_elapsed) + " delta=" + string(real_elapsed - expected_elapsed));
    }
    
    // Process ALL events in this timestamp group
    var has_last_note_on = false;
    var last_note_on_note = 0;
    var last_note_on_channel = 0;
    var midi_send_accum_us = 0;
    var midi_send_count = 0;
    for (var i = 0; i < ordered_count; i++) {
        var ev = ordered_events[i];
        
        // PLAY EVENT using Giavapps MIDI send_short
        if (ev.type == "note_on") {
            var status_byte = 144 + ev.channel;
            var _send_t0_us = get_timer();
            midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, ev.velocity);
            midi_send_accum_us += (get_timer() - _send_t0_us);
            midi_send_count += 1;
            // Track for UI update (only if not metronome channel)
            if (ev.channel != global.METRONOME_CONFIG.channel) {
                has_last_note_on = true;
                last_note_on_note = ev.note;
                last_note_on_channel = ev.channel;
                if (use_current_note_panel) {
                    tune_scheduler_enqueue_deferred({
                        kind: "panel_note_on",
                        measure: real(ev.measure ?? 0),
                        note: real(ev.note ?? 0),
                        channel: real(ev.channel ?? 0),
                        time_ms: real(ev.time ?? expected_elapsed)
                    });
                }
            }
        } 
        else if (ev.type == "note_off") {
            var status_byte = 128 + ev.channel;
            var _send_t0_us = get_timer();
            midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, 0);
            midi_send_accum_us += (get_timer() - _send_t0_us);
            midi_send_count += 1;
            if (ev.channel != global.METRONOME_CONFIG.channel) {
                if (use_current_note_panel) {
                    tune_scheduler_enqueue_deferred({
                        kind: "panel_note_off",
                        measure: real(ev.measure ?? 0),
                        note: real(ev.note ?? 0),
                        channel: real(ev.channel ?? 0),
                        time_ms: real(ev.time ?? expected_elapsed)
                    });
                }
            }
        }
        else if (ev.type == "marker") {
            // No MIDI output for marker entries.
            var marker_kind = string(ev.marker_type ?? "");
            if (marker_kind == "beat" || marker_kind == "countin_beat") {
                if (use_current_note_panel) {
                    tune_scheduler_enqueue_deferred({
                        kind: "panel_beat",
                        measure: real(ev.measure ?? 0),
                        beat: real(ev.beat ?? 0),
                        countin: (marker_kind == "countin_beat")
                    });
                }
            }
        }

        // Skip metronome MIDI events (channel 9 note_on/note_off) - keep structure markers
        var ev_channel = struct_exists(ev, "channel") ? ev.channel : 0;
        var is_metronome_midi = (ev.type == "note_on" || ev.type == "note_off") 
                                && ev_channel == global.METRONOME_CONFIG.channel;
        
        if (!is_metronome_midi) {
            tune_scheduler_enqueue_deferred({
                kind: "history_event",
                ev: ev,
                expected_time_ms: expected_elapsed,
                actual_time_ms: real_elapsed
            });
        }
    }
    
    // Update UI once per group (only for note_on events)
    if (has_last_note_on) {
        tune_scheduler_enqueue_deferred({
            kind: "current_note_display",
            note: real(last_note_on_note),
            channel: real(last_note_on_channel),
            delta_ms: real(real_elapsed - expected_elapsed)
        });
    }
    
    // Advance to next group
    global.tune_group_index++;
    
    // Check if done
    if (global.tune_group_index >= array_length(global.tune_event_groups)) {
        if (variable_global_exists("tune_scheduler_mode_step") && !global.tune_scheduler_mode_step
            && variable_global_exists("tune_timer") && global.tune_timer != noone) {
            time_source_stop(global.tune_timer);
        }
        global.tune_scheduler_active = false;
        tune_scheduler_flush_deferred_all();
        gv_on_tune_playback_finished(expected_elapsed);
        tune_rt_budget_diag_record_scheduler_group(n_group_events, (get_timer() - callback_start_us) * 0.001, midi_send_accum_us * 0.001, midi_send_count);
        if (global.EVENT_HISTORY_AUTO_EXPORT && !global.EVENT_HISTORY_EXPORTED) {
            export_event_history();
            global.EVENT_HISTORY_EXPORTED = true;
        }
        // Schedule cleanup one beat later (600ms at moderate tempo)
        schedule_tune_cleanup(600);
        // show_debug_message("Tune finished.");
        return;
    }
    
    // Step scheduler runs from Step event and does not arm a time_source timer.
    if (variable_global_exists("tune_scheduler_mode_step") && global.tune_scheduler_mode_step) {
        tune_rt_budget_diag_record_scheduler_group(n_group_events, (get_timer() - callback_start_us) * 0.001, midi_send_accum_us * 0.001, midi_send_count);
        return;
    }

    // Schedule next group
    var next_time = global.tune_event_groups[global.tune_group_index].time;
    var prev_time = group.time;
    var delta_ms = next_time - prev_time;
    if (global.PLAYBACK_SCHEDULER_CATCHUP) {
        var real_elapsed_now = timing_get_engine_now_ms() - global.tune_start_real;
        delta_ms = next_time - real_elapsed_now;
    }
    delta_ms = max(delta_ms, 0.001);  // Clamp to minimum time source period
    
    time_source_reconfigure(
        global.tune_timer,
        delta_ms / 1000,
        time_source_units_seconds,
        script_tune_callback_batched,
        [],
        1,
        time_source_expire_after
    );
    
    time_source_start(global.tune_timer);
    tune_rt_budget_diag_record_scheduler_group(n_group_events, (get_timer() - callback_start_us) * 0.001, midi_send_accum_us * 0.001, midi_send_count);
}

function tune_scheduler_step_tick() {
    if (!variable_global_exists("tune_scheduler_mode_step") || !global.tune_scheduler_mode_step) return;
    if (!variable_global_exists("tune_scheduler_active") || !global.tune_scheduler_active) return;
    if (!variable_global_exists("tune_event_groups") || !is_array(global.tune_event_groups)) return;
    if (!variable_global_exists("tune_group_index")) return;

    var n_groups = array_length(global.tune_event_groups);
    if (global.tune_group_index < 0 || global.tune_group_index >= n_groups) return;

    var elapsed_ms = timing_get_engine_now_ms() - real(global.tune_start_real ?? 0);
    var lookahead_ms = max(0, real(global.PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS ?? 0));
    var max_groups = max(1, floor(real(global.PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP ?? 32)));
    var max_pump_us = max(100, real(global.PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US ?? 1000));
    var pump_start_us = get_timer();

    var dispatched = 0;
    var max_overdue_ms = -1000000000;
    var min_overdue_ms = 1000000000;
    while (dispatched < max_groups && global.tune_group_index < n_groups) {
        if (get_timer() - pump_start_us >= max_pump_us) break;
        var due_time_ms = real(global.tune_event_groups[global.tune_group_index].time ?? 0);
        if (due_time_ms > elapsed_ms + lookahead_ms) break;
        var overdue_ms = elapsed_ms - due_time_ms;
        if (overdue_ms > max_overdue_ms) max_overdue_ms = overdue_ms;
        if (overdue_ms < min_overdue_ms) min_overdue_ms = overdue_ms;
        script_tune_callback_batched();
        dispatched += 1;
        elapsed_ms = timing_get_engine_now_ms() - real(global.tune_start_real ?? 0);
        if (!variable_global_exists("tune_scheduler_active") || !global.tune_scheduler_active) break;
    }

    if (dispatched > 0) {
        tune_rt_budget_diag_record_scheduler_step_pump(dispatched, max_overdue_ms, min_overdue_ms);
    }
}

// ============ OLD SINGLE-EVENT CALLBACK (PRESERVED FOR REFERENCE) ============

function script_tune_callback() {

    var ev = global.tune_events[global.tune_index];

    // Debugging: compare real time vs expected tune time
    var real_elapsed = timing_get_engine_now_ms() - global.tune_start_real;
    var expected_elapsed = ev.time;
    // show_debug_message("Event " + string(global.tune_index)
    //     + " expected=" + string(expected_elapsed)
    //     + " real=" + string(real_elapsed));
    
    // Temp: log first and last few events to verify delta calculation
    if (global.tune_index < 3 || global.tune_index > array_length(global.tune_events) - 3) {
        show_debug_message("Event " + string(global.tune_index) + ": real=" + string(real_elapsed) + " expected=" + string(expected_elapsed) + " delta=" + string(real_elapsed - expected_elapsed));
    }

    // PLAY EVENT using Giavapps MIDI send_short
    // Formula: Status Byte = Base Event Code + Channel
    // Note On: 144 + channel, Note Off: 128 + channel
    if (ev.type == "note_on") {
        var status_byte = 144 + ev.channel;
        midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, ev.velocity);
        // show_debug_message("Note ON: " + string(ev.note) + " velocity=" + string(ev.velocity) + " channel=" + string(ev.channel));
    } 
    else if (ev.type == "note_off") {
        var status_byte = 128 + ev.channel;
        midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, 0);
        // show_debug_message("Note OFF: " + string(ev.note) + " channel=" + string(ev.channel));
    }

	//Write to the beam drawing array
		//Future function

	//Write to the EVENT LOG
	// Log event to history for analysis
var note_letter = "";
if (ev.type == "note_on") {
    // Convert MIDI note back to letter (for display/analysis)
    note_letter = midi_to_letter(ev.note, ev.channel);
}

// TEMPORARILY DISABLED FOR TIMING TEST
/*
event_history_add({
    timestamp_ms: real_elapsed,  // Actual elapsed time since tune start
    expected_time_ms: expected_elapsed,  // Expected elapsed time
    actual_time_ms: real_elapsed,  // Same as timestamp for game playback
    delta_ms: real_elapsed - expected_elapsed,  // Timing error (+ = late, - = early)
    
    measure: 0,  // Populated later when metronome added
    beat: 0,
    beat_fraction: 0,
    
    event_type: ev.type,
    source: "game",
    
    note_midi: ev.note ?? 0,
    note_letter: note_letter,
    velocity: ev.velocity ?? 0,
    channel: ev.channel ?? 0,
    
    tune_name: obj_tune.tune_data.filename ?? "unknown",
    event_id: 0,
    is_embellishment: false,
    embellishment_name: "",
    
    timing_quality: "on_time"  // Always perfect for game playback
});
*/
	
	//Write to the Current-Note window (only for non-metronome events)
	if (ev.type == "note_on" && ev.channel != global.METRONOME_CONFIG.channel) {
		var display_text = note_letter + " (delta: " + string(real_elapsed - expected_elapsed) + "ms)";
		global.current_note_display = display_text;
	}

    // Advance index
    global.tune_index++;

    // If no more events, stop
    if (global.tune_index >= array_length(global.tune_events)) {
        time_source_stop(global.tune_timer);
        gv_on_tune_playback_finished(expected_elapsed);
        // Schedule cleanup one beat later (600ms at moderate tempo)
        schedule_tune_cleanup(600);
        // show_debug_message("Tune finished.");
        return;
    }

    // Compute next delay (absolute-time catch-up when enabled)
    var next_time  = global.tune_events[global.tune_index].time;
    var prev_time  = ev.time;
    var delta_ms   = next_time - prev_time;
    if (global.PLAYBACK_SCHEDULER_CATCHUP) {
        var real_elapsed_now = timing_get_engine_now_ms() - global.tune_start_real;
        delta_ms = next_time - real_elapsed_now;
    }
    delta_ms = max(delta_ms, 0.001);

    time_source_reconfigure(
        global.tune_timer,
        delta_ms / 1000,
        time_source_units_seconds,
        script_tune_callback,
        [],
        1,
        time_source_expire_after
    );

    time_source_start(global.tune_timer);
}

/// @function schedule_tune_cleanup(_delay_ms)
/// @description Schedule MIDI cleanup (stop all notes, stop input checking) after a delay
/// @param _delay_ms Delay in milliseconds before cleanup (typically one beat duration)

function schedule_tune_cleanup(_delay_ms) {
    var cleanup_timer = time_source_create(
        time_source_global,
        _delay_ms / 1000,
        time_source_units_seconds,
        tune_cleanup_after_finish,
        [],
        1,
        time_source_expire_after
    );
    time_source_start(cleanup_timer);
    show_debug_message("⏱ Scheduled tune cleanup in " + string(_delay_ms) + "ms");
}

/// @function tune_cleanup_after_finish()
/// @description Cleanup callback: stop all MIDI notes and disable MIDI input checking

function tune_cleanup_after_finish() {
    MIDI_send_off();  // Stop all notes on all channels
    MIDI_stop_checking_messages_and_errors();  // Stop MIDI input checking and close devices
    show_debug_message("✓ Tune cleanup complete");
}

//////Metronome//////
// Metronome playback generation is implemented in `scr_metronome.gml`
// (`metronome_generate_events` and `metronome_generate_countin_events`).
// The historical prototype below is intentionally left as reference only.
    /*
    // Check if metronome exists and is enabled
    if (is_undefined(_tune.metronome) || !variable_struct_exists(_tune.metronome, "enabled") || !_tune.metronome.enabled) {
        return [];
    }

    var settings = _tune.metronome;
    var events = [];

    var bpm          = settings.bpm;
    var beats_per_bar = settings.beats_per_bar;
    var ms_per_beat  = 60000 / bpm; // ms, not seconds

    var bar_pattern = tune_metronome_build_pattern(ms_per_beat, settings.subdivision);
    var tune_length = tune_get_total_ms(_tune);

    var t = 0;
    while (t < tune_length)
    {
        for (var i = 0; i < array_length(bar_pattern); i++)
        {
            var p = bar_pattern[i];
            var click_time = t + p.time;

            var note = p.accent ? settings.accent_note : settings.normal_note;

            array_push(events, {
                time:     click_time,
                type:     ev_midi,
                channel:  settings.channel,
                note:     note,
                velocity: settings.velocity
            });
        }

        t += beats_per_bar * ms_per_beat;
    }

    return events;
}


function tune_metronome_build_pattern(_mpb, _subdivision)
{
    var pattern = [];

    switch (_subdivision)
    {
        case "quarter":
            array_push(pattern, { time: 0, accent: true });
            break;

        case "eighth":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.5, accent: false });
            break;

        case "dotcut":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.666, accent: false });
            break;

        case "cutdot":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.333, accent: false });
            break;

        default:
            array_push(pattern, { time: 0, accent: true });
            break;
    }

    return pattern;
}


function tune_get_total_ms(_tune)
{
    var events = _tune.events;
    var last_time = 0;

    for (var i = 0; i < array_length(events); i++)
    {
        if (events[i].time > last_time)
            last_time = events[i].time;
    }

    return last_time;
}


function tune_build_events(_tune)
{
    // Base events (manual)
    var base = _tune.events;
    show_debug_message("tune_build_events: Base has " + string(array_length(base)) + " events");
    
    var met  = metronome_generate_events(_tune);  // Use new metronome system
    show_debug_message("tune_build_events: Metronome returned " + string(array_length(met)) + " events");
    
    // Debug: show first metronome event if any
    if (array_length(met) > 0) {
        var first = met[0];
        show_debug_message("  First metro event: time=" + string(first.time) + " note=" + string(first.note) + " channel=" + string(first.channel));
    }

    // Merge arrays
    var total = array_length(base) + array_length(met);
    var merged = array_create(total);

    var i = 0;
    for (var j = 0; j < array_length(base); j++) {
        merged[i++] = base[j];
    }
    for (var j = 0; j < array_length(met); j++) {
        merged[i++] = met[j];
    }

    // Sort by time
    array_sort(merged, function(a, b) { return a.time - b.time; });
    
    show_debug_message("tune_build_events: Merged total = " + string(array_length(merged)) + " events");

    return merged;
	}