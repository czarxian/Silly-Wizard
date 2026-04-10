// scr_set_scripts — Musical set loading, preprocessing, and playback stitching
// Purpose: Load a set JSON file, preprocess all constituent tunes with their
//          per-tune overrides, stitch into a single contiguous playback_events
//          array, and track which tune segment is active during playback.
//
// Phase 1: direct and gap transitions only.
//          Transition content (alt endings, mini-tune fragments) is Phase 3.
//
// Global state written:
//   global.active_set       — loaded set metadata + segments (see scr_set_init_global)
//   global.playback_events  — stitched event array (shared with single-tune path)
//   global.playback_context — thin wrapper consumed by viz/scoring/export

// ─────────────────────────────────────────────────────────────────────────────
// Initialiser — called once from obj_game_controller Create
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_init_global()
/// @description Initialise global.active_set and global.playback_context to clean unloaded states.
function scr_set_init_global() {
    global.active_set = {
        is_loaded:    false,
        filename:     "",
        title:        "",
        id:           "",
        description:  "",
        tunes:        [],
        segments:     [],
        active_segment_index: 0,
        first_bpm:    120,
        first_meter:  "4/4",
        // Set-level playback overrides (applied to every tune unless tune entry overrides)
        set_bpm_percent:         1.0,   // e.g. 0.85 = play whole set at 85% speed
        set_gracenote_override_ms: undefined, // ms override for all gracenotes, or undefined
        set_count_in_measures:    0           // count-in measures before first tune only
    };
    scr_playback_context_init();
}

// ─────────────────────────────────────────────────────────────────────────────
// Set loading
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_load_json(_filename)
/// @description Parse and validate a set JSON file, populate global.active_set.
/// @param _filename  Path relative to working_directory (e.g. "sets/my_msr.json")
/// @returns bool — true on success
function scr_set_load_json(_filename) {
    show_debug_message("=== scr_set_load_json: " + string(_filename) + " ===");

    // ── parse ──────────────────────────────────────────────────────────────
    var f = file_text_open_read(_filename);
    if (f < 0) {
        show_debug_message("  ERROR: Cannot open file");
        return false;
    }
    var raw = "";
    while (!file_text_eof(f)) {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }
    file_text_close(f);

    var data = json_parse(raw);
    if (!is_struct(data)) {
        show_debug_message("  ERROR: JSON parse failed");
        return false;
    }

    // ── validate ───────────────────────────────────────────────────────────
    var set_meta = data[$ "set"] ?? undefined;
    var tunes    = data[$ "tunes"] ?? undefined;

    if (!is_struct(set_meta)) {
        show_debug_message("  ERROR: Missing 'set' struct");
        return false;
    }
    if (!is_array(tunes) || array_length(tunes) == 0) {
        show_debug_message("  ERROR: Missing or empty 'tunes' array");
        return false;
    }

    // ── populate global.active_set ─────────────────────────────────────────
    global.active_set.is_loaded   = false; // stays false until preprocess succeeds
    global.active_set.filename    = _filename;
    global.active_set.title       = string(set_meta[$ "title"] ?? "Untitled Set");
    global.active_set.id          = string(set_meta[$ "id"]    ?? scr_set_slugify(global.active_set.title));
    global.active_set.description = string(set_meta[$ "description"] ?? "");
    global.active_set.tunes       = tunes;
    global.active_set.segments    = [];
    global.active_set.active_segment_index = 0;

    // ── set-level playback overrides ───────────────────────────────────────
    var set_overrides = set_meta[$ "playback_overrides"] ?? undefined;
    global.active_set.set_bpm_percent = is_struct(set_overrides)
        ? real(set_overrides[$ "bpm_percent"] ?? 1.0) : 1.0;
    global.active_set.set_gracenote_override_ms = is_struct(set_overrides)
        ? (set_overrides[$ "gracenote_override_ms"] ?? undefined) : undefined;

    show_debug_message("  Loaded set '" + global.active_set.title + "' with "
                       + string(array_length(tunes)) + " tune(s)");
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Preprocessing & stitching
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_preprocess_and_build_playback(_count_in_measures)
/// @description Preprocess every tune in global.active_set, offset timestamps
///              so they form one contiguous timeline, and write the result into
///              global.playback_events.  Also populates global.active_set.segments.
/// @param _count_in_measures  Metronome count-in beats before the FIRST tune (0 = none)
/// @returns bool — true on success
function scr_set_preprocess_and_build_playback(_count_in_measures = 0) {
    if (!is_struct(global.active_set) || array_length(global.active_set.tunes) == 0) {
        show_debug_message("ERROR: scr_set_preprocess_and_build_playback — no set loaded");
        return false;
    }

    var all_events = [];
    var segments   = [];
    var offset_ms  = 0;   // running time cursor

    // ── optional count-in for first tune ──────────────────────────────────
    if (_count_in_measures > 0) {
        var first_entry  = global.active_set.tunes[0];
        var first_struct = scr_tune_load_to_struct(scr_set_resolve_tune_path(string(first_entry[$ "filename"] ?? "")));
        if (!is_undefined(first_struct)) {
            var ci_bpm    = scr_set_entry_bpm(first_entry, first_struct);
            var ci_meter  = metronome_normalize_time_sig(string(first_struct.tune_data.tune_metadata[$ "meter"] ?? "4/4"));
            var ci_beats_per_measure = real(string_split(ci_meter, "/")[0]);
            var ci_settings = {
                bpm:                ci_bpm,
                metronome_mode:     global.metronome_mode,
                metronome_pattern:  global.metronome_pattern_selection,
                metronome_volume:   global.metronome_volume
            };
            var ci_events   = metronome_generate_countin_events(first_struct, ci_settings, _count_in_measures);
            var ci_duration = scr_set_beats_duration_ms(ci_bpm, ci_meter, _count_in_measures * ci_beats_per_measure);
            // count-in events start at time=0; offset_ms is 0 here so just append
            scr_set_append_events(all_events, ci_events);
            offset_ms += ci_duration;
        }
    }

    // ── process each tune ──────────────────────────────────────────────────
    var tune_count = array_length(global.active_set.tunes);
    for (var ti = 0; ti < tune_count; ti++) {
        var entry = global.active_set.tunes[ti];
        var filename = scr_set_resolve_tune_path(string(entry[$ "filename"] ?? ""));

        show_debug_message("  [Set tune " + string(ti + 1) + "/" + string(tune_count) + "] " + filename);

        // load tune without touching global.tune
        var tune_struct = scr_tune_load_to_struct(filename);
        if (is_undefined(tune_struct)) {
            show_debug_message("  ERROR: Failed to load tune — aborting set preprocess");
            return false;
        }

        // build overrides from set entry (all optional)
        var overrides = scr_set_entry_overrides(entry, tune_struct);

        // capture first tune's timing for timeline binding in start_play
        if (ti == 0) {
            global.active_set.first_bpm   = scr_set_entry_bpm(entry, tune_struct);
            global.active_set.first_meter = metronome_normalize_time_sig(string(tune_struct.tune_data.tune_metadata[$ "meter"] ?? "4/4"));
        }

        // preprocess → tune events (0-based times)
        var tune_events = scr_preprocess_tune(tune_struct, overrides);

        // generate metronome events aligned to these tune events
        var metro_settings = {
            bpm: overrides.bpm,
            metronome_mode:    global.metronome_mode,
            metronome_pattern: global.metronome_pattern_selection,
            metronome_volume:  global.metronome_volume
        };
        var metro_events = metronome_generate_events({
            events:    tune_events,
            tune_data: tune_struct.tune_data
        }, metro_settings);

        // tune duration = last event time (add a small tail so next tune doesn't overlap)
        var tune_end_ms = scr_set_max_event_time(tune_events);

        // Collect all events with a measure number for this tune (0-based time, pre-offset).
        // Including note events alongside bar/beat markers ensures gv_build_measure_nav_map
        // can fill in any measure that has no explicit marker, preventing gap skips
        // (e.g. measure 4 → 6) in the tune-structure panel.
        var seg_bar_events = [];
        var _te_n = array_length(tune_events);
        for (var _bei = 0; _bei < _te_n; _bei++) {
            var _bev = tune_events[_bei];
            if (!is_struct(_bev)) continue;
            var _bm = real(_bev[$ "measure"] ?? 0);
            if (_bm >= 1) array_push(seg_bar_events, _bev);
        }

        // record segment BEFORE offsetting
        var seg_title = string(tune_struct.tune_data.tune_metadata[$ "title"] ?? filename);
        var seg_bpm   = scr_set_entry_bpm(entry, tune_struct);
        var seg_bpm_percent = real(global.active_set.set_bpm_percent ?? 1.0);
        array_push(segments, {
            tune_index:  ti,
            filename:    filename,
            title:       seg_title,
            bpm:         seg_bpm * seg_bpm_percent,
            meter:       metronome_normalize_time_sig(string(tune_struct.tune_data.tune_metadata[$ "meter"] ?? "4/4")),
            start_ms:    offset_ms,
            end_ms:      offset_ms + tune_end_ms,
            bar_events:  seg_bar_events  // 0-based times — add start_ms to get absolute
        });

        // offset and append tune + metro events
        scr_set_offset_and_append(all_events, tune_events,  offset_ms);
        scr_set_offset_and_append(all_events, metro_events, offset_ms);

        offset_ms += tune_end_ms;

        // ── transition to next tune ───────────────────────────────────────
        if (ti < tune_count - 1) {
            var transition = entry[$ "transition"] ?? { type: "direct" };
            var trans_type = string(transition[$ "type"] ?? "direct");

            if (trans_type == "gap") {
                var gap_beats   = real(transition[$ "beats"] ?? 4);
                var next_entry  = global.active_set.tunes[ti + 1];
                var next_struct = scr_tune_load_to_struct(scr_set_resolve_tune_path(string(next_entry[$ "filename"] ?? "")));
                if (!is_undefined(next_struct)) {
                    var gap_bpm   = scr_set_entry_bpm(next_entry, next_struct);
                    var gap_meter = metronome_normalize_time_sig(string(next_struct.tune_data.tune_metadata[$ "meter"] ?? "4/4"));
                    var gap_beats_per_measure = real(string_split(gap_meter, "/")[0]);
                    // Round up to full measures so the gap uses the pattern grid
                    var gap_measures = max(1, ceil(gap_beats / gap_beats_per_measure));
                    var gap_settings = {
                        bpm:                gap_bpm,
                        metronome_mode:     global.metronome_mode,
                        metronome_pattern:  global.metronome_pattern_selection,
                        metronome_volume:   global.metronome_volume
                    };
                    var gap_events = metronome_generate_countin_events(next_struct, gap_settings, gap_measures);
                    var gap_ms     = scr_set_beats_duration_ms(gap_bpm, gap_meter, gap_measures * gap_beats_per_measure);
                    scr_set_offset_and_append(all_events, gap_events, offset_ms);
                    offset_ms += gap_ms;
                }
            }
            // "direct" — no gap, offset_ms stays at tune_end boundary
        }
    }

    // ── final sort and publish ─────────────────────────────────────────────
    array_sort(all_events, function(a, b) {
        return real(a[$ "time"] ?? 0) - real(b[$ "time"] ?? 0);
    });

    global.playback_events = all_events;
    global.active_set.segments = segments;
    global.active_set.active_segment_index = 0;
    global.active_set.is_loaded = true;

    show_debug_message("Set preprocess complete: "
        + string(array_length(all_events)) + " events, "
        + string(tune_count) + " segments, total duration ~"
        + string(floor(offset_ms / 1000)) + "s");
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Segment tracking (called each step during playback)
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_get_active_segment_index(_elapsed_ms)
/// @description Return the segment index whose time window contains _elapsed_ms.
///              Returns the last segment if past the end.
function scr_set_get_active_segment_index(_elapsed_ms) {
    var segs = global.active_set.segments;
    var n = array_length(segs);
    if (n == 0) return 0;

    for (var i = n - 1; i >= 0; i--) {
        if (_elapsed_ms >= segs[i].start_ms) return i;
    }
    return 0;
}

/// @function scr_set_update_active_segment(_elapsed_ms)
/// @description Update global.active_set.active_segment_index; returns true if
///              the index changed (caller can react to tune boundary crossing).
function scr_set_update_active_segment(_elapsed_ms) {
    var new_idx = scr_set_get_active_segment_index(_elapsed_ms);
    if (new_idx != global.active_set.active_segment_index) {
        global.active_set.active_segment_index = new_idx;
        return true;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Playback context — thin wrapper consumed by viz, scoring, export
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_playback_context_init()
/// @description Reset global.playback_context to an empty state.
function scr_playback_context_init() {
    global.playback_context = {
        mode:           "none",   // "tune" | "set"
        display_title:  "",
        active_segment: 0,
        segments:       []
    };
}

/// @function scr_playback_context_build_for_tune(_tune_struct)
/// @description Populate global.playback_context from a single loaded tune.
/// @param _tune_struct  The struct returned by scr_tune_load_to_struct, or global.tune
function scr_playback_context_build_for_tune(_tune_struct) {
    var meta  = _tune_struct.tune_data.tune_metadata;
    var title = string(meta[$ "title"] ?? "");
    var bpm_s = string(meta[$ "tempo_default"] ?? "120");
    var bpm   = (string_length(bpm_s) > 0) ? real(bpm_s) : 120;
    var meter = metronome_normalize_time_sig(string(meta[$ "meter"] ?? "4/4"));

    // Extract bar/beat marker events from global.playback_events (times already final)
    var bar_events = [];
    if (variable_global_exists("playback_events") && is_array(global.playback_events)) {
        var _n = array_length(global.playback_events);
        for (var _i = 0; _i < _n; _i++) {
            var _ev = global.playback_events[_i];
            if (!is_struct(_ev)) continue;
            if (string(_ev[$ "type"] ?? "") == "marker") {
                var _mt = string(_ev[$ "marker_type"] ?? "");
                if (_mt == "bar" || _mt == "beat") array_push(bar_events, _ev);
            }
        }
    }

    global.playback_context = {
        mode:           "tune",
        display_title:  title,
        active_segment: 0,
        segments: [{
            tune_index:  0,
            filename:    string(_tune_struct.tune_data.filename ?? ""),
            title:       title,
            bpm:         bpm,
            meter:       meter,
            start_ms:    0,
            end_ms:      scr_set_max_event_time(global.playback_events),
            bar_events:  bar_events
        }]
    };
}

/// @function scr_playback_context_build_for_set()
/// @description Populate global.playback_context from global.active_set after preprocess.
function scr_playback_context_build_for_set() {
    var segs_src = global.active_set.segments;
    var n        = array_length(segs_src);
    var segs_out = array_create(n);
    for (var i = 0; i < n; i++) {
        var s = segs_src[i];
        // bar_events hold references to the same structs mutated by scr_set_offset_and_append,
        // so orig.time is already absolute. We deep-copy to avoid aliasing and sync ALL
        // time fields (time_ms, timestamp_ms, expected_ms) to the same absolute value so
        // gv_evt_time_ms — which prefers time_ms over time — reads the correct absolute time.
        var abs_bars = [];
        var nb = array_length(s.bar_events);
        for (var bi = 0; bi < nb; bi++) {
            var orig = s.bar_events[bi];
            var copy = {};
            var keys = struct_get_names(orig);
            for (var ki = 0; ki < array_length(keys); ki++) {
                copy[$ keys[ki]] = orig[$ keys[ki]];
            }
            var abs_t = real(orig[$ "time"] ?? 0); // already absolute
            copy[$ "time"] = abs_t;
            if (variable_struct_exists(orig, "time_ms"))      copy[$ "time_ms"]      = abs_t;
            if (variable_struct_exists(orig, "timestamp_ms")) copy[$ "timestamp_ms"] = abs_t;
            if (variable_struct_exists(orig, "expected_ms"))  copy[$ "expected_ms"]  = abs_t;
            array_push(abs_bars, copy);
        }
        segs_out[i] = {
            tune_index:  s.tune_index,
            filename:    s.filename,
            title:       s.title,
            bpm:         s.bpm,
            meter:       s.meter,
            start_ms:    s.start_ms,
            end_ms:      s.end_ms,
            bar_events:  abs_bars
        };
    }

    global.playback_context = {
        mode:           "set",
        display_title:  global.active_set.title,
        active_segment: 0,
        segments:       segs_out
    };
}


/// @function scr_playback_context_get_active_segment()
/// @description Returns the active segment struct, or undefined if none.
function scr_playback_context_get_active_segment() {
    if (!variable_global_exists("playback_context")) return undefined;
    var ctx = global.playback_context;
    var segs = ctx[$ "segments"] ?? [];
    var idx  = clamp(real(ctx[$ "active_segment"] ?? 0), 0, max(0, array_length(segs) - 1));
    return (array_length(segs) > 0) ? segs[idx] : undefined;
}

/// @function scr_set_is_active()
/// @description Returns true when a set JSON has been loaded (tunes populated).
///              Does NOT require preprocess to have completed yet.
function scr_set_is_active() {
    return is_struct(global.active_set)
        && is_array(global.active_set.tunes)
        && array_length(global.active_set.tunes) > 0;
}

/// @function scr_gameinfo_update_title(_seg_index)
/// @description Update the gameinfo window title field based on the current
///              playback context. In set mode: "Set Title — Tune Title".
///              In tune mode: just the tune title. Safe to call at any time.
function scr_gameinfo_update_title(_seg_index) {
    if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) return;

    var ctx        = global.playback_context;
    var mode       = string(ctx[$ "mode"] ?? "tune");
    var set_title  = string(ctx[$ "display_title"] ?? "");
    var segs       = ctx[$ "segments"] ?? [];
    var idx        = clamp(floor(real(_seg_index)), 0, max(0, array_length(segs) - 1));
    var tune_title = (array_length(segs) > 0) ? string(segs[idx][$ "title"] ?? "") : "";

    var display = "";
    if (mode == "set" && string_length(set_title) > 0 && string_length(tune_title) > 0) {
        display = set_title + " \u2014 " + tune_title;  // em dash separator
    } else if (string_length(tune_title) > 0) {
        display = tune_title;
    } else {
        display = set_title;
    }

    if (string_length(display) > 0) {
        global.gameinfo_title[0] = display;
        scr_update_fields(3); // push to gameplay_layer fields
    }
}

/// @function scr_set_resolve_tune_path(_filename)
/// @description Prepend "tunes/" prefix if the filename has no path separator.
function scr_set_resolve_tune_path(_filename) {
    if (string_pos("/", _filename) > 0 || string_pos("\\", _filename) > 0) {
        return _filename;
    }
    return "tunes/" + _filename;
}

/// @function scr_set_entry_bpm(_entry, _tune_struct)
/// @description Resolve effective BPM: set entry override → tune default → 120.
function scr_set_entry_bpm(_entry, _tune_struct) {
    var v = _entry[$ "bpm"] ?? undefined;
    if (!is_undefined(v)) return real(v);
    if (!is_undefined(_tune_struct)) {
        var ts = string(_tune_struct.tune_data.tune_metadata[$ "tempo_default"] ?? "");
        if (string_length(ts) > 0) return real(ts);
    }
    return 120;
}

/// @function scr_set_entry_overrides(_entry, _tune_struct)
/// @description Build an overrides struct for scr_preprocess_tune from a set tune entry.
///              Priority: tune-entry > set-level > tune-JSON default.
function scr_set_entry_overrides(_entry, _tune_struct) {
    // Resolve BPM: entry bpm × set bpm_percent (entry wins if specified, then scale)
    var entry_bpm = _entry[$ "bpm"] ?? undefined;
    var base_bpm  = !is_undefined(entry_bpm)
        ? real(entry_bpm)
        : scr_set_entry_bpm(_entry, _tune_struct);
    var bpm_percent = real(global.active_set.set_bpm_percent ?? 1.0);
    var effective_bpm = (bpm_percent != 1.0 || !is_undefined(entry_bpm))
        ? base_bpm * bpm_percent
        : undefined; // leave undefined so preprocess uses tune default

    // Gracenote: entry > set-level > undefined
    var grace = _entry[$ "gracenote_override_ms"] ?? global.active_set.set_gracenote_override_ms ?? undefined;

    return {
        bpm:                   effective_bpm,
        swing_mult:            _entry[$ "swing"] ?? undefined,
        gracenote_override_ms: grace
    };
}

/// @function scr_set_max_event_time(_events)
/// @description Return the highest `time` value in an event array, or 0.
function scr_set_max_event_time(_events) {
    var mx = 0;
    var n  = array_length(_events);
    for (var i = 0; i < n; i++) {
        var t = real(_events[i][$ "time"] ?? 0);
        if (t > mx) mx = t;
    }
    return mx;
}

/// @function scr_set_offset_and_append(_dest, _src, _offset_ms)
/// @description Offset every event in _src by _offset_ms then push into _dest.
function scr_set_offset_and_append(_dest, _src, _offset_ms) {
    var n = array_length(_src);
    for (var i = 0; i < n; i++) {
        var ev = _src[i];
        ev[$ "time"] = real(ev[$ "time"] ?? 0) + _offset_ms;
        array_push(_dest, ev);
    }
}

/// @function scr_set_append_events(_dest, _src)
/// @description Append all events from _src into _dest without offsetting.
function scr_set_append_events(_dest, _src) {
    var n = array_length(_src);
    for (var i = 0; i < n; i++) {
        array_push(_dest, _src[i]);
    }
}

/// @function scr_set_beats_duration_ms(_bpm, _meter, _beat_count)
/// @description Convert a number of beats to milliseconds at the given BPM/meter.
function scr_set_beats_duration_ms(_bpm, _meter, _beat_count) {
    var norm   = metronome_normalize_time_sig(string(_meter));
    var parts  = string_split(norm, "/");
    var denom  = (array_length(parts) >= 2) ? real(parts[1]) : 4;
    var qbpm   = metronome_get_effective_quarter_bpm(_bpm, norm);
    var ms_per_beat = 60000 / qbpm * (4 / denom);
    return ms_per_beat * _beat_count;
}

/// @function scr_set_slugify(_str)
/// @description Convert a title string to a lowercase filename-safe slug.
function scr_set_slugify(_str) {
    var s = string_lower(string_trim(string(_str)));
    var out = "";
    for (var i = 1; i <= string_length(s); i++) {
        var c = string_copy(s, i, 1);
        if (c == " " || c == "-") {
            out += "_";
        } else if ((ord(c) >= ord("a") && ord(c) <= ord("z"))
                || (ord(c) >= ord("0") && ord(c) <= ord("9"))
                || c == "_") {
            out += c;
        }
    }
    return out;
}
