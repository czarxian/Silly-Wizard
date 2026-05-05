// scr_set_scripts — Musical set loading, preprocessing, and playback stitching
// Purpose: Load a set JSON file, preprocess all constituent tunes with their
//          per-tune overrides, stitch into a single contiguous playback_events
//          array, and track which tune segment is active during playback.
//
// ──── TRANSITION-AUTHORITATIVE MODEL (Phase 1-2, May 2026) ────
// Transition tunes are the single source of truth for boundary behavior:
//  1. Transition exports must declare explicit replacement counts (prior/bridge/follow).
//  2. Each declared replacement group must have matching exported score images/payloads.
//  3. Set assembly builds a deterministic boundary plan from these declarations.
//  4. Runtime applies no inference from mixed event types (marker+note-on); only measure-index mapping.
//  5. Contract violations fail fast at preprocess time.
// See scr_set_validate_transition_contract() and scr_set_build_boundary_plan().
//
// Global state written:
//   global.active_set       — loaded set metadata + segments + boundary_plan (see scr_set_init_global)
//   global.playback_events  — stitched event array (shared with single-tune path)
//   global.playback_context — thin wrapper consumed by viz/scoring/export

// ─────────────────────────────────────────────────────────────────────────────
// Initialiser — called once from obj_game_controller Create
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_init_global()
/// @description Initialise global.active_set and global.playback_context to clean unloaded states.
/// @reads   none
/// @writes  global.active_set, global.playback_context
/// @objects none
/// @callers obj_game_controller Create
function scr_set_init_global() {
    global.active_set = {
        is_loaded:    false,
        filename:     "",
        title:        "",
        id:           "",
        description:  "",
        tunes:        [],
        segments:     [],
        score_override_plan: [],
        boundary_plan:       [],  // NEW: explicit transition-authoritative boundary plan
        active_segment_index: 0,
        first_bpm:    120,
        first_meter:  "4/4",
        // Set-level playback overrides (applied to every tune unless tune entry overrides)
        set_bpm_percent:         1.0,   // e.g. 0.85 = play whole set at 85% speed
        set_gracenote_override_ms: undefined, // ms override for all gracenotes, or undefined
        set_count_in_measures:    0           // count-in measures before first tune only
    };
    scr_playback_context_init();
    global.score_segments_sprites = []; // per-segment sprite cache for multi-segment score display
    global.playback_set_measure_nav_all = []; // flat prebuilt measure-nav table across all set segments
}

// ─────────────────────────────────────────────────────────────────────────────
// Transition Contract Validation (Phase 2)
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_validate_transition_contract(_tune_struct)
/// @description Validate that a transition tune export includes required contract fields.
///              Fails if: declared replacement counts > 0 but no matching group is exported.
/// @param _tune_struct  Loaded tune struct from scr_tune_load_to_struct()
/// @returns bool — true if valid, false on violation
function scr_set_validate_transition_contract(_tune_struct) {
    if (!is_struct(_tune_struct)) return true; // not a loaded tune, skip
    
    var meta = _tune_struct[$ "tune_data"] ?? {};
    var rhythm = string(meta[$ "rhythm"] ?? "");
    
    if (rhythm != "transition") return true; // not a transition, always valid
    
    // Extract declared replacement counts from metadata
    var prior_count = floor(real(meta[$ "head_cut_measures"] ?? 0));
    var bridge_count = floor(real(meta[$ "bridge_measures"] ?? 0));
    var follow_count = floor(real(meta[$ "tail_cut_measures"] ?? 0));
    
    // Check if score manifest exists
    var manifest = meta[$ "score_manifest"] ?? undefined;
    if (!is_struct(manifest)) {
        show_debug_message("  [VALIDATION] WARNING: transition tune has no score_manifest; replacement boundaries may be undefined");
        return true; // warn but don't fail (older exports)
    }
    
    var trans_score = manifest[$ "transition_score"] ?? {};
    if (!is_struct(trans_score)) {
        show_debug_message("  [VALIDATION] WARNING: transition score manifest has no transition_score object");
        return true;
    }
    
    // Validate each declared replacement group exists with matching content
    var violations = [];
    
    if (prior_count > 0) {
        var prior_group = trans_score[$ "prior_replace"] ?? undefined;
        if (!is_struct(prior_group)) {
            array_push(violations, "prior replacement declared (" + string(prior_count) + " measures) but prior_replace group missing");
        }
    }
    
    if (bridge_count > 0) {
        var bridge_group = trans_score[$ "bridge"] ?? undefined;
        if (!is_struct(bridge_group)) {
            array_push(violations, "bridge declared (" + string(bridge_count) + " measures) but bridge group missing");
        }
    }
    
    if (follow_count > 0) {
        var follow_group = trans_score[$ "follow_replace"] ?? undefined;
        if (!is_struct(follow_group)) {
            array_push(violations, "follow replacement declared (" + string(follow_count) + " measures) but follow_replace group missing");
        }
    }
    
    if (array_length(violations) > 0) {
        show_debug_message("  [VALIDATION ERROR] Transition contract violations:");
        for (var vi = 0; vi < array_length(violations); vi++) {
            show_debug_message("    - " + violations[vi]);
        }
        return false;
    }
    
    return true;
}

/// @function scr_set_build_boundary_plan(_tunes, _segments)
/// @description Build an explicit boundary plan for each transition boundary.
///              Plan defines: prior measures replaced, bridge inserted, follow measures replaced.
///              Fails if any transition violates the contract.
/// @param _tunes     Array of tune filenames from global.active_set.tunes[]
/// @param _segments  Array of segment structs from global.active_set.segments[]
/// @returns struct array OR false on contract violation
function scr_set_build_boundary_plan(_tunes, _segments) {
    var n = array_length(_segments);
    var plan = array_create(n);
    
    // Initialize: no replacement for any boundary
    for (var i = 0; i < n; i++) {
        plan[i] = {
            boundary_type: "none",
            transition_segment_index: -1,
            prior_measures_replaced: 0,
            bridge_measures_inserted: 0,
            follow_measures_replaced: 0
        };
    }
    
    // Scan each segment to find transitions and validate contract
    for (var ti = 0; ti < n; ti++) {
        var seg = _segments[ti];
        if (!is_struct(seg)) continue;
        
        var tune_file = string(seg[$ "tune_file"] ?? seg[$ "filename"] ?? "");
        var is_transition = (string(seg[$ "tune_rhythm"] ?? "") == "transition");
        
        if (!is_transition) continue;
        
        // Load full tune struct to validate contract
        var tune_path = scr_set_resolve_tune_path(tune_file);
        var tune_struct = scr_tune_load_to_struct(tune_path);
        
        if (!scr_set_validate_transition_contract(tune_struct)) {
            show_debug_message("  [BOUNDARY PLAN] FAILED: transition at segment " + string(ti) + " violates contract");
            return false;
        }
        
        // Extract declared replacement counts
        if (!is_struct(tune_struct)) continue;
        var meta = is_struct(tune_struct[$ "tune_data"] ?? undefined) ? tune_struct[$ "tune_data"] : {};
        var prior_count = floor(real(meta[$ "head_cut_measures"] ?? 0));
        var bridge_count = floor(real(meta[$ "bridge_measures"] ?? 0));
        var follow_count = floor(real(meta[$ "tail_cut_measures"] ?? 0));
        
        // Apply boundary plan using struct accessor notation
        if (ti > 0) {
            plan[ti - 1][$ "boundary_type"] = "transition";
            plan[ti - 1][$ "transition_segment_index"] = ti;
            plan[ti - 1][$ "prior_measures_replaced"] = prior_count;
        }
        
        plan[ti][$ "boundary_type"] = "transition";
        plan[ti][$ "transition_segment_index"] = ti;
        plan[ti][$ "bridge_measures_inserted"] = bridge_count;
        
        if (ti < n - 1) {
            plan[ti + 1][$ "boundary_type"] = "transition";
            plan[ti + 1][$ "transition_segment_index"] = ti;
            plan[ti + 1][$ "follow_measures_replaced"] = follow_count;
        }
    }
    
    show_debug_message("  [BOUNDARY PLAN] Built plan for " + string(n) + " segments");
    return plan;
}

// ─────────────────────────────────────────────────────────────────────────────
// Set loading
// ─────────────────────────────────────────────────────────────────────────────

/// @function scr_set_load_json(_filename)
/// @description Parse and validate a set JSON file, populate global.active_set.
/// @param _filename  Path relative to working_directory (e.g. "sets/my_msr.json")
/// @returns bool — true on success
/// @reads   none
/// @writes  global.active_set (is_loaded, filename, title, id, description, tunes, set_bpm_percent, etc.)
/// @objects none
/// @callers scr_button_scripts (set selection path)
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
    global.active_set.score_override_plan = [];
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
/// @reads   global.active_set (tunes, set_bpm_percent, set_gracenote_override_ms), global.metronome_mode, global.metronome_pattern_selection, global.metronome_volume
/// @writes  global.playback_events, global.active_set.segments, global.active_set.active_segment_index, global.active_set.is_loaded, global.active_set.first_bpm, global.active_set.first_meter
/// @objects none
/// @callers scr_button_scripts (set play path)
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
            var ci_bpm    = scr_set_entry_bpm(first_entry, first_struct) * real(global.active_set.set_bpm_percent ?? 1.0);
            var _td = first_struct[$ "tune_data"] ?? {};
            var _tm = _td[$ "tune_metadata"] ?? {};
            var ci_meter  = metronome_normalize_time_sig(string(_tm[$ "meter"] ?? "4/4"));
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

        // Transition tune metadata defines cuts for neighbors, not for itself
        // when stitched as part of a set.
        if (scr_set_is_transition_tune(entry, tune_struct)) {
            overrides.head_cut_beats = 0;
            overrides.tail_cut_beats = 0;
        }

        // Transition-tune semantics:
        // If adjacent entry is a transition tune, its metadata defines cuts on
        // neighboring tunes (tail on previous, head on next).
        if (ti > 0) {
            var prev_entry = global.active_set.tunes[ti - 1];
            var prev_file = scr_set_resolve_tune_path(string(prev_entry[$ "filename"] ?? ""));
            var prev_struct = scr_tune_load_to_struct(prev_file);
            if (!is_undefined(prev_struct) && scr_set_is_transition_tune(prev_entry, prev_struct)) {
                var prev_cuts = scr_set_get_transition_cuts(prev_struct);
                if (is_struct(prev_cuts) && real(prev_cuts[$ "head_cut_beats"] ?? 0) > 0) {
                    overrides[$ "head_cut_beats"] = prev_cuts[$ "head_cut_beats"];
                }
            }
        }

        if (ti < tune_count - 1) {
            var next_entry = global.active_set.tunes[ti + 1];
            var next_file = scr_set_resolve_tune_path(string(next_entry[$ "filename"] ?? ""));
            var next_struct = scr_tune_load_to_struct(next_file);
            if (!is_undefined(next_struct) && scr_set_is_transition_tune(next_entry, next_struct)) {
                var next_cuts = scr_set_get_transition_cuts(next_struct);
                if (is_struct(next_cuts) && real(next_cuts[$ "tail_cut_beats"] ?? 0) > 0) {
                    overrides[$ "tail_cut_beats"] = next_cuts[$ "tail_cut_beats"];
                }
            }
        }

        // capture first tune's timing for timeline binding in start_play
        if (ti == 0) {
            global.active_set.first_bpm   = scr_set_entry_bpm(entry, tune_struct);
            var _td2 = tune_struct[$ "tune_data"] ?? {};
            var _tm2 = _td2[$ "tune_metadata"] ?? {};
            global.active_set.first_meter = metronome_normalize_time_sig(string(_tm2[$ "meter"] ?? "4/4"));
        }

        // preprocess → tune events (0-based times)
        var tune_events = scr_preprocess_tune(tune_struct, overrides);

        // generate metronome events aligned to these tune events
        var metro_settings = {
            bpm: overrides[$ "bpm"],
            metronome_mode:    global.metronome_mode,
            metronome_pattern: global.metronome_pattern_selection,
            metronome_volume:  global.metronome_volume
        };
        var metro_events = metronome_generate_events({
            events:    tune_events,
            tune_data: tune_struct[$ "tune_data"]
        }, metro_settings);

        // tune duration = last event time (add a small tail so next tune doesn't overlap)
        var tune_end_ms = scr_set_max_event_time(tune_events);

        // Resolve segment BPM early (also needed for boundary lead-in computation below).
        var seg_bpm         = scr_set_entry_bpm(entry, tune_struct);
        var seg_bpm_percent = real(global.active_set.set_bpm_percent ?? 1.0);

        // ── fallback boundary lead-in (Option 2 model) ────────────────────────────────
        // When the next tune has a pickup and no authored gap/transition tune is present,
        // apply the appropriate fallback based on T1's measure boundary and T2's pickup status.
        var boundary_lead_in_ms   = 0;
        var boundary_metro_events = [];
        if (ti < tune_count - 1 && !scr_set_is_transition_tune(entry, tune_struct)) {
            var _bli_transition = entry[$ "transition"] ?? { type: "direct" };
            var _bli_trans_type = string(_bli_transition[$ "type"] ?? "direct");
            if (_bli_trans_type != "gap") {
                var _bli_next_entry  = global.active_set.tunes[ti + 1];
                var _bli_next_path   = scr_set_resolve_tune_path(string(_bli_next_entry[$ "filename"] ?? ""));
                var _bli_next_struct = scr_tune_load_to_struct(_bli_next_path);
                if (!is_undefined(_bli_next_struct) && !scr_set_is_transition_tune(_bli_next_entry, _bli_next_struct)) {
                    var _bli = scr_set_compute_boundary_lead_in(
                        tune_struct, tune_events, _bli_next_struct,
                        seg_bpm * seg_bpm_percent, _bli_next_entry);
                    boundary_lead_in_ms = real(_bli[$ "duration_ms"] ?? 0);
                    if (boundary_lead_in_ms > 0) {
                        scr_set_extend_last_note_off(tune_events, boundary_lead_in_ms);
                        var _bli_settings = {
                            bpm:               real(_bli[$ "leadin_bpm"] ?? 120),
                            metronome_mode:    global.metronome_mode,
                            metronome_pattern: global.metronome_pattern_selection,
                            metronome_volume:  global.metronome_volume
                        };
                        boundary_metro_events = metronome_generate_countin_events(
                            _bli_next_struct, _bli_settings, real(_bli[$ "leadin_measures"] ?? 0));
                        show_debug_message("  [Boundary] Case " + string(_bli[$ "boundary_case"]) + " lead-in: "
                            + string(floor(boundary_lead_in_ms)) + "ms (seg "
                            + string(ti) + "→" + string(ti + 1) + ")");
                    }
                }
            }
        }

        // Collect all events with a measure number for this tune (0-based time, pre-offset).
        // Including note events alongside bar/beat markers ensures gv_build_measure_nav_map
        // can fill in any measure that has no explicit marker, preventing gap skips
        // (e.g. measure 4 → 6) in the tune-structure panel.
        // Keep pickup bucket (measure 0) when present so score playback maps remain
        // index-aligned (seq 0 = pickup image, seq 1 = first full measure).
        var seg_bar_events = [];
        var seg_note_anchor_seen = {};
        var _te_n = array_length(tune_events);
        for (var _bei = 0; _bei < _te_n; _bei++) {
            var _bev = tune_events[_bei];
            if (!is_struct(_bev)) continue;
            var _bm = real(_bev[$ "measure"] ?? 0);
            if (_bm < 0) continue;

            var _bt = string(_bev[$ "type"] ?? "");
            if (_bt == "marker") {
                array_push(seg_bar_events, _bev);
                continue;
            }

            // Keep one representative note anchor per measure to let nav-map
            // fallback infer missing marker boundaries without multi-voice spam.
            if (_bt == "note_on") {
                var _mkey = string(floor(_bm));
                if (!variable_struct_exists(seg_note_anchor_seen, _mkey)) {
                    seg_note_anchor_seen[$ _mkey] = true;
                    array_push(seg_bar_events, _bev);
                }
            }
        }

        // record segment BEFORE offsetting
        var _td4 = tune_struct[$ "tune_data"] ?? {};
        var _tm4 = _td4[$ "tune_metadata"] ?? {};
        var seg_title = string(_tm4[$ "title"] ?? filename);
        // seg_bpm and seg_bpm_percent are declared above for boundary lead-in computation
        array_push(segments, {
            tune_index:  ti,
            filename:    filename,
            title:       seg_title,
            bpm:         seg_bpm * seg_bpm_percent,
            meter:       metronome_normalize_time_sig(string(_tm4[$ "meter"] ?? "4/4")),
            score_manifest: _td4[$ "score_manifest"] ?? {},
            start_ms:       offset_ms,
            content_end_ms: offset_ms + tune_end_ms,
            end_ms:         offset_ms + tune_end_ms + boundary_lead_in_ms,
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
                    var gap_bpm   = scr_set_entry_bpm(next_entry, next_struct) * real(global.active_set.set_bpm_percent ?? 1.0);
                    var _td3 = next_struct[$ "tune_data"] ?? {};
                    var _tm3 = _td3[$ "tune_metadata"] ?? {};
                    var gap_meter = metronome_normalize_time_sig(string(_tm3[$ "meter"] ?? "4/4"));
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
            } else if (boundary_lead_in_ms > 0) {
                // Fallback lead-in (Option 2): the last note of tune 1 has already been
                // extended in tune_events above.  Now insert metronome clicks for the
                // hold window and advance offset_ms so tune 2 starts at the right time.
                // metronome_generate_countin_events returns events with positive times
                // starting from 0; offset by offset_ms (= start of the hold window) so
                // they land in [offset_ms, offset_ms + boundary_lead_in_ms).
                scr_set_offset_and_append(all_events, boundary_metro_events, offset_ms);
                offset_ms += boundary_lead_in_ms;
            }
            // "direct" with no pickup in next tune — no action; tune 2 starts immediately
        }
    }

    // ── final sort and publish ─────────────────────────────────────────────
    array_sort(all_events, function(a, b) {
        return real(a[$ "time"] ?? 0) - real(b[$ "time"] ?? 0);
    });

    global.playback_events = all_events;
    global.active_set.segments = segments;
    
    // Build transition-authoritative boundary plan (Phase 2)
    var boundary_plan = scr_set_build_boundary_plan(global.active_set.tunes, segments);
    if (boundary_plan == false) {
        show_debug_message("Set preprocess FAILED: boundary plan validation error");
        return false;
    }
    global.active_set.boundary_plan = boundary_plan;
    
    // Keep legacy score override plan for backward compat (will deprecate in Phase 5)
    global.active_set.score_override_plan = scr_set_build_score_override_plan(segments);
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
/// @reads   global.active_set.segments
/// @callers scr_set_update_active_segment
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
/// @reads   global.active_set.active_segment_index
/// @writes  global.active_set.active_segment_index
/// @callers obj_game_controller Step
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
/// @writes  global.playback_context
/// @callers scr_set_init_global, scr_button_scripts
function scr_playback_context_init() {
    global.playback_context = {
        mode:           "none",   // "tune" | "set"
        display_title:  "",
        active_segment: 0,
        segments:       [],
        score_override_plan: []
    };
}

/// @function scr_playback_context_build_for_tune(_tune_struct)
/// @description Populate global.playback_context from a single loaded tune.
/// @param _tune_struct  The struct returned by scr_tune_load_to_struct, or global.tune
/// @reads   global.playback_events (bar/beat markers)
/// @writes  global.playback_context
/// @callers scr_button_scripts (single-tune play path)
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
        score_override_plan: [],
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
/// @reads   global.active_set.segments, global.active_set.title
/// @writes  global.playback_context
/// @callers scr_button_scripts (set play path)
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
            tune_index:     s.tune_index,
            filename:       s.filename,
            title:          s.title,
            bpm:            s.bpm,
            meter:          s.meter,
            start_ms:       s.start_ms,
            content_end_ms: s.content_end_ms,
            end_ms:         s.end_ms,
            bar_events:     abs_bars
        };
    }

    global.playback_context = {
        mode:           "set",
        display_title:  global.active_set.title,
        active_segment: 0,
        segments:       segs_out,
        score_override_plan: global.active_set.score_override_plan
    };
}

/// @function scr_set_transition_group(_score_manifest, _group_name)
/// @description Return a transition image group manifest from a score manifest, or undefined.
function scr_set_transition_group(_score_manifest, _group_name) {
    if (!is_struct(_score_manifest)) return undefined;
    var groups = _score_manifest[$ "transition_images"] ?? undefined;
    if (!is_struct(groups) || !variable_struct_exists(groups, _group_name)) return undefined;
    return groups[$ _group_name];
}

/// @function scr_set_build_score_override_plan(_segments)
/// @description Build a per-segment score override plan from transition score manifests.
///              This is metadata only; draw-time application happens elsewhere.
function scr_set_build_score_override_plan(_segments) {
    var n = array_length(_segments);
    var plan = array_create(n);

    for (var i = 0; i < n; i++) {
        plan[i] = {
            tail_override: undefined,
            bridge_override: undefined,
            head_override: undefined
        };
    }

    for (var ti = 0; ti < n; ti++) {
        var seg = _segments[ti];
        if (!is_struct(seg)) continue;
        var manifest = seg[$ "score_manifest"] ?? undefined;
        if (!is_struct(manifest)) continue;
        if (!(manifest[$ "is_transition"] ?? false)) continue;

        var refs = manifest[$ "transition_refs"] ?? {};
        var _tailRaw = refs[$ "tail_cut_measures"] ?? 0;
        var _headRaw = refs[$ "head_cut_measures"] ?? 0;
        var tailMeasures = (is_string(_tailRaw) && _tailRaw == "") ? 0 : real(_tailRaw);
        var headMeasures = (is_string(_headRaw) && _headRaw == "") ? 0 : real(_headRaw);
        var priorGroup = scr_set_transition_group(manifest, "prior_replace");
        var bridgeGroup = scr_set_transition_group(manifest, "bridge");
        var followGroup = scr_set_transition_group(manifest, "follow_replace");

        if (ti > 0 && is_struct(priorGroup)) {
            plan[ti - 1][$ "tail_override"] = {
                transition_segment_index: ti,
                count_measures: max(0, tailMeasures),
                refs: refs,
                manifest_group: priorGroup
            };
        }

        if (is_struct(bridgeGroup)) {
            plan[ti][$ "bridge_override"] = {
                transition_segment_index: ti,
                refs: refs,
                manifest_group: bridgeGroup
            };
        }

        if (ti < n - 1 && is_struct(followGroup)) {
            plan[ti + 1][$ "head_override"] = {
                transition_segment_index: ti,
                count_measures: max(0, headMeasures),
                refs: refs,
                manifest_group: followGroup
            };
        }
    }

    return plan;
}


/// @function scr_playback_context_get_active_segment()
/// @description Returns the active segment struct, or undefined if none.
/// @reads   global.playback_context
/// @callers scr_game_viz, scr_scoring, scr_UI_scripts
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
/// @reads   global.active_set
/// @callers scr_UI_scripts, scr_game_viz, scr_button_scripts
function scr_set_is_active() {
    return is_struct(global.active_set)
        && is_array(global.active_set.tunes)
        && array_length(global.active_set.tunes) > 0;
}

/// @function scr_gameinfo_update_title(_seg_index)
/// @description Update the gameinfo window title field based on the current
///              playback context. In set mode: "Set Title — Tune Title".
///              In tune mode: just the tune title. Safe to call at any time.
/// @reads   global.playback_context
/// @writes  global.gameinfo_title
/// @callers scr_set_update_active_segment, scr_button_scripts
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
/// @description Resolve a tune filename to the subfolder structure:
///              tunes/TuneName/TuneName.json
///              If the filename already contains a path separator it is returned as-is.
function scr_set_resolve_tune_path(_filename) {
    if (string_pos("/", _filename) > 0 || string_pos("\\", _filename) > 0) {
        return _filename;
    }
    // Strip .json extension to get the folder/file stem
    var _stem = _filename;
    if (string_lower(string_copy(_stem, string_length(_stem) - 4, 5)) == ".json") {
        _stem = string_copy(_stem, 1, string_length(_stem) - 5);
    }
    return "tunes/" + _stem + "/" + _stem + ".json";
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
/// @reads   global.active_set.set_bpm_percent, global.active_set.set_gracenote_override_ms
/// @callers scr_set_preprocess_and_build_playback
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

/// @function scr_set_parse_cut_beats(_raw)
/// @description Parse cut-beat metadata into a non-negative real.
function scr_set_parse_cut_beats(_raw) {
    var s = string_trim(string(_raw ?? ""));
    if (string_length(s) <= 0) return 0;
    var v = real(s);
    if (v < 0) v = 0;
    return v;
}

/// @function scr_set_transition_beats_per_measure(_tune_struct)
/// @description Resolve beats-per-measure for a transition tune from its meter metadata.
function scr_set_transition_beats_per_measure(_tune_struct) {
    var meta = _tune_struct.tune_data.tune_metadata;
    var meter = metronome_normalize_time_sig(string(meta[$ "meter"] ?? "4/4"));
    var parts = string_split(meter, "/");
    var beats = (array_length(parts) >= 1) ? real(parts[0]) : 4;
    if (beats <= 0) beats = 4;
    return beats;
}

/// @function scr_set_parse_cut_measures_to_beats(_raw_measures, _beats_per_measure)
/// @description Parse cut-measure metadata into beats (non-negative real).
function scr_set_parse_cut_measures_to_beats(_raw_measures, _beats_per_measure) {
    var measures = scr_set_parse_cut_beats(_raw_measures);
    if (measures <= 0) return 0;
    var bpm = max(1, real(_beats_per_measure));
    return measures * bpm;
}

/// @function scr_set_get_transition_cuts(_tune_struct)
/// @description Read tail/head cut values from transition metadata.
///              Supports legacy *_cut_beats and new *_cut_measures (converted to beats).
function scr_set_get_transition_cuts(_tune_struct) {
    var meta = _tune_struct.tune_data.tune_metadata;
    var beats_per_measure = scr_set_transition_beats_per_measure(_tune_struct);

    var tail_cut_beats = scr_set_parse_cut_beats(meta[$ "tail_cut_beats"] ?? "");
    var head_cut_beats = scr_set_parse_cut_beats(meta[$ "head_cut_beats"] ?? "");

    if (tail_cut_beats <= 0) {
        tail_cut_beats = scr_set_parse_cut_measures_to_beats(meta[$ "tail_cut_measures"] ?? "", beats_per_measure);
    }
    if (head_cut_beats <= 0) {
        head_cut_beats = scr_set_parse_cut_measures_to_beats(meta[$ "head_cut_measures"] ?? "", beats_per_measure);
    }

    return {
        tail_cut_beats: tail_cut_beats,
        head_cut_beats: head_cut_beats
    };
}

/// @function scr_set_is_transition_tune(_entry, _tune_struct)
/// @description Heuristic to identify transition tunes in a set.
function scr_set_is_transition_tune(_entry, _tune_struct) {
    if (!is_undefined(_tune_struct)) {
        var meta = _tune_struct.tune_data.tune_metadata;
        var rhythm = string_lower(string_trim(string(meta[$ "rhythm"] ?? "")));
        if (rhythm == "transition") return true;

        var title = string_lower(string_trim(string(meta[$ "title"] ?? "")));
        if (string_pos("transition", title) > 0) return true;
    }

    var fn = string_lower(string(_entry[$ "filename"] ?? ""));
    if (string_copy(fn, 1, 2) == "t_") return true;
    if (string_pos("transition", fn) > 0) return true;

    return false;
}

/// @function scr_set_extend_last_note_off(_events, _extend_ms)
/// @description Extend the latest note_off event in an array by _extend_ms.
///              Implements "hold last note" for Option 2 fallback boundary lead-in:
///              bagpipes can't stop, so the last note continues into the lead-in window.
/// @param _events     Playable event array (0-based ms times from scr_preprocess_tune)
/// @param _extend_ms  Milliseconds to add to the last note_off's time
/// @reads   none
/// @writes  _events (mutates last note_off event in-place)
/// @callers scr_set_preprocess_and_build_playback
function scr_set_extend_last_note_off(_events, _extend_ms) {
    if (_extend_ms <= 0) return;
    var n         = array_length(_events);
    var last_idx  = -1;
    var last_time = -1;
    for (var i = 0; i < n; i++) {
        var ev = _events[i];
        if (!is_struct(ev)) continue;
        if (string(ev[$ "type"] ?? "") != "note_off") continue;
        var t = real(ev[$ "time"] ?? 0);
        if (t > last_time) {
            last_time = t;
            last_idx  = i;
        }
    }
    if (last_idx >= 0) {
        _events[last_idx][$ "time"] += _extend_ms;
    }
}

/// @function scr_set_compute_boundary_lead_in(_t1_struct, _t1_events, _t2_struct, _t1_effective_bpm, _t2_entry)
/// @description Compute Option 2 fallback boundary lead-in when no transition tune is present.
///   Case 1: T2 has no pickup → duration_ms = 0 (direct handoff; BPM/meter change on beat 1).
///   Case 2: T1 ends mid-measure, T2 has no pickup → hold to complete T1's measure.
///   Cases 3 & 4 (unified): T2 has pickup. hold = remaining_in_T1_measure - T2_pickup_ms.
///     T1 at boundary (Case 3): remaining = t1_measure_ms, giving hold = measure - pickup.
///     T1 mid-measure (Case 4): remaining = t1_measure_ms - t1_measure_offset.
///     If hold < 0, roll by one T2 measure. If hold ≈ 0, direct handoff.
///   T1 pickup phase correction: the modulo uses (t1_tune_end_ms - t1_pickup_ms) so the
///   measure boundary is relative to the first downbeat, not the absolute timeline start.
/// @param _t1_struct         Loaded tune struct for tune 1
/// @param _t1_events         Preprocessed events array for tune 1 (0-based ms times)
/// @param _t2_struct         Loaded tune struct for tune 2
/// @param _t1_effective_bpm  Resolved BPM for tune 1 (including set bpm_percent)
/// @param _t2_entry          Set entry struct for tune 2 (for bpm override)
/// @returns struct {case, duration_ms, hold_note_extension_ms, leadin_measures, leadin_bpm}
/// @reads   global.active_set.set_bpm_percent
/// @writes  none
/// @callers scr_set_preprocess_and_build_playback
function scr_set_compute_boundary_lead_in(_t1_struct, _t1_events, _t2_struct, _t1_effective_bpm, _t2_entry) {
    var result = {
        boundary_case:          1,
        duration_ms:            0,
        hold_note_extension_ms: 0,
        leadin_measures:        0,
        leadin_bpm:             120
    };

    // Read T1 metadata
    var t1_meta         = _t1_struct.tune_data.tune_metadata;
    var t1_meter        = metronome_normalize_time_sig(string(t1_meta[$ "meter"] ?? "4/4"));
    var t1_parts        = string_split(t1_meter, "/");
    var t1_beats_per_meas = (array_length(t1_parts) >= 1) ? real(t1_parts[0]) : 4;
    var t1_measure_ms   = scr_set_beats_duration_ms(_t1_effective_bpm, t1_meter, t1_beats_per_meas);

    // Compute T1's tune duration (last event time)
    var t1_tune_end_ms  = scr_set_max_event_time(_t1_events);

    // Measure-phase offset: subtract T1's pickup so the modulo is relative to
    // the first downbeat, not the absolute start. Without this, a tune whose
    // total length happens to be a multiple of measure_ms (e.g. 1 pickup unit +
    // 16 full measures = 129 units → 128 units when bars land at 128 because
    // the bar is placed one unit before the mathematical boundary) would
    // incorrectly appear to end on a measure boundary.
    var t1_pickup_units   = real(t1_meta[$ "pickup_offset_units"] ?? 0);
    var t1_units_per_meas = real(t1_meta[$ "units_per_measure"] ?? 0);
    var t1_pickup_ms      = (t1_units_per_meas > 0)
        ? (t1_pickup_units * (t1_measure_ms / t1_units_per_meas))
        : 0;

    // Check if T1 ends mid-measure (phase-corrected).
    var t1_phase_ms = t1_tune_end_ms - t1_pickup_ms;
    if (t1_phase_ms < 0) {
        show_error("scr_set_compute_boundary_lead_in: T1 pickup_ms (" + string(t1_pickup_ms)
            + ") exceeds tune duration (" + string(t1_tune_end_ms) + "). Check pickup_offset_units metadata.", true);
    }
    var t1_measure_offset = t1_phase_ms mod t1_measure_ms;
    var t1_ends_mid_measure = (t1_measure_offset > 1.0); // allow 1ms tolerance for rounding

    // Read T2 pickup metadata
    var t2_meta         = _t2_struct.tune_data.tune_metadata;
    var t2_has_pickup   = bool(t2_meta[$ "has_pickup"] ?? false);
    var t2_pickup_units = real(t2_meta[$ "pickup_offset_units"] ?? 0);

    // ── Case 1 / 2: T2 has no pickup ──
    if (!t2_has_pickup || t2_pickup_units <= 0) {
        if (t1_ends_mid_measure) {
            // Case 2: complete the remaining space in T1's current measure.
            var c2_remaining_in_t1_measure = t1_measure_ms - t1_measure_offset;
            result.boundary_case          = 2;
            result.duration_ms            = c2_remaining_in_t1_measure;
            result.hold_note_extension_ms = c2_remaining_in_t1_measure;
            result.leadin_measures        = 0;
            result.leadin_bpm             = _t1_effective_bpm;
        }
        return result;
    }

    // ── T2 has a pickup ──
    var t2_meter          = metronome_normalize_time_sig(string(t2_meta[$ "meter"] ?? "4/4"));
    var t2_bpm            = scr_set_entry_bpm(_t2_entry, _t2_struct) * real(global.active_set.set_bpm_percent ?? 1.0);
    var t2_parts          = string_split(t2_meter, "/");
    var t2_beats_per_meas = (array_length(t2_parts) >= 1) ? real(t2_parts[0]) : 4;
    var t2_measure_ms     = scr_set_beats_duration_ms(t2_bpm, t2_meter, t2_beats_per_meas);

    // ── Cases 3 & 4: T2 has pickup ──
    // Unified formula: hold = (remaining space in T1's last measure) - T2 pickup.
    // When T1 ends exactly on a measure boundary (t1_measure_offset = 0, old Case 3),
    // remaining = t1_measure_ms and hold = t1_measure_ms - t2_pickup_ms.
    // When T1 ends mid-measure (old Case 4), remaining = t1_measure_ms - t1_measure_offset.
    // Roll by one T2 measure if hold < 0; clamp to 0 if ≈ 0.
    // This ensures T2's pickup fills the gap up to the next downbeat.
    var c4_remaining_in_t1_measure = t1_measure_ms - t1_measure_offset;
    var t2_units_per_measure = real(t2_meta[$ "units_per_measure"] ?? 0);
    if (t2_units_per_measure <= 0) {
        // Fallback for legacy/partial metadata: derive from denominator and beats-per-measure.
        // units_per_measure = beats_per_measure * (8 / denom) for unit-note default 1/8 pipeline.
        var t2_denom = (array_length(t2_parts) >= 2) ? real(t2_parts[1]) : 4;
        t2_units_per_measure = t2_beats_per_meas * (8 / max(1, t2_denom));
    }

    var t2_pickup_beats = (t2_units_per_measure > 0)
        ? (t2_pickup_units * (t2_beats_per_meas / t2_units_per_measure))
        : 0;
    var t2_pickup_ms = scr_set_beats_duration_ms(t2_bpm, t2_meter, t2_pickup_beats);

    // D = R + k*M - P, choose smallest k >= 0 such that D >= 0.
    var c4_hold_ms = c4_remaining_in_t1_measure - t2_pickup_ms;
    if (c4_hold_ms < 0) {
        c4_hold_ms += t2_measure_ms; // roll to next boundary if pickup is longer than remaining space
    }
    if (c4_hold_ms < 1.0) c4_hold_ms = 0; // tolerance for near-exact arithmetic

    // Preserve original case numbering for diagnostics (3 = T1 at boundary, 4 = mid-measure).
    result.boundary_case          = t1_ends_mid_measure ? 4 : 3;
    result.duration_ms            = c4_hold_ms;
    result.hold_note_extension_ms = c4_hold_ms;
    result.leadin_measures        = 0;
    result.leadin_bpm             = _t1_effective_bpm;
    return result;
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
