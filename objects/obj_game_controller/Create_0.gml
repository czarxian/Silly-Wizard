//Create Globals

//Global ID References
	global.ID_game_handler = id;
	global.metronome=noone;
	global.tune=noone;

//Game State
	global.game_state="menu";
		
//MIDI globals
  //MIDI Input 
	global.midi_input_devices[0] = "not selected";
	global.midi_input_device=0;
	global.midi_input_device_name="not selected";
	//global.chanter_number=0;
	//global.chanter_name="not selected";
	global.midi_input_channel=0;

  //MIDI Output 
	global.midi_output_devices[0] = "not selected"; 
	global.midi_output_device=0;
	global.midi_output_device_name="not selected";
	global.midi_ouput_channel=0;
	
	global.midi_output_drum=0;
	global.midi_output_drum_name="not selected";
	global.midi_ouput_drum_channel=0;

//Event gobals
	global.Midi_event_number=0;
	global.Midi_last_event_number=0;
	global.Midi_current_event_time=0;	
	global.Midi_next_event_deltatime=0;

