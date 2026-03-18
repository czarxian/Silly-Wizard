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

	// Initialize game visualization controls
	if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
		global.timeline_cfg = {
			enabled: true,
			tune_channel: 2,
			tune_show_other_parts_ghost: false,
			tune_other_parts_alpha: 0.18
		};
	} else {
		if (!variable_struct_exists(global.timeline_cfg, "enabled")) {
			global.timeline_cfg.enabled = true;
		}
		if (!variable_struct_exists(global.timeline_cfg, "tune_channel")) {
			global.timeline_cfg.tune_channel = 2;
		}
		if (!variable_struct_exists(global.timeline_cfg, "tune_show_other_parts_ghost")) {
			global.timeline_cfg.tune_show_other_parts_ghost = false;
		}
		if (!variable_struct_exists(global.timeline_cfg, "tune_other_parts_alpha")) {
			global.timeline_cfg.tune_other_parts_alpha = 0.18;
		}
	}

/// ============ EMBELLISHMENT & GRACENOTE TIMING CONFIGURATION ============
/// BPM-aware gracenote timing with safety constraints
	global.EMBELLISHMENT_CONFIG = {
		gracenote_unit_ms_base: 40,        // Base unit at reference BPM (e.g., 30ms at 60 BPM)
		min_gracenote_ms: 15,              // Hard minimum (fastest notes can't go below this)
		max_gracenote_ms: 80,              // Hard maximum (slowest notes can't exceed this)
		bpm_scaling_factor: -0.1,          // ms per BPM increase (negative = faster tempo → shorter notes)
		reference_bpm: 60,                 // Reference tempo for base unit calculation
		max_emb_percent: 0.8,              // Optional: embellishment notes can't exceed 80% of target duration
		
		// Fallback gracenote timing (for literal embellishment expansion)
		fallback_min_ms: 20,               // Duration at fast tempo (120+ BPM)
		fallback_max_ms: 80,               // Duration at slow tempo (50-60 BPM)
		fallback_fast_bpm_threshold: 120,  // BPM above which uses fallback_min_ms
		fallback_slow_bpm_threshold: 60    // BPM below which uses fallback_max_ms
	};

/// ============ METRONOME DRUM PROFILES ============
/// Drum kit note mappings for different VSTs/synths
	global.METRONOME_DRUM_PROFILES = {
		"General MIDI": {
			kick: 35,           // Acoustic Bass Drum
			snare: 38,          // Acoustic Snare
			hi_hat: 42,         // Closed Hi-Hat
			side_stick: 37,     // Side Stick
			cowbell: 56         // Cowbell
		},
		"Cantabile Drumline": {
			kick: 41,           // Low bass drum (F1)
			snare: 48,          // Snare straight (C2)
			hi_hat: 51,         // Cymbal edge choke (D#2)
			side_stick: 48,     // Snare straight
			cowbell: 51         // Cymbal edge choke
		}
	};
	global.current_metronome_drum_profile = "General MIDI";  // Default profile

//Global ID References
	global.ID_game_handler = id;
	global.metronome=noone;
	global.ID_player=noone;
	global.tune_picker=noone;
	global.tune=instance_create_depth(0, 0, 0, obj_tune);

//Game State
	global.game_state="menu";

// Review overlay toggles
	// Master switches for post-play notebeam overlays.
	// These live in obj_game_controller so UI can toggle them later without touching timeline config.
	if (!variable_global_exists("show_review_beat_bands")) {
		global.show_review_beat_bands = true;
	}
	if (!variable_global_exists("show_review_emb_boxes")) {
		global.show_review_emb_boxes = true;
	}
		
//MIDI globals
  //MIDI Input 
	global.midi_input_devices[0] = "not selected";
	global.midi_input_device=0;
	global.midi_input_device_name="not selected";
	global.midi_input_channel=0;
	global.chanter_channel=0;

  //MIDI Output 
	global.midi_output_devices[0] = "not selected"; 
	global.midi_output_device=0;
	global.midi_output_device_name="not selected";
	global.midi_ouput_channel=0;

	// Chanter MIDI output mapping selection
	global.MIDI_chanter_options = ["default", "blair"];
	// global.MIDI_chanter = "default";
	global.MIDI_chanter = "blair";

//Metronome Settings
	global.metronome_mode_options = ["None", "Click", "Drums"];
	global.metronome_mode = 2; // 0=None, 1=Click, 2=Drums (default to Drums)
	
	global.metronome_pattern_options = ["Auto"]; // Populated dynamically based on tune
	global.metronome_pattern_selection = 0; // Index into pattern_options array
	
	global.metronome_volume = 100; // 0-127 MIDI velocity

// Swing/gracenote overrides (0 = use default BPM-scaled timing)
	global.swing_mult = 0;
	global.gracenote_override_ms = 0;

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


