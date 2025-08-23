//Step events


//Inherit dragging functionality
	event_inherited();

//Update metronome time
	global.metronome_curent_time = current_time - (global.metronome_start_time);

//if global.paused==false {
	//Check MIDI messages on each step
	MIDI_process_messages();
	MIDI_check_errors();
//}