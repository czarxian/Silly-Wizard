

// scr_button_scripts — UI button dispatcher
// Purpose: Routes button presses to actions (open windows, change settings, start play, confirm tune) and coordinates UI → logic flows.
// Key functions: scr_handle_button_click, scr_open_window, scr_settings_OK, scr_tune_OK, start_play
// Related objects: obj_tune_picker, obj_ui_controller, obj_game_controller

//Main menu buttons
	//Button handler
	/// @function scr_handle_button_click(button_ID, _ctx)
	/// @description Central button dispatcher; routes button ID to its handler function.
	/// @param button_ID Integer button code (see switch table in function body)
	/// @param _ctx Optional caller object instance (button context), default noone
	/// @callers obj_btn_base (Click event)
	function scr_handle_button_click(button_ID, _ctx = noone){
		if (is_real(button_ID) && button_ID < 0) return;

		var ctx = scr_button_get_ctx(_ctx);

		switch (button_ID) {
			case 0: scr_script_not_set(ctx); break;						//"button"
			case 1: scr_goto_playroom(); break;		//"play"
			case 2: scr_checkbox_click(ctx); break;											//"settings"
			case 3: scr_open_window(scr_button_inst_get(ctx, "button_click_value", 0)); break;	//"tune"
			case 4: scr_exit_game(); break;		//exit"
			case 5: scr_goto_mainmenu(); break;		//exit"
			case 6: scr_settings_change(ctx); break;	//exit
			case 7: scr_settings_MIDI_In_change(ctx); break;	//exit
			case 8: scr_settings_MIDI_Out_change(ctx); break;	//exit
			case 9: scr_settings_OK(ctx); break;		//exit
			case 10: scr_tune_OK(ctx); break;				//exit
			case 11: start_play(); break;		//exit
			case 12: scr_regenerate_tune_library(); break;		//regenerate
			case 13: export_event_history(); break;
			case 14: scr_metronome_mode_change(ctx); break;
			case 15: scr_metronome_pattern_change(ctx); break;
			case 16: scr_metronome_volume_change(ctx); break;
			case 17: scr_tune_bpm_change(ctx); break;
			case 18: scr_tune_countin_change(ctx); break;
			case 19: scr_gracenote_override_change(ctx); break;
			case 20: scr_swing_mult_change(ctx); break;
			case 21: scr_current_note_measure_scroll(ctx); break;
			case 22: scr_notebeam_zoom_change(ctx); break;
			case 23: scr_notebeam_pan_scroll(ctx); break;
			case 24: scr_loop_mode_toggle(ctx); break;
			case 25: scr_judge_settings_OK(ctx); break;
			case 26: scr_tune_reset_to_defaults(ctx); break;
			case 27: scr_select_player(ctx); break;
			case 28: scr_player_clear_guest_history(); break;
			case 29: scr_toggle_loop_score_overview(ctx); break;
			case 30: scr_settings_logs_toggle(ctx); break;
			case 31: scr_calibration_mode_change(ctx); break;
			case 32: scr_calibration_offset_change(ctx); break;
			case 33: scr_calibration_test_preview(ctx); break;
			case 34: scr_calibration_reset_defaults(ctx); break;
			case 35: scr_calibration_save_profile(ctx); break;
			case 36: scr_calibration_toggle_advanced(ctx); break;
			case 37: scr_calibration_apply_profile(ctx); break;
			case 38: scr_settings_data_root_set(ctx); break;
			case 39: scr_settings_data_root_reset_auto(ctx); break;
			case 40: scr_viewport_ahead_change(ctx); break;
			// Compatibility aliases for calibration controls if RoomUI script indices drift.
			case 78: scr_calibration_test_preview(ctx); break;
			case 92: scr_calibration_mode_change(ctx); break;
			case 93: scr_calibration_mode_change(ctx); break;
			default: show_debug_message("Unknown button script index: " + string(button_ID)); scr_script_not_set(ctx); break;
		}
	}

	/// @function scr_button_get_ctx(_ctx)
	/// @description Validate and return the context instance, or noone if invalid.
	function scr_button_get_ctx(_ctx = noone) {
		if (_ctx != noone && instance_exists(_ctx)) return _ctx;
		return noone;
	}

	/// @function scr_button_is_set_mode()
	/// @description Return true when runtime is in set workflow mode.
	/// @returns {bool} True if active playback mode is set
	/// @reads global.playback_context
	/// @callers scr_button_get_active_settings_segment, scr_tune_bpm_change
	function scr_button_is_set_mode() {
		return variable_global_exists("playback_context")
			&& is_struct(global.playback_context)
			&& string(global.playback_context[$ "mode"] ?? "") == "set";
	}

	/// @function scr_button_inst_get(_ctx, _name, _default)
	/// @description Safe instance variable getter — returns default if instance or variable doesn't exist.
	function scr_button_inst_get(_ctx, _name, _default = undefined) {
		if (_ctx == noone || !instance_exists(_ctx)) return _default;
		if (!variable_instance_exists(_ctx, _name)) return _default;
		return variable_instance_get(_ctx, _name);
	}

	/// @function scr_button_inst_set(_ctx, _name, _value)
	/// @description Safe instance variable setter — no-ops if instance doesn't exist.
	function scr_button_inst_set(_ctx, _name, _value) {
		if (_ctx == noone || !instance_exists(_ctx)) return;
		variable_instance_set(_ctx, _name, _value);
	}

	/// @function scr_button_field_get(_field, _name, _default)
	/// @description Safe field instance variable getter.
	function scr_button_field_get(_field, _name, _default = undefined) {
		if (_field == noone || !instance_exists(_field)) return _default;
		if (!variable_instance_exists(_field, _name)) return _default;
		return variable_instance_get(_field, _name);
	}

	/// @function scr_button_field_set(_field, _name, _value)
	/// @description Safe field instance variable setter.
	function scr_button_field_set(_field, _name, _value) {
		if (_field == noone || !instance_exists(_field)) return;
		variable_instance_set(_field, _name, _value);
	}

	/// @function scr_button_struct_get(_value, _name, _default)
	/// @description Safe struct key getter with fallback default.
	function scr_button_struct_get(_value, _name, _default = undefined) {
		if (!is_struct(_value) || !variable_struct_exists(_value, _name)) return _default;
		return variable_struct_get(_value, _name);
	}

	/// @function scr_button_struct_set(_value, _name, _new_value)
	/// @description Safe struct key setter — no-op if not a struct.
	function scr_button_struct_set(_value, _name, _new_value) {
		if (!is_struct(_value)) return;
		variable_struct_set(_value, _name, _new_value);
	}

	/// @function scr_button_tune_data_get(_tune)
	/// @description Return the tune_data struct from an obj_tune instance, or undefined.
	function scr_button_tune_data_get(_tune) {
		return scr_button_inst_get(_tune, "tune_data", undefined);
	}

	/// @function scr_button_tune_is_loaded(_tune)
	/// @description Return true if the obj_tune instance has tune_data.is_loaded set.
	function scr_button_tune_is_loaded(_tune) {
		var tune_data = scr_button_tune_data_get(_tune);
		return scr_button_struct_get(tune_data, "is_loaded", false);
	}

	/// @function scr_button_find_field_by_ui_name(_field_ui_name)
	/// @description Find the first obj_field_base instance whose ui_name matches, or noone.
	/// @returns The matching instance ID or noone
	/// @objects obj_field_base (iterated via instance_find)
	function scr_button_find_field_by_ui_name(_field_ui_name) {
		var field_count = instance_number(obj_field_base);
		for (var i = 0; i < field_count; i++) {
			var field_inst = instance_find(obj_field_base, i);
			if (field_inst == noone) continue;
			var field_name = string(scr_button_inst_get(field_inst, "ui_name", ""));
			if (field_name == _field_ui_name) return field_inst;
		}
		return noone;
	}

	/// @function scr_button_calibration_refresh_ui()
	/// @description Refresh timing calibration offset fields when those UI fields exist.
	/// @reads global.timeline_cfg
	/// @writes obj_field_base.field_min_value/field_max_value/field_value/field_contents
	/// @objects obj_field_base
	/// @callers scr_open_window, scr_calibration_offset_change, scr_calibration_apply_profile
	function scr_button_calibration_refresh_ui() {
		if (!script_exists(asset_get_index("timing_calibration_get_current_offsets"))) return;

		var offsets = timing_calibration_get_current_offsets();
		var offset_min = -300;
		var offset_max = 300;
		var specs = [
			{ ui_name: "calibration_mode_field", key: "mode" },
			{ ui_name: "setting_field_cal_audio", key: "audio_output_offset_ms" },
			{ ui_name: "setting_field_cal_visual", key: "visual_alignment_offset_ms" },
			{ ui_name: "setting_field_cal_input", key: "input_capture_offset_ms" },
			{ ui_name: "calibration_summary_field", key: "summary" },
			{ ui_name: "calibration_status_field", key: "status" }
		];

		for (var i = 0; i < array_length(specs); i++) {
			var spec = specs[i];
			var field_inst = scr_button_find_field_by_ui_name(spec.ui_name);
			if (!instance_exists(field_inst)) continue;

			if (spec.key == "mode") {
				var mode_idx = timing_calibration_get_current_mode_index();
				var mode_labels = timing_calibration_get_mode_labels();
				scr_button_field_set(field_inst, "field_min_value", 0);
				scr_button_field_set(field_inst, "field_max_value", max(0, array_length(mode_labels) - 1));
				scr_button_field_set(field_inst, "field_value", mode_idx);
				scr_button_field_set(field_inst, "field_contents", timing_calibration_get_mode_label(mode_idx));
			} else if (spec.key == "summary") {
				scr_button_field_set(field_inst, "field_min_value", 0);
				scr_button_field_set(field_inst, "field_max_value", 1);
				scr_button_field_set(field_inst, "field_value", 0);
				scr_button_field_set(field_inst, "field_contents", "");
			} else if (spec.key == "input_capture_offset_ms") {
				var input_ms = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms"))
					? real(variable_struct_get(global.timeline_cfg, "input_capture_offset_ms"))
					: 0;
				scr_button_field_set(field_inst, "field_min_value", offset_min);
				scr_button_field_set(field_inst, "field_max_value", offset_max);
				scr_button_field_set(field_inst, "field_value", input_ms);
				scr_button_field_set(field_inst, "field_contents", string_format(input_ms, 0, 1) + " ms (usually keep 0)");
			} else if (spec.key == "status") {
				var state_status = timing_calibration_ensure_state();
				scr_button_field_set(field_inst, "field_min_value", 0);
				scr_button_field_set(field_inst, "field_max_value", 1);
				scr_button_field_set(field_inst, "field_value", 0);
				scr_button_field_set(field_inst, "field_contents", string(state_status.last_message ?? "Ready"));
			} else {
				var current_ms = variable_struct_exists(offsets, spec.key)
					? real(variable_struct_get(offsets, spec.key))
					: 0;
				scr_button_field_set(field_inst, "field_min_value", offset_min);
				scr_button_field_set(field_inst, "field_max_value", offset_max);
				scr_button_field_set(field_inst, "field_value", current_ms);
				scr_button_field_set(field_inst, "field_contents", string_format(current_ms, 0, 1) + " ms");
			}
		}
	}

	/// @function scr_button_calibration_apply_offset_delta(_field_ui_name, _delta_ms)
	/// @description Apply a manual ms delta to audio, visual, or MIDI input calibration offset domain.
	/// @param _field_ui_name Calibration field ui_name
	/// @param _delta_ms Signed milliseconds to apply
	/// @returns {bool} True when a known offset field was updated
	/// @reads global.timeline_cfg
	/// @writes global.timeline_cfg.* offsets, global.timing_calibration.last_message
	/// @callers scr_calibration_offset_change
	function scr_button_calibration_apply_offset_delta(_field_ui_name, _delta_ms) {
		if (!script_exists(asset_get_index("timing_calibration_get_current_offsets"))) return false;
		if (!script_exists(asset_get_index("timing_calibration_apply_offsets"))) return false;

		var ui_name = string(_field_ui_name);
		var delta = real(_delta_ms);
		if (delta == 0) return false;

		var offsets = timing_calibration_get_current_offsets();
		var audio_ms = variable_struct_exists(offsets, "audio_output_offset_ms")
			? real(variable_struct_get(offsets, "audio_output_offset_ms"))
			: 0;
		var visual_ms = variable_struct_exists(offsets, "visual_alignment_offset_ms")
			? real(variable_struct_get(offsets, "visual_alignment_offset_ms"))
			: 0;
		var input_ms = variable_struct_exists(offsets, "input_capture_offset_ms")
			? real(variable_struct_get(offsets, "input_capture_offset_ms"))
			: 0;

		if (ui_name == "setting_field_cal_audio") {
			audio_ms += delta;
		} else if (ui_name == "setting_field_cal_visual") {
			visual_ms += delta;
		} else if (ui_name == "setting_field_cal_input") {
			input_ms += delta;
		} else {
			return false;
		}

		timing_calibration_apply_offsets(audio_ms, visual_ms, "settings-manual");
		variable_struct_set(gv_ensure_timeline_cfg_defaults(), "input_capture_offset_ms", input_ms);
		var state = timing_calibration_ensure_state();
		state.last_message = "Manual calibration nudge applied.";
		if (script_exists(asset_get_index("timing_calibration_store_current_device_profile"))) {
			timing_calibration_store_current_device_profile();
		}
		if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
			scoring_player_settings_save_for_player();
		}
		return true;
	}

	/// @function scr_button_get_bpm_from_bound_field(_default)
	/// @description Resolve BPM from the field_ref bound to BPM +/- buttons (button_script_index 17), preferring visible-layer buttons.
	/// @param _default Value returned when no valid bound field value exists
	/// @returns Real BPM value or _default
	/// @objects obj_btn_base
	function scr_button_get_bpm_from_bound_field(_default = undefined) {
		var best_visible = noone;
		var best_any = noone;
		var btn_count = instance_number(obj_btn_base);
		for (var i = 0; i < btn_count; i++) {
			var btn = instance_find(obj_btn_base, i);
			if (btn == noone) continue;
			if (real(scr_button_inst_get(btn, "button_script_index", -1)) != 17) continue;

			var field = scr_button_inst_get(btn, "field_ref", noone);
			if (!instance_exists(field)) continue;

			if (best_any == noone || btn > best_any) best_any = btn;

			var ui_layer_num = real(scr_button_inst_get(btn, "ui_layer_num", -1));
			if (ui_layer_num >= 0) {
				var layer_name = GetLayerNameFromIndex(ui_layer_num);
				var layer_id = layer_get_id(layer_name);
				if (layer_id != -1 && layer_get_visible(layer_id)) {
					if (best_visible == noone || btn > best_visible) best_visible = btn;
				}
			}
		}

		var pick_btn = (best_visible != noone) ? best_visible : best_any;
		if (pick_btn == noone) {
			scr_button_bpm_debug_log("[BPM-FIELD-LOOKUP] no button found for script_index=17; trying direct field lookup");

			// Fallback: BPM field may exist even if +/- button instances are not present/visible.
			var direct_field = scr_button_find_field_by_ui_name("metro_field_3");
			if (direct_field == noone) {
				direct_field = scr_button_find_field_by_ui_name("tune_BPM_field");
			}

			if (direct_field != noone && instance_exists(direct_field)) {
				var direct_val = scr_button_field_get(direct_field, "field_value", _default);
				scr_button_bpm_debug_log("[BPM-FIELD-LOOKUP] direct field fallback value=" + string(direct_val ?? "<undefined>"));
				if (!is_undefined(direct_val)) return real(direct_val);
			}

			return _default;
		}

		var pick_field = scr_button_inst_get(pick_btn, "field_ref", noone);
		if (!instance_exists(pick_field)) {
			scr_button_bpm_debug_log("[BPM-FIELD-LOOKUP] button found but field_ref missing or destroyed");
			return _default;
		}

		var val = scr_button_field_get(pick_field, "field_value", _default);
		scr_button_bpm_debug_log("[BPM-FIELD-LOOKUP] found field: value=" + string(val ?? "<undefined>"));
		if (is_undefined(val)) return _default;
		return real(val);
	}

	/// @function scr_button_clone_struct(_src)
	/// @description Shallow-clone a struct into a new struct (one level deep).
	function scr_button_clone_struct(_src) {
		if (!is_struct(_src)) return _src;
		var out = {};
		var names = variable_struct_get_names(_src);
		for (var i = 0; i < array_length(names); i++) {
			var key = string(names[i]);
			out[$ key] = variable_struct_get(_src, key);
		}
		return out;
	}

	/// @function scr_button_sync_single_tune_settings_segment(_segment)
	/// @description Mirror a single-tune settings segment into both virtual set storage and playback_context.
	/// @param {struct} _segment Segment/settings struct to mirror
	/// @reads global.playback_context
	/// @writes global.current_set, global.current_set_item_index, global.playback_context.mode, global.playback_context.segments
	/// @callers scr_button_get_active_settings_segment, scr_button_write_setting_to_active_segment, scr_button_resolve_effective_settings
	function scr_button_sync_single_tune_settings_segment(_segment) {
		if (!is_struct(_segment)) return;

		if (!variable_global_exists("current_set") || !is_array(global.current_set)) {
			global.current_set = [];
		}

		var seg_copy = scr_button_clone_struct(_segment);
		if (array_length(global.current_set) <= 0) {
			global.current_set = [seg_copy];
		} else {
			global.current_set[0] = seg_copy;
		}
		global.current_set_item_index = 0;

		if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) {
			global.playback_context = {
				mode: "tune",
				display_title: "",
				active_segment: 0,
				segments: [],
				score_override_plan: []
			};
		}
		if (!is_array(global.playback_context.segments)) {
			global.playback_context.segments = [];
		}
		if (string(global.playback_context[$ "mode"] ?? "") == "") {
			global.playback_context[$ "mode"] = "tune";
		}
		if (string(global.playback_context[$ "mode"] ?? "") != "set") {
			global.playback_context[$ "mode"] = "tune";
			if (array_length(global.playback_context.segments) <= 0 || !is_struct(global.playback_context.segments[0])) {
				global.playback_context.segments = [scr_button_clone_struct(seg_copy)];
			} else {
				var ctx_seg = global.playback_context.segments[0];
				var keys = variable_struct_get_names(seg_copy);
				for (var i = 0; i < array_length(keys); i++) {
					var key = string(keys[i]);
					ctx_seg[$ key] = seg_copy[$ key];
				}
				global.playback_context.segments[0] = ctx_seg;
			}
		}
	}

	/// @function scr_button_get_active_settings_segment(_create_if_missing)
	/// @description Resolve the authoritative active settings segment (set item in set mode, virtual one-tune set item in single mode).
	/// @param {bool} _create_if_missing Create and seed a single-tune segment from globals when missing
	/// @returns {struct|undefined} Active settings segment
	/// @reads global.current_set, global.current_set_item_index, global.playback_context, global.current_bpm, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.count_in_measures, global.swing_mult, global.gracenote_override_ms, global.loop_jump_to_selection
	/// @writes global.current_set, global.current_set_item_index, global.playback_context.mode, global.playback_context.segments
	/// @callers scr_button_write_setting_to_active_segment, scr_button_prepare_single_tune_playback_events
	function scr_button_get_active_settings_segment(_create_if_missing = false) {
		if (scr_button_is_set_mode()) {
			if (variable_global_exists("current_set")
				&& is_array(global.current_set)
				&& array_length(global.current_set) > 0
				&& variable_global_exists("current_set_item_index")
				&& global.current_set_item_index >= 0
				&& global.current_set_item_index < array_length(global.current_set)) {
				return global.current_set[global.current_set_item_index];
			}
			return undefined;
		}

		if (variable_global_exists("current_set")
			&& is_array(global.current_set)
			&& array_length(global.current_set) > 0
			&& variable_global_exists("current_set_item_index")
			&& global.current_set_item_index >= 0
			&& global.current_set_item_index < array_length(global.current_set)
			&& is_struct(global.current_set[global.current_set_item_index])) {
			var current_item = global.current_set[global.current_set_item_index];
			scr_button_sync_single_tune_settings_segment(current_item);
			return current_item;
		}

		if (variable_global_exists("playback_context")
			&& is_struct(global.playback_context)
			&& is_array(global.playback_context.segments)
			&& array_length(global.playback_context.segments) > 0
			&& is_struct(global.playback_context.segments[0])) {
			var ctx_item = global.playback_context.segments[0];
			scr_button_sync_single_tune_settings_segment(ctx_item);
			return ctx_item;
		}

		if (!_create_if_missing) return undefined;

		var seed_bpm = variable_global_exists("current_bpm") ? real(global.current_bpm) : 120;
		var seed_field_bpm = scr_button_get_bpm_from_bound_field(undefined);
		if (!is_undefined(seed_field_bpm)) seed_bpm = real(seed_field_bpm);

		var seed_metro_mode = variable_global_exists("metronome_mode") ? real(global.metronome_mode) : 0;
		var seed_metro_field = scr_button_find_field_by_ui_name("metro_field_1");
		if (seed_metro_field != noone && instance_exists(seed_metro_field)) {
			seed_metro_mode = real(scr_button_field_get(seed_metro_field, "field_value", seed_metro_mode));
		}

		var segment = {
			bpm: seed_bpm,
			metronome_mode: seed_metro_mode,
			metronome_pattern: variable_global_exists("metronome_pattern_selection") ? real(global.metronome_pattern_selection) : 0,
			metronome_volume: variable_global_exists("metronome_volume") ? real(global.metronome_volume) : 100,
			count_in_measures: variable_global_exists("count_in_measures") ? real(global.count_in_measures) : 0,
			swing_mult: variable_global_exists("swing_mult") ? real(global.swing_mult) : 0,
			gracenote_override_ms: variable_global_exists("gracenote_override_ms") ? real(global.gracenote_override_ms) : 0,
			loop_jump_to_selection: variable_global_exists("loop_jump_to_selection") ? (global.loop_jump_to_selection == true) : false
		};

		scr_button_sync_single_tune_settings_segment(segment);
		return segment;
	}

	/// @function scr_button_force_single_runtime_settings_sync()
	/// @description In single-tune mode, force the virtual one-tune set segment/context to match current runtime globals.
	/// @reads global.current_bpm, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.count_in_measures, global.loop_jump_to_selection, global.swing_mult, global.gracenote_override_ms
	/// @writes global.current_set, global.current_set_item_index, global.playback_context.segments
	/// @callers scr_tune_bpm_change, scr_gracenote_override_change, scr_swing_mult_change, scr_button_prepare_single_tune_playback_events, start_play
	function scr_button_force_single_runtime_settings_sync() {
		if (scr_button_is_set_mode()) return;

		var seg = scr_button_get_active_settings_segment(true);
		if (!is_struct(seg)) seg = {};

		seg.bpm = variable_global_exists("current_bpm") ? real(global.current_bpm) : real(scr_button_struct_get(seg, "bpm", 120));
		seg.metronome_mode = variable_global_exists("metronome_mode") ? real(global.metronome_mode) : real(scr_button_struct_get(seg, "metronome_mode", 0));
		seg.metronome_pattern = variable_global_exists("metronome_pattern_selection") ? real(global.metronome_pattern_selection) : real(scr_button_struct_get(seg, "metronome_pattern", 0));
		seg.metronome_volume = variable_global_exists("metronome_volume") ? real(global.metronome_volume) : real(scr_button_struct_get(seg, "metronome_volume", 100));
		seg.count_in_measures = variable_global_exists("count_in_measures") ? real(global.count_in_measures) : real(scr_button_struct_get(seg, "count_in_measures", 0));
		seg.loop_jump_to_selection = variable_global_exists("loop_jump_to_selection") ? (global.loop_jump_to_selection == true) : (scr_button_struct_get(seg, "loop_jump_to_selection", false) == true);
		seg.swing_mult = variable_global_exists("swing_mult") ? real(global.swing_mult) : real(scr_button_struct_get(seg, "swing_mult", scr_button_struct_get(seg, "swing", 0)));
		seg.gracenote_override_ms = variable_global_exists("gracenote_override_ms") ? real(global.gracenote_override_ms) : real(scr_button_struct_get(seg, "gracenote_override_ms", scr_button_struct_get(seg, "gracenote_ms", 0)));

		scr_button_sync_single_tune_settings_segment(seg);
	}

	/// @function scr_button_write_setting_to_active_segment(_key, _value)
	/// @description Write a setting key/value into the active segment for the current mode.
	/// @param {string} _key Setting key name (bpm, swing_mult, etc.)
	/// @param _value Setting value
	/// @returns {bool} True when write succeeded
	/// @reads global.current_set, global.current_set_item_index
	/// @writes global.current_set[idx], global.current_set_item_index, global.playback_context.segments[0]
	/// @callers scr_metronome_mode_change, scr_metronome_pattern_change, scr_metronome_volume_change, scr_tune_bpm_change, scr_tune_countin_change, scr_gracenote_override_change, scr_swing_mult_change
	function scr_button_write_setting_to_active_segment(_key, _value) {
		if (scr_button_is_set_mode()) {
			if (is_array(global.current_set)) {
				var idx = global.current_set_item_index;
				if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
					var item = global.current_set[idx];
					if (is_struct(item)) {
						scr_button_struct_set(item, _key, _value);
						global.current_set[idx] = item;
						return true;
					}
				}
			}
			return false;
		}

		var single_segment = scr_button_get_active_settings_segment(true);
		if (!is_struct(single_segment)) return false;
		scr_button_struct_set(single_segment, _key, _value);
		scr_button_sync_single_tune_settings_segment(single_segment);
		return true;
	}

	/// @function scr_button_resolve_effective_settings(_pull_live_fields)
	/// @description Resolve authoritative playback settings from the active segment, optionally overlaying visible UI field values.
	/// @param {bool} _pull_live_fields When true, field values from tune/metro controls override single-tune runtime values
	/// @returns {struct} Effective settings {bpm, swing_mult, gracenote_override_ms, metronome_mode, metronome_pattern, metronome_volume, count_in_measures, loop_jump_to_selection}
	/// @reads global.current_bpm, global.swing_mult, global.gracenote_override_ms, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.count_in_measures, global.loop_jump_to_selection
	/// @writes global.current_bpm, global.single_tune_runtime_bpm, global.swing_mult, global.gracenote_override_ms, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.count_in_measures, global.loop_jump_to_selection, global.current_set, global.current_set_item_index, global.playback_context.segments
	/// @callers scr_button_prepare_single_tune_playback_events, start_play
	function scr_button_resolve_effective_settings(_pull_live_fields = true) {
		var set_mode = scr_button_is_set_mode();
		var seg = scr_button_get_active_settings_segment(true);
		var out = {
			bpm: variable_global_exists("current_bpm") ? real(global.current_bpm) : 120,
			swing_mult: variable_global_exists("swing_mult") ? real(global.swing_mult) : 0,
			gracenote_override_ms: variable_global_exists("gracenote_override_ms") ? real(global.gracenote_override_ms) : 0,
			metronome_mode: variable_global_exists("metronome_mode") ? real(global.metronome_mode) : 0,
			metronome_pattern: variable_global_exists("metronome_pattern_selection") ? real(global.metronome_pattern_selection) : 0,
			metronome_volume: variable_global_exists("metronome_volume") ? real(global.metronome_volume) : 100,
			count_in_measures: variable_global_exists("count_in_measures") ? real(global.count_in_measures) : 0,
			loop_jump_to_selection: variable_global_exists("loop_jump_to_selection") ? (global.loop_jump_to_selection == true) : false
		};

		if (is_struct(seg)) {
			if (set_mode) {
				out.bpm = real(scr_button_struct_get(seg, "bpm", out.bpm));
				out.swing_mult = real(scr_button_struct_get(seg, "swing_mult", scr_button_struct_get(seg, "swing", out.swing_mult)));
				out.gracenote_override_ms = real(scr_button_struct_get(seg, "gracenote_override_ms", scr_button_struct_get(seg, "gracenote_ms", out.gracenote_override_ms)));
			}
			out.metronome_mode = real(scr_button_struct_get(seg, "metronome_mode", out.metronome_mode));
			out.metronome_pattern = real(scr_button_struct_get(seg, "metronome_pattern", out.metronome_pattern));
			out.metronome_volume = real(scr_button_struct_get(seg, "metronome_volume", out.metronome_volume));
			out.count_in_measures = real(scr_button_struct_get(seg, "count_in_measures", out.count_in_measures));
			out.loop_jump_to_selection = (scr_button_struct_get(seg, "loop_jump_to_selection", out.loop_jump_to_selection) == true);
		}

		if (_pull_live_fields && !set_mode) {
			var mode_field = scr_button_find_field_by_ui_name("metro_field_1");
			if (mode_field != noone && instance_exists(mode_field)) {
				out.metronome_mode = real(scr_button_field_get(mode_field, "field_value", out.metronome_mode));
			}

			var pattern_field = scr_button_find_field_by_ui_name("metro_field_2");
			if (pattern_field != noone && instance_exists(pattern_field)) {
				out.metronome_pattern = real(scr_button_field_get(pattern_field, "field_value", out.metronome_pattern));
			}

			var volume_field = scr_button_find_field_by_ui_name("metro_field_5");
			if (volume_field != noone && instance_exists(volume_field)) {
				out.metronome_volume = real(scr_button_field_get(volume_field, "field_value", out.metronome_volume));
			}

			var countin_field = scr_button_find_field_by_ui_name("metro_field_4");
			if (countin_field == noone) countin_field = scr_button_find_field_by_ui_name("tune_countin_field");
			if (countin_field != noone && instance_exists(countin_field)) {
				out.count_in_measures = real(scr_button_field_get(countin_field, "field_value", out.count_in_measures));
			}
		}

		out.bpm = max(1, real(out.bpm));
		out.swing_mult = max(0, real(out.swing_mult));
		out.gracenote_override_ms = max(0, real(out.gracenote_override_ms));
		out.metronome_mode = max(0, real(out.metronome_mode));
		out.metronome_pattern = max(0, real(out.metronome_pattern));
		out.metronome_volume = clamp(real(out.metronome_volume), 0, 127);
		out.count_in_measures = max(0, real(out.count_in_measures));

		global.current_bpm = out.bpm;
		if (!set_mode) global.single_tune_runtime_bpm = out.bpm;
		global.swing_mult = out.swing_mult;
		global.gracenote_override_ms = out.gracenote_override_ms;
		global.metronome_mode = out.metronome_mode;
		global.metronome_pattern_selection = out.metronome_pattern;
		global.metronome_volume = out.metronome_volume;
		global.count_in_measures = out.count_in_measures;
		global.loop_jump_to_selection = out.loop_jump_to_selection;

		if (is_struct(seg)) {
			seg.bpm = out.bpm;
			seg.swing_mult = out.swing_mult;
			seg.gracenote_override_ms = out.gracenote_override_ms;
			seg.metronome_mode = out.metronome_mode;
			seg.metronome_pattern = out.metronome_pattern;
			seg.metronome_volume = out.metronome_volume;
			seg.count_in_measures = out.count_in_measures;
			seg.loop_jump_to_selection = out.loop_jump_to_selection;
			if (!set_mode) {
				scr_button_sync_single_tune_settings_segment(seg);
			}
		}

		return out;
	}

	/// @function scr_button_bpm_debug_log(_line)
	/// @description Emit BPM diagnostics to Output and ALWAYS to dedicated bpm_trace.log file (independent of Logs toggle).
	/// @param {string} _line Text line to log
	/// @reads none
	/// @writes file at <primary_data_root>/debug/bpm_trace.log (append)
	/// @objects none
	/// @callers scr_tune_bpm_change, scr_button_prepare_single_tune_playback_events, start_play
	function scr_button_bpm_debug_log(_line) {
		var _msg = string(_line);
		diag_log_append_line(_msg, "bpm_trace.log", true);
	}

	/// @function scr_button_debug_get_root_dir()
	/// @description Resolve the debug export directory for loop/base planned-event snapshots.
	/// @returns {string} Absolute or runtime-relative folder path ending with '/'.
	/// @reads diag_log_get_debug_root (optional)
	/// @writes filesystem directory create (if missing)
	/// @objects none
	/// @callers scr_button_export_planned_events_snapshot
	function scr_button_debug_get_root_dir() {
		var root = "datafiles/debug/";
		if (is_undefined(diag_log_get_debug_root) == false) {
			root = string(diag_log_get_debug_root());
		}
		if (string_length(root) <= 0) root = "datafiles/debug/";
		var last_ch = string_copy(root, string_length(root), 1);
		if (last_ch != "/" && last_ch != "\\") root += "/";
		if (!directory_exists(root)) directory_create(root);
		return root;
	}

	/// @function scr_button_export_planned_events_snapshot(_events, _label, _run_id)
	/// @description Export planned events to CSV (event rows + per-measure summary) for side-by-side loop diagnostics.
	/// @param {array} _events Planned event array to export.
	/// @param {string} _label Snapshot label, e.g. "base" or "active_loop".
	/// @param {string} _run_id Stable run identifier to pair base/active exports.
	/// @returns {bool} true if export succeeded.
	/// @reads global.current_tune_name
	/// @writes files under datafiles/debug/loop_compare_*.csv
	/// @objects none
	/// @callers start_play
	function scr_button_export_planned_events_snapshot(_events, _label, _run_id) {
		if (!is_array(_events) || array_length(_events) <= 0) return false;
		var label = string(_label);
		if (label == "") label = "events";
		var run_id = string(_run_id);
		if (run_id == "") run_id = string(current_time);

		var root = scr_button_debug_get_root_dir();
		var tune_name = variable_global_exists("current_tune_name") ? string(global.current_tune_name) : "unknown";
		var safe_tune = string_replace_all(tune_name, " ", "_");
		safe_tune = string_replace_all(safe_tune, "/", "-");
		safe_tune = string_replace_all(safe_tune, "\\", "-");
		safe_tune = string_replace_all(safe_tune, ":", "-");

		var events_path = root + "loop_compare_events_" + safe_tune + "_" + run_id + "_" + label + ".csv";
		var summary_path = root + "loop_compare_summary_" + safe_tune + "_" + run_id + "_" + label + ".csv";

		var f = file_text_open_write(events_path);
		if (f < 0) return false;
		file_text_write_string(f,
			"idx,time_ms,measure,part,type,marker_type,note,channel,loop_iteration,loop_blank,loop_support_tail,owner_nav_idx,owner_measure,owner_part,owner_source,boundary_role,owner_label_mismatch\n");

		var summary_map = {};
		for (var i = 0; i < array_length(_events); i++) {
			var ev = _events[i];
			if (!is_struct(ev)) continue;
			var t = real(scr_button_struct_get(ev, "time", 0));
			var m = floor(real(scr_button_struct_get(ev, "measure", -1)));
			var p = max(1, floor(real(scr_button_struct_get(ev, "part", 1))));
			var typ = string(scr_button_struct_get(ev, "type", ""));
			var mt = string(scr_button_struct_get(ev, "marker_type", ""));
			var note = floor(real(scr_button_struct_get(ev, "note", -1)));
			var ch = floor(real(scr_button_struct_get(ev, "channel", -1)));
			var li = floor(real(scr_button_struct_get(ev, "loop_iteration", 0)));
			var lblank = scr_button_struct_get(ev, "loop_blank_measure", false) ? 1 : 0;
			var ltail = scr_button_struct_get(ev, "loop_support_tail", false) ? 1 : 0;
			var own_nav = floor(real(scr_button_struct_get(ev, "owner_nav_idx", -1)));
			var own_m = floor(real(scr_button_struct_get(ev, "owner_measure", -1)));
			var own_p = max(1, floor(real(scr_button_struct_get(ev, "owner_part", 1))));
			var own_src = string(scr_button_struct_get(ev, "owner_source", ""));
			var b_role = string(scr_button_struct_get(ev, "boundary_role", ""));
			var mismatch = scr_button_struct_get(ev, "owner_label_mismatch", false) ? 1 : 0;

			var line = string(i) + "," + string(t)
				+ "," + string(m)
				+ "," + string(p)
				+ "," + typ
				+ "," + mt
				+ "," + string(note)
				+ "," + string(ch)
				+ "," + string(li)
				+ "," + string(lblank)
				+ "," + string(ltail)
				+ "," + string(own_nav)
				+ "," + string(own_m)
				+ "," + string(own_p)
				+ "," + own_src
				+ "," + b_role
				+ "," + string(mismatch)
				+ "\n";
			file_text_write_string(f, line);

			var sk = string(p) + ":" + string(m);
			if (!variable_struct_exists(summary_map, sk)) {
				summary_map[$ sk] = {
					part: p,
					measure: m,
					event_count: 0,
					note_on_count: 0,
					note_off_count: 0,
					marker_count: 0,
					first_time_ms: t,
					last_time_ms: t,
					owner_mismatch_count: 0,
					support_tail_count: 0
				};
			}
			var sm = summary_map[$ sk];
			sm.event_count += 1;
			if (typ == "note_on") sm.note_on_count += 1;
			else if (typ == "note_off") sm.note_off_count += 1;
			else if (typ == "marker") sm.marker_count += 1;
			if (t < real(sm.first_time_ms)) sm.first_time_ms = t;
			if (t > real(sm.last_time_ms)) sm.last_time_ms = t;
			if (mismatch == 1) sm.owner_mismatch_count += 1;
			if (ltail == 1) sm.support_tail_count += 1;
			summary_map[$ sk] = sm;
		}
		file_text_close(f);

		var sf = file_text_open_write(summary_path);
		if (sf < 0) return false;
		file_text_write_string(sf,
			"part,measure,event_count,note_on_count,note_off_count,marker_count,first_time_ms,last_time_ms,owner_mismatch_count,support_tail_count\n");
		var skeys = variable_struct_get_names(summary_map);
		if (is_array(skeys) && array_length(skeys) > 1) {
			array_sort(skeys, function(a, b) {
				var sa = string(a);
				var sb = string(b);
				var cpa = string_pos(":", sa);
				var cpb = string_pos(":", sb);
				var pa = (cpa > 0) ? floor(real(string_copy(sa, 1, cpa - 1))) : 1;
				var pb = (cpb > 0) ? floor(real(string_copy(sb, 1, cpb - 1))) : 1;
				if (pa != pb) return pa - pb;
				var ma = (cpa > 0) ? floor(real(string_delete(sa, 1, cpa))) : floor(real(sa));
				var mb = (cpb > 0) ? floor(real(string_delete(sb, 1, cpb))) : floor(real(sb));
				return ma - mb;
			});
		}

		for (var si = 0; is_array(skeys) && si < array_length(skeys); si++) {
			var s_key = string(skeys[si]);
			if (!variable_struct_exists(summary_map, s_key)) continue;
			var row = summary_map[$ s_key];
			file_text_write_string(sf,
				string(scr_button_struct_get(row, "part", 1)) + ","
				+ string(scr_button_struct_get(row, "measure", -1)) + ","
				+ string(scr_button_struct_get(row, "event_count", 0)) + ","
				+ string(scr_button_struct_get(row, "note_on_count", 0)) + ","
				+ string(scr_button_struct_get(row, "note_off_count", 0)) + ","
				+ string(scr_button_struct_get(row, "marker_count", 0)) + ","
				+ string(scr_button_struct_get(row, "first_time_ms", 0)) + ","
				+ string(scr_button_struct_get(row, "last_time_ms", 0)) + ","
				+ string(scr_button_struct_get(row, "owner_mismatch_count", 0)) + ","
				+ string(scr_button_struct_get(row, "support_tail_count", 0))
				+ "\n");
		}
		file_text_close(sf);

		show_debug_message("[LOOP_COMPARE] Exported " + label + " events: " + events_path);
		show_debug_message("[LOOP_COMPARE] Exported " + label + " summary: " + summary_path);
		return true;
	}

	/// @function scr_button_apply_event_ownership_metadata(_events)
	/// @description Annotate planned events with canonical ownership metadata (part/measure/nav) and boundary role.
	/// @param {array} _events Planned event array to annotate in-place.
	/// @returns {struct} Annotation stats: {events, annotated, unresolved, nav_entries}
	/// @reads global.timeline_state.measure_ms, gv_build_measure_nav_map
	/// @writes _events[].owner_part/owner_measure/owner_nav_idx/owner_start_ms/owner_end_ms/boundary_role/exec_rank
	/// @objects none
	/// @callers scr_button_prepare_single_tune_playback_events, scr_button_loop_build_playback_events
	function scr_button_build_measure_nav_map_for_ownership(_events) {
		var out = { entries: [] };
		if (!is_array(_events) || array_length(_events) <= 0) return out;

		var measure_start_marker = {};
		var measure_start_any = {};
		var measure_part_map = {};
		var part_end_ms = {};

		for (var i = 0; i < array_length(_events); i++) {
			var ev = _events[i];
			if (!is_struct(ev)) continue;
			var ev_time = real(scr_button_struct_get(ev, "time", 0));
			var ev_measure = floor(real(scr_button_struct_get(ev, "measure", -1)));
			var ev_part = max(1, floor(real(scr_button_struct_get(ev, "part", 1))));
			var ev_iter = max(0, floor(real(scr_button_struct_get(ev, "loop_iteration", 0))));

			var part_key = string(ev_part);
			if (!variable_struct_exists(part_end_ms, part_key) || ev_time > real(part_end_ms[$ part_key])) {
				part_end_ms[$ part_key] = ev_time;
			}

			if (ev_measure < 1) continue;
			var pmk = string(ev_part) + ":" + string(ev_measure) + ":" + string(ev_iter);
			if (!variable_struct_exists(measure_start_any, pmk)
				|| ev_time < real(measure_start_any[$ pmk])) {
				measure_start_any[$ pmk] = ev_time;
				measure_part_map[$ pmk] = ev_part;
			}

			var ev_type = string(scr_button_struct_get(ev, "type", ""));
			if (ev_type != "marker") continue;
			var mk = string(scr_button_struct_get(ev, "marker_type", ""));
			var beat = floor(real(scr_button_struct_get(ev, "beat", 0)));
			var beat_frac = real(scr_button_struct_get(ev, "beat_fraction", 0));
			var is_boundary = (mk == "bar") || (mk == "beat" && beat == 1 && abs(beat_frac) <= 0.001);
			if (!is_boundary) continue;

			if (!variable_struct_exists(measure_start_marker, pmk)
				|| ev_time < real(measure_start_marker[$ pmk])) {
				measure_start_marker[$ pmk] = ev_time;
			}
		}

		var keys = variable_struct_get_names(measure_start_any);
		if (!is_array(keys) || array_length(keys) <= 0) return out;

		var entries = [];
		for (var ki = 0; ki < array_length(keys); ki++) {
			var key = string(keys[ki]);
			var cpos = string_pos(":", key);
			if (cpos <= 0) continue;
			var ptxt = string_copy(key, 1, cpos - 1);
			var rest = string_delete(key, 1, cpos);
			var cpos2 = string_pos(":", rest);
			if (cpos2 <= 0) continue;
			var mtxt = string_copy(rest, 1, cpos2 - 1);
			var itxt = string_delete(rest, 1, cpos2);
			var p = max(1, floor(real(ptxt)));
			var m = floor(real(mtxt));
			var iter = max(0, floor(real(itxt)));
			if (m < 1) continue;

			var s = variable_struct_exists(measure_start_marker, key)
				? real(measure_start_marker[$ key])
				: real(measure_start_any[$ key]);
			array_push(entries, {
				part: p,
				measure: m,
				loop_iteration: iter,
				start_ms: s,
				end_ms: s
			});
		}

		if (array_length(entries) <= 0) return out;
		array_sort(entries, function(a, b) {
			var ap = floor(real(scr_button_struct_get(a, "part", 1)));
			var bp = floor(real(scr_button_struct_get(b, "part", 1)));
			if (ap != bp) return ap - bp;
			var ai = max(0, floor(real(scr_button_struct_get(a, "loop_iteration", 0))));
			var bi = max(0, floor(real(scr_button_struct_get(b, "loop_iteration", 0))));
			if (ai != bi) return ai - bi;
			var as = real(scr_button_struct_get(a, "start_ms", 0));
			var bs = real(scr_button_struct_get(b, "start_ms", 0));
			if (as != bs) return as - bs;
			var am = floor(real(scr_button_struct_get(a, "measure", 0)));
			var bm = floor(real(scr_button_struct_get(b, "measure", 0)));
			return am - bm;
		});

		var fallback_measure_ms = (variable_global_exists("timeline_state")
			&& is_struct(global.timeline_state)
			&& variable_struct_exists(global.timeline_state, "measure_ms"))
			? max(1, real(global.timeline_state.measure_ms))
			: 1000;

		for (var ei = 0; ei < array_length(entries); ei++) {
			var cur = entries[ei];
			if (!is_struct(cur)) continue;
			var cur_p = max(1, floor(real(scr_button_struct_get(cur, "part", 1))));
			var cur_i = max(0, floor(real(scr_button_struct_get(cur, "loop_iteration", 0))));
			var cur_s = real(scr_button_struct_get(cur, "start_ms", 0));
			var end_ms = cur_s + fallback_measure_ms;
			var found_next = false;

			for (var ni = ei + 1; ni < array_length(entries); ni++) {
				var nxt = entries[ni];
				if (!is_struct(nxt)) continue;
				var nxt_p = max(1, floor(real(scr_button_struct_get(nxt, "part", 1))));
				var nxt_i = max(0, floor(real(scr_button_struct_get(nxt, "loop_iteration", 0))));
				if (nxt_p != cur_p) continue;
				if (nxt_i != cur_i) continue;
				end_ms = max(cur_s, real(scr_button_struct_get(nxt, "start_ms", cur_s)));
				found_next = true;
				break;
			}

			if (!found_next) {
				var pk = string(cur_p);
				if (variable_struct_exists(part_end_ms, pk)) {
					end_ms = max(end_ms, real(part_end_ms[$ pk]));
				}
			}

			cur.end_ms = end_ms;
			entries[ei] = cur;
		}

		out.entries = entries;
		return out;
	}

	function scr_button_apply_event_ownership_metadata(_events) {
		var stats = { events: 0, annotated: 0, unresolved: 0, nav_entries: 0 };
		if (!is_array(_events) || array_length(_events) <= 0) return stats;

		var nav_map = scr_button_build_measure_nav_map_for_ownership(_events);
		var nav_entries = (is_struct(nav_map)
			&& variable_struct_exists(nav_map, "entries")
			&& is_array(variable_struct_get(nav_map, "entries")))
			? variable_struct_get(nav_map, "entries")
			: [];

		var nav_index_by_part_measure = {};
		var nav_index_by_part_measure_iter = {};
		for (var ni = 0; ni < array_length(nav_entries); ni++) {
			var ne = nav_entries[ni];
			if (!is_struct(ne)) continue;
			var npm = floor(real(scr_button_struct_get(ne, "measure", -1)));
			var npp = max(1, floor(real(scr_button_struct_get(ne, "part", 1))));
			var npi = max(0, floor(real(scr_button_struct_get(ne, "loop_iteration", 0))));
			if (npm < 1) continue;
			var npk = string(npp) + ":" + string(npm);
			if (!variable_struct_exists(nav_index_by_part_measure, npk)) {
				nav_index_by_part_measure[$ npk] = ni;
			}
			var npki = npk + ":" + string(npi);
			if (!variable_struct_exists(nav_index_by_part_measure_iter, npki)) {
				nav_index_by_part_measure_iter[$ npki] = ni;
			}
		}

		stats.events = array_length(_events);
		stats.nav_entries = array_length(nav_entries);

		for (var ei = 0; ei < array_length(_events); ei++) {
			var ev = _events[ei];
			if (!is_struct(ev)) continue;

			var ev_type = string(scr_button_struct_get(ev, "type", ""));
			var ev_time = real(scr_button_struct_get(ev, "time", 0));
			var ev_measure = floor(real(scr_button_struct_get(ev, "measure", -1)));
			var ev_part = max(1, floor(real(scr_button_struct_get(ev, "part", 1))));
			var ev_iter = max(0, floor(real(scr_button_struct_get(ev, "loop_iteration", 0))));

			var exec_rank = 3;
			if (ev_type == "note_off") exec_rank = 0;
			else if (ev_type == "marker") exec_rank = 1;
			else if (ev_type == "note_on") exec_rank = 2;

			var owner_nav_idx = -1;
			var owner_part = ev_part;
			var owner_measure = ev_measure;
			var owner_start_ms = ev_time;
			var owner_end_ms = ev_time;
			var owner_source = "none";
			var source_measure = ev_measure;

			if (array_length(nav_entries) > 0) {
				for (var si = 0; si < array_length(nav_entries); si++) {
					var se = nav_entries[si];
					if (!is_struct(se)) continue;
					var s_part = max(1, floor(real(scr_button_struct_get(se, "part", 1))));
					var s_iter = max(0, floor(real(scr_button_struct_get(se, "loop_iteration", 0))));
					if (s_part != ev_part) continue;
					if (s_iter != ev_iter) continue;
					var s_start = real(scr_button_struct_get(se, "start_ms", 0));
					var s_end = real(scr_button_struct_get(se, "end_ms", s_start));
					if (ev_time >= s_start && ev_time < s_end) {
						owner_nav_idx = si;
						owner_source = "time_window";
						break;
					}
				}
			}

			if (owner_nav_idx < 0 && ev_measure >= 1) {
				var pmk = string(ev_part) + ":" + string(ev_measure);
				var pmki = pmk + ":" + string(ev_iter);
				if (variable_struct_exists(nav_index_by_part_measure_iter, pmki)) {
					owner_nav_idx = floor(real(nav_index_by_part_measure_iter[$ pmki]));
					owner_source = "measure_label_iter";
				} else if (variable_struct_exists(nav_index_by_part_measure, pmk)) {
					owner_nav_idx = floor(real(nav_index_by_part_measure[$ pmk]));
					owner_source = "measure_label";
				}
			}

			if (owner_nav_idx >= 0 && owner_nav_idx < array_length(nav_entries)) {
				var oe = nav_entries[owner_nav_idx];
				if (is_struct(oe)) {
					owner_part = max(1, floor(real(scr_button_struct_get(oe, "part", ev_part))));
					owner_measure = floor(real(scr_button_struct_get(oe, "measure", ev_measure)));
					owner_start_ms = real(scr_button_struct_get(oe, "start_ms", ev_time));
					owner_end_ms = real(scr_button_struct_get(oe, "end_ms", owner_start_ms));
				}
			}

			var boundary_role = "outside_next";
			if (variable_struct_exists(ev, "loop_boundary") && bool(ev.loop_boundary) && ev_type == "note_off") {
				boundary_role = "boundary_cleanup";
			} else if (owner_nav_idx >= 0) {
				if (abs(ev_time - owner_start_ms) <= 0.001) boundary_role = "inside_start";
				else boundary_role = "inside_body";
			}

			ev.exec_rank = exec_rank;
			ev.owner_nav_idx = owner_nav_idx;
			ev.owner_part = owner_part;
			ev.owner_measure = owner_measure;
			ev.owner_start_ms = owner_start_ms;
			ev.owner_end_ms = owner_end_ms;
			ev.boundary_role = boundary_role;
			ev.owner_source = owner_source;
			ev.source_measure = source_measure;
			ev.owner_label_mismatch = (source_measure >= 1 && owner_measure >= 1 && source_measure != owner_measure);

			_events[ei] = ev;
			if (owner_nav_idx >= 0) stats.annotated += 1;
			else stats.unresolved += 1;
		}

		return stats;
	}

	/// @function scr_button_canonicalize_event_measure_labels(_events)
	/// @description Rewrite event measure/part labels from ownership metadata when available so downstream systems consume one canonical identity.
	/// @param {array} _events Planned events array.
	/// @returns {struct} Stats: {events, relabeled, marker_relabeled}
	/// @reads _events[].owner_measure, _events[].owner_part
	/// @writes _events[].measure, _events[].part, _events[].source_measure (when absent)
	/// @callers scr_button_prepare_single_tune_playback_events, scr_button_loop_build_playback_events
	function scr_button_canonicalize_event_measure_labels(_events) {
		var stats = { events: 0, relabeled: 0, marker_relabeled: 0 };
		if (!is_array(_events) || array_length(_events) <= 0) return stats;

		stats.events = array_length(_events);
		for (var i = 0; i < array_length(_events); i++) {
			var ev = _events[i];
			if (!is_struct(ev)) continue;

			var src_measure = floor(real(scr_button_struct_get(ev, "measure", -1)));
			var src_part = max(1, floor(real(scr_button_struct_get(ev, "part", 1))));
			var own_measure = floor(real(scr_button_struct_get(ev, "owner_measure", src_measure)));
			var own_part = max(1, floor(real(scr_button_struct_get(ev, "owner_part", src_part))));

			if (!variable_struct_exists(ev, "source_measure")) {
				ev.source_measure = src_measure;
			}

			if (own_measure >= 1 && (own_measure != src_measure || own_part != src_part)) {
				ev.measure = own_measure;
				ev.part = own_part;
				stats.relabeled += 1;
				if (string(scr_button_struct_get(ev, "type", "")) == "marker") {
					stats.marker_relabeled += 1;
				}
			}

			// Keep mismatch diagnostics aligned with the final canonical label, while
			// retaining source_measure for provenance in debug exports.
			var final_measure = floor(real(scr_button_struct_get(ev, "measure", src_measure)));
			var final_part = max(1, floor(real(scr_button_struct_get(ev, "part", src_part))));
			ev.owner_label_mismatch = (final_measure >= 1 && own_measure >= 1)
				? (final_measure != own_measure || final_part != own_part)
				: false;

			_events[i] = ev;
		}

		return stats;
	}

	/// @function scr_button_reset_loop_state()
	/// @description Reset all loop runtime globals and clear loop-related timeline_state entries.
	/// @writes global.loop_mode_enabled, global.loop_runtime_active, global.loop_runtime_current_iteration, global.loop_runtime_repeat_total, global.loop_runtime_blank_measure, global.playback_events_active
	/// @writes global.timeline_state.measure_nav_entries, global.timeline_state.loop_runtime_cache, global.timeline_state.loop_session, global.timeline_state.loop_selected_measures, global.timeline_state.loop_blank_measure
	/// @callers scr_goto_playroom, scr_goto_mainmenu
	function scr_button_reset_loop_state() {
		global.loop_mode_enabled = false;
		global.loop_runtime_active = false;
		global.loop_runtime_current_iteration = 0;
		global.loop_runtime_repeat_total = 0;
		global.loop_runtime_blank_measure = false;
		global.playback_events_active = [];

		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			global.timeline_state.measure_nav_entries = [];
			global.timeline_state.measure_nav_parts = [];
			global.timeline_state.measure_nav_pickup_by_part = {};
			global.timeline_state.loop_runtime_cache = { valid: false, measure_starts: [] };
			global.timeline_state.loop_session = {
				active: false,
				selected_refs: [],
				loop_start_boundary: {},
				loop_end_boundary: {},
				boundary_refinement: {},
				timeline_segments: [],
				start_ms: 0,
				end_ms: 0,
				pass_duration_ms: 0,
				passes_total: 0,
				passes_completed: 0,
				spacer_enabled: false,
				spacer_duration_ms: 0,
				jump_enabled: false,
				phase: "complete",
				current_pass_index: 0,
				phase_start_ms: 0,
				phase_end_ms: 0,
				pickup_mode: "none",
				degraded: false
			};
			global.timeline_state.measure_nav_tile_hitboxes = [];
			global.timeline_state.measure_nav_controls = {};

			if (is_undefined(gv_loop_clear_selected_measures) == false) {
				gv_loop_clear_selected_measures();
			} else {
				global.timeline_state.loop_selected_measures = {};
				global.timeline_state.loop_last_selected_measure = -1;
			}

			if (is_undefined(gv_loop_set_blank_measure_enabled) == false) {
				gv_loop_set_blank_measure_enabled(false);
			} else {
				global.timeline_state.loop_blank_measure = false;
			}

			global.timeline_state.loop_boundary_refinement = {
				enabled: false,
				start_part: 1,
				start_measure: -1,
				start_beat: 1,
				start_beat_fraction: 0,
				end_part: 1,
				end_measure: -1,
				end_beat: 1,
				end_beat_fraction: 0
			};
		}
	}

	/// @function scr_button_reset_play_session_state()
	/// @description Full gameplay/session reset used when leaving play and returning to menu.
	/// @reads global.tune, global.timeline_state
	/// @writes global.loop_mode_enabled, global.playback_events, global.playback_events_active, global.current_set, global.current_set_item_index, global.current_tune_filename, global.tune_selection, global.selected_tune_time_sig, global.pending_auto_start_play, global.scoring_last_run
	/// @writes global.timeline_state (active/playback/score/loop fields), global.tune_event_groups, global.tune_group_index, global.tune_scheduler_active, global.tune_timer
	/// @objects obj_tune, obj_tune_picker
	/// @callers scr_goto_mainmenu
	function scr_button_reset_play_session_state() {
		// Stop any active scheduler/timer so no stale callbacks survive room switches.
		if (variable_global_exists("tune_timer") && global.tune_timer != noone) {
			time_source_stop(global.tune_timer);
			global.tune_timer = noone;
		}
		global.tune_scheduler_active = false;
		global.tune_scheduler_mode_step = false;
		global.tune_event_groups = [];
		global.tune_group_index = 0;
		global.tune_start_real = 0;
		global.tune_deferred_queue = [];
		global.tune_deferred_head = 0;

		global.playback_events = [];
		global.playback_events_active = [];

		// Reset single-tune + set state so a new play flow always starts clean.
		if (script_exists(asset_get_index("scr_set_init_global"))) {
			scr_set_init_global();
		}
		global.current_set = [];
		global.current_set_item_index = -1;
		global.current_tune_filename = "";
		global.tune_selection = -1;
		global.selected_tune_time_sig = "";

		// Clear loaded tune payload to prevent stale tune reuse.
		if (variable_global_exists("tune") && instance_exists(global.tune)
			&& variable_instance_exists(global.tune, "tune_data")) {
			var _tune_data_reset = variable_instance_get(global.tune, "tune_data");
			if (is_struct(_tune_data_reset)) {
				_tune_data_reset.tune_metadata = {};
				_tune_data_reset.performance = {};
				_tune_data_reset.metronome = {};
				_tune_data_reset.events = [];
				_tune_data_reset.event_count = 0;
				_tune_data_reset.is_loaded = false;
				_tune_data_reset.filename = "";
				variable_instance_set(global.tune, "tune_data", _tune_data_reset);
			}
		}

		// Reset picker selection visuals/state if picker exists.
		var _picker = instance_find(obj_tune_picker, 0);
		if (_picker != noone && is_undefined(scr_tune_picker_clear_selection) == false) {
			scr_tune_picker_clear_selection();
			if (is_undefined(scr_tune_picker_sync_selected_entry_ui) == false) {
				scr_tune_picker_sync_selected_entry_ui();
			}
		}

		// Reset scoring/timeline runtime overlays and loop-score data.
		global.scoring_last_run = undefined;
		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			global.timeline_state.active = false;
			global.timeline_state.playback_complete = false;
			global.timeline_state.playhead_ms = 0;
			global.timeline_state.start_clock_ms = current_time;
			global.timeline_state.current_measure = 0;
			global.timeline_state.last_dispatched_expected_ms = 0;
			global.timeline_state.tune_played = [];
			global.timeline_state.player_in = [];
			global.timeline_state.review_full_trace = [];
			global.timeline_state.score_by_segment = [];
			global.timeline_state.score_measure_maps_by_key = {};
			global.timeline_state.score_popup_measure = -1;
			global.timeline_state.score_popup_measure_key = "";
			global.timeline_state.score_popup_nav_idx = -1;
			global.timeline_state.score_detail_popup = false;
			global.timeline_state.loop_iteration_scores = [];
		}

		scr_button_reset_loop_state();

		// Force close floating gameplay windows.
		var _layers = ["judge_settings_layer", "player_window_layer", "loop_score_overview_layer"];
		for (var _li = 0; _li < array_length(_layers); _li++) {
			var _lid = layer_get_id(_layers[_li]);
			if (_lid != -1) {
				layer_set_visible(_lid, false);
				instance_deactivate_layer(_lid);
			}
		}

		global.gameinfo_title[0] = "No tune selected";
		global.pending_auto_start_play = false;
	}

	/// @function scr_button_loop_build_playback_events(_base_events)
	/// @description Expand the base playback event array into a looped sequence based on selected measures using half-open loop ownership and deterministic same-timestamp ordering.
	/// @param _base_events Base MIDI event array from scr_goto_playroom preprocessing
	/// @returns Expanded event array, or _base_events unmodified if loop is off or no measures selected
	/// @reads global.loop_mode_enabled, global.loop_repeat_total, global.METRONOME_CONFIG, global.timeline_state, global.score_has_pickup
	/// @writes global.loop_runtime_active, global.loop_runtime_repeat_total, global.loop_runtime_blank_measure, global.loop_runtime_jump_to_selection, global.timeline_state.loop_session
	/// @callers start_play (when loop mode is enabled)
	function scr_button_loop_build_playback_events(_base_events) {
		if (!is_array(_base_events) || array_length(_base_events) <= 0) return _base_events;
		if (!variable_global_exists("loop_mode_enabled") || !global.loop_mode_enabled) return _base_events;
		if (is_undefined(gv_loop_get_selected_measures)) return _base_events;

		var selected_refs = [];
		if (is_undefined(gv_loop_get_selected_measure_refs) == false) {
			selected_refs = gv_loop_get_selected_measure_refs();
		}
		if (!is_array(selected_refs) || array_length(selected_refs) <= 0) {
			var selected = gv_loop_get_selected_measures();
			if (is_array(selected) && array_length(selected) > 0) {
				for (var sfi = 0; sfi < array_length(selected); sfi++) {
					var sm = floor(real(selected[sfi]));
					if (sm < 1) continue;
					array_push(selected_refs, { part: 1, measure: sm, key: "1:" + string(sm) });
				}
			}
		}
		if (!is_array(selected_refs) || array_length(selected_refs) <= 0) {
			show_debug_message("[LOOP] Loop mode ON but no measures selected; using normal playback.");
			return _base_events;
		}

		var repeat_total = variable_global_exists("loop_repeat_total")
			? max(1, floor(real(global.loop_repeat_total)))
			: 10;
		var blank_enabled = (is_undefined(gv_loop_blank_measure_enabled) == false) && gv_loop_blank_measure_enabled();
		var jump_to_selection = variable_global_exists("loop_jump_to_selection") && global.loop_jump_to_selection;
		var metro_channel = (variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG))
			? floor(real(global.METRONOME_CONFIG.channel ?? 9))
			: 9;

		var tune_start_ms = 1000000000000;
		for (var tsi = 0; tsi < array_length(_base_events); tsi++) {
			var tev = _base_events[tsi];
			if (!is_struct(tev)) continue;
			var tm = floor(real(scr_button_struct_get(tev, "measure", -1)));
			var tt = real(scr_button_struct_get(tev, "time", 0));
			if (tm >= 1 && tt < tune_start_ms) tune_start_ms = tt;
		}
		if (tune_start_ms > 999999999999) tune_start_ms = 0;

		var loop_boundary_ctx = {
			valid: false,
			start_ms: -1,
			end_ms: -1,
			source: "none",
			start_boundary: {},
			end_boundary: {}
		};
		if (is_undefined(gv_loop_resolve_boundary_endpoints) == false) {
			var _resolved = gv_loop_resolve_boundary_endpoints(selected_refs);
			if (is_struct(_resolved)) loop_boundary_ctx = _resolved;
		}

		var loop_start = 1000000000000;
		var loop_end = -1000000000000;
		if (bool(scr_button_struct_get(loop_boundary_ctx, "valid", false))) {
			loop_start = real(scr_button_struct_get(loop_boundary_ctx, "start_ms", loop_start));
			loop_end = real(scr_button_struct_get(loop_boundary_ctx, "end_ms", loop_end));
		}
		if (loop_start > 999999999999 || loop_end <= loop_start + 0.001) {
			for (var sri = 0; sri < array_length(selected_refs); sri++) {
				var sref = selected_refs[sri];
				if (!is_struct(sref)) continue;
				var s_start = real(scr_button_struct_get(sref, "timeline_start_ms", scr_button_struct_get(sref, "start_ms", -1)));
				var s_end = real(scr_button_struct_get(sref, "timeline_end_ms", scr_button_struct_get(sref, "end_ms", -1)));
				if (s_start < 0 || s_end <= s_start + 0.001) {
					s_start = real(scr_button_struct_get(sref, "start_ms", -1));
					s_end = real(scr_button_struct_get(sref, "end_ms", -1));
				}
				if (s_start >= 0 && s_end > s_start + 0.001) {
					if (s_start < loop_start) loop_start = s_start;
					if (s_end > loop_end) loop_end = s_end;
				}
			}
		}

		if (loop_start > 999999999999 || loop_end <= loop_start + 0.001) {
			var selected_map = {};
			for (var smi = 0; smi < array_length(selected_refs); smi++) {
				var sr = selected_refs[smi];
				if (!is_struct(sr)) continue;
				var sm = floor(real(sr.measure ?? -1));
				var sp = max(1, floor(real(sr.part ?? 1)));
				if (sm < 1) continue;
				selected_map[$ string(sp) + ":" + string(sm)] = true;
			}
			for (var bi = 0; bi < array_length(_base_events); bi++) {
				var bev = _base_events[bi];
				if (!is_struct(bev)) continue;
				var bm = floor(real(scr_button_struct_get(bev, "measure", -1)));
				var bp = max(1, floor(real(scr_button_struct_get(bev, "part", 1))));
				if (bm < 1) continue;
				var bkey = string(bp) + ":" + string(bm);
				if (!(variable_struct_exists(selected_map, bkey) && selected_map[$ bkey])) continue;
				var bt = real(scr_button_struct_get(bev, "time", 0));
				if (bt < loop_start) loop_start = bt;
				if (bt > loop_end) loop_end = bt;
			}
			if (loop_start < 999999999999 && loop_end > loop_start) {
				loop_end += 1;
			}
		}

		if (loop_start > 999999999999 || loop_end <= loop_start + 0.001) {
			show_debug_message("[LOOP] Unable to resolve canonical selected window; using normal playback.");
			return _base_events;
		}

		var selected_owner_nav_count = 0;
		for (var sni = 0; sni < array_length(selected_refs); sni++) {
			var snr = selected_refs[sni];
			if (!is_struct(snr)) continue;
			var sn_owner_nav = floor(real(scr_button_struct_get(snr, "owner_nav_idx", -1)));
			if (sn_owner_nav >= 0) selected_owner_nav_count += 1;
		}

		var measure_duration_ms = (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
			&& variable_struct_exists(global.timeline_state, "measure_ms"))
			? max(1, real(global.timeline_state.measure_ms))
			: 2000;
		var boundary_times = [];
		for (var mti = 0; mti < array_length(_base_events); mti++) {
			var mev = _base_events[mti];
			if (!is_struct(mev)) continue;
			if (string(scr_button_struct_get(mev, "type", "")) != "marker") continue;
			var mk = string(scr_button_struct_get(mev, "marker_type", ""));
			var mb = floor(real(scr_button_struct_get(mev, "beat", 0)));
			var mf = real(scr_button_struct_get(mev, "beat_fraction", 0));
			if (!((mk == "bar") || (mk == "beat" && mb == 1 && abs(mf) <= 0.001))) continue;
			array_push(boundary_times, real(scr_button_struct_get(mev, "time", 0)));
		}
		if (array_length(boundary_times) > 1) array_sort(boundary_times, function(a, b) { return a - b; });
		for (var bti = 0; bti < array_length(boundary_times) - 1; bti++) {
			var b0 = real(boundary_times[bti]);
			var b1 = real(boundary_times[bti + 1]);
			if (b0 >= loop_start - 0.001 && b1 > b0 + 0.001) {
				measure_duration_ms = max(1, b1 - b0);
				break;
			}
		}

		var prefix_events = [];
		var prefix_min_t = 1000000000000;
		var prefix_max_t = 0;
		var loop_template = [];
		var loop_window_raw_count = 0;
		var loop_window_selected_count = 0;
		for (var ei = 0; ei < array_length(_base_events); ei++) {
			var ev = _base_events[ei];
			if (!is_struct(ev)) continue;
			var ev_time = real(scr_button_struct_get(ev, "time", 0));
			var ev_type = string(scr_button_struct_get(ev, "type", ""));

			if (ev_time < loop_start) {
				var include_prefix = !jump_to_selection;
				if (jump_to_selection) {
					var ev_marker_prefix = string(scr_button_struct_get(ev, "marker_type", ""));
					var ev_channel_prefix = floor(real(scr_button_struct_get(ev, "channel", -1)));
					var is_countin_marker = (ev_type == "marker" && ev_marker_prefix == "countin_beat");
					var is_countin_metro = (ev_time < tune_start_ms)
						&& (ev_type == "note_on" || ev_type == "note_off")
						&& (ev_channel_prefix == metro_channel);
					include_prefix = is_countin_marker || is_countin_metro;
				}
				if (include_prefix) {
					var pcp = scr_button_clone_struct(ev);
					array_push(prefix_events, pcp);
					if (ev_time < prefix_min_t) prefix_min_t = ev_time;
					if (ev_time > prefix_max_t) prefix_max_t = ev_time;
				}
			}
		}

		var _manifest = undefined;
		var _loop_manifest_fn = asset_get_index("loop_build_manifest");
		if (script_exists(_loop_manifest_fn) && array_length(selected_refs) > 0) {
			var _m_start_ref = selected_refs[0];
			var _m_end_ref = selected_refs[array_length(selected_refs) - 1];
			_manifest = script_execute(_loop_manifest_fn, _m_start_ref, _m_end_ref, {
				events: _base_events,
				start_ms: loop_start,
				end_ms: loop_end,
				metro_channel: metro_channel,
				run_parity_check: true,
				parity_debug_dump: variable_global_exists("LOOP_COMPARE_DUMP_ENABLED") && bool(global.LOOP_COMPARE_DUMP_ENABLED)
			});
		}

		if (!(is_struct(_manifest) && bool(_manifest[$ "valid"] ?? false))) {
			show_debug_message("[LOOP_V3] Manifest unavailable/invalid; aborting loop payload build.");
			return _base_events;
		}

		var loop_boundary_note_offs = _manifest[$ "cleanup_events"] ?? [];
		loop_template = _manifest[$ "window_events"] ?? [];
		loop_window_raw_count = array_length(loop_template);
		loop_window_selected_count = array_length(loop_template);

		if (array_length(loop_template) <= 0) return _base_events;
		if (prefix_min_t > 999999999999) prefix_min_t = 0;

		var spacer_template = [];
		if (blank_enabled) {
			var spacer_end = loop_start + measure_duration_ms;
			for (var si = 0; si < array_length(_base_events); si++) {
				var sev = _base_events[si];
				if (!is_struct(sev)) continue;
				var st = real(scr_button_struct_get(sev, "time", 0));
				if (st < loop_start || st >= spacer_end) continue;
				var sty = string(scr_button_struct_get(sev, "type", ""));
				var sch = floor(real(scr_button_struct_get(sev, "channel", -1)));
				if ((sty == "note_on" || sty == "note_off") && sch == metro_channel) {
					var scp = scr_button_clone_struct(sev);
					scp.measure = 0;
					array_push(spacer_template, scp);
				}
			}
		}

		var out = [];
		for (var pre_i = 0; pre_i < array_length(prefix_events); pre_i++) {
			var pev = prefix_events[pre_i];
			pev.time = real(scr_button_struct_get(pev, "time", 0)) - prefix_min_t;
			pev.loop_iteration = 0;
			pev.loop_phase = "prelude";
			array_push(out, pev);
		}

		var cursor_time = 0;
		if (jump_to_selection) {
			if (array_length(prefix_events) > 0) {
				cursor_time = max(0, prefix_max_t - prefix_min_t + 1);
			}
		} else {
			cursor_time = max(0, loop_start - prefix_min_t);
		}
		var loop_pass_start_ms = cursor_time;
		var loop_core_duration_ms = max(1, loop_end - loop_start);
		var iteration_duration = loop_core_duration_ms;
		var loop_pass_manifest = [];

		for (var iter = 1; iter <= repeat_total; iter++) {
			if (iter > 1 && blank_enabled && array_length(spacer_template) > 0) {
				for (var spi = 0; spi < array_length(spacer_template); spi++) {
					var s_ev = scr_button_clone_struct(spacer_template[spi]);
					s_ev.time = cursor_time + (real(scr_button_struct_get(s_ev, "time", 0)) - loop_start);
					s_ev.loop_iteration = iter;
					s_ev.loop_phase = "spacer";
					s_ev.loop_blank_measure = true;
					array_push(out, s_ev);
				}
				cursor_time += measure_duration_ms;
			}

			var pass_start_ms = cursor_time;
			var pass_note_on = 0;
			var pass_note_off = 0;
			var pass_marker = 0;

			for (var li = 0; li < array_length(loop_template); li++) {
				var lev = scr_button_clone_struct(loop_template[li]);
				lev.time = cursor_time + (real(scr_button_struct_get(lev, "time", 0)) - loop_start);
				lev.loop_iteration = iter;
				lev.loop_pass_index = iter;
				lev.loop_pass_time_ms = max(0, lev.time - pass_start_ms);
				lev.loop_cycle_time_ms = lev.loop_pass_time_ms;
				lev.loop_phase = "pass";
				array_push(out, lev);
				var lty = string(scr_button_struct_get(lev, "type", ""));
				if (lty == "note_on") pass_note_on += 1;
				else if (lty == "note_off") pass_note_off += 1;
				else if (lty == "marker") pass_marker += 1;
			}

			cursor_time += iteration_duration;
			var boundary_time = max(0, cursor_time);
			for (var boi = 0; boi < array_length(loop_boundary_note_offs); boi++) {
				var boff = scr_button_clone_struct(loop_boundary_note_offs[boi]);
				boff.time = boundary_time;
				boff.loop_iteration = iter;
				boff.loop_pass_index = iter;
				boff.loop_pass_time_ms = max(0, boff.time - pass_start_ms);
				boff.loop_cycle_time_ms = boff.loop_pass_time_ms;
				boff.loop_phase = "pass";
				boff.loop_boundary = true;
				array_push(out, boff);
				pass_note_off += 1;
			}

			array_push(loop_pass_manifest, {
				pass_index: iter,
				pass_start_ms: pass_start_ms,
				pass_end_ms: boundary_time,
				selected_start_ms: pass_start_ms,
				selected_end_ms: pass_start_ms + loop_core_duration_ms,
				expected_note_on: pass_note_on,
				expected_note_off: pass_note_off,
				expected_marker: pass_marker
			});
		}

		array_sort(out, function(a, b) {
			var ta = real(scr_button_struct_get(a, "time", 0));
			var tb = real(scr_button_struct_get(b, "time", 0));
			if (ta != tb) return ta - tb;
			var type_a = string(scr_button_struct_get(a, "type", ""));
			var type_b = string(scr_button_struct_get(b, "type", ""));
			var pri_a = 3;
			var pri_b = 3;
			if (type_a == "note_off") pri_a = 0;
			else if (type_a == "marker") pri_a = 1;
			else if (type_a == "note_on") pri_a = 2;
			if (type_b == "note_off") pri_b = 0;
			else if (type_b == "marker") pri_b = 1;
			else if (type_b == "note_on") pri_b = 2;
			if (pri_a != pri_b) return pri_a - pri_b;
			return 0;
		});

		global.loop_runtime_active = true;
		global.loop_runtime_repeat_total = repeat_total;
		global.loop_runtime_blank_measure = blank_enabled;
		global.loop_runtime_jump_to_selection = jump_to_selection;

		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			var _resolved_refs = [];
			var _timeline_segments = [];
			var _segment_seq = 0;
			var _src_loop_start = loop_start;
			var _src_loop_end = loop_end;
			for (var srr_i = 0; srr_i < array_length(selected_refs); srr_i++) {
				var srr = selected_refs[srr_i];
				if (!is_struct(srr)) continue;
				var _m = floor(real(scr_button_struct_get(srr, "measure", -1)));
				var _p = max(1, floor(real(scr_button_struct_get(srr, "part", 1))));
				if (_m < 1) continue;
				var _orig_timeline_start = real(scr_button_struct_get(srr, "timeline_start_ms", scr_button_struct_get(srr, "start_ms", -1)));
				var _orig_timeline_end = real(scr_button_struct_get(srr, "timeline_end_ms", scr_button_struct_get(srr, "end_ms", -1)));
				var _orig_start = _orig_timeline_start;
				var _orig_end = _orig_timeline_end;
				if (_orig_start < 0 || _orig_end <= _orig_start + 0.001) {
					_orig_start = real(scr_button_struct_get(srr, "start_ms", -1));
					_orig_end = real(scr_button_struct_get(srr, "end_ms", -1));
				}
				var _orig_owner_start = real(scr_button_struct_get(srr, "owner_start_ms", -1));
				var _orig_owner_end = real(scr_button_struct_get(srr, "owner_end_ms", -1));
				var _owner_nav_idx = floor(real(scr_button_struct_get(srr, "owner_nav_idx", -1)));
				var _nav_idx = floor(real(scr_button_struct_get(srr, "nav_idx", -1)));
				var _runtime_start = -1;
				var _runtime_end = -1;
				var _runtime_owner_start = -1;
				var _runtime_owner_end = -1;
				var _clip_start = _orig_start;
				var _clip_end = _orig_end;
				if (_clip_start >= 0 && _clip_end > _clip_start + 0.001) {
					_clip_start = max(_clip_start, _src_loop_start);
					_clip_end = min(_clip_end, _src_loop_end);
				}
				if (_clip_start >= 0 && _clip_end > _clip_start + 0.001) {
					_runtime_start = loop_pass_start_ms + (_clip_start - loop_start);
					_runtime_end = loop_pass_start_ms + (_clip_end - loop_start);
				}
				if (_orig_owner_start >= 0 && _orig_owner_end > _orig_owner_start + 0.001) {
					var _owner_clip_start = max(_orig_owner_start, _src_loop_start);
					var _owner_clip_end = min(_orig_owner_end, _src_loop_end);
					if (_owner_clip_end > _owner_clip_start + 0.001) {
						_runtime_owner_start = loop_pass_start_ms + (_owner_clip_start - loop_start);
						_runtime_owner_end = loop_pass_start_ms + (_owner_clip_end - loop_start);
					}
				}
				if (_runtime_end <= _runtime_start + 0.001) continue;
				array_push(_resolved_refs, {
					part: _p,
					measure: _m,
					nav_idx: _nav_idx,
					owner_nav_idx: _owner_nav_idx,
					timeline_start_ms: _runtime_start,
					timeline_end_ms: _runtime_end,
					owner_start_ms: _runtime_owner_start,
					owner_end_ms: _runtime_owner_end,
					start_ms: _runtime_start,
					end_ms: _runtime_end,
					source_start_ms: _orig_start,
					source_end_ms: _orig_end,
					source_clip_start_ms: _clip_start,
					source_clip_end_ms: _clip_end,
					source_owner_start_ms: _orig_owner_start,
					source_owner_end_ms: _orig_owner_end
				});

				if (_runtime_start >= 0 && _runtime_end > _runtime_start + 0.001) {
					array_push(_timeline_segments, {
						seq: _segment_seq,
						part: _p,
						measure: _m,
						timeline_measure: _m,
						owner_measure: _m,
						nav_idx: _nav_idx,
						owner_nav_idx: _owner_nav_idx,
						start_ms: _runtime_start,
						end_ms: _runtime_end,
						segment_kind: "core"
					});
					_segment_seq += 1;
				}
			}

			if (array_length(_timeline_segments) > 1) {
				array_sort(_timeline_segments, function(a, b) {
					var as = real(scr_button_struct_get(a, "start_ms", 0));
					var bs = real(scr_button_struct_get(b, "start_ms", 0));
					if (as != bs) return as - bs;
					var an = floor(real(scr_button_struct_get(a, "seq", 0)));
					var bn = floor(real(scr_button_struct_get(b, "seq", 0)));
					return an - bn;
				});
			}

			var loop_pass_end_ms = loop_pass_start_ms + iteration_duration;
			var _session_refine = (variable_struct_exists(global.timeline_state, "loop_boundary_refinement")
				&& is_struct(global.timeline_state.loop_boundary_refinement))
				? global.timeline_state.loop_boundary_refinement
				: {};
			global.timeline_state.loop_session = {
				active: true,
				selected_refs: _resolved_refs,
				loop_start_boundary: scr_button_struct_get(loop_boundary_ctx, "start_boundary", {}),
				loop_end_boundary: scr_button_struct_get(loop_boundary_ctx, "end_boundary", {}),
				boundary_refinement: _session_refine,
				timeline_segments: _timeline_segments,
				pass_manifest: loop_pass_manifest,
				start_ms: loop_pass_start_ms,
				end_ms: loop_pass_end_ms,
				core_end_ms: loop_pass_end_ms,
				pass_duration_ms: iteration_duration,
				core_pass_duration_ms: loop_core_duration_ms,
				support_tail_ms: 0,
				passes_total: repeat_total,
				passes_completed: 0,
				spacer_enabled: blank_enabled,
				spacer_duration_ms: blank_enabled ? measure_duration_ms : 0,
				jump_enabled: jump_to_selection,
				phase: jump_to_selection ? "pass" : "prelude",
				current_pass_index: jump_to_selection ? 1 : 0,
				phase_start_ms: jump_to_selection ? loop_pass_start_ms : 0,
				phase_end_ms: jump_to_selection ? loop_pass_end_ms : loop_pass_start_ms,
				pickup_mode: variable_global_exists("score_has_pickup") && bool(global.score_has_pickup) ? "initial" : "none",
				degraded: false
			};
		}

		var _sel_first = "";
		var _sel_last = "";
		if (array_length(selected_refs) > 0) {
			var _rf0 = selected_refs[0];
			var _rfn = selected_refs[array_length(selected_refs) - 1];
			_sel_first = string(max(1, floor(real(scr_button_struct_get(_rf0, "part", 1)))))
				+ ":" + string(floor(real(scr_button_struct_get(_rf0, "measure", -1))));
			_sel_last = string(max(1, floor(real(scr_button_struct_get(_rfn, "part", 1)))))
				+ ":" + string(floor(real(scr_button_struct_get(_rfn, "measure", -1))));
		}

		show_debug_message("[LOOP-V2] canonical_transform active; selected=" + _sel_first + ".." + _sel_last
			+ " count=" + string(array_length(selected_refs))
			+ " window=" + string(floor(loop_start)) + "-" + string(floor(loop_end))
			+ " source=" + string(scr_button_struct_get(loop_boundary_ctx, "source", "fallback"))
			+ " start=" + string(floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "start_boundary", {}), "time_ms", -1))))
			+ "(" + string(max(1, floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "start_boundary", {}), "part", 1)))))
			+ ":" + string(floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "start_boundary", {}), "measure", -1))))
			+ ":b" + string(max(1, floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "start_boundary", {}), "beat", 1)))))
			+ ")"
			+ " end=" + string(floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "end_boundary", {}), "time_ms", -1))))
			+ "(" + string(max(1, floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "end_boundary", {}), "part", 1)))))
			+ ":" + string(floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "end_boundary", {}), "measure", -1))))
			+ ":b" + string(max(1, floor(real(scr_button_struct_get(scr_button_struct_get(loop_boundary_ctx, "end_boundary", {}), "beat", 1)))))
			+ ")"
			+ " pass_ms=" + string(floor(iteration_duration))
			+ " spacer_ms=" + string(blank_enabled ? floor(measure_duration_ms) : 0));

		show_debug_message("[LOOP] Built canonical loop events: " + string(array_length(out))
			+ ", selected_refs=" + string(array_length(selected_refs))
			+ ", selected_owner_nav=" + string(selected_owner_nav_count)
			+ ", window_ms=" + string(floor(loop_start)) + "-" + string(floor(loop_end))
			+ ", in_window_raw=" + string(loop_window_raw_count)
			+ ", in_window_selected=" + string(loop_window_selected_count)
			+ ", repeats=" + string(repeat_total)
			+ ", blank=" + string(blank_enabled)
			+ ", jump=" + string(jump_to_selection)
			+ ", boundary_note_offs=" + string(array_length(loop_boundary_note_offs)));

		var _loop_own_stats = scr_button_apply_event_ownership_metadata(out);
		var _loop_relabel_stats = scr_button_canonicalize_event_measure_labels(out);
		show_debug_message("[OWNERSHIP] loop annotate events=" + string(scr_button_struct_get(_loop_own_stats, "events", 0))
			+ " annotated=" + string(scr_button_struct_get(_loop_own_stats, "annotated", 0))
			+ " unresolved=" + string(scr_button_struct_get(_loop_own_stats, "unresolved", 0))
			+ " nav_entries=" + string(scr_button_struct_get(_loop_own_stats, "nav_entries", 0))
			+ " relabeled=" + string(scr_button_struct_get(_loop_relabel_stats, "relabeled", 0))
			+ " marker_relabeled=" + string(scr_button_struct_get(_loop_relabel_stats, "marker_relabeled", 0)));
		return out;
	}
	
	//CASE 0 
	//No button action
	/// @function scr_script_not_set(_ctx)
	/// @description Debug fallback for unassigned buttons; prints ui_assets grid to debug console.
	/// @reads global.ui_assets (debug print only)
	function scr_script_not_set(_ctx = noone){
		var ctx = scr_button_get_ctx(_ctx);
		var ui_name = string(scr_button_inst_get(ctx, "ui_name", "button"));
		if (ui_name == "tune_library_canvas_anchor") return;
		if (ui_name == "setting_field_cal_input") return;
		if (ui_name == "calibration_status_field") return;
		if (ui_name == "calibration_summary_field") return;
		show_debug_message(ui_name + ": No button action set");
		
		// Assume arr is your 2D array
		var rows = array_length(global.ui_assets);

		for (var i = 0; i < rows; i++) {
		    var cols = array_length(global.ui_assets[i]); // measure this row's length
		    var line = "";
		    for (var j = 0; j < cols; j++) {
		        line += string(global.ui_assets[i][j]) + " ";
		    }
		    show_debug_message("Row " + string(i) + ": " + line);
			show_debug_message("Row length " + string(cols));
		}
	}

	//CASE 1 	
	//Main Menu - Play button
	/// @function scr_goto_playroom()
	/// @description Preprocess tune/set, merge metronome events, build global.playback_events, then go to Room_play.
	/// @reads global.tune, global.current_set, global.current_set_item_index, global.count_in_measures, global.pending_auto_start_play
	/// @writes global.playback_events, global.score_segments_sprites, global.SET_PREP_LAST_TOTAL_MS, global.SET_PREP_LAST_SCORE_MS, global.SET_PREP_LAST_NAV_MS, global.enable_current_note_layer, global.pending_layer_mode, global.pending_layer_room, global.pending_auto_start_play
	/// @objects obj_tune (loaded tune instance)
	/// @callers scr_handle_button_click (button 1)
	function scr_goto_playroom(){
		scr_button_reset_loop_state();

		// Preprocess tune/set and merge with metronome BEFORE switching rooms
		if (scr_set_is_active()) {
			// ── SET PATH ────────────────────────────────────────────────────
			show_debug_message("=== SET MODE: preprocessing all tunes ===");
			var _set_countin = variable_global_exists("count_in_measures") ? real(global.count_in_measures) : 0;
			var set_ok = scr_set_preprocess_and_build_playback(_set_countin);
			if (!set_ok) {
				show_debug_message("WARNING: Set preprocess failed, proceeding without events");
				global.playback_events = [];
			} else {
				scr_playback_context_build_for_set();
				var _set_prepare_start_us = get_timer();
				// Pre-load score sprites for ALL segments into global.score_segments_sprites.
				// This lets future segments display in the score lane before the now line,
				// and avoids disk re-reads on segment changes.
				var _pc_segs_init = global.playback_context[$ "segments"];
				var _pc_seg_n = is_array(_pc_segs_init) ? array_length(_pc_segs_init) : 0;
				var _pc_active_before_preload = floor(real(global.playback_context[$ "active_segment"] ?? 0));
				scr_score_segment_runtime_cache_clear();
				global.score_segments_sprites = array_create(_pc_seg_n, undefined);
				for (var _si = 0; _si < _pc_seg_n; _si++) {
					var _pc_seg_i = _pc_segs_init[_si];
					var _pc_fn_i = is_struct(_pc_seg_i) ? string(_pc_seg_i[$ "filename"] ?? "") : "";
					if (_pc_fn_i != "") {
						// Clear without deleting sprites so each segment load is independent.
						global.score_lane_sprites = [];
						global.score_playback_map = [];
						if (variable_global_exists("score_lane_meta")) global.score_lane_meta = [];
						global.score_override_groups = {};
						global.playback_context[$ "active_segment"] = _si;
						scr_score_sprites_load(_pc_fn_i, undefined);
						global.score_segments_sprites[_si] = {
							sprites: global.score_lane_sprites,
							pbmap:   global.score_playback_map,
							meta:    variable_global_exists("score_lane_meta") ? global.score_lane_meta : [],
							durations: variable_global_exists("score_snippet_durations") ? global.score_snippet_durations : [],
							units_per_measure: variable_global_exists("score_units_per_measure") ? real(global.score_units_per_measure) : 0,
							has_pickup: variable_global_exists("score_has_pickup") ? global.score_has_pickup : false,
							override_groups: variable_global_exists("score_override_groups") ? global.score_override_groups : {}
						};
					}
				}
				global.playback_context[$ "active_segment"] = clamp(_pc_active_before_preload, 0, max(0, _pc_seg_n - 1));
				// Restore segment 0 as the active sprite set and reload its override groups.
				if (_pc_seg_n > 0 && is_struct(global.score_segments_sprites[0])) {
					var _s0 = global.score_segments_sprites[0];
					global.score_lane_sprites = _s0.sprites;
					global.score_playback_map = _s0.pbmap;
					if (variable_global_exists("score_lane_meta")) global.score_lane_meta = _s0.meta;
					if (variable_global_exists("score_snippet_durations")) global.score_snippet_durations = _s0.durations;
					if (variable_global_exists("score_units_per_measure")) global.score_units_per_measure = real(_s0.units_per_measure ?? 0);
					if (variable_global_exists("score_has_pickup")) global.score_has_pickup = bool(_s0[$ "has_pickup"] ?? false);
					global.score_override_groups = _s0[$ "override_groups"] ?? {};
				}
				// Build the flat prebuilt measure-nav table now that all segment caches are populated.
				// gv_get_current_planned_measure() will use this in set mode, avoiding stale measure
				// numbers during segment transitions.
				var _set_nav_prepare_start_us = get_timer();
				gv_build_set_measure_nav_all();
				global.SET_PREP_LAST_NAV_MS = (get_timer() - _set_nav_prepare_start_us) * 0.001;
				global.SET_PREP_LAST_TOTAL_MS = (get_timer() - _set_prepare_start_us) * 0.001;
				global.SET_PREP_LAST_SCORE_MS = max(0, global.SET_PREP_LAST_TOTAL_MS - global.SET_PREP_LAST_NAV_MS);
			}
		} else {
		// ── SINGLE TUNE PATH ────────────────────────────────────────────────
		var tune = global.tune;
		var tune_data = scr_button_tune_data_get(tune);
		if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
			show_debug_message("Preprocessing tune for playback...");
			var rebuilt = scr_button_prepare_single_tune_playback_events();
			if (rebuilt) {
				show_debug_message("Single-tune playback events rebuilt via unified settings resolver.");
			}
			// Build playback context so viz/scoring know the active tune
			var _ctx_tune_struct = { tune_data: tune_data };
			if (is_struct(tune_data)) {
				scr_playback_context_build_for_tune(_ctx_tune_struct);
				var _active_after_ctx = scr_button_get_active_settings_segment(true);
				if (is_struct(_active_after_ctx)) {
					scr_button_sync_single_tune_settings_segment(_active_after_ctx);
				}
			}
		} else {
			show_debug_message("WARNING: No tune loaded, proceeding without events");
			global.playback_events = [];
		}
		} // end single-tune else
		if (variable_global_exists("pending_auto_start_play")) {
			global.pending_auto_start_play = false;
		}
		
		// Update title field from playback_context
		scr_gameinfo_update_title(0);

		global.enable_current_note_layer = false;
		global.pending_layer_mode = "play";
		global.pending_layer_room = Room_play;
		room_goto(Room_play);
	}

	//CASE 2 Clicked Checkbox
	//Used in tune window but could be made generic
	/// @function scr_checkbox_click(_ctx)
	/// @description Toggle the clicked checkbox and clear siblings in the same group; updates the global named by button_target.
	/// @reads global.ui_assets (passed to scr_uncheck_all)
	/// @writes global.[button_target] (dynamic target, set via variable_global_set)
	/// @objects obj_tune_picker (calls scr_tune_picker_select_index / scr_tune_picker_clear_selection)
	/// @callers scr_handle_button_click (button 2)
	function scr_checkbox_click(_ctx = noone)	{
	//Set the choices that were made in the settings window.
	// Remove "global." from the string
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var button_target = string(scr_button_inst_get(ctx, "button_target", ""));
		var target_name = string_replace(button_target, "global.", "");
		var button_checked = real(scr_button_inst_get(ctx, "button_checked", 0));
		var ui_layer_num = real(scr_button_inst_get(ctx, "ui_layer_num", 0));
		var ui_group = scr_button_inst_get(ctx, "ui_group", 0);
		var ui_num = real(scr_button_inst_get(ctx, "ui_num", -1));
		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", -1));

		var picker = instance_find(obj_tune_picker, 0);

		if (button_checked == 0) {
			// Unchecked → first click on this row: select tune at P1
			scr_uncheck_all(global.ui_assets, ui_layer_num, ui_group, ui_num);
			scr_button_inst_set(ctx, "button_checked", 1);
			scr_button_inst_set(ctx, "image_index", 3);
			variable_global_set(target_name, button_click_value);
			if (picker != noone) {
				var source_idx = scr_tune_picker_get_visible_source_index(button_click_value);
				if (source_idx >= 0) {
					scr_tune_picker_activate_index(source_idx);
				} else {
					scr_tune_picker_select_index(button_click_value);
				}
				scr_tune_picker_sync_selected_entry_ui();
			}
		}
		else if (button_checked == 1) {
			// Already checked → cycle to next part, or deselect if on last part
			if (picker != noone) {
				var source_idx = scr_tune_picker_get_visible_source_index(button_click_value);
				if (source_idx >= 0) {
					scr_tune_picker_activate_index(source_idx);
				} else {
					scr_tune_picker_clear_selection();
				}
				// If activate_index cleared the selection (was last part), uncheck button
				if (!variable_global_exists("tune_selection") || global.tune_selection < 0) {
					scr_uncheck_all(global.ui_assets, ui_layer_num, ui_group, -1);
					scr_button_inst_set(ctx, "button_checked", 0);
					scr_button_inst_set(ctx, "image_index", 0);
					variable_global_set(target_name, -1);
				}
				scr_tune_picker_sync_selected_entry_ui();
			} else {
				scr_uncheck_all(global.ui_assets, ui_layer_num, ui_group, ui_num);
				scr_button_inst_set(ctx, "button_checked", 0);
				scr_button_inst_set(ctx, "image_index", 0);
				variable_global_set(target_name, -1);
			}
		}
	}	

	//Script to uncheck checkboxes for use when checking a new checkbox
	/// @function scr_uncheck_all(array_of_checkboxes, ui_layer, ui_group, this_num)
	/// @description Uncheck all other checkboxes in the same group/layer, except the given ui_num.
	/// @objects obj_UI_parent (re-links stale array entries)
	/// @callers scr_checkbox_click
	function scr_uncheck_all(array_of_checkboxes,ui_layer, ui_group, this_num) {
		show_debug_message("Uncheck in layer " + string(ui_layer) +
                       " group " + string(ui_group) +
                       " except ui_num " + string(this_num));
			var target_group = ui_group;

		var layer_entries = array_of_checkboxes[ui_layer];

		for (var i = 0; i < array_length(layer_entries); i++) {
			var entry = layer_entries[i];
			var num   = entry[0];
			var cb    = entry[1];

			// Only act on other checkboxes in the same group
			if (num != this_num && instance_exists(cb)) {
				var cb_group = scr_button_inst_get(cb, "ui_group", undefined);
				if (!is_undefined(cb_group) && cb_group == target_group) {
					scr_button_inst_set(cb, "button_checked", 0);
					scr_button_inst_set(cb, "image_index", 0);
					var cb_name = string(scr_button_inst_get(cb, "ui_name", "checkbox"));
					show_debug_message("Unchecked " + cb_name + " in group " + string(cb_group));
				}
			} else if (!instance_exists(cb)) {
				// Attempt on-the-fly re-link by ui_num
				var parent_count = instance_number(obj_UI_parent);
				for (var p = 0; p < parent_count; p++) {
					var parent_inst = instance_find(obj_UI_parent, p);
					if (parent_inst == noone) continue;
					var parent_num = real(scr_button_inst_get(parent_inst, "ui_num", -1));
					var parent_layer = real(scr_button_inst_get(parent_inst, "ui_layer_num", -1));
					if (parent_num == num && parent_layer == ui_layer) {
						array_of_checkboxes[ui_layer][i][1] = parent_inst;
						break;
					}
				}
			}
		}
	}


    //CASE 3 Open Window
	//Open Settings and Tune window from main menu, close them from windows close button
	/// @function scr_open_window(layer_num, vis)
	/// @description Show or hide a UI layer; populates metadata fields (MIDI device names, metronome pattern) when opening.
	/// @param layer_num Integer layer index to show/hide
	/// @param vis true = make visible; false/undefined = toggle (hide all then show target)
	/// @reads global.ui_assets, global.tune, global.metronome_pattern_options, global.metronome_pattern_selection, global.midi_input_device, global.midi_output_device, global.midi_input_device_name, global.midi_output_device_name
	/// @writes global.midi_input_device, global.midi_output_device, global.midi_input_device_name, global.midi_output_device_name (resets stale refs)
	/// @objects obj_tune (reads tune_data), obj_field_base (updates field contents)
	/// @callers scr_handle_button_click (button 3), scr_select_player
	function scr_open_window(layer_num, vis = undefined) {
		var layer_name = GetLayerNameFromIndex(layer_num);
		var layer_id = layer_get_id(layer_name);
		var current_visibility = layer_get_visible(layer_id); // Get the current visibility
		if (is_undefined(vis)) vis = false;		
		
		if (vis == false) {
			for (var i = 1; i < array_length(global.ui_assets); i++) {
					var cur_layer_name = GetLayerNameFromIndex(i);
					var cur_layer_id = layer_get_id(cur_layer_name);
					if (cur_layer_id != -1) {
						layer_set_visible(cur_layer_id, false);
						instance_deactivate_layer(cur_layer_id);
					}
			}
		}
		layer_set_visible(layer_id, !current_visibility); // Toggle visibility

		var new_visibility = layer_get_visible(layer_id);
		if (new_visibility) {
			instance_activate_layer(layer_id);
		} else {
			instance_deactivate_layer(layer_id);
		}
		// If we just opened the tune window, populate the picker
		if (new_visibility && layer_name == "tune_window_layer") {
			scr_tune_picker_populate();
			
			// Refresh metronome pattern list for current tune/mode
			var tune = global.tune;
			var tune_data = scr_button_tune_data_get(tune);
			var time_sig = "4/4";
			if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
				var meta = scr_button_struct_get(tune_data, "tune_metadata", undefined);
				time_sig = string(scr_button_struct_get(meta, "meter", "4/4"));
			}
			metronome_update_pattern_list(time_sig);
			var metro_pattern_field = scr_button_find_field_by_ui_name("metro_field_2");
			if (instance_exists(metro_pattern_field) && array_length(global.metronome_pattern_options) > 0) {
				scr_button_field_set(metro_pattern_field, "field_value", global.metronome_pattern_selection);
				scr_button_field_set(metro_pattern_field, "field_contents", global.metronome_pattern_options[global.metronome_pattern_selection]);
			}
		}
		
		// If we opened settings window, update metronome pattern list based on current tune
		if (new_visibility && layer_name == "settings_window_layer") {
			// Refresh MIDI device lists each time settings opens (handles runtime port changes)
			MIDI_scan_input_devices();
			MIDI_scan_output_devices();

			var input_count = midi_input_device_count();
			var output_count = midi_output_device_count();
			global._midi_refresh_input_count = input_count;
			global._midi_refresh_output_count = output_count;

			// Keep selected device indices in range and update display names
			if (input_count > 0) {
				global.midi_input_device = clamp(global.midi_input_device, 0, input_count - 1);
				global.midi_input_device_name = midi_input_device_name(global.midi_input_device);
			} else {
				global.midi_input_device = 0;
				global.midi_input_device_name = "no MIDI input devices found";
			}

			if (output_count > 0) {
				global.midi_output_device = clamp(global.midi_output_device, 0, output_count - 1);
				global.midi_output_device_name = midi_output_device_name(global.midi_output_device);
			} else {
				global.midi_output_device = 0;
				global.midi_output_device_name = "no MIDI output devices found";
			}

			// Refresh MIDI field bounds/values. Support both field_target wiring and
			// legacy settings fields keyed by ui_name (setting_field_1/setting_field_2).
			var field_count = instance_number(obj_field_base);
			for (var fi = 0; fi < field_count; fi++) {
				var field_inst = instance_find(obj_field_base, fi);
				if (field_inst == noone) continue;

				var field_target_raw = scr_button_inst_get(field_inst, "field_target", "");
				var field_target_name = is_string(field_target_raw) ? string_lower(string_trim(field_target_raw)) : "";
				var field_ui_name = string_lower(string_trim(string(scr_button_inst_get(field_inst, "ui_name", ""))));

				var is_midi_in_field = (field_target_name == "midi_input_devices"
					|| field_target_name == "global.midi_input_devices"
					|| field_ui_name == "setting_field_1");
				var is_midi_out_field = (field_target_name == "midi_output_devices"
					|| field_target_name == "global.midi_output_devices"
					|| field_ui_name == "setting_field_2");

				if (is_midi_in_field) {
					var in_min = 0;
					var in_max = max(global._midi_refresh_input_count - 1, 0);
					var in_value = clamp(global.midi_input_device, in_min, in_max);
					var in_contents = (global._midi_refresh_input_count > 0) ? midi_input_device_name(in_value) : "none";
					scr_button_field_set(field_inst, "field_min_value", in_min);
					scr_button_field_set(field_inst, "field_max_value", in_max);
					scr_button_field_set(field_inst, "field_value", in_value);
					scr_button_field_set(field_inst, "field_contents", in_contents);
				}

				if (is_midi_out_field) {
					var out_min = 0;
					var out_max = max(global._midi_refresh_output_count - 1, 0);
					var out_value = clamp(global.midi_output_device, out_min, out_max);
					var out_contents = (global._midi_refresh_output_count > 0) ? midi_output_device_name(out_value) : "none";
					scr_button_field_set(field_inst, "field_min_value", out_min);
					scr_button_field_set(field_inst, "field_max_value", out_max);
					scr_button_field_set(field_inst, "field_value", out_value);
					scr_button_field_set(field_inst, "field_contents", out_contents);
				}

				var is_logs_field = (field_ui_name == "setting_field_logs");
				if (is_logs_field) {
					if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
						global.timeline_cfg = {};
					}
					if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_log")) {
						global.timeline_cfg.score_lane_debug_log = false;
					}
					if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")) {
						global.timeline_cfg.score_lane_debug_file_log = false;
					}
					if (!variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log")) {
						global.timeline_cfg.score_render_plan_debug_log = global.timeline_cfg.score_lane_debug_log;
					}

					var logs_enabled = bool(global.timeline_cfg.score_lane_debug_log);
					scr_button_field_set(field_inst, "field_min_value", 0);
					scr_button_field_set(field_inst, "field_max_value", 1);
					scr_button_field_set(field_inst, "field_value", logs_enabled ? 1 : 0);
					scr_button_field_set(field_inst, "field_contents", logs_enabled ? "ON" : "OFF");
				}
			}
			global._midi_refresh_input_count = undefined;
			global._midi_refresh_output_count = undefined;

			show_debug_message("=== MIDI INPUT DEVICES (" + string(input_count) + ") ===");
			for (var in_i = 0; in_i < input_count; in_i++) {
				show_debug_message("IN[" + string(in_i) + "]: " + midi_input_device_name(in_i));
			}
			show_debug_message("=== MIDI OUTPUT DEVICES (" + string(output_count) + ") ===");
			for (var out_i = 0; out_i < output_count; out_i++) {
				show_debug_message("OUT[" + string(out_i) + "]: " + midi_output_device_name(out_i));
			}

			var tune = global.tune;
			var tune_data = scr_button_tune_data_get(tune);
			var time_sig = "4/4"; // Default
			
			if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
				var meta = scr_button_struct_get(tune_data, "tune_metadata", undefined);
				time_sig = string(scr_button_struct_get(meta, "meter", "4/4"));
			}
			
			metronome_update_pattern_list(time_sig);
			scr_button_calibration_refresh_ui();
			scr_settings_refresh_data_root_field();

			// Refresh View ahead / behind fields. Behind stays locked at half of ahead.
			var _vcfg = gv_ensure_timeline_cfg_defaults();
			var _ahead_ms = real(variable_struct_get(_vcfg, "time_ahead_ms") ?? 4500);
			var _ahead_field = scr_button_find_field_by_ui_name("setting_field_view_ahead");
			if (instance_exists(_ahead_field)) {
				scr_button_field_set(_ahead_field, "field_min_value", 500);
				scr_button_field_set(_ahead_field, "field_max_value", 30000);
				scr_button_field_set(_ahead_field, "field_value", _ahead_ms);
				scr_button_field_set(_ahead_field, "field_contents", string_format(_ahead_ms / 1000, 1, 2));
			}
		}

		if (layer_name == "calibration_window_layer") {
			if (new_visibility) {
				if (script_exists(asset_get_index("timing_calibration_apply_profile_for_current_device"))) {
					timing_calibration_apply_profile_for_current_device();
				}
				timing_calibration_begin_session();
			} else {
				timing_calibration_close_session(timing_calibration_get_session_commit_on_close());
			}
			scr_button_calibration_refresh_ui();
		}

    // Refresh and update fields for the target window
		scr_ui_refresh(layer_num);
		scr_update_fields(layer_num);
	}
	
	//CASE 4 
	//Main Menu - End Button
	/// @function scr_exit_game()
	/// @description Quit the game immediately.
	function scr_exit_game(){
		game_end();
	}

	//CASE 5 	
	//Go to Main Menu button
	/// @function scr_goto_mainmenu()
	/// @description Stop MIDI, reset loop state, clear active flags, then go to Room_main_menu.
	/// @writes global.timing_calibration.active/status, global.timeline_state.active, global.pending_auto_start_play, global.pending_layer_mode, global.pending_layer_room
	/// @callers scr_handle_button_click (button 5)
	function scr_goto_mainmenu(){
		scr_button_reset_play_session_state();
		MIDI_send_off();
		MIDI_stop_checking_messages_and_errors();
		if (variable_global_exists("timing_calibration") && is_struct(global.timing_calibration)) {
			global.timing_calibration.active = false;
			global.timing_calibration.status = "idle";
		}
		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			global.timeline_state.active = false;
		}
		if (variable_global_exists("pending_auto_start_play")) {
			global.pending_auto_start_play = false;
		}
		global.pending_layer_mode = "main";
		global.pending_layer_room = Room_main_menu;
		room_goto(Room_main_menu);
	}
	
	//CASE 6
	//change settings field by button value ... for +/- buttons (generic array cycling)
	/// @function scr_settings_change(_ctx)
	/// @description Advance or cycle a field's value through its target global array (+/- buttons).
	/// @writes global.[field_target] (dynamic — the array named by the field's field_target string)
	/// @callers scr_handle_button_click (button 6)
	function scr_settings_change(_ctx = noone)	{
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_target = scr_button_field_get(field, "field_target", undefined);
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		var target_array = is_string(field_target) ? variable_global_get(field_target) : field_target;

		if (is_array(target_array)) {
			var array_len = array_length(target_array);
			field_value = (field_value + button_click_value + array_len) % array_len;
			scr_button_field_set(field, "field_value", field_value);
			var field_contents = target_array[field_value];
			scr_button_field_set(field, "field_contents", field_contents);
			show_debug_message("Field now shows: " + string(field_contents) + " (index " + string(field_value) + ")");
		} else {
			show_debug_message("WARNING: field_target is not an array");
		}
	}
	
	//CASE 7 - change settings specific for MIDI in
	/// @function scr_settings_MIDI_In_change(_ctx)
	/// @description Cycle to the next/previous MIDI input device and update the UI field.
	/// @writes global.midi_input_device, global.midi_input_device_name
	/// @callers scr_handle_button_click (button 7)
	function scr_settings_MIDI_In_change(_ctx = noone)	{
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var input_count = midi_input_device_count();
		if (input_count <= 0) {
			scr_button_field_set(field, "field_min_value", 0);
			scr_button_field_set(field, "field_max_value", 0);
			scr_button_field_set(field, "field_value", 0);
			scr_button_field_set(field, "field_contents", "none");
			global.midi_input_device = 0;
			global.midi_input_device_name = "no MIDI input devices found";
			show_debug_message("No MIDI input devices found");
			return;
		}

		scr_button_field_set(field, "field_min_value", 0);
		scr_button_field_set(field, "field_max_value", input_count - 1);

		var field_value = real(scr_button_field_get(field, "field_value", 0));
		field_value += button_click_value;
		if (field_value < 0) {
			field_value = input_count - 1;
		}
		else if (field_value >= input_count) {
			field_value = 0;
		}

		var field_contents = midi_input_device_name(field_value);
		scr_button_field_set(field, "field_value", field_value);
		scr_button_field_set(field, "field_contents", field_contents);
		global.midi_input_device = field_value;
		global.midi_input_device_name = field_contents;
		show_debug_message(string(field_contents) + " " + string(field_value));
	}
	
	//CASE 8 - change settings specific for MIDI out
	/// @function scr_settings_MIDI_Out_change(_ctx)
	/// @description Cycle to the next/previous MIDI output device and update the UI field.
	/// @writes global.midi_output_device, global.midi_output_device_name
	/// @callers scr_handle_button_click (button 8)
	function scr_settings_MIDI_Out_change(_ctx = noone)	{
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var output_count = midi_output_device_count();
		if (output_count <= 0) {
			scr_button_field_set(field, "field_min_value", 0);
			scr_button_field_set(field, "field_max_value", 0);
			scr_button_field_set(field, "field_value", 0);
			scr_button_field_set(field, "field_contents", "none");
			global.midi_output_device = 0;
			global.midi_output_device_name = "no MIDI output devices found";
			show_debug_message("No MIDI output devices found");
			return;
		}

		scr_button_field_set(field, "field_min_value", 0);
		scr_button_field_set(field, "field_max_value", output_count - 1);

		var field_value = real(scr_button_field_get(field, "field_value", 0));
		field_value += button_click_value;
		if (field_value < 0) {
			field_value = output_count - 1;
		}
		else if (field_value >= output_count) {
			field_value = 0;
		}

		var field_contents = midi_output_device_name(field_value);
		scr_button_field_set(field, "field_value", field_value);
		scr_button_field_set(field, "field_contents", field_contents);
		global.midi_output_device = field_value;
		global.midi_output_device_name = field_contents;
		show_debug_message(string(field_contents) + " " + string(field_value));
	}

	//CASE 30 - Logs toggle in settings (OFF/ON)
	/// @function scr_settings_logs_toggle(_ctx)
	/// @description Toggle settings Logs control and sync score-lane debug flags plus optional verbose runtime diagnostics.
	/// @reads global.timeline_cfg.score_lane_debug_log, global.timeline_cfg.score_lane_debug_file_log, global.MIDI_TIMING_DIAG_ENABLED
	/// @writes global.timeline_cfg.score_lane_debug_log, global.timeline_cfg.score_lane_debug_file_log, global.MIDI_TIMING_DIAG_ENABLED, global.PLAYBACK_DEBUG_GROUP_TIMING
	/// @callers scr_handle_button_click (button 30)
	function scr_settings_logs_toggle(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
			global.timeline_cfg = {};
		}
		if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_log")) {
			global.timeline_cfg.score_lane_debug_log = false;
		}
		if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")) {
			global.timeline_cfg.score_lane_debug_file_log = false;
		}
		if (!variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log")) {
			global.timeline_cfg.score_render_plan_debug_log = global.timeline_cfg.score_lane_debug_log;
		}

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		if (button_click_value == 0) button_click_value = 1;
		field_value = (field_value + button_click_value + 2) mod 2;
		var logs_enabled = (field_value == 1);

		scr_button_field_set(field, "field_min_value", 0);
		scr_button_field_set(field, "field_max_value", 1);
		scr_button_field_set(field, "field_value", field_value);
		scr_button_field_set(field, "field_contents", logs_enabled ? "ON" : "OFF");

		global.timeline_cfg.score_lane_debug_log = logs_enabled;
		global.timeline_cfg.score_lane_debug_file_log = logs_enabled;
		global.timeline_cfg.score_render_plan_debug_log = logs_enabled;
		global.MIDI_TIMING_DIAG_ENABLED = logs_enabled;
		global.PLAYBACK_DEBUG_GROUP_TIMING = logs_enabled;

		show_debug_message("[SETTINGS] Logs " + (logs_enabled ? "ON" : "OFF"));
	}

	/// @function scr_settings_refresh_data_root_field()
	/// @description Refresh the settings field text for tune content root mode (AUTO/CUSTOM) and current resolved tune root.
	/// @reads global.primary_data_root_override
	/// @writes obj_field_base.field_value/field_contents for setting_field_tune_root
	/// @objects obj_field_base
	/// @callers scr_open_window, scr_settings_data_root_set, scr_settings_data_root_reset_auto
	function scr_settings_refresh_data_root_field() {
		var field = scr_button_find_field_by_ui_name("setting_field_tune_root");
		if (!instance_exists(field)) return;

		var override_root = "";
		if (variable_global_exists("primary_data_root_override")) {
			override_root = scr_tune_library_normalize_root(global.primary_data_root_override);
		}

		var resolved_root = script_exists(asset_get_index("scr_data_paths_get_content_root"))
			? scr_data_paths_get_content_root()
			: "datafiles/";

		var contents = (override_root != "")
			? ("CUSTOM: " + override_root)
			: ("AUTO: " + resolved_root);

		scr_button_field_set(field, "field_min_value", 0);
		scr_button_field_set(field, "field_max_value", 0);
		scr_button_field_set(field, "field_value", 0);
		scr_button_field_set(field, "field_contents", contents);
	}

	/// @function scr_settings_data_root_set(_ctx)
	/// @description Set a custom tune content root (folder path prompt with optional file-picker assist), persist to runtime paths config, and regenerate the tune library.
	/// @param _ctx Button context
	/// @reads global.primary_data_root_override
	/// @writes global.primary_data_root_override, runtime paths config, global.tune_library
	/// @objects obj_field_base
	/// @callers scr_handle_button_click (button 38)
	function scr_settings_data_root_set(_ctx = noone) {
		var seed = "";
		if (variable_global_exists("primary_data_root_override")) {
			seed = scr_tune_library_normalize_root(global.primary_data_root_override);
		}
		if (seed == "" && script_exists(asset_get_index("scr_data_paths_get_content_root"))) {
			seed = scr_data_paths_get_content_root();
		}

		var picked = "";
		var picker_filter = "All files (*.*)|*.*";

		// Select any file under the desired root; the containing folder is used as root.
		var raw = "";
		if (seed != "" && directory_exists(seed)) {
			picked = get_open_filename(picker_filter, seed + "pick_any_file.tmp");
		}
		if (string_trim(string(picked)) == "") {
			picked = get_open_filename(picker_filter, "");
		}
		raw = string(picked);
		raw = string(raw);
		if (string_trim(raw) == "") return;

		var root = scr_tune_library_normalize_root(raw);
		if (root != "" && !directory_exists(root) && file_exists(root)) {
			root = scr_tune_library_normalize_root(scr_tune_library_get_parent_dir(root));
		}

		// Accept either direct data root (.../datafiles/) or project root (.../) containing datafiles/tunes.
		if (root != "" && !directory_exists(root + "tunes/") && directory_exists(root + "datafiles/tunes/")) {
			root = scr_tune_library_normalize_root(root + "datafiles/");
		}

		if (root == "") return;
		if (!directory_exists(root)) {
			show_message("Could not access selected folder:\n" + root);
			return;
		}

		var tunes_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
			? scr_tune_library_normalize_root(root + "tunes/")
			: (root + "tunes/");

		if (!directory_exists(tunes_root)) {
			show_debug_message("[SETTINGS] Data root rejected (missing /tunes folder): " + root);
			show_message("Could not find a tunes folder under:\n" + root + "\n\nPick your tune content root (the folder that contains /tunes).\nIf you selected the project root, pick the datafiles folder instead.");
			return;
		}
		if (!scr_tune_library_root_has_json_content(tunes_root)) {
			show_debug_message("[SETTINGS] Data root accepted but /tunes has no tune JSON yet: " + root);
		}

		global.primary_data_root_override = root;
		global.tune_library_root_override = root + "tunes/";
		if (script_exists(asset_get_index("scr_data_paths_save_primary_root_to_config"))) {
			scr_data_paths_save_primary_root_to_config(root);
		} else if (script_exists(asset_get_index("scr_tune_library_save_root_override_to_config"))) {
			scr_tune_library_save_root_override_to_config(root + "tunes/");
		}

		scr_regenerate_tune_library();
		scr_settings_refresh_data_root_field();
		show_debug_message("[SETTINGS] Tune content root set: " + root);
	}

	/// @function scr_settings_data_root_reset_auto(_ctx)
	/// @description Clear custom tune content root override, persist AUTO mode to runtime paths config, and regenerate the tune library.
	/// @param _ctx Button context
	/// @writes global.primary_data_root_override, runtime paths config, global.tune_library
	/// @callers scr_handle_button_click (button 39)
	function scr_settings_data_root_reset_auto(_ctx = noone) {
		global.primary_data_root_override = "";
		global.tune_library_root_override = "";
		if (script_exists(asset_get_index("scr_data_paths_save_primary_root_to_config"))) {
			scr_data_paths_save_primary_root_to_config("");
		} else if (script_exists(asset_get_index("scr_tune_library_save_root_override_to_config"))) {
			scr_tune_library_save_root_override_to_config("");
		}

		scr_regenerate_tune_library();
		scr_settings_refresh_data_root_field();
		show_debug_message("[SETTINGS] Tune content root reset to AUTO");
	}

	/// @function scr_settings_refresh_tune_root_field()
	/// @description Backward-compatible alias.
	function scr_settings_refresh_tune_root_field() {
		scr_settings_refresh_data_root_field();
	}

	/// @function scr_settings_tune_root_set(_ctx)
	/// @description Backward-compatible alias.
	function scr_settings_tune_root_set(_ctx = noone) {
		scr_settings_data_root_set(_ctx);
	}

	/// @function scr_settings_tune_root_reset_auto(_ctx)
	/// @description Backward-compatible alias.
	function scr_settings_tune_root_reset_auto(_ctx = noone) {
		scr_settings_data_root_reset_auto(_ctx);
	}

	//CASE 32 - Manual calibration offset nudge (+/- 1ms) for audio/visual fields
	/// @function scr_calibration_offset_change(_ctx)
	/// @description Adjust one calibration offset domain by fixed-step milliseconds.
	/// @callers scr_handle_button_click (button 32)
	function scr_calibration_offset_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var ui_name = string(scr_button_inst_get(field, "ui_name", ""));
		var delta = real(scr_button_inst_get(ctx, "button_click_value", 0));
		if (scr_button_calibration_apply_offset_delta(ui_name, delta)) {
			scr_button_calibration_refresh_ui();
		}
	}

	//CASE 31 - Calibration mode selector
	/// @function scr_calibration_mode_change(_ctx)
	/// @description Cycle the calibration calibration mode between bouncing ball and converging beams.
	/// @callers scr_handle_button_click (button 31)
	function scr_calibration_mode_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var delta = real(scr_button_inst_get(ctx, "button_click_value", 0));
		timing_calibration_set_mode_index(delta);
		scr_button_calibration_refresh_ui();
	}

	//CASE 33 - Start/stop continuous calibration test loop
	/// @function scr_calibration_test_preview(_ctx)
	/// @description Toggle the continuous preview loop for the current calibration mode.
	/// @callers scr_handle_button_click (button 33)
	function scr_calibration_test_preview(_ctx = noone) {
		var state = timing_calibration_ensure_state();
		var running = timing_calibration_start_preview_click();
		if (running) {
			var offsets = timing_calibration_get_current_offsets();
			var audio_ms = 0;
			var visual_ms = 0;
			var input_ms = 0;
			if (is_struct(offsets)) {
				if (variable_struct_exists(offsets, "audio_output_offset_ms")) {
					audio_ms = real(variable_struct_get(offsets, "audio_output_offset_ms"));
				}
				if (variable_struct_exists(offsets, "visual_alignment_offset_ms")) {
					visual_ms = real(variable_struct_get(offsets, "visual_alignment_offset_ms"));
				}
				if (variable_struct_exists(offsets, "input_capture_offset_ms")) {
					input_ms = real(variable_struct_get(offsets, "input_capture_offset_ms"));
				}
			}
			state.last_message = "Calibration test running in " + timing_calibration_get_mode_label(timing_calibration_get_current_mode_index())
				+ " (audio " + string_format(audio_ms, 0, 1)
				+ " ms, visual " + string_format(visual_ms, 0, 1)
				+ " ms, MIDI In " + string_format(input_ms, 0, 1) + " ms).";
		} else {
			state.last_message = "Calibration test stopped.";
		}
		scr_button_calibration_refresh_ui();
	}

	//CASE 34 - Reset calibration to system defaults
	/// @function scr_calibration_reset_defaults(_ctx)
	/// @description Restore current offsets to the measured system baseline.
	/// @callers scr_handle_button_click (button 34)
	function scr_calibration_reset_defaults(_ctx = noone) {
		var state = timing_calibration_ensure_state();
		timing_calibration_reset_to_system_defaults();
		state.last_message = "Calibration restored to system defaults.";
		scr_button_calibration_refresh_ui();
	}

	//CASE 35 - Calibration OK (save + close)
	/// @function scr_calibration_save_profile(_ctx)
	/// @description Persist the current offsets, commit the session, and close the calibration window.
	/// @callers scr_handle_button_click (button 35)
	function scr_calibration_save_profile(_ctx = noone) {
		var state = timing_calibration_ensure_state();
		timing_calibration_set_session_commit_on_close(true);
		timing_calibration_save_current_profile();
		state.last_message = "Calibration saved.";
		scr_open_window(8);
	}

	//CASE 36 - Toggle calibration advanced panel
	/// @function scr_calibration_toggle_advanced(_ctx)
	/// @description Toggle the advanced calibration readout between compact and verbose summaries.
	/// @callers scr_handle_button_click (button 36)
	function scr_calibration_toggle_advanced(_ctx = noone) {
		var state = timing_calibration_ensure_state();
		timing_calibration_toggle_advanced_panel();
		state.last_message = bool(state.calibration_advanced_open ?? false)
			? "Advanced calibration details opened."
			: "Advanced calibration details closed.";
		scr_button_calibration_refresh_ui();
	}

	//CASE 37 - Calibration Cancel (close with no change)
	/// @function scr_calibration_apply_profile(_ctx)
	/// @description Close the calibration window and restore pre-session offsets.
	/// @callers scr_handle_button_click (button 37)
	function scr_calibration_apply_profile(_ctx = noone) {
		timing_calibration_set_session_commit_on_close(false);
		scr_open_window(8);
	}
	
	//CASE 14 - Metronome Mode (None/Click/Drums)
	/// @function scr_metronome_mode_change(_ctx)
	/// @description Change the metronome mode (None/Click/Drums) and sync pattern field and METRONOME_CONFIG.
	/// @reads global.metronome_mode_options, global.selected_tune_time_sig, global.METRONOME_CONFIG, global.metronome_pattern_options, global.current_set, global.current_set_item_index
	/// @writes global.metronome_mode, global.METRONOME_CONFIG.enabled/mode, global.metronome_pattern_selection, global.current_set[idx]
	/// @objects obj_field_base (updates pattern field via scr_button_find_field_by_ui_name)
	/// @callers scr_handle_button_click (button 14)
	function scr_metronome_mode_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var array_len = array_length(global.metronome_mode_options);
		if (array_len <= 0) return;

		var field_value = real(scr_button_field_get(field, "field_value", 0));
		field_value = (field_value + button_click_value + array_len) % array_len;
		var field_contents = global.metronome_mode_options[field_value];
		scr_button_field_set(field, "field_value", field_value);
		scr_button_field_set(field, "field_contents", field_contents);

		global.metronome_mode = field_value;
		global.METRONOME_CONFIG.enabled = (global.metronome_mode > 0);
		global.METRONOME_CONFIG.mode = global.metronome_mode_options[field_value];

		var time_sig = "4/4";
		if (variable_global_exists("selected_tune_time_sig") && global.selected_tune_time_sig != "") {
			time_sig = global.selected_tune_time_sig;
		} else {
			var tune = global.tune;
			var tune_data = scr_button_tune_data_get(tune);
			if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
				var meta = scr_button_struct_get(tune_data, "tune_metadata", undefined);
				time_sig = string(scr_button_struct_get(meta, "meter", "4/4"));
			}
		}

		metronome_update_pattern_list(time_sig);
		var metro_pattern_field = scr_button_find_field_by_ui_name("metro_field_2");
		if (instance_exists(metro_pattern_field) && array_length(global.metronome_pattern_options) > 0) {
			scr_button_field_set(metro_pattern_field, "field_value", global.metronome_pattern_selection);
			scr_button_field_set(metro_pattern_field, "field_contents", global.metronome_pattern_options[global.metronome_pattern_selection]);
		}

		scr_button_write_setting_to_active_segment("metronome_mode", global.metronome_mode);
		if (!scr_button_is_set_mode()) {
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Metronome mode: " + string(field_contents));
	}
	
	//CASE 15 - Metronome Pattern
	/// @function scr_metronome_pattern_change(_ctx)
	/// @description Cycle to the next/previous metronome pattern.
	/// @reads global.metronome_pattern_options, global.current_set, global.current_set_item_index
	/// @writes global.metronome_pattern_selection, global.current_set[idx]
	/// @callers scr_handle_button_click (button 15)
	function scr_metronome_pattern_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var array_len = array_length(global.metronome_pattern_options);
		if (array_len <= 0) {
			show_debug_message("No patterns available");
			return;
		}

		var field_value = real(scr_button_field_get(field, "field_value", 0));
		field_value = (field_value + button_click_value + array_len) % array_len;
		var field_contents = global.metronome_pattern_options[field_value];
		scr_button_field_set(field, "field_value", field_value);
		scr_button_field_set(field, "field_contents", field_contents);

		global.metronome_pattern_selection = field_value;
		scr_button_write_setting_to_active_segment("metronome_pattern", global.metronome_pattern_selection);
		if (!scr_button_is_set_mode()) {
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Metronome pattern: " + string(field_contents));
	}
	
	//CASE 16 - Metronome Volume
	/// @function scr_metronome_volume_change(_ctx)
	/// @description Adjust metronome MIDI velocity by ±10 steps and sync METRONOME_CONFIG.
	/// @reads global.metronome_volume, global.METRONOME_CONFIG, global.current_set, global.current_set_item_index
	/// @writes global.metronome_volume, global.METRONOME_CONFIG.velocity_emphasis, global.METRONOME_CONFIG.velocity_normal, global.current_set[idx]
	/// @callers scr_handle_button_click (button 16)
	function scr_metronome_volume_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var min_volume = real(scr_button_field_get(field, "field_min_value", 0));
		var max_volume = real(scr_button_field_get(field, "field_max_value", 127));
		var new_volume = global.metronome_volume + (button_click_value * 10);
		new_volume = clamp(new_volume, min_volume, max_volume);

		global.metronome_volume = new_volume;
		scr_button_field_set(field, "field_value", new_volume);
		scr_button_field_set(field, "field_contents", string(new_volume));

		global.METRONOME_CONFIG.velocity_emphasis = new_volume;
		global.METRONOME_CONFIG.velocity_normal = floor(new_volume * 0.7);

		scr_button_write_setting_to_active_segment("metronome_volume", global.metronome_volume);
		if (!scr_button_is_set_mode()) {
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Metronome volume: " + string(new_volume));
	}

	//CASE 17 - Tune BPM
	/// @function scr_tune_bpm_change(_ctx)
	/// @description Change the current BPM via +/- field button.
	/// @reads global.current_set, global.current_set_item_index
	/// @writes global.current_bpm, global.current_set[idx]
	/// @callers scr_handle_button_click (button 17)
	function scr_tune_bpm_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 120));
		var min_value = real(scr_button_field_get(field, "field_min_value", 1));
		var max_value = real(scr_button_field_get(field, "field_max_value", 300));
		var new_val = clamp(field_value + button_click_value, min_value, max_value);

		scr_button_field_set(field, "field_value", new_val);
		scr_button_field_set(field, "field_contents", string(new_val));
		global.current_bpm = new_val;
		global.single_tune_runtime_bpm = new_val;

		scr_button_write_setting_to_active_segment("bpm", global.current_bpm);
		scr_button_force_single_runtime_settings_sync();
		scr_set_builder_writeback_field_to_selected_slot("metro_field_3", new_val);
		var save_override_script = asset_get_index("scoring_tune_override_save_current");
		if (script_exists(save_override_script)) {
			var override_filename = scr_button_get_single_tune_override_target_filename();
			script_execute(save_override_script, override_filename);
		}
		var _bpm_is_set_mode = scr_button_is_set_mode();
		if (!_bpm_is_set_mode) {
			scr_button_prepare_single_tune_playback_events();
		}

		scr_button_bpm_debug_log("[BPM-CHANGE] field->global: new_val=" + string(new_val) + " is_set_mode=" + string(_bpm_is_set_mode));
	}

	//CASE 18 - Tune Count-In
	/// @function scr_tune_countin_change(_ctx)
	/// @description Change the count-in measure count. In set mode updates active_set.set_count_in_measures.
	/// @reads global.current_set, global.current_set_item_index, global.active_set
	/// @writes global.count_in_measures, global.active_set.set_count_in_measures (set mode), global.current_set[idx]
	/// @callers scr_handle_button_click (button 18)
	function scr_tune_countin_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		var new_val = clamp(field_value + button_click_value, 0, 2);
		scr_button_field_set(field, "field_value", new_val);
		scr_button_field_set(field, "field_contents", string(new_val));

		global.count_in_measures = new_val;
		if (scr_set_is_active()) {
			// Set mode: count-in applies to whole set (first tune only), not per-tune
			global.active_set.set_count_in_measures = new_val;
		} else {
			scr_button_write_setting_to_active_segment("count_in_measures", global.count_in_measures);
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Count-in measures: " + string(new_val));
	}

	//CASE 19 - Gracenote Override (ms)
	/// @function scr_gracenote_override_change(_ctx)
	/// @description Change the gracenote timing override in ms via +/- field button.
	/// @reads global.current_set, global.current_set_item_index
	/// @writes global.gracenote_override_ms, global.current_set[idx]
	/// @callers scr_handle_button_click (button 19)
	function scr_gracenote_override_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		var min_value = real(scr_button_field_get(field, "field_min_value", 0));
		var max_value = real(scr_button_field_get(field, "field_max_value", 500));
		var new_val = clamp(field_value + button_click_value, min_value, max_value);

		scr_button_field_set(field, "field_value", new_val);
		scr_button_field_set(field, "field_contents", string(new_val));
		global.gracenote_override_ms = new_val;

		scr_button_write_setting_to_active_segment("gracenote_override_ms", global.gracenote_override_ms);
		scr_button_force_single_runtime_settings_sync();
		scr_set_builder_writeback_field_to_selected_slot("metro_field_7", new_val);
		var save_override_script = asset_get_index("scoring_tune_override_save_current");
		if (script_exists(save_override_script)) {
			var override_filename = scr_button_get_single_tune_override_target_filename();
			script_execute(save_override_script, override_filename);
		}
		if (!scr_button_is_set_mode()) {
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Gracenote override (ms): " + string(new_val));
	}

	//CASE 20 - Swing Multiplier
	/// @function scr_swing_mult_change(_ctx)
	/// @description Change the swing multiplier via +/- field button.
	/// @reads global.current_set, global.current_set_item_index
	/// @writes global.swing_mult, global.current_set[idx]
	/// @callers scr_handle_button_click (button 20)
	function scr_swing_mult_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		var min_value = real(scr_button_field_get(field, "field_min_value", 0));
		var max_value = real(scr_button_field_get(field, "field_max_value", 4));
		var new_val = clamp(field_value + button_click_value, min_value, max_value);

		scr_button_field_set(field, "field_value", new_val);
		scr_button_field_set(field, "field_contents", string(new_val));
		global.swing_mult = new_val;

		scr_button_write_setting_to_active_segment("swing_mult", global.swing_mult);
		scr_button_force_single_runtime_settings_sync();
		scr_set_builder_writeback_field_to_selected_slot("metro_field_6", new_val);
		var save_override_script = asset_get_index("scoring_tune_override_save_current");
		if (script_exists(save_override_script)) {
			var override_filename = scr_button_get_single_tune_override_target_filename();
			script_execute(save_override_script, override_filename);
		}
		if (!scr_button_is_set_mode()) {
			scr_button_prepare_single_tune_playback_events();
		}

		show_debug_message("Swing multiplier: " + string(new_val));
	}

	//CASE 21 - Current-note measure scroll
	/// @function scr_current_note_measure_scroll(_ctx)
	/// @description Scroll the current-note measure panel forward or back.
	/// @reads global.current_note_panel
	/// @callers scr_handle_button_click (button 21)
	function scr_current_note_measure_scroll(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;

		var delta = real(scr_button_inst_get(ctx, "button_click_value", 0));
		if (delta == 0) return;

		var previous_measure = real(scr_button_struct_get(global.current_note_panel, "current_measure", 1));
		var next_measure = cn_panel_scroll_measure(delta);
		show_debug_message("Current-note measure: " + string(previous_measure) + " -> " + string(next_measure));
	}

	//CASE 22 - Notebeam zoom controls (+/-)
	/// @function scr_notebeam_zoom_change(_ctx)
	/// @description Zoom the notebeam timeline in/out via gv_notebeam_zoom_by_steps.
	/// @callers scr_handle_button_click (button 22)
	function scr_notebeam_zoom_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) {
			show_debug_message("Notebeam zoom is locked during active playback.");
			return;
		}

		var steps = real(scr_button_inst_get(ctx, "button_click_value", 0));
		if (steps == 0) return;

		var changed = gv_notebeam_zoom_by_steps(steps);
		if (changed) {
			if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
				scoring_player_settings_save_for_player();
			}
			if (!scr_button_is_set_mode()) {
				var save_override_script = asset_get_index("scoring_tune_override_save_current");
				if (script_exists(save_override_script)) {
					var override_filename = scr_button_get_single_tune_override_target_filename();
					script_execute(save_override_script, override_filename);
				}
			}
			show_debug_message("Notebeam zoom step: " + string(steps));
		}
	}

	//CASE 23 - Notebeam pan controls (left/right)
	/// @function scr_notebeam_pan_scroll(_ctx)
	/// @description Pan the notebeam timeline left/right via gv_notebeam_pan_by_steps.
	/// @callers scr_handle_button_click (button 23)
	function scr_notebeam_pan_scroll(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;
		if (script_exists(asset_get_index("gv_is_live_playback")) && gv_is_live_playback()) return;

		var steps = real(scr_button_inst_get(ctx, "button_click_value", 0));
		if (steps == 0) return;

		var changed = gv_notebeam_pan_by_steps(steps);
		if (changed) {
			show_debug_message("Notebeam pan step: " + string(steps));
		}
	}

	//CASE 40 - Notebeam view-ahead change (+/-)
	/// @function scr_viewport_ahead_change(_ctx)
	/// @description Adjust global.timeline_cfg.time_ahead_ms by the button step (from button_click_value, e.g. ±50/±500 ms), clamped 500..30000. Keeps time_behind_ms locked to half of ahead, updates both field displays, and syncs the notebeam window.
	/// @callers scr_handle_button_click (button 40)
	function scr_viewport_ahead_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var delta_ms = real(scr_button_inst_get(ctx, "button_click_value", 0));
		if (delta_ms == 0) return;

		var cfg = gv_ensure_timeline_cfg_defaults();
		var cur_ms = real(variable_struct_get(cfg, "time_ahead_ms") ?? 4500);
		var new_ms = clamp(cur_ms + delta_ms, 500, 30000);
		variable_struct_set(cfg, "time_ahead_ms", new_ms);
		var behind_ms = clamp(round(new_ms * 0.5), 250, 15000);
		variable_struct_set(cfg, "time_behind_ms", behind_ms);

		// Re-sync runtime window if active
		if (script_exists(asset_get_index("gv_notebeam_sync_window_from_cfg"))) {
			gv_notebeam_sync_window_from_cfg();
		}

		// Update field display
		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) field = scr_button_find_field_by_ui_name("setting_field_view_ahead");
		if (instance_exists(field)) {
			scr_button_field_set(field, "field_value", new_ms);
			scr_button_field_set(field, "field_contents", string_format(new_ms / 1000, 1, 2));
		}

		if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
			scoring_player_settings_save_for_player();
		}
		show_debug_message("Viewport ahead: " + string(new_ms) + " ms");
	}

	//CASE 9
	/// @function scr_settings_OK(_ctx)
	/// @description Open the selected MIDI devices (from settings window) and save player settings.
	/// @reads global.midi_input_device, global.midi_output_device
	/// @callers scr_handle_button_click (button 9)
	function scr_settings_OK(_ctx = noone)	{
	//Set the choices that were made in the settings window.
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		midi_input_device_open(global.midi_input_device);
		midi_output_device_open(global.midi_output_device);
		if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
			scoring_player_settings_save_for_player();
		}

		var button_label = string(scr_button_inst_get(ctx, "button_label", ""));
		if (!scr_hide_window(button_label, ctx)) {
			show_debug_message("Warning! - scr_settings_OK: could not find layer to hide for target: " + button_label);
		}
	}	

	/// @function scr_judge_settings_OK(_ctx)
	/// @description Save judge profile settings for the current player and close the judge settings layer.
	/// @callers scr_handle_button_click (button 25)
	function scr_judge_settings_OK(_ctx = noone) {
		var _save_idx = asset_get_index("scoring_judge_settings_save_for_player");
		if (script_exists(_save_idx)) {
			script_execute(_save_idx);
		}

		var _layer_name = "judge_settings_layer";
		var _lid = layer_get_id(_layer_name);
		if (_lid != -1) {
			layer_set_visible(_lid, false);
			instance_deactivate_layer(_lid);
		}
	}

	/// @function scr_select_player(_ctx)
	/// @description Switch the active player, save/load their judge and performance settings.
	/// @reads global.player_names
	/// @writes global.current_player_index, global.current_player_id
	/// @callers scr_handle_button_click (button 27)
	function scr_select_player(_ctx = noone) {
		var idx = real(scr_button_inst_get(_ctx, "button_click_value", 0));

		// Save outgoing player's judge settings before switching
		if (script_exists(asset_get_index("scoring_judge_settings_save_for_player"))) {
			scoring_judge_settings_save_for_player();
		}
		if (script_exists(asset_get_index("scoring_player_settings_save_for_player"))) {
			scoring_player_settings_save_for_player();
		}

		global.current_player_index = idx;
		var name = global.player_names[idx];
		global.current_player_id = string_lower(string_replace_all(name, " ", "_"));

		// Load incoming player's judge settings
		if (script_exists(asset_get_index("scoring_judge_settings_load_for_player"))) {
			scoring_judge_settings_load_for_player();
		}
		if (script_exists(asset_get_index("scoring_player_settings_load_for_player"))) {
			scoring_player_settings_load_for_player();
		}
		if (script_exists(asset_get_index("scoring_tune_overrides_load_for_player"))) {
			scoring_tune_overrides_load_for_player();
		}
		if (!scr_set_is_active() && script_exists(asset_get_index("scoring_tune_override_apply_current"))) {
			scoring_tune_override_apply_current();
		}

		scr_open_window(6);  // closes the player popup
		scr_player_button_label_refresh();
	}

	/// @function scr_player_button_label_refresh()
	/// @description Update the player button label instance text to match the current player name.
	/// @reads global.current_player_index, global.player_names, global.ui_text_refs
	/// @callers scr_select_player
	function scr_player_button_label_refresh() {
		if (!variable_global_exists("current_player_index")) exit;
		if (!variable_global_exists("ui_text_refs")) exit;
		if (!variable_struct_exists(global.ui_text_refs, "player_btn")) exit;
		var label = global.player_names[global.current_player_index];
		var inst = global.ui_text_refs[$ "player_btn"];
		if (instance_exists(inst)) inst.label_text = label;
	}

	/// @function scr_player_clear_history(_player_id)
	/// @description Remove all performance history for a given player_id.
	///   - Strips that player's context entries from tune_history_index.json.
	///   - Deletes their per-run _summary.json files from all tune performance folders.
	///   - CSV files are left intact (they are for external analysis only).
	///   - To clear ALL players at once, manually delete datafiles/performances/ and
	///     datafiles/config/players/.
	/// @callers scr_player_clear_guest_history, scr_handle_button_click (button 28 → scr_player_clear_guest_history)
	function scr_player_clear_history(_player_id) {
		var target = string_lower(string_trim(string(_player_id ?? "")));
		if (target == "") {
			show_debug_message("[PLAYER_CLEAR] Skipped: empty player_id.");
			return false;
		}

		var deleted_summaries = 0;
		var perf_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
			? scr_data_paths_get_category_root("performances")
			: "datafiles/performances/";
		if (string_copy(perf_root, string_length(perf_root), 1) == "/") {
			perf_root = string_copy(perf_root, 1, string_length(perf_root) - 1);
		}

		// --- 1. Delete player's summary JSON files from all tune folders ---
		if (directory_exists(perf_root)) {
			var tune_dir = file_find_first(perf_root + "/*", fa_directory);
			while (tune_dir != "") {
				if (tune_dir != "." && tune_dir != "..") {
					var tune_folder = perf_root + "/" + tune_dir;
					if (directory_exists(tune_folder)) {
						var summary_file = file_find_first(tune_folder + "/*_summary.json", 0);
						while (summary_file != "") {
							var filepath = tune_folder + "/" + summary_file;
							var summary = scr_tune_parse_json_file(filepath);
							if (is_struct(summary)) {
								var file_player = string_lower(string_trim(string(event_history_struct_get(summary, "player_id", ""))));
								if (file_player == target) {
									file_delete(filepath);
									deleted_summaries++;
								}
							}
							summary_file = file_find_next();
						}
						file_find_close();
					}
				}
				tune_dir = file_find_next();
			}
			file_find_close();
		}

		// --- 2. Strip player's context entries from tune_history_index.json ---
		var history_index = event_history_load_tune_history_index();
		var tunes = variable_struct_exists(history_index, "tunes") ? variable_struct_get(history_index, "tunes") : [];
		var removed_contexts = 0;

		if (is_array(tunes)) {
			for (var i = 0; i < array_length(tunes); i++) {
				var tune_entry = tunes[i];
				if (!is_struct(tune_entry)) continue;
				if (!variable_struct_exists(tune_entry, "contexts")) continue;

				var contexts = variable_struct_get(tune_entry, "contexts");
				if (!is_array(contexts)) continue;

				var kept = array_create(0);
				for (var ci = 0; ci < array_length(contexts); ci++) {
					var ctx = contexts[ci];
					if (!is_struct(ctx)) continue;
					var ctx_player = string_lower(string_trim(string(event_history_struct_get(ctx, "player_id", ""))));
					if (ctx_player == target) {
						removed_contexts++;
					} else {
						array_push(kept, ctx);
					}
				}
				variable_struct_set(tune_entry, "contexts", kept);
				tunes[i] = tune_entry;
			}
			variable_struct_set(history_index, "tunes", tunes);
			event_history_store_tune_history_index(history_index);
		}

		show_debug_message("[PLAYER_CLEAR] player=" + target
			+ " deleted_summaries=" + string(deleted_summaries)
			+ " removed_contexts=" + string(removed_contexts));
		return true;
	}

	/// @function scr_player_clear_guest_history()
	/// @description Convenience wrapper to clear history for the Guest player.
	/// @callers scr_handle_button_click (button 28)
	function scr_player_clear_guest_history() {
		return scr_player_clear_history("guest");
	}

	/// @function scr_button_resolve_picker_selection()
	/// @description Get the selected tune entry from the active obj_tune_picker instance.
	/// @returns Struct { picker, library, selected_index, entry }
	/// @objects obj_tune_picker (instance_find)
	/// @callers scr_tune_OK
	function scr_button_resolve_picker_selection() {
		var result = {
			picker: noone,
			library: undefined,
			selected_index: -1,
			entry: undefined
		};

		result.picker = instance_find(obj_tune_picker, 0);
		if (result.picker == noone) return result;

		result.entry = scr_tune_picker_get_selected_entry();
		result.library = scr_tune_picker_get_library(result.picker);
		result.selected_index = real(scr_tune_picker_get_instance_var(result.picker, "selected_index", -1));

		var library_tunes = scr_button_struct_get(result.library, "tunes", array_create(0));
		if (!is_struct(result.entry)
			&& is_array(library_tunes)
			&& result.selected_index >= 0
			&& result.selected_index < array_length(library_tunes)) {
			result.entry = library_tunes[result.selected_index];
		}

		return result;
	}

	/// @function scr_button_get_single_tune_override_target_filename()
	/// @description Resolve the selected tune filename to use when saving single-tune player overrides from the picker UI.
	/// @returns {string} Selected picker filename when available, otherwise current_tune_filename, otherwise ""
	/// @reads global.current_tune_filename
	/// @objects obj_tune_picker
	/// @callers scr_tune_bpm_change, scr_gracenote_override_change, scr_swing_mult_change
	function scr_button_get_single_tune_override_target_filename() {
		var selection = scr_button_resolve_picker_selection();
		if (is_struct(selection.entry)) {
			var selected_filename = string(scr_button_struct_get(selection.entry, "filename", ""));
			if (selected_filename != "") return selected_filename;
		}

		if (variable_global_exists("current_tune_filename")) {
			var current_filename = string(global.current_tune_filename);
			if (current_filename != "") return current_filename;
		}

		return "";
	}

	/// @function scr_button_build_tune_load_candidates(_library, _filename)
	/// @description Build an ordered list of file paths to try when loading a tune by filename.
	/// @returns Array of candidate path strings
	/// @callers scr_tune_OK, scr_button_try_load_tune_candidate
	function scr_button_build_tune_load_candidates(_library, _filename) {
		var candidates = array_create(0);
		var library_root = string(scr_button_struct_get(_library, "root", ""));
		if (library_root != "") {
			array_push(candidates, library_root + _filename);
		}
		array_push(candidates, "tunes/" + _filename);
		array_push(candidates, (script_exists(asset_get_index("scr_data_paths_get_category_root"))
			? scr_data_paths_get_category_root("tunes")
			: "datafiles/tunes/") + _filename);
		return candidates;
	}

	/// @function scr_button_apply_set_item_from_ui_fields(_item)
	/// @description Write current UI field values into a set item struct. In set mode, count-in is written to active_set instead.
	/// @reads global.active_set (set mode check)
	/// @writes global.active_set.set_count_in_measures (set mode only)
	/// @objects obj_field_base (iterated via instance_find)
	/// @callers scr_tune_OK
	function scr_button_apply_set_item_from_ui_fields(_item) {
		var field_count = instance_number(obj_field_base);
		for (var fi = 0; fi < field_count; fi++) {
			var field_inst = instance_find(obj_field_base, fi);
			if (field_inst == noone) continue;
			var field_ui_name = string(scr_button_inst_get(field_inst, "ui_name", ""));
			var field_val = scr_button_field_get(field_inst, "field_value", 0);

			if (field_ui_name == "tune_BPM_field" || field_ui_name == "metro_field_3") {
				scr_button_struct_set(_item, "bpm", field_val);
			}
			if (field_ui_name == "tune_countin_field" || field_ui_name == "metro_field_4") {
				// In set mode count-in is set-level only — don't write to individual tune items
				if (scr_set_is_active()) {
					global.active_set.set_count_in_measures = real(field_val);
				} else {
					scr_button_struct_set(_item, "count_in_measures", field_val);
				}
			}
			if (field_ui_name == "tune_loopjump_field" || field_ui_name == "metro_field_8") {
				scr_button_struct_set(_item, "loop_jump_to_selection", (real(field_val) >= 1));
			}
			if (field_ui_name == "metro_field_1") scr_button_struct_set(_item, "metronome_mode", field_val);
			if (field_ui_name == "metro_field_2") scr_button_struct_set(_item, "metronome_pattern", field_val);
			if (field_ui_name == "metro_field_5") scr_button_struct_set(_item, "metronome_volume", field_val);
			if (field_ui_name == "metro_field_6") scr_button_struct_set(_item, "swing_mult", field_val);
			if (field_ui_name == "metro_field_7") scr_button_struct_set(_item, "gracenote_override_ms", field_val);
		}
	}

	/// @function scr_button_apply_globals_from_set_item(_item)
	/// @description Copy playback settings from a set item struct into their respective globals.
	/// @writes global.current_bpm, global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume, global.count_in_measures, global.loop_jump_to_selection, global.swing_mult, global.gracenote_override_ms
	/// @callers scr_button_try_load_tune_candidate
	function scr_button_apply_globals_from_set_item(_item) {
		global.current_bpm = scr_button_struct_get(_item, "bpm", 120);
		global.metronome_mode = scr_button_struct_get(_item, "metronome_mode", global.metronome_mode);
		global.metronome_pattern_selection = scr_button_struct_get(_item, "metronome_pattern", global.metronome_pattern_selection);
		global.metronome_volume = scr_button_struct_get(_item, "metronome_volume", global.metronome_volume);
		// In set mode count-in is set-level — don't overwrite global from the per-tune item
		if (!scr_set_is_active()) {
			global.count_in_measures = scr_button_struct_get(_item, "count_in_measures", 0);
		}
		global.loop_jump_to_selection = scr_button_struct_get(_item, "loop_jump_to_selection", false);
		global.swing_mult = scr_button_struct_get(_item, "swing_mult", 1);
		global.gracenote_override_ms = scr_button_struct_get(_item, "gracenote_override_ms", 0);
	}

	/// @function scr_button_apply_post_tune_load_ui(_button_label, _entry)
	/// @description Hide the tune window layer and update the gameinfo title field from the entry.
	/// @writes global.gameinfo_title[0]
	/// @callers scr_button_try_load_tune_candidate
	function scr_button_apply_post_tune_load_ui(_button_label, _entry) {
		if (is_string(_button_label) && layer_get_id(_button_label) != -1) {
			layer_set_visible(_button_label, 0);
		}

		var entry_title = scr_button_struct_get(_entry, "title", undefined);
		if (!is_undefined(entry_title)) {
			global.gameinfo_title[0] = entry_title;
			scr_update_fields(3);
		}
	}

	/// @function scr_button_try_load_tune_candidate(_tryfile, _entry, _button_label, _force_tune_defaults)
	/// @description Try to load a tune from the given file path; if successful, apply set item globals and update UI.
	/// @returns true if load succeeded, false otherwise
	/// @reads global.tune (loaded tune instance)
	/// @writes global.current_set, global.current_set_item_index, global.current_tune_filename, global.current_bpm, global.swing_mult, global.gracenote_override_ms
	/// @objects obj_tune (reads tune_data after scr_tune_load_json)
	/// @callers scr_tune_OK, scr_tune_reset_to_defaults
	function scr_button_try_load_tune_candidate(_tryfile, _entry, _button_label, _force_tune_defaults = false) {
		var _loaded = (is_struct(_entry) && scr_button_struct_get(_entry, "manifest_backed", false))
			? scr_tune_load_compiled_json(_tryfile)
			: scr_tune_load_json(_tryfile);
		if (!_loaded) return false;

		var item = create_set_item(_tryfile);
		var loaded_tune_data = scr_button_tune_data_get(global.tune);
		var perf = scr_button_struct_get(loaded_tune_data, "performance", undefined);
		var meta = scr_button_struct_get(loaded_tune_data, "tune_metadata", undefined);
		var default_swing = scr_button_struct_get(perf, "swing", scr_button_struct_get(meta, "swing", ""));
		if (!is_undefined(default_swing) && string(default_swing) != "") {
			scr_button_struct_set(item, "swing_mult", default_swing);
		}

		scr_button_apply_set_item_from_ui_fields(item);

		// Clear any previously-loaded set so play uses single-tune path
		scr_set_init_global();

		global.current_set = [item];
		global.current_set_item_index = 0;
		scr_button_apply_globals_from_set_item(item);
		global.single_tune_runtime_bpm = global.current_bpm;
		scr_button_sync_single_tune_settings_segment(item);

		var tune_key = string(scr_button_struct_get(_entry, "filename", ""));
		if (tune_key == "") tune_key = _tryfile;
		global.current_tune_filename = tune_key;
		if (!_force_tune_defaults && script_exists(asset_get_index("scoring_tune_override_apply_current"))) {
			scoring_tune_override_apply_current(tune_key);
			scr_button_struct_set(item, "bpm", global.current_bpm);
			scr_button_struct_set(item, "swing_mult", global.swing_mult);
			scr_button_struct_set(item, "gracenote_override_ms", global.gracenote_override_ms);
			global.current_set[0] = item;
			scr_button_sync_single_tune_settings_segment(item);
		} else if (_force_tune_defaults) {
			var default_bpm = 120;
			var tempo_str = string(scr_button_struct_get(meta, "tempo_default", ""));
			if (string_length(tempo_str) > 0) default_bpm = real(tempo_str);

			default_swing = scr_button_struct_get(perf, "swing", scr_button_struct_get(meta, "swing", 0));
			if (is_undefined(default_swing) || string(default_swing) == "") default_swing = 0;

			var default_grace = scr_button_struct_get(perf, "gracenote_override_ms", scr_button_struct_get(meta, "gracenote_override_ms", scr_button_struct_get(meta, "gracenote_ms", 0)));
			if (is_undefined(default_grace) || string(default_grace) == "") default_grace = 0;

			global.current_bpm = max(1, real(default_bpm));
			global.single_tune_runtime_bpm = global.current_bpm;
			global.swing_mult = max(0, real(default_swing));
			global.gracenote_override_ms = max(0, real(default_grace));

			scr_button_struct_set(item, "bpm", global.current_bpm);
			scr_button_struct_set(item, "swing_mult", global.swing_mult);
			scr_button_struct_set(item, "gracenote_override_ms", global.gracenote_override_ms);
			global.current_set[0] = item;
			scr_button_sync_single_tune_settings_segment(item);

			var save_override_script = asset_get_index("scoring_tune_override_save_current");
			if (script_exists(save_override_script)) {
				script_execute(save_override_script, tune_key);
			}

			if (script_exists(asset_get_index("scr_tune_picker_sync_selected_entry_ui"))) {
				scr_tune_picker_sync_selected_entry_ui();
			}
		}

		scr_button_apply_post_tune_load_ui(_button_label, _entry);
		return true;
	}
	
	//CASE 10  THis OK button in the tune window locks in the selected 
	/// @function scr_tune_OK(_ctx)
	/// @description Confirm tune selection from picker: load the tune, apply globals, and hide the tune window.
	/// @reads global.tune (after load)
	/// @writes global.current_tune_filename
	/// @objects obj_tune_picker (reads selection), obj_tune (after load)
	/// @callers scr_handle_button_click (button 10)
	function scr_tune_OK(_ctx = noone)	{
	//Set the choices that were made in the settings window.
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var saved_button_label = string(scr_button_inst_get(ctx, "button_label", ""));
		var button_label = saved_button_label;
		if (!is_string(button_label) || layer_get_id(button_label) == -1) {
			var ui_layer_num = real(scr_button_inst_get(ctx, "ui_layer_num", -1));
			if (ui_layer_num >= 0) {
				button_label = GetLayerNameFromIndex(ui_layer_num);
				scr_button_inst_set(ctx, "button_label", button_label);
			}
		}

		// --- Sets mode: arm global.active_set so scr_goto_playroom plays the whole set ---
		var _ok_picker = instance_find(obj_tune_picker, 0);
		if (_ok_picker != noone && string(scr_tune_picker_get_instance_var(_ok_picker, "view_mode", "tunes")) == "sets") {
			var _ok_slots = scr_tune_picker_get_instance_var(_ok_picker, "set_builder_slots", []);
			if (array_length(_ok_slots) > 0) {
				// Populate global.active_set from all builder slots
				var _armed = scr_set_builder_arm_for_play();
				if (_armed) {
					// Also load slot[0] into global.tune so main-menu UI has something to show
					scr_set_builder_sync_fields_from_slot(0);
					var _ok_slot0 = _ok_slots[0];
					var _ok_fname = string(scr_button_struct_get(_ok_slot0, "filename", ""));
					var _ok_lib   = scr_tune_picker_get_library(_ok_picker);
					var _ok_tunes = scr_tune_library_get_tunes(_ok_lib);
					var _ok_entry = undefined;
					if (is_array(_ok_tunes)) {
						for (var _ok_i = 0; _ok_i < array_length(_ok_tunes); _ok_i++) {
							if (string(scr_button_struct_get(_ok_tunes[_ok_i], "filename", "")) == _ok_fname) {
								_ok_entry = _ok_tunes[_ok_i];
								break;
							}
						}
					}
					if (is_struct(_ok_entry)) {
						var _ok_cands = scr_button_build_tune_load_candidates(_ok_lib, _ok_fname);
						for (var _ok_ci = 0; _ok_ci < array_length(_ok_cands); _ok_ci++) {
							if (scr_tune_load_json(_ok_cands[_ok_ci])) {
								global.current_tune_filename = _ok_fname;
								break;
							}
						}
					}
					if (!scr_hide_window(button_label, ctx)) {
						show_debug_message("Warning! scr_tune_OK sets mode: could not hide window.");
					}
				} else {
					show_debug_message("scr_tune_OK sets mode: arm_for_play failed.");
				}
			} else {
				show_debug_message("scr_tune_OK sets mode: no slots to play.");
			}
			scr_button_inst_set(ctx, "button_label", saved_button_label);
			return;
		}

		var picker_selection = scr_button_resolve_picker_selection();
		var library = picker_selection.library;
		var entry = picker_selection.entry;
		var force_tune_defaults = keyboard_check(vk_shift) && !scr_set_is_active();

		if (is_struct(entry)) {
			var filename = string(scr_button_struct_get(entry, "filename", ""));
			if (filename == "") {
				show_debug_message("No tune filename selected in picker entry.");
			} else {
				var candidates = scr_button_build_tune_load_candidates(library, filename);

			    var loaded = false;
			    for (var i = 0; i < array_length(candidates) && !loaded; i++) {
			        var tryfile = candidates[i];
		        loaded = scr_button_try_load_tune_candidate(tryfile, entry, button_label, force_tune_defaults);
			    }

				if (!loaded) {
					show_debug_message("Failed to load tune from candidates.");
				} else if (!scr_hide_window(button_label, ctx)) {
					show_debug_message("Warning! - scr_tune_OK: could not find layer to hide for target: " + string(button_label));
				}
			}
		} else {
			show_debug_message("No tune selected in picker.");
		}

		scr_button_inst_set(ctx, "button_label", saved_button_label);
	}	

	//CASE 26
	/// @function scr_tune_reset_to_defaults(_ctx)
	/// @description Reset selected single-tune BPM/swing/gracenote to tune defaults and persist as the current player's override.
	/// @reads global.tune_library, global.current_tune_filename
	/// @writes global.current_bpm, global.swing_mult, global.gracenote_override_ms, global.current_set
	/// @objects obj_tune_picker
	/// @callers scr_handle_button_click (button 26)
	function scr_tune_reset_to_defaults(_ctx = noone) {
		if (scr_set_is_active()) return;

		var ctx = scr_button_get_ctx(_ctx);
		var button_label = ctx != noone ? string(scr_button_inst_get(ctx, "button_label", "")) : "";
		if (button_label == "" && ctx != noone) {
			var ui_layer_num = real(scr_button_inst_get(ctx, "ui_layer_num", -1));
			if (ui_layer_num >= 0) button_label = GetLayerNameFromIndex(ui_layer_num);
		}

		var picker_selection = scr_button_resolve_picker_selection();
		if (!is_struct(picker_selection.entry)) return;

		var filename = string(scr_button_struct_get(picker_selection.entry, "filename", ""));
		if (filename == "") return;

		var candidates = scr_button_build_tune_load_candidates(picker_selection.library, filename);
		for (var i = 0; i < array_length(candidates); i++) {
			if (scr_button_try_load_tune_candidate(candidates[i], picker_selection.entry, button_label, true)) {
				show_debug_message("Reset tune defaults for " + filename + " to bpm=" + string(global.current_bpm)
					+ " swing=" + string(global.swing_mult)
					+ " grace_ms=" + string(global.gracenote_override_ms));
				return;
			}
		}
	}
	
	//CASE 11
	/// @function scr_button_prepare_single_tune_playback_events()
	/// @description Rebuild global.playback_events from canonical tune_data using current BPM/swing/grace/count-in settings; fail fast when preprocessing yields no tune events.
	/// @returns {bool} true when non-empty events were rebuilt; false when the tune is unavailable or preprocessing fails
	/// @reads global.tune, global.current_set, global.current_set_item_index, global.current_bpm, global.swing_mult, global.gracenote_override_ms
	/// @writes global.playback_events
	/// @objects obj_tune
	/// @callers start_play, scr_tune_bpm_change
	function scr_button_prepare_single_tune_playback_events() {
		scr_button_force_single_runtime_settings_sync();
		var tune = global.tune;
		var tune_data = scr_button_tune_data_get(tune);
		if (!(instance_exists(tune) && scr_button_tune_is_loaded(tune))) {
			global.playback_events = [];
			return false;
		}

		var _single_is_set_mode = scr_button_is_set_mode();
		var effective = scr_button_resolve_effective_settings(true);
		var bpm_override = real(scr_button_struct_get(effective, "bpm", variable_global_exists("current_bpm") ? global.current_bpm : 120));
		var overrides = {
			bpm: bpm_override,
			swing_mult: real(scr_button_struct_get(effective, "swing_mult", variable_global_exists("swing_mult") ? global.swing_mult : 0)),
			gracenote_override_ms: real(scr_button_struct_get(effective, "gracenote_override_ms", variable_global_exists("gracenote_override_ms") ? global.gracenote_override_ms : 0))
		};

		scr_button_bpm_debug_log("[EFFECTIVE-SETTINGS] bpm=" + string(overrides.bpm)
			+ " swing_mult=" + string(overrides.swing_mult)
			+ " grace_ms=" + string(overrides.gracenote_override_ms)
			+ " metro_mode=" + string(scr_button_struct_get(effective, "metronome_mode", 0))
			+ " metro_pattern=" + string(scr_button_struct_get(effective, "metronome_pattern", 0))
			+ " metro_volume=" + string(scr_button_struct_get(effective, "metronome_volume", 100))
			+ " count_in=" + string(scr_button_struct_get(effective, "count_in_measures", 0))
			+ " mode=" + (_single_is_set_mode ? "set" : "single_virtual_set"));

		var _authored = scr_button_struct_get(tune_data, "authored", {});
		var tune_events = variable_struct_exists(tune_data, "compiled")
			&& is_struct(scr_button_struct_get(tune_data, "compiled", undefined))
			? run_build(scr_button_struct_get(tune_data, "compiled", {}), {
				bpm: bpm_override,
				base_midi: 55,
				default_channel: 2,
				pointing_id: string(scr_button_struct_get(_authored, "pointing_id", "written")),
				pulse_id: string(scr_button_struct_get(_authored, "pulse_id",
					scr_button_struct_get(_authored, "pulse_profile_id", ""))),
				grouping_id: string(scr_button_struct_get(_authored, "grouping_id", ""))
			})
			: scr_preprocess_tune(tune_data, overrides);
		if (!is_array(tune_events) || array_length(tune_events) <= 0) {
			global.playback_events = [];
			show_debug_message("ERROR: Playback preparation produced no tune events.");
			return false;
		}

		var metronome_settings = {
			bpm: bpm_override,
			metronome_mode: real(scr_button_struct_get(effective, "metronome_mode", 0)),
			metronome_pattern: real(scr_button_struct_get(effective, "metronome_pattern", 0)),
			metronome_volume: real(scr_button_struct_get(effective, "metronome_volume", 100))
		};

		var metronome_events = metronome_generate_events({
			events: tune_events,
			tune_data: tune_data
		}, metronome_settings);

		var countin_events = array_create(0);
		var count_in_measures = real(scr_button_struct_get(effective, "count_in_measures", 0));
		if (count_in_measures > 0) {
			var meta = scr_button_struct_get(tune_data, "tune_metadata", undefined);
			var time_sig = metronome_normalize_time_sig(scr_button_struct_get(meta, "meter", "4/4"));
			var time_sig_parts = string_split(time_sig, "/");
			var beats_per_measure = real(time_sig_parts[0]);
			var denom = real(time_sig_parts[1]);
			var tempo_str = string(scr_button_struct_get(meta, "tempo_default", ""));
			var bpm_effective = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
			if (!is_undefined(bpm_override)) bpm_effective = real(bpm_override);
			var quarter_bpm_effective = metronome_get_effective_quarter_bpm(bpm_effective, time_sig);
			var ms_per_quarter = 60000 / quarter_bpm_effective;
			var beat_unit_ms = ms_per_quarter * (4 / denom);
			var count_in_ms = count_in_measures * beats_per_measure * beat_unit_ms;

			countin_events = metronome_generate_countin_events({
				events: tune_events,
				tune_data: tune_data
			}, metronome_settings, count_in_measures);

			var pickup_start_ms = 0;
			for (var i = 0; i < array_length(tune_events); i++) {
				var ev = tune_events[i];
				var ev_type = string(scr_button_struct_get(ev, "type", ""));
				var ev_marker_type = string(scr_button_struct_get(ev, "marker_type", ""));
				var ev_measure = real(scr_button_struct_get(ev, "measure", 0));
				if (ev_type == "marker"
					&& ev_marker_type == "bar"
					&& ev_measure == 1) {
					pickup_start_ms = real(scr_button_struct_get(ev, "time", 0));
					break;
				}
			}
			if (pickup_start_ms == 0) {
				for (var i = 0; i < array_length(tune_events); i++) {
					var ev = tune_events[i];
					var ev_type = string(scr_button_struct_get(ev, "type", ""));
					var ev_measure = real(scr_button_struct_get(ev, "measure", 0));
					if (ev_type == "note_on" && ev_measure >= 1) {
						pickup_start_ms = real(scr_button_struct_get(ev, "time", 0));
						break;
					}
				}
			}

			var shift_ms = max(count_in_ms - pickup_start_ms, 0);
			for (var i = 0; i < array_length(tune_events); i++) {
				var tune_event = tune_events[i];
				var tune_event_time = real(scr_button_struct_get(tune_event, "time", 0));
				scr_button_struct_set(tune_event, "time", tune_event_time + shift_ms);
			}
			for (var i = 0; i < array_length(metronome_events); i++) {
				var metro_event = metronome_events[i];
				var metro_event_time = real(scr_button_struct_get(metro_event, "time", 0));
				scr_button_struct_set(metro_event, "time", metro_event_time + shift_ms);
			}
		}

		var total = array_length(tune_events) + array_length(metronome_events) + array_length(countin_events);
		var merged = array_create(total);
		var idx = 0;
		for (var i = 0; i < array_length(countin_events); i++) merged[idx++] = countin_events[i];
		for (var i = 0; i < array_length(tune_events); i++) merged[idx++] = tune_events[i];
		for (var i = 0; i < array_length(metronome_events); i++) merged[idx++] = metronome_events[i];

		array_sort(merged, function(a, b) {
			return real(scr_button_struct_get(a, "time", 0)) - real(scr_button_struct_get(b, "time", 0));
		});

		var _own_stats = scr_button_apply_event_ownership_metadata(merged);
		var _relabel_stats = scr_button_canonicalize_event_measure_labels(merged);
		show_debug_message("[OWNERSHIP] base annotate events=" + string(scr_button_struct_get(_own_stats, "events", 0))
			+ " annotated=" + string(scr_button_struct_get(_own_stats, "annotated", 0))
			+ " unresolved=" + string(scr_button_struct_get(_own_stats, "unresolved", 0))
			+ " nav_entries=" + string(scr_button_struct_get(_own_stats, "nav_entries", 0))
			+ " relabeled=" + string(scr_button_struct_get(_relabel_stats, "relabeled", 0))
			+ " marker_relabeled=" + string(scr_button_struct_get(_relabel_stats, "marker_relabeled", 0)));

		global.playback_events = merged;
		show_debug_message("[PLAYBACK-PREP] raw=" + string(array_length(scr_button_struct_get(tune_data, "events", [])))
			+ " tune=" + string(array_length(tune_events))
			+ " metronome=" + string(array_length(metronome_events))
			+ " countin=" + string(array_length(countin_events))
			+ " merged=" + string(array_length(merged)));
		
		// Sync playback_context to the rebuilt BPM so timeline reads current value
		// (in single-tune mode, context was built from JSON tempo_default at room entry, never refreshed)
		if (variable_global_exists("playback_context")
			&& is_struct(global.playback_context)
			&& is_array(global.playback_context.segments)
			&& array_length(global.playback_context.segments) > 0
			&& !is_undefined(bpm_override)) {
			global.playback_context.segments[0].bpm = real(bpm_override);
			scr_button_bpm_debug_log("[CONTEXT-SYNC] updated playback_context.segments[0].bpm to " + string(bpm_override));
		}
		
		return true;
	}

	/// @function start_play()
	/// @description Open MIDI devices, start MIDI polling, activate playback_events, bind timeline.
	/// @reads global.midi_output_device, global.midi_input_device, global.tune, global.timeline_cfg, global.selected_player_tune_channel, global.playback_events, global.loop_mode_enabled, global.playback_context
	/// @writes global.selected_player_tune_channel, global.timeline_cfg.tune_channel/player_channels, global.loop_runtime_active, global.loop_runtime_current_iteration, global.playback_events_active
	/// @objects obj_tune (checks is_loaded)
	/// @callers scr_handle_button_click (button 11)
	function start_play() {
		midi_output_device_open(global.midi_output_device);
		midi_input_device_open(global.midi_input_device);
		MIDI_start_manual_check_messages();
		show_debug_message("manual MIDI started");
		show_debug_message("input = " + string(global.midi_input_device));
		show_debug_message("tune start " + string(global.tune_selection));
		
		// global.tune is the obj_tune instance (not an array)
		var tune = global.tune;
		var _start_is_set_mode = variable_global_exists("playback_context")
			&& is_struct(global.playback_context)
			&& string(global.playback_context[$ "mode"] ?? "") == "set";
		scr_button_bpm_debug_log("[START-PLAY] mode_detected=" + (variable_global_exists("playback_context") && is_struct(global.playback_context) ? string(global.playback_context[$ "mode"] ?? "<none>") : "<no-context>") + " is_set_mode=" + string(_start_is_set_mode));
		if (!_start_is_set_mode) {
			scr_button_force_single_runtime_settings_sync();
			var _start_effective = scr_button_resolve_effective_settings(true);
			scr_button_bpm_debug_log("[START-PLAY-EFFECTIVE] bpm=" + string(scr_button_struct_get(_start_effective, "bpm", global.current_bpm))
				+ " swing=" + string(scr_button_struct_get(_start_effective, "swing_mult", global.swing_mult))
				+ " grace_ms=" + string(scr_button_struct_get(_start_effective, "gracenote_override_ms", global.gracenote_override_ms)));
			if (!scr_button_prepare_single_tune_playback_events()) {
				show_debug_message("ERROR: Single-tune playback preparation failed; start aborted.");
				return;
			}
		}
		var tune_data = scr_button_tune_data_get(tune);
		var tune_events = scr_button_struct_get(tune_data, "events", array_create(0));

		if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
			var selected_part = variable_global_exists("selected_player_tune_channel")
				? floor(real(global.selected_player_tune_channel))
				: floor(real(global.timeline_cfg.tune_channel ?? 2));

			var available_parts = [2];
			var detected_parts = scr_tune_picker_collect_player_part_channels(tune_data);
			if (is_array(detected_parts) && array_length(detected_parts) > 0) {
				available_parts = detected_parts;
			}

			var has_selected_part = false;
			var n_parts = array_length(available_parts);
			for (var part_i = 0; part_i < n_parts; part_i++) {
				if (floor(real(available_parts[part_i])) == selected_part) {
					has_selected_part = true;
					break;
				}
			}
			if (!has_selected_part && n_parts > 0) {
				selected_part = floor(real(available_parts[0]));
			}

			if (selected_part < 2 || selected_part > 5) selected_part = 2;
			global.selected_player_tune_channel = selected_part;
			global.timeline_cfg.tune_channel = selected_part;

			if (!variable_struct_exists(global.timeline_cfg, "player_channels")
				|| !is_array(global.timeline_cfg.player_channels)
				|| array_length(global.timeline_cfg.player_channels) <= 0) {
				global.timeline_cfg.player_channels = [0];
			}

		}
		
		
		if (scr_set_is_active() || (instance_exists(tune) && scr_button_tune_is_loaded(tune))) {
		// Events are already preprocessed and stored in global.playback_events
			if (variable_global_exists("playback_events") && array_length(global.playback_events) > 0) {
				global.loop_runtime_active = false;
				global.loop_runtime_current_iteration = 0;
				var start_events = global.playback_events;
				if (!scr_set_is_active() && variable_global_exists("loop_mode_enabled") && global.loop_mode_enabled) {
					start_events = scr_button_loop_build_playback_events(global.playback_events);
				}
				global.playback_events_active = start_events;

				if (variable_global_exists("LOOP_COMPARE_DUMP_ENABLED") && bool(global.LOOP_COMPARE_DUMP_ENABLED)) {
					var _cmp_run = string(current_time);
					scr_button_export_planned_events_snapshot(global.playback_events, "base", _cmp_run);
					var _cmp_label = (!scr_set_is_active() && variable_global_exists("loop_mode_enabled") && global.loop_mode_enabled)
						? "active_loop"
						: "active_no_loop";
					scr_button_export_planned_events_snapshot(start_events, _cmp_label, _cmp_run);
				}

				var _started = tune_start(start_events);
		        // If tune_start returns undefined on success, this still passes
				if (_started != false) {
					if (is_undefined(gv_bind_timeline_on_tune_start) == false
						&& is_undefined(gv_resolve_loaded_tune_timing) == false) {
						var _timing_bpm = 120;
						var _timing_meter = "4/4";
						// Read from playback_context (covers both tune and set modes)
						var _ctx_seg = scr_playback_context_get_active_segment();
						if (!is_undefined(_ctx_seg)) {
							_timing_bpm   = real(_ctx_seg[$ "bpm"]   ?? 120);
							_timing_meter = string(_ctx_seg[$ "meter"] ?? "4/4");
						} else if (!scr_set_is_active()) {
							var _timing = gv_resolve_loaded_tune_timing();
							_timing_bpm   = real(scr_button_struct_get(_timing, "bpm", 120));
							_timing_meter = string(scr_button_struct_get(_timing, "meter", "4/4"));
						}
						// In single-tune mode, playback_context.segments[0].bpm holds tempo_default from
						// the JSON (set at room entry, never updated). Override with global.current_bpm
						// so the notebeam scroll speed matches the events already preprocessed at that BPM.
						if (!_start_is_set_mode && variable_global_exists("current_bpm")) {
							var _timing_bpm_old = _timing_bpm;
							_timing_bpm = real(global.current_bpm);
							scr_button_bpm_debug_log("[START-PLAY-BPM] overriding stale context bpm: " + string(_timing_bpm_old) + " -> " + string(_timing_bpm));
						}
						gv_bind_timeline_on_tune_start(start_events, _timing_bpm, _timing_meter);
						// Segment-level nav rebuild is set-only; in single-tune mode (especially loop runtime)
						// keep the bind-time nav map derived from active playback events.
						var _pc_is_set = variable_global_exists("playback_context")
							&& is_struct(global.playback_context)
							&& string(global.playback_context[$ "mode"] ?? "") == "set";
						if (_pc_is_set) {
							gv_apply_cached_segment_runtime(
								floor(real(global.playback_context[$ "active_segment"] ?? 0))
							);
						}
					} else {
						gv_bind_from_loaded_tune();
					}
				} else {
					show_debug_message("ERROR: tune_start failed.");
				}
				} else {
					show_debug_message("ERROR: No playback events prepared. Did you go through main menu?");
				}
				} else {
				show_debug_message("ERROR: No tune loaded. Please select and confirm a tune first.");
				if (!instance_exists(tune)) show_debug_message("  - obj_tune instance does not exist");
				else if (!scr_button_tune_is_loaded(tune)) show_debug_message("  - tune.is_loaded = false");
		}
	}

	//CASE 12
	//Regenerate Tune Library (manual trigger)
	/// @function scr_regenerate_tune_library()
	/// @description Rescan tunes folder, rebuild tune_library.json, reload into global, and refresh picker.
	/// @writes global.tune_library
	/// @objects obj_tune_picker (refreshes visible rows)
	/// @callers scr_handle_button_click (button 12)
	function scr_regenerate_tune_library(){
		var _tune_root = script_exists(asset_get_index("scr_tune_library_get_runtime_root"))
			? scr_tune_library_get_runtime_root()
			: (script_exists(asset_get_index("scr_data_paths_get_category_root"))
				? scr_data_paths_get_category_root("tunes")
				: "datafiles/tunes/");
		scr_build_tune_library(_tune_root);
		var library = scr_load_tune_library();
		global.tune_library = library;
		var picker = instance_find(obj_tune_picker, 0);
		if (picker != noone) {
			scr_tune_picker_set_instance_var(picker, "library", library);
			scr_tune_picker_refresh_visible_rows();
		}
		var tune_count = 0;
		var library_tunes = scr_button_struct_get(library, "tunes", array_create(0));
		if (is_array(library_tunes)) {
			tune_count = array_length(library_tunes);
		}
		show_debug_message("Tune library now contains " + string(tune_count) + " tunes");
	}

	//CASE 13
	/// @function export_event_history()
	/// @description Export the current event history to CSV
	/// @reads global.EVENT_HISTORY_LIBRARY_UPDATED
	/// @writes global.EVENT_HISTORY_LIBRARY_UPDATED
	/// @callers scr_handle_button_click (button 13)
	function export_event_history() {
		var export_info = event_history_get_export_info();
		var export_folder = string(scr_button_struct_get(export_info, "folder", ""));
		var export_csv_path = string(scr_button_struct_get(export_info, "csv_path", ""));
		var export_summary_path = string(scr_button_struct_get(export_info, "summary_path", ""));
		if (export_folder != "" && !directory_exists(export_folder)) {
			directory_create(export_folder);
		}
	    event_history_export_csv(export_csv_path);
		event_history_export_summary_json(export_summary_path, export_info);
		if (is_undefined(event_history_export_loop_session_json) == false) {
			event_history_export_loop_session_json(export_info);
		}
		if (!global.EVENT_HISTORY_LIBRARY_UPDATED) {
			event_history_update_tune_history_index(export_info);
			global.EVENT_HISTORY_LIBRARY_UPDATED = true;
		}
	}

	// CASE 24 - Loop mode toggle button in gameplay info window.
	/// @function scr_loop_mode_toggle(_ctx)
	/// @description Toggle loop mode on/off; when turning off, clears selected measures and blank-measure state.
	/// @reads global.loop_mode_enabled, global.timeline_state
	/// @writes global.loop_mode_enabled
	/// @callers scr_handle_button_click (button 24)
	function scr_loop_mode_toggle(_ctx = noone) {
		if (!variable_global_exists("loop_mode_enabled")) {
			global.loop_mode_enabled = false;
		}
		global.loop_mode_enabled = !global.loop_mode_enabled;

		if (global.loop_mode_enabled) {
			show_debug_message("Loop mode: ON");
			scr_button_inst_set(_ctx, "button_active_frame", 3);
			scr_button_inst_set(_ctx, "image_index", 3);
			scr_button_inst_set(_ctx, "image_blend", c_white);
		} else {
			show_debug_message("Loop mode: OFF");
			scr_button_inst_set(_ctx, "button_active_frame", -1);
			scr_button_inst_set(_ctx, "image_index", 0);
			scr_button_inst_set(_ctx, "image_blend", c_white);
			if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
				if (is_undefined(gv_loop_clear_selected_measures) == false) {
					gv_loop_clear_selected_measures();
				}
				if (is_undefined(gv_loop_set_blank_measure_enabled) == false) {
					gv_loop_set_blank_measure_enabled(false);
				}
			}
		}

		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			global.timeline_state.score_render_plan_needs_rebuild = true;
			global.timeline_state.score_render_plan_pending_reason = global.loop_mode_enabled ? "loop_mode_on" : "loop_mode_off";
			if (variable_struct_exists(global.timeline_state, "score_render_plan")
				&& is_struct(global.timeline_state.score_render_plan)) {
				global.timeline_state.score_render_plan.valid = false;
				global.timeline_state.score_render_plan.status = "pending";
				global.timeline_state.score_render_plan.reason = global.timeline_state.score_render_plan_pending_reason;
			}
			if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
				&& is_struct(global.timeline_state.score_render_plan_stats)) {
				global.timeline_state.score_render_plan_stats.invalidations += 1;
				global.timeline_state.score_render_plan_stats.last_reason = global.timeline_state.score_render_plan_pending_reason;
			}
			global.timeline_state.score_lane_layout_cache_single = {};

			if (script_exists(asset_get_index("gv_build_loop_runtime_cache"))
				&& variable_global_exists("playback_events_active")
				&& is_array(global.playback_events_active)) {
				if (global.loop_mode_enabled) {
					global.timeline_state.loop_runtime_cache = gv_build_loop_runtime_cache(global.playback_events_active);
				} else {
					global.timeline_state.loop_runtime_cache = { valid: false, measure_starts: [] };
				}
			}
		}
	}
	/// @function scr_toggle_loop_score_overview(_ctx)
	/// @description Toggle the visibility of the loop score overview panel (loop_score_overview_layer).
	/// @param {Id.Instance} _ctx  Button context (unused)
	/// @reads   none
	/// @writes  none (controls layer visibility via layer_set_visible / instance_activate_layer)
	/// @callers scr_handle_button_click (case 29)
	function scr_toggle_loop_score_overview(_ctx = noone) {
		var _layer_id = layer_get_id("loop_score_overview_layer");
		if (_layer_id == -1) {
			show_debug_message("[loop_score_overview] Layer not found: loop_score_overview_layer");
			return;
		}
		var _cur_vis = layer_get_visible(_layer_id);
		var _new_vis = !_cur_vis;
		layer_set_visible(_layer_id, _new_vis);
		if (_new_vis) {
			instance_activate_layer(_layer_id);
		} else {
			instance_deactivate_layer(_layer_id);
		}
	}