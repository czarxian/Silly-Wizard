// scr_tune_load — Tune JSON loader with validation and remediation
// Purpose: Read, validate, and remediate tune JSON files, then populate `obj_tune`.
// 
// Expected JSON structure:
// {
//   "tune": { title, tempo_default, default_unit_ms, ... },
//   "performance": { channel, instrument_midi_note_base, ... },
//   "metronome": { enabled, beats_per_bar, ... },
//   "events": [ { type, letter, total_units, ... }, ... ]
// }

/// @function scr_tune_load_json(_filename)
/// @description Main entry point: parse, validate, remediate, and load a tune JSON file into global.tune.
/// @param {string} _filename  Path to tune JSON file
/// @returns {bool}  true if load successful, false otherwise
/// @reads   none
/// @writes  global.tune.tune_data (via scr_tune_load_into_global), global.score_lane_sprites, global.score_playback_map, global.score_measure_map
/// @objects global.tune (write)
/// @callers scr_button_scripts scr_tune_OK (single-tune path)
function scr_tune_load_json(_filename) {
    show_debug_message("=== Loading tune: " + string(_filename) + " ===");
    
    // Step 1: Parse JSON file
    var raw_data = scr_tune_parse_json_file(_filename);
    if (raw_data == undefined) {
        return false;
    }
    
    // Step 2: Validate and remediate structure
    var validation = scr_tune_validate_and_remediate(raw_data, _filename);
    if (!validation.valid) {
        show_debug_message("ERROR: Tune validation failed");
        for (var i = 0; i < array_length(validation.errors); i++) {
            show_debug_message("  - " + validation.errors[i]);
        }
        return false;
    }
    
    // Step 3: Load into global.tune
    scr_tune_load_into_global(validation.data, _filename);
    show_debug_message("Tune loaded successfully");
    return true;
}

/// @function scr_tune_parse_json_file(_filename)
/// @description Read a JSON file from disk and return the parsed struct.
/// @param {string} _filename  Path to JSON file
/// @returns {struct|undefined}  Parsed struct, or undefined on read/parse failure
function scr_tune_parse_json_file(_filename) {
    var f = file_text_open_read(_filename);
    if (f < 0) {
        show_debug_message("ERROR: Failed to open file: " + string(_filename));
        return undefined;
    }
    
    var raw = "";
    while (!file_text_eof(f)) {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }
    file_text_close(f);
    
    var data = json_parse(raw);
    if (data == undefined) {
        show_debug_message("ERROR: JSON parse failed for: " + string(_filename));
        return undefined;
    }
    
    return data;
}

/// @function scr_tune_validate_and_remediate(_data, _filename)
/// @description Validate raw parsed tune struct for required fields; remediate trivial issues (e.g. missing title).
/// @param {struct} _data  Raw parsed JSON root struct
/// @param {string} _filename  Source path (used to derive title if missing)
/// @returns {struct}  {valid: bool, errors: array, data: normalized tune struct}
function scr_tune_validate_and_remediate(_data, _filename) {
    var result = {
        valid: false,
        errors: array_create(0),
        data: undefined
    };
    
    // Check if data is a struct
    if (!is_struct(_data)) {
        array_push(result.errors, "Root JSON must be a struct, not an array");
        return result;
    }
    
    // Extract top-level fields
    var tune_meta = _data[$ "tune"] ?? undefined;
    var events = _data[$ "events"] ?? undefined;
    var perf = _data[$ "performance"] ?? undefined;
    var metronome = _data[$ "metronome"] ?? undefined;
    
    // Validate required fields
    if (tune_meta == undefined || !is_struct(tune_meta)) {
        array_push(result.errors, "Missing or invalid 'tune' struct");
    }
    if (events == undefined || !is_array(events)) {
        array_push(result.errors, "Missing or invalid 'events' array");
    }
    if (perf == undefined || !is_struct(perf)) {
        array_push(result.errors, "Missing or invalid 'performance' struct");
    }
    
    if (array_length(result.errors) > 0) {
        return result;
    }
    
    // Remediate trivial issues
    // If title is missing, derive from filename
    if (!variable_struct_exists(tune_meta, "title") || tune_meta.title == "") {
        var title = scr_tune_extract_filename_base(_filename);
        tune_meta.title = title;
        show_debug_message("  Remediated: Derived title from filename = '" + title + "'");
    }
    
    // Return validated and remediated data
    result.valid = true;
    result.data = {
        tune_metadata: tune_meta,
        performance: perf,
        metronome: metronome ?? {},  // Optional, default to empty struct
        events: events
    };
    
    show_debug_message("  Validation passed: " + string(array_length(events)) + " events, title '" + tune_meta.title + "'");
    return result;
}

/// @function scr_tune_load_into_global(_tune_data, _filename)
/// @description Store validated tune data into the global.tune (obj_tune) instance.
/// @param {struct} _tune_data  Normalized tune struct from scr_tune_validate_and_remediate
/// @param {string} _filename  Source path (stored on tune_data.filename)
/// @reads   none
/// @writes  global.tune.tune_data fields, global.score_lane_sprites (via scr_score_sprites_load)
/// @objects global.tune (write)
/// @callers scr_tune_load_json
function scr_tune_load_into_global(_tune_data, _filename) {
    if (!instance_exists(global.tune)) {
        show_debug_message("ERROR: obj_tune instance does not exist!");
        return;
    }
    
    global.tune.tune_data.tune_metadata = _tune_data.tune_metadata;
    global.tune.tune_data.performance = _tune_data.performance;
    global.tune.tune_data.metronome = _tune_data.metronome;
    global.tune.tune_data.events = _tune_data.events;
    global.tune.tune_data.event_count = array_length(_tune_data.events);
    global.tune.tune_data.is_loaded = true;
    global.tune.tune_data.filename = _filename;
    global.tune.tune_data.score_manifest = scr_score_manifest_read(_filename) ?? {};
    
    show_debug_message("  Stored into obj_tune:");
    show_debug_message("    Events: " + string(array_length(global.tune.tune_data.events)));
    show_debug_message("    Title: " + string(global.tune.tune_data.tune_metadata.title));

    // Load per-measure score sprites (silently skipped if no score folder exists)
    scr_score_sprites_load(_filename, global.tune.tune_data.score_manifest);
}

/// @function scr_tune_extract_filename_base(_filepath)
/// @description Extract the filename without path prefix or .json extension.
/// @param {string} _filepath  Full file path
/// @returns {string}  Bare filename (e.g. "Scotland_The_Brave")
function scr_tune_extract_filename_base(_filepath) {
    var lastSlash = 1;
    for (var i = 1; i <= string_length(_filepath); i++) {
        if (string_copy(_filepath, i, 1) == "/" || string_copy(_filepath, i, 1) == "\\") {
            lastSlash = i + 1;
        }
    }
    var base = string_copy(_filepath, lastSlash, string_length(_filepath) - lastSlash + 1);
    return string_replace(base, ".json", "");
}

/// @function scr_tune_load_to_struct(_filename)
/// @description Load and validate a tune JSON file, returning a lightweight struct. Does NOT write to global.tune — safe to call for multiple tunes in a set.
/// @param {string} _filename  Path to tune JSON (e.g. "tunes/Scotland_The_Brave/Scotland_The_Brave.json")
/// @returns {struct|undefined}  {tune_data: {tune_metadata, performance, metronome, events, event_count, is_loaded, filename}}, or undefined on failure
/// @reads   none
/// @writes  none
/// @objects none
/// @callers scr_set_scripts scr_set_load_json
function scr_tune_load_to_struct(_filename) {
    show_debug_message("=== scr_tune_load_to_struct: " + string(_filename) + " ===");

    var raw_data = scr_tune_parse_json_file(_filename);
    if (is_undefined(raw_data)) {
        show_debug_message("  ERROR: Could not parse file");
        return undefined;
    }

    var validation = scr_tune_validate_and_remediate(raw_data, _filename);
    if (!validation.valid) {
        show_debug_message("  ERROR: Validation failed");
        for (var i = 0; i < array_length(validation.errors); i++) {
            show_debug_message("    - " + validation.errors[i]);
        }
        return undefined;
    }

    var d = validation.data;
    var score_manifest = scr_score_manifest_read(_filename) ?? {};
    return {
        tune_data: {
            tune_metadata: d.tune_metadata,
            performance:   d.performance,
            metronome:     d.metronome,
            score_manifest: score_manifest,
            events:        d.events,
            event_count:   array_length(d.events),
            is_loaded:     true,
            filename:      _filename
        }
    };
}

/// @function scr_score_manifest_read(_filename)
/// @description Read and parse score/score_images.json next to a tune JSON file, returning a manifest struct or undefined.
/// @param {string} _filename  Tune JSON path
/// @returns {struct|undefined} Parsed score manifest, or undefined if absent/invalid
/// @reads   none
/// @writes  none
/// @objects none
/// @callers scr_tune_load_into_global, scr_tune_load_to_struct, scr_score_sprites_load
function scr_score_manifest_read(_filename) {
    // Derive parent directory from filename
    var last_slash = 0;
    for (var c = 1; c <= string_length(_filename); c++) {
        if (string_copy(_filename, c, 1) == "/") last_slash = c;
    }
    if (last_slash == 0) return undefined;

    var tune_dir = string_copy(_filename, 1, last_slash);
    var manifest_path = tune_dir + "score/score_images.json";

    var f = file_text_open_read(manifest_path);
    if (f < 0) return undefined;

    var raw = "";
    while (!file_text_eof(f)) {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }
    file_text_close(f);

    var manifest = json_parse(raw);
    return is_struct(manifest) ? manifest : undefined;
}

/// @function scr_score_manifest_normalize_image_meta(_image_meta, _beats_per_measure)
/// @description Normalize score image metadata so beat_anchors are always a fixed-length array (or missing) per entry.
/// @param {array} _image_meta Raw image_meta array from score_images.json
/// @param {real} _beats_per_measure Expected beats per measure from manifest metadata
/// @returns {array} Normalized image_meta array
/// @reads none
/// @writes none
/// @objects none
/// @callers scr_score_sprites_load, scr_score_group_bundle_load
function scr_score_manifest_normalize_image_meta(_image_meta, _beats_per_measure) {
    if (!is_array(_image_meta)) return [];

    var _beat_count = max(0, floor(real(_beats_per_measure)));
    var _out = array_create(array_length(_image_meta), undefined);
    for (var _mi = 0; _mi < array_length(_image_meta); _mi++) {
        var _meta_entry = _image_meta[_mi];
        if (!is_struct(_meta_entry)) {
            _out[_mi] = _meta_entry;
            continue;
        }

        var _normalized = variable_clone(_meta_entry);
        if (_beat_count > 0 && variable_struct_exists(_meta_entry, "beat_anchors") && is_array(_meta_entry.beat_anchors)) {
            var _raw = _meta_entry.beat_anchors;
            var _anchors = array_create(_beat_count, undefined);
            var _raw_n = array_length(_raw);
            var _copy_n = min(_beat_count, _raw_n);
            for (var _ai = 0; _ai < _copy_n; _ai++) {
                _anchors[_ai] = _raw[_ai];
            }
            _normalized.beat_anchors = _anchors;
        }

        _out[_mi] = _normalized;
    }

    return _out;
}

/// @function scr_score_sprites_load(_filename, _manifest)
/// @description Load per-measure score PNG sprites for a tune from a score/ subdirectory next to the tune JSON. Reads score_images.json manifest and populates global.score_lane_sprites, global.score_playback_map, and global.score_measure_map. Frees previously loaded sprites first.
/// @param {string} _filename  Tune JSON path (e.g. "tunes/BarnyrdsofDelgaty/BarnyrdsofDelgaty.json")
/// @param {struct|undefined} _manifest Optional pre-parsed score manifest
/// @reads   none
/// @writes  global.score_lane_sprites, global.score_playback_map, global.score_measure_map, global.score_transition_images, global.score_override_groups
/// @objects none
/// @callers scr_tune_load_into_global
function scr_score_sprites_load(_filename, _manifest) {
    // Free any previously loaded score sprites
    if (!variable_global_exists("score_lane_sprites")) {
        global.score_lane_sprites = [];
    } else {
        for (var i = 0; i < array_length(global.score_lane_sprites); i++) {
            var old_spr = global.score_lane_sprites[i];
            if (sprite_exists(old_spr)) sprite_delete(old_spr);
        }
        global.score_lane_sprites = [];
    }
    scr_score_override_groups_clear();

    // Derive parent directory from filename
    var last_slash = 0;
    for (var c = 1; c <= string_length(_filename); c++) {
        if (string_copy(_filename, c, 1) == "/") last_slash = c;
    }
    if (last_slash == 0) {
        show_debug_message("scr_score_sprites_load: no slash in filename, skipping");
        return;
    }
    var tune_dir      = string_copy(_filename, 1, last_slash); // "tunes/BarnyrdsofDelgaty/"
    var score_dir     = tune_dir + "score/";
    var manifest_path = score_dir + "score_images.json";

    var manifest = is_struct(_manifest) ? _manifest : scr_score_manifest_read(_filename);
    if (!is_struct(manifest) || !variable_struct_exists(manifest, "images")) {
        show_debug_message("scr_score_sprites_load: no manifest at " + manifest_path);
        return;
    }

    var images = manifest.images;
    for (var i = 0; i < array_length(images); i++) {
        var png_path = score_dir + images[i];
        var spr      = sprite_add(png_path, 1, false, false, 0, 0);
        array_push(global.score_lane_sprites, spr);
    }

    // Load measure_map if present (maps expanded measure index -> physical image index)
    if (!variable_global_exists("score_measure_map")) {
        global.score_measure_map = [];
    } else {
        global.score_measure_map = [];
    }
    if (variable_struct_exists(manifest, "measure_map")) {
        global.score_measure_map = manifest.measure_map;
    }

    // Load playback_to_image if present (new pipeline: explicit per-playback-measure → image index).
    // Maps seq index (0-based, repeat-expanded) directly to the physical sprite index.
    // Takes priority over score_measure_map in the score lane draw.
    if (!variable_global_exists("score_playback_map")) {
        global.score_playback_map = [];
    } else {
        global.score_playback_map = [];
    }
    if (variable_struct_exists(manifest, "playback_to_image")) {
        global.score_playback_map = manifest.playback_to_image;
    }

    // Load snippet_durations if present.
    // This is the authoritative structural timing for each rendered score image,
    // expressed in abstract note units from the export pipeline.
    if (!variable_global_exists("score_snippet_durations")) {
        global.score_snippet_durations = [];
    } else {
        global.score_snippet_durations = [];
    }
    if (variable_struct_exists(manifest, "snippet_durations")) {
        global.score_snippet_durations = manifest.snippet_durations;
    }

    // Load image_meta if present (geometry sidecar: staff positions, content bounds, beat anchors)
    if (!variable_global_exists("score_lane_meta")) {
        global.score_lane_meta = [];
    } else {
        global.score_lane_meta = [];
    }
    if (variable_struct_exists(manifest, "image_meta")) {
        var _meta_beats = variable_struct_exists(manifest, "beats_per_measure")
            ? real(manifest.beats_per_measure)
            : 0;
        global.score_lane_meta = scr_score_manifest_normalize_image_meta(manifest.image_meta, _meta_beats);
    }

    if (!variable_global_exists("score_transition_images")) {
        global.score_transition_images = {};
    } else {
        global.score_transition_images = {};
    }
    if (variable_struct_exists(manifest, "transition_images")) {
        global.score_transition_images = manifest.transition_images;
    }

    scr_score_override_groups_load_for_current_segment(_filename);

    // Load beats_per_measure / units_per_measure if present (snippets-style manifest)
    global.score_beats_per_measure = variable_struct_exists(manifest, "beats_per_measure")
        ? real(manifest.beats_per_measure) : 0;
    global.score_units_per_measure = variable_struct_exists(manifest, "units_per_measure")
        ? real(manifest.units_per_measure) : 0;

    var _sprite_count = array_length(global.score_lane_sprites);
    var _map_count    = array_length(global.score_measure_map);
    var _pbmap_count  = array_length(global.score_playback_map);
    show_debug_message("scr_score_sprites_load: loaded " + string(_sprite_count) + " sprites, "
        + string(array_length(global.score_lane_meta)) + " meta, "
        + string(_pbmap_count) + " playback_map entries from " + score_dir);

    // ---- Manifest validation diagnostics ----
    if (_pbmap_count > 0) {
        for (var _vi = 0; _vi < _pbmap_count; _vi++) {
            var _pmi = global.score_playback_map[_vi];
            if (_pmi < 0 || _pmi >= _sprite_count) {
                show_debug_message("scr_score_sprites_load WARNING: playback_to_image[" + string(_vi) + "] = " + string(_pmi) + " is out of range [0," + string(_sprite_count - 1) + "]");
            }
        }
    } else if (_map_count > 0) {
        var _prev_idx = -1;
        for (var _vi = 0; _vi < _map_count; _vi++) {
            var _mi = global.score_measure_map[_vi];
            if (_mi < 0 || _mi >= _sprite_count) {
                show_debug_message("scr_score_sprites_load WARNING: measure_map[" + string(_vi) + "] = " + string(_mi) + " is out of range [0," + string(_sprite_count - 1) + "]");
            }
            if (_mi < _prev_idx) {
                show_debug_message("scr_score_sprites_load WARNING: measure_map is non-monotonic at index " + string(_vi) + " (" + string(_prev_idx) + " -> " + string(_mi) + ")");
            }
            _prev_idx = _mi;
        }
    }
}

/// @function scr_score_override_groups_clear()
/// @description Free any currently loaded tail/head override sprite bundles.
/// @writes global.score_override_groups
function scr_score_override_groups_clear() {
    if (!variable_global_exists("score_override_groups") || !is_struct(global.score_override_groups)) {
        global.score_override_groups = {};
        return;
    }

    var group_names = ["tail", "head"];
    for (var gi = 0; gi < array_length(group_names); gi++) {
        var group_name = group_names[gi];
        if (!variable_struct_exists(global.score_override_groups, group_name)) continue;
        var bundle = global.score_override_groups[$ group_name];
        if (!is_struct(bundle)) continue;
        var sprites = bundle[$ "sprites"] ?? [];
        for (var si = 0; si < array_length(sprites); si++) {
            var spr = sprites[si];
            if (sprite_exists(spr)) sprite_delete(spr);
        }
    }

    global.score_override_groups = {};
}

/// @function scr_score_override_groups_load_for_current_segment(_filename)
/// @description Load tail/head override sprite bundles for the currently active set segment, if any.
/// @param {string} _filename Base segment filename currently being loaded
/// @writes global.score_override_groups
function scr_score_override_groups_load_for_current_segment(_filename) {
    global.score_override_groups = {};

    if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) return;
    if (string(global.playback_context[$ "mode"] ?? "") != "set") return;

    var seg_idx = floor(real(global.playback_context[$ "active_segment"] ?? 0));
    var segs = global.playback_context[$ "segments"];
    var plans = global.playback_context[$ "score_override_plan"] ?? [];
    if (!is_array(segs) || !is_array(plans)) return;

    var seg_count = array_length(segs);
    var plan_count = array_length(plans);
    if (seg_idx < 0 || seg_idx >= seg_count || seg_idx >= plan_count) return;

    var active_seg = segs[seg_idx];
    var active_filename = string(active_seg[$ "filename"] ?? "");
    if (active_filename != "" && _filename != "" && active_filename != _filename) {
        for (var i = 0; i < seg_count; i++) {
            if (string(segs[i][$ "filename"] ?? "") == _filename) {
                seg_idx = i;
                break;
            }
        }
        if (seg_idx >= plan_count) return;
    }

    var plan = plans[seg_idx];
    if (!is_struct(plan)) return;

    var tail_plan = plan[$ "tail_override"] ?? undefined;
    if (is_struct(tail_plan)) {
        var tail_transition_idx = floor(real(tail_plan[$ "transition_segment_index"] ?? -1));
        if (tail_transition_idx >= 0 && tail_transition_idx < seg_count) {
            var tail_filename = string(segs[tail_transition_idx][$ "filename"] ?? "");
            var tail_bundle = scr_score_group_bundle_load(tail_filename, tail_plan[$ "manifest_group"] ?? undefined, real(tail_plan[$ "count_measures"] ?? 0));
            if (is_struct(tail_bundle)) global.score_override_groups[$ "tail"] = tail_bundle;
        }
    }

    var head_plan = plan[$ "head_override"] ?? undefined;
    if (is_struct(head_plan)) {
        var head_transition_idx = floor(real(head_plan[$ "transition_segment_index"] ?? -1));
        if (head_transition_idx >= 0 && head_transition_idx < seg_count) {
            var head_filename = string(segs[head_transition_idx][$ "filename"] ?? "");
            var head_bundle = scr_score_group_bundle_load(head_filename, head_plan[$ "manifest_group"] ?? undefined, real(head_plan[$ "count_measures"] ?? 0));
            if (is_struct(head_bundle)) global.score_override_groups[$ "head"] = head_bundle;
        }
    }
}

/// @function scr_score_group_bundle_load(_transition_filename, _group_manifest, _count_measures)
/// @description Load one transition score-image group bundle from a transition tune score directory.
/// @param {string} _transition_filename Transition tune JSON path
/// @param {struct|undefined} _group_manifest Group manifest from transition_images
/// @param {real} _count_measures Number of measures this override should affect
/// @returns {struct|undefined} Bundle with sprites/meta/playback map, or undefined on failure
function scr_score_group_bundle_load(_transition_filename, _group_manifest, _count_measures) {
    if (!is_struct(_group_manifest)) return undefined;

    var images = _group_manifest[$ "images"] ?? undefined;
    if (!is_array(images) || array_length(images) <= 0) return undefined;

    var last_slash = 0;
    for (var c = 1; c <= string_length(_transition_filename); c++) {
        if (string_copy(_transition_filename, c, 1) == "/") last_slash = c;
    }
    if (last_slash == 0) return undefined;

    var tune_dir = string_copy(_transition_filename, 1, last_slash);
    var score_dir = tune_dir + "score/";

    var sprites = [];
    for (var i = 0; i < array_length(images); i++) {
        var png_path = score_dir + string(images[i]);
        var spr = sprite_add(png_path, 1, false, false, 0, 0);
        array_push(sprites, spr);
    }

    var _group_beats = variable_struct_exists(_group_manifest, "beats_per_measure")
        ? real(_group_manifest[$ "beats_per_measure"])
        : 0;

    return {
        sprites: sprites,
        meta: scr_score_manifest_normalize_image_meta(_group_manifest[$ "image_meta"] ?? [], _group_beats),
        playback_map: _group_manifest[$ "playback_to_image"] ?? [],
        count_measures: max(0, real(_count_measures)),
        pickup_image_index: real(_group_manifest[$ "pickup_image_index"] ?? -1)
    };
}
