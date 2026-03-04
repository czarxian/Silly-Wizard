
// scr_tune_scripts — Playback & event preprocessing
// Purpose: Build runtime event lists (merge tune + metronome), start playback and provide the time-source callback that sends MIDI.
// Key functions: tune_build_events, tune_generate_metronome, tune_start, script_tune_callback

/// @function create_set_item(_tune_filename)
/// @description Create a new set item with default settings
/// @param _tune_filename The tune file path
/// @returns Set item struct

function create_set_item(_tune_filename) {
    return {
        tune_filename: _tune_filename,
        bpm: undefined,  // undefined = use tune metadata
        metronome_mode: global.metronome_mode ?? 2,
        metronome_pattern: global.metronome_pattern_selection,
        metronome_volume: global.metronome_volume ?? 100,
        count_in_measures: 1,
        include_drum_roll: false,
        drum_roll_variant: undefined
    };
}

/// @function midi_to_letter(_midi_note)
/// @description Convert MIDI note number to bagpipe letter notation
/// @param _midi_note The MIDI note number
/// @returns String letter notation

function midi_to_letter(_midi_note, _channel = -1) {
    // Handle percussion/drums on channel 9 (MIDI channel 10)
    if (_channel == 9) {
        // Return descriptive percussion names for common drum MIDI notes
        switch (_midi_note) {
            case 35: return "kick";
            case 36: return "kick";
            case 38: return "snare";
            case 40: return "snare";
            case 42: return "hi-hat";
            case 44: return "hi-hat";
            case 46: return "hi-hat";
            case 49: return "crash";
            case 51: return "ride";
            default: return "drum" + string(_midi_note);
        }
    }
    
    // Initialize global note map once (cached per chanter selection)
    var chanter = string(global.MIDI_chanter ?? "default");
    if (!variable_global_exists("NOTE_MAP") || global.NOTE_MAP_CHANTER != chanter) {
        var note_map = tune_get_note_map(chanter);
        global.NOTE_MAP = tune_build_midi_to_letter_map(note_map);
        global.NOTE_MAP_CHANTER = chanter;
    }
    return global.NOTE_MAP[$ string(_midi_note)] ?? "?";
}

/// @function tune_group_events_by_timestamp(_events)
/// @description Group events by timestamp to batch simultaneous events
/// @param _events Array of event structs with .time property
/// @returns Array of timestamp groups: [{time: ms, events: [...]}, ...]

function tune_group_events_by_timestamp(_events) {
    var groups = [];
    var current_timestamp = -1;
    var current_group = undefined;
    
    // Events are already sorted by time from preprocessing
    for (var i = 0; i < array_length(_events); i++) {
        var ev = _events[i];
        
        if (ev.time != current_timestamp) {
            // New timestamp - start new group
            current_timestamp = ev.time;
            current_group = {
                time: current_timestamp,
                events: []
            };
            array_push(groups, current_group);
        }
        
        // Add event to current group
        array_push(current_group.events, ev);
    }
    
    show_debug_message("✓ Batched " + string(array_length(_events)) + " events into " + string(array_length(groups)) + " timestamp groups");
    return groups;
}

/// @function tune_start(tune_events)
/// @param tune_events  The array of events to play

function tune_start(_tune_events) {
    cn_panel_prepare_tune_plan(_tune_events);

    // Group events by timestamp for batched processing
    global.tune_event_groups = tune_group_events_by_timestamp(_tune_events);
    global.tune_group_index = 0;
    
    // Cache tune filename for event logging (avoid repeated lookups)
    global.current_tune_name = obj_tune.tune_data.filename ?? "unknown";

    // Initialize event history before playback
    event_history_clear();
    
    // Initialize current note display
    global.current_note_display = "";

    // First group delay is simply its timestamp
    var delta_ms = global.tune_event_groups[0].time;
	show_debug_message("delta_ms " + string(delta_ms)); //For testing only
    global.tune_timer = time_source_create(
        time_source_global,
        delta_ms / 1000,
		time_source_units_seconds,
        script_tune_callback_batched,
        [],
        1,
        time_source_expire_after
    );
	time_source_start(global.tune_timer);
    global.tune_start_real = current_time;
}

/// @function script_tune_callback_batched()
/// @description Batched callback that processes all events at the same timestamp

function script_tune_callback_batched() {
    var group = global.tune_event_groups[global.tune_group_index];
    var real_elapsed = current_time - global.tune_start_real;
    var expected_elapsed = group.time;

    var ordered_events = [];
    for (var oi = 0; oi < array_length(group.events); oi++) {
        var oev = group.events[oi];
        if (oev.type == "note_off") array_push(ordered_events, oev);
    }
    for (var oi = 0; oi < array_length(group.events); oi++) {
        var oev = group.events[oi];
        if (oev.type == "marker") array_push(ordered_events, oev);
    }
    for (var oi = 0; oi < array_length(group.events); oi++) {
        var oev = group.events[oi];
        if (oev.type == "note_on") array_push(ordered_events, oev);
    }
    
    // Temp: log first and last few groups to verify delta calculation
    if (global.tune_group_index < 3 || global.tune_group_index > array_length(global.tune_event_groups) - 3) {
        show_debug_message("Group " + string(global.tune_group_index) + " (" + string(array_length(group.events)) + " events): real=" + string(real_elapsed) + " expected=" + string(expected_elapsed) + " delta=" + string(real_elapsed - expected_elapsed));
    }
    
    // Process ALL events in this timestamp group
    var has_last_note_on = false;
    var last_note_on_note = 0;
    var last_note_on_channel = 0;
    for (var i = 0; i < array_length(ordered_events); i++) {
        var ev = ordered_events[i];
        
        // PLAY EVENT using Giavapps MIDI send_short
        if (ev.type == "note_on") {
            var status_byte = 144 + ev.channel;
            midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, ev.velocity);
            // Track for UI update (only if not metronome channel)
            if (ev.channel != global.METRONOME_CONFIG.channel) {
                has_last_note_on = true;
                last_note_on_note = ev.note;
                last_note_on_channel = ev.channel;
                cn_panel_on_tune_note_on(real(ev.measure ?? 0), ev.note, ev.channel, real(ev.time ?? expected_elapsed));
            }
        } 
        else if (ev.type == "note_off") {
            var status_byte = 128 + ev.channel;
            midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, 0);
            if (ev.channel != global.METRONOME_CONFIG.channel) {
                cn_panel_on_tune_note_off(real(ev.measure ?? 0), ev.note, ev.channel, real(ev.time ?? expected_elapsed));
            }
        }
        else if (ev.type == "marker") {
            // No MIDI output for marker entries.
            var marker_kind = string(ev.marker_type ?? "");
            if (marker_kind == "beat" || marker_kind == "countin_beat") {
                cn_panel_on_beat_marker(real(ev.measure ?? 0), real(ev.beat ?? 0), marker_kind == "countin_beat");
            }
        }
        
        // Log raw event data to history (enrichment will derive labels/structure later)
        var ev_type = ev.type;
        var marker_type = "";
        if (ev.type == "marker") {
            marker_type = struct_exists(ev, "marker_type") ? ev.marker_type : "";
            ev_type = "marker_" + string(marker_type);
        }
        var ev_note = struct_exists(ev, "note") ? ev.note : 0;
        var ev_velocity = struct_exists(ev, "velocity") ? ev.velocity : 0;
        var ev_channel = struct_exists(ev, "channel") ? ev.channel : 0;
        var ev_measure = struct_exists(ev, "measure") ? ev.measure : 0;
        var ev_beat = struct_exists(ev, "beat") ? ev.beat : 0;
        var ev_beat_fraction = struct_exists(ev, "beat_fraction") ? ev.beat_fraction : 0;
        if (ev_beat_fraction == 0 && struct_exists(ev, "division")) {
            ev_beat_fraction = ev.division;
        }
        
        // Raw log struct: minimal fields + timing + marker context
        var raw_log = {
            timestamp_ms: real_elapsed,
            expected_time_ms: expected_elapsed,
            actual_time_ms: real_elapsed,
            delta_ms: real_elapsed - expected_elapsed,
            event_type: ev_type,
            source: "game",
            note_midi: ev_note,
            velocity: ev_velocity,
            channel: ev_channel,
            tune_name: global.current_tune_name,
            event_id: struct_exists(ev, "event_id") ? ev.event_id : 0,
            marker_type: marker_type,
            measure: ev_measure,
            beat: ev_beat,
            beat_fraction: ev_beat_fraction
        };
        
        // Skip metronome MIDI events (channel 9 note_on/note_off) - keep structure markers
        var is_metronome_midi = (ev.type == "note_on" || ev.type == "note_off") 
                                && ev_channel == global.METRONOME_CONFIG.channel;
        
        if (!is_metronome_midi) {
            event_history_add(raw_log);
        }
    }
    
    // Update UI once per group (only for note_on events)
    if (has_last_note_on) {
        var note_letter = midi_to_letter(last_note_on_note, last_note_on_channel);
        var display_text = note_letter + " (delta: " + string(real_elapsed - expected_elapsed) + "ms)";
        global.current_note_display = display_text;
    }
    
    // Advance to next group
    global.tune_group_index++;
    
    // Check if done
    if (global.tune_group_index >= array_length(global.tune_event_groups)) {
        time_source_stop(global.tune_timer);
        if (global.EVENT_HISTORY_AUTO_EXPORT && !global.EVENT_HISTORY_EXPORTED) {
            export_event_history();
            global.EVENT_HISTORY_EXPORTED = true;
        }
        // Schedule cleanup one beat later (600ms at moderate tempo)
        schedule_tune_cleanup(600);
        // show_debug_message("Tune finished.");
        return;
    }
    
    // Schedule next group
    var next_time = global.tune_event_groups[global.tune_group_index].time;
    var prev_time = group.time;
    var delta_ms = next_time - prev_time;
    delta_ms = max(delta_ms, 0.001);  // Clamp to minimum time source period
    
    time_source_reconfigure(
        global.tune_timer,
        delta_ms / 1000,
        time_source_units_seconds,
        script_tune_callback_batched,
        [],
        1,
        time_source_expire_after
    );
    
    time_source_start(global.tune_timer);
}

// ============ OLD SINGLE-EVENT CALLBACK (PRESERVED FOR REFERENCE) ============

function script_tune_callback() {

    var ev = global.tune_events[global.tune_index];

    // Debugging: compare real time vs expected tune time
    var real_elapsed = current_time - global.tune_start_real;
    var expected_elapsed = ev.time;
    // show_debug_message("Event " + string(global.tune_index)
    //     + " expected=" + string(expected_elapsed)
    //     + " real=" + string(real_elapsed));
    
    // Temp: log first and last few events to verify delta calculation
    if (global.tune_index < 3 || global.tune_index > array_length(global.tune_events) - 3) {
        show_debug_message("Event " + string(global.tune_index) + ": real=" + string(real_elapsed) + " expected=" + string(expected_elapsed) + " delta=" + string(real_elapsed - expected_elapsed));
    }

    // PLAY EVENT using Giavapps MIDI send_short
    // Formula: Status Byte = Base Event Code + Channel
    // Note On: 144 + channel, Note Off: 128 + channel
    if (ev.type == "note_on") {
        var status_byte = 144 + ev.channel;
        midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, ev.velocity);
        // show_debug_message("Note ON: " + string(ev.note) + " velocity=" + string(ev.velocity) + " channel=" + string(ev.channel));
    } 
    else if (ev.type == "note_off") {
        var status_byte = 128 + ev.channel;
        midi_output_message_send_short(global.midi_output_device, status_byte, ev.note, 0);
        // show_debug_message("Note OFF: " + string(ev.note) + " channel=" + string(ev.channel));
    }

	//Write to the beam drawing array
		//Future function

	//Write to the EVENT LOG
	// Log event to history for analysis
var note_letter = "";
if (ev.type == "note_on") {
    // Convert MIDI note back to letter (for display/analysis)
    note_letter = midi_to_letter(ev.note, ev.channel);
}

// TEMPORARILY DISABLED FOR TIMING TEST
/*
event_history_add({
    timestamp_ms: real_elapsed,  // Actual elapsed time since tune start
    expected_time_ms: expected_elapsed,  // Expected elapsed time
    actual_time_ms: real_elapsed,  // Same as timestamp for game playback
    delta_ms: real_elapsed - expected_elapsed,  // Timing error (+ = late, - = early)
    
    measure: 0,  // Populated later when metronome added
    beat: 0,
    beat_fraction: 0,
    
    event_type: ev.type,
    source: "game",
    
    note_midi: ev.note ?? 0,
    note_letter: note_letter,
    velocity: ev.velocity ?? 0,
    channel: ev.channel ?? 0,
    
    tune_name: obj_tune.tune_data.filename ?? "unknown",
    event_id: 0,
    is_embellishment: false,
    embellishment_name: "",
    
    timing_quality: "on_time"  // Always perfect for game playback
});
*/
	
	//Write to the Current-Note window (only for non-metronome events)
	if (ev.type == "note_on" && ev.channel != global.METRONOME_CONFIG.channel) {
		var display_text = note_letter + " (delta: " + string(real_elapsed - expected_elapsed) + "ms)";
		global.current_note_display = display_text;
	}

    // Advance index
    global.tune_index++;

    // If no more events, stop
    if (global.tune_index >= array_length(global.tune_events)) {
        time_source_stop(global.tune_timer);
        // Schedule cleanup one beat later (600ms at moderate tempo)
        schedule_tune_cleanup(600);
        // show_debug_message("Tune finished.");
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

/// @function schedule_tune_cleanup(_delay_ms)
/// @description Schedule MIDI cleanup (stop all notes, stop input checking) after a delay
/// @param _delay_ms Delay in milliseconds before cleanup (typically one beat duration)

function schedule_tune_cleanup(_delay_ms) {
    var cleanup_timer = time_source_create(
        time_source_global,
        _delay_ms / 1000,
        time_source_units_seconds,
        tune_cleanup_after_finish,
        [],
        1,
        time_source_expire_after
    );
    time_source_start(cleanup_timer);
    show_debug_message("⏱ Scheduled tune cleanup in " + string(_delay_ms) + "ms");
}

/// @function tune_cleanup_after_finish()
/// @description Cleanup callback: stop all MIDI notes and disable MIDI input checking

function tune_cleanup_after_finish() {
    MIDI_send_off();  // Stop all notes on all channels
    MIDI_stop_checking_messages_and_errors();  // Stop MIDI input checking and close devices
    show_debug_message("✓ Tune cleanup complete");
}

//////Metronome//////
// Metronome playback generation is implemented in `scr_metronome.gml`
// (`metronome_generate_events` and `metronome_generate_countin_events`).
// The historical prototype below is intentionally left as reference only.
    /*
    // Check if metronome exists and is enabled
    if (is_undefined(_tune.metronome) || !variable_struct_exists(_tune.metronome, "enabled") || !_tune.metronome.enabled) {
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
    show_debug_message("tune_build_events: Base has " + string(array_length(base)) + " events");
    
    var met  = metronome_generate_events(_tune);  // Use new metronome system
    show_debug_message("tune_build_events: Metronome returned " + string(array_length(met)) + " events");
    
    // Debug: show first metronome event if any
    if (array_length(met) > 0) {
        var first = met[0];
        show_debug_message("  First metro event: time=" + string(first.time) + " note=" + string(first.note) + " channel=" + string(first.channel));
    }

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
    
    show_debug_message("tune_build_events: Merged total = " + string(array_length(merged)) + " events");

    return merged;
	}