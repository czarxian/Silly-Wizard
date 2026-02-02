// obj_game_controller — Project controller
// Purpose: Central global state & references hub. Initializes tune library and MIDI/global game state.
// Key responsibilities:
//  - Calls old_scr_tune_library() to initialize tune library.
//  - Sets global.ID_game_handler, global.metronome, global.ID_player, global.tune_picker, global.tune.
//  - Initializes MIDI device lists and MIDI event counters used by scr_MIDI and scr_button_scripts.
// Related scripts: scripts/scr_tune_library/, scripts/scr_MIDI/, scripts/scr_button_scripts/

// Set high step rate for precise MIDI timing (callbacks fire with ~1ms precision)
room_speed = 1000;  // 1000 steps per second (rendering still at monitor refresh rate)

//Create Globals
	//old_scr_tune_library();
	//scr_build_tune_library("datafiles/tunes/");
	scr_build_tune_library("tunes/");
	global.emb_library = load_embellishment_library("embellishments.json");

/// ============ EMBELLISHMENT TIMING CONFIGURATION ============
/// BPM-aware gracenote timing with safety constraints
	global.EMBELLISHMENT_CONFIG = {
		gracenote_unit_ms_base: 30,        // Base unit at reference BPM (e.g., 30ms at 60 BPM)
		min_gracenote_ms: 15,              // Hard minimum (fastest notes can't go below this)
		max_gracenote_ms: 80,              // Hard maximum (slowest notes can't exceed this)
		bpm_scaling_factor: -0.1,          // ms per BPM increase (negative = faster tempo → shorter notes)
		reference_bpm: 60,                 // Reference tempo for base unit calculation
		max_emb_percent: 0.8               // Optional: embellishment notes can't exceed 80% of target duration
	};

//Global ID References
	global.ID_game_handler = id;
	global.metronome=noone;
	global.ID_player=noone;
	global.tune_picker=noone;
	global.tune=instance_create_depth(0, 0, 0, obj_tune);

//Game State
	global.game_state="menu";
		
//MIDI globals
  //MIDI Input 
	global.midi_input_devices[0] = "not selected";
	global.midi_input_device=0;
	global.midi_input_device_name="not selected";
	global.midi_input_channel=0;

  //MIDI Output 
	global.midi_output_devices[0] = "not selected"; 
	global.midi_output_device=0;
	global.midi_output_device_name="not selected";
	global.midi_ouput_channel=0;

//Metronome Settings
	global.metronome_mode_options = ["None", "Click", "Drums"];
	global.metronome_mode = 2; // 0=None, 1=Click, 2=Drums (default to Drums)
	
	global.metronome_pattern_options = ["Auto"]; // Populated dynamically based on tune
	global.metronome_pattern_selection = 0; // Index into pattern_options array
	
	global.metronome_volume = 100; // 0-127 MIDI velocity

// === SET/PLAYLIST STRUCTURE ===
// Current set is an array of set items (each containing tune + playback settings)
	global.current_set = [];

// Currently selected set item index (for editing in tune window)
	global.current_set_item_index = -1;
	
	global.midi_output_drum=0;
	global.midi_output_drum_name="not selected";
	global.midi_ouput_drum_channel=0;

//Event gobals
	global.Midi_event_number=0;
	global.Midi_last_event_number=0;
	global.Midi_current_event_time=0;	
	global.Midi_next_event_deltatime=0;


