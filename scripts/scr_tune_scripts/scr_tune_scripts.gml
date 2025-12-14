

function script_tune_callback() {
	//Track 
    //var actual_time = get_timer()/1000; //in microseconds
    var actual_time = current_time - global.tune_start_time; //in milliseconds
	show_debug_message("Event " + string(global.tune_index) + " fired.");
	show_debug_message("Actual Time: " + string(actual_time) + " ms.");
	show_debug_message(string(current_time - global.tune_start_time));
	// Handle the fired event
	
	//Write to the event log
		//Future function
	
	//Play MIDI note
		//Future function
    
	//Write to the beam drawing array
		//Future function
	
	// Advance
    global.tune_index++;

    // If more events, reconfigure and restart
    if (global.tune_index < array_length(global.tune_events)) {
        var next_ms   = global.tune_events[global.tune_index];
        var next_secs = next_ms / 1000.0;

        time_source_reconfigure(
            global.tune_timer,
            next_secs,
            time_source_units_seconds,
            script_tune_callback,
            [],
            1,
            time_source_expire_after
        );
        time_source_start(global.tune_timer);

	//Else end the tune	
    } else {
        // Optional: stop or leave as-is
        time_source_stop(global.tune_timer);
        show_debug_message("Tune finished.");
    }
}



