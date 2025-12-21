// obj_player Create Event

global.ID_player = id;

// Player instance variables
NoteOnVar = false;
NoteChange = false;
NotePlaying = NOTE_e;

// Initialize note arrays
NoteOnVar[NOTE_G] = false;
NoteOnVar[2] = false;
NoteOnVar[NOTE_A] = false;
NoteOnVar[4] = false;
NoteOnVar[NOTE_B] = false;
NoteOnVar[NOTE_c] = false;
NoteOnVar[NOTE_cshp] = false;
NoteOnVar[NOTE_d] = false;
NoteOnVar[9] = false;
NoteOnVar[NOTE_e] = false;
NoteOnVar[NOTE_f] = false;
NoteOnVar[NOTE_fshp] = false;
NoteOnVar[NOTE_g] = false;
NoteOnVar[14] = false;
NoteOnVar[NOTE_a] = false;

// Note locations
NoteLoc[1] = 395;
NoteLoc[3] = 365;
NoteLoc[5] = 335;
NoteLoc[6] = 319;
NoteLoc[7] = 289;
NoteLoc[8] = 252;
NoteLoc[10] = 214;
NoteLoc[11] = 175;
NoteLoc[12] = 120;
NoteLoc[13] = 102;
NoteLoc[15] = 70;



////global.current_index = 0;
//global.tune_index = 0;
//global.tune_events = global.tune[2];
//
//var first_time = global.tune_events[global.tune_index].time;
//var delta = first_time - current_time; // system clock approach
//
//// Create the timesource with dynamic period
//	global.tune_timer = time_source_create(
//	    time_source_game,          // parent
//	    delta / 1000,              // convert ms to seconds
//	    time_source_units_seconds, // units
//	    script_tune_callback,      // callback script
//	    [],                        // optional args
//	    1,                         // fire once
//	    time_source_expire_after   // expire after firing
//	);
//
//reference holder
//global.ID_player=id;
//
//
//// Ensure a tune has been selected
//if (is_undefined(global.tune_events)) {
//    show_debug_message("No tune selected!");
//    exit;
//}
//
//// Start at the first event
//global.tune_index = 0;
//var first_time = global.tune_events[global.tune_index].time;
//var delta = first_time - current_time;
//
//// Create the timesource
//global.tune_timer = time_source_create(
//    time_source_game,
//    delta / 1000,
//    time_source_units_seconds,
//    script_tune_callback,
//    [],
//    1,
//    time_source_expire_after
//);
//
//
//
////Player instance variables
//NoteOnVar=false;
//NoteChange=false;
//NotePlaying=NOTE_e;
//
//NoteOnVar[NOTE_G]=false;
//NoteOnVar[2]=false;
//NoteOnVar[NOTE_A]=false;
//NoteOnVar[4]=false;
//NoteOnVar[NOTE_B]=false;
//NoteOnVar[NOTE_c]=false;
//NoteOnVar[NOTE_cshp]=false;
//NoteOnVar[NOTE_d]=false;
//NoteOnVar[9]=false;
//NoteOnVar[NOTE_e]=false;
//NoteOnVar[NOTE_f]=false;
//NoteOnVar[NOTE_fshp]=false;
//NoteOnVar[NOTE_g]=false;
//NoteOnVar[14]=false;
//NoteOnVar[NOTE_a]=false;
//
//NoteLoc[1]=395;
//NoteLoc[3]=365;
//NoteLoc[5]=335;
//NoteLoc[6]=319;
//NoteLoc[7]=289;
//NoteLoc[8]=252;
//NoteLoc[10]=214;
//NoteLoc[11]=175;
//NoteLoc[12]=120;
//NoteLoc[13]=102;
//NoteLoc[15]=70;







