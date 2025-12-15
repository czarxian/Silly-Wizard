

/// @desc Processes scheduled tune events and resets timesource for next batch
function script_tune_callback() {
	var event_time = tune_events[current_index].time;
	
	// Process all events at this timestamp
	while (current_index < array_length(tune_events)
	    && tune_events[current_index].time == event_time) {
	    
	    var ev = tune_events[current_index];
	    
	    // MIDI playback only for now
	    if (ev.type == ev_midi) {
	        var status = NoteOnEvent + ev.channel;
	        midi_output_message_send_short(global.midi_output, status, ev.note, ev.velocity);
	    }
	
	    current_index++;
	}
	
	// Schedule next batch
	if (global.current_index < array_length(global.tune_events)) {
    var next_time = global.tune_events[global.current_index].time;
    var delta = next_time - current_time; // using system clock approach

    // Recreate/reset the timesource with the new period
    global.tune_timer = time_source_create(
        time_source_game,
        delta / 1000,                // convert ms to seconds
        time_source_units_seconds,
        script_tune_callback,
        [],
        1,
        time_source_expire_after
    );
}
	
	
	
	
	
}


//function script_tune_callback() {
//	//Track 
//    //var actual_time = get_timer()/1000; //in microseconds
//    var actual_time = current_time - global.tune_start_time; //in milliseconds
//	show_debug_message("Event " + string(global.tune_index) + " fired.");
//	show_debug_message("Actual Time: " + string(actual_time) + " ms.");
//	show_debug_message(string(current_time - global.tune_start_time));
//	// Handle the fired event
//	
//	//Write to the event log
//		//Future function
//	
//	//Play MIDI note
//		//Future function
//    
//	//Write to the beam drawing array
//		//Future function
//	
//	// Advance
//    global.tune_index++;
//
//    // If more events, reconfigure and restart
//    if (global.tune_index < array_length(global.tune_events)) {
//        var next_ms   = global.tune_events[global.tune_index];
//        var next_secs = next_ms / 1000.0;
//
//        time_source_reconfigure(
//            global.tune_timer,
//            next_secs,
//            time_source_units_seconds,
//            script_tune_callback,
//            [],
//            1,
//            time_source_expire_after
//        );
//        time_source_start(global.tune_timer);
//
//	//Else end the tune	
//    } else {
//        // Optional: stop or leave as-is
//        time_source_stop(global.tune_timer);
//        show_debug_message("Tune finished.");
//    }
//}



