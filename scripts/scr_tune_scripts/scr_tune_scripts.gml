
// scr_tune_scripts â€” Playback & event preprocessing
// Purpose: Build runtime event lists (merge tune + metronome), start playback and provide the time-source callback that sends MIDI.
// Key functions: tune_start, script_tune_callback_batched

/// @function create_set_item(_tune_filename)
/// @description Create a new set item with default settings
/// @param _tune_filename The tune file path
/// @returns Set item struct
/// @reads global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.loop_jump_to_selection
/// @callers scr_button_try_load_tune_candidate, scr_tune_OK

function create_set_item(_tune_filename) {
    return {
        tune_filename: _tune_filename,
        bpm: undefined,  // undefined = use tune metadata
        metronome_mode: global.metronome_mode ?? 2,
        metronome_pattern: global.metronome_pattern_selection,
        metronome_volume: global.metronome_volume ?? 100,
        count_in_measures: 1,
        loop_jump_to_selection: global.loop_jump_to_selection ?? false,
        include_drum_roll: false,
        drum_roll_variant: undefined
    };
}

/// @function timing_calibration_ensure_state()
/// @description Lazily initialise global.timing_calibration to its default struct and return it.
/// @reads global.timing_calibration
/// @writes global.timing_calibration (first call only)
/// @callers all timing_calibration_* functions
function timing_calibration_ensure_state() {
    if (!variable_global_exists("timing_calibration") || !is_struct(global.timing_calibration)) {
        global.timing_calibration = {
            active: false,
            status: "idle",
            active_device_key: "",
            device_profiles: {},
            audio_offset_ms: 0,
            visual_offset_ms: 0,
            input_offset_ms: 0,  // RESERVED: future use if true MIDI device timestamps become available
            last_message: "Timing offsets loaded.",
            jitter_summary: {
                scheduler_late_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
                controller_step_interval_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
                midi_process_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
                draw_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 }
            }
        };
    }

    var state = global.timing_calibration;
    if (!variable_struct_exists(state, "active_device_key")) state.active_device_key = "";
    if (!variable_struct_exists(state, "device_profiles") || !is_struct(state.device_profiles)) state.device_profiles = {};
    if (!variable_struct_exists(state, "audio_offset_ms")) state.audio_offset_ms = 0;
    if (!variable_struct_exists(state, "visual_offset_ms")) state.visual_offset_ms = 0;
    if (!variable_struct_exists(state, "input_offset_ms")) state.input_offset_ms = 0;  // RESERVED
    if (!variable_struct_exists(state, "jitter_summary") || !is_struct(state.jitter_summary)) {
        state.jitter_summary = {
            scheduler_late_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
            controller_step_interval_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
            midi_process_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 },
            draw_ms: { p50: 0, p95: 0, p99: 0, max: 0, n: 0 }
        };
    }

    return global.timing_calibration;
}

/// @function timing_calibration_get_status_text()
/// @description Return the human-readable status string from the calibration state.
/// @reads global.timing_calibration (via timing_calibration_ensure_state)
function timing_calibration_get_status_text() {
    var state = timing_calibration_ensure_state();
    return string(state.last_message ?? "Timing calibration has not been run.");
}

/// @function timing_calibration_is_active()
/// @description Return true if a calibration run is currently in progress.
/// @reads global.timing_calibration (via timing_calibration_ensure_state)
function timing_calibration_is_active() {
    var state = timing_calibration_ensure_state();
    return state.active;
}

/// @function timing_calibration_get_current_offsets()
/// @description Return current split offsets (audio and visual) from global.timeline_cfg.
/// @returns Struct {audio_output_offset_ms, visual_alignment_offset_ms}
/// @reads global.timeline_cfg (via gv_ensure_timeline_cfg_defaults)
function timing_calibration_get_current_offsets() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var audio_offset_ms = 0;
    var visual_offset_ms = 0;
    if (variable_struct_exists(cfg, "audio_output_offset_ms")) audio_offset_ms = real(variable_struct_get(cfg, "audio_output_offset_ms"));
    if (variable_struct_exists(cfg, "visual_alignment_offset_ms")) visual_offset_ms = real(variable_struct_get(cfg, "visual_alignment_offset_ms"));

    return {
        audio_output_offset_ms: audio_offset_ms,
        visual_alignment_offset_ms: visual_offset_ms
    };
}

/// @function timing_calibration_get_device_key()
/// @description Build a stable per-device signature key for calibration profiles.
/// @returns Device key string
/// @reads global.midi_input_device_name, global.midi_output_device_name, global.MIDI_chanter
function timing_calibration_get_device_key() {
    var midi_in = variable_global_exists("midi_input_device_name") ? string(global.midi_input_device_name) : "midi_in_unknown";
    var midi_out = variable_global_exists("midi_output_device_name") ? string(global.midi_output_device_name) : "midi_out_unknown";
    var chanter = variable_global_exists("MIDI_chanter") ? string(global.MIDI_chanter) : "default";
    return string_lower(string_trim(midi_in)) + "|" + string_lower(string_trim(midi_out)) + "|" + string_lower(string_trim(chanter));
}

/// @function timing_calibration_store_current_device_profile()
/// @description Persist current split offsets (audio/visual) to the active device profile.
/// @returns Struct profile stored for current device
/// @reads global.timeline_cfg (via timing_calibration_get_current_offsets)
/// @writes global.timing_calibration.device_profiles, global.timing_calibration.active_device_key
function timing_calibration_store_current_device_profile() {
    var state = timing_calibration_ensure_state();
    var device_key = timing_calibration_get_device_key();
    var offsets = timing_calibration_get_current_offsets();
    
    scoring_calibration_debug_log("[STORE_PROFILE] device_key='" + device_key + "' | audio_ms=" + string(offsets.audio_output_offset_ms ?? 0) + " | visual_ms=" + string(offsets.visual_alignment_offset_ms ?? 0));

    state.active_device_key = device_key;
    state.device_profiles[$ device_key] = {
        audio_output_offset_ms: real(offsets.audio_output_offset_ms ?? 0),
        visual_alignment_offset_ms: real(offsets.visual_alignment_offset_ms ?? 0)
    };

    return state.device_profiles[$ device_key];
}

/// @function timing_calibration_apply_profile_for_current_device()
/// @description Apply saved split offsets for the active device profile if one exists.
/// @returns True if profile existed and was applied
/// @writes global.timeline_cfg.* offsets (via timing_calibration_apply_offsets)
function timing_calibration_apply_profile_for_current_device() {
    var state = timing_calibration_ensure_state();
    var device_key = timing_calibration_get_device_key();
    state.active_device_key = device_key;
    
    scoring_calibration_debug_log("[APPLY_PROFILE] Attempting to match device_key: '" + device_key + "'");
    
    if (!is_struct(state.device_profiles)) {
        scoring_calibration_debug_log("[APPLY_PROFILE] device_profiles is not a struct");
        return false;
    }
    
    if (!variable_struct_exists(state.device_profiles, device_key)) {
        var available_keys = struct_get_names(state.device_profiles);
        scoring_calibration_debug_log("[APPLY_PROFILE] Key NOT found. Available: " + string(available_keys));
        return false;
    }

    var prof = state.device_profiles[$ device_key];
    if (!is_struct(prof)) {
        scoring_calibration_debug_log("[APPLY_PROFILE] Profile is not a struct");
        return false;
    }
    
    scoring_calibration_debug_log("[APPLY_PROFILE] SUCCESS! Applying audio_ms=" + string(prof.audio_output_offset_ms ?? 0) + " | visual_ms=" + string(prof.visual_alignment_offset_ms ?? 0));
    timing_calibration_apply_offsets(
        real(prof.audio_output_offset_ms ?? 0),
        real(prof.visual_alignment_offset_ms ?? 0),
        "profile-load"
    );
    return true;
}

/// @function timing_calibration_build_settings_payload()
/// @description Build calibration settings payload (audio/visual offsets) for player app settings save.
/// @returns Struct payload for embedding under app settings
function timing_calibration_build_settings_payload() {
    var state = timing_calibration_ensure_state();
    return {
        active_device_key: string(state.active_device_key ?? ""),
        device_profiles: state.device_profiles
    };
}

/// @function timing_calibration_hydrate_from_settings(_settings)
/// @description Restore calibration settings from a saved app settings payload and apply current-device profile.
/// @param _settings Settings struct loaded from app_settings.json
/// @returns True if a matching current-device profile was applied
/// @writes global.timing_calibration.*
function timing_calibration_hydrate_from_settings(_settings) {
    var state = timing_calibration_ensure_state();
    if (!is_struct(_settings)) {
        scoring_calibration_debug_log("[HYDRATE] _settings is not a struct - hydration failed");
        return false;
    }

    var tc = variable_struct_exists(_settings, "timing_calibration") && is_struct(variable_struct_get(_settings, "timing_calibration"))
        ? variable_struct_get(_settings, "timing_calibration")
        : _settings;
    
    scoring_calibration_debug_log("[HYDRATE] Found timing_calibration: device_profiles=" + string(variable_struct_exists(tc, "device_profiles")));

    if (variable_struct_exists(tc, "active_device_key")) {
        state.active_device_key = string(tc[$ "active_device_key"]);
    }
    if (variable_struct_exists(tc, "device_profiles") && is_struct(tc[$ "device_profiles"])) {
        state.device_profiles = tc[$ "device_profiles"];
        var dp_keys = struct_get_names(tc[$ "device_profiles"]);
        scoring_calibration_debug_log("[HYDRATE] Loaded device_profiles with " + string(array_length(dp_keys)) + " keys");
    }

    var result = timing_calibration_apply_profile_for_current_device();
    scoring_calibration_debug_log("[HYDRATE] apply_profile_for_current_device returned: " + string(result));
    return result;
}

/// @function timing_calibration_summarize_ring_buffer(_buf, _count)
/// @description Compute p50/p95/p99/max/n stats from a numeric ring buffer snapshot.
/// @param _buf Numeric array buffer
/// @param _count Number of valid samples in buffer
/// @returns Struct {p50, p95, p99, max, n}
function timing_calibration_summarize_ring_buffer(_buf, _count) {
    var n = min(array_length(_buf), max(0, floor(real(_count))));
    if (n <= 0) {
        return { p50: 0, p95: 0, p99: 0, max: 0, n: 0 };
    }

    var vals = array_create(n, 0);
    for (var i = 0; i < n; i++) {
        vals[i] = max(0, real(_buf[i]));
    }
    array_sort(vals, true);

    var i50 = floor((n - 1) * 0.50);
    var i95 = floor((n - 1) * 0.95);
    var i99 = floor((n - 1) * 0.99);
    return {
        p50: real(vals[i50]),
        p95: real(vals[i95]),
        p99: real(vals[i99]),
        max: real(vals[n - 1]),
        n: n
    };
}

/// @function timing_calibration_capture_jitter_summary()
/// @description Snapshot current RT jitter diagnostics into global.timing_calibration.jitter_summary.
/// @returns Struct jitter summary
/// @reads global.rt_budget_sched_late_buf/count, global.rt_budget_controller_step_dt_buf/count, global.rt_budget_midi_step_buf/count, global.rt_budget_draw_buf/count
/// @writes global.timing_calibration.jitter_summary
/// @callers tune_cleanup_after_finish
function timing_calibration_capture_jitter_summary() {
    var state = timing_calibration_ensure_state();

    var sched = (variable_global_exists("rt_budget_sched_late_buf") && is_array(global.rt_budget_sched_late_buf))
        ? timing_calibration_summarize_ring_buffer(global.rt_budget_sched_late_buf, real(global.rt_budget_sched_late_count ?? 0))
        : { p50: 0, p95: 0, p99: 0, max: 0, n: 0 };
    var ctrl_dt = (variable_global_exists("rt_budget_controller_step_dt_buf") && is_array(global.rt_budget_controller_step_dt_buf))
        ? timing_calibration_summarize_ring_buffer(global.rt_budget_controller_step_dt_buf, real(global.rt_budget_controller_step_dt_count ?? 0))
        : { p50: 0, p95: 0, p99: 0, max: 0, n: 0 };
    var midi = (variable_global_exists("rt_budget_midi_step_buf") && is_array(global.rt_budget_midi_step_buf))
        ? timing_calibration_summarize_ring_buffer(global.rt_budget_midi_step_buf, real(global.rt_budget_midi_step_count ?? 0))
        : { p50: 0, p95: 0, p99: 0, max: 0, n: 0 };
    var draw = (variable_global_exists("rt_budget_draw_buf") && is_array(global.rt_budget_draw_buf))
        ? timing_calibration_summarize_ring_buffer(global.rt_budget_draw_buf, real(global.rt_budget_draw_count ?? 0))
        : { p50: 0, p95: 0, p99: 0, max: 0, n: 0 };

    state.jitter_summary = {
        scheduler_late_ms: sched,
        controller_step_interval_ms: ctrl_dt,
        midi_process_ms: midi,
        draw_ms: draw
    };

    show_debug_message("[CALIBRATION] jitter snapshot sched_p95=" + string_format(real(sched.p95 ?? 0), 0, 3)
        + " ctrl_dt_p95=" + string_format(real(ctrl_dt.p95 ?? 0), 0, 3)
        + " midi_p95=" + string_format(real(midi.p95 ?? 0), 0, 3)
        + " draw_p95=" + string_format(real(draw.p95 ?? 0), 0, 3));

    return state.jitter_summary;
}



/// @function midi_to_letter(_midi_note)
/// @description Convert MIDI note number to bagpipe letter notation
/// @param _midi_note The MIDI note number
/// @returns String letter notation
/// @reads global.MIDI_chanter (via chanter_midi_to_display)

function midi_to_letter(_midi_note, _channel = -1) {
    return chanter_midi_to_display(_midi_note, _channel, global.MIDI_chanter ?? "default");
}

/// @function tune_rt_budget_diag_record_scheduler_late_ms(_late_ms)
/// @description Record a scheduler-late sample to the ring buffer; logs a summary every RT_BUDGET_DIAG_LOG_INTERVAL_MS.
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.RT_BUDGET_SCHED_WARMUP_MS, global.tune_start_real
/// @writes global.rt_budget_sched_late_buf, global.rt_budget_sched_late_head, global.rt_budget_sched_late_count, global.rt_budget_diag_last_log_ms
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

/// @function tune_rt_budget_diag_record_scheduler_group(_group_events, _proc_ms, _midi_send_ms, _midi_send_count)
/// @description Record per-group CPU cost samples (proc_ms, midi_send_ms, event count).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.RT_BUDGET_SCHED_WARMUP_MS, global.tune_start_real
/// @writes global.rt_budget_sched_group_proc_buf/events_buf/send_ms_buf/send_count_buf/head/count/last_log_ms
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

/// @function tune_rt_budget_diag_record_controller_step_ms(_step_ms)
/// @description Record a game controller step duration sample.
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.RT_BUDGET_SCHED_WARMUP_MS, global.tune_start_real
/// @writes global.rt_budget_controller_step_buf/head/count/last_log_ms
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

/// @function tune_rt_budget_diag_record_midi_step_ms(_step_ms)
/// @description Record a MIDI polling step duration sample (no warmup guard).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS
/// @writes global.rt_budget_midi_step_buf/head/count/last_log_ms
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

/// @function tune_rt_budget_diag_record_draw_ms(_draw_ms)
/// @description Record a frame draw duration sample (no warmup guard).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS
/// @writes global.rt_budget_draw_buf/head/count/last_log_ms
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

/// @function tune_rt_budget_diag_record_anchor_draw_ms(_anchor_kind, _draw_ms)
/// @description Accumulate per-anchor draw time into a keyed stats struct (no warmup guard).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS
/// @writes global.rt_budget_anchor_draw_stats (keyed by _anchor_kind string)
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

/// @function tune_rt_budget_diag_record_controller_step_interval_ms(_step_dt_ms)
/// @description Record the time between game-controller steps (jitter measurement).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.RT_BUDGET_SCHED_WARMUP_MS, global.tune_start_real
/// @writes global.rt_budget_controller_step_dt_buf/head/count/last_log_ms
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

/// @function tune_rt_budget_diag_record_scheduler_step_pump(_dispatched, _max_overdue_ms, _min_overdue_ms)
/// @description Record one scheduler pump cycle (dispatched count, overdue stats).
/// @reads global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.RT_BUDGET_SCHED_WARMUP_MS, global.tune_start_real
/// @writes global.rt_budget_sched_step_overdue_buf/dispatched_buf/early_buf/head/count/last_log_ms
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

        var loop_iteration = 0;
        for (var li = 0; li < ordered_count; li++) {
            var lev = ordered_events[li];
            if (!is_struct(lev)) continue;
            if (loop_iteration <= 0 && variable_struct_exists(lev, "loop_iteration")) {
                loop_iteration = floor(real(lev.loop_iteration));
            }
        }
        grp.loop_iteration = max(0, loop_iteration);
        groups[g] = grp;
    }
    
    show_debug_message("âœ“ Batched " + string(array_length(_events)) + " events into " + string(array_length(groups)) + " timestamp groups");
    return groups;
}

/// @function tune_scheduler_enqueue_deferred(_item)
/// @description Push a deferred work item onto global.tune_deferred_queue (e.g. panel_note_on).
/// @reads global.tune_deferred_queue, global.tune_deferred_head
/// @writes global.tune_deferred_queue (initialises if absent)
function tune_scheduler_enqueue_deferred(_item) {
    if (!is_struct(_item)) return;
    if (!variable_global_exists("tune_deferred_queue") || !is_array(global.tune_deferred_queue)) {
        global.tune_deferred_queue = [];
        global.tune_deferred_head = 0;
    }
    array_push(global.tune_deferred_queue, _item);
}

/// @function tune_scheduler_process_deferred(_max_items, _max_budget_us)
/// @description Drain up to _max_items deferred work items within a microsecond budget.
/// @param _max_items Max items to process per call (default 128)
/// @param _max_budget_us Microsecond budget before stopping (default 1200; 0 = unlimited)
/// @returns Number of items processed
/// @reads global.tune_deferred_queue, global.tune_deferred_head, global.MIDI_chanter, global.current_tune_name
/// @writes global.tune_deferred_queue, global.tune_deferred_head, global.current_note_display
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

                event_history_add({
                    timestamp_ms: actual_elapsed,
                    expected_time_ms: expected_elapsed,
                    actual_time_ms: actual_elapsed,
                    delta_ms: actual_elapsed - expected_elapsed,
                    canonical_time_ms: expected_elapsed,
                    audio_target_time_ms: expected_elapsed + audio_offset_ms,
                    visual_target_time_ms: expected_elapsed + visual_offset_ms,
                    input_aligned_time_ms: actual_elapsed + input_offset_ms,
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
                    beat_fraction: ev_beat_fraction,
                    audio_output_offset_ms: audio_offset_ms,
                    visual_alignment_offset_ms: visual_offset_ms,
                    input_capture_offset_ms: input_offset_ms,
                    loop_iteration: struct_exists(ev, "loop_iteration") ? real(ev.loop_iteration) : 0
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

/// @function tune_scheduler_flush_deferred_all()
/// @description Flush the entire deferred queue in chunks until empty (end-of-tune shutdown).
/// @callers tune_cleanup_after_finish, tune_start
function tune_scheduler_flush_deferred_all() {
    var guard = 0;
    while (guard < 100000) {
        var processed = tune_scheduler_process_deferred(4096, 0);
        if (processed <= 0) break;
        guard += processed;
    }
}

/// @function tune_start(tune_events)
/// @description Group playable events, configure the scheduler, and start the GML time source.
/// @param _tune_events Array of playable event structs from scr_goto_playroom preprocessing
/// @returns false if no event groups were produced; undefined on success
/// @reads global.loop_runtime_current_iteration, global.enable_current_note_layer, global.PLAYBACK_SCHEDULER_* globals
/// @writes global.tune_event_groups, global.tune_group_index, global.current_tune_name, global.tune_start_real, global.tune_timer, global.tune_scheduler_active, global.tune_scheduler_mode_step, global.tune_deferred_queue, global.tune_deferred_head, global.PLAYBACK_SCHEDULER_* (init if absent)
/// @objects obj_tune (reads tune_data.filename)
/// @callers start_play

function tune_start(_tune_events) {
    if (!variable_global_exists("loop_runtime_current_iteration")) {
        global.loop_runtime_current_iteration = 0;
    }

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

    var audio_sched_offset_ms = 0;
    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        if (variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) {
            audio_sched_offset_ms = real(variable_struct_get(global.timeline_cfg, "audio_output_offset_ms"));
        }
    }
    var first_due_ms = real(global.tune_event_groups[0].time ?? 0) + audio_sched_offset_ms;
    first_due_ms = max(0.001, first_due_ms);
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
/// @description GML time-source callback: dispatch one event group (all events at the current timestamp) via MIDI and panel callbacks.
/// @reads global.tune_event_groups, global.tune_group_index, global.tune_start_real, global.loop_runtime_active, global.loop_runtime_current_iteration, global.timeline_state, global.enable_current_note_layer, global.midi_output_device, global.METRONOME_CONFIG, global.MIDI_chanter, global.EVENT_HISTORY_AUTO_EXPORT, global.EVENT_HISTORY_EXPORTED, global.PLAYBACK_SCHEDULER_CATCHUP
/// @writes global.loop_runtime_current_iteration, global.tune_group_index, global.tune_scheduler_active, global.EVENT_HISTORY_EXPORTED, global.loop_runtime_active, global.timeline_state.last_dispatched_expected_ms, global.timeline_state.current_measure
/// @callers tune_scheduler_step_tick (step mode) or GML time_source callback (legacy mode)

function script_tune_callback_batched() {
    if (!variable_global_exists("tune_event_groups") || !is_array(global.tune_event_groups)) return;
    if (!variable_global_exists("tune_group_index")) return;
    if (global.tune_group_index < 0 || global.tune_group_index >= array_length(global.tune_event_groups)) return;

    var group = global.tune_event_groups[global.tune_group_index];
    if (variable_global_exists("loop_runtime_active") && global.loop_runtime_active) {
        global.loop_runtime_current_iteration = floor(real(group.loop_iteration ?? 0));
    }
    var real_elapsed = timing_get_engine_now_ms() - global.tune_start_real;
    var expected_elapsed = real(group.time ?? 0);
    var audio_sched_offset_ms = 0;
    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        if (variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) {
            audio_sched_offset_ms = real(variable_struct_get(global.timeline_cfg, "audio_output_offset_ms"));
        }
    }
    var scheduled_elapsed = expected_elapsed + audio_sched_offset_ms;
    tune_rt_budget_diag_record_scheduler_late_ms(real_elapsed - scheduled_elapsed);
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
        show_debug_message("Group " + string(global.tune_group_index) + " (" + string(n_group_events) + " events): real=" + string(real_elapsed) + " expected=" + string(scheduled_elapsed) + " delta=" + string(real_elapsed - scheduled_elapsed));
    }
    
    // Process ALL events in this timestamp group
    var has_last_note_on = false;
    var last_note_on_note = 0;
    var last_note_on_channel = 0;
    var latest_group_measure = -1;
    var latest_group_bar_measure = -1;
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

            if (marker_kind == "bar") {
                var marker_measure_num = floor(real(ev.measure ?? -1));
                if (marker_measure_num >= 1) {
                    latest_group_bar_measure = max(latest_group_bar_measure, marker_measure_num);
                }
            }
        }

        // Skip metronome MIDI events (channel 9 note_on/note_off) - keep structure markers
        var ev_channel = struct_exists(ev, "channel") ? ev.channel : 0;
        var is_metronome_midi = (ev.type == "note_on" || ev.type == "note_off") 
                                && ev_channel == global.METRONOME_CONFIG.channel;

        if (!is_metronome_midi && struct_exists(ev, "measure")) {
            var ev_measure_num = floor(real(ev.measure));
            if (ev_measure_num >= 1) {
                latest_group_measure = max(latest_group_measure, ev_measure_num);
            }
        }
        
        if (!is_metronome_midi) {
            tune_scheduler_enqueue_deferred({
                kind: "history_event",
                ev: ev,
                expected_time_ms: expected_elapsed,
                actual_time_ms: real_elapsed
            });
        }
    }

    if (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "active")
        && global.timeline_state.active) {
        var _prev_group_measure = variable_struct_exists(global.timeline_state, "current_measure")
            ? floor(real(global.timeline_state.current_measure))
            : -1;

        var _resolved_group_measure = _prev_group_measure;

        // Authoritative live boundary: only bar markers advance current measure.
        if (latest_group_bar_measure >= 1) {
            _resolved_group_measure = latest_group_bar_measure;
        }
        // Bootstrap before first bar marker only; afterwards keep stable until next bar.
        else if (_resolved_group_measure < 1 && latest_group_measure >= 1) {
            _resolved_group_measure = latest_group_measure;
        }

        if (_resolved_group_measure >= 1) {
            global.timeline_state.current_measure = _resolved_group_measure;
        }
    }
    
    // Update UI once per group (only for note_on events)
    if (has_last_note_on) {
        tune_scheduler_enqueue_deferred({
            kind: "current_note_display",
            note: real(last_note_on_note),
            channel: real(last_note_on_channel),
            delta_ms: real(real_elapsed - scheduled_elapsed)
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
        global.loop_runtime_current_iteration = 0;
        global.loop_runtime_active = false;
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
    var next_time = real(global.tune_event_groups[global.tune_group_index].time ?? 0) + audio_sched_offset_ms;
    var prev_time = expected_elapsed + audio_sched_offset_ms;
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

/// @function tune_scheduler_step_tick()
/// @description Per-frame pump called from obj_game_controller Step event; dispatches all overdue event groups within a budget.
/// @reads global.tune_scheduler_mode_step, global.tune_scheduler_active, global.tune_event_groups, global.tune_group_index, global.tune_start_real, global.PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS, global.PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP, global.PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US
/// @callers obj_game_controller (Step event)
function tune_scheduler_step_tick() {
    if (!variable_global_exists("tune_scheduler_mode_step") || !global.tune_scheduler_mode_step) return;
    if (!variable_global_exists("tune_scheduler_active") || !global.tune_scheduler_active) return;
    if (!variable_global_exists("tune_event_groups") || !is_array(global.tune_event_groups)) return;
    if (!variable_global_exists("tune_group_index")) return;

    var n_groups = array_length(global.tune_event_groups);
    if (global.tune_group_index < 0 || global.tune_group_index >= n_groups) return;

    var elapsed_ms = timing_get_engine_now_ms() - real(global.tune_start_real ?? 0);
    var audio_sched_offset_ms = 0;
    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        if (variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) {
            audio_sched_offset_ms = real(variable_struct_get(global.timeline_cfg, "audio_output_offset_ms"));
        }
    }
    var lookahead_ms = max(0, real(global.PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS ?? 0));
    var max_groups = max(1, floor(real(global.PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP ?? 32)));
    var max_pump_us = max(100, real(global.PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US ?? 1000));
    var pump_start_us = get_timer();

    var dispatched = 0;
    var max_overdue_ms = -1000000000;
    var min_overdue_ms = 1000000000;
    while (dispatched < max_groups && global.tune_group_index < n_groups) {
        if (get_timer() - pump_start_us >= max_pump_us) break;
        var due_time_ms = real(global.tune_event_groups[global.tune_group_index].time ?? 0) + audio_sched_offset_ms;
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

/// @function script_tune_callback()
/// @description LEGACY single-event GML time-source callback â€” superseded by script_tune_callback_batched. Preserved for reference only.
/// @reads global.tune_events, global.tune_index, global.tune_start_real, global.METRONOME_CONFIG, global.midi_output_device, global.tune_timer
/// @writes global.current_note_display, global.tune_index
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
    show_debug_message("â± Scheduled tune cleanup in " + string(_delay_ms) + "ms");
}

/// @function tune_cleanup_after_finish()
/// @description Cleanup callback: stop all MIDI notes and disable MIDI input checking
/// @reads global.rt_budget_sched_late_buf/count, global.rt_budget_controller_step_dt_buf/count, global.rt_budget_midi_step_buf/count, global.rt_budget_draw_buf/count
/// @writes global.timing_calibration.jitter_summary

function tune_cleanup_after_finish() {
    timing_calibration_capture_jitter_summary();
    MIDI_send_off();  // Stop all notes on all channels
    MIDI_stop_checking_messages_and_errors();  // Stop MIDI input checking and close devices
    show_debug_message("âœ“ Tune cleanup complete");
}

/// @function timing_calibration_apply_offsets(_audio_ms, _visual_ms, _source_label)
/// @description Apply audio and visual timing offsets (active offsets). Input offset reserved for future MIDI timestamp work.
/// @param _audio_ms Audio output scheduling offset in ms
/// @param _visual_ms Visual alignment offset in ms
/// @param _source_label Optional text label for diagnostics
/// @returns Struct { audio_output_offset_ms, visual_alignment_offset_ms }
/// @writes global.timeline_cfg.audio_output_offset_ms, global.timeline_cfg.visual_alignment_offset_ms
function timing_calibration_apply_offsets(_audio_ms, _visual_ms, _source_label = "manual") {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var audio_ms = real(_audio_ms ?? 0);
    var visual_ms = real(_visual_ms ?? 0);

    variable_struct_set(cfg, "audio_output_offset_ms", audio_ms);
    variable_struct_set(cfg, "visual_alignment_offset_ms", visual_ms);

    show_debug_message("[CALIBRATION] offsets applied source=" + string(_source_label)
        + " audio=" + string_format(audio_ms, 0, 2)
        + " visual=" + string_format(visual_ms, 0, 2));

    return {
        audio_output_offset_ms: audio_ms,
        visual_alignment_offset_ms: visual_ms
    };
}
