global.tune_data = {
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
    ]
};


// Example tune events (replace with your own)
	global.tune_events = [
	    { time: 0,    type: ev_midi, channel: 0, note: 60, velocity: 100 },
	    { time: 500,  type: ev_midi, channel: 0, note: 64, velocity: 100 },
	    { time: 1000, type: ev_midi, channel: 0, note: 67, velocity: 100 }
	];
	
	global.current_index = 0;

// Calculate delay until the first event
	var first_time = global.tune_events[global.current_index].time;
	var delta = first_time - current_time; // system clock approach

// Create the timesource with dynamic period
	global.tune_timer = time_source_create(
	    time_source_game,          // parent
	    delta / 1000,              // convert ms to seconds
	    time_source_units_seconds, // units
	    script_tune_callback,      // callback script
	    [],                        // optional args
	    1,                         // fire once
	    time_source_expire_after   // expire after firing
	);


//reference holder
global.ID_player=id;

//Player instance variables
NoteOnVar=false;
NoteChange=false;
NotePlaying=NOTE_e;

NoteOnVar[NOTE_G]=false;
NoteOnVar[2]=false;
NoteOnVar[NOTE_A]=false;
NoteOnVar[4]=false;
NoteOnVar[NOTE_B]=false;
NoteOnVar[NOTE_c]=false;
NoteOnVar[NOTE_cshp]=false;
NoteOnVar[NOTE_d]=false;
NoteOnVar[9]=false;
NoteOnVar[NOTE_e]=false;
NoteOnVar[NOTE_f]=false;
NoteOnVar[NOTE_fshp]=false;
NoteOnVar[NOTE_g]=false;
NoteOnVar[14]=false;
NoteOnVar[NOTE_a]=false;

NoteLoc[1]=395;
NoteLoc[3]=365;
NoteLoc[5]=335;
NoteLoc[6]=319;
NoteLoc[7]=289;
NoteLoc[8]=252;
NoteLoc[10]=214;
NoteLoc[11]=175;
NoteLoc[12]=120;
NoteLoc[13]=102;
NoteLoc[15]=70;



//sample tune data for testing
global.tune_events_2 = [
    250,   // 0.25 sec
    1200,  // 1.2 sec
    800,   // 0.8 sec
    1500,  // 1.5 sec
    400,   // 0.4 sec
    100,   // 0.1 sec
    950,   // 0.95 sec
    600,   // 0.6 sec
    1350,  // 1.35 sec
    700    // 0.7 sec
];

//sample tune data for testing
global.tune_events = [
    100,   // 0.25 sec
    100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
	100,   // 0.25 sec
];


global.tune_index = 0;

// Create a time source that waits 1000 ms (1 second) then calls a script
global.tune_timer = time_source_create(
    time_source_game,         // parent (this object will own the timer)
    1,                        // period (3 seconds)
    time_source_units_seconds, // units
    script_tune_callback,        // callback script
    [],                   // optional args
    1,                           // repetitions (1 = fire once)
    time_source_expire_after     // expiry type (remove after firing)
);

/// @desc Initializes tune playback and timesource




