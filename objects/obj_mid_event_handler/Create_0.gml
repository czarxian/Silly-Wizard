//reference holder
	global.ID_tune_handler=id;
	global.tune_processor=noone;

//Right now these values arent defined in a central location
	//Create a tune file, midi event log, etc. 
	var num_events = 4;
	global.tune_events = array_create(num_events);
	whole_note = ((60/global.metronome_bpm)*2);
	half_note = ((60/global.metronome_bpm)*2);
	quarter_note = ((60/global.metronome_bpm));
	eight_note = ((60/global.metronome_bpm)/2);
	sixteenth_note = ((60/global.metronome_bpm)/4);
	thirtysecond_note = ((60/global.metronome_bpm)/8);
	sixtyfourth_note = ((60/global.metronome_bpm)/16);

//Tune data. 
	//Load tune data into array.
	//temporary tune data is in global.tune_events

//Update tune data based on settings (bpm etc).
//	update_timing(global.tune_events, 60, global.metronome_bpm); //60 should be the specific tunes base bpm);


//create timesource... it will start when play is clicked. Note that this requires a event checking step.
	global.tune_processor = time_source_create(time_source_game, (global.Midi_next_event_deltatime), time_source_units_seconds, method(self, Process_Events_3), [global.Midi_event_number, global.metro_processor], 1, time_source_expire_nearest);
	

	