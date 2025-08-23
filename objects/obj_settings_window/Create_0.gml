
//The window is associated with items, which show a specific value and buttons to increment it.
//The buttons are not directly associated with a varaible; rather they are handled via the window.


// Inherit the parent event
event_inherited();
dragging = false;


//Set up the OK button. 
//Default just closes the screen.
	ok_button_script = function() 	{
	//Add code to open whatever MIDI input and outpur devices are selected.
	dragging = false;
	midi_input_device_open(global.chanter_number);
	midi_output_device_open(global.midi_output);
		
	//Close window and clear up all of the objects.
		//show_message("Midi input: " + global.chanter_name + ".\nMidi output: " + global.midi_output_name);
		instance_destroy(self);
		global.next_window_depth-=10;
	}
	ok_button.button_script = ok_button_script;


//Set up the configuration for the setting items.
//Each item is tied to a variable, the fields display the value, and the other buttons change it.

number_of_settings = 4;
setting_window_title_origin = 0;
setting_window_content_origin = 72 + 0;
setting_item_space = 20;
setting_item_height = 48; //calculate this in future
setting_item_scale = -.55;
setting_item_width = sprite_get_width(spr_setting_item) * -setting_item_scale;
setting_item_max_length = 20;
setting_item_suffix = "...";


//Each setting item has a block of code. The setting item field to show the value and the left and right buttons.
//Ideally this would be relaced with e.g., a script ot something more compressed.

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
show_debug_message(item_value);

//Button Code Template: Setting item 0 - MIDI Input
	i=0;
	if(i >= number_of_settings) {show_message("Too many items in the setting window")};
	item_value[i] = global.chanter_number;
	global.chanter_name = midi_input_device_name(global.chanter_number);
	item_min_value[i] = 0;
	item_max_value[i] = midi_input_device_count()-1;	
	setting_item[i] = instance_create_depth(x + 10 + sprite_get_width(spr_arrow_left)+10, y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].field_label = "MIDI In:";
	setting_item[i].field_text = truncate(global.chanter_name,setting_item_max_length,setting_item_suffix);
	setting_item[i].field_updated = false;
	
	setting_item_left_button_script[i] = function(item_number) {
			dragging = false; 
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			global.chanter_number=item_value[item_number];
			global.chanter_name = midi_input_device_name(global.chanter_number);
			setting_item[item_number].field_text = truncate(global.chanter_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			global.chanter_number=item_value[item_number];
			global.chanter_name = midi_input_device_name(global.chanter_number);
			setting_item[item_number].field_text = truncate(global.chanter_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
			dragging = false; 
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			global.chanter_number=item_value[item_number];
			global.chanter_name = midi_input_device_name(global.chanter_number);
			setting_item[item_number].field_text = truncate(global.chanter_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			global.chanter_number=item_value[item_number];
			global.chanter_name = midi_input_device_name(global.chanter_number);
			setting_item[item_number].field_text = truncate(global.chanter_name,setting_item_max_length,setting_item_suffix);
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


////MIDI OUT Button
	i=1;
	if(i >= number_of_settings) {show_message("Too many items in the setting window")};
	item_value[i] = global.midi_output;
	global.midi_output_name = midi_output_device_name(global.midi_output);	
	item_min_value[i] = 0;
	item_max_value[i] = midi_output_device_count()-1;
	setting_item[i] = instance_create_depth(x+10+sprite_get_width(spr_arrow_left)+10,y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].field_label = "MIDI Out:";
	setting_item[i].field_text = truncate(global.midi_output_name,setting_item_max_length,setting_item_suffix);
	setting_item[i].field_updated = false;

	setting_item_left_button_script[i] = function(item_number) {
			dragging = false; 
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			global.midi_output=item_value[item_number];
			global.midi_output_name = midi_output_device_name(global.midi_output);
			setting_item[item_number].field_text = truncate(global.midi_output_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			global.midi_output=item_value[item_number];
			global.midi_output_name = midi_output_device_name(global.midi_output);
			setting_item[item_number].field_text = truncate(global.midi_output_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
			dragging = false; 
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			global.midi_output=item_value[item_number];
			global.midi_output_name = midi_output_device_name(global.midi_output);
			setting_item[item_number].field_text = truncate(global.midi_output_name,setting_item_max_length,setting_item_suffix);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			global.midi_output=item_value[item_number];
			global.midi_output_name = midi_output_device_name(global.midi_output);
			setting_item[item_number].field_text = truncate(global.midi_output_name,setting_item_max_length,setting_item_suffix);
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

//Button Code Template: Setting item 2 
	i=2;
	if(i >= number_of_settings) {show_message("Too many items in the setting window")};
	item_value[i] = 2;
	item_min_value[i] = 0;
	item_max_value[i] = 5;	
	setting_item[i] = instance_create_depth(x + 10 + sprite_get_width(spr_arrow_left)+10,y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].field_label = "Setting Item";
	setting_item[i].field_text = "Item " + string(item_value[i]);
	setting_item[i].field_updated = false;

	setting_item_left_button_script[i] = function(item_number) {
		dragging = false; 
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
		dragging = false; 
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
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


//Button Code Template: Setting item 3 
	i=3;
	if(i >= number_of_settings) {show_message("Too many items in the setting window")};
	item_value[i] = 3;
	item_min_value[i] = 0;
	item_max_value[i] = 5;	
	setting_item[i] = instance_create_depth(x + 10 + sprite_get_width(spr_arrow_left)+10,y+((i+1)*(setting_window_content_origin+setting_item_space)), depth-11, obj_setting_item);
	setting_item[i].image_xscale = setting_item_scale;
	setting_item[i].field_label = "Setting Item";
	setting_item[i].field_text = "Item " + string(item_value[i]);
	setting_item[i].field_updated = false;
	
	setting_item_left_button_script[i] = function(item_number) {
		dragging = false; 
		if (item_value[item_number] > item_min_value[item_number]) {
			item_value[item_number]--;
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_max_value[item_number];
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
	}

	setting_item_right_button_script[i] = function(item_number) {
		dragging = false; 
		if (item_value[item_number] < item_max_value[item_number]) {
			item_value[item_number]++;
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
		else	{
			item_value[item_number]=item_min_value[item_number];
			setting_item[item_number].field_text = "Item " + string(item_value[item_number]);
			setting_item[item_number].field_updated = true;
		}
	}
	
	setting_item_left_button[i] = instance_create_depth(x + 20, y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_left);
	setting_item_left_button[i].item_parent = setting_item[i];
	setting_item_left_button[i].button_script = setting_item_left_button_script[i];
	setting_item_left_button[i].button_script_number = i;

	setting_item_right_button[i] = instance_create_depth((x + setting_item_width + 52 ), y + ((1+i) * (setting_item_space + setting_item_height)), depth-13, obj_setting_item_button_right);
	setting_item_right_button[i].item_parent = setting_item[i];
	setting_item_right_button[i].button_script = setting_item_right_button_script[i];
	setting_item_right_button[i].button_script_number = i;

