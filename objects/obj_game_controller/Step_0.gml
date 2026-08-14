/// @description Insert description here
// You can write your code in this editor

var _controller_step_start_us = get_timer();
var _is_live_playback = false;
if (script_exists(asset_get_index("gv_is_live_playback"))) {
	_is_live_playback = gv_is_live_playback();
}
if ((!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL") || global.RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL)
	&& variable_global_exists("rt_budget_controller_step_prev_start_us")) {
	tune_rt_budget_diag_record_controller_step_interval_ms(
		(_controller_step_start_us - real(global.rt_budget_controller_step_prev_start_us)) * 0.001
	);
}
global.rt_budget_controller_step_prev_start_us = _controller_step_start_us;

// Step-driven playback scheduler mode dispatches all due tune event groups here.
var _scheduler_active = variable_global_exists("tune_scheduler_active") && bool(global.tune_scheduler_active);
var _timeline_active = variable_global_exists("timeline_state")
	&& is_struct(global.timeline_state)
	&& variable_struct_exists(global.timeline_state, "active")
	&& bool(global.timeline_state.active);
var _deferred_queue_has_items = variable_global_exists("tune_deferred_queue")
	&& is_array(global.tune_deferred_queue)
	&& array_length(global.tune_deferred_queue) > 0;

var _phase_t0_us = get_timer();
if (_scheduler_active && variable_global_exists("tune_scheduler_mode_step") && bool(global.tune_scheduler_mode_step)) {
	tune_scheduler_step_tick();
}
if (!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES") || global.RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES) {
	tune_rt_budget_diag_record_controller_phase_ms("scheduler_tick", (get_timer() - _phase_t0_us) * 0.001);
}
// Keep timeline/playhead maintenance owned by the controller step so it does
// not depend on any specific UI anchor instance being active.
_phase_t0_us = get_timer();
if (_timeline_active) {
	var _timeline_tick_idx = variable_global_exists("gv_timeline_step_tick_idx")
		? real(global.gv_timeline_step_tick_idx)
		: asset_get_index("gv_timeline_step_tick");
	if (!variable_global_exists("gv_timeline_step_tick_idx")) {
		global.gv_timeline_step_tick_idx = _timeline_tick_idx;
	}
	if (script_exists(_timeline_tick_idx)) {
		script_execute(_timeline_tick_idx);
	}
}
if (!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES") || global.RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES) {
	tune_rt_budget_diag_record_controller_phase_ms("timeline_tick", (get_timer() - _phase_t0_us) * 0.001);
}
var _deferred_max_items = variable_global_exists("PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP")
	? max(1, floor(real(global.PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP)))
	: 128;
var _deferred_budget_us = variable_global_exists("PLAYBACK_DEFERRED_MAX_BUDGET_US")
	? max(0, real(global.PLAYBACK_DEFERRED_MAX_BUDGET_US))
	: 1200;
_phase_t0_us = get_timer();
if (_scheduler_active && _deferred_queue_has_items) {
	tune_scheduler_process_deferred(
		_deferred_max_items,
		_deferred_budget_us
	);
}
var _deferred_elapsed_ms = (get_timer() - _phase_t0_us) * 0.001;
perf_report_record_sample("deferred_work_ms", _deferred_elapsed_ms);
if (!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES") || global.RT_BUDGET_DIAG_INCLUDE_CONTROLLER_PHASES) {
	tune_rt_budget_diag_record_controller_phase_ms("deferred_tick", _deferred_elapsed_ms);
}

// Apply deferred UI layer visibility after room switches.
// room_goto() transitions at end-of-step, so this guarantees we set layers in the destination room.
if (variable_global_exists("pending_layer_mode")) {
	var _mode = string(global.pending_layer_mode);
	if (_mode != "") {
		var _room_ok = true;
		if (variable_global_exists("pending_layer_room")) {
			var _target_room = real(global.pending_layer_room);
			if (_target_room >= 0) {
				_room_ok = (room == _target_room);
			}
		}

		if (_room_ok) {
			var _main_layer_id = layer_get_id("main_menu_layer");
			var _settings_layer_id = layer_get_id("settings_window_layer");
			var _tune_layer_id = layer_get_id("tune_window_layer");
			var _gameplay_layer_id = layer_get_id("gameplay_layer");
			var _current_note_layer_id = layer_get_id("current_note_layer");
			var _judge_settings_layer_id = layer_get_id("judge_settings_layer");
			var _player_window_layer_id = layer_get_id("player_window_layer");

			switch (_mode) {
				case "play":
					if (_main_layer_id != -1) {
						layer_set_visible(_main_layer_id, false);
						instance_deactivate_layer(_main_layer_id);
					}
					if (_settings_layer_id != -1) {
						layer_set_visible(_settings_layer_id, false);
						instance_deactivate_layer(_settings_layer_id);
					}
					if (_tune_layer_id != -1) {
						layer_set_visible(_tune_layer_id, false);
						instance_deactivate_layer(_tune_layer_id);
					}
					if (_current_note_layer_id != -1) {
						layer_set_visible(_current_note_layer_id, false);
						instance_deactivate_layer(_current_note_layer_id);
					}
					if (_judge_settings_layer_id != -1) {
						layer_set_visible(_judge_settings_layer_id, false);
						instance_deactivate_layer(_judge_settings_layer_id);
					}
					if (_player_window_layer_id != -1) {
						layer_set_visible(_player_window_layer_id, false);
						instance_deactivate_layer(_player_window_layer_id);
					}
					if (_gameplay_layer_id != -1) {
						// Force a visibility refresh in destination room so gameplay anchors wake up reliably.
						layer_set_visible(_gameplay_layer_id, false);
						layer_set_visible(_gameplay_layer_id, true);
						instance_activate_layer(_gameplay_layer_id);
					}
				break;

				case "main":
					if (_main_layer_id != -1) {
						layer_set_visible(_main_layer_id, true);
						instance_activate_layer(_main_layer_id);
					}
					if (_settings_layer_id != -1) {
						layer_set_visible(_settings_layer_id, false);
						instance_deactivate_layer(_settings_layer_id);
					}
					if (_tune_layer_id != -1) {
						layer_set_visible(_tune_layer_id, false);
						instance_deactivate_layer(_tune_layer_id);
					}
					if (_gameplay_layer_id != -1) {
						layer_set_visible(_gameplay_layer_id, false);
						instance_deactivate_layer(_gameplay_layer_id);
					}
					if (_current_note_layer_id != -1) {
						layer_set_visible(_current_note_layer_id, false);
						instance_deactivate_layer(_current_note_layer_id);
					}
				break;
			}

			global.pending_layer_mode = "";
			if (variable_global_exists("pending_layer_room")) {
				global.pending_layer_room = -1;
			}
		}
	}
}

if (!_is_live_playback
	&& variable_global_exists("pending_auto_start_play")
	&& global.pending_auto_start_play
	&& room == Room_play
	&& (!variable_global_exists("pending_layer_mode") || string(global.pending_layer_mode) == "")) {
	global.pending_auto_start_play = false;
	start_play();
}

if (!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME") || global.RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME) {
	tune_rt_budget_diag_record_controller_step_ms((get_timer() - _controller_step_start_us) * 0.001);
}

// ── DEBUG: S = load example MSR set, D = clear set ──────────────────────────
if (keyboard_check_pressed(ord("S"))) {
	var _ok = scr_set_load_json("sets/example_msr.json");
	show_debug_message("S: scr_set_load_json -> " + string(_ok)
	    + " | set active: " + string(scr_set_is_active())
	    + " | title: " + (scr_set_is_active() ? global.active_set.title : "n/a"));
}
if (keyboard_check_pressed(ord("D"))) {
	scr_set_init_global();
	show_debug_message("D: set cleared, scr_set_is_active() = " + string(scr_set_is_active()));
}

// ── DEV: L = run MIDI loopback calibration ──────────────────────────
if (keyboard_check_pressed(ord("L"))) {
	// Only allow in main menu or settings (no tune/gameplay active)
	var _main_layer_id = layer_get_id("main_menu_layer");
	var _settings_layer_id = layer_get_id("settings_window_layer");
	var _main_visible = (_main_layer_id != -1) && layer_get_visible(_main_layer_id);
	var _settings_visible = (_settings_layer_id != -1) && layer_get_visible(_settings_layer_id);
	if (_main_visible || _settings_visible) {
		var _ok = timing_calibration_dev_run_midi_loopback(20);
		show_debug_message("L: MIDI loopback calibration triggered, ok=" + string(_ok));
	}
}

// ── DEV: O = run external audio loopback pulse stage ─────────────────
if (keyboard_check_pressed(ord("O"))) {
	// Only allow in main menu or settings (no tune/gameplay active)
	var _main_layer_id_o = layer_get_id("main_menu_layer");
	var _settings_layer_id_o = layer_get_id("settings_window_layer");
	var _main_visible_o = (_main_layer_id_o != -1) && layer_get_visible(_main_layer_id_o);
	var _settings_visible_o = (_settings_layer_id_o != -1) && layer_get_visible(_settings_layer_id_o);
	if (_main_visible_o || _settings_visible_o) {
		var _ok_o = timing_calibration_dev_run_external_audio_loopback(20);
		show_debug_message("O: external audio loopback pulse stage triggered, ok=" + string(_ok_o));
	}
}

// ── DEV: P = shadow-diff the GML ABC parser against exported tune.json ──────
if (keyboard_check_pressed(ord("P"))) {
	tune_shadow_diff_all();
}

// ── DEV: N = compile staged ABC into tune folders (never touches legacy .json) ────
if (keyboard_check_pressed(ord("N"))) {
	tune_author_create_from_staged();
}