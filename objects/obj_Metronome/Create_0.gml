//This is 

//Create metronome object
	event_inherited();
	dragging = false;

//create a time source, start via the menu
	global.metronome = id;
	global.metronome_beat_updated=false;
	global.metronome_start_time = current_time;
	global.metronome_curent_time = current_time - (global.metronome_start_time);
	global.Midi_event_number = 0;
	global.Midi_next_event_deltatime = global.metronome_events[global.Midi_event_number+1].deltatime;

//create timesource... it will start when play is clicked. Note that this requires a event checking step.
	global.metro_processor = time_source_create(time_source_game, (global.Midi_next_event_deltatime), time_source_units_seconds, method(self, Process_Events_3), [global.Midi_event_number, global.metro_processor], 1, time_source_expire_nearest);
	
//Create central text... 
	textOffsetx = (sprite_width/2);
	textOffsety = (sprite_height/2);
	textx = x + textOffsetx;
	texty = y + textOffsety;
	text=0;
	textstring=(string(global.metronome_curent_time));

//Change the OK button to a play button.
	if(has_right_button==true) {
		//rely on the parent create event to create the button and update the text and function.
		dragging = false;
		ok_button.button_text = "Play";
		ok_button_script = function() {
			//Add code to open whatever MIDI input and outpur devices are selected.
			MIDI_start_manual_check_messages();
			MIDI_process_messages();
			time_source_start(global.metro_processor);
		}
		ok_button.button_script = ok_button_script;
	}




	