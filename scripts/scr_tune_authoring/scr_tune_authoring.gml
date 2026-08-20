// Minimal "create a new tune" workflow: ABC text in, tune folder out.
// See TUNE_PIPELINE_CONTRACT.md §7. This is the authoring path that replaces the Excel export.
//
// Not yet wired to playback: run_build (ms projection, ornament expansion) is still stubbed,
// so a tune created here compiles and validates but does not play. Legacy `<Tune>.json` and
// `score/` are therefore left untouched — they are what the current runtime plays.

#macro TUNE_STAGING_FOLDER "_incoming"

/// @function tune_author_slug(_title)
/// @description Turn a tune title into a folder-safe name.
/// @param {string} _title  Tune title
/// @returns {string}  Folder name
function tune_author_slug(_title) {
	var _s = string_trim(string(_title));
	var _bad = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"];
	for (var _i = 0; _i < array_length(_bad); _i++) {
		_s = string_replace_all(_s, _bad[_i], "");
	}
	return string_trim(_s);
}

/// @function tune_author_write_text(_path, _text)
/// @description Write a text file, replacing any existing content.
/// @param {string} _path  Destination path
/// @param {string} _text  File contents
/// @returns {bool}  True on success
function tune_author_write_text(_path, _text) {
	var _f = file_text_open_write(_path);
	if (_f < 0) return false;
	file_text_write_string(_f, string(_text));
	file_text_close(_f);
	return true;
}

/// @function tune_author_index_entry(_compiled, _diag)
/// @description Build the tune_library index row for a compiled tune.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _diag      Diagnostics from the compile
/// @returns {struct}  Index entry
function tune_author_index_entry(_compiled, _diag) {
	var _structure = _compiled[$ "structure"];
	var _measures = _structure[$ "measures"];
	var _has_pickup = false;
	for (var _i = 0; _i < array_length(_measures); _i++) {
		if (_measures[_i].pickup_role == "pickup_head") { _has_pickup = true; break; }
	}

	var _counts = _diag[$ "counts"];
	return {
		tune_uid: string(_compiled[$ "tune_uid"]),
		title: string(_compiled[$ "title"]),
		composer: string(_compiled[$ "composer"]),
		rhythm_type: string(_compiled[$ "rhythm_type"]),
		meter: string(_compiled[$ "meter"]),
		measures_total: array_length(_measures),
		voices: _compiled[$ "voices"],
		has_pickup: _has_pickup,
		tempo_default: real(_compiled[$ "tempo_default"]),
		tags: [],
		compiled_ok: !tune_diagnostics_has_errors(_diag),
		diagnostic_counts: {
			error: real(_counts[$ "error"]),
			warning: real(_counts[$ "warning"]),
			info: real(_counts[$ "info"])
		}
	};
}

/// @function tune_author_log_summary(_compiled)
/// @description Print a human-readable structure summary of a compiled tune.
/// @param {struct} _compiled  Compiled tune
/// @returns {undefined}
function tune_author_log_summary(_compiled) {
	var _structure = _compiled[$ "structure"];
	var _measures = _structure[$ "measures"];
	var _grid = _compiled[$ "beat_grid"];
	var _events = _compiled[$ "events"];

	show_debug_message("[TUNE] \"" + string(_compiled[$ "title"]) + "\""
		+ "  meter=" + string(_compiled[$ "meter"])
		+ "  L=" + string(_compiled[$ "unit_note_length"])
		+ "  Q=" + string(_compiled[$ "tempo_default"]));
	show_debug_message("[TUNE] measures=" + string(array_length(_measures))
		+ "  beats=" + string(array_length(_grid[$ "beats"]))
		+ "  units/beat=" + string(_grid[$ "units_per_beat"]));

	var _voices = variable_struct_get_names(_events);
	for (var _v = 0; _v < array_length(_voices); _v++) {
		var _list = variable_struct_get(_events, _voices[_v]);
		var _orn = 0;
		for (var _i = 0; _i < array_length(_list); _i++) {
			if (_list[_i].has_ornament) _orn += 1;
		}
		show_debug_message("[TUNE]   voice " + _voices[_v]
			+ ": " + string(array_length(_list)) + " notes, "
			+ string(_orn) + " ornamented");
	}

	for (var _i = 0; _i < min(4, array_length(_measures)); _i++) {
		var _m = _measures[_i];
		show_debug_message("[TUNE]   " + _m.measure_uid
			+ "  beats=" + string(_m.actual_beats) + "/" + string(_m.expected_beats)
			+ ((_m.pickup_role != "none") ? ("  " + _m.pickup_role + " <-> " + _m.complement_uid) : ""));
	}
	if (array_length(_measures) > 4) show_debug_message("[TUNE]   …");
}

/// @function tune_author_log_compiled_detail(_compiled)
/// @description Dump the loaded tune's L0 measures, L1 beats and unexpanded L2 voice events.
/// @param {struct} _compiled  Compiled tune envelope
/// @returns {undefined}
/// @reads compiled tune layers
/// @writes debug output only
/// @objects none
/// @callers manual (dev key V)
function tune_author_log_compiled_detail(_compiled) {
	if (!is_struct(_compiled)) {
		show_debug_message("[TUNE-DETAIL] no compiled tune loaded");
		return;
	}

	var _structure = _compiled[$ "structure"];
	var _measures = is_struct(_structure) ? _structure[$ "measures"] : [];
	var _grid = _compiled[$ "beat_grid"];
	var _beats = is_struct(_grid) ? _grid[$ "beats"] : [];
	var _events = _compiled[$ "events"];

	show_debug_message("[TUNE-DETAIL] " + string(_compiled[$ "title"] ?? "")
		+ " uid=" + string(_compiled[$ "tune_uid"] ?? "")
		+ " measures=" + string(array_length(_measures))
		+ " beats=" + string(array_length(_beats)));
	show_debug_message("[TUNE-DETAIL] L0 STRUCTURE");
	for (var _m = 0; _m < array_length(_measures); _m++) {
		var _measure = _measures[_m];
		show_debug_message("[TUNE-DETAIL] M " + string(_measure[$ "measure_uid"])
			+ " start=" + string(_measure[$ "start_units"])
			+ " end=" + string(_measure[$ "end_units"])
			+ " beats=" + string(_measure[$ "actual_beats"]) + "/" + string(_measure[$ "expected_beats"])
			+ " role=" + string(_measure[$ "pickup_role"])
			+ " complement=" + string(_measure[$ "complement_uid"]));
	}

	show_debug_message("[TUNE-DETAIL] L1 BEAT GRID");
	for (var _b = 0; _b < array_length(_beats); _b++) {
		var _beat = _beats[_b];
		show_debug_message("[TUNE-DETAIL] B " + string(_beat[$ "beat_uid"])
			+ " units=" + string(_beat[$ "units_from_start"])
			+ " weight=" + string(_beat[$ "weight"]));
	}

	show_debug_message("[TUNE-DETAIL] L2 VOICE EVENTS");
	if (!is_struct(_events)) return;
	var _voices = variable_struct_get_names(_events);
	for (var _v = 0; _v < array_length(_voices); _v++) {
		var _voice = _voices[_v];
		var _list = variable_struct_get(_events, _voice);
		show_debug_message("[TUNE-DETAIL] VOICE " + _voice + " events=" + string(array_length(_list)));
		for (var _e = 0; _e < array_length(_list); _e++) {
			var _event = _list[_e];
			show_debug_message("[TUNE-DETAIL] E " + string(_event[$ "event_uid"])
				+ " letter=" + string(_event[$ "letter"])
				+ " units=" + string(_event[$ "total_units"])
				+ " duration=" + string(_event[$ "written_units"])
				+ " ornament=" + string(_event[$ "has_ornament"])
				+ (variable_struct_exists(_event, "broken_pair_uid")
					? " broken=" + string(_event[$ "broken_pair_uid"])
						+ "/" + string(_event[$ "broken_role"])
						+ " total=" + string(_event[$ "broken_pair_total_units"])
					: ""));
		}
	}
}

/// @function tune_author_validate_dependencies(_compiled, _dir, _diag)
/// @description Validate external rhythm and embellishment dependencies before writing tune artifacts.
/// @param {struct} _compiled  Compiled tune envelope
/// @param {string} _dir  Intended tune folder
/// @param {struct} _diag  Compile diagnostics collector
/// @returns {bool} True when no blocking dependency errors exist
/// @reads global.emb_library, rhythm registry, existing tune manifest
/// @writes diagnostics collector
/// @objects none
/// @callers tune_author_create_from_abc
function tune_author_validate_dependencies(_compiled, _dir, _diag) {
	var _events = _compiled[$ "events"];
	var _missing = {};
	if (is_struct(_events)) {
		var _voices = variable_struct_get_names(_events);
		for (var _v = 0; _v < array_length(_voices); _v++) {
			var _voice = _voices[_v];
			var _list = variable_struct_get(_events, _voice);
			for (var _e = 0; _e < array_length(_list); _e++) {
				var _event = _list[_e];
				var _attachments = _event[$ "attachments"];
				if (!is_array(_attachments)) continue;
				for (var _a = 0; _a < array_length(_attachments); _a++) {
					var _attachment = _attachments[_a];
					var _pattern = is_struct(_attachment) ? string(_attachment[$ "pattern"] ?? "") : "";
					var _target = string(_event[$ "letter"] ?? "");
					if (is_struct(find_embellishment(global.emb_library, _pattern, _target, 0, ""))) continue;
					var _key = _voice + "|" + _pattern + "|" + _target;
					if (!variable_struct_exists(_missing, _key)) {
						variable_struct_set(_missing, _key, {
							voice: _voice, pattern: _pattern, target: _target,
							count: 0, event_uid: string(_event[$ "event_uid"] ?? "")
						});
					}
					var _row = variable_struct_get(_missing, _key);
					_row[$ "count"] += 1;
				}
			}
		}
	}

	var _missing_keys = variable_struct_get_names(_missing);
	for (var _i = 0; _i < array_length(_missing_keys); _i++) {
		var _row = variable_struct_get(_missing, _missing_keys[_i]);
		tune_diagnostics_add(_diag, TUNE_DIAG_ERROR, "emb_definition_missing",
			"No embellishment definition for pattern '" + string(_row[$ "pattern"])
			+ "', target '" + string(_row[$ "target"])
			+ "', voice '" + string(_row[$ "voice"])
			+ "' (" + string(_row[$ "count"]) + " occurrence(s)).",
			{ event_uid: _row[$ "event_uid"] });
	}

	var _registry = tune_rhythm_registry_load();
	var _meter = string(_compiled[$ "meter"] ?? "");
	var _meter_norm = timing_normalize_time_sig(_meter);
	var _existing = tune_manifest_read(_dir);
	var _authored = is_struct(_existing) ? _existing[$ "authored"] : undefined;
	if (!is_struct(_authored)) _authored = {};

	var _pointing_id = string(_authored[$ "pointing_id"] ?? "written");
	if (!is_struct(tune_rhythm_profile_find(_registry[$ "pointing_profiles"], _pointing_id, "pointing_id"))) {
		tune_diagnostics_add(_diag, TUNE_DIAG_ERROR, "pointing_profile_missing",
			"Selected pointing profile '" + _pointing_id + "' is not defined.");
	}

	var _pulse_id = string(_authored[$ "pulse_id"] ?? _authored[$ "pulse_profile_id"] ?? "");
	if (_pulse_id != "") {
		var _pulse = tune_pulse_normalize(
			tune_rhythm_profile_find(_registry[$ "pulse_profiles"], _pulse_id, "pulse_id"), _meter_norm);
		if (!is_struct(_pulse)) {
			tune_diagnostics_add(_diag, TUNE_DIAG_ERROR, "pulse_profile_incompatible",
				"Selected pulse profile '" + _pulse_id + "' is missing or incompatible with meter " + _meter_norm + ".");
		}
	} else {
		var _defaults = _registry[$ "defaults"];
		var _pulse_defaults = is_struct(_defaults) ? _defaults[$ "pulse_by_meter"] : undefined;
		if (!is_struct(_pulse_defaults) || !variable_struct_exists(_pulse_defaults, _meter_norm)) {
			tune_diagnostics_add(_diag, TUNE_DIAG_WARNING, "meter_pulse_default_missing",
				"No pulse default is defined for meter " + _meter_norm + "; playback will be straight.");
		}
	}

	return !tune_diagnostics_has_errors(_diag);
}

/// @function tune_author_create_from_abc(_abc_text, _title_override)
/// @description Create a tune from ABC: make the folder, write the source, compile, write the
///              compiled cache and the tune manifest, and report. Does not touch tune_library.json.
/// @param {string} _abc_text        Raw ABC source
/// @param {string} [_title_override] Folder name; defaults to the ABC T: title
/// @returns {struct}  {ok, tune_uid, folder, compiled, diagnostics, index_entry}
/// @reads   ABC text
/// @writes  datafiles/tunes/<Tune>/<Tune>.abc, .compiled.json, tune.meta.json
/// @objects none
/// @callers manual (dev key N)
function tune_author_create_from_abc(_abc_text, _title_override = "") {
	var _headers = abc_parse_headers(_abc_text);
	var _title = (_title_override != "") ? _title_override : string(_headers[$ "t"] ?? "");
	var _folder = tune_author_slug(_title);

	var _result = {
		ok: false,
		tune_uid: _folder,
		folder: "",
		compiled: undefined,
		diagnostics: undefined,
		index_entry: undefined
	};

	if (_folder == "") {
		show_debug_message("[TUNE] cannot create: ABC has no T: title and no name was given.");
		return _result;
	}

	var _compile = tune_compile(_abc_text, {}, _folder);
	var _compiled = _compile[$ "compiled"];
	var _diag = _compile[$ "diagnostics"];
	var _root = scr_data_paths_get_category_root("tunes");
	var _dir = _root + _folder + "/";

	_result.compiled = _compiled;
	_result.diagnostics = _diag;
	_result.folder = _dir;
	_result.ok = _compile[$ "ok"] && tune_author_validate_dependencies(_compiled, _dir, _diag);

	tune_author_log_summary(_compiled);
	tune_diagnostics_log(_diag, "[TUNE] " + _folder);
	if (!_result.ok) {
		show_debug_message("[TUNE] REJECTED " + _folder + ": fix errors and press N again; no tune artifacts were written.");
		return _result;
	}

	if (!directory_exists(_dir)) directory_create(_dir);
	tune_author_write_text(_dir + _folder + ".abc", _abc_text);

	tune_author_write_text(_dir + _folder + ".compiled.json", json_stringify(_compiled));
	tune_manifest_write(_dir, tune_manifest_build(_dir, _folder, _compiled));

	_result.index_entry = tune_author_index_entry(_compiled, _diag);

	show_debug_message("[TUNE] wrote " + _dir + " (ok=" + string(_result.ok) + ")");

	return _result;
}

/// @function tune_author_create_from_staged()
/// @description Compile every ABC in the staging folder into its tune folder, creating the folder
///              when absent and updating it when present. Only pipeline artifacts are written:
///              legacy `<Tune>.json`, `score/` and snippet files are never touched, so the current
///              runtime keeps playing while the new path is built out.
/// @returns {struct}  {total, created, updated, failed}
/// @reads   datafiles/tunes/_incoming/*.abc
/// @writes  datafiles/tunes/<Tune>/{.abc, .compiled.json, tune.meta.json}
/// @objects none
/// @callers manual (dev key N)
function tune_author_create_from_staged() {
	var _root = scr_data_paths_get_category_root("tunes");
	var _stage = _root + TUNE_STAGING_FOLDER + "/";
	var _summary = { total: 0, created: 0, updated: 0, failed: 0 };

	if (!directory_exists(_stage)) {
		show_debug_message("[TUNE] staging folder not found: " + _stage);
		return _summary;
	}

	var _files = [];
	var _f = file_find_first(_stage + "*.abc", 0);
	while (_f != "") {
		array_push(_files, _f);
		_f = file_find_next();
	}
	file_find_close();

	for (var _i = 0; _i < array_length(_files); _i++) {
		var _abc = tune_shadow_read_text(_stage + _files[_i]);
		if (_abc == "") continue;

		_summary.total += 1;

		var _headers = abc_parse_headers(_abc);
		var _folder = tune_author_slug(string(_headers[$ "t"] ?? ""));
		var _existed = (_folder != "") && directory_exists(_root + _folder + "/");

		var _r = tune_author_create_from_abc(_abc);
		if (!_r[$ "ok"]) {
			_summary.failed += 1;
		} else if (_existed) {
			_summary.updated += 1;
		} else {
			_summary.created += 1;
		}
	}

	show_debug_message("[TUNE] SUMMARY total=" + string(_summary.total)
		+ " created=" + string(_summary.created)
		+ " updated=" + string(_summary.updated)
		+ " failed=" + string(_summary.failed));
	show_debug_message("[TUNE] legacy .json and score/ files were not modified.");
	return _summary;
}
