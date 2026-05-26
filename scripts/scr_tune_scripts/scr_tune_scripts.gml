
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
            calibration_mode_index: 0,
            calibration_advanced_open: false,
            calibration_preview: {
                active: false,
                loop_active: false,
                note: 69,
                channel: 0,
                velocity: 110,
                note_off_due_ms: 0,
                next_note_on_ms: 0,
                last_impact_ms: 0,
                impact_seq: 0,
                visual_last_impact_ms: 0,
                visual_next_impact_ms: 0,
                visual_impact_seq: 0,
                interval_ms: 900,
                pulse_ms: 35
            },
            calibration_session: {
                active: false,
                commit_on_close: false,
                snapshot_audio_ms: 0,
                snapshot_visual_ms: 0,
                snapshot_input_ms: 0
            },
            calibration_logs: [],
            calibration_result: {
                internal_midi_offset_ms: 0,
                external_audio_offset_ms: 5,
                system_audio_output_offset_ms: 7,
                system_visual_alignment_offset_ms: 0,
                audio_output_offset_ms: 7,
                visual_alignment_offset_ms: 0,
                midi_internal_offset_ms: 0,
                jitter_audio_ms: 0,
                jitter_midi_ms: 0,
                timestamp: 0
            },
            midi_loopback: {
                active: false,
                status: "idle"
            },
            external_audio_loopback: {
                active: false,
                status: "idle"
            },
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
    if (!variable_struct_exists(state, "calibration_mode_index")) state.calibration_mode_index = 0;
    if (!variable_struct_exists(state, "calibration_advanced_open")) state.calibration_advanced_open = false;
    if (!variable_struct_exists(state, "calibration_preview") || !is_struct(state.calibration_preview)) {
        state.calibration_preview = {
            active: false,
            loop_active: false,
            note: 69,
            channel: 0,
            velocity: 110,
            note_off_due_ms: 0,
            next_note_on_ms: 0,
            last_impact_ms: 0,
            impact_seq: 0,
            visual_last_impact_ms: 0,
            visual_next_impact_ms: 0,
            visual_impact_seq: 0,
            interval_ms: 900,
            pulse_ms: 35
        };
    }
    if (!variable_struct_exists(state, "calibration_session") || !is_struct(state.calibration_session)) {
        state.calibration_session = {
            active: false,
            commit_on_close: false,
            snapshot_audio_ms: 0,
            snapshot_visual_ms: 0,
            snapshot_input_ms: 0
        };
    }
    if (!variable_struct_exists(state.calibration_preview, "loop_active")) state.calibration_preview.loop_active = false;
    if (!variable_struct_exists(state.calibration_preview, "next_note_on_ms")) state.calibration_preview.next_note_on_ms = 0;
    if (!variable_struct_exists(state.calibration_preview, "last_impact_ms")) state.calibration_preview.last_impact_ms = 0;
    if (!variable_struct_exists(state.calibration_preview, "impact_seq")) state.calibration_preview.impact_seq = 0;
    if (!variable_struct_exists(state.calibration_preview, "visual_last_impact_ms")) state.calibration_preview.visual_last_impact_ms = 0;
    if (!variable_struct_exists(state.calibration_preview, "visual_next_impact_ms")) state.calibration_preview.visual_next_impact_ms = 0;
    if (!variable_struct_exists(state.calibration_preview, "visual_impact_seq")) state.calibration_preview.visual_impact_seq = 0;
    if (!variable_struct_exists(state.calibration_preview, "interval_ms")) state.calibration_preview.interval_ms = 900;
    if (!variable_struct_exists(state.calibration_preview, "pulse_ms")) state.calibration_preview.pulse_ms = 35;
    if (!variable_struct_exists(state.calibration_session, "active")) state.calibration_session.active = false;
    if (!variable_struct_exists(state.calibration_session, "commit_on_close")) state.calibration_session.commit_on_close = false;
    if (!variable_struct_exists(state.calibration_session, "snapshot_audio_ms")) state.calibration_session.snapshot_audio_ms = 0;
    if (!variable_struct_exists(state.calibration_session, "snapshot_visual_ms")) state.calibration_session.snapshot_visual_ms = 0;
    if (!variable_struct_exists(state.calibration_session, "snapshot_input_ms")) state.calibration_session.snapshot_input_ms = 0;
    if (!variable_struct_exists(state, "calibration_logs") || !is_array(state.calibration_logs)) state.calibration_logs = [];
    if (!variable_struct_exists(state, "calibration_result") || !is_struct(state.calibration_result)) {
        state.calibration_result = {
            internal_midi_offset_ms: 0,
            external_audio_offset_ms: 5,
            system_audio_output_offset_ms: 7,
            system_visual_alignment_offset_ms: 0,
            audio_output_offset_ms: 7,
            visual_alignment_offset_ms: 0,
            midi_internal_offset_ms: 0,
            jitter_audio_ms: 0,
            jitter_midi_ms: 0,
            timestamp: 0
        };
    } else {
        var result = state.calibration_result;
        if (!variable_struct_exists(result, "internal_midi_offset_ms")) result.internal_midi_offset_ms = 0;
        if (!variable_struct_exists(result, "external_audio_offset_ms")) result.external_audio_offset_ms = 5;
        if (!variable_struct_exists(result, "system_audio_output_offset_ms")) result.system_audio_output_offset_ms = 7;
        if (!variable_struct_exists(result, "system_visual_alignment_offset_ms")) result.system_visual_alignment_offset_ms = 0;
        if (!variable_struct_exists(result, "audio_output_offset_ms")) result.audio_output_offset_ms = real(result.system_audio_output_offset_ms ?? 7);
        if (!variable_struct_exists(result, "visual_alignment_offset_ms")) result.visual_alignment_offset_ms = real(result.system_visual_alignment_offset_ms ?? 0);
        if (!variable_struct_exists(result, "midi_internal_offset_ms")) result.midi_internal_offset_ms = 0;
        if (!variable_struct_exists(result, "jitter_audio_ms")) result.jitter_audio_ms = 0;
        if (!variable_struct_exists(result, "jitter_midi_ms")) result.jitter_midi_ms = 0;
        if (!variable_struct_exists(result, "timestamp")) result.timestamp = 0;
    }
    if (!variable_struct_exists(state, "midi_loopback") || !is_struct(state.midi_loopback)) {
        state.midi_loopback = { active: false, status: "idle" };
    }
    if (!variable_struct_exists(state, "external_audio_loopback") || !is_struct(state.external_audio_loopback)) {
        state.external_audio_loopback = { active: false, status: "idle" };
    }
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

/// @function timing_calibration_get_mode_labels()
/// @description Return the calibration mode labels used by the prototype UI.
/// @returns Array of mode labels
function timing_calibration_get_mode_labels() {
    return ["Bouncing Ball", "Converging Beams"];
}

/// @function timing_calibration_begin_session()
/// @description Capture a calibration snapshot when the calibration window is opened.
/// @returns Bool active session
/// @writes global.timing_calibration.calibration_session
function timing_calibration_begin_session() {
    var state = timing_calibration_ensure_state();
    var session = state.calibration_session;
    if (!bool(session.active ?? false)) {
        var cur_offsets = timing_calibration_get_current_offsets();
        session.snapshot_audio_ms = real(cur_offsets.audio_output_offset_ms ?? 0);
        session.snapshot_visual_ms = real(cur_offsets.visual_alignment_offset_ms ?? 0);
        session.snapshot_input_ms = real(cur_offsets.input_capture_offset_ms ?? 0);
        session.active = true;
    }
    session.commit_on_close = false;
    state.calibration_session = session;
    return true;
}

/// @function timing_calibration_set_session_commit_on_close(_commit)
/// @description Set whether closing the calibration window should commit or restore session offsets.
/// @param _commit Bool commit on close
/// @returns Bool commit state
/// @writes global.timing_calibration.calibration_session.commit_on_close
function timing_calibration_set_session_commit_on_close(_commit) {
    var state = timing_calibration_ensure_state();
    state.calibration_session.commit_on_close = bool(_commit);
    return bool(state.calibration_session.commit_on_close);
}

/// @function timing_calibration_get_session_commit_on_close()
/// @description Return the current commit-on-close flag for the calibration session.
/// @returns Bool commit state
function timing_calibration_get_session_commit_on_close() {
    var state = timing_calibration_ensure_state();
    return bool(state.calibration_session.commit_on_close ?? false);
}

/// @function timing_calibration_close_session(_commit)
/// @description End the calibration session, restoring snapshot offsets when canceled.
/// @param _commit Bool true to keep current values, false to restore snapshot
/// @returns Bool success
/// @writes global.timeline_cfg.audio_output_offset_ms, global.timeline_cfg.visual_alignment_offset_ms, global.timing_calibration.calibration_session
function timing_calibration_close_session(_commit) {
    var state = timing_calibration_ensure_state();
    var session = state.calibration_session;
    var commit = bool(_commit);

    // Always stop any running preview loop when leaving the calibration window.
    var preview = state.calibration_preview;
    if (is_struct(preview) && bool(preview.active ?? false)) {
        var output_count = midi_output_device_count();
        var output_idx = variable_global_exists("midi_output_device") ? floor(real(global.midi_output_device)) : 0;
        if (output_count > 0) {
            output_idx = clamp(output_idx, 0, output_count - 1);
            midi_output_message_send_short(output_idx, 128 + floor(real(preview.channel ?? 0)), floor(real(preview.note ?? 69)), 0);
        }
    }
    preview.active = false;
    preview.loop_active = false;
    preview.note_off_due_ms = 0;
    preview.next_note_on_ms = 0;
    state.calibration_preview = preview;

    if (bool(session.active ?? false) && !commit) {
        timing_calibration_apply_offsets(
            real(session.snapshot_audio_ms ?? 0),
            real(session.snapshot_visual_ms ?? 0),
            "session-cancel"
        );
        var cfg = gv_ensure_timeline_cfg_defaults();
        variable_struct_set(cfg, "input_capture_offset_ms", real(session.snapshot_input_ms ?? 0));
        state.last_message = "Calibration canceled. Previous offsets restored.";
    }

    session.active = false;
    session.commit_on_close = false;
    state.calibration_session = session;
    return true;
}

/// @function timing_calibration_get_mode_label(_mode_index)
/// @description Return a safe calibration mode label for the given index.
/// @param _mode_index Requested mode index
/// @returns Mode label string
function timing_calibration_get_mode_label(_mode_index = 0) {
    var labels = timing_calibration_get_mode_labels();
    if (array_length(labels) <= 0) return "Calibration";
    var idx = floor(real(_mode_index));
    idx = (idx mod array_length(labels) + array_length(labels)) mod array_length(labels);
    return string(labels[idx]);
}

/// @function timing_calibration_get_current_mode_index()
/// @description Return the current prototype calibration mode index.
/// @returns Integer mode index
function timing_calibration_get_current_mode_index() {
    var state = timing_calibration_ensure_state();
    return max(0, floor(real(state.calibration_mode_index ?? 0)));
}

/// @function timing_calibration_set_mode_index(_delta)
/// @description Cycle the calibration mode index by a signed step.
/// @param _delta Signed integer step
/// @returns Integer new mode index
/// @writes global.timing_calibration.calibration_mode_index, global.timing_calibration.last_message
function timing_calibration_set_mode_index(_delta) {
    var state = timing_calibration_ensure_state();
    var labels = timing_calibration_get_mode_labels();
    var count = array_length(labels);
    if (count <= 0) return 0;

    var delta = floor(real(_delta ?? 0));
    var cur = floor(real(state.calibration_mode_index ?? 0));
    var next = (cur + delta) mod count;
    if (next < 0) next += count;
    state.calibration_mode_index = next;
    state.last_message = "Calibration mode: " + timing_calibration_get_mode_label(next);
    return next;
}

/// @function timing_calibration_toggle_advanced_panel()
/// @description Toggle the prototype calibration advanced panel open/closed state.
/// @returns Bool new state
/// @writes global.timing_calibration.calibration_advanced_open, global.timing_calibration.last_message
function timing_calibration_toggle_advanced_panel() {
    var state = timing_calibration_ensure_state();
    state.calibration_advanced_open = !bool(state.calibration_advanced_open ?? false);
    state.last_message = state.calibration_advanced_open
        ? "Advanced calibration details shown."
        : "Advanced calibration details hidden.";
    return bool(state.calibration_advanced_open);
}

/// @function timing_calibration_reset_to_system_defaults()
/// @description Restore the current audio/visual offsets to the measured system defaults.
/// @returns Struct applied offsets
/// @writes global.timeline_cfg.audio_output_offset_ms, global.timeline_cfg.visual_alignment_offset_ms
function timing_calibration_reset_to_system_defaults() {
    var state = timing_calibration_ensure_state();
    var audio_ms = real(state.calibration_result.system_audio_output_offset_ms ?? 7);
    var visual_ms = real(state.calibration_result.system_visual_alignment_offset_ms ?? 0);
    timing_calibration_apply_offsets(audio_ms, visual_ms, "system-defaults");
    state.last_message = "System defaults restored (audio " + string_format(audio_ms, 0, 2) + " ms, visual " + string_format(visual_ms, 0, 2) + " ms).";
    timing_calibration_store_current_device_profile();
    if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
        scoring_player_settings_save_for_player();
    }
    return timing_calibration_get_current_offsets();
}

/// @function timing_calibration_save_current_profile()
/// @description Persist the current offsets to the active device profile and player settings.
/// @returns Bool success
/// @writes global.timing_calibration.device_profiles
function timing_calibration_save_current_profile() {
    var state = timing_calibration_ensure_state();
    timing_calibration_store_current_device_profile();
    if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
        scoring_player_settings_save_for_player();
    }
    state.last_message = "Calibration profile saved for current device.";
    return true;
}

/// @function timing_calibration_start_preview_click()
/// @description Toggle a continuous preview click loop for the current calibration mode.
/// @returns Bool true when loop is running, false when stopped or unavailable
/// @writes global.timing_calibration.calibration_preview
function timing_calibration_start_preview_click() {
    var state = timing_calibration_ensure_state();
    var preview = state.calibration_preview;
    if (!is_struct(preview)) {
        preview = { active: false, loop_active: false, note: 69, channel: 0, velocity: 110, note_off_due_ms: 0, next_note_on_ms: 0, last_impact_ms: 0, impact_seq: 0, visual_last_impact_ms: 0, visual_next_impact_ms: 0, visual_impact_seq: 0, interval_ms: 900, pulse_ms: 35 };
    }

    var output_count = midi_output_device_count();
    if (output_count <= 0) {
        state.last_message = "Preview unavailable: no MIDI output devices found.";
        preview.active = false;
        preview.loop_active = false;
        preview.note_off_due_ms = 0;
        preview.next_note_on_ms = 0;
        preview.last_impact_ms = 0;
        preview.impact_seq = 0;
        preview.visual_last_impact_ms = 0;
        preview.visual_next_impact_ms = 0;
        preview.visual_impact_seq = 0;
        state.calibration_preview = preview;
        return false;
    }

    var output_idx = variable_global_exists("midi_output_device") ? floor(real(global.midi_output_device)) : 0;
    output_idx = clamp(output_idx, 0, output_count - 1);
    global.midi_output_device = output_idx;
    global.midi_output_device_name = midi_output_device_name(output_idx);
    midi_output_device_open(output_idx);
    // Try to clear lingering notes on common preview channels before (re)starting.
    midi_output_message_send_short(output_idx, 176 + 0, 123, 0);
    midi_output_message_send_short(output_idx, 176 + 9, 123, 0);

    if (bool(preview.loop_active ?? false)) {
        // Stop loop and ensure no note remains active.
        if (bool(preview.active ?? false)) {
            midi_output_message_send_short(output_idx, 128 + floor(real(preview.channel ?? 0)), floor(real(preview.note ?? 69)), 0);
        }
        preview.active = false;
        preview.loop_active = false;
        preview.note_off_due_ms = 0;
        preview.next_note_on_ms = 0;
        preview.last_impact_ms = 0;
        preview.impact_seq = 0;
        preview.visual_last_impact_ms = 0;
        preview.visual_next_impact_ms = 0;
        preview.visual_impact_seq = 0;
        state.calibration_preview = preview;
        state.last_message = "Calibration test stopped.";
        scoring_calibration_debug_log("[PREVIEW] stopped out='" + string(global.midi_output_device_name) + "'");
        return false;
    }

    var mode_idx = timing_calibration_get_current_mode_index();
    var canonical_note = (mode_idx == 0) ? "e" : "a";
    var mapped_note = chanter_canonical_to_midi(canonical_note, global.MIDI_chanter ?? "default");
    var note = is_undefined(mapped_note) ? ((mode_idx == 0) ? 64 : 69) : floor(real(mapped_note));
    preview.active = false;
    preview.loop_active = true;
    preview.note = floor(real(note));
    preview.channel = 0;
    preview.velocity = 110;
    preview.interval_ms = max(350, real(preview.interval_ms ?? 900));
    preview.pulse_ms = clamp(real(preview.pulse_ms ?? 35), 15, preview.interval_ms - 60);
    var offsets = timing_calibration_get_current_offsets();
    var audio_sched_offset_ms = real(offsets.audio_output_offset_ms ?? 0);
    var now_engine_ms = timing_get_engine_now_ms();
    var now_audio_ms = now_engine_ms + audio_sched_offset_ms;
    preview.note_off_due_ms = 0;
    preview.next_note_on_ms = now_audio_ms;
    preview.last_impact_ms = now_audio_ms;
    preview.impact_seq = 0;
    preview.visual_last_impact_ms = now_engine_ms;
    preview.visual_next_impact_ms = now_engine_ms;
    preview.visual_impact_seq = 0;

    scoring_calibration_debug_log("[PREVIEW] start mode='" + timing_calibration_get_mode_label(mode_idx) + "' note=" + string(preview.note)
        + " out='" + string(global.midi_output_device_name) + "' audio_offset_ms=" + string_format(audio_sched_offset_ms, 0, 2));
    state.calibration_preview = preview;
    state.last_message = "Calibration test running in " + timing_calibration_get_mode_label(mode_idx) + " mode on " + string(global.midi_output_device_name) + ".";
    return true;
}

/// @function timing_calibration_step_preview_click()
/// @description Tick the continuous preview loop and send note-on/off events at the loop cadence.
/// @returns Bool true while preview loop or note gate is active
function timing_calibration_step_preview_click() {
    var state = timing_calibration_ensure_state();
    var preview = state.calibration_preview;
    if (!is_struct(preview)) return false;
    if (!bool(preview.loop_active ?? false) && !bool(preview.active ?? false)) return false;

    var output_count = midi_output_device_count();
    if (output_count <= 0) {
        preview.active = false;
        preview.loop_active = false;
        preview.note_off_due_ms = 0;
        preview.next_note_on_ms = 0;
        preview.last_impact_ms = 0;
        preview.impact_seq = 0;
        preview.visual_last_impact_ms = 0;
        preview.visual_next_impact_ms = 0;
        preview.visual_impact_seq = 0;
        state.calibration_preview = preview;
        return false;
    }

    var output_idx = variable_global_exists("midi_output_device") ? floor(real(global.midi_output_device)) : 0;
    output_idx = clamp(output_idx, 0, output_count - 1);

    var offsets = timing_calibration_get_current_offsets();
    var audio_sched_offset_ms = real(offsets.audio_output_offset_ms ?? 0);
    var now_engine_ms = timing_get_engine_now_ms();
    var now_audio_ms = now_engine_ms + audio_sched_offset_ms;

    if (bool(preview.loop_active ?? false) && now_engine_ms >= real(preview.visual_next_impact_ms ?? 0)) {
        preview.visual_last_impact_ms = now_engine_ms;
        preview.visual_impact_seq = floor(real(preview.visual_impact_seq ?? 0)) + 1;
        preview.visual_next_impact_ms = now_engine_ms + real(preview.interval_ms ?? 900);
    }

    if (bool(preview.active ?? false) && now_audio_ms >= real(preview.note_off_due_ms ?? 0)) {
        midi_output_message_send_short(output_idx, 128 + floor(real(preview.channel ?? 0)), floor(real(preview.note ?? 69)), 0);
        midi_output_message_send_short(output_idx, 176 + floor(real(preview.channel ?? 0)), 120, 0);
        midi_output_message_send_short(output_idx, 176 + floor(real(preview.channel ?? 0)), 123, 0);
        preview.active = false;
        preview.note_off_due_ms = 0;
    }

    if (bool(preview.loop_active ?? false) && now_audio_ms >= real(preview.next_note_on_ms ?? 0) && !bool(preview.active ?? false)) {
        var mode_idx = timing_calibration_get_current_mode_index();
        var canonical_note = (mode_idx == 0) ? "e" : "a";
        var mapped_note = chanter_canonical_to_midi(canonical_note, global.MIDI_chanter ?? "default");
        preview.note = is_undefined(mapped_note) ? ((mode_idx == 0) ? 64 : 69) : floor(real(mapped_note));
        // Pre-clear voice so each impact pulse starts from silence.
        midi_output_message_send_short(output_idx, 128 + floor(real(preview.channel ?? 0)), floor(real(preview.note ?? 69)), 0);
        midi_output_message_send_short(output_idx, 176 + floor(real(preview.channel ?? 0)), 120, 0);
        midi_output_message_send_short(output_idx, 144 + floor(real(preview.channel ?? 0)), floor(real(preview.note ?? 69)), floor(real(preview.velocity ?? 110)));
        preview.active = true;
        preview.last_impact_ms = now_audio_ms;
        preview.impact_seq = floor(real(preview.impact_seq ?? 0)) + 1;
        preview.note_off_due_ms = now_audio_ms + real(preview.pulse_ms ?? 35);
        preview.next_note_on_ms = now_audio_ms + real(preview.interval_ms ?? 900);
    }

    state.calibration_preview = preview;
    return bool(preview.loop_active ?? false) || bool(preview.active ?? false);
}

/// @function timing_calibration_draw_preview_canvas(_x1, _y1, _x2, _y2)
/// @description Draw calibration preview visuals locked to the same impact schedule used by preview audio pulses.
/// @param {real} _x1 Left canvas coordinate
/// @param {real} _y1 Top canvas coordinate
/// @param {real} _x2 Right canvas coordinate
/// @param {real} _y2 Bottom canvas coordinate
/// @returns {bool} True when calibration preview visuals were drawn
/// @reads global.timing_calibration.calibration_preview, global.timeline_cfg.audio_output_offset_ms
/// @callers obj_field_base Draw
function timing_calibration_draw_preview_canvas(_x1, _y1, _x2, _y2) {
    var x1 = real(_x1);
    var y1 = real(_y1);
    var x2 = real(_x2);
    var y2 = real(_y2);

    var state = timing_calibration_ensure_state();
    var preview = state.calibration_preview;
    var mode_idx = timing_calibration_get_current_mode_index();
    var running = is_struct(preview) && bool(preview.loop_active ?? false);

    draw_set_alpha(1);
    draw_set_color(make_color_rgb(30, 34, 42));
    draw_rectangle(x1, y1, x2, y2, false);

    var pad = 14;
    var ix1 = x1 + pad;
    var iy1 = y1 + pad;
    var ix2 = x2 - pad;
    var iy2 = y2 - pad;
    if (ix2 <= ix1 + 4 || iy2 <= iy1 + 4) return true;

    draw_set_color(make_color_rgb(58, 66, 80));
    draw_rectangle(ix1, iy1, ix2, iy2, true);

    var now_engine_ms = timing_get_engine_now_ms();
    var interval_ms = running ? max(1, real(preview.interval_ms ?? 900)) : 900;
    var last_impact_ms = running ? real(preview.visual_last_impact_ms ?? now_engine_ms) : now_engine_ms;
    var phase = clamp((now_engine_ms - last_impact_ms) / interval_ms, 0, 1);
    var impact_age_ms = now_engine_ms - last_impact_ms;

    if (mode_idx == 0) {
        var track_y = (iy1 + iy2) * 0.5;
        var rail_left = ix1 + 8;
        var rail_right = ix2 - 8;

        draw_set_alpha(0.9);
        draw_set_color(make_color_rgb(198, 206, 220));
        draw_line_width(rail_left, track_y, rail_right, track_y, 3);

        draw_set_alpha(0.5);
        draw_set_color(make_color_rgb(244, 111, 91));
        draw_line_width(rail_left, track_y - 10, rail_left, track_y + 10, 2);
        draw_line_width(rail_right, track_y - 10, rail_right, track_y + 10, 2);

        var seq = running ? floor(real(preview.visual_impact_seq ?? 0)) : 0;
        var left_to_right = ((seq mod 2) == 1);
        var ball_x = left_to_right
            ? lerp(rail_left, rail_right, phase)
            : lerp(rail_right, rail_left, phase);
        var ball_r = 10;

        if (impact_age_ms <= 85) {
            var flash = 1 - (impact_age_ms / 85);
            draw_set_alpha(0.35 * flash);
            draw_set_color(make_color_rgb(255, 235, 140));
            var wall_x = left_to_right ? rail_left : rail_right;
            draw_circle(wall_x, track_y, 18 + flash * 14, false);
        }

        draw_set_alpha(1);
        draw_set_color(make_color_rgb(243, 197, 91));
        draw_circle(ball_x, track_y, ball_r, false);
    } else {
        var mid_x = (ix1 + ix2) * 0.5;
        var beam_y1 = iy1 + 12;
        var beam_y2 = iy2 - 12;
        var left_x = lerp(ix1 + 6, mid_x, phase);
        var right_x = lerp(ix2 - 6, mid_x, phase);
        draw_set_alpha(0.8);
        draw_set_color(make_color_rgb(117, 190, 218));
        draw_line_width(left_x, beam_y1, left_x, beam_y2, 4);
        draw_line_width(right_x, beam_y1, right_x, beam_y2, 4);
        // Keep center line width fixed; amplify impact readability via color + vertical pulse only.
        var center_pulse = 0;
        if (impact_age_ms <= 140) {
            center_pulse = 1 - (impact_age_ms / 140);
        }
        var center_y_pad = 2 + (12 * center_pulse);
        var center_y1 = max(iy1 + 2, beam_y1 - center_y_pad);
        var center_y2 = min(iy2 - 2, beam_y2 + center_y_pad);

        var base_r = 255;
        var base_g = 235;
        var base_b = 140;
        var hit_r = 255;
        var hit_g = 110;
        var hit_b = 90;
        var center_r = floor(lerp(base_r, hit_r, center_pulse));
        var center_g = floor(lerp(base_g, hit_g, center_pulse));
        var center_b = floor(lerp(base_b, hit_b, center_pulse));

        draw_set_alpha(0.4 + (0.45 * center_pulse));
        draw_set_color(make_color_rgb(center_r, center_g, center_b));
        draw_line_width(mid_x, center_y1, mid_x, center_y2, 2);
    }

    draw_set_alpha(1);
    draw_set_color(c_white);

    return true;
}

/// @function timing_calibration_get_current_offsets()
/// @description Return current split offsets (audio and visual) from global.timeline_cfg.
/// @returns Struct {audio_output_offset_ms, visual_alignment_offset_ms, input_capture_offset_ms}
/// @reads global.timeline_cfg (via gv_ensure_timeline_cfg_defaults)
function timing_calibration_get_current_offsets() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var audio_offset_ms = 0;
    var visual_offset_ms = 0;
    var input_offset_ms = 0;
    if (variable_struct_exists(cfg, "audio_output_offset_ms")) audio_offset_ms = real(variable_struct_get(cfg, "audio_output_offset_ms"));
    if (variable_struct_exists(cfg, "visual_alignment_offset_ms")) visual_offset_ms = real(variable_struct_get(cfg, "visual_alignment_offset_ms"));
    if (variable_struct_exists(cfg, "input_capture_offset_ms")) input_offset_ms = real(variable_struct_get(cfg, "input_capture_offset_ms"));

    return {
        audio_output_offset_ms: audio_offset_ms,
        visual_alignment_offset_ms: visual_offset_ms,
        input_capture_offset_ms: input_offset_ms
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
/// @description Persist current split offsets (audio/visual/input) to the active device profile.
/// @returns Struct profile stored for current device
/// @reads global.timeline_cfg (via timing_calibration_get_current_offsets)
/// @writes global.timing_calibration.device_profiles, global.timing_calibration.active_device_key
function timing_calibration_store_current_device_profile() {
    var state = timing_calibration_ensure_state();
    var device_key = timing_calibration_get_device_key();
    var offsets = timing_calibration_get_current_offsets();
    
    scoring_calibration_debug_log("[STORE_PROFILE] device_key='" + device_key + "' | audio_ms=" + string(offsets.audio_output_offset_ms ?? 0) + " | visual_ms=" + string(offsets.visual_alignment_offset_ms ?? 0) + " | input_ms=" + string(offsets.input_capture_offset_ms ?? 0));

    state.active_device_key = device_key;
    state.device_profiles[$ device_key] = {
        audio_output_offset_ms: real(offsets.audio_output_offset_ms ?? 0),
        visual_alignment_offset_ms: real(offsets.visual_alignment_offset_ms ?? 0),
        input_capture_offset_ms: real(offsets.input_capture_offset_ms ?? 0)
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
    
    scoring_calibration_debug_log("[APPLY_PROFILE] SUCCESS! Applying audio_ms=" + string(prof.audio_output_offset_ms ?? 0) + " | visual_ms=" + string(prof.visual_alignment_offset_ms ?? 0) + " | input_ms=" + string(prof.input_capture_offset_ms ?? 0));
    timing_calibration_apply_offsets(
        real(prof.audio_output_offset_ms ?? 0),
        real(prof.visual_alignment_offset_ms ?? 0),
        "profile-load",
        real(prof.input_capture_offset_ms ?? 0)
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
        device_profiles: state.device_profiles,
        calibration_result: state.calibration_result
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
        var _profile_keys = struct_get_names(state.device_profiles);
        for (var _pi = 0; _pi < array_length(_profile_keys); _pi++) {
            var _pk = string(_profile_keys[_pi]);
            if (!variable_struct_exists(state.device_profiles, _pk)) continue;
            var _prof = state.device_profiles[$ _pk];
            if (!is_struct(_prof)) continue;
            if (!variable_struct_exists(_prof, "audio_output_offset_ms")) _prof.audio_output_offset_ms = 0;
            if (!variable_struct_exists(_prof, "visual_alignment_offset_ms")) _prof.visual_alignment_offset_ms = 0;
            if (!variable_struct_exists(_prof, "input_capture_offset_ms")) _prof.input_capture_offset_ms = 0;
            state.device_profiles[$ _pk] = _prof;
        }
        var dp_keys = struct_get_names(tc[$ "device_profiles"]);
        scoring_calibration_debug_log("[HYDRATE] Loaded device_profiles with " + string(array_length(dp_keys)) + " keys");
    }
    if (variable_struct_exists(tc, "calibration_result") && is_struct(tc[$ "calibration_result"])) {
        state.calibration_result = tc[$ "calibration_result"];
    }

    var result = timing_calibration_apply_profile_for_current_device();
    scoring_calibration_debug_log("[HYDRATE] apply_profile_for_current_device returned: " + string(result));
    return result;
}

/// @function timing_calibration_log_add(_event_type, _value)
/// @description Append a calibration log entry using shared format: {timestamp_ms, event_type, value}.
/// @param _event_type One of send/receive/info/error
/// @param _value Event-specific payload (struct or primitive)
/// @returns Struct log entry
/// @writes global.timing_calibration.calibration_logs
function timing_calibration_log_add(_event_type, _value) {
    var state = timing_calibration_ensure_state();
    var ev = {
        timestamp_ms: timing_get_engine_now_ms(),
        event_type: string_lower(string(_event_type)),
        value: _value
    };
    array_push(state.calibration_logs, ev);
    return ev;
}

/// @function timing_calibration_logs_reset()
/// @description Clear in-memory calibration logs.
/// @writes global.timing_calibration.calibration_logs
function timing_calibration_logs_reset() {
    var state = timing_calibration_ensure_state();
    state.calibration_logs = [];
}

/// @function timing_calibration_export_logs(_path)
/// @description Export calibration logs to CSV with columns: timestamp_ms,event_type,value.
/// @param _path Optional output path
/// @returns Export path on success, "" on failure
function timing_calibration_export_logs(_path = "") {
    var state = timing_calibration_ensure_state();
    var path = string(_path);
    if (path == "") {
        var stamp = string(floor(timing_get_engine_now_ms()));
        path = "calibration_logs_" + stamp + ".csv";
    }

    var fh = file_text_open_write(path);
    if (fh < 0) {
        timing_calibration_log_add("error", "Failed to open export path: " + path);
        return "";
    }

    file_text_write_string(fh, "timestamp_ms,event_type,value\n");
    var logs = state.calibration_logs;
    for (var i = 0; i < array_length(logs); i++) {
        var row = logs[i];
        if (!is_struct(row)) continue;
        var ts = string(real(row.timestamp_ms ?? 0));
        var et = string(row.event_type ?? "info");
        var vv = row.value;
        var value_text = is_struct(vv) || is_array(vv) ? json_stringify(vv) : string(vv);
        value_text = string_replace_all(value_text, "\"", "'");
        value_text = string_replace_all(value_text, ",", ";");
        file_text_write_string(fh, ts + "," + et + "," + value_text + "\n");
    }

    file_text_close(fh);
    timing_calibration_log_add("info", "Exported calibration logs: " + path);
    return path;
}

/// @function timing_calibration_import_result_json(_path)
/// @description Import calibration result JSON from disk and apply to current calibration state.
/// @param _path File path
/// @returns True when imported
/// @writes global.timing_calibration.calibration_result
function timing_calibration_import_result_json(_path) {
    var path = string(_path);
    if (path == "" || !file_exists(path)) {
        timing_calibration_log_add("error", "Import result path not found: " + path);
        return false;
    }

    var fh = file_text_open_read(path);
    if (fh < 0) {
        timing_calibration_log_add("error", "Failed to open import path: " + path);
        return false;
    }

    var raw = "";
    while (!file_text_eof(fh)) {
        raw += file_text_read_string(fh);
        file_text_readln(fh);
    }
    file_text_close(fh);

    var parsed = undefined;
    try {
        parsed = json_parse(raw);
    } catch (ex) {
        timing_calibration_log_add("error", "Invalid calibration result JSON");
        return false;
    }
    if (!is_struct(parsed)) {
        timing_calibration_log_add("error", "Imported calibration result is not an object");
        return false;
    }

    var state = timing_calibration_ensure_state();
    state.calibration_result = {
        audio_output_offset_ms: variable_struct_exists(parsed, "audio_output_offset_ms") ? real(variable_struct_get(parsed, "audio_output_offset_ms")) : 0,
        midi_internal_offset_ms: variable_struct_exists(parsed, "midi_internal_offset_ms") ? real(variable_struct_get(parsed, "midi_internal_offset_ms")) : 0,
        jitter_audio_ms: variable_struct_exists(parsed, "jitter_audio_ms") ? real(variable_struct_get(parsed, "jitter_audio_ms")) : 0,
        jitter_midi_ms: variable_struct_exists(parsed, "jitter_midi_ms") ? real(variable_struct_get(parsed, "jitter_midi_ms")) : 0,
        timestamp: variable_struct_exists(parsed, "timestamp") ? real(variable_struct_get(parsed, "timestamp")) : timing_get_engine_now_ms()
    };
    timing_calibration_log_add("info", "Imported calibration result from " + path);
    return true;
}

/// @function timing_calibration_find_loopmidi_devices()
/// @description Find loopMIDI input/output ports by name; if not found, falls back to active globals and reports whether loopMIDI was found.
/// @returns Struct {input_index, output_index, input_name, output_name}
function timing_calibration_find_loopmidi_devices() {
    var in_idx = variable_global_exists("midi_input_device") ? floor(real(global.midi_input_device)) : 0;
    var out_idx = variable_global_exists("midi_output_device") ? floor(real(global.midi_output_device)) : 0;
    var in_count = midi_input_device_count();
    var out_count = midi_output_device_count();
    var in_valid = (in_count > 0 && in_idx >= 0 && in_idx < in_count);
    var out_valid = (out_count > 0 && out_idx >= 0 && out_idx < out_count);
    var in_name = in_valid ? midi_input_device_name(in_idx) : "";
    var out_name = out_valid ? midi_output_device_name(out_idx) : "";

    // For internal loopback calibration, always prefer explicit loopMIDI ports when present.
    var found_loop_input = false;
    var found_loop_output = false;
    for (var i = 0; i < in_count; i++) {
        var nm_in = string_lower(string(midi_input_device_name(i)));
        if (string_pos("loopmidi", nm_in) > 0 || string_pos("loop midi", nm_in) > 0) {
            in_idx = i;
            in_name = midi_input_device_name(i);
            in_valid = true;
            found_loop_input = true;
            break;
        }
    }

    for (var j = 0; j < out_count; j++) {
        var nm_out = string_lower(string(midi_output_device_name(j)));
        if (string_pos("loopmidi", nm_out) > 0 || string_pos("loop midi", nm_out) > 0) {
            out_idx = j;
            out_name = midi_output_device_name(j);
            out_valid = true;
            found_loop_output = true;
            break;
        }
    }

    // Final clamp fallback if no valid selection found.
    if (!in_valid && in_count > 0) {
        in_idx = 0;
        in_name = midi_input_device_name(0);
    }
    if (!out_valid && out_count > 0) {
        out_idx = 0;
        out_name = midi_output_device_name(0);
    }

    return {
        input_index: in_idx,
        output_index: out_idx,
        input_name: in_name,
        output_name: out_name,
        found_loop_input: found_loop_input,
        found_loop_output: found_loop_output
    };
}

/// @function timing_calibration_should_suppress_midi_thru()
/// @description Return true while MIDI loopback calibration is active to prevent MIDI thru feedback loops.
/// @returns Bool
function timing_calibration_should_suppress_midi_thru() {
    var state = timing_calibration_ensure_state();
    return is_struct(state.midi_loopback) && bool(state.midi_loopback.active ?? false);
}

/// @function timing_calibration_start_midi_loopback(_trials)
/// @description Start internal MIDI loopback calibration test (loopMIDI roundtrip) and capture per-trial latency.
/// @param _trials Number of loopback trials
/// @returns Bool started
/// @writes global.timing_calibration.midi_loopback, global.timing_calibration.calibration_logs
function timing_calibration_start_midi_loopback(_trials = 20) {
    var state = timing_calibration_ensure_state();
    var trials = max(1, floor(real(_trials)));
    var ports = timing_calibration_find_loopmidi_devices();

    if (!bool(ports.found_loop_input ?? false) || !bool(ports.found_loop_output ?? false)) {
        show_debug_message("[CAL_LOOPBACK] warning: loopMIDI port(s) not found; using currently selected devices."
            + " | found_in=" + string(bool(ports.found_loop_input ?? false))
            + " | found_out=" + string(bool(ports.found_loop_output ?? false))
            + " | selected_in='" + string(ports.input_name) + "'"
            + " | selected_out='" + string(ports.output_name) + "'");
        timing_calibration_log_add("warning", {
            mode: "midi_loopback",
            reason: "missing_loopmidi_ports",
            found_loop_input: bool(ports.found_loop_input ?? false),
            found_loop_output: bool(ports.found_loop_output ?? false),
            selected_input_name: string(ports.input_name),
            selected_output_name: string(ports.output_name)
        });
    }

    timing_calibration_logs_reset();
    timing_calibration_log_add("info", {
        mode: "midi_loopback",
        trials: trials,
        input_name: ports.input_name,
        output_name: ports.output_name
    });

    state.midi_loopback = {
        active: true,
        status: "running",
        total_trials: trials,
        completed_trials: 0,
        awaiting_receive: false,
        note: 65,
        velocity: 110,
        channel: 0,
        cycle_interval_ms: 1000,
        pulse_duration_ms: 500,
        next_send_ms: timing_get_engine_now_ms(),
        note_off_due_ms: 0,
        pulse_note_off_sent: true,
        last_send_ms: 0,
        timeout_ms: 1000,
        send_times: [],
        latency_pairs_ms: [],
        rx_note_on_total: 0,
        rx_note_on_match_total: 0,
        rx_note_on_mismatch_total: 0,
        manual_poll_enabled_by_loopback: true,
        prev_input_device: variable_global_exists("midi_input_device") ? floor(real(global.midi_input_device)) : 0,
        prev_output_device: variable_global_exists("midi_output_device") ? floor(real(global.midi_output_device)) : 0,
        prev_input_name: variable_global_exists("midi_input_device_name") ? string(global.midi_input_device_name) : "",
        prev_output_name: variable_global_exists("midi_output_device_name") ? string(global.midi_output_device_name) : "",
        loop_input_device: floor(real(ports.input_index)),
        loop_output_device: floor(real(ports.output_index))
    };

    global.midi_input_device = state.midi_loopback.loop_input_device;
    global.midi_output_device = state.midi_loopback.loop_output_device;
    midi_input_device_open(global.midi_input_device);
    midi_output_device_open(global.midi_output_device);
    midi_input_message_manual_checking(1);
    midi_error_manual_checking(1);
    if (midi_input_device_count() > 0 && global.midi_input_device >= 0 && global.midi_input_device < midi_input_device_count()) {
        global.midi_input_device_name = midi_input_device_name(global.midi_input_device);
    }
    if (midi_output_device_count() > 0 && global.midi_output_device >= 0 && global.midi_output_device < midi_output_device_count()) {
        global.midi_output_device_name = midi_output_device_name(global.midi_output_device);
    }

    state.last_message = "MIDI loopback calibration started (" + string(trials) + " trials).";
    show_debug_message("[CAL_LOOPBACK] start in=" + string(state.midi_loopback.loop_input_device)
        + " '" + string(global.midi_input_device_name) + "'"
        + " | out=" + string(state.midi_loopback.loop_output_device)
        + " '" + string(global.midi_output_device_name) + "'"
        + " | pulse_ms=" + string(state.midi_loopback.pulse_duration_ms)
        + " | cycle_ms=" + string(state.midi_loopback.cycle_interval_ms)
        + " | trials=" + string(trials));
    if (string_lower(string(global.midi_input_device_name)) == string_lower(string(global.midi_output_device_name))) {
        show_debug_message("[CAL_LOOPBACK] warning: input/output resolved to the same device; two-port roundtrip may not work.");
    }
    return true;
}

/// @function timing_calibration_finish_midi_loopback(_ok)
/// @description Finalize MIDI loopback test, compute latency/jitter, restore previous MIDI devices, and persist result.
/// @param _ok Whether run completed successfully
/// @returns Struct calibration result
function timing_calibration_finish_midi_loopback(_ok) {
    var state = timing_calibration_ensure_state();
    var ml = state.midi_loopback;
    var vals = is_struct(ml) && is_array(ml.latency_pairs_ms) ? ml.latency_pairs_ms : [];

    var n = array_length(vals);
    var run_ok = bool(_ok) && (n > 0);
    var latency_mean = 0;
    if (n > 0) {
        for (var i = 0; i < n; i++) latency_mean += real(vals[i]);
        latency_mean /= n;
    }

    var variance = 0;
    if (n > 0) {
        for (var j = 0; j < n; j++) {
            var d = real(vals[j]) - latency_mean;
            variance += d * d;
        }
        variance /= n;
    }
    var jitter = sqrt(max(0, variance));

    if (run_ok) {
        state.calibration_result.midi_internal_offset_ms = latency_mean;
        state.calibration_result.jitter_midi_ms = jitter;
        state.calibration_result.timestamp = timing_get_engine_now_ms();
    }

    if (is_struct(ml)) {
        if (bool(ml.note_on_pending ?? false)) {
            var status_off = 128 + floor(real(ml.channel ?? 0));
            var note = floor(real(ml.note ?? 65));
            midi_output_message_send_short(global.midi_output_device, status_off, note, 0);
            ml.note_on_pending = false;
            ml.pulse_note_off_sent = true;
        }
        global.midi_input_device = floor(real(ml.prev_input_device ?? global.midi_input_device));
        global.midi_output_device = floor(real(ml.prev_output_device ?? global.midi_output_device));
        global.midi_input_device_name = string(ml.prev_input_name ?? global.midi_input_device_name);
        global.midi_output_device_name = string(ml.prev_output_name ?? global.midi_output_device_name);
        if (bool(ml.manual_poll_enabled_by_loopback ?? false)) {
            midi_input_message_manual_checking(0);
            midi_error_manual_checking(0);
        }
    }

    state.midi_loopback = { active: false, status: run_ok ? "done" : "error" };
    state.last_message = run_ok
        ? "MIDI loopback complete: latency=" + string_format(latency_mean, 0, 2) + " ms, jitter=" + string_format(jitter, 0, 2) + " ms"
        : "MIDI loopback failed: no valid receive samples.";
    var _send_count = is_struct(ml) && is_array(ml.send_times) ? array_length(ml.send_times) : 0;
    var _rx_total = is_struct(ml) ? floor(real(ml.rx_note_on_total ?? 0)) : 0;
    var _rx_match_total = is_struct(ml) ? floor(real(ml.rx_note_on_match_total ?? 0)) : 0;
    var _rx_mismatch_total = is_struct(ml) ? floor(real(ml.rx_note_on_mismatch_total ?? 0)) : 0;
    var _loopback_summary = "[CAL_LOOPBACK] " + string(state.last_message)
        + " | trials=" + string(n)
        + " | sends=" + string(_send_count)
        + " | rx_note_on_total=" + string(_rx_total)
        + " | rx_note_on_match_total=" + string(_rx_match_total)
        + " | rx_note_on_mismatch_total=" + string(_rx_mismatch_total)
        + " | offset_ms=" + string_format(latency_mean, 0, 2)
        + " | jitter_ms=" + string_format(jitter, 0, 2);
    show_debug_message(_loopback_summary);

    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)
        && variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")
        && bool(global.timeline_cfg.score_lane_debug_file_log)) {
        var _log_path = variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_path")
            ? string(variable_struct_get(global.timeline_cfg, "score_lane_debug_file_path"))
            : "score_lane_debug.log";
        if (_log_path == "") _log_path = "score_lane_debug.log";
        var _f = file_text_open_append(_log_path);
        if (_f != -1) {
            file_text_write_string(_f, _loopback_summary);
            file_text_writeln(_f);
            file_text_close(_f);
        }
    }
    timing_calibration_log_add(run_ok ? "info" : "error", {
        completed_trials: n,
        midi_internal_offset_ms: latency_mean,
        jitter_midi_ms: jitter
    });

    if (run_ok && script_exists(asset_get_index("scoring_player_settings_save_for_player")) && variable_global_exists("current_player_id")) {
        scoring_player_settings_save_for_player(global.current_player_id);
    }

    return state.calibration_result;
}

/// @function timing_calibration_step_midi_loopback()
/// @description Update MIDI loopback calibration runner. Call once per step.
/// @returns Bool active
function timing_calibration_step_midi_loopback() {
    var state = timing_calibration_ensure_state();
    var ml = state.midi_loopback;
    if (!is_struct(ml) || !bool(ml.active ?? false)) return false;

    var now = timing_get_engine_now_ms();
    var _pulse_note_off_sent = variable_struct_exists(ml, "pulse_note_off_sent")
        ? bool(variable_struct_get(ml, "pulse_note_off_sent"))
        : true;
    var _last_send_ms = variable_struct_exists(ml, "last_send_ms")
        ? real(variable_struct_get(ml, "last_send_ms"))
        : 0;
    var _pulse_duration_ms = variable_struct_exists(ml, "pulse_duration_ms")
        ? real(variable_struct_get(ml, "pulse_duration_ms"))
        : 500;
    if (!_pulse_note_off_sent && _last_send_ms > 0 && now - _last_send_ms >= _pulse_duration_ms) {
        var status_off_pulse = 128 + floor(real(ml.channel ?? 0));
        var note_pulse = floor(real(ml.note ?? 65));
        midi_output_message_send_short(global.midi_output_device, status_off_pulse, note_pulse, 0);
        ml.note_on_pending = false;
        ml.pulse_note_off_sent = true;
    }

    if (bool(ml.awaiting_receive ?? false)) {
        if (now - real(ml.last_send_ms ?? 0) > real(ml.timeout_ms ?? 500)) {
            if (bool(ml.note_on_pending ?? false)) {
                var status_off = 128 + floor(real(ml.channel ?? 0));
                var note = floor(real(ml.note ?? 65));
                midi_output_message_send_short(global.midi_output_device, status_off, note, 0);
                ml.note_on_pending = false;
                ml.pulse_note_off_sent = true;
            }
            timing_calibration_log_add("error", {
                event: "timeout",
                trial: floor(real(ml.completed_trials ?? 0)) + 1
            });
            // Advance trial index on timeout so runs can terminate even without loopback receive.
            ml.completed_trials = floor(real(ml.completed_trials ?? 0)) + 1;
            ml.awaiting_receive = false;
            ml.next_send_ms = max(now, real(ml.last_send_ms ?? now) + real(ml.cycle_interval_ms ?? 1000));
        }
        state.midi_loopback = ml;
        return true;
    }

    if (floor(real(ml.completed_trials ?? 0)) >= floor(real(ml.total_trials ?? 0))) {
        timing_calibration_finish_midi_loopback(true);
        return false;
    }

    if (now < real(ml.next_send_ms ?? 0)) {
        state.midi_loopback = ml;
        return true;
    }

    var status_on = 144 + floor(real(ml.channel ?? 0));
    var note = floor(real(ml.note ?? 65));
    var vel = floor(real(ml.velocity ?? 110));

    midi_output_message_send_short(global.midi_output_device, status_on, note, vel);

    ml.last_send_ms = now;
    ml.note_off_due_ms = now + real(ml.pulse_duration_ms ?? 500);
    ml.awaiting_receive = true;
    ml.note_on_pending = true;
    ml.pulse_note_off_sent = false;
    array_push(ml.send_times, now);
    timing_calibration_log_add("send", {
        trial: floor(real(ml.completed_trials ?? 0)) + 1,
        note: note,
        channel: floor(real(ml.channel ?? 0))
    });

    state.midi_loopback = ml;
    return true;
}

/// @function timing_calibration_on_midi_message(_status_type, _note_midi, _velocity, _channel)
/// @description Calibration receive hook called from MIDI_process_messages for each MIDI message.
/// @param _status_type MIDI status high nibble (128/144)
/// @param _note_midi MIDI note number
/// @param _velocity MIDI velocity
/// @param _channel MIDI channel
function timing_calibration_on_midi_message(_status_type, _note_midi, _velocity, _channel) {
    var state = timing_calibration_ensure_state();
    var ml = state.midi_loopback;
    if (!is_struct(ml) || !bool(ml.active ?? false)) return;

    var status_type = floor(real(_status_type));
    var note = floor(real(_note_midi));
    var vel = floor(real(_velocity));
    var chan = floor(real(_channel));
    if (!(status_type == 144 && vel > 0)) return;

    ml.rx_note_on_total = floor(real(ml.rx_note_on_total ?? 0)) + 1;
    var expected_note = floor(real(ml.note ?? 65));
    var expected_chan = floor(real(ml.channel ?? 0));
    if (note != expected_note || chan != expected_chan) {
        ml.rx_note_on_mismatch_total = floor(real(ml.rx_note_on_mismatch_total ?? 0)) + 1;
        state.midi_loopback = ml;
        return;
    }

    ml.rx_note_on_match_total = floor(real(ml.rx_note_on_match_total ?? 0)) + 1;
    if (!bool(ml.awaiting_receive ?? false)) {
        state.midi_loopback = ml;
        return;
    }

    var now = timing_get_engine_now_ms();
    var send_ms = real(ml.last_send_ms ?? now);
    var latency_ms = max(0, now - send_ms);

    array_push(ml.latency_pairs_ms, latency_ms);
    ml.awaiting_receive = false;
    ml.completed_trials = floor(real(ml.completed_trials ?? 0)) + 1;
    ml.next_send_ms = max(now, send_ms + real(ml.cycle_interval_ms ?? 1000));

    timing_calibration_log_add("receive", {
        trial: ml.completed_trials,
        note: note,
        channel: chan,
        latency_ms: latency_ms
    });

    state.midi_loopback = ml;
}

/// @function apply_calibration_offset(_subsystem, _raw_timestamp_ms)
/// @description Apply loaded calibration offset for the requested subsystem.
/// @param _subsystem audio|midi_in|midi_out
/// @param _raw_timestamp_ms Raw timestamp
/// @returns Adjusted timestamp in ms
function apply_calibration_offset(_subsystem, _raw_timestamp_ms) {
    var sub = string_lower(string(_subsystem));
    var t = real(_raw_timestamp_ms);
    var offset_ms = 0;

    if (sub == "audio") {
        if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) {
            offset_ms = real(variable_struct_get(global.timeline_cfg, "audio_output_offset_ms"));
        }
    } else if (sub == "midi_in") {
        if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")) {
            offset_ms = real(variable_struct_get(global.timeline_cfg, "input_capture_offset_ms"));
        }
    } else if (sub == "midi_out") {
        offset_ms = 0;
    }

    return t + offset_ms;
}

/// @function timing_calibration_dev_run_midi_loopback(_trials)
/// @description Developer helper to run MIDI loopback calibration.
/// @returns Bool started
function timing_calibration_dev_run_midi_loopback(_trials = 20) {
    return timing_calibration_start_midi_loopback(_trials);
}

/// @function timing_calibration_start_external_audio_loopback(_trials)
/// @description Start external audio loopback pulse runner (MIDI note pulses out, auto-detects onset from line-in audio).
/// @param _trials Number of pulse trials
/// @returns Bool started
/// @writes global.timing_calibration.external_audio_loopback, global.timing_calibration.calibration_logs
function timing_calibration_start_external_audio_loopback(_trials = 20) {
    var state = timing_calibration_ensure_state();
    var trials = max(1, floor(real(_trials)));

    // Start audio recording from input device (typically line-in from loopback cable)
    var audio_rec_index = -1;
    if (audio_get_recorder_count() > 0) {
        audio_rec_index = audio_start_recording(0);
    }

    state.external_audio_loopback = {
        active: true,
        status: "running",
        detection_mode: "real_audio_onset",
        total_trials: trials,
        completed_trials: 0,
        note: 69,
        velocity: 127,
        channel: 0,
        cycle_interval_ms: 1000,
        pulse_duration_ms: 180,
        next_send_ms: timing_get_engine_now_ms(),
        last_send_ms: 0,
        note_on_pending: false,
        pulse_note_off_sent: true,
        awaiting_audio: false,
        send_times: [],
        latency_pairs_ms: [],
        registered_samples: 0,
        recorder_channel_index: audio_rec_index,
        recording_start_ms: timing_get_engine_now_ms(),
        audio_frames_processed: 0,
        async_packet_count: 0,
        async_channel_mismatch_count: 0,
        last_async_ms: 0,
        detection_threshold: 0.002,
        detection_ratio: 4.0,
        detect_min_latency_ms: 3,
        detect_max_latency_ms: 600,
        warmup_end_ms: timing_get_engine_now_ms() + 300,
        noise_floor_ema: 0,
        noise_floor_ready: false,
        prev_audio_level: 0,
        max_audio_level_seen: 0,
        max_window_level_seen: 0,
        sample_rate: 48000
    };

    timing_calibration_log_add("info", {
        mode: "external_audio_loopback",
        trials: trials,
        midi_out_name: variable_global_exists("midi_output_device_name") ? string(global.midi_output_device_name) : "",
        audio_recorder_index: audio_rec_index,
        detection_mode: "real_audio_onset"
    });

    state.last_message = "External audio loopback started (" + string(trials) + " pulses; real audio onset detection).";
    show_debug_message("[CAL_EXT_AUDIO] start out='" + string(variable_global_exists("midi_output_device_name") ? global.midi_output_device_name : "")
        + "' | pulse_ms=" + string(state.external_audio_loopback.pulse_duration_ms)
        + " | cycle_ms=" + string(state.external_audio_loopback.cycle_interval_ms)
        + " | trials=" + string(trials)
        + " | audio_recorder=" + string(audio_rec_index)
        + " | detect_mode=" + string(state.external_audio_loopback.detection_mode));
    return true;
}

/// @function timing_calibration_on_audio_recording_async(_async_map)
/// @description Process Audio Recording async chunks and register onset timings for external loopback.
/// @param _async_map async_load ds_map from Audio Recording event
/// @returns Bool handled
function timing_calibration_on_audio_recording_async(_async_map) {
    var state = timing_calibration_ensure_state();
    var ext = state.external_audio_loopback;
    if (!is_struct(ext) || !bool(ext.active ?? false)) return false;
    if (!is_struct(_async_map) && !is_real(_async_map)) {
        // async_load is a DS map id, so just proceed with accessors below.
    }

    var ch_idx = floor(real(_async_map[? "channel_index"]));
    var expected_ch = floor(real(ext.recorder_channel_index ?? -1));
    if (expected_ch < 0 || ch_idx != expected_ch) {
        ext.async_channel_mismatch_count = floor(real(ext.async_channel_mismatch_count ?? 0)) + 1;
        state.external_audio_loopback = ext;
        return false;
    }

    var tmp_buf = floor(real(_async_map[? "buffer_id"]));
    var data_len = floor(real(_async_map[? "data_len"]));
    if (tmp_buf < 0 || data_len <= 0) return false;

    ext.async_packet_count = floor(real(ext.async_packet_count ?? 0)) + 1;
    ext.last_async_ms = timing_get_engine_now_ms();

    var channels = 2;
    var bytes_per_sample = 4;
    var sample_rate = max(1, real(ext.sample_rate ?? 48000));
    var bytes_per_frame = max(1, channels * bytes_per_sample);
    var frames = floor(data_len / bytes_per_frame);
    if (frames <= 0) return false;

    var now_ms = timing_get_engine_now_ms();
    var frame_cursor = floor(real(ext.audio_frames_processed ?? 0));
    var threshold = real(ext.detection_threshold ?? 0.05);
    var min_lat_ms = real(ext.detect_min_latency_ms ?? 3);
    var max_lat_ms = real(ext.detect_max_latency_ms ?? 250);
    var prev_level = real(ext.prev_audio_level ?? 0);

    buffer_seek(tmp_buf, buffer_seek_start, 0);
    var packet_peak = 0;

    for (var i = 0; i < frames; i++) {
        var l = buffer_read(tmp_buf, buffer_f32);
        var r = buffer_read(tmp_buf, buffer_f32);
        var level = max(abs(real(l)), abs(real(r)));
        if (level > packet_peak) packet_peak = level;

        prev_level = level;
    }

    ext.audio_frames_processed = frame_cursor + frames;
    ext.prev_audio_level = prev_level;
    ext.max_audio_level_seen = max(real(ext.max_audio_level_seen ?? 0), packet_peak);

    // Track ambient level while idle so threshold adapts to the real input noise floor.
    var now_floor_ms = timing_get_engine_now_ms();
    var floor_alpha = 0.08;
    if (!bool(ext.awaiting_audio ?? false)) {
        var floor_prev = real(ext.noise_floor_ema ?? 0);
        if (!bool(ext.noise_floor_ready ?? false)) {
            ext.noise_floor_ema = packet_peak;
            ext.noise_floor_ready = true;
        } else {
            ext.noise_floor_ema = floor_prev + (packet_peak - floor_prev) * floor_alpha;
        }
    }

    if (now_floor_ms < real(ext.warmup_end_ms ?? 0)) {
        state.external_audio_loopback = ext;
        return true;
    }

    if (ext.awaiting_audio) {
        ext.max_window_level_seen = max(real(ext.max_window_level_seen ?? 0), packet_peak);
        var send_ms = real(ext.last_send_ms ?? now_ms);
        var dt_now = now_ms - send_ms;
        var floor_now = real(ext.noise_floor_ema ?? 0);
        var rel_thresh = max(threshold, floor_now * real(ext.detection_ratio ?? 4.0), floor_now + 0.001);
        if (dt_now >= min_lat_ms && dt_now <= max_lat_ms && packet_peak >= rel_thresh) {
            var latency_ms = max(0, dt_now);
            timing_calibration_external_audio_register_sample(latency_ms);
            ext.awaiting_audio = false;
            ext.completed_trials = floor(real(ext.completed_trials ?? 0)) + 1;

            timing_calibration_log_add("audio_detect", {
                mode: "external_audio_loopback",
                trial: ext.completed_trials,
                latency_ms: latency_ms,
                threshold: rel_thresh,
                noise_floor: floor_now,
                packet_peak: packet_peak
            });
        }
    }

    state.external_audio_loopback = ext;
    return true;
}

/// @function timing_calibration_external_audio_register_sample(_latency_ms)
/// @description Register one measured external-audio latency sample in ms.
/// @param _latency_ms Measured latency in ms for a trial
/// @returns Bool true when accepted
/// @writes global.timing_calibration.external_audio_loopback
function timing_calibration_external_audio_register_sample(_latency_ms) {
    var state = timing_calibration_ensure_state();
    var ext = state.external_audio_loopback;
    if (!is_struct(ext) || !bool(ext.active ?? false)) return false;

    var sample_ms = max(0, real(_latency_ms));
    array_push(ext.latency_pairs_ms, sample_ms);
    ext.registered_samples = floor(real(ext.registered_samples ?? 0)) + 1;

    timing_calibration_log_add("receive", {
        mode: "external_audio_loopback",
        sample_index: ext.registered_samples,
        latency_ms: sample_ms
    });

    state.external_audio_loopback = ext;
    return true;
}

/// @function timing_calibration_finish_external_audio_loopback(_ok)
/// @description Finalize external audio loopback, compute audio offset/jitter from registered samples, and apply audio offset.
/// @param _ok Whether run completed successfully
/// @returns Struct calibration result
function timing_calibration_finish_external_audio_loopback(_ok) {
    var state = timing_calibration_ensure_state();
    var ext = state.external_audio_loopback;
    var vals = is_struct(ext) && is_array(ext.latency_pairs_ms) ? ext.latency_pairs_ms : [];
    var detection_mode = is_struct(ext) ? string(ext.detection_mode ?? "") : "";
    var is_real_mode = (detection_mode == "real_audio_onset");

    var n = array_length(vals);
    var run_ok = bool(_ok) && is_real_mode && (n > 0);
    var latency_mean = 0;
    if (n > 0) {
        for (var i = 0; i < n; i++) latency_mean += real(vals[i]);
        latency_mean /= n;
    }

    var variance = 0;
    if (n > 0) {
        for (var j = 0; j < n; j++) {
            var d = real(vals[j]) - latency_mean;
            variance += d * d;
        }
        variance /= n;
    }
    var jitter = sqrt(max(0, variance));

    if (run_ok) {
        state.calibration_result.audio_output_offset_ms = latency_mean;
        state.calibration_result.jitter_audio_ms = jitter;
        state.calibration_result.timestamp = timing_get_engine_now_ms();
        var cur_offsets = timing_calibration_get_current_offsets();
        timing_calibration_apply_offsets(latency_mean, real(cur_offsets.visual_alignment_offset_ms ?? 0), "external-audio-loopback");
    }

    if (is_struct(ext) && bool(ext.note_on_pending ?? false)) {
        var status_off = 128 + floor(real(ext.channel ?? 0));
        var note = floor(real(ext.note ?? 65));
        midi_output_message_send_short(global.midi_output_device, status_off, note, 0);
    }

    // Stop audio recording if active
    if (is_struct(ext) && floor(real(ext.recorder_channel_index ?? -1)) >= 0) {
        audio_stop_recording(floor(real(ext.recorder_channel_index)));
    }

    state.external_audio_loopback = { active: false, status: run_ok ? "done" : "error" };
    state.last_message = run_ok
        ? "External audio loopback complete: latency=" + string_format(latency_mean, 0, 2) + " ms, jitter=" + string_format(jitter, 0, 2) + " ms"
        : "External audio loopback failed: no registered audio samples.";

    var _send_count = is_struct(ext) && is_array(ext.send_times) ? array_length(ext.send_times) : 0;
    var _sample_count = is_struct(ext) ? floor(real(ext.registered_samples ?? 0)) : 0;
    var _packet_count = is_struct(ext) ? floor(real(ext.async_packet_count ?? 0)) : 0;
    var _channel_mismatch_count = is_struct(ext) ? floor(real(ext.async_channel_mismatch_count ?? 0)) : 0;
    var _max_audio_level = is_struct(ext) ? real(ext.max_audio_level_seen ?? 0) : 0;
    var _max_window_level = is_struct(ext) ? real(ext.max_window_level_seen ?? 0) : 0;
    var _noise_floor = is_struct(ext) ? real(ext.noise_floor_ema ?? 0) : 0;
    var _summary = "[CAL_EXT_AUDIO] " + string(state.last_message)
        + " | trials=" + string(n)
        + " | sends=" + string(_send_count)
        + " | samples=" + string(_sample_count)
        + " | async_packets=" + string(_packet_count)
        + " | async_ch_mismatch=" + string(_channel_mismatch_count)
        + " | peak=" + string_format(_max_audio_level, 0, 4)
        + " | peak_window=" + string_format(_max_window_level, 0, 4)
        + " | noise_floor=" + string_format(_noise_floor, 0, 4)
        + " | offset_ms=" + string_format(latency_mean, 0, 2)
        + " | jitter_ms=" + string_format(jitter, 0, 2);
    show_debug_message(_summary);

    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)
        && variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")
        && bool(global.timeline_cfg.score_lane_debug_file_log)) {
        var _log_path = variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_path")
            ? string(variable_struct_get(global.timeline_cfg, "score_lane_debug_file_path"))
            : "score_lane_debug.log";
        if (_log_path == "") _log_path = "score_lane_debug.log";
        var _f = file_text_open_append(_log_path);
        if (_f != -1) {
            file_text_write_string(_f, _summary);
            file_text_writeln(_f);
            file_text_close(_f);
        }
    }

    timing_calibration_log_add(run_ok ? "info" : "error", {
        mode: "external_audio_loopback",
        completed_trials: n,
        audio_output_offset_ms: latency_mean,
        jitter_audio_ms: jitter
    });

    if (run_ok && script_exists(asset_get_index("scoring_player_settings_save_for_player")) && variable_global_exists("current_player_id")) {
        scoring_player_settings_save_for_player(global.current_player_id);
    }

    return state.calibration_result;
}

/// @function timing_calibration_step_external_audio_loopback()
/// @description Update external audio loopback pulse runner. Emits pulse trials and waits for async audio onset detection.
/// @returns Bool active
function timing_calibration_step_external_audio_loopback() {
    var state = timing_calibration_ensure_state();
    var ext = state.external_audio_loopback;
    if (!is_struct(ext) || !bool(ext.active ?? false)) return false;

    var now = timing_get_engine_now_ms();
    var pulse_sent = bool(ext.pulse_note_off_sent ?? true);
    var last_send_ms = real(ext.last_send_ms ?? 0);
    var pulse_duration_ms = real(ext.pulse_duration_ms ?? 30);
    
    // Send note-off after pulse duration
    if (!pulse_sent && last_send_ms > 0 && now - last_send_ms >= pulse_duration_ms) {
        var status_off_pulse = 128 + floor(real(ext.channel ?? 0));
        var note_pulse = floor(real(ext.note ?? 65));
        midi_output_message_send_short(global.midi_output_device, status_off_pulse, note_pulse, 0);
        ext.note_on_pending = false;
        ext.pulse_note_off_sent = true;
    }

    // Timeout if async audio detection did not find onset in time.
    if (ext.awaiting_audio && now - last_send_ms > real(ext.detect_max_latency_ms ?? 250)) {
        // Timeout: no audio detected
        ext.awaiting_audio = false;
        ext.completed_trials = floor(real(ext.completed_trials ?? 0)) + 1;
        
        timing_calibration_log_add("audio_timeout", {
            mode: "external_audio_loopback",
            trial: ext.completed_trials,
            peak_window: real(ext.max_window_level_seen ?? 0),
            threshold: real(ext.detection_threshold ?? 0)
        });
        ext.max_window_level_seen = 0;
    }

    if (floor(real(ext.completed_trials ?? 0)) >= floor(real(ext.total_trials ?? 0))) {
        timing_calibration_finish_external_audio_loopback(true);
        return false;
    }

    if (now < real(ext.next_send_ms ?? 0)) {
        state.external_audio_loopback = ext;
        return true;
    }

    var status_on = 144 + floor(real(ext.channel ?? 0));
    var note = floor(real(ext.note ?? 65));
    var vel = floor(real(ext.velocity ?? 110));
    midi_output_message_send_short(global.midi_output_device, status_on, note, vel);

    ext.last_send_ms = now;
    ext.note_on_pending = true;
    ext.pulse_note_off_sent = false;
    ext.awaiting_audio = true;
    ext.next_send_ms = now + real(ext.cycle_interval_ms ?? 1000);
    array_push(ext.send_times, now);

    timing_calibration_log_add("send", {
        mode: "external_audio_loopback",
        trial: floor(real(ext.completed_trials ?? 0)) + 1,
        note: note,
        channel: floor(real(ext.channel ?? 0))
    });

    state.external_audio_loopback = ext;
    return true;
}

/// @function timing_calibration_dev_run_external_audio_loopback(_trials)
/// @description Developer helper to run external audio loopback pulse stage.
/// @returns Bool started
function timing_calibration_dev_run_external_audio_loopback(_trials = 20) {
    return timing_calibration_start_external_audio_loopback(_trials);
}

/// @function timing_calibration_dev_export_logs(_path)
/// @description Developer helper to export current calibration logs.
/// @returns Export path string or empty string on failure
function timing_calibration_dev_export_logs(_path = "") {
    return timing_calibration_export_logs(_path);
}

/// @function timing_calibration_dev_import_results(_path)
/// @description Developer helper to import a calibration result JSON file.
/// @returns Bool success
function timing_calibration_dev_import_results(_path) {
    return timing_calibration_import_result_json(_path);
}

/// @function timing_calibration_dev_view_current()
/// @description Developer helper to inspect current calibration result object.
/// @returns Calibration result struct
function timing_calibration_dev_view_current() {
    var state = timing_calibration_ensure_state();
    return state.calibration_result;
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
/// @param [_input_ms] Optional input capture offset in ms; omitted preserves current value
/// @returns Struct { audio_output_offset_ms, visual_alignment_offset_ms, input_capture_offset_ms }
/// @writes global.timeline_cfg.audio_output_offset_ms, global.timeline_cfg.visual_alignment_offset_ms, global.timeline_cfg.input_capture_offset_ms
function timing_calibration_apply_offsets(_audio_ms, _visual_ms, _source_label = "manual", _input_ms = undefined) {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var audio_ms = real(_audio_ms ?? 0);
    var visual_ms = real(_visual_ms ?? 0);
    var input_ms = is_undefined(_input_ms)
        ? (variable_struct_exists(cfg, "input_capture_offset_ms") ? real(variable_struct_get(cfg, "input_capture_offset_ms")) : 0)
        : real(_input_ms);

    variable_struct_set(cfg, "audio_output_offset_ms", audio_ms);
    variable_struct_set(cfg, "visual_alignment_offset_ms", visual_ms);
    variable_struct_set(cfg, "input_capture_offset_ms", input_ms);

    show_debug_message("[CALIBRATION] offsets applied source=" + string(_source_label)
        + " audio=" + string_format(audio_ms, 0, 2)
        + " visual=" + string_format(visual_ms, 0, 2)
        + " input=" + string_format(input_ms, 0, 2));

    return {
        audio_output_offset_ms: audio_ms,
        visual_alignment_offset_ms: visual_ms,
        input_capture_offset_ms: input_ms
    };
}
