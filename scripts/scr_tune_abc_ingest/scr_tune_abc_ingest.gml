// Ingest raw source ABC files from datafiles/tunes/_incoming/ into their tune folders.
// See TUNE_PIPELINE_CONTRACT.md §7 — <Tune>.abc is the source of truth; this only moves files
// into that position. No normalisation happens here: gaps are surfaced by parser diagnostics.

#macro TUNE_INGEST_FOLDER "_incoming"

/// @function tune_ingest_normalise_name(_name)
/// @description Reduce a tune name to a comparable key: lowercase, no punctuation, no leading "the".
/// @param {string} _name  Folder name, file stem or ABC title
/// @returns {string}  Comparison key
function tune_ingest_normalise_name(_name) {
	var _s = string_lower(string_trim(string(_name)));

	var _out = "";
	for (var _i = 1; _i <= string_length(_s); _i++) {
		var _ch = string_char_at(_s, _i);
		var _o = ord(_ch);
		if ((_o >= 48 && _o <= 57) || (_o >= 97 && _o <= 122)) _out += _ch;
	}

	if (string_copy(_out, 1, 3) == "the") _out = string_delete(_out, 1, 3);
	return _out;
}

/// @function tune_ingest_list_tune_folders(_root)
/// @description List tune folder names, excluding the staging folder.
/// @param {string} _root  Tunes root path ending with '/'
/// @returns {array}  Folder names
function tune_ingest_list_tune_folders(_root) {
	var _names = [];
	var _name = file_find_first(_root + "*", fa_directory);
	while (_name != "") {
		if (_name != "." && _name != ".." && _name != TUNE_INGEST_FOLDER
			&& directory_exists(_root + _name)) {
			array_push(_names, _name);
		}
		_name = file_find_next();
	}
	file_find_close();
	return _names;
}

/// @function tune_ingest_match_folder(_folders, _file_stem, _abc_title)
/// @description Find the tune folder a staged file belongs to, by filename then ABC title.
/// @param {array}  _folders    Tune folder names
/// @param {string} _file_stem  Staged file name without extension
/// @param {string} _abc_title  Title from the ABC T: header
/// @returns {struct}  {status: "matched"|"new"|"ambiguous", folder, by}
function tune_ingest_match_folder(_folders, _file_stem, _abc_title) {
	var _by_stem = [];
	var _by_title = [];
	var _stem_key = tune_ingest_normalise_name(_file_stem);
	var _title_key = tune_ingest_normalise_name(_abc_title);

	for (var _i = 0; _i < array_length(_folders); _i++) {
		var _folder_key = tune_ingest_normalise_name(_folders[_i]);
		if (_folder_key == "") continue;
		if (_stem_key != "" && _folder_key == _stem_key)  array_push(_by_stem, _folders[_i]);
		if (_title_key != "" && _folder_key == _title_key) array_push(_by_title, _folders[_i]);
	}

	if (array_length(_by_stem) == 1)  return { status: "matched", folder: _by_stem[0],  by: "filename" };
	if (array_length(_by_stem) > 1)   return { status: "ambiguous", folder: "", by: "filename" };
	if (array_length(_by_title) == 1) return { status: "matched", folder: _by_title[0], by: "title" };
	if (array_length(_by_title) > 1)  return { status: "ambiguous", folder: "", by: "title" };

	return { status: "new", folder: "", by: "" };
}

/// @function tune_ingest_scan(_apply)
/// @description Report how each staged ABC maps to a tune folder, and optionally copy matches
///              into place. Reports voices and diagnostics so problems surface before copying.
/// @param {bool} [_apply]  When true, copy matched files to <Tune>/<Tune>.abc
/// @returns {struct}  {total, matched, ambiguous, new_tunes, copied}
/// @reads   datafiles/tunes/_incoming/*.abc, tune folder names
/// @writes  datafiles/tunes/<Tune>/<Tune>.abc when _apply is true
/// @objects none
/// @callers manual (dev keys I / Shift+I)
function tune_ingest_scan(_apply = false) {
	var _root = scr_data_paths_get_category_root("tunes");
	var _stage = _root + TUNE_INGEST_FOLDER + "/";
	var _summary = { total: 0, matched: 0, ambiguous: 0, new_tunes: 0, copied: 0 };

	if (!directory_exists(_stage)) {
		show_debug_message("[INGEST] staging folder not found: " + _stage);
		return _summary;
	}

	var _folders = tune_ingest_list_tune_folders(_root);

	var _files = [];
	var _f = file_find_first(_stage + "*.abc", 0);
	while (_f != "") {
		array_push(_files, _f);
		_f = file_find_next();
	}
	file_find_close();

	for (var _i = 0; _i < array_length(_files); _i++) {
		var _file = _files[_i];
		var _path = _stage + _file;
		var _stem = string_replace(_file, ".abc", "");

		var _abc = tune_shadow_read_text(_path);
		var _headers = abc_parse_headers(_abc);
		var _title = string(_headers[$ "t"] ?? "");
		var _voices = abc_list_voices(_abc);

		var _diag = tune_diagnostics_create();
		abc_tokenize(abc_extract_body(_abc, ""), _diag);
		var _warnings = _diag[$ "counts"][$ "warning"];

		var _match = tune_ingest_match_folder(_folders, _stem, _title);
		var _status = string(_match[$ "status"]);
		_summary.total += 1;

		var _line = "[INGEST] " + _file
			+ " | title=\"" + _title + "\""
			+ " | voices=" + string(array_length(_voices))
			+ " | warnings=" + string(_warnings)
			+ " | " + _status;

		if (_status == "matched") {
			_summary.matched += 1;
			_line += " -> " + string(_match[$ "folder"]) + " (by " + string(_match[$ "by"]) + ")";

			if (_apply) {
				var _folder = string(_match[$ "folder"]);
				var _dest = _root + _folder + "/" + _folder + ".abc";
				file_copy(_path, _dest);
				_summary.copied += 1;
				_line += " [COPIED]";
			}
		} else if (_status == "ambiguous") {
			_summary.ambiguous += 1;
		} else {
			_summary.new_tunes += 1;
		}

		show_debug_message(_line);
	}

	show_debug_message("[INGEST] SUMMARY total=" + string(_summary.total)
		+ " matched=" + string(_summary.matched)
		+ " ambiguous=" + string(_summary.ambiguous)
		+ " new=" + string(_summary.new_tunes)
		+ " copied=" + string(_summary.copied));

	if (!_apply && _summary.matched > 0) {
		show_debug_message("[INGEST] press Shift+I to copy the " + string(_summary.matched)
			+ " matched file(s) into their tune folders.");
	}

	return _summary;
}
