

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
			if (array_length(global.tune_library)>global.tune_selection)	{
				show_debug_message("Should set the gameinfo tune");
				obj_gameinfo_win_title.field_contents = string(global.tune_library[global.tune_selection]);
			} else { show_debug_message("Should set the gameinfo tune"); }
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
		room_goto(Room_main_menu);
		scr_open_window(0);
	}
	
	//CASE 6
	//change settings field by button value ... for +/- buttons
	function scr_settings_change()	{
		//THis is generic, its not used for anything right now. 
		show_debug_message("I clicked " + string(button_ID));
		self.field_ref.field_value = (self.field_ref.field_value + self.button_click_value);

		if(self.field_ref.field_value < self.field_ref.field_min_value) {
			self.field_ref.field_value = self.field_ref.field_max_value;
		}
		else if(self.field_ref.field_value > self.field_ref.field_max_value) {
			self.field_ref.field_value = self.field_ref.field_min_value;
		}		
		self.field_ref.field_contents = string(self.field_ref.field_value);
		variable_global_set(var_name, new_value);
		
		show_debug_message(string(self.field_ref.field_contents) + " " + string(self.field_ref.field_value));
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
	
	//CASE 8 - change settings specific for MIDI in
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

	//CASE 9
	function scr_settings_OK()	{
	//Set the choices that were made in the settings window. 
		show_debug_message("I clicked " + string(button_ID));
		midi_input_device_open(global.midi_input_device);
		midi_output_device_open(global.midi_output_device);
		layer_set_visible(self.button_label, 0); // Toggle visibility
	}	
	
	//CASE 10  THis OK button in the tune window locks in the selected 
	function scr_tune_OK()	{
	//Set the choices that were made in the settings window. 
		show_debug_message("I clicked " + string(button_ID));
		show_debug_message("Tune selected: " + string(global.tune_selection));
		scr_open_window(self.ui_layer_num,true);
		//global.tune_events = global.tune[global.tune_selection] //tune_selection is changed by the tune checkboxes...
		//global.tune_index = 0;
		//layer_set_visible(self.button_label, 0); // Toggle visibility closing the window
	}	
	
	//CASE 11
	function start_play() {
		midi_output_device_open_all();
		midi_input_device_open_all();
		MIDI_start_manual_check_messages();
		show_debug_message("manual MIDI started");
		show_debug_message("input = " + string(global.midi_input_device));
		show_debug_message("tune start " + string(global.tune_selection));
		tune_start(global.tune[global.tune_selection]);

		//
		// Start playback at the first part, first event
		//time_source_start(global.tune_timer);
		//global.tune_start_time = current_time;
		//show_debug_message(string(current_time - global.tune_start_time));
	}



