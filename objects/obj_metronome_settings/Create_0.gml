/// @description Insert description here
// You can write your code in this editor

// Inherit the parent event
	event_inherited();
	dragging = false;

//Set up the OK button. Default just closes the screen.
	ok_button_script = function()		{
	//Add code to open whatever MIDI input and outpur devices are selected.
		//show_message(string(global.metronome_events[0].deltatime));
		dragging = false;
		instance_destroy(self);
		global.next_window_depth-=10;
		//update whatever you are playing to the new BPM.
		update_timing(global.metronome_events,60,global.metronome_bpm);
	}
	ok_button.button_script = ok_button_script;

//Set up Metronome Settings screen
//Each item is tied to a variable, the fields display the value, and the other buttons change it.
	number_of_settings = 2;
	setting_window_title_origin = 0;
	setting_window_content_origin = 25 + 0;
	setting_item_space = 10;
	setting_item_height = 48; //calculate this in future
	setting_item_scale = -.55;
	setting_item_yscale = 1.0;
	setting_item_width = sprite_get_width(spr_setting_item) * -setting_item_scale;
	setting_item_max_length = 20;
	setting_item_suffix = "...";

//Each setting item has a block of code. The setting item field to show the value and the left and right buttons.
//Ideally this would be relaced with e.g., a script ot something more compressed.

//Create setting with left and right arrow
	for(i=0; i< number_of_settings; i++;) {
		item_value = array_create(i,0);
		item_min_value = array_create(i,0);
		item_max_value = array_create(i,0);
		setting_item = array_create(i,noone);
		setting_item_left_button = array_create(i,noone);
		setting_item_left_button_script = array_create(i,noone);
		setting_item_right_button = array_create(i,noone);
		setting_item_right_button_script = array_create(i,noone);
	}
	

//Button Code Template: Setting item 0 - ... Select Tunetype, this loads default bpm, rhythm settings 
	i=0;
	if(i >= number_of_settings) {show_message("Too many items in the metronome settings window")};
	item_value[i] = global.metronome_tunetype_number;
	item_min_value[i] = 0;
	item_max_value[i] = global.metronome_tunetype_max;	
	setting_item[i] = instance_create_depth(x + 10 + sprite_get_width(spr_arrow_left)+10, y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].image_yscale = setting_item_yscale;
	setting_item[i].field_label = "Type";
	setting_item[i].field_text = truncate(global.ID_metronome.tunetypes[global.metronome_tunetype_number].tunetype_name,setting_item_max_length,setting_item_suffix);
	setting_item[i].field_updated = false;
	
	setting_item_left_button_script[i] = function(item_number) {
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			global.metronome_tunetype_number=item_value[item_number];
			setting_item[item_number].field_text = truncate(global.ID_metronome.tunetypes[global.metronome_tunetype_number].tunetype_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
			with(obj_Metronome_handler) {
				Set_Metronome_to_Tunetype(global.metronome_tunetype_number);
			}
			setting_item[1].field_text=string(global.metronome_bpm);
			item_value[1]=global.metronome_bpm;
			setting_item[1].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			global.metronome_tunetype_number=item_value[item_number];
			setting_item[item_number].field_text = truncate(global.ID_metronome.tunetypes[global.metronome_tunetype_number].tunetype_name,setting_item_max_length,setting_item_suffix);
			with(obj_Metronome_handler) {
				Set_Metronome_to_Tunetype(global.metronome_tunetype_number);
			} 
//			Set_Metronome_to_Tunetype(global.metronome_tunetype_number);
			setting_item[item_number].field_updated = true;
			setting_item[1].field_text=string(global.metronome_bpm);
			item_value[1]=global.metronome_bpm;
			setting_item[1].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			global.metronome_tunetype_number=item_value[item_number];
			setting_item[item_number].field_text = truncate(global.ID_metronome.tunetypes[global.metronome_tunetype_number].tunetype_name,setting_item_max_length,setting_item_suffix);
		//update metronome settings
			with(obj_Metronome_handler) {
				Set_Metronome_to_Tunetype(global.metronome_tunetype_number);
			} 
			setting_item[item_number].field_updated = true;
			setting_item[1].field_text=string(global.metronome_bpm);
			item_value[1]=global.metronome_bpm;			
			setting_item[1].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			global.metronome_tunetype_number=item_value[item_number];
			setting_item[item_number].field_text = truncate(global.ID_metronome.tunetypes[global.metronome_tunetype_number].tunetype_name,setting_item_max_length,setting_item_suffix);
		//update metronome settings
			with(obj_Metronome_handler) {
				Set_Metronome_to_Tunetype(global.metronome_tunetype_number);
			} 
			setting_item[item_number].field_updated = true;
			setting_item[1].field_text=string(global.metronome_bpm);
			item_value[1]=global.metronome_bpm;			
			setting_item[1].field_updated = true;
		}
	}
	setting_item_left_button[i] = instance_create_depth(x + 20, y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_left);
	setting_item_right_button[i] = instance_create_depth((x + setting_item_width + 52 ), y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_right);
	setting_item_left_button[i].item_parent = setting_item[i];
	setting_item_left_button[i].button_script = setting_item_left_button_script[i];
	setting_item_left_button[i].button_script_number = i;
	setting_item_right_button[i].item_parent = setting_item[i];
	setting_item_right_button[i].button_script = setting_item_right_button_script[i];
	setting_item_right_button[i].button_script_number = i;


//Button Code Template: Setting item 1 - ...
	i=1;
	if(i >= number_of_settings) {show_message("Too many items in the metronome settings window")};
	item_value[i] = global.metronome_bpm;
	item_min_value[i] = 0;
	item_max_value[i] = 300;	
	setting_item[i] = instance_create_depth(x + 10 + sprite_get_width(spr_arrow_left)+10, y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].image_yscale = setting_item_yscale;
	setting_item[i].field_label = "BPM";
	setting_item[i].field_text = string(global.metronome_bpm);
	setting_item[i].field_updated = false;
	
	setting_item_left_button_script[i] = function(item_number) {
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			global.metronome_bpm = item_value[item_number];
			setting_item[item_number].field_text = string(global.metronome_bpm);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			global.metronome_bpm = item_value[item_number];
			setting_item[item_number].field_text = string(global.metronome_bpm);
			setting_item[item_number].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			global.metronome_bpm = item_value[item_number];
			setting_item[item_number].field_text = string(global.metronome_bpm);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			global.metronome_bpm = item_value[item_number];
			setting_item[item_number].field_text = string(global.metronome_bpm);
			setting_item[item_number].field_updated = true;
		}
	}
	setting_item_left_button[i] = instance_create_depth(x + 20, y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_left);
	setting_item_right_button[i] = instance_create_depth((x + setting_item_width + 52 ), y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_right);
	setting_item_left_button[i].item_parent = setting_item[i];
	setting_item_left_button[i].button_script = setting_item_left_button_script[i];
	setting_item_left_button[i].button_script_number = i;
	setting_item_right_button[i].item_parent = setting_item[i];
	setting_item_right_button[i].button_script = setting_item_right_button_script[i];
	setting_item_right_button[i].button_script_number = i;
