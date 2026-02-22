

// scr_button_scripts — UI button dispatcher
// Purpose: Routes button presses to actions (open windows, change settings, start play, confirm tune) and coordinates UI → logic flows.
// Key functions: scr_handle_button_click, scr_open_window, scr_settings_OK, scr_tune_OK, start_play
// Related objects: obj_tune_picker, obj_ui_controller, obj_game_controller

//Main menu buttons
	//Button handler
	function scr_handle_button_click(button_ID){
		switch (button_ID) {
			case 0: show_debug_message("switch 0"); scr_script_not_set(); break;						//"button"
			case 1: show_debug_message("main clicked play"); scr_goto_playroom(); break;		//"play"
			case 2: show_debug_message("clicked tune checkbox"); scr_checkbox_click(); break;											//"settings"
			case 3: show_debug_message("toggle target UI layer"); scr_open_window(self.button_click_value); break;	//"tune"
			case 4: show_debug_message("clicked exit"); scr_exit_game(); break;		//exit"
			case 5: show_debug_message("Go to main menu");  scr_goto_mainmenu(); break;		//exit"
			case 6: show_debug_message("settings change");  scr_settings_change(); break;	//exit
			case 7: show_debug_message("settings MIDI IN change");  scr_settings_MIDI_In_change(); break;	//exit
			case 8: show_debug_message("settings MIDI OUT change");  scr_settings_MIDI_Out_change(); break;	//exit
			case 9: show_debug_message("settings OK"); scr_settings_OK(); break;		//exit
			case 10: show_debug_message("tune OK"); scr_tune_OK(); break;				//exit
			case 11: show_debug_message("Play room play"); start_play(); break;		//exit
			case 12: show_debug_message("Regenerating tune library"); scr_regenerate_tune_library(); break;		//regenerate
			case 13: show_debug_message("Exporting event history"); export_event_history(); break;
			case 14: show_debug_message("Metronome Mode change"); scr_metronome_mode_change(); break;
			case 15: show_debug_message("Metronome Pattern change"); scr_metronome_pattern_change(); break;
			case 16: show_debug_message("Metronome Volume change"); scr_metronome_volume_change(); break;
			case 17: show_debug_message("Tune BPM change"); scr_tune_bpm_change(); break;
			case 18: show_debug_message("Tune Count-In change"); scr_tune_countin_change(); break;
			case 19: show_debug_message("Gracenote Override change"); scr_gracenote_override_change(); break;
			case 20: show_debug_message("Swing Multiplier change"); scr_swing_mult_change(); break;
			default: show_debug_message("switch default"); scr_script_not_set(); break;
		}
	}
	
	//CASE 0 
	//No button action
	function scr_script_not_set(){
		show_debug_message(self.ui_name + ": No button action set");
		
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
		if (instance_exists(tune) && tune.tune_data.is_loaded) {
			show_debug_message("Preprocessing tune for playback...");
			
			// Step 1: Preprocess tune JSON into playable MIDI events
			var set_item = undefined;
			if (array_length(global.current_set) > 0 && global.current_set_item_index >= 0) {
				set_item = global.current_set[global.current_set_item_index];
			}
			var bpm_override = (is_struct(set_item) && !is_undefined(set_item.bpm)) ? set_item.bpm : undefined;
			var overrides = undefined;
			if (is_struct(set_item)) {
				var swing_override = set_item.swing_mult;
				if (is_undefined(swing_override)) swing_override = set_item.swing;
				var grace_override = set_item.gracenote_override_ms;
				if (is_undefined(grace_override)) grace_override = set_item.gracenote_ms;
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
					bpm: set_item.bpm,
					metronome_mode: set_item.metronome_mode,
					metronome_pattern: set_item.metronome_pattern,
					metronome_volume: set_item.metronome_volume
				};
			}
		
			// Step 3: Generate metronome events for the tune
			var metronome_events = metronome_generate_events({
				events: tune_events,
				tune_data: tune.tune_data
			}, metronome_settings);
		
			// Step 4: Optional count-in (prepend metronome measures)
			var countin_events = array_create(0);
			var count_in_measures = (is_struct(set_item) && !is_undefined(set_item.count_in_measures)) ? set_item.count_in_measures : 0;
			var count_in_ms = 0;
			if (count_in_measures > 0) {
				var meta = tune.tune_data.tune_metadata;
				var time_sig = metronome_normalize_time_sig(meta.meter ?? "4/4");
				var time_sig_parts = string_split(time_sig, "/");
				var beats_per_measure = real(time_sig_parts[0]);
				var denom = real(time_sig_parts[1]);
				var tempo_str = string(meta.tempo_default ?? "");
				var bpm_effective = (string_length(tempo_str) > 0) ? real(tempo_str) : 120;
				if (!is_undefined(bpm_override)) bpm_effective = real(bpm_override);
				var quarter_bpm_effective = metronome_get_effective_quarter_bpm(bpm_effective, time_sig);
				var ms_per_quarter = 60000 / quarter_bpm_effective;
				var beat_unit_ms = ms_per_quarter * (4 / denom);
				count_in_ms = count_in_measures * beats_per_measure * beat_unit_ms;
			
				countin_events = metronome_generate_countin_events({
					events: tune_events,
					tune_data: tune.tune_data
				}, metronome_settings, count_in_measures);
			
				// Find pickup duration (time before measure 1)
				// Prefer explicit measure-1 bar marker to avoid false offsets.
				var pickup_start_ms = 0;
				for (var i = 0; i < array_length(tune_events); i++) {
					var ev = tune_events[i];
					if (ev.type == "marker"
						&& (ev.marker_type ?? "") == "bar"
						&& real(ev.measure ?? 0) == 1) {
						pickup_start_ms = ev.time;
						break;
					}
				}
				// Fallback if markers are unavailable.
				if (pickup_start_ms == 0) {
					for (var i = 0; i < array_length(tune_events); i++) {
						var ev = tune_events[i];
						if (ev.type == "note_on" && real(ev.measure ?? 0) >= 1) {
							pickup_start_ms = ev.time;
							break;
						}
					}
				}
			
				// Shift tune + metronome events so measure 1 starts after count-in,
				// keeping pickup notes aligned within the count-in window.
				var shift_ms = max(count_in_ms - pickup_start_ms, 0);
				for (var i = 0; i < array_length(tune_events); i++) {
					tune_events[i].time += shift_ms;
				}
				for (var i = 0; i < array_length(metronome_events); i++) {
					metronome_events[i].time += shift_ms;
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
			array_sort(merged, function(a, b) { return a.time - b.time; });
			
			global.playback_events = merged;
			show_debug_message("Merged " + string(array_length(tune_events)) + " tune + " + string(array_length(metronome_events)) + " metronome = " + string(array_length(merged)) + " total");
			
			// Merged events ready for playback
			
			show_debug_message("Ready for playback with " + string(array_length(global.playback_events)) + " total events");
		} else {
			show_debug_message("WARNING: No tune loaded, proceeding without events");
			global.playback_events = [];
		}
		
		room_goto(Room_play);
		scr_open_window(0);
		scr_open_window(3);
		scr_open_window(4, true);
	}

	//CASE 2 Clicked Checkbox
	//Used in tune window but could be made generic
	function scr_checkbox_click()	{
	//Set the choices that were made in the settings window.
	// Remove "global." from the string
		var target_name = string_replace(self.button_target, "global.", "");
		
		if (self.button_checked==0) {
			//scr_uncheck_all(global.tune_window_checkboxes, self.button_ID) 
			scr_uncheck_all(global.ui_assets,self.ui_layer_num, self.ui_group, self.ui_num);
			self.button_checked=1;
			self.image_index=3;
			show_debug_message("input: " + string(target_name));
			variable_global_set(target_name, self.button_click_value);
			// Also notify the picker instance of the selection
			var picker = instance_find(obj_tune_picker, 0);
			if (picker != noone) picker.selected_index = self.button_click_value;
			// Safely update gameinfo title from the picker's library
			if (picker != noone && is_struct(picker.library) && picker.selected_index >= 0 && array_length(picker.library.tunes) > picker.selected_index) {
				obj_gameinfo_win_title.field_contents = picker.library.tunes[picker.selected_index].title;
				
				// Get tune metadata directly from library (no file reading needed)
				var entry = picker.library.tunes[picker.selected_index];
				
				// Update BPM field from library
				var tempo_str = string(entry.tempo_default ?? "120");
				if (string_length(tempo_str) > 0 && instance_exists(metro_field_3)) {
					metro_field_3.field_value = real(tempo_str);
					metro_field_3.field_contents = tempo_str;
				}
				
				// Update pattern list based on time signature from library
				var time_sig = string(entry.meter ?? "4/4");
				// Store in temp global so metronome mode changes use the selected tune's time sig
				global.selected_tune_time_sig = time_sig;
				show_debug_message("Checkbox click - updating patterns for time_sig: " + time_sig);
				metronome_update_pattern_list(time_sig);
				show_debug_message("Pattern options after update: " + string(global.metronome_pattern_options));
				if (instance_exists(metro_field_2) && array_length(global.metronome_pattern_options) > 0) {
					metro_field_2.field_value = global.metronome_pattern_selection;
					metro_field_2.field_contents = global.metronome_pattern_options[global.metronome_pattern_selection];
					show_debug_message("Set metro_field_2 to: " + metro_field_2.field_contents);
				}
			} else {
				show_debug_message("Should set the gameinfo tune");
			}
			show_debug_message("tune selection: " + string(global.tune_selection));
			
		}
		else if (self.button_checked==1) {
			//scr_uncheck_all(global.tune_window_checkboxes, self.button_ID)			
			scr_uncheck_all(global.ui_assets,self.ui_layer_num, self.ui_group, self.ui_num);
			self.button_checked=0;		
			variable_global_set(target_name, -1);
		}

		//show_debug_message("I clicked " + string(button_ID));
		//show_debug_message("button value " + string(button_click_value));
		//show_debug_message("tune selection = " + string(global.tune_selection));
	}	

	//Script to uncheck checkboxes for use when checking a new checkbox
	function scr_uncheck_all(array_of_checkboxes,ui_layer, ui_group, this_num) {
		show_debug_message("Uncheck in layer " + string(ui_layer) +
                       " group " + string(ui_group) +
                       " except ui_num " + string(this_num));

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
				with (cb) {
					if (variable_instance_exists(id, "ui_group") && ui_group == other.ui_group) {
						button_checked = 0;
						image_index    = 0;
						show_debug_message("Unchecked " + string(ui_name) + " in group " + string(ui_group));
					}
			    }
			} else if (!instance_exists(cb)) {
				// Attempt on-the-fly re-link by ui_num
				with (obj_ui_parent) {
					if (ui_num == num && ui_layer_num == ui_layer) {
						array_of_checkboxes[ui_layer][i][1] = id;
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
			var time_sig = "4/4";
			if (instance_exists(tune) && tune.tune_data.is_loaded) {
				var meta = tune.tune_data.tune_metadata;
				time_sig = string(meta.meter ?? "4/4");
			}
			metronome_update_pattern_list(time_sig);
			if (instance_exists(metro_field_2) && array_length(global.metronome_pattern_options) > 0) {
				metro_field_2.field_value = global.metronome_pattern_selection;
				metro_field_2.field_contents = global.metronome_pattern_options[global.metronome_pattern_selection];
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

			// Refresh MIDI field bounds/values without relying on fragile instance names
			with (obj_field_base) {
				if (!variable_instance_exists(id, "field_target")) continue;
				if (!is_string(field_target)) continue;

				if (field_target == "midi_input_devices" || field_target == "global.midi_input_devices") {
					field_min_value = 0;
					field_max_value = max(global._midi_refresh_input_count - 1, 0);
					field_value = clamp(field_value, field_min_value, field_max_value);
					field_contents = (global._midi_refresh_input_count > 0) ? midi_input_device_name(field_value) : "none";
				}

				if (field_target == "midi_output_devices" || field_target == "global.midi_output_devices") {
					field_min_value = 0;
					field_max_value = max(global._midi_refresh_output_count - 1, 0);
					field_value = clamp(field_value, field_min_value, field_max_value);
					field_contents = (global._midi_refresh_output_count > 0) ? midi_output_device_name(field_value) : "none";
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
			var time_sig = "4/4"; // Default
			
			if (instance_exists(tune) && tune.tune_data.is_loaded) {
				var meta = tune.tune_data.tune_metadata;
				time_sig = string(meta.meter ?? "4/4");
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
		room_goto(Room_main_menu);
		scr_open_window(0);
	}
	
	//CASE 6
	//change settings field by button value ... for +/- buttons (generic array cycling)
	function scr_settings_change()	{
		show_debug_message("I clicked " + string(button_ID));
		var field = self.field_ref;
		
		// Get the array this field is bound to
		var target_array = is_string(field.field_target) ? variable_global_get(field.field_target) : field.field_target;
		
		if (is_array(target_array)) {
			var array_len = array_length(target_array);
			
			// Cycle through array indices
			field.field_value = (field.field_value + self.button_click_value + array_len) % array_len;
			
			// Update display to show array element
			field.field_contents = target_array[field.field_value];
			
			show_debug_message("Field now shows: " + string(field.field_contents) + " (index " + string(field.field_value) + ")");
		} else {
			show_debug_message("WARNING: field_target is not an array");
		}
	}
	
	//CASE 7 - change settings specific for MIDI in
	function scr_settings_MIDI_In_change()	{

		show_debug_message("I clicked " + string(button_ID));
		self.field_ref.field_value = (self.field_ref.field_value + self.button_click_value);

		if(self.field_ref.field_value < self.field_ref.field_min_value) {
			self.field_ref.field_value = self.field_ref.field_max_value;
		}
		else if(self.field_ref.field_value > self.field_ref.field_max_value) {
			self.field_ref.field_value = self.field_ref.field_min_value;
		}		
		self.field_ref.field_contents = midi_input_device_name(self.field_ref.field_value);
		global.midi_input_device = self.field_ref.field_value;
		show_debug_message(string(self.field_ref.field_contents) + " " + string(self.field_ref.field_value));
	}
	
	//CASE 8 - change settings specific for MIDI out
	function scr_settings_MIDI_Out_change()	{

		show_debug_message("I clicked " + string(button_ID));
		self.field_ref.field_value = (self.field_ref.field_value + self.button_click_value);

		if(self.field_ref.field_value < self.field_ref.field_min_value) {
			self.field_ref.field_value = self.field_ref.field_max_value;
		}
		else if(self.field_ref.field_value > self.field_ref.field_max_value) {
			self.field_ref.field_value = self.field_ref.field_min_value;
		}		
		self.field_ref.field_contents = midi_output_device_name(self.field_ref.field_value);
		global.midi_output_device = self.field_ref.field_value;
		show_debug_message(string(self.field_ref.field_contents) + " " + string(self.field_ref.field_value));
	}
	
	//CASE 14 - Metronome Mode (None/Click/Drums)
	function scr_metronome_mode_change() {
		var field = self.field_ref;
		
		var array_len = array_length(global.metronome_mode_options);
		
		// Cycle through modes
		field.field_value = (field.field_value + self.button_click_value + array_len) % array_len;
		field.field_contents = global.metronome_mode_options[field.field_value];
		
		// Update global metronome mode
		global.metronome_mode = field.field_value;
		
		// Update METRONOME_CONFIG
		global.METRONOME_CONFIG.enabled = (global.metronome_mode > 0);
		global.METRONOME_CONFIG.mode = global.metronome_mode_options[field.field_value];
		
		// Refresh pattern list based on selected tune (if in tune window) or current loaded tune
		var time_sig = "4/4";
		// Use selected tune's time sig if available (set when checkbox clicked)
		if (variable_global_exists("selected_tune_time_sig") && global.selected_tune_time_sig != "") {
			time_sig = global.selected_tune_time_sig;
		} else {
			// Otherwise use currently loaded tune
			var tune = global.tune;
			if (instance_exists(tune) && tune.tune_data.is_loaded) {
				var meta = tune.tune_data.tune_metadata;
				time_sig = string(meta.meter ?? "4/4");
			}
		}
		metronome_update_pattern_list(time_sig);
		if (instance_exists(metro_field_2) && array_length(global.metronome_pattern_options) > 0) {
			metro_field_2.field_value = global.metronome_pattern_selection;
			metro_field_2.field_contents = global.metronome_pattern_options[global.metronome_pattern_selection];
		}
		
		// Persist to current set item
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.metronome_mode = global.metronome_mode;
					global.current_set[idx] = item;
				}
			}
		}
		
		show_debug_message("Metronome mode: " + field.field_contents);
	}
	
	//CASE 15 - Metronome Pattern
	function scr_metronome_pattern_change() {
		var field = self.field_ref;
		
		var array_len = array_length(global.metronome_pattern_options);
		
		if (array_len == 0) {
			show_debug_message("No patterns available");
			return;
		}
		
		// Cycle through patterns
		field.field_value = (field.field_value + self.button_click_value + array_len) % array_len;
		field.field_contents = global.metronome_pattern_options[field.field_value];
		
		// Update global selection
		global.metronome_pattern_selection = field.field_value;
		
		// Persist to current set item
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.metronome_pattern = global.metronome_pattern_selection;
					global.current_set[idx] = item;
				}
			}
		}
		
		show_debug_message("Metronome pattern: " + field.field_contents);
	}
	
	//CASE 16 - Metronome Volume
	function scr_metronome_volume_change() {
		var field = self.field_ref;
		
		// Change volume by button_click_value (typically ±10)
		var new_volume = global.metronome_volume + (self.button_click_value * 10);
		
		// Clamp to field's min/max range
		new_volume = clamp(new_volume, field.field_min_value, field.field_max_value);
		
		// Update global and field
		global.metronome_volume = new_volume;
		field.field_value = new_volume;
		field.field_contents = string(new_volume);
		
		// Update METRONOME_CONFIG velocities
		global.METRONOME_CONFIG.velocity_emphasis = new_volume;
		global.METRONOME_CONFIG.velocity_normal = floor(new_volume * 0.7); // Normal beats at 70% of emphasis
		
		// Persist to current set item
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.metronome_volume = global.metronome_volume;
					global.current_set[idx] = item;
				}
			}
		}
		
		show_debug_message("Metronome volume: " + string(new_volume));
	}

	//CASE 17 - Tune BPM
	function scr_tune_bpm_change() {
		var field = self.field_ref;
		
		var new_val = field.field_value + self.button_click_value;
		new_val = clamp(new_val, field.field_min_value, field.field_max_value);
		field.field_value = new_val;
		field.field_contents = string(new_val);
		
		// Update global BPM
		global.current_bpm = new_val;
		
		// Persist to current set item
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.bpm = global.current_bpm;
					global.current_set[idx] = item;
				}
			}
		}
		
		show_debug_message("BPM: " + string(new_val));
	}

	//CASE 18 - Tune Count-In
	function scr_tune_countin_change() {
		var field = self.field_ref;
		
		var new_val = field.field_value + self.button_click_value;
		new_val = clamp(new_val, 0, 2);
		field.field_value = new_val;
		field.field_contents = string(new_val);
		
		// Update global count-in
		global.count_in_measures = new_val;
		
		// Persist to current set item
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.count_in_measures = global.count_in_measures;
					global.current_set[idx] = item;
				}
			}
		}
		
		show_debug_message("Count-in measures: " + string(new_val));
	}

	//CASE 19 - Gracenote Override (ms)
	function scr_gracenote_override_change() {
		var field = self.field_ref;
		var new_val = field.field_value + self.button_click_value;
		new_val = clamp(new_val, field.field_min_value, field.field_max_value);
		field.field_value = new_val;
		field.field_contents = string(new_val);
		global.gracenote_override_ms = new_val;
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.gracenote_override_ms = global.gracenote_override_ms;
					global.current_set[idx] = item;
				}
			}
		}
		show_debug_message("Gracenote override (ms): " + string(new_val));
	}

	//CASE 20 - Swing Multiplier
	function scr_swing_mult_change() {
		var field = self.field_ref;
		var new_val = field.field_value + self.button_click_value;
		new_val = clamp(new_val, field.field_min_value, field.field_max_value);
		field.field_value = new_val;
		field.field_contents = string(new_val);
		global.swing_mult = new_val;
		if (is_array(global.current_set)) {
			var idx = global.current_set_item_index;
			if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
				var item = global.current_set[idx];
				if (is_struct(item)) {
					item.swing_mult = global.swing_mult;
					global.current_set[idx] = item;
				}
			}
		}
		show_debug_message("Swing multiplier: " + string(new_val));
	}

	//CASE 9
	function scr_settings_OK()	{
	//Set the choices that were made in the settings window. 
		show_debug_message("I clicked " + string(button_ID));
		midi_input_device_open(global.midi_input_device);
		midi_output_device_open(global.midi_output_device);
		// Hide settings window robustly
		if (!scr_hide_window(self.button_label, self)) show_debug_message("Warning! - scr_settings_OK: could not find layer to hide for target: " + string(self.button_label)); // Toggle visibility
	}	
	
	//CASE 10  THis OK button in the tune window locks in the selected 
	function scr_tune_OK()	{
	//Set the choices that were made in the settings window. 
		show_debug_message("I clicked " + string(button_ID));
		show_debug_message("Tune selected: " + string(global.tune_selection));
		// Ensure button_label points to a valid layer name (fallback to ui_layer_num)
		var saved_button_label = self.button_label;
		if (!is_string(self.button_label) || layer_get_id(self.button_label) == -1) {
			if (variable_instance_exists(self, "ui_layer_num")) {
				self.button_label = GetLayerNameFromIndex(self.ui_layer_num);
			}
		}
		
		var picker = instance_find(obj_tune_picker, 0);
		if (picker != noone && picker.selected_index >= 0) {
		    var entry = picker.library.tunes[picker.selected_index];
		    var candidates = array_create(0);
		    // Use library root when available
		    if (is_struct(picker.library) && variable_struct_exists(picker.library, "root") && picker.library.root != "") {
		        array_push(candidates, picker.library.root + entry.filename);
		    }
		    array_push(candidates, "tunes/" + entry.filename);
		    array_push(candidates, "datafiles/tunes/" + entry.filename);

		    var loaded = false;
		    for (var i = 0; i < array_length(candidates) && !loaded; i++) {
		        var tryfile = candidates[i];
		        show_debug_message("Attempting to load tune: " + string(tryfile));
		        if (scr_tune_load_json(tryfile)) {
		            show_debug_message("Loaded tune: " + string(tryfile));
		            
		            // === CREATE SET ITEM FROM SELECTED TUNE ===
		            var item = create_set_item(tryfile);
		            var perf = global.tune.tune_data.performance;
		            var meta = global.tune.tune_data.tune_metadata;
		            var default_swing = perf.swing ?? meta.swing ?? "";
		            if (!is_undefined(default_swing) && string(default_swing) != "") {
		                item.swing_mult = default_swing;
		            }
		            
		            // Find and capture tune-specific settings by ui_name
				    with(obj_field_base) {
				        if (ui_name == "tune_BPM_field") item.bpm = field_value;
				        if (ui_name == "tune_countin_field") item.count_in_measures = field_value;
				        if (ui_name == "metro_field_3") item.bpm = field_value;
				        if (ui_name == "metro_field_4") item.count_in_measures = field_value;
				    }
		            
		            with(obj_field_base) {
		                if (ui_name == "metro_field_1") item.metronome_mode = field_value;
		                if (ui_name == "metro_field_2") item.metronome_pattern = field_value;
		                if (ui_name == "metro_field_5") item.metronome_volume = field_value;
						if (ui_name == "metro_field_6") item.swing_mult = field_value;
						if (ui_name == "metro_field_7") item.gracenote_override_ms = field_value;
		            }
				    global.current_set = [item];
				    global.current_set_item_index = 0;
		    
				    // Sync set item values to globals for UI display
				    global.current_bpm = item.bpm ?? 120;
				    global.metronome_mode = item.metronome_mode;
				    global.metronome_pattern_selection = item.metronome_pattern;
				    global.metronome_volume = item.metronome_volume;
				    global.count_in_measures = item.count_in_measures;
			    	global.swing_mult = item.swing_mult;
					global.gracenote_override_ms = item.gracenote_override_ms;
		    
				    show_debug_message("Created set item: " + tryfile + 
		                " | BPM=" + string(item.bpm) + 
		                " | Count-in=" + string(item.count_in_measures) + 
		                " | Metronome=" + global.metronome_mode_options[item.metronome_mode]);
		            
		            // Close the tune window
		            layer_set_visible(self.button_label, 0);
		            // Update game info title if available
		            if (variable_struct_exists(entry, "title")) obj_gameinfo_win_title.field_contents = entry.title;
		            loaded = true;
		        }
		    }
		    if (!loaded) show_debug_message("Failed to load tune from candidates.");
		    else { if (!scr_hide_window(self.button_label, self)) show_debug_message("Warning! - scr_tune_OK: could not find layer to hide for target: " + string(self.button_label)); }
		    // Restore original button label
		    self.button_label = saved_button_label;
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
		show_debug_message("Tune instance: " + string(tune) + " exists: " + string(instance_exists(tune)));
		show_debug_message("  DEBUG: Before preprocessing - tune.events length = " + string(array_length(tune.tune_data.events ?? array_create(0))));
		if (instance_exists(tune) && tune.tune_data.is_loaded) {
			// Events are already preprocessed and stored in global.playback_events
			if (variable_global_exists("playback_events") && array_length(global.playback_events) > 0) {
				tune_start(global.playback_events);
			} else {
				show_debug_message("ERROR: No playback events prepared. Did you go through main menu?");
			}
		} else {
			show_debug_message("ERROR: No tune loaded. Please select and confirm a tune first.");
			if (!instance_exists(tune)) show_debug_message("  - obj_tune instance does not exist");
			else if (!tune.tune_data.is_loaded) show_debug_message("  - tune.is_loaded = " + string(tune.tune_data.is_loaded));
		}
}

	//CASE 12
	//Regenerate Tune Library (manual trigger)
	function scr_regenerate_tune_library(){
		show_debug_message("===== REGENERATING TUNE LIBRARY =====");
		scr_build_tune_library("tunes/");
		show_debug_message("===== TUNE LIBRARY REGENERATION COMPLETE =====");
		show_debug_message("Tune library now contains " + string(array_length(global.tune)) + " tunes");
	}

	//CASE 13
	/// @function export_event_history()
	/// @description Export the current event history to CSV
	function export_event_history() {
		var tune_name = global.current_tune_name ?? "unknown";
		var safe_tune = event_history_sanitize_name(tune_name);
		var tune_title = event_history_get_tune_title();
		var clean_tune = event_history_clean_tune_name(tune_title);
		if (clean_tune == "") {
			clean_tune = "unknown";
		}
		var bpm = !is_undefined(global.current_bpm) ? global.current_bpm : 120;
		var swing = !is_undefined(global.swing_mult) ? global.swing_mult : 0;
		var grace = !is_undefined(global.gracenote_override_ms) ? global.gracenote_override_ms : 0;
		var timestamp = event_history_format_timestamp();
		var folder = "datafiles/performances/" + clean_tune;
		if (!directory_exists(folder)) {
			directory_create(folder);
		}
		var filename = clean_tune + "_" + timestamp + "_" + string(bpm) + "_" + string(swing) + "_" + string(grace) + ".csv";
		var filepath = folder + "/" + filename;
	    event_history_export_csv(filepath);
	}
