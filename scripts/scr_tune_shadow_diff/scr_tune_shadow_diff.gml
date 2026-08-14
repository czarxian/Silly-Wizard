// Phase 2 shadow diff: compare the GML ABC parser against the exported Excel tune.json.
// Validation tooling only — nothing here runs during playback, and it is deleted at cutover.
//
// Expected differences (not reported as mismatches):
//   - `adjusted` units. The Excel pipeline bakes broken-rhythm pointing into `adjusted`;
//     under TUNE_PIPELINE_CONTRACT.md §4 that becomes a run-time rhythm rule instead.
//   - `start_time_ms` / `end_time_ms` / `tempo`. Vestigial in the export; ms is a projection.

#macro TUNE_SHADOW_EPS 0.0001
#macro TUNE_SHADOW_MAX_REPORTED 25

/// @function tune_shadow_read_text(_path)
/// @description Read a whole text file.
/// @param {string} _path  File path
/// @returns {string}  File contents, or "" when the file cannot be opened
function tune_shadow_read_text(_path) {
	if (!file_exists(_path)) return "";

	var _f = file_text_open_read(_path);
	if (_f < 0) return "";

	var _raw = "";
	while (!file_text_eof(_f)) {
		_raw += file_text_read_string(_f);
		_raw += "\n";
		file_text_readln(_f);
	}
	file_text_close(_f);
	return _raw;
}

/// @function tune_shadow_compare_field(_report, _index, _field, _legacy, _parsed)
/// @description Record a mismatch when two field values differ, with tolerance for reals.
/// @param {struct} _report  Diff report
/// @param {real}   _index   Event index
/// @param {string} _field   Field name
/// @param {any}    _legacy  Value from tune.json
/// @param {any}    _parsed  Value from the GML parser
/// @returns {bool}  True when the values matched
function tune_shadow_compare_field(_report, _index, _field, _legacy, _parsed) {
	var _same;
	if (is_real(_legacy) || is_real(_parsed)) {
		_same = (abs(real(_legacy) - real(_parsed)) <= TUNE_SHADOW_EPS);
	} else {
		_same = (string(_legacy) == string(_parsed));
	}
	if (_same) return true;

	_report.mismatch_count += 1;
	var _list = _report[$ "mismatches"];
	if (array_length(_list) < TUNE_SHADOW_MAX_REPORTED) {
		array_push(_list, {
			index: _index,
			field: _field,
			legacy: _legacy,
			parsed: _parsed
		});
	}
	return false;
}

/// @function tune_shadow_diff_events(_legacy_events, _parsed_events, _report)
/// @description Compare two event streams position by position.
/// @param {array}  _legacy_events  Events from tune.json
/// @param {array}  _parsed_events  Flat events from the GML parser
/// @param {struct} _report         Diff report to populate
/// @returns {struct}  _report
function tune_shadow_diff_events(_legacy_events, _parsed_events, _report) {
	var _ln = array_length(_legacy_events);
	var _pn = array_length(_parsed_events);
	var _n = min(_ln, _pn);

	for (var _i = 0; _i < _n; _i++) {
		var _l = _legacy_events[_i];
		var _p = _parsed_events[_i];

		var _type_ok = tune_shadow_compare_field(_report, _i, "type", _l[$ "type"] ?? "", _p.type);
		if (!_type_ok) continue;   // once the streams desynchronise, further fields are noise

		tune_shadow_compare_field(_report, _i, "total_units", _l[$ "total_units"] ?? 0, _p.total_units);
		tune_shadow_compare_field(_report, _i, "measure", _l[$ "measure"] ?? 0, _p.measure);
		tune_shadow_compare_field(_report, _i, "beat", _l[$ "beat"] ?? 0, _p.beat);

		if (_p.type == "note") {
			tune_shadow_compare_field(_report, _i, "letter", _l[$ "letter"] ?? "", _p.letter);
			tune_shadow_compare_field(_report, _i, "written", _l[$ "written"] ?? 0, _p.written);
		} else if (_p.type == "embellishment") {
			tune_shadow_compare_field(_report, _i, "emb_literal", _l[$ "emb_literal"] ?? "", _p.emb_literal);
			tune_shadow_compare_field(_report, _i, "emb_target", _l[$ "emb_target"] ?? "", _p[$ "emb_target"] ?? "");
		} else if (_p.type == "structure") {
			tune_shadow_compare_field(_report, _i, "structure", _l[$ "structure"] ?? "", _p.structure);
		}
	}

	return _report;
}

/// @function tune_shadow_legacy_voices(_legacy_events)
/// @description Collect the distinct non-empty voice names present in an exported tune.json.
/// @param {array} _legacy_events  Events from tune.json
/// @returns {array}  Voice names in order of first appearance
function tune_shadow_legacy_voices(_legacy_events) {
	var _out = [];
	for (var _i = 0; _i < array_length(_legacy_events); _i++) {
		var _v = string(_legacy_events[_i][$ "voice"] ?? "");
		if (_v == "") continue;

		var _found = false;
		for (var _j = 0; _j < array_length(_out); _j++) {
			if (_out[_j] == _v) { _found = true; break; }
		}
		if (!_found) array_push(_out, _v);
	}
	return _out;
}

/// @function tune_shadow_diff_tune(_tune_dir, _tune_name)
/// @description Parse one tune's ABC and diff it against the exported tune.json.
/// @param {string} _tune_dir   Folder containing the tune files, ending with '/'
/// @param {string} _tune_name  Tune folder name, used for the file stems
/// @returns {struct}  {tune, ok, status, legacy_count, parsed_count, mismatch_count, mismatches, diagnostics}
function tune_shadow_diff_tune(_tune_dir, _tune_name) {
	var _report = {
		tune: string(_tune_name),
		ok: false,
		status: "",
		legacy_count: 0,
		parsed_count: 0,
		mismatch_count: 0,
		mismatches: [],
		diagnostics: tune_diagnostics_create()
	};

	var _abc_path  = _tune_dir + _tune_name + ".abc";
	var _json_path = _tune_dir + _tune_name + ".json";

	var _abc = tune_shadow_read_text(_abc_path);
	if (_abc == "") {
		_report.status = "no_abc";
		return _report;
	}

	var _legacy = scr_tune_parse_json_file(_json_path);
	if (!is_struct(_legacy)) {
		_report.status = "no_json";
		return _report;
	}

	var _legacy_events = _legacy[$ "events"];
	if (!is_array(_legacy_events)) {
		_report.status = "no_events";
		return _report;
	}

	// The exporter strips V: headers, so a multi-voice export cannot be reconstructed
	// from its own .abc. Report rather than pretend to compare.
	var _legacy_voices = tune_shadow_legacy_voices(_legacy_events);
	var _abc_voices = abc_list_voices(_abc);
	if (array_length(_legacy_voices) > 1 && array_length(_abc_voices) == 0) {
		_report.status = "abc_missing_voices";
		tune_diagnostics_add(_report.diagnostics, TUNE_DIAG_WARNING, "abc_missing_voice_headers",
			"Export has " + string(array_length(_legacy_voices))
			+ " voices but the .abc declares none; re-export with V: headers to compare.");
		return _report;
	}

	var _parsed = abc_parse_tune(_abc, _report.diagnostics, _legacy_voices);
	var _parsed_events = _parsed[$ "events"];

	_report.legacy_count = array_length(_legacy_events);
	_report.parsed_count = array_length(_parsed_events);

	if (_report.legacy_count != _report.parsed_count) {
		tune_diagnostics_add(_report.diagnostics, TUNE_DIAG_ERROR, "shadow_count_mismatch",
			"Event count differs: legacy " + string(_report.legacy_count)
			+ " vs parsed " + string(_report.parsed_count) + ".");
	}

	tune_shadow_diff_events(_legacy_events, _parsed_events, _report);

	_report.ok = (_report.mismatch_count == 0)
		&& (_report.legacy_count == _report.parsed_count)
		&& !tune_diagnostics_has_errors(_report.diagnostics);
	_report.status = _report.ok ? "match" : "differs";
	return _report;
}

/// @function tune_shadow_diff_log_report(_report)
/// @description Print one tune's diff result.
/// @param {struct} _report  Report from tune_shadow_diff_tune
/// @returns {undefined}
function tune_shadow_diff_log_report(_report) {
	var _head = "[SHADOW] " + string(_report[$ "tune"])
		+ " status=" + string(_report[$ "status"])
		+ " legacy=" + string(_report[$ "legacy_count"])
		+ " parsed=" + string(_report[$ "parsed_count"])
		+ " mismatches=" + string(_report[$ "mismatch_count"]);
	show_debug_message(_head);

	var _mm = _report[$ "mismatches"];
	for (var _i = 0; _i < array_length(_mm); _i++) {
		var _m = _mm[_i];
		show_debug_message("[SHADOW]   idx " + string(_m[$ "index"])
			+ " " + string(_m[$ "field"])
			+ ": legacy=" + string(_m[$ "legacy"])
			+ " parsed=" + string(_m[$ "parsed"]));
	}

	tune_diagnostics_log(_report[$ "diagnostics"], "[SHADOW] " + string(_report[$ "tune"]));
}

/// @function tune_shadow_diff_all()
/// @description Diff every tune folder under the tunes root and log a summary.
///              Manual validation entry point; not wired to playback.
/// @returns {struct}  {total, matched, differed, skipped, reports}
/// @reads   tune folders under scr_data_paths_get_category_root("tunes")
/// @writes  none (debug output only)
/// @objects none
/// @callers manual invocation during Phase 2
function tune_shadow_diff_all() {
	var _root = scr_data_paths_get_category_root("tunes");
	var _summary = { total: 0, matched: 0, differed: 0, skipped: 0, reports: [] };

	var _name = file_find_first(_root + "*", fa_directory);
	var _names = [];
	while (_name != "") {
		if (_name != "." && _name != ".." && directory_exists(_root + _name)) {
			array_push(_names, _name);
		}
		_name = file_find_next();
	}
	file_find_close();

	for (var _i = 0; _i < array_length(_names); _i++) {
		var _tune = _names[_i];
		var _report = tune_shadow_diff_tune(_root + _tune + "/", _tune);

		_summary.total += 1;
		var _status = _report[$ "status"];
		if (_status == "match")        _summary.matched += 1;
		else if (_status == "differs") _summary.differed += 1;
		else                           _summary.skipped += 1;
		array_push(_summary.reports, _report);
		tune_shadow_diff_log_report(_report);
	}

	show_debug_message("[SHADOW] SUMMARY total=" + string(_summary.total)
		+ " matched=" + string(_summary.matched)
		+ " differed=" + string(_summary.differed)
		+ " skipped=" + string(_summary.skipped));

	return _summary;
}
