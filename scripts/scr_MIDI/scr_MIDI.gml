// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

//Macro
//#macro <variable> <expression>;

//Need to re do these to account for broader note range etc.
	#macro NoteOnEvent 144 //midi on event for channel 0
	#macro NoteOffEvent 128 //midi off event for channel 0
	
	#macro NOTE_a 15
	#macro NOTE_g 13
	#macro NOTE_fshp 12
	#macro NOTE_f 11
	#macro NOTE_e 10
	#macro NOTE_d 8
	#macro NOTE_cshp 7
	#macro NOTE_c 6
	#macro NOTE_B 5
	#macro NOTE_A 3
	#macro NOTE_G 1		//set a value for low G,
	
	#macro MidiLowNoteOffset 55
	#macro NoteXOffset 100
	#macro default_velocity 100
	#macro DRUM_Base 41
	
	global.Midi_Note_Values[0]="F#";
	global.Midi_Note_Values[1]="G";
	global.Midi_Note_Values[2]="G#";
	global.Midi_Note_Values[3]="A";
	global.Midi_Note_Values[4]="A#";
	global.Midi_Note_Values[5]="B";
	global.Midi_Note_Values[6]="c";
	global.Midi_Note_Values[7]="c#";
	global.Midi_Note_Values[8]="d";
	global.Midi_Note_Values[9]="d#";
	global.Midi_Note_Values[10]="e";
	global.Midi_Note_Values[11]="f";
	global.Midi_Note_Values[12]="f#";
	global.Midi_Note_Values[13]="g";
	global.Midi_Note_Values[14]="g#";
	global.Midi_Note_Values[15]="a";
	


//Start manual checking
	function MIDI_start_manual_check_messages()
	{
		midi_input_message_manual_checking(1);//Enables manual checking of MIDI Messages
		midi_error_manual_checking(1);//Enables manual checking of MIDI errors
		show_debug_message("starting to check MIDI input");
	
	//```
		//Play an initial E using the construct method... otherwise it doesnt seem to work for some reason
		midi_output_message_clear();//Clears the MIDI Message buffer
		midi_output_message_byte(144);//Adds one byte to the MIDI Message buffer
		midi_output_message_byte(65);//Adds one byte to the MIDI Message buffer
		midi_output_message_byte(110);//Adds one byte to the MIDI Message buffer
		midi_output_message_send(0);//Sends the MIDI Message to the MIDI Output Device
		show_debug_message("playing initial E to prime buffer");
	
		midi_output_message_clear();//Clears the MIDI Message buffer
		midi_output_message_byte(128);//Adds one byte to the MIDI Message buffer
		midi_output_message_byte(65);//Adds one byte to the MIDI Message buffer
		midi_output_message_byte(0);//Adds one byte to the MIDI Message buffer
		midi_output_message_send(0);//Sends the MIDI Message to the MIDI Output Device
		show_debug_message("stop playing initial E");
	}

//```

function MIDI_process_messages()
	{
		////Loops through each MIDI Input Message…
		var messages, bytes, byte, byte1, byte2, byte3, byte2note, m, b, time, _MIDI_input_device, _MIDI_output_device, _MIDI_event_number, _last_MIDI_on_event, _chanter_channel;
		byte1=0;
		byte2=0;
		byte3=0;
		byte2note=0;
		messages = midi_input_message_count(global.midi_input);
		_last_MIDI_on_event = 0;
		_MIDI_input_device = global.midi_input;
		_MIDI_output_device = global.midi_output;
		_chanter_channel = global.chanter_channel;
		var _metronome_start_time = global.metronome_start_time;
		var _metronome_pause_delta = global.metronome_pause_delta;
		
//		```
			for (m = 0; m < messages; m++)	{
				////Composes the MIDI Input Message...
				bytes = midi_input_message_size(_MIDI_input_device,m);
		
//		```
		
		//			time = midi_input_message_time(_MIDI_input_device, m);   //This uses MIDI time. Probably should be logged somewhere.
		time = current_time - (_metronome_start_time + _metronome_pause_delta);   //This uses song time. Matches metronome.
		
//		```
		_MIDI_event_number = global.Midi_event_number;
		_last_MIDI_on_event = global.Midi_last_event_number;

		for(b = 0; b < bytes; b++)	{
			byte = midi_input_message_byte(_MIDI_input_device,m,b);
			if (b==0) {byte1 = midi_input_message_byte(_MIDI_input_device,m,b);
			}
			else if (b==1) {
				byte2 = midi_input_message_byte(_MIDI_input_device,m,b);
				byte2note = (byte2 - MidiLowNoteOffset);
			}
			else if (b==2) { byte3 = midi_input_message_byte(_MIDI_input_device,m,b);
			}
		}

	//	if (byte1>=NoteOnEvent && byte1<=(NoteOnEvent+15)) {
	//		//write note to MIDI log if it is a note event
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_time]=time;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_source]="player";
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_type]=byte1;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_note]=byte2note;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_velocity]=byte3;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_measure]=global.metronome_current_measure;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_beat]=global.metronome_current_beat;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_length]=0;
	//		global.MIDI_log[_MIDI_event_number][MIDI_log_note_off]=0;
	//		global.Midi_last_event_number=_MIDI_event_number;
	//		global.Midi_event_number++;
	//
	//		show_debug_message( string(global.MIDI_log[_MIDI_event_number][MIDI_log_time]) + " - gametime: " + string(global.metronome_curent_time));
	//		//write to notebeam drawing table.
	//		//should add an if statement so note beams is optional.
	//		array_push(global.ID_note_beams.draw_array, _MIDI_event_number);
	//	}
	//
	//	else if (byte1>=NoteOffEvent && byte1<NoteOnEvent) {
	//		global.MIDI_log[_last_MIDI_on_event][MIDI_log_note_off] = time;
	//		global.MIDI_log[_last_MIDI_on_event][MIDI_log_length] = global.MIDI_log[_last_MIDI_on_event][MIDI_log_note_off]-global.MIDI_log[_last_MIDI_on_event][MIDI_log_time];

//```

//		//		show_debug_message( string(global.MIDI_log[_last_MIDI_on_event][MIDI_log_note_off]));
//	}

//```
		//  Having parsed the input, do something with it!
		midi_output_message_send_short(_MIDI_output_device,byte1,byte2,byte3);  //Sends the MIDI Message to the MIDI Output Device

//```

//			show_debug_message("Send to" + string(_MIDI_output_device) + "Note: " + string(byte2note) );
//			show_debug_message(string(time) + "  " + string(byte1) + "  " + string(byte2) + "  " + string(byte3));
//			global.MIDI_log[_MIDI_event_number][MIDI_log_time]=time;
//			global.MIDI_log[_MIDI_event_number][MIDI_log_source]="pipes";
//			global.MIDI_log[_MIDI_event_number][MIDI_log_type]=byte1;			
//			global.MIDI_log[_MIDI_event_number][MIDI_log_note]=byte2;
//			global.MIDI_log[_MIDI_event_number][MIDI_log_note_off]= ;
//			global.MIDI_log[_MIDI_event_number][MIDI_log_velocity]=byte3;
//			show_debug_message("time: " + string(MIDI_log[_MIDI_event_number][MIDI_log_time])+"type: " + string(MIDI_log[_MIDI_event_number][MIDI_log_type])+"note: " + string(MIDI_log[_MIDI_event_number][MIDI_log_note]) );
	}
}

function MIDI_send_off() 	{
	var n;
	for(n=50; n<99; n++)  {   //Send end message to all notes in case one is playing
		midi_output_message_send_short(1,128,n,0);
	}
	show_debug_message("stop playing all notes");
}

//Check MIDI errors on each step
function MIDI_check_errors() 	{
	var errors, e;
	errors = midi_error_count();
	for(e=0; e<errors; e++)		{
		show_debug_message(midi_error_string(e));
	}
}

//Stop checking MIDI messages
function MIDI_stop_checking_messages_and_errors()  {
	midi_input_message_manual_checking(0);//Disables manual checking of MIDI Messages
	midi_error_manual_checking(0);//Disables manual checking of MIDI errors
	midi_input_device_close_all();
	midi_output_device_close_all();
}

//Find Blair Chanter device number
//****This should be changed to allow any input to be selected via a menu system
//function MIDI_set_global_chanternumber()
//	{
//		var devices, d, str;
//		devices = midi_input_device_count();
//		global.chantername = "Blair Pipe MIDI"; //Name of target chanter, hard coded to Blair
//		global.chanternumber = 0; //Sets defualt chanter number to first input device
//		str="";
//		//Loops through each MIDI Input Device to find the blair…
//		for(d = 0; d < devices; d++)  {
//			if (midi_input_device_name(d) = global.chantername)  {
//				global.chanternumber = d;
//			}
//		}
//		show_debug_message(global.chantername + " set to: " + string(global.chanternumber));	
//	}

function MIDI_show_input_devices() {
	    var str, i;
		str = "MIDI INPUT DEVICES\n\n";
		for(i=0; i<midi_input_device_count(); i++)  {
			str += midi_input_device_name(i)+"\n";
		}
		show_message(str);
}

function MIDI_scan_input_devices() {
	for(i=0; i<midi_input_device_count(); i++)  {
		global.midi_input_devices[i] = midi_input_device_name(i);
	}
}

function MIDI_scan_output_devices() {
	for(i=0; i<midi_output_device_count(); i++)  {
		global.midi_output_devices[i] = midi_output_device_name(i);
	}
}
	
function MIDI_show_output_devices() {
	str = "MIDI OUTPUT DEVICES\n\n";
	for(i=0; i<midi_output_device_count(); i++)  {
		str += midi_output_device_name(i)+"\n";
	}
	show_message(str);
}