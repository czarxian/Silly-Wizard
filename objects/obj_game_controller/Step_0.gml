/// @description Insert description here
// You can write your code in this editor

var _controller_step_start_us = get_timer();
var _controller_step_start_ms = timing_get_engine_now_ms();
if ((!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL") || global.RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL)
	&& variable_global_exists("rt_budget_controller_step_prev_start_ms")) {
	tune_rt_budget_diag_record_controller_step_interval_ms(
		_controller_step_start_ms - real(global.rt_budget_controller_step_prev_start_ms)
	);
}
global.rt_budget_controller_step_prev_start_ms = _controller_step_start_ms;

// Step-driven playback scheduler mode dispatches all due tune event groups here.
tune_scheduler_step_tick();
var _deferred_max_items = variable_global_exists("PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP")
	? max(1, floor(real(global.PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP)))
	: 128;
var _deferred_budget_us = variable_global_exists("PLAYBACK_DEFERRED_MAX_BUDGET_US")
	? max(0, real(global.PLAYBACK_DEFERRED_MAX_BUDGET_US))
	: 1200;
tune_scheduler_process_deferred(
	_deferred_max_items,
	_deferred_budget_us
);

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

if (!variable_global_exists("RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME") || global.RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME) {
	tune_rt_budget_diag_record_controller_step_ms((get_timer() - _controller_step_start_us) * 0.001);
}