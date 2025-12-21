

/// @function tune_start(tune_events)
/// @param tune_events  The array of events to play

function tune_start(_tune_events) {
    global.tune_events = _tune_events;
    global.tune_index  = 0;

    // First event delay is simply its timestamp
    var delta_ms = global.tune_events[0].time;
	show_debug_message("delta_ms " + string(delta_ms)); //For testing only
    global.tune_timer = time_source_create(
        time_source_game,
        delta_ms / 1000,
		time_source_units_seconds,
        script_tune_callback,
        [],
        1,
        time_source_expire_after
    );
	time_source_start(global.tune_timer);
    global.tune_start_real = current_time;
}

function script_tune_callback() {

    var ev = global.tune_events[global.tune_index];

    // Debugging: compare real time vs expected tune time
    var real_elapsed = current_time - global.tune_start_real;
    var expected_elapsed = ev.time;
    show_debug_message("Event " + string(global.tune_index)
        + " expected=" + string(expected_elapsed)
        + " real=" + string(real_elapsed));

    // PLAY EVENT
    if (ev.type == ev_midi) {
        var status = NoteOnEvent + ev.channel;
        midi_output_message_send_short(global.midi_output_device, status, ev.note, ev.velocity);
    }

	//Write to the beam drawing array
		//Future function

	//Write to the EVENT LOG
		//Future function
	
	//Write to the Current_Note window
	obj_currentnote_field_1.field_contents = string(global.tune_events[global.tune_index].note);

    // Advance index
    global.tune_index++;

    // If no more events, stop
    if (global.tune_index >= array_length(global.tune_events)) {
        time_source_stop(global.tune_timer);
        show_debug_message("Tune finished.");
        return;
    }

    // Compute RELATIVE delta
    var next_time  = global.tune_events[global.tune_index].time;
    var prev_time  = ev.time;
    var delta_ms   = next_time - prev_time;

    time_source_reconfigure(
        global.tune_timer,
        delta_ms / 1000,
        time_source_units_seconds,
        script_tune_callback,
        [],
        1,
        time_source_expire_after
    );

    time_source_start(global.tune_timer);
}

//////Metronome//////
function tune_generate_metronome(_tune)
{
    if (!is_undefined(_tune.metronome) && !_tune.metronome.enabled) {
        return [];
    }

    if (is_undefined(_tune.metronome)) {
        return [];
    }

    var settings = _tune.metronome;
    var events = [];

    var bpm          = settings.bpm;
    var beats_per_bar = settings.beats_per_bar;
    var ms_per_beat  = 60000 / bpm; // ms, not seconds

    var bar_pattern = tune_metronome_build_pattern(ms_per_beat, settings.subdivision);
    var tune_length = tune_get_total_ms(_tune);

    var t = 0;
    while (t < tune_length)
    {
        for (var i = 0; i < array_length(bar_pattern); i++)
        {
            var p = bar_pattern[i];
            var click_time = t + p.time;

            var note = p.accent ? settings.accent_note : settings.normal_note;

            array_push(events, {
                time:     click_time,
                type:     ev_midi,
                channel:  settings.channel,
                note:     note,
                velocity: settings.velocity
            });
        }

        t += beats_per_bar * ms_per_beat;
    }

    return events;
}


function tune_metronome_build_pattern(_mpb, _subdivision)
{
    var pattern = [];

    switch (_subdivision)
    {
        case "quarter":
            array_push(pattern, { time: 0, accent: true });
            break;

        case "eighth":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.5, accent: false });
            break;

        case "dotcut":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.666, accent: false });
            break;

        case "cutdot":
            array_push(pattern, { time: 0, accent: true });
            array_push(pattern, { time: _mpb * 0.333, accent: false });
            break;

        default:
            array_push(pattern, { time: 0, accent: true });
            break;
    }

    return pattern;
}


function tune_get_total_ms(_tune)
{
    var events = _tune.events;
    var last_time = 0;

    for (var i = 0; i < array_length(events); i++)
    {
        if (events[i].time > last_time)
            last_time = events[i].time;
    }

    return last_time;
}


function tune_build_events(_tune)
{
    // Base events (manual)
    var base = _tune.events;
    var met  = tune_generate_metronome(_tune);

    // Merge arrays
    var total = array_length(base) + array_length(met);
    var merged = array_create(total);

    var i = 0;
    for (var j = 0; j < array_length(base); j++) {
        merged[i++] = base[j];
    }
    for (var j = 0; j < array_length(met); j++) {
        merged[i++] = met[j];
    }

    // Sort by time
    array_sort(merged, function(a, b) { return a.time - b.time; });

    return merged;
}