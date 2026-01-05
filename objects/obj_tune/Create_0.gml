
// obj_tune — Tune data model
// Purpose: Holds the canonical tune data and metadata loaded from JSON.
// Key responsibilities:
//  - Registers global.tune
//  - Stores tune_metadata, events[], event_count, is_loaded, filename
// Related scripts: scripts/scr_tune_load/, scripts/scr_tune_scripts/

	global.tune=id;
	
/// obj_tune Create
	tune_metadata = {};
	events = [];
	event_count = 0;
	is_loaded = false;
	filename = "";
