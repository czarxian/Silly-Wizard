// Minimal "create a new tune" workflow: ABC text in, tune folder out.
// See TUNE_PIPELINE_CONTRACT.md §7. This is the authoring path that replaces the Excel export.
//
// Not yet wired to playback: run_build (ms projection, ornament expansion) is still stubbed,
// so a tune created here compiles and validates but does not play.

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

/// @function tune_author_default_meta(_compiled)
/// @description Build the starting <Tune>.meta.json — the things ABC cannot express.
/// @param {struct} _compiled  Compiled tune
/// @returns {struct}  Meta struct
function tune_author_default_meta(_compiled) {
	return {
		schema_version: TUNE_PIPELINE_SCHEMA_VERSION,
		tune_uid: string(_compiled[$ "tune_uid"]),
		rhythm_rule_id: "",              // empty = resolve from rhythm_type + meter
		embellishment_variant_set: "",   // empty = library defaults
		pulse_profile_id: "",            // empty = no pulse
		annotations: [],                 // L4
		tags: []
	};
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

/// @function tune_author_create_from_abc(_abc_text, _title_override)
/// @description Create a tune from ABC: make the folder, write the source, compile, write the
///              compiled cache and meta, and report. Does not touch tune_library.json.
/// @param {string} _abc_text        Raw ABC source
/// @param {string} [_title_override] Folder name; defaults to the ABC T: title
/// @returns {struct}  {ok, tune_uid, folder, compiled, diagnostics, index_entry}
/// @reads   ABC text
/// @writes  datafiles/tunes/<Tune>/<Tune>.abc, .compiled.json, .meta.json
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

	var _root = scr_data_paths_get_category_root("tunes");
	var _dir = _root + _folder + "/";
	if (!directory_exists(_dir)) directory_create(_dir);
	_result.folder = _dir;

	tune_author_write_text(_dir + _folder + ".abc", _abc_text);

	var _compile = tune_compile(_abc_text, {}, _folder);
	var _compiled = _compile[$ "compiled"];
	var _diag = _compile[$ "diagnostics"];

	_result.compiled = _compiled;
	_result.diagnostics = _diag;
	_result.ok = _compile[$ "ok"];

	tune_author_write_text(_dir + _folder + ".compiled.json", json_stringify(_compiled));
	tune_author_write_text(_dir + _folder + ".meta.json",
		json_stringify(tune_author_default_meta(_compiled)));

	_result.index_entry = tune_author_index_entry(_compiled, _diag);

	tune_author_log_summary(_compiled);
	tune_diagnostics_log(_diag, "[TUNE] " + _folder);
	show_debug_message("[TUNE] wrote " + _dir + " (ok=" + string(_result.ok) + ")");

	return _result;
}

/// @function tune_author_create_from_staged()
/// @description Create a tune from each ABC in the staging folder that has no tune folder yet.
///              This is the "new tune" path; existing tunes are left to the ingest flow.
/// @returns {struct}  {created, skipped}
/// @reads   datafiles/tunes/_incoming/*.abc
/// @writes  new tune folders
/// @objects none
/// @callers manual (dev key N)
function tune_author_create_from_staged() {
	var _root = scr_data_paths_get_category_root("tunes");
	var _stage = _root + TUNE_INGEST_FOLDER + "/";
	var _summary = { created: 0, skipped: 0 };

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

		var _headers = abc_parse_headers(_abc);
		var _folder = tune_author_slug(string(_headers[$ "t"] ?? ""));

		if (_folder != "" && directory_exists(_root + _folder + "/")) {
			show_debug_message("[TUNE] skip (folder exists): " + _folder);
			_summary.skipped += 1;
			continue;
		}

		var _r = tune_author_create_from_abc(_abc);
		if (_r[$ "ok"]) _summary.created += 1; else _summary.skipped += 1;
	}

	show_debug_message("[TUNE] SUMMARY created=" + string(_summary.created)
		+ " skipped=" + string(_summary.skipped));
	return _summary;
}
