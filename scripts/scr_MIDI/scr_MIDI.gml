// scr_MIDI — MIDI device & message utilities
// Purpose: Low-level MIDI I/O, device scanning/opening and input processing used by playback and player input.
// Key responsibilities:
//  - Device scanning/opening (MIDI_scan_input_devices, MIDI_scan_output_devices)
//  - Process incoming MIDI (MIDI_process_messages) and send messages for playback (midi_output_message_send_short)
//  - Helper functions (MIDI_send_off, MIDI_check_errors)
// Related scripts/objects: scr_tune_scripts (playback), obj_player (input)

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

			// Timing diagnostics (off by default). Enable with: global.MIDI_TIMING_DIAG_ENABLED = true;
			if (!variable_global_exists("MIDI_TIMING_DIAG_ENABLED")) global.MIDI_TIMING_DIAG_ENABLED = false;
			if (!variable_global_exists("MIDI_TIMING_DIAG_LOG_INTERVAL_MS")) global.MIDI_TIMING_DIAG_LOG_INTERVAL_MS = 1000;
			global.midi_input_clock_offset_ms = undefined;
			global.midi_timing_delay_buf = array_create(128, 0);
			global.midi_timing_skew_buf = array_create(128, 0);
			global.midi_timing_delay_head = 0;
			global.midi_timing_delay_count = 0;
			global.midi_timing_diag_last_log_ms = timing_get_engine_now_ms();
			global.midi_timing_diag_zero_count = 0;
			global.midi_timing_diag_negative_raw_count = 0;
			global.midi_timing_diag_source_midi_count = 0;
			global.midi_timing_diag_source_wall_count = 0;
	
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

function MIDI_timing_diag_record_poll_delay(_delay_ms, _raw_skew_ms = 0, _clock_source = "") {
	if (!variable_global_exists("MIDI_TIMING_DIAG_ENABLED") || !global.MIDI_TIMING_DIAG_ENABLED) return;
	if (!variable_global_exists("midi_timing_delay_buf") || !is_array(global.midi_timing_delay_buf)) return;
	if (!variable_global_exists("midi_timing_skew_buf") || !is_array(global.midi_timing_skew_buf)) return;

	var buf = global.midi_timing_delay_buf;
	var skew_buf = global.midi_timing_skew_buf;
	var n_buf = array_length(buf);
	if (n_buf <= 0) return;

	var head = floor(real(global.midi_timing_delay_head ?? 0));
	head = ((head mod n_buf) + n_buf) mod n_buf;
	var delay_ms = max(0, real(_delay_ms));
	var raw_skew_ms = real(_raw_skew_ms);
	buf[head] = delay_ms;
	skew_buf[head] = raw_skew_ms;
	if (delay_ms <= 0.0001) global.midi_timing_diag_zero_count += 1;
	if (raw_skew_ms < 0) global.midi_timing_diag_negative_raw_count += 1;
	if (string(_clock_source) == "midi_input_message_time") global.midi_timing_diag_source_midi_count += 1;
	else global.midi_timing_diag_source_wall_count += 1;

	global.midi_timing_delay_buf = buf;
	global.midi_timing_skew_buf = skew_buf;
	global.midi_timing_delay_head = (head + 1) mod n_buf;
	global.midi_timing_delay_count = min(n_buf, floor(real(global.midi_timing_delay_count ?? 0)) + 1);

	var now_ms = timing_get_engine_now_ms();
	var interval_ms = max(250, real(global.MIDI_TIMING_DIAG_LOG_INTERVAL_MS ?? 1000));
	if ((now_ms - real(global.midi_timing_diag_last_log_ms ?? 0)) < interval_ms) return;

	var count = floor(real(global.midi_timing_delay_count ?? 0));
	if (count < 8) return;

	var vals = array_create(count, 0);
	var skew_vals = array_create(count, 0);
	for (var i = 0; i < count; i++) {
		vals[i] = real(buf[i]);
		skew_vals[i] = real(skew_buf[i]);
	}
	array_sort(vals, function(a, b) { return real(a) - real(b); });
	array_sort(skew_vals, function(a, b) { return real(a) - real(b); });

	var i50 = floor((count - 1) * 0.50);
	var i95 = floor((count - 1) * 0.95);
	var i99 = floor((count - 1) * 0.99);
	var p50 = vals[i50];
	var p95 = vals[i95];
	var p99 = vals[i99];
	var s50 = skew_vals[i50];
	var s95 = skew_vals[i95];
	var s99 = skew_vals[i99];
	var zero_pct = (real(global.midi_timing_diag_zero_count ?? 0) * 100.0) / max(1, count);
	var neg_pct = (real(global.midi_timing_diag_negative_raw_count ?? 0) * 100.0) / max(1, count);
	var src_midi = floor(real(global.midi_timing_diag_source_midi_count ?? 0));
	var src_wall = floor(real(global.midi_timing_diag_source_wall_count ?? 0));

	show_debug_message("[MIDI_TIMING] poll_delay_ms p50=" + string_format(p50, 0, 3)
		+ " p95=" + string_format(p95, 0, 3)
		+ " p99=" + string_format(p99, 0, 3)
		+ " | raw_skew_ms p50=" + string_format(s50, 0, 3)
		+ " p95=" + string_format(s95, 0, 3)
		+ " p99=" + string_format(s99, 0, 3)
		+ " | zero%=" + string_format(zero_pct, 0, 1)
		+ " neg%=" + string_format(neg_pct, 0, 1)
		+ " src[midi/wall]=" + string(src_midi) + "/" + string(src_wall)
		+ " n=" + string(count));

	global.midi_timing_diag_zero_count = 0;
	global.midi_timing_diag_negative_raw_count = 0;
	global.midi_timing_diag_source_midi_count = 0;
	global.midi_timing_diag_source_wall_count = 0;
	global.midi_timing_diag_last_log_ms = now_ms;
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
		messages = midi_input_message_count(global.midi_input_device);
		_last_MIDI_on_event = 0;
		_MIDI_input_device = global.midi_input_device;
		_MIDI_output_device = global.midi_output_device;
		_chanter_channel = global.chanter_channel;
		// Prefer MIDI device message timestamp when available; fallback to realtime.
		
//		```
			for (m = 0; m < messages; m++)	{
				////Composes the MIDI Input Message...
				bytes = midi_input_message_size(_MIDI_input_device,m);
		
//		```
		
		var wall_now = timing_get_engine_now_ms();
		var raw_abs_time = wall_now;
		var clock_source = "current_time";
		var msg_time = midi_input_message_time(_MIDI_input_device, m);
		if (!is_undefined(msg_time)) {
			var msg_time_real = real(msg_time);
			if (msg_time_real >= 0) {
				if (!variable_global_exists("midi_input_clock_offset_ms") || is_undefined(global.midi_input_clock_offset_ms)) {
					global.midi_input_clock_offset_ms = wall_now - msg_time_real;
				}

				raw_abs_time = msg_time_real + real(global.midi_input_clock_offset_ms);
				// Re-anchor if clock offset becomes clearly invalid.
				if (abs(raw_abs_time - wall_now) > 10000) {
					global.midi_input_clock_offset_ms = wall_now - msg_time_real;
					raw_abs_time = msg_time_real + real(global.midi_input_clock_offset_ms);
				}
				clock_source = "midi_input_message_time";
			}
		}

		time = raw_abs_time;
		var raw_poll_skew_ms = wall_now - raw_abs_time;
		var processing_delay_ms = max(0, raw_poll_skew_ms);
		MIDI_timing_diag_record_poll_delay(processing_delay_ms, raw_poll_skew_ms, clock_source);
		
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
		var log_channel = (byte1 >= 128) ? (byte1 & 15) : 0;
		var normalized_time = time;
		if (variable_global_exists("tune_start_real") && global.tune_start_real != undefined) {
			normalized_time = time - global.tune_start_real;
		}
		var status_type = byte1 & 240;  // Clear channel bits
		var raw_note_midi = byte2;
		var normalized_note_midi = raw_note_midi;
		var canonical_note = "";
		var is_note_message = (status_type == 144 || status_type == 128);
		if (is_note_message) {
			canonical_note = chanter_midi_to_canonical(raw_note_midi, global.MIDI_chanter ?? "default", log_channel);
			if (string_length(canonical_note) > 0) {
				var mapped_note = chanter_canonical_to_midi(canonical_note, global.MIDI_chanter ?? "default");
				if (!is_undefined(mapped_note)) {
					normalized_note_midi = mapped_note;
				}
			}
		}

		if (status_type == 144 && byte3 > 0) {
			gv_on_player_note_on(normalized_note_midi, log_channel, normalized_time, byte3, canonical_note);
		} else if (status_type == 128 || (status_type == 144 && byte3 <= 0)) {
			gv_on_player_note_off(normalized_note_midi, log_channel, normalized_time, canonical_note);
		}

		var use_current_note_panel = (!variable_global_exists("enable_current_note_layer") || global.enable_current_note_layer);
		if (use_current_note_panel) {
			if (status_type == 144 && byte3 > 0) {
				cn_panel_on_player_note_on(normalized_note_midi, log_channel, normalized_time);
			} else if (status_type == 128 || (status_type == 144 && byte3 <= 0)) {
				cn_panel_on_player_note_off(normalized_note_midi, log_channel, normalized_time);
			}
		}

		if (variable_global_exists("EVENT_HISTORY_ENABLED") && global.EVENT_HISTORY_ENABLED) {
			// Determine event type from MIDI status byte
			var ev_type = "unknown";
			if (status_type == 144) {  // Note On
				ev_type = (byte3 > 0) ? "note_on" : "note_off";  // Velocity-zero = note off
			} else if (status_type == 128) {  // Note Off
				ev_type = "note_off";
			}
			// Raw log for player MIDI input (minimal fields)
			event_history_add({
				timestamp_ms: normalized_time,
				raw_timestamp_ms: raw_abs_time,
				normalized_time_ms: normalized_time,
				processing_delay_ms: processing_delay_ms,
				clock_source: clock_source,
				expected_time_ms: 0,
				actual_time_ms: normalized_time,
				delta_ms: 0,
				event_type: ev_type,
				source: "player",
				note_midi: normalized_note_midi,
				note_midi_raw: raw_note_midi,
				note_canonical: canonical_note,
				velocity: byte3,
				channel: log_channel,
				tune_name: variable_global_exists("current_tune_name") ? global.current_tune_name : "unknown",
				event_id: 0,
				marker_type: "",
				measure: 0,
				beat: 0,
				beat_fraction: 0
			});
		}
		var out_status = byte1;
		if (byte1 < 240) {
			// Force output to channel 0 for channel voice messages.
			out_status = (byte1 & 240);
		}
		var out_data1 = byte2;
		if (is_note_message) {
			out_data1 = normalized_note_midi;
		}
		midi_output_message_send_short(_MIDI_output_device, out_status, out_data1, byte3);  //Sends the MIDI Message to the MIDI Output Device
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
	// Send note-off to all notes on all channels on the main output device
	if (!variable_global_exists("midi_output_device")) {
		show_debug_message("MIDI output device not initialized");
		return;
	}
	
	var channel, note;
	for (channel = 0; channel < 16; channel++) {
		var status_byte = 128 + channel; // Note-off (128) + channel
		for (note = 0; note < 128; note++) {
			midi_output_message_send_short(global.midi_output_device, status_byte, note, 0);
		}
	}
	show_debug_message("✓ All notes stopped on all channels");
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
	global.midi_input_devices = [];
	var device_count = midi_input_device_count();
	for (var i = 0; i < device_count; i++) {
		global.midi_input_devices[i] = midi_input_device_name(i);
	}
}

function MIDI_scan_output_devices() {
	global.midi_output_devices = [];
	var device_count = midi_output_device_count();
	for (var i = 0; i < device_count; i++) {
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