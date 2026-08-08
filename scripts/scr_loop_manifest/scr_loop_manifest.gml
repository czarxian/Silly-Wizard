/// @function loop_build_manifest(_start_ref, _end_ref, _options)
/// @description Build a canonical loop manifest from structural refs using a strict half-open time window and explicit boundary cleanup note-offs.
/// @param {struct} _start_ref Start structural reference (selected ref shape from gv_loop_get_selected_measure_refs).
/// @param {struct} _end_ref End structural reference (selected ref shape from gv_loop_get_selected_measure_refs).
/// @param {struct|undefined} _options Optional settings: {events, start_ms, end_ms, metro_channel, run_parity_check, parity_debug_dump}.
/// @returns {struct} Loop manifest with boundary info, strict window events, cleanup events, and minimal timeline spans.
/// @reads global.playback_events, global.METRONOME_CONFIG
/// @writes none
/// @objects none
/// @callers scr_button_loop_build_playback_events
function loop_build_manifest(_start_ref, _end_ref, _options) {
    var out = {
        valid: false,
        manifest_version: "loop_v3_min",
        source: "loop_build_manifest",
        reason: "",
        boundary_info: {
            start_ms: -1,
            end_ms: -1,
            interval: "half_open",
            start_ref_resolved: {},
            end_ref_resolved: {},
            pickup_normalization: { applied: false }
        },
        selected_refs: {
            start_ref: _start_ref,
            end_ref: _end_ref,
            canonical_start_ref: {},
            canonical_end_ref: {}
        },
        window_events: [],
        cleanup_events: [],
        loop_time_spans: [],
        timeline_segments: [],
        measure_starts: [],
        score_mapping: {
            primary_domain: "sequence",
            playback_to_image_candidates: [],
            fallback_policy: "legacy_when_manifest_missing"
        },
        assertions: {
            pass1_note_on_equivalent: true,
            extra_events_allowed_only_cleanup_noteoff: true,
            mismatch_counts: {
                missing_note_on: 0,
                extra_note_on: 0
            }
        },
        debug: {
            compare_run_id: "",
            export_paths: {},
            stats: {
                base_window_event_count: 0,
                manifest_window_event_count: 0,
                cleanup_event_count: 0
            }
        }
    };

    var opts = is_struct(_options) ? _options : {};
    var events = variable_struct_exists(opts, "events") && is_array(variable_struct_get(opts, "events"))
        ? variable_struct_get(opts, "events")
        : ((variable_global_exists("playback_events") && is_array(global.playback_events)) ? global.playback_events : []);
    if (!is_array(events) || array_length(events) <= 0) {
        out.reason = "no_events";
        return out;
    }

    var start_ms = real(variable_struct_exists(opts, "start_ms") ? variable_struct_get(opts, "start_ms") : -1);
    var end_ms = real(variable_struct_exists(opts, "end_ms") ? variable_struct_get(opts, "end_ms") : -1);

    if (start_ms < 0 || end_ms <= start_ms + 0.001) {
        var refs = [];
        if (is_struct(_start_ref)) array_push(refs, _start_ref);
        if (is_struct(_end_ref)) array_push(refs, _end_ref);
        if (array_length(refs) >= 2
            && is_undefined(gv_loop_resolve_boundary_endpoints) == false) {
            var resolved = gv_loop_resolve_boundary_endpoints(refs);
            if (is_struct(resolved) && bool(resolved[$ "valid"] ?? false)) {
                start_ms = real(resolved[$ "start_ms"] ?? start_ms);
                end_ms = real(resolved[$ "end_ms"] ?? end_ms);
                out.boundary_info.start_ref_resolved = resolved[$ "start_boundary"] ?? {};
                out.boundary_info.end_ref_resolved = resolved[$ "end_boundary"] ?? {};
            }
        }
    }

    if (!(start_ms >= 0 && end_ms > start_ms + 0.001)) {
        out.reason = "invalid_boundaries";
        return out;
    }

    out.boundary_info.start_ms = start_ms;
    out.boundary_info.end_ms = end_ms;
    out.selected_refs.canonical_start_ref = is_struct(_start_ref) ? _start_ref : {};
    out.selected_refs.canonical_end_ref = is_struct(_end_ref) ? _end_ref : {};

    var metro_channel = variable_struct_exists(opts, "metro_channel")
        ? floor(real(variable_struct_get(opts, "metro_channel")))
        : ((variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG))
            ? floor(real(global.METRONOME_CONFIG.channel ?? 9))
            : 9);

    var window_events = [];
    var active_notes = {};
    // Treat the end boundary as strictly exclusive with a small epsilon so
    // boundary-timestamp events cannot leak into the loop payload due to
    // floating-point jitter from duration accumulation.
    var end_exclusive_ms = end_ms - 0.001;

    for (var i = 0; i < array_length(events); i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;

        var ev_time = real(ev[$ "time"] ?? 0);
        var ev_type = string(ev[$ "type"] ?? "");
        var ev_note = floor(real(ev[$ "note"] ?? -1));
        var ev_chan = floor(real(ev[$ "channel"] ?? -1));

        if (ev_type == "note_on" || ev_type == "note_off") {
            if (ev_note >= 0 && ev_chan >= 0 && ev_chan != metro_channel) {
                var note_key = string(ev_chan) + ":" + string(ev_note);
                var count = variable_struct_exists(active_notes, note_key)
                    ? floor(real(active_notes[$ note_key]))
                    : 0;
                if (ev_type == "note_on") {
                    if (ev_time < end_exclusive_ms) active_notes[$ note_key] = count + 1;
                } else {
                    if (ev_time < end_exclusive_ms) {
                        if (count > 0) active_notes[$ note_key] = count - 1;
                    }
                }
            }
        }

        if (ev_time < start_ms || ev_time >= end_exclusive_ms) continue;

        var cp = loop_manifest_clone_struct(ev);
        cp.canonical_event_id = i;
        cp.canonical_time_ms = ev_time;
        cp.canonical_part = floor(real(cp[$ "part"] ?? 1));
        cp.canonical_measure = floor(real(cp[$ "measure"] ?? -1));
        array_push(window_events, cp);
    }

    // Add explicit end-boundary cleanup note_offs for notes that remain active.
    var cleanup_events = [];
    var keys = variable_struct_get_names(active_notes);
    for (var ki = 0; ki < array_length(keys); ki++) {
        var k = string(keys[ki]);
        var remaining = floor(real(active_notes[$ k] ?? 0));
        if (remaining <= 0) continue;

        var split = string_pos(":", k);
        if (split <= 0) continue;
        var ch_txt = string_copy(k, 1, split - 1);
        var note_txt = string_delete(k, 1, split);
        var ch = floor(real(ch_txt));
        var note = floor(real(note_txt));

        for (var ci = 0; ci < remaining; ci++) {
            var off_ev = {
                type: "note_off",
                note: note,
                channel: ch,
                velocity: 0,
                time: end_ms,
                loop_is_cleanup_boundary: true
            };
            array_push(cleanup_events, off_ev);
        }
    }

    // Build minimal manifest spans from ownership map for downstream consumers.
    var spans = [];
    if (is_undefined(scr_button_build_measure_nav_map_for_ownership) == false) {
        var nav_map = scr_button_build_measure_nav_map_for_ownership(window_events);
        var entries = (is_struct(nav_map)
            && variable_struct_exists(nav_map, "entries")
            && is_array(variable_struct_get(nav_map, "entries")))
            ? variable_struct_get(nav_map, "entries")
            : [];
        for (var si = 0; si < array_length(entries); si++) {
            var e = entries[si];
            if (!is_struct(e)) continue;
            var ss = max(start_ms, real(e[$ "start_ms"] ?? -1));
            var se = min(end_ms, real(e[$ "end_ms"] ?? ss));
            if (ss < 0 || se <= ss + 0.001) continue;
            var sm = floor(real(e[$ "measure"] ?? -1));
            var sp = max(1, floor(real(e[$ "part"] ?? 1)));
            var key = string(sp) + ":" + string(sm) + ":" + string(si);
            array_push(spans, {
                start_ms: ss,
                end_ms: se,
                part: sp,
                measure: sm,
                nav_idx: si,
                owner_nav_idx: si,
                seq_hint: si,
                measure_ref_key: key
            });
        }
    }

    // Parity check: note_on set in window must match raw base window note_on set.
    var run_parity = !variable_struct_exists(opts, "run_parity_check")
        || bool(variable_struct_get(opts, "run_parity_check"));
    if (run_parity) {
        var base_map = loop_manifest_note_on_multiset(events, start_ms, end_ms);
        var loop_map = loop_manifest_note_on_multiset(window_events, start_ms, end_ms);
        var cmp = loop_manifest_compare_multiset(base_map, loop_map);
        var cmp_missing = floor(real(cmp[$ "missing"] ?? 0));
        var cmp_extra = floor(real(cmp[$ "extra"] ?? 0));
        out.assertions.pass1_note_on_equivalent = (cmp_missing == 0 && cmp_extra == 0);
        out.assertions.mismatch_counts.missing_note_on = cmp_missing;
        out.assertions.mismatch_counts.extra_note_on = cmp_extra;

        if ((!out.assertions.pass1_note_on_equivalent)
            && bool(variable_struct_exists(opts, "parity_debug_dump") ? variable_struct_get(opts, "parity_debug_dump") : false)
            && is_undefined(scr_button_export_planned_events_snapshot) == false) {
            var run_id = "manifest_v3_" + string(current_time);
            out.debug.compare_run_id = run_id;
            scr_button_export_planned_events_snapshot(events, "manifest_base", run_id);
            var dbg = [];
            for (var wi = 0; wi < array_length(window_events); wi++) array_push(dbg, window_events[wi]);
            for (var ci2 = 0; ci2 < array_length(cleanup_events); ci2++) array_push(dbg, cleanup_events[ci2]);
            scr_button_export_planned_events_snapshot(dbg, "manifest_window", run_id);
        }
    }

    out.window_events = window_events;
    out.cleanup_events = cleanup_events;
    out.loop_time_spans = spans;
    out.timeline_segments = spans;
    out.measure_starts = spans;
    out.debug.stats.base_window_event_count = array_length(window_events);
    out.debug.stats.manifest_window_event_count = array_length(window_events);
    out.debug.stats.cleanup_event_count = array_length(cleanup_events);
    out.valid = true;
    return out;
}

/// @function loop_manifest_clone_struct(_src)
/// @description Clone a struct shallowly for event-safe mutation.
/// @param {struct} _src Source struct.
/// @returns {struct} Cloned struct.
function loop_manifest_clone_struct(_src) {
    var out = {};
    if (!is_struct(_src)) return out;
    var keys = variable_struct_get_names(_src);
    for (var i = 0; i < array_length(keys); i++) {
        var k = string(keys[i]);
        out[$ k] = variable_struct_get(_src, k);
    }
    return out;
}

/// @function loop_manifest_note_on_multiset(_events, _start_ms, _end_ms)
/// @description Build a note_on multiset keyed by time/note/channel for parity checks.
/// @param {array} _events Event array.
/// @param {real} _start_ms Inclusive start.
/// @param {real} _end_ms Exclusive end.
/// @returns {struct} key -> count map.
function loop_manifest_note_on_multiset(_events, _start_ms, _end_ms) {
    var out = {};
    if (!is_array(_events)) return out;
    for (var i = 0; i < array_length(_events); i++) {
        var ev = _events[i];
        if (!is_struct(ev)) continue;
        if (string(ev[$ "type"] ?? "") != "note_on") continue;
        var t = real(ev[$ "time"] ?? 0);
        if (t < _start_ms || t >= _end_ms) continue;
        var n = floor(real(ev[$ "note"] ?? -1));
        var c = floor(real(ev[$ "channel"] ?? -1));
        var key = string_format(t, 0, 3) + "|" + string(n) + "|" + string(c);
        var count = variable_struct_exists(out, key) ? floor(real(out[$ key])) : 0;
        out[$ key] = count + 1;
    }
    return out;
}

/// @function loop_manifest_compare_multiset(_base_map, _loop_map)
/// @description Compare two multiset maps and return missing/extra counts.
/// @param {struct} _base_map Expected multiset.
/// @param {struct} _loop_map Observed multiset.
/// @returns {struct} {missing, extra}
function loop_manifest_compare_multiset(_base_map, _loop_map) {
    var missing = 0;
    var extra = 0;

    var keys_base = variable_struct_get_names(_base_map);
    for (var i = 0; i < array_length(keys_base); i++) {
        var kb = string(keys_base[i]);
        var b = floor(real(_base_map[$ kb] ?? 0));
        var l = variable_struct_exists(_loop_map, kb) ? floor(real(_loop_map[$ kb])) : 0;
        if (b > l) missing += (b - l);
    }

    var keys_loop = variable_struct_get_names(_loop_map);
    for (var j = 0; j < array_length(keys_loop); j++) {
        var kl = string(keys_loop[j]);
        var lv = floor(real(_loop_map[$ kl] ?? 0));
        var bv = variable_struct_exists(_base_map, kl) ? floor(real(_base_map[$ kl])) : 0;
        if (lv > bv) extra += (lv - bv);
    }

    return { missing: missing, extra: extra };
}
