

// Struct for a tune
//	sample_tune_data = {
//	title: "Peter MacKenzies Warren",
//	bpm: 72,
//	beats_per_measure: 4,
//	beat_note: 4,
//	parts: [
//		{ instrument: "chanter", events: [...] },
//		{ instrument: "drums",   events: [...] }
//	]
//	};

 
 tune_data = {
    title: "Peter MacKenzies Warren",
    bpm: 72,
    beats_per_measure: 4,
    beat_note: 4,
    parts: [
        {
            instrument: "chanter",
            events: [
				{ time:0, delta:0, event:144, channel:1, note:NOTE_G, velocity:90 },
				{ time:250, delta:250, event:128, channel:1, note:NOTE_G, velocity:0 },
				{ time:250, delta:0, event:144, channel:1, note:NOTE_A, velocity:90 },
				{ time:500, delta:250, event:128, channel:1, note:NOTE_A, velocity:0 },
				{ time:500, delta:0, event:144, channel:1, note:NOTE_B, velocity:90 },
				{ time:750, delta:0, event:128, channel:1, note:NOTE_B, velocity:0 },
				{ time:750, delta:250, event:144, channel:1, note:NOTE_c, velocity:70},
				{ time:1000, delta:0, event:128, channel:1, note:NOTE_c, velocity:0 },
				{ time:1000, delta:250, event:144, channel:1, note:NOTE_d, velocity:70 },
				{ time:1250, delta:250, event:144, channel:1, note:NOTE_d, velocity:70, length:70 }
            ]
        },
        {
            instrument: "drums",
            events: [
                { time:0,   event:144, note:38, velocity:100 }, // snare hit
                { time:500, event:128, note:38, velocity:0 }
            ]
        }
    ]
};



// Struct for metronome
//	metronome_data = {
//		bpm: tune_data.bpm,
//		time_signature: [tune_data.beats_per_measure, tune_data.beat_note],
//		click_pattern: [1,0,0,0], // accent first beat
//		click_sound: snd_click
//	};

// Struct for startup options
//	startup_data = {
//		countdown: 0, // measures
//		drum_roll: false
//	};
	
// Final play log (precalculated)
	play_log = [];
	
//Build the PLAY LOG from the sources	
function build_play_log(_tune, _metronome, _startup) {
	var log = [];
	
	var ms_per_beat = (60000 / _tune.bpm);
	var tune_current_time = 0;
	
	// Startup countdown NOT IN USE
	if (_startup.countdown > 0) {
	    for (var c = 0; c < _startup.countdown * _tune.beats_per_measure; c++) {
	        array_push(log, {
	            time: tune_current_time,
	            type: "metronome",
	            sound: _metronome.click_sound,
	            beat: (c mod _tune.beats_per_measure)
	        });
	        tune_current_time += ms_per_beat;
	    }
	}
	
	// Optional drum roll NOT IN USE
	if (_startup.drum_roll) {
	    for (var d = 0; d < 8; d++) {
	        array_push(log, {
	            time: tune_current_time,
	            type: "drum_roll",
	            note: 38, // snare MIDI
	            velocity: 100
	        });
	        tune_current_time += ms_per_beat / 4; // fast roll
	    }
	}
	
	// Tune events (all parts)
	for (var p = 0; p < array_length(_tune.parts); p++) {
	    var part = _tune.parts[p];
	    for (var e = 0; e < array_length(part.events); e++) {
	        var ev = part.events[e];
	        array_push(log, {
	            time: ev.time_ms,
				delta: ev.delta,
	            event: ev.event_type,
				channel: ev.channel,
				note: ev.note_num + MidiLowNoteOffset,
	            velocity: ev.velocity,
	            instrument: part.instrument
	        });
	    }
	}

	// Sort by time so playback is linear
	array_sort(log, function(a,b){ return a.time - b.time; });
	
	return log;
	}