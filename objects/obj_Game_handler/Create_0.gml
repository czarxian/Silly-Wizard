/// @description Insert description here
// You can write your code in this editor

//Global UI variables	
    global.ui_elements = [];


//Game options
	global.gamespeed=120;
	game_set_speed(global.gamespeed, gamespeed_fps);
//	global.graphics_scale=1;  //Not in use
	global.volume=1;
	global.paused = false;

//Create Globals

//Global ID References
	global.ID_game_handler = id;
	


//Global UI variables	
	global.metronome=noone;
	global.tune=noone;

//MIDI globals
	global.midi_input_devices[0] = "";
	global.output_device=0;
	global.output_drum_device=0;
	global.midi_input_name="not selected";
	global.midi_input=0;
	global.chanter_number=0;
	global.chanter_name="not selected";
	global.midi_input_channel=0;
	global.chanter_channel=global.midi_input_channel;
	global.midi_output_name="not selected";
	global.midi_output=0;
	global.Midi_event_number=0;
	global.Midi_last_event_number=0;
	global.Midi_current_event_time=0;	
	global.Midi_next_event_deltatime=0;
	
	global.metronome_pause_delta=0;

//Metronome globals
	global.metronome_start_time=0;
	global.metronome_current_beat=0;
	global.metronome_beatspermeasure=0; 
	global.metronome_current_measure=0;
	
	
//windows handlers
	global.next_window_depth = -10;
	global.mainmenu_window_exists = false;