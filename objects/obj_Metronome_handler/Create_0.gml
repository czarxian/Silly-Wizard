//reference holder
	global.ID_metronome=id;
	global.metro_processor=noone;
	
//globals
	//Starting time and time since start
	global.metronome_start_time=0;
	global.metronome_time_since_start=0;

	//current time
	global.metronome_curent_time = current_time - (global.metronome_start_time);


//Create Tunetypes, template settings for a metronome. 
	//This is an array of preset metronome settings.
	tunetypes = array_create(4); 
	tunetypes[0] = create_metronome_tunetype("custom",4,4,1,60);
	tunetypes[1] = create_metronome_tunetype("4/4 March",4,4,1,80);
	tunetypes[2] = create_metronome_tunetype("3/4 March",3,4,1,70);
	tunetypes[3] = create_metronome_tunetype("6/8 March",2,3,3,180);

	global.metronome_tunetype_max=array_length(tunetypes)-1;
	global.metronome_tunetype_number= 1;
	Set_Metronome_to_Tunetype(global.metronome_tunetype_number);

	//Create a tune file, midi event log, etc. 
	var num_events = 12;
	global.metronome_events = array_create(num_events);
	quarter_note = ((60/global.metronome_bpm));
	eight_note = ((60/global.metronome_bpm)/2);
	sixteenth_note = ((60/global.metronome_bpm)/4);
	thirtysecond_note = ((60/global.metronome_bpm)/8);
	sixtyfourth_note = ((60/global.metronome_bpm)/16);
	
//	
	global.metronome_events[0] = create_midi_eventfile(0, 0, 144, 9, 153, 36, "kick", 100);
	global.metronome_events[1] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 	
	global.metronome_events[2] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 
	global.metronome_events[3] = create_midi_eventfile(0, 0, 144, 9, 153, 38, "snare", 100);
	global.metronome_events[4] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 	
	global.metronome_events[5] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 	
	global.metronome_events[6] = create_midi_eventfile(0, 0, 144, 9, 153, 36, "kick", 100);
	global.metronome_events[7] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 	
	global.metronome_events[8] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 	
	global.metronome_events[9] = create_midi_eventfile(0, 0, 144, 9, 153, 38, "snare", 100);
	global.metronome_events[10] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
	 
	global.metronome_events[11] = create_midi_eventfile(eight_note, eight_note, 144, 9, 153, 42, "hihat", 100);
		
	global.metronome_events[12] = create_midi_eventfile(0, 0, 999, 0, 999, 0, "END", 0);

	
//This should send a note on event for channel 09 (percussion) and note 38 (snare) at a high velocity, followed by a note off.
//	midi_output_message_send_short(global.midi_output, 152, 38, 100);//Sends the MIDI Message to the MIDI Output Device
//	midi_output_message_send_short(global.midi_output, 136, 38, 0);//Sends the MIDI Message to the MIDI Output Device


//Update an array based on the selected bpm.
	update_timing(global.metronome_events,60,global.metronome_bpm); //60 should be the specific tunes base bpm);
	 
	