

// scr_button_scripts — UI button dispatcher
// Purpose: Routes button presses to actions (open windows, change settings, start play, confirm tune) and coordinates UI → logic flows.
// Key functions: scr_handle_button_click, scr_open_window, scr_settings_OK, scr_tune_OK, start_play
// Related objects: obj_tune_picker, obj_ui_controller, obj_game_controller

//Main menu buttons
	//Button handler
	function scr_handle_button_click(button_ID, _ctx = noone){
		if (is_real(button_ID) && button_ID < 0) return;

		var ctx = scr_button_get_ctx(_ctx);

		switch (button_ID) {
			case 0: show_debug_message("switch 0"); scr_script_not_set(ctx); break;						//"button"
			case 1: show_debug_message("main clicked play"); scr_goto_playroom(); break;		//"play"
			case 2: show_debug_message("clicked tune checkbox"); scr_checkbox_click(ctx); break;											//"settings"
			case 3: show_debug_message("toggle target UI layer"); scr_open_window(scr_button_inst_get(ctx, "button_click_value", 0)); break;	//"tune"
			case 4: show_debug_message("clicked exit"); scr_exit_game(); break;		//exit"
			case 5: show_debug_message("Go to main menu");  scr_goto_mainmenu(); break;		//exit"
			case 6: show_debug_message("settings change");  scr_settings_change(ctx); break;	//exit
			case 7: show_debug_message("settings MIDI IN change");  scr_settings_MIDI_In_change(ctx); break;	//exit
			case 8: show_debug_message("settings MIDI OUT change");  scr_settings_MIDI_Out_change(ctx); break;	//exit
			case 9: show_debug_message("settings OK"); scr_settings_OK(ctx); break;		//exit
			case 10: show_debug_message("tune OK"); scr_tune_OK(ctx); break;				//exit
			case 11: show_debug_message("Play room play"); start_play(); break;		//exit
			case 12: show_debug_message("Regenerating tune library"); scr_regenerate_tune_library(); break;		//regenerate
			case 13: show_debug_message("Exporting event history"); export_event_history(); break;
			case 14: show_debug_message("Metronome Mode change"); scr_metronome_mode_change(ctx); break;
			case 15: show_debug_message("Metronome Pattern change"); scr_metronome_pattern_change(ctx); break;
			case 16: show_debug_message("Metronome Volume change"); scr_metronome_volume_change(ctx); break;
			case 17: show_debug_message("Tune BPM change"); scr_tune_bpm_change(ctx); break;
			case 18: show_debug_message("Tune Count-In change"); scr_tune_countin_change(ctx); break;
			case 19: show_debug_message("Gracenote Override change"); scr_gracenote_override_change(ctx); break;
			case 20: show_debug_message("Swing Multiplier change"); scr_swing_mult_change(ctx); break;
			case 21: show_debug_message("Current-note measure scroll"); scr_current_note_measure_scroll(ctx); break;
			default: show_debug_message("switch default"); scr_script_not_set(ctx); break;
		}
	}

	function scr_button_get_ctx(_ctx = noone) {
		if (_ctx != noone && instance_exists(_ctx)) return _ctx;
		return noone;
	}

	function scr_button_inst_get(_ctx, _name, _default = undefined) {
		if (_ctx == noone || !instance_exists(_ctx)) return _default;
		if (!variable_instance_exists(_ctx, _name)) return _default;
		return variable_instance_get(_ctx, _name);
	}

	function scr_button_inst_set(_ctx, _name, _value) {
		if (_ctx == noone || !instance_exists(_ctx)) return;
		variable_instance_set(_ctx, _name, _value);
	}

	function scr_button_field_get(_field, _name, _default = undefined) {
		if (_field == noone || !instance_exists(_field)) return _default;
		if (!variable_instance_exists(_field, _name)) return _default;
		return variable_instance_get(_field, _name);
	}

	function scr_button_field_set(_field, _name, _value) {
		if (_field == noone || !instance_exists(_field)) return;
		variable_instance_set(_field, _name, _value);
	}

	function scr_button_struct_get(_value, _name, _default = undefined) {
		if (!is_struct(_value) || !variable_struct_exists(_value, _name)) return _default;
		return variable_struct_get(_value, _name);
	}

	function scr_button_struct_set(_value, _name, _new_value) {
		if (!is_struct(_value)) return;
		variable_struct_set(_value, _name, _new_value);
	}

	function scr_button_tune_data_get(_tune) {
		return scr_button_inst_get(_tune, "tune_data", undefined);
	}

	function scr_button_tune_is_loaded(_tune) {
		var tune_data = scr_button_tune_data_get(_tune);
		return scr_button_struct_get(tune_data, "is_loaded", false);
	}

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
	
	//CASE 0 
	//No button action
	function scr_script_not_set(_ctx = noone){
		var ctx = scr_button_get_ctx(_ctx);
		var ui_name = string(scr_button_inst_get(ctx, "ui_name", "button"));
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
	function scr_goto_playroom(){
		// Preprocess tune and merge with metronome BEFORE switching rooms
		var tune = global.tune;
		var tune_data = scr_button_tune_data_get(tune);
		if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
			show_debug_message("Preprocessing tune for playback...");
			
			// Step 1: Preprocess tune JSON into playable MIDI events
			var set_item = undefined;
			if (array_length(global.current_set) > 0 && global.current_set_item_index >= 0) {
				set_item = global.current_set[global.current_set_item_index];
			}
			var bpm_override = is_struct(set_item) ? scr_button_struct_get(set_item, "bpm", undefined) : undefined;
			var overrides = undefined;
			if (is_struct(set_item)) {
				var swing_override = scr_button_struct_get(set_item, "swing_mult", undefined);
				if (is_undefined(swing_override)) swing_override = scr_button_struct_get(set_item, "swing", undefined);
				var grace_override = scr_button_struct_get(set_item, "gracenote_override_ms", undefined);
				if (is_undefined(grace_override)) grace_override = scr_button_struct_get(set_item, "gracenote_ms", undefined);
				overrides = {
					bpm: bpm_override,
					swing_mult: swing_override,
					gracenote_override_ms: grace_override
				};
			}
			var tune_events = scr_preprocess_tune(tune, is_struct(overrides) ? overrides : bpm_override);
		
			// Step 2: Metronome settings (from set item if available)
			var metronome_settings = undefined;
			if (is_struct(set_item)) {
				metronome_settings = {
					bpm: scr_button_struct_get(set_item, "bpm", undefined),
					metronome_mode: scr_button_struct_get(set_item, "metronome_mode", 0),
					metronome_pattern: scr_button_struct_get(set_item, "metronome_pattern", 0),
					metronome_volume: scr_button_struct_get(set_item, "metronome_volume", 100)
				};
			}
		
			// Step 3: Generate metronome events for the tune
			var metronome_events = metronome_generate_events({
				events: tune_events,
				tune_data: tune_data
			}, metronome_settings);
		
			// Step 4: Optional count-in (prepend metronome measures)
			var countin_events = array_create(0);
			var count_in_measures = is_struct(set_item) ? real(scr_button_struct_get(set_item, "count_in_measures", 0)) : 0;
			var count_in_ms = 0;
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
				count_in_ms = count_in_measures * beats_per_measure * beat_unit_ms;
			
				countin_events = metronome_generate_countin_events({
					events: tune_events,
					tune_data: tune_data
				}, metronome_settings, count_in_measures);
			
				// Find pickup duration (time before measure 1)
				// Prefer explicit measure-1 bar marker to avoid false offsets.
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
				// Fallback if markers are unavailable.
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
			
				// Shift tune + metronome events so measure 1 starts after count-in,
				// keeping pickup notes aligned within the count-in window.
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
		
			// Merge arrays manually
			var total = array_length(tune_events) + array_length(metronome_events) + array_length(countin_events);
			var merged = array_create(total);
			var idx = 0;
			for (var i = 0; i < array_length(countin_events); i++) {
				merged[idx++] = countin_events[i];
			}
			for (var i = 0; i < array_length(tune_events); i++) {
				merged[idx++] = tune_events[i];
			}
			for (var i = 0; i < array_length(metronome_events); i++) {
				merged[idx++] = metronome_events[i];
			}
			// Sort by time
			array_sort(merged, function(a, b) {
				return real(scr_button_struct_get(a, "time", 0)) - real(scr_button_struct_get(b, "time", 0));
			});
			
			global.playback_events = merged;
			show_debug_message("Merged " + string(array_length(tune_events)) + " tune + " + string(array_length(metronome_events)) + " metronome = " + string(array_length(merged)) + " total");
			
			// Merged events ready for playback
			
			show_debug_message("Ready for playback with " + string(array_length(global.playback_events)) + " total events");
		} else {
			show_debug_message("WARNING: No tune loaded, proceeding without events");
			global.playback_events = [];
		}
		
		global.enable_current_note_layer = false;
		room_goto(Room_play);

		// Explicit layer visibility for play room (no toggle behavior)
		var _main_layer_id = layer_get_id("main_menu_layer");
		if (_main_layer_id != -1) layer_set_visible(_main_layer_id, false);

		var _settings_layer_id = layer_get_id("settings_window_layer");
		if (_settings_layer_id != -1) layer_set_visible(_settings_layer_id, false);

		var _tune_layer_id = layer_get_id("tune_window_layer");
		if (_tune_layer_id != -1) layer_set_visible(_tune_layer_id, false);

		var _gameplay_layer_id = layer_get_id("gameplay_layer");
		if (_gameplay_layer_id != -1) layer_set_visible(_gameplay_layer_id, true);

		var _current_note_layer_id = layer_get_id("current_note_layer");
		if (_current_note_layer_id != -1) layer_set_visible(_current_note_layer_id, false);
	}

	//CASE 2 Clicked Checkbox
	//Used in tune window but could be made generic
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

		if (button_checked == 0) {
			scr_uncheck_all(global.ui_assets, ui_layer_num, ui_group, ui_num);
			scr_button_inst_set(ctx, "button_checked", 1);
			scr_button_inst_set(ctx, "image_index", 3);
			show_debug_message("input: " + string(target_name));
			variable_global_set(target_name, button_click_value);
			var picker = instance_find(obj_tune_picker, 0);
			if (picker != noone) {
				if (is_undefined(scr_tune_picker_select_index) == false) {
					scr_tune_picker_select_index(button_click_value);
				} else if (is_undefined(scr_tune_picker_set_selected_by_index) == false) {
					scr_tune_picker_set_selected_by_index(button_click_value);
				} else if (is_undefined(scr_tune_picker_set_instance_var) == false) {
					scr_tune_picker_set_instance_var(picker, "selected_index", button_click_value);
				} else {
					variable_instance_set(picker, "selected_index", button_click_value);
				}
			}
			if (picker != noone && is_undefined(scr_tune_picker_sync_selected_entry_ui) == false) {
				scr_tune_picker_sync_selected_entry_ui();
			}
			show_debug_message("tune selection: " + string(global.tune_selection));
		}
		else if (button_checked == 1) {
			scr_uncheck_all(global.ui_assets, ui_layer_num, ui_group, ui_num);
			scr_button_inst_set(ctx, "button_checked", 0);
			variable_global_set(target_name, -1);
			var picker2 = instance_find(obj_tune_picker, 0);
			if (picker2 != noone) {
				if (is_undefined(scr_tune_picker_clear_selection) == false) {
					scr_tune_picker_clear_selection();
				} else if (is_undefined(scr_tune_picker_set_instance_var) == false) {
					scr_tune_picker_set_instance_var(picker2, "selected_index", -1);
				} else {
					variable_instance_set(picker2, "selected_index", -1);
				}
				if (is_undefined(scr_tune_picker_refresh_visible_rows) == false) {
					scr_tune_picker_refresh_visible_rows();
				}
			}
		}
	}	

	//Script to uncheck checkboxes for use when checking a new checkbox
	function scr_uncheck_all(array_of_checkboxes,ui_layer, ui_group, this_num) {
		show_debug_message("Uncheck in layer " + string(ui_layer) +
                       " group " + string(ui_group) +
                       " except ui_num " + string(this_num));
			var target_group = ui_group;

		var layer_entries = array_of_checkboxes[ui_layer];

		//doublecheck contents
		//show_debug_message("Checkbox array length: " + string(array_length(array_of_checkboxes[ui_layer])));
		for (var k = 0; k < array_length(array_of_checkboxes[ui_layer]); k++) {
		    var entry = array_of_checkboxes[ui_layer][k];
		//    show_debug_message("Entry " + string(k) + ": num=" + string(entry[0]) + " id=" + string(entry[1]));
		}

		for (var i = 0; i < array_length(layer_entries); i++) {
			var entry = layer_entries[i];
			var num   = entry[0];
			var cb    = entry[1];

			//doublecheck cb
			if (instance_exists(cb)) {
			//    show_debug_message("Checkbox " + string(num) + " exists: " + string(cb));
			} else {
			//    show_debug_message("Checkbox " + string(num) + " is missing");
			}

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
	function scr_open_window(layer_num, vis = undefined) {
		var layer_name = GetLayerNameFromIndex(layer_num);
		var layer_id = layer_get_id(layer_name);
		var current_visibility = layer_get_visible(layer_id); // Get the current visibility
		if (is_undefined(vis)) vis = false;		
		
		if (vis == false) {
			for (var i = 1; i < array_length(global.ui_assets); i++) {
					var cur_layer_name = GetLayerNameFromIndex(i);
					var cur_layer_id = layer_get_id(cur_layer_name);
					layer_set_visible(cur_layer_id, false);
			}
		}
		layer_set_visible(layer_id, !current_visibility); // Toggle visibility

		var new_visibility = layer_get_visible(layer_id);
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
		}

    // Refresh and update fields for the target window
		scr_ui_refresh(layer_num);
		scr_update_fields(layer_num);
	}
	
	//CASE 4 
	//Main Menu - End Button
	function scr_exit_game(){
		game_end();
	}

	//CASE 5 	
	//Go to Main Menu button
	function scr_goto_mainmenu(){
		MIDI_send_off();
		MIDI_stop_checking_messages_and_errors();
		if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
			global.timeline_state.active = false;
		}
		room_goto(Room_main_menu);

		var _main_layer_id = layer_get_id("main_menu_layer");
		if (_main_layer_id != -1) layer_set_visible(_main_layer_id, true);

		var _gameplay_layer_id = layer_get_id("gameplay_layer");
		if (_gameplay_layer_id != -1) layer_set_visible(_gameplay_layer_id, false);

		var _current_note_layer_id = layer_get_id("current_note_layer");
		if (_current_note_layer_id != -1) layer_set_visible(_current_note_layer_id, false);
	}
	
	//CASE 6
	//change settings field by button value ... for +/- buttons (generic array cycling)
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
	
	//CASE 14 - Metronome Mode (None/Click/Drums)
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

		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "metronome_mode", global.metronome_mode);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Metronome mode: " + string(field_contents));
	}
	
	//CASE 15 - Metronome Pattern
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
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "metronome_pattern", global.metronome_pattern_selection);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Metronome pattern: " + string(field_contents));
	}
	
	//CASE 16 - Metronome Volume
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

		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "metronome_volume", global.metronome_volume);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Metronome volume: " + string(new_volume));
	}

	//CASE 17 - Tune BPM
	function scr_tune_bpm_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

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

		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "bpm", global.current_bpm);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("BPM: " + string(new_val));
	}

	//CASE 18 - Tune Count-In
	function scr_tune_countin_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		var field = scr_button_inst_get(ctx, "field_ref", noone);
		if (!instance_exists(field)) return;

		var button_click_value = real(scr_button_inst_get(ctx, "button_click_value", 0));
		var field_value = real(scr_button_field_get(field, "field_value", 0));
		var new_val = clamp(field_value + button_click_value, 0, 2);
		scr_button_field_set(field, "field_value", new_val);
		scr_button_field_set(field, "field_contents", string(new_val));

		global.count_in_measures = new_val;
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "count_in_measures", global.count_in_measures);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Count-in measures: " + string(new_val));
	}

	//CASE 19 - Gracenote Override (ms)
	function scr_gracenote_override_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

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

		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "gracenote_override_ms", global.gracenote_override_ms);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Gracenote override (ms): " + string(new_val));
	}

	//CASE 20 - Swing Multiplier
	function scr_swing_mult_change(_ctx = noone) {
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

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

		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					scr_button_struct_set(item, "swing_mult", global.swing_mult);
					global.current_set[idx] = item;
				}
			}
		}

		show_debug_message("Swing multiplier: " + string(new_val));
	}

	//CASE 21 - Current-note measure scroll
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

	//CASE 9
	function scr_settings_OK(_ctx = noone)	{
	//Set the choices that were made in the settings window.
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		midi_input_device_open(global.midi_input_device);
		midi_output_device_open(global.midi_output_device);

		var button_label = string(scr_button_inst_get(ctx, "button_label", ""));
		if (!scr_hide_window(button_label, ctx)) {
			show_debug_message("Warning! - scr_settings_OK: could not find layer to hide for target: " + button_label);
		}
	}	
	
	//CASE 10  THis OK button in the tune window locks in the selected 
	function scr_tune_OK(_ctx = noone)	{
	//Set the choices that were made in the settings window.
		var ctx = scr_button_get_ctx(_ctx);
		if (ctx == noone) return;

		show_debug_message("Tune selected: " + string(global.tune_selection));

		var saved_button_label = string(scr_button_inst_get(ctx, "button_label", ""));
		var button_label = saved_button_label;
		if (!is_string(button_label) || layer_get_id(button_label) == -1) {
			var ui_layer_num = real(scr_button_inst_get(ctx, "ui_layer_num", -1));
			if (ui_layer_num >= 0) {
				button_label = GetLayerNameFromIndex(ui_layer_num);
				scr_button_inst_set(ctx, "button_label", button_label);
			}
		}

		var picker = instance_find(obj_tune_picker, 0);
		var library = undefined;
		var selected_index = -1;
		var entry = undefined;
		if (picker != noone) {
			if (is_undefined(scr_tune_picker_get_selected_entry) == false) {
				entry = scr_tune_picker_get_selected_entry();
			}

			if (is_undefined(scr_tune_picker_get_library) == false) {
				library = scr_tune_picker_get_library(picker);
			} else if (variable_instance_exists(picker, "library")) {
				library = variable_instance_get(picker, "library");
			}

			if (is_undefined(scr_tune_picker_get_instance_var) == false) {
				selected_index = real(scr_tune_picker_get_instance_var(picker, "selected_index", -1));
			} else if (variable_instance_exists(picker, "selected_index")) {
				selected_index = real(variable_instance_get(picker, "selected_index"));
			}

			var library_tunes = scr_button_struct_get(library, "tunes", array_create(0));
			if (!is_struct(entry)
				&& is_array(library_tunes)
				&& selected_index >= 0
				&& selected_index < array_length(library_tunes)) {
				entry = library_tunes[selected_index];
			}
		}

		if (is_struct(entry)) {
			var filename = string(scr_button_struct_get(entry, "filename", ""));
			if (filename == "") {
				show_debug_message("No tune filename selected in picker entry.");
				scr_button_inst_set(ctx, "button_label", saved_button_label);
				return;
			}

		    var candidates = array_create(0);
			var library_root = string(scr_button_struct_get(library, "root", ""));
		    if (library_root != "") {
		        array_push(candidates, library_root + filename);
		    }
		    array_push(candidates, "tunes/" + filename);
		    array_push(candidates, "datafiles/tunes/" + filename);

		    var loaded = false;
		    for (var i = 0; i < array_length(candidates) && !loaded; i++) {
		        var tryfile = candidates[i];
		        show_debug_message("Attempting to load tune: " + string(tryfile));
		        if (scr_tune_load_json(tryfile)) {
		            show_debug_message("Loaded tune: " + string(tryfile));

		            var item = create_set_item(tryfile);
				var loaded_tune_data = scr_button_tune_data_get(global.tune);
		            var perf = scr_button_struct_get(loaded_tune_data, "performance", undefined);
		            var meta = scr_button_struct_get(loaded_tune_data, "tune_metadata", undefined);
		            var default_swing = scr_button_struct_get(perf, "swing", scr_button_struct_get(meta, "swing", ""));
		            if (!is_undefined(default_swing) && string(default_swing) != "") {
		                scr_button_struct_set(item, "swing_mult", default_swing);
		            }

				var field_count = instance_number(obj_field_base);
				for (var fi = 0; fi < field_count; fi++) {
					var field_inst = instance_find(obj_field_base, fi);
					if (field_inst == noone) continue;
					var field_ui_name = string(scr_button_inst_get(field_inst, "ui_name", ""));
					var field_val = scr_button_field_get(field_inst, "field_value", 0);

					if (field_ui_name == "tune_BPM_field" || field_ui_name == "metro_field_3") {
						scr_button_struct_set(item, "bpm", field_val);
					}
					if (field_ui_name == "tune_countin_field" || field_ui_name == "metro_field_4") {
						scr_button_struct_set(item, "count_in_measures", field_val);
					}
					if (field_ui_name == "metro_field_1") scr_button_struct_set(item, "metronome_mode", field_val);
					if (field_ui_name == "metro_field_2") scr_button_struct_set(item, "metronome_pattern", field_val);
					if (field_ui_name == "metro_field_5") scr_button_struct_set(item, "metronome_volume", field_val);
					if (field_ui_name == "metro_field_6") scr_button_struct_set(item, "swing_mult", field_val);
					if (field_ui_name == "metro_field_7") scr_button_struct_set(item, "gracenote_override_ms", field_val);
				}

				global.current_set = [item];
				global.current_set_item_index = 0;

				global.current_bpm = scr_button_struct_get(item, "bpm", 120);
				global.metronome_mode = scr_button_struct_get(item, "metronome_mode", 0);
				global.metronome_pattern_selection = scr_button_struct_get(item, "metronome_pattern", 0);
				global.metronome_volume = scr_button_struct_get(item, "metronome_volume", 100);
				global.count_in_measures = scr_button_struct_get(item, "count_in_measures", 0);
				global.swing_mult = scr_button_struct_get(item, "swing_mult", 1);
				global.gracenote_override_ms = scr_button_struct_get(item, "gracenote_override_ms", 0);

				var item_bpm = scr_button_struct_get(item, "bpm", 120);
				var item_count_in = scr_button_struct_get(item, "count_in_measures", 0);
				var item_metronome_mode = scr_button_struct_get(item, "metronome_mode", 0);

				show_debug_message("Created set item: " + tryfile
					+ " | BPM=" + string(item_bpm)
					+ " | Count-in=" + string(item_count_in)
					+ " | Metronome=" + global.metronome_mode_options[item_metronome_mode]);

				if (is_string(button_label) && layer_get_id(button_label) != -1) {
					layer_set_visible(button_label, 0);
				}
				var entry_title = scr_button_struct_get(entry, "title", undefined);
				if (!is_undefined(entry_title)
					&& variable_global_exists("obj_gameinfo_win_title")
					&& instance_exists(global.obj_gameinfo_win_title)) {
					variable_instance_set(global.obj_gameinfo_win_title, "field_contents", entry_title);
				}
				loaded = true;
		        }
		    }

			if (!loaded) {
				show_debug_message("Failed to load tune from candidates.");
			} else if (!scr_hide_window(button_label, ctx)) {
				show_debug_message("Warning! - scr_tune_OK: could not find layer to hide for target: " + string(button_label));
			}

			scr_button_inst_set(ctx, "button_label", saved_button_label);
		} else {
			show_debug_message("No tune selected in picker.");
			scr_button_inst_set(ctx, "button_label", saved_button_label);
		}
				
		// tune_selection_ok_button pressed
		//var tune_file = "ScotlandTheBrave.json"; // temporary hard-coded path
		//
		//if (scr_tune_load_json(tune_file))	{
		//	show_debug_message("Tune Loaded !!!");
		//	layer_set_visible(self.button_label, 0); // Toggle window visibility
		//}	else	{
		//    show_debug_message("Failed to load tune.");
		//}
		
	}	
	
	//CASE 11
	function start_play() {
		midi_output_device_open(global.midi_output_device);
		midi_input_device_open(global.midi_input_device);
		MIDI_start_manual_check_messages();
		show_debug_message("manual MIDI started");
		show_debug_message("input = " + string(global.midi_input_device));
		show_debug_message("tune start " + string(global.tune_selection));
		
		// global.tune is the obj_tune instance (not an array)
		var tune = global.tune;
		var tune_data = scr_button_tune_data_get(tune);
		var tune_events = scr_button_struct_get(tune_data, "events", array_create(0));

		if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
			var selected_part = variable_global_exists("selected_player_tune_channel")
				? floor(real(global.selected_player_tune_channel))
				: floor(real(global.timeline_cfg.tune_channel ?? 2));

			var available_parts = [2];
			if (is_undefined(scr_tune_picker_collect_player_part_channels) == false) {
				var detected_parts = scr_tune_picker_collect_player_part_channels(tune_data);
				if (is_array(detected_parts) && array_length(detected_parts) > 0) {
					available_parts = detected_parts;
				}
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

			show_debug_message("[TIMELINE] target tune channel=" + string(selected_part)
				+ " parts=" + string(array_length(available_parts)));
		}

		show_debug_message("Tune instance: " + string(tune) + " exists: " + string(instance_exists(tune)));
		show_debug_message("  DEBUG: Before preprocessing - tune.events length = " + string(array_length(tune_events)));
		
		
		if (instance_exists(tune) && scr_button_tune_is_loaded(tune)) {
		// Events are already preprocessed and stored in global.playback_events
			if (variable_global_exists("playback_events") && array_length(global.playback_events) > 0) {
				var _started = tune_start(global.playback_events);
		        // If tune_start returns undefined on success, this still passes
				if (_started != false) {
					gv_bind_from_loaded_tune();
					
					//Temp debug code
					var _len = -1;
					if (variable_global_exists("timeline_state")
					    && is_struct(global.timeline_state)
					    && variable_struct_exists(global.timeline_state, "planned_spans")
					    && is_array(global.timeline_state.planned_spans)) {
					    _len = array_length(global.timeline_state.planned_spans);
					}
					show_debug_message("[TIMELINE] planned_spans len=" + string(_len));
					//end of temp debug code
					
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
		
		//if (instance_exists(tune) && tune.tune_data.is_loaded) {
		//	// Events are already preprocessed and stored in global.playback_events
		//	if (variable_global_exists("playback_events") && array_length(global.playback_events) > 0) {
		//		tune_start(global.playback_events);
		//	} else {
		//		show_debug_message("ERROR: No playback events prepared. Did you go through main menu?");
		//	}
		//} else {
		//	show_debug_message("ERROR: No tune loaded. Please select and confirm a tune first.");
		//	if (!instance_exists(tune)) show_debug_message("  - obj_tune instance does not exist");
		//	else if (!tune.tune_data.is_loaded) show_debug_message("  - tune.is_loaded = " + string(tune.tune_data.is_loaded));
		//}
	}

	//CASE 12
	//Regenerate Tune Library (manual trigger)
	function scr_regenerate_tune_library(){
		show_debug_message("===== REGENERATING TUNE LIBRARY =====");
		scr_build_tune_library("tunes/");
		var library = scr_load_tune_library();
		global.tune_library = library;
		var picker = instance_find(obj_tune_picker, 0);
		if (picker != noone) {
			if (is_undefined(scr_tune_picker_set_instance_var) == false) {
				scr_tune_picker_set_instance_var(picker, "library", library);
			} else {
				variable_instance_set(picker, "library", library);
			}
			scr_tune_picker_refresh_visible_rows();
		}
		show_debug_message("===== TUNE LIBRARY REGENERATION COMPLETE =====");
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
	function export_event_history() {
		var export_info = event_history_get_export_info();
		if (!directory_exists(export_info.folder)) {
			directory_create(export_info.folder);
		}
	    event_history_export_csv(export_info.csv_path);
		event_history_export_summary_json(export_info.summary_path, export_info);
		if (!global.EVENT_HISTORY_LIBRARY_UPDATED) {
			event_history_update_tune_history_index(export_info);
			global.EVENT_HISTORY_LIBRARY_UPDATED = true;
		}
	}
