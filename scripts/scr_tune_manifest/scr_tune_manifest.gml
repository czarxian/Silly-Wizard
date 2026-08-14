// Per-tune manifest: the one file that says "this folder is a tune" and names its assets.
// See TUNE_PIPELINE_CONTRACT.md §7.
//
// Discovery is a presence test on a fixed filename, not a glob with a suffix blacklist.
// Identity (tune_uid, title) lives inside the file, so the folder name is cosmetic.

#macro TUNE_MANIFEST_FILENAME "tune.meta.json"

/// @function tune_manifest_path(_dir)
/// @description Manifest path for a tune folder.
/// @param {string} _dir  Tune folder, ending with '/'
/// @returns {string}
function tune_manifest_path(_dir) {
	return string(_dir) + TUNE_MANIFEST_FILENAME;
}

/// @function tune_manifest_exists(_dir)
/// @description Whether a folder is a tune. This is the discovery test.
/// @param {string} _dir  Tune folder, ending with '/'
/// @returns {bool}
function tune_manifest_exists(_dir) {
	return file_exists(tune_manifest_path(_dir));
}

/// @function tune_manifest_read(_dir)
/// @description Read a tune manifest.
/// @param {string} _dir  Tune folder, ending with '/'
/// @returns {struct|undefined}  Manifest, or undefined when absent or unparseable
function tune_manifest_read(_dir) {
	var _path = tune_manifest_path(_dir);
	if (!file_exists(_path)) return undefined;
	return scr_tune_parse_json_file(_path);
}

/// @function tune_manifest_is_pipeline_json(_lower_name)
/// @description Whether a lowercase filename is a pipeline/score artifact rather than tune events.
/// @param {string} _lower_name  Lowercase filename
/// @returns {bool}
function tune_manifest_is_pipeline_json(_lower_name) {
	return (_lower_name == "tune_library.json")
		|| (_lower_name == "score_images.json")
		|| (_lower_name == TUNE_MANIFEST_FILENAME)
		|| (string_pos(".score_snippets.json", _lower_name) > 0)
		|| (string_pos(".score_groups.json", _lower_name) > 0)
		|| (string_pos(".score_part", _lower_name) > 0)
		|| (string_pos(".compiled.json", _lower_name) > 0)
		|| (string_pos(".meta.json", _lower_name) > 0);
}

/// @function tune_manifest_detect_artifacts(_dir)
/// @description Inventory a tune folder by inspecting what is actually present.
///              Used to build a manifest; afterwards the manifest is authoritative.
/// @param {string} _dir  Tune folder, ending with '/'
/// @returns {struct}  {abc, compiled, score_dir, legacy_events}
function tune_manifest_detect_artifacts(_dir) {
	var _abc = "";
	var _compiled = "";
	var _legacy = "";

	var _f = file_find_first(_dir + "*", 0);
	while (_f != "") {
		var _lower = string_lower(_f);

		if (string_pos(".abc", _lower) > 0 && string_pos(".abc.", _lower) <= 0) {
			if (_abc == "") _abc = _f;
		} else if (string_pos(".compiled.json", _lower) > 0) {
			_compiled = _f;
		} else if (string_pos(".json", _lower) > 0 && !tune_manifest_is_pipeline_json(_lower)) {
			if (_legacy == "") _legacy = _f;
		}

		_f = file_find_next();
	}
	file_find_close();

	return {
		abc: _abc,
		compiled: _compiled,
		score_dir: directory_exists(_dir + "score") ? "score/" : "",
		legacy_events: _legacy
	};
}

/// @function tune_manifest_build(_dir, _folder_name, _compiled)
/// @description Build a manifest for a tune folder, preserving authored fields when one exists.
/// @param {string} _dir          Tune folder, ending with '/'
/// @param {string} _folder_name  Folder name, used as the fallback identity and title
/// @param {struct} [_compiled]   Compiled tune, when the caller has just compiled one
/// @returns {struct}  Manifest
function tune_manifest_build(_dir, _folder_name, _compiled = undefined) {
	var _artifacts = tune_manifest_detect_artifacts(_dir);
	var _existing = tune_manifest_read(_dir);

	var _title = string(_folder_name);
	var _composer = "";
	var _rhythm = "";
	var _meter = "";
	var _tempo = 0;

	// Prefer the ABC headers; they are the source of truth for descriptive metadata.
	if (_artifacts[$ "abc"] != "") {
		var _headers = abc_parse_headers(tune_shadow_read_text(_dir + _artifacts[$ "abc"]));
		if (string(_headers[$ "t"] ?? "") != "") _title = string(_headers[$ "t"]);
		_composer = string(_headers[$ "c"] ?? "");
		_rhythm = string(_headers[$ "r"] ?? "");
		_meter = string(_headers[$ "m"] ?? "");
		_tempo = real(_headers[$ "q"] ?? 0);
	} else if (_artifacts[$ "legacy_events"] != "") {
		var _legacy = scr_tune_parse_json_file(_dir + _artifacts[$ "legacy_events"]);
		if (is_struct(_legacy)) {
			var _meta = _legacy[$ "tune"];
			if (is_struct(_meta)) {
				if (string(_meta[$ "title"] ?? "") != "") _title = string(_meta[$ "title"]);
				_composer = string(_meta[$ "composer"] ?? "");
				_rhythm = string(_meta[$ "rhythm"] ?? "");
				_meter = string(_meta[$ "meter"] ?? "");
				_tempo = real(_meta[$ "tempo_default"] ?? 0);
			}
		}
	}

	if (is_struct(_compiled)) {
		if (string(_compiled[$ "title"] ?? "") != "") _title = string(_compiled[$ "title"]);
		if (string(_compiled[$ "meter"] ?? "") != "") _meter = string(_compiled[$ "meter"]);
		if (string(_compiled[$ "rhythm_type"] ?? "") != "") _rhythm = string(_compiled[$ "rhythm_type"]);
	}

	// Identity is captured once and never rederived, so renaming the folder is safe.
	var _uid = is_struct(_existing) ? string(_existing[$ "tune_uid"] ?? "") : "";
	if (_uid == "") _uid = string(_folder_name);

	var _authored = is_struct(_existing) ? _existing[$ "authored"] : undefined;
	if (!is_struct(_authored)) {
		_authored = { rhythm_rule_id: "", embellishment_variant_set: "", pulse_profile_id: "" };
	}

	var _annotations = is_struct(_existing) ? _existing[$ "annotations"] : undefined;
	if (!is_array(_annotations)) _annotations = [];

	var _tags = is_struct(_existing) ? _existing[$ "tags"] : undefined;
	if (!is_array(_tags)) _tags = [];

	return {
		schema_version: TUNE_PIPELINE_SCHEMA_VERSION,
		tune_uid: _uid,

		// Descriptive fields are derived from the source and safe to rebuild.
		title: _title,
		composer: _composer,
		rhythm_type: _rhythm,
		meter: _meter,
		tempo_default: _tempo,

		source: { abc: _artifacts[$ "abc"] },
		artifacts: {
			compiled: _artifacts[$ "compiled"],
			score_dir: _artifacts[$ "score_dir"],
			legacy_events: _artifacts[$ "legacy_events"]
		},

		// Authored fields are the source of truth and are preserved across rebuilds.
		authored: _authored,
		annotations: _annotations,
		tags: _tags
	};
}

/// @function tune_manifest_write(_dir, _manifest)
/// @description Write a tune manifest.
/// @param {string} _dir       Tune folder, ending with '/'
/// @param {struct} _manifest  Manifest struct
/// @returns {bool}  True on success
function tune_manifest_write(_dir, _manifest) {
	return tune_author_write_text(tune_manifest_path(_dir), json_stringify(_manifest));
}

/// @function tune_manifest_backfill_all()
/// @description Write a manifest into every tune folder that lacks one, and refresh the artifact
///              inventory of those that have one. Authored fields are preserved.
/// @returns {struct}  {total, created, refreshed}
/// @reads   every folder under the tunes root
/// @writes  <folder>/tune.meta.json
/// @objects none
/// @callers manual (dev key I)
function tune_manifest_backfill_all() {
	var _root = scr_data_paths_get_category_root("tunes");
	var _summary = { total: 0, created: 0, refreshed: 0 };

	var _names = [];
	var _name = file_find_first(_root + "*", fa_directory);
	while (_name != "") {
		if (_name != "." && _name != ".." && string_char_at(_name, 1) != "_"
			&& directory_exists(_root + _name)) {
			array_push(_names, _name);
		}
		_name = file_find_next();
	}
	file_find_close();

	for (var _i = 0; _i < array_length(_names); _i++) {
		var _folder = _names[_i];
		var _dir = _root + _folder + "/";
		var _had = tune_manifest_exists(_dir);

		var _manifest = tune_manifest_build(_dir, _folder);
		tune_manifest_write(_dir, _manifest);

		_summary.total += 1;
		if (_had) _summary.refreshed += 1; else _summary.created += 1;

		var _art = _manifest[$ "artifacts"];
		show_debug_message("[MANIFEST] " + _folder
			+ " | uid=" + string(_manifest[$ "tune_uid"])
			+ " | abc=" + (string(_manifest[$ "source"][$ "abc"]) != "" ? "yes" : "-")
			+ " | compiled=" + (string(_art[$ "compiled"]) != "" ? "yes" : "-")
			+ " | legacy=" + (string(_art[$ "legacy_events"]) != "" ? "yes" : "-")
			+ " | score=" + (string(_art[$ "score_dir"]) != "" ? "yes" : "-"));
	}

	show_debug_message("[MANIFEST] SUMMARY total=" + string(_summary.total)
		+ " created=" + string(_summary.created)
		+ " refreshed=" + string(_summary.refreshed));
	return _summary;
}
