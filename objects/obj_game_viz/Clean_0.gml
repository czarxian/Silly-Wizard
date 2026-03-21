/// Clean Up - Free cached surfaces
if (variable_global_exists("player_surface_cache") && surface_exists(global.player_surface_cache)) {
	surface_free(global.player_surface_cache);
	global.player_surface_cache = noone;
}

if (variable_global_exists("notebeam_live_player_surface") && surface_exists(global.notebeam_live_player_surface)) {
	surface_free(global.notebeam_live_player_surface);
	global.notebeam_live_player_surface = noone;
}

if (variable_global_exists("timeline_anchor_surface_cache") && is_struct(global.timeline_anchor_surface_cache)) {
	var _keys = variable_struct_get_names(global.timeline_anchor_surface_cache);
	for (var i = 0; i < array_length(_keys); i++) {
		var _k = _keys[i];
		var _entry = global.timeline_anchor_surface_cache[$ _k];
		if (is_struct(_entry) && variable_struct_exists(_entry, "surf") && surface_exists(_entry.surf)) {
			surface_free(_entry.surf);
		}
	}
	global.timeline_anchor_surface_cache = {};
}
