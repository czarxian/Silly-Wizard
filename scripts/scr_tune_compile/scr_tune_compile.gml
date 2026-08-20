// Compile pipeline stage registry and compiled-tune validator.
// See TUNE_PIPELINE_CONTRACT.md §6 (compile/run boundary) and §10 (stage ordering).
//
// Every stage below is a no-op stub. Stages are filled in by later phases; a deferred
// feature stays a no-op in the list rather than being absent from it.

/// @function tune_compiled_create_empty(_tune_uid)
/// @description Create the compiled-tune envelope with all layers empty.
/// @param {string} [_tune_uid]  Stable tune identity (folder slug)
/// @returns {struct}  Compiled tune carrying layers L0, L1, L2 and L4
function tune_compiled_create_empty(_tune_uid = "") {
	return {
		schema_version: TUNE_PIPELINE_SCHEMA_VERSION,
		tune_uid: tune_uid_sanitize_token(_tune_uid),
		provenance: undefined,

		meter: "",
		voices: [],

		structure: { parts: [], measures: [] },   // L0
		beat_grid: { beats: [] },                 // L1 — unit space only; ms is a run-time projection
		events: {},                               // L2 — voice name -> array of events
		annotations: []                           // L4
	};
}

/// @function tune_compile_context(_abc_text, _tune_config, _tune_uid)
/// @description Build the mutable context threaded through every compile stage.
/// @param {string} _abc_text     ABC source text
/// @param {struct} _tune_config  Resolved tune configuration
/// @param {string} [_tune_uid]   Stable tune identity
/// @returns {struct}  {abc_text, config, compiled, diagnostics, tokens}
function tune_compile_context(_abc_text, _tune_config, _tune_uid = "") {
	return {
		abc_text: string(_abc_text),
		config: is_struct(_tune_config) ? _tune_config : {},
		compiled: tune_compiled_create_empty(_tune_uid),
		diagnostics: tune_diagnostics_create(),
		parsed: undefined,
		tokens: []
	};
}

// ---------------------------------------------------------------------------
// tune_compile stages (§10) — pure, cacheable, stored
// ---------------------------------------------------------------------------

/// @function tune_compile_stage_parse_abc(_ctx)
/// @description Stage 1: parse every voice into unit-space flat events.
///              Repeat expansion happens inside this pass per voice, so stage 2 is a no-op.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_parse_abc(_ctx) {
	var _parsed = abc_parse_tune(_ctx[$ "abc_text"], _ctx[$ "diagnostics"]);
	_ctx[$ "parsed"] = _parsed;

	var _compiled = _ctx[$ "compiled"];
	var _consts = _parsed[$ "consts"];
	var _headers = _parsed[$ "headers"];

	_compiled[$ "meter"] = string(_consts[$ "meter"]);
	_compiled[$ "title"] = string(_headers[$ "t"] ?? "");
	_compiled[$ "composer"] = string(_headers[$ "c"] ?? "");
	_compiled[$ "rhythm_type"] = string(_headers[$ "r"] ?? "");
	_compiled[$ "unit_note_length"] = string(_consts[$ "unit_note_length"]);
	_compiled[$ "tempo_default"] = real(_headers[$ "q"] ?? 0);

	var _voices = _parsed[$ "voices"];
	var _names = [];
	for (var _i = 0; _i < array_length(_voices); _i++) {
		array_push(_names, _voices[_i].voice_name);
	}
	_compiled[$ "voices"] = _names;

	if (array_length(_voices) == 0) {
		tune_diagnostics_add(_ctx[$ "diagnostics"], TUNE_DIAG_ERROR, "abc_no_voices",
			"ABC produced no playable voices.");
	}
}

/// @function tune_compile_stage_expand_repeats(_ctx)
/// @description Stage 2: repeats are already flattened per voice by stage 1.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_expand_repeats(_ctx) { }

/// @function tune_compile_stage_build_structure(_ctx)
/// @description Stage 3: build L0 from the first voice's bar positions. Measure 0 is a pickup;
///              a pickup is paired with the short measure that completes its beat budget.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_structure(_ctx) {
	var _parsed = _ctx[$ "parsed"];
	var _voices = _parsed[$ "voices"];
	if (array_length(_voices) == 0) return;

	var _consts = _parsed[$ "consts"];
	var _units_per_beat = _consts[$ "units_per_beat"];
	var _expected_beats = _consts[$ "beats_per_measure"];
	var _events = _voices[0].events;

	// Collect measure spans in the order they first appear.
	var _measures = [];
	var _seen = {};
	for (var _i = 0; _i < array_length(_events); _i++) {
		var _e = _events[_i];
		var _m = _e.measure;
		var _key = string(_m);

		if (!variable_struct_exists(_seen, _key)) {
			var _uid = tune_uid_measure("1", _m);
			var _rec = {
				measure_uid: _uid,
				part_id: "1",
				expanded_index: _m,
				canonical_measure: _m,
				start_units: _e.total_units,
				end_units: _e.total_units,
				expected_beats: _expected_beats,
				actual_beats: 0,
				pickup_role: (_m == 0) ? "pickup_head" : "none",
				complement_uid: ""
			};
			variable_struct_set(_seen, _key, _rec);
			array_push(_measures, _rec);
		}

		var _cur = variable_struct_get(_seen, _key);
		_cur.end_units = max(_cur.end_units, _e.total_units + real(_e.written));
	}

	for (var _i = 0; _i < array_length(_measures); _i++) {
		var _rec = _measures[_i];
		_rec.actual_beats = (_rec.end_units - _rec.start_units) / _units_per_beat;
	}

	// A pickup is completed by the last short measure; pair them so loops stay whole.
	if (array_length(_measures) > 0 && _measures[0].pickup_role == "pickup_head") {
		var _head = _measures[0];
		var _need = _head.expected_beats - _head.actual_beats;
		for (var _i = array_length(_measures) - 1; _i >= 1; _i--) {
			if (abs(_measures[_i].actual_beats - _need) < 0.01) {
				_measures[_i].pickup_role = "pickup_complement";
				_measures[_i].complement_uid = _head.measure_uid;
				_head.complement_uid = _measures[_i].measure_uid;
				break;
			}
		}
		if (_head.complement_uid == "") {
			tune_diagnostics_add(_ctx[$ "diagnostics"], TUNE_DIAG_WARNING, "pickup_no_complement",
				"Pickup of " + string(_head.actual_beats)
				+ " beats has no matching short measure.", { measure_uid: _head.measure_uid });
		}
	}

	var _compiled = _ctx[$ "compiled"];
	_compiled[$ "structure"] = {
		parts: [{ part_id: "1", measure_count: array_length(_measures) }],
		measures: _measures
	};
}

/// @function tune_compile_stage_build_beat_grid(_ctx)
/// @description Stage 4: build L1 in unit space. Milliseconds are a run-time projection.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_beat_grid(_ctx) {
	var _parsed = _ctx[$ "parsed"];
	var _consts = _parsed[$ "consts"];
	var _units_per_beat = _consts[$ "units_per_beat"];

	var _compiled = _ctx[$ "compiled"];
	var _structure = _compiled[$ "structure"];
	var _measures = _structure[$ "measures"];

	var _beats = [];
	for (var _i = 0; _i < array_length(_measures); _i++) {
		var _m = _measures[_i];
		var _count = ceil((_m.end_units - _m.start_units) / _units_per_beat);
		for (var _b = 1; _b <= _count; _b++) {
			array_push(_beats, {
				beat_uid: tune_uid_beat(_m.measure_uid, _b),
				measure_uid: _m.measure_uid,
				beat_index: _b,
				units_from_start: _m.start_units + (_b - 1) * _units_per_beat,
				weight: 1
			});
		}
	}

	_compiled[$ "beat_grid"] = {
		units_per_beat: _units_per_beat,
		beats_per_measure: _consts[$ "beats_per_measure"],
		units_per_measure: _consts[$ "units_per_measure"],
		beats: _beats
	};
}

/// @function tune_compile_stage_build_events(_ctx)
/// @description Stage 5: build L2 per voice with grid-reference UIDs. Ornaments are stored as
///              unexpanded attachments on their host note; components appear only at run time.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_events(_ctx) {
	var _parsed = _ctx[$ "parsed"];
	var _voices = _parsed[$ "voices"];
	var _consts = _parsed[$ "consts"];
	var _units_per_beat = _consts[$ "units_per_beat"];

	var _out = {};

	for (var _v = 0; _v < array_length(_voices); _v++) {
		var _voice = _voices[_v];
		var _name = _voice.voice_name;
		var _events = _voice.events;

		var _list = [];
		var _tracker = tune_uid_ordinal_tracker();
		var _pending = [];
		var _pending_broken_pair = undefined;

		for (var _i = 0; _i < array_length(_events); _i++) {
			var _e = _events[_i];

			if (_e.type == "embellishment") {
				var _pattern = string_replace_all(string_replace_all(_e.emb_literal, "{", ""), "}", "");
				array_push(_pending, { pattern: _pattern, anchor: 1 });
				continue;
			}
			if (_e.type != "note") continue;

			var _measure_uid = tune_uid_measure("1", _e.measure);
			var _units_into_beat = round(_e.total_units
				- (_e.total_units - (_e.division * _units_per_beat)));
			var _pos_key = tune_uid_event_position_key(_name, _measure_uid, _e.beat, _units_into_beat);
			var _ordinal = tune_uid_next_ordinal(_tracker, _pos_key);

			var _event_uid = tune_uid_event(_name, _measure_uid, _e.beat, _units_into_beat, _ordinal);
			var _event_rec = {
				event_uid: _event_uid,
				measure_uid: _measure_uid,
				beat_index: _e.beat,
				units_from_beat_start: _units_into_beat,
				ordinal: _ordinal,
				letter: _e.letter,
				written_units: _e.written,
				total_units: _e.total_units,
				has_ornament: (array_length(_pending) > 0),
				attachments: _pending
			};

			if (is_struct(_pending_broken_pair)) {
				_event_rec[$ "broken_pair_uid"] = _pending_broken_pair[$ "broken_pair_uid"];
				_event_rec[$ "broken_role"] = _pending_broken_pair[$ "second_role"];
				_event_rec[$ "broken_pair_total_units"] = _pending_broken_pair[$ "total_units"];
				_pending_broken_pair = undefined;
			}

			var _broken_dir = string(_e.broken_dir ?? "");
			if (_broken_dir != "" && (_i + 1) < array_length(_events) && _events[_i + 1].type == "note") {
				var _first_role = (_broken_dir == "dotcut") ? "long" : "short";
				var _second_role = (_broken_dir == "dotcut") ? "short" : "long";
				var _pair_total = real(_e.written) + real(_events[_i + 1].written);
				_event_rec[$ "broken_pair_uid"] = _event_uid;
				_event_rec[$ "broken_role"] = _first_role;
				_event_rec[$ "broken_pair_total_units"] = _pair_total;
				_pending_broken_pair = {
					broken_pair_uid: _event_uid,
					second_role: _second_role,
					total_units: _pair_total
				};
			}

			array_push(_list, _event_rec);
			_pending = [];
		}

		if (array_length(_pending) > 0) {
			tune_diagnostics_add(_ctx[$ "diagnostics"], TUNE_DIAG_WARNING, "ornament_no_host",
				string(array_length(_pending)) + " ornament(s) in voice '" + _name
				+ "' have no following note to attach to.");
		}

		variable_struct_set(_out, _name, _list);
	}

	_ctx[$ "compiled"][$ "events"] = _out;
}

/// @function tune_compile_stage_attach_annotations(_ctx)
/// @description Stage 6: attach L4 from tune meta and report re-keyed targets. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_attach_annotations(_ctx) { }

/// @function tune_compile_stage_stamp_provenance(_ctx)
/// @description Stage 7: stamp provenance onto the compiled tune.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_stamp_provenance(_ctx) {
	var _compiled = _ctx[$ "compiled"];
	_compiled[$ "provenance"] = tune_provenance_create(_ctx[$ "abc_text"], _ctx[$ "config"]);
}

/// @function tune_compile_stages()
/// @description The ordered compile stage list. Order is contractual — see §10.
/// @returns {array}  Array of {name, fn}
function tune_compile_stages() {
	return [
		{ name: "parse_abc",          fn: tune_compile_stage_parse_abc },
		{ name: "expand_repeats",     fn: tune_compile_stage_expand_repeats },
		{ name: "build_structure",    fn: tune_compile_stage_build_structure },
		{ name: "build_beat_grid",    fn: tune_compile_stage_build_beat_grid },
		{ name: "build_events",       fn: tune_compile_stage_build_events },
		{ name: "attach_annotations", fn: tune_compile_stage_attach_annotations },
		{ name: "stamp_provenance",   fn: tune_compile_stage_stamp_provenance }
	];
}

/// @function tune_compile(_abc_text, _tune_config, _tune_uid)
/// @description Run the compile stage list. Pure: same inputs produce the same layers.
///              Never runs during active playback — see contract invariant 13.
/// @param {string} _abc_text     ABC source text
/// @param {struct} _tune_config  Resolved tune configuration
/// @param {string} [_tune_uid]   Stable tune identity
/// @returns {struct}  {compiled, diagnostics, ok}
/// @reads   none
/// @writes  none
/// @objects none
/// @callers not yet wired; will be called from tune load
function tune_compile(_abc_text, _tune_config, _tune_uid = "") {
	var _ctx = tune_compile_context(_abc_text, _tune_config, _tune_uid);
	var _diagnostics = _ctx[$ "diagnostics"];
	var _stages = tune_compile_stages();

	for (var _i = 0; _i < array_length(_stages); _i++) {
		var _stage = _stages[_i];
		var _fn = _stage[$ "fn"];
		_fn(_ctx);
		if (tune_diagnostics_has_errors(_diagnostics)) break;
	}

	var _compiled = _ctx[$ "compiled"];
	tune_diagnostics_merge(_diagnostics, tune_compiled_validate(_compiled));

	return {
		compiled: _compiled,
		diagnostics: _diagnostics,
		ok: !tune_diagnostics_has_errors(_diagnostics)
	};
}

/// @function tune_compiled_voice_map(_compiled, _voice)
/// @description Return a view of one unexpanded voice from compiled L2 data.
/// @param {struct} _compiled  Compiled tune envelope
/// @param {string} _voice  Voice name to select
/// @returns {struct}  {voice, events, source} view over compiled events
function tune_compiled_voice_map(_compiled, _voice) {
	if (!is_struct(_compiled)) return { voice: "", events: [], source: "compiled.events", voice_kind: "unknown", applies_bagpipe_rules: false };
	var _events = _compiled[$ "events"];
	if (!is_struct(_events)) return { voice: "", events: [], source: "compiled.events", voice_kind: "unknown", applies_bagpipe_rules: false };

	var _selected = string(_voice);
	if (!variable_struct_exists(_events, _selected)) {
		var _voices = variable_struct_get_names(_events);
		_selected = (array_length(_voices) > 0) ? string(_voices[0]) : "";
	}
	var _list = (_selected != "") ? variable_struct_get(_events, _selected) : [];
	if (!is_array(_list)) _list = [];
	var _is_bagpipe = tune_voice_is_bagpipe(_selected);
	return {
		voice: _selected,
		events: _list,
		source: "compiled.events",
		voice_kind: _is_bagpipe ? "bagpipe" : "backing",
		applies_bagpipe_rules: _is_bagpipe
	};
}

/// @function tune_voice_is_bagpipe(_voice)
/// @description Identify voices that receive bagpipe rhythm and embellishment rules.
/// @param {string} _voice  Compiled voice name
/// @returns {bool} True for bagpipe voices, false for backing voices
function tune_voice_is_bagpipe(_voice) {
	var _name = string_lower(string(_voice));
	return string_pos("pipes_", _name) == 1
		|| _name == "melody"
		|| _name == "harmony1"
		|| _name == "harmony2"
		|| _name == "harmony3";
}

/// @function tune_voice_map_apply_rhythm(_voice_map, _pointing_profile)
/// @description Create an independent unit-space working view for one voice.
///              The identity rule preserves compiled L2 until rhythm rules are configured.
/// @param {struct} _voice_map  Compiled voice-map view
/// @param {struct} _pointing_profile  Resolved pointing profile
/// @returns {struct}  Per-run voice map with copied events
function tune_voice_map_apply_rhythm(_voice_map, _pointing_profile) {
	var _source = is_struct(_voice_map) ? _voice_map[$ "events"] : [];
	var _working = [];
	for (var _i = 0; _i < array_length(_source); _i++) {
		var _source_event = _source[_i];
		var _event_copy = {};
		if (is_struct(_source_event)) {
			var _fields = variable_struct_get_names(_source_event);
			for (var _f = 0; _f < array_length(_fields); _f++) {
				var _field = _fields[_f];
				variable_struct_set(_event_copy, _field, variable_struct_get(_source_event, _field));
			}
		}
		array_push(_working, _event_copy);
	}

	var _result = {};
	if (is_struct(_voice_map)) {
		var _map_fields = variable_struct_get_names(_voice_map);
		for (var _m = 0; _m < array_length(_map_fields); _m++) {
			var _map_field = _map_fields[_m];
			variable_struct_set(_result, _map_field, variable_struct_get(_voice_map, _map_field));
		}
	}
	variable_struct_set(_result, "events", _working);
	var _pointing_id = is_struct(_pointing_profile) ? string(_pointing_profile[$ "pointing_id"] ?? "written") : "written";
	variable_struct_set(_result, "pointing_id", _pointing_id);
	variable_struct_set(_result, "source_events", _source);

	if (bool(_result[$ "applies_bagpipe_rules"] ?? false)
		&& is_struct(_pointing_profile)
		&& string(_pointing_profile[$ "mode"] ?? "written") == "ratio") {
		var _long_share = max(0, real(_pointing_profile[$ "long_share"] ?? 1.67));
		var _short_share = max(0, real(_pointing_profile[$ "short_share"] ?? 0.33));
		var _share_total = _long_share + _short_share;
		if (_share_total > 0) {
			for (var _p = 0; _p + 1 < array_length(_working); _p++) {
				var _first = _working[_p];
				var _second = _working[_p + 1];
				var _pair_uid = string(_first[$ "broken_pair_uid"] ?? "");
				if (_pair_uid == "" || string(_second[$ "broken_pair_uid"] ?? "") != _pair_uid) continue;

				var _pair_units = real(_first[$ "broken_pair_total_units"] ?? 0);
				if (_pair_units <= 0) continue;
				var _long_units = _pair_units * _long_share / _share_total;
				var _short_units = _pair_units - _long_units;
				var _first_units = (string(_first[$ "broken_role"] ?? "") == "long") ? _long_units : _short_units;
				var _second_units = _pair_units - _first_units;
				_first[$ "written_units"] = _first_units;
				_second[$ "written_units"] = _second_units;
				_second[$ "total_units"] = real(_first[$ "total_units"]) + _first_units;
				_p += 1;
			}
		}
	}
	return _result;
}

/// @function tune_rhythm_registry_load()
/// @description Load the packaged rhythm profile registry, with safe built-in fallbacks.
/// @returns {struct} Rhythm profile registry
function tune_rhythm_registry_load() {
	var _fallback = {
		pointing_profiles: [
			{ pointing_id: "written", mode: "written" },
			{ pointing_id: "pointed_default", mode: "ratio", long_share: 1.67, short_share: 0.33 }
		],
		pulse_profiles: [],
		grouping_profiles: [],
		defaults: { pointing_id: "written", pulse_by_meter: {} }
	};
	var _paths = [
		scr_data_paths_get_content_root() + "config/rhythm_rules.json",
		working_directory + "datafiles/config/rhythm_rules.json",
		"datafiles/config/rhythm_rules.json"
	];
	for (var _i = 0; _i < array_length(_paths); _i++) {
		if (!file_exists(_paths[_i])) continue;
		var _loaded = scr_tune_parse_json_file(_paths[_i]);
		if (is_struct(_loaded)) return _loaded;
	}
	return _fallback;
}

/// @function tune_rhythm_profile_find(_profiles, _id, _id_field)
/// @description Find a named profile in a registry array.
/// @param {array} _profiles  Profile records
/// @param {string} _id  Requested identifier
/// @param {string} _id_field  Identifier field name
/// @returns {struct|undefined} Matching profile
function tune_rhythm_profile_find(_profiles, _id, _id_field) {
	for (var _i = 0; _i < array_length(_profiles); _i++) {
		var _profile = _profiles[_i];
		if (is_struct(_profile) && string(_profile[$ _id_field] ?? "") == string(_id)) return _profile;
	}
	return undefined;
}

/// @function tune_pulse_normalize(_profile, _meter)
/// @description Validate pulse meter/slot count and normalize weights to preserve measure length.
/// @param {struct} _profile  Pulse profile
/// @param {string} _meter  Normalized tune meter
/// @returns {struct|undefined} Copied profile with normalized_weights, or undefined when incompatible
function tune_pulse_normalize(_profile, _meter) {
	if (!is_struct(_profile)) return undefined;
	var _meter_norm = timing_normalize_time_sig(string(_meter));
	if (timing_normalize_time_sig(string(_profile[$ "meter"] ?? "")) != _meter_norm) return undefined;
	var _parts = string_split(_meter_norm, "/");
	if (array_length(_parts) != 2) return undefined;
	var _beats = floor(real(_parts[0]));
	var _subdivision = max(1, floor(real(_profile[$ "subdivision"] ?? 1)));
	var _weights = _profile[$ "weights"];
	var _slot_count = _beats * _subdivision;
	if (!is_array(_weights) || array_length(_weights) != _slot_count) return undefined;

	var _sum = 0;
	for (var _i = 0; _i < array_length(_weights); _i++) _sum += max(0, real(_weights[_i]));
	if (_sum <= 0) return undefined;
	var _normalized = [];
	for (var _i = 0; _i < array_length(_weights); _i++) {
		array_push(_normalized, max(0, real(_weights[_i])) * _slot_count / _sum);
	}

	var _copy = {};
	var _fields = variable_struct_get_names(_profile);
	for (var _f = 0; _f < array_length(_fields); _f++) {
		var _field = _fields[_f];
		variable_struct_set(_copy, _field, variable_struct_get(_profile, _field));
	}
	_copy[$ "normalized_weights"] = _normalized;
	_copy[$ "subdivision"] = _subdivision;
	return _copy;
}

/// @function tune_rhythm_resolve(_registry, _meter, _config)
/// @description Resolve pointing and meter-compatible pulse profiles with safe defaults.
/// @param {struct} _registry  Rhythm registry
/// @param {string} _meter  Tune meter
/// @param {struct} _config  Run overrides
/// @returns {struct} {pointing, pulse, pointing_id, pulse_id}
function tune_rhythm_resolve(_registry, _meter, _config) {
	var _meter_norm = timing_normalize_time_sig(string(_meter));
	var _defaults = _registry[$ "defaults"];
	var _pointing_id = string(_config[$ "pointing_id"] ?? _defaults[$ "pointing_id"] ?? "written");
	var _pointing = tune_rhythm_profile_find(_registry[$ "pointing_profiles"], _pointing_id, "pointing_id");
	if (!is_struct(_pointing)) {
		_pointing_id = "written";
		_pointing = tune_rhythm_profile_find(_registry[$ "pointing_profiles"], _pointing_id, "pointing_id");
	}

	var _pulse_id = string(_config[$ "pulse_id"] ?? "");
	var _pulse_defaults = _defaults[$ "pulse_by_meter"];
	if (_pulse_id == "" && is_struct(_pulse_defaults) && variable_struct_exists(_pulse_defaults, _meter_norm)) {
		_pulse_id = string(variable_struct_get(_pulse_defaults, _meter_norm));
	}
	var _pulse = tune_pulse_normalize(
		tune_rhythm_profile_find(_registry[$ "pulse_profiles"], _pulse_id, "pulse_id"),
		_meter_norm
	);
	if (!is_struct(_pulse)) _pulse_id = "";
	return { pointing: _pointing, pulse: _pulse, pointing_id: _pointing_id, pulse_id: _pulse_id };
}

/// @function run_build_warp_units(_compiled, _pulse, _absolute_units)
/// @description Apply a normalized pulse profile within one measure while preserving its boundaries.
/// @param {struct} _compiled  Compiled tune
/// @param {struct|undefined} _pulse  Normalized pulse profile
/// @param {real} _absolute_units  Absolute tune-unit position
/// @returns {real} Warped absolute tune-unit position
function run_build_warp_units(_compiled, _pulse, _absolute_units) {
	if (!is_struct(_pulse)) return real(_absolute_units);
	var _structure = _compiled[$ "structure"];
	var _measures = is_struct(_structure) ? _structure[$ "measures"] : [];
	var _measure = undefined;
	var _units = real(_absolute_units);
	for (var _i = 0; _i < array_length(_measures); _i++) {
		var _candidate = _measures[_i];
		if (_units >= real(_candidate[$ "start_units"]) - 0.0001
			&& _units <= real(_candidate[$ "end_units"]) + 0.0001) {
			_measure = _candidate;
			break;
		}
	}
	if (!is_struct(_measure)) return _units;

	var _start = real(_measure[$ "start_units"]);
	var _length = real(_measure[$ "end_units"]) - _start;
	if (_length <= 0) return _units;
	var _x = clamp(_units - _start, 0, _length);
	var _grid = _compiled[$ "beat_grid"];
	var _units_per_beat = real(_grid[$ "units_per_beat"] ?? 0);
	var _subdivision = max(1, real(_pulse[$ "subdivision"] ?? 1));
	var _slot_units = _units_per_beat / _subdivision;
	var _weights = _pulse[$ "normalized_weights"];
	if (_slot_units <= 0 || !is_array(_weights) || array_length(_weights) == 0) return _units;

	var _weighted_total = 0;
	var _weighted_x = 0;
	var _position = 0;
	var _slot = 0;
	while (_position < _length - 0.0001) {
		var _segment = min(_slot_units, _length - _position);
		var _weight = real(_weights[_slot mod array_length(_weights)]);
		_weighted_total += _segment * _weight;
		if (_x > _position) _weighted_x += min(_segment, _x - _position) * _weight;
		_position += _segment;
		_slot += 1;
	}
	if (_weighted_total <= 0) return _units;
	return _start + _weighted_x * _length / _weighted_total;
}

/// @function tune_compiled_melody_map(_compiled)
/// @description Return the primary melody voice view over unexpanded compiled L2 events.
/// @param {struct} _compiled  Compiled tune envelope
/// @returns {struct}  {voice, events, source} view over compiled events
function tune_compiled_melody_map(_compiled) {
	return tune_compiled_voice_map(_compiled, "pipes_melody");
}

// ---------------------------------------------------------------------------
// run_build stages (§10) — per play, never stored
// ---------------------------------------------------------------------------

/// @function run_build_stage_resolve_config(_ctx)
/// @description Stage 1: resolve BPM, unit duration and MIDI base settings for a compiled tune.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_resolve_config(_ctx) {
	var _compiled = _ctx[$ "compiled"];
	var _config = _ctx[$ "config"];
	var _bpm = real(_config[$ "bpm"] ?? _compiled[$ "tempo_default"] ?? 120);
	if (_bpm <= 0) _bpm = 120;
	var _meter = string(_compiled[$ "meter"] ?? "4/4");
	var _quarter_bpm = tune_get_effective_quarter_bpm(_bpm, _meter);
	var _unit_multiplier = tune_note_fraction_to_quarter_multiplier(_compiled[$ "unit_note_length"] ?? "1/8");
	if (_unit_multiplier <= 0) _unit_multiplier = 0.5;
	var _resolved = {
		bpm: _bpm,
		meter: _meter,
		unit_ms: (60000 / _quarter_bpm) * _unit_multiplier,
		base_midi: real(_config[$ "base_midi"] ?? 55),
		default_channel: real(_config[$ "default_channel"] ?? 2),
		gracenote_override_ms: real(_config[$ "gracenote_override_ms"] ?? 0)
	};
	var _registry = tune_rhythm_registry_load();
	var _rhythm = tune_rhythm_resolve(_registry, _meter, _config);
	_resolved[$ "rhythm"] = _rhythm;
	_ctx[$ "resolved"] = _resolved;
}

/// @function run_build_stage_apply_rhythm_rules(_ctx)
/// @description Stage 2: apply unit-space rhythm rules. The initial rule is identity.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_apply_rhythm_rules(_ctx) {
	var _compiled = _ctx[$ "compiled"];
	_ctx[$ "melody_map"] = tune_compiled_melody_map(_compiled);
	var _rhythm = _ctx[$ "resolved"][$ "rhythm"];
	var _pointing = _rhythm[$ "pointing"];
	var _voice_maps = {};
	var _voice_names = variable_struct_get_names(_compiled[$ "events"]);
	for (var _v = 0; _v < array_length(_voice_names); _v++) {
		var _voice_name = _voice_names[_v];
		var _compiled_map = tune_compiled_voice_map(_compiled, _voice_name);
		variable_struct_set(_voice_maps, _voice_name, tune_voice_map_apply_rhythm(_compiled_map, _pointing));
	}
	_ctx[$ "voice_maps"] = _voice_maps;
	var _working_events = {};
	for (var _v = 0; _v < array_length(_voice_names); _v++) {
		var _name = _voice_names[_v];
		var _map = variable_struct_get(_voice_maps, _name);
		variable_struct_set(_working_events, _name, _map[$ "events"]);
	}
	_ctx[$ "unit_events"] = _working_events;
	_ctx[$ "resolved_pointing_id"] = _rhythm[$ "pointing_id"];
	_ctx[$ "resolved_pulse_id"] = _rhythm[$ "pulse_id"];
}

/// @function run_build_stage_compose_performance(_ctx)
/// @description Stage 3: flatten the compiled voice streams into one performance input.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_compose_performance(_ctx) {
	var _voices = _ctx[$ "unit_events"];
	var _flat = [];
	var _names = variable_struct_get_names(_voices);
	for (var _v = 0; _v < array_length(_names); _v++) {
		var _voice = _names[_v];
		var _list = variable_struct_get(_voices, _voice);
		for (var _i = 0; _i < array_length(_list); _i++) {
			array_push(_flat, { voice: _voice, event: _list[_i] });
		}
	}
	_ctx[$ "composed"] = _flat;
}

/// @function run_build_stage_project_to_ms(_ctx)
/// @description Stage 4: project unit-space events onto milliseconds and emit scheduler events.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_project_to_ms(_ctx) {
	var _resolved = _ctx[$ "resolved"];
	var _compiled = _ctx[$ "compiled"];
	var _pulse = _resolved[$ "rhythm"][$ "pulse"];
	var _out = [];
	var _composed = _ctx[$ "composed"];
	for (var _i = 0; _i < array_length(_composed); _i++) {
		var _row = _composed[_i];
		var _voice = string(_row[$ "voice"]);
		var _event = _row[$ "event"];
		var _start_units = real(_event[$ "total_units"]);
		var _end_units = _start_units + real(_event[$ "written_units"]);
		var _start_ms = run_build_warp_units(_compiled, _pulse, _start_units) * _resolved[$ "unit_ms"];
		var _end_ms = run_build_warp_units(_compiled, _pulse, _end_units) * _resolved[$ "unit_ms"];
		var _duration_ms = max(_end_ms - _start_ms, 1);
		var _channel = run_build_voice_channel(_voice, _resolved[$ "default_channel"]);
		var _parsed = tune_uid_parse_event(_event[$ "event_uid"]);
		var _measure = is_struct(_parsed) ? real(_parsed[$ "expanded_index"]) : 0;
		var _beat = is_struct(_parsed) ? real(_parsed[$ "beat_index"]) : 0;
		var _division = is_struct(_parsed) ? real(_parsed[$ "units_from_beat_start"]) : 0;
		var _note = tune_note_letter_to_midi(_event[$ "letter"], _resolved[$ "base_midi"]);
		var _event_uid = string(_event[$ "event_uid"]);
		var _event_id = _i + 1;
		array_push(_out, {
			time: _start_ms, type: "note_on", note: _note, velocity: 80,
			channel: _channel, part: _channel - 1, measure: _measure, beat: _beat,
			beat_fraction: _division, is_embellishment: false, event_id: _event_id,
			event_uid: _event_uid, voice: _voice, attachments: _event[$ "attachments"]
		});
		array_push(_out, {
			time: _start_ms + _duration_ms, type: "note_off", note: _note, velocity: 0,
			channel: _channel, part: _channel - 1, measure: _measure, beat: _beat,
			beat_fraction: _division, is_embellishment: false, event_id: _event_id,
			event_uid: _event_uid, voice: _voice
		});
	}
	_ctx[$ "projected"] = _out;
}

/// @function run_build_voice_channel(_voice, _default_channel)
/// @description Map a compiled voice name to its playback MIDI channel.
/// @param {string} _voice  Compiled voice name
/// @param {real} _default_channel  Fallback MIDI channel
/// @returns {real} MIDI channel
function run_build_voice_channel(_voice, _default_channel) {
	var _name = string_lower(string(_voice));
	if (_name == "pipes_melody") return 2;
	if (_name == "pipes_harmony1") return 3;
	if (_name == "pipes_harmony2") return 4;
	if (_name == "pipes_harmony3") return 5;
	if (_name == "snare" || _name == "drums") return 9;
	return _default_channel;
}

/// @function run_build_stage_apply_timing_map(_ctx)
/// @description Stage 5: apply the expressive timing map. Deferred; intentionally a no-op.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_apply_timing_map(_ctx) { }

/// @function run_build_stage_resolve_embellishments(_ctx)
/// @description Stage 6: expand attachments against final host ms and declared anchor.
///              Numeric anchors and lead placement are supported; trail awaits a test tune.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_resolve_embellishments(_ctx) {
	var _events = _ctx[$ "projected"];
	var _resolved = _ctx[$ "resolved"];
	var _extra = [];
	var _previous_off_by_voice = {};
	var _component_serial = array_length(_events) + 1;
	var _expanded_count = 0;
	var _missing_count = 0;
	var _trail_count = 0;

	for (var _i = 0; _i + 1 < array_length(_events); _i += 2) {
		var _host_on = _events[_i];
		var _host_off = _events[_i + 1];
		if (string(_host_on[$ "type"] ?? "") != "note_on") continue;
		var _voice = string(_host_on[$ "voice"] ?? "");
		var _attachments = _host_on[$ "attachments"];
		if (!is_array(_attachments) || array_length(_attachments) == 0 || !tune_voice_is_bagpipe(_voice)) {
			variable_struct_set(_previous_off_by_voice, _voice, _host_off);
			continue;
		}

		for (var _a = 0; _a < array_length(_attachments); _a++) {
			var _attachment = _attachments[_a];
			var _pattern = is_struct(_attachment) ? string(_attachment[$ "pattern"] ?? "") : "";
			var _definition = find_embellishment(global.emb_library, _pattern, string(_ctx[$ "composed"][_i div 2][$ "event"][$ "letter"]), 0, "");
			if (!is_struct(_definition)) {
				_missing_count += 1;
				show_debug_message("[EMB] ERROR missing definition pattern=" + _pattern
					+ " target=" + string(_ctx[$ "composed"][_i div 2][$ "event"][$ "letter"])
					+ " voice=" + _voice + " host=" + string(_host_on[$ "event_uid"]));
				continue;
			}

			var _notes_text = string(_definition[$ "notes"] ?? "");
			var _component_count = array_length(string_split(_notes_text, ","));
			var _legacy_anchor = floor(real(_definition[$ "anchor_index"] ?? 1));
			var _anchor = (_legacy_anchor > _component_count) ? TUNE_ANCHOR_LEAD : max(1, _legacy_anchor);
			if (is_struct(_attachment) && variable_struct_exists(_attachment, "alt_anchor")) {
				_anchor = _attachment[$ "alt_anchor"];
			}
			if (is_string(_anchor) && string_lower(string(_anchor)) == TUNE_ANCHOR_TRAIL) {
				_trail_count += 1;
				show_debug_message("[EMB] ERROR trail anchor deferred pattern=" + _pattern
					+ " voice=" + _voice + " host=" + string(_host_on[$ "event_uid"]));
				continue;
			}

			var _host_start = real(_host_on[$ "time"]);
			var _host_end = real(_host_off[$ "time"]);
			var _host_duration = max(1, _host_end - _host_start);
			var _previous_off = variable_struct_exists(_previous_off_by_voice, _voice)
				? variable_struct_get(_previous_off_by_voice, _voice) : undefined;
			var _previous_duration = _resolved[$ "unit_ms"];
			if (is_struct(_previous_off)) _previous_duration = max(1, _host_start - real(_previous_off[$ "time"]) + _resolved[$ "unit_ms"]);
			var _components = embellishment_to_notes(_definition, _host_duration, _previous_duration,
				_resolved[$ "bpm"], _resolved[$ "gracenote_override_ms"]);

			var _anchor_index = is_string(_anchor) ? array_length(_components) : clamp(floor(real(_anchor)) - 1, 0, max(0, array_length(_components) - 1));
			var _before_ms = 0;
			var _after_ms = 0;
			for (var _c = 0; _c < array_length(_components); _c++) {
				if (_c < _anchor_index) _before_ms += real(_components[_c][$ "duration_ms"]);
				else _after_ms += real(_components[_c][$ "duration_ms"]);
			}
			var _component_time = _host_start - _before_ms;
			if (_before_ms > 0 && is_struct(_previous_off)) {
				_previous_off[$ "time"] = min(real(_previous_off[$ "time"]), _component_time);
			}
			_host_on[$ "time"] = _host_start + _after_ms;

			for (var _c = 0; _c < array_length(_components); _c++) {
				var _component = _components[_c];
				var _duration = max(1, real(_component[$ "duration_ms"]));
				var _component_uid = tune_uid_component(string(_host_on[$ "event_uid"]), _anchor, _c + 1);
				var _component_id = _component_serial;
				_component_serial += 1;
				var _component_note = tune_note_letter_to_midi(_component[$ "note"], _resolved[$ "base_midi"]);
				array_push(_extra, {
					time: _component_time, type: "note_on", note: _component_note, velocity: 70,
					channel: _host_on[$ "channel"], part: _host_on[$ "part"], measure: _host_on[$ "measure"],
					beat: _host_on[$ "beat"], beat_fraction: _host_on[$ "beat_fraction"],
					is_embellishment: true, event_id: _component_id, event_uid: _component_uid,
					host_event_uid: _host_on[$ "event_uid"], voice: _voice
				});
				array_push(_extra, {
					time: _component_time + _duration, type: "note_off", note: _component_note, velocity: 0,
					channel: _host_on[$ "channel"], part: _host_on[$ "part"], measure: _host_on[$ "measure"],
					beat: _host_on[$ "beat"], beat_fraction: _host_on[$ "beat_fraction"],
					is_embellishment: true, event_id: _component_id, event_uid: _component_uid,
					host_event_uid: _host_on[$ "event_uid"], voice: _voice
				});
				_component_time += _duration;
			}
			_expanded_count += 1;
		}
		variable_struct_set(_previous_off_by_voice, _voice, _host_off);
	}

	if (_missing_count > 0 || _trail_count > 0) {
		_ctx[$ "projected"] = [];
	} else {
		for (var _x = 0; _x < array_length(_extra); _x++) array_push(_events, _extra[_x]);
		_ctx[$ "projected"] = _events;
	}
	show_debug_message("[EMB] expanded=" + string(_expanded_count)
		+ " missing=" + string(_missing_count) + " trail_deferred=" + string(_trail_count));
}

/// @function run_build_stage_emit_run_events(_ctx)
/// @description Stage 7: assign MIDI channels and emit the ordered run event list. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_emit_run_events(_ctx) {
	array_sort(_ctx[$ "projected"], function(a, b) {
		var _time_diff = real(a[$ "time"] ?? 0) - real(b[$ "time"] ?? 0);
		if (_time_diff != 0) return _time_diff;
		if (string(a[$ "type"] ?? "") == "note_off" && string(b[$ "type"] ?? "") != "note_off") return -1;
		if (string(b[$ "type"] ?? "") == "note_off" && string(a[$ "type"] ?? "") != "note_off") return 1;
		return real(a[$ "event_id"] ?? 0) - real(b[$ "event_id"] ?? 0);
	});
}

/// @function run_build(_compiled, _run_config)
/// @description Build the first playable run projection from a compiled tune. Rhythm maps and
///              ornament expansion remain identity/deferred until their dedicated stages land.
/// @param {struct} _compiled  Compiled tune envelope
/// @param {struct} [_run_config]  Player/run overrides such as bpm and base_midi
/// @returns {array} Scheduler-compatible note events
function run_build(_compiled, _run_config = {}) {
	var _ctx = {
		compiled: _compiled,
		config: is_struct(_run_config) ? _run_config : {},
		resolved: undefined,
		unit_events: {},
		voice_maps: {},
		composed: [],
		projected: []
	};
	var _stages = run_build_stages();
	for (var _i = 0; _i < array_length(_stages); _i++) {
		_stages[_i][$ "fn"](_ctx);
	}
	show_debug_message("[RHYTHM] pointing=" + string(_ctx[$ "resolved_pointing_id"] ?? "written")
		+ " pulse=" + string(_ctx[$ "resolved_pulse_id"] ?? "none")
		+ " meter=" + string(_ctx[$ "resolved"][$ "meter"] ?? "")
		+ " events=" + string(array_length(_ctx[$ "projected"])));
	return _ctx[$ "projected"];
}

/// @function run_build_stages()
/// @description The ordered run-build stage list. Order is contractual — see §10.
/// @returns {array}  Array of {name, fn}
function run_build_stages() {
	return [
		{ name: "resolve_config",         fn: run_build_stage_resolve_config },
		{ name: "apply_rhythm_rules",     fn: run_build_stage_apply_rhythm_rules },
		{ name: "compose_performance",    fn: run_build_stage_compose_performance },
		{ name: "project_to_ms",          fn: run_build_stage_project_to_ms },
		{ name: "apply_timing_map",       fn: run_build_stage_apply_timing_map },
		{ name: "resolve_embellishments", fn: run_build_stage_resolve_embellishments },
		{ name: "emit_run_events",        fn: run_build_stage_emit_run_events }
	];
}

// ---------------------------------------------------------------------------
// Validation — the acceptance gate for every later phase
// ---------------------------------------------------------------------------

/// @function tune_compiled_validate(_compiled)
/// @description Check a compiled tune against the contract. Tolerates empty layers so that
///              stub compiles pass; reports structural violations once layers are populated.
/// @param {struct} _compiled  Compiled tune
/// @returns {struct}  Diagnostics collector describing any violations
function tune_compiled_validate(_compiled) {
	var _d = tune_diagnostics_create();

	if (!is_struct(_compiled)) {
		tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "compiled_not_struct", "Compiled tune is not a struct.");
		return _d;
	}

	var _required = ["schema_version", "tune_uid", "structure", "beat_grid", "events", "annotations"];
	for (var _i = 0; _i < array_length(_required); _i++) {
		if (!variable_struct_exists(_compiled, _required[_i])) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "compiled_missing_field",
				"Compiled tune is missing required field '" + _required[_i] + "'.");
		}
	}
	if (tune_diagnostics_has_errors(_d)) return _d;

	if (real(_compiled[$ "schema_version"]) != TUNE_PIPELINE_SCHEMA_VERSION) {
		tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "schema_version_mismatch",
			"Compiled schema_version " + string(_compiled[$ "schema_version"])
			+ " does not match compiler version " + string(TUNE_PIPELINE_SCHEMA_VERSION) + ".");
	}

	tune_compiled_validate_measures(_compiled, _d);
	tune_compiled_validate_events(_compiled, _d);
	tune_compiled_validate_annotations(_compiled, _d);

	return _d;
}

/// @function tune_compiled_validate_measures(_compiled, _d)
/// @description Check measure uid uniqueness and pickup beat-budget pairing in L0.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_measures(_compiled, _d) {
	var _structure = _compiled[$ "structure"];
	if (!is_struct(_structure)) return;

	var _measures = _structure[$ "measures"];
	if (!is_array(_measures)) return;

	var _seen = {};
	for (var _i = 0; _i < array_length(_measures); _i++) {
		var _m = _measures[_i];
		if (!is_struct(_m) || !variable_struct_exists(_m, "measure_uid")) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "measure_missing_uid",
				"Measure at index " + string(_i) + " has no measure_uid.");
			continue;
		}

		var _uid = string(_m[$ "measure_uid"]);
		if (variable_struct_exists(_seen, _uid)) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "measure_uid_duplicate",
				"Duplicate measure_uid.", { measure_uid: _uid });
		}
		variable_struct_set(_seen, _uid, true);

		// A pickup measure must name the measure that completes its beat budget.
		var _role = string(_m[$ "pickup_role"] ?? "none");
		if (_role == "pickup_head" || _role == "pickup_complement") {
			if (string(_m[$ "complement_uid"] ?? "") == "") {
				tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "pickup_missing_complement",
					"Measure has pickup_role '" + _role + "' but no complement_uid.",
					{ measure_uid: _uid });
			}
		}
	}
}

/// @function tune_compiled_validate_events(_compiled, _d)
/// @description Check event uid uniqueness per voice and that voices are declared in L2.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_events(_compiled, _d) {
	var _events = _compiled[$ "events"];
	if (!is_struct(_events)) return;

	var _voices = variable_struct_get_names(_events);
	for (var _v = 0; _v < array_length(_voices); _v++) {
		var _voice = _voices[_v];
		var _list = variable_struct_get(_events, _voice);
		if (!is_array(_list)) continue;

		var _seen = {};
		for (var _i = 0; _i < array_length(_list); _i++) {
			var _e = _list[_i];
			if (!is_struct(_e) || !variable_struct_exists(_e, "event_uid")) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_missing_uid",
					"Event at index " + string(_i) + " in voice '" + _voice + "' has no event_uid.");
				continue;
			}

			var _uid = string(_e[$ "event_uid"]);
			if (variable_struct_exists(_seen, _uid)) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_uid_duplicate",
					"Duplicate event_uid; ordinals must disambiguate simultaneous events.",
					{ event_uid: _uid });
			}
			variable_struct_set(_seen, _uid, true);

			if (is_undefined(tune_uid_parse_event(_uid))) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_uid_malformed",
					"event_uid does not parse as a grid reference.", { event_uid: _uid });
			}

			// Components are generated at run_build stage 6 and must not be stored.
			if (variable_struct_exists(_e, "components")) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_has_components",
					"Compiled events store ornament attachments, not expanded components.",
					{ event_uid: _uid });
			}
		}
	}
}

/// @function tune_compiled_validate_annotations(_compiled, _d)
/// @description Check that every annotation targets a grid reference that exists.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_annotations(_compiled, _d) {
	var _annotations = _compiled[$ "annotations"];
	if (!is_array(_annotations)) return;

	for (var _i = 0; _i < array_length(_annotations); _i++) {
		var _a = _annotations[_i];
		var _t = is_struct(_a) ? _a[$ "target"] : undefined;
		if (!is_struct(_t)) {
			tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "annotation_no_target",
				"Annotation at index " + string(_i) + " has no target.");
			continue;
		}

		var _has = variable_struct_exists(_t, "measure_uid")
			|| variable_struct_exists(_t, "beat_uid")
			|| variable_struct_exists(_t, "event_uid");
		if (!_has) {
			tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "annotation_target_empty",
				"Annotation target names no measure, beat or event.");
		}
	}
}
