// obj_game_controller — Project controller
// Purpose: Central global state & references hub. Initializes tune library and MIDI/global game state.
// Key responsibilities:
//  - Calls old_scr_tune_library() to initialize tune library.
//  - Sets global.ID_game_handler, global.metronome, global.ID_player, global.tune_picker, global.tune.
//  - Initializes MIDI device lists and MIDI event counters used by scr_MIDI and scr_button_scripts.
// Related scripts: scripts/scr_tune_library/, scripts/scr_MIDI/, scripts/scr_button_scripts/

//Create Globals
	old_scr_tune_library();

//Global ID References
	global.ID_game_handler = id;
	global.metronome=noone;
	global.ID_player=noone;
	global.tune_picker=noone;
	global.tune=noone;

//Game State
	global.game_state="menu";
		
//MIDI globals
  //MIDI Input 
	global.midi_input_devices[0] = "not selected";
	global.midi_input_device=0;
	global.midi_input_device_name="not selected";
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

