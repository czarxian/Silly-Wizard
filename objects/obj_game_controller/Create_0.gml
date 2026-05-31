// obj_game_controller — Project controller
// Purpose: Central global state & references hub. Initializes tune library and MIDI/global game state.
// Key responsibilities:
//  - Sets global.ID_game_handler, global.metronome, global.ID_player, global.tune_picker, global.tune.
//  - Initializes MIDI device lists and MIDI event counters used by scr_MIDI and scr_button_scripts.
// Related scripts: scripts/scr_tune_library/, scripts/scr_MIDI/, scripts/scr_button_scripts/

show_debug_message("=== RUNTIME PATHS ===");
show_debug_message("working_directory: " + working_directory);
show_debug_message("Export tunes to: " + working_directory + "tunes/");
show_debug_message("=====================");

// Set step rate for gameplay/update loop.
// Higher FPS lowers frame-quantized scheduler jitter (at CPU cost).
if (!variable_global_exists("GAME_STEP_FPS")) {
	global.GAME_STEP_FPS = 500;
}
var _game_step_fps = max(30, floor(real(global.GAME_STEP_FPS)));
game_set_speed(_game_step_fps, gamespeed_fps);

// Playback scheduler mode: "step" (per-step due-group pump) or "timesource".
if (!variable_global_exists("PLAYBACK_SCHEDULER_MODE")) {
	global.PLAYBACK_SCHEDULER_MODE = "timesource";
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS")) {
	// Small lookahead lets the step scheduler dispatch near-due groups before
	// they become visibly late under occasional frame stalls.
	global.PLAYBACK_SCHEDULER_STEP_LOOKAHEAD_MS = 1.0;
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP")) {
	global.PLAYBACK_SCHEDULER_MAX_GROUPS_PER_STEP = 12;
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US")) {
	global.PLAYBACK_SCHEDULER_STEP_MAX_PUMP_US = 1500;
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_STARTUP_DRAIN_MS")) {
	global.PLAYBACK_SCHEDULER_STARTUP_DRAIN_MS = 4.0;
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_STARTUP_ARM_DELAY_MS")) {
	global.PLAYBACK_SCHEDULER_STARTUP_ARM_DELAY_MS = 40.0;
}
if (!variable_global_exists("PLAYBACK_SCHEDULER_STARTUP_SPIKE_GRACE_MS")) {
	global.PLAYBACK_SCHEDULER_STARTUP_SPIKE_GRACE_MS = 200.0;
}
if (!variable_global_exists("PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP")) {
	global.PLAYBACK_DEFERRED_MAX_ITEMS_PER_STEP = 192;
}
if (!variable_global_exists("PLAYBACK_DEFERRED_MAX_BUDGET_US")) {
	global.PLAYBACK_DEFERRED_MAX_BUDGET_US = 1800;
}

//Create Globals
	// Optional tune content root override loaded from JSON config (runtime_paths.json).
	// Leave unset/blank in config to use AUTO content-root detection.
	if (!variable_global_exists("primary_data_root_override")) {
		var _cfg_root_override = "";
		if (script_exists(asset_get_index("scr_data_paths_load_primary_root_from_config"))) {
			_cfg_root_override = scr_data_paths_load_primary_root_from_config();
		} else if (script_exists(asset_get_index("scr_tune_library_load_root_override_from_config"))) {
			_cfg_root_override = scr_tune_library_load_root_override_from_config();
		}
		global.primary_data_root_override = _cfg_root_override;
	}

	// Legacy mirror while migration is in progress.
	if (!variable_global_exists("tune_library_root_override")) {
		global.tune_library_root_override = (global.primary_data_root_override != "")
			? (global.primary_data_root_override + "tunes/")
			: "";
	}

	// Diagnostic: print resolved content/user-data roots at boot to verify IDE vs packaged behavior.
	var _resolved_user_root = script_exists(asset_get_index("scr_data_paths_get_user_data_root"))
		? scr_data_paths_get_user_data_root()
		: "datafiles/";
	var _resolved_content_root = script_exists(asset_get_index("scr_data_paths_get_content_root"))
		? scr_data_paths_get_content_root()
		: _resolved_user_root;
	show_debug_message("[PATHS] user_data_root=" + _resolved_user_root);
	show_debug_message("[PATHS] content_root=" + _resolved_content_root);

	// Build tune library using runtime-resolved root (supports zipped/package distribution).
	var _tune_root = script_exists(asset_get_index("scr_tune_library_get_runtime_root"))
		? scr_tune_library_get_runtime_root()
		: "datafiles/tunes/";
	scr_build_tune_library(_tune_root);
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
	if (!variable_global_exists("pending_layer_mode")) {
		global.pending_layer_mode = "";
	}
	if (!variable_global_exists("pending_layer_room")) {
		global.pending_layer_room = -1;
	}
	if (!variable_global_exists("pending_auto_start_play")) {
		global.pending_auto_start_play = false;
	}
		if (!variable_global_exists("loop_mode_enabled")) {
			global.loop_mode_enabled = false;
		}
		if (!variable_global_exists("loop_repeat_total")) {
			global.loop_repeat_total = 10;
		}
		if (!variable_global_exists("loop_jump_to_selection")) {
			global.loop_jump_to_selection = false;
		}
	if (room == Room_main_menu) {
		global.pending_layer_mode = "main";
		global.pending_layer_room = Room_main_menu;
		scr_player_button_label_refresh();
	}

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

// === MUSICAL SET (multi-tune named set, Phase 1) ===
	scr_set_init_global();  // also calls scr_playback_context_init()

	global.midi_output_drum=0;
	global.midi_output_drum_name="not selected";
	global.midi_ouput_drum_channel=0;

//Event gobals
	global.Midi_event_number=0;
	global.Midi_last_event_number=0;
	global.Midi_current_event_time=0;	
	global.Midi_next_event_deltatime=0;

// Ensure active player identity exists before loading any per-player settings.
if (!variable_global_exists("current_player_index")) {
	global.current_player_index = 0;
}
if (!variable_global_exists("current_player_id") || string_trim(string(global.current_player_id)) == "") {
	global.current_player_id = "player_1";
}

// Load settings for the active player on startup.
if (script_exists(asset_get_index("scoring_judge_settings_load_for_player"))) {
	scoring_judge_settings_load_for_player(global.current_player_id);
}
if (script_exists(asset_get_index("scoring_player_settings_load_for_player"))) {
	scoring_player_settings_load_for_player(global.current_player_id);
}
if (script_exists(asset_get_index("scoring_tune_overrides_load_for_player"))) {
	scoring_tune_overrides_load_for_player(global.current_player_id);
}

