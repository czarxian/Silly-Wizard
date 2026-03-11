// scr_UI_scripts — UI layer utilities & field sync
// Purpose: Helpers for mapping layer names/indices, refreshing UI assets, and updating fields from global arrays.
// Key functions: GetLayerNameFromIndex, GetLayerIndexFromName, scr_update_fields, scr_ui_refresh

/// @desc UI Layer Utilities
//test//
/// @function GetLayerNameFromIndex(_index)
	// @desc Returns the layer name string for a given index, or "unknown layer" if invalid.
	function GetLayerNameFromIndex(_index) {
	    if (_index >= 0 && _index < array_length(global.ui_layer_names)) {
	        return global.ui_layer_names[_index];
	    }
	    return "unknown layer";
	}

/// @function GetLayerIndexFromName(_name)
	// @desc Returns the numeric index for a given layer name, or -1 if not found.
	function GetLayerIndexFromName(_name) {
	    var len = array_length(global.ui_layer_names);
	    for (var i = 0; i < len; i++) {
	        if (global.ui_layer_names[i] == _name) {
	            return i;
	        }
	    }
	    return -1;
	}
	
	/// @function scr_hide_window(_target, _inst)
	// @desc Safely hide a UI layer based on a button's label, a layer name, or a layer index. Returns true if a layer was hidden.
	function scr_hide_window(_target, _inst) {
	    var hid = false;
	
	    // Direct string target (likely a layer name)
	    if (!is_undefined(_target) && is_string(_target)) {
	        var lid = layer_get_id(_target);
	        if (lid != -1) {
	            layer_set_visible(lid, false);
	            return true;
	        }
	        // Try mapping via our layer name array
	        var idx = GetLayerIndexFromName(_target);
	        if (idx >= 0) {
	            var lname = GetLayerNameFromIndex(idx);
	            var lid2 = layer_get_id(lname);
	            if (lid2 != -1) {
	                layer_set_visible(lid2, false);
	                return true;
	            }
	        }
	    }
	
	    // Numeric target (layer index)
	    if (!is_undefined(_target) && (is_real(_target) || is_integer(_target))) {
	        var lname2 = GetLayerNameFromIndex(_target);
	        var lid3 = layer_get_id(lname2);
	        if (lid3 != -1) {
	            layer_set_visible(lid3, false);
	            return true;
	        }
	    }
	
	    // Fallback to the instance's ui_layer_num if provided
	    if (!is_undefined(_inst) && variable_instance_exists(_inst, "ui_layer_num")) {
	        var lname3 = GetLayerNameFromIndex(_inst.ui_layer_num);
	        var lid4 = layer_get_id(lname3);
	        if (lid4 != -1) {
	            layer_set_visible(lid4, false);
	            return true;
	        }
	    }
	
	    return false;
	}
	
		function scr_update_fields(_ui_layer_num) {
	    var assets = global.ui_assets[_ui_layer_num];
	
	    for (var i = 0; i < array_length(assets); i++) {
	        var entry = assets[i];
	        var inst  = entry[1];
	
	        if (instance_exists(inst) && inst.ui_type == "field") {
	            with (inst) {
	                var target_array;
	
	                if (is_string(field_target)) {
	                    // resolve the global variable by name
	                    target_array = variable_global_get(field_target);
	                } else {
	                    target_array = field_target; // already a reference
	                }
	
	                if (is_array(target_array)) {
	                    var len = array_length(target_array);
	                    if (field_value >= 0 && field_value < len) {
	                        field_contents = target_array[field_value];
	                    }
	                }
	            }
	        }
	    }
	}
	
	function scr_ui_refresh(_layer_num) {
	    if (!is_array(global.ui_assets) || !is_array(global.ui_assets[_layer_num])) return;
	
	    for (var i = 0; i < array_length(global.ui_assets[_layer_num]); i++) {
	        var entry = global.ui_assets[_layer_num][i];
	        var num   = entry[0];
	        var oldID = entry[1];
	
	        if (!instance_exists(oldID)) {
	            with (obj_UI_parent) {
	                if (ui_num == num && ui_layer_num == _layer_num) {
	                    global.ui_assets[_layer_num][i][1] = id;
	                }
	            }
	        }
	    }
	}

function cn_panel_init_state() {
	var panel_min_note_ms = 15;
	if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "filter_noise_ms")) {
		panel_min_note_ms = max(0, real(global.timeline_cfg.filter_noise_ms));
	}

	global.current_note_panel = {
		bound: false,
		refs: {
			last_tune: noone,
			current_tune: noone,
			next_tune: noone,
			last_player: noone,
			current_player: noone,
			next_player: noone
		},
		min_note_ms: panel_min_note_ms,
		core_min_note_ms: 100,
		filter_marker_symbol: "^",
		current_measure: 0,
		tune_plan_by_measure: {},
		plan_last_beat_by_measure: {},
		tune_played_by_measure: {},
		player_played_by_measure: {},
		render_tokens: {},
		classified_events: [],
		pending_tune_notes: {},
		pending_player_notes: {}
	};
}

function cn_panel_note_key(_channel, _note_midi) {
	return string(_channel) + ":" + string(_note_midi);
}

function cn_panel_append_note(_map, _measure, _note, _note_class = "normal") {
	if (_measure < 1) return;
	var key = string(_measure);
	var slot = _map[$ key];
	if (is_undefined(slot)) {
		slot = {
			text: "",
			count: 0,
			tokens: []
		};
	}
	if (!variable_struct_exists(slot, "tokens") || !is_array(slot.tokens)) {
		slot.tokens = [];
	}
	if (slot.count > 0) {
		slot.text += " ";
		array_push(slot.tokens, {
			text: " ",
			class: "space"
		});
	}
	var token_text = string(_note);
	slot.text += token_text;
	array_push(slot.tokens, {
		text: token_text,
		class: string(_note_class)
	});
	slot.count += 1;
	_map[$ key] = slot;
}

function cn_panel_append_separator(_map, _measure) {
	if (_measure < 1) return;
	cn_panel_append_note(_map, _measure, "|", "separator");
}

function cn_panel_append_filtered_marker(_map, _measure) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	var marker = string(global.current_note_panel.filter_marker_symbol ?? "^");
	if (string_length(marker) <= 0) marker = "^";
	cn_panel_append_note(_map, _measure, marker, "filtered_noise");
}

function cn_panel_get_tokens(_map, _measure) {
	if (_measure < 1) return [];
	var slot = _map[$ string(_measure)];
	if (is_undefined(slot)) return [];
	var tokens = slot.tokens;
	if (is_undefined(tokens) || !is_array(tokens)) return [];
	return tokens;
}

function cn_panel_tokens_to_text(_tokens) {
	var out = "";
	for (var i = 0; i < array_length(_tokens); i++) {
		var tk = _tokens[i];
		out += string(tk.text ?? "");
	}
	return out;
}

function cn_panel_record_event(_source, _measure, _note_midi, _channel, _duration_ms, _note_class, _is_filtered, _time_ms) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	var note_text = midi_to_letter(_note_midi, _channel);
	array_push(global.current_note_panel.classified_events, {
		source: string(_source),
		measure: real(_measure),
		note_midi: real(_note_midi),
		note_text: note_text,
		channel: real(_channel),
		duration_ms: real(_duration_ms),
		note_class: string(_note_class),
		is_filtered: _is_filtered,
		time_ms: real(_time_ms)
	});
}

function cn_panel_get_text(_map, _measure) {
	if (_measure < 1) return "";
	var slot = _map[$ string(_measure)];
	if (is_undefined(slot)) return "";
	return string(slot.text ?? "");
}

function cn_panel_try_bind_refs() {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) {
		cn_panel_init_state();
	}
	if (global.current_note_panel.bound) return;

	if (!variable_global_exists("ui_assets") || !is_array(global.ui_assets)) return;

	var refs = global.current_note_panel.refs;
	for (var layer_idx = 0; layer_idx < array_length(global.ui_assets); layer_idx++) {
		if (!is_array(global.ui_assets[layer_idx])) continue;
		for (var i = 0; i < array_length(global.ui_assets[layer_idx]); i++) {
			var entry = global.ui_assets[layer_idx][i];
			if (!is_array(entry) || array_length(entry) < 2) continue;
			var inst = entry[1];
			if (!instance_exists(inst)) continue;

			var key = "";
			if (variable_instance_exists(inst, "ui_name")) {
				key = string(inst.ui_name);
			}
			if (key == "" || key == "n/a") continue;

			switch (key) {
				case "obj_last_measure_tune_notes": refs.last_tune = inst; break;
				case "obj_current_measure_tune_notes": refs.current_tune = inst; break;
				case "obj_next_measure_tune_notes": refs.next_tune = inst; break;
				case "obj_last_measure_player_notes": refs.last_player = inst; break;
				case "obj_current_measure_player_notes": refs.current_player = inst; break;
				case "obj_next_measure_player_notes": refs.next_player = inst; break;
			}
		}
	}

	global.current_note_panel.refs = refs;
	if (instance_exists(refs.last_tune) && instance_exists(refs.current_tune) && instance_exists(refs.next_tune)
		&& instance_exists(refs.last_player) && instance_exists(refs.current_player)) {
		global.current_note_panel.bound = true;
	}
}

function cn_panel_set_field(_field_id, _text) {
	if (!instance_exists(_field_id)) return;
	with (_field_id) {
		field_contents = _text;
	}
}

function cn_panel_get_max_measure() {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return 1;

	var panel = global.current_note_panel;
	var max_measure = 1;
	var maps = [
		panel.tune_plan_by_measure,
		panel.tune_played_by_measure,
		panel.player_played_by_measure
	];

	for (var i = 0; i < array_length(maps); i++) {
		var map = maps[i];
		if (!is_struct(map)) continue;

		var names = variable_struct_get_names(map);
		for (var j = 0; j < array_length(names); j++) {
			var key = names[j];
			var measure = floor(real(key));
			if (measure > max_measure) max_measure = measure;
		}
	}

	return max_measure;
}

function cn_panel_scroll_measure(_delta) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return 1;

	var panel = global.current_note_panel;
	var current_measure = max(1, floor(real(panel.current_measure ?? 1)));
	var target_measure = current_measure + floor(real(_delta));
	var max_measure = max(1, cn_panel_get_max_measure());

	target_measure = clamp(target_measure, 1, max_measure);
	panel.current_measure = target_measure;
	global.current_note_panel = panel;
	cn_panel_render();

	return target_measure;
}

function cn_panel_render() {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	cn_panel_try_bind_refs();
	var panel = global.current_note_panel;
	var m = panel.current_measure;

	var last_tune_tokens = cn_panel_get_tokens(panel.tune_played_by_measure, m - 1);
	var current_tune_tokens = cn_panel_get_tokens(panel.tune_played_by_measure, m);
	var next_tune_tokens = cn_panel_get_tokens(panel.tune_plan_by_measure, m + 1);
	var last_player_tokens = cn_panel_get_tokens(panel.player_played_by_measure, m - 1);
	var current_player_tokens = cn_panel_get_tokens(panel.player_played_by_measure, m);
	var next_player_tokens = cn_panel_get_tokens(panel.player_played_by_measure, m + 1);

	var last_tune_text = cn_panel_tokens_to_text(last_tune_tokens);
	var current_tune_text = cn_panel_tokens_to_text(current_tune_tokens);
	var next_tune_text = cn_panel_tokens_to_text(next_tune_tokens);
	var last_player_text = cn_panel_tokens_to_text(last_player_tokens);
	var current_player_text = cn_panel_tokens_to_text(current_player_tokens);
	var next_player_text = cn_panel_tokens_to_text(next_player_tokens);

	panel.render_tokens[$ "obj_last_measure_tune_notes"] = last_tune_tokens;
	panel.render_tokens[$ "obj_current_measure_tune_notes"] = current_tune_tokens;
	panel.render_tokens[$ "obj_next_measure_tune_notes"] = next_tune_tokens;
	panel.render_tokens[$ "obj_last_measure_player_notes"] = last_player_tokens;
	panel.render_tokens[$ "obj_current_measure_player_notes"] = current_player_tokens;
	panel.render_tokens[$ "obj_next_measure_player_notes"] = next_player_tokens;
	global.current_note_panel = panel;

	cn_panel_set_field(panel.refs.last_tune, last_tune_text);
	cn_panel_set_field(panel.refs.current_tune, current_tune_text);
	cn_panel_set_field(panel.refs.next_tune, next_tune_text);
	cn_panel_set_field(panel.refs.last_player, last_player_text);
	cn_panel_set_field(panel.refs.current_player, current_player_text);
	cn_panel_set_field(panel.refs.next_player, next_player_text);
}

function cn_panel_prepare_tune_plan(_events) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) {
		cn_panel_init_state();
	}
	global.current_note_panel.current_measure = 1;
	global.current_note_panel.tune_plan_by_measure = {};
	global.current_note_panel.plan_last_beat_by_measure = {};
	global.current_note_panel.tune_played_by_measure = {};
	global.current_note_panel.player_played_by_measure = {};
	global.current_note_panel.render_tokens = {};
	global.current_note_panel.classified_events = [];
	global.current_note_panel.pending_tune_notes = {};
	global.current_note_panel.pending_player_notes = {};

	for (var i = 0; i < array_length(_events); i++) {
		var ev = _events[i];
		if (ev.type != "note_on") continue;
		if (!struct_exists(ev, "channel") || ev.channel == global.METRONOME_CONFIG.channel) continue;
		var measure = real(ev.measure ?? 0);
		if (measure < 1) continue;
		var plan_key = string(measure);
		var beat = real(ev.beat ?? 0);
		if (beat > 0) {
			var last_beat = global.current_note_panel.plan_last_beat_by_measure[$ plan_key];
			if (!is_undefined(last_beat) && beat != last_beat) {
				cn_panel_append_separator(global.current_note_panel.tune_plan_by_measure, measure);
			}
			global.current_note_panel.plan_last_beat_by_measure[$ plan_key] = beat;
		}
		var note_text = midi_to_letter(ev.note, ev.channel);
		cn_panel_append_note(global.current_note_panel.tune_plan_by_measure, measure, note_text, "planned");
	}

	cn_panel_try_bind_refs();
	cn_panel_render();
}

function cn_panel_on_tune_note_on(_measure, _note_midi, _channel, _time_ms) {
	if (_measure < 1) return;
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	if (_channel == global.METRONOME_CONFIG.channel) return;

	global.current_note_panel.current_measure = _measure;
	var key = cn_panel_note_key(_channel, _note_midi);
	global.current_note_panel.pending_tune_notes[$ key] = {
		start_ms: real(_time_ms),
		measure: _measure,
		note_midi: _note_midi,
		channel: _channel
	};
	cn_panel_render();
}

function cn_panel_on_tune_note_off(_measure, _note_midi, _channel, _time_ms) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	if (_channel == global.METRONOME_CONFIG.channel) return;

	var key = cn_panel_note_key(_channel, _note_midi);
	var pending = global.current_note_panel.pending_tune_notes[$ key];
	if (is_undefined(pending)) return;

	var duration_ms = real(_time_ms) - real(pending.start_ms);
	global.current_note_panel.pending_tune_notes[$ key] = undefined;
	if (duration_ms < real(global.current_note_panel.min_note_ms)) {
		var filtered_measure = real(pending.measure ?? _measure);
		if (filtered_measure >= 1) {
			cn_panel_append_filtered_marker(global.current_note_panel.tune_played_by_measure, filtered_measure);
			cn_panel_record_event("tune", filtered_measure, _note_midi, _channel, duration_ms, "filtered_noise", true, _time_ms);
			cn_panel_render();
		}
		return;
	}

	var resolved_measure = real(pending.measure ?? _measure);
	if (resolved_measure < 1) return;
	var note_text = midi_to_letter(_note_midi, _channel);
	var tune_class = (duration_ms < real(global.current_note_panel.core_min_note_ms)) ? "short_noncore" : "core_melody";
	cn_panel_append_note(global.current_note_panel.tune_played_by_measure, resolved_measure, note_text, tune_class);
	cn_panel_record_event("tune", resolved_measure, _note_midi, _channel, duration_ms, tune_class, false, _time_ms);
	cn_panel_render();
}

function cn_panel_on_player_note_on(_note_midi, _channel, _time_ms) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	if (_channel != 0) return;

	var measure = real(global.current_note_panel.current_measure ?? 0);
	if (measure < 1) return;
	var key = cn_panel_note_key(_channel, _note_midi);
	global.current_note_panel.pending_player_notes[$ key] = {
		start_ms: real(_time_ms),
		measure: measure,
		note_midi: _note_midi,
		channel: _channel
	};
	cn_panel_render();
}

function cn_panel_on_player_note_off(_note_midi, _channel, _time_ms) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;
	if (_channel != 0) return;

	var key = cn_panel_note_key(_channel, _note_midi);
	var pending = global.current_note_panel.pending_player_notes[$ key];
	if (is_undefined(pending)) return;

	var duration_ms = real(_time_ms) - real(pending.start_ms);
	global.current_note_panel.pending_player_notes[$ key] = undefined;
	if (duration_ms < real(global.current_note_panel.min_note_ms)) {
		var filtered_measure = real(pending.measure ?? 0);
		if (filtered_measure >= 1) {
			cn_panel_append_filtered_marker(global.current_note_panel.player_played_by_measure, filtered_measure);
			cn_panel_record_event("player", filtered_measure, _note_midi, _channel, duration_ms, "filtered_noise", true, _time_ms);
			cn_panel_render();
		}
		return;
	}

	var measure = real(pending.measure ?? 0);
	if (measure < 1) return;

	var note_text = midi_to_letter(_note_midi, _channel);
	var player_class = "core_melody";
	cn_panel_append_note(global.current_note_panel.player_played_by_measure, measure, note_text, player_class);
	cn_panel_record_event("player", measure, _note_midi, _channel, duration_ms, player_class, false, _time_ms);
	cn_panel_render();
}

function cn_panel_on_beat_marker(_measure, _beat, _is_countin) {
	if (!variable_global_exists("current_note_panel") || !is_struct(global.current_note_panel)) return;

	var measure = real(_measure);
	if (measure < 1) {
		measure = max(1, real(global.current_note_panel.current_measure ?? 1));
	}
	if (measure < 1) measure = 1;

	global.current_note_panel.current_measure = measure;
	cn_panel_append_separator(global.current_note_panel.tune_played_by_measure, measure);
	cn_panel_append_separator(global.current_note_panel.player_played_by_measure, measure);
	cn_panel_render();
}