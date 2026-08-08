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
    if (!is_struct(manifest)) return undefined;

    // Merge pickup/snippet fields from the sibling .score_snippets.json if present.
    // score_images.json has no pickup awareness; the snippets bundle does.
    var base_name = "";
    var last_slash2 = 0;
    var _tune_base = "";
    for (var _c2 = 1; _c2 <= string_length(_filename); _c2++) {
        if (string_copy(_filename, _c2, 1) == "/") last_slash2 = _c2;
    }
    if (last_slash2 > 0) {
        _tune_base = string_copy(_filename, last_slash2 + 1, string_length(_filename) - last_slash2);
        _tune_base = string_replace(_tune_base, ".json", "");
        var _snippets_path = tune_dir + _tune_base + ".score_snippets.json";
        var _sf = file_text_open_read(_snippets_path);
        if (_sf >= 0) {
            var _sraw = "";
            while (!file_text_eof(_sf)) {
                _sraw += file_text_read_string(_sf);
                file_text_readln(_sf);
            }
            file_text_close(_sf);
            var _snippets_manifest = json_parse(_sraw);
            if (is_struct(_snippets_manifest)) {
                if (variable_struct_exists(_snippets_manifest, "has_pickup"))
                    manifest.has_pickup = _snippets_manifest.has_pickup;
                if (variable_struct_exists(_snippets_manifest, "snippets"))
                    manifest.snippets = _snippets_manifest.snippets;
                if (variable_struct_exists(_snippets_manifest, "units_per_measure")
                    && !variable_struct_exists(manifest, "units_per_measure"))
                    manifest.units_per_measure = _snippets_manifest.units_per_measure;
            }
        }
    }

    if (last_slash2 > 0) {
        var _groups_path = tune_dir + _tune_base + ".score_groups.json";
        var _gf = file_text_open_read(_groups_path);
        if (_gf >= 0) {
            var _graw = "";
            while (!file_text_eof(_gf)) {
                _graw += file_text_read_string(_gf);
                file_text_readln(_gf);
            }
            file_text_close(_gf);
            var _groups_manifest = json_parse(_graw);
            if (is_struct(_groups_manifest)) {
                if (variable_struct_exists(_groups_manifest, "groups") && is_array(_groups_manifest.groups)) {
                    manifest.groups = _groups_manifest.groups;
                }
                if (variable_struct_exists(_groups_manifest, "part_groups") && is_array(_groups_manifest.part_groups)) {
                    manifest.part_groups = _groups_manifest.part_groups;
                }
                if (variable_struct_exists(_groups_manifest, "default_group")) {
                    manifest.default_group = _groups_manifest.default_group;
                }
                if (variable_struct_exists(_groups_manifest, "default_part_channel")) {
                    manifest.default_part_channel = _groups_manifest.default_part_channel;
                } else if (variable_struct_exists(_groups_manifest, "default_channel")) {
                    manifest.default_part_channel = _groups_manifest.default_channel;
                }
            }
        }
    }

    return manifest;
}

/// @function scr_score_manifest_get_group_list(_manifest)
/// @description Return the first available group array from a score manifest, supporting both `groups` and `part_groups`.
/// @param {struct|undefined} _manifest Score manifest struct
/// @returns {array} Group array or [] when none are present
function scr_score_manifest_get_group_list(_manifest) {
    if (!is_struct(_manifest)) return [];
    if (variable_struct_exists(_manifest, "groups") && is_array(variable_struct_get(_manifest, "groups"))) return variable_struct_get(_manifest, "groups");
    if (variable_struct_exists(_manifest, "part_groups") && is_array(variable_struct_get(_manifest, "part_groups"))) return variable_struct_get(_manifest, "part_groups");
    return [];
}

/// @function scr_score_manifest_group_supports_channel(_group, _channel)
/// @description Return true when a group explicitly supports a given player part channel.
/// @param {struct} _group Group struct from score groups list
/// @param {real} _channel Target player part channel
/// @returns {bool} True when supported
function scr_score_manifest_group_supports_channel(_group, _channel) {
    if (!is_struct(_group)) return false;
    var target_channel = floor(real(_channel));
    if (target_channel < 0) return false;

    if (variable_struct_exists(_group, "part_channels") && is_array(_group.part_channels)) {
        var group_channels = _group.part_channels;
        for (var i = 0; i < array_length(group_channels); i++) {
            if (floor(real(group_channels[i])) == target_channel) return true;
        }
    }

    if (variable_struct_exists(_group, "part_channel")) {
        if (floor(real(_group.part_channel)) == target_channel) return true;
    }
    if (variable_struct_exists(_group, "channel")) {
        if (floor(real(_group.channel)) == target_channel) return true;
    }

    return false;
}

/// @function scr_score_manifest_merge_group(_manifest, _group)
/// @description Merge selected group fields over a cloned root manifest.
/// @param {struct} _manifest Root manifest
/// @param {struct} _group Selected group struct
/// @returns {struct} Merged manifest
function scr_score_manifest_merge_group(_manifest, _group) {
    var merged = variable_clone(_manifest);
    if (!is_struct(_group)) return merged;

    var copy_fields = ["group", "part_channel", "part_channels", "part_label", "subdir", "images", "playback_to_image", "image_meta", "measure_map", "snippet_durations", "snippets", "has_pickup", "beats_per_measure", "units_per_measure", "pickup_image_index", "transition_images"];
    for (var fi = 0; fi < array_length(copy_fields); fi++) {
        var key = copy_fields[fi];
        if (variable_struct_exists(_group, key)) {
            variable_struct_set(merged, key, variable_struct_get(_group, key));
        }
    }
    merged.selected_group = _group;
    return merged;
}

/// @function scr_score_manifest_resolve_source(_manifest, _part_channel)
/// @description Resolve score source for a selected part channel using explicit group/default rules with base-manifest fallback.
/// @param {struct|undefined} _manifest Score manifest struct
/// @param {real} _part_channel Selected player MIDI channel
/// @returns {struct} {manifest, selected_group, target_channel, resolved_channel, source, matched}
function scr_score_manifest_resolve_source(_manifest, _part_channel) {
    var out = {
        manifest: _manifest,
        selected_group: undefined,
        target_channel: -1,
        resolved_channel: -1,
        source: "none",
        matched: false
    };

    if (!is_struct(_manifest)) return out;

    var groups = scr_score_manifest_get_group_list(_manifest);
    var target_channel = floor(real(_part_channel));
    if (target_channel < 0) {
        target_channel = floor(real(scr_tune_picker_get_selected_part_channel()));
    }
    out.target_channel = target_channel;

    if (array_length(groups) <= 0) {
        out.manifest = _manifest;
        out.source = "base_no_groups";
        out.matched = true;
        return out;
    }

    // 1) Exact channel match.
    for (var i = 0; i < array_length(groups); i++) {
        var group_exact = groups[i];
        if (!is_struct(group_exact)) continue;
        if (scr_score_manifest_group_supports_channel(group_exact, target_channel)) {
            out.selected_group = group_exact;
            out.manifest = scr_score_manifest_merge_group(_manifest, group_exact);
            out.resolved_channel = target_channel;
            out.source = "group_exact_channel";
            out.matched = true;
            return out;
        }
    }

    // 2) Explicit manifest default group name.
    if (variable_struct_exists(_manifest, "default_group")) {
        var default_group_name = string(_manifest.default_group);
        if (default_group_name != "") {
            for (var gi = 0; gi < array_length(groups); gi++) {
                var named_group = groups[gi];
                if (!is_struct(named_group)) continue;
                var group_name = variable_struct_exists(named_group, "group") ? string(named_group.group) : "";
                if (group_name == default_group_name) {
                    out.selected_group = named_group;
                    out.manifest = scr_score_manifest_merge_group(_manifest, named_group);
                    out.resolved_channel = variable_struct_exists(named_group, "part_channel") ? floor(real(named_group.part_channel)) : -1;
                    out.source = "group_default_name";
                    out.matched = true;
                    return out;
                }
            }
        }
    }

    // 3) Explicit manifest default channel.
    var default_channel = -1;
    if (variable_struct_exists(_manifest, "default_part_channel")) {
        default_channel = floor(real(_manifest.default_part_channel));
    } else if (variable_struct_exists(_manifest, "default_channel")) {
        default_channel = floor(real(_manifest.default_channel));
    }
    if (default_channel >= 0) {
        for (var di = 0; di < array_length(groups); di++) {
            var group_default_channel = groups[di];
            if (!is_struct(group_default_channel)) continue;
            if (scr_score_manifest_group_supports_channel(group_default_channel, default_channel)) {
                out.selected_group = group_default_channel;
                out.manifest = scr_score_manifest_merge_group(_manifest, group_default_channel);
                out.resolved_channel = default_channel;
                out.source = "group_default_channel";
                out.matched = true;
                return out;
            }
        }
    }

    // 4) Group-level explicit default marker.
    for (var mi = 0; mi < array_length(groups); mi++) {
        var marked_group = groups[mi];
        if (!is_struct(marked_group)) continue;
        var is_default = (variable_struct_exists(marked_group, "is_default") && bool(marked_group.is_default))
            || (variable_struct_exists(marked_group, "default") && bool(variable_struct_get(marked_group, "default")));
        if (!is_default) continue;

        out.selected_group = marked_group;
        out.manifest = scr_score_manifest_merge_group(_manifest, marked_group);
        out.resolved_channel = variable_struct_exists(marked_group, "part_channel") ? floor(real(marked_group.part_channel)) : -1;
        out.source = "group_marked_default";
        out.matched = true;
        return out;
    }

    // 5) No match/defaults: keep base manifest (important for main-part correctness).
    out.manifest = _manifest;
    out.source = "base_fallback_no_match";
    out.matched = false;
    return out;
}

/// @function scr_score_manifest_select_group(_manifest, _part_channel)
/// @description Resolve a selected-part score group from a manifest, or return the legacy manifest when no groups are available.
/// @param {struct|undefined} _manifest Score manifest struct
/// @param {real} _part_channel Selected player MIDI channel
/// @returns {struct|undefined} Selected group struct or original manifest when no groups exist
function scr_score_manifest_select_group(_manifest, _part_channel) {
    var resolved = scr_score_manifest_resolve_source(_manifest, _part_channel);
    return resolved.manifest;
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

        var root_manifest = manifest;
        var selected_part_channel = scr_tune_picker_get_selected_part_channel();
        var resolved_source = scr_score_manifest_resolve_source(manifest, selected_part_channel);
        var selected_group = resolved_source.selected_group;
        manifest = resolved_source.manifest;

        if (is_struct(manifest)) {
            manifest.score_source = resolved_source.source;
            manifest.score_target_channel = resolved_source.target_channel;
        }

        if (resolved_source.source == "base_fallback_no_match") {
            show_debug_message("scr_score_sprites_load: no exact/default group for channel " + string(selected_part_channel) + ", using base score manifest");
        }

        if (is_struct(selected_group) && variable_struct_exists(selected_group, "subdir")) {
            var group_subdir = string(variable_struct_get(selected_group, "subdir"));
            if (string_length(group_subdir) > 0) {
                if (string_copy(group_subdir, string_length(group_subdir), 1) != "/") group_subdir += "/";
                var group_manifest_path = score_dir + group_subdir + "score_images.json";
                var _group_f = file_text_open_read(group_manifest_path);
                if (_group_f >= 0) {
                    var _group_raw = "";
                    while (!file_text_eof(_group_f)) {
                        _group_raw += file_text_read_string(_group_f);
                        file_text_readln(_group_f);
                    }
                    file_text_close(_group_f);
                    var _group_manifest = json_parse(_group_raw);
                    if (is_struct(_group_manifest)) {
                        manifest = _group_manifest;
                        var _merge_fields = ["has_pickup", "snippets", "snippet_durations", "units_per_measure", "beats_per_measure"];
                        for (var _mfi = 0; _mfi < array_length(_merge_fields); _mfi++) {
                            var _mkey = _merge_fields[_mfi];
                            if (variable_struct_exists(root_manifest, _mkey) && !variable_struct_exists(manifest, _mkey)) {
                                variable_struct_set(manifest, _mkey, variable_struct_get(root_manifest, _mkey));
                            }
                        }
                        score_dir += group_subdir;
                    }
                }
            }
        }

        // Re-apply selected group metadata over the loaded manifest so the loader keeps
        // selected channel/subdir even when the group score_images.json is sparse.
        if (is_struct(selected_group)) {
            var _group_fields = ["group", "part_channel", "part_label", "subdir"];
            for (var _gfi = 0; _gfi < array_length(_group_fields); _gfi++) {
                var _gkey = _group_fields[_gfi];
                if (variable_struct_exists(selected_group, _gkey)) {
                    variable_struct_set(manifest, _gkey, variable_struct_get(selected_group, _gkey));
                }
            }
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
    } else if (variable_struct_exists(manifest, "snippets") && is_array(manifest.snippets)) {
        // Manifest stores durations per-snippet; extract into the flat array GML expects.
        var _snip_arr = manifest.snippets;
        var _snip_n = array_length(_snip_arr);
        var _flat_dur = array_create(_snip_n, 0);
        for (var _si = 0; _si < _snip_n; _si++) {
            var _snip = _snip_arr[_si];
            _flat_dur[_si] = is_struct(_snip) ? real(_snip[$ "duration_units"] ?? 0) : 0;
        }
        global.score_snippet_durations = _flat_dur;
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
    if (!variable_global_exists("score_has_pickup")) global.score_has_pickup = false;
    global.score_has_pickup = variable_struct_exists(manifest, "has_pickup")
        ? bool(manifest.has_pickup) : false;

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

/// @function scr_score_segment_runtime_cache_clear()
/// @description Delete dynamic score and override sprites retained by every preloaded set-segment cache entry.
/// @returns none
/// @reads global.score_segments_sprites
/// @writes global.score_segments_sprites, global.score_override_groups
/// @callers scr_goto_playroom
function scr_score_segment_runtime_cache_clear() {
    var caches = variable_global_exists("score_segments_sprites") ? global.score_segments_sprites : [];
    if (is_array(caches)) {
        for (var cache_index = 0; cache_index < array_length(caches); cache_index++) {
            var cache_entry = caches[cache_index];
            if (!is_struct(cache_entry)) continue;
            var sprites = cache_entry[$ "sprites"] ?? [];
            for (var cache_sprite_index = 0; cache_sprite_index < array_length(sprites); cache_sprite_index++) {
                var sprite_id = sprites[cache_sprite_index];
                if (sprite_exists(sprite_id)) sprite_delete(sprite_id);
            }
            var override_groups = cache_entry[$ "override_groups"] ?? {};
            if (!is_struct(override_groups)) continue;
            var group_names = ["tail", "head"];
            for (var group_index = 0; group_index < array_length(group_names); group_index++) {
                var group_name = group_names[group_index];
                if (!variable_struct_exists(override_groups, group_name)) continue;
                var bundle = override_groups[$ group_name];
                if (!is_struct(bundle)) continue;
                var bundle_sprites = bundle[$ "sprites"] ?? [];
                for (var bundle_index = 0; bundle_index < array_length(bundle_sprites); bundle_index++) {
                    var bundle_sprite = bundle_sprites[bundle_index];
                    if (sprite_exists(bundle_sprite)) sprite_delete(bundle_sprite);
                }
            }
        }
    }
    global.score_segments_sprites = [];
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

/// @function scr_score_sprites_reload_current_tune()
/// @description Reload score sprites for the currently loaded tune using the active selected player part channel.
/// @returns {bool} True if a current tune was found and reloaded.
/// @reads global.tune, global.tune.tune_data.filename, global.tune.tune_data.score_manifest
/// @writes global.score_lane_sprites, global.score_playback_map, global.score_measure_map, global.score_lane_meta, global.score_transition_images, global.score_snippet_durations, global.score_has_pickup
function scr_score_sprites_reload_current_tune() {
    if (!variable_global_exists("tune") || !instance_exists(global.tune)) return false;
    var _tune_data = variable_instance_get(global.tune, "tune_data");
    if (!is_struct(_tune_data)) return false;

    var _filename = string(_tune_data[$ "filename"] ?? "");
    if (_filename == "") return false;

    scr_score_sprites_load(_filename, _tune_data[$ "score_manifest"] ?? undefined);
    return true;
}
