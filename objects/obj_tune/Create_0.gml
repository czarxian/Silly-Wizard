
// obj_tune — Tune data model
// Purpose: Holds the canonical tune data and metadata loaded from JSON.
// Key responsibilities:
//  - Registers global.tune
//  - Stores tune_metadata, events[], event_count, is_loaded, filename
// Related scripts: scripts/scr_tune_load/, scripts/scr_tune_scripts/

	global.tune=id;
	persistent = true;
	
	/// obj_tune Create
	// Store all data in a struct for better persistence across room transitions
	tune_data = {
		tune_metadata: {},
		events: [],
		performance: {},
		event_count: 0,
		is_loaded: false,
		filename: ""
	};
