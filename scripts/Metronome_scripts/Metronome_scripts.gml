// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

//Process a midi event from a tune, log, or metronome array. 
	function Process_Midi_Event(Event_num, timesource, event_array)	{
		textstring=(string(current_time) );
	    show_debug_message("Starting processing"+string(Event_num));
		var _eventtype=event_array[Event_num].midi_event_type;
		switch (_eventtype)	{
			case 144: //NoteOn is 144-159 .... event type = 144 plus the channel 0-15...
				midi_output_message_send_short(global.midi_output, event_array[Event_num].midi_byte1, event_array[Event_num].midi_event_value, event_array[Event_num].midi_event_velocity);//Sends the MIDI Message to the MIDI Output Device
				show_debug_message("Note on " + string(Event_num) + textstring);
			case 128: //NoteOff is 128-143 .... event type = 128 plus the channel 0-15...
				midi_output_message_send_short(global.midi_output, event_array[Event_num].midi_byte1, event_array[Event_num].midi_event_value, event_array[Event_num].midi_event_velocity);//Sends the MIDI Message to the MIDI Output Device
				show_debug_message("Note off " + string(Event_num) + textstring);		
			case 999: //End of event array
				show_debug_message("End " + string(Event_num) + textstring);
		break;
		}
		//Set up next event
		global.Midi_event_number++;
		global.Midi_next_event_deltatime = global.metronome_events[global.Midi_event_number].deltatime;
		time_source_reconfigure(timesource,(global.Midi_next_event_deltatime), time_source_units_seconds, method(self, Process_Events_3), [global.Midi_event_number, timesource], 1, time_source_expire_nearest);
		time_source_start(timesource);		
	}

//Process a midi event from a tune, log, or metronome array. 
	function Process_Events_3(Event_num, timesource)	{
		textstring=(string(current_time) );
	    show_debug_message("Starting processing"+string(global.Midi_event_number));
		var _eventtype=global.metronome_events[global.Midi_event_number].midi_event_type;
		switch (_eventtype)	{
			case 144: //NoteOn
				midi_output_message_send_short(global.midi_output, global.metronome_events[global.Midi_event_number].midi_byte1, global.metronome_events[global.Midi_event_number].midi_event_value, global.metronome_events[global.Midi_event_number].midi_event_velocity);//Sends the MIDI Message to the MIDI Output Device
				show_debug_message("Note on " + string(Event_num) + textstring);
			case 128: //NoteOff
				//midi_output_message_send_short(global.midi_output, 137, 38, 0);//Sends the MIDI Message to the MIDI Output Device
				show_debug_message("Note off " + string(Event_num) + textstring);		
			case 999: //End of 
				show_debug_message("End " + string(Event_num) + textstring);
		break;
		}
		//Set up next event
		global.Midi_event_number++;
		if(global.Midi_event_number>12) {global.Midi_event_number=0;}
		global.Midi_next_event_deltatime = global.metronome_events[global.Midi_event_number].deltatime;
		time_source_reconfigure(global.metro_processor,(global.Midi_next_event_deltatime), time_source_units_seconds, method(self, Process_Events_3), [global.Midi_event_number, timesource], 1, time_source_expire_nearest);
		time_source_start(global.metro_processor);		
	}


//Create Tunetypes, template settings for a metronome. 
	//This is a function to create a structure so you can easily do it in an array.
	function Set_Metronome_to_Tunetype(tune_type)	{
	//update metronome settings
		global.metronome_tunetype=global.ID_metronome.tunetypes[tune_type].tunetype_name; 
		global.metronome_beatspermeasure=global.ID_metronome.tunetypes[tune_type].beatspermeasure;
		global.metronome_beatnote=global.ID_metronome.tunetypes[tune_type].beatnote;  //this is the note type per beat. 4=quarter, 8=eighth ...  
		global.metronome_eventsperbeat=global.ID_metronome.tunetypes[tune_type].eventsperbeat;   //this is how many clicks etc happen per beat. 1+.  Allows subdividing in different patterns.
		global.metronome_bpm=global.ID_metronome.tunetypes[tune_type].beatsperminute;  //beats per minute ... varies by tune
	}

//Create a tune file, midi event log, etc. 
	//This is a struct which will be in an array but should be moved to a multidimensional array perhaps. 
	function create_midi_eventfile(deltatime, basetime, midi_event_type, midi_event_channel, midi_byte1, midi_event_value, midi_event_note, midi_event_velocity) {
	    return {
	        deltatime: deltatime,
			basetime: basetime, 
			midi_event_type: midi_event_type,
			midi_event_channel: midi_event_channel,
			midi_byte1: midi_byte1,
	        midi_event_value: midi_event_value,
			midi_event_note: midi_event_note,
			midi_event_velocity: midi_event_velocity,
	    };
	}

//Metronome settings for types of tunes
	//this function creates a struct, which will live in an array.
	function create_metronome_tunetype(tunetype_name, beatspermeasure, beatnote, eventsperbeat, beatsperminute) {
	    return {
	        tunetype_name: tunetype_name, 
			beatspermeasure: beatspermeasure,
	        beatnote: beatnote,
			eventsperbeat: eventsperbeat,
			beatsperminute: beatsperminute,
	    };
	}

//Update an array based on the selected bpm.
	function update_timing(tune_events,base_bpm,target_bpm) {
		//This is a WIP
		//need a tune struct that has core info as well as an array. basebpm is core info...
		var _num_events = array_length(tune_events);
		for( var i=0; i<_num_events; i++)	{ 
			tune_events[@i].deltatime = (tune_events[@i].basetime * (base_bpm/target_bpm));
		}
	}	


//
//
//
//
//
//


//Metronome settings for types of tunes
//midi log macros
	#macro MIDI_log_ ... 
	#macro MIDI_log_time 0
	#macro MIDI_log_source 1
	#macro MIDI_log_type 2
	#macro MIDI_log_note 3
	#macro MIDI_log_note_off 4
	#macro MIDI_log_velocity 5
	#macro MIDI_log_measure 6
	#macro MIDI_log_beat 7
	#macro MIDI_log_length 8	

function Count_beat(){
// Beat one (or beats matching an emphasize beats setting)
	var _metronome_start_time = global.metronome_start_time;
	var _metronome_time_since_start = 0;
	global.metronome_current_beat++;
	if (global.metronome_current_beat > global.metronome_beatspermeasure) { 
		global.metronome_current_beat = 1;
	}	
//	show_debug_message("current beat = "+ string(global.metronome_current_beat));
	show_debug_message("current beat = "+ string(global.metronome_game_time) + ":  " + string(global.metronome_current_beat));

//	text=global.metronome_current_beat;
//	textstring=(string(global.metronome_game_time) + ":  " + string(global.metronome_current_beat));
	global.beat_updated=true;
}


//	global.metronome_time = time_source_create(time_source_game, (60/global.metronome_bpm), time_source_units_seconds,Count_beat, [], -1, time_source_expire_after);
function Count_beat_alt(_time_source){
// Beat one (or beats matching an emphasize beats setting)

	var _metronome_start_time = global.metronome_start_time;
	var _metronome_time_since_start = 0;
	global.metronome_current_beat++;
	if (global.metronome_current_beat > global.metronome_beatspermeasure) { 
		global.metronome_current_beat = 1;
	}	
//	show_debug_message("current beat = "+ string(global.metronome_current_beat));
	show_debug_message("current beat = "+ string(global.metronome_game_time) + ":  " + string(global.metronome_current_beat));
	_time_source = time_source_create(time_source_game, (60/global.metronome_bpm), time_source_units_seconds,Count_beat_alt(global.metronome_time), [], 1, time_source_expire_after);
//	text=global.metronome_current_beat;
//	textstring=(string(global.metronome_game_time) + ":  " + string(global.metronome_current_beat));
	global.beat_updated=true;
}


