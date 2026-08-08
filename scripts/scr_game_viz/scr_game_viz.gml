// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

/// @function gv_parse_meter(_meter_text)
/// @description Parse a meter string like "6/8" into [numerator, denominator]. Returns [4,4] on invalid input.
/// @param {string} _meter_text  Meter string in "num/den" format.
/// @returns {array}  Two-element array [numerator, denominator], each clamped to minimum 1.
function gv_parse_meter(_meter_text) {
    var _num = 4;
    var _den = 4;

    if (!is_undefined(_meter_text)) {
        var _parts = string_split(string(_meter_text), "/");
        if (array_length(_parts) == 2) {
            _num = max(1, real(_parts[0]));
            _den = max(1, real(_parts[1]));
        }
    }

    return [_num, _den];
}

/// @function gv_measure_ms(_bpm, _meter_num, _meter_den)
/// @description Calculate the duration of one measure in milliseconds for the given BPM and time signature.
/// @param {real} _bpm        Beats per minute (quarter-note BPM).
/// @param {real} _meter_num  Numerator of the time signature.
/// @param {real} _meter_den  Denominator of the time signature.
/// @returns {real}  Duration of one measure in ms.
function gv_measure_ms(_bpm, _meter_num, _meter_den) {
    var _quarter_ms = 60000 / max(1, real(_bpm));
    return _quarter_ms * real(_meter_num) * (4 / real(_meter_den));
}


/// @function gv_evt_time_ms(_e)
/// @description Extract the timestamp in ms from a planned-event struct, checking multiple field names (time_ms, time, timestamp_ms, expected_ms).
/// @param {struct} _e  Planned event struct.
/// @returns {real}  Event timestamp in ms, or 0 if not found.
function gv_evt_time_ms(_e) {
    if (!is_struct(_e)) return 0;
    if (variable_struct_exists(_e, "time_ms")) return real(_e.time_ms);
    if (variable_struct_exists(_e, "time")) return real(_e.time);
    if (variable_struct_exists(_e, "timestamp_ms")) return real(_e.timestamp_ms);
    if (variable_struct_exists(_e, "expected_ms")) return real(_e.expected_ms);
    return 0;
}

/// @function gv_note_key(_ch, _note)
/// @description Build a unique string key for a MIDI note on a given channel (format: "ch:note").
/// @param {real} _ch    MIDI channel number.
/// @param {real} _note  MIDI note number.
/// @returns {string}  Key string like "2:73".
function gv_note_key(_ch, _note) {
    return string(_ch) + ":" + string(_note);
}

/// @function gv_build_loop_runtime_cache(_events)
/// @description Precompute single-tune loop runtime timing metadata once so draw/measure lookup can avoid per-frame event scans.
/// @param {array} _events Planned playback events (typically global.playback_events_active)
/// @returns {struct} Cache {valid, iter1_start_ms, iter2_start_ms, phase_start_ms, phase_iteration, loop_cycle_ms, measure_starts, fallback_measure_ms}
/// @reads global.METRONOME_CONFIG
function gv_build_loop_runtime_cache(_events) {
    var _cache = {
        valid: false,
        iter1_start_ms: -1,
        iter2_start_ms: -1,
        phase_start_ms: -1,
        phase_iteration: 1,
        loop_cycle_ms: 0,
        measure_starts: [],
        fallback_measure_ms: 1000
    };
    if (!is_array(_events) || array_length(_events) <= 0) return _cache;

    var _skip_met = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var _met_ch = _skip_met ? floor(real(global.METRONOME_CONFIG.channel ?? 9)) : -999;
    var _has_pickup_map = variable_global_exists("score_has_pickup") && bool(global.score_has_pickup);

    var _iter_start_boundary = {};
    var _iter_start_any = {};
    var _ne = array_length(_events);

    for (var _i = 0; _i < _ne; _i++) {
        var _ev = _events[_i];
        if (!is_struct(_ev)) continue;
        var _iter = floor(real(_ev[$ "loop_iteration"] ?? 0));
        if (_iter <= 0) continue;

        var _iter_key = string(_iter);
        var _et = gv_evt_time_ms(_ev);
        if (!variable_struct_exists(_iter_start_any, _iter_key)
            || _et < real(_iter_start_any[$ _iter_key])) {
            _iter_start_any[$ _iter_key] = _et;
        }

        if (string(_ev[$ "type"] ?? "") != "marker") continue;

        var _mt = string(_ev[$ "marker_type"] ?? "");
        var _beat = floor(real(_ev[$ "beat"] ?? 0));
        var _frac = real(_ev[$ "beat_fraction"] ?? 0);
        var _is_boundary = (_mt == "bar") || (_mt == "beat" && _beat == 1 && abs(_frac) <= 0.001);
        if (!_is_boundary) continue;

        if (!variable_struct_exists(_iter_start_boundary, _iter_key)
            || _et < real(_iter_start_boundary[$ _iter_key])) {
            _iter_start_boundary[$ _iter_key] = _et;
        }
    }

    var _iter1_start = variable_struct_exists(_iter_start_boundary, "1")
        ? real(_iter_start_boundary[$ "1"])
        : (variable_struct_exists(_iter_start_any, "1") ? real(_iter_start_any[$ "1"]) : -1);
    var _iter2_start = variable_struct_exists(_iter_start_boundary, "2")
        ? real(_iter_start_boundary[$ "2"])
        : (variable_struct_exists(_iter_start_any, "2") ? real(_iter_start_any[$ "2"]) : -1);
    var _iter3_start = variable_struct_exists(_iter_start_boundary, "3")
        ? real(_iter_start_boundary[$ "3"])
        : (variable_struct_exists(_iter_start_any, "3") ? real(_iter_start_any[$ "3"]) : -1);

    // Prefer steady-state phase (iteration 2 -> 3) so spacer/blank loops normalize correctly.
    var _phase_start = _iter1_start;
    var _phase_iteration = 1;
    var _loop_cycle_ms = 0;
    if (_iter2_start >= 0 && _iter3_start > _iter2_start) {
        _phase_start = _iter2_start;
        _phase_iteration = 2;
        _loop_cycle_ms = _iter3_start - _iter2_start;
    } else if (_iter1_start >= 0 && _iter2_start > _iter1_start) {
        _phase_start = _iter1_start;
        _phase_iteration = 1;
        _loop_cycle_ms = _iter2_start - _iter1_start;
    }

    if (_loop_cycle_ms <= 1) {
        var _iter_keys = variable_struct_get_names(_iter_start_any);
        if (is_array(_iter_keys) && array_length(_iter_keys) >= 2) {
            for (var _ik = 1; _ik < array_length(_iter_keys); _ik++) {
                var _iv = floor(real(_iter_keys[_ik]));
                var _jk = _ik - 1;
                while (_jk >= 0 && floor(real(_iter_keys[_jk])) > _iv) {
                    _iter_keys[_jk + 1] = _iter_keys[_jk];
                    _jk--;
                }
                _iter_keys[_jk + 1] = _iv;
            }

            for (var _pi = 0; _pi < array_length(_iter_keys) - 1; _pi++) {
                var _a_key = string(floor(real(_iter_keys[_pi])));
                var _b_key = string(floor(real(_iter_keys[_pi + 1])));
                if (!variable_struct_exists(_iter_start_any, _a_key) || !variable_struct_exists(_iter_start_any, _b_key)) continue;
                var _a_t = real(_iter_start_any[$ _a_key]);
                var _b_t = real(_iter_start_any[$ _b_key]);
                if (_b_t > _a_t) {
                    _phase_start = _a_t;
                    _phase_iteration = floor(real(_iter_keys[_pi]));
                    _loop_cycle_ms = _b_t - _a_t;
                    break;
                }
            }
        }
    }

    // Keep measure-start extraction anchored to iteration 1 when available so
    // first-pass score image mapping matches current-measure highlighting.
    // Phase normalization still uses steady-state anchor/cycle for repeat passes.
    var _measure_iter_ref = (_iter1_start >= 0) ? 1 : max(1, _phase_iteration);

    // Layered runtime model: if loop_session provides explicit timeline segments,
    // use them as the primary timing source for measure/image projection.
    var _ls_segments = [];
    if (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "loop_session")
        && is_struct(global.timeline_state.loop_session)) {
        var _ls_for_cache = global.timeline_state.loop_session;
        if (variable_struct_exists(_ls_for_cache, "active")
            && bool(variable_struct_get(_ls_for_cache, "active"))
            && variable_struct_exists(_ls_for_cache, "timeline_segments")
            && is_array(variable_struct_get(_ls_for_cache, "timeline_segments"))) {
            _ls_segments = variable_struct_get(_ls_for_cache, "timeline_segments");
            if (_loop_cycle_ms <= 1) {
                var _ls_pass_cache = max(0, real(variable_struct_exists(_ls_for_cache, "pass_duration_ms") ? variable_struct_get(_ls_for_cache, "pass_duration_ms") : 0));
                var _ls_spacer_cache = max(0, real(variable_struct_exists(_ls_for_cache, "spacer_duration_ms") ? variable_struct_get(_ls_for_cache, "spacer_duration_ms") : 0));
                var _ls_cycle_cache = _ls_pass_cache + _ls_spacer_cache;
                if (_ls_cycle_cache > 1) {
                    _loop_cycle_ms = _ls_cycle_cache;
                }
            }
            if (_phase_start < 0 && variable_struct_exists(_ls_for_cache, "start_ms")) {
                _phase_start = real(variable_struct_get(_ls_for_cache, "start_ms"));
            }
        }
    }

    if (is_array(_ls_segments) && array_length(_ls_segments) > 0) {
        if (array_length(_ls_segments) > 1) {
            array_sort(_ls_segments, function(a, b) {
                var as = real(a[$ "start_ms"] ?? 0);
                var bs = real(b[$ "start_ms"] ?? 0);
                if (as != bs) return as - bs;
                var an = floor(real(a[$ "seq"] ?? 0));
                var bn = floor(real(b[$ "seq"] ?? 0));
                return an - bn;
            });
        }

        var _seg_measure_starts = [];
        for (var _sgi = 0; _sgi < array_length(_ls_segments); _sgi++) {
            var _seg = _ls_segments[_sgi];
            if (!is_struct(_seg)) continue;
            var _ss = real(_seg[$ "start_ms"] ?? -1);
            var _se = real(_seg[$ "end_ms"] ?? -1);
            if (_ss < 0 || _se <= _ss + 0.001) continue;

            var _sm_timeline = floor(real(_seg[$ "timeline_measure"] ?? (_seg[$ "measure"] ?? -1)));
            var _sm_owner = floor(real(_seg[$ "owner_measure"] ?? _sm_timeline));
            var _sm_part = max(1, floor(real(_seg[$ "part"] ?? 1)));
            var _sm_value = (_sm_timeline >= 1) ? _sm_timeline : _sm_owner;
            if (_sm_value < 1) continue;
            var _sm_seq = (_sm_value == 0) ? 0 : (_sm_value - (_has_pickup_map ? 0 : 1));

            array_push(_seg_measure_starts, {
                m: _sm_value,
                p: _sm_part,
                b: 1,
                t: _ss,
                seq: _sm_seq,
                seg_idx: -1,
                seg_title: "",
                seg_start_ms: _ss,
                seg_end_ms: _se
            });
        }

        var _seg_n = array_length(_seg_measure_starts);
        if (_seg_n > 0) {
            var _seg_fallback = 1000;
            if (_seg_n >= 2) {
                _seg_fallback = max(1,
                    real(_seg_measure_starts[_seg_n - 1][$ "t"] ?? 0)
                    - real(_seg_measure_starts[_seg_n - 2][$ "t"] ?? 0));
            } else if (_loop_cycle_ms > 1) {
                _seg_fallback = _loop_cycle_ms;
            }

            _cache.iter1_start_ms = (_iter1_start >= 0) ? _iter1_start : real(_seg_measure_starts[0][$ "t"] ?? -1);
            _cache.iter2_start_ms = _iter2_start;
            _cache.phase_start_ms = (_phase_start >= 0) ? _phase_start : _cache.iter1_start_ms;
            _cache.phase_iteration = _phase_iteration;
            _cache.loop_cycle_ms = _loop_cycle_ms;
            _cache.measure_starts = _seg_measure_starts;
            _cache.fallback_measure_ms = _seg_fallback;
            _cache.valid = (_cache.phase_start_ms >= 0) && (_cache.loop_cycle_ms > 1);
            return _cache;
        }
    }

    var _measure_starts = [];
    var _last_key = "";
    for (var _i = 0; _i < _ne; _i++) {
        var _ev = _events[_i];
        if (!is_struct(_ev)) continue;
        if (string(_ev[$ "type"] ?? "") != "marker") continue;

        var _iter = floor(real(_ev[$ "loop_iteration"] ?? 0));
        if (_iter > 0 && _iter != _measure_iter_ref) continue;

        var _mt = string(_ev[$ "marker_type"] ?? "");
        var _beat = floor(real(_ev[$ "beat"] ?? 0));
        var _frac = real(_ev[$ "beat_fraction"] ?? 0);
        var _is_start = (_mt == "bar") || (_mt == "beat" && _beat == 1 && abs(_frac) <= 0.001);
        if (!_is_start) continue;

        var _m = floor(real(_ev[$ "owner_measure"] ?? (_ev[$ "measure"] ?? 0)));
        if (_m < 1) continue;
        var _p = floor(real(_ev[$ "owner_part"] ?? (_ev[$ "part"] ?? 1)));
        if (_p < 1) _p = 1;
        var _seq = (_m == 0) ? 0 : (_m - (_has_pickup_map ? 0 : 1));

        var _key = string(_p) + ":" + string(_m);
        if (_key == _last_key) continue;
        _last_key = _key;

        array_push(_measure_starts, {
            m: _m,
            p: _p,
            b: _beat,
            t: gv_evt_time_ms(_ev),
            seq: _seq,
            seg_idx: -1,
            seg_title: "",
            seg_start_ms: -1,
            seg_end_ms: -1
        });
    }

    var _nm = array_length(_measure_starts);
    var _fallback_measure_ms = 1000;
    if (_nm >= 2) {
        _fallback_measure_ms = max(1,
            real(_measure_starts[_nm - 1][$ "t"] ?? 0)
            - real(_measure_starts[_nm - 2][$ "t"] ?? 0));
    } else if (_loop_cycle_ms > 1) {
        _fallback_measure_ms = _loop_cycle_ms;
    }

    // One-time pickup alignment: move each measure start earlier to include same-measure lead-ins.
    if (_nm > 0) {
        for (var _msi = 0; _msi < _nm; _msi++) {
            var _ms = _measure_starts[_msi];
            var _ms_m = floor(real(_ms[$ "m"] ?? 0));
            var _ms_p = floor(real(_ms[$ "p"] ?? 1));
            if (_ms_p < 1) _ms_p = 1;
            if (_ms_m < 1) continue;

            var _ms_t = real(_ms[$ "t"] ?? 0);
            var _prev_t = (_msi > 0)
                ? real(_measure_starts[_msi - 1][$ "t"] ?? (_ms_t - _fallback_measure_ms))
                : (_ms_t - _fallback_measure_ms);
            var _lead_t = _ms_t;

            for (var _ei = 0; _ei < _ne; _ei++) {
                var _lev = _events[_ei];
                if (!is_struct(_lev)) continue;

                var _lev_iter = floor(real(_lev[$ "loop_iteration"] ?? 0));
                if (_lev_iter > 0 && _lev_iter != _measure_iter_ref) continue;

                var _lev_type = string(_lev[$ "type"] ?? "");
                if ((_lev_type == "note_on" || _lev_type == "note_off") && _skip_met) {
                    var _lev_ch = floor(real(_lev[$ "channel"] ?? -1));
                    if (_lev_ch == _met_ch) continue;
                }

                var _lev_t = gv_evt_time_ms(_lev);
                if (_lev_t < _prev_t || _lev_t >= _ms_t) continue;

                var _lev_m = floor(real(_lev[$ "owner_measure"] ?? (_lev[$ "measure"] ?? -1)));
                var _lev_p = floor(real(_lev[$ "owner_part"] ?? (_lev[$ "part"] ?? 1)));
                if (_lev_p < 1) _lev_p = 1;
                if (_lev_m != _ms_m || _lev_p != _ms_p) continue;

                if (_lev_t < _lead_t) _lead_t = _lev_t;
            }

            if (_lead_t < _ms_t) {
                variable_struct_set(_measure_starts[_msi], "t", _lead_t);
            }
        }
    }

    _cache.iter1_start_ms = _iter1_start;
    _cache.iter2_start_ms = _iter2_start;
    _cache.phase_start_ms = _phase_start;
    _cache.phase_iteration = _phase_iteration;
    _cache.loop_cycle_ms = _loop_cycle_ms;
    _cache.measure_starts = _measure_starts;
    _cache.fallback_measure_ms = _fallback_measure_ms;
    _cache.valid = (_phase_start >= 0) && (_loop_cycle_ms > 1) && (_nm > 0);
    return _cache;
}

/// @function gv_anchor_cache_get_or_create(_cache_key, _w, _h)
/// @description Retrieve or create a surface-cache entry for a named anchor. Creates a new surface if missing or size changed.
/// @param {string} _cache_key  Identifier key for this anchor surface.
/// @param {real}   _w          Required surface width.
/// @param {real}   _h          Required surface height.
/// @returns {struct}  Cache entry struct with fields: surf, w, h, last_ms.
/// @reads  global.timeline_anchor_surface_cache
/// @writes global.timeline_anchor_surface_cache
function gv_anchor_cache_get_or_create(_cache_key, _w, _h) {
    if (!variable_global_exists("timeline_anchor_surface_cache") || !is_struct(global.timeline_anchor_surface_cache)) {
        global.timeline_anchor_surface_cache = {};
    }

    var _cache = variable_struct_exists(global.timeline_anchor_surface_cache, _cache_key)
        ? global.timeline_anchor_surface_cache[$ _cache_key]
        : { surf: noone, w: 0, h: 0, last_ms: -1000000000 };

    if (!surface_exists(_cache.surf) || _cache.w != _w || _cache.h != _h) {
        if (surface_exists(_cache.surf)) surface_free(_cache.surf);
        _cache.surf = surface_create(_w, _h);
        _cache.w = _w;
        _cache.h = _h;
        _cache.last_ms = -1000000000;
    }

    return _cache;
}

/// @function gv_anchor_cache_store(_cache_key, _cache)
/// @description Write a surface-cache entry back to the global anchor cache.
/// @param {string} _cache_key  Identifier key for this anchor surface.
/// @param {struct} _cache      Cache entry struct to store.
/// @reads  global.timeline_anchor_surface_cache
/// @writes global.timeline_anchor_surface_cache
function gv_anchor_cache_store(_cache_key, _cache) {
    if (!variable_global_exists("timeline_anchor_surface_cache") || !is_struct(global.timeline_anchor_surface_cache)) {
        global.timeline_anchor_surface_cache = {};
    }
    global.timeline_anchor_surface_cache[$ _cache_key] = _cache;
}

/// @function gv_build_synthetic_measure_nav_map(_fallback_end_ms, _fallback_measure_ms)
/// @description Build a simple uniform measure-nav map when no bar-event data is available.
/// @param {real} _fallback_end_ms      Total tune duration in ms.
/// @param {real} _fallback_measure_ms  Duration of one measure in ms.
/// @returns {struct}  Measure-nav map with fields: entries[], parts[], pickup_by_part.
function gv_build_synthetic_measure_nav_map(_fallback_end_ms, _fallback_measure_ms) {
    var _measure_ms = max(1, real(_fallback_measure_ms));
    var _end_ms = max(_measure_ms, real(_fallback_end_ms));
    var _count = max(1, ceil(_end_ms / _measure_ms));
    var _entries = [];
    for (var _fm = 1; _fm <= _count; _fm++) {
        array_push(_entries, {
            measure: _fm,
            part: 1,
            iteration: 0,
            start_ms: (_fm - 1) * _measure_ms,
            end_ms: _fm * _measure_ms,
            status: 0,
            struct_idx: _fm
        });
    }

    var _pickup = {};
    _pickup[$ "1"] = false;

    return {
        entries: _entries,
        parts: [1],
        pickup_by_part: _pickup
    };
}

/// @function gv_tune_structure_rule_classify_segment(_entry, _measure_ms)
/// @description Classify one structural segment from timing span for model metadata.
/// @param {struct} _entry  Measure-nav entry with start/end/measure fields.
/// @param {real} _measure_ms  Reference full-measure duration in ms.
/// @returns {string}  One of: full, pickup, partial, rest_only.
function gv_tune_structure_rule_classify_segment(_entry, _measure_ms) {
    if (!is_struct(_entry)) return "partial";

    var _measure = floor(real(variable_struct_exists(_entry, "measure") ? variable_struct_get(_entry, "measure") : 0));
    if (_measure <= 0) return "pickup";

    var _start_ms = real(variable_struct_exists(_entry, "start_ms") ? variable_struct_get(_entry, "start_ms") : 0);
    var _end_ms = real(variable_struct_exists(_entry, "end_ms") ? variable_struct_get(_entry, "end_ms") : _start_ms);
    var _dur_ms = max(0, _end_ms - _start_ms);
    var _full_ms = max(1, real(_measure_ms));
    var _ratio = _dur_ms / _full_ms;

    if (_ratio >= 0.9 && _ratio <= 1.1) return "full";
    if (_ratio < 0.25) return "pickup";
    return "partial";
}

/// @function gv_tune_structure_rule_musical_measure_idx(_entry, _next_default)
/// @description Resolve player-facing musical measure index while preserving pickup-as-zero behavior.
/// @param {struct} _entry  Measure-nav entry.
/// @param {real} _next_default  Next fallback musical index when label is unavailable.
/// @returns {struct}  { musical_measure_idx, next_default }.
function gv_tune_structure_rule_musical_measure_idx(_entry, _next_default) {
    var _next = max(1, floor(real(_next_default)));
    if (!is_struct(_entry)) {
        return {
            musical_measure_idx: _next,
            next_default: _next + 1
        };
    }

    var _measure = floor(real(variable_struct_exists(_entry, "measure") ? variable_struct_get(_entry, "measure") : 0));
    if (_measure <= 0) {
        return {
            musical_measure_idx: 0,
            next_default: _next
        };
    }

    return {
        musical_measure_idx: _measure,
        next_default: max(_next, _measure + 1)
    };
}

/// @function gv_tune_structure_rule_display_row_kind(_classification)
/// @description Convert segment classification into tune-structure row-kind hint.
/// @param {string} _classification  Segment classification.
/// @returns {string}  full_row or pickup_row.
function gv_tune_structure_rule_display_row_kind(_classification) {
    var _kind = string(_classification ?? "full");
    if (_kind == "pickup") return "pickup_row";
    return "full_row";
}

/// @function gv_measure_nav_normalize_struct_idx(_entries)
/// @description Ensure every measure-nav entry carries a canonical struct_idx so downstream model builders can rely on a consistent schema.
/// @param {array} _entries  Measure-nav entry array.
/// @returns {array}  Same entries with struct_idx normalized.
function gv_measure_nav_normalize_struct_idx(_entries) {
    var _out = [];
    if (!is_array(_entries)) return _out;

    for (var _i = 0; _i < array_length(_entries); _i++) {
        var _entry = _entries[_i];
        if (!is_struct(_entry)) continue;

        if (!variable_struct_exists(_entry, "struct_idx")) {
            var _assigned_struct_idx = _i + 1;
            variable_struct_set(_entry, "struct_idx", _assigned_struct_idx);
            if (is_undefined(show_debug_message) == false) {
                show_debug_message("[gv_measure_nav_normalize_struct_idx] Missing struct_idx for entry " + string(_i) + "; assigned " + string(_assigned_struct_idx));
            }
        } else {
            var _struct_idx_value = variable_struct_get(_entry, "struct_idx");
            var _struct_idx = floor(real(_struct_idx_value));
            if (_struct_idx >= 1) {
                variable_struct_set(_entry, "struct_idx", _struct_idx);
            } else {
                variable_struct_set(_entry, "struct_idx", _i + 1);
            }
        }

        array_push(_out, _entry);
    }

    return _out;
}

/// @function gv_build_tune_structure_model_from_measure_nav(_measure_nav)
/// @description Build a canonical tune-structure model from current measure-nav entries without changing draw/runtime read paths.
/// @param {struct} _measure_nav  Measure-nav map with entries/parts/pickup_by_part.
/// @returns {struct}  Canonical tune-structure model with segment metadata and display hints.
/// @reads  global.timeline_state.measure_ms
function gv_build_tune_structure_model_from_measure_nav(_measure_nav) {
    var _entries = [];
    if (is_struct(_measure_nav) && variable_struct_exists(_measure_nav, "entries") && is_array(_measure_nav.entries)) {
        _entries = gv_measure_nav_normalize_struct_idx(_measure_nav.entries);
        variable_struct_set(_measure_nav, "entries", _entries);
    }

    var _ownership_by_key = {};
    if (is_undefined(scr_button_build_measure_nav_map_for_ownership) == false
        && variable_global_exists("playback_events")
        && is_array(global.playback_events)
        && array_length(global.playback_events) > 0) {
        var _own_map = scr_button_build_measure_nav_map_for_ownership(global.playback_events);
        if (is_struct(_own_map)
            && variable_struct_exists(_own_map, "entries")
            && is_array(variable_struct_get(_own_map, "entries"))) {
            var _own_entries = variable_struct_get(_own_map, "entries");
            for (var _oi = 0; _oi < array_length(_own_entries); _oi++) {
                var _oe = _own_entries[_oi];
                if (!is_struct(_oe)) continue;
                var _op = max(1, floor(real(_oe.part ?? 1)));
                var _om = floor(real(_oe.measure ?? -1));
                if (_om < 1) continue;
                var _ok = string(_op) + ":" + string(_om);
                if (!variable_struct_exists(_ownership_by_key, _ok)) {
                    _ownership_by_key[$ _ok] = {
                        owner_nav_idx: _oi,
                        start_ms: real(_oe.start_ms ?? -1),
                        end_ms: real(_oe.end_ms ?? -1)
                    };
                }
            }
        }
    }

    var _measure_ms_fallback = 1000;
    if (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "measure_ms")) {
        _measure_ms_fallback = max(1, real(global.timeline_state.measure_ms));
    }

    var _entry_n = array_length(_entries);

    // Derive full-bar reference duration from nav windows so segment
    // classification is robust even when tempo/meter BPM semantics differ.
    var _dur_samples = [];
    for (var _di = 0; _di < _entry_n; _di++) {
        var _de = _entries[_di];
        if (!is_struct(_de)) continue;
        var _dm = floor(real(_de.measure ?? 0));
        if (_dm < 1) continue;
        var _ds = real(_de.start_ms ?? 0);
        var _de_ms = real(_de.end_ms ?? _ds);
        var _dur = _de_ms - _ds;
        if (_dur > 1) array_push(_dur_samples, _dur);
    }

    var _measure_ms = _measure_ms_fallback;
    if (array_length(_dur_samples) > 0) {
        if (array_length(_dur_samples) > 1) {
            array_sort(_dur_samples, function(a, b) { return real(a) - real(b); });
        }
        var _mid = floor((array_length(_dur_samples) - 1) * 0.5);
        _measure_ms = max(1, real(_dur_samples[_mid]));
    }

    var _segments = [];
    var _next_musical = 1;
    for (var _i = 0; _i < _entry_n; _i++) {
        var _entry = _entries[_i];
        if (!is_struct(_entry)) continue;

        var _measure = floor(real(variable_struct_exists(_entry, "measure") ? variable_struct_get(_entry, "measure") : 0));
        var _part = max(1, floor(real(variable_struct_exists(_entry, "part") ? variable_struct_get(_entry, "part") : 1)));
        var _struct_idx_raw = variable_struct_exists(_entry, "struct_idx") ? variable_struct_get(_entry, "struct_idx") : undefined;
        var _struct_idx = is_undefined(_struct_idx_raw) ? -1 : floor(real(_struct_idx_raw));
        var _timeline_start_ms = real(variable_struct_exists(_entry, "start_ms") ? variable_struct_get(_entry, "start_ms") : 0);
        var _timeline_end_ms = real(variable_struct_exists(_entry, "end_ms") ? variable_struct_get(_entry, "end_ms") : _timeline_start_ms);
        var _own_key = string(_part) + ":" + string(_measure);
        var _owner_nav_idx = -1;
        var _owner_start_ms = -1;
        var _owner_end_ms = -1;
        if (variable_struct_exists(_ownership_by_key, _own_key)) {
            var _own_ref = _ownership_by_key[$ _own_key];
            if (is_struct(_own_ref)) {
                _owner_nav_idx = floor(real(_own_ref.owner_nav_idx ?? -1));
                _owner_start_ms = real(_own_ref.start_ms ?? -1);
                _owner_end_ms = real(_own_ref.end_ms ?? -1);
            }
        }
        var _start_ms = _timeline_start_ms;
        var _end_ms = _timeline_end_ms;
        if ((_end_ms <= _start_ms + 0.001) && _owner_end_ms > _owner_start_ms + 0.001) {
            _start_ms = _owner_start_ms;
            _end_ms = _owner_end_ms;
        }

        var _beat_count = (_measure_ms > 0) ? ((_end_ms - _start_ms) / _measure_ms) : 0;
        var _classification = gv_tune_structure_rule_classify_segment(_entry, _measure_ms);
        var _mus = gv_tune_structure_rule_musical_measure_idx(_entry, _next_musical);
        _next_musical = floor(real(_mus.next_default ?? _next_musical));
        var _display_row_kind = gv_tune_structure_rule_display_row_kind(_classification);

        var _boundary_role = "normal";
        if (_i == 0) _boundary_role = "loop_start_candidate";
        if (_i == _entry_n - 1) _boundary_role = "loop_end_candidate";

        array_push(_segments, {
            segment_id: "seg:" + string(_part) + ":" + string(_measure) + ":" + string(_i),
            source_nav_idx: _i,
            struct_idx: _struct_idx,
            part: _part,
            source_measure: _measure,
            owner_nav_idx: _owner_nav_idx,
            canonical_measure_idx: _struct_idx,
            musical_measure_idx: floor(real(_mus.musical_measure_idx ?? 0)),
            start_ms: _start_ms,
            end_ms: _end_ms,
            timeline_start_ms: _timeline_start_ms,
            timeline_end_ms: _timeline_end_ms,
            owner_start_ms: _owner_start_ms,
            owner_end_ms: _owner_end_ms,
            start_beat: 1,
            end_beat: max(1, _beat_count),
            beat_count: _beat_count,
            classification: _classification,
            boundary_role: _boundary_role,
            display_row_kind: _display_row_kind,
            display_part_group: _part,
            display_line_group: 1 + floor(_i / 4),
            display_col: _i mod 4
        });
    }

    return {
        version: 1,
        source: "measure_nav",
        built_at_ms: timing_get_engine_now_ms(),
        source_entry_count: _entry_n,
        segment_count: array_length(_segments),
        segments: _segments
    };
}

/// @function gv_tune_structure_build_parity(_measure_nav, _model)
/// @description Build lightweight parity stats between legacy measure-nav and canonical model.
/// @param {struct} _measure_nav  Legacy measure-nav source.
/// @param {struct} _model  Canonical model built from legacy source.
/// @returns {struct}  Parity summary.
function gv_tune_structure_build_parity(_measure_nav, _model) {
    var _entries = (is_struct(_measure_nav) && variable_struct_exists(_measure_nav, "entries") && is_array(_measure_nav.entries))
        ? gv_measure_nav_normalize_struct_idx(_measure_nav.entries)
        : [];
    var _segments = (is_struct(_model) && variable_struct_exists(_model, "segments") && is_array(_model.segments))
        ? _model.segments
        : [];

    var _nav_n = array_length(_entries);
    var _seg_n = array_length(_segments);
    var _paired_n = min(_nav_n, _seg_n);
    var _timing_mismatch = 0;
    for (var _i = 0; _i < _paired_n; _i++) {
        var _e = _entries[_i];
        var _s = _segments[_i];
        if (!is_struct(_e) || !is_struct(_s)) continue;
        var _ds = abs(real(_e.start_ms ?? 0) - real(_s.start_ms ?? 0));
        var _de = abs(real(_e.end_ms ?? 0) - real(_s.end_ms ?? 0));
        if (_ds > 0.001 || _de > 0.001) _timing_mismatch += 1;
    }

    return {
        nav_count: _nav_n,
        model_count: _seg_n,
        count_delta: _seg_n - _nav_n,
        timing_mismatch_count: _timing_mismatch
    };
}

/// @function gv_tune_structure_refresh_model_from_measure_nav(_measure_nav, _reason)
/// @description Refresh Stage-1 canonical tune-structure model cache and optional parity logging.
/// @param {struct} _measure_nav  Legacy measure-nav input.
/// @param {string} _reason  Refresh reason tag.
/// @reads  global.timeline_cfg.tune_structure_model_build_enabled, global.timeline_cfg.tune_structure_model_parity_log
/// @writes global.timeline_state.tune_structure_model, global.timeline_state.tune_structure_model_parity, global.timeline_state.tune_structure_model_reason
function gv_tune_structure_refresh_model_from_measure_nav(_measure_nav, _reason) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    var _cfg = gv_ensure_timeline_cfg_defaults();
    var _build_enabled = !variable_struct_exists(_cfg, "tune_structure_model_build_enabled")
        || bool(variable_struct_get(_cfg, "tune_structure_model_build_enabled"));
    if (!_build_enabled) return;

    var _model = gv_build_tune_structure_model_from_measure_nav(_measure_nav);
    var _parity = gv_tune_structure_build_parity(_measure_nav, _model);
    global.timeline_state.tune_structure_model = _model;
    global.timeline_state.tune_structure_model_parity = _parity;
    global.timeline_state.tune_structure_model_reason = string(_reason ?? "");

    var _parity_log = variable_struct_exists(_cfg, "tune_structure_model_parity_log")
        && bool(variable_struct_get(_cfg, "tune_structure_model_parity_log"));
    if (_parity_log) {
        var _msg = "[TSM_PARITY] reason=" + string(_reason ?? "")
            + " nav=" + string(_parity.nav_count)
            + " model=" + string(_parity.model_count)
            + " delta=" + string(_parity.count_delta)
            + " timing_mismatch=" + string(_parity.timing_mismatch_count);
        if (is_undefined(diag_log_append_line) == false) {
            diag_log_append_line(_msg, "perf_benchmark.log", false);
        } else {
            show_debug_message(_msg);
        }
    }
}

/// @function gv_tune_structure_model_resolve_musical_measure_at_time(_time_ms, _fallback_measure)
/// @description Resolve timeline label measure index from canonical tune-structure model at a time position.
/// @param {real} _time_ms  Time to resolve in ms.
/// @param {real} _fallback_measure  Legacy measure label fallback.
/// @returns {real}  Musical measure index from model when available, else fallback.
/// @reads  global.timeline_state.tune_structure_model
function gv_tune_structure_model_resolve_musical_measure_at_time(_time_ms, _fallback_measure) {
    var _fallback = floor(real(_fallback_measure));
    if (_fallback < 0) _fallback = 0;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return _fallback;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return _fallback;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return _fallback;

    var _segments = _model.segments;
    var _n = array_length(_segments);
    var _t = real(_time_ms);
    for (var _i = 0; _i < _n; _i++) {
        var _seg = _segments[_i];
        if (!is_struct(_seg)) continue;
        var _start = real(_seg.start_ms ?? -1);
        var _end = real(_seg.end_ms ?? _start);
        if (_t < _start) continue;
        if (_t >= _end) continue;

        if (variable_struct_exists(_seg, "musical_measure_idx")) {
            var _m = floor(real(_seg.musical_measure_idx));
            if (_m >= 0) return _m;
        }
        return _fallback;
    }

    return _fallback;
}

/// @function gv_tune_structure_model_resolve_musical_measure_for_nav_idx(_source_nav_idx, _fallback_measure)
/// @description Resolve musician-facing measure label from canonical model by source nav index.
/// @param {real} _source_nav_idx  Source nav index from measure-nav table.
/// @param {real} _fallback_measure  Legacy measure label fallback.
/// @returns {real}  Musical measure index from model when available, else fallback.
/// @reads  global.timeline_state.tune_structure_model
function gv_tune_structure_model_resolve_musical_measure_for_nav_idx(_source_nav_idx, _fallback_measure) {
    var _fallback = floor(real(_fallback_measure));
    if (_fallback < 0) _fallback = 0;

    var _target_idx = floor(real(_source_nav_idx));
    if (_target_idx < 0) return _fallback;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return _fallback;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return _fallback;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return _fallback;
    var _segments = _model.segments;

    for (var _i = 0; _i < array_length(_segments); _i++) {
        var _seg = _segments[_i];
        if (!is_struct(_seg)) continue;
        var _src = floor(real(_seg.source_nav_idx ?? -1));
        if (_src != _target_idx) continue;
        if (!variable_struct_exists(_seg, "musical_measure_idx")) return _fallback;
        var _m = floor(real(_seg.musical_measure_idx));
        return (_m >= 0) ? _m : _fallback;
    }

    return _fallback;
}

/// @function gv_tune_structure_model_has_reliable_segment_coverage(_model, _fallback_entries)
/// @description Return true only when the canonical tune-structure model covers the same structural identities as the live measure-nav source.
/// @param {struct} _model  Canonical tune-structure model.
/// @param {array} _fallback_entries  Legacy measure-nav entries.
/// @returns {bool}  True when the model is safe to use for panel/context resolution.
function gv_tune_structure_model_has_reliable_segment_coverage(_model, _fallback_entries) {
    if (!is_struct(_model)) return false;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return false;

    var _segments = _model.segments;
    if (array_length(_segments) <= 0) return false;

    var _source_entries = is_array(_fallback_entries) ? _fallback_entries : [];
    var _source_identity_count = 0;
    var _source_seen = {};
    for (var _si = 0; _si < array_length(_source_entries); _si++) {
        var _src_entry = _source_entries[_si];
        if (!is_struct(_src_entry)) continue;
        var _src_measure = floor(real(_src_entry[$ "measure"] ?? -1));
        if (_src_measure < 1) continue;
        var _src_part = max(1, floor(real(_src_entry[$ "part"] ?? 1)));
        var _src_key = string(_src_part) + ":" + string(_src_measure);
        if (variable_struct_exists(_source_seen, _src_key)) continue;
        _source_seen[$ _src_key] = true;
        _source_identity_count += 1;
    }

    if (_source_identity_count <= 1) return true;

    var _model_identity_count = 0;
    var _model_seen = {};
    for (var _mi = 0; _mi < array_length(_segments); _mi++) {
        var _seg = _segments[_mi];
        if (!is_struct(_seg)) continue;
        var _seg_measure = floor(real(_seg[$ "source_measure"] ?? -1));
        if (_seg_measure < 1) continue;
        var _seg_part = max(1, floor(real(_seg[$ "part"] ?? 1)));
        var _seg_key = string(_seg_part) + ":" + string(_seg_measure);
        if (variable_struct_exists(_model_seen, _seg_key)) continue;
        _model_seen[$ _seg_key] = true;
        _model_identity_count += 1;
    }

    if (_model_identity_count <= 1 && _source_identity_count > 1) return false;
    if (_model_identity_count < _source_identity_count) return false;
    return true;
}

/// @function gv_tune_structure_model_build_panel_entries(_fallback_entries)
/// @description Build panel entry source from canonical tune-structure model when enabled, else return legacy entries.
/// @param {array} _fallback_entries  Legacy measure-nav entries.
/// @returns {struct}  { entries, source_idx_map, used_model }.
/// @reads  global.timeline_cfg.use_canonical_tune_structure_model, global.timeline_state.tune_structure_model
function gv_tune_structure_model_build_panel_entries(_fallback_entries) {
    var _result = {
        entries: is_array(_fallback_entries) ? _fallback_entries : [],
        source_idx_map: [],
        used_model: false
    };

    var _fallback_n = array_length(_result.entries);
    for (var _fi = 0; _fi < _fallback_n; _fi++) {
        _result.source_idx_map[_fi] = _fi;
    }

    var _cfg = gv_ensure_timeline_cfg_defaults();
    var _use_model = variable_struct_exists(_cfg, "use_canonical_tune_structure_model")
        && bool(variable_struct_get(_cfg, "use_canonical_tune_structure_model"));
    if (!_use_model) return _result;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return _result;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return _result;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return _result;

    if (!gv_tune_structure_model_has_reliable_segment_coverage(_model, _result.entries)) return _result;

    var _segments = _model.segments;
    if (array_length(_segments) <= 0) return _result;

    var _entries = [];
    var _source_idx_map = [];
    for (var _si = 0; _si < array_length(_segments); _si++) {
        var _seg = _segments[_si];
        if (!is_struct(_seg)) continue;

        var _measure = floor(real(_seg.source_measure ?? -1));
        var _part = max(1, floor(real(_seg.part ?? 1)));
        var _start = real(_seg.start_ms ?? 0);
        var _end = real(_seg.end_ms ?? _start);
        var _src_idx = floor(real(_seg.source_nav_idx ?? _si));
        var _status = 0;

        array_push(_entries, {
            measure: _measure,
            part: _part,
            iteration: 0,
            start_ms: _start,
            end_ms: _end,
            status: _status,
            struct_idx: floor(real(_seg.struct_idx ?? (_si + 1))),
            segment_id: string(_seg.segment_id ?? ""),
            display_kind: string(_seg.classification ?? "full"),
            display_row_kind: string(_seg.display_row_kind ?? "full_row"),
            display_row: floor(real(_seg.display_line_group ?? 0)),
            display_col: floor(real(_seg.display_col ?? (_si mod 4))),
            display_label: "",
            musical_measure_idx: floor(real(_seg.musical_measure_idx ?? _measure))
        });
        array_push(_source_idx_map, _src_idx);
    }

    if (array_length(_entries) <= 0) return _result;

    _result.entries = _entries;
    _result.source_idx_map = _source_idx_map;
    _result.used_model = true;
    return _result;
}

/// @function gv_tune_structure_model_resolve_context_at_time(_time_ms)
/// @description Resolve structural context directly from canonical tune-structure model windows.
/// @param {real} _time_ms  Time in ms.
/// @returns {struct}  {found, measure, part, nav_idx, struct_idx, measure_ref_key, segment_id, musical_measure_idx}.
/// @reads  global.timeline_cfg.use_canonical_tune_structure_model, global.timeline_state.tune_structure_model
function gv_tune_structure_model_resolve_context_at_time(_time_ms) {
    var _out = {
        found: false,
        measure: -1,
        part: 1,
        nav_idx: -1,
        struct_idx: -1,
        measure_ref_key: "",
        segment_id: "",
        musical_measure_idx: -1
    };

    var _cfg = gv_ensure_timeline_cfg_defaults();
    var _use_model = variable_struct_exists(_cfg, "use_canonical_tune_structure_model")
        && bool(variable_struct_get(_cfg, "use_canonical_tune_structure_model"));
    if (!_use_model) return _out;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return _out;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return _out;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return _out;

    var _source_entries = [];
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries)) {
        _source_entries = global.timeline_state.measure_nav_entries;
    }
    if (!gv_tune_structure_model_has_reliable_segment_coverage(_model, _source_entries)) return _out;

    var _segments = _model.segments;
    var _t = real(_time_ms);
    for (var _i = 0; _i < array_length(_segments); _i++) {
        var _seg = _segments[_i];
        if (!is_struct(_seg)) continue;

        var _start = real(_seg.start_ms ?? -1);
        var _end = real(_seg.end_ms ?? _start);
        if (_start < 0 || _end <= _start + 0.001) continue;
        if (_t < _start || _t >= _end) continue;

        var _part = max(1, floor(real(_seg.part ?? 1)));
        var _measure = floor(real(_seg.source_measure ?? -1));
        var _nav_idx = floor(real(_seg.source_nav_idx ?? -1));
        var _measure_ref_key = "";
        var _score_key_fn = asset_get_index("scoring_measure_ref_key");
        if (script_exists(_score_key_fn) && _measure >= 1) {
            _measure_ref_key = string(script_execute(_score_key_fn, _part, _measure, _nav_idx));
            if (_measure_ref_key == "") {
                _measure_ref_key = string(script_execute(_score_key_fn, _part, _measure, -1));
            }
        }
        if (_measure_ref_key == "" && _measure >= 1) {
            _measure_ref_key = string(_part) + ":" + string(_measure);
        }

        _out.found = true;
        _out.part = _part;
        _out.measure = _measure;
        _out.nav_idx = _nav_idx;
        _out.struct_idx = floor(real(_seg.struct_idx ?? (_i + 1)));
        _out.measure_ref_key = _measure_ref_key;
        _out.segment_id = string(_seg.segment_id ?? "");
        _out.musical_measure_idx = floor(real(_seg.musical_measure_idx ?? -1));
        return _out;
    }

    return _out;
}

/// @function gv_tune_structure_model_find_segment(_part, _measure, _nav_idx)
/// @description Find a canonical model segment by structural identity, preferring exact source-nav match when available.
/// @param {real} _part  Part number.
/// @param {real} _measure  Source measure number.
/// @param {real} _nav_idx  Source nav index, or -1.
/// @returns {struct|undefined} Matching segment, or undefined.
/// @reads  global.timeline_state.tune_structure_model
function gv_tune_structure_model_find_segment(_part, _measure, _nav_idx) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return undefined;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return undefined;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return undefined;

    var _target_part = max(1, floor(real(_part)));
    var _target_measure = floor(real(_measure));
    var _target_nav = floor(real(_nav_idx));
    var _segments = _model.segments;
    var _fallback = undefined;

    for (var _i = 0; _i < array_length(_segments); _i++) {
        var _seg = _segments[_i];
        if (!is_struct(_seg)) continue;
        var _part_i = max(1, floor(real(_seg.part ?? 1)));
        var _measure_i = floor(real(_seg.source_measure ?? -1));
        var _nav_i = floor(real(_seg.source_nav_idx ?? -1));
        if (_part_i != _target_part || _measure_i != _target_measure) continue;
        if (_target_nav >= 0 && _nav_i == _target_nav) return _seg;
        if (is_undefined(_fallback)) _fallback = _seg;
    }

    return _fallback;
}

/// @function gv_tune_structure_model_find_next_segment(_part, _measure, _nav_idx)
/// @description Find the next canonical model segment after the provided structural identity.
/// @param {real} _part  Part number.
/// @param {real} _measure  Source measure number.
/// @param {real} _nav_idx  Source nav index, or -1.
/// @returns {struct|undefined} Next segment, or undefined.
/// @reads  global.timeline_state.tune_structure_model
function gv_tune_structure_model_find_next_segment(_part, _measure, _nav_idx) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return undefined;
    if (!variable_struct_exists(global.timeline_state, "tune_structure_model")
        || !is_struct(global.timeline_state.tune_structure_model)) return undefined;

    var _model = global.timeline_state.tune_structure_model;
    if (!variable_struct_exists(_model, "segments") || !is_array(_model.segments)) return undefined;

    var _target_part = max(1, floor(real(_part)));
    var _target_measure = floor(real(_measure));
    var _target_nav = floor(real(_nav_idx));
    var _segments = _model.segments;
    var _match_index = -1;
    var _fallback_index = -1;

    for (var _i = 0; _i < array_length(_segments); _i++) {
        var _seg = _segments[_i];
        if (!is_struct(_seg)) continue;
        var _part_i = max(1, floor(real(_seg.part ?? 1)));
        var _measure_i = floor(real(_seg.source_measure ?? -1));
        var _nav_i = floor(real(_seg.source_nav_idx ?? -1));
        if (_part_i != _target_part || _measure_i != _target_measure) continue;
        if (_target_nav >= 0 && _nav_i == _target_nav) {
            _match_index = _i;
            break;
        }
        if (_fallback_index < 0) _fallback_index = _i;
    }

    if (_match_index < 0) _match_index = _fallback_index;
    if (_match_index < 0) return undefined;
    if ((_match_index + 1) >= array_length(_segments)) return undefined;
    return _segments[_match_index + 1];
}

/// @function gv_measure_nav_apply_to_timeline_state(_measure_nav)
/// @description Copy entries, parts, and pickup flags from a measure-nav map struct into global.timeline_state.
/// @param {struct} _measure_nav  Measure-nav map from gv_build_measure_nav_map or gv_build_synthetic_measure_nav_map.
/// @reads  global.timeline_state
/// @writes global.timeline_state.measure_nav_entries, global.timeline_state.measure_nav_parts, global.timeline_state.measure_nav_pickup_by_part
function gv_measure_nav_apply_to_timeline_state(_measure_nav) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    var _entries = [];
    var _parts = [1];
    var _pickup = {};
    _pickup[$ "1"] = false;

    if (is_struct(_measure_nav)) {
        if (variable_struct_exists(_measure_nav, "entries") && is_array(_measure_nav.entries)) {
            _entries = gv_measure_nav_normalize_struct_idx(_measure_nav.entries);
            variable_struct_set(_measure_nav, "entries", _entries);
        }
        if (variable_struct_exists(_measure_nav, "parts") && is_array(_measure_nav.parts) && array_length(_measure_nav.parts) > 0) {
            _parts = _measure_nav.parts;
        }
        if (variable_struct_exists(_measure_nav, "pickup_by_part") && is_struct(_measure_nav.pickup_by_part)) {
            _pickup = _measure_nav.pickup_by_part;
        }
    }

    global.timeline_state.measure_nav_entries = _entries;
    global.timeline_state.measure_nav_parts = _parts;
    global.timeline_state.measure_nav_pickup_by_part = _pickup;
    gv_tune_structure_refresh_model_from_measure_nav(_measure_nav, "measure_nav_apply");
}

/// @function gv_measure_nav_ensure_state_defaults()
/// @description Initialise missing measure-nav sub-fields on global.timeline_state (scroll_row, total_rows, view_rows, tile_hitboxes, controls).
/// @reads  global.timeline_state
/// @writes global.timeline_state.measure_nav_scroll_row, global.timeline_state.measure_nav_total_rows, global.timeline_state.measure_nav_view_rows, global.timeline_state.measure_nav_tile_hitboxes, global.timeline_state.measure_nav_controls
function gv_measure_nav_ensure_state_defaults() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    if (!variable_struct_exists(global.timeline_state, "measure_nav_scroll_row")) {
        global.timeline_state.measure_nav_scroll_row = 0;
    }
    if (!variable_struct_exists(global.timeline_state, "measure_nav_total_rows")) {
        global.timeline_state.measure_nav_total_rows = 0;
    }
    if (!variable_struct_exists(global.timeline_state, "measure_nav_view_rows")) {
        global.timeline_state.measure_nav_view_rows = 0;
    }
    if (!variable_struct_exists(global.timeline_state, "measure_nav_tile_hitboxes")) {
        global.timeline_state.measure_nav_tile_hitboxes = [];
    }
    if (!variable_struct_exists(global.timeline_state, "measure_nav_controls") || !is_struct(global.timeline_state.measure_nav_controls)) {
        global.timeline_state.measure_nav_controls = {};
    }
}

/// @function gv_restore_score_segment_cache(_seg_idx, _restore_media)
/// @description Restore per-segment cached score data from global.score_segments_sprites.
///              Always restores structural metadata (durations, units_per_measure) so
///              measure-nav rebuild can detect pickups correctly; optionally restores
///              draw-time media arrays (sprites, playback map, image metadata).
/// @param {real} _seg_idx  Segment index into global.score_segments_sprites.
/// @param {bool} _restore_media  True to also restore score draw arrays.
/// @returns {bool}  True when a cache entry was found and applied.
/// @reads  global.score_segments_sprites
/// @writes global.score_snippet_durations, global.score_units_per_measure, global.score_lane_sprites, global.score_playback_map, global.score_lane_meta
/// @callers gv_rebuild_measure_nav_for_segment, gv_update_live_playhead, gv_sync_now_line_display, gv_review_handle_measure_nav_action
function gv_restore_score_segment_cache(_seg_idx, _restore_media) {
    var _seg_cache = variable_global_exists("score_segments_sprites") ? global.score_segments_sprites : [];
    if (!(is_array(_seg_cache) && _seg_idx >= 0 && _seg_idx < array_length(_seg_cache))) return false;

    var _cache_entry = _seg_cache[_seg_idx];
    if (!is_struct(_cache_entry)) return false;

    if (variable_global_exists("score_snippet_durations")) {
        global.score_snippet_durations = _cache_entry[$ "durations"] ?? [];
    }
    if (variable_global_exists("score_units_per_measure")) {
        global.score_units_per_measure = real(_cache_entry[$ "units_per_measure"] ?? 0);
    }
    if (variable_global_exists("score_has_pickup")) {
        global.score_has_pickup = bool(_cache_entry[$ "has_pickup"] ?? false);
    }

    if (_restore_media) {
        global.score_lane_sprites = _cache_entry[$ "sprites"] ?? [];
        global.score_playback_map = _cache_entry[$ "pbmap"] ?? [];
        if (variable_global_exists("score_lane_meta")) {
            global.score_lane_meta = _cache_entry[$ "meta"] ?? [];
        }
    }

    return true;
}

/// @function gv_rebuild_measure_nav_for_segment(_seg_idx)
/// @description Rebuild timeline_state.measure_nav_entries from
///              playback_context.segments[_seg_idx].bar_events so the structure
///              panel shows one tune at a time during set playback.
function gv_rebuild_measure_nav_for_segment(_seg_idx) {
    if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) return;
    var _pc_mode = string(global.playback_context[$ "mode"] ?? "");
    var _segs = global.playback_context[$ "segments"];
    if (!is_array(_segs) || _seg_idx < 0 || _seg_idx >= array_length(_segs)) return;
    var _seg = _segs[_seg_idx];
    if (!is_struct(_seg)) return;
    var _bar_evts = _seg[$ "bar_events"];
    if (!is_array(_bar_evts)) _bar_evts = [];

    // Restore per-segment snippet durations so gv_build_measure_nav_map can detect pickups.
    gv_restore_score_segment_cache(_seg_idx, false);

    var _nav = gv_build_measure_nav_map(_bar_evts);
    // bar_events in playback_context already have absolute times
    // (scr_playback_context_build_for_set shifts each event's time field by start_ms).
    // In set mode, clamp entries to the active segment window. This removes
    // trailing boundary-only markers that can appear exactly at seg_end and
    // would otherwise manifest as a phantom final measure.
    var _seg_end = real(_seg[$ "end_ms"] ?? 0);
    if (_pc_mode == "set" && _seg_end > 0 && is_array(_nav.entries) && array_length(_nav.entries) > 0) {
        var _seg_start = real(_seg[$ "start_ms"] ?? 0);
        var _trimmed = [];
        var _en = array_length(_nav.entries);
        for (var _ei = 0; _ei < _en; _ei++) {
            var _entry = _nav.entries[_ei];
            if (!is_struct(_entry)) continue;
            var _start = real(_entry.start_ms ?? 0);
            if (_start >= _seg_end - 0.001) continue;

            var _end = real(_entry.end_ms ?? _start);
            _entry.start_ms = max(_seg_start, _start);
            _entry.end_ms = min(_seg_end, max(_entry.start_ms, _end));
            array_push(_trimmed, _entry);
        }

        if (array_length(_trimmed) > 0) {
            var _last_i = array_length(_trimmed) - 1;
            var _last_start = real(_trimmed[_last_i].start_ms ?? 0);
            _trimmed[_last_i].end_ms = max(_last_start, _seg_end);
            _nav.entries = _trimmed;
        }
    }
    gv_measure_nav_apply_to_timeline_state(_nav);
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.measure_nav_scroll_row = 0;
    }
}

/// @function gv_build_set_measure_nav_all()
/// @description Build a flat, sorted array of measure-nav entries covering ALL segments of the
///              active set, each tagged with segment_idx.  Called once at load time (after the
///              sprite cache is populated) so that gv_get_current_planned_measure() can resolve
///              the correct measure at any playhead position without re-building state on segment
///              transitions.  Entries use absolute timestamps (bar_events in playback_context are
///              already shifted to wall-clock time by scr_playback_context_build_for_set).
/// @returns {array}  Flat array of nav-entry structs; each entry has the standard fields plus
///                   segment_idx.  Empty array on error or non-set mode.
/// @reads  global.playback_context, global.score_segments_sprites, global.timeline_state
/// @writes global.playback_set_measure_nav_all
function gv_build_set_measure_nav_all() {
    global.playback_set_measure_nav_all = [];

    if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) return [];
    if (string(global.playback_context[$ "mode"] ?? "") != "set") return [];

    var _segs = global.playback_context[$ "segments"];
    if (!is_array(_segs)) return [];
    var _seg_n = array_length(_segs);
    if (_seg_n == 0) return [];

    var _flat = [];

    // Snapshot the globals that gv_build_measure_nav_map() reads so we can restore them.
    var _saved_durations    = variable_global_exists("score_snippet_durations")  ? global.score_snippet_durations  : [];
    var _saved_upm          = variable_global_exists("score_units_per_measure")  ? real(global.score_units_per_measure) : 0;
    var _saved_has_pickup   = variable_global_exists("score_has_pickup") ? global.score_has_pickup : false;
    var _saved_measure_ms   = (variable_global_exists("timeline_state") && is_struct(global.timeline_state)
                                && variable_struct_exists(global.timeline_state, "measure_ms"))
                             ? real(global.timeline_state.measure_ms) : 1000;

    for (var _si = 0; _si < _seg_n; _si++) {
        var _seg = _segs[_si];
        if (!is_struct(_seg)) continue;

        // Load per-segment snippet data so gv_build_measure_nav_map uses the right durations/upm.
        if (variable_global_exists("score_segments_sprites")
            && is_array(global.score_segments_sprites)
            && _si < array_length(global.score_segments_sprites)
            && is_struct(global.score_segments_sprites[_si])) {
            var _cache = global.score_segments_sprites[_si];
            global.score_snippet_durations  = _cache.durations ?? [];
            global.score_units_per_measure  = real(_cache.units_per_measure ?? 0);
            if (variable_global_exists("score_has_pickup")) global.score_has_pickup = bool(_cache[$ "has_pickup"] ?? false);
        } else {
            global.score_snippet_durations  = [];
            global.score_units_per_measure  = 0;
            if (variable_global_exists("score_has_pickup")) global.score_has_pickup = false;
        }

        // Derive measure_ms for this segment from its BPM/meter.
        var _seg_bpm    = real(_seg[$ "bpm"]   ?? 120);
        var _seg_meter  = string(_seg[$ "meter"] ?? "4/4");
        var _mp         = string_split(_seg_meter, "/");
        var _mn         = real(_mp[0] ?? 4);
        var _md         = real(_mp[1] ?? 4);
        var _seg_mms    = gv_measure_ms(_seg_bpm, _mn, _md);
        if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
            global.timeline_state.measure_ms = _seg_mms;
        }

        var _bar_evts = _seg[$ "bar_events"];
        if (!is_array(_bar_evts)) _bar_evts = [];

        var _nav = gv_build_measure_nav_map(_bar_evts);
        if (!is_struct(_nav) || !is_array(_nav.entries)) continue;

        var _en = array_length(_nav.entries);
        for (var _ei = 0; _ei < _en; _ei++) {
            var _entry = _nav.entries[_ei];
            if (!is_struct(_entry)) continue;
            // Deep-copy the struct so segment-transition trimming of timeline_state doesn't corrupt this table.
            array_push(_flat, {
                measure:      real(_entry.measure ?? 0),
                part:         real(_entry.part ?? 1),
                start_ms:     real(_entry.start_ms ?? 0),
                end_ms:       real(_entry.end_ms ?? 0),
                status:       real(_entry.status ?? 0),
                segment_idx:  _si
            });
        }
    }

    // Restore globals to their pre-call state.
    global.score_snippet_durations  = _saved_durations;
    global.score_units_per_measure  = _saved_upm;
    if (variable_global_exists("score_has_pickup")) global.score_has_pickup = _saved_has_pickup;
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.measure_ms = _saved_measure_ms;
    }

    // Sort by start_ms so the binary-style scan in gv_get_current_planned_measure works.
    var _flat_n = array_length(_flat);
    for (var _i = 1; _i < _flat_n; _i++) {
        var _tmp = _flat[_i];
        var _j = _i - 1;
        while (_j >= 0 && real(_flat[_j].start_ms) > real(_tmp.start_ms)) {
            _flat[_j + 1] = _flat[_j];
            _j--;
        }
        _flat[_j + 1] = _tmp;
    }

    global.playback_set_measure_nav_all = _flat;
    show_debug_message("[gv_build_set_measure_nav_all] Built " + string(_flat_n) + " entries across " + string(_seg_n) + " segments.");
    return _flat;
}

/// @function gv_measure_nav_resolve_source_events()
/// @description Resolve the best available planned-events source for measure-nav building. Prefers gv_get_planned_events_for_viz(); falls back to flattening global.tune_event_groups.
/// @returns {array}  Array of planned event structs, possibly empty.
/// @reads  global.tune_event_groups
function gv_measure_nav_resolve_source_events() {
    var _source_events = gv_get_planned_events_for_viz();
    if (!is_array(_source_events)) _source_events = [];

    if (array_length(_source_events) <= 0
        && variable_global_exists("tune_event_groups")
        && is_array(global.tune_event_groups)
        && array_length(global.tune_event_groups) > 0) {
        var _flat_events = [];
        var _group_count = array_length(global.tune_event_groups);
        for (var _gi = 0; _gi < _group_count; _gi++) {
            var _grp = global.tune_event_groups[_gi];
            if (!is_struct(_grp)) continue;
            if (!variable_struct_exists(_grp, "events") || !is_array(_grp.events)) continue;

            var _gev = _grp.events;
            var _gev_n = array_length(_gev);
            for (var _gj = 0; _gj < _gev_n; _gj++) {
                array_push(_flat_events, _gev[_gj]);
            }
        }
        _source_events = _flat_events;
    }

    return _source_events;
}

/// @function gv_measure_nav_resolve_end_ms_from_events(_planned_events)
/// @description Find the maximum event timestamp in a planned-events array, also comparing against gv_get_planned_end_ms().
/// @param {array} _planned_events  Array of planned event structs.
/// @returns {real}  Resolved end time in ms.
function gv_measure_nav_resolve_end_ms_from_events(_planned_events) {
    var _fallback_end_ms = 0;
    if (is_array(_planned_events)) {
        var _n = array_length(_planned_events);
        for (var _i = 0; _i < _n; _i++) {
            var _ev = _planned_events[_i];
            if (!is_struct(_ev)) continue;
            _fallback_end_ms = max(_fallback_end_ms, gv_evt_time_ms(_ev));
        }
    }
    _fallback_end_ms = max(_fallback_end_ms, gv_get_planned_end_ms());
    return _fallback_end_ms;
}

/// @function gv_measure_nav_resolve_end_ms_from_state()
/// @description Read current review_end_ms and playhead_ms from global.timeline_state to determine the known end time.
/// @returns {real}  End time in ms (max of review_end_ms and playhead_ms, or 0 if state absent).
/// @reads  global.timeline_state.review_end_ms, global.timeline_state.playhead_ms
function gv_measure_nav_resolve_end_ms_from_state() {
    var _fallback_end_ms = 0;
    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        if (variable_struct_exists(global.timeline_state, "review_end_ms")) {
            _fallback_end_ms = max(_fallback_end_ms, real(global.timeline_state.review_end_ms));
        }
        if (variable_struct_exists(global.timeline_state, "playhead_ms")) {
            _fallback_end_ms = max(_fallback_end_ms, real(global.timeline_state.playhead_ms));
        }
    }
    return _fallback_end_ms;
}

/// @function gv_is_live_playback()
/// @description Return true only during active live playback (timeline active and playback not yet complete).
/// @returns {bool}  true if playback is ongoing; false during review, idle, or when timeline_state is absent.
/// @reads  global.timeline_state.active, global.timeline_state.playback_complete
function gv_is_live_playback() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return false;
    var done = variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete;
    return !done;
}

/// @function gv_ensure_timeline_cfg_defaults()
/// @description Initialise global.timeline_cfg if absent and fill in all missing default fields (enabled, zoom, BPM, channel, notebeam settings, lane colours, etc.). Returns global.timeline_cfg.
/// @returns {struct}  global.timeline_cfg with all defaults guaranteed present.
/// @reads  global.timeline_cfg
/// @writes global.timeline_cfg (all sub-fields set to defaults if missing)
function gv_ensure_timeline_cfg_defaults() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
        global.timeline_cfg = {};
    }

    if (!variable_struct_exists(global.timeline_cfg, "enabled")) {
        variable_struct_set(global.timeline_cfg, "enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "show_structure_row")) {
        variable_struct_set(global.timeline_cfg, "show_structure_row", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_channel")) {
        variable_struct_set(global.timeline_cfg, "tune_channel", 2);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_show_other_parts_ghost")) {
        variable_struct_set(global.timeline_cfg, "tune_show_other_parts_ghost", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_other_parts_alpha")) {
        variable_struct_set(global.timeline_cfg, "tune_other_parts_alpha", 0.18);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_structure_follow_mode")) {
        variable_struct_set(global.timeline_cfg, "tune_structure_follow_mode", "paged");
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_structure_page_rows")) {
        variable_struct_set(global.timeline_cfg, "tune_structure_page_rows", 8);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_structure_show_pickup_rows")) {
        variable_struct_set(global.timeline_cfg, "tune_structure_show_pickup_rows", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "use_canonical_tune_structure_model")) {
        variable_struct_set(global.timeline_cfg, "use_canonical_tune_structure_model", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_structure_model_build_enabled")) {
        variable_struct_set(global.timeline_cfg, "tune_structure_model_build_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tune_structure_model_parity_log")) {
        variable_struct_set(global.timeline_cfg, "tune_structure_model_parity_log", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "now_ratio")) {
        variable_struct_set(global.timeline_cfg, "now_ratio", 0.33);
    }
    if (!variable_struct_exists(global.timeline_cfg, "audio_output_offset_ms")) {
        variable_struct_set(global.timeline_cfg, "audio_output_offset_ms", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "visual_alignment_offset_ms")) {
        variable_struct_set(global.timeline_cfg, "visual_alignment_offset_ms", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")) {
        variable_struct_set(global.timeline_cfg, "input_capture_offset_ms", 0);
    }
    // Scoring offset is no longer supported (player feedback must be honest)
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_even_color")) {
        variable_struct_set(global.timeline_cfg, "notebeam_beat_box_even_color", make_color_rgb(245, 245, 245));
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_odd_color")) {
        variable_struct_set(global.timeline_cfg, "notebeam_beat_box_odd_color", make_color_rgb(35, 35, 35));
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_even_alpha")) {
        variable_struct_set(global.timeline_cfg, "notebeam_beat_box_even_alpha", 0.06);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_odd_alpha")) {
        variable_struct_set(global.timeline_cfg, "notebeam_beat_box_odd_alpha", 0.14);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_postplay_overlay_mode")) {
        variable_struct_set(global.timeline_cfg, "notebeam_postplay_overlay_mode", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "scoring_panel_visible")) {
        variable_struct_set(global.timeline_cfg, "scoring_panel_visible", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "timeline_score_visibility_mode")) {
        // 0 = score + markers, 1 = markers only
        variable_struct_set(global.timeline_cfg, "timeline_score_visibility_mode", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_enabled")) {
            variable_struct_set(global.timeline_cfg, "notebeam_diag_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_log_interval_frames")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_log_interval_frames", 45);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_planned")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_planned", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_player")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_player", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_pending")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_pending", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_history")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_history", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_beat_boxes")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_beat_boxes", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_emb_boxes")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_emb_boxes", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_popup_hitboxes")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_popup_hitboxes", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_popup_draw")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_popup_draw", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_overlap_compare")) {
        variable_struct_set(global.timeline_cfg, "notebeam_diag_disable_overlap_compare", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_planned_min_visible_px")) {
        variable_struct_set(global.timeline_cfg, "notebeam_planned_min_visible_px", 1.0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_planned_view_pad_px")) {
        variable_struct_set(global.timeline_cfg, "notebeam_planned_view_pad_px", 0.5);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_player_history_window_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_player_history_window_ms", 6000);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_live_player_color")) {
        variable_struct_set(global.timeline_cfg, "notebeam_live_player_color", make_color_rgb(78, 210, 255));
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_live_player_alpha")) {
        variable_struct_set(global.timeline_cfg, "notebeam_live_player_alpha", 0.96);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_history_window_pad_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_history_window_pad_ms", 250);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_visual_throttle_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_visual_throttle_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_visual_target_hz")) {
        variable_struct_set(global.timeline_cfg, "notebeam_visual_target_hz", 60);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_log")) {
        variable_struct_set(global.timeline_cfg, "score_lane_debug_log", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_boundary_window_ms")) {
        variable_struct_set(global.timeline_cfg, "score_lane_debug_boundary_window_ms", 2500);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_focus_title")) {
        variable_struct_set(global.timeline_cfg, "score_lane_debug_focus_title", "");
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")) {
        variable_struct_set(global.timeline_cfg, "score_lane_debug_file_log", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_path")) {
        variable_struct_set(global.timeline_cfg, "score_lane_debug_file_path", "score_lane_debug.log");
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guides_enabled")) {
        variable_struct_set(global.timeline_cfg, "score_lane_anchor_guides_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_color")) {
        variable_struct_set(global.timeline_cfg, "score_lane_anchor_guide_color", make_color_rgb(246, 210, 94));
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_alpha")) {
        variable_struct_set(global.timeline_cfg, "score_lane_anchor_guide_alpha", 0.28);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_width")) {
        variable_struct_set(global.timeline_cfg, "score_lane_anchor_guide_width", 1);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_lane_snap_pixels")) {
        // Preserve subpixel score-lane motion; content-window mapping handles measure-to-measure alignment.
        variable_struct_set(global.timeline_cfg, "score_lane_snap_pixels", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log")) {
        variable_struct_set(global.timeline_cfg, "score_render_plan_debug_log", false);
    }
    if (!variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log_interval_ms")) {
        variable_struct_set(global.timeline_cfg, "score_render_plan_debug_log_interval_ms", 3000);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_underlay_cache_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_underlay_cache_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_underlay_invalidation_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_underlay_invalidation_ms", 33);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_maintenance_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_maintenance_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_maintenance_budget_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_maintenance_budget_ms", 0.35);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_maintenance_stride_steps")) {
        variable_struct_set(global.timeline_cfg, "notebeam_maintenance_stride_steps", 1);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_prune_scan_per_tick")) {
        variable_struct_set(global.timeline_cfg, "notebeam_prune_scan_per_tick", 64);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_prune_compact_min_prefix")) {
        variable_struct_set(global.timeline_cfg, "notebeam_prune_compact_min_prefix", 128);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_prune_compact_interval_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_prune_compact_interval_ms", 750);
    }
    if (!variable_struct_exists(global.timeline_cfg, "measures_ahead")) {
        variable_struct_set(global.timeline_cfg, "measures_ahead", 2);
    }
    if (!variable_struct_exists(global.timeline_cfg, "measures_behind")) {
        variable_struct_set(global.timeline_cfg, "measures_behind", 1);
    }
    // ZOOM MODE TOGGLE: Set to "time" to test pure time-based zoom (ms), or "measures" for measure-based.
    // When in time mode, ignore measures_ahead/behind; use time_ahead_ms/time_behind_ms instead.
    // This allows side-by-side comparison before deciding on permanent architecture.
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_zoom_mode")) {
        variable_struct_set(global.timeline_cfg, "notebeam_zoom_mode", "time");
    }
    if (!variable_struct_exists(global.timeline_cfg, "time_ahead_ms")) {
        variable_struct_set(global.timeline_cfg, "time_ahead_ms", 4500);
    }
    if (!variable_struct_exists(global.timeline_cfg, "time_behind_ms")) {
        variable_struct_set(global.timeline_cfg, "time_behind_ms", 2250);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_zoom_fixed_presets_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_zoom_fixed_presets_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_zoom_step_scale")) {
        variable_struct_set(global.timeline_cfg, "notebeam_zoom_step_scale", 1.2);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_pan_step_measures")) {
        variable_struct_set(global.timeline_cfg, "notebeam_pan_step_measures", 0.25);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_pan_smooth_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_pan_smooth_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_pan_smooth_factor")) {
        variable_struct_set(global.timeline_cfg, "notebeam_pan_smooth_factor", 0.35);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_view_offset_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_ms", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_view_offset_target_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_target_ms", 0);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_enabled")) {
        variable_struct_set(global.timeline_cfg, "notebeam_nowline_planned_pulse_enabled", true);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_pre_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_nowline_planned_pulse_pre_ms", 28);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_post_ms")) {
        variable_struct_set(global.timeline_cfg, "notebeam_nowline_planned_pulse_post_ms", 60);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_width_boost")) {
        variable_struct_set(global.timeline_cfg, "notebeam_nowline_planned_pulse_width_boost", 1.4);
    }
    if (!variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_height_pad_px")) {
        variable_struct_set(global.timeline_cfg, "notebeam_nowline_planned_pulse_height_pad_px", 7);
    }
    if (!variable_struct_exists(global.timeline_cfg, "structure_past_tick_alpha")) {
        variable_struct_set(global.timeline_cfg, "structure_past_tick_alpha", 0.35);
    }
    if (!variable_struct_exists(global.timeline_cfg, "structure_future_tick_alpha")) {
        variable_struct_set(global.timeline_cfg, "structure_future_tick_alpha", 1.0);
    }

    if (!variable_struct_exists(global.timeline_cfg, "tl_beat_lane_h")) {
        // Keep beat lane readable without over-allocating vertical space.
        variable_struct_set(global.timeline_cfg, "tl_beat_lane_h", 32);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tl_word_lane_h")) {
        // Reserve more space for future lyrics/canntaireachd/tips lane.
        variable_struct_set(global.timeline_cfg, "tl_word_lane_h", 56);
    }
    if (!variable_struct_exists(global.timeline_cfg, "tl_beat_lane_bg_color")) {
        variable_struct_set(global.timeline_cfg, "tl_beat_lane_bg_color", make_color_rgb(26, 26, 30));
    }

    return global.timeline_cfg;
}

/// @function gv_is_bagpipe_tune_channel(_channel)
/// @description Return true if the channel number is one of the bagpipe tune channels (2-5).
/// @param {real} _channel  MIDI channel index.
/// @returns {bool}
function gv_is_bagpipe_tune_channel(_channel) {
    var ch = floor(real(_channel));
    return (ch >= 2 && ch <= 5);
}

/// @function gv_notebeam_sync_window_from_cfg()
/// @description Recompute global.timeline_state.ms_ahead and ms_behind from timeline_cfg.
/// Routes to either measure-based (legacy) or time-based zoom depending on notebeam_zoom_mode flag.
/// @returns {bool}  true if sync succeeded; false if timeline not active or measure_ms absent.
/// @reads  global.timeline_state.active, global.timeline_state.measure_ms, global.timeline_cfg.notebeam_zoom_mode, global.timeline_cfg.measures_ahead/behind or time_ahead/behind_ms
/// @writes global.timeline_state.ms_ahead, global.timeline_state.ms_behind
function gv_notebeam_sync_window_from_cfg() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return false;
    if (!variable_struct_exists(global.timeline_state, "measure_ms")) return false;

    var cfg = gv_ensure_timeline_cfg_defaults();
    var zoom_mode = string(variable_struct_get(cfg, "notebeam_zoom_mode") ?? "measures");

    if (zoom_mode == "time") {
        // TIME-BASED MODE: Direct millisecond window, regardless of tune meter/BPM.
        // This standardizes visible duration across all tunes in a set.
        var time_ahead_ms = real(variable_struct_get(cfg, "time_ahead_ms") ?? 1500);
        var time_behind_ms = clamp(round(time_ahead_ms * 0.5), 250, 15000);
        variable_struct_set(cfg, "time_behind_ms", time_behind_ms);
        
        global.timeline_state.ms_ahead = clamp(time_ahead_ms, 10, 30000);
        global.timeline_state.ms_behind = clamp(time_behind_ms, 10, 15000);
        
        // Store mode flag in state for UI/debug reference.
        variable_struct_set(global.timeline_state, "zoom_mode_active", "time");
    } else {
        // MEASURE-BASED MODE: Convert musical structure to milliseconds (current legacy behavior).
        var ahead_measures = variable_struct_exists(cfg, "measures_ahead")
            ? real(cfg.measures_ahead)
            : 2;
        var behind_measures = variable_struct_exists(cfg, "measures_behind")
            ? real(cfg.measures_behind)
            : 1;

        if (!variable_struct_exists(cfg, "notebeam_zoom_fixed_presets_enabled")
            || variable_struct_get(cfg, "notebeam_zoom_fixed_presets_enabled")) {
            var zoom_preset_factors = gv_notebeam_get_zoom_preset_factors();
            var zoom_factor = max(0.25, real(ahead_measures) / 2.0);
            if (is_real(behind_measures)) {
                zoom_factor = (zoom_factor + max(0.25, real(behind_measures))) * 0.5;
            }

            var best_index = 0;
            var best_delta = 1000000000.0;
            for (var i = 0; i < array_length(zoom_preset_factors); i++) {
                var candidate = real(zoom_preset_factors[i]);
                var delta = abs(candidate - zoom_factor);
                if (delta < best_delta) {
                    best_delta = delta;
                    best_index = i;
                }
            }

            var best_factor = real(zoom_preset_factors[best_index]);
            ahead_measures = max(0.25, 2.0 * best_factor);
            behind_measures = max(0.25, 1.0 * best_factor);
            variable_struct_set(cfg, "notebeam_zoom_preset_index", best_index);
            variable_struct_set(cfg, "notebeam_zoom_preset_factor", best_factor);
        }

        ahead_measures = clamp(ahead_measures, 0.25, 24.0);
        behind_measures = clamp(behind_measures, 0.25, 12.0);
        variable_struct_set(cfg, "measures_ahead", ahead_measures);
        variable_struct_set(cfg, "measures_behind", behind_measures);

        var measure_ms = max(1, real(global.timeline_state.measure_ms));
        global.timeline_state.ms_ahead = measure_ms * ahead_measures;
        global.timeline_state.ms_behind = measure_ms * behind_measures;
        
        // Store mode flag in state for UI/debug reference.
        variable_struct_set(global.timeline_state, "zoom_mode_active", "measures");
    }
    
    gv_invalidate_player_surface_cache();
    return true;
}

/// @function gv_notebeam_get_zoom_preset_factors()
/// @description Return the fixed zoom factors used to quantize the notebeam window.
/// @returns {array}  Ordered array of zoom factors from zoomed-out to zoomed-in.
function gv_notebeam_get_zoom_preset_factors() {
    return [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0];
}

/// @function gv_notebeam_zoom_by_steps(_steps)
/// @description Adjust the notebeam time window (ms_ahead/ms_behind) by a number of zoom steps, clamped to configured min/max limits.
/// @param {real} _steps  Positive = zoom out (more time visible); negative = zoom in.
/// @returns {bool}  true if a change was made.
/// @reads  global.timeline_state.measure_ms, global.timeline_cfg.notebeam_zoom_*
/// @writes global.timeline_cfg.notebeam_view_scale, global.timeline_state.ms_ahead/ms_behind; invalidates player surface cache
function gv_notebeam_zoom_by_steps(_steps) {
    var steps = real(_steps);
    if (steps == 0) return false;
    if (gv_is_live_playback()) {
        show_debug_message("Notebeam zoom ignored during active playback.");
        return false;
    }

    var cfg = gv_ensure_timeline_cfg_defaults();
    var cur_ahead = variable_struct_exists(cfg, "measures_ahead") ? real(cfg.measures_ahead) : 2;
    var cur_behind = variable_struct_exists(cfg, "measures_behind") ? real(cfg.measures_behind) : 1;

    var zoom_fixed_presets = !variable_struct_exists(cfg, "notebeam_zoom_fixed_presets_enabled")
        || variable_struct_get(cfg, "notebeam_zoom_fixed_presets_enabled");
    var new_ahead = cur_ahead;
    var new_behind = cur_behind;

    if (zoom_fixed_presets) {
        var factors = gv_notebeam_get_zoom_preset_factors();
        var current_factor = max(0.25, real(cur_ahead) / 2.0);
        if (is_real(cur_behind)) {
            current_factor = (current_factor + max(0.25, real(cur_behind))) * 0.5;
        }

        var current_index = 0;
        var current_delta = 1000000000.0;
        for (var i = 0; i < array_length(factors); i++) {
            var candidate = real(factors[i]);
            var delta = abs(candidate - current_factor);
            if (delta < current_delta) {
                current_delta = delta;
                current_index = i;
            }
        }

        var next_index = floor(clamp(current_index - floor(steps), 0, array_length(factors) - 1));
        var next_factor = real(factors[next_index]);
        new_ahead = 2.0 * next_factor;
        new_behind = 1.0 * next_factor;
        variable_struct_set(cfg, "notebeam_zoom_preset_index", next_index);
        variable_struct_set(cfg, "notebeam_zoom_preset_factor", next_factor);
    } else {
        var zoom_step_scale = variable_struct_exists(cfg, "notebeam_zoom_step_scale")
            ? max(1.01, real(variable_struct_get(cfg, "notebeam_zoom_step_scale")))
            : 1.2;
        var zoom_factor = power(zoom_step_scale, steps);
        new_ahead = clamp(cur_ahead / zoom_factor, 0.25, 24.0);
        new_behind = clamp(cur_behind / zoom_factor, 0.25, 12.0);
    }

    variable_struct_set(cfg, "measures_ahead", new_ahead);
    variable_struct_set(cfg, "measures_behind", new_behind);

    var synced = gv_notebeam_sync_window_from_cfg();
    if (!synced) {
        var planned_events = gv_get_planned_events_for_viz();
        if (is_array(planned_events) && array_length(planned_events) > 0) {
            // Pre-play preview: bootstrap timeline without starting audio so zoom is visible.
            gv_bind_from_loaded_tune();
            if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
                global.timeline_state.playhead_ms = 0;
                global.timeline_state.review_mode = true;
                global.timeline_state.playback_complete = true;
                global.timeline_state.review_end_ms = gv_get_planned_end_ms();
                global.timeline_state.review_measure_offset = 0;
            }
            synced = gv_notebeam_sync_window_from_cfg();
        }
    }

    if (synced && variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.score_render_plan_needs_rebuild = true;
        global.timeline_state.score_render_plan_pending_reason = "zoom_change";
        if (variable_struct_exists(global.timeline_state, "score_render_plan")
            && is_struct(global.timeline_state.score_render_plan)) {
            global.timeline_state.score_render_plan.valid = false;
            global.timeline_state.score_render_plan.status = "pending";
            global.timeline_state.score_render_plan.reason = "zoom_change";
        }
        if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
            && is_struct(global.timeline_state.score_render_plan_stats)) {
            global.timeline_state.score_render_plan_stats.invalidations += 1;
            global.timeline_state.score_render_plan_stats.last_reason = "zoom_change";
        }
        global.timeline_state.score_lane_layout_cache_single = {};
    }

    gv_invalidate_notebeam_underlay_surface_cache();
    gv_invalidate_notebeam_live_player_surface_cache();
    return synced;
}

/// @function gv_notebeam_pan_by_steps(_steps)
/// @description Pan the notebeam view forward or back by a number of steps. In review mode nudges the measure offset; in live mode adjusts notebeam_view_offset_target_ms on timeline_cfg.
/// @param {real} _steps  Number of pan steps (positive = forward, negative = back).
/// @returns {bool}  true if state changed.
/// @reads  global.timeline_state.active, global.timeline_state.measure_ms, global.timeline_state.playback_complete, global.timeline_cfg
/// @writes global.timeline_cfg.notebeam_view_offset_target_ms, global.timeline_cfg.notebeam_view_offset_ms
function gv_notebeam_pan_by_steps(_steps) {
    var steps = real(_steps);
    if (steps == 0) return false;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return false;
    if (!variable_struct_exists(global.timeline_state, "measure_ms")) return false;

    var cfg = gv_ensure_timeline_cfg_defaults();
    var pan_step_measures = variable_struct_exists(cfg, "notebeam_pan_step_measures")
        ? max(0.01, real(variable_struct_get(cfg, "notebeam_pan_step_measures")))
        : 0.25;

    if (variable_struct_exists(global.timeline_state, "playback_complete")
        && global.timeline_state.playback_complete) {
        var review_delta = steps * pan_step_measures;
        var changed_review = gv_review_nudge_measures(review_delta);
        if (changed_review) {
            variable_struct_set(cfg, "notebeam_view_offset_target_ms", 0);
            variable_struct_set(cfg, "notebeam_view_offset_ms", 0);
        }
        return changed_review;
    }

    var step_ms = real(global.timeline_state.measure_ms) * pan_step_measures;

    var current_target = variable_struct_exists(cfg, "notebeam_view_offset_target_ms")
        ? real(variable_struct_get(cfg, "notebeam_view_offset_target_ms"))
        : real(variable_struct_get(cfg, "notebeam_view_offset_ms"));
    var new_target = current_target + (steps * step_ms);

    var base_playhead = real(global.timeline_state.playhead_ms ?? 0);
    if (variable_struct_exists(global.timeline_state, "playback_complete")
        && global.timeline_state.playback_complete
        && variable_struct_exists(global.timeline_state, "review_end_ms")) {
        var end_ms = max(0, real(global.timeline_state.review_end_ms));
        var target_playhead = clamp(base_playhead + new_target, 0, end_ms);
        new_target = target_playhead - base_playhead;
    }

    variable_struct_set(cfg, "notebeam_view_offset_target_ms", new_target);
    if (!variable_struct_exists(cfg, "notebeam_pan_smooth_enabled")
        || !variable_struct_get(cfg, "notebeam_pan_smooth_enabled")) {
        variable_struct_set(cfg, "notebeam_view_offset_ms", new_target);
    }
    return true;
}

/// @function gv_get_target_tune_channel()
/// @description Return the active bagpipe tune channel from timeline_cfg.tune_channel (clamped to 2 if out of range).
/// @returns {real}  Tune channel index (2-5).
/// @reads  global.timeline_cfg.tune_channel
function gv_get_target_tune_channel() {
    var cfg = gv_ensure_timeline_cfg_defaults();

    var target = variable_struct_exists(cfg, "tune_channel")
        ? floor(real(cfg.tune_channel))
        : 2;

    if (!gv_is_bagpipe_tune_channel(target)) return 2;
    return target;
}

/// @function gv_count_selected_channel_score_measures(_events)
/// @description Count distinct positive score-measure labels present on note_on events for the selected tune channel.
/// @param {array} _events Planned events array.
/// @returns {real} Distinct playable measure count for the selected tune channel, or 0 when unavailable.
/// @reads global.timeline_cfg.tune_channel (via gv_get_target_tune_channel)
function gv_count_selected_channel_score_measures(_events) {
    if (!is_array(_events)) return 0;

    var _target_channel = gv_get_target_tune_channel();
    if (!gv_is_bagpipe_tune_channel(_target_channel)) return 0;

    var _seen_measures = {};
    var _count = 0;
    var _n = array_length(_events);
    for (var _i = 0; _i < _n; _i++) {
        var _ev = _events[_i];
        if (!is_struct(_ev)) continue;
        if (string(_ev[$ "type"] ?? "") != "note_on") continue;

        var _ev_ch = floor(real(_ev[$ "channel"] ?? -1));
        if (_ev_ch != _target_channel) continue;

        var _ev_measure = floor(real(_ev[$ "owner_measure"] ?? (_ev[$ "measure"] ?? -1)));
        if (_ev_measure <= 0) continue;

        var _key = string(_ev_measure);
        if (variable_struct_exists(_seen_measures, _key)) continue;

        _seen_measures[$ _key] = true;
        _count += 1;
    }

    return _count;
}

/// @function gv_use_tune_ghost_parts()
/// @description Return whether ghost display of non-focus tune parts is enabled.
/// @returns {bool}
/// @reads  global.timeline_cfg.tune_show_other_parts_ghost
function gv_use_tune_ghost_parts() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(cfg, "tune_show_other_parts_ghost")) return false;
    return cfg.tune_show_other_parts_ghost;
}

/// @function gv_get_tune_other_parts_alpha()
/// @description Return the draw alpha for non-focus tune parts when ghost mode is active.
/// @returns {real}  Alpha value, clamped to [0.02, 1].
/// @reads  global.timeline_cfg.tune_other_parts_alpha
function gv_get_tune_other_parts_alpha() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(cfg, "tune_other_parts_alpha")) return 0.18;
    return clamp(real(cfg.tune_other_parts_alpha), 0.02, 1);
}

/// @function gv_get_timeline_score_visibility_mode()
/// @description Return the timeline score-lane visibility mode.
/// @returns {real} 0 = score + markers, 1 = markers only.
/// @reads  global.timeline_cfg.timeline_score_visibility_mode
function gv_get_timeline_score_visibility_mode() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var mode = variable_struct_exists(cfg, "timeline_score_visibility_mode")
        ? floor(real(variable_struct_get(cfg, "timeline_score_visibility_mode")))
        : 0;
    if (mode < 0 || mode > 1) mode = 0;
    return mode;
}

/// @function gv_should_draw_timeline_score_images()
/// @description Return true when timeline score images should be drawn.
/// @returns {bool}
/// @reads  global.timeline_cfg.timeline_score_visibility_mode
function gv_should_draw_timeline_score_images() {
    return gv_get_timeline_score_visibility_mode() == 0;
}

/// @function gv_cycle_timeline_score_visibility_mode()
/// @description Toggle timeline score visibility between score+markers and markers-only.
/// @returns {real} New mode value.
/// @writes global.timeline_cfg.timeline_score_visibility_mode
function gv_cycle_timeline_score_visibility_mode() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    var cur_mode = gv_get_timeline_score_visibility_mode();
    var next_mode = (cur_mode == 0) ? 1 : 0;
    variable_struct_set(cfg, "timeline_score_visibility_mode", next_mode);
    return next_mode;
}

/// @function gv_draw_gameinfo_timeline_visibility_panel(_x1, _y1, _x2, _y2)
/// @description Draw loop boundary summary text in game-info window (`M# B# - M# B#`) with clickable beat fields.
/// @param {real} _x1 Left edge.
/// @param {real} _y1 Top edge.
/// @param {real} _x2 Right edge.
/// @param {real} _y2 Bottom edge.
/// @reads  global.timeline_state, global.loop_mode_enabled
/// @writes global.timeline_state.loop_boundary_ui_controls
function gv_get_gameinfo_timeline_visibility_button_rect(_x1, _y1, _x2, _y2) {
    var pad = 6;
    var left = _x1 + pad;
    var top = _y1 + pad;
    var right = _x2 - pad;
    var bottom = _y2 - pad;

    if (right <= left) right = left + 1;
    if (bottom <= top) bottom = top + 1;

    return [left, top, right, bottom];
}

/// @function gv_loop_get_ui_resolved_boundaries()
/// @description Resolve boundaries for UI display using selected refs and current refinement state.
/// @returns {struct} `{valid, start_measure, start_beat, end_measure, end_beat, start_part, end_part, source}`.
/// @reads global.loop_mode_enabled, global.timeline_state
function gv_loop_get_ui_resolved_boundaries() {
    var out = {
        valid: false,
        start_measure: -1,
        start_beat: 1,
        end_measure: -1,
        end_beat: 1,
        start_part: 1,
        end_part: 1,
        source: "none"
    };

    if (!gv_loop_mode_enabled()) return out;
    if (is_undefined(gv_loop_get_selected_measure_refs) || is_undefined(gv_loop_resolve_boundary_endpoints)) return out;

    var refs = gv_loop_get_selected_measure_refs();
    if (!is_array(refs) || array_length(refs) <= 0) return out;

    var ctx = gv_loop_resolve_boundary_endpoints(refs);
    if (!is_struct(ctx) || !(ctx[$ "valid"] ?? false)) return out;

    var sb = ctx[$ "start_boundary"];
    var eb = ctx[$ "end_boundary"];
    if (!is_struct(sb) || !is_struct(eb)) return out;

    out.valid = true;
    out.start_measure = floor(real(sb[$ "measure"] ?? -1));
    out.start_beat = max(1, floor(real(sb[$ "beat"] ?? 1)));
    out.end_measure = floor(real(eb[$ "measure"] ?? -1));
    out.end_beat = max(1, floor(real(eb[$ "beat"] ?? 1)));
    out.start_part = max(1, floor(real(sb[$ "part"] ?? 1)));
    out.end_part = max(1, floor(real(eb[$ "part"] ?? 1)));

    // Guard against unresolved/invalid boundary labels so UI never falls back
    // to "M1" for the end selector while a valid range is selected.
    if (out.start_measure < 1) {
        var _first_ref = refs[0];
        if (is_struct(_first_ref)) {
            out.start_measure = max(1, floor(real(_first_ref[$ "measure"] ?? 1)));
            out.start_part = max(1, floor(real(_first_ref[$ "part"] ?? out.start_part)));
        } else {
            out.start_measure = 1;
        }
    }
    if (out.end_measure < 1) {
        var _last_ref = refs[array_length(refs) - 1];
        if (is_struct(_last_ref)) {
            out.end_measure = max(1, floor(real(_last_ref[$ "measure"] ?? out.start_measure)) + 1);
            out.end_part = max(1, floor(real(_last_ref[$ "part"] ?? out.start_part)));
        } else {
            out.end_measure = max(1, out.start_measure + 1);
            out.end_part = out.start_part;
        }
    }

    out.source = string(ctx[$ "source"] ?? "none");
    return out;
}

/// @function gv_loop_get_measure_beat_count(_part, _measure)
/// @description Estimate available beats in a measure from canonical marker events, with meter fallback.
/// @param {real} _part Part number.
/// @param {real} _measure Measure number.
/// @returns {real} Max beat count for this measure (>=1).
/// @reads global.playback_events, global.timeline_state.meter_num
function gv_loop_get_measure_beat_count(_part, _measure) {
    var target_part = max(1, floor(real(_part)));
    var target_measure = floor(real(_measure));
    if (target_measure < 1) return 1;

    // Authoritative source for selector beat caps: active playback segment meter.
    // No silent fallback chain here; if meter cannot be resolved, log and fail closed.
    if (is_undefined(scr_playback_context_get_active_segment) || is_undefined(gv_parse_meter)) {
        show_debug_message("[LOOP_V3][ERROR] Missing meter resolver scripts; loop beat cap defaults to 1.");
        return 1;
    }

    var _active_seg = scr_playback_context_get_active_segment();
    if (!is_struct(_active_seg)) {
        show_debug_message("[LOOP_V3][ERROR] No active playback segment; loop beat cap defaults to 1.");
        return 1;
    }

    var _seg_meter = string(_active_seg[$ "meter"] ?? "");
    if (string_pos("/", _seg_meter) <= 0) {
        show_debug_message("[LOOP_V3][ERROR] Active segment meter missing/invalid ('" + _seg_meter + "'); loop beat cap defaults to 1.");
        return 1;
    }

    var _seg_parts = gv_parse_meter(_seg_meter);
    if (!is_array(_seg_parts) || array_length(_seg_parts) < 1) {
        show_debug_message("[LOOP_V3][ERROR] Failed to parse active segment meter ('" + _seg_meter + "'); loop beat cap defaults to 1.");
        return 1;
    }

    var beats_per_measure = max(1, floor(real(_seg_parts[0])));
    return beats_per_measure;
}

/// @function gv_loop_adjust_boundary_refinement_beat(_which, _delta)
/// @description Adjust start/end boundary beat and keep resolver-valid ordering.
/// @param {string} _which "start" or "end".
/// @param {real} _delta +1 to advance, -1 to step backward.
/// @returns {bool} true when adjustment applied.
/// @reads global.timeline_state.loop_boundary_refinement
/// @writes global.timeline_state.loop_boundary_refinement
function gv_loop_adjust_boundary_refinement_beat(_which, _delta) {
    if (!gv_loop_mode_enabled()) return false;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (is_undefined(gv_loop_get_selected_measure_refs) || is_undefined(gv_loop_resolve_boundary_endpoints)) return false;

    var refs = gv_loop_get_selected_measure_refs();
    if (!is_array(refs) || array_length(refs) <= 0) return false;

    if (!variable_struct_exists(global.timeline_state, "loop_boundary_refinement")
        || !is_struct(global.timeline_state.loop_boundary_refinement)) {
        gv_loop_sync_boundary_refinement_from_selection();
    }
    var refine = global.timeline_state.loop_boundary_refinement;
    if (!is_struct(refine)) return false;

    var field_prefix = (_which == "end") ? "end_" : "start_";
    var part_key = field_prefix + "part";
    var measure_key = field_prefix + "measure";
    var beat_key = field_prefix + "beat";
    var frac_key = field_prefix + "beat_fraction";

    var part = max(1, floor(real(refine[$ part_key] ?? 1)));
    var measure = floor(real(refine[$ measure_key] ?? -1));
    if (measure < 1) return false;

    var max_beat = gv_loop_get_measure_beat_count(part, measure);
    var old_beat = max(1, floor(real(refine[$ beat_key] ?? 1)));
    var new_beat = old_beat;
    if (_delta >= 0) {
        new_beat = (old_beat mod max_beat) + 1;
    } else {
        new_beat = old_beat - 1;
        if (new_beat < 1) new_beat = max_beat;
    }

    var old_enabled = bool(refine[$ "enabled"] ?? false);
    var old_frac = real(refine[$ frac_key] ?? 0);

    refine[$ "enabled"] = true;
    refine[$ beat_key] = new_beat;
    refine[$ frac_key] = 0;
    global.timeline_state.loop_boundary_refinement = refine;

    var ctx = gv_loop_resolve_boundary_endpoints(refs);
    var invalid = !is_struct(ctx)
        || !(ctx[$ "valid"] ?? false)
        || string_pos("refine_invalid_fallback", string(ctx[$ "source"] ?? "")) > 0;
    if (invalid) {
        refine[$ "enabled"] = old_enabled;
        refine[$ beat_key] = old_beat;
        refine[$ frac_key] = old_frac;
        global.timeline_state.loop_boundary_refinement = refine;
        return false;
    }
    return true;
}

/// @function gv_get_gameinfo_loop_boundary_layout(_x1, _y1, _x2, _y2, _summary)
/// @description Build text/button layout for the loop boundary line.
/// @param {real} _x1 Left edge.
/// @param {real} _y1 Top edge.
/// @param {real} _x2 Right edge.
/// @param {real} _y2 Bottom edge.
/// @param {struct} _summary Result from gv_loop_get_ui_resolved_boundaries().
/// @returns {struct} Layout with `start_beat_rect`, `end_beat_rect`, and text positions.
function gv_get_gameinfo_loop_boundary_layout(_x1, _y1, _x2, _y2, _summary) {
    var line_scale = 0.8;
    var prefix_a = "M" + string(max(1, floor(real(_summary[$ "start_measure"] ?? 1)))) + " ";
    var beat_a = "B" + string(max(1, floor(real(_summary[$ "start_beat"] ?? 1))));
    var mid = " - M" + string(max(1, floor(real(_summary[$ "end_measure"] ?? 1)))) + " ";
    var beat_b = "B" + string(max(1, floor(real(_summary[$ "end_beat"] ?? 1))));

    var w_prefix_a = string_width(prefix_a) * line_scale;
    var w_beat_a = string_width(beat_a) * line_scale;
    var w_mid = string_width(mid) * line_scale;
    var w_beat_b = string_width(beat_b) * line_scale;
    var pad_x = 4;
    var total_w = w_prefix_a + (w_beat_a + pad_x * 2) + w_mid + (w_beat_b + pad_x * 2);

    var content_rect = gv_get_gameinfo_timeline_visibility_button_rect(_x1, _y1, _x2, _y2);
    var cx = (content_rect[0] + content_rect[2]) * 0.5;
    var line_h = string_height("M0 B0") * line_scale;
    var line_y = floor(content_rect[1] + max(2, ((content_rect[3] - content_rect[1]) - line_h) * 0.35));
    var x_cursor = cx - (total_w * 0.5);

    var prefix_a_x = x_cursor;
    x_cursor += w_prefix_a;
    var beat_a_x1 = x_cursor;
    var beat_a_x2 = beat_a_x1 + w_beat_a + pad_x * 2;
    x_cursor = beat_a_x2;
    var mid_x = x_cursor;
    x_cursor += w_mid;
    var beat_b_x1 = x_cursor;
    var beat_b_x2 = beat_b_x1 + w_beat_b + pad_x * 2;

    var beat_y1 = line_y - 2;
    var beat_y2 = line_y + line_h + 2;
    return {
        line_scale: line_scale,
        prefix_a: prefix_a,
        beat_a: beat_a,
        mid: mid,
        beat_b: beat_b,
        prefix_a_x: prefix_a_x,
        beat_a_x: beat_a_x1 + pad_x,
        mid_x: mid_x,
        beat_b_x: beat_b_x1 + pad_x,
        line_y: line_y,
        start_beat_rect: [beat_a_x1, beat_y1, beat_a_x2, beat_y2],
        end_beat_rect: [beat_b_x1, beat_y1, beat_b_x2, beat_y2]
    };
}

function gv_draw_gameinfo_timeline_visibility_panel(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    var summary = gv_loop_get_ui_resolved_boundaries();
    global.timeline_state.loop_boundary_ui_controls = {
        valid: false,
        start_beat_rect: [-1, -1, -1, -1],
        end_beat_rect: [-1, -1, -1, -1]
    };

    if (!summary[$ "valid"]) return;

    draw_set_font(fnt_setting);
    var can_interact = gv_gameviz_controls_can_interact();
    var layout = gv_get_gameinfo_loop_boundary_layout(_x1, _y1, _x2, _y2, summary);

    var border_col = can_interact ? make_colour_rgb(168, 168, 168) : make_colour_rgb(90, 90, 90);
    var fill_col = can_interact ? make_colour_rgb(58, 58, 58) : make_colour_rgb(44, 44, 44);
    var text_col = can_interact ? make_colour_rgb(222, 222, 222) : make_colour_rgb(148, 148, 148);

    var b1 = layout[$ "start_beat_rect"];
    var b2 = layout[$ "end_beat_rect"];

    draw_set_colour(fill_col);
    draw_rectangle(b1[0], b1[1], b1[2], b1[3], false);
    draw_rectangle(b2[0], b2[1], b2[2], b2[3], false);
    draw_set_colour(border_col);
    draw_rectangle(b1[0], b1[1], b1[2], b1[3], true);
    draw_rectangle(b2[0], b2[1], b2[2], b2[3], true);

    draw_set_colour(text_col);
    gv_draw_text_scaled_top_left(layout[$ "prefix_a_x"], layout[$ "line_y"], layout[$ "prefix_a"], layout[$ "line_scale"]);
    gv_draw_text_scaled_top_left(layout[$ "beat_a_x"], layout[$ "line_y"], layout[$ "beat_a"], layout[$ "line_scale"]);
    gv_draw_text_scaled_top_left(layout[$ "mid_x"], layout[$ "line_y"], layout[$ "mid"], layout[$ "line_scale"]);
    gv_draw_text_scaled_top_left(layout[$ "beat_b_x"], layout[$ "line_y"], layout[$ "beat_b"], layout[$ "line_scale"]);

    // Tiny affordances: start beat advances (+), end beat steps backward (-).
    var hint_scale = 0.58;
    var hint_dy = 1;
    var hint_col = can_interact ? make_colour_rgb(188, 188, 188) : make_colour_rgb(122, 122, 122);
    draw_set_colour(hint_col);
    gv_draw_text_scaled_top_left(b1[2] - (string_width("+") * hint_scale) - 2, b1[1] + hint_dy, "+", hint_scale);
    gv_draw_text_scaled_top_left(b2[2] - (string_width("-") * hint_scale) - 2, b2[1] + hint_dy, "-", hint_scale);

    global.timeline_state.loop_boundary_ui_controls = {
        valid: true,
        start_beat_rect: b1,
        end_beat_rect: b2
    };
}

/// @function gv_handle_gameinfo_timeline_visibility_click(_mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle clicks on game-info loop boundary beat buttons (start advances, end steps backward).
/// @param {real} _mx Mouse X.
/// @param {real} _my Mouse Y.
/// @param {real} _x1 Left edge.
/// @param {real} _y1 Top edge.
/// @param {real} _x2 Right edge.
/// @param {real} _y2 Bottom edge.
/// @returns {bool} True if click was consumed.
/// @reads  global.timeline_state
/// @writes global.timeline_state.loop_boundary_refinement
function gv_handle_gameinfo_timeline_visibility_click(_mx, _my, _x1, _y1, _x2, _y2) {
    if (!gv_loop_mode_enabled()) return false;
    if (!gv_gameviz_controls_can_interact()) return false;

    var summary = gv_loop_get_ui_resolved_boundaries();
    if (!(summary[$ "valid"])) return false;

    var layout = gv_get_gameinfo_loop_boundary_layout(_x1, _y1, _x2, _y2, summary);
    var start_rect = layout[$ "start_beat_rect"];
    var end_rect = layout[$ "end_beat_rect"];

    if (gv_gameviz_point_in_rect(_mx, _my, start_rect)) {
        return gv_loop_adjust_boundary_refinement_beat("start", 1);
    }
    if (gv_gameviz_point_in_rect(_mx, _my, end_rect)) {
        return gv_loop_adjust_boundary_refinement_beat("end", -1);
    }

    return false;
}

/// @function gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2)
/// @description Calculate pixel rects for all controls buttons and legacy scoring regions within the gameviz controls panel.
/// @param {real} _x1  Left edge of panel.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @returns {struct}  Layout struct with fields: overview_rect, btn_toggle, btn_overlay_mode, btn_judges, btn_slot4-6, etc.
function gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2) {
    var pad = 4;
    var left = _x1 + pad;
    var right = _x2 - pad;
    if (right <= left) right = left + 1;

    var col_gap = 4;
    var row_gap = 4;
    var panel_h = max(1, _y2 - _y1);
    var btn_h = max(16, floor((panel_h - (pad * 2) - (row_gap * 2)) / 3));
    var btn_w = max(36, floor((right - left - col_gap) / 2));

    var col1_x1 = left;
    var col1_x2 = left + btn_w;
    var col2_x1 = col1_x2 + col_gap;
    var col2_x2 = right;

    var row0_y1 = _y1 + pad;
    var row0_y2 = row0_y1 + btn_h;
    var row1_y1 = row0_y2 + row_gap;
    var row1_y2 = row1_y1 + btn_h;
    var row2_y1 = row1_y2 + row_gap;
    var row2_y2 = row2_y1 + btn_h;

    // Keep legacy panel regions so existing click paths remain valid.
    var overview_h = max(1, row0_y2 - (_y1 + 2));

    var lower_top = _y1 + overview_h + 4;
    var header_h = 16;
    var row_h = 18;
    var table_y1 = lower_top;
    var table_header_y2 = table_y1 + header_h;
    var judge_row_y1 = table_header_y2 + 2;
    var judge_row_y2 = judge_row_y1 + row_h;
    var popup_y1 = judge_row_y2 + 4;
    var popup_y2 = _y2 - 4;
    if (popup_y2 <= popup_y1) {
        popup_y1 = judge_row_y2 + 2;
        popup_y2 = max(popup_y1 + 2, _y2 - 2);
    }

    return {
        overview_rect: [left, _y1 + 2, right, _y1 + overview_h],
        table_header_rect: [left, table_y1, right, table_header_y2],
        judge_row_rect: [col1_x1, row1_y1, col1_x2, row1_y2],
        popup_rect: [left, popup_y1, right, popup_y2],
        btn_toggle: [col1_x1, row0_y1, col1_x2, row0_y2],
        btn_overlay_mode: [col2_x1, row0_y1, col2_x2, row0_y2],
        btn_judges: [col1_x1, row1_y1, col1_x2, row1_y2],
        btn_slot4: [col2_x1, row1_y1, col2_x2, row1_y2],
        btn_slot5: [col1_x1, row2_y1, col1_x2, row2_y2],
        btn_slot6: [col2_x1, row2_y1, col2_x2, row2_y2]
    };
}

/// @function gv_gameviz_controls_can_interact()
/// @description Return true if the gameviz controls panel allows user interaction (i.e. not during live playback).
/// @returns {bool}
/// @reads  global.timeline_state.active, global.timeline_state.review_mode
function gv_gameviz_controls_can_interact() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return true;

    var active = variable_struct_exists(global.timeline_state, "active") && global.timeline_state.active;
    if (!active) return true;

    var review_mode = variable_struct_exists(global.timeline_state, "review_mode") && global.timeline_state.review_mode;
    return review_mode;
}

/// @function gv_gameviz_point_in_rect(_mx, _my, _r)
/// @description Test whether a point is inside a [x1,y1,x2,y2] rect array.
/// @param {real}  _mx  X coordinate to test.
/// @param {real}  _my  Y coordinate to test.
/// @param {array} _r   Four-element rect array [x1,y1,x2,y2].
/// @returns {bool}
function gv_gameviz_point_in_rect(_mx, _my, _r) {
    if (!is_array(_r) || array_length(_r) < 4) return false;
    return (_mx >= _r[0] && _mx <= _r[2] && _my >= _r[1] && _my <= _r[3]);
}

/// @function gv_is_gameviz_anchor(_inst)
/// @description Return true if the given instance exists and has ui_name == "gameviz_canvas_anchor".
/// @param {id} _inst  Instance ID to check.
/// @returns {bool}
/// @objects obj_field_base (reads ui_name variable)
function gv_is_gameviz_anchor(_inst) {
    if (!instance_exists(_inst)) return false;
    if (!variable_instance_exists(_inst, "ui_name")) return false;
    return string(variable_instance_get(_inst, "ui_name")) == "gameviz_canvas_anchor";
}

/// @function gv_is_notebeam_anchor(_inst)
/// @description Return true if the given instance exists and has ui_name == "notebeam_canvas_anchor".
/// @param {id} _inst  Instance ID to check.
/// @returns {bool}
/// @objects obj_field_base (reads ui_name variable)
function gv_is_notebeam_anchor(_inst) {
    if (!instance_exists(_inst)) return false;
    if (!variable_instance_exists(_inst, "ui_name")) return false;
    return string(variable_instance_get(_inst, "ui_name")) == "notebeam_canvas_anchor";
}

/// @function gv_scoring_call_script(_script_name, _arg0, _arg1, _arg2, _arg3, _arg4)
/// @description Dynamically invoke a scoring script asset by name, passing up to five optional arguments.
/// @param {string} _script_name  Asset name of the scoring script.
/// @param {any}    _arg0         Optional first argument.
/// @param {any}    _arg1         Optional second argument.
/// @param {any}    _arg2         Optional third argument.
/// @param {any}    _arg3         Optional fourth argument.
/// @param {any}    _arg4         Optional fifth argument.
/// @returns {any}  Return value from the script, or undefined if not found.
function gv_scoring_call_script(_script_name, _arg0 = undefined, _arg1 = undefined, _arg2 = undefined, _arg3 = undefined, _arg4 = undefined) {
    var idx = asset_get_index(_script_name);
    if (!script_exists(idx)) return undefined;
    if (is_undefined(_arg0) && is_undefined(_arg1) && is_undefined(_arg2) && is_undefined(_arg3) && is_undefined(_arg4)) return script_execute(idx);
    if (is_undefined(_arg1) && is_undefined(_arg2) && is_undefined(_arg3) && is_undefined(_arg4)) return script_execute(idx, _arg0);
    if (is_undefined(_arg2) && is_undefined(_arg3) && is_undefined(_arg4)) return script_execute(idx, _arg0, _arg1);
    if (is_undefined(_arg3) && is_undefined(_arg4)) return script_execute(idx, _arg0, _arg1, _arg2);
    if (is_undefined(_arg4)) return script_execute(idx, _arg0, _arg1, _arg2, _arg3);
    return script_execute(idx, _arg0, _arg1, _arg2, _arg3, _arg4);
}

/// @function gv_scoring_get_overview_lines()
/// @description Call scoring_get_ui_overview_rows and return the result array, or [] if unavailable.
/// @returns {array}  Overview score rows.
function gv_scoring_get_overview_lines() {
    var lines = gv_scoring_call_script("scoring_get_ui_overview_rows");
    return lines;
}

/// @function gv_scoring_get_selected_measure_context()
/// @description Resolve selected score context from timeline state with key-first fallback.
/// @returns {struct}  {measure, part, nav_idx, measure_key}
function gv_scoring_get_selected_measure_context() {
    var out = {
        measure: -1,
        part: -1,
        nav_idx: -1,
        measure_key: ""
    };

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;

    if (variable_struct_exists(global.timeline_state, "score_popup_nav_idx")) {
        out.nav_idx = floor(real(global.timeline_state.score_popup_nav_idx));
    }
    if (variable_struct_exists(global.timeline_state, "score_popup_measure_key")) {
        out.measure_key = string(global.timeline_state.score_popup_measure_key);
    }

    if (out.measure_key != "") {
        var first_sep = string_pos(":", out.measure_key);
        if (first_sep > 0) {
            var part_txt = string_copy(out.measure_key, 1, first_sep - 1);
            var rem = string_copy(out.measure_key, first_sep + 1, string_length(out.measure_key) - first_sep);
            var rem_sep = string_pos(":", rem);
            var measure_txt = (rem_sep > 0) ? string_copy(rem, 1, rem_sep - 1) : rem;
            var nav_txt = (rem_sep > 0) ? string_copy(rem, rem_sep + 1, string_length(rem) - rem_sep) : "";

            if (part_txt != "") out.part = max(1, floor(real(part_txt)));
            if (measure_txt != "") out.measure = floor(real(measure_txt));
            if (out.nav_idx < 0 && nav_txt != "") out.nav_idx = floor(real(nav_txt));
        }
    }

    return out;
}

/// @function gv_scoring_set_selected_measure_key(_measure_key, _nav_idx)
/// @description Set canonical selection identity and keep legacy numeric selection as derived-only compatibility state.
/// @param {string} _measure_key  Canonical score key (`part:measure[:nav]`), or "" to clear selection.
/// @param {real} [_nav_idx]  Optional nav index override; when < 0, nav may be parsed from key suffix.
/// @returns {struct}  Resolved context from key parse.
/// @writes global.timeline_state.score_popup_measure_key, global.timeline_state.score_popup_nav_idx, global.timeline_state.score_popup_measure
function gv_scoring_set_selected_measure_key(_measure_key, _nav_idx = -1) {
    var out = {
        measure: -1,
        part: -1,
        nav_idx: floor(real(_nav_idx)),
        measure_key: string(_measure_key)
    };

    var key = out.measure_key;
    if (key != "") {
        var first_sep = string_pos(":", key);
        if (first_sep > 0) {
            var part_txt = string_copy(key, 1, first_sep - 1);
            var rem = string_copy(key, first_sep + 1, string_length(key) - first_sep);
            var rem_sep = string_pos(":", rem);
            var measure_txt = (rem_sep > 0) ? string_copy(rem, 1, rem_sep - 1) : rem;
            var nav_txt = (rem_sep > 0) ? string_copy(rem, rem_sep + 1, string_length(rem) - rem_sep) : "";

            if (part_txt != "") out.part = max(1, floor(real(part_txt)));
            if (measure_txt != "") out.measure = floor(real(measure_txt));
            if (out.nav_idx < 0 && nav_txt != "") out.nav_idx = floor(real(nav_txt));
        }
    } else {
        out.nav_idx = -1;
    }

    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.score_popup_measure_key = out.measure_key;
        global.timeline_state.score_popup_nav_idx = out.nav_idx;
        // Compatibility field remains derived from canonical key only.
        global.timeline_state.score_popup_measure = out.measure;
    }

    return out;
}

/// @function gv_scoring_get_judge_rows()
/// @description Return judge table rows for the currently selected measure and judge from the active scoring run.
/// @returns {array}  Judge row structs, or [] if unavailable.
/// @reads  global.timeline_state.score_popup_measure_key, global.timeline_state.score_popup_nav_idx, global.timeline_state.score_selected_judge
function gv_scoring_get_judge_rows() {
    var ctx = gv_scoring_get_selected_measure_context();
    var selected_measure = floor(real(ctx.measure ?? -1));
    var selected_part = floor(real(ctx.part ?? -1));
    var selected_nav_idx = floor(real(ctx.nav_idx ?? -1));
    var selected_measure_key = string(ctx.measure_key ?? "");

    // Request all enabled judges for the current scope; selection/highlight is handled in the panel draw path.
    var rows = gv_scoring_call_script("scoring_get_judge_table_rows", selected_measure, "", selected_part, selected_nav_idx, selected_measure_key);
    if (!is_array(rows)) return [];
    return rows;
}

/// @function gv_scoring_get_panel_focus(_measure_num, _judge_id)
/// @description Return the scoring focus struct (judge name, score_value, score_percent_text, subtitle) for a given measure and judge.
/// @param {real}   _measure_num  Measure number to query.
/// @param {string} _judge_id     Judge identifier string.
/// @returns {struct}  Focus struct.
function gv_scoring_get_panel_focus(_measure_num, _judge_id) {
    var part_num = (argument_count > 2) ? floor(real(argument[2])) : -1;
    var nav_idx = (argument_count > 3) ? floor(real(argument[3])) : -1;
    var measure_key = (argument_count > 4) ? string(argument[4]) : "";
    var focus = gv_scoring_call_script("scoring_get_panel_focus", _measure_num, _judge_id, part_num, nav_idx, measure_key);
    if (!is_struct(focus)) {
        return {
            judge_id: "ms_overlap",
            judge_name: "Matching time",
            score_value: 0,
            score_percent_text: "0%",
            subtitle: "overall"
        };
    }
    return focus;
}

/// @function gv_scoring_get_popup_lines(_measure_num, _judge_id)
/// @description Return detail popup lines for a given measure and judge.
/// @param {real}   _measure_num  Measure number.
/// @param {string} _judge_id     Judge identifier (default "ms_overlap").
/// @returns {array}  Array of display strings.
function gv_scoring_get_popup_lines(_measure_num, _judge_id = "ms_overlap") {
    var part_num = (argument_count > 2) ? floor(real(argument[2])) : -1;
    var nav_idx = (argument_count > 3) ? floor(real(argument[3])) : -1;
    var measure_key = (argument_count > 4) ? string(argument[4]) : "";
    var lines = gv_scoring_call_script("scoring_get_detail_popup_rows", _measure_num, _judge_id, part_num, nav_idx, measure_key);
    if (!is_array(lines)) {
        lines = gv_scoring_call_script("scoring_get_measure_popup_rows", _measure_num, _judge_id, part_num, nav_idx, measure_key);
    }
    if (!is_array(lines)) return [];
    return lines;
}

/// @function gv_scoring_get_grade(_score_value)
/// @description Convert a numeric score value to a letter grade string via the scoring script.
/// @param {real} _score_value  Numeric score (0-100 typical).
/// @returns {string}  Grade letter, or "-" if unavailable.
function gv_scoring_get_grade(_score_value) {
    var grade_value = gv_scoring_call_script("scoring_score_to_grade", _score_value);
    if (is_string(grade_value) && string_length(grade_value) > 0) return string(grade_value);
    return "-";
}

/// @function gv_notebeam_scoring_panel_get_layout(_x1, _y1, _x2, _y2)
/// @description Calculate pixel rects for the scoring panel overlay within the notebeam canvas.
/// @param {real} _x1  Left edge of notebeam canvas.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @returns {struct}  Layout struct with: panel_rect, overview_rect, table_header_rect, table_rows_rect, row_h.
function gv_notebeam_scoring_panel_get_layout(_x1, _y1, _x2, _y2) {
    var panel_w = clamp(floor((_x2 - _x1) * 0.30), 240, 430);
    var pad = 8;
    var panel_x1 = _x1 + pad;
    var panel_x2 = min(_x2 - pad, panel_x1 + panel_w);
    var panel_y1 = _y1 + pad;
    var panel_y2 = _y2 - pad;

    var overview_h = clamp(floor((panel_y2 - panel_y1) * 0.16), 72, 88);
    var header_h = 14;
    var row_h = 26;
    var sep_gap = 8;

    var overview_rect = [panel_x1 + 6, panel_y1 + 6, panel_x2 - 6, panel_y1 + overview_h - 2];
    var table_header_rect = [panel_x1 + 6, panel_y1 + overview_h + sep_gap * 2, panel_x2 - 6, panel_y1 + overview_h + sep_gap * 2 + header_h];
    var table_rows_rect = [panel_x1 + 6, table_header_rect[3] + row_h - 2, panel_x2 - 6, panel_y2 - 6];

    return {
        panel_rect: [panel_x1, panel_y1, panel_x2, panel_y2],
        overview_rect: overview_rect,
        table_header_rect: table_header_rect,
        table_rows_rect: table_rows_rect,
        row_h: row_h,
    };
}

/// @function gv_draw_text_scaled_top_left(_x, _y, _text, _scale)
/// @description Draw text at (_x,_y) top-left aligned with uniform scale.
/// @param {real}   _x      Draw X position.
/// @param {real}   _y      Draw Y position.
/// @param {string} _text   Text to render.
/// @param {real}   _scale  Uniform X/Y scale.
function gv_draw_text_scaled_top_left(_x, _y, _text, _scale) {
    draw_text_transformed(_x, _y, string(_text), _scale, _scale, 0);
}

/// @function gv_draw_notebeam_scoring_panel(_x1, _y1, _x2, _y2)
/// @description Draw the post-play scoring panel over the notebeam canvas, including overview grade, judge table rows, and optional detail popup.
/// @param {real} _x1  Left edge of notebeam canvas.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @reads  global.timeline_state.playback_complete, global.timeline_state.score_popup_measure_key, global.timeline_state.score_popup_nav_idx, global.timeline_state.score_selected_judge, global.timeline_state.score_detail_popup, global.timeline_state.perf_summary_popup
/// @writes global.timeline_state.score_judge_row_hitboxes, global.timeline_state.score_detail_popup, global.timeline_state.perf_summary_popup
function gv_draw_notebeam_scoring_panel(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return;

    var perf_popup_open = gv_perf_summary_popup_visible();
    var _scfg = gv_ensure_timeline_cfg_defaults();
    var layout = gv_notebeam_scoring_panel_get_layout(_x1, _y1, _x2, _y2);
    if (!perf_popup_open && variable_struct_exists(_scfg, "scoring_panel_visible") && !bool(variable_struct_get(_scfg, "scoring_panel_visible"))) return;
    if (perf_popup_open) {
        var perf_summary = gv_perf_summary_get_latest(false);
        global.timeline_state.score_judge_row_hitboxes = [];
        global.timeline_state.score_detail_popup = { visible: false };
        gv_gameviz_draw_perf_summary_popup(layout.panel_rect[0], layout.panel_rect[1], layout.panel_rect[2], layout.panel_rect[3], perf_summary, true);
        return;
    }

    var panel_rect = layout.panel_rect;
    var judge_rows = gv_scoring_get_judge_rows();
    var title_scale = 0.84;
    var body_scale = 0.66;
    var big_scale = 0.98;
    var body_line_h = max(9, floor(string_height("Ag") * body_scale) + 2);

    draw_set_font(fnt_setting);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    draw_set_alpha(0.92);
    draw_set_color(make_color_rgb(18, 18, 22));
    draw_rectangle(panel_rect[0], panel_rect[1], panel_rect[2], panel_rect[3], false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(74, 74, 82));
    draw_rectangle(panel_rect[0], panel_rect[1], panel_rect[2], panel_rect[3], true);

    var selected_ctx = gv_scoring_get_selected_measure_context();
    var selected_measure = floor(real(selected_ctx.measure ?? -1));
    var selected_judge = variable_struct_exists(global.timeline_state, "score_selected_judge")
        ? string(variable_struct_get(global.timeline_state, "score_selected_judge"))
        : "ms_overlap";

    var selected_judge_valid = false;
    for (var judge_i = 0; judge_i < array_length(judge_rows); judge_i++) {
        var judge_row = judge_rows[judge_i];
        if (!is_struct(judge_row)) continue;
        var judge_row_id = string(variable_struct_exists(judge_row, "judge_id") ? variable_struct_get(judge_row, "judge_id") : "");
        if (judge_row_id == selected_judge) {
            selected_judge_valid = true;
            break;
        }
    }
    if (selected_judge == "" && array_length(judge_rows) > 0 && is_struct(judge_rows[0])) {
        selected_judge = string(variable_struct_exists(judge_rows[0], "judge_id") ? variable_struct_get(judge_rows[0], "judge_id") : "ms_overlap");
        selected_judge_valid = true;
    }
    if (!selected_judge_valid && array_length(judge_rows) > 0 && is_struct(judge_rows[0])) {
        selected_judge = string(variable_struct_exists(judge_rows[0], "judge_id") ? variable_struct_get(judge_rows[0], "judge_id") : "ms_overlap");
    }
    if (selected_judge != "") {
        global.timeline_state.score_selected_judge = selected_judge;
    }

    var focus = gv_scoring_get_panel_focus(selected_measure, selected_judge, selected_ctx.part, selected_ctx.nav_idx, selected_ctx.measure_key);

    var o = layout.overview_rect;
    var left_w = floor((o[2] - o[0]) * 0.52);

    draw_set_font(fnt_title);
    draw_set_color(c_white);
    gv_draw_text_scaled_top_left(o[0], o[1] + 2, string(variable_struct_exists(focus, "score_percent_text") ? variable_struct_get(focus, "score_percent_text") : "0%"), big_scale);

    draw_set_font(fnt_setting);
    draw_set_color(c_ltgray);
    gv_draw_text_scaled_top_left(o[0], o[1] + 2 + max(18, floor(string_height("88%") * big_scale)), string(variable_struct_exists(focus, "subtitle") ? variable_struct_get(focus, "subtitle") : "overall"), body_scale);

    var right_x = o[0] + left_w + 6;
    draw_set_color(c_gray);
    gv_draw_text_scaled_top_left(right_x, o[1] + 4, "Judge", body_scale);
    draw_set_color(c_white);
    gv_draw_text_scaled_top_left(right_x, o[1] + 4 + body_line_h, string(variable_struct_exists(focus, "judge_name") ? variable_struct_get(focus, "judge_name") : "Matching time"), title_scale);

    var hdr = layout.table_header_rect;
    draw_set_color(make_color_rgb(60, 60, 68));
    draw_line(panel_rect[0] + 6, hdr[1] - 8, panel_rect[2] - 6, hdr[1] - 8);
    draw_set_color(c_ltgray);
    var table_rows_rect = layout.table_rows_rect;
    var table_w = table_rows_rect[2] - table_rows_rect[0];
    var col_judge = table_rows_rect[0] + 4;
    var col_score = table_rows_rect[0] + floor(table_w * 0.62);
    var col_best = table_rows_rect[0] + floor(table_w * 0.74);
    var col_avg = table_rows_rect[0] + floor(table_w * 0.87);

    gv_draw_text_scaled_top_left(col_judge, hdr[1], "Judge", body_scale);
    gv_draw_text_scaled_top_left(col_score, hdr[1], "Score", body_scale);
    gv_draw_text_scaled_top_left(col_best, hdr[1], "Best", body_scale);
    gv_draw_text_scaled_top_left(col_avg, hdr[1], "Avg", body_scale);

    var row_h = max(16, floor(real(layout.row_h)));
    var max_rows_visible = max(1, floor((table_rows_rect[3] - table_rows_rect[1]) / row_h));
    var row_count = min(array_length(judge_rows), max_rows_visible);
    var row_hitboxes = [];

    for (var row_i = 0; row_i < row_count; row_i++) {
        var row_rect = [
            table_rows_rect[0],
            table_rows_rect[1] + (row_i * row_h),
            table_rows_rect[2],
            table_rows_rect[1] + ((row_i + 1) * row_h)
        ];
        var row_data = judge_rows[row_i];
        if (!is_struct(row_data)) continue;

        var row_judge_id = string(variable_struct_exists(row_data, "judge_id") ? variable_struct_get(row_data, "judge_id") : "");
        var is_selected = (row_judge_id != "" && row_judge_id == selected_judge);

        draw_set_color(is_selected ? make_color_rgb(42, 42, 52) : make_color_rgb(30, 30, 36));
        draw_rectangle(row_rect[0], row_rect[1], row_rect[2], row_rect[3], false);
        draw_set_color(c_dkgray);
        draw_rectangle(row_rect[0], row_rect[1], row_rect[2], row_rect[3], true);

        var text_offset_y = max(2, floor((row_h - (body_line_h - 2)) / 2));
        draw_set_color(c_white);
        gv_draw_text_scaled_top_left(col_judge, row_rect[1] + text_offset_y, string(variable_struct_exists(row_data, "judge_name") ? variable_struct_get(row_data, "judge_name") : "-"), body_scale);
        gv_draw_text_scaled_top_left(col_score, row_rect[1] + text_offset_y, string(variable_struct_exists(row_data, "score") ? variable_struct_get(row_data, "score") : "-"), body_scale);
        gv_draw_text_scaled_top_left(col_best, row_rect[1] + text_offset_y, string(variable_struct_exists(row_data, "best") ? variable_struct_get(row_data, "best") : "-"), body_scale);
        gv_draw_text_scaled_top_left(col_avg, row_rect[1] + text_offset_y, string(variable_struct_exists(row_data, "avg") ? variable_struct_get(row_data, "avg") : "-"), body_scale);

        array_push(row_hitboxes, {
            judge_id: row_judge_id,
            x1: row_rect[0],
            y1: row_rect[1],
            x2: row_rect[2],
            y2: row_rect[3]
        });
    }

    global.timeline_state.score_judge_row_hitboxes = row_hitboxes;

    if (!variable_struct_exists(global.timeline_state, "score_detail_popup") || !is_struct(global.timeline_state.score_detail_popup)) {
        global.timeline_state.score_detail_popup = { visible: false };
    }

    var popup_state = global.timeline_state.score_detail_popup;
    if (variable_struct_exists(popup_state, "visible") && popup_state.visible) {
        var popup_judge_id = variable_struct_exists(popup_state, "judge_id")
            ? string(variable_struct_get(popup_state, "judge_id"))
            : selected_judge;
        if (popup_judge_id == "") popup_judge_id = selected_judge;

        var popup_lines = gv_scoring_get_popup_lines(selected_measure, popup_judge_id, selected_ctx.part, selected_ctx.nav_idx, selected_ctx.measure_key);
        var max_popup_lines = min(8, array_length(popup_lines));
        var popup_inner_w = 180;
        for (var popup_i = 0; popup_i < max_popup_lines; popup_i++) {
            popup_inner_w = max(popup_inner_w, string_width(string(popup_lines[popup_i])) * body_scale);
        }
        popup_inner_w = max(popup_inner_w, string_width("Judge detail") * title_scale);

        var popup_header_h = max(body_line_h + 10, 22);
        var popup_w = clamp(ceil(popup_inner_w) + 28, 240, 520);
        var popup_x1 = min(_x2 - popup_w - 8, panel_rect[2] + 10);
        var popup_y1 = panel_rect[1] + 10;
        var popup_content_y = popup_y1 + 8 + popup_header_h + 8;
        var popup_h = (popup_content_y - popup_y1) + (max_popup_lines * body_line_h) + 10;
        var popup_x2 = popup_x1 + popup_w;
        var popup_y2 = min(_y2 - 8, popup_y1 + popup_h);

        draw_set_alpha(0.96);
        draw_set_color(make_color_rgb(16, 16, 20));
        draw_rectangle(popup_x1, popup_y1, popup_x2, popup_y2, false);
        draw_set_alpha(1);
        draw_set_color(make_color_rgb(90, 90, 98));
        draw_rectangle(popup_x1, popup_y1, popup_x2, popup_y2, true);

        draw_set_color(c_white);
        gv_draw_text_scaled_top_left(popup_x1 + 6, popup_y1 + 6, "Judge detail", title_scale);

        var divider_y = popup_y1 + 8 + popup_header_h;
        draw_set_color(make_color_rgb(90, 90, 98));
        draw_line(popup_x1 + 6, divider_y, popup_x2 - 20, divider_y);

        var close_rect = [popup_x2 - 16, popup_y1 + 5, popup_x2 - 4, popup_y1 + 17];
        draw_set_color(c_ltgray);
        draw_rectangle(close_rect[0], close_rect[1], close_rect[2], close_rect[3], true);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text_transformed((close_rect[0] + close_rect[2]) * 0.5, (close_rect[1] + close_rect[3]) * 0.5, "x", body_scale, body_scale, 0);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);

        for (var detail_i = 0; detail_i < max_popup_lines; detail_i++) {
            draw_set_color(c_ltgray);
            gv_draw_text_scaled_top_left(popup_x1 + 8, popup_content_y + (detail_i * body_line_h), string(popup_lines[detail_i]), body_scale);
        }

        global.timeline_state.score_detail_popup = {
            visible: true,
            judge_id: popup_judge_id,
            popup_rect: [popup_x1, popup_y1, popup_x2, popup_y2],
            close_rect: close_rect
        };
    } else {
        global.timeline_state.score_detail_popup = { visible: false };
    }
}

/// @function gv_gameviz_draw_toggle_button(_rect, _label, _selected, _enabled)
/// @description Draw a two-state toggle button (selected/unselected/disabled) inside a rect array.
/// @param {array} _rect      Four-element [x1,y1,x2,y2] rect.
/// @param {string} _label    Button text label.
/// @param {bool}  _selected  Whether the button is in the "on" state.
/// @param {bool}  _enabled   Whether the button is interactive (default true).
function gv_gameviz_draw_toggle_button(_rect, _label, _selected, _enabled = true) {
    var x1 = _rect[0];
    var y1 = _rect[1];
    var x2 = _rect[2];
    var y2 = _rect[3];

    if (!_enabled) {
        draw_set_colour(make_colour_rgb(28, 28, 28));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(c_dkgray);
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_gray);
    } else if (_selected) {
        draw_set_colour(make_colour_rgb(68, 112, 160));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(c_white);
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_white);
    } else {
        draw_set_colour(make_colour_rgb(38, 38, 38));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(c_ltgray);
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_ltgray);
    }

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text((x1 + x2) * 0.5, (y1 + y2) * 0.5, _label);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @function gv_perf_summary_struct_get(_s, _k, _default)
/// @description Safely read a dynamic field from a struct.
/// @param {struct} _s Source struct
/// @param {string} _k Field key
/// @param _default Fallback value
/// @returns Field value or _default
function gv_perf_summary_struct_get(_s, _k, _default = undefined) {
    if (!is_struct(_s)) return _default;
    if (!variable_struct_exists(_s, _k)) return _default;
    return variable_struct_get(_s, _k);
}

/// @function gv_perf_summary_get_latest(_force_refresh)
/// @description Load/cache the latest compact performance run summary from run_summaries.jsonl.
/// @param {bool} _force_refresh True to bypass cache and reread disk
/// @returns {struct|undefined} Latest summary object, or undefined when unavailable
function gv_perf_summary_get_latest(_force_refresh = false) {
    static cache = {
        loaded: false,
        last_read_ms: -1000000000,
        summary: undefined
    };

    var now_ms = timing_get_engine_now_ms();
    if (!_force_refresh && cache.loaded && (now_ms - cache.last_read_ms) < 750) {
        return cache.summary;
    }

    var perf_root = script_exists(asset_get_index("scr_data_paths_get_category_root"))
        ? scr_data_paths_get_category_root("performances")
        : "datafiles/performances/";
    if (string_copy(perf_root, string_length(perf_root), 1) != "/") {
        perf_root += "/";
    }

    var path = perf_root + "run_summaries.jsonl";
    cache.loaded = true;
    cache.last_read_ms = now_ms;
    cache.summary = undefined;
    if (!file_exists(path)) {
        return undefined;
    }

    var f = file_text_open_read(path);
    if (f < 0) {
        return undefined;
    }

    var last_line = "";
    while (!file_text_eof(f)) {
        var line = string_trim(file_text_readln(f));
        if (line != "") last_line = line;
    }
    file_text_close(f);

    if (last_line == "") {
        return undefined;
    }

    try {
        var parsed = json_parse(last_line);
        if (is_struct(parsed)) {
            cache.summary = parsed;
            return cache.summary;
        }
    } catch (e) {
        show_debug_message("[PERF_SUMMARY] Could not parse last JSONL line: " + string(e));
    }

    return undefined;
}

/// @function gv_perf_summary_is_warn(_summary)
/// @description Classify latest run summary using conservative warning thresholds.
/// @param {struct} _summary Run summary struct
/// @returns {bool} True when any metric exceeds warn threshold
function gv_perf_summary_is_warn(_summary) {
    if (!is_struct(_summary)) return false;

    var ctrl = gv_perf_summary_struct_get(_summary, "controller_step_interval_ms", undefined);
    var sched = gv_perf_summary_struct_get(_summary, "scheduler_late_ms", undefined);
    var ctrl_p95 = real(gv_perf_summary_struct_get(ctrl, "p95", 0));
    var sched_p95 = real(gv_perf_summary_struct_get(sched, "p95", 0));
    var spikes = floor(real(gv_perf_summary_struct_get(_summary, "spike_count", 0)));

    var warn_ctrl_p95_ms = 6.0;
    var warn_sched_p95_ms = 6.0;
    var warn_spikes = 1;
    return (ctrl_p95 >= warn_ctrl_p95_ms)
        || (sched_p95 >= warn_sched_p95_ms)
        || (spikes >= warn_spikes);
}

/// @function gv_gameviz_draw_perf_summary_button(_rect, _summary, _enabled)
/// @description Draw a compact "Last Run" performance tile.
/// @param {array} _rect [x1,y1,x2,y2]
/// @param {struct|undefined} _summary Latest run summary
/// @param {bool} _enabled Whether tile should render as active
function gv_gameviz_draw_perf_summary_button(_rect, _summary, _enabled = true) {
    var x1 = _rect[0];
    var y1 = _rect[1];
    var x2 = _rect[2];
    var y2 = _rect[3];

    var has_summary = is_struct(_summary);
    var warn = has_summary && gv_perf_summary_is_warn(_summary);

    if (!_enabled || !has_summary) {
        draw_set_colour(make_colour_rgb(28, 28, 28));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(c_dkgray);
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_gray);
    } else if (warn) {
        draw_set_colour(make_colour_rgb(92, 34, 34));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(make_colour_rgb(220, 130, 130));
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_white);
    } else {
        draw_set_colour(make_colour_rgb(34, 84, 44));
        draw_rectangle(x1, y1, x2, y2, false);
        draw_set_colour(make_colour_rgb(145, 214, 160));
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_colour(c_white);
    }

    var line1 = "Perf: N/A";
    var line2 = "Tap for details";
    if (has_summary) {
        var ctrl = gv_perf_summary_struct_get(_summary, "controller_step_interval_ms", undefined);
        var sched = gv_perf_summary_struct_get(_summary, "scheduler_late_ms", undefined);
        var ctrl_p95 = real(gv_perf_summary_struct_get(ctrl, "p95", 0));
        var sched_p95 = real(gv_perf_summary_struct_get(sched, "p95", 0));
        var spikes = floor(real(gv_perf_summary_struct_get(_summary, "spike_count", 0)));
        line1 = warn ? "Perf: WARN" : "Perf: OK";
        line2 = "c95 " + string_format(ctrl_p95, 0, 2)
            + " s95 " + string_format(sched_p95, 0, 2)
            + " sp " + string(spikes);
    }

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_transformed((x1 + x2) * 0.5, y1 + max(6, floor((y2 - y1) * 0.34)), line1, 0.8, 0.8, 0);
    draw_text_transformed((x1 + x2) * 0.5, y1 + max(10, floor((y2 - y1) * 0.68)), line2, 0.62, 0.62, 0);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @function gv_perf_summary_build_lines(_summary)
/// @description Build multi-line detail strings for the performance summary popup.
/// @param {struct|undefined} _summary Latest run summary
/// @returns {array} Text lines for popup body
function gv_perf_summary_build_lines(_summary) {
    if (!is_struct(_summary)) {
        return [
            "No run summary available.",
            "Finish a run and tap refresh."
        ];
    }

    var mode = string(gv_perf_summary_struct_get(_summary, "mode", "single"));
    var title = string(gv_perf_summary_struct_get(_summary, "title", "unknown"));
    var segs = floor(real(gv_perf_summary_struct_get(_summary, "segments", 0)));
    var elapsed = real(gv_perf_summary_struct_get(_summary, "elapsed_ms", 0));
    var groups = floor(real(gv_perf_summary_struct_get(_summary, "groups_total", 0)));
    var events = floor(real(gv_perf_summary_struct_get(_summary, "events_total", 0)));
    var spikes = floor(real(gv_perf_summary_struct_get(_summary, "spike_count", 0)));

    var ctrl = gv_perf_summary_struct_get(_summary, "controller_step_interval_ms", undefined);
    var sched = gv_perf_summary_struct_get(_summary, "scheduler_late_ms", undefined);
    var draw = gv_perf_summary_struct_get(_summary, "draw_ms", undefined);
    var midi = gv_perf_summary_struct_get(_summary, "midi_process_ms", undefined);

    var ctrl_p95 = real(gv_perf_summary_struct_get(ctrl, "p95", 0));
    var ctrl_p99 = real(gv_perf_summary_struct_get(ctrl, "p99", 0));
    var ctrl_max = real(gv_perf_summary_struct_get(ctrl, "max", 0));
    var sched_p95 = real(gv_perf_summary_struct_get(sched, "p95", 0));
    var sched_p99 = real(gv_perf_summary_struct_get(sched, "p99", 0));
    var sched_max = real(gv_perf_summary_struct_get(sched, "max", 0));
    var draw_p95 = real(gv_perf_summary_struct_get(draw, "p95", 0));
    var midi_p95 = real(gv_perf_summary_struct_get(midi, "p95", 0));

    var short_title = title;
    if (string_length(short_title) > 40) {
        short_title = string_copy(short_title, 1, 40) + "...";
    }

    return [
        "Mode: " + mode + "   Segments: " + string(segs),
        "Title: " + short_title,
        "Elapsed: " + string_format(elapsed, 0, 2) + " ms   Groups: " + string(groups) + "   Events: " + string(events),
        "Ctrl ms p95 " + string_format(ctrl_p95, 0, 2) + "  p99 " + string_format(ctrl_p99, 0, 2) + "  max " + string_format(ctrl_max, 0, 2),
        "Sched ms p95 " + string_format(sched_p95, 0, 2) + "  p99 " + string_format(sched_p99, 0, 2) + "  max " + string_format(sched_max, 0, 2),
        "Draw p95 " + string_format(draw_p95, 0, 2) + " ms   MIDI p95 " + string_format(midi_p95, 0, 2) + " ms",
        "Spikes: " + string(spikes)
    ];
}

/// @function gv_perf_summary_popup_visible()
/// @description Return true when the performance summary popup state is visible.
/// @returns {bool}
/// @reads global.timeline_state.perf_summary_popup
function gv_perf_summary_popup_visible() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "perf_summary_popup") || !is_struct(global.timeline_state.perf_summary_popup)) {
        return false;
    }
    return bool(gv_perf_summary_struct_get(global.timeline_state.perf_summary_popup, "visible", false));
}

/// @function gv_gameviz_draw_perf_summary_popup(_x1, _y1, _x2, _y2, _summary, _replace_panel)
/// @description Draw on-canvas popup with detailed run metrics when enabled.
/// @param {real} _x1 Left edge of controls panel
/// @param {real} _y1 Top edge of controls panel
/// @param {real} _x2 Right edge of controls panel
/// @param {real} _y2 Bottom edge of controls panel
/// @param {struct|undefined} _summary Latest run summary
/// @param {bool} _replace_panel True to fill the supplied panel rect (judge-panel replacement mode)
/// @writes global.timeline_state.perf_summary_popup
function gv_gameviz_draw_perf_summary_popup(_x1, _y1, _x2, _y2, _summary, _replace_panel = false) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    if (!variable_struct_exists(global.timeline_state, "perf_summary_popup") || !is_struct(global.timeline_state.perf_summary_popup)) {
        global.timeline_state.perf_summary_popup = { visible: false };
    }

    var popup_state = global.timeline_state.perf_summary_popup;
    if (!variable_struct_exists(popup_state, "visible") || !popup_state.visible) return;

    var lines = gv_perf_summary_build_lines(_summary);
    var body_scale = 0.64;
    var title_scale = 0.78;
    var body_line_h = max(14, ceil(string_height("Ag") * body_scale) + 2);
    var popup_inner_w = 260;
    for (var i = 0; i < array_length(lines); i++) {
        popup_inner_w = max(popup_inner_w, string_width(string(lines[i])) * body_scale);
    }
    popup_inner_w = max(popup_inner_w, string_width("Performance Summary") * title_scale);

    var edge_pad = 8;
    var popup_w = clamp(ceil(popup_inner_w) + 30, 300, max(300, floor(_x2 - _x1) - (edge_pad * 2)));
    var popup_h = 40 + (array_length(lines) * body_line_h) + 14;
    var popup_x1 = max(_x1 + 6, min(_x2 - popup_w - 6, _x1 + 10));
    var popup_y1 = max(_y1 + 6, _y1 + 8);
    var popup_x2 = popup_x1 + popup_w;
    var popup_y2 = min(_y2 - 6, popup_y1 + popup_h);

    if (_replace_panel) {
        popup_x1 = _x1 + edge_pad;
        popup_y1 = _y1 + edge_pad;
        popup_x2 = _x2 - edge_pad;
        popup_y2 = _y2 - edge_pad;
        if (popup_x2 <= popup_x1 + 80) popup_x2 = popup_x1 + 80;
        if (popup_y2 <= popup_y1 + 40) popup_y2 = popup_y1 + 40;
    }

    draw_set_alpha(0.96);
    draw_set_color(make_color_rgb(16, 16, 20));
    draw_rectangle(popup_x1, popup_y1, popup_x2, popup_y2, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(90, 90, 98));
    draw_rectangle(popup_x1, popup_y1, popup_x2, popup_y2, true);

    draw_set_color(c_white);
    gv_draw_text_scaled_top_left(popup_x1 + 6, popup_y1 + 6, "Performance Summary", title_scale);

    var close_rect = [popup_x2 - 16, popup_y1 + 5, popup_x2 - 4, popup_y1 + 17];
    draw_set_color(c_ltgray);
    draw_rectangle(close_rect[0], close_rect[1], close_rect[2], close_rect[3], true);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_transformed((close_rect[0] + close_rect[2]) * 0.5, (close_rect[1] + close_rect[3]) * 0.5, "x", 0.6, 0.6, 0);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var line_y = popup_y1 + 28;
    for (var li = 0; li < array_length(lines); li++) {
        draw_set_color(c_ltgray);
        gv_draw_text_scaled_top_left(popup_x1 + 8, line_y, string(lines[li]), body_scale);
        line_y += body_line_h;
        if (line_y > popup_y2 - 8) break;
    }

    global.timeline_state.perf_summary_popup = {
        visible: true,
        popup_rect: [popup_x1, popup_y1, popup_x2, popup_y2],
        close_rect: close_rect
    };
}

/// @function gv_draw_gameviz_controls_panel(_x1, _y1, _x2, _y2)
/// @description Draw the gameviz controls buttons panel (ghost-mode toggle, overlay-mode, judges) within the given rect.
/// @param {real} _x1  Left edge.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @reads  global.timeline_state.playback_complete, global.timeline_cfg
function gv_draw_gameviz_controls_panel(_x1, _y1, _x2, _y2) {
    var layout = gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2);
    var can_interact = gv_gameviz_controls_can_interact();
    var score_mode = gv_get_timeline_score_visibility_mode();
    var score_images_visible = (score_mode == 0);
    var label = score_images_visible ? "Score" : "Marker";
    var review_active = variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "playback_complete")
        && global.timeline_state.playback_complete;

    draw_set_font(fnt_setting);
    gv_gameviz_draw_toggle_button(layout.btn_toggle, label, score_images_visible, can_interact);

    // Overlay mode button â€” only visible once playback is complete
    if (review_active) {
        var cfg = gv_ensure_timeline_cfg_defaults();
        var cur_mode = floor(real(cfg.notebeam_postplay_overlay_mode ?? 0));
        var mode_labels = ["Raw", "Segmented", "Planned", "History"];
        var mode_label = (cur_mode >= 0 && cur_mode < array_length(mode_labels))
            ? mode_labels[cur_mode] : "Raw";
        gv_gameviz_draw_toggle_button(layout.btn_overlay_mode, mode_label, cur_mode > 0, true);
        var scoring_visible = !variable_struct_exists(cfg, "scoring_panel_visible") || bool(variable_struct_get(cfg, "scoring_panel_visible"));
        gv_gameviz_draw_toggle_button(layout.btn_judges, "Judges", scoring_visible, true);

        // Loop Scores button — only when loop iteration scores were recorded
        var _has_loop_scores = variable_global_exists("timeline_state") && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "loop_iteration_scores")
            && array_length(global.timeline_state[$ "loop_iteration_scores"]) > 0;
        if (_has_loop_scores) {
            var _ls_layer_id = layer_get_id("loop_score_overview_layer");
            var _ls_visible  = (_ls_layer_id != -1) && layer_get_visible(_ls_layer_id);
            gv_gameviz_draw_toggle_button(layout.btn_slot4, "Loop Scores", _ls_visible, true);
        }

        // Phase 1 perf tile: show latest compact run summary status.
        var perf_summary = gv_perf_summary_get_latest(false);
        gv_gameviz_draw_perf_summary_button(layout.btn_slot5, perf_summary, true);
    }
}

/// @function gv_handle_gameviz_controls_click(_mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle a mouse click in the gameviz controls panel, toggling score visibility, overlay mode, scoring visibility, loop scores, or opening perf details.
/// @param {real} _mx  Mouse X.
/// @param {real} _my  Mouse Y.
/// @param {real} _x1  Panel left edge.
/// @param {real} _y1  Panel top edge.
/// @param {real} _x2  Panel right edge.
/// @param {real} _y2  Panel bottom edge.
/// @returns {bool}  true if click was consumed.
/// @reads  global.timeline_state.playback_complete, global.timeline_cfg
/// @writes global.timeline_cfg.timeline_score_visibility_mode, global.timeline_cfg.notebeam_postplay_overlay_mode, global.timeline_cfg.scoring_panel_visible, global.timeline_state.score_detail_popup, global.timeline_state.perf_summary_popup
function gv_handle_gameviz_controls_click(_mx, _my, _x1, _y1, _x2, _y2) {
    var layout = gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2);

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_toggle)) {
        if (!gv_gameviz_controls_can_interact()) return false;
        gv_cycle_timeline_score_visibility_mode();
        return true;
    }

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_overlay_mode)) {
        if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
        if (!variable_struct_exists(global.timeline_state, "playback_complete")
            || !global.timeline_state.playback_complete) return false;
        var cfg = gv_ensure_timeline_cfg_defaults();
        var cur_mode = floor(real(cfg.notebeam_postplay_overlay_mode ?? 0));
        variable_struct_set(cfg, "notebeam_postplay_overlay_mode", (cur_mode + 1) mod 4);
        return true;
    }

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_judges)) {
        if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
        if (!variable_struct_exists(global.timeline_state, "playback_complete")
            || !global.timeline_state.playback_complete) return false;
        var cfg = gv_ensure_timeline_cfg_defaults();
        var cur_vis = !variable_struct_exists(cfg, "scoring_panel_visible") || bool(variable_struct_get(cfg, "scoring_panel_visible"));
        variable_struct_set(cfg, "scoring_panel_visible", !cur_vis);
        return true;
    }

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_slot4)) {
        if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
        if (!variable_struct_exists(global.timeline_state, "playback_complete")
            || !global.timeline_state.playback_complete) return false;
        if (!variable_struct_exists(global.timeline_state, "loop_iteration_scores")
            || array_length(global.timeline_state[$ "loop_iteration_scores"]) == 0) return false;
        scr_toggle_loop_score_overview();
        return true;
    }

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_slot5)) {
        if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
        if (!variable_struct_exists(global.timeline_state, "playback_complete")
            || !global.timeline_state.playback_complete) return false;
        gv_perf_summary_get_latest(true);
        global.timeline_state.score_detail_popup = { visible: false };
        global.timeline_state.perf_summary_popup = { visible: true };
        return true;
    }

    return false;
}

/// @function scr_gameviz_set_ghost_mode(_enable_ghost)
/// @description Enable or disable ghost display of non-focus tune parts, writing timeline_cfg.tune_show_other_parts_ghost.
/// @param {bool} _enable_ghost  true to show all parts; false to show only the focus channel.
/// @writes global.timeline_cfg.tune_show_other_parts_ghost
function scr_gameviz_set_ghost_mode(_enable_ghost) {
    var cfg = gv_ensure_timeline_cfg_defaults();
    variable_struct_set(cfg, "tune_show_other_parts_ghost", bool(_enable_ghost));
}

/// @function scr_gameviz_get_ghost_mode()
/// @description Return the current ghost mode setting from timeline_cfg.
/// @returns {bool}  true if ghost mode is active.
/// @reads  global.timeline_cfg.tune_show_other_parts_ghost
function scr_gameviz_get_ghost_mode() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return false;
    if (!variable_struct_exists(global.timeline_cfg, "tune_show_other_parts_ghost")) return false;
    return bool(global.timeline_cfg.tune_show_other_parts_ghost);
}

/// @function scr_gameviz_init_config()
/// @description Initialise global.timeline_cfg with all default values. Called during game setup.
/// @writes global.timeline_cfg (via gv_ensure_timeline_cfg_defaults)
function scr_gameviz_init_config() {
    gv_ensure_timeline_cfg_defaults();
}

/// @function gv_timeline_run_maintenance(_now_ms)
/// @description Amortised per-step maintenance: prunes stale player history entries within a configurable time budget. Only runs when timeline is active.
/// @param {real} _now_ms  Current engine time in ms.
/// @reads  global.timeline_state.active, global.timeline_cfg
/// @writes global.timeline_state (via gv_timeline_prune_player_history_slice)
function gv_timeline_run_maintenance(_now_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!global.timeline_state.active) return;

    if (!variable_struct_exists(global.timeline_state, "player_in") || !is_array(global.timeline_state.player_in)) return;
    if (array_length(global.timeline_state.player_in) <= 0) {
        global.timeline_state.player_prune_cursor = 0;
        return;
    }

    var cfg = gv_ensure_timeline_cfg_defaults();
    var maintenance_enabled = true;
    if (variable_struct_exists(cfg, "notebeam_maintenance_enabled")) {
        maintenance_enabled = bool(variable_struct_get(cfg, "notebeam_maintenance_enabled"));
    }
    if (!maintenance_enabled) return;

    var is_live_playback = false;
    if (script_exists(asset_get_index("gv_is_live_playback"))) {
        is_live_playback = gv_is_live_playback();
    }
    var stride = variable_struct_exists(cfg, "notebeam_maintenance_stride_steps")
        ? max(1, floor(real(variable_struct_get(cfg, "notebeam_maintenance_stride_steps"))))
        : (is_live_playback ? 4 : 1);
    if (!variable_struct_exists(global.timeline_state, "maintenance_tick_count")) {
        global.timeline_state.maintenance_tick_count = 0;
    }
    global.timeline_state.maintenance_tick_count += 1;
    if ((global.timeline_state.maintenance_tick_count mod stride) != 0) return;

    var budget_ms = variable_struct_exists(cfg, "notebeam_maintenance_budget_ms")
        ? max(0.05, real(variable_struct_get(cfg, "notebeam_maintenance_budget_ms")))
        : 0.35;
    var maintenance_start_ms = timing_get_engine_now_ms();

    gv_timeline_prune_player_history_slice(_now_ms, budget_ms, maintenance_start_ms);
}

/// @function gv_timeline_prune_player_history_slice(_now_ms, _budget_ms, _start_ms)
/// @description Incrementally prune stale entries from global.timeline_state.player_in within a per-frame time budget. Compacts the array when the cursor advances past a threshold.
/// @param {real} _now_ms     Current engine time (used for compaction interval check).
/// @param {real} _budget_ms  Maximum wall-clock ms allowed for pruning work this tick.
/// @param {real} _start_ms   Engine timestamp at which the budget window started.
/// @reads  global.timeline_state.player_in, global.timeline_state.player_prune_cursor, global.timeline_cfg, global.timeline_state.playhead_ms
/// @writes global.timeline_state.player_prune_cursor, global.timeline_state.player_in, global.timeline_state.player_prune_last_compact_ms
function gv_timeline_prune_player_history_slice(_now_ms, _budget_ms, _start_ms) {
    if (!variable_struct_exists(global.timeline_state, "player_in") || !is_array(global.timeline_state.player_in)) return;

    var hist = global.timeline_state.player_in;
    var n_hist = array_length(hist);
    if (n_hist <= 0) {
        global.timeline_state.player_prune_cursor = 0;
        return;
    }

    var cfg = gv_ensure_timeline_cfg_defaults();
    var keep_window_ms = variable_struct_exists(cfg, "notebeam_player_history_window_ms")
        ? max(1000, real(variable_struct_get(cfg, "notebeam_player_history_window_ms")))
        : 12000;
    var playhead_ms = real(global.timeline_state.playhead_ms ?? 0);
    var trim_before_ms = playhead_ms - keep_window_ms;
    var scan_limit = variable_struct_exists(cfg, "notebeam_prune_scan_per_tick")
        ? max(8, floor(real(variable_struct_get(cfg, "notebeam_prune_scan_per_tick"))))
        : 64;

    var cursor = floor(real(global.timeline_state.player_prune_cursor ?? 0));
    cursor = clamp(cursor, 0, n_hist);
    var scanned = 0;

    while (cursor < n_hist && scanned < scan_limit) {
        if ((timing_get_engine_now_ms() - _start_ms) >= _budget_ms) break;

        var old_s = hist[cursor];
        if (!is_struct(old_s)) {
            cursor += 1;
            scanned += 1;
            continue;
        }

        var old_end = real(old_s.end_ms ?? 0);
        if (old_end >= trim_before_ms) break;

        cursor += 1;
        scanned += 1;
    }

    global.timeline_state.player_prune_cursor = cursor;

    var compact_min_prefix = variable_struct_exists(cfg, "notebeam_prune_compact_min_prefix")
        ? max(32, floor(real(variable_struct_get(cfg, "notebeam_prune_compact_min_prefix"))))
        : 128;
    var compact_interval_ms = variable_struct_exists(cfg, "notebeam_prune_compact_interval_ms")
        ? max(100, real(variable_struct_get(cfg, "notebeam_prune_compact_interval_ms")))
        : 750;
    var last_compact_ms = real(global.timeline_state.player_prune_last_compact_ms ?? 0);
    var should_compact = (cursor >= compact_min_prefix) && ((_now_ms - last_compact_ms) >= compact_interval_ms || cursor >= n_hist);
    if (!should_compact) return;
    if ((timing_get_engine_now_ms() - _start_ms) >= _budget_ms) return;

    var new_n = n_hist - cursor;
    if (new_n <= 0) {
        global.timeline_state.player_in = [];
        global.timeline_state.player_prune_cursor = 0;
        global.timeline_state.player_prune_last_compact_ms = _now_ms;
        return;
    }

    var new_hist = array_create(new_n);
    for (var i = 0; i < new_n; i++) {
        if ((timing_get_engine_now_ms() - _start_ms) >= _budget_ms) {
            // Defer compaction if budget is exceeded mid-copy.
            return;
        }
        new_hist[i] = hist[cursor + i];
    }

    global.timeline_state.player_in = new_hist;
    global.timeline_state.player_prune_cursor = 0;
    global.timeline_state.player_prune_last_compact_ms = _now_ms;
}

/// @function gv_rt_budget_diag_record_visual_alignment_ms(_abs_delta_ms)
/// @description Record the absolute delta between visual playhead and last dispatched event for RT diagnostic ring-buffer statistics.
/// @param {real} _abs_delta_ms  Absolute delta in ms between visual playhead and last dispatched expected_ms.
/// @reads  global.RT_BUDGET_DIAG_ENABLED, global.RT_BUDGET_DIAG_LOG_INTERVAL_MS, global.timeline_state.last_dispatched_expected_ms
/// @writes global.rt_budget_visual_align_buf, global.rt_budget_visual_align_head, global.rt_budget_visual_align_count, global.rt_budget_visual_diag_last_log_ms
function gv_rt_budget_diag_record_visual_alignment_ms(_abs_delta_ms) {
    if (!variable_global_exists("RT_BUDGET_DIAG_ENABLED") || !global.RT_BUDGET_DIAG_ENABLED) return;
    if (variable_global_exists("RT_BUDGET_DIAG_INCLUDE_VISUAL_ALIGN") && !global.RT_BUDGET_DIAG_INCLUDE_VISUAL_ALIGN) return;

    if (!variable_global_exists("rt_budget_visual_align_buf") || !is_array(global.rt_budget_visual_align_buf)) {
        global.rt_budget_visual_align_buf = array_create(128, 0);
        global.rt_budget_visual_align_head = 0;
        global.rt_budget_visual_align_count = 0;
        global.rt_budget_visual_diag_last_log_ms = timing_get_engine_now_ms();
    }

    var buf = global.rt_budget_visual_align_buf;
    var n_buf = array_length(buf);
    if (n_buf <= 0) return;

    var head = floor(real(global.rt_budget_visual_align_head ?? 0));
    head = ((head mod n_buf) + n_buf) mod n_buf;
    buf[head] = abs(real(_abs_delta_ms));

    global.rt_budget_visual_align_buf = buf;
    global.rt_budget_visual_align_head = (head + 1) mod n_buf;
    global.rt_budget_visual_align_count = min(n_buf, floor(real(global.rt_budget_visual_align_count ?? 0)) + 1);

    var now_ms = timing_get_engine_now_ms();
    var interval_ms = max(250, real(global.RT_BUDGET_DIAG_LOG_INTERVAL_MS ?? 1000));
    if ((now_ms - real(global.rt_budget_visual_diag_last_log_ms ?? 0)) < interval_ms) return;

    var count = floor(real(global.rt_budget_visual_align_count ?? 0));
    if (count < 8) return;

    var vals = array_create(count, 0);
    for (var i = 0; i < count; i++) {
        vals[i] = real(buf[i]);
    }
    array_sort(vals, function(a, b) { return real(a) - real(b); });

    var i50 = floor((count - 1) * 0.50);
    var i95 = floor((count - 1) * 0.95);
    var i99 = floor((count - 1) * 0.99);
    var p50 = vals[i50];
    var p95 = vals[i95];
    var p99 = vals[i99];

    show_debug_message("[RT_BUDGET] visual_vs_dispatch_abs_ms p50=" + string_format(p50, 0, 3)
        + " p95=" + string_format(p95, 0, 3)
        + " p99=" + string_format(p99, 0, 3)
        + " n=" + string(count));

    global.rt_budget_visual_diag_last_log_ms = now_ms;
}

// Shared timeline tick so playhead/review input still work when timeline is drawn
// from RoomUI anchors without an obj_game_viz instance in the room.
/// @function gv_timeline_step_tick()
/// @description Per-step tick: advances the playhead clock, handles mouse input for review navigation, smooth-pans the notebeam, and auto-advances the active set segment. Called from obj_game_controller Step event.
/// @returns {bool}  false if timeline is disabled or inactive; true otherwise.
/// @reads  global.timeline_cfg, global.timeline_state, global.TIMELINE_STEP_LAST_MS, global.tune_start_real, global.playback_context
/// @writes global.TIMELINE_STEP_LAST_MS, global.timeline_state.playhead_ms, global.timeline_state.start_clock_ms, global.playback_context.active_segment, global.timeline_cfg.notebeam_view_offset_ms
/// @callers obj_game_controller Step event
function gv_timeline_step_tick() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return false;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return false;

// Expose a stable global reference so object events can call the timeline tick
// even if direct identifier resolution changes across compile/runtime contexts.
global.gv_timeline_step_tick_ref = gv_timeline_step_tick;
    var now_ms = timing_get_engine_now_ms();

    // Avoid duplicate processing when multiple instances call this in one frame.
    if (variable_global_exists("TIMELINE_STEP_LAST_MS")) {
        if (real(global.TIMELINE_STEP_LAST_MS) == now_ms) {
            return false;
        }
    }
    global.TIMELINE_STEP_LAST_MS = now_ms;

    var cfg = gv_ensure_timeline_cfg_defaults();

    if (!variable_struct_exists(cfg, "enabled") || !cfg.enabled) return false;

    var loop_mode = gv_loop_mode_enabled();
    var is_live_playback = gv_is_live_playback();
    var score_images_visible = gv_should_draw_timeline_score_images();
    if (!is_live_playback && mouse_check_button_pressed(mb_left)) {
        // Review controls and measure tiles are tracked in world/screen space.
        gv_review_handle_click(mouse_x, mouse_y);
    }

    if (!is_live_playback) {
        var notebeam_rect = gv_get_anchor_rect_by_name("notebeam_canvas_anchor");
        if (is_struct(notebeam_rect)
            && mouse_x >= real(variable_struct_get(notebeam_rect, "x1"))
            && mouse_x <= real(variable_struct_get(notebeam_rect, "x2"))
            && mouse_y >= real(variable_struct_get(notebeam_rect, "y1"))
            && mouse_y <= real(variable_struct_get(notebeam_rect, "y2"))) {
            if (mouse_wheel_up()) gv_notebeam_pan_by_steps(-1);
            if (mouse_wheel_down()) gv_notebeam_pan_by_steps(1);
        }
    }

    if (!is_live_playback && variable_struct_exists(cfg, "notebeam_view_offset_target_ms")) {
        var smooth_enabled = !variable_struct_exists(cfg, "notebeam_pan_smooth_enabled")
            || variable_struct_get(cfg, "notebeam_pan_smooth_enabled");
        var target_offset_ms = real(variable_struct_get(cfg, "notebeam_view_offset_target_ms"));
        var current_offset_ms = variable_struct_exists(cfg, "notebeam_view_offset_ms")
            ? real(variable_struct_get(cfg, "notebeam_view_offset_ms"))
            : target_offset_ms;

        if (smooth_enabled) {
            var smooth_factor = variable_struct_exists(cfg, "notebeam_pan_smooth_factor")
                ? clamp(real(variable_struct_get(cfg, "notebeam_pan_smooth_factor")), 0.05, 1.0)
                : 0.35;
            current_offset_ms += (target_offset_ms - current_offset_ms) * smooth_factor;
            if (abs(target_offset_ms - current_offset_ms) <= 0.5) {
                current_offset_ms = target_offset_ms;
            }
        } else {
            current_offset_ms = target_offset_ms;
        }

        variable_struct_set(cfg, "notebeam_view_offset_ms", current_offset_ms);
    }

    var review_mode = variable_struct_exists(global.timeline_state, "review_mode") && global.timeline_state.review_mode;
    if (review_mode) return true;

    var playhead_lag_ms = 0;
    if (variable_struct_exists(cfg, "playhead_audio_lag_ms")) {
        playhead_lag_ms = max(0, real(cfg.playhead_audio_lag_ms));
    }

    if (variable_global_exists("tune_start_real")) {
        global.timeline_state.playhead_ms = max(0, now_ms - real(global.tune_start_real) - playhead_lag_ms);
    } else {
        if (!variable_struct_exists(global.timeline_state, "start_clock_ms")) {
            global.timeline_state.start_clock_ms = now_ms;
        }
        global.timeline_state.playhead_ms = max(0, now_ms - real(global.timeline_state.start_clock_ms) - playhead_lag_ms);
    }

    if (variable_struct_exists(global.timeline_state, "last_dispatched_expected_ms")) {
        var last_dispatched_expected = max(0, real(global.timeline_state.last_dispatched_expected_ms));
        var visual_unlagged = real(global.timeline_state.playhead_ms) + playhead_lag_ms;
        gv_rt_budget_diag_record_visual_alignment_ms(visual_unlagged - last_dispatched_expected);
    }

    // Auto-advance structure panel segment during set playback.
    // When the playhead crosses into the next segment, update active_segment
    // and rebuild the measure nav so the panel tracks the current tune.
    if (variable_global_exists("playback_context") && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set") {
        var _ac_segs = global.playback_context[$ "segments"];
        var _ac_n = is_array(_ac_segs) ? array_length(_ac_segs) : 0;
        if (_ac_n > 1) {
            var _ac_cur = floor(real(global.playback_context[$ "active_segment"] ?? 0));
            var _ph = real(global.timeline_state.playhead_ms ?? 0);
            // Advance forward while playhead is past the current segment's end.
            while (_ac_cur < _ac_n - 1) {
                var _ac_seg = _ac_segs[_ac_cur];
                var _ac_end = real(_ac_seg[$ "end_ms"] ?? 0);
                if (_ph < _ac_end) break;
                _ac_cur++;
            }
            // Retreat backward while playhead is before the current segment's start.
            while (_ac_cur > 0) {
                var _ac_seg = _ac_segs[_ac_cur];
                var _ac_start = real(_ac_seg[$ "start_ms"] ?? 0);
                if (_ph >= _ac_start) break;
                _ac_cur--;
            }
            var _ac_prev = floor(real(global.playback_context[$ "active_segment"] ?? 0));
            if (_ac_cur != _ac_prev) {
                global.playback_context[$ "active_segment"] = _ac_cur;
                gv_rebuild_measure_nav_for_segment(_ac_cur);
                scr_gameinfo_update_title(_ac_cur);
                var _new_seg = _ac_segs[_ac_cur];
                
                if (score_images_visible) {
                    // Restore score sprites from preloaded segment cache.
                    gv_restore_score_segment_cache(_ac_cur, true);
                    var _seg_filename = string(_new_seg[$ "filename"] ?? "");
                    if (_seg_filename != "") scr_score_override_groups_load_for_current_segment(_seg_filename);

                    // Segment switches invalidate any future precomputed score render plan.
                    global.timeline_state.score_render_plan_needs_rebuild = true;
                    global.timeline_state.score_render_plan_pending_reason = "segment_change_step";
                    if (variable_struct_exists(global.timeline_state, "score_render_plan")
                        && is_struct(global.timeline_state.score_render_plan)) {
                        global.timeline_state.score_render_plan.valid = false;
                        global.timeline_state.score_render_plan.status = "pending";
                        global.timeline_state.score_render_plan.reason = "segment_change_step";
                    }
                    if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
                        && is_struct(global.timeline_state.score_render_plan_stats)) {
                        global.timeline_state.score_render_plan_stats.invalidations += 1;
                        global.timeline_state.score_render_plan_stats.last_reason = "segment_change_step";
                    }
                    global.timeline_state.score_lane_layout_cache_single = {};
                } else {
                    // Keep the timeline responsive without paying for score-lane rebuild work while the
                    // score imagery is hidden. The next visible draw will rebuild the plan on demand.
                    global.timeline_state.score_render_plan_needs_rebuild = true;
                    global.timeline_state.score_render_plan_pending_reason = "segment_change_step_hidden";
                    if (variable_struct_exists(global.timeline_state, "score_render_plan")
                        && is_struct(global.timeline_state.score_render_plan)) {
                        global.timeline_state.score_render_plan.valid = false;
                        global.timeline_state.score_render_plan.status = "pending";
                        global.timeline_state.score_render_plan.reason = "segment_change_step_hidden";
                    }
                    if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
                        && is_struct(global.timeline_state.score_render_plan_stats)) {
                        global.timeline_state.score_render_plan_stats.invalidations += 1;
                        global.timeline_state.score_render_plan_stats.last_reason = "segment_change_step_hidden";
                    }
                }
                
                // ───────────────────────────────────────────────────────────────
                // PHASE 3: Recalculate measure_ms from new segment's BPM/meter
                // to prevent score lane compression at segment transitions.
                // ───────────────────────────────────────────────────────────────
                var _seg_bpm = real(_new_seg[$ "bpm"] ?? 120);
                var _seg_meter = string(_new_seg[$ "meter"] ?? "4/4");
                var _meter_parts = string_split(_seg_meter, "/");
                var _meter_num = real(_meter_parts[0] ?? 4);
                var _meter_den = real(_meter_parts[1] ?? 4);
                
                var _new_measure_ms = gv_measure_ms(_seg_bpm, _meter_num, _meter_den);
                global.timeline_state.measure_ms = _new_measure_ms;
                global.timeline_state.meter_num = _meter_num;
                global.timeline_state.meter_den = _meter_den;

                // Keep window extents in sync with timeline_cfg after per-segment meter/BPM changes.
                gv_notebeam_sync_window_from_cfg();

                // Reset highlight caches and reseed segment-local measure to avoid
                // carrying a stale measure number from the previous segment.
                global.timeline_state.measure_highlight_last_measure = -1;
                global.timeline_state.measure_highlight_last_nav_idx = -1;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                var _seg_seed = gv_resolve_measure_context(_ph);
                var _seg_seed_measure = floor(real(_seg_seed.measure ?? -1));
                global.timeline_state.current_measure = max(0, floor(real(_seg_seed_measure)));
                
                show_debug_message("  [SEGMENT TRANSITION] Segment " + string(_ac_cur) + ": measure_ms=" + string(_new_measure_ms)
                    + " (BPM=" + string(_seg_bpm) + ", meter=" + _seg_meter + ")");
            }

        }
    }

    // Amortize non-critical timeline maintenance across steps.
    gv_timeline_run_maintenance(now_ms);

    return true;
}

// Returns visibility mode for tune-planned spans:
// 0 = hidden, 1 = ghost, 2 = focus/target part
/// @function gv_get_tune_span_visibility_state(_channel)
/// @description Return the visibility mode for planned spans on a given channel: 0=hidden, 1=ghost, 2=focus.
/// @param {real} _channel  MIDI channel to check.
/// @returns {real}  0, 1, or 2.
/// @reads  global.timeline_cfg.tune_channel (via gv_get_target_tune_channel and gv_use_tune_ghost_parts)
function gv_get_tune_span_visibility_state(_channel) {
    var ch = floor(real(_channel));
    if (!gv_is_bagpipe_tune_channel(ch)) return 0;

    var target_ch = gv_get_target_tune_channel();
    if (ch == target_ch) return 2;

    if (gv_use_tune_ghost_parts()) return 1;
    return 0;
}

/// @function gv_is_tune_focus_channel(_channel)
/// @description Return true if the given channel is the current focus tune channel.
/// @param {real} _channel  MIDI channel to check.
/// @returns {bool}
function gv_is_tune_focus_channel(_channel) {
    return (gv_get_tune_span_visibility_state(_channel) == 2);
}

/// @function gv_planned_spans_have_focus_channel(_spans)
/// @description Return true if any span in the array belongs to the current focus tune channel.
/// @param {array} _spans  Array of planned-span structs.
/// @returns {bool}
function gv_planned_spans_have_focus_channel(_spans) {
    if (!is_array(_spans)) return false;
    var n = array_length(_spans);
    for (var i = 0; i < n; i++) {
        var s = _spans[i];
        if (!is_struct(s)) continue;
        if (gv_is_tune_focus_channel(real(s.channel ?? -999))) return true;
    }
    return false;
}

/// @function gv_build_planned_spans(_events)
/// @description Convert a flat array of planned note_on/note_off events into matched span structs with start_ms, end_ms, lane_idx, note info, etc. Reads global.MIDI_chanter for canonical mapping.
/// @param {array} _events  Array of planned event structs.
/// @returns {array}  Array of span structs.
/// @reads  global.MIDI_chanter (via chanter_midi_to_canonical)
function gv_build_planned_spans(_events) {
    var _spans = [];
    var _active = {}; // key -> stack of note_on structs
    var _last_note_event_ms = 0;
    var _dangling_tail_ms = 90;

    if (!is_array(_events)) return _spans;

    var _n = array_length(_events);
    for (var i = 0; i < _n; i++) {
        var e = _events[i];
        if (!is_struct(e) || !variable_struct_exists(e, "type")) continue;

        var _type = string(e.type);
        if (_type != "note_on" && _type != "note_off") continue;

        var _t = gv_evt_time_ms(e);
        if (_t > _last_note_event_ms) _last_note_event_ms = _t;
        var _ch = variable_struct_exists(e, "channel") ? real(e.channel) : 0;

        var _note = -1;
        if (variable_struct_exists(e, "note")) _note = real(e.note);
        else if (variable_struct_exists(e, "note_midi")) _note = real(e.note_midi);
        if (_note < 0) continue;

        var _measure = variable_struct_exists(e, "measure") ? real(e.measure) : -1;
        var _part = variable_struct_exists(e, "part") ? real(e.part) : 1;
        if (_part < 1) _part = 1;
        var _beat = variable_struct_exists(e, "beat") ? real(e.beat) : -1;
        var _bf = 0;
        if (variable_struct_exists(e, "beat_fraction")) _bf = real(e.beat_fraction);
        else if (variable_struct_exists(e, "beat_frac")) _bf = real(e.beat_frac);
        var _eid = variable_struct_exists(e, "event_id") ? e.event_id : "";
        var _is_emb = variable_struct_exists(e, "is_embellishment") && e.is_embellishment;
        var _canonical = chanter_midi_to_canonical(_note, global.MIDI_chanter ?? "default", _ch);
        var _lane_idx = gv_note_to_lane_index(_canonical, _note, _ch);
        var _measure_ref_key_seed = "";
        if (_measure >= 1) {
            _measure_ref_key_seed = string(floor(_part)) + ":" + string(floor(_measure));
        }

        var _k = gv_note_key(_ch, _note);

        if (_type == "note_on") {
            var _on = {
                start_ms: _t,
                note_midi: _note,
                note_canonical: _canonical,
                note_letter: chanter_canonical_to_display(_canonical),
                lane_idx: _lane_idx,
                is_embellishment: _is_emb,
                channel: _ch,
                part: _part,
                measure: _measure,
                beat: _beat,
                beat_fraction: _bf,
                measure_ref_key_seed: _measure_ref_key_seed,
                event_id: _eid
            };

            if (!variable_struct_exists(_active, _k)) _active[$ _k] = [];
            var _stack_on = _active[$ _k];
            array_push(_stack_on, _on);
            _active[$ _k] = _stack_on;
        } else { // note_off
            if (!variable_struct_exists(_active, _k)) continue;

            var _stack_off = _active[$ _k];
            var _len = array_length(_stack_off);
            if (_len <= 0) continue;

            var _on2 = _stack_off[_len - 1];
            array_resize(_stack_off, _len - 1);
            _active[$ _k] = _stack_off;

            var _end_ms = max(_on2.start_ms, _t);

            array_push(_spans, {
                source: "tune_planned",
                start_ms: _on2.start_ms,
                end_ms: _end_ms,
                dur_ms: _end_ms - _on2.start_ms,
                note_midi: _on2.note_midi,
                note_canonical: _on2.note_canonical,
                note_letter: _on2.note_letter,
                lane_idx: real(_on2.lane_idx ?? -1),
                is_embellishment: _on2.is_embellishment,
                channel: _on2.channel,
                part: _on2.part,
                measure: _on2.measure,
                beat: _on2.beat,
                beat_fraction: _on2.beat_fraction,
                measure_ref_key_seed: _on2.measure_ref_key_seed,
                event_id: _on2.event_id
            });
        }
    }

    // Some streams end with note_on events and rely on transport/all-notes-off,
    // so synthesize short tails for unmatched notes to keep final planned beams visible.
    var _active_keys = variable_struct_get_names(_active);
    for (var _ki = 0; _ki < array_length(_active_keys); _ki++) {
        var _k2 = string(_active_keys[_ki]);
        if (!variable_struct_exists(_active, _k2)) continue;
        var _stack_tail = _active[$ _k2];
        if (!is_array(_stack_tail) || array_length(_stack_tail) <= 0) continue;

        for (var _si = 0; _si < array_length(_stack_tail); _si++) {
            var _on_tail = _stack_tail[_si];
            if (!is_struct(_on_tail)) continue;

            var _tail_end_ms = real(_on_tail.start_ms) + _dangling_tail_ms;
            array_push(_spans, {
                source: "tune_planned",
                start_ms: _on_tail.start_ms,
                end_ms: _tail_end_ms,
                dur_ms: _tail_end_ms - real(_on_tail.start_ms),
                note_midi: _on_tail.note_midi,
                note_canonical: _on_tail.note_canonical,
                note_letter: _on_tail.note_letter,
                lane_idx: real(_on_tail.lane_idx ?? -1),
                is_embellishment: _on_tail.is_embellishment,
                channel: _on_tail.channel,
                part: _on_tail.part,
                measure: _on_tail.measure,
                beat: _on_tail.beat,
                beat_fraction: _on_tail.beat_fraction,
                measure_ref_key_seed: _on_tail.measure_ref_key_seed,
                event_id: _on_tail.event_id
            });
        }
    }

    if (array_length(_spans) > 1) {
        array_sort(_spans, function(_a, _b) {
            var _as = real(_a.start_ms ?? 0);
            var _bs = real(_b.start_ms ?? 0);
            if (_as != _bs) return _as - _bs;
            return real(_a.end_ms ?? _as) - real(_b.end_ms ?? _bs);
        });
    }

    return _spans;
}

/// @function gv_score_plan_prebuild_single_tune(_planned_events)
/// @description Prebuild and persist a single-tune, non-loop score render plan at bind time to reduce first-draw cache misses.
/// @param {array} _planned_events Planned events array for the run.
/// @returns {bool} True when a plan was built and persisted.
/// @reads global.timeline_state, global.timeline_cfg, global.loop_runtime_active, global.METRONOME_CONFIG, global.score_snippet_durations, global.score_playback_map, global.score_has_pickup, global.score_units_per_measure
/// @writes global.timeline_state.score_render_plan, global.timeline_state.score_render_plan_needs_rebuild, global.timeline_state.score_render_plan_pending_reason, global.timeline_state.score_render_plan_stats, global.timeline_state.score_lane_layout_cache_single, global.timeline_state.structural_measure_starts
function gv_score_plan_prebuild_single_tune(_planned_events) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;

    var _is_set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    if (_is_set_mode) return false;

    var _single_tune_loop_runtime = variable_global_exists("loop_runtime_active")
        && bool(global.loop_runtime_active);
    if (_single_tune_loop_runtime) return false;

    var _events = is_array(_planned_events) ? _planned_events : [];
    if (array_length(_events) <= 0) {
        _events = gv_get_planned_events_for_viz();
    }
    if (!is_array(_events) || array_length(_events) <= 0) return false;

    var _selected_tune_channel = gv_get_target_tune_channel();
    var _selected_playable_measure_count = gv_count_selected_channel_score_measures(_events);

    var _skip_met = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var _met_ch = _skip_met ? real(global.METRONOME_CONFIG.channel) : -999;

    var _measure_starts = [];
    var _ne = array_length(_events);
    var _has_marker_timing = false;
    for (var _mi_probe = 0; _mi_probe < _ne; _mi_probe++) {
        var _probe = _events[_mi_probe];
        if (!is_struct(_probe)) continue;
        if (string(_probe[$ "type"] ?? "") != "marker") continue;
        var _probe_mt = string(_probe[$ "marker_type"] ?? "");
        var _probe_beat = floor(real(_probe[$ "beat"] ?? 0));
        var _probe_frac = real(_probe[$ "beat_fraction"] ?? 0);
        if (_probe_mt == "bar" || (_probe_mt == "beat" && _probe_beat == 1 && abs(_probe_frac) <= 0.001)) {
            _has_marker_timing = true;
            break;
        }
    }

    var _allow_note_fallback_single = !_has_marker_timing;
    var _last_key = "";
    var _seq = 0;
    for (var _i = 0; _i < _ne; _i++) {
        var _ev = _events[_i];
        if (!is_struct(_ev)) continue;
        var _etype = variable_struct_exists(_ev, "type") ? string(_ev.type) : "";

        var _is_measure_start = false;
        if (_etype == "marker") {
            var _marker_type = string(_ev[$ "marker_type"] ?? "");
            var _marker_beat = floor(real(_ev[$ "beat"] ?? 0));
            var _marker_frac = real(_ev[$ "beat_fraction"] ?? 0);
            _is_measure_start = (_marker_type == "bar") || (_marker_type == "beat" && _marker_beat == 1 && abs(_marker_frac) <= 0.001);
        }
        if (!_is_measure_start && _allow_note_fallback_single && _etype == "note_on") _is_measure_start = true;
        if (!_is_measure_start) continue;

        var _et = gv_evt_time_ms(_ev);
        var _em = variable_struct_exists(_ev, "measure") ? floor(real(_ev.measure)) : -999;
        if (_em <= 0) continue;

        if (_skip_met && _etype == "note_on") {
            var _ch = variable_struct_exists(_ev, "channel") ? real(_ev.channel) : 0;
            if (_ch == _met_ch) continue;
        }

        var _part = variable_struct_exists(_ev, "part") ? floor(real(_ev.part)) : 1;
        var _beat = variable_struct_exists(_ev, "beat") ? floor(real(_ev.beat)) : 0;
        var _key = string(_em);
        if (_key == _last_key) continue;
        _last_key = _key;

        array_push(_measure_starts, {
            m: _em,
            p: _part,
            b: _beat,
            t: _et,
            seq: _seq,
            seg_idx: -1,
            seg_title: "",
            seg_start_ms: -1,
            seg_end_ms: -1
        });
        _seq += 1;
    }

    var _nm = array_length(_measure_starts);
    if (_nm <= 0) return false;

    var _fallback_measure_ms = 1000;
    if (_nm >= 2) {
        _fallback_measure_ms = max(1,
            real(variable_struct_get(_measure_starts[_nm - 1], "t"))
            - real(variable_struct_get(_measure_starts[_nm - 2], "t")));
    }

    var _structural_durations = (variable_global_exists("score_snippet_durations")
        && is_array(global.score_snippet_durations)) ? global.score_snippet_durations : [];
    var _structural_duration_count = array_length(_structural_durations);
    var _target_map_count = (variable_global_exists("score_playback_map")
        && is_array(global.score_playback_map)) ? array_length(global.score_playback_map) : 0;

    if (_structural_duration_count > 0 && _nm > 0) {
        var _units_per_measure = variable_global_exists("score_units_per_measure")
            ? real(global.score_units_per_measure)
            : 0;
        var _marker_measure_ms = max(1, real(variable_struct_get(_measure_starts[0], "t")));
        if (_nm >= 2) {
            _marker_measure_ms = max(1,
                real(variable_struct_get(_measure_starts[1], "t"))
                - real(variable_struct_get(_measure_starts[0], "t")));
        }
        var _ms_per_unit = _units_per_measure > 0 ? (_marker_measure_ms / _units_per_measure) : 1;

        var _first_is_pickup = variable_global_exists("score_has_pickup") && global.score_has_pickup;
        var _structural_cap_count = _structural_duration_count;
        if (_selected_playable_measure_count > 0) {
            var _cap_with_pickup = _selected_playable_measure_count + (_first_is_pickup ? 1 : 0);
            _structural_cap_count = min(_structural_duration_count, _cap_with_pickup);
        }

        var _structural_measure_starts = [];
        var _observed_first_measure_raw = floor(real(variable_struct_get(_measure_starts[0], "m")));
        var _observed_first_measure = _observed_first_measure_raw;
        if (_observed_first_measure < 1) _observed_first_measure = 1;
        var _structural_t = real(variable_struct_get(_measure_starts[0], "t"));
        var _missing_lead_count = _observed_first_measure - 1;
        if (_missing_lead_count > 0) {
            var _lead_back_ms = 0;
            var _lead_limit = min(_missing_lead_count, _structural_cap_count);
            for (var _lead_i = 0; _lead_i < _lead_limit; _lead_i++) {
                _lead_back_ms += max(1, real(_structural_durations[_lead_i]) * _ms_per_unit);
            }
            _structural_t -= _lead_back_ms;
        }
        if (_first_is_pickup && _observed_first_measure_raw >= 1) {
            _structural_t -= max(1, real(_structural_durations[0]) * _ms_per_unit);
        }

        var _next_measure_num = 1;
        for (var _sd_i = 0; _sd_i < _structural_cap_count; _sd_i++) {
            var _duration_units = real(_structural_durations[_sd_i]);
            var _is_pickup_snippet = (_sd_i == 0)
                && (_units_per_measure > 0)
                && (_duration_units < (_units_per_measure - 0.02));
            var _structural_m = _next_measure_num;
            if (_is_pickup_snippet) {
                _structural_m = (_sd_i <= 0) ? 0 : max(1, _next_measure_num - 1);
            }

            array_push(_structural_measure_starts, {
                m: _structural_m,
                p: 1,
                b: 1,
                t: _structural_t,
                seq: _sd_i,
                seg_idx: -1,
                seg_title: "",
                seg_start_ms: -1,
                seg_end_ms: -1
            });

            var _duration_ms = max(1, _duration_units * _ms_per_unit);
            _structural_t += _duration_ms;
            if (!_is_pickup_snippet) {
                _next_measure_num += 1;
            }
        }

        _measure_starts = _structural_measure_starts;
        _nm = array_length(_measure_starts);
        if (_nm >= 2) {
            _fallback_measure_ms = max(1,
                real(variable_struct_get(_measure_starts[_nm - 1], "t"))
                - real(variable_struct_get(_measure_starts[_nm - 2], "t")));
        }
        global.timeline_state.structural_measure_starts = _measure_starts;
    } else {
        global.timeline_state.structural_measure_starts = [];
    }

    if (_structural_duration_count <= 0 && _target_map_count > 0 && _nm > 0) {
        while (_nm > _target_map_count) {
            var _drop_idx = -1;
            for (var _gi = 1; _gi < _nm; _gi++) {
                var _m_prev = floor(real(variable_struct_get(_measure_starts[_gi - 1], "m")));
                var _m_cur = floor(real(variable_struct_get(_measure_starts[_gi], "m")));
                if (_m_cur == _m_prev) {
                    _drop_idx = _gi;
                    break;
                }
            }
            if (_drop_idx < 0) {
                var _min_gap = 1000000000;
                for (var _gg = 1; _gg < _nm; _gg++) {
                    var _gap = real(variable_struct_get(_measure_starts[_gg], "t"))
                        - real(variable_struct_get(_measure_starts[_gg - 1], "t"));
                    if (_gap < _min_gap) {
                        _min_gap = _gap;
                        _drop_idx = _gg;
                    }
                }
            }
            if (_drop_idx < 0) break;
            var _compact = [];
            for (var _ki = 0; _ki < _nm; _ki++) {
                if (_ki == _drop_idx) continue;
                array_push(_compact, _measure_starts[_ki]);
            }
            _measure_starts = _compact;
            _nm = array_length(_measure_starts);
        }

        while (_nm < _target_map_count) {
            var _last = _measure_starts[_nm - 1];
            var _last_t = real(variable_struct_get(_last, "t"));
            var _last_m = floor(real(variable_struct_get(_last, "m")));
            array_push(_measure_starts, {
                m: _last_m + 1,
                p: floor(real(variable_struct_get(_last, "p"))),
                b: 1,
                t: _last_t + _fallback_measure_ms,
                seq: _nm,
                seg_idx: floor(real(variable_struct_get(_last, "seg_idx"))),
                seg_title: string(variable_struct_get(_last, "seg_title")),
                seg_start_ms: real(variable_struct_get(_last, "seg_start_ms")),
                seg_end_ms: real(variable_struct_get(_last, "seg_end_ms"))
            });
            _nm = array_length(_measure_starts);
        }
    }

    if (_nm <= 0) return false;
    for (var _ri = 0; _ri < _nm; _ri++) {
        variable_struct_set(_measure_starts[_ri], "seq", _ri);
    }

    var _zoom_preset_idx = (variable_global_exists("timeline_cfg")
        && is_struct(global.timeline_cfg)
        && variable_struct_exists(global.timeline_cfg, "notebeam_zoom_preset_index"))
        ? floor(real(global.timeline_cfg.notebeam_zoom_preset_index))
        : -1;
    var _ms_ahead = real(global.timeline_state[$ "ms_ahead"] ?? 0);
    var _ms_behind = real(global.timeline_state[$ "ms_behind"] ?? 0);
    var _score_cache_event_count = array_length(_events);
    var _score_cache_pbmap_count = (variable_global_exists("score_playback_map") && is_array(global.score_playback_map))
        ? array_length(global.score_playback_map)
        : 0;
    var _score_cache_dur_count = (variable_global_exists("score_snippet_durations") && is_array(global.score_snippet_durations))
        ? array_length(global.score_snippet_durations)
        : 0;
    var _score_cache_has_pickup = variable_global_exists("score_has_pickup") && bool(global.score_has_pickup);
    var _score_layout_cache_key = string(_zoom_preset_idx)
        + "|" + string_format(_ms_ahead, 0, 3)
        + "|" + string_format(_ms_behind, 0, 3)
        + "|ch=" + string(_selected_tune_channel)
        + "|selm=" + string(_selected_playable_measure_count)
        + "|" + string(_score_cache_event_count)
        + "|" + string(_score_cache_pbmap_count)
        + "|" + string(_score_cache_dur_count)
        + "|" + string(_score_cache_has_pickup)
        + "|" + string(floor(gv_get_planned_end_ms()));

    global.timeline_state.score_lane_layout_cache_single = {
        key: _score_layout_cache_key,
        measure_starts: _measure_starts,
        fallback_measure_ms: _fallback_measure_ms,
        structural_measure_starts: variable_struct_exists(global.timeline_state, "structural_measure_starts")
            ? global.timeline_state.structural_measure_starts
            : []
    };

    global.timeline_state.score_render_plan = {
        version: 1,
        valid: true,
        status: "ready",
        reason: "bind_prebuild",
        mode: "tune",
        built_for_loop: false,
        target_tune_channel: _selected_tune_channel,
        selected_channel_measure_count: _selected_playable_measure_count,
        source_event_count: array_length(_events),
        built_at_ms: timing_get_engine_now_ms(),
        fallback_measure_ms: _fallback_measure_ms,
        seg_raw_measure_counts: [],
        items: _measure_starts
    };
    global.timeline_state.score_render_plan_needs_rebuild = false;
    global.timeline_state.score_render_plan_pending_reason = "";

    if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
        && is_struct(global.timeline_state.score_render_plan_stats)) {
        global.timeline_state.score_render_plan_stats.builds += 1;
        global.timeline_state.score_render_plan_stats.last_reason = "bind_prebuild";
    }

    return true;
}

// Replace your existing function with this version.
/// @function gv_bind_timeline_on_tune_start(_planned_events, _bpm, _meter_text)
/// @description Fully initialise global.timeline_state for a new playback run: store planned events/spans, build measure nav, reset all review/scoring/loop/player-history state, precompute now-line pulse cues, and invalidate surface caches.
/// @param {array}  _planned_events  Flat array of planned MIDI event structs.
/// @param {real}   _bpm             Quarter-note BPM for this tune.
/// @param {string} _meter_text      Time signature string (e.g. "6/8").
/// @reads  global.timeline_cfg
/// @writes global.timeline_state (all sub-fields), global.timeline_cfg.notebeam_view_offset_*
function gv_bind_timeline_on_tune_start(_planned_events, _bpm, _meter_text) {
    if (!is_array(_planned_events)) _planned_events = [];

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        global.timeline_state = {};
    }

    var _ahead_measures = 2;
    var _behind_measures = 1;

    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        if (variable_struct_exists(global.timeline_cfg, "measures_ahead")) {
            _ahead_measures = max(0, real(global.timeline_cfg.measures_ahead));
        }
        if (variable_struct_exists(global.timeline_cfg, "measures_behind")) {
            _behind_measures = max(0, real(global.timeline_cfg.measures_behind));
        }
    }

    var _m = gv_parse_meter(_meter_text);
    var _meter_num = _m[0];
    var _meter_den = _m[1];

    var _bpm_safe = max(1, real(_bpm));
    var _measure_ms = gv_measure_ms(_bpm_safe, _meter_num, _meter_den);

    global.timeline_state.active = true;
    global.timeline_state.playhead_ms = 0;
    global.timeline_state.current_measure = 1;
    global.timeline_state.bpm = _bpm_safe;
    global.timeline_state.meter_num = _meter_num;
    global.timeline_state.meter_den = _meter_den;
    global.timeline_state.measure_ms = _measure_ms;
    global.timeline_state.ms_ahead = _measure_ms * _ahead_measures;
    global.timeline_state.ms_behind = _measure_ms * _behind_measures;
    global.timeline_state.planned_events = _planned_events;
    global.timeline_state.planned_spans = gv_build_planned_spans(_planned_events);
    global.timeline_state.emb_groups    = gv_build_emb_groups(global.timeline_state.planned_spans);
    global.timeline_state.loop_runtime_cache = { valid: false, measure_starts: [] };
    if (!variable_struct_exists(global.timeline_state, "loop_session")
        || !is_struct(global.timeline_state.loop_session)) {
        global.timeline_state.loop_session = {
            active: false,
            selected_refs: [],
            loop_start_boundary: {},
            loop_end_boundary: {},
            boundary_refinement: {},
            timeline_segments: [],
            start_ms: 0,
            end_ms: 0,
            pass_duration_ms: 0,
            passes_total: 0,
            passes_completed: 0,
            spacer_enabled: false,
            spacer_duration_ms: 0,
            jump_enabled: false,
            phase: "complete",
            current_pass_index: 0,
            phase_start_ms: 0,
            phase_end_ms: 0,
            pickup_mode: "none",
            degraded: false
        };
    }

    // Apply active zoom mode (time vs measures) immediately at bind/start.
    // Without this, startup can briefly inherit measure-derived window sizing.
    gv_notebeam_sync_window_from_cfg();

    var _bind_set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _bind_single_loop_runtime = !_bind_set_mode
        && variable_global_exists("loop_runtime_active")
        && bool(global.loop_runtime_active);
    if (!_bind_single_loop_runtime) {
        var _ls_reset = global.timeline_state.loop_session;
        _ls_reset.active = false;
        _ls_reset.phase = "complete";
        _ls_reset.current_pass_index = 0;
        _ls_reset.passes_completed = 0;
        _ls_reset.phase_start_ms = 0;
        _ls_reset.phase_end_ms = 0;
        _ls_reset.loop_start_boundary = {};
        _ls_reset.loop_end_boundary = {};
        _ls_reset.boundary_refinement = {};
        _ls_reset.timeline_segments = [];
        global.timeline_state.loop_session = _ls_reset;
    }
    if (_bind_single_loop_runtime) {
        var _loop_cache = gv_build_loop_runtime_cache(_planned_events);
        global.timeline_state.loop_runtime_cache = _loop_cache;
        if (is_struct(_loop_cache)
            && bool(_loop_cache[$ "valid"] ?? false)
            && is_array(_loop_cache[$ "measure_starts"])
            && array_length(_loop_cache[$ "measure_starts"]) > 0) {
            global.timeline_state.structural_measure_starts = _loop_cache[$ "measure_starts"];
        }
    }

    // Force beat-lane marker cache rebuild for the new run.
    global.timeline_beat_positions = [];
    global.timeline_beat_positions_event_count = -1;
    global.timeline_beat_positions_signature = "";

    var _measure_nav = gv_build_measure_nav_map(_planned_events);
    gv_measure_nav_apply_to_timeline_state(_measure_nav);
    global.timeline_state.measure_nav_scroll_row = 0;
    global.timeline_state.measure_nav_total_rows = 0;
    global.timeline_state.measure_nav_view_rows = 0;
    global.timeline_state.measure_nav_tile_hitboxes = [];
    global.timeline_state.measure_nav_controls = {};
    if (!variable_struct_exists(global.timeline_state, "loop_selected_measures")
        || !is_struct(global.timeline_state.loop_selected_measures)) {
        global.timeline_state.loop_selected_measures = {};
    }
    if (!variable_struct_exists(global.timeline_state, "loop_blank_measure")) {
        global.timeline_state.loop_blank_measure = false;
    }
    if (!variable_struct_exists(global.timeline_state, "loop_boundary_refinement")
        || !is_struct(global.timeline_state.loop_boundary_refinement)) {
        global.timeline_state.loop_boundary_refinement = {
            enabled: false,
            start_part: 1,
            start_measure: -1,
            start_beat: 1,
            start_beat_fraction: 0,
            end_part: 1,
            end_measure: -1,
            end_beat: 1,
            end_beat_fraction: 0
        };
    }
    global.timeline_state.loop_last_selected_measure = -1;
    global.timeline_state.loop_last_selected_part = 1;
    global.timeline_state.loop_last_selected_key = "";
    global.timeline_state.loop_last_selected_nav_idx = -1;
    global.timeline_state.loop_drag = {
        active: false,
        start_measure: -1,
        current_measure: -1,
        additive: false,
        preview_base: {}
    };
    global.timeline_state.loop_session_runs = [];

    global.timeline_state.tune_played = [];
    global.timeline_state.player_in = [];
    global.timeline_state.pending_tune = {};
    global.timeline_state.pending_player = {};
    // Two-buffer model: full-trace for complete post-play review, realtime buffer for fast draw
    global.timeline_state.review_full_trace = [];

    global.timeline_state.planned_i0 = 0;
    global.timeline_state.planned_i1 = -1;
    global.timeline_state.planned_span_i0 = 0;
    global.timeline_state.planned_span_i1 = -1;
    // Explicit window cursors for scalable active-window rendering.
    global.timeline_state.planned_window_i0 = 0;
    global.timeline_state.planned_window_i1 = -1;
    global.timeline_state.player_window_i0 = 0;
    global.timeline_state.player_window_i1 = -1;
    global.timeline_state.player_prune_cursor = 0;
    global.timeline_state.player_prune_last_compact_ms = timing_get_engine_now_ms();
    global.timeline_state.maintenance_tick_count = 0;
    global.timeline_state.start_clock_ms = current_time;
    global.timeline_state.anchor_id = noone;

    var _end_ms = 0;
    var _planned_count = array_length(_planned_events);
    var _planned_idx = 0;
    repeat (_planned_count) {
        var _ev = _planned_events[_planned_idx];
        if (is_struct(_ev)) {
            _end_ms = max(_end_ms, gv_evt_time_ms(_ev));
        }
        _planned_idx += 1;
    }

    global.timeline_state.playback_complete = false;
    global.timeline_state.review_mode = false;
    global.timeline_state.review_end_ms = _end_ms;
    global.timeline_state.last_dispatched_expected_ms = 0;
    global.timeline_state.review_measure_offset = 0;
    global.timeline_state.review_buttons = [];
    global.timeline_state.review_history_runs = [];
    global.timeline_state.review_history_loaded = false;
    global.timeline_state.review_history_count = 0;
    global.timeline_state.notebeam_player_hitboxes = [];
    global.timeline_state.notebeam_note_popup = { visible: false };
    var _default_judge = (variable_global_exists("judge_settings_store")
        && is_struct(global.judge_settings_store)
        && variable_struct_exists(global.judge_settings_store, "selected_judge_id"))
        ? string(global.judge_settings_store.selected_judge_id)
        : "ms_overlap";
    if (_default_judge == "") _default_judge = "ms_overlap";
    global.timeline_state.score_selected_judge = _default_judge;
    global.timeline_state.score_measure_maps_by_key = {};
    global.timeline_state.score_popup_measure = -1;
    global.timeline_state.score_popup_measure_key = "";
    global.timeline_state.score_popup_nav_idx = -1;
    global.timeline_state.score_judge_row_hitboxes = [];
    global.timeline_state.score_detail_popup = { visible: false };
    global.timeline_state.perf_summary_popup = { visible: false };

    // Precompute planned note-on cue times for a lightweight now-line pulse effect.
    var _pulse_cues = [];
    var _pulse_spans = global.timeline_state.planned_spans;
    if (is_array(_pulse_spans)) {
        var _pulse_n = array_length(_pulse_spans);
        for (var _pi = 0; _pi < _pulse_n; _pi++) {
            var _ps = _pulse_spans[_pi];
            if (!is_struct(_ps)) continue;
            var _lane_idx = floor(real(_ps.lane_idx ?? -1));
            if (_lane_idx < 0 || _lane_idx > 8) continue;
            array_push(_pulse_cues, {
                start_ms: real(_ps.start_ms ?? 0),
                lane_idx: _lane_idx,
                is_embellishment: variable_struct_exists(_ps, "is_embellishment") && _ps.is_embellishment
            });
        }
    }
    global.timeline_state.nowline_planned_pulse_cues = _pulse_cues;
    global.timeline_state.nowline_planned_pulse_i = 0;
    global.timeline_state.score_lane_layout_cache_single = {};
    global.timeline_state.score_render_plan = {
        version: 1,
        valid: false,
        status: "pending",
        reason: "bind_tune_start",
        mode: _bind_set_mode ? "set" : "tune",
        built_for_loop: _bind_single_loop_runtime,
        source_event_count: array_length(_planned_events),
        built_at_ms: timing_get_engine_now_ms(),
        items: []
    };
    global.timeline_state.score_render_plan_stats = {
        hits: 0,
        misses: 0,
        builds: 0,
        invalidations: 0,
        last_log_ms: 0,
        last_reason: "bind_tune_start"
    };
    global.timeline_state.score_render_plan_needs_rebuild = true;
    global.timeline_state.score_render_plan_pending_reason = "bind_tune_start";
    if (!_bind_set_mode && !_bind_single_loop_runtime) {
        gv_score_plan_prebuild_single_tune(_planned_events);
    }

    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_target_ms", 0);
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_ms", 0);
    }
    gv_invalidate_notebeam_underlay_surface_cache();
    gv_invalidate_notebeam_live_player_surface_cache();
    gv_invalidate_player_surface_cache();
}


/// @function gv_resolve_loaded_tune_timing()
/// @description Resolve BPM and meter from the best available tune metadata source (selected_tune, tune_meta, or global.tune).
/// @returns {struct}  Struct with fields: bpm, meter.
/// @reads  global.selected_tune, global.tune_meta, global.tune
function gv_resolve_loaded_tune_timing() {
    var _bpm = 120;
    var _meter = "4/4";
    var _src = undefined;

    // Preferred source: loaded/selected tune metadata
    if (variable_global_exists("selected_tune") && is_struct(global.selected_tune)) {
        _src = global.selected_tune;
    } else if (variable_global_exists("tune_meta") && is_struct(global.tune_meta)) {
        _src = global.tune_meta;
    } else if (variable_global_exists("tune") && is_struct(global.tune)) {
        _src = global.tune;
    }

    if (is_struct(_src)) {
        if (variable_struct_exists(_src, "bpm")) {
            _bpm = real(_src.bpm);
        } else if (variable_struct_exists(_src, "tempo")) {
            _bpm = real(_src.tempo);
        }

        if (variable_struct_exists(_src, "meter")) {
            _meter = string(_src.meter);
        } else if (variable_struct_exists(_src, "time_signature")) {
            _meter = string(_src.time_signature);
        }
    }

    _bpm = max(1, _bpm);
    if (string_pos("/", _meter) <= 0) _meter = "4/4";

    return { bpm: _bpm, meter: _meter };
}



/// @function gv_get_planned_events_for_viz()
/// @description Return the best available planned-events array: prefers playback_events_active, then playback_events, then tune.settings/events, then tune_settings.
/// @returns {array}  Planned event structs, or [] if none found.
/// @reads  global.playback_events_active, global.playback_events, global.tune, global.tune_settings
function gv_get_planned_events_for_viz() {
    if (variable_global_exists("playback_events_active")
        && is_array(global.playback_events_active)
        && array_length(global.playback_events_active) > 0) {
        return global.playback_events_active;
    }

    // Priority 1 (canonical at play time): preprocessed playback stream
    if (variable_global_exists("playback_events")
        && is_array(global.playback_events)
        && array_length(global.playback_events) > 0) {
        return global.playback_events;
    }

    // Compatibility fallback chain (old loaders / editor states):
    // 1) tune.settings, 2) tune.events, 3) tune_settings.
    // Keep ordering stable so data source selection stays deterministic.
    if (variable_global_exists("tune") && is_struct(global.tune)) {
        if (variable_struct_exists(global.tune, "settings") && is_array(global.tune.settings)) {
            return global.tune.settings;
        }
        if (variable_struct_exists(global.tune, "events") && is_array(global.tune.events)) {
            return global.tune.events;
        }
    }

    if (variable_global_exists("tune_settings") && is_array(global.tune_settings)) {
        return global.tune_settings;
    }

    return [];
}



/// @function gv_bind_from_loaded_tune()
/// @description Convenience wrapper: resolves planned events and timing from the loaded tune globals and calls gv_bind_timeline_on_tune_start.
/// @reads  global.playback_events, global.tune, global.tune_settings, global.selected_tune, global.tune_meta (via helpers)
function gv_bind_from_loaded_tune() {
    var _events = gv_get_planned_events_for_viz();
    var _timing = gv_resolve_loaded_tune_timing();
    gv_bind_timeline_on_tune_start(_events, _timing.bpm, _timing.meter);
}

/// @function gv_find_anchor_id_by_name(_ui_name)
/// @description Find the first obj_field_base instance whose ui_name matches the given string. Includes a compatibility fallback for label-anchor instances identified by field_contents.
/// @param {string} _ui_name  Anchor name to search for.
/// @returns {id}  Instance ID or noone.
/// @objects obj_field_base
function gv_find_anchor_id_by_name(_ui_name) {
    var target = string(_ui_name ?? "");
    if (string_length(target) <= 0) return noone;

    var count = instance_number(obj_field_base);
    for (var i = 0; i < count; i++) {
        var inst = instance_find(obj_field_base, i);
        if (!instance_exists(inst)) continue;
        if (!variable_instance_exists(inst, "ui_name")) continue;
        if (string(inst.ui_name) == target) {
            return inst;
        }
    }

    // Compatibility path for label anchors when RoomUI instances were not
    // assigned explicit ui_name overrides.
    // Expected anchor keys are label_a_anchor..label_G_anchor and field_contents carries the note key.
    var tlen = string_length(target);
    var is_label_anchor = (tlen > 13)
        && (string_copy(target, 1, 6) == "label_")
        && (string_copy(target, tlen - 6, 7) == "_anchor");
    if (is_label_anchor) {
        var note_key = string_copy(target, 7, tlen - 13);
        if (string_length(note_key) > 0) {
            for (var j = 0; j < count; j++) {
                var inst2 = instance_find(obj_field_base, j);
                if (!instance_exists(inst2)) continue;

                // Room instances inherit ui_name="n/a" by default; treat that as unnamed here.
                var ui_name2 = "";
                if (variable_instance_exists(inst2, "ui_name")) {
                    ui_name2 = string_lower(string_trim(string(inst2.ui_name)));
                }
                var ui_name2_is_unset = (ui_name2 == "" || ui_name2 == "n/a" || ui_name2 == "na" || ui_name2 == "none" || ui_name2 == "null");
                if (!ui_name2_is_unset) continue;
                if (!variable_instance_exists(inst2, "field_contents")) continue;
                if (string(inst2.field_contents) != note_key) continue;

                return inst2;
            }
        }
    }

    return noone;
}

/// @function gv_find_timeline_anchor_id()
/// @description Return the instance ID of the "timeline_canvas_anchor" field instance.
/// @returns {id}  Instance ID or noone.
/// @objects obj_field_base (via gv_find_anchor_id_by_name)
function gv_find_timeline_anchor_id() {
    return gv_find_anchor_id_by_name("timeline_canvas_anchor");
}

/// @function gv_get_anchor_rect_by_name(_ui_name)
/// @description Return the world-space bounding rect of a named anchor instance as a struct, optionally offset by global.GV_ANCHOR_RECT_X_OFFSET/Y_OFFSET for surface-local rendering.
/// @param {string} _ui_name  Anchor name.
/// @returns {struct|undefined}  Struct with x1, y1, x2, y2, w, h; or undefined if anchor not found.
/// @reads  global.GV_ANCHOR_RECT_X_OFFSET, global.GV_ANCHOR_RECT_Y_OFFSET
/// @objects obj_field_base (via gv_find_anchor_id_by_name)
function gv_get_anchor_rect_by_name(_ui_name) {
    var anchor_id = gv_find_anchor_id_by_name(_ui_name);
    if (!instance_exists(anchor_id)) return undefined;

    var x1 = anchor_id.bbox_left;
    var y1 = anchor_id.bbox_top;
    var x2 = anchor_id.bbox_right;
    var y2 = anchor_id.bbox_bottom;

    // Fall back to sprite+scale when bbox has collapsed (e.g. fully-transparent sprite
    // with automatic bbox mode produces a near-zero bounding box in world space).
    if ((x2 <= x1 || y2 <= y1 || (x2 - x1) < 4 || (y2 - y1) < 4) && anchor_id.sprite_index != noone) {
        var sw = sprite_get_width(anchor_id.sprite_index) * abs(anchor_id.image_xscale);
        var sh = sprite_get_height(anchor_id.sprite_index) * abs(anchor_id.image_yscale);
        var ox = sprite_get_xoffset(anchor_id.sprite_index) * abs(anchor_id.image_xscale);
        var oy = sprite_get_yoffset(anchor_id.sprite_index) * abs(anchor_id.image_yscale);
        x1 = anchor_id.x - ox;
        y1 = anchor_id.y - oy;
        x2 = x1 + sw;
        y2 = y1 + sh;
    }

    // When rendering into a surface, a caller may set GV_ANCHOR_RECT_OFFSET to translate
    // room-space coordinates into surface-local space.
    var _xo = variable_global_exists("GV_ANCHOR_RECT_X_OFFSET") ? real(global.GV_ANCHOR_RECT_X_OFFSET) : 0;
    var _yo = variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET") ? real(global.GV_ANCHOR_RECT_Y_OFFSET) : 0;
    return {
        x1: x1 + _xo,
        y1: y1 + _yo,
        x2: x2 + _xo,
        y2: y2 + _yo,
        w: max(1, x2 - x1),
        h: max(1, y2 - y1)
    };
}

/// @description Draw the notebeam "now" position marker (yellow vertical line) in GUI space.
/// Called exclusively from obj_game_viz Draw GUI (Draw_64) so it renders above all world-space
/// content regardless of depth ordering.
///
/// @function gv_draw_notebeam_nowline_overlay_gui()
/// @description Draw the notebeam "now" line overlay in GUI space: a vertical marker and optional pulsed lane highlights. Reads all parameters from global.timeline_cfg and global.timeline_state.
/// @reads  global.NOTEBEAM_OVERLAY_NOWLINE_ENABLED, global.timeline_cfg.*, global.timeline_state.nowline_planned_pulse_cues, global.timeline_state.ms_behind, global.timeline_state.ms_ahead
/// @writes global.timeline_state.nowline_planned_pulse_i, global.NOTEBEAM_DIAG_NOWLINE_PULSE_MS
function gv_draw_notebeam_nowline_overlay_gui() {
    // -- Guard checks --
    if (!variable_global_exists("NOTEBEAM_OVERLAY_NOWLINE_ENABLED") || !global.NOTEBEAM_OVERLAY_NOWLINE_ENABLED) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;

    var show_now_line = !variable_struct_exists(global.timeline_cfg, "notebeam_show_now_line")
        || global.timeline_cfg.notebeam_show_now_line;
    if (!show_now_line) return;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    var rect = gv_get_anchor_rect_by_name("notebeam_canvas_anchor");
    if (!is_struct(rect)) return;

    // -- Compute X position --
    // Prefer notebeam_now_ratio; fall back to shared now_ratio.
    var base_now_ratio = variable_struct_exists(global.timeline_cfg, "now_ratio")
        ? real(global.timeline_cfg.now_ratio)
        : 0.33;
    var beam_now_ratio = variable_struct_exists(global.timeline_cfg, "notebeam_now_ratio")
        ? real(global.timeline_cfg.notebeam_now_ratio)
        : -1;
    var now_ratio = (beam_now_ratio >= 0) ? beam_now_ratio : base_now_ratio;
    now_ratio = clamp(now_ratio, 0.0, 1.0);
    var now_offset_px = variable_struct_exists(global.timeline_cfg, "notebeam_now_x_offset_px")
        ? real(global.timeline_cfg.notebeam_now_x_offset_px)
        : 0;

    var gui_x = real(rect.x1) + ((real(rect.x2) - real(rect.x1)) * now_ratio) + now_offset_px;

    // -- Compute Y span from lane anchors --
    // Scan all 9 note-lane anchors to get the exact pixel band the notebeam rows occupy,
    // rather than using the full notebeam panel height.
    var gui_y1 = real(rect.y1); // fallback: full panel
    var gui_y2 = real(rect.y2);
    var lane_count = 9;
    var lane_flip = variable_struct_exists(global.timeline_cfg, "notebeam_lane_flip")
        && global.timeline_cfg.notebeam_lane_flip;
    var lane_min = 1000000000;
    var lane_max = -1000000000;
    for (var li = 0; li < lane_count; li++) {
        var anchor_name = gv_get_notebeam_anchor_name_for_lane(li, lane_flip);
        if (string_length(anchor_name) <= 0) continue;
        var lane_rect = gv_get_anchor_rect_by_name(anchor_name);
        if (!is_struct(lane_rect)) continue;
        var ly1 = real(variable_struct_get(lane_rect, "y1"));
        var ly2 = real(variable_struct_get(lane_rect, "y2"));
        lane_min = min(lane_min, min(ly1, ly2));
        lane_max = max(lane_max, max(ly1, ly2));
    }
    if (lane_max > lane_min) {
        gui_y1 = lane_min;
        gui_y2 = lane_max;
    }

    // -- Draw now-line --
    var now_line_color = variable_struct_exists(global.timeline_cfg, "notebeam_now_line_color")
        ? global.timeline_cfg.notebeam_now_line_color
        : c_yellow;
    var now_line_width = variable_struct_exists(global.timeline_cfg, "notebeam_now_line_width")
        ? max(1, real(global.timeline_cfg.notebeam_now_line_width))
        : 2;

    var diag_pulse_enabled = variable_struct_exists(global.timeline_cfg, "notebeam_diag_enabled")
        && global.timeline_cfg.notebeam_diag_enabled;
    var diag_pulse_start_us = diag_pulse_enabled ? get_timer() : 0;

    var pulse_hits = [];
    var pulse_enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_enabled")
        || global.timeline_cfg.notebeam_nowline_planned_pulse_enabled;
    if (pulse_enabled
        && variable_struct_exists(global.timeline_state, "nowline_planned_pulse_cues")
        && is_array(global.timeline_state.nowline_planned_pulse_cues)
        && variable_struct_exists(global.timeline_state, "playhead_ms")) {
        var _cues = global.timeline_state.nowline_planned_pulse_cues;
        var _n_cues = array_length(_cues);
        if (_n_cues > 0) {
            var _playhead = real(global.timeline_state.playhead_ms);
            var _pre_ms = max(0, real(variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_pre_ms")
                ? global.timeline_cfg.notebeam_nowline_planned_pulse_pre_ms : 28));
            var _post_ms = max(0, real(variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_post_ms")
                ? global.timeline_cfg.notebeam_nowline_planned_pulse_post_ms : 60));
            var _pulse_i = variable_struct_exists(global.timeline_state, "nowline_planned_pulse_i")
                ? floor(real(global.timeline_state.nowline_planned_pulse_i))
                : 0;
            _pulse_i = clamp(_pulse_i, 0, _n_cues);

            while (_pulse_i < _n_cues && _playhead > real(_cues[_pulse_i].start_ms ?? 0) + _post_ms) {
                _pulse_i++;
            }
            while (_pulse_i > 0 && _playhead < real(_cues[_pulse_i - 1].start_ms ?? 0) - _pre_ms) {
                _pulse_i--;
            }
            global.timeline_state.nowline_planned_pulse_i = _pulse_i;

            var _chk_start = max(0, _pulse_i - 2);
            var _chk_end = min(_n_cues - 1, _pulse_i + 2);
            for (var _ci = _chk_start; _ci <= _chk_end; _ci++) {
                var _cue = _cues[_ci];
                if (!is_struct(_cue)) continue;
                var _cue_ms = real(_cue.start_ms ?? 0);
                var _dt = _playhead - _cue_ms;
                var _s = 0;
                if (_dt < 0) {
                    if (_pre_ms > 0 && _dt >= -_pre_ms) _s = 1 - (abs(_dt) / _pre_ms);
                } else {
                    if (_post_ms > 0 && _dt <= _post_ms) _s = 1 - (_dt / _post_ms);
                }
                if (_s > 0) {
                    array_push(pulse_hits, {
                        lane_idx: floor(real(_cue.lane_idx ?? -1)),
                        strength: clamp(_s, 0, 1),
                        is_embellishment: variable_struct_exists(_cue, "is_embellishment") && _cue.is_embellishment
                    });
                }
            }
        }
    }

    draw_set_alpha(1);
    draw_set_color(now_line_color);
    draw_line_width(gui_x, gui_y1, gui_x, gui_y2, now_line_width);

    var pulse_hit_count = array_length(pulse_hits);
    if (pulse_hit_count > 0) {
        var _width_boost = real(variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_width_boost")
            ? global.timeline_cfg.notebeam_nowline_planned_pulse_width_boost : 1.4);
        var _height_pad = real(variable_struct_exists(global.timeline_cfg, "notebeam_nowline_planned_pulse_height_pad_px")
            ? global.timeline_cfg.notebeam_nowline_planned_pulse_height_pad_px : 7);
        var _pulse_color = merge_color(now_line_color, c_white, 0.65);
        for (var _hi = 0; _hi < pulse_hit_count; _hi++) {
            var _hit = pulse_hits[_hi];
            if (!is_struct(_hit)) continue;
            var _lane_idx = floor(real(_hit.lane_idx ?? -1));
            if (_lane_idx < 0 || _lane_idx >= lane_count) continue;
            var _strength = clamp(real(_hit.strength ?? 0), 0, 1);
            var _is_emb = variable_struct_exists(_hit, "is_embellishment") && _hit.is_embellishment;
            if (_strength <= 0) continue;

            var _hit_anchor = gv_get_notebeam_anchor_name_for_lane(_lane_idx, lane_flip);
            if (string_length(_hit_anchor) <= 0) continue;
            var _hit_rect = gv_get_anchor_rect_by_name(_hit_anchor);
            if (!is_struct(_hit_rect)) continue;

            var _hy1 = real(variable_struct_get(_hit_rect, "y1"));
            var _hy2 = real(variable_struct_get(_hit_rect, "y2"));
            var _hmid = (min(_hy1, _hy2) + max(_hy1, _hy2)) * 0.5;
            var _pad = max(0, _height_pad) * _strength;
            var _line_w = now_line_width + 1 + (max(0, _width_boost) * _strength);
            var _cross_half_w = (_is_emb ? 5 : 8) + (6 * _strength);
            var _cross_line_w = 2 + (2 * _strength);
            draw_set_color(_pulse_color);
            draw_set_alpha(0.55 + (0.25 * _strength));
            draw_line_width(gui_x, min(_hy1, _hy2) - _pad, gui_x, max(_hy1, _hy2) + _pad, _line_w);
            draw_set_alpha(0.75 + (0.20 * _strength));
            draw_line_width(gui_x - _cross_half_w, _hmid, gui_x + _cross_half_w, _hmid, _cross_line_w);
        }
        draw_set_color(now_line_color);
        draw_set_alpha(1);
    }
    if (diag_pulse_enabled) {
        var _pulse_ms = (get_timer() - diag_pulse_start_us) * 0.001;
        if (!variable_global_exists("NOTEBEAM_DIAG_NOWLINE_PULSE_MS")) {
            global.NOTEBEAM_DIAG_NOWLINE_PULSE_MS = 0;
        }
        global.NOTEBEAM_DIAG_NOWLINE_PULSE_MS += _pulse_ms;
    }
    draw_set_alpha(1);
}

/// @description Draw note-lane labels in GUI space so they sit above notebeam beams.
/// This mirrors the default obj_field_base label text style (fnt_setting, c_ltgray).
/// @function gv_draw_notebeam_lane_labels_overlay_gui()
/// @description Draw note-lane labels (a, g, f, â€¦G) at their anchor positions in GUI space.
/// @objects obj_field_base (reads ui_name and field_contents via gv_find_anchor_id_by_name)
function gv_draw_notebeam_lane_labels_overlay_gui() {
    var label_names = [
        "label_a_anchor",
        "label_g_anchor",
        "label_f_anchor",
        "label_e_anchor",
        "label_d_anchor",
        "label_c_anchor",
        "label_B_anchor",
        "label_A_anchor",
        "label_G_anchor"
    ];

    draw_set_font(fnt_setting);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_ltgray);

    var n = array_length(label_names);
    for (var i = 0; i < n; i++) {
        var inst = gv_find_anchor_id_by_name(label_names[i]);
        if (inst == noone || !instance_exists(inst)) continue;

        var txt = variable_instance_exists(inst, "field_contents")
            ? string(variable_instance_get(inst, "field_contents"))
            : "";
        if (string_length(txt) <= 0) continue;

        draw_text(inst.x + 10, inst.y, txt);
    }

    draw_set_color(c_white);
}

/// @function gv_get_timeline_anchor_rect()
/// @description Return the bounding rect of the timeline canvas anchor instance, caching the anchor ID in global.timeline_state.anchor_id.
/// @returns {struct|undefined}  Struct with x1, y1, x2, y2, w, h; or undefined if anchor absent.
/// @reads  global.timeline_state.anchor_id
/// @writes global.timeline_state.anchor_id
function gv_get_timeline_anchor_rect() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return undefined;

    var anchor_id = variable_struct_exists(global.timeline_state, "anchor_id") ? global.timeline_state.anchor_id : noone;
    if (!instance_exists(anchor_id)) {
        anchor_id = gv_find_timeline_anchor_id();
        global.timeline_state.anchor_id = anchor_id;
    }
    if (!instance_exists(anchor_id)) return undefined;

    var x1 = anchor_id.bbox_left;
    var y1 = anchor_id.bbox_top;
    var x2 = anchor_id.bbox_right;
    var y2 = anchor_id.bbox_bottom;

    if ((x2 <= x1 || y2 <= y1) && anchor_id.sprite_index != noone) {
        var sw = sprite_get_width(anchor_id.sprite_index) * abs(anchor_id.image_xscale);
        var sh = sprite_get_height(anchor_id.sprite_index) * abs(anchor_id.image_yscale);
        var ox = sprite_get_xoffset(anchor_id.sprite_index) * abs(anchor_id.image_xscale);
        var oy = sprite_get_yoffset(anchor_id.sprite_index) * abs(anchor_id.image_yscale);
        x1 = anchor_id.x - ox;
        y1 = anchor_id.y - oy;
        x2 = x1 + sw;
        y2 = y1 + sh;
    }

    return {
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        w: max(1, x2 - x1),
        h: max(1, y2 - y1)
    };
}

/// @function gv_get_planned_end_ms()
/// @description Return the latest event/span end time from global.timeline_state, also comparing the current playhead_ms.
/// @returns {real}  End time in ms.
/// @reads  global.timeline_state.playhead_ms, global.timeline_state.planned_events, global.timeline_state.planned_spans
function gv_get_planned_end_ms() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return 0;

    var end_ms = real(global.timeline_state.playhead_ms ?? 0);

    if (variable_struct_exists(global.timeline_state, "planned_events") && is_array(global.timeline_state.planned_events)) {
        var events = global.timeline_state.planned_events;
        var n_events = array_length(events);
        for (var i = 0; i < n_events; i++) {
            var e = events[i];
            if (!is_struct(e)) continue;
            end_ms = max(end_ms, gv_evt_time_ms(e));
        }
    }

    if (variable_struct_exists(global.timeline_state, "planned_spans") && is_array(global.timeline_state.planned_spans)) {
        var spans = global.timeline_state.planned_spans;
        var n_spans = array_length(spans);
        for (var j = 0; j < n_spans; j++) {
            var s = spans[j];
            if (!is_struct(s)) continue;
            end_ms = max(end_ms, real(s.end_ms ?? 0));
        }
    }

    return max(0, end_ms);
}

/// @function gv_on_tune_playback_finished(_final_time_ms)
/// @description Mark playback complete, switch to review mode, set review_end_ms, invoke scoring build and timing calibration, and refresh review history cache.
/// @param {real} _final_time_ms  Actual finish time in ms; pass -1 to use planned end.
/// @reads  global.timeline_state.active
/// @writes global.timeline_state.playback_complete, global.timeline_state.review_mode, global.timeline_state.review_end_ms, global.timeline_state.review_measure_offset, global.timeline_state.playhead_ms, global.timeline_cfg.notebeam_view_offset_*
function gv_on_tune_playback_finished(_final_time_ms = -1) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!global.timeline_state.active) return;

    var end_ms = gv_get_planned_end_ms();
    if (_final_time_ms >= 0) {
        end_ms = max(end_ms, real(_final_time_ms));
    }

    global.timeline_state.playback_complete = true;
    global.timeline_state.review_mode = true;
    global.timeline_state.review_end_ms = end_ms;
    global.timeline_state.review_measure_offset = 0;
    global.timeline_state.playhead_ms = end_ms;
    if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_target_ms", 0);
        variable_struct_set(global.timeline_cfg, "notebeam_view_offset_ms", 0);
    }
    gv_refresh_review_history_cache();

    // Build objective ms-overlap score immediately so review visuals can use it
    // before any manual export action is triggered.
    var _scoring_run_idx = asset_get_index("scoring_run_judge_summary");
    var _registry_idx = asset_get_index("scoring_judge_settings_get_registry");
    if (script_exists(_scoring_run_idx)) {
        var _export_info = event_history_get_export_info();
        var _registry = script_exists(_registry_idx) ? script_execute(_registry_idx) : [];
        var _promoted_once = false;

        if (is_array(_registry) && array_length(_registry) > 0) {
            for (var _ri = 0; _ri < array_length(_registry); _ri++) {
                var _jr = _registry[_ri];
                if (!is_struct(_jr)) continue;
                if (!bool(_jr.enabled ?? true)) continue;
                var _jid = string(_jr.id ?? "");
                if (_jid == "") continue;
                script_execute(_scoring_run_idx, _export_info, _jid, !_promoted_once);
                if (!_promoted_once) _promoted_once = true;
            }
        }

        if (!_promoted_once) {
            script_execute(_scoring_run_idx, _export_info, "ms_overlap", true);
        }

        // Respect persisted selected judge when key maps are available.
        if (variable_global_exists("judge_settings_store")
            && is_struct(global.judge_settings_store)
            && variable_struct_exists(global.judge_settings_store, "selected_judge_id")
            && variable_struct_exists(global.timeline_state, "score_measure_maps_by_key")
            && is_struct(global.timeline_state.score_measure_maps_by_key)) {
            var _pref_judge = string(global.judge_settings_store.selected_judge_id);
            if (_pref_judge != "" && variable_struct_exists(global.timeline_state.score_measure_maps_by_key, _pref_judge)) {
                global.timeline_state.score_selected_judge = _pref_judge;
            }
        }
    }

    // If this was a loop session, compute per-iteration scores for the overview panel.
    var _was_loop = variable_global_exists("loop_runtime_active") && global.loop_runtime_active;
    if (_was_loop) {
        var _loop_score_idx = asset_get_index("scoring_build_loop_iteration_scores");
        if (script_exists(_loop_score_idx)) {
            script_execute(_loop_score_idx);
        }
    }

    // Pre-classify all review_full_trace spans against planned_spans once,
    // so the draw loop can use span.review_match_state (0=miss, 1=bleed, 2=match)
    // instead of calling gv_player_span_classify_and_draw() per-span per-frame.
    var _rc_slack = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)
        && variable_struct_exists(global.timeline_cfg, "notebeam_player_timing_slack_ms"))
        ? max(0, real(global.timeline_cfg.notebeam_player_timing_slack_ms)) : 50;
    if (variable_struct_exists(global.timeline_state, "review_full_trace")
        && is_array(global.timeline_state.review_full_trace)
        && variable_struct_exists(global.timeline_state, "planned_spans")
        && is_array(global.timeline_state.planned_spans)) {
        var _rc_spans   = global.timeline_state.review_full_trace;
        var _rc_planned = global.timeline_state.planned_spans;
        var _rc_pn      = array_length(_rc_planned);
        var _rc_n       = array_length(_rc_spans);
        for (var _rci = 0; _rci < _rc_n; _rci++) {
            var _rcs = _rc_spans[_rci];
            if (!is_struct(_rcs)) continue;
            var _rca1  = real(_rcs[$ "start_ms"] ?? 0);
            var _rca2  = real(_rcs[$ "end_ms"]   ?? _rca1);
            var _rclane = real(_rcs[$ "lane_idx"] ?? -999);
            if (_rclane == -999) _rclane = gv_note_to_lane_index(_rcs[$ "note_canonical"] ?? "", _rcs[$ "note_midi"] ?? -1, _rcs[$ "channel"] ?? -1);
            var _rcstate = 0;
            // Binary search: find first planned span whose end could reach _rca1
            var _rp_lo = 0; var _rp_hi = _rc_pn;
            while (_rp_lo < _rp_hi) {
                var _rp_mid = (_rp_lo + _rp_hi) >> 1;
                var _rp_sub = _rc_planned[_rp_mid];
                if (real(_rp_sub[$ "end_ms"] ?? real(_rp_sub[$ "start_ms"] ?? 0)) < _rca1 - _rc_slack) _rp_lo = _rp_mid + 1;
                else _rp_hi = _rp_mid;
            }
            for (var _rpi = _rp_lo; _rpi < _rc_pn; _rpi++) {
                var _rpp = _rc_planned[_rpi];
                if (!is_struct(_rpp)) continue;
                if (!gv_is_tune_focus_channel(real(_rpp[$ "channel"] ?? -999))) continue;
                var _rp_lane = real(_rpp[$ "lane_idx"] ?? -999);
                if (_rp_lane == -999) _rp_lane = gv_note_to_lane_index(_rpp[$ "note_canonical"] ?? "", _rpp[$ "note_midi"] ?? -1, _rpp[$ "channel"] ?? -1);
                if (_rp_lane != _rclane) continue;
                var _rpb1 = min(real(_rpp[$ "start_ms"] ?? 0), real(_rpp[$ "end_ms"] ?? 0));
                var _rpb2 = max(real(_rpp[$ "start_ms"] ?? 0), real(_rpp[$ "end_ms"] ?? 0));
                if (_rpb1 > _rca2 + _rc_slack) break;
                if (_rpb2 <= _rca1 || _rpb1 >= _rca2) continue;
                if (_rcstate < 2) {
                    if ((_rca1 >= _rpb1 - _rc_slack) && (_rca2 <= _rpb2 + _rc_slack)) _rcstate = 2;
                    else _rcstate = max(_rcstate, 1);
                }
            }
            _rcs[$ "review_match_state"] = _rcstate;
        }
    }
}

/// @function map_time_to_context(_time_ms)
/// @description Resolve canonical musical context at a timeline time.
/// Priority: active loop session windows -> measure_nav_entries -> legacy helpers.
/// @param {real} _time_ms Time in ms.
/// @returns {struct} {segment_idx, part, measure, beat, beat_fraction, nav_idx, owner_nav_idx, loop_iteration, phase, measure_ref_key}
/// @reads global.timeline_state, global.playback_context, global.loop_runtime_current_iteration
function map_time_to_context(_time_ms) {
    var t = real(_time_ms);
    var out = {
        segment_idx: -1,
        part: 1,
        measure: -1,
        beat: -1,
        beat_fraction: 0,
        nav_idx: -1,
        owner_nav_idx: -1,
        loop_iteration: variable_global_exists("loop_runtime_current_iteration") ? floor(real(global.loop_runtime_current_iteration)) : 0,
        phase: "none",
        measure_ref_key: ""
    };

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;

    if (variable_global_exists("playback_context") && is_struct(global.playback_context)) {
        var active_seg = floor(real(global.playback_context[$ "active_segment"] ?? -1));
        out.segment_idx = active_seg;
        var segs = global.playback_context[$ "segments"];
        if (is_array(segs) && array_length(segs) > 0) {
            for (var si = 0; si < array_length(segs); si++) {
                var seg = segs[si];
                if (!is_struct(seg)) continue;
                var s0 = real(seg[$ "start_ms"] ?? 0);
                var s1 = real(seg[$ "end_ms"] ?? s0);
                if (t >= s0 && t < s1) {
                    out.segment_idx = si;
                    break;
                }
            }
        }
    }

    var has_loop = variable_struct_exists(global.timeline_state, "loop_session")
        && is_struct(global.timeline_state.loop_session)
        && bool(global.timeline_state.loop_session.active ?? false);
    if (has_loop) {
        var ls = global.timeline_state.loop_session;
        out.phase = string(ls.phase ?? "pass");
        var refs = variable_struct_exists(ls, "selected_refs") && is_array(ls.selected_refs) ? ls.selected_refs : [];
        var segs2 = variable_struct_exists(ls, "timeline_segments") && is_array(ls.timeline_segments) ? ls.timeline_segments : [];

        var hit = undefined;
        for (var i = 0; i < array_length(segs2); i++) {
            var seg2 = segs2[i];
            if (!is_struct(seg2)) continue;
            var ss = real(seg2.start_ms ?? -1);
            var se = real(seg2.end_ms ?? ss);
            if (ss < 0 || se <= ss + 0.001) continue;
            if (t >= ss && t < se) {
                hit = seg2;
                break;
            }
        }

        if (!is_struct(hit)) {
            for (var ri = 0; ri < array_length(refs); ri++) {
                var r = refs[ri];
                if (!is_struct(r)) continue;
                var rs = real(r.start_ms ?? -1);
                var re = real(r.end_ms ?? rs);
                if (rs < 0 || re <= rs + 0.001) continue;
                if (t >= rs && t < re) {
                    hit = r;
                    break;
                }
            }
        }

        if (is_struct(hit)) {
            out.part = max(1, floor(real(variable_struct_exists(hit, "part") ? variable_struct_get(hit, "part") : 1)));
            out.measure = floor(real(variable_struct_exists(hit, "owner_measure")
                ? variable_struct_get(hit, "owner_measure")
                : (variable_struct_exists(hit, "measure") ? variable_struct_get(hit, "measure") : -1)));
            out.nav_idx = floor(real(variable_struct_exists(hit, "nav_idx") ? variable_struct_get(hit, "nav_idx") : -1));
            out.owner_nav_idx = floor(real(variable_struct_exists(hit, "owner_nav_idx") ? variable_struct_get(hit, "owner_nav_idx") : out.nav_idx));
        }
    }

    if (out.measure < 1) {
        var m = gv_measure_at_ms(t);
        if (m >= 1) {
            var ni = gv_measure_nav_find_local_idx(t, m);
            out.measure = m;
            out.nav_idx = ni;
            out.owner_nav_idx = ni;
            if (ni >= 0 && variable_struct_exists(global.timeline_state, "measure_nav_entries") && is_array(global.timeline_state.measure_nav_entries)
                && ni < array_length(global.timeline_state.measure_nav_entries)) {
                var e = global.timeline_state.measure_nav_entries[ni];
                if (is_struct(e)) {
                    out.part = max(1, floor(real(e.part ?? out.part)));
                }
            }
        }
    }

    if (out.measure >= 1) {
        var score_key_fn = asset_get_index("scoring_measure_ref_key");
        if (script_exists(score_key_fn)) {
            out.measure_ref_key = string(script_execute(score_key_fn, out.part, out.measure, out.nav_idx));
            if (out.measure_ref_key == "") {
                out.measure_ref_key = string(script_execute(score_key_fn, out.part, out.measure, -1));
            }
        }
        if (out.measure_ref_key == "") {
            out.measure_ref_key = string(out.part) + ":" + string(out.measure);
        }
    }

    return out;
}

/// @function gv_resolve_measure_context(_time_ms)
/// @description Resolve structural context with mapper-first behavior and legacy measure fallback.
/// @param {real} _time_ms Time in ms.
/// @returns {struct} {measure, part, nav_idx, struct_idx, measure_ref_key, segment_id, ctx}
function gv_resolve_measure_context(_time_ms) {
    var t = real(_time_ms);
    var model_ctx = gv_tune_structure_model_resolve_context_at_time(t);
    var ctx = map_time_to_context(t);

    var measure = model_ctx.found ? floor(real(model_ctx.measure ?? -1)) : floor(real(ctx.measure ?? -1));
    var part = model_ctx.found ? max(1, floor(real(model_ctx.part ?? 1))) : max(1, floor(real(ctx.part ?? 1)));
    var nav_idx = model_ctx.found ? floor(real(model_ctx.nav_idx ?? -1)) : floor(real(ctx.nav_idx ?? -1));
    var struct_idx = model_ctx.found ? floor(real(model_ctx.struct_idx ?? -1)) : -1;
    var measure_ref_key = model_ctx.found ? string(model_ctx.measure_ref_key ?? "") : string(ctx.measure_ref_key ?? "");
    var segment_id = model_ctx.found ? string(model_ctx.segment_id ?? "") : "";

    if (!model_ctx.found) {
        if (measure < 1 && floor(real(ctx.measure ?? -1)) >= 1) {
            measure = floor(real(ctx.measure ?? -1));
        }
        if (nav_idx < 0 && floor(real(ctx.nav_idx ?? -1)) >= 0) {
            nav_idx = floor(real(ctx.nav_idx ?? -1));
        }
        if (measure_ref_key == "") {
            measure_ref_key = string(ctx.measure_ref_key ?? "");
        }
    }

    if (measure < 1) {
        measure = gv_get_current_planned_measure(t);
        if (measure >= 1) {
            if (nav_idx < 0 && variable_global_exists("timeline_state") && is_struct(global.timeline_state)
                && variable_struct_exists(global.timeline_state, "measure_highlight_last_nav_idx")) {
                nav_idx = floor(real(global.timeline_state.measure_highlight_last_nav_idx));
            }
            if (measure_ref_key == "") {
                measure_ref_key = string(part) + ":" + string(measure);
            }
        }
    }

    return {
        measure: measure,
        part: part,
        nav_idx: nav_idx,
        struct_idx: struct_idx,
        measure_ref_key: measure_ref_key,
        segment_id: segment_id,
        ctx: ctx
    };
}

/// @function map_context_to_window(_measure_ref_key)
/// @description Resolve canonical time window for a structural key (part:measure[:nav]).
/// @param {string} _measure_ref_key Canonical key.
/// @returns {struct} {found, part, measure, nav_idx, owner_nav_idx, start_ms, end_ms, timeline_start_ms, timeline_end_ms, owner_start_ms, owner_end_ms, source}
/// @reads global.timeline_state.loop_session, global.timeline_state.measure_nav_entries, global.timeline_state.structural_measure_starts
function map_context_to_window(_measure_ref_key) {
    var out = {
        found: false,
        part: 1,
        measure: -1,
        nav_idx: -1,
        owner_nav_idx: -1,
        start_ms: -1,
        end_ms: -1,
        timeline_start_ms: -1,
        timeline_end_ms: -1,
        owner_start_ms: -1,
        owner_end_ms: -1,
        source: "none"
    };

    var key = string(_measure_ref_key);
    if (key == "") return out;
    var s1 = string_pos(":", key);
    if (s1 <= 0) return out;
    var ptxt = string_copy(key, 1, s1 - 1);
    var rest = string_copy(key, s1 + 1, string_length(key) - s1);
    var s2 = string_pos(":", rest);
    var mtxt = (s2 > 0) ? string_copy(rest, 1, s2 - 1) : rest;
    var ntxt = (s2 > 0) ? string_copy(rest, s2 + 1, string_length(rest) - s2) : "";
    var p = max(1, floor(real(ptxt)));
    var m = floor(real(mtxt));
    var n = (ntxt != "") ? floor(real(ntxt)) : -1;

    out.part = p;
    out.measure = m;
    out.nav_idx = n;

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state) || m < 1) return out;

    if (variable_struct_exists(global.timeline_state, "loop_session")
        && is_struct(global.timeline_state.loop_session)
        && bool(global.timeline_state.loop_session.active ?? false)) {
        var ls = global.timeline_state.loop_session;
        var refs = variable_struct_exists(ls, "selected_refs") && is_array(ls.selected_refs) ? ls.selected_refs : [];
        for (var i = 0; i < array_length(refs); i++) {
            var r = refs[i];
            if (!is_struct(r)) continue;
            var rp = max(1, floor(real(r.part ?? 1)));
            var rm = floor(real(r.measure ?? -1));
            var rn = floor(real(r.nav_idx ?? -1));
            if (rp != p || rm != m) continue;
            if (n >= 0 && rn >= 0 && rn != n) continue;
            out.found = true;
            out.nav_idx = rn;
            out.owner_nav_idx = floor(real(r.owner_nav_idx ?? rn));
            out.start_ms = real(r.start_ms ?? -1);
            out.end_ms = real(r.end_ms ?? out.start_ms);
            out.timeline_start_ms = real(r.timeline_start_ms ?? out.start_ms);
            out.timeline_end_ms = real(r.timeline_end_ms ?? out.end_ms);
            out.owner_start_ms = real(r.owner_start_ms ?? out.start_ms);
            out.owner_end_ms = real(r.owner_end_ms ?? out.end_ms);
            out.source = "loop_session";
            return out;
        }
    }

    var _model_seg = gv_tune_structure_model_find_segment(p, m, n);
    if (is_struct(_model_seg)) {
        out.found = true;
        out.nav_idx = floor(real(_model_seg.source_nav_idx ?? n));
        out.owner_nav_idx = floor(real(_model_seg.owner_nav_idx ?? out.nav_idx));
        out.start_ms = real(_model_seg.start_ms ?? -1);
        out.end_ms = real(_model_seg.end_ms ?? out.start_ms);
        out.timeline_start_ms = real(_model_seg.timeline_start_ms ?? out.start_ms);
        out.timeline_end_ms = real(_model_seg.timeline_end_ms ?? out.end_ms);
        out.owner_start_ms = real(_model_seg.owner_start_ms ?? out.start_ms);
        out.owner_end_ms = real(_model_seg.owner_end_ms ?? out.end_ms);
        out.source = "canonical_model";
        return out;
    }

    if (variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries)) {
        var entries = global.timeline_state.measure_nav_entries;
        for (var ei = 0; ei < array_length(entries); ei++) {
            var e = entries[ei];
            if (!is_struct(e)) continue;
            var ep = max(1, floor(real(e.part ?? 1)));
            var em = floor(real(e.measure ?? -1));
            if (ep != p || em != m) continue;
            if (n >= 0 && ei != n) continue;
            out.found = true;
            out.nav_idx = ei;
            out.owner_nav_idx = ei;
            out.start_ms = real(e.start_ms ?? -1);
            out.end_ms = real(e.end_ms ?? out.start_ms);
            out.timeline_start_ms = out.start_ms;
            out.timeline_end_ms = out.end_ms;
            out.owner_start_ms = out.start_ms;
            out.owner_end_ms = out.end_ms;
            out.source = "measure_nav";
            return out;
        }
    }

    var starts = variable_struct_exists(global.timeline_state, "structural_measure_starts") ? global.timeline_state.structural_measure_starts : [];
    if (is_array(starts) && array_length(starts) > 0) {
        for (var si = 0; si < array_length(starts); si++) {
            var s = starts[si];
            if (!is_struct(s)) continue;
            var sm = floor(real(variable_struct_get(s, "m")));
            if (sm != m) continue;
            var st = real(variable_struct_get(s, "t"));
            var en = st + max(1, real(global.timeline_state.measure_ms ?? 1000));
            if (si + 1 < array_length(starts) && is_struct(starts[si + 1])) {
                en = real(variable_struct_get(starts[si + 1], "t"));
            }
            out.found = true;
            out.start_ms = st;
            out.end_ms = en;
            out.timeline_start_ms = st;
            out.timeline_end_ms = en;
            out.owner_start_ms = st;
            out.owner_end_ms = en;
            out.source = "structural";
            return out;
        }
    }

    return out;
}

/// @function gv_measure_at_ms(_ms)
/// @description Returns the measure number at a given time (ms), using
///              timeline_state.measure_nav_entries. Returns -1 if not found.
/// @param {real} _ms  Time in ms.
/// @returns {real}  Measure number (1-based), or -1 if state absent.
/// @reads  global.timeline_state.measure_nav_entries
function gv_measure_at_ms(_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return -1;
    var entries = variable_struct_exists(global.timeline_state, "measure_nav_entries")
        ? global.timeline_state.measure_nav_entries : [];
    if (!is_array(entries)) return -1;
    var pickup_by_part = (variable_struct_exists(global.timeline_state, "measure_nav_pickup_by_part")
        && is_struct(global.timeline_state.measure_nav_pickup_by_part))
        ? global.timeline_state.measure_nav_pickup_by_part
        : {};
    var n = array_length(entries);
    for (var i = 0; i < n; i++) {
        var e = entries[i];
        if (!is_struct(e)) continue;
        var s = real(e[$ "start_ms"] ?? 0);
        var ed = real(e[$ "end_ms"] ?? 0);
        if (_ms >= s && _ms < ed) return floor(real(e[$ "measure"] ?? -1));
    }
    // If the nav says this part starts with a pickup, preserve the pre-measure state
    // instead of clamping early boundary time to measure 1.
    if (n > 0 && _ms < real(entries[0][$ "start_ms"] ?? 0)) {
        var _first_part = floor(real(entries[0][$ "part"] ?? 1));
        var _first_part_key = string(max(1, _first_part));
        if (variable_struct_exists(pickup_by_part, _first_part_key) && bool(pickup_by_part[$ _first_part_key])) {
            return -1;
        }
        return floor(real(entries[0][$ "measure"] ?? -1));
    }
    // Past end: return last measure.
    if (n > 0) return floor(real(entries[n-1][$ "measure"] ?? -1));
    return -1;
}

/// @function gv_measure_nav_find_local_idx(_ms, _measure_num)
/// @description Resolve a measure-nav index in timeline_state.measure_nav_entries for a given wall-clock time and measure number.
/// @param {real} _ms  Time in ms.
/// @param {real} _measure_num  Target measure number (>= 1).
/// @returns {real}  Local nav index (0-based), or -1 if no matching entry exists.
/// @reads  global.timeline_state.measure_nav_entries
function gv_measure_nav_find_local_idx(_ms, _measure_num) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return -1;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries") || !is_array(global.timeline_state.measure_nav_entries)) return -1;

    var entries = global.timeline_state.measure_nav_entries;
    var target_measure = floor(real(_measure_num));
    var n = array_length(entries);

    // Primary resolution: local time window only (authoritative for panel namespace).
    var active_idx = -1;
    for (var i = 0; i < n; i++) {
        var e = entries[i];
        if (!is_struct(e)) continue;
        var m = floor(real(e[$ "measure"] ?? -1));
        if (m < 1) continue;
        var s = real(e[$ "start_ms"] ?? 0);
        var ed = real(e[$ "end_ms"] ?? s);
        if (_ms >= s && _ms < ed) {
            active_idx = i;
            break;
        }
    }
    if (active_idx >= 0) return active_idx;

    if (target_measure < 1) return -1;

    var first_match_idx = -1;
    var last_match_before_or_at_ms = -1;
    for (var i = 0; i < n; i++) {
        var e = entries[i];
        if (!is_struct(e)) continue;
        var m = floor(real(e[$ "measure"] ?? -1));
        if (m != target_measure) continue;

        if (first_match_idx < 0) first_match_idx = i;

        var s = real(e[$ "start_ms"] ?? 0);
        var ed = real(e[$ "end_ms"] ?? s);
        if (_ms >= s && _ms < ed) return i;
        if (_ms >= s) last_match_before_or_at_ms = i;
    }

    if (last_match_before_or_at_ms >= 0) return last_match_before_or_at_ms;
    return first_match_idx;
}

/// @function gv_sync_now_line_display()
/// @description After any change to playhead_ms, sync all derived display state:
///              canonical score selection identity, active_segment (sets), and gameinfo_title.
///              Segment/measure-nav rebuild happens first so the measure lookup
///              always uses up-to-date entries.
/// @reads  global.timeline_state.playhead_ms, global.playback_context, global.timeline_state.measure_nav_entries
/// @writes global.playback_context.active_segment, global.timeline_state.score_popup_measure_key, global.timeline_state.score_popup_nav_idx, global.timeline_state.score_popup_measure, global.timeline_state.score_selected_judge
function gv_sync_now_line_display() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    var playhead_ms = real(global.timeline_state.playhead_ms ?? 0);

    // Step 1: check for segment change in sets and rebuild measure nav first
    if (variable_global_exists("playback_context") && is_struct(global.playback_context)) {
        var segs = global.playback_context[$ "segments"];
        if (is_array(segs) && array_length(segs) > 1) {
            var n = array_length(segs);
            for (var i = 0; i < n; i++) {
                var seg = segs[i];
                if (!is_struct(seg)) continue;
                var seg_start = real(seg[$ "start_ms"] ?? 0);
                var seg_end   = real(seg[$ "end_ms"] ?? 0);
                if (playhead_ms >= seg_start && playhead_ms < seg_end) {
                    var prev = real(global.playback_context[$ "active_segment"] ?? 0);
                    if (prev != i) {
                        global.playback_context[$ "active_segment"] = i;
                        gv_rebuild_measure_nav_for_segment(i);
                        scr_gameinfo_update_title(i);
                        
                        // Restore score sprites from preloaded segment cache.
                        gv_restore_score_segment_cache(i, true);
                        var _seg_filename = string(seg[$ "filename"] ?? "");
                        if (_seg_filename != "") scr_score_override_groups_load_for_current_segment(_seg_filename);

                        global.timeline_state.score_render_plan_needs_rebuild = true;
                        global.timeline_state.score_render_plan_pending_reason = "segment_change_sync";
                        if (variable_struct_exists(global.timeline_state, "score_render_plan")
                            && is_struct(global.timeline_state.score_render_plan)) {
                            global.timeline_state.score_render_plan.valid = false;
                            global.timeline_state.score_render_plan.status = "pending";
                            global.timeline_state.score_render_plan.reason = "segment_change_sync";
                        }
                        if (variable_struct_exists(global.timeline_state, "score_render_plan_stats")
                            && is_struct(global.timeline_state.score_render_plan_stats)) {
                            global.timeline_state.score_render_plan_stats.invalidations += 1;
                            global.timeline_state.score_render_plan_stats.last_reason = "segment_change_sync";
                        }
                        global.timeline_state.score_lane_layout_cache_single = {};
                    }
                    break;
                }
            }
        }
    }

    // Step 2: sync canonical score selection using (now up-to-date) measure_nav_entries
    var resolved = gv_resolve_measure_context(playhead_ms);
    var m = floor(real(resolved.measure ?? -1));
    if (m >= 1) {
        var sync_part = max(1, floor(real(resolved.part ?? 1)));
        var sync_nav_idx = floor(real(resolved.nav_idx ?? -1));
        var sync_key = string(resolved.measure_ref_key ?? "");
        if (sync_key == "") sync_key = string(sync_part) + ":" + string(m);
        gv_scoring_set_selected_measure_key(sync_key, sync_nav_idx);
        if (!variable_struct_exists(global.timeline_state, "score_selected_judge")) {
            var _default_judge = (variable_global_exists("judge_settings_store")
                && is_struct(global.judge_settings_store)
                && variable_struct_exists(global.judge_settings_store, "selected_judge_id"))
                ? string(global.judge_settings_store.selected_judge_id)
                : "ms_overlap";
            if (_default_judge == "") _default_judge = "ms_overlap";
            global.timeline_state.score_selected_judge = _default_judge;
        }
    } else {
        gv_scoring_set_selected_measure_key("", -1);
    }
}

/// @function gv_review_nudge_measures(_delta_measures)
/// @description Move the review playhead by a number of measures from the end of the tune. Clamps to [0, end_ms].
/// @param {real} _delta_measures  Signed measure offset (negative = backwards).
/// @returns {bool}  true if the position changed.
/// @reads  global.timeline_state.playback_complete, global.timeline_state.measure_ms, global.timeline_state.review_end_ms, global.timeline_state.review_measure_offset
/// @writes global.timeline_state.review_mode, global.timeline_state.review_measure_offset, global.timeline_state.playhead_ms
function gv_review_nudge_measures(_delta_measures) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    var measure_ms = variable_struct_exists(global.timeline_state, "measure_ms")
        ? max(1, real(global.timeline_state.measure_ms))
        : 1000;
    var end_ms = variable_struct_exists(global.timeline_state, "review_end_ms")
        ? max(0, real(global.timeline_state.review_end_ms))
        : gv_get_planned_end_ms();
    var current_offset = variable_struct_exists(global.timeline_state, "review_measure_offset")
        ? real(global.timeline_state.review_measure_offset)
        : 0;

    var new_offset = current_offset + real(_delta_measures);
    var min_offset = -floor(end_ms / measure_ms);
    new_offset = clamp(new_offset, min_offset, 0);

    if (abs(new_offset - current_offset) <= 0.001) return false;

    global.timeline_state.review_mode = true;
    global.timeline_state.review_measure_offset = new_offset;
    global.timeline_state.playhead_ms = clamp(end_ms + (new_offset * measure_ms), 0, end_ms);
    gv_sync_now_line_display();
    return true;
}

// Scans planned_spans (in time order) and groups each consecutive run of
// is_embellishment=true spans plus the immediately following melody note into
// an embellishment window struct used for live player feedback.
/// @function gv_build_emb_groups(_planned_spans)
/// @description Scan planned_spans and group consecutive embellishment spans plus the following melody note into embellishment-window structs used for live player feedback.
/// @param {array} _planned_spans  Array of planned-span structs (from gv_build_planned_spans).
/// @returns {array}  Array of embellishment-group structs.
/// @reads  global.timeline_cfg.tune_channel
function gv_build_emb_groups(_planned_spans) {
    var groups = [];
    if (!is_array(_planned_spans)) return groups;

    var tune_channel = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)
        && variable_struct_exists(global.timeline_cfg, "tune_channel"))
        ? real(global.timeline_cfg.tune_channel) : -1;
    var require_tune_channel = (tune_channel >= 0);

    var n = array_length(_planned_spans);
    var i = 0;
    while (i < n) {
        var s = _planned_spans[i];
        if (!is_struct(s)) { i++; continue; }
        var s_ch = real(s.channel ?? 0);
        if (require_tune_channel && s_ch != tune_channel) { i++; continue; }
        var s_is_emb = variable_struct_exists(s, "is_embellishment") && s.is_embellishment;
        if (!s_is_emb) { i++; continue; }

        var window_start = real(s.start_ms ?? 0);
        var expected_notes = [];
        var note_set = {};
        var lane_indices = [];
        var lane_seen = {};

        // Consume grace notes on the tune channel, ignoring interleaved spans from other channels.
        var j = i;
        var last_emb_index = -1;
        var target_index = -1;

        while (j < n) {
            var sj = _planned_spans[j];
            if (!is_struct(sj)) { j++; continue; }

            var sj_ch = real(sj.channel ?? 0);
            if (require_tune_channel && sj_ch != tune_channel) {
                j++;
                continue;
            }

            var sj_is_emb = variable_struct_exists(sj, "is_embellishment") && sj.is_embellishment;
            if (sj_is_emb) {
                var canon = string(sj.note_canonical ?? "");
                array_push(expected_notes, canon);
                note_set[$ canon] = true;

                var lane_idx = gv_note_to_lane_index(sj.note_canonical ?? "", sj.note_midi ?? -1, sj.channel ?? -1);
                if (lane_idx >= 0 && lane_idx <= 8) {
                    var lane_key = string(lane_idx);
                    if (!variable_struct_exists(lane_seen, lane_key)) {
                        lane_seen[$ lane_key] = true;
                        array_push(lane_indices, lane_idx);
                    }
                }

                last_emb_index = j;
                j++;
                continue;
            }

            // First non-emb note on the tune channel is the target note.
            target_index = j;
            break;
        }

        if (array_length(expected_notes) <= 0) {
            i += 1;
            continue;
        }

        if (target_index >= 0) {
            var tgt = _planned_spans[target_index];
            var tgt_canon = string(tgt.note_canonical ?? "");
            array_push(expected_notes, tgt_canon);
            note_set[$ tgt_canon] = true;

            var tgt_lane_idx = gv_note_to_lane_index(tgt.note_canonical ?? "", tgt.note_midi ?? -1, tgt.channel ?? -1);
            if (tgt_lane_idx >= 0 && tgt_lane_idx <= 8) {
                var tgt_lane_key = string(tgt_lane_idx);
                if (!variable_struct_exists(lane_seen, tgt_lane_key)) {
                    lane_seen[$ tgt_lane_key] = true;
                    array_push(lane_indices, tgt_lane_idx);
                }
            }

            array_push(groups, {
                window_start_ms: window_start,
                window_end_ms: real(tgt.end_ms ?? real(tgt.start_ms ?? window_start)),
                anchor_ms: real(tgt.start_ms ?? window_start),
                target_measure: floor(real(tgt.measure ?? -1)),
                lane_idx: tgt_lane_idx,
                expected_notes: expected_notes,
                note_set: note_set,
                lane_indices: lane_indices,
                has_target: true
            });

            i = target_index + 1;
            continue;
        }

        // No target found Ã¢â‚¬â€œ seal group at last grace end.
        var ls = (last_emb_index >= 0) ? _planned_spans[last_emb_index] : s;
        array_push(groups, {
            window_start_ms: window_start,
            window_end_ms: is_struct(ls) ? real(ls.end_ms ?? window_start) : window_start,
            anchor_ms: is_struct(ls) ? real(ls.start_ms ?? window_start) : window_start,
            target_measure: -1,
            lane_idx: -1,
            expected_notes: expected_notes,
            note_set: note_set,
            lane_indices: lane_indices,
            has_target: false
        });

        i = max(i + 1, j + 1);
    }
    return groups;
}

/// @function gv_build_measure_nav_map(_planned_events)
/// @description Build a measure-navigation map from planned events: produces entries[], parts[], and pickup_by_part. Each entry covers one measure with its start/end times.
/// @param {array} _planned_events  Flat array of planned event structs.
/// @returns {struct}  Measure-nav map with fields: entries[], parts[], pickup_by_part.
function gv_build_measure_nav_map(_planned_events) {
    var result = {
        entries: [],
        parts: [],
        pickup_by_part: {}
    };
    if (!is_array(_planned_events)) return result;

    // Structural authority: canonical segmentation comes from event-bar boundaries.
    // Snippet/image metadata is rendering-only and must not define structure.
    var _set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _single_tune_loop_runtime = !_set_mode
        && variable_global_exists("loop_runtime_active")
        && bool(global.loop_runtime_active);

    // Loop-runtime path: preserve repeated-pass identity by tracking
    // measure starts per (iteration, part, measure), then ordering by time.
    if (_single_tune_loop_runtime) {
        var _loop_candidates = [];
        var _loop_seen_parts = {};
        var _planned_n_loop = array_length(_planned_events);
        for (var _li = 0; _li < _planned_n_loop; _li++) {
            var _lev = _planned_events[_li];
            if (!is_struct(_lev)) continue;
            var _lev_type = variable_struct_exists(_lev, "type") ? string(_lev.type) : "";
            if (_lev_type != "marker") continue;

            var _lmt = variable_struct_exists(_lev, "marker_type") ? string(_lev.marker_type) : "";
            var _lbeat = variable_struct_exists(_lev, "beat") ? floor(real(_lev.beat)) : 0;
            var _lfrac = variable_struct_exists(_lev, "beat_fraction") ? real(_lev.beat_fraction) : 0;
            var _is_boundary_loop = (_lmt == "bar") || (_lmt == "beat" && _lbeat == 1 && abs(_lfrac) <= 0.001);
            if (!_is_boundary_loop) continue;

            var _lm = -1;
            if (variable_struct_exists(_lev, "owner_measure")) _lm = floor(real(_lev.owner_measure));
            else if (variable_struct_exists(_lev, "measure")) _lm = floor(real(_lev.measure));
            if (_lm < 1) continue;
            var _lp = 1;
            if (variable_struct_exists(_lev, "owner_part")) _lp = max(1, floor(real(_lev.owner_part)));
            else if (variable_struct_exists(_lev, "part")) _lp = max(1, floor(real(_lev.part)));
            var _lit = variable_struct_exists(_lev, "loop_iteration")
                ? max(0, floor(real(_lev.loop_iteration)))
                : 0;
            var _lt = gv_evt_time_ms(_lev);

            array_push(_loop_candidates, {
                iteration: _lit,
                part: _lp,
                measure: _lm,
                start_ms: _lt
            });

            var _lp_key = string(_lp);
            if (!variable_struct_exists(_loop_seen_parts, _lp_key)) {
                _loop_seen_parts[$ _lp_key] = true;
                array_push(result.parts, _lp);
            }
        }

        if (array_length(_loop_candidates) <= 0) {
            return result;
        }

        if (array_length(_loop_candidates) > 1) {
            array_sort(_loop_candidates, function(a, b) {
                var _at = real(a.start_ms ?? 0);
                var _bt = real(b.start_ms ?? 0);
                if (_at != _bt) return _at - _bt;
                var _ait = floor(real(a.iteration ?? 0));
                var _bit = floor(real(b.iteration ?? 0));
                if (_ait != _bit) return _ait - _bit;
                var _ap = floor(real(a.part ?? 1));
                var _bp = floor(real(b.part ?? 1));
                if (_ap != _bp) return _ap - _bp;
                var _am = floor(real(a.measure ?? 0));
                var _bm = floor(real(b.measure ?? 0));
                return _am - _bm;
            });
        }

        var _loop_dedup = [];
        for (var _lc = 0; _lc < array_length(_loop_candidates); _lc++) {
            var _cand = _loop_candidates[_lc];
            if (!is_struct(_cand)) continue;
            var _keep = true;
            if (array_length(_loop_dedup) > 0) {
                var _prev = _loop_dedup[array_length(_loop_dedup) - 1];
                var _same_it = floor(real(_prev.iteration ?? 0)) == floor(real(_cand.iteration ?? 0));
                var _same_p = floor(real(_prev.part ?? 1)) == floor(real(_cand.part ?? 1));
                var _same_m = floor(real(_prev.measure ?? 0)) == floor(real(_cand.measure ?? 0));
                if (_same_it && _same_p && _same_m
                    && abs(real(_prev.start_ms ?? 0) - real(_cand.start_ms ?? 0)) <= 0.001) {
                    _keep = false;
                }
            }
            if (_keep) array_push(_loop_dedup, _cand);
        }

        result.entries = _loop_dedup;

        var _loop_entries_n = array_length(result.entries);
        var _loop_struct_idx = 1;
        for (var _lei = 0; _lei < _loop_entries_n; _lei++) {
            var _e_loop = result.entries[_lei];
            var _next_start_loop = (_lei + 1 < _loop_entries_n)
                ? real(result.entries[_lei + 1].start_ms ?? _e_loop.start_ms)
                : real(gv_get_planned_end_ms());
            if (_next_start_loop <= real(_e_loop.start_ms)) {
                var _fallback_loop_ms = (variable_global_exists("timeline_state")
                    && is_struct(global.timeline_state)
                    && variable_struct_exists(global.timeline_state, "measure_ms"))
                    ? max(1, real(global.timeline_state.measure_ms))
                    : 1000;
                _next_start_loop = real(_e_loop.start_ms) + _fallback_loop_ms;
            }
            _e_loop.end_ms = _next_start_loop;
            _e_loop.status = 0;
            _e_loop.struct_idx = _loop_struct_idx;
            _loop_struct_idx += 1;
            result.entries[_lei] = _e_loop;
        }

        var _loop_pickup = {};
        for (var _pi_loop = 0; _pi_loop < array_length(result.parts); _pi_loop++) {
            _loop_pickup[$ string(result.parts[_pi_loop])] = false;
        }
        result.pickup_by_part = _loop_pickup;
        return result;
    }

    var _boundaries = [];
    var _n = array_length(_planned_events);
    for (var _i = 0; _i < _n; _i++) {
        var _ev = _planned_events[_i];
        if (!is_struct(_ev)) continue;
        var _ev_type = variable_struct_exists(_ev, "type") ? string(_ev.type) : "";
        if (_ev_type != "marker") continue;

        var _is_boundary = false;
        if (variable_struct_exists(_ev, "nav_anchor_is_bar")) {
            _is_boundary = bool(_ev.nav_anchor_is_bar);
        } else {
            var _mt = variable_struct_exists(_ev, "marker_type") ? string(_ev.marker_type) : "";
            var _beat = variable_struct_exists(_ev, "beat") ? floor(real(_ev.beat)) : 0;
            var _frac = 0;
            if (variable_struct_exists(_ev, "beat_fraction")) _frac = real(_ev.beat_fraction);
            else if (variable_struct_exists(_ev, "beat_frac")) _frac = real(_ev.beat_frac);
            _is_boundary = (_mt == "bar") || (_mt == "beat" && _beat == 1 && abs(_frac) <= 0.001);
        }
        if (!_is_boundary) continue;

        var _m = -1;
        if (variable_struct_exists(_ev, "owner_measure")) _m = floor(real(_ev.owner_measure));
        else if (variable_struct_exists(_ev, "measure")) _m = floor(real(_ev.measure));
        if (_m < 1) continue;
        var _p = 1;
        if (variable_struct_exists(_ev, "owner_part")) _p = max(1, floor(real(_ev.owner_part)));
        else if (variable_struct_exists(_ev, "part")) _p = max(1, floor(real(_ev.part)));
        var _iter = variable_struct_exists(_ev, "loop_iteration")
            ? max(0, floor(real(_ev.loop_iteration)))
            : 0;
        var _t = gv_evt_time_ms(_ev);

        array_push(_boundaries, {
            order_idx: _i,
            time_ms: _t,
            part: _p,
            measure: _m,
            iteration: _iter
        });
    }

    if (array_length(_boundaries) <= 0) {
        var _fallback_measure_ms = (variable_global_exists("timeline_state")
            && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "measure_ms"))
            ? max(1, real(global.timeline_state.measure_ms))
            : 1000;
        var _fallback_end_ms = gv_measure_nav_resolve_end_ms_from_events(_planned_events);
        var _synthetic_map = gv_build_synthetic_measure_nav_map(_fallback_end_ms, _fallback_measure_ms);
        result.entries = _synthetic_map.entries;
        result.parts = _synthetic_map.parts;
        result.pickup_by_part = _synthetic_map.pickup_by_part;
        return result;
    }

    if (array_length(_boundaries) > 1) {
        array_sort(_boundaries, function(a, b) {
            var _at = real(a.time_ms ?? 0);
            var _bt = real(b.time_ms ?? 0);
            if (_at != _bt) return _at - _bt;
            var _ao = floor(real(a.order_idx ?? 0));
            var _bo = floor(real(b.order_idx ?? 0));
            return _ao - _bo;
        });
    }

    var _dedup = [];
    for (var _bi = 0; _bi < array_length(_boundaries); _bi++) {
        var _b = _boundaries[_bi];
        if (!is_struct(_b)) continue;

        var _keep = true;
        if (array_length(_dedup) > 0) {
            var _prev = _dedup[array_length(_dedup) - 1];
            var _same_t = abs(real(_prev.time_ms ?? 0) - real(_b.time_ms ?? 0)) <= 0.001;
            var _same_p = floor(real(_prev.part ?? 1)) == floor(real(_b.part ?? 1));
            var _same_m = floor(real(_prev.measure ?? -1)) == floor(real(_b.measure ?? -1));
            var _same_i = floor(real(_prev.iteration ?? 0)) == floor(real(_b.iteration ?? 0));
            if (_same_t && _same_p && _same_m && _same_i) _keep = false;
        }
        if (_keep) array_push(_dedup, _b);
    }

    var _entries = [];
    var _struct_idx = 1;
    for (var _ei = 0; _ei < array_length(_dedup); _ei++) {
        var _start_b = _dedup[_ei];
        if (!is_struct(_start_b)) continue;

        var _start_ms = real(_start_b.time_ms ?? -1);
        if (_start_ms < 0) continue;

        var _end_ms = -1;
        if (_ei + 1 < array_length(_dedup)) {
            _end_ms = real(_dedup[_ei + 1].time_ms ?? -1);
        } else {
            _end_ms = real(gv_get_planned_end_ms());
            if (_end_ms <= _start_ms + 0.001) {
                var _fallback_ms = (variable_global_exists("timeline_state")
                    && is_struct(global.timeline_state)
                    && variable_struct_exists(global.timeline_state, "measure_ms"))
                    ? max(1, real(global.timeline_state.measure_ms))
                    : 1000;
                _end_ms = _start_ms + _fallback_ms;
            }
        }
        if (_end_ms <= _start_ms + 0.001) continue;

        array_push(_entries, {
            measure: floor(real(_start_b.measure ?? -1)),
            part: max(1, floor(real(_start_b.part ?? 1))),
            iteration: floor(real(_start_b.iteration ?? 0)),
            start_ms: _start_ms,
            end_ms: _end_ms,
            status: 0,
            struct_idx: _struct_idx
        });
        _struct_idx += 1;
    }

    result.entries = _entries;

    var _part_seen = {};
    for (var _pi = 0; _pi < array_length(result.entries); _pi++) {
        var _e = result.entries[_pi];
        if (!is_struct(_e)) continue;
        var _pnum = max(1, floor(real(_e.part ?? 1)));
        var _pk = string(_pnum);
        if (!variable_struct_exists(_part_seen, _pk)) {
            _part_seen[$ _pk] = true;
            array_push(result.parts, _pnum);
        }
    }

    if (array_length(result.parts) > 1) {
        for (var _s = 1; _s < array_length(result.parts); _s++) {
            var _v = result.parts[_s];
            var _j = _s - 1;
            while (_j >= 0 && real(result.parts[_j]) > real(_v)) {
                result.parts[_j + 1] = result.parts[_j];
                _j -= 1;
            }
            result.parts[_j + 1] = _v;
        }
    }

    var _first_start_by_part = {};
    for (var _fsi = 0; _fsi < array_length(result.entries); _fsi++) {
        var _fe = result.entries[_fsi];
        if (!is_struct(_fe)) continue;
        var _fpk = string(max(1, floor(real(_fe.part ?? 1))));
        if (!variable_struct_exists(_first_start_by_part, _fpk)
            || real(_fe.start_ms ?? 0) < real(_first_start_by_part[$ _fpk])) {
            _first_start_by_part[$ _fpk] = real(_fe.start_ms ?? 0);
        }
    }

    for (var _rp = 0; _rp < array_length(result.parts); _rp++) {
        result.pickup_by_part[$ string(result.parts[_rp])] = false;
    }

    for (var _pe = 0; _pe < _n; _pe++) {
        var _pev = _planned_events[_pe];
        if (!is_struct(_pev)) continue;

        var _part_num = variable_struct_exists(_pev, "part")
            ? max(1, floor(real(_pev.part)))
            : 1;
        var _part_key = string(_part_num);
        if (!variable_struct_exists(_first_start_by_part, _part_key)) continue;

        var _measure_num = variable_struct_exists(_pev, "measure")
            ? floor(real(_pev.measure))
            : 1;
        if (_measure_num > 0) continue;

        var _time_ev = gv_evt_time_ms(_pev);
        if (_time_ev <= real(_first_start_by_part[$ _part_key]) + 0.001) {
            result.pickup_by_part[$ _part_key] = true;
        }
    }

    return result;
}

/// @function gv_measure_nav_scroll_rows(_delta_rows)
/// @description Scroll the measure nav view by a number of rows, clamped to valid range.
/// @param {real} _delta_rows  Positive = scroll down; negative = scroll up.
/// @returns {bool}  true if scroll position changed.
/// @reads  global.timeline_state.measure_nav_total_rows, global.timeline_state.measure_nav_view_rows, global.timeline_state.measure_nav_scroll_row
/// @writes global.timeline_state.measure_nav_scroll_row
function gv_measure_nav_scroll_rows(_delta_rows) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;

    var total_rows = max(0, floor(real(global.timeline_state.measure_nav_total_rows ?? 0)));
    var view_rows = max(1, floor(real(global.timeline_state.measure_nav_view_rows ?? 1)));
    var max_scroll = max(0, total_rows - view_rows);
    var current_scroll = max(0, floor(real(global.timeline_state.measure_nav_scroll_row ?? 0)));
    var target_scroll = clamp(current_scroll + floor(real(_delta_rows)), 0, max_scroll);
    if (target_scroll == current_scroll) return false;

    global.timeline_state.measure_nav_scroll_row = target_scroll;
    return true;
}

/// @function gv_log_measure_nav_page_turn(_playhead_ms, _measure_num, _from_scroll, _to_scroll, _target_row, _view_rows, _page_rows, _follow_mode)
/// @description Emit a structured page_turn event when tune-structure auto-follow changes panel scroll.
/// @param {real} _playhead_ms  Playhead time that triggered the turn.
/// @param {real} _measure_num  Measure active when the turn happened.
/// @param {real} _from_scroll  Previous scroll row.
/// @param {real} _to_scroll  New scroll row.
/// @param {real} _target_row  Target row for the active measure entry.
/// @param {real} _view_rows  Visible panel rows.
/// @param {real} _page_rows  Follow page size rows (0 when continuous mode).
/// @param {string} _follow_mode  Follow mode name (paged/continuous).
/// @returns {none}
/// @reads  global.EVENT_HISTORY_ENABLED, global.current_tune_name, global.current_set_item_index, global.playback_context
/// @writes global.EVENT_HISTORY
function gv_log_measure_nav_page_turn(_playhead_ms, _measure_num, _from_scroll, _to_scroll, _target_row, _view_rows, _page_rows, _follow_mode) {
    if (!variable_global_exists("EVENT_HISTORY")) return;
    if (variable_global_exists("EVENT_HISTORY_ENABLED") && !global.EVENT_HISTORY_ENABLED) return;

    var playhead_ms = real(_playhead_ms);
    var from_scroll = max(0, floor(real(_from_scroll)));
    var to_scroll = max(0, floor(real(_to_scroll)));
    var target_row = max(0, floor(real(_target_row)));
    var view_rows = max(1, floor(real(_view_rows)));
    var page_rows = max(0, floor(real(_page_rows)));
    var follow_mode = string_lower(string(_follow_mode ?? "paged"));

    var page_size = max(1, (page_rows > 0) ? page_rows : view_rows);
    var from_page = floor(from_scroll / page_size);
    var to_page = floor(to_scroll / page_size);

    var active_segment = 0;
    if (variable_global_exists("playback_context") && is_struct(global.playback_context)) {
        active_segment = floor(real(global.playback_context[$ "active_segment"] ?? 0));
    }

    var tune_name = variable_global_exists("current_tune_name")
        ? string(global.current_tune_name)
        : "unknown";

    var eh_add_idx = asset_get_index("event_history_add");
    if (!script_exists(eh_add_idx)) {
        // Logging must never block panel rendering.
        return;
    }

    script_execute(eh_add_idx, {
        timestamp_ms: playhead_ms,
        expected_time_ms: playhead_ms,
        actual_time_ms: playhead_ms,
        delta_ms: 0,
        canonical_time_ms: playhead_ms,
        audio_target_time_ms: playhead_ms,
        visual_target_time_ms: playhead_ms,
        input_aligned_time_ms: playhead_ms,
        event_type: "page_turn",
        source: "tune_structure_follow",
        note_midi: 0,
        note_letter: "",
        velocity: 0,
        channel: 0,
        tune_name: tune_name,
        event_id: -1,
        marker_type: "page_turn",
        measure: max(-1, floor(real(_measure_num))),
        beat: 0,
        beat_fraction: 0,
        follow_mode: follow_mode,
        from_scroll_row: from_scroll,
        to_scroll_row: to_scroll,
        target_row: target_row,
        view_rows: view_rows,
        page_rows: page_rows,
        from_page: from_page,
        to_page: to_page,
        active_segment: max(0, active_segment)
    });

    show_debug_message(
        "[PAGE_TURN] ms=" + string(playhead_ms)
        + " measure=" + string(max(-1, floor(real(_measure_num))))
        + " mode=" + follow_mode
        + " seg=" + string(max(0, active_segment))
        + " row " + string(from_scroll) + "->" + string(to_scroll)
        + " page " + string(from_page) + "->" + string(to_page)
        + " target_row=" + string(target_row)
    );
}

/// @function gv_loop_mode_enabled()
/// @description Return true if global loop mode is currently enabled.
/// @returns {bool}
/// @reads  global.loop_mode_enabled
function gv_loop_mode_enabled() {
    return variable_global_exists("loop_mode_enabled") && global.loop_mode_enabled;
}

/// @function gv_loop_blank_measure_enabled()
/// @description Return whether the loop blank measure (silent count-in measure) is enabled.
/// @returns {bool}
/// @reads  global.timeline_state.loop_blank_measure
function gv_loop_blank_measure_enabled() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    return variable_struct_exists(global.timeline_state, "loop_blank_measure")
        && global.timeline_state.loop_blank_measure;
}

/// @function gv_loop_set_blank_measure_enabled(_enabled)
/// @description Enable or disable the loop blank measure (silent count-in).
/// @param {bool} _enabled  true to enable.
/// @returns {bool}  false if timeline_state absent.
/// @writes global.timeline_state.loop_blank_measure
function gv_loop_set_blank_measure_enabled(_enabled) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    global.timeline_state.loop_blank_measure = (_enabled == true);
    return true;
}

/// @function gv_loop_get_selected_measures()
/// @description Return a sorted array of measure numbers that are currently selected for looping.
/// @returns {array}  Sorted array of measure numbers.
/// @reads  global.timeline_state.loop_selected_measures
function gv_loop_make_selection_key(_measure, _part = 1) {
    var m = floor(real(_measure));
    var p = floor(real(_part));
    if (p < 1) p = 1;
    return string(p) + ":" + string(m);
}

/// @function gv_loop_parse_selection_key(_key)
/// @description Parse a persisted loop-selection key into `{part, measure, valid}`. Supports legacy measure-only keys.
/// @param {string} _key  Selection key (`part:measure`) or legacy (`measure`).
/// @returns {struct}  Parsed key info.
function gv_loop_parse_selection_key(_key) {
    var s = string(_key ?? "");
    var out = { part: 1, measure: -1, valid: false };
    if (s == "") return out;

    var colon_pos = string_pos(":", s);
    if (colon_pos > 0) {
        var p_text = string_copy(s, 1, colon_pos - 1);
        var m_text = string_delete(s, 1, colon_pos);
        out.part = max(1, floor(real(p_text)));
        out.measure = floor(real(m_text));
        out.valid = (out.measure >= 1);
        return out;
    }

    out.part = 1;
    out.measure = floor(real(s));
    out.valid = (out.measure >= 1);
    return out;
}

/// @function gv_loop_get_selected_measure_refs()
/// @description Return selected loop targets as part-aware refs.
/// @returns {array}  Array of `{part, measure, key, nav_idx, owner_nav_idx, timeline_start_ms, timeline_end_ms, owner_start_ms, owner_end_ms, start_ms, end_ms}`.
/// @reads  global.timeline_state.loop_selected_measures, global.timeline_state.measure_nav_entries, global.playback_events
function gv_loop_get_selected_measure_refs() {
    var out = [];
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;
    if (!variable_struct_exists(global.timeline_state, "loop_selected_measures")
        || !is_struct(global.timeline_state.loop_selected_measures)) {
        return out;
    }

    var sel = global.timeline_state.loop_selected_measures;
    var entries = (variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries))
        ? global.timeline_state.measure_nav_entries
        : [];
    var ownership_entries = [];
    if (is_undefined(scr_button_build_measure_nav_map_for_ownership) == false
        && variable_global_exists("playback_events")
        && is_array(global.playback_events)
        && array_length(global.playback_events) > 0) {
        var _own_map = scr_button_build_measure_nav_map_for_ownership(global.playback_events);
        if (is_struct(_own_map)
            && variable_struct_exists(_own_map, "entries")
            && is_array(variable_struct_get(_own_map, "entries"))) {
            ownership_entries = variable_struct_get(_own_map, "entries");
        }
    }

    var ownership_by_key = {};
    for (var oi = 0; oi < array_length(ownership_entries); oi++) {
        var oe = ownership_entries[oi];
        if (!is_struct(oe)) continue;
        var op = max(1, floor(real(oe.part ?? 1)));
        var om = floor(real(oe.measure ?? -1));
        if (om < 1) continue;
        var ok = gv_loop_make_selection_key(om, op);
        if (!variable_struct_exists(ownership_by_key, ok)) {
            ownership_by_key[$ ok] = {
                owner_nav_idx: oi,
                start_ms: real(oe.start_ms ?? -1),
                end_ms: real(oe.end_ms ?? -1)
            };
        }
    }
    var keys = variable_struct_get_names(sel);
    if (!is_array(keys)) return out;

    for (var i = 0; i < array_length(keys); i++) {
        var key = string(keys[i]);
        if (!variable_struct_exists(sel, key) || !sel[$ key]) continue;
        var parsed = gv_loop_parse_selection_key(key);
        if (!is_struct(parsed) || !(parsed.valid ?? false)) continue;

        var p = floor(real(parsed.part ?? 1));
        var m = floor(real(parsed.measure ?? -1));
        if (m < 1) continue;

        var nav_idx = -1;
        var start_ms = -1;
        var end_ms = -1;
        for (var ei = 0; ei < array_length(entries); ei++) {
            var e = entries[ei];
            if (!is_struct(e)) continue;
            var ep = max(1, floor(real(e.part ?? 1)));
            var em = floor(real(e.measure ?? -1));
            if (ep != p || em != m) continue;
            nav_idx = ei;
            start_ms = real(e.start_ms ?? -1);
            end_ms = real(e.end_ms ?? -1);
            break;
        }

        var own_key = gv_loop_make_selection_key(m, p);
        var owner_nav_idx = -1;
        var owner_start_ms = -1;
        var owner_end_ms = -1;
        if (variable_struct_exists(ownership_by_key, own_key)) {
            var own_ref = ownership_by_key[$ own_key];
            if (is_struct(own_ref)) {
                owner_nav_idx = floor(real(own_ref.owner_nav_idx ?? -1));
                owner_start_ms = real(own_ref.start_ms ?? -1);
                owner_end_ms = real(own_ref.end_ms ?? -1);
            }
        }

        var timeline_start_ms = start_ms;
        var timeline_end_ms = end_ms;
        var effective_start_ms = start_ms;
        var effective_end_ms = end_ms;
        var owner_valid = owner_start_ms >= 0 && owner_end_ms > owner_start_ms + 0.001;
        var timeline_valid = effective_start_ms >= 0 && effective_end_ms > effective_start_ms + 0.001;
        if (timeline_valid && owner_valid) {
            effective_start_ms = min(effective_start_ms, owner_start_ms);
            effective_end_ms = max(effective_end_ms, owner_end_ms);
        } else if (!timeline_valid && owner_valid) {
            effective_start_ms = owner_start_ms;
            effective_end_ms = owner_end_ms;
        }

        array_push(out, {
            part: p,
            measure: m,
            key: gv_loop_make_selection_key(m, p),
            nav_idx: nav_idx,
            owner_nav_idx: owner_nav_idx,
            timeline_start_ms: timeline_start_ms,
            timeline_end_ms: timeline_end_ms,
            owner_start_ms: owner_start_ms,
            owner_end_ms: owner_end_ms,
            start_ms: effective_start_ms,
            end_ms: effective_end_ms
        });
    }

    if (array_length(out) <= 1) return out;
    for (var a = 1; a < array_length(out); a++) {
        var v = out[a];
        var b = a - 1;
        while (b >= 0) {
            var bn = floor(real(out[b].nav_idx ?? -1));
            var vn = floor(real(v.nav_idx ?? -1));
            if (bn >= 0 && vn >= 0) {
                if (bn <= vn) break;
                out[b + 1] = out[b];
                b--;
                continue;
            }

            var bp = floor(real(out[b].part ?? 1));
            var bm = floor(real(out[b].measure ?? -1));
            var vp = floor(real(v.part ?? 1));
            var vm = floor(real(v.measure ?? -1));
            if (bp < vp || (bp == vp && bm <= vm)) break;
            out[b + 1] = out[b];
            b--;
        }
        out[b + 1] = v;
    }
    return out;
}

/// @function gv_loop_resolve_boundary_endpoints(_selected_refs)
/// @description Resolve canonical loop boundary endpoints (start/end) from selected measure refs using timeline windows first, then effective windows; applies optional beat-level refinement when configured.
/// @param {array} _selected_refs Selected refs from gv_loop_get_selected_measure_refs().
/// @returns {struct} {valid, start_ms, end_ms, start_boundary, end_boundary, source}
/// @reads global.timeline_state.measure_nav_entries, global.timeline_state.loop_boundary_refinement, global.playback_events
/// @writes none
/// @objects none
/// @callers scr_button_loop_build_playback_events
function gv_loop_resolve_boundary_endpoints(_selected_refs) {
    var out = {
        valid: false,
        start_ms: -1,
        end_ms: -1,
        source: "none",
        start_boundary: {
            part: 1,
            measure: -1,
            beat: 1,
            beat_fraction: 0,
            nav_idx: -1,
            time_ms: -1,
            source: "none"
        },
        end_boundary: {
            part: 1,
            measure: -1,
            beat: 1,
            beat_fraction: 0,
            nav_idx: -1,
            time_ms: -1,
            source: "none"
        }
    };

    if (!is_array(_selected_refs) || array_length(_selected_refs) <= 0) return out;

    var _first = _selected_refs[0];
    var _last = _selected_refs[array_length(_selected_refs) - 1];
    if (!is_struct(_first) || !is_struct(_last)) return out;

    var _timeline_start_ms = real(_first[$ "timeline_start_ms"] ?? -1);
    var _timeline_end_ms = real(_last[$ "timeline_end_ms"] ?? -1);
    var _effective_start_ms = real(_first[$ "start_ms"] ?? -1);
    var _effective_end_ms = real(_last[$ "end_ms"] ?? -1);
    var _owner_start_ms = real(_first[$ "owner_start_ms"] ?? -1);
    var _owner_end_ms = real(_last[$ "owner_end_ms"] ?? -1);

    var _start_ms = _timeline_start_ms;
    var _end_ms = _timeline_end_ms;
    var _source = "timeline_refs";

    var _timeline_valid = _start_ms >= 0 && _end_ms > _start_ms + 0.001;
    var _effective_valid = _effective_start_ms >= 0 && _effective_end_ms > _effective_start_ms + 0.001;
    var _owner_valid_start = _owner_start_ms >= 0;
    var _owner_valid_end = _owner_end_ms >= 0;

    if (_timeline_valid) {
        if (_owner_valid_start) _start_ms = min(_start_ms, _owner_start_ms);
        if (_owner_valid_end) _end_ms = max(_end_ms, _owner_end_ms);
        if (_start_ms != _timeline_start_ms || _end_ms != _timeline_end_ms) {
            _source = "timeline_owner_envelope";
        }
    } else if (_effective_valid) {
        _start_ms = _effective_start_ms;
        _end_ms = _effective_end_ms;
        _source = "effective_refs";
    }

    if (_start_ms < 0 || _end_ms <= _start_ms + 0.001) return out;

    var _start_part = max(1, floor(real(_first[$ "part"] ?? 1)));
    var _start_measure = floor(real(_first[$ "measure"] ?? -1));
    var _start_nav_idx = floor(real(_first[$ "nav_idx"] ?? -1));

    out.start_ms = _start_ms;
    out.end_ms = _end_ms;
    out.source = _source;
    out.start_boundary = {
        part: _start_part,
        measure: _start_measure,
        beat: 1,
        beat_fraction: 0,
        nav_idx: _start_nav_idx,
        time_ms: _start_ms,
        source: "selected_start"
    };

    var _end_part = max(1, floor(real(_last[$ "part"] ?? 1)));
    var _end_measure = floor(real(_last[$ "measure"] ?? -1)) + 1;
    var _end_nav_idx = -1;
    var _end_source = "derived_following_measure";

    var _entries = (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries))
        ? global.timeline_state.measure_nav_entries
        : [];

    var _last_nav_idx = floor(real(_last[$ "nav_idx"] ?? -1));
	var _model_next_seg = gv_tune_structure_model_find_next_segment(_end_part, floor(real(_last[$ "measure"] ?? -1)), _last_nav_idx);
	if (is_struct(_model_next_seg)) {
		_end_part = max(1, floor(real(_model_next_seg.part ?? _end_part)));
		_end_measure = floor(real(_model_next_seg.source_measure ?? _end_measure));
		_end_nav_idx = floor(real(_model_next_seg.source_nav_idx ?? -1));
		_end_source = "canonical_model_next_segment";
	} else if (_last_nav_idx >= 0 && (_last_nav_idx + 1) < array_length(_entries)) {
        var _next_entry = _entries[_last_nav_idx + 1];
        if (is_struct(_next_entry)) {
            _end_part = max(1, floor(real(_next_entry[$ "part"] ?? _end_part)));
            _end_measure = floor(real(_next_entry[$ "measure"] ?? _end_measure));
            _end_nav_idx = _last_nav_idx + 1;
            _end_source = "next_nav_entry";
        }
    } else {
        var _best_idx = -1;
        var _best_dt = 1000000000;
        for (var _ei = 0; _ei < array_length(_entries); _ei++) {
            var _e = _entries[_ei];
            if (!is_struct(_e)) continue;
            var _est = real(_e[$ "start_ms"] ?? -1);
            if (_est < 0) continue;
            var _dt = abs(_est - _end_ms);
            if (_dt < _best_dt) {
                _best_dt = _dt;
                _best_idx = _ei;
            }
        }
        if (_best_idx >= 0 && _best_dt <= 1.0) {
            var _hit = _entries[_best_idx];
            _end_part = max(1, floor(real(_hit[$ "part"] ?? _end_part)));
            _end_measure = floor(real(_hit[$ "measure"] ?? _end_measure));
            _end_nav_idx = _best_idx;
            _end_source = "time_aligned_nav_entry";
        }
    }

    out.end_boundary = {
        part: _end_part,
        measure: _end_measure,
        beat: 1,
        beat_fraction: 0,
        nav_idx: _end_nav_idx,
        time_ms: _end_ms,
        source: _end_source
    };

    // Phase B backend wiring: optional beat-level endpoint refinement.
    var _refine = (variable_global_exists("timeline_state")
        && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "loop_boundary_refinement")
        && is_struct(global.timeline_state.loop_boundary_refinement))
        ? global.timeline_state.loop_boundary_refinement
        : {};

    if (is_struct(_refine) && bool(_refine[$ "enabled"] ?? false)) {
        var _events = (variable_global_exists("playback_events") && is_array(global.playback_events))
            ? global.playback_events
            : [];
        if (array_length(_events) > 0) {
            var _base_start_ms = out.start_ms;
            var _base_end_ms = out.end_ms;
            var _base_start_boundary = out.start_boundary;
            var _base_end_boundary = out.end_boundary;

            var _refined_start_ms = out.start_ms;
            var _refined_end_ms = out.end_ms;
            var _refined_start_applied = false;
            var _refined_end_applied = false;

            var _target_start_part = max(1, floor(real(_refine[$ "start_part"] ?? _start_part)));
            var _target_start_measure = floor(real(_refine[$ "start_measure"] ?? _start_measure));
            if (_target_start_measure < 1) _target_start_measure = _start_measure;
            var _target_start_beat = max(1, floor(real(_refine[$ "start_beat"] ?? 1)));
            var _target_start_frac = real(_refine[$ "start_beat_fraction"] ?? 0);

            var _target_end_part = max(1, floor(real(_refine[$ "end_part"] ?? _end_part)));
            var _target_end_measure = floor(real(_refine[$ "end_measure"] ?? _end_measure));
            if (_target_end_measure < 1) _target_end_measure = _end_measure;
            var _target_end_beat = max(1, floor(real(_refine[$ "end_beat"] ?? 1)));
            var _target_end_frac = real(_refine[$ "end_beat_fraction"] ?? 0);

            var _start_hit_ms = -1;
            var _start_max_beat_seen = 0;
            var _start_last_marker_ms = -1;
            for (var _si = 0; _si < array_length(_events); _si++) {
                var _sev = _events[_si];
                if (!is_struct(_sev)) continue;
                if (string(_sev[$ "type"] ?? "") != "marker") continue;

                var _sp = max(1, floor(real(_sev[$ "owner_part"] ?? (_sev[$ "part"] ?? 1))));
                var _sm = floor(real(_sev[$ "owner_measure"] ?? (_sev[$ "measure"] ?? -1)));
                if (_sp != _target_start_part || _sm != _target_start_measure) continue;

                var _s_mk = string(_sev[$ "marker_type"] ?? "");
                var _s_beat = floor(real(_sev[$ "beat"] ?? 0));
                var _s_frac = real(_sev[$ "beat_fraction"] ?? 0);
                if (_s_mk == "beat") {
                    _start_max_beat_seen = max(_start_max_beat_seen, _s_beat);
                }
                if (_s_mk == "bar" || _s_mk == "beat") {
                    var _s_marker_t = real(_sev[$ "time"] ?? -1);
                    if (_s_marker_t >= 0) {
                        _start_last_marker_ms = max(_start_last_marker_ms, _s_marker_t);
                    }
                }
                var _s_hit = false;
                if (_target_start_beat == 1 && abs(_target_start_frac) <= 0.001) {
                    _s_hit = (_s_mk == "bar") || (_s_mk == "beat" && _s_beat == 1 && abs(_s_frac) <= 0.001);
                } else {
                    _s_hit = (_s_mk == "beat" && _s_beat == _target_start_beat && abs(_s_frac - _target_start_frac) <= 0.001);
                }
                if (!_s_hit) continue;

                var _st = real(_sev[$ "time"] ?? -1);
                if (_st < 0) continue;
                if (_start_hit_ms < 0 || _st < _start_hit_ms) _start_hit_ms = _st;
            }
            if (_start_hit_ms < 0
                && _target_start_frac == 0
                && _target_start_beat > 1
                && _start_max_beat_seen > 0
                && _target_start_beat == (_start_max_beat_seen + 1)) {
                // Internal-pickup bars can export one fewer beat marker; map the
                // implied trailing beat to the last in-measure marker time so the
                // pickup note is included in loop start selection.
                if (_start_last_marker_ms >= 0) {
                    _start_hit_ms = _start_last_marker_ms;
                }
            }
            if (_start_hit_ms >= 0) {
                _refined_start_ms = _start_hit_ms;
                out.start_boundary = {
                    part: _target_start_part,
                    measure: _target_start_measure,
                    beat: _target_start_beat,
                    beat_fraction: _target_start_frac,
                    nav_idx: _start_nav_idx,
                    time_ms: _start_hit_ms,
                    source: "refined_beat"
                };
                _refined_start_applied = true;
            }

            var _end_hit_ms = -1;
            var _end_max_beat_seen = 0;
            var _end_target_start_ms = -1;
            for (var _ei2 = 0; _ei2 < array_length(_events); _ei2++) {
                var _eev = _events[_ei2];
                if (!is_struct(_eev)) continue;
                if (string(_eev[$ "type"] ?? "") != "marker") continue;

                var _ep2 = max(1, floor(real(_eev[$ "owner_part"] ?? (_eev[$ "part"] ?? 1))));
                var _em2 = floor(real(_eev[$ "owner_measure"] ?? (_eev[$ "measure"] ?? -1)));
                if (_ep2 != _target_end_part || _em2 != _target_end_measure) continue;

                var _e_mk = string(_eev[$ "marker_type"] ?? "");
                var _e_beat = floor(real(_eev[$ "beat"] ?? 0));
                var _e_frac = real(_eev[$ "beat_fraction"] ?? 0);
                if (_e_mk == "beat") {
                    _end_max_beat_seen = max(_end_max_beat_seen, _e_beat);
                }
                var _e_hit = false;
                if (_target_end_beat == 1 && abs(_target_end_frac) <= 0.001) {
                    _e_hit = (_e_mk == "bar") || (_e_mk == "beat" && _e_beat == 1 && abs(_e_frac) <= 0.001);
                } else {
                    _e_hit = (_e_mk == "beat" && _e_beat == _target_end_beat && abs(_e_frac - _target_end_frac) <= 0.001);
                }
                if (!_e_hit) continue;

                var _et = real(_eev[$ "time"] ?? -1);
                if (_et < 0) continue;
                if (_end_target_start_ms < 0 || _et < _end_target_start_ms) _end_target_start_ms = _et;
            }

            if (_end_target_start_ms >= 0) {
                _end_hit_ms = _end_target_start_ms;
            }

            if (_end_hit_ms < 0
                && _target_end_frac == 0
                && _target_end_beat > 1
                && _end_max_beat_seen > 0
                && _target_end_beat == (_end_max_beat_seen + 1)) {
                for (var _en = 0; _en < array_length(_events); _en++) {
                    var _neev = _events[_en];
                    if (!is_struct(_neev)) continue;
                    if (string(_neev[$ "type"] ?? "") != "marker") continue;
                    var _np2 = max(1, floor(real(_neev[$ "owner_part"] ?? (_neev[$ "part"] ?? 1))));
                    var _nm2 = floor(real(_neev[$ "owner_measure"] ?? (_neev[$ "measure"] ?? -1)));
                    if (_np2 != _target_end_part || _nm2 != (_target_end_measure + 1)) continue;
                    var _nmk2 = string(_neev[$ "marker_type"] ?? "");
                    var _nb2 = floor(real(_neev[$ "beat"] ?? 0));
                    var _nf2 = real(_neev[$ "beat_fraction"] ?? 0);
                    var _is_next_boundary2 = (_nmk2 == "bar") || (_nmk2 == "beat" && _nb2 == 1 && abs(_nf2) <= 0.001);
                    if (!_is_next_boundary2) continue;
                    var _nt2 = real(_neev[$ "time"] ?? -1);
                    if (_nt2 < 0) continue;
                    if (_end_hit_ms < 0 || _nt2 < _end_hit_ms) _end_hit_ms = _nt2;
                }
            }
            if (_end_hit_ms >= 0) {
                _refined_end_ms = _end_hit_ms;
                out.end_boundary = {
                    part: _target_end_part,
                    measure: _target_end_measure,
                    beat: _target_end_beat,
                    beat_fraction: _target_end_frac,
                    nav_idx: _end_nav_idx,
                    time_ms: _end_hit_ms,
                    source: "refined_beat"
                };
                _refined_end_applied = true;
            }

            if (_refined_end_ms > _refined_start_ms + 0.001) {
                out.start_ms = _refined_start_ms;
                out.end_ms = _refined_end_ms;
                if (_refined_start_applied) out.source += "+start_beat";
                if (_refined_end_applied) out.source += "+end_beat";
            } else {
                out.start_ms = _base_start_ms;
                out.end_ms = _base_end_ms;
                out.start_boundary = _base_start_boundary;
                out.end_boundary = _base_end_boundary;
                out.source += "+refine_invalid_fallback";
            }
        }
    }

    out.valid = true;
    return out;
}

function gv_loop_get_selected_measures() {
    var out = [];
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return out;
    if (!variable_struct_exists(global.timeline_state, "loop_selected_measures")
        || !is_struct(global.timeline_state.loop_selected_measures)) {
        return out;
    }

    var sel = global.timeline_state.loop_selected_measures;
    var keys = variable_struct_get_names(sel);
    if (!is_array(keys)) return out;

    var seen = {};
    for (var i = 0; i < array_length(keys); i++) {
        var key = string(keys[i]);
        if (!variable_struct_exists(sel, key) || !sel[$ key]) continue;
        var parsed = gv_loop_parse_selection_key(key);
        if (!is_struct(parsed) || !(parsed.valid ?? false)) continue;

        var m = floor(real(parsed.measure ?? -1));
        if (m < 1) continue;
        var mkey = string(m);
        if (variable_struct_exists(seen, mkey)) continue;
        seen[$ mkey] = true;
        array_push(out, m);
    }

    if (array_length(out) <= 1) return out;
    for (var a = 1; a < array_length(out); a++) {
        var v = out[a];
        var b = a - 1;
        while (b >= 0 && out[b] > v) {
            out[b + 1] = out[b];
            b--;
        }
        out[b + 1] = v;
    }
    return out;
}

/// @function gv_loop_has_selected_measures()
/// @description Return true if at least one measure is currently selected for looping.
/// @returns {bool}
function gv_loop_has_selected_measures() {
    return array_length(gv_loop_get_selected_measures()) > 0;
}

/// @function gv_loop_measure_is_selected(_measure, _part)
/// @description Return true if a specific measure number is in the loop selection set.
/// @param {real} _measure  Measure number (1-based).
/// @param {real} _part  Optional part number (defaults to 1).
/// @returns {bool}
/// @reads  global.timeline_state.loop_selected_measures
function gv_loop_measure_is_selected(_measure, _part = 1) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "loop_selected_measures")
        || !is_struct(global.timeline_state.loop_selected_measures)) {
        return false;
    }
    var m = floor(real(_measure));
    if (m < 1) return false;
    var p = max(1, floor(real(_part)));
    var key_pm = gv_loop_make_selection_key(m, p);
    if (variable_struct_exists(global.timeline_state.loop_selected_measures, key_pm)
        && global.timeline_state.loop_selected_measures[$ key_pm]) {
        return true;
    }

    // Backward-compat for persisted legacy selection keys.
    var legacy_key = string(m);
    return variable_struct_exists(global.timeline_state.loop_selected_measures, legacy_key)
        && global.timeline_state.loop_selected_measures[$ legacy_key];
}

/// @function gv_loop_clear_selected_measures()
/// @description Clear all loop measure selections and reset the last-selected tracker.
/// @returns {bool}  false if timeline_state absent.
/// @writes global.timeline_state.loop_selected_measures, global.timeline_state.loop_last_selected_measure, global.timeline_state.loop_boundary_refinement
function gv_loop_clear_selected_measures() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    global.timeline_state.loop_selected_measures = {};
    global.timeline_state.loop_last_selected_measure = -1;
    global.timeline_state.loop_last_selected_part = 1;
    global.timeline_state.loop_last_selected_key = "";
    global.timeline_state.loop_last_selected_nav_idx = -1;
    global.timeline_state.loop_boundary_refinement = {
        enabled: false,
        start_part: 1,
        start_measure: -1,
        start_beat: 1,
        start_beat_fraction: 0,
        end_part: 1,
        end_measure: -1,
        end_beat: 1,
        end_beat_fraction: 0
    };
    return true;
}

/// @function gv_loop_sync_boundary_refinement_from_selection()
/// @description Seed loop boundary refinement defaults from current selected measure refs (no UI dependency).
/// @returns {bool} true when refinement was refreshed from a non-empty selection.
/// @reads global.timeline_state.loop_selected_measures, global.timeline_state.loop_boundary_refinement
/// @writes global.timeline_state.loop_boundary_refinement
/// @objects none
/// @callers gv_loop_select_measure, gv_loop_select_measure_range, gv_loop_select_nav_range
function gv_loop_sync_boundary_refinement_from_selection() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;

    var refs = gv_loop_get_selected_measure_refs();
    if (!is_array(refs) || array_length(refs) <= 0) {
        global.timeline_state.loop_boundary_refinement = {
            enabled: false,
            start_part: 1,
            start_measure: -1,
            start_beat: 1,
            start_beat_fraction: 0,
            end_part: 1,
            end_measure: -1,
            end_beat: 1,
            end_beat_fraction: 0
        };
        return false;
    }

    var first_ref = refs[0];
    var last_ref = refs[array_length(refs) - 1];
    if (!is_struct(first_ref) || !is_struct(last_ref)) return false;

    var start_part = max(1, floor(real(first_ref[$ "part"] ?? 1)));
    var start_measure = floor(real(first_ref[$ "measure"] ?? -1));
    var start_beat = 1;
    var start_frac = 0;

    var end_part = max(1, floor(real(last_ref[$ "part"] ?? 1)));
    var end_measure = max(1, floor(real(last_ref[$ "measure"] ?? 1)));
    var end_beat = gv_loop_get_measure_beat_count(end_part, end_measure);
    var end_frac = 0;

    var previous_refine = (variable_struct_exists(global.timeline_state, "loop_boundary_refinement")
        && is_struct(global.timeline_state.loop_boundary_refinement))
        ? global.timeline_state.loop_boundary_refinement
        : { enabled: false };

    // Resolve baseline boundaries without refinement influence, then mirror those
    // endpoints into the refinement payload used by future UI controls.
    var tmp_refine = previous_refine;
    tmp_refine[$ "enabled"] = false;
    global.timeline_state.loop_boundary_refinement = tmp_refine;

    var boundary_ctx = gv_loop_resolve_boundary_endpoints(refs);
    if (is_struct(boundary_ctx) && bool(boundary_ctx[$ "valid"] ?? false)) {
        var sb = boundary_ctx[$ "start_boundary"];
        var eb = boundary_ctx[$ "end_boundary"];
        if (is_struct(sb)) {
            start_part = max(1, floor(real(sb[$ "part"] ?? start_part)));
            start_measure = floor(real(sb[$ "measure"] ?? start_measure));
            start_beat = max(1, floor(real(sb[$ "beat"] ?? start_beat)));
            start_frac = real(sb[$ "beat_fraction"] ?? start_frac);
        }
        if (is_struct(eb)) {
            end_part = max(1, floor(real(eb[$ "part"] ?? end_part)));
            end_measure = floor(real(eb[$ "measure"] ?? end_measure));
            end_beat = max(1, floor(real(eb[$ "beat"] ?? end_beat)));
            end_frac = real(eb[$ "beat_fraction"] ?? end_frac);
        }
    }

    if (start_measure < 1) start_measure = 1;
    if (end_measure < 1) end_measure = start_measure + 1;

    global.timeline_state.loop_boundary_refinement = {
        enabled: true,
        start_part: start_part,
        start_measure: start_measure,
        start_beat: start_beat,
        start_beat_fraction: start_frac,
        end_part: end_part,
        end_measure: end_measure,
        end_beat: end_beat,
        end_beat_fraction: end_frac
    };
    return true;
}

/// @function gv_loop_select_measure(_measure, _selected, _part)
/// @description Set the selection state of a single measure for looping.
/// @param {real} _measure   Measure number (1-based).
/// @param {bool} _selected  true to select; false to deselect.
/// @param {real} _part  Optional part number (defaults to 1).
/// @param {bool} _sync_defaults  Optional; when true, refresh boundary refinement defaults from selection.
/// @returns {bool}  false if invalid measure or state absent.
/// @reads  global.timeline_state.loop_selected_measures
/// @writes global.timeline_state.loop_selected_measures, global.timeline_state.loop_last_selected_measure, global.timeline_state.loop_boundary_refinement
function gv_loop_select_measure(_measure, _selected, _part = 1, _sync_defaults = true) {
    var m = floor(real(_measure));
    if (m < 1) return false;
    var p = max(1, floor(real(_part)));

    if (!variable_struct_exists(global.timeline_state, "loop_selected_measures")
        || !is_struct(global.timeline_state.loop_selected_measures)) {
        global.timeline_state.loop_selected_measures = {};
    }

    var key = gv_loop_make_selection_key(m, p);
    global.timeline_state.loop_selected_measures[$ key] = (_selected == true);
    // Clear stale legacy key for this measure when writing explicit part-aware state.
    var legacy_key = string(m);
    if (variable_struct_exists(global.timeline_state.loop_selected_measures, legacy_key)) {
        global.timeline_state.loop_selected_measures[$ legacy_key] = false;
    }
    if (_selected) {
        global.timeline_state.loop_last_selected_measure = m;
        global.timeline_state.loop_last_selected_part = p;
        global.timeline_state.loop_last_selected_key = key;
    }
    if (_sync_defaults) {
        gv_loop_sync_boundary_refinement_from_selection();
    }
    return true;
}

/// @function gv_loop_select_measure_range(_m1, _m2, _additive)
/// @description Select (or additively add) all measures between m1 and m2 (inclusive) for looping.
/// @param {real} _m1       Start measure (inclusive).
/// @param {real} _m2       End measure (inclusive).
/// @param {bool} _additive If true, keep existing selections; if false, clear first.
/// @returns {bool}  false if invalid inputs or state absent.
/// @reads  global.timeline_state.loop_selected_measures
/// @writes global.timeline_state.loop_selected_measures, global.timeline_state.loop_last_selected_measure, global.timeline_state.loop_boundary_refinement
function gv_loop_select_measure_range(_m1, _m2, _additive, _part1 = 1, _part2 = 1) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;

    var a = floor(real(_m1));
    var b = floor(real(_m2));
    if (a < 1 || b < 1) return false;
    var p1 = max(1, floor(real(_part1)));
    var p2 = max(1, floor(real(_part2)));
    var lo = min(a, b);
    var hi = max(a, b);

    if (!_additive) {
        gv_loop_clear_selected_measures();
    }

    if (p1 != p2) {
        gv_loop_select_measure(a, true, p1, false);
        gv_loop_select_measure(b, true, p2, false);
        global.timeline_state.loop_last_selected_measure = b;
        global.timeline_state.loop_last_selected_part = p2;
        global.timeline_state.loop_last_selected_key = gv_loop_make_selection_key(b, p2);
        gv_loop_sync_boundary_refinement_from_selection();
        return true;
    }

    for (var m = lo; m <= hi; m++) {
        gv_loop_select_measure(m, true, p1, false);
    }

    global.timeline_state.loop_last_selected_measure = b;
    global.timeline_state.loop_last_selected_part = p1;
    global.timeline_state.loop_last_selected_key = gv_loop_make_selection_key(b, p1);
    gv_loop_sync_boundary_refinement_from_selection();
    return true;
}

/// @function gv_loop_select_nav_range(_nav_idx_a, _nav_idx_b, _additive)
/// @description Select loop tiles by local nav-index span so part-local measure numbering stays unambiguous.
/// @param {real} _nav_idx_a  Start nav index.
/// @param {real} _nav_idx_b  End nav index.
/// @param {bool} _additive  true keeps existing selection.
/// @returns {bool}  false if nav entries unavailable.
function gv_loop_select_nav_range(_nav_idx_a, _nav_idx_b, _additive) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries")
        || !is_array(global.timeline_state.measure_nav_entries)) {
        return false;
    }

    var entries = global.timeline_state.measure_nav_entries;
    var n = array_length(entries);
    if (n <= 0) return false;

    var a = clamp(floor(real(_nav_idx_a)), 0, n - 1);
    var b = clamp(floor(real(_nav_idx_b)), 0, n - 1);
    var lo = min(a, b);
    var hi = max(a, b);

    if (!_additive) {
        gv_loop_clear_selected_measures();
    }

    var selected_any = false;
    for (var i = lo; i <= hi; i++) {
        var e = entries[i];
        if (!is_struct(e)) continue;
        var m = floor(real(e[$ "measure"] ?? -1));
        if (m < 1) continue;
        var p = floor(real(e[$ "part"] ?? 1));
        if (p < 1) p = 1;
        gv_loop_select_measure(m, true, p, false);
        selected_any = true;
    }

    if (selected_any) {
        var end_entry = entries[b];
        if (is_struct(end_entry)) {
            var end_m = floor(real(end_entry[$ "measure"] ?? -1));
            var end_p = max(1, floor(real(end_entry[$ "part"] ?? 1)));
            if (end_m >= 1) {
                global.timeline_state.loop_last_selected_measure = end_m;
                global.timeline_state.loop_last_selected_part = end_p;
                global.timeline_state.loop_last_selected_key = gv_loop_make_selection_key(end_m, end_p);
                global.timeline_state.loop_last_selected_nav_idx = b;
            }
        }
    }

    if (selected_any) {
        gv_loop_sync_boundary_refinement_from_selection();
    }

    return true;
}

/// @function gv_measure_nav_hit_test(_mx, _my)
/// @description Test a screen point against measure-nav tile hitboxes and nav controls (scrollbar, loop controls, segment arrows).
/// @param {real} _mx  Mouse X.
/// @param {real} _my  Mouse Y.
/// @returns {struct|undefined}  Hit result struct (control kind or measure tile identity: measure/part/nav_idx/segment_id/display metadata) or undefined.
/// @reads  global.timeline_state.measure_nav_controls, global.timeline_state.measure_nav_tile_hitboxes
function gv_measure_nav_hit_test(_mx, _my) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return undefined;

    if (variable_struct_exists(global.timeline_state, "measure_nav_controls") && is_struct(global.timeline_state.measure_nav_controls)) {
        var ctrls = global.timeline_state.measure_nav_controls;

        if (variable_struct_exists(ctrls, "scroll_thumb") && is_struct(ctrls.scroll_thumb)) {
            var thumb = ctrls.scroll_thumb;
            if (variable_struct_exists(thumb, "enabled") && thumb.enabled
                && _mx >= real(thumb.x1 ?? -1) && _mx <= real(thumb.x2 ?? -1)
                && _my >= real(thumb.y1 ?? -1) && _my <= real(thumb.y2 ?? -1)) {
                return { kind: "scroll_thumb" };
            }
        }
        if (variable_struct_exists(ctrls, "scroll_track") && is_struct(ctrls.scroll_track)) {
            var track = ctrls.scroll_track;
            if (variable_struct_exists(track, "enabled") && track.enabled
                && _mx >= real(track.x1 ?? -1) && _mx <= real(track.x2 ?? -1)
                && _my >= real(track.y1 ?? -1) && _my <= real(track.y2 ?? -1)) {
                return { kind: "scroll_track" };
            }
        }

        if (variable_struct_exists(ctrls, "up") && is_struct(ctrls.up)) {
            var up = ctrls.up;
            if (_mx >= real(up.x1 ?? -1) && _mx <= real(up.x2 ?? -1)
                && _my >= real(up.y1 ?? -1) && _my <= real(up.y2 ?? -1)
                && variable_struct_exists(up, "enabled") && up.enabled) {
                return { kind: "up" };
            }
        }
        if (variable_struct_exists(ctrls, "down") && is_struct(ctrls.down)) {
            var down = ctrls.down;
            if (_mx >= real(down.x1 ?? -1) && _mx <= real(down.x2 ?? -1)
                && _my >= real(down.y1 ?? -1) && _my <= real(down.y2 ?? -1)
                && variable_struct_exists(down, "enabled") && down.enabled) {
                return { kind: "down" };
            }
        }
        if (variable_struct_exists(ctrls, "left") && is_struct(ctrls.left)) {
            var left = ctrls.left;
            if (_mx >= real(left.x1 ?? -1) && _mx <= real(left.x2 ?? -1)
                && _my >= real(left.y1 ?? -1) && _my <= real(left.y2 ?? -1)) {
                    return { kind: "loop_dec" };
            }
        }
        if (variable_struct_exists(ctrls, "right") && is_struct(ctrls.right)) {
            var right = ctrls.right;
            if (_mx >= real(right.x1 ?? -1) && _mx <= real(right.x2 ?? -1)
                && _my >= real(right.y1 ?? -1) && _my <= real(right.y2 ?? -1)) {
                    return { kind: "loop_inc" };
            }
        }
        if (variable_struct_exists(ctrls, "blank") && is_struct(ctrls.blank)) {
            var blank_ctrl = ctrls.blank;
            if (_mx >= real(blank_ctrl.x1 ?? -1) && _mx <= real(blank_ctrl.x2 ?? -1)
                && _my >= real(blank_ctrl.y1 ?? -1) && _my <= real(blank_ctrl.y2 ?? -1)) {
                    return { kind: "spacer" };
            }
        }
        if (variable_struct_exists(ctrls, "jump") && is_struct(ctrls.jump)) {
            var jump_ctrl = ctrls.jump;
            if (_mx >= real(jump_ctrl.x1 ?? -1) && _mx <= real(jump_ctrl.x2 ?? -1)
                && _my >= real(jump_ctrl.y1 ?? -1) && _my <= real(jump_ctrl.y2 ?? -1)) {
                    return { kind: "jump" };
            }
        }
        if (variable_struct_exists(ctrls, "seg_prev") && is_struct(ctrls.seg_prev)) {
            var sp = ctrls.seg_prev;
            if (variable_struct_exists(sp, "enabled") && sp.enabled
                && _mx >= real(sp.x1 ?? -1) && _mx <= real(sp.x2 ?? -1)
                && _my >= real(sp.y1 ?? -1) && _my <= real(sp.y2 ?? -1)) {
                return { kind: "seg_prev" };
            }
        }
        if (variable_struct_exists(ctrls, "seg_next") && is_struct(ctrls.seg_next)) {
            var sn = ctrls.seg_next;
            if (variable_struct_exists(sn, "enabled") && sn.enabled
                && _mx >= real(sn.x1 ?? -1) && _mx <= real(sn.x2 ?? -1)
                && _my >= real(sn.y1 ?? -1) && _my <= real(sn.y2 ?? -1)) {
                return { kind: "seg_next" };
            }
        }
    }

    if (!variable_struct_exists(global.timeline_state, "measure_nav_tile_hitboxes")
        || !is_array(global.timeline_state.measure_nav_tile_hitboxes)) {
        return undefined;
    }

    var hits = global.timeline_state.measure_nav_tile_hitboxes;
    var n_hits = array_length(hits);
    for (var i = 0; i < n_hits; i++) {
        var h = hits[i];
        if (!is_struct(h)) continue;
        var _hx1 = variable_struct_exists(h, "x1") ? real(h.x1) : -1;
        var _hx2 = variable_struct_exists(h, "x2") ? real(h.x2) : -1;
        var _hy1 = variable_struct_exists(h, "y1") ? real(h.y1) : -1;
        var _hy2 = variable_struct_exists(h, "y2") ? real(h.y2) : -1;
        if (_mx < _hx1 || _mx > _hx2) continue;
        if (_my < _hy1 || _my > _hy2) continue;

        var _measure = variable_struct_exists(h, "measure") ? floor(real(h.measure)) : -1;
        var _part = variable_struct_exists(h, "part") ? max(1, floor(real(h.part))) : 1;
        var _nav_idx = variable_struct_exists(h, "nav_idx") ? floor(real(h.nav_idx)) : -1;
        var _struct_idx = variable_struct_exists(h, "struct_idx") ? floor(real(h.struct_idx)) : -1;
        var _segment_id = variable_struct_exists(h, "segment_id") ? string(h.segment_id) : "";
        var _display_row = variable_struct_exists(h, "display_row") ? floor(real(h.display_row)) : -1;
        var _display_col = variable_struct_exists(h, "display_col") ? floor(real(h.display_col)) : -1;
        var _display_kind = variable_struct_exists(h, "display_kind") ? string(h.display_kind) : "full";

        return {
            kind: "measure",
            measure: _measure,
            part: _part,
            nav_idx: _nav_idx,
            struct_idx: _struct_idx,
            segment_id: _segment_id,
            display_row: _display_row,
            display_col: _display_col,
            display_kind: _display_kind
        };
    }

    return undefined;
}

/// @function gv_review_jump_to_measure(_measure, _part, _nav_idx, _measure_key)
/// @description Jump the review playhead to the start of a specific measure.
/// @param {real} _measure  Target measure number (1-based).
/// @param {real} [_part]  Target part number (default 1).
/// @param {real} [_nav_idx]  Target local nav index (default -1).
/// @param {string} [_measure_key]  Canonical measure key (`part:measure[:nav]`) when available.
/// @returns {bool}  true if jump succeeded.
/// @reads  global.timeline_state.playback_complete, global.timeline_state.measure_nav_entries, global.timeline_state.review_end_ms, global.timeline_state.measure_ms
/// @writes global.timeline_state.review_mode, global.timeline_state.playhead_ms, global.timeline_state.review_measure_offset
function gv_review_jump_to_measure(_measure, _part = 1, _nav_idx = -1, _measure_key = "") {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries") || !is_array(global.timeline_state.measure_nav_entries)) return false;

    var target_measure = floor(real(_measure));
    if (target_measure < 1) return false;
    var target_part = max(1, floor(real(_part)));
    var target_nav_idx = floor(real(_nav_idx));
    var target_measure_key = string(_measure_key);

    if (target_measure_key == "") {
        target_measure_key = string(target_part) + ":" + string(target_measure);
    }

    // Canonical mapping path first.
    var key_with_nav = (target_nav_idx >= 0) ? (target_measure_key + ":" + string(target_nav_idx)) : target_measure_key;
    var target_ms = undefined;
    var win = map_context_to_window(key_with_nav);
    if (!(is_struct(win) && bool(win.found ?? false)) && target_nav_idx >= 0) {
        win = map_context_to_window(target_measure_key);
    }
    if (is_struct(win) && bool(win.found ?? false)) {
        var mapped_start = real(win.start_ms ?? -1);
        if (mapped_start >= 0) target_ms = mapped_start;
    }

    var entries = global.timeline_state.measure_nav_entries;
    if (is_undefined(target_ms)) {
        var n = array_length(entries);
        for (var i = 0; i < n; i++) {
            if (target_nav_idx >= 0 && i != target_nav_idx) continue;
            var e = entries[i];
            if (!is_struct(e)) continue;
            var em = floor(real(e.measure ?? -1));
            var ep = max(1, floor(real(e.part ?? 1)));
            if (em != target_measure) continue;
            if (target_nav_idx < 0 && ep != target_part) continue;
            target_ms = real(e.start_ms ?? 0);
            break;
        }
    }
    if (is_undefined(target_ms)) return false;

    var end_ms = variable_struct_exists(global.timeline_state, "review_end_ms")
        ? max(0, real(global.timeline_state.review_end_ms))
        : gv_get_planned_end_ms();
    target_ms = clamp(target_ms, 0, end_ms);

    var measure_ms = variable_struct_exists(global.timeline_state, "measure_ms")
        ? max(1, real(global.timeline_state.measure_ms))
        : 1000;
    var min_offset = -floor(end_ms / measure_ms);
    var new_offset = (target_ms - end_ms) / measure_ms;

    global.timeline_state.review_mode = true;
    global.timeline_state.playhead_ms = target_ms;
    global.timeline_state.review_measure_offset = clamp(new_offset, min_offset, 0);
    return true;
}

/// @function gv_measure_nav_handle_click(_mx, _my)
/// @description Handle a mouse click on the measure nav panel. Routes to: scrollbar navigation, loop-mode measure selection, or jumping the review playhead to the clicked measure.
/// @param {real} _mx  Mouse X.
/// @param {real} _my  Mouse Y.
/// @returns {bool}  true if click was consumed.
/// @reads  global.timeline_state.playback_complete, global.loop_mode_enabled, global.loop_repeat_total, global.loop_jump_to_selection, global.playback_context, global.current_set
/// @writes global.timeline_state (measure selection, playhead, review state), global.playback_context.active_segment
function gv_measure_nav_handle_click(_mx, _my) {
    var playback_complete = variable_struct_exists(global.timeline_state, "playback_complete")
        && global.timeline_state.playback_complete;
    var loop_mode = gv_loop_mode_enabled();

    var hit = gv_measure_nav_hit_test(_mx, _my);
    if (!is_struct(hit)) return false;

    var kind = string(hit.kind ?? "");
    switch (kind) {
        case "scroll_thumb":
        case "scroll_track":
            if (!variable_struct_exists(global.timeline_state, "measure_nav_controls")
                || !is_struct(global.timeline_state.measure_nav_controls)) {
                return false;
            }
            var _scroll_ctrls = global.timeline_state.measure_nav_controls;
            if (!variable_struct_exists(_scroll_ctrls, "scroll_track")
                || !is_struct(_scroll_ctrls.scroll_track)
                || !variable_struct_exists(_scroll_ctrls, "scroll_thumb")
                || !is_struct(_scroll_ctrls.scroll_thumb)) {
                return false;
            }
            var _track = _scroll_ctrls.scroll_track;
            var _thumb = _scroll_ctrls.scroll_thumb;
            if (!(variable_struct_exists(_track, "enabled") && _track.enabled)) return false;

            var _total_rows = max(0, floor(real(global.timeline_state.measure_nav_total_rows ?? 0)));
            var _view_rows = max(1, floor(real(global.timeline_state.measure_nav_view_rows ?? 1)));
            var _max_scroll = max(0, _total_rows - _view_rows);
            if (_max_scroll <= 0) return false;

            var _track_y1 = real(_track.y1 ?? 0);
            var _track_y2 = real(_track.y2 ?? 0);
            var _thumb_h = max(1, real(_thumb.y2 ?? _track_y1) - real(_thumb.y1 ?? _track_y1));
            var _track_h = max(1, _track_y2 - _track_y1);
            _thumb_h = clamp(_thumb_h, 1, _track_h);
            var _thumb_range = max(1, _track_h - _thumb_h);

            var _thumb_top = clamp(_my - _track_y1 - (_thumb_h * 0.5), 0, _thumb_range);
            var _target_scroll = floor((_thumb_top / _thumb_range) * _max_scroll + 0.5);
            _target_scroll = clamp(_target_scroll, 0, _max_scroll);

            if (_target_scroll == floor(real(global.timeline_state.measure_nav_scroll_row ?? 0))) return false;
            global.timeline_state.measure_nav_scroll_row = _target_scroll;
            return true;
        case "up":
            return gv_measure_nav_scroll_rows(-1);
        case "down":
            return gv_measure_nav_scroll_rows(1);
        case "loop_dec":
            if (!variable_global_exists("loop_repeat_total")) global.loop_repeat_total = 10;
            global.loop_repeat_total = max(1, floor(real(global.loop_repeat_total)) - 1);
            return true;
        case "loop_inc":
            if (!variable_global_exists("loop_repeat_total")) global.loop_repeat_total = 10;
            global.loop_repeat_total = min(128, floor(real(global.loop_repeat_total)) + 1);
            return true;
        case "spacer":
            gv_loop_set_blank_measure_enabled(!gv_loop_blank_measure_enabled());
            return true;
        case "jump":
            if (!variable_global_exists("loop_jump_to_selection")) global.loop_jump_to_selection = false;
            global.loop_jump_to_selection = !global.loop_jump_to_selection;
            if (variable_global_exists("current_set") && is_array(global.current_set)) {
                var _set_i = variable_global_exists("current_set_item_index") ? floor(real(global.current_set_item_index)) : -1;
                if (_set_i >= 0 && _set_i < array_length(global.current_set)) {
                    var _item = global.current_set[_set_i];
                    if (is_struct(_item)) {
                        _item[$ "loop_jump_to_selection"] = global.loop_jump_to_selection;
                        global.current_set[_set_i] = _item;
                    }
                }
            }
            return true;
        case "measure":
            var m = variable_struct_exists(hit, "measure") ? floor(real(hit[$ "measure"])) : -1;
            var p = variable_struct_exists(hit, "part") ? max(1, floor(real(hit[$ "part"]))) : 1;
            var nav_idx = variable_struct_exists(hit, "nav_idx") ? floor(real(hit[$ "nav_idx"])) : -1;
            if (m < 1) return false;

            // score_popup_measure is managed by gv_review_handle_click (on press).
            // This function handles navigation only.

            if (loop_mode) {
                var shift_down = keyboard_check(vk_shift);
                if (shift_down) {
                    var last_nav_idx = variable_struct_exists(global.timeline_state, "loop_last_selected_nav_idx")
                        ? floor(real(global.timeline_state.loop_last_selected_nav_idx))
                        : -1;
                    if (last_nav_idx >= 0 && nav_idx >= 0) {
                        gv_loop_select_nav_range(last_nav_idx, nav_idx, true);
                    } else {
                        gv_loop_select_measure(m, true, p);
                    }
                } else {
                    var _already_selected = gv_loop_measure_is_selected(m, p);
                    var _last_nav_idx = variable_struct_exists(global.timeline_state, "loop_last_selected_nav_idx")
                        ? floor(real(global.timeline_state.loop_last_selected_nav_idx))
                        : -1;
                    if (nav_idx >= 0) {
                        // Two-click range UX: first click sets anchor, second click on a
                        // different tile expands to contiguous range without requiring Shift.
                        if (!_already_selected && _last_nav_idx >= 0 && _last_nav_idx != nav_idx) {
                            gv_loop_select_nav_range(_last_nav_idx, nav_idx, false);
                        } else {
                            gv_loop_select_nav_range(nav_idx, nav_idx, false);
                        }
                    } else {
                        var _last_m = variable_struct_exists(global.timeline_state, "loop_last_selected_measure")
                            ? floor(real(global.timeline_state.loop_last_selected_measure))
                            : -1;
                        var _last_p = variable_struct_exists(global.timeline_state, "loop_last_selected_part")
                            ? max(1, floor(real(global.timeline_state.loop_last_selected_part)))
                            : p;
                        if (!_already_selected && _last_m >= 1 && (_last_m != m || _last_p != p)) {
                            gv_loop_select_measure_range(_last_m, m, false, _last_p, p);
                        } else {
                            gv_loop_select_measure_range(m, m, false, p, p);
                        }
                    }
                }
                return true;
            }

            if (playback_complete) {
                var click_key = string(p) + ":" + string(m);
                if (nav_idx >= 0) click_key += ":" + string(nav_idx);
                return gv_review_jump_to_measure(m, p, nav_idx, click_key);
            }
            return false;
        case "seg_prev":
        case "seg_next":
            if (!variable_global_exists("playback_context") || !is_struct(global.playback_context)) return false;
            var _pc_segs = global.playback_context[$ "segments"];
            var _pc_n = is_array(_pc_segs) ? array_length(_pc_segs) : 0;
            if (_pc_n <= 1) return false;
            var _pc_cur = floor(real(global.playback_context[$ "active_segment"] ?? 0));
            var _pc_new = _pc_cur + ((kind == "seg_prev") ? -1 : 1);
            _pc_new = clamp(_pc_new, 0, _pc_n - 1);
            if (_pc_new == _pc_cur) return false;
            global.playback_context[$ "active_segment"] = _pc_new;
            gv_rebuild_measure_nav_for_segment(_pc_new);
            
            // Restore score sprites from preloaded segment cache.
            gv_restore_score_segment_cache(_pc_new, true);
            var _new_seg = _pc_segs[_pc_new];
            var _seg_filename = string(_new_seg[$ "filename"] ?? "");
            if (_seg_filename != "") scr_score_override_groups_load_for_current_segment(_seg_filename);
            return true;
    }

    return false;
}

/// @function gv_draw_gameviz_structure_panel(_x1, _y1, _x2, _y2)
/// @description Draw the compact gameviz structure overview panel (set name row, part labels) in the given rect.
/// @param {real} _x1  Left edge.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @reads  global.timeline_state.active, global.timeline_state.measure_nav_parts, global.playback_context
/// @writes global.timeline_state.measure_nav_controls
function gv_draw_gameviz_structure_panel(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    var x1 = _x1 + 6;
    var y1 = _y1 + 4;
    var x2 = _x2 - 6;
    var y2 = _y2 - 4;
    if (x2 <= x1 || y2 <= y1) return;

    var panel_h = max(16, y2 - y1);
    var row_y1 = y1;
    var row_y2 = min(y2, row_y1 + panel_h);

    var hitbox_x_bias = variable_global_exists("GV_ANCHOR_RECT_X_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_X_OFFSET)
        : 0;
    var hitbox_y_bias = variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_Y_OFFSET)
        : 0;

    var left_btn_w = 22;
    var right_btn_w = 22;
    var spacer_w = 64;
    var jump_w = 56;
    var control_gap = 6;

    var left_btn_x1 = x1;
    var left_btn_x2 = left_btn_x1 + left_btn_w;
    var jump_x2 = x2;
    var jump_x1 = jump_x2 - jump_w;
    var spacer_x2 = jump_x1 - control_gap;
    var spacer_x1 = spacer_x2 - spacer_w;
    var right_btn_x2 = spacer_x1 - control_gap;
    var right_btn_x1 = right_btn_x2 - right_btn_w;
    var loops_mid_x = (left_btn_x2 + right_btn_x1) * 0.5;

    var loop_count = variable_global_exists("loop_repeat_total") ? max(1, floor(real(global.loop_repeat_total))) : 10;
    var blank_enabled = gv_loop_blank_measure_enabled();
    var jump_enabled = variable_global_exists("loop_jump_to_selection") && global.loop_jump_to_selection;

    if (!variable_struct_exists(global.timeline_state, "measure_nav_controls") || !is_struct(global.timeline_state.measure_nav_controls)) {
        global.timeline_state.measure_nav_controls = {};
    }
    var ctrls = global.timeline_state.measure_nav_controls;
    ctrls.left = {
        x1: left_btn_x1 + hitbox_x_bias,
        y1: row_y1 + hitbox_y_bias,
        x2: left_btn_x2 + hitbox_x_bias,
        y2: row_y2 + hitbox_y_bias,
        enabled: true
    };
    ctrls.right = {
        x1: right_btn_x1 + hitbox_x_bias,
        y1: row_y1 + hitbox_y_bias,
        x2: right_btn_x2 + hitbox_x_bias,
        y2: row_y2 + hitbox_y_bias,
        enabled: true
    };
    ctrls.blank = {
        x1: spacer_x1 + hitbox_x_bias,
        y1: row_y1 + hitbox_y_bias,
        x2: spacer_x2 + hitbox_x_bias,
        y2: row_y2 + hitbox_y_bias,
        enabled: true
    };
    ctrls.jump = {
        x1: jump_x1 + hitbox_x_bias,
        y1: row_y1 + hitbox_y_bias,
        x2: jump_x2 + hitbox_x_bias,
        y2: row_y2 + hitbox_y_bias,
        enabled: true
    };
    global.timeline_state.measure_nav_controls = ctrls;

    draw_set_alpha(0.85);
    draw_set_color(make_color_rgb(78, 78, 84));
    draw_rectangle(left_btn_x1, row_y1, left_btn_x2, row_y2, false);
    draw_rectangle(right_btn_x1, row_y1, right_btn_x2, row_y2, false);

    var spacer_fill_color = blank_enabled ? make_color_rgb(222, 126, 38) : make_color_rgb(64, 64, 70);
    var spacer_fill_alpha = blank_enabled ? 0.92 : 0.85;
    draw_set_alpha(spacer_fill_alpha);
    draw_set_color(spacer_fill_color);
    draw_rectangle(spacer_x1, row_y1, spacer_x2, row_y2, false);

    var jump_fill_color = jump_enabled ? make_color_rgb(90, 140, 88) : make_color_rgb(64, 64, 70);
    var jump_fill_alpha = jump_enabled ? 0.92 : 0.85;
    draw_set_alpha(jump_fill_alpha);
    draw_set_color(jump_fill_color);
    draw_rectangle(jump_x1, row_y1, jump_x2, row_y2, false);
    draw_set_alpha(1);

    draw_set_font(fnt_setting);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_color(c_ltgray);
    draw_text((left_btn_x1 + left_btn_x2) * 0.5, (row_y1 + row_y2) * 0.5, "<");
    draw_text((right_btn_x1 + right_btn_x2) * 0.5, (row_y1 + row_y2) * 0.5, ">");
    draw_text(loops_mid_x, (row_y1 + row_y2) * 0.5, "Loops: " + string(loop_count));
    draw_text_transformed((spacer_x1 + spacer_x2) * 0.5, (row_y1 + row_y2) * 0.5, "Spacer", 0.82, 0.82, 0);
    draw_text_transformed((jump_x1 + jump_x2) * 0.5, (row_y1 + row_y2) * 0.5, "Jump", 0.82, 0.82, 0);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @function gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2)
/// @description Draw the full tune structure grid panel: measure tiles, part labels, post-play scrollbar, loop selection overlays. Pickup rows are projected as first-tile + spacer slots (spacers are intentionally undrawn/unused) and tile hitboxes carry canonical segment/display identity.
/// @param {real} _x1  Left edge.
/// @param {real} _y1  Top edge.
/// @param {real} _x2  Right edge.
/// @param {real} _y2  Bottom edge.
/// @reads  global.timeline_state.*, global.playback_context, global.timeline_cfg
/// @writes global.timeline_state.measure_nav_total_rows, global.timeline_state.measure_nav_view_rows, global.timeline_state.measure_nav_tile_hitboxes, global.timeline_state.measure_nav_controls, global.timeline_state.measure_nav_auto_follow_last_ms
function gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    // Lazy bootstrap in case timeline state was initialized before bind or reset during room transitions.
    // This keeps the panel resilient even if bind timing differs across play flows.
    var _has_entries = variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries)
        && array_length(global.timeline_state.measure_nav_entries) > 0;
    if (!_has_entries) {
        // Use the same source resolution as timeline bind, then flatten
        // active scheduler groups only if primary arrays are unavailable.
        var _source_events = gv_measure_nav_resolve_source_events();

        if (array_length(_source_events) > 0) {
            var _measure_nav = gv_build_measure_nav_map(_source_events);
            gv_measure_nav_apply_to_timeline_state(_measure_nav);
        } else {
            // Last-resort synthetic map so panel navigation remains usable when
            // no source arrays are currently available.
            var _fallback_measure_ms = variable_struct_exists(global.timeline_state, "measure_ms")
                ? max(1, real(global.timeline_state.measure_ms))
                : 1000;
            var _fallback_end_ms = gv_measure_nav_resolve_end_ms_from_state();

            var _synthetic_nav = gv_build_synthetic_measure_nav_map(_fallback_end_ms, _fallback_measure_ms);
            gv_measure_nav_apply_to_timeline_state(_synthetic_nav);
        }

        gv_measure_nav_ensure_state_defaults();
    }

    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries") || !is_array(global.timeline_state.measure_nav_entries)) {
        draw_set_font(fnt_setting);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_color(c_ltgray);
        draw_text(_x1 + 8, _y1 + 8, "Measure map unavailable");
        draw_set_color(c_white);
        return;
    }

    var _panel_source = gv_tune_structure_model_build_panel_entries(global.timeline_state.measure_nav_entries);
    var entries = is_struct(_panel_source) ? (_panel_source.entries ?? global.timeline_state.measure_nav_entries) : global.timeline_state.measure_nav_entries;
    var _entry_source_idx_map = is_struct(_panel_source) ? (_panel_source.source_idx_map ?? []) : [];
    var _panel_used_model = is_struct(_panel_source) && bool(_panel_source.used_model ?? false);
    if (!is_array(_entry_source_idx_map) || array_length(_entry_source_idx_map) != array_length(entries)) {
        _entry_source_idx_map = [];
        for (var _esi = 0; _esi < array_length(entries); _esi++) {
            _entry_source_idx_map[_esi] = _esi;
        }
    }

    var _is_set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _live_loop_runtime = (!_is_set_mode)
        && variable_global_exists("loop_runtime_active")
        && bool(global.loop_runtime_active);
    var _has_loop_review = variable_struct_exists(global.timeline_state, "loop_iteration_scores")
        && is_array(global.timeline_state.loop_iteration_scores)
        && array_length(global.timeline_state.loop_iteration_scores) > 0;
    var _panel_single_tune_loop = (!_is_set_mode) && (_live_loop_runtime || _has_loop_review);

    // Single-tune loop sessions should always render a canonical one-pass structure.
    // Expanding measure_nav_entries by iteration is valid runtime timing data, but it is
    // not a suitable display model for the tune-structure panel.
    if (_panel_single_tune_loop && !_panel_used_model) {
        var _canonical_entries = [];
        var _canonical_source_idx = [];
        var _canonical_seen = {};
        for (var _ci = 0; _ci < array_length(entries); _ci++) {
            var _ce = entries[_ci];
            if (!is_struct(_ce)) continue;
            var _cm = floor(real(_ce[$ "measure"] ?? -1));
            var _cp = max(1, floor(real(_ce[$ "part"] ?? 1)));
            if (_cm < 0) continue;
            var _ckey = string(_cp) + ":" + string(_cm);
            if (variable_struct_exists(_canonical_seen, _ckey)) continue;
            _canonical_seen[$ _ckey] = true;
            array_push(_canonical_entries, _ce);
            array_push(_canonical_source_idx, _ci);
        }
        if (array_length(_canonical_entries) > 0) {
            entries = _canonical_entries;
            _entry_source_idx_map = _canonical_source_idx;
        }
    }
    if (array_length(entries) <= 0) {
        global.timeline_state.measure_nav_tile_hitboxes = [];
        if (!variable_struct_exists(global.timeline_state, "measure_nav_controls") || !is_struct(global.timeline_state.measure_nav_controls)) {
            global.timeline_state.measure_nav_controls = {};
        }
        var _ctrls_empty = global.timeline_state.measure_nav_controls;
        _ctrls_empty.show = false;
        _ctrls_empty.up = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
        _ctrls_empty.down = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
        _ctrls_empty.scroll_track = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
        _ctrls_empty.scroll_thumb = { x1: -1, y1: -1, x2: -1, y2: -1, enabled: false };
        global.timeline_state.measure_nav_controls = _ctrls_empty;
        draw_set_font(fnt_setting);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_color(c_ltgray);
        draw_text(_x1 + 8, _y1 + 8, "No measures found");
        draw_set_color(c_white);
        return;
    }

    draw_set_font(fnt_setting);

    var x1 = _x1 + 6;
    var y1 = _y1 + 6;
    var x2 = _x2 - 6;
    var y2 = _y2 - 6;
    if (x2 <= x1 || y2 <= y1) return;

    // When the panel is rendered into a cached anchor surface, convert any
    // stored hitboxes/controls back to global screen space for click tests.
    var hitbox_x_bias = variable_global_exists("GV_ANCHOR_RECT_X_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_X_OFFSET)
        : 0;
    var hitbox_y_bias = variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_Y_OFFSET)
        : 0;

    // === Segment/tune title strip with optional prev/next arrows ===
    // Default "no arrow" coords (-1 = degenerate box that never hits a screen coordinate).
    var _snav_count  = 0;
    var _snav_active = 0;
    var _snav_title  = "";
    var _snav_prev_x1 = -1; var _snav_prev_y1 = -1; var _snav_prev_x2 = -1; var _snav_prev_y2 = -1;
    var _snav_next_x1 = -1; var _snav_next_y1 = -1; var _snav_next_x2 = -1; var _snav_next_y2 = -1;
    if (variable_global_exists("playback_context") && is_struct(global.playback_context)) {
        var _snav_segs = global.playback_context[$ "segments"];
        _snav_count  = is_array(_snav_segs) ? array_length(_snav_segs) : 0;
        _snav_active = floor(real(global.playback_context[$ "active_segment"] ?? 0));
        _snav_active = clamp(_snav_active, 0, max(0, _snav_count - 1));
        if (_snav_count > 0) {
            var _snav_seg = _snav_segs[_snav_active];
            _snav_title = is_struct(_snav_seg) ? string(_snav_seg[$ "title"] ?? "") : "";
        }
    }
    var _title_strip_h = (_snav_count > 0) ? 20 : 0;
    if (_title_strip_h > 0 && (y2 - y1) > _title_strip_h + 12) {
        var _ts_y1    = y1;
        var _ts_y2    = y1 + _title_strip_h;
        var _ts_mid_y = (_ts_y1 + _ts_y2) * 0.5;
        var _arr_w    = (_snav_count > 1) ? 18 : 0;
        // background
        draw_set_alpha(0.35);
        draw_set_color(make_color_rgb(40, 40, 52));
        draw_rectangle(x1, _ts_y1, x2, _ts_y2 - 1, false);
        draw_set_alpha(1);
        if (_snav_count > 1) {
            _snav_prev_x1 = x1;            _snav_prev_y1 = _ts_y1;
            _snav_prev_x2 = x1 + _arr_w;  _snav_prev_y2 = _ts_y2;
            _snav_next_x1 = x2 - _arr_w;  _snav_next_y1 = _ts_y1;
            _snav_next_x2 = x2;            _snav_next_y2 = _ts_y2;
            // arrow button backgrounds
            draw_set_alpha(0.65);
            draw_set_color(make_color_rgb(60, 60, 74));
            draw_rectangle(_snav_prev_x1, _ts_y1, _snav_prev_x2, _ts_y2 - 1, false);
            draw_rectangle(_snav_next_x1, _ts_y1, _snav_next_x2, _ts_y2 - 1, false);
            draw_set_alpha(1);
            // arrow sprites (spr_arrow_left / spr_arrow_right) scaled to fit the button area
            var _spr_w = sprite_get_width(spr_arrow_left);
            var _spr_h = sprite_get_height(spr_arrow_left);
            var _spr_scale = min(_arr_w / _spr_w, _title_strip_h / _spr_h) * 0.85;
            var _prev_alpha = (_snav_active > 0) ? 0.90 : 0.22;
            var _next_alpha = (_snav_active < _snav_count - 1) ? 0.90 : 0.22;
            draw_sprite_ext(spr_arrow_left,  0,
                (_snav_prev_x1 + _snav_prev_x2) * 0.5 - (_spr_w * _spr_scale * 0.5),
                _ts_mid_y - (_spr_h * _spr_scale * 0.5),
                _spr_scale, _spr_scale, 0, c_white, _prev_alpha);
            draw_sprite_ext(spr_arrow_right, 0,
                (_snav_next_x1 + _snav_next_x2) * 0.5 - (_spr_w * _spr_scale * 0.5),
                _ts_mid_y - (_spr_h * _spr_scale * 0.5),
                _spr_scale, _spr_scale, 0, c_white, _next_alpha);
        }
        // title text (centred in the space between arrows, truncated with "..." if needed)
        var _title_cx = (x1 + x2) * 0.5;
        var _title_max_w = (x2 - x1) - (_arr_w * 2) - 8;
        var _title_str = _snav_title;
        if (string_width(_title_str) > _title_max_w) {
            var _ellipsis = "...";
            var _ew = string_width(_ellipsis);
            while (string_length(_title_str) > 0 && string_width(_title_str) + _ew > _title_max_w) {
                _title_str = string_copy(_title_str, 1, string_length(_title_str) - 1);
            }
            _title_str += _ellipsis;
        }
        draw_set_color(make_color_rgb(220, 215, 190));
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text(_title_cx, _ts_mid_y, _title_str);
        draw_set_color(c_white);
        // push tile content area below the strip (with a small gap)
        y1 = _ts_y2 + 6;
    }

    var cols = 4;
    var col_gap = 4;
    var row_gap = 4;
    var available_w = max(20, x2 - x1 - 8);
    var tile_w = floor((available_w - (col_gap * (cols - 1))) / cols);
    tile_w = min(max(12, tile_w), 54);
    var tile_h = tile_w;
    var content_w = (tile_w * cols) + (col_gap * (cols - 1));
    var content_x1 = floor(((x1 + x2) * 0.5) - (content_w * 0.5));
    content_x1 = clamp(content_x1, x1 + 4, max(x1 + 4, x2 - content_w - 4));
    var row_step = tile_h + row_gap;
    var part_gap_rows = 1;

    // Section grouping: every 2 rows (= 8 measures at 4-wide) is a repeat section,
    // every 4 rows (= 16 measures) is a part (AÃ¢â€ â€™B) boundary.
    var section_rows    = 2;
    var repeat_sep_h    = max(2, floor(tile_h * 0.12));  // space between repeat groups
    var part_sep_h      = max(6, floor(tile_h * 0.30));  // space + line between tune parts

    var y_top = y1 + 2;
    var y_bottom = y2 - 2;
    // view_rows: conservative estimate accounting for separator overhead.
    // Average separator overhead Ã¢â€°Ë† repeat_sep_h / section_rows per row.
    var _avg_sep_per_row = repeat_sep_h / section_rows;
    var view_rows = max(1, floor(((y_bottom - y_top) + row_gap) / (row_step + _avg_sep_per_row)));

    // Tune-structure visual tuning comes from timeline config so appearance can be adjusted centrally.
    var ts_cfg = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) ? global.timeline_cfg : undefined;
    var use_canonical_model_labels = is_struct(ts_cfg)
        && variable_struct_exists(ts_cfg, "use_canonical_tune_structure_model")
        && bool(ts_cfg.use_canonical_tune_structure_model);
    var ts_current_base_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_color"))
        ? ts_cfg.tune_structure_current_base_color
        : make_color_rgb(104, 100, 76);
    var ts_current_base_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_base_alpha), 0, 1)
        : 0.55;
    var ts_current_overlay_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_color"))
        ? ts_cfg.tune_structure_current_overlay_color
        : make_color_rgb(224, 206, 92);
    var ts_current_overlay_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_overlay_alpha), 0, 1)
        : 0.35;
    var ts_played_fill_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_played_fill_color"))
        ? ts_cfg.tune_structure_played_fill_color
        : make_color_rgb(48, 48, 54);
    var ts_played_fill_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_played_fill_alpha"))
        ? clamp(real(ts_cfg.tune_structure_played_fill_alpha), 0, 1)
        : 0.72;
    var ts_border_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_border_color"))
        ? ts_cfg.tune_structure_border_color
        : make_color_rgb(176, 176, 186);
    var ts_border_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_border_alpha"))
        ? clamp(real(ts_cfg.tune_structure_border_alpha), 0, 1)
        : 0.58;
    var ts_current_border_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_color"))
        ? ts_cfg.tune_structure_current_border_color
        : make_color_rgb(255, 230, 96);
    var ts_current_border_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_border_alpha), 0, 1)
        : 1.0;
    var ts_part_sep_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_part_separator_color"))
        ? ts_cfg.tune_structure_part_separator_color
        : make_color_rgb(200, 202, 220);
    var ts_part_sep_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_part_separator_alpha"))
        ? clamp(real(ts_cfg.tune_structure_part_separator_alpha), 0, 1)
        : 0.50;

    var part_order = [];
    if (variable_struct_exists(global.timeline_state, "measure_nav_parts") && is_array(global.timeline_state.measure_nav_parts)) {
        part_order = global.timeline_state.measure_nav_parts;
    }
    if (array_length(part_order) <= 0) {
        var part_seen = {};
        for (var ei = 0; ei < array_length(entries); ei++) {
            var ep = entries[ei];
            if (!is_struct(ep)) continue;
            var part_num = floor(real(ep.part ?? 1));
            if (part_num < 1) part_num = 1;
            var pkey = string(part_num);
            if (!variable_struct_exists(part_seen, pkey)) {
                part_seen[$ pkey] = true;
                array_push(part_order, part_num);
            }
        }
    }

    var part_entries = {};
    var _show_pickup_rows = is_struct(ts_cfg)
        && variable_struct_exists(ts_cfg, "tune_structure_show_pickup_rows")
        && bool(ts_cfg.tune_structure_show_pickup_rows);

    var _ts_append_slot = function(_arr, _entry, _source_idx_abs, _slot_kind) {
        var _slot_cols = 4;
        var _slot_idx = array_length(_arr);
        array_push(_arr, {
            entry: _entry,
            source_idx: _source_idx_abs,
            segment_id: string(is_struct(_entry) ? (_entry.segment_id ?? "") : ""),
            display_row: floor(_slot_idx / _slot_cols),
            display_col: _slot_idx mod _slot_cols,
            display_kind: string(_slot_kind),
            display_label: ""
        });
    };

    for (var pe = 0; pe < array_length(entries); pe++) {
        var e = entries[pe];
        if (!is_struct(e)) continue;
        var _entry_measure_num = floor(real(e.measure ?? -1));
        var _entry_row_kind = string(e.display_row_kind ?? "full_row");
        var _is_pickup_row = (_entry_measure_num < 1) || (_entry_row_kind == "pickup_row");
        if (_is_pickup_row && !_show_pickup_rows) continue;
        var p = floor(real(e.part ?? 1));
        if (p < 1) p = 1;
        var pkey = string(p);
        if (!variable_struct_exists(part_entries, pkey)) {
            part_entries[$ pkey] = [];
        }
        var arr = part_entries[$ pkey];
        var _source_idx_abs = (pe >= 0 && pe < array_length(_entry_source_idx_map))
            ? floor(real(_entry_source_idx_map[pe]))
            : pe;

        if (_is_pickup_row) {
            while ((array_length(arr) mod cols) != 0) {
                _ts_append_slot(arr, e, -1, "spacer");
            }
            _ts_append_slot(arr, e, _source_idx_abs, "pickup");
            while ((array_length(arr) mod cols) != 0) {
                _ts_append_slot(arr, e, -1, "spacer");
            }
        } else {
            _ts_append_slot(arr, e, _source_idx_abs, "full");
        }

        part_entries[$ pkey] = arr;
    }

    var total_rows = 0;
    var n_parts = array_length(part_order);
    var part_idx = 0;
    for (; part_idx < n_parts; part_idx += 1) {
        var pkey2 = string(floor(real(part_order[part_idx])));
        var p_arr = variable_struct_exists(part_entries, pkey2) ? part_entries[$ pkey2] : [];
        var rows_for_part = max(2, ceil(max(1, array_length(p_arr)) / cols));
        total_rows += rows_for_part;
        if (part_idx < n_parts - 1) total_rows += part_gap_rows;
    }

    var max_scroll = max(0, total_rows - view_rows);
    var scroll_row = max(0, floor(real(global.timeline_state.measure_nav_scroll_row ?? 0)));
    scroll_row = clamp(scroll_row, 0, max_scroll);
    global.timeline_state.measure_nav_scroll_row = scroll_row;
    global.timeline_state.measure_nav_total_rows = total_rows;
    global.timeline_state.measure_nav_view_rows = view_rows;

    var playback_complete = variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete;
    var show_scroll_controls = (max_scroll > 0);

    var ctrl_x1 = x1 + 2;
    var ctrl_x2 = x1 + 16;
    var track_y1 = y1 + 2;
    var track_y2 = y2 - 2;
    var track_h = max(1, track_y2 - track_y1);
    var thumb_h = max(14, floor((view_rows / max(1, total_rows)) * track_h));
    thumb_h = clamp(thumb_h, 14, track_h);
    var thumb_range = max(1, track_h - thumb_h);
    var thumb_t = (max_scroll > 0) ? (real(scroll_row) / real(max_scroll)) : 0;
    var thumb_y1 = track_y1 + floor(thumb_t * thumb_range);
    var thumb_y2 = thumb_y1 + thumb_h;

    var ctrl_h = max(8, floor(tile_h * 0.45));
    var up_y1 = y1 + 2;
    var up_y2 = up_y1 + ctrl_h;
    var down_y2 = y2 - 2;
    var down_y1 = down_y2 - ctrl_h;

    var up_enabled = (scroll_row > 0);
    var down_enabled = (scroll_row < max_scroll);

    if (!variable_struct_exists(global.timeline_state, "measure_nav_controls") || !is_struct(global.timeline_state.measure_nav_controls)) {
        global.timeline_state.measure_nav_controls = {};
    }
    var _ctrls = global.timeline_state.measure_nav_controls;
    _ctrls.show = show_scroll_controls;
    _ctrls.up = {
        x1: -1,
        y1: -1,
        x2: -1,
        y2: -1,
        enabled: false
    };
    _ctrls.down = {
        x1: -1,
        y1: -1,
        x2: -1,
        y2: -1,
        enabled: false
    };
    _ctrls.scroll_track = {
        x1: ctrl_x1 + hitbox_x_bias,
        y1: track_y1 + hitbox_y_bias,
        x2: ctrl_x2 + hitbox_x_bias,
        y2: track_y2 + hitbox_y_bias,
        enabled: show_scroll_controls
    };
    _ctrls.scroll_thumb = {
        x1: ctrl_x1 + hitbox_x_bias,
        y1: thumb_y1 + hitbox_y_bias,
        x2: ctrl_x2 + hitbox_x_bias,
        y2: thumb_y2 + hitbox_y_bias,
        enabled: show_scroll_controls && (max_scroll > 0)
    };
    // Segment navigation arrow hitboxes (set during title strip draw above; -1 = no-hit default)
    _ctrls.seg_prev = {
        x1: _snav_prev_x1 + hitbox_x_bias, y1: _snav_prev_y1 + hitbox_y_bias,
        x2: _snav_prev_x2 + hitbox_x_bias, y2: _snav_prev_y2 + hitbox_y_bias,
        enabled: (_snav_count > 1 && _snav_active > 0)
    };
    _ctrls.seg_next = {
        x1: _snav_next_x1 + hitbox_x_bias, y1: _snav_next_y1 + hitbox_y_bias,
        x2: _snav_next_x2 + hitbox_x_bias, y2: _snav_next_y2 + hitbox_y_bias,
        enabled: (_snav_count > 1 && _snav_active < _snav_count - 1)
    };
    global.timeline_state.measure_nav_controls = _ctrls;

    if (show_scroll_controls) {
        draw_set_alpha(0.8);
        draw_set_color(make_color_rgb(58, 58, 64));
        draw_rectangle(ctrl_x1, track_y1, ctrl_x2, track_y2, false);
        draw_set_alpha(0.95);
        draw_set_color(make_color_rgb(166, 166, 176));
        draw_rectangle(ctrl_x1 + 1, thumb_y1, ctrl_x2 - 1, thumb_y2, false);
        draw_set_alpha(1);
    }

    var display_ms = real(global.timeline_state.playhead_ms ?? 0);
    var nav_display_ms = display_ms;
    if (_panel_single_tune_loop && array_length(entries) > 0) {
        var _canon_start_ms = real(entries[0][$ "start_ms"] ?? 0);
        if (_live_loop_runtime
            && variable_struct_exists(global.timeline_state, "loop_session")
            && is_struct(global.timeline_state.loop_session)
            && bool(global.timeline_state.loop_session[$ "active"] ?? false)) {
            var _panel_ls = global.timeline_state.loop_session;
            var _panel_pass = max(1, real(_panel_ls[$ "pass_duration_ms"] ?? 0));
            var _panel_core = max(1, real(_panel_ls[$ "core_pass_duration_ms"] ?? _panel_pass));
            _panel_core = min(_panel_core, _panel_pass);
            var _panel_spacer = bool(_panel_ls[$ "spacer_enabled"] ?? false)
                ? max(0, real(_panel_ls[$ "spacer_duration_ms"] ?? 0))
                : 0;
            var _panel_cycle = _panel_pass + _panel_spacer;
            if (_panel_cycle > 1 && display_ms >= _canon_start_ms) {
                var _panel_dt = display_ms - _canon_start_ms;
                var _panel_mod = _panel_dt mod _panel_cycle;
                if (_panel_mod < 0) _panel_mod += _panel_cycle;
                if (_panel_mod >= _panel_pass) {
                    nav_display_ms = _canon_start_ms + max(0, _panel_core - 0.001);
                } else {
                    if (_panel_mod >= _panel_core) _panel_mod = max(0, _panel_core - 0.001);
                    nav_display_ms = _canon_start_ms + _panel_mod;
                }
            }
        } else if (_has_loop_review
            && variable_struct_exists(global.timeline_state, "review_selected_loop_window")
            && is_struct(global.timeline_state.review_selected_loop_window)) {
            var _review_win = global.timeline_state.review_selected_loop_window;
            var _review_start = real(_review_win[$ "start_ms"] ?? -1);
            var _review_end = real(_review_win[$ "end_ms"] ?? -1);
            if (_review_start >= 0 && _review_end > _review_start + 0.001) {
                var _review_local = clamp(display_ms - _review_start, 0, max(0, _review_end - _review_start - 0.001));
                nav_display_ms = _canon_start_ms + _review_local;
            }
        }
    }
    var current_resolved = gv_resolve_measure_context(nav_display_ms);
    var current_measure = floor(real(current_resolved.measure ?? -1));
    var current_segment_id = string(current_resolved.segment_id ?? "");
    var gameplay_static = variable_global_exists("GV_TUNESTRUCTURE_GAMEPLAY_STATIC")
        && global.GV_TUNESTRUCTURE_GAMEPLAY_STATIC;
    // No forced fallback Ã¢â‚¬â€ current_measure=-1 means pickup/pre-tune phase; no tile highlighted.

    var current_source_idx = -1;
    var current_best_source_idx = -1;
    var _current_entry_n = array_length(entries);
    for (var _cei = 0; _cei < _current_entry_n; _cei++) {
        var _ce = entries[_cei];
        if (!is_struct(_ce)) continue;
        var _cm = floor(real(_ce.measure ?? -1));
        if (_cm < 1) continue;
        var _cs = real(_ce.start_ms ?? 0);
        var _ce_ms = real(_ce.end_ms ?? _cs);

        if (nav_display_ms < _cs) break;

        current_best_source_idx = (_cei >= 0 && _cei < array_length(_entry_source_idx_map))
            ? floor(real(_entry_source_idx_map[_cei]))
            : _cei;
        if (nav_display_ms < _ce_ms) {
            current_source_idx = current_best_source_idx;
            break;
        }
    }
    if (current_source_idx < 0) current_source_idx = current_best_source_idx;

    // During active gameplay the tune-structure panel is intentionally static;
    // the current-measure highlight is composited separately as a lightweight overlay.
    if (!playback_complete && current_measure >= 1 && max_scroll > 0) {
        // Auto-follow uses one source of truth: active local measure-nav entry by playhead time.
        var ags_active_source_idx = current_source_idx;

        var ags_count = 0;
        var ags_target_row = -1;
        if (ags_active_source_idx >= 0) {
            for (var ags_pi = 0; ags_pi < n_parts && ags_target_row < 0; ags_pi++) {
                var ags_pk = string(floor(real(part_order[ags_pi])));
                var ags_pa = variable_struct_exists(part_entries, ags_pk) ? part_entries[$ ags_pk] : [];
                var ags_rp = max(2, ceil(max(1, array_length(ags_pa)) / cols));

                var ags_local_idx = -1;
                var ags_pa_n = array_length(ags_pa);
                for (var ags_ai = 0; ags_ai < ags_pa_n; ags_ai++) {
                    var ags_slot = ags_pa[ags_ai];
                    if (!is_struct(ags_slot)) continue;
                    var ags_src_idx = variable_struct_exists(ags_slot, "source_idx")
                        ? floor(real(ags_slot.source_idx))
                        : -1;
                    if (ags_src_idx == ags_active_source_idx) {
                        ags_local_idx = ags_ai;
                        break;
                    }
                }

                if (ags_local_idx >= 0) {
                    ags_target_row = ags_count + floor(ags_local_idx / cols);
                    break;
                }

                ags_count += ags_rp;
                if (ags_pi < n_parts - 1) ags_count += part_gap_rows;
            }
        }
        if (ags_target_row >= 0) {
            var follow_mode = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_follow_mode"))
                ? string_lower(string(ts_cfg.tune_structure_follow_mode))
                : "paged";
            var use_paged_follow = (follow_mode == "paged" || follow_mode == "page");
            var desired_scroll = scroll_row;
            var follow_page_rows = 0;

            if (use_paged_follow) {
                var page_rows_cfg = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_page_rows"))
                    ? max(1, floor(real(ts_cfg.tune_structure_page_rows)))
                    : 8;
                var page_rows = clamp(page_rows_cfg, 1, max(1, view_rows));
                follow_page_rows = page_rows;
                desired_scroll = clamp(floor(ags_target_row / page_rows) * page_rows, 0, max_scroll);
            } else {
                var top_margin = clamp(1, 0, max(0, view_rows - 1));
                var bottom_margin = clamp(2, 0, max(0, view_rows - 1));
                var view_top = scroll_row + top_margin;
                var view_bottom = scroll_row + max(0, view_rows - 1 - bottom_margin);

                if (ags_target_row < view_top) {
                    desired_scroll = clamp(ags_target_row - top_margin, 0, max_scroll);
                } else if (ags_target_row > view_bottom) {
                    desired_scroll = clamp(ags_target_row - max(0, view_rows - 1 - bottom_margin), 0, max_scroll);
                }
            }

            if (desired_scroll != scroll_row) {
                var follow_cfg_ms = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_auto_follow_interval_ms"))
                    ? max(0, real(ts_cfg.tune_structure_auto_follow_interval_ms))
                    : 90;
                var follow_cfg_max_rows = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_auto_follow_max_rows_per_step"))
                    ? max(1, floor(real(ts_cfg.tune_structure_auto_follow_max_rows_per_step)))
                    : 1;
                var follow_now_ms = timing_get_engine_now_ms();
                var follow_last_ms = variable_struct_exists(global.timeline_state, "measure_nav_auto_follow_last_ms")
                    ? real(global.timeline_state.measure_nav_auto_follow_last_ms)
                    : -1000000000;

                if ((follow_now_ms - follow_last_ms) >= follow_cfg_ms) {
                    var scroll_before_follow = scroll_row;
                    if (use_paged_follow) {
                        scroll_row = desired_scroll;
                    } else {
                        var row_delta = desired_scroll - scroll_row;
                        var clamped_delta = clamp(row_delta, -follow_cfg_max_rows, follow_cfg_max_rows);
                        scroll_row = clamp(scroll_row + clamped_delta, 0, max_scroll);
                    }
                    global.timeline_state.measure_nav_scroll_row = scroll_row;
                    global.timeline_state.measure_nav_auto_follow_last_ms = follow_now_ms;
                    if (scroll_row != scroll_before_follow) {
                        gv_log_measure_nav_page_turn(
                            display_ms,
                            current_measure,
                            scroll_before_follow,
                            scroll_row,
                            ags_target_row,
                            view_rows,
                            follow_page_rows,
                            follow_mode
                        );
                    }
                }
            }
        }
    }

    var tile_hits = [];
    var pickup_by_part = (variable_struct_exists(global.timeline_state, "measure_nav_pickup_by_part") && is_struct(global.timeline_state.measure_nav_pickup_by_part))
        ? global.timeline_state.measure_nav_pickup_by_part
        : {};

    // Pre-compute separator base offsets for the current scroll position.
    // _sep_base_n and _sep_base_part_n are the accumulated separator counts before scroll_row,
    // used to make every row_y relative to y_top.
    var _sep_base_n      = floor(scroll_row / section_rows);
    var _sep_base_part_n = floor(scroll_row / (section_rows * 2));
    var section_label_x = content_x1 - 8;

    var global_row_cursor = 0;
    for (var pidx = 0; pidx < n_parts; pidx++) {
        var part_num2 = floor(real(part_order[pidx]));
        var part_key2 = string(part_num2);
        var rows_part_entries = variable_struct_exists(part_entries, part_key2) ? part_entries[$ part_key2] : [];
        var rows_for_part2 = max(2, ceil(max(1, array_length(rows_part_entries)) / cols));

        for (var r = 0; r < rows_for_part2; r++) {
            var abs_row    = global_row_cursor + r;
            var screen_row = abs_row - scroll_row;
            if (screen_row < -1 || screen_row > view_rows + 1) continue;

            // Separator-aware y: each section boundary adds repeat_sep_h,
            // each part boundary adds (part_sep_h - repeat_sep_h) on top of that.
            var _sep_n      = floor(abs_row / section_rows);
            var _sep_part_n = floor(abs_row / (section_rows * 2));
            var row_y = y_top
                + (screen_row * row_step)
                + (_sep_n - _sep_base_n) * repeat_sep_h
                + (_sep_part_n - _sep_base_part_n) * (part_sep_h - repeat_sep_h);
            if (row_y + tile_h > y_bottom + row_gap) continue;
            if (row_y + tile_h <= y_top) continue;

            // Draw a thin centered line at part boundaries (every section_rows*2 rows).
            if (abs_row > 0 && (abs_row mod (section_rows * 2)) == 0) {
                var _line_y = row_y - floor(part_sep_h * 0.55);
                if (_line_y > y_top && _line_y < y_bottom) {
                    var _line_cx = (content_x1 + x2) * 0.5;
                    var _line_hw = tile_w;  // half-width = 1 tile Ã¢â€ â€™ total line = 2 tiles wide
                    draw_set_alpha(ts_part_sep_alpha);
                    draw_set_color(ts_part_sep_color);
                    draw_line(_line_cx - _line_hw, _line_y, _line_cx + _line_hw, _line_y);
                    draw_set_alpha(1);
                }
            }

            var _section_start_idx = (r * cols);
            var _section_end_idx = min(array_length(rows_part_entries), _section_start_idx + cols);
            var _section_slot = undefined;
            for (var _ss = _section_start_idx; _ss < _section_end_idx; _ss++) {
                var _cand = rows_part_entries[_ss];
                if (!is_struct(_cand)) continue;
                if (string(_cand.display_kind ?? "full") == "spacer") continue;
                if (!variable_struct_exists(_cand, "entry") || !is_struct(_cand.entry)) continue;
                _section_slot = _cand;
                break;
            }
            if (is_struct(_section_slot)) {
                var _section_entry = variable_struct_exists(_section_slot, "entry") ? _section_slot[$ "entry"] : undefined;
                var _section_measure = is_struct(_section_entry)
                    ? floor(real(_section_entry[$ "measure"] ?? -1))
                    : -1;
                var _section_measure_display = _section_measure;
                if (use_canonical_model_labels && variable_struct_exists(_section_slot, "source_idx")) {
                    var _section_source_idx = floor(real(_section_slot[$ "source_idx"] ?? -1));
                    _section_measure_display = gv_tune_structure_model_resolve_musical_measure_for_nav_idx(_section_source_idx, _section_measure);
                }

                // Label by musical section starts (1, 9, 17, 25, ...) so
                // inserted pickup rows do not shift repeat/part labels.
                var _is_section_start_label = (_section_measure_display >= 1)
                    && (((_section_measure_display - 1) mod 8) == 0);
                if (_is_section_start_label) {
                    draw_set_alpha(0.95);
                    draw_set_color(make_color_rgb(188, 190, 205));
                    draw_set_halign(fa_right);
                    draw_set_valign(fa_middle);
                    draw_text_transformed(section_label_x, row_y + (tile_h * 0.5), string(_section_measure_display), 0.68, 0.68, 0);
                    draw_set_alpha(1);
                }
            }

            for (var c = 0; c < cols; c++) {
                var idx = (r * cols) + c;
                if (idx >= array_length(rows_part_entries)) continue;

                var slot = rows_part_entries[idx];
                if (!is_struct(slot) || !variable_struct_exists(slot, "entry") || !is_struct(slot.entry)) continue;
                var entry = slot.entry;
                var slot_kind = string(slot.display_kind ?? "full");
                var slot_segment_id = string(slot.segment_id ?? string(entry.segment_id ?? ""));
                var is_spacer_slot = (slot_kind == "spacer");
                var source_idx = variable_struct_exists(slot, "source_idx")
                    ? floor(real(slot.source_idx))
                    : -1;

                var tx1 = content_x1 + (c * (tile_w + col_gap));
                var ty1 = row_y;
                var tx2 = tx1 + tile_w;
                var ty2 = ty1 + tile_h;

                if (is_spacer_slot) {
                    // Spacer slots preserve fixed-grid layout for pickup rows but stay visually unused.
                    continue;
                }

                var entry_measure = floor(real(entry.measure ?? -1));
                var entry_end_ms = real(entry.end_ms ?? 0);
                // After playback completes, all measures stay completed regardless of review playhead.
                var is_completed = (!gameplay_static) && (playback_complete || (display_ms >= entry_end_ms));
                var is_current = false;
                if (!gameplay_static && !is_completed) {
                    if (current_segment_id != "" && slot_segment_id != "") {
                        is_current = (slot_segment_id == current_segment_id);
                    } else if (current_source_idx >= 0 && source_idx >= 0) {
                        is_current = (source_idx == current_source_idx);
                    } else {
                        is_current = (entry_measure == current_measure);
                    }
                }
                var entry_part = floor(real(entry.part ?? 1));
                if (entry_part < 1) entry_part = 1;
                var is_loop_selected = (!playback_complete) && gv_loop_measure_is_selected(entry_measure, entry_part);
                var entry_measure_key = string(entry_part) + ":" + string(entry_measure);
                var entry_nav_idx = source_idx;
                var entry_measure_key_nav = (entry_nav_idx >= 0)
                    ? (entry_measure_key + ":" + string(entry_nav_idx))
                    : entry_measure_key;
                var selected_measure_key = variable_struct_exists(global.timeline_state, "score_popup_measure_key")
                    ? string(global.timeline_state.score_popup_measure_key)
                    : "";
                var selected_nav_idx = variable_struct_exists(global.timeline_state, "score_popup_nav_idx")
                    ? floor(real(global.timeline_state.score_popup_nav_idx))
                    : -1;
                var is_score_selected = playback_complete
                    && (selected_measure_key != ""
                        && (selected_measure_key == entry_measure_key_nav
                            || (selected_nav_idx < 0 && selected_measure_key == entry_measure_key)));

                var loop_base_color = make_color_rgb(120, 78, 28);
                var loop_overlay_color = make_color_rgb(234, 148, 42);
                var loop_border_color = make_color_rgb(255, 176, 64);

                // Tile draw: unplayed=outline only, completed=dark fill, current=yellow highlight, score_selected=blue
                if (is_loop_selected) {
                    draw_set_alpha(ts_current_base_alpha);
                    draw_set_color(loop_base_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                    draw_set_alpha(ts_current_overlay_alpha);
                    draw_set_color(loop_overlay_color);
                    draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);
                } else if (is_current) {
                    // Current measure: warm dark base + yellow tint overlay
                    draw_set_alpha(ts_current_base_alpha);
                    draw_set_color(ts_current_base_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                    draw_set_alpha(ts_current_overlay_alpha);
                    draw_set_color(ts_current_overlay_color);
                    draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);
                } else if (is_score_selected) {
                    // Score-selected (post-play): same yellow style as current-measure highlight
                    draw_set_alpha(ts_current_base_alpha);
                    draw_set_color(ts_current_base_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                    draw_set_alpha(ts_current_overlay_alpha);
                    draw_set_color(ts_current_overlay_color);
                    draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);
                } else if (is_completed) {
                    // Played: dark semi-transparent fill (spr_cell_dark style)
                    var completed_fill_color = ts_played_fill_color;
                    var completed_fill_alpha = ts_played_fill_alpha;
                    var scoring_style_idx = asset_get_index("scoring_get_measure_visual_style");
                    if (script_exists(scoring_style_idx)) {
                        var completed_style = script_execute(scoring_style_idx,
                            entry_measure,
                            ts_played_fill_color,
                            ts_played_fill_alpha,
                            entry_part,
                            source_idx,
                            string(entry_part) + ":" + string(entry_measure));
                        if (is_struct(completed_style) && (completed_style.has_score ?? false)) {
                            completed_fill_color = completed_style.color;
                            completed_fill_alpha = completed_style.alpha;
                        }
                    }
                    draw_set_alpha(completed_fill_alpha);
                    draw_set_color(completed_fill_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                }

                var border_color = is_loop_selected
                    ? loop_border_color
                    : ((is_current || is_score_selected) ? ts_current_border_color : ts_border_color);
                var border_alpha = (is_loop_selected || is_current || is_score_selected) ? ts_current_border_alpha : ts_border_alpha;
                var border_width = 3;
                draw_set_alpha(border_alpha);
                draw_set_color(border_color);
                draw_line_width(tx1, ty1, tx2, ty1, border_width);
                draw_line_width(tx2, ty1, tx2, ty2, border_width);
                draw_line_width(tx2, ty2, tx1, ty2, border_width);
                draw_line_width(tx1, ty2, tx1, ty1, border_width);

                draw_set_alpha(1);

                array_push(tile_hits, {
                    measure: entry_measure,
                    part: entry_part,
                    nav_idx: source_idx,
                    segment_id: slot_segment_id,
                    display_row: floor(real(slot.display_row ?? -1)),
                    display_col: floor(real(slot.display_col ?? -1)),
                    display_kind: slot_kind,
                    x1: tx1 + hitbox_x_bias,
                    y1: ty1 + hitbox_y_bias,
                    x2: tx2 + hitbox_x_bias,
                    y2: ty2 + hitbox_y_bias
                });
            }
        }

        global_row_cursor += rows_for_part2;
        if (pidx < n_parts - 1) global_row_cursor += part_gap_rows;
    }

    // Diagnostic visibility fallback: if normal layout yields zero visible
    // tiles, draw a compact grid so click/hitbox behavior can still be tested.
    if (array_length(tile_hits) <= 0 && array_length(entries) > 0) {
        var fb_cols = 4;
        var fb_gap = 4;
        var fb_w = 30;
        var fb_h = 18;
        var fb_x = _x1 + 8;
        var fb_y = _y1 + 22;
        var fb_n = min(array_length(entries), 12);

        for (var f = 0; f < fb_n; f++) {
            var fr = floor(f / fb_cols);
            var fc = f mod fb_cols;

            var fx1 = fb_x + (fc * (fb_w + fb_gap));
            var fy1 = fb_y + (fr * (fb_h + fb_gap));
            var fx2 = fx1 + fb_w;
            var fy2 = fy1 + fb_h;

            var fe = entries[f];
            var fm = (is_struct(fe) && variable_struct_exists(fe, "measure"))
                ? floor(real(fe.measure))
                : (f + 1);
            var fm_display = fm;
            if (use_canonical_model_labels) {
                fm_display = gv_tune_structure_model_resolve_musical_measure_for_nav_idx(f, fm);
            }

            draw_set_alpha(0.92);
            draw_set_color(make_color_rgb(80, 80, 88));
            draw_rectangle(fx1, fy1, fx2, fy2, false);
            draw_set_alpha(0.9);
            draw_set_color(make_color_rgb(180, 180, 190));
            draw_rectangle(fx1, fy1, fx2, fy2, true);
            draw_set_alpha(1);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((fx1 + fx2) * 0.5, (fy1 + fy2) * 0.5, "M" + string(fm_display));

            array_push(tile_hits, {
                measure: fm,
                nav_idx: -1,
                x1: fx1 + hitbox_x_bias,
                y1: fy1 + hitbox_y_bias,
                x2: fx2 + hitbox_x_bias,
                y2: fy2 + hitbox_y_bias
            });
        }
    }

    global.timeline_state.measure_nav_tile_hitboxes = tile_hits;

    draw_set_alpha(1);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @function gv_draw_tune_structure_current_overlay_to_surface(_sx, _sy, _ex, _ey, _current_measure_override)
/// @description Draw the current-measure highlight overlay into an already-active surface. Used by the surface-cache render path.
/// @param {real} _sx  Surface left edge (world-space offset).
/// @param {real} _sy  Surface top edge.
/// @param {real} _ex  Surface right edge.
/// @param {real} _ey  Surface bottom edge.
/// @param {real} _current_measure_override  Measure number to highlight (must be >= 1).
/// @reads  global.timeline_state.measure_nav_tile_hitboxes, global.timeline_cfg, global.GV_ANCHOR_RECT_X_OFFSET, global.GV_ANCHOR_RECT_Y_OFFSET
function gv_draw_tune_structure_current_overlay_to_surface(_sx, _sy, _ex, _ey, _current_measure_override) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_tile_hitboxes") || !is_array(global.timeline_state.measure_nav_tile_hitboxes)) return;

    var current_measure = (_current_measure_override >= 1) ? _current_measure_override : -1;
    if (current_measure < 1) return;

    var ts_cfg = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) ? global.timeline_cfg : undefined;
    var ts_current_base_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_color"))
        ? ts_cfg.tune_structure_current_base_color
        : make_color_rgb(104, 100, 76);
    var ts_current_base_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_base_alpha), 0, 1)
        : 0.55;
    var ts_current_overlay_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_color"))
        ? ts_cfg.tune_structure_current_overlay_color
        : make_color_rgb(224, 206, 92);
    var ts_current_overlay_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_overlay_alpha), 0, 1)
        : 0.35;
    var ts_current_border_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_color"))
        ? ts_cfg.tune_structure_current_border_color
        : make_color_rgb(255, 230, 96);
    var ts_current_border_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_border_alpha), 0, 1)
        : 1.0;

    var hits = global.timeline_state.measure_nav_tile_hitboxes;
    var _overlay_resolved = gv_resolve_measure_context(real(global.timeline_state.playhead_ms ?? 0));
    var current_segment_id = string(_overlay_resolved.segment_id ?? "");
    var current_nav_idx = variable_struct_exists(global.timeline_state, "measure_highlight_last_nav_idx")
        ? floor(real(global.timeline_state.measure_highlight_last_nav_idx))
        : -1;
    for (var i = 0; i < array_length(hits); i++) {
        var hit = hits[i];
        if (!is_struct(hit)) continue;
        var hit_segment_id = string(hit.segment_id ?? "");
        var hit_nav_idx = variable_struct_exists(hit, "nav_idx")
            ? floor(real(hit.nav_idx))
            : -1;
        if (current_segment_id != "" && hit_segment_id != "") {
            if (hit_segment_id != current_segment_id) continue;
        } else if (current_nav_idx >= 0) {
            if (hit_nav_idx != current_nav_idx) continue;
        } else {
            if (floor(real(hit.measure ?? -1)) != current_measure) continue;
        }

        // Hitbox is in screen coords, but we're drawing to surface coords (0-based).
        // Account for any offset stored during main panel render.
        var _offset_x = variable_global_exists("GV_ANCHOR_RECT_X_OFFSET") ? real(global.GV_ANCHOR_RECT_X_OFFSET) : 0;
        var _offset_y = variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET") ? real(global.GV_ANCHOR_RECT_Y_OFFSET) : 0;
        
        var tx1 = real(hit.x1 ?? 0) + _offset_x;
        var ty1 = real(hit.y1 ?? 0) + _offset_y;
        var tx2 = real(hit.x2 ?? tx1) + _offset_x;
        var ty2 = real(hit.y2 ?? ty1) + _offset_y;

        draw_set_alpha(ts_current_base_alpha);
        draw_set_color(ts_current_base_color);
        draw_rectangle(tx1, ty1, tx2, ty2, false);
        draw_set_alpha(ts_current_overlay_alpha);
        draw_set_color(ts_current_overlay_color);
        draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);

        draw_set_alpha(ts_current_border_alpha);
        draw_set_color(ts_current_border_color);
        draw_line_width(tx1, ty1, tx2, ty1, 3);
        draw_line_width(tx2, ty1, tx2, ty2, 3);
        draw_line_width(tx2, ty2, tx1, ty2, 3);
        draw_line_width(tx1, ty2, tx1, ty1, 3);
        draw_set_alpha(1);
        return;
    }
}

/// @function gv_draw_tune_structure_current_overlay()
/// @description Draw the current-measure highlight on the tune structure panel in world space. Guards for live vs. review mode and resolves the anchor rect from RoomUI.
/// @reads  global.timeline_state.active, global.timeline_state.playback_complete, global.timeline_state.measure_nav_tile_hitboxes, global.timeline_state.playhead_ms, global.timeline_cfg
function gv_draw_tune_structure_current_overlay() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return;
    if (variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete) return;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_tile_hitboxes") || !is_array(global.timeline_state.measure_nav_tile_hitboxes)) return;

    var display_ms = real(global.timeline_state.playhead_ms ?? 0);
    var current_resolved = gv_resolve_measure_context(display_ms);
    var current_measure = floor(real(current_resolved.measure ?? -1));
    var current_nav_idx = floor(real(current_resolved.nav_idx ?? -1));
    var current_segment_id = string(current_resolved.segment_id ?? "");
    if (current_measure < 1) return;

    var ts_cfg = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) ? global.timeline_cfg : undefined;
    var ts_current_base_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_color"))
        ? ts_cfg.tune_structure_current_base_color
        : make_color_rgb(104, 100, 76);
    var ts_current_base_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_base_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_base_alpha), 0, 1)
        : 0.55;
    var ts_current_overlay_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_color"))
        ? ts_cfg.tune_structure_current_overlay_color
        : make_color_rgb(224, 206, 92);
    var ts_current_overlay_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_overlay_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_overlay_alpha), 0, 1)
        : 0.35;
    var ts_current_border_color = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_color"))
        ? ts_cfg.tune_structure_current_border_color
        : make_color_rgb(255, 230, 96);
    var ts_current_border_alpha = (is_struct(ts_cfg) && variable_struct_exists(ts_cfg, "tune_structure_current_border_alpha"))
        ? clamp(real(ts_cfg.tune_structure_current_border_alpha), 0, 1)
        : 1.0;

    var hits = global.timeline_state.measure_nav_tile_hitboxes;
    for (var i = 0; i < array_length(hits); i++) {
        var hit = hits[i];
        if (!is_struct(hit)) continue;
        var hit_segment_id = string(hit.segment_id ?? "");
        var hit_nav_idx = variable_struct_exists(hit, "nav_idx") ? floor(real(hit.nav_idx)) : -1;
        if (current_segment_id != "" && hit_segment_id != "") {
            if (hit_segment_id != current_segment_id) continue;
        } else if (current_nav_idx >= 0) {
            if (hit_nav_idx != current_nav_idx) continue;
        } else {
            if (floor(real(hit.measure ?? -1)) != current_measure) continue;
        }

        var tx1 = real(hit.x1 ?? 0);
        var ty1 = real(hit.y1 ?? 0);
        var tx2 = real(hit.x2 ?? tx1);
        var ty2 = real(hit.y2 ?? ty1);

        draw_set_alpha(ts_current_base_alpha);
        draw_set_color(ts_current_base_color);
        draw_rectangle(tx1, ty1, tx2, ty2, false);
        draw_set_alpha(ts_current_overlay_alpha);
        draw_set_color(ts_current_overlay_color);
        draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);

        draw_set_alpha(ts_current_border_alpha);
        draw_set_color(ts_current_border_color);
        draw_line_width(tx1, ty1, tx2, ty1, 3);
        draw_line_width(tx2, ty1, tx2, ty2, 3);
        draw_line_width(tx2, ty2, tx1, ty2, 3);
        draw_line_width(tx1, ty2, tx1, ty1, 3);
        draw_set_alpha(1);
        return;
    }
}

/// @function gv_review_handle_click(_mx, _my)
/// @description Handle a click anywhere in the post-play review canvas: routes to scoring popup close, judge row selection, or measure jump in the structure panel.
/// @param {real} _mx/_my  Mouse coordinates.
/// @returns {bool}  true if the click was consumed.
/// @reads  global.timeline_state.playback_complete/measure_nav_entries/score_popup_measure_key/score_popup_nav_idx
/// @writes global.timeline_state.score_selected_judge/score_popup_measure_key/score_popup_nav_idx/score_popup_measure/playhead_ms
function gv_review_handle_click(_mx, _my) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    // Toggle score-selection here (on press, fires once via mouse_check_button_pressed).
    // Intercept same-measure clicks to deselect â€” skip the jump in that case.
    var _hit_pre = gv_measure_nav_hit_test(_mx, _my);
    if (is_struct(_hit_pre) && string(variable_struct_exists(_hit_pre, "kind") ? _hit_pre[$ "kind"] : "") == "measure") {
        var _m_pre = variable_struct_exists(_hit_pre, "measure") ? floor(real(_hit_pre[$ "measure"])) : -1;
        var _p_pre = variable_struct_exists(_hit_pre, "part") ? max(1, floor(real(_hit_pre[$ "part"]))) : 1;
        var _n_pre = variable_struct_exists(_hit_pre, "nav_idx") ? floor(real(_hit_pre[$ "nav_idx"])) : -1;
        var _key_pre = (_m_pre >= 1) ? (string(_p_pre) + ":" + string(_m_pre)) : "";
        var _key_nav_pre = (_n_pre >= 0 && _key_pre != "")
            ? (_key_pre + ":" + string(_n_pre))
            : _key_pre;
        if (_m_pre >= 1) {
            var _prev_nav = variable_struct_exists(global.timeline_state, "score_popup_nav_idx")
                ? floor(real(global.timeline_state.score_popup_nav_idx))
                : -1;
            var _prev_key = variable_struct_exists(global.timeline_state, "score_popup_measure_key")
                ? string(global.timeline_state.score_popup_measure_key)
                : "";
            if (!variable_struct_exists(global.timeline_state, "score_selected_judge")) {
                var _default_judge = (variable_global_exists("judge_settings_store")
                    && is_struct(global.judge_settings_store)
                    && variable_struct_exists(global.judge_settings_store, "selected_judge_id"))
                    ? string(global.judge_settings_store.selected_judge_id)
                    : "ms_overlap";
                if (_default_judge == "") _default_judge = "ms_overlap";
                global.timeline_state.score_selected_judge = _default_judge;
            }
            if ((_prev_key != ""
                    && (_prev_key == _key_nav_pre
                    || (_prev_nav < 0 && _prev_key == _key_pre)))) {
                gv_scoring_set_selected_measure_key("", -1); // deselect â€” whole-tune view
                return true; // don't also jump
            } else {
                gv_scoring_set_selected_measure_key(_key_nav_pre, _n_pre); // select new
                if (gv_review_jump_to_measure(_m_pre, _p_pre, _n_pre, _key_nav_pre)) {
                    gv_sync_now_line_display();
                    return true;
                }

                // Click was on a valid measure tile; consume even if jump target is unavailable.
                return true;
            }
        }
    }

    if (gv_measure_nav_handle_click(_mx, _my)) return true;

    var nb_rect = gv_get_anchor_rect_by_name("notebeam_canvas_anchor");
    if (is_struct(nb_rect)) {
        if (gv_handle_notebeam_click(
            _mx,
            _my,
            real(nb_rect.x1 ?? 0),
            real(nb_rect.y1 ?? 0),
            real(nb_rect.x2 ?? 0),
            real(nb_rect.y2 ?? 0)
        )) {
            return true;
        }
    }

    if (!variable_struct_exists(global.timeline_state, "review_buttons") || !is_array(global.timeline_state.review_buttons)) return false;

    var buttons = global.timeline_state.review_buttons;
    var n = array_length(buttons);
    for (var i = 0; i < n; i++) {
        var b = buttons[i];
        if (!is_struct(b)) continue;

        var enabled = variable_struct_exists(b, "enabled") && b.enabled;
        if (!enabled) continue;

        var x1 = real(b.x1 ?? 0);
        var y1 = real(b.y1 ?? 0);
        var x2 = real(b.x2 ?? 0);
        var y2 = real(b.y2 ?? 0);
        if (_mx < x1 || _mx > x2 || _my < y1 || _my > y2) continue;

        var step = real(b.delta_measures ?? 0);
        return gv_review_nudge_measures(step);
    }

    return false;
}

/// @function gv_notebeam_note_label(_span)
/// @description Return the display label for a span (note letter preferred, then midi_to_letter, then raw MIDI number).
/// @param {struct} _span  Span struct with note_letter, note_canonical, or note_midi.
/// @returns {string}  Display label, or "?" if unknown.
function gv_notebeam_note_label(_span) {
    if (!is_struct(_span)) return "?";

    var label = string(_span.note_letter ?? "");
    if (string_length(label) > 0 && label != "?") return label;

    if (variable_struct_exists(_span, "note_canonical")) {
        label = chanter_canonical_to_display(string(_span.note_canonical));
        if (string_length(label) > 0 && label != "?") return label;
    }

    if (variable_struct_exists(_span, "note_midi")) {
        var channel = real(_span.channel ?? -1);
        label = midi_to_letter(real(_span.note_midi), channel);
        if (string_length(label) > 0 && label != "?") return label;
        return gv_note_label_from_midi(real(_span.note_midi));
    }

    return "?";
}

/// @function gv_find_best_planned_overlap(_planned_spans, _player_span)
/// @description Find the planned span with the greatest time overlap with a given player span on the same lane.
/// @param {array}  _planned_spans  Planned-span array from timeline_state.
/// @param {struct} _player_span    Player span struct with start_ms, end_ms, note fields.
/// @returns {struct|undefined}  Best-match planned span or undefined.
function gv_find_best_planned_overlap(_planned_spans, _player_span) {
    if (!is_array(_planned_spans) || !is_struct(_player_span)) return undefined;

    var player_start = real(_player_span.start_ms ?? 0);
    var player_end = max(player_start, real(_player_span.end_ms ?? player_start));
    var player_lane = gv_note_to_lane_index(_player_span.note_canonical ?? "", _player_span.note_midi ?? -1, _player_span.channel ?? -1);
    if (player_lane < 0) return undefined;

    var best_span = undefined;
    var best_overlap = 0;
    var n = array_length(_planned_spans);
    for (var i = 0; i < n; i++) {
        var planned = _planned_spans[i];
        if (!is_struct(planned)) continue;

        var planned_lane = gv_note_to_lane_index(planned.note_canonical ?? "", planned.note_midi ?? -1, planned.channel ?? -1);
        if (planned_lane != player_lane) continue;

        var planned_start = real(planned.start_ms ?? 0);
        var planned_end = max(planned_start, real(planned.end_ms ?? planned_start));
        var overlap_ms = min(player_end, planned_end) - max(player_start, planned_start);
        if (overlap_ms <= 0) continue;

        if (is_undefined(best_span) || overlap_ms > best_overlap) {
            best_span = planned;
            best_overlap = overlap_ms;
        }
    }

    return best_span;
}

/// @function gv_handle_notebeam_click(_mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle a click on the notebeam canvas: checks scoring panel first, then player-span hitboxes, showing or hiding the note popup.
/// @param {real} _mx  Mouse X.
/// @param {real} _my  Mouse Y.
/// @param {real} _x1  Canvas left edge.
/// @param {real} _y1  Canvas top edge.
/// @param {real} _x2  Canvas right edge.
/// @param {real} _y2  Canvas bottom edge.
/// @returns {bool}  true if click was consumed.
/// @reads  global.timeline_state.playback_complete, global.timeline_state.notebeam_player_hitboxes, global.timeline_state.planned_spans
/// @writes global.timeline_state.notebeam_note_popup
function gv_handle_notebeam_click(_mx, _my, _x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    if (gv_handle_notebeam_scoring_panel_click(_mx, _my, _x1, _y1, _x2, _y2)) {
        return true;
    }

    if (!variable_struct_exists(global.timeline_state, "notebeam_player_hitboxes")
        || !is_array(global.timeline_state.notebeam_player_hitboxes)) {
        global.timeline_state.notebeam_player_hitboxes = [];
    }

    var hits = global.timeline_state.notebeam_player_hitboxes;
    var n_hits = array_length(hits);
    for (var i = 0; i < n_hits; i++) {
        var hit = hits[i];
        if (!is_struct(hit)) continue;

        var hx1 = real(hit.x1 ?? 0);
        var hy1 = real(hit.y1 ?? 0);
        var hx2 = real(hit.x2 ?? 0);
        var hy2 = real(hit.y2 ?? 0);
        if (_mx < hx1 || _mx > hx2 || _my < hy1 || _my > hy2) continue;

        var player_span = hit.player_span;
        if (!is_struct(player_span)) break;

        var player_span_index = variable_struct_exists(hit, "player_span_index")
            ? floor(real(hit.player_span_index))
            : -1;

        var planned_span = undefined;
        if (!is_struct(planned_span)
            && variable_struct_exists(global.timeline_state, "planned_spans")
            && is_array(global.timeline_state.planned_spans)) {
            planned_span = gv_find_best_planned_overlap(global.timeline_state.planned_spans, player_span);
        }

        var hit_cx = (hx1 + hx2) * 0.5;
        var hit_cy = (hy1 + hy2) * 0.5;

        global.timeline_state.notebeam_note_popup = {
            visible: true,
            anchor_x: hit_cx,
            anchor_y: hit_cy,
            player_span: player_span,
            planned_span: planned_span,
            player_span_index: player_span_index,
            matched_source_kind: "",
            matched_target_event_id: "",
            matched_target_span_index: -1
        };
        return true;
    }

    global.timeline_state.notebeam_note_popup = { visible: false };
    return false;
}

/// @function gv_handle_notebeam_scoring_panel_click(_mx, _my, _x1, _y1, _x2, _y2)
/// @description Handle a click within the notebeam scoring panel: routes to perf popup close/consume when active, otherwise close-button, detail popup, and judge row selection.
/// @returns {bool}  true if click consumed.
/// @reads  global.timeline_state.playback_complete, global.timeline_state.score_detail_popup, global.timeline_state.score_judge_row_hitboxes, global.timeline_state.perf_summary_popup
/// @writes global.timeline_state.score_detail_popup, global.timeline_state.score_selected_judge, global.timeline_state.perf_summary_popup
function gv_handle_notebeam_scoring_panel_click(_mx, _my, _x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    if (gv_perf_summary_popup_visible()) {
        var perf_popup_state = global.timeline_state.perf_summary_popup;
        var perf_popup_rect = gv_perf_summary_struct_get(perf_popup_state, "popup_rect", []);
        var perf_close_rect = gv_perf_summary_struct_get(perf_popup_state, "close_rect", []);
        if (gv_gameviz_point_in_rect(_mx, _my, perf_close_rect)) {
            global.timeline_state.perf_summary_popup = { visible: false };
            return true;
        }
        if (gv_gameviz_point_in_rect(_mx, _my, perf_popup_rect)) {
            return true;
        }

        var perf_layout = gv_notebeam_scoring_panel_get_layout(_x1, _y1, _x2, _y2);
        if (gv_gameviz_point_in_rect(_mx, _my, perf_layout.panel_rect)) {
            global.timeline_state.perf_summary_popup = { visible: false };
            return true;
        }
        return false;
    }

    if (!variable_struct_exists(global.timeline_state, "score_detail_popup") || !is_struct(global.timeline_state.score_detail_popup)) {
        global.timeline_state.score_detail_popup = { visible: false };
    }

    var popup_state = global.timeline_state.score_detail_popup;
    var popup_visible = variable_struct_exists(popup_state, "visible") && popup_state.visible;
    if (popup_visible) {
        var popup_rect = variable_struct_exists(popup_state, "popup_rect") ? variable_struct_get(popup_state, "popup_rect") : [];
        var close_rect = variable_struct_exists(popup_state, "close_rect") ? variable_struct_get(popup_state, "close_rect") : [];

        if (gv_gameviz_point_in_rect(_mx, _my, close_rect)) {
            global.timeline_state.score_detail_popup = { visible: false };
            return true;
        }

        if (gv_gameviz_point_in_rect(_mx, _my, popup_rect)) {
            return true;
        }
    }

    var layout = gv_notebeam_scoring_panel_get_layout(_x1, _y1, _x2, _y2);
    var panel_rect = layout.panel_rect;
    if (!gv_gameviz_point_in_rect(_mx, _my, panel_rect)) {
        if (popup_visible) {
            global.timeline_state.score_detail_popup = { visible: false };
            return true;
        }
        return false;
    }

    var row_hitboxes = variable_struct_exists(global.timeline_state, "score_judge_row_hitboxes")
        ? global.timeline_state.score_judge_row_hitboxes
        : [];
    if (!is_array(row_hitboxes)) row_hitboxes = [];

    for (var i = 0; i < array_length(row_hitboxes); i++) {
        var row = row_hitboxes[i];
        if (!is_struct(row)) continue;

        var rect = [
            real(variable_struct_exists(row, "x1") ? variable_struct_get(row, "x1") : 0),
            real(variable_struct_exists(row, "y1") ? variable_struct_get(row, "y1") : 0),
            real(variable_struct_exists(row, "x2") ? variable_struct_get(row, "x2") : 0),
            real(variable_struct_exists(row, "y2") ? variable_struct_get(row, "y2") : 0)
        ];
        if (!gv_gameviz_point_in_rect(_mx, _my, rect)) continue;

        var judge_id = string(variable_struct_exists(row, "judge_id") ? variable_struct_get(row, "judge_id") : "ms_overlap");
        if (judge_id == "") judge_id = "ms_overlap";
        global.timeline_state.score_selected_judge = judge_id;
        if (variable_global_exists("judge_settings_store") && is_struct(global.judge_settings_store)) {
            global.judge_settings_store.selected_judge_id = judge_id;
        }
        var _save_settings_idx = asset_get_index("scoring_judge_settings_save_for_player");
        if (script_exists(_save_settings_idx)) {
            script_execute(_save_settings_idx);
        }
        global.timeline_state.score_detail_popup = {
            visible: true,
            judge_id: judge_id
        };
        return true;
    }

    return true;
}

/// @function gv_draw_notebeam_note_popup(_canvas_x1, _canvas_y1, _canvas_x2, _canvas_y2)
/// @description Draw the note-detail popup floating near a clicked player span, showing note label, timing delta, planned span info.
/// @param {real} _canvas_x1  Left edge of notebeam canvas.
/// @param {real} _canvas_y1  Top edge.
/// @param {real} _canvas_x2  Right edge.
/// @param {real} _canvas_y2  Bottom edge.
/// @reads  global.timeline_state.notebeam_note_popup, global.GV_ANCHOR_RECT_X_OFFSET, global.GV_ANCHOR_RECT_Y_OFFSET
function gv_draw_notebeam_note_popup(_canvas_x1, _canvas_y1, _canvas_x2, _canvas_y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(global.timeline_state, "notebeam_note_popup") || !is_struct(global.timeline_state.notebeam_note_popup)) return;

    var popup = global.timeline_state.notebeam_note_popup;
    if (!variable_struct_exists(popup, "visible") || !popup.visible) return;

    var player_span = popup.player_span;
    if (!is_struct(player_span)) return;

    var planned_span = variable_struct_exists(popup, "planned_span") ? popup.planned_span : undefined;
    var player_label = gv_notebeam_note_label(player_span);
    var player_start = floor(real(player_span.start_ms ?? 0));
    var player_end = floor(real(player_span.end_ms ?? player_start));
    var player_duration = max(0, player_end - player_start);

    var popup_player_span_index = variable_struct_exists(popup, "player_span_index")
        ? floor(real(popup.player_span_index))
        : -1;
    var popup_target_span_index = variable_struct_exists(popup, "matched_target_span_index")
        ? floor(real(popup.matched_target_span_index))
        : -1;
    var player_source_event_id = variable_struct_exists(player_span, "source_event_id")
        ? string(player_span.source_event_id)
        : "";
    var score_summary = gv_scoring_call_script("scoring_get_note_popup_score_summary", player_span, planned_span, "", popup_player_span_index);
    var score_line = "judge score: -";
    var judge_line = "judge: -";
    var detail_line = "";
    if (is_struct(score_summary)) {
        judge_line = "judge: " + string(variable_struct_exists(score_summary, "judge_name") ? variable_struct_get(score_summary, "judge_name") : "-");
        score_line = "judge score: " + string(variable_struct_exists(score_summary, "score_text") ? variable_struct_get(score_summary, "score_text") : "-")
            + " (" + string(variable_struct_exists(score_summary, "grade") ? variable_struct_get(score_summary, "grade") : "-") + ")";
        detail_line = string(variable_struct_exists(score_summary, "detail_text") ? variable_struct_get(score_summary, "detail_text") : "");
    }

    var line1 = "intended note: none";
    var line2 = "status: no intended overlap";
    var line3 = score_line;
    var line4 = judge_line;
    var line5 = "player dur.: " + string(player_duration) + " ms";
    var line6 = "intended dur.: --";
    var line7 = "intended s/e: --";
    var line8 = "player s/e: " + string(player_start) + " / " + string(player_end);
    var line9 = "planned id: --";
    var line10 = "played id: --";
    var matched_source_kind = variable_struct_exists(popup, "matched_source_kind")
        ? string(popup.matched_source_kind)
        : "";
    var has_planned = is_struct(planned_span);
    if (has_planned) {
        var planned_label = gv_notebeam_note_label(planned_span);
        var planned_event_id = variable_struct_exists(planned_span, "event_id")
            ? string(variable_struct_get(planned_span, "event_id"))
            : "";
        var planned_global_span_index = variable_struct_exists(planned_span, "global_span_index")
            ? floor(real(variable_struct_get(planned_span, "global_span_index")))
            : popup_target_span_index;
        var planned_start = floor(real(variable_struct_exists(planned_span, "start_ms") ? variable_struct_get(planned_span, "start_ms") : 0));
        var planned_end = floor(real(variable_struct_exists(planned_span, "end_ms") ? variable_struct_get(planned_span, "end_ms") : planned_start));
        var planned_duration = max(0, planned_end - planned_start);
        line1 = "intended note: " + planned_label + " (player " + player_label + ")";
        line2 = "status: overlaps intended";
        line5 = "player dur.: " + string(player_duration) + " ms";
        line6 = "intended dur.: " + string(planned_duration) + " ms";
        line7 = "intended s/e: " + string(planned_start) + " / " + string(planned_end);
        line8 = "player s/e: " + string(player_start) + " / " + string(player_end);
        line9 = "planned id: "
            + (planned_event_id != "" ? planned_event_id : "--")
            + " | span#"
            + (planned_global_span_index >= 0 ? string(planned_global_span_index) : "--");
    }

    if (!has_planned && (matched_source_kind == "embellishment_unit" || matched_source_kind == "emb_cluster")) {
        line1 = "intended event: embellishment unit";
        line2 = "status: matched embellishment unit";
    }

    if (detail_line != "") {
        line2 = "status: " + detail_line;
    }

    line10 = "played id: "
        + (player_source_event_id != "" ? player_source_event_id : "--")
        + " | span#"
        + (popup_player_span_index >= 0 ? string(popup_player_span_index) : "--");

    draw_set_font(fnt_setting);
    var lines = [line1, line2, line3, line4, line5, line6, line7, line8, line9, line10];
    var text_scale = 0.75;
    var text_w = 0;
    var line_h = max(8, (string_height("Ag") * text_scale) + 2);
    for (var i = 0; i < array_length(lines); i++) {
        text_w = max(text_w, string_width(lines[i]) * text_scale);
    }

    var pad = 12;
    var box_w = text_w + (pad * 2);
    var box_h = (array_length(lines) * line_h) + (pad * 2);
    var anchor_x_global = real(popup.anchor_x ?? ((_canvas_x1 + _canvas_x2) * 0.5));
    var anchor_y_global = real(popup.anchor_y ?? ((_canvas_y1 + _canvas_y2) * 0.5));
    // Popup may render into a local anchor surface; map global anchor to
    // current draw-space via active anchor offsets.
    var anchor_x = anchor_x_global + (variable_global_exists("GV_ANCHOR_RECT_X_OFFSET")
        ? real(global.GV_ANCHOR_RECT_X_OFFSET)
        : 0);
    var anchor_y = anchor_y_global + (variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET")
        ? real(global.GV_ANCHOR_RECT_Y_OFFSET)
        : 0);

    var px1 = anchor_x + 12;
    var py1 = anchor_y - box_h - 12;

    if (py1 < (_canvas_y1 + 4)) {
        py1 = anchor_y + 12;
    }

    px1 = clamp(px1, _canvas_x1 + 4, _canvas_x2 - box_w - 4);
    py1 = clamp(py1, _canvas_y1 + 4, _canvas_y2 - box_h - 4);

    var px2 = px1 + box_w;
    var py2 = py1 + box_h;

    draw_set_alpha(0.94);
    draw_set_color(make_color_rgb(24, 24, 28));
    draw_rectangle(px1, py1, px2, py2, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(210, 210, 216));
    draw_rectangle(px1, py1, px2, py2, true);

    draw_set_color(make_color_rgb(188, 188, 196));
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    for (var li = 0; li < array_length(lines); li++) {
        draw_text_transformed(px1 + pad, py1 + pad + (li * line_h), lines[li], text_scale, text_scale, 0);
    }
}

/// @function gv_refresh_review_history_cache()
/// @description Load recent run summaries from event-history storage matching the current tune/bpm/swing/player settings. Stores results in timeline_state.review_history_*.
/// @returns {array}  Array of history-run summary structs.
/// @reads  global.timeline_state, global.timeline_cfg (notebeam_history_* config fields)
/// @writes global.timeline_state.review_history_runs, global.timeline_state.review_history_loaded, global.timeline_state.review_history_count
function gv_refresh_review_history_cache() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        return array_create(0);
    }

    var history_runs = array_create(0);
    global.timeline_state.review_history_runs = history_runs;
    global.timeline_state.review_history_loaded = false;
    global.timeline_state.review_history_count = 0;

    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
        return history_runs;
    }

    var history_enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_history_enabled")
        || global.timeline_cfg.notebeam_history_enabled;
    if (!history_enabled) {
        global.timeline_state.review_history_loaded = true;
        return history_runs;
    }

    var requested_count = variable_struct_exists(global.timeline_cfg, "notebeam_history_run_count")
        ? max(0, floor(real(global.timeline_cfg.notebeam_history_run_count)))
        : 10;
    if (requested_count <= 0) {
        global.timeline_state.review_history_loaded = true;
        return history_runs;
    }

    var export_info = event_history_get_export_info();
    var require_same_bpm = !variable_struct_exists(global.timeline_cfg, "notebeam_history_require_same_bpm")
        || global.timeline_cfg.notebeam_history_require_same_bpm;
    var require_same_swing = !variable_struct_exists(global.timeline_cfg, "notebeam_history_require_same_swing")
        || global.timeline_cfg.notebeam_history_require_same_swing;

    var export_clean_tune = variable_struct_exists(export_info, "clean_tune") ? string(variable_struct_get(export_info, "clean_tune")) : "";
    var export_bpm = variable_struct_exists(export_info, "bpm") ? real(variable_struct_get(export_info, "bpm")) : 0;
    var export_swing = variable_struct_exists(export_info, "swing") ? string(variable_struct_get(export_info, "swing")) : "";
    var export_player_id = variable_struct_exists(export_info, "player_id") ? string(variable_struct_get(export_info, "player_id")) : "";
    var require_same_player = !variable_struct_exists(global.timeline_cfg, "notebeam_history_require_same_player")
        || global.timeline_cfg.notebeam_history_require_same_player;

    history_runs = event_history_load_recent_summaries(
        export_clean_tune,
        export_bpm,
        export_swing,
        requested_count,
        require_same_bpm,
        require_same_swing,
        export_player_id,
        require_same_player
    );

    global.timeline_state.review_history_runs = history_runs;
    global.timeline_state.review_history_loaded = true;
    global.timeline_state.review_history_count = array_length(history_runs);

    show_debug_message("[REVIEW_HISTORY] loaded=" + string(global.timeline_state.review_history_count)
        + " tune=" + export_clean_tune
        + " bpm=" + string(export_bpm)
        + " swing=" + string(export_swing));

    return history_runs;
}

/// @function gv_get_notebeam_lane_metrics(_lane_idx, _lane_count, _y1, _y2, _lane_h, _using_lane_anchors, _lane_anchor_y, _lane_anchor_h, _beam_width_px, _match_label_width, _match_label_width_scale, _lane_flip, _use_label_lane_layout, _lane_top_spacer_ratio, _lane_top_spacer_px, _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px, _history_use_gap_band)
/// @description Compute center_y, beam_width, and history-band y1/y2 for one note lane. Handles anchor-based and uniform-division layout modes.
/// @param {int}   _lane_idx              Lane index (0=high A, 8=low G).
/// @param {int}   _lane_count            Total number of lanes.
/// @param {real}  _y1                    Canvas top edge.
/// @param {real}  _y2                    Canvas bottom edge.
/// @param {real}  _lane_h                Default uniform lane height.
/// @param {bool}  _using_lane_anchors    True if sprite anchors define lane position.
/// @param {array} _lane_anchor_y         Per-lane anchor center y values.
/// @param {array} _lane_anchor_h         Per-lane anchor height values.
/// @param {real}  _beam_width_px         Default beam pixel width.
/// @param {real}  _match_label_width     (unused in layout; passed for consistency).
/// @param {real}  _match_label_width_scale  (unused in layout).
/// @param {bool}  _lane_flip             Flip lane order vertically.
/// @param {bool}  _use_label_lane_layout Use explicit row-height spacer layout.
/// @param {real}  _lane_top_spacer_ratio Fraction of canvas height to use as top spacer.
/// @param {real}  _lane_top_spacer_px    Fixed px to add to top spacer.
/// @param {real}  _lane_row_height_px    Row height per lane.
/// @param {real}  _lane_row_gap_px       Gap between rows.
/// @param {real}  _lane_y_offset_px      Additional y offset applied to center_y.
/// @param {bool}  _history_use_gap_band  If true, place history band in inter-lane gap.
/// @returns {struct|undefined}  Struct {center_y, beam_width, history_y1, history_y2, history_mid_y} or undefined if lane index invalid.
function gv_get_notebeam_lane_metrics(_lane_idx, _lane_count, _y1, _y2, _lane_h,
    _using_lane_anchors, _lane_anchor_y, _lane_anchor_h,
    _beam_width_px, _match_label_width, _match_label_width_scale,
    _lane_flip, _use_label_lane_layout, _lane_top_spacer_ratio, _lane_top_spacer_px,
    _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px,
    _history_use_gap_band) {
    if (_lane_idx < 0 || _lane_idx >= _lane_count) return undefined;

    var center_y = -1;
    var lane_beam_width = _beam_width_px;
    if (_using_lane_anchors && _lane_anchor_y[_lane_idx] >= 0) {
        center_y = _lane_anchor_y[_lane_idx];
        if (_lane_anchor_h[_lane_idx] > 0) {
            lane_beam_width = _lane_anchor_h[_lane_idx];
        }
    } else {
        var lane_visual_idx = _lane_flip ? (_lane_count - 1 - _lane_idx) : _lane_idx;
        center_y = _y1 + ((lane_visual_idx + 0.5) * _lane_h);
        if (_use_label_lane_layout) {
            var spacer_px = ((_y2 - _y1) * _lane_top_spacer_ratio) + _lane_top_spacer_px;
            center_y = _y1 + spacer_px + _lane_row_gap_px
                + (lane_visual_idx * (_lane_row_height_px + _lane_row_gap_px))
                + (_lane_row_height_px * 0.5);
        }
    }

    center_y += _lane_y_offset_px;
    center_y = clamp(center_y, _y1 + 1, _y2 - 1);

    var lane_half = lane_beam_width * 0.5;
    var lane_top = center_y - lane_half;
    var lane_bottom = center_y + lane_half;
    var history_h = max(1, lane_beam_width * 0.5);
    var history_y1 = center_y + 1;
    var history_y2 = center_y + history_h - 1;

    if (_history_use_gap_band) {
        var nearest_above_bottom = _y1;
        var nearest_below_top = _y2;
        var has_above_neighbor = false;
        var has_below_neighbor = false;

        for (var scan_idx = 0; scan_idx < _lane_count; scan_idx++) {
            if (scan_idx == _lane_idx) continue;

            var other_center_y = -1;
            var other_beam_width = _beam_width_px;
            if (_using_lane_anchors && _lane_anchor_y[scan_idx] >= 0) {
                other_center_y = _lane_anchor_y[scan_idx];
                if (_lane_anchor_h[scan_idx] > 0) {
                    other_beam_width = _lane_anchor_h[scan_idx];
                }
            } else {
                var other_visual_idx = _lane_flip ? (_lane_count - 1 - scan_idx) : scan_idx;
                other_center_y = _y1 + ((other_visual_idx + 0.5) * _lane_h);
                if (_use_label_lane_layout) {
                    var other_spacer_px = ((_y2 - _y1) * _lane_top_spacer_ratio) + _lane_top_spacer_px;
                    other_center_y = _y1 + other_spacer_px + _lane_row_gap_px
                        + (other_visual_idx * (_lane_row_height_px + _lane_row_gap_px))
                        + (_lane_row_height_px * 0.5);
                }
            }

            other_center_y += _lane_y_offset_px;

            var other_half = other_beam_width * 0.5;
            var other_top = other_center_y - other_half;
            var other_bottom = other_center_y + other_half;

            if (other_center_y < center_y) {
                has_above_neighbor = true;
                nearest_above_bottom = max(nearest_above_bottom, other_bottom);
            } else if (other_center_y > center_y) {
                has_below_neighbor = true;
                nearest_below_top = min(nearest_below_top, other_top);
            }
        }

        // If no below neighbor found in the note lanes, look for a spacer anchor
        // placed below the last lane (e.g. label_spacer_anchor_low under low G).
        if (!has_below_neighbor) {
            var low_spacer_rect = gv_get_anchor_rect_by_name("label_spacer_anchor_low");
            if (is_struct(low_spacer_rect)) {
                var spacer_top_y = real(low_spacer_rect.y1);
                if (spacer_top_y > lane_bottom) {
                    has_below_neighbor = true;
                    nearest_below_top = min(nearest_below_top, spacer_top_y);
                }
            }
        }

        // If the spacer anchor is unnamed, unavailable, or its top lands inside the
        // low-G lane because of its own sprite bounds, synthesize the same gap from
        // the label-layout row gap so the bottom lane behaves like the interior lanes.
        if (!has_below_neighbor && _use_label_lane_layout && _lane_row_gap_px > 0) {
            has_below_neighbor = true;
            nearest_below_top = min(nearest_below_top, lane_bottom + _lane_row_gap_px);
        }

        var gap_pad = 2;
        var gap_below_y1 = lane_bottom + gap_pad;
        var gap_below_y2 = nearest_below_top - gap_pad;
        var gap_above_y1 = nearest_above_bottom + gap_pad;
        var gap_above_y2 = lane_top - gap_pad;

        var use_below_gap = has_below_neighbor && (gap_below_y2 > gap_below_y1);
        var use_above_gap = has_above_neighbor && (gap_above_y2 > gap_above_y1);

        if (use_below_gap) {
            history_y1 = gap_below_y1;
            history_y2 = gap_below_y2;
        } else if (use_above_gap) {
            history_y1 = gap_above_y1;
            history_y2 = gap_above_y2;
        }
    }

    history_y1 = clamp(history_y1, _y1 + 1, _y2 - 1);
    history_y2 = clamp(history_y2, _y1 + 1, _y2 - 1);
    if (history_y2 < history_y1) history_y2 = history_y1;

    return {
        center_y: center_y,
        beam_width: lane_beam_width,
        history_y1: history_y1,
        history_y2: history_y2,
        history_mid_y: history_y1 + ((history_y2 - history_y1) * 0.5)
    };
}

/// @function gv_time_to_x(_event_ms, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead)
/// @description Convert a timestamp to an on-screen x pixel position using the notebeam time-to-space mapping.
/// @param {real} _event_ms    The event timestamp in ms.
/// @param {real} _playhead_ms Current playhead timestamp.
/// @param {real} _x1          Left edge of the canvas.
/// @param {real} _x2          Right edge of the canvas.
/// @param {real} _now_ratio   Fraction of canvas width where "now" sits.
/// @param {real} _ms_behind   Time window behind the now-line in ms.
/// @param {real} _ms_ahead    Time window ahead of the now-line in ms.
/// @returns {real}  Screen x coordinate.
function gv_time_to_x(_event_ms, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead) {
    var width = max(1, _x2 - _x1);
    var now_x = _x1 + (width * _now_ratio);
    var left_w = max(1, now_x - _x1);
    var right_w = max(1, _x2 - now_x);

    if (_event_ms <= _playhead_ms) {
        return now_x - ((_playhead_ms - _event_ms) / max(1, _ms_behind)) * left_w;
    } else {
        return now_x + ((_event_ms - _playhead_ms) / max(1, _ms_ahead)) * right_w;
    }
}

/// @function gv_note_label_from_midi(_midi)
/// @description Return a short chromatic note name ("C","C#", ...) for a MIDI note number, ignoring octave.
/// @param {real} _midi  MIDI note number 0â€“127.
/// @returns {string}
function gv_note_label_from_midi(_midi) {
    var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    var idx = clamp(floor(_midi), 0, 127) mod 12;
    return names[idx];
}

/// @function gv_note_to_lane_index(_canonical, _note_midi, _channel)
/// @description Map a note (canonical string or MIDI) to a 0-based chanter lane index (0=high A, 8=low G). Returns -1 for unknown notes.
/// @param {string} _canonical    Canonical note name (may be empty or "?").
/// @param {real}   _note_midi    MIDI note number (fallback lookup).
/// @param {real}   _channel      MIDI channel (used for canonical lookup).
/// @returns {int}  Lane index 0â€“8, or -1.
function gv_note_to_lane_index(_canonical, _note_midi, _channel) {
    var canonical = string(_canonical ?? "");
    if (string_length(canonical) <= 0 || canonical == "?") {
        canonical = chanter_midi_to_canonical(real(_note_midi), global.MIDI_chanter ?? "default", real(_channel));
    }
    if (string_length(canonical) <= 0 || canonical == "?") {
        return -1;
    }

    var display = chanter_canonical_to_display(canonical);
    if (string_length(display) <= 0 || display == "?") {
        return -1;
    }

    var key = string(display);
    if (string_copy(key, 1, 1) == "=") {
        key = string_copy(key, 2, string_length(key) - 1);
    }
    if (string_length(key) > 1) {
        key = string_copy(key, 1, 1);
    }

    switch (key) {
        case "a": return 0;
        case "g": return 1;
        case "f": return 2;
        case "e": return 3;
        case "d": return 4;
        case "c": return 5;
        case "B": return 6;
        case "A": return 7;
        case "G": return 8;
    }

    return -1;
}

/// @function gv_lane_index_to_note_key(_lane_idx)
/// @description Convert a lane index (0â€“8) to a lowercase/uppercase note key string used in anchor lookups.
/// @param {real} _lane_idx  Lane index 0â€“8.
/// @returns {string}  Note key such as "a", "G", etc., or "" if out of range.
function gv_lane_index_to_note_key(_lane_idx) {
    switch (floor(_lane_idx)) {
        case 0: return "a";
        case 1: return "g";
        case 2: return "f";
        case 3: return "e";
        case 4: return "d";
        case 5: return "c";
        case 6: return "B";
        case 7: return "A";
        case 8: return "G";
    }

    return "";
}

/// @function gv_get_notebeam_anchor_name_for_lane(_lane_idx, _lane_flip)
/// @description Build the UI anchor name (e.g., "label_a_anchor") used to look up the sprite-anchor rect for a lane.
/// @param {real} _lane_idx  Lane index 0â€“8.
/// @param {bool} _lane_flip If true, flip lane order before lookup.
/// @returns {string}  Anchor name string, or "" if out of range.
function gv_get_notebeam_anchor_name_for_lane(_lane_idx, _lane_flip = false) {
    var lane_count = 9;
    var idx = floor(_lane_idx);
    if (_lane_flip) {
        idx = (lane_count - 1 - idx);
    }
    if (idx < 0 || idx >= lane_count) return "";

    var note_key = gv_lane_index_to_note_key(idx);
    if (string_length(note_key) <= 0) return "";

    return "label_" + note_key + "_anchor";
}

/// @function gv_player_span_timing_state(_planned_spans, _start_ms, _end_ms, _lane_idx, _slack_ms)
/// @description Classify the timing quality of a player span against planned spans on the same lane: 0=miss, 1=timing-bleed overlap, 2=fully within planned window.
/// @param {array} _planned_spans  Sorted planned-span array from timeline_state.
/// @param {real}  _start_ms       Player span start.
/// @param {real}  _end_ms         Player span end.
/// @param {int}   _lane_idx       Lane index to match.
/// @param {real}  _slack_ms       Allowed tolerance in ms (default 0).
/// @returns {int}  0=miss, 1=bleed, 2=match.
function gv_player_span_timing_state(_planned_spans, _start_ms, _end_ms, _lane_idx, _slack_ms = 0) {
    if (!is_array(_planned_spans)) return 0;

    var a1 = min(real(_start_ms), real(_end_ms));
    var a2 = max(real(_start_ms), real(_end_ms));
    if (a2 <= a1) return 0;

    var slack = max(0, real(_slack_ms));
    var best_state = 0;

    var n = array_length(_planned_spans);
    for (var i = 0; i < n; i++) {
        var ps = _planned_spans[i];
        if (!is_struct(ps)) continue;
        if (!gv_is_tune_focus_channel(real(ps.channel ?? -999))) continue;

        var lane = real(ps.lane_idx ?? -999);
        if (lane == -999) {
            lane = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
        }
        if (lane != _lane_idx) continue;

        var b1 = min(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        var b2 = max(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));

        if (b1 > a2 + slack) break; // planned_spans sorted by time; no later span can overlap
        // Must actually overlap
        if (b2 <= a1 || b1 >= a2) continue;

        // Overlaps - check containment within planned window
        var starts_ok = (a1 >= b1 - slack);
        var ends_ok   = (a2 <= b2 + slack);

        if (starts_ok && ends_ok) {
            return 2;  // perfect - no need to look further
        }
        best_state = 1;  // timing bleed - keep scanning in case another span is exact
    }

    return best_state;
}

/// @function gv_collect_lane_overlap_segments(_planned_spans, _start_ms, _end_ms, _lane_idx)
/// @description Collect sorted, merged overlap segments between a player span and all planned spans on the same lane.
/// @param {array} _planned_spans  Sorted planned-span array.
/// @param {real}  _start_ms       Player span start ms.
/// @param {real}  _end_ms         Player span end ms.
/// @param {int}   _lane_idx       Lane index to query.
/// @returns {array}  Sorted, merged array of {start_ms, end_ms} overlap structs.
function gv_collect_lane_overlap_segments(_planned_spans, _start_ms, _end_ms, _lane_idx) {
    var overlaps = [];
    if (!is_array(_planned_spans)) return overlaps;

    var a1 = min(real(_start_ms), real(_end_ms));
    var a2 = max(real(_start_ms), real(_end_ms));
    if (a2 <= a1) return overlaps;

    var n = array_length(_planned_spans);
    for (var i = 0; i < n; i++) {
        var ps = _planned_spans[i];
        if (!is_struct(ps)) continue;
        if (!gv_is_tune_focus_channel(real(ps.channel ?? -999))) continue;

        var lane = real(ps.lane_idx ?? -999);
        if (lane == -999) {
            lane = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
        }
        if (lane != _lane_idx) continue;

        var b1 = min(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        var b2 = max(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        if (b1 > a2) break; // planned_spans sorted by time; no later span can overlap
        if (b2 <= a1 || b1 >= a2) continue;

        var s = max(a1, b1);
        var e = min(a2, b2);
        if (e <= s) continue;

        array_push(overlaps, { start_ms: s, end_ms: e });
    }

    var n_overlaps = array_length(overlaps);
    if (n_overlaps <= 1) return overlaps;

    // Insertion sort by start_ms
    for (var oi = 1; oi < n_overlaps; oi++) {
        var key_seg = overlaps[oi];
        var oj = oi - 1;
        while (oj >= 0 && real(overlaps[oj].start_ms) > real(key_seg.start_ms)) {
            overlaps[oj + 1] = overlaps[oj];
            oj--;
        }
        overlaps[oj + 1] = key_seg;
    }

    // Merge touching/overlapping segments
    var merged = [];
    var cur_s = real(overlaps[0].start_ms);
    var cur_e = real(overlaps[0].end_ms);

    for (var mi = 1; mi < n_overlaps; mi++) {
        var seg = overlaps[mi];
        var s2 = real(seg.start_ms);
        var e2 = real(seg.end_ms);

        if (s2 <= cur_e) {
            cur_e = max(cur_e, e2);
        } else {
            array_push(merged, { start_ms: cur_s, end_ms: cur_e });
            cur_s = s2;
            cur_e = e2;
        }
    }
    array_push(merged, { start_ms: cur_s, end_ms: cur_e });

    return merged;
}

/// @function gv_draw_split_normal_player_beam(_planned_spans, _start_ms, _end_ms, _lane_idx, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead, _y, _line_width, _match_color, _miss_color, _alpha)
/// @description Draw a player beam split into matched (hit) and unmatched (miss) colored segments using overlap analysis.
/// @param {array} _planned_spans  Sorted planned spans from timeline_state.
/// @param {real}  _start_ms       Player note start ms.
/// @param {real}  _end_ms         Player note end ms.
/// @param {int}   _lane_idx       Lane index.
/// @param {real}  _playhead_ms    Current playhead ms.
/// @param {real}  _x1/_x2         Canvas x bounds.
/// @param {real}  _now_ratio      Fraction of canvas width at "now".
/// @param {real}  _ms_behind/_ms_ahead  Time window extents.
/// @param {real}  _y              Vertical line y position.
/// @param {real}  _line_width     Beam pixel thickness.
/// @param {int}   _match_color    Color for matched segments.
/// @param {int}   _miss_color     Color for unmatched segments.
/// @param {real}  _alpha          Alpha for matched segments (misses get 72%).
function gv_draw_split_normal_player_beam(_planned_spans, _start_ms, _end_ms, _lane_idx,
    _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead,
    _y, _line_width, _match_color, _miss_color, _alpha) {

    var a1 = min(real(_start_ms), real(_end_ms));
    var a2 = max(real(_start_ms), real(_end_ms));
    if (a2 <= a1) return;

    var overlaps = gv_collect_lane_overlap_segments(_planned_spans, a1, a2, _lane_idx);
    var n_overlaps = array_length(overlaps);
    var cursor = a1;
    var miss_alpha = clamp(real(_alpha) * 0.95, 0, 1);

    for (var i = 0; i < n_overlaps; i++) {
        var seg = overlaps[i];
        var s = max(cursor, real(seg.start_ms ?? cursor));
        var e = min(a2, real(seg.end_ms ?? s));
        if (e <= s) continue;

        if (s > cursor) {
            var mx1 = gv_time_to_x(cursor, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
            var mx2 = gv_time_to_x(s, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
            var ml = clamp(min(mx1, mx2), _x1, _x2);
            var mr = clamp(max(mx1, mx2), _x1, _x2);
            if (mr > ml) {
                draw_set_alpha(miss_alpha);
                draw_set_color(_miss_color);
                draw_line_width(ml, _y, mr, _y, _line_width);
            }
        }

        var yx1 = gv_time_to_x(s, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var yx2 = gv_time_to_x(e, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var yl = clamp(min(yx1, yx2), _x1, _x2);
        var yr = clamp(max(yx1, yx2), _x1, _x2);
        if (yr > yl) {
            draw_set_alpha(_alpha);
            draw_set_color(_match_color);
            draw_line_width(yl, _y, yr, _y, _line_width);
        }

        cursor = max(cursor, e);
    }

    if (cursor < a2) {
        var tx1 = gv_time_to_x(cursor, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var tx2 = gv_time_to_x(a2, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var tl = clamp(min(tx1, tx2), _x1, _x2);
        var tr = clamp(max(tx1, tx2), _x1, _x2);
        if (tr > tl) {
            draw_set_alpha(miss_alpha);
            draw_set_color(_miss_color);
            draw_line_width(tl, _y, tr, _y, _line_width);
        }
    }
}

/// @function gv_player_span_classify_and_draw(_planned_spans, _start_ms, _end_ms, _lane_idx, _slack_ms, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead, _y, _line_width, _match_color, _miss_color, _alpha)
/// @description Single-pass classify and draw for a player span: combines gv_player_span_timing_state + gv_draw_split_normal_player_beam. Returns match quality.
/// @param {array} _planned_spans  Sorted planned spans.
/// @param {real}  _start_ms/_end_ms  Player span time bounds.
/// @param {int}   _lane_idx        Lane index.
/// @param {real}  _slack_ms        Timing tolerance ms.
/// @param {real}  _playhead_ms     Current playhead.
/// @param {real}  _x1/_x2          Canvas x bounds.
/// @param {real}  _now_ratio        Position of now-line.
/// @param {real}  _ms_behind/_ms_ahead  Time window.
/// @param {real}  _y               y position for drawing.
/// @param {real}  _line_width      Beam thickness.
/// @param {int}   _match_color/_miss_color  Hit/miss colors.
/// @param {real}  _alpha           Draw alpha.
/// @returns {int}  0=miss, 1=bleed, 2=match.
function gv_player_span_classify_and_draw(
    _planned_spans, _start_ms, _end_ms, _lane_idx, _slack_ms,
    _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead,
    _y, _line_width, _match_color, _miss_color, _alpha) {

    var a1 = min(real(_start_ms), real(_end_ms));
    var a2 = max(real(_start_ms), real(_end_ms));
    var miss_alpha = clamp(real(_alpha) * 0.95, 0, 1);

    if (a2 <= a1 || !is_array(_planned_spans)) {
        var fx1 = gv_time_to_x(a1, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var fx2 = gv_time_to_x(a2, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var fl = clamp(min(fx1, fx2), _x1, _x2);
        var fr = clamp(max(fx1, fx2), _x1, _x2);
        if (fr > fl) {
            draw_set_alpha(miss_alpha);
            draw_set_color(_miss_color);
            draw_line_width(fl, _y, fr, _y, _line_width);
        }
        return 0;
    }

    var slack = max(0, real(_slack_ms));
    var n = array_length(_planned_spans);
    var overlaps = [];
    var best_state = 0;

    // Binary search: skip planned spans whose end is before the player window (minus slack)
    var _bs_lo = 0; var _bs_hi = n; var _bs_thresh = a1 - slack;
    while (_bs_lo < _bs_hi) {
        var _bs_mid = (_bs_lo + _bs_hi) >> 1;
        var _bs_sub = _planned_spans[_bs_mid];
        if (max(real(_bs_sub.start_ms ?? 0), real(_bs_sub.end_ms ?? 0)) < _bs_thresh) _bs_lo = _bs_mid + 1;
        else _bs_hi = _bs_mid;
    }
    for (var i = _bs_lo; i < n; i++) {
        var ps = _planned_spans[i];
        if (!is_struct(ps)) continue;
        if (!gv_is_tune_focus_channel(real(ps.channel ?? -999))) continue;

        var lane = real(ps.lane_idx ?? -999);
        if (lane == -999) {
            lane = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
        }
        if (lane != _lane_idx) continue;

        var b1 = min(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        var b2 = max(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));

        if (b1 > a2 + slack) break; // planned_spans sorted by time; no later span can overlap
        if (b2 <= a1 || b1 >= a2) continue;

        if (best_state < 2) {
            if ((a1 >= b1 - slack) && (a2 <= b2 + slack)) {
                best_state = 2;
            } else {
                best_state = max(best_state, 1);
            }
        }

        var seg_s = max(a1, b1);
        var seg_e = min(a2, b2);
        if (seg_e > seg_s) {
            array_push(overlaps, { start_ms: seg_s, end_ms: seg_e });
        }
    }

    var n_ov = array_length(overlaps);
    if (n_ov > 1) {
        array_sort(overlaps, function(x, y) { return real(x.start_ms) - real(y.start_ms); });
        var merged = [];
        var cs = real(overlaps[0].start_ms);
        var ce = real(overlaps[0].end_ms);
        for (var mi = 1; mi < n_ov; mi++) {
            var ms2 = real(overlaps[mi].start_ms);
            var me2 = real(overlaps[mi].end_ms);
            if (ms2 <= ce) { ce = max(ce, me2); }
            else { array_push(merged, { start_ms: cs, end_ms: ce }); cs = ms2; ce = me2; }
        }
        array_push(merged, { start_ms: cs, end_ms: ce });
        overlaps = merged;
        n_ov = array_length(overlaps);
    }

    var cursor = a1;
    for (var di = 0; di < n_ov; di++) {
        var dseg = overlaps[di];
        var ds = max(cursor, real(dseg.start_ms ?? cursor));
        var de = min(a2, real(dseg.end_ms ?? ds));
        if (de <= ds) continue;

        if (ds > cursor) {
            var mx1 = gv_time_to_x(cursor, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
            var mx2 = gv_time_to_x(ds, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
            var ml = clamp(min(mx1, mx2), _x1, _x2);
            var mr = clamp(max(mx1, mx2), _x1, _x2);
            if (mr > ml) {
                draw_set_alpha(miss_alpha);
                draw_set_color(_miss_color);
                draw_line_width(ml, _y, mr, _y, _line_width);
            }
        }

        var yx1 = gv_time_to_x(ds, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var yx2 = gv_time_to_x(de, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var yl = clamp(min(yx1, yx2), _x1, _x2);
        var yr = clamp(max(yx1, yx2), _x1, _x2);
        if (yr > yl) {
            draw_set_alpha(_alpha);
            draw_set_color(_match_color);
            draw_line_width(yl, _y, yr, _y, _line_width);
        }

        cursor = max(cursor, de);
    }

    if (cursor < a2) {
        var tx1 = gv_time_to_x(cursor, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var tx2 = gv_time_to_x(a2, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var tl = clamp(min(tx1, tx2), _x1, _x2);
        var tr = clamp(max(tx1, tx2), _x1, _x2);
        if (tr > tl) {
            draw_set_alpha(miss_alpha);
            draw_set_color(_miss_color);
            draw_line_width(tl, _y, tr, _y, _line_width);
        }
    }

    return best_state;
}

/// @function gv_compact_note_label(_label)
/// @description Shorten a display note label to a single character: strip leading "=" prefix and truncate to one char.
/// @param {string} _label  Full label string.
/// @returns {string}  Single-character note label.
function gv_compact_note_label(_label) {
    var s = string(_label ?? "");
    if (string_length(s) <= 1) return s;
    if (string_copy(s, 1, 1) == "=") {
        return string_copy(s, 2, 1);
    }
    return string_copy(s, 1, 1);
}

/// @function gv_get_current_planned_measure(_playhead_ms)
/// @description Find the measure number currently active at the given playhead time.
///              In set mode uses global.playback_set_measure_nav_all (flat prebuilt table) so
///              segment transitions cannot cause stale measure values.  Falls back to per-segment
///              measure_nav_entries and then structural_measure_starts for single-tune mode.
/// @param {real} _playhead_ms  Current playhead time in ms.
/// @returns {int}  Measure number (>=1), or -1 if none active (e.g. pickup phase).
/// @reads  global.timeline_state, global.timeline_cfg, global.METRONOME_CONFIG, global.playback_set_measure_nav_all, global.playback_context, global.loop_runtime_active, global.playback_events_active
/// @writes global.timeline_state.measure_highlight_last_measure, global.timeline_state.measure_highlight_last_nav_idx, global.timeline_state.measure_highlight_last_struct_idx, global.timeline_state.current_measure
function gv_get_current_planned_measure(_playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return -1;

    var _query_ms = _playhead_ms;
    // In single-tune loop runtime, tune-structure entries typically represent one loop window.
    // Normalize query time into that loop-cycle so current-measure highlight wraps each iteration.
    var _is_set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _single_tune_loop_runtime = !_is_set_mode
                && variable_global_exists("loop_runtime_active")
                && bool(global.loop_runtime_active);
    var _loop_session_active = false;
    var _loop_session = undefined;
    if (variable_struct_exists(global.timeline_state, "loop_session")
        && is_struct(global.timeline_state.loop_session)) {
        _loop_session = global.timeline_state.loop_session;
        _loop_session_active = variable_struct_exists(_loop_session, "active")
            && bool(variable_struct_get(_loop_session, "active"));
    }
    if (_single_tune_loop_runtime && _loop_session_active) {
        var _ls_start = max(0, real(variable_struct_exists(_loop_session, "start_ms")
            ? variable_struct_get(_loop_session, "start_ms") : 0));
        var _ls_pass_ms = max(1, real(variable_struct_exists(_loop_session, "pass_duration_ms")
            ? variable_struct_get(_loop_session, "pass_duration_ms") : 0));
        var _ls_core_pass_ms = max(1, real(variable_struct_exists(_loop_session, "core_pass_duration_ms")
            ? variable_struct_get(_loop_session, "core_pass_duration_ms") : _ls_pass_ms));
        _ls_core_pass_ms = min(_ls_core_pass_ms, _ls_pass_ms);
        var _ls_spacer_enabled = variable_struct_exists(_loop_session, "spacer_enabled")
            && bool(variable_struct_get(_loop_session, "spacer_enabled"));
        var _ls_spacer_ms = _ls_spacer_enabled
            ? max(0, real(variable_struct_exists(_loop_session, "spacer_duration_ms")
                ? variable_struct_get(_loop_session, "spacer_duration_ms") : 0))
            : 0;
        var _ls_cycle_ms = _ls_pass_ms + _ls_spacer_ms;

        if (_query_ms >= _ls_start && _ls_cycle_ms > 1) {
            var _ls_dt = _query_ms - _ls_start;
            var _ls_mod = _ls_dt mod _ls_cycle_ms;
            if (_ls_mod < 0) _ls_mod += _ls_cycle_ms;

            // Spacer phase has no active measure/highlight identity.
            if (_ls_mod >= _ls_pass_ms) {
                global.timeline_state.measure_highlight_last_measure = -1;
                global.timeline_state.measure_highlight_last_nav_idx = -1;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                global.timeline_state.current_measure = -1;
                return -1;
            }

            // Support-tail portion should keep measure identity pinned to the
            // selected loop range end (no next-measure visual jump).
            if (_ls_mod >= _ls_core_pass_ms) {
                _ls_mod = max(0, _ls_core_pass_ms - 0.001);
            }

            _query_ms = _ls_start + _ls_mod;
        }

        // Layered loop contract: resolve by timeline segments first (time placement),
        // then return identity from segment owner fields.
        if (variable_struct_exists(_loop_session, "timeline_segments")
            && is_array(variable_struct_get(_loop_session, "timeline_segments"))) {
            var _ls_segments = variable_struct_get(_loop_session, "timeline_segments");
            var _seg_hit_measure = -1;
            var _seg_hit_nav_idx = -1;
            var _seg_best_measure = -1;
            var _seg_best_nav_idx = -1;

            for (var _si = 0; _si < array_length(_ls_segments); _si++) {
                var _seg = _ls_segments[_si];
                if (!is_struct(_seg)) continue;
                var _ss = real(variable_struct_exists(_seg, "start_ms") ? variable_struct_get(_seg, "start_ms") : -1);
                var _se = real(variable_struct_exists(_seg, "end_ms") ? variable_struct_get(_seg, "end_ms") : -1);
                if (_ss < 0 || _se <= _ss + 0.001) continue;

                var _sm = floor(real(variable_struct_exists(_seg, "owner_measure")
                    ? variable_struct_get(_seg, "owner_measure")
                    : (variable_struct_exists(_seg, "measure") ? variable_struct_get(_seg, "measure") : -1)));
                var _sn = floor(real(variable_struct_exists(_seg, "nav_idx") ? variable_struct_get(_seg, "nav_idx") : -1));
                if (_sm < 1) continue;

                if (_query_ms >= _ss) {
                    _seg_best_measure = _sm;
                    _seg_best_nav_idx = _sn;
                }
                if (_query_ms >= _ss && _query_ms < _se) {
                    _seg_hit_measure = _sm;
                    _seg_hit_nav_idx = _sn;
                    break;
                }
            }

            if (_seg_hit_measure < 1 && _seg_best_measure >= 1) {
                _seg_hit_measure = _seg_best_measure;
                _seg_hit_nav_idx = _seg_best_nav_idx;
            }

            if (_seg_hit_measure >= 1) {
                global.timeline_state.measure_highlight_last_measure = _seg_hit_measure;
                global.timeline_state.measure_highlight_last_nav_idx = _seg_hit_nav_idx;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                global.timeline_state.current_measure = _seg_hit_measure;
                return _seg_hit_measure;
            }
        }

        // In active loop runtime, selected refs are canonical for current-measure
        // identity. Use them first to avoid drift from global nav-table heuristics.
        if (variable_struct_exists(_loop_session, "selected_refs")
            && is_array(variable_struct_get(_loop_session, "selected_refs"))) {
            var _ls_refs = variable_struct_get(_loop_session, "selected_refs");
            var _ls_measure = -1;
            var _ls_best_measure = -1;
            var _ls_nav_idx = -1;
            var _ls_best_nav_idx = -1;

            for (var _ri = 0; _ri < array_length(_ls_refs); _ri++) {
                var _ref = _ls_refs[_ri];
                if (!is_struct(_ref)) continue;
                var _rs = real(variable_struct_exists(_ref, "start_ms") ? variable_struct_get(_ref, "start_ms") : -1);
                var _re = real(variable_struct_exists(_ref, "end_ms") ? variable_struct_get(_ref, "end_ms") : -1);
                var _rm = floor(real(variable_struct_exists(_ref, "measure") ? variable_struct_get(_ref, "measure") : -1));
                var _rn = floor(real(variable_struct_exists(_ref, "nav_idx") ? variable_struct_get(_ref, "nav_idx") : -1));
                if (_rm < 1 || _rs < 0 || _re <= _rs + 0.001) continue;

                if (_query_ms >= _rs) {
                    _ls_best_measure = _rm;
                    _ls_best_nav_idx = _rn;
                }
                if (_query_ms >= _rs && _query_ms < _re) {
                    _ls_measure = _rm;
                    _ls_nav_idx = _rn;
                    break;
                }
            }

            if (_ls_measure < 1 && _ls_best_measure >= 1) {
                _ls_measure = _ls_best_measure;
                _ls_nav_idx = _ls_best_nav_idx;
            }

            if (_ls_measure >= 1) {
                global.timeline_state.measure_highlight_last_measure = _ls_measure;
                global.timeline_state.measure_highlight_last_nav_idx = _ls_nav_idx;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                global.timeline_state.current_measure = _ls_measure;
                return _ls_measure;
            }
        }
    }

    var _pickup_by_part = (variable_struct_exists(global.timeline_state, "measure_nav_pickup_by_part")
        && is_struct(global.timeline_state.measure_nav_pickup_by_part))
        ? global.timeline_state.measure_nav_pickup_by_part
        : {};

    // Priority 0 (set mode only): prebuilt flat table covering all segments.
    // Using this avoids stale measure numbers during segment transitions because
    // the table never changes at runtime — it was built once at load time with
    // absolute timestamps for every measure across every segment.
    if (_is_set_mode
        && variable_global_exists("playback_set_measure_nav_all")
        && is_array(global.playback_set_measure_nav_all)
        && array_length(global.playback_set_measure_nav_all) > 0) {
        var _fall = global.playback_set_measure_nav_all;
        var _fall_n = array_length(_fall);
        var _fall_best_m = -1;
        var _fall_resolved_m = -1;
        for (var _fi = 0; _fi < _fall_n; _fi++) {
            var _fe = _fall[_fi];
            if (!is_struct(_fe)) continue;
            var _fs = real(_fe.start_ms ?? 0);
            var _fe_end = real(_fe.end_ms ?? _fs);
            var _fm = floor(real(_fe.measure ?? -1));
            if (_query_ms < _fs) break;
            if (_query_ms >= _fs && _query_ms < _fe_end) {
                if (_fm < 1) {
                    global.timeline_state.measure_highlight_last_measure = -1;
                    global.timeline_state.measure_highlight_last_nav_idx = -1;
                    global.timeline_state.measure_highlight_last_struct_idx = -1;
                    global.timeline_state.current_measure = -1;
                    return -1;
                }
                _fall_resolved_m = _fm;
                break;
            }
            if (_fm < 1) continue;
            _fall_best_m = _fm;
        }
        // Check if we are in a pickup window (before the first non-pickup entry).
        if (_fall_resolved_m < 1 && _fall_n > 0 && _query_ms < real(_fall[0].start_ms ?? 0)) {
            // Before the first entry of the whole set — treat as pickup (no highlight).
            global.timeline_state.measure_highlight_last_measure = -1;
            global.timeline_state.measure_highlight_last_nav_idx = -1;
            global.timeline_state.measure_highlight_last_struct_idx = -1;
            global.timeline_state.current_measure = -1;
            return -1;
        }
        if (_fall_resolved_m < 1 && _fall_best_m >= 1) {
            _fall_resolved_m = _fall_best_m;
        }
        if (_fall_resolved_m >= 1) {
            var _local_nav_idx = gv_measure_nav_find_local_idx(_query_ms, _fall_resolved_m);
            if (_local_nav_idx < 0) {
                // Fail closed when set-wide and panel-local nav tables disagree.
                // This prevents writing a cross-namespace index that would break follow/page turn.
                global.timeline_state.measure_highlight_last_measure = -1;
                global.timeline_state.measure_highlight_last_nav_idx = -1;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                global.timeline_state.current_measure = -1;
                return -1;
            }
            global.timeline_state.measure_highlight_last_measure = _fall_resolved_m;
            global.timeline_state.measure_highlight_last_nav_idx = _local_nav_idx;
            global.timeline_state.measure_highlight_last_struct_idx = -1;
            global.timeline_state.current_measure = _fall_resolved_m;
            return _fall_resolved_m;
        }
        // Fall through to per-segment path if flat table returned nothing useful.
    }

    // Priority 1: measure-nav entries (authoritative tile/model source for single-tune and set UI panel).
    if (variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries)
        && array_length(global.timeline_state.measure_nav_entries) > 0) {
        var _entries = global.timeline_state.measure_nav_entries;
        var _best_measure_nav = -1;
        var _best_nav_idx = -1;
        var _resolved_measure_nav = -1;
        var _resolved_nav_idx = -1;
        var _en = array_length(_entries);
        for (var _ei = 0; _ei < _en; _ei++) {
            var _entry = _entries[_ei];
            if (!is_struct(_entry)) continue;
            var _s = real(_entry.start_ms ?? 0);
            var _e = real(_entry.end_ms ?? _s);
            var _m = floor(real(_entry.measure ?? -1));
            if (_m < 1) continue;
            if (_query_ms < _s) break;
            if (_query_ms >= _s && _query_ms < _e) {
                _resolved_measure_nav = _m;
                _resolved_nav_idx = _ei;
                break;
            }
            _best_measure_nav = _m;
            _best_nav_idx = _ei;
        }

        if (_resolved_measure_nav < 1 && _en > 0 && _query_ms < real(_entries[0].start_ms ?? 0)) {
            var _first_part = floor(real(_entries[0].part ?? 1));
            var _first_part_key = string(max(1, _first_part));
            if (variable_struct_exists(_pickup_by_part, _first_part_key) && bool(_pickup_by_part[$ _first_part_key])) {
                global.timeline_state.measure_highlight_last_measure = -1;
                global.timeline_state.measure_highlight_last_nav_idx = -1;
                global.timeline_state.measure_highlight_last_struct_idx = -1;
                global.timeline_state.current_measure = -1;
                return -1;
            }
        }

        if (_resolved_measure_nav < 1 && _best_measure_nav >= 1) {
            _resolved_measure_nav = _best_measure_nav;
            _resolved_nav_idx = _best_nav_idx;
        }

        if (_resolved_measure_nav >= 1) {
            var _hysteresis_ms = 24;
            if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)
                && variable_struct_exists(global.timeline_cfg, "tune_structure_measure_hysteresis_ms")) {
                _hysteresis_ms = max(0, real(global.timeline_cfg.tune_structure_measure_hysteresis_ms));
            }

            var _prev_measure = variable_struct_exists(global.timeline_state, "measure_highlight_last_measure")
                ? floor(real(global.timeline_state.measure_highlight_last_measure))
                : -1;
            var _prev_nav_idx = variable_struct_exists(global.timeline_state, "measure_highlight_last_nav_idx")
                ? floor(real(global.timeline_state.measure_highlight_last_nav_idx))
                : -1;

            if (_hysteresis_ms > 0
                && _prev_measure >= 1
                && _prev_nav_idx >= 0
                && _prev_nav_idx < _en
                && _resolved_nav_idx >= 0
                && _resolved_nav_idx < _en
                && _prev_nav_idx != _resolved_nav_idx
                && abs(_resolved_nav_idx - _prev_nav_idx) == 1) {
                var _boundary_ms = (_resolved_nav_idx > _prev_nav_idx)
                    ? real(_entries[_resolved_nav_idx].start_ms ?? 0)
                    : real(_entries[_prev_nav_idx].start_ms ?? 0);

                if (abs(_query_ms - _boundary_ms) <= _hysteresis_ms) {
                    _resolved_measure_nav = _prev_measure;
                    _resolved_nav_idx = _prev_nav_idx;
                }
            }

            global.timeline_state.measure_highlight_last_measure = _resolved_measure_nav;
            global.timeline_state.measure_highlight_last_nav_idx = _resolved_nav_idx;
            global.timeline_state.measure_highlight_last_struct_idx = -1;
            global.timeline_state.current_measure = _resolved_measure_nav;
            return _resolved_measure_nav;
        }
    }
    
    // Structural path (priority): if structural measure starts exist, use those
    var struct_starts = variable_struct_exists(global.timeline_state, "structural_measure_starts")
        ? global.timeline_state.structural_measure_starts : [];
    if (is_array(struct_starts) && array_length(struct_starts) > 0) {
        var best_measure = -1;
        var best_idx = -1;
        var n_struct = array_length(struct_starts);
        for (var _si = 0; _si < n_struct; _si++) {
            var _start = struct_starts[_si];
            if (!is_struct(_start)) continue;
            var _start_t = real(variable_struct_get(_start, "t"));
            if (_start_t <= _query_ms) {
                best_measure = real(variable_struct_get(_start, "m"));
                best_idx = _si;
            } else {
                break;  // Times are monotonic, stop early
            }
        }
        if (best_measure >= 1) {
            global.timeline_state.measure_highlight_last_measure = best_measure;
            global.timeline_state.measure_highlight_last_nav_idx = -1;
            global.timeline_state.measure_highlight_last_struct_idx = -1;
            return best_measure;
        }
        global.timeline_state.measure_highlight_last_measure = -1;
        global.timeline_state.measure_highlight_last_nav_idx = -1;
        global.timeline_state.measure_highlight_last_struct_idx = -1;
        return -1;  // No measure in structural range yet
    }
    
    // Fallback: scan planned events (original logic)
    var events = gv_get_planned_events_for_viz();
    if (!is_array(events) || array_length(events) <= 0) return -1;

    var skip_metronome = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var met_channel = skip_metronome ? real(global.METRONOME_CONFIG.channel) : -999;

    var best_measure = -1;
    var best_time = -1000000000000;

    var n = array_length(events);
    for (var i = 0; i < n; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;

        var ev_type = variable_struct_exists(ev, "type") ? string(ev.type) : "";
        if (ev_type != "marker" && ev_type != "note_on" && ev_type != "note_off") continue;
        if (variable_struct_exists(ev, "loop_blank_measure") && ev.loop_blank_measure) continue;

        var ch = variable_struct_exists(ev, "channel") ? real(ev.channel) : 0;
        if (skip_metronome && (ev_type == "note_on" || ev_type == "note_off") && ch == met_channel) continue;

        var m = variable_struct_exists(ev, "measure") ? real(ev.measure) : -1;
        if (m < 1) continue;

        var t = gv_evt_time_ms(ev);
        if (t <= _query_ms && t >= best_time) {
            best_time = t;
            best_measure = m;
        }
    }

    if (best_measure >= 1) {
        global.timeline_state.measure_highlight_last_measure = best_measure;
        global.timeline_state.measure_highlight_last_nav_idx = -1;
        global.timeline_state.measure_highlight_last_struct_idx = -1;
        return best_measure;
    }
    global.timeline_state.measure_highlight_last_measure = -1;
    global.timeline_state.measure_highlight_last_nav_idx = -1;
    global.timeline_state.measure_highlight_last_struct_idx = -1;
    return -1;  // No real measure active yet (pickup phase or pre-tune)
}

/// @function gv_get_planned_sequence_for_measure(_measure, _max_notes)
/// @description Build a compact note-sequence string for a given measure number from planned spans, e.g. "{tLG}dE".
/// @param {int}  _measure    Measure number to query.
/// @param {int}  _max_notes  Maximum notes to include before truncating (default 24).
/// @returns {string}  Sequence string, or "" if unavailable.
/// @reads  global.timeline_state.planned_spans, global.timeline_cfg.tune_channel, global.METRONOME_CONFIG
function gv_get_planned_sequence_for_measure(_measure, _max_notes = 24) {
    if (_measure < 1) return "";
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return "";
    if (!variable_struct_exists(global.timeline_state, "planned_spans")) return "";

    var spans = global.timeline_state.planned_spans;
    if (!is_array(spans)) return "";

    var max_notes = max(1, floor(real(_max_notes)));
    var skip_metronome = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var met_channel = skip_metronome ? real(global.METRONOME_CONFIG.channel) : -999;

    var tune_channel = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "tune_channel"))
        ? real(global.timeline_cfg.tune_channel)
        : -1;
    var require_tune_channel = (tune_channel >= 0);

    var seq = "";
    var count = 0;
    var in_emb_group = false;

    var n = array_length(spans);
    for (var i = 0; i < n; i++) {
        var s = spans[i];
        if (!is_struct(s)) continue;

        if (real(s.measure ?? -1) != _measure) continue;

        var ch = real(s.channel ?? 0);
        if (skip_metronome && ch == met_channel) continue;
        if (require_tune_channel && ch != tune_channel) continue;

        var label = variable_struct_exists(s, "note_letter")
            ? string(s.note_letter)
            : midi_to_letter(real(s.note_midi ?? 0), ch);
        if ((label == "?" || string_length(label) <= 0) && variable_struct_exists(s, "note_canonical")) {
            label = chanter_canonical_to_display(string(s.note_canonical));
        }
        if (label == "?" || string_length(label) <= 0) {
            label = gv_note_label_from_midi(real(s.note_midi ?? 0));
        }

        var is_emb = variable_struct_exists(s, "is_embellishment") && s.is_embellishment;
        if (is_emb && !in_emb_group) {
            seq += "{";
            in_emb_group = true;
        }
        if (!is_emb && in_emb_group) {
            seq += "}";
            in_emb_group = false;
        }

        seq += gv_compact_note_label(label);
        count++;
        if (count >= max_notes) {
            if (in_emb_group) {
                seq += "}";
                in_emb_group = false;
            }
            seq += "Ã¢â‚¬Â¦";
            break;
        }
    }

    if (in_emb_group) {
        seq += "}";
    }

    return seq;
}

/// @function gv_draw_planned_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms)
/// @description Draw the planned-note row of the timeline canvas: colored bars + note labels for planned spans in the visible window.
/// @param {real} _rx1/_ry1  Canvas top-left.
/// @param {real} _rx2/_ry2  Canvas bottom-right.
/// @param {real} _playhead_ms  Current playhead position.
/// @reads  global.timeline_state.planned_spans/ms_behind/ms_ahead, global.timeline_cfg.*, global.METRONOME_CONFIG
function gv_draw_planned_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(global.timeline_state, "planned_spans")) return;

    var spans = global.timeline_state.planned_spans;
    if (!is_array(spans)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var bar_color = variable_struct_exists(global.timeline_cfg, "planned_bar_color")
        ? global.timeline_cfg.planned_bar_color
        : c_aqua;
    var bar_alpha = variable_struct_exists(global.timeline_cfg, "planned_bar_alpha")
        ? clamp(real(global.timeline_cfg.planned_bar_alpha), 0, 1)
        : 0.82;
    var melody_text_color = variable_struct_exists(global.timeline_cfg, "planned_melody_text_color")
        ? global.timeline_cfg.planned_melody_text_color
        : c_white;
    var embell_text_color = variable_struct_exists(global.timeline_cfg, "planned_embellishment_text_color")
        ? global.timeline_cfg.planned_embellishment_text_color
        : c_green;
    var label_min_px = variable_struct_exists(global.timeline_cfg, "planned_label_min_px")
        ? max(1, real(global.timeline_cfg.planned_label_min_px))
        : 4;
    var label_full_px = variable_struct_exists(global.timeline_cfg, "planned_label_full_px")
        ? max(label_min_px, real(global.timeline_cfg.planned_label_full_px))
        : 12;
    var note_text_scale = variable_struct_exists(global.timeline_cfg, "planned_note_text_scale")
        ? max(0.5, real(global.timeline_cfg.planned_note_text_scale))
        : 1.15;

    var skip_metronome = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var met_channel = skip_metronome ? real(global.METRONOME_CONFIG.channel) : -999;
    var ghost_parts = gv_use_tune_ghost_parts();
    var ghost_alpha = gv_get_tune_other_parts_alpha();
    var pass_count = ghost_parts ? 2 : 1;

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var n = array_length(spans);
    for (var pass = 0; pass < pass_count; pass++) {
        for (var i = 0; i < n; i++) {
            var s = spans[i];
            if (!is_struct(s)) continue;

            var planned_channel = real(s.channel ?? -999);
            if (skip_metronome && planned_channel == met_channel) continue;

            var vis_state = gv_get_tune_span_visibility_state(planned_channel);
            if (vis_state <= 0) continue;

            if (ghost_parts) {
                if (pass == 0 && vis_state != 1) continue;
                if (pass == 1 && vis_state != 2) continue;
            } else {
                if (vis_state != 2) continue;
            }

            if (s.end_ms < t_min) continue;
            if (s.start_ms > t_max) continue;

            var x1 = gv_time_to_x(s.start_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            var x2 = gv_time_to_x(s.end_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);

            if (x2 < _rx1 || x1 > _rx2) continue;

            var lx = floor(clamp(min(x1, x2), _rx1, _rx2));
            var rx = floor(clamp(max(x1, x2), _rx1, _rx2));

            var alpha_scale = (vis_state == 1) ? ghost_alpha : 1;
            var is_emb = variable_struct_exists(s, "is_embellishment") && s.is_embellishment;
            draw_set_alpha(bar_alpha * alpha_scale);
            draw_set_color(bar_color);
            draw_rectangle(lx, _ry1, max(lx + 2, rx), _ry2, false);
            draw_set_alpha(1);

            var span_w = rx - lx;
            if (span_w >= label_min_px) {
                var label = variable_struct_exists(s, "note_letter")
                    ? string(s.note_letter)
                    : midi_to_letter(real(s.note_midi ?? 0), real(s.channel ?? -1));
                if ((label == "?" || string_length(label) <= 0) && variable_struct_exists(s, "note_canonical")) {
                    label = chanter_canonical_to_display(string(s.note_canonical));
                }
                if (label == "?" || string_length(label) <= 0) {
                    label = gv_note_label_from_midi(real(s.note_midi ?? 0));
                }

                var draw_label = label;
                var text_x = lx + 2;
                if (span_w < label_full_px) {
                    draw_label = gv_compact_note_label(label);
                    text_x = ((lx + rx) * 0.5) - (4 * note_text_scale);
                }

                var text_h = string_height(draw_label) * note_text_scale;
                var row_mid = (_ry1 + _ry2) * 0.5;
                var text_y = _ry1 + 1;
                if (is_emb) {
                    text_y = row_mid + 1;
                }
                text_y = clamp(text_y, _ry1 + 1, max(_ry1 + 1, _ry2 - text_h - 1));

                draw_set_alpha(alpha_scale);
                draw_set_color(is_emb ? embell_text_color : melody_text_color);
                draw_text_transformed(text_x, text_y, draw_label, note_text_scale, note_text_scale, 0);
                draw_set_alpha(1);
            }
        }
    }
}

/// @function gv_player_channel_matches(_channel)
/// @description Check whether a MIDI channel should be recorded as player input given the current channel filter config.
/// @param {real} _channel  MIDI channel to test.
/// @returns {bool}  true if the channel is accepted.
/// @reads  global.timeline_cfg.player_channels, global.timeline_cfg.player_channel
function gv_player_channel_matches(_channel) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return true;

    var ch = real(_channel);

    if (variable_struct_exists(global.timeline_cfg, "player_channels") && is_array(global.timeline_cfg.player_channels)) {
        var allowed = global.timeline_cfg.player_channels;
        var n_allowed = array_length(allowed);
        if (n_allowed > 0) {
            for (var i = 0; i < n_allowed; i++) {
                if (real(allowed[i]) == ch) return true;
            }
            return false;
        }
    }

    if (!variable_struct_exists(global.timeline_cfg, "player_channel")) return true;

    var target = real(global.timeline_cfg.player_channel);
    if (target < 0) return true;
    return (ch == target);
}

/// @function gv_on_player_note_on(_note_midi, _channel, _time_ms, _velocity, _note_canonical)
/// @description Handle a MIDI note-on event by opening a pending player span.
/// @param {real}   _note_midi       MIDI note number.
/// @param {real}   _channel         MIDI channel.
/// @param {real}   _time_ms         Event timestamp.
/// @param {real}   _velocity        MIDI velocity (default 0).
/// @param {string} _note_canonical  Canonical note name (default "").
/// @reads  global.timeline_state.active
/// @writes global.timeline_state.pending_player
function gv_on_player_note_on(_note_midi, _channel, _time_ms, _velocity = 0, _note_canonical = "") {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!global.timeline_state.active) return;
    if (!gv_player_channel_matches(_channel)) return;

    var note = floor(real(_note_midi));
    if (note < 0 || note > 127) return;
    var canonical = string(_note_canonical ?? "");
    if (canonical == "?") canonical = "";

    if (!variable_struct_exists(global.timeline_state, "pending_player") || !is_struct(global.timeline_state.pending_player)) {
        global.timeline_state.pending_player = {};
    }

    var key_note = (string_length(canonical) > 0) ? canonical : string(note);
    var key = gv_note_key(_channel, key_note);
    var lane_idx_cached = gv_note_to_lane_index(canonical, note, _channel);
    global.timeline_state.pending_player[$ key] = {
        start_ms: real(_time_ms),
        note_midi: note,
        note_canonical: canonical,
        note_letter: chanter_canonical_to_display(canonical),
        channel: real(_channel),
        velocity: real(_velocity),
        lane_idx: lane_idx_cached
    };
}

// Pre-classifies every player span against embellishment groups for the draw frame.
// Returns:
// {
//   player_states: int[], pending_states: struct,
//   player_grace_overlay: bool[], pending_grace_overlay: struct
// }
// State: -1=not in emb window, 0=in window wrong/unmatched, 1=correct but bleeds, 2=correct in-window.
/// @function gv_classify_player_spans_for_emb(_emb_groups, _player_spans, _pending_player, _playhead_ms, _player_offset_ms)
/// @description Pre-classify every player span against embellishment groups for per-frame draw. Returns state arrays (0â€“2) and grace-overlay flags for both completed and pending spans.
/// @param {array}  _emb_groups       Embellishment group array from gv_build_emb_groups.
/// @param {array}  _player_spans     Completed player span array.
/// @param {struct} _pending_player   In-progress (note-on, not yet note-off) spans.
/// @param {real}   _playhead_ms      Current playhead time.
/// @param {real}   _player_offset_ms Timing offset applied to player spans.
/// @returns {struct}  {player_states[], pending_states{}, player_grace_overlay[], pending_grace_overlay{}}
function gv_classify_player_spans_for_emb(_emb_groups, _player_spans, _pending_player, _playhead_ms, _player_offset_ms) {
    var n_player = is_array(_player_spans) ? array_length(_player_spans) : 0;
    var player_states = array_create(n_player, -1);
    var pending_states = {};
    var player_grace_overlay = array_create(n_player, false);
    var pending_grace_overlay = {};

    if (!is_array(_emb_groups) || array_length(_emb_groups) <= 0) {
        return {
            player_states: player_states,
            pending_states: pending_states,
            player_grace_overlay: player_grace_overlay,
            pending_grace_overlay: pending_grace_overlay
        };
    }

    var n_groups = array_length(_emb_groups);
    for (var g = 0; g < n_groups; g++) {
        var grp = _emb_groups[g];
        if (!is_struct(grp)) continue;
        var wstart = real(grp.window_start_ms ?? 0);
        var wend   = real(grp.window_end_ms ?? wstart);
        if (wend <= wstart) continue;
        var expected = grp.expected_notes;
        if (!is_array(expected) || array_length(expected) <= 0) continue;
        var n_exp = array_length(expected);
        var note_set = (variable_struct_exists(grp, "note_set") && is_struct(grp.note_set))
            ? grp.note_set
            : {};

        // Collect candidates overlapping the window
        var candidates = [];
        for (var pidx = 0; pidx < n_player; pidx++) {
            var ps = _player_spans[pidx];
            if (!is_struct(ps)) continue;
            var ps1 = real(ps.start_ms ?? 0) + _player_offset_ms;
            var ps2 = real(ps.end_ms   ?? ps1) + _player_offset_ms;
            if (ps2 <= wstart || ps1 >= wend) continue;

            var canon_ps = string(ps.note_canonical ?? "");
            if (canon_ps == "?" || string_length(canon_ps) <= 0) {
                canon_ps = chanter_midi_to_canonical(real(ps.note_midi ?? -1), global.MIDI_chanter ?? "default", real(ps.channel ?? 0));
            }
            if (canon_ps == "?" || string_length(canon_ps) <= 0) continue;
            if (!variable_struct_exists(note_set, canon_ps)) continue;

            array_push(candidates, { start_ms: ps1, end_ms: ps2,
                canonical: canon_ps,
                ctype: "player", ref_idx: pidx });
        }
        if (is_struct(_pending_player)) {
            var pkeys = variable_struct_get_names(_pending_player);
            for (var pk = 0; pk < array_length(pkeys); pk++) {
                var pk_key = pkeys[pk];
                var pp = _pending_player[$ pk_key];
                if (is_undefined(pp) || !is_struct(pp)) continue;
                var pp1 = real(pp.start_ms ?? _playhead_ms) + _player_offset_ms;
                var pp2 = max(pp1, _playhead_ms + _player_offset_ms);
                if (pp2 <= wstart || pp1 >= wend) continue;

                var canon_pp = string(pp.note_canonical ?? "");
                if (canon_pp == "?" || string_length(canon_pp) <= 0) {
                    canon_pp = chanter_midi_to_canonical(real(pp.note_midi ?? -1), global.MIDI_chanter ?? "default", real(pp.channel ?? 0));
                }
                if (canon_pp == "?" || string_length(canon_pp) <= 0) continue;
                if (!variable_struct_exists(note_set, canon_pp)) continue;

                array_push(candidates, { start_ms: pp1, end_ms: pp2,
                    canonical: canon_pp,
                    ctype: "pending", ref_key: pk_key });
            }
        }

        // Insertion sort by start_ms
        var nc = array_length(candidates);
        for (var ci = 1; ci < nc; ci++) {
            var key_c = candidates[ci];
            var cj = ci - 1;
            while (cj >= 0 && real(candidates[cj].start_ms) > real(key_c.start_ms)) {
                candidates[cj + 1] = candidates[cj];
                cj--;
            }
            candidates[cj + 1] = key_c;
        }

        // Greedy ordered sequence match; look-ahead handles skipped grace notes.
        // Only grace-note in-window matches (state==2 and matched_at<n_exp-1) get overlay=true.
        var exp_idx = 0;
        for (var ci2 = 0; ci2 < nc; ci2++) {
            var cand = candidates[ci2];
            var ccanon = string(cand.canonical ?? "");
            var matched_at = -1;
            if (exp_idx < n_exp && ccanon == expected[exp_idx]) {
                matched_at = exp_idx;
            } else {
                for (var fi = exp_idx + 1; fi < n_exp; fi++) {
                    if (ccanon == expected[fi]) { matched_at = fi; break; }
                }
            }

            var state;
            if (matched_at >= 0) {
                exp_idx = matched_at + 1;
                state = (real(cand.start_ms) < wstart || real(cand.end_ms) > wend) ? 1 : 2;
            } else {
                state = 0;  // in window but wrong/out-of-order
            }

            var is_grace_overlay = (matched_at >= 0) && (matched_at < (n_exp - 1)) && (state == 2);

            if (cand.ctype == "player") {
                var ri = real(cand.ref_idx);
                if (player_states[ri] < state) player_states[ri] = state;
                if (is_grace_overlay) player_grace_overlay[ri] = true;
            } else {
                var rk = string(cand.ref_key ?? "");
                var cur = variable_struct_exists(pending_states, rk) ? real(pending_states[$ rk]) : -1;
                if (cur < state) pending_states[$ rk] = state;
                if (is_grace_overlay) pending_grace_overlay[$ rk] = true;
            }
        }

        // Ensure all candidates in window have state >= 0
        for (var ci3 = 0; ci3 < nc; ci3++) {
            var c3 = candidates[ci3];
            if (c3.ctype == "player") {
                var ri3 = real(c3.ref_idx);
                if (player_states[ri3] < 0) player_states[ri3] = 0;
            } else {
                var rk3 = string(c3.ref_key ?? "");
                if (!variable_struct_exists(pending_states, rk3)) pending_states[$ rk3] = 0;
            }
        }
    }

    return {
        player_states: player_states,
        pending_states: pending_states,
        player_grace_overlay: player_grace_overlay,
        pending_grace_overlay: pending_grace_overlay
    };
}

/// @function gv_on_player_note_off(_note_midi, _channel, _time_ms, _note_canonical)
/// @description Handle a MIDI note-off event: close the matching pending span, apply noise-filter, and push the completed span to player_in and review_full_trace.
/// @param {real}   _note_midi       MIDI note number.
/// @param {real}   _channel         MIDI channel.
/// @param {real}   _time_ms         Event timestamp.
/// @param {string} _note_canonical  Canonical note name (default "").
/// @reads  global.timeline_state.active/pending_player, global.timeline_cfg.filter_noise_ms
/// @writes global.timeline_state.pending_player, global.timeline_state.player_in, global.timeline_state.review_full_trace, global.player_surface_cache_valid
function gv_on_player_note_off(_note_midi, _channel, _time_ms, _note_canonical = "") {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!global.timeline_state.active) return;
    if (!gv_player_channel_matches(_channel)) return;

    var note = floor(real(_note_midi));
    if (note < 0 || note > 127) return;
    var canonical = string(_note_canonical ?? "");
    if (canonical == "?") canonical = "";

    if (!variable_struct_exists(global.timeline_state, "pending_player") || !is_struct(global.timeline_state.pending_player)) return;

    var key_note = (string_length(canonical) > 0) ? canonical : string(note);
    var key = gv_note_key(_channel, key_note);
    var pending = global.timeline_state.pending_player[$ key];
    if (is_undefined(pending) || !is_struct(pending)) return;

    var start_ms = real(pending.start_ms ?? _time_ms);
    var end_ms = max(start_ms, real(_time_ms));
    var duration_ms = end_ms - start_ms;
    var noise_filter_ms = (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg) && variable_struct_exists(global.timeline_cfg, "filter_noise_ms"))
        ? max(0, real(global.timeline_cfg.filter_noise_ms))
        : 10;

    global.timeline_state.pending_player[$ key] = undefined;

    // Keep only crossing-noise suppression; keep all other notes.
    if (duration_ms < noise_filter_ms) {
        return;
    }

    var final_canonical = string(pending.note_canonical ?? "");
    if (string_length(final_canonical) <= 0) {
        final_canonical = canonical;
    }

    if (!variable_struct_exists(global.timeline_state, "player_in") || !is_array(global.timeline_state.player_in)) {
        global.timeline_state.player_in = [];
    }

    var final_lane_idx = real(pending.lane_idx ?? gv_note_to_lane_index(final_canonical, note, _channel));
    var full_span = {
        source: "player_midi_in",
        start_ms: start_ms,
        end_ms: end_ms,
        dur_ms: duration_ms,
        note_midi: note,
        note_canonical: final_canonical,
        note_letter: chanter_canonical_to_display(final_canonical),
        channel: real(_channel),
        lane_idx: final_lane_idx
    };

    array_push(global.timeline_state.player_in, full_span);
    
    // Invalidate surface cache when new spans are added (pending changes are visible)
    if (variable_global_exists("player_surface_cache_valid")) {
        global.player_surface_cache_valid = false;
    }
    
    // Two-buffer: append full span record for complete post-play review
    // (realtime player_in buffer is pruned aggressively for speed)
    if (variable_struct_exists(global.timeline_state, "review_full_trace") && is_array(global.timeline_state.review_full_trace)) {
        array_push(global.timeline_state.review_full_trace, full_span);
    }
}

// Surface-cache helpers are kept in this script so calls are always resolvable,
// even if separate script assets are not registered in the project file yet.
/// @function gv_invalidate_player_surface_cache()
/// @description Free the player surface cache and mark it invalid.
/// @reads  global.player_surface_cache
/// @writes global.player_surface_cache, global.player_surface_cache_valid
function gv_invalidate_player_surface_cache() {
    if (variable_global_exists("player_surface_cache") && surface_exists(global.player_surface_cache)) {
        surface_free(global.player_surface_cache);
    }
    global.player_surface_cache = noone;
    global.player_surface_cache_valid = false;
}

/// @function gv_ensure_player_surface_cache(_width, _height)
/// @description Return a surface of the requested dimensions from the player cache, recreating it if size changed.
/// @param {real} _width   Required surface width.
/// @param {real} _height  Required surface height.
/// @returns {surface}  Valid GPU surface handle.
/// @reads  global.player_surface_cache
/// @writes global.player_surface_cache
function gv_ensure_player_surface_cache(_width, _height) {
    if (surface_exists(global.player_surface_cache)) {
        var surf_w = surface_get_width(global.player_surface_cache);
        var surf_h = surface_get_height(global.player_surface_cache);
        if (surf_w == _width && surf_h == _height) {
            return global.player_surface_cache;
        }
        surface_free(global.player_surface_cache);
    }

    global.player_surface_cache = surface_create(_width, _height);
    return global.player_surface_cache;
}

/// @function gv_draw_player_row_to_surface(_surface, _surf_width, _surf_height, _rx1, _ry1, _rx2, _ry2, _playhead_ms)
/// @description Render the player-input row to a cached surface. Draws both completed spans and live pending spans.
/// @param {surface} _surface       Destination GPU surface.
/// @param {real}  _surf_width/_surf_height  Surface dimensions.
/// @param {real}  _rx1/_ry1/_rx2/_ry2  Canvas rect coords.
/// @param {real}  _playhead_ms     Current playhead time ms.
/// @reads  global.timeline_state.player_in/pending_player/ms_behind/ms_ahead, global.timeline_cfg.*, global.METRONOME_CONFIG
function gv_draw_player_row_to_surface(_surface, _surf_width, _surf_height, _rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!surface_exists(_surface)) return;

    surface_set_target(_surface);
    draw_clear_alpha(c_black, 0);

    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        surface_reset_target();
        return;
    }

    var cfg = gv_ensure_timeline_cfg_defaults();
    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var player_offset_ms = variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")
        ? real(global.timeline_cfg.input_capture_offset_ms)
        : 0;
    var player_bar_color = variable_struct_exists(global.timeline_cfg, "player_bar_color")
        ? global.timeline_cfg.player_bar_color
        : make_color_rgb(78, 78, 84);
    var player_pending_bar_color = variable_struct_exists(global.timeline_cfg, "notebeam_live_player_color")
        ? global.timeline_cfg.notebeam_live_player_color
        : make_color_rgb(78, 210, 255);
    var player_bar_alpha = variable_struct_exists(global.timeline_cfg, "player_bar_alpha")
        ? clamp(real(global.timeline_cfg.player_bar_alpha), 0, 1)
        : 0.84;
    var note_text_scale = variable_struct_exists(global.timeline_cfg, "player_note_text_scale")
        ? max(0.5, real(global.timeline_cfg.player_note_text_scale))
        : 1.10;
    var label_min_px = variable_struct_exists(global.timeline_cfg, "player_label_min_px")
        ? max(1, real(global.timeline_cfg.player_label_min_px))
        : 12;
    var core_min_ms = variable_struct_exists(global.timeline_cfg, "core_min_ms")
        ? max(0, real(global.timeline_cfg.core_min_ms))
        : 100;
    var player_melody_text_color = variable_struct_exists(global.timeline_cfg, "player_melody_text_color")
        ? global.timeline_cfg.player_melody_text_color
        : c_white;
    var player_short_text_color = variable_struct_exists(global.timeline_cfg, "player_short_text_color")
        ? global.timeline_cfg.player_short_text_color
        : c_green;

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var spans = variable_struct_exists(global.timeline_state, "player_in") ? global.timeline_state.player_in : [];
    if (is_array(spans)) {
        var n = array_length(spans);
        for (var i = 0; i < n; i++) {
            var s = spans[i];
            if (!is_struct(s)) continue;
            if (!gv_player_channel_matches(real(s.channel ?? 0))) continue;

            var s_start = real(s.start_ms ?? 0) + player_offset_ms;
            var s_end = real(s.end_ms ?? s_start) + player_offset_ms;
            if (s_end < t_min) continue;
            if (s_start > t_max) continue;

            var x1 = gv_time_to_x(s_start, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            var x2 = gv_time_to_x(s_end, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            if (x2 < _rx1 || x1 > _rx2) continue;

            var lx = clamp(min(x1, x2), _rx1, _rx2);
            var rx = clamp(max(x1, x2), _rx1, _rx2);

            draw_set_alpha(player_bar_alpha);
            draw_set_color(player_bar_color);
            draw_rectangle(lx, _ry1, max(lx + 2, rx), _ry2, false);
            draw_set_alpha(1);

            if (rx - lx >= label_min_px) {
                var label = variable_struct_exists(s, "note_letter") ? string(s.note_letter) : "";
                if ((label == "?" || string_length(label) <= 0) && variable_struct_exists(s, "note_canonical")) {
                    label = chanter_canonical_to_display(string(s.note_canonical));
                }
                if (label == "?" || string_length(label) <= 0) {
                    label = midi_to_letter(real(s.note_midi ?? 0), real(s.channel ?? -1));
                }
                if (label == "?" || string_length(label) <= 0) {
                    label = gv_note_label_from_midi(real(s.note_midi ?? 0));
                }
                var span_duration_ms = variable_struct_exists(s, "dur_ms")
                    ? real(s.dur_ms)
                    : max(0, s_end - s_start);
                var is_short = (span_duration_ms < core_min_ms);
                var text_h = string_height(label) * note_text_scale;
                var row_mid = (_ry1 + _ry2) * 0.5;
                var text_y = is_short ? (row_mid + 1) : (_ry1 + 1);
                text_y = clamp(text_y, _ry1 + 1, max(_ry1 + 1, _ry2 - text_h - 1));

                draw_set_color(is_short ? player_short_text_color : player_melody_text_color);
                draw_text_transformed(lx + 2, text_y, label, note_text_scale, note_text_scale, 0);
            }
        }
    }

    if (variable_struct_exists(global.timeline_state, "pending_player") && is_struct(global.timeline_state.pending_player)) {
        var names = variable_struct_get_names(global.timeline_state.pending_player);
        for (var ni = 0; ni < array_length(names); ni++) {
            var key = names[ni];
            var p = global.timeline_state.pending_player[$ key];
            if (is_undefined(p) || !is_struct(p)) continue;
            if (!gv_player_channel_matches(real(p.channel ?? 0))) continue;

            var start_ms = real(p.start_ms ?? _playhead_ms) + player_offset_ms;
            var end_ms = max(start_ms, _playhead_ms + player_offset_ms);
            if (end_ms < t_min || start_ms > t_max) continue;

            var px1 = gv_time_to_x(start_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            var px2 = gv_time_to_x(end_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            if (px2 < _rx1 || px1 > _rx2) continue;

            var plx = clamp(min(px1, px2), _rx1, _rx2);
            var prx = clamp(max(px1, px2), _rx1, _rx2);

            draw_set_alpha(player_bar_alpha);
            draw_set_color(player_pending_bar_color);
            draw_rectangle(plx, _ry1, max(plx + 2, prx), _ry2, false);
            draw_set_alpha(1);

            if (prx - plx >= label_min_px) {
                var p_label = variable_struct_exists(p, "note_letter") ? string(p.note_letter) : "";
                if ((p_label == "?" || string_length(p_label) <= 0) && variable_struct_exists(p, "note_canonical")) {
                    p_label = chanter_canonical_to_display(string(p.note_canonical));
                }
                if (p_label == "?" || string_length(p_label) <= 0) {
                    p_label = midi_to_letter(real(p.note_midi ?? 0), real(p.channel ?? -1));
                }
                if (p_label == "?" || string_length(p_label) <= 0) {
                    p_label = gv_note_label_from_midi(real(p.note_midi ?? 0));
                }
                var pending_duration_ms = max(0, end_ms - start_ms);
                var is_pending_short = (pending_duration_ms < core_min_ms);
                var p_text_h = string_height(p_label) * note_text_scale;
                var p_row_mid = (_ry1 + _ry2) * 0.5;
                var p_text_y = is_pending_short ? (p_row_mid + 1) : (_ry1 + 1);
                p_text_y = clamp(p_text_y, _ry1 + 1, max(_ry1 + 1, _ry2 - p_text_h - 1));

                draw_set_color(is_pending_short ? player_short_text_color : player_melody_text_color);
                draw_text_transformed(plx + 2, p_text_y, p_label, note_text_scale, note_text_scale, 0);
            }
        }
    }

    surface_reset_target();
}

/// @function gv_blit_player_surface_cache(_surface, _screen_x1, _screen_y1)
/// @description Draw a cached player surface to screen at the given position.
/// @param {surface} _surface     GPU surface to blit.
/// @param {real}  _screen_x1    Target x.
/// @param {real}  _screen_y1    Target y.
/// @returns {bool}  true if surface was valid and blitted.
function gv_blit_player_surface_cache(_surface, _screen_x1, _screen_y1) {
    if (!surface_exists(_surface)) return false;

    draw_set_color(c_white);
    draw_set_alpha(1);
    draw_surface(_surface, _screen_x1, _screen_y1);
    return true;
}

/// @function gv_invalidate_notebeam_live_player_surface_cache()
/// @description Free the notebeam live-player surface and mark it invalid.
/// @writes global.notebeam_live_player_surface, global.notebeam_live_player_surface_valid, global.notebeam_live_player_surface_last_span_count
function gv_invalidate_notebeam_live_player_surface_cache() {
    if (variable_global_exists("notebeam_live_player_surface") && surface_exists(global.notebeam_live_player_surface)) {
        surface_free(global.notebeam_live_player_surface);
    }
    global.notebeam_live_player_surface = noone;
    global.notebeam_live_player_surface_valid = false;
    global.notebeam_live_player_surface_last_span_count = -1;
}

/// @function gv_invalidate_notebeam_underlay_surface_cache()
/// @description Free the notebeam underlay surface and reset all staleness-tracking state.
/// @writes global.notebeam_underlay_surface, global.notebeam_underlay_surface_valid, global.notebeam_underlay_surface_last_playhead_ms, global.notebeam_underlay_surface_signature
function gv_invalidate_notebeam_underlay_surface_cache() {
    if (variable_global_exists("notebeam_underlay_surface") && surface_exists(global.notebeam_underlay_surface)) {
        surface_free(global.notebeam_underlay_surface);
    }
    global.notebeam_underlay_surface = noone;
    global.notebeam_underlay_surface_valid = false;
    global.notebeam_underlay_surface_last_playhead_ms = -9999;
    global.notebeam_underlay_surface_signature = "";
}

/// @function gv_ensure_notebeam_underlay_surface_cache(_width, _height)
/// @description Return the notebeam underlay surface at the requested size, recreating if dimensions changed.
/// @param {real} _width/_height  Required dimensions.
/// @returns {surface}
/// @reads  global.notebeam_underlay_surface
/// @writes global.notebeam_underlay_surface
function gv_ensure_notebeam_underlay_surface_cache(_width, _height) {
    if (surface_exists(global.notebeam_underlay_surface)) {
        var surf_w = surface_get_width(global.notebeam_underlay_surface);
        var surf_h = surface_get_height(global.notebeam_underlay_surface);
        if (surf_w == _width && surf_h == _height) {
            return global.notebeam_underlay_surface;
        }
        surface_free(global.notebeam_underlay_surface);
    }

    global.notebeam_underlay_surface = surface_create(_width, _height);
    return global.notebeam_underlay_surface;
}

/// @function gv_get_notebeam_underlay_surface_signature(_ctx)
/// @description Build a string hash key from notebeam render context fields used to detect when the underlay surface must be invalidated.
/// @param {struct} _ctx  Notebeam render context struct with fields: review_mode_active, review_split_beams, ghost_parts_*, ms_behind/ahead, etc.
/// @returns {string}  Signature string for cache comparison.
function gv_get_notebeam_underlay_surface_signature(_ctx) {
    var sig = string(_ctx.review_mode_active) + "|"
        + string(_ctx.review_split_beams) + "|"
        + string(_ctx.ghost_parts_enabled) + "|"
        + string_format(_ctx.ghost_parts_alpha, 0, 3) + "|"
        + string_format(_ctx.ms_behind, 0, 3) + "|"
        + string_format(_ctx.ms_ahead, 0, 3) + "|"
        + string(_ctx.target_tune_channel) + "|"
        + string(_ctx.emb_group_count) + "|"
        + string(_ctx.planned_span_count) + "|"
        + string(_ctx.planned_event_count) + "|"
        + string(_ctx.diag_disable_beat_boxes) + "|"
        + string(_ctx.diag_disable_emb_boxes) + "|"
        + string(_ctx.diag_disable_planned) + "|"
        + string(_ctx.lane_count) + "|"
        + string_format(_ctx.now_ratio, 0, 3);

    for (var i = 0; i < _ctx.lane_count; i++) {
        sig += "|" + string(floor(_ctx.lane_center_y[i])) + ":" + string(floor(_ctx.lane_beam_w[i]));
    }

    return sig;
}

/// @function gv_draw_notebeam_underlay_layers(_ctx)
/// @description Draw the static underlay layers for the notebeam canvas (beat boxes, embellishment boxes, planned-span beams) given a pre-built render context struct.
/// @param {struct} _ctx  Notebeam render context built by gv_draw_notebeam_canvas_core.
/// @reads  global.timeline_state.emb_groups/planned_spans/playback_complete
function gv_draw_notebeam_underlay_layers(_ctx) {
    if (_ctx.review_mode_active && !_ctx.diag_disable_beat_boxes) {
        gv_draw_notebeam_beat_boxes(
            _ctx.x1, _ctx.y1, _ctx.x2, _ctx.y2,
            _ctx.playhead_ms, _ctx.ms_behind, _ctx.ms_ahead, _ctx.now_ratio
        );
    }

    if (!_ctx.diag_disable_emb_boxes) {
        gv_draw_notebeam_emb_group_boxes(
            _ctx.x1, _ctx.y1, _ctx.x2, _ctx.y2,
            _ctx.playhead_ms, _ctx.ms_behind, _ctx.ms_ahead, _ctx.now_ratio,
            _ctx.lane_count, _ctx.lane_h,
            _ctx.using_lane_anchors, _ctx.lane_anchor_y, _ctx.lane_anchor_h,
            _ctx.beam_width_px, _ctx.match_label_width, _ctx.match_label_width_scale,
            _ctx.lane_flip, _ctx.use_label_lane_layout, _ctx.lane_top_spacer_ratio, _ctx.lane_top_spacer_px,
            _ctx.lane_row_height_px, _ctx.lane_row_gap_px, _ctx.lane_y_offset_px
        );
    }

    if (_ctx.diag_disable_planned || !is_array(_ctx.planned_spans) || array_length(_ctx.planned_spans) <= 0) {
        return;
    }

    var planned_draw_x_min = _ctx.x1 - _ctx.planned_view_pad_px;
    var planned_draw_x_max = _ctx.x2 + _ctx.planned_view_pad_px;
    var n_planned = array_length(_ctx.planned_spans);
    var _pbs_lo = 0;
    var _pbs_hi = n_planned;
    while (_pbs_lo < _pbs_hi) {
        var _pbs_mid = (_pbs_lo + _pbs_hi) >> 1;
        var _pbs_sub = _ctx.planned_spans[_pbs_mid];
        if (max(real(_pbs_sub.start_ms ?? 0), real(_pbs_sub.end_ms ?? 0)) < _ctx.t_min) _pbs_lo = _pbs_mid + 1;
        else _pbs_hi = _pbs_mid;
    }
    var planned_first_i = _pbs_lo;
    var planned_pass_count = _ctx.ghost_parts_enabled ? 2 : 1;

    for (var pass_planned = 0; pass_planned < planned_pass_count; pass_planned++) {
        var pass_alpha_scale = (_ctx.ghost_parts_enabled && pass_planned == 0) ? _ctx.ghost_parts_alpha : 1.0;
        draw_set_alpha(_ctx.planned_beam_alpha * pass_alpha_scale);
        draw_set_color(_ctx.planned_beam_color);

        for (var i = planned_first_i; i < n_planned; i++) {
            var ps = _ctx.planned_spans[i];
            if (!is_struct(ps)) continue;

            var planned_channel = floor(real(ps.channel ?? -999));
            var vis_state = 0;
            if (planned_channel >= 2 && planned_channel <= 5) {
                if (planned_channel == _ctx.target_tune_channel) {
                    vis_state = 2;
                } else if (_ctx.ghost_parts_enabled) {
                    vis_state = 1;
                }
            }
            if (vis_state <= 0) continue;

            if (_ctx.ghost_parts_enabled) {
                if (pass_planned == 0 && vis_state != 1) continue;
                if (pass_planned == 1 && vis_state != 2) continue;
            } else if (vis_state != 2) {
                continue;
            }

            var p_start = real(ps.start_ms ?? 0);
            var p_end = real(ps.end_ms ?? p_start);
            if (p_end < _ctx.t_min) continue;
            if (p_start > _ctx.t_max) break;

            var lane_idx = real(ps.lane_idx ?? -999);
            if (lane_idx == -999) {
                lane_idx = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
            }
            if (lane_idx < 0 || lane_idx >= _ctx.lane_count) continue;

            var px1 = gv_time_to_x(p_start, _ctx.playhead_ms, _ctx.x1, _ctx.x2, _ctx.now_ratio, _ctx.ms_behind, _ctx.ms_ahead);
            var px2 = gv_time_to_x(p_end, _ctx.playhead_ms, _ctx.x1, _ctx.x2, _ctx.now_ratio, _ctx.ms_behind, _ctx.ms_ahead);
            var px_left = min(px1, px2);
            var px_right = max(px1, px2);
            if (px_right < planned_draw_x_min) continue;
            if (px_left > planned_draw_x_max) break;

            var plx = floor(clamp(px_left, _ctx.x1, _ctx.x2));
            var prx = floor(clamp(px_right, _ctx.x1, _ctx.x2));
            if ((prx - plx) < _ctx.planned_min_visible_px) continue;

            var py = _ctx.lane_center_y[lane_idx];
            var lane_beam_width = _ctx.lane_beam_w[lane_idx];
            var py_draw = round(py);
            var lane_beam_draw_width = lane_beam_width;
            if (_ctx.review_split_beams) {
                py_draw = clamp(round(py - (lane_beam_width * 0.25)), _ctx.y1 + 1, _ctx.y2 - 1);
                lane_beam_draw_width = max(1, lane_beam_width * 0.5);
            }

            draw_line_width(plx, py_draw, prx, py_draw, lane_beam_draw_width);
        }
    }

    draw_set_alpha(1);
}

/// @function gv_ensure_notebeam_live_player_surface_cache(_width, _height)
/// @description Return the notebeam live-player surface at the requested size, recreating if dimensions changed.
/// @param {real} _width/_height  Required surface dimensions.
/// @returns {surface}
/// @reads  global.notebeam_live_player_surface
/// @writes global.notebeam_live_player_surface
function gv_ensure_notebeam_live_player_surface_cache(_width, _height) {
    if (surface_exists(global.notebeam_live_player_surface)) {
        var surf_w = surface_get_width(global.notebeam_live_player_surface);
        var surf_h = surface_get_height(global.notebeam_live_player_surface);
        if (surf_w == _width && surf_h == _height) {
            return global.notebeam_live_player_surface;
        }
        surface_free(global.notebeam_live_player_surface);
    }

    global.notebeam_live_player_surface = surface_create(_width, _height);
    return global.notebeam_live_player_surface;
}

/// @function gv_render_notebeam_live_player_surface(_surface, _player_spans, _x1, _y1, _x2, _y2, _playhead_ms, _t_min, _t_max, _player_offset_ms, _now_ratio, _ms_behind, _ms_ahead, _lane_count, _lane_center_y, _lane_beam_w, _player_beam_color, _player_beam_alpha)
/// @description Render visible completed player spans as lane-aligned beam lines to a GPU surface.
/// @param {surface} _surface            Target surface (must already be sized).
/// @param {array}   _player_spans       Sorted completed player span array.
/// @param {real}    _x1/_y1/_x2/_y2     Canvas rect.
/// @param {real}    _playhead_ms         Current playhead.
/// @param {real}    _t_min/_t_max        Visible time window.
/// @param {real}    _player_offset_ms    Timing compensation offset.
/// @param {real}    _now_ratio           Position of now-line.
/// @param {real}    _ms_behind/_ms_ahead Time window extents.
/// @param {int}     _lane_count          Number of note lanes.
/// @param {array}   _lane_center_y       Per-lane center y values.
/// @param {array}   _lane_beam_w         Per-lane beam widths.
/// @param {int}     _player_beam_color   Beam color.
/// @param {real}    _player_beam_alpha   Beam alpha.
function gv_render_notebeam_live_player_surface(_surface, _player_spans, _x1, _y1, _x2, _y2,
    _playhead_ms, _t_min, _t_max, _player_offset_ms, _now_ratio, _ms_behind, _ms_ahead,
    _lane_count, _lane_center_y, _lane_beam_w, _player_beam_color, _player_beam_alpha) {
    if (!surface_exists(_surface)) return;
    if (!is_array(_player_spans)) return;

    var w = max(1, _x2 - _x1);
    var h = max(1, _y2 - _y1);

    surface_set_target(_surface);
    draw_clear_alpha(c_black, 0);
    draw_set_alpha(_player_beam_alpha);
    draw_set_color(_player_beam_color);

    var n_player = array_length(_player_spans);
    var _qbs_raw_tmin = _t_min - _player_offset_ms;
    var _qbs_lo = 0; var _qbs_hi = n_player;
    while (_qbs_lo < _qbs_hi) {
        var _qbs_mid = (_qbs_lo + _qbs_hi) >> 1;
        if (real(_player_spans[_qbs_mid].end_ms ?? 0) < _qbs_raw_tmin) _qbs_lo = _qbs_mid + 1;
        else _qbs_hi = _qbs_mid;
    }

    for (var j = _qbs_lo; j < n_player; j++) {
        var ps2 = _player_spans[j];
        if (!is_struct(ps2)) continue;
        var q_start = real(ps2.start_ms ?? 0) + _player_offset_ms;
        var q_end = real(ps2.end_ms ?? q_start) + _player_offset_ms;
        if (q_start > _t_max) break;

        var lane_idx2 = real(ps2.lane_idx ?? -999);
        if (lane_idx2 == -999) {
            lane_idx2 = gv_note_to_lane_index(ps2.note_canonical ?? "", ps2.note_midi ?? -1, ps2.channel ?? -1);
        }
        if (lane_idx2 < 0 || lane_idx2 >= _lane_count) continue;

        var qx1 = gv_time_to_x(q_start, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var qx2 = gv_time_to_x(q_end, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        var qlx = clamp(min(qx1, qx2), _x1, _x2) - _x1;
        var qrx = clamp(max(qx1, qx2), _x1, _x2) - _x1;
        if (qrx <= qlx) {
            if (qlx >= w) {
                qlx = max(0, w - 1);
                qrx = w;
            } else {
                qrx = min(w, qlx + 1);
            }
        }
        if (qrx <= qlx) continue;

        var qy = _lane_center_y[lane_idx2] - _y1;
        var lane_beam_width2 = _lane_beam_w[lane_idx2];
        qy = clamp(qy, 1, max(1, h - 1));

        draw_line_width(qlx, qy, qrx, qy, lane_beam_width2);
    }

    draw_set_alpha(1);
    surface_reset_target();
}

/// @function gv_draw_player_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms)
/// @description Draw (or blit from cache) the player-input canvas row. Uses a surface cache that is invalidated when the playhead moves significantly or spans change.
/// @param {real} _rx1/_ry1/_rx2/_ry2  Canvas bounds.
/// @param {real} _playhead_ms          Current playhead time ms.
/// @reads  global.timeline_state.player_in/pending_player/ms_behind/ms_ahead
/// @reads  global.player_surface_cache, global.player_surface_cache_valid, global.player_surface_cache_last_playhead_ms
/// @writes global.player_surface_cache, global.player_surface_cache_valid, global.player_surface_cache_last_playhead_ms
function gv_draw_player_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    if (!variable_global_exists("player_surface_cache")) global.player_surface_cache = noone;
    if (!variable_global_exists("player_surface_cache_valid")) global.player_surface_cache_valid = false;
    if (!variable_global_exists("player_surface_cache_last_playhead_ms")) global.player_surface_cache_last_playhead_ms = -9999;
    if (!variable_global_exists("player_surface_cache_invalidation_threshold_ms")) global.player_surface_cache_invalidation_threshold_ms = 200;
    
    var row_width = max(1, _rx2 - _rx1);
    var row_height = max(1, _ry2 - _ry1);
    
    // Check if cache needs invalidation (playhead moved significantly)
    var playhead_delta = abs(_playhead_ms - global.player_surface_cache_last_playhead_ms);
    var needs_redraw = !global.player_surface_cache_valid 
        || playhead_delta >= global.player_surface_cache_invalidation_threshold_ms;
    
    if (needs_redraw) {
        // Render to surface (replaces full per-frame drawing logic)
        var surf = gv_ensure_player_surface_cache(row_width, row_height);
        gv_draw_player_row_to_surface(surf, row_width, row_height, _rx1, _ry1, _rx2, _ry2, _playhead_ms);
        global.player_surface_cache_valid = true;
        global.player_surface_cache_last_playhead_ms = _playhead_ms;
    }
    
    // Fast blit cached surface to screen
    if (surface_exists(global.player_surface_cache)) {
        gv_blit_player_surface_cache(global.player_surface_cache, _rx1, _ry1);
    } else {
        // Fallback: surface invalid, redraw directly (safety)
        gv_invalidate_player_surface_cache();
    }
}

/// @function gv_timeline_ensure_beat_positions()
/// @description Lazily build a sorted array of beat positions from planned_events. Caches result in global.timeline_beat_positions; re-runs only when event count changes.
/// @reads  global.timeline_state.planned_events, global.timeline_beat_positions_event_count
/// @writes global.timeline_beat_positions, global.timeline_beat_positions_event_count
function gv_timeline_ensure_beat_positions() {
    // O(n) scan runs once per tune load; all per-frame lookups use binary search.
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(global.timeline_state, "planned_events")
        || !is_array(global.timeline_state.planned_events)) return;

    var events = global.timeline_state.planned_events;
    var n = array_length(events);

    var _nav_entries = (variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries))
        ? global.timeline_state.measure_nav_entries
        : [];
    var _nav_n = array_length(_nav_entries);
    var _nav_first = (_nav_n > 0) ? real(_nav_entries[0].start_ms ?? 0) : -1;
    var _nav_last = (_nav_n > 0) ? real(_nav_entries[_nav_n - 1].start_ms ?? 0) : -1;
    var _nav_last_measure = (_nav_n > 0) ? floor(real(_nav_entries[_nav_n - 1].measure ?? 0)) : -1;
    var _active_seg = variable_global_exists("playback_context") && is_struct(global.playback_context)
        ? floor(real(global.playback_context[$ "active_segment"] ?? -1))
        : -1;
    var _is_set_mode = variable_global_exists("playback_context")
        && is_struct(global.playback_context)
        && string(global.playback_context[$ "mode"] ?? "") == "set";
    var _single_tune_loop_runtime = !_is_set_mode
        && variable_global_exists("loop_runtime_active")
        && bool(global.loop_runtime_active);

    var _cache_sig = "v4|" + string(n)
        + "|" + string(_nav_n)
        + "|" + string(_nav_first)
        + "|" + string(_nav_last)
        + "|" + string(_nav_last_measure)
        + "|loop=" + string(_single_tune_loop_runtime)
        + "|" + string(_active_seg);
    if (variable_global_exists("timeline_beat_positions_signature")
        && string(global.timeline_beat_positions_signature) == _cache_sig
        && variable_global_exists("timeline_beat_positions")
        && is_array(global.timeline_beat_positions)) return;

    var result = [];
    var _last_labeled_measure_key = "";
    var _has_bar_markers = false;
    for (var _scan_i = 0; _scan_i < n; _scan_i++) {
        var _scan_ev = events[_scan_i];
        if (!is_struct(_scan_ev)) continue;
        if (string(_scan_ev.type ?? "") != "marker") continue;
        if (string(_scan_ev.marker_type ?? "") == "bar") {
            _has_bar_markers = true;
            break;
        }
    }
    var _labeled_measure1_fallback = false;
    for (var i = 0; i < n; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;
        if (string(ev.type ?? "") != "marker") continue;
        var _marker_type = string(ev.marker_type ?? "");
        if (_marker_type != "beat" && _marker_type != "bar") continue;

        var t = gv_evt_time_ms(ev);
        var beat_fraction = real(ev.beat_fraction ?? 0);
        var is_major = (_marker_type == "bar") || (abs(beat_fraction) <= 0.001);
        var label = "";

        // Prefer tune-authored bar markers for labels when present.
        // Metronome beat markers can be lead-shifted and should not drive measure numbering.
        var _is_boundary = false;
        if (_has_bar_markers) {
            _is_boundary = (_marker_type == "bar");
            // ABC exports often omit a bar marker at measure 1 start.
            // Allow a single beat=1 fallback label for measure 1 only.
            if (!_is_boundary && !_labeled_measure1_fallback
                && _marker_type == "beat"
                && floor(real(ev.beat ?? 0)) == 1
                && floor(real(ev.measure ?? 0)) == 1) {
                _is_boundary = true;
                if (!_single_tune_loop_runtime) {
                    _labeled_measure1_fallback = true;
                }
            }
        } else {
            _is_boundary = (_marker_type == "beat" && floor(real(ev.beat ?? 0)) == 1);
        }
        if (_is_boundary) {
            var _iter = _single_tune_loop_runtime
                ? max(0, floor(real(ev.loop_iteration ?? 0)))
                : 0;
            var _nm = _single_tune_loop_runtime
                ? floor(real(ev.owner_measure ?? ev.measure ?? 0))
                : floor(real(ev.measure ?? 0));
            if (!_single_tune_loop_runtime && _nav_n > 0) {
                var _lo = 0;
                var _hi = _nav_n - 1;
                var _idx = -1;
                while (_lo <= _hi) {
                    var _mid = (_lo + _hi) div 2;
                    var _st = real(_nav_entries[_mid].start_ms ?? 0);
                    if (_st <= t) {
                        _idx = _mid;
                        _lo = _mid + 1;
                    } else {
                        _hi = _mid - 1;
                    }
                }
                if (_idx >= 0) {
                    _nm = floor(real(_nav_entries[_idx].measure ?? _nm));
                }
            }
            var _label_key = _single_tune_loop_runtime
                ? (string(_iter) + ":" + string(_nm))
                : string(_nm);
            if (_nm >= 1 && _label_key != _last_labeled_measure_key) {
                label = "M" + string(_nm);
                _last_labeled_measure_key = _label_key;
            }
        }
        array_push(result, {
            time_ms: t,
            is_major: is_major,
            label: label,
            iteration: _single_tune_loop_runtime ? max(0, floor(real(ev.loop_iteration ?? 0))) : 0
        });
    }

    global.timeline_beat_positions = result;
    global.timeline_beat_positions_event_count = n;
    global.timeline_beat_positions_signature = _cache_sig;
}

/// @function gv_draw_beat_lane(_x1, _y1, _x2, _y2, _playhead_ms)
/// @description Draw the scrolling beat-tick lane: vertical tick marks for every beat, with measure labels on beat 1 major ticks.
/// @param {real} _x1/_y1/_x2/_y2  Canvas lane bounds.
/// @param {real} _playhead_ms      Current playhead time ms.
/// @reads  global.timeline_state.ms_behind/ms_ahead, global.timeline_cfg, global.timeline_beat_positions
function gv_draw_beat_lane(_x1, _y1, _x2, _y2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    var cfg = gv_ensure_timeline_cfg_defaults();

    var bg_color = variable_struct_exists(cfg, "tl_beat_lane_bg_color")
        ? cfg.tl_beat_lane_bg_color : make_color_rgb(26, 26, 30);
    draw_set_color(bg_color);
    draw_set_alpha(1);
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    gv_timeline_ensure_beat_positions();
    if (!variable_global_exists("timeline_beat_positions")
        || !is_array(global.timeline_beat_positions)
        || array_length(global.timeline_beat_positions) == 0) return;

    var ms_behind = variable_struct_exists(global.timeline_state, "ms_behind") ? real(global.timeline_state.ms_behind) : 3000;
    var ms_ahead  = variable_struct_exists(global.timeline_state, "ms_ahead")  ? real(global.timeline_state.ms_ahead)  : 6000;
    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var now_x = _x1 + ((_x2 - _x1) * now_ratio);

    var t_min = _playhead_ms - ms_behind;
    var t_max = _playhead_ms + ms_ahead;

    var major_color  = variable_struct_exists(cfg, "structure_major_color") ? cfg.structure_major_color : c_ltgray;
    var minor_color  = variable_struct_exists(cfg, "structure_minor_color") ? cfg.structure_minor_color : c_gray;
    var text_color   = variable_struct_exists(cfg, "structure_text_color")  ? cfg.structure_text_color  : c_white;
    var past_alpha   = variable_struct_exists(cfg, "structure_past_tick_alpha")
        ? clamp(real(cfg.structure_past_tick_alpha), 0, 1) : 0.35;
    var future_alpha = variable_struct_exists(cfg, "structure_future_tick_alpha")
        ? clamp(real(cfg.structure_future_tick_alpha), 0, 1) : 1.0;
    var label_spacing = variable_struct_exists(cfg, "structure_label_spacing_px")
        ? max(1, real(cfg.structure_label_spacing_px)) : 26;

    // Binary search for first event in visible window (O(log n))
    var pos = global.timeline_beat_positions;
    var n   = array_length(pos);
    var lo = 0; var hi = n - 1; var start_i = n;
    while (lo <= hi) {
        var mid = (lo + hi) div 2;
        if (pos[mid].time_ms < t_min) { lo = mid + 1; }
        else { start_i = mid; hi = mid - 1; }
    }

    var _prev_font = draw_get_font();
    draw_set_font(fnt_measure);
    draw_set_halign(fa_left);
    draw_set_valign(fa_middle);
    var mid_y = _y1 + ((_y2 - _y1) * 0.5);
    var last_label_x = -1000000;

    for (var i = start_i; i < n; i++) {
        var ev = pos[i];
        if (ev.time_ms > t_max) break;

        var x_tick = gv_time_to_x(ev.time_ms, _playhead_ms, _x1, _x2, now_ratio, ms_behind, ms_ahead);
        if (x_tick < _x1 || x_tick > _x2) continue;

        var is_past   = (x_tick < now_x);
        var tick_alpha = is_past ? past_alpha : future_alpha;
        var is_major  = ev.is_major;

        draw_set_alpha(tick_alpha);
        draw_set_color(is_major ? major_color : minor_color);
        var y_from = is_major ? _y1 : (_y1 + 4);
        draw_line_width(x_tick, y_from, x_tick, _y2, is_major ? 2 : 1);

        if (!is_major || string_length(ev.label) == 0) continue;
        if ((x_tick - last_label_x) < label_spacing) continue;

        draw_set_alpha(tick_alpha);
        draw_set_color(text_color);
        draw_text(x_tick + 2, mid_y, ev.label);
        last_label_x = x_tick;
    }

    draw_set_alpha(1);
    draw_set_valign(fa_top);
    draw_set_font(_prev_font);
}

/// @function gv_draw_beat_guides(_rx1, _ry1, _rx2, _ry2, _playhead_ms)
/// @description Draw vertical beat-guide lines across a canvas row for all beat/countin-beat markers in the visible window.
/// @param {real} _rx1/_ry1/_rx2/_ry2  Row bounds.
/// @param {real} _playhead_ms          Current playhead time ms.
/// @reads  global.timeline_state.planned_events/ms_behind/ms_ahead, global.timeline_cfg
function gv_draw_beat_guides(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(global.timeline_state, "planned_events")) return;

    if (variable_struct_exists(cfg, "show_beat_guides") && !cfg.show_beat_guides) return;

    var events = global.timeline_state.planned_events;
    if (!is_array(events)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var ms_behind = variable_struct_exists(global.timeline_state, "ms_behind") ? real(global.timeline_state.ms_behind) : 0;
    var ms_ahead = variable_struct_exists(global.timeline_state, "ms_ahead") ? real(global.timeline_state.ms_ahead) : 0;
    var show_countin = !variable_struct_exists(cfg, "show_countin") || cfg.show_countin;

    var major_color = variable_struct_exists(cfg, "beat_guide_major_color")
        ? cfg.beat_guide_major_color
        : c_gray;
    var minor_color = variable_struct_exists(cfg, "beat_guide_minor_color")
        ? cfg.beat_guide_minor_color
        : c_dkgray;
    var major_alpha = variable_struct_exists(cfg, "beat_guide_major_alpha")
        ? clamp(real(cfg.beat_guide_major_alpha), 0, 1)
        : 0.28;
    var minor_alpha = variable_struct_exists(cfg, "beat_guide_minor_alpha")
        ? clamp(real(cfg.beat_guide_minor_alpha), 0, 1)
        : 0.16;
    var major_width = variable_struct_exists(cfg, "beat_guide_major_width")
        ? max(1, real(cfg.beat_guide_major_width))
        : 1;
    var minor_width = variable_struct_exists(cfg, "beat_guide_minor_width")
        ? max(1, real(cfg.beat_guide_minor_width))
        : 1;

    var n = array_length(events);
    for (var i = 0; i < n; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;
        if (!variable_struct_exists(ev, "type") || string(ev.type) != "marker") continue;

        var marker_type = string(ev.marker_type ?? "");
        if (marker_type != "beat" && marker_type != "countin_beat") continue;
        if (!show_countin && marker_type == "countin_beat") continue;

        var marker_time = gv_evt_time_ms(ev);
        if (marker_time < t_min || marker_time > t_max) continue;

        var x_tick = gv_time_to_x(marker_time, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
        if (x_tick < _rx1 || x_tick > _rx2) continue;

        var beat_fraction = real(ev.beat_fraction ?? 0);
        var is_major = abs(beat_fraction) <= 0.001;

        draw_set_alpha(is_major ? major_alpha : minor_alpha);
        draw_set_color(is_major ? major_color : minor_color);
        draw_line_width(x_tick, _ry1, x_tick, _ry2, is_major ? major_width : minor_width);
    }

    draw_set_alpha(1);
}

/// @function gv_draw_notebeam_beat_boxes(_x1, _y1, _x2, _y2, _playhead_ms, _ms_behind, _ms_ahead, _now_ratio)
/// @description Draw alternating even/odd shaded rectangles between each pair of consecutive beat positions. Only shows in post-playback review mode.
/// @param {real} _x1/_y1/_x2/_y2   Canvas bounds.
/// @param {real} _playhead_ms       Current playhead ms.
/// @param {real} _ms_behind/_ms_ahead  Time window extents.
/// @param {real} _now_ratio         Fraction of canvas at now-line.
/// @reads  global.timeline_state.playback_complete/planned_events, global.timeline_cfg, global.show_review_beat_bands
function gv_draw_notebeam_beat_boxes(_x1, _y1, _x2, _y2, _playhead_ms, _ms_behind, _ms_ahead, _now_ratio) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;

    gv_ensure_timeline_cfg_defaults();

    if (variable_global_exists("show_review_beat_bands") && !global.show_review_beat_bands) return;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return;
    if (!variable_struct_exists(global.timeline_state, "planned_events")) return;

    var events = global.timeline_state.planned_events;
    if (!is_array(events)) return;

    var even_color = variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_even_color")
        ? global.timeline_cfg.notebeam_beat_box_even_color
        : make_color_rgb(245, 245, 245);
    var odd_color = variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_odd_color")
        ? global.timeline_cfg.notebeam_beat_box_odd_color
        : make_color_rgb(35, 35, 35);
    var even_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_even_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_beat_box_even_alpha), 0, 1)
        : 0.06;
    var odd_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_beat_box_odd_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_beat_box_odd_alpha), 0, 1)
        : 0.14;

    // Keep parity stable while scrolling by counting beat markers globally.
    var beat_xs = [];
    var beat_idx = 0;
    var n = array_length(events);
    for (var i = 0; i < n; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;
        if (!variable_struct_exists(ev, "type") || string(ev.type) != "marker") continue;
        if (string(ev.marker_type ?? "") != "beat") continue;

        var marker_time = gv_evt_time_ms(ev);
        var x_tick = gv_time_to_x(marker_time, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead);
        array_push(beat_xs, { x: x_tick, idx: beat_idx });
        beat_idx += 1;
    }

    if (array_length(beat_xs) < 2) return;

    for (var j = 0; j < array_length(beat_xs) - 1; j++) {
        var bx1 = clamp(beat_xs[j].x, _x1, _x2);
        var bx2 = clamp(beat_xs[j + 1].x, _x1, _x2);
        if (bx2 <= bx1 + 1) continue;

        var is_even = ((beat_xs[j].idx mod 2) == 0);
        draw_set_color(is_even ? even_color : odd_color);
        draw_set_alpha(is_even ? even_alpha : odd_alpha);
        draw_rectangle(bx1, _y1, bx2, _y2, false);
    }

    draw_set_alpha(1);
}

/// @function gv_draw_notebeam_emb_group_boxes(_x1, _y1, _x2, _y2, _playhead_ms, _ms_behind, _ms_ahead, _now_ratio, _lane_count, _lane_h, _using_lane_anchors, _lane_anchor_y, _lane_anchor_h, _beam_width_px, _match_label_width, _match_label_width_scale, _lane_flip, _use_label_lane_layout, _lane_top_spacer_ratio, _lane_top_spacer_px, _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px)
/// @description Draw highlighted rectangles around embellishment group windows spanning their note-lane rows. Configurable via timeline_cfg.notebeam_emb_box_* fields.
/// @param {real}  _x1/_y1/_x2/_y2   Canvas bounds.
/// @param {real}  _playhead_ms/_ms_behind/_ms_ahead/_now_ratio  Time mapping params.
/// @param {int}   _lane_count        Number of lanes.
/// @param ...     (remaining params forwarded to gv_get_notebeam_lane_metrics)
/// @reads  global.timeline_state.emb_groups/playback_complete, global.timeline_cfg, global.show_review_emb_boxes
function gv_draw_notebeam_emb_group_boxes(_x1, _y1, _x2, _y2, _playhead_ms, _ms_behind, _ms_ahead, _now_ratio,
    _lane_count, _lane_h,
    _using_lane_anchors, _lane_anchor_y, _lane_anchor_h,
    _beam_width_px, _match_label_width, _match_label_width_scale,
    _lane_flip, _use_label_lane_layout, _lane_top_spacer_ratio, _lane_top_spacer_px,
    _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    if (variable_global_exists("show_review_emb_boxes") && !global.show_review_emb_boxes) return;
    if (!variable_struct_exists(global.timeline_state, "emb_groups") || !is_array(global.timeline_state.emb_groups)) return;

    var cfg = global.timeline_cfg;
    var enabled = !variable_struct_exists(cfg, "notebeam_emb_box_enabled") || cfg.notebeam_emb_box_enabled;
    if (!enabled) return;

    var review_only = !variable_struct_exists(cfg, "notebeam_emb_box_review_only") || cfg.notebeam_emb_box_review_only;
    var playback_complete = variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete;
    if (review_only && !playback_complete) return;

    var fill_color = variable_struct_exists(cfg, "notebeam_emb_box_fill_color")
        ? cfg.notebeam_emb_box_fill_color
        : make_color_rgb(60, 155, 70);
    var fill_alpha = variable_struct_exists(cfg, "notebeam_emb_box_fill_alpha")
        ? clamp(real(cfg.notebeam_emb_box_fill_alpha), 0, 1)
        : 0.24;
    var border_color = variable_struct_exists(cfg, "notebeam_emb_box_border_color")
        ? cfg.notebeam_emb_box_border_color
        : fill_color;
    var border_alpha = variable_struct_exists(cfg, "notebeam_emb_box_border_alpha")
        ? clamp(real(cfg.notebeam_emb_box_border_alpha), 0, 1)
        : 1.0;
    var lane_padding_px = variable_struct_exists(cfg, "notebeam_emb_box_lane_padding_px")
        ? max(0, real(cfg.notebeam_emb_box_lane_padding_px))
        : 3;
    var time_padding_ms = variable_struct_exists(cfg, "notebeam_emb_box_time_padding_ms")
        ? max(0, real(cfg.notebeam_emb_box_time_padding_ms))
        : 0;

    var t_min = _playhead_ms - _ms_behind - time_padding_ms;
    var t_max = _playhead_ms + _ms_ahead + time_padding_ms;

    var groups = global.timeline_state.emb_groups;
    var n_groups = array_length(groups);
    for (var g = 0; g < n_groups; g++) {
        var grp = groups[g];
        if (!is_struct(grp)) continue;

        // Only draw full embellishment windows that include a confirmed target note.
        var has_target = variable_struct_exists(grp, "has_target") ? grp.has_target : false;
        if (!has_target) continue;

        var win_start = real(grp.window_start_ms ?? 0) - time_padding_ms;
        var win_end = real(grp.window_end_ms ?? win_start) + time_padding_ms;
        if (win_end < t_min || win_start > t_max) continue;

        var gx1 = clamp(gv_time_to_x(win_start, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead), _x1, _x2);
        var gx2 = clamp(gv_time_to_x(win_end, _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead), _x1, _x2);
        if (gx2 <= gx1 + 1) continue;

        var min_y = 1000000000;
        var max_y = -1000000000;
        var found_lane = false;

        var lanes = [];
        if (variable_struct_exists(grp, "lane_indices") && is_array(grp.lane_indices)) {
            lanes = grp.lane_indices;
        }
        if (!is_array(lanes) || array_length(lanes) <= 0) continue;

        var n_lanes = array_length(lanes);
        for (var i = 0; i < n_lanes; i++) {
            var lane_idx = floor(real(lanes[i]));
            if (lane_idx < 0 || lane_idx >= _lane_count) continue;

            var lane_metrics = gv_get_notebeam_lane_metrics(
                lane_idx, _lane_count, _y1, _y2, _lane_h,
                _using_lane_anchors, _lane_anchor_y, _lane_anchor_h,
                _beam_width_px, _match_label_width, _match_label_width_scale,
                _lane_flip, _use_label_lane_layout, _lane_top_spacer_ratio, _lane_top_spacer_px,
                _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px,
                false
            );
            if (!is_struct(lane_metrics)) continue;

            var half_h = max(1, real(lane_metrics.beam_width) * 0.5);
            var ly1 = real(lane_metrics.center_y) - half_h;
            var ly2 = real(lane_metrics.center_y) + half_h;

            min_y = min(min_y, ly1);
            max_y = max(max_y, ly2);
            found_lane = true;
        }

        if (!found_lane) continue;

        var gy1 = clamp(min_y - lane_padding_px, _y1, _y2);
        var gy2 = clamp(max_y + lane_padding_px, _y1, _y2);
        if (gy2 <= gy1 + 1) continue;

        draw_set_alpha(fill_alpha);
        draw_set_color(fill_color);
        draw_rectangle(gx1, gy1, gx2, gy2, false);

        draw_set_alpha(border_alpha);
        draw_set_color(border_color);
        draw_rectangle(gx1, gy1, gx2, gy2, true);
    }

    draw_set_alpha(1);
}

/// @function gv_draw_structure_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms)
/// @description Draw scrolling structure tick marks and measure labels (M1, M2, ...) in a structure overview row.
/// @param {real} _rx1/_ry1/_rx2/_ry2  Row bounds.
/// @param {real} _playhead_ms          Current playhead ms.
/// @reads  global.timeline_state.planned_events/ms_behind/ms_ahead, global.timeline_cfg
function gv_draw_structure_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(global.timeline_state, "planned_events")) return;

    var events = global.timeline_state.planned_events;
    if (!is_array(events)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var now_x = _rx1 + ((_rx2 - _rx1) * now_ratio);

    var show_countin = !variable_struct_exists(global.timeline_cfg, "show_countin") || global.timeline_cfg.show_countin;
    var label_every_beat = !variable_struct_exists(global.timeline_cfg, "structure_label_every_beat") || global.timeline_cfg.structure_label_every_beat;
    var label_spacing = variable_struct_exists(global.timeline_cfg, "structure_label_spacing_px")
        ? max(1, real(global.timeline_cfg.structure_label_spacing_px))
        : 26;

    var major_color = variable_struct_exists(global.timeline_cfg, "structure_major_color")
        ? global.timeline_cfg.structure_major_color
        : c_ltgray;
    var minor_color = variable_struct_exists(global.timeline_cfg, "structure_minor_color")
        ? global.timeline_cfg.structure_minor_color
        : c_gray;
    var text_color = variable_struct_exists(global.timeline_cfg, "structure_text_color")
        ? global.timeline_cfg.structure_text_color
        : c_white;
    var past_alpha = variable_struct_exists(global.timeline_cfg, "structure_past_tick_alpha")
        ? clamp(real(global.timeline_cfg.structure_past_tick_alpha), 0, 1)
        : 0.35;
    var future_alpha = variable_struct_exists(global.timeline_cfg, "structure_future_tick_alpha")
        ? clamp(real(global.timeline_cfg.structure_future_tick_alpha), 0, 1)
        : 1.0;

    var last_label_x = -1000000;
    var _prev_font = draw_get_font();
    draw_set_font(fnt_measure);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var n = array_length(events);
    var has_bar_markers = false;
    for (var _bi = 0; _bi < n; _bi++) {
        var _bev = events[_bi];
        if (!is_struct(_bev)) continue;
        if (string(_bev.type ?? "") != "marker") continue;
        if (string(_bev.marker_type ?? "") != "bar") continue;
        if (floor(real(_bev.measure ?? 0)) < 1) continue;
        has_bar_markers = true;
        break;
    }

    for (var i = 0; i < n; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;
        if (!variable_struct_exists(ev, "type") || string(ev.type) != "marker") continue;

        var marker_type = string(ev.marker_type ?? "");
        if (marker_type != "bar" && marker_type != "beat" && marker_type != "countin_beat") continue;
        if (!show_countin && marker_type == "countin_beat") continue;

        var marker_time = gv_evt_time_ms(ev);
        if (marker_time < t_min || marker_time > t_max) continue;

        var x_tick = gv_time_to_x(marker_time, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
        if (x_tick < _rx1 || x_tick > _rx2) continue;

        var beat_fraction = (marker_type == "bar") ? 0 : real(ev.beat_fraction ?? 0);
        var is_major = (marker_type == "bar") || abs(beat_fraction) <= 0.001;
        var is_past = (x_tick < now_x);
        var tick_alpha = is_past ? past_alpha : future_alpha;

        draw_set_alpha(tick_alpha);
        draw_set_color(is_major ? major_color : minor_color);
        var y_from = is_major ? _ry1 : (_ry1 + 4);
        draw_line_width(x_tick, y_from, x_tick, _ry2, is_major ? 2 : 1);

        if (!is_major) continue;

        var beat_num = (marker_type == "bar") ? 1 : floor(real(ev.beat ?? 0));
        if (beat_num < 1) continue;

        var measure_num = floor(real(ev.measure ?? 0));
        var measure_num_display = measure_num;
        var _use_canonical_model = variable_struct_exists(cfg, "use_canonical_tune_structure_model")
            && bool(variable_struct_get(cfg, "use_canonical_tune_structure_model"));
        if (_use_canonical_model) {
            measure_num_display = gv_tune_structure_model_resolve_musical_measure_at_time(marker_time, measure_num);
        }
        // Pickup segments are unlabeled in musician-facing numbering.
        if (measure_num_display <= 0) continue;
        var label = "";
        if (marker_type == "bar") {
            label = "M" + string(measure_num_display);
        } else if (!has_bar_markers && beat_num == 1) {
            // Fallback for legacy/diagnostic streams that do not include bar markers.
            label = "M" + string(measure_num_display);
        } else if (label_every_beat) {
            label = "B" + string(beat_num);
        }

        if (string_length(label) <= 0) continue;
        // Keep major measure labels visible even when split-bars produce close starts.
        if (beat_num != 1 && (x_tick - last_label_x) < label_spacing) continue;

        draw_set_alpha(tick_alpha);
        draw_set_color(text_color);
        draw_text(x_tick + 2, _ry1 + 1, label);
        last_label_x = x_tick;
    }

    draw_set_alpha(1);
    draw_set_font(_prev_font);
}

/// @function gv_draw_review_controls(_x1, _y1, _x2, _y2)
/// @description Draw the set of measure-step review buttons (+/-1, +/-8) and register their hitboxes in timeline_state.review_buttons.
/// @param {real} _x1/_y1/_x2/_y2  Area bounds.
/// @reads  global.timeline_state.playback_complete/review_measure_offset/playhead_ms
/// @writes global.timeline_state.review_buttons
function gv_draw_review_controls(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    global.timeline_state.review_buttons = [];

    var playback_complete = variable_struct_exists(global.timeline_state, "playback_complete") && global.timeline_state.playback_complete;
    if (!playback_complete) return;

    var step_small = 1;
    var step_large = 8;

    var offset_measures = variable_struct_exists(global.timeline_state, "review_measure_offset")
        ? real(global.timeline_state.review_measure_offset)
        : 0;
    var can_forward = (offset_measures < -0.001);
    var can_back = (real(global.timeline_state.playhead_ms ?? 0) > 0.5);

    var labels = ["-" + string(step_large), "-" + string(step_small), "+" + string(step_small), "+" + string(step_large)];
    var steps = [-step_large, -step_small, step_small, step_large];

    var btn_w = 32;
    var btn_h = 14;
    var btn_gap = 4;
    var margin = 6;
    var total_w = (btn_w * 4) + (btn_gap * 3);
    var x_start = _x2 - total_w - margin;
    var y_top = _y1 + margin;

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    var buttons = [];

    for (var i = 0; i < 4; i++) {
        var step = steps[i];
        var enabled = (step < 0) ? can_back : can_forward;

        var bx1 = x_start + (i * (btn_w + btn_gap));
        var by1 = y_top;
        var bx2 = bx1 + btn_w;
        var by2 = by1 + btn_h;

        draw_set_alpha(0.94);
        draw_set_color(enabled ? make_color_rgb(76, 76, 82) : make_color_rgb(46, 46, 50));
        draw_rectangle(bx1, by1, bx2, by2, false);
        draw_set_alpha(1);

        draw_set_color(enabled ? c_white : c_gray);
        draw_text((bx1 + bx2) * 0.5, (by1 + by2) * 0.5, labels[i]);

        array_push(buttons, {
            x1: bx1,
            y1: by1,
            x2: bx2,
            y2: by2,
            delta_measures: step,
            enabled: enabled
        });
    }

    global.timeline_state.review_buttons = buttons;

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

/// @function gv_draw_timeline_canvas(_x1, _y1, _x2, _y2)
/// @description Draw the static background layers of the timeline canvas (lane backgrounds only). Also ticks the step clock as fallback when no active game_viz Step event runs.
/// @param {real} _x1/_y1/_x2/_y2  Canvas bounds.
/// @reads  global.timeline_cfg, global.timeline_state
function gv_draw_timeline_canvas(_x1, _y1, _x2, _y2) {
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(cfg, "enabled") || !cfg.enabled) return;

    // Fallback tick only when the controller owner is unavailable.
    // Normal runtime ownership is obj_game_controller Step to avoid duplicate work.
    if (global.timeline_state.active) {
        var _has_controller_owner = variable_global_exists("ID_game_handler")
            && global.ID_game_handler != noone
            && instance_exists(global.ID_game_handler);
        if (!_has_controller_owner) {
            gv_timeline_step_tick();
        }
    }
    var is_active = global.timeline_state.active;

    var pad = variable_struct_exists(cfg, "padding_px") ? real(cfg.padding_px) : 8;
    var x1 = _x1 + pad;
    var y1 = _y1 + pad;
    var x2 = _x2 - pad;
    var y2 = _y2 - pad;
    if (x2 <= x1 || y2 <= y1) return;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var now_x = x1 + ((x2 - x1) * now_ratio);

    // Lane layout (bottom-up): beat bar at bottom, word lane above, staff fills rest
    var beat_h = variable_struct_exists(cfg, "tl_beat_lane_h") ? max(16, real(cfg.tl_beat_lane_h)) : 24;
    var word_h = variable_struct_exists(cfg, "tl_word_lane_h") ? max(16, real(cfg.tl_word_lane_h)) : beat_h;
    var lane_gap = 2;
    var beat_y2  = y2;
    var beat_y1  = y2 - beat_h;
    var word_y2  = beat_y1 - lane_gap;
    var word_y1  = word_y2 - word_h;
    var staff_y1 = y1;
    var staff_y2 = (word_h > 0 ? word_y1 : beat_y1) - lane_gap;
    var staff_h  = max(0, staff_y2 - staff_y1);

    var canvas_bg_color = variable_struct_exists(cfg, "canvas_bg_color") ? cfg.canvas_bg_color : make_color_rgb(16, 16, 16);
    var canvas_bg_alpha = variable_struct_exists(cfg, "canvas_bg_alpha") ? clamp(real(cfg.canvas_bg_alpha), 0, 1) : 0.97;
    draw_set_alpha(canvas_bg_alpha);
    draw_set_color(canvas_bg_color);
    draw_rectangle(x1, y1, x2, y2, false);
    draw_set_alpha(1);

    // Lane backgrounds only â€” static chrome, safe to cache.
    // Scrolling ticks + now-line are drawn by gv_draw_timeline_canvas_overlay each frame.
    draw_set_color(make_color_rgb(26, 26, 30));
    draw_set_alpha(1);
    draw_rectangle(x1, beat_y1, x2, beat_y2, false);

    // Canntaireachd / word lane (stub â€” reserved for future)
    if (word_h > 0) {
        draw_set_color(make_color_rgb(24, 24, 28));
        draw_set_alpha(1);
        draw_rectangle(x1, word_y1, x2, word_y2, false);
    }

    // Music staff lane (stub â€” reserved for future)
    if (staff_h > 8) {
        draw_set_color(make_color_rgb(20, 20, 24));
        draw_set_alpha(1);
        draw_rectangle(x1, staff_y1, x2, staff_y2, false);
    }
}

/// @function gv_draw_timeline_canvas_overlay(_x1, _y1, _x2, _y2)
/// @description Draw the per-frame overlay for the timeline canvas: scrolling beat lane and now-line. Only draws when timeline is active.
/// @param {real} _x1/_y1/_x2/_y2  Canvas bounds.
/// @reads  global.timeline_cfg, global.timeline_state.active/playhead_ms/ms_behind/ms_ahead, global.playback_context, global.loop_runtime_active
function gv_draw_timeline_canvas_overlay(_x1, _y1, _x2, _y2) {
    // Contains all scrolling/time-sensitive content.
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(cfg, "enabled") || !cfg.enabled) return;
    var is_active = variable_struct_exists(global.timeline_state, "active") && global.timeline_state.active;
    var visual_cal_ms = variable_struct_exists(cfg, "visual_alignment_offset_ms")
        ? real(cfg.visual_alignment_offset_ms)
        : 0;

    var pad = variable_struct_exists(cfg, "padding_px") ? real(cfg.padding_px) : 8;
    var x1 = _x1 + pad;  var y1 = _y1 + pad;
    var x2 = _x2 - pad;  var y2 = _y2 - pad;
    if (x2 <= x1 || y2 <= y1) return;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var now_x = x1 + ((x2 - x1) * now_ratio);

    var beat_h = variable_struct_exists(cfg, "tl_beat_lane_h") ? max(16, real(cfg.tl_beat_lane_h)) : 24;
    var word_h = variable_struct_exists(cfg, "tl_word_lane_h") ? max(16, real(cfg.tl_word_lane_h)) : beat_h;
    var lane_gap = 2;
    var beat_y2  = y2;
    var beat_y1  = beat_y2 - beat_h;
    var word_y2  = beat_y1 - lane_gap;
    var word_y1  = word_y2 - word_h;
    var staff_y1 = y1;
    var staff_y2 = (word_h > 0 ? word_y1 : beat_y1) - lane_gap;
    var staff_h  = max(0, staff_y2 - staff_y1);

    var score_images_visible = gv_should_draw_timeline_score_images();

    // Score images: re-enabled with geometry metadata support (Milestone D-1, B-4)
    // Keep this scoped to active playback; beat lane still draws below even when inactive.
    if (is_active && staff_h > 8 && score_images_visible) {
        // Score background
        draw_set_alpha(1);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_rectangle(x1, staff_y1, x2, staff_y2, false);

        var _spr_count = (variable_global_exists("score_lane_sprites")) ? array_length(global.score_lane_sprites) : -1;
        if (_spr_count > 0) {
            var _playhead_raw = max(0, real(global.timeline_state.playhead_ms ?? 0) + visual_cal_ms);
            var _playhead = _playhead_raw;
            var _ms_behind = variable_struct_exists(global.timeline_state, "ms_behind") ? real(global.timeline_state.ms_behind) : 2000;
            var _ms_ahead  = variable_struct_exists(global.timeline_state, "ms_ahead")  ? real(global.timeline_state.ms_ahead)  : 4000;
            var _set_mode = variable_global_exists("playback_context")
                && is_struct(global.playback_context)
                && string(global.playback_context[$ "mode"] ?? "") == "set";
            var _single_tune_loop_runtime = !_set_mode
                && variable_global_exists("loop_runtime_active")
                && bool(global.loop_runtime_active);
            var _loop_session_draw = undefined;
            var _loop_session_draw_active = false;
            if (variable_struct_exists(global.timeline_state, "loop_session")
                && is_struct(global.timeline_state.loop_session)) {
                _loop_session_draw = global.timeline_state.loop_session;
                _loop_session_draw_active = variable_struct_exists(_loop_session_draw, "active")
                    && bool(variable_struct_get(_loop_session_draw, "active"));
            }
            var _loop_cache_draw = (variable_struct_exists(global.timeline_state, "loop_runtime_cache")
                && is_struct(global.timeline_state.loop_runtime_cache))
                ? global.timeline_state.loop_runtime_cache
                : undefined;
            var _iter1_start_cached = -1;
            var _loop_cycle_cached = 0;
            var _use_loop_projection = false;
            var _proj_min_k = 0;
            var _proj_max_k = 0;

            // Build per-measure start times from planned events.
            // In set mode, include all segments so future tunes can scroll into view.
            var _events = gv_get_planned_events_for_viz();
            if (_single_tune_loop_runtime && _loop_session_draw_active) {
                var _ls_start_draw = max(0, real(variable_struct_exists(_loop_session_draw, "start_ms")
                    ? variable_struct_get(_loop_session_draw, "start_ms") : 0));
                var _ls_pass_draw = max(1, real(variable_struct_exists(_loop_session_draw, "pass_duration_ms")
                    ? variable_struct_get(_loop_session_draw, "pass_duration_ms") : 0));
                var _ls_core_pass_draw = max(1, real(variable_struct_exists(_loop_session_draw, "core_pass_duration_ms")
                    ? variable_struct_get(_loop_session_draw, "core_pass_duration_ms") : _ls_pass_draw));
                _ls_core_pass_draw = min(_ls_core_pass_draw, _ls_pass_draw);
                var _ls_spacer_draw_enabled = variable_struct_exists(_loop_session_draw, "spacer_enabled")
                    && bool(variable_struct_get(_loop_session_draw, "spacer_enabled"));
                var _ls_spacer_draw = _ls_spacer_draw_enabled
                    ? max(0, real(variable_struct_exists(_loop_session_draw, "spacer_duration_ms")
                        ? variable_struct_get(_loop_session_draw, "spacer_duration_ms") : 0))
                    : 0;
                _iter1_start_cached = _ls_start_draw;
                _loop_cycle_cached = _ls_pass_draw + _ls_spacer_draw;
                if (_loop_cycle_cached > 1 && _playhead >= _iter1_start_cached) {
                    var _loop_dt_cached = _playhead - _iter1_start_cached;
                    var _loop_mod_cached = _loop_dt_cached mod _loop_cycle_cached;
                    if (_loop_mod_cached < 0) _loop_mod_cached += _loop_cycle_cached;

                    // During spacer, hide score projection entirely.
                    if (_loop_mod_cached >= _ls_pass_draw) {
                        _use_loop_projection = false;
                    } else {
                        if (_loop_mod_cached >= _ls_core_pass_draw) {
                            _loop_mod_cached = max(0, _ls_core_pass_draw - 0.001);
                        }
                        _playhead = _iter1_start_cached + _loop_mod_cached;
                        nav_display_ms = _playhead;
                        _use_loop_projection = true;

                        var _window_start = _playhead - _ms_behind;
                        var _window_end = _playhead + _ms_ahead;
                        _proj_min_k = floor((_window_start - _iter1_start_cached) / _loop_cycle_cached) - 1;
                        _proj_max_k = floor((_window_end - _iter1_start_cached) / _loop_cycle_cached) + 1;
                    }
                }
            } else if (_single_tune_loop_runtime
                && is_struct(_loop_cache_draw)
                && bool(_loop_cache_draw[$ "valid"] ?? false)) {
                // Backward-compatible fallback for legacy loop sessions.
                _iter1_start_cached = real(_loop_cache_draw[$ "phase_start_ms"] ?? (_loop_cache_draw[$ "iter1_start_ms"] ?? -1));
                _loop_cycle_cached = real(_loop_cache_draw[$ "loop_cycle_ms"] ?? 0);
                if (_loop_cycle_cached > 1 && _iter1_start_cached >= 0 && _playhead >= _iter1_start_cached) {
                    var _loop_dt_cached_fallback = _playhead - _iter1_start_cached;
                    var _loop_mod_cached_fallback = _loop_dt_cached_fallback mod _loop_cycle_cached;
                    if (_loop_mod_cached_fallback < 0) _loop_mod_cached_fallback += _loop_cycle_cached;
                    _playhead = _iter1_start_cached + _loop_mod_cached_fallback;
                    _use_loop_projection = true;

                    var _window_start_fallback = _playhead - _ms_behind;
                    var _window_end_fallback = _playhead + _ms_ahead;
                    _proj_min_k = floor((_window_start_fallback - _iter1_start_cached) / _loop_cycle_cached) - 1;
                    _proj_max_k = floor((_window_end_fallback - _iter1_start_cached) / _loop_cycle_cached) + 1;
                }
            }
            var _measure_starts = array_create(0); // [{m,p,b,t,seq,seg_idx,seg_title,seg_start_ms,seg_end_ms}]
            var _nm = 0;
            var _fallback_measure_ms = 1000;
            var _seg_measure_counts = [];
            var _seg_raw_measure_counts = []; // original (uncut) count per segment, for tail override anchor
            var _set_segments = _set_mode ? global.playback_context[$ "segments"] : [];
            var _set_seg_count = is_array(_set_segments) ? array_length(_set_segments) : 0;
            var _seg_start_ms = -1;
            var _seg_end_ms = -1;
            var _seg_title = "";
            var _seg_idx = -1;
            var _plan_canonical_seq_by_measure = undefined;
            var _score_layout_cache_hit = false;
            var _score_layout_cache_key = "";
            var _score_plan_cache_hit = false;
            if (!variable_struct_exists(global.timeline_state, "score_render_plan_stats")
                || !is_struct(global.timeline_state.score_render_plan_stats)) {
                global.timeline_state.score_render_plan_stats = {
                    hits: 0,
                    misses: 0,
                    builds: 0,
                    invalidations: 0,
                    last_log_ms: 0,
                    last_reason: "init"
                };
            }
            var _score_plan_stats = global.timeline_state.score_render_plan_stats;

            // Active-segment metadata (for debug focus and override-group application).
            if (_set_mode) {
                _seg_idx = floor(real(global.playback_context[$ "active_segment"] ?? 0));
                if (_seg_idx >= 0 && _seg_idx < _set_seg_count) {
                    var _seg_cur = _set_segments[_seg_idx];
                    if (is_struct(_seg_cur)) {
                        _seg_start_ms = real(_seg_cur[$ "start_ms"] ?? -1);
                        _seg_end_ms = real(_seg_cur[$ "end_ms"] ?? -1);
                        _seg_title = string(_seg_cur[$ "title"] ?? _seg_cur[$ "filename"] ?? "");
                    }
                }
            }

            var _skip_met = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
            var _met_ch   = _skip_met ? real(global.METRONOME_CONFIG.channel) : -999;

            var _score_target_tune_channel = gv_get_target_tune_channel();

            // Preferred path: consume precomputed score render plan when valid.
            if (variable_struct_exists(global.timeline_state, "score_render_plan")
                && is_struct(global.timeline_state.score_render_plan)
                && (!variable_struct_exists(global.timeline_state, "score_render_plan_needs_rebuild")
                    || !bool(global.timeline_state.score_render_plan_needs_rebuild))) {
                var _plan = global.timeline_state.score_render_plan;
                var _plan_mode = string(_plan[$ "mode"] ?? "");
                var _expect_mode = _set_mode ? "set" : "tune";
                var _plan_items = _plan[$ "items"] ?? [];
                var _plan_loop = bool(_plan[$ "built_for_loop"] ?? false);
                var _plan_events = floor(real(_plan[$ "source_event_count"] ?? -1));
                var _plan_target_channel = floor(real(_plan[$ "target_tune_channel"] ?? -1));
                var _current_events = is_array(_events) ? array_length(_events) : 0;
                if (bool(_plan[$ "valid"] ?? false)
                    && _plan_mode == _expect_mode
                    && _plan_loop == _single_tune_loop_runtime
                    && (_set_mode || _plan_target_channel == _score_target_tune_channel)
                    && is_array(_plan_items)
                    && array_length(_plan_items) > 0
                    && (_plan_events < 0 || _plan_events == _current_events)) {
                    _measure_starts = _plan_items;
                    _nm = array_length(_measure_starts);
                    _fallback_measure_ms = max(1, real(_plan[$ "fallback_measure_ms"] ?? 1000));
                    _seg_raw_measure_counts = _plan[$ "seg_raw_measure_counts"] ?? [];
                    _plan_canonical_seq_by_measure = _plan[$ "canonical_seq_by_measure"] ?? undefined;
                    _score_layout_cache_hit = true;
                    _score_plan_cache_hit = true;
                    _score_plan_stats.hits += 1;
                }
            }
            if (!_score_plan_cache_hit) {
                _score_plan_stats.misses += 1;
            }

            if (!_set_mode && !_single_tune_loop_runtime) {
                var _zoom_preset_idx = variable_struct_exists(cfg, "notebeam_zoom_preset_index")
                    ? floor(real(variable_struct_get(cfg, "notebeam_zoom_preset_index")))
                    : -1;
                var _score_cache_event_count = is_array(_events) ? array_length(_events) : 0;
                var _score_cache_pbmap_count = (variable_global_exists("score_playback_map") && is_array(global.score_playback_map))
                    ? array_length(global.score_playback_map)
                    : 0;
                var _score_cache_dur_count = (variable_global_exists("score_snippet_durations") && is_array(global.score_snippet_durations))
                    ? array_length(global.score_snippet_durations)
                    : 0;
                var _score_cache_has_pickup = variable_global_exists("score_has_pickup") && bool(global.score_has_pickup);
                var _selected_playable_measure_count = gv_count_selected_channel_score_measures(_events);

                _score_layout_cache_key = string(_zoom_preset_idx)
                    + "|" + string_format(_ms_ahead, 0, 3)
                    + "|" + string_format(_ms_behind, 0, 3)
                    + "|ch=" + string(_score_target_tune_channel)
                    + "|selm=" + string(_selected_playable_measure_count)
                    + "|" + string(_score_cache_event_count)
                    + "|" + string(_score_cache_pbmap_count)
                    + "|" + string(_score_cache_dur_count)
                    + "|" + string(_score_cache_has_pickup)
                    + "|" + string(floor(gv_get_planned_end_ms()));

                if (variable_struct_exists(global.timeline_state, "score_lane_layout_cache_single")) {
                    var _single_cache = global.timeline_state.score_lane_layout_cache_single;
                    if (is_struct(_single_cache)) {
                        var _cached_key = string(_single_cache[$ "key"] ?? "");
                        var _cached_starts = _single_cache[$ "measure_starts"] ?? [];
                        if (_cached_key == _score_layout_cache_key
                            && is_array(_cached_starts)
                            && array_length(_cached_starts) > 0) {
                            _measure_starts = _cached_starts;
                            _nm = array_length(_measure_starts);
                            _fallback_measure_ms = max(1, real(_single_cache[$ "fallback_measure_ms"] ?? 1000));
                            if (variable_struct_exists(_single_cache, "structural_measure_starts")
                                && is_array(_single_cache[$ "structural_measure_starts"])) {
                                global.timeline_state.structural_measure_starts = _single_cache[$ "structural_measure_starts"];
                            }
                            _score_layout_cache_hit = true;
                        }
                    }
                }
            }

            if (!_score_layout_cache_hit) {
            if (_set_mode) {
                for (var _sidx = 0; _sidx < _set_seg_count; _sidx++) {
                    var _seg = _set_segments[_sidx];
                    if (!is_struct(_seg)) continue;

                    var _seg_s = real(_seg[$ "start_ms"] ?? -1);
                    var _seg_e = real(_seg[$ "end_ms"] ?? -1);
                    var _seg_t = string(_seg[$ "title"] ?? _seg[$ "filename"] ?? "");
                    var _seg_seq = 0;

                    // Source-of-truth parity with single-tune mode:
                    // if structural snippet durations are available for this segment,
                    // build starts from those durations first, then fall back to
                    // marker-derived starts only when duration metadata is missing.
                    var _seg_durations = [];
                    var _seg_units_per_measure = 0;
                    var _seg_cache_for_dur = undefined;
                    if (variable_global_exists("score_segments_sprites") && is_array(global.score_segments_sprites)
                        && _sidx >= 0 && _sidx < array_length(global.score_segments_sprites)) {
                        _seg_cache_for_dur = global.score_segments_sprites[_sidx];
                        if (is_struct(_seg_cache_for_dur)) {
                            _seg_durations = _seg_cache_for_dur[$ "durations"] ?? [];
                            _seg_units_per_measure = real(_seg_cache_for_dur[$ "units_per_measure"] ?? 0);
                        }
                    }

                    if (is_array(_seg_durations) && array_length(_seg_durations) > 0
                        && _seg_s >= 0 && _seg_e > _seg_s) {
                        // In set mode, segment content_end_ms reflects musical cuts. When
                        // active-segment head/tail overrides are present, trim the structural
                        // duration list used for timing so early measures are not globally
                        // compressed to fit a shortened segment.
                        var _timing_durations = _seg_durations;
                        var _trim_head = 0;
                        var _trim_tail = 0;
                        if (_sidx == _seg_idx
                            && variable_global_exists("score_override_groups")
                            && is_struct(global.score_override_groups)) {
                            var _head_bundle_timing = variable_struct_exists(global.score_override_groups, "head")
                                ? global.score_override_groups[$ "head"] : undefined;
                            var _tail_bundle_timing = variable_struct_exists(global.score_override_groups, "tail")
                                ? global.score_override_groups[$ "tail"] : undefined;
                            _trim_head = is_struct(_head_bundle_timing)
                                ? max(0, floor(real(_head_bundle_timing[$ "count_measures"] ?? 0))) : 0;
                            _trim_tail = is_struct(_tail_bundle_timing)
                                ? max(0, floor(real(_tail_bundle_timing[$ "count_measures"] ?? 0))) : 0;

                            var _raw_n = array_length(_seg_durations);
                            _trim_head = min(_trim_head, _raw_n);
                            _trim_tail = min(_trim_tail, max(0, _raw_n - _trim_head));

                            if (_trim_head > 0 || _trim_tail > 0) {
                                var _trim_start = _trim_head;
                                var _trim_end_excl = _raw_n - _trim_tail;
                                if (_trim_end_excl <= _trim_start) {
                                    _trim_start = 0;
                                    _trim_end_excl = _raw_n;
                                }
                                var _trimmed = [];
                                for (var _ti = _trim_start; _ti < _trim_end_excl; _ti++) {
                                    array_push(_trimmed, _seg_durations[_ti]);
                                }
                                if (array_length(_trimmed) > 0) {
                                    _timing_durations = _trimmed;
                                }
                            }
                        }

                        var _dur_n = array_length(_timing_durations);
                        var _dur_total_units = 0;
                        for (var _dui = 0; _dui < _dur_n; _dui++) {
                            _dur_total_units += max(0.0001, real(_timing_durations[_dui]));
                        }

                        // Use content_end_ms (excludes boundary lead-in hold window) so
                        // score images are not stretched across the hold time.
                        var _seg_content_e = real(_seg[$ "content_end_ms"] ?? _seg_e);
                        var _seg_len_ms = max(1, _seg_content_e - _seg_s);
                        var _dur_ms_per_unit = (_dur_total_units > 0)
                            ? (_seg_len_ms / _dur_total_units)
                            : (_seg_len_ms / max(1, _dur_n));

                        var _dur_t = _seg_s;
                        var _display_measure = 0;
                        var _first_is_pickup = is_struct(_seg_cache_for_dur)
                            && bool(_seg_cache_for_dur[$ "has_pickup"] ?? false)
                            && (_trim_head <= 0);

                        for (var _dsi = 0; _dsi < _dur_n; _dsi++) {
                            var _dur_units = max(0.0001, real(_timing_durations[_dsi]));
                            var _is_pickup = (_dsi == 0) && _first_is_pickup;
                            var _display_m = 0;
                            if (_is_pickup) {
                                _display_m = 0;
                            } else {
                                _display_measure += 1;
                                _display_m = _display_measure;
                            }

                            array_push(_measure_starts, {
                                m: _display_m,
                                p: 1,
                                b: 1,
                                t: _dur_t,
                                seq: _seg_seq,
                                seg_idx: _sidx,
                                seg_title: _seg_t,
                                seg_start_ms: _seg_s,
                                seg_content_end_ms: real(_seg[$ "content_end_ms"] ?? _seg_e),
                                seg_end_ms: _seg_e
                            });
                            _seg_seq++;
                            _dur_t += max(1, _dur_units * _dur_ms_per_unit);
                        }

                        _seg_measure_counts[_sidx] = _seg_seq;
                        _seg_raw_measure_counts[_sidx] = array_length(_seg_durations);
                        continue;
                    }

                    var _seg_src = _seg[$ "bar_events"] ?? [];
                    if (!is_array(_seg_src) || array_length(_seg_src) <= 0) continue;

                    // Resolve per-segment visual capacity/mapping from preloaded score cache.
                    var _seg_pbmap = [];
                    var _seg_pbmap_len = 0;
                    var _seg_sprite_count = 0;
                    if (variable_global_exists("score_segments_sprites") && is_array(global.score_segments_sprites)
                        && _sidx >= 0 && _sidx < array_length(global.score_segments_sprites)) {
                        var _seg_cache_entry = global.score_segments_sprites[_sidx];
                        if (is_struct(_seg_cache_entry)) {
                            _seg_pbmap = _seg_cache_entry[$ "pbmap"] ?? [];
                            _seg_pbmap_len = is_array(_seg_pbmap) ? array_length(_seg_pbmap) : 0;
                            var _seg_sprites = _seg_cache_entry[$ "sprites"] ?? [];
                            _seg_sprite_count = is_array(_seg_sprites) ? array_length(_seg_sprites) : 0;
                        }
                    }

                    var _seg_has_bar = false;
                    var _seg_has_beat1 = false;
                    var _seg_n = array_length(_seg_src);
                    for (var _sj = 0; _sj < _seg_n; _sj++) {
                        var _sm = _seg_src[_sj];
                        if (!is_struct(_sm)) continue;
                        if (string(_sm[$ "type"] ?? "") != "marker") continue;
                        var _sm_type = string(_sm[$ "marker_type"] ?? "");
                        if (_sm_type == "bar") {
                            _seg_has_bar = true;
                            continue;
                        }
                        if (_sm_type == "beat") {
                            var _sm_beat = floor(real(_sm[$ "beat"] ?? 0));
                            var _sm_frac = real(_sm[$ "beat_fraction"] ?? 0);
                            if (_sm_beat == 1 && abs(_sm_frac) <= 0.001) _seg_has_beat1 = true;
                        }
                    }
                    var _seg_marker_mode = _seg_has_bar ? "bar" : (_seg_has_beat1 ? "beat1" : "");
                    var _allow_note_fallback = (_seg_marker_mode == "");

                    var _seg_last_key = "";
                    for (var _si = 0; _si < _seg_n; _si++) {
                        var _ev = _seg_src[_si];
                        if (!is_struct(_ev)) continue;

                        var _etype = variable_struct_exists(_ev, "type") ? string(_ev.type) : "";
                        var _is_measure_start = false;
                        if (_etype == "marker") {
                            var _marker_type = string(_ev[$ "marker_type"] ?? "");
                            var _marker_beat = floor(real(_ev[$ "beat"] ?? 0));
                            var _marker_frac = real(_ev[$ "beat_fraction"] ?? 0);
                            if (_seg_marker_mode == "bar") {
                                _is_measure_start = (_marker_type == "bar");
                            } else if (_seg_marker_mode == "beat1") {
                                _is_measure_start = (_marker_type == "beat" && _marker_beat == 1 && abs(_marker_frac) <= 0.001);
                            } else {
                                _is_measure_start = (_marker_type == "bar") || (_marker_type == "beat" && _marker_beat == 1 && abs(_marker_frac) <= 0.001);
                            }
                        }
                        if (!_is_measure_start && _allow_note_fallback && _etype == "note_on") _is_measure_start = true;
                        if (!_is_measure_start) continue;

                        var _et = gv_evt_time_ms(_ev);
                        var _em = variable_struct_exists(_ev, "measure") ? floor(real(_ev.measure)) : -999;
                        if (_em < 0) continue;
                        // Drop carryover boundary events from the previous segment.
                        if (_seg_s >= 0 && _et <= _seg_s && _em > 2) continue;
                        if (_seg_s >= 0 && _et < _seg_s) continue;
                        if (_seg_e > _seg_s && _et >= _seg_e) continue;

                        if (_skip_met && _etype == "note_on") {
                            var _ch = variable_struct_exists(_ev, "channel") ? real(_ev.channel) : 0;
                            if (_ch == _met_ch) continue;
                        }

                        var _part = variable_struct_exists(_ev, "part") ? floor(real(_ev.part)) : 1;
                        var _beat = variable_struct_exists(_ev, "beat") ? floor(real(_ev.beat)) : 0;

                        // In set mode we anchor displayed measures at full measures.
                        // Ignore marker/note starts with non-positive measure labels.
                        if (_em <= 0) continue;

                        // Emit only starts that can map to a real score sprite for this segment.
                        if (_seg_pbmap_len > 0) {
                            if (_seg_seq >= _seg_pbmap_len) continue;
                            var _mapped_img = floor(real(_seg_pbmap[_seg_seq] ?? _seg_seq));
                            if (_seg_sprite_count > 0 && (_mapped_img < 0 || _mapped_img >= _seg_sprite_count)) continue;
                        } else if (_seg_sprite_count > 0 && _seg_seq >= _seg_sprite_count) {
                            continue;
                        }

                        // De-duplicate multi-voice starts: one visual start per sequential measure index.
                        var _key = string(_em);
                        if (_key == _seg_last_key) continue;
                        _seg_last_key = _key;

                        array_push(_measure_starts, {
                            m: _em,
                            p: _part,
                            b: _beat,
                            t: _et,
                            seq: _seg_seq,
                            seg_idx: _sidx,
                            seg_title: _seg_t,
                            seg_start_ms: _seg_s,
                            seg_content_end_ms: real(_seg[$ "content_end_ms"] ?? _seg_e),
                            seg_end_ms: _seg_e
                        });
                        _seg_seq++;
                    }

                    _seg_measure_counts[_sidx] = _seg_seq;
                }
            } else if (_single_tune_loop_runtime
                && is_struct(_loop_session_draw)
                && variable_struct_exists(_loop_session_draw, "timeline_segments")
                && is_array(variable_struct_get(_loop_session_draw, "timeline_segments"))
                && array_length(variable_struct_get(_loop_session_draw, "timeline_segments")) > 0) {
                var _tls = variable_struct_get(_loop_session_draw, "timeline_segments");
                var _has_pickup_map = variable_global_exists("score_has_pickup") && bool(global.score_has_pickup);
                var _loop_runtime_start_ms = real(_loop_session_draw[$ "start_ms"] ?? -1);

                // Prelude measures must still render before the loop body starts.
                // Build one canonical prelude pass from active events, then mark it
                // as non-repeating so loop phase projection does not replicate it.
                if (is_array(_events) && _loop_runtime_start_ms > 0) {
                    var _prelude_seen = {};
                    for (var _pei = 0; _pei < array_length(_events); _pei++) {
                        var _pev = _events[_pei];
                        if (!is_struct(_pev)) continue;
                        var _ptype = string(_pev[$ "type"] ?? "");
                        var _is_start = false;
                        if (_ptype == "marker") {
                            var _pmt = string(_pev[$ "marker_type"] ?? "");
                            var _pbeat = floor(real(_pev[$ "beat"] ?? 0));
                            var _pfrac = real(_pev[$ "beat_fraction"] ?? 0);
                            _is_start = (_pmt == "bar") || (_pmt == "beat" && _pbeat == 1 && abs(_pfrac) <= 0.001);
                        }
                        if (!_is_start) continue;

                        var _pt = gv_evt_time_ms(_pev);
                        if (_pt >= _loop_runtime_start_ms - 0.001) break;

                        var _pm = floor(real(_pev[$ "measure"] ?? -999));
                        if (_pm <= 0) continue;
                        var _pp = max(1, floor(real(_pev[$ "part"] ?? 1)));
                        var _pkey = string(_pp) + ":" + string(_pm);
                        if (variable_struct_exists(_prelude_seen, _pkey)) continue;
                        _prelude_seen[$ _pkey] = true;

                        var _pseq = (_pm == 0) ? 0 : (_pm - (_has_pickup_map ? 0 : 1));
                        array_push(_measure_starts, {
                            m: _pm,
                            p: _pp,
                            b: 1,
                            t: _pt,
                            seq: _pseq,
                            seg_idx: -1,
                            seg_title: "",
                            seg_start_ms: _pt,
                            seg_end_ms: _loop_runtime_start_ms,
                            loop_repeatable: false
                        });
                    }
                }

                for (var _tsi = 0; _tsi < array_length(_tls); _tsi++) {
                    var _segm = _tls[_tsi];
                    if (!is_struct(_segm)) continue;

                    var _ts = real(_segm[$ "start_ms"] ?? -1);
                    var _te = real(_segm[$ "end_ms"] ?? -1);
                    if (_ts < 0 || _te <= _ts + 0.001) continue;

                    var _m_owner = floor(real(_segm[$ "owner_measure"] ?? (_segm[$ "measure"] ?? -1)));
                    if (_m_owner < 0) continue;
                    var _p_owner = max(1, floor(real(_segm[$ "part"] ?? 1)));

                    var _seq_owner = -1;
                    if (_m_owner == 0) {
                        _seq_owner = 0;
                    } else if (_m_owner > 0) {
                        _seq_owner = _m_owner - (_has_pickup_map ? 0 : 1);
                    }

                    array_push(_measure_starts, {
                        m: _m_owner,
                        p: _p_owner,
                        b: 1,
                        t: _ts,
                        seq: _seq_owner,
                        seg_idx: -1,
                        seg_title: "",
                        seg_start_ms: _ts,
                        seg_end_ms: _te,
                        loop_repeatable: true
                    });
                }

                if (array_length(_measure_starts) > 1) {
                    array_sort(_measure_starts, function(a, b) {
                        var at = real(a[$ "t"] ?? 0);
                        var bt = real(b[$ "t"] ?? 0);
                        if (at != bt) return at - bt;
                        var am = floor(real(a[$ "m"] ?? -1));
                        var bm = floor(real(b[$ "m"] ?? -1));
                        return am - bm;
                    });
                }

                var _loop_compact = [];
                for (var _lci = 0; _lci < array_length(_measure_starts); _lci++) {
                    var _cur = _measure_starts[_lci];
                    if (!is_struct(_cur)) continue;
                    if (array_length(_loop_compact) > 0) {
                        var _prev = _loop_compact[array_length(_loop_compact) - 1];
                        var _prev_m = floor(real(_prev[$ "m"] ?? -1));
                        var _cur_m = floor(real(_cur[$ "m"] ?? -1));
                        var _prev_t = real(_prev[$ "t"] ?? -1);
                        var _cur_t = real(_cur[$ "t"] ?? -1);
                        if (_prev_m == _cur_m && abs(_cur_t - _prev_t) <= 0.001) continue;
                    }
                    array_push(_loop_compact, _cur);
                }
                _measure_starts = _loop_compact;

            } else if (is_array(_events)) {
                var _ne = array_length(_events);
                var _has_marker_timing = false;
                for (var _mi_probe = 0; _mi_probe < _ne; _mi_probe++) {
                    var _probe = _events[_mi_probe];
                    if (!is_struct(_probe)) continue;
                    if (string(_probe[$ "type"] ?? "") != "marker") continue;
                    var _probe_mt = string(_probe[$ "marker_type"] ?? "");
                    var _probe_beat = floor(real(_probe[$ "beat"] ?? 0));
                    var _probe_frac = real(_probe[$ "beat_fraction"] ?? 0);
                    if (_probe_mt == "bar" || (_probe_mt == "beat" && _probe_beat == 1 && abs(_probe_frac) <= 0.001)) {
                        _has_marker_timing = true;
                        break;
                    }
                }
                var _allow_note_fallback_single = !_has_marker_timing;
                var _last_key = "";
                var _seq = 0;
                for (var _i = 0; _i < _ne; _i++) {
                    var _ev = _events[_i];
                    if (!is_struct(_ev)) continue;
                    var _etype = variable_struct_exists(_ev, "type") ? string(_ev.type) : "";

                    var _is_measure_start = false;
                    if (_etype == "marker") {
                        var _marker_type = string(_ev[$ "marker_type"] ?? "");
                        var _marker_beat = floor(real(_ev[$ "beat"] ?? 0));
                        var _marker_frac = real(_ev[$ "beat_fraction"] ?? 0);
                        _is_measure_start = (_marker_type == "bar") || (_marker_type == "beat" && _marker_beat == 1 && abs(_marker_frac) <= 0.001);
                    }
                    if (!_is_measure_start && _allow_note_fallback_single && _etype == "note_on") _is_measure_start = true;
                    if (!_is_measure_start) continue;

                    var _et = gv_evt_time_ms(_ev);
                    var _em = variable_struct_exists(_ev, "measure") ? floor(real(_ev.measure)) : -999;
                    if (_em <= 0) continue;
                    if (_skip_met && _etype == "note_on") {
                        var _ch = variable_struct_exists(_ev, "channel") ? real(_ev.channel) : 0;
                        if (_ch == _met_ch) continue;
                    }

                    var _part = variable_struct_exists(_ev, "part") ? floor(real(_ev.part)) : 1;
                    var _beat = variable_struct_exists(_ev, "beat") ? floor(real(_ev.beat)) : 0;
                    // De-duplicate multi-voice starts: one visual start per sequential measure index.
                    var _key = string(_em);
                    if (_key == _last_key) continue;
                    _last_key = _key;

                    array_push(_measure_starts, {
                        m: _em,
                        p: _part,
                        b: _beat,
                        t: _et,
                        seq: _seq,
                        seg_idx: -1,
                        seg_title: "",
                        seg_start_ms: -1,
                        seg_end_ms: -1
                    });
                    _seq++;
                }
            }

            // Single-tune loop fallback: if no starts were derived from active events,
            // reuse loop runtime cache starts as a last resort.
            if (!_set_mode
                && _single_tune_loop_runtime
                && array_length(_measure_starts) <= 0
                && is_struct(_loop_cache_draw)
                && bool(_loop_cache_draw[$ "valid"] ?? false)
                && is_array(_loop_cache_draw[$ "measure_starts"])
                && array_length(_loop_cache_draw[$ "measure_starts"]) > 0) {
                _measure_starts = _loop_cache_draw[$ "measure_starts"];
            }
            _nm = array_length(_measure_starts);
            _fallback_measure_ms = 1000;
            if (_nm >= 2) {
                _fallback_measure_ms = max(1,
                    real(variable_struct_get(_measure_starts[_nm - 1], "t"))
                    - real(variable_struct_get(_measure_starts[_nm - 2], "t")));
            } else if (_set_mode && _seg_start_ms >= 0 && _seg_end_ms > _seg_start_ms) {
                _fallback_measure_ms = max(1, _seg_end_ms - _seg_start_ms);
            }

            var _structural_durations = (!_set_mode && variable_global_exists("score_snippet_durations")
                && is_array(global.score_snippet_durations)) ? global.score_snippet_durations : [];
            var _structural_duration_count = array_length(_structural_durations);
            var _target_map_count = (!_set_mode && is_array(global.score_playback_map))
                ? array_length(global.score_playback_map)
                : 0;

            // Single-tune authoritative path: when exported image durations exist and line up with
            // playback_to_image, build measure starts directly from score structure rather than
            // event-marker timing. This removes split-bar ambiguity entirely.
            if (!_set_mode && !_single_tune_loop_runtime && _structural_duration_count > 0 && _nm > 0) {
                var _selected_playable_measure_count_draw = gv_count_selected_channel_score_measures(_events);
                var _units_per_measure = variable_global_exists("score_units_per_measure")
                    ? real(global.score_units_per_measure)
                    : 0;
                // Compute ms_per_unit from the marker-derived starts to preserve playback calibration.
                var _marker_measure_ms = max(1, real(variable_struct_get(_measure_starts[0], "t")));
                if (_nm >= 2) {
                    _marker_measure_ms = max(1,
                        real(variable_struct_get(_measure_starts[1], "t"))
                        - real(variable_struct_get(_measure_starts[0], "t")));
                }
                var _ms_per_unit = _units_per_measure > 0 ? (_marker_measure_ms / _units_per_measure) : 1;
                
                // Check if first snippet is a pickup: flag comes from the exported JSON.
                var _first_is_pickup = (variable_global_exists("score_has_pickup") ? global.score_has_pickup : false);
                var _structural_cap_count = _structural_duration_count;
                if (_selected_playable_measure_count_draw > 0) {
                    var _cap_with_pickup_draw = _selected_playable_measure_count_draw + (_first_is_pickup ? 1 : 0);
                    _structural_cap_count = min(_structural_duration_count, _cap_with_pickup_draw);
                }
                
                var _structural_measure_starts = [];
                var _observed_first_measure_raw = floor(real(variable_struct_get(_measure_starts[0], "m")));
                var _observed_first_measure = _observed_first_measure_raw;
                if (_observed_first_measure < 1) _observed_first_measure = 1;
                var _structural_t = real(variable_struct_get(_measure_starts[0], "t"));
                var _missing_lead_count = _observed_first_measure - 1;
                if (_missing_lead_count > 0) {
                    var _lead_back_ms = 0;
                    var _lead_limit = min(_missing_lead_count, _structural_cap_count);
                    for (var _lead_i = 0; _lead_i < _lead_limit; _lead_i++) {
                        _lead_back_ms += max(1, real(_structural_durations[_lead_i]) * _ms_per_unit);
                    }
                    _structural_t -= _lead_back_ms;
                }
                // If marker-derived starts begin at measure 1, but snippet 0 is an opening
                // pickup, shift the structural timeline back by exactly the pickup duration.
                // This keeps score images and beat markers phase-aligned in single-tune mode.
                if (_first_is_pickup && _observed_first_measure_raw >= 1) {
                    _structural_t -= max(1, real(_structural_durations[0]) * _ms_per_unit);
                }
                // Measure numbering should start at 1 for the first full bar.
                // If snippet 0 is a pickup, it is explicitly assigned measure 0
                // and does not consume a measure number.
                var _next_measure_num = 1;
                
                for (var _sd_i = 0; _sd_i < _structural_cap_count; _sd_i++) {
                    var _duration_units = real(_structural_durations[_sd_i]);
                    // Only snippet 0 can represent an opening pickup; later short snippets are real measures.
                    var _is_pickup_snippet = (_sd_i == 0)
                        && (_units_per_measure > 0)
                        && (_duration_units < (_units_per_measure - 0.02));
                    var _structural_m = _next_measure_num;
                    if (_is_pickup_snippet) {
                        _structural_m = (_sd_i <= 0) ? 0 : max(1, _next_measure_num - 1);
                    }
                    
                    array_push(_structural_measure_starts, {
                        m: _structural_m,
                        p: 1,
                        b: 1,
                        t: _structural_t,
                        seq: _sd_i,
                        seg_idx: -1,
                        seg_title: "",
                        seg_start_ms: -1,
                        seg_end_ms: -1
                    });

                    var _duration_ms = max(1, _duration_units * _ms_per_unit);
                    _structural_t += _duration_ms;
                    
                    // Only full measures advance display numbering.
                    if (!_is_pickup_snippet) {
                        _next_measure_num++;
                    }
                }

                _measure_starts = _structural_measure_starts;
                _nm = array_length(_measure_starts);
                if (_nm >= 2) {
                    _fallback_measure_ms = max(1,
                        real(variable_struct_get(_measure_starts[_nm - 1], "t"))
                        - real(variable_struct_get(_measure_starts[_nm - 2], "t")));
                }
                
                // Store structural measure starts globally so measure navigator uses correct numbering
                global.timeline_state.structural_measure_starts = _measure_starts;
            } else if (!_single_tune_loop_runtime) {
                // Keep pre-loop structural starts during loop runtime so score-image
                // lookup can reuse canonical measure->seq identity across repeats.
                global.timeline_state.structural_measure_starts = [];
            }

            // Single-tune alignment: score snippets define authoritative playback measure count.
            // Reconcile marker-derived starts to that count deterministically so image indexing
            // cannot drift at split-bar seams.
            if (!_single_tune_loop_runtime && _structural_duration_count <= 0 && _target_map_count > 0 && _nm > 0) {
                // Too many starts: prefer collapsing split-bar seams (consecutive starts with the
                // same musical measure number m), falling back to shortest-gap if none found.
                while (_nm > _target_map_count) {
                    var _drop_idx = -1;
                    // First pass: find a same-m pair (split-bar seam).
                    for (var _gi = 1; _gi < _nm; _gi++) {
                        var _m_prev = floor(real(variable_struct_get(_measure_starts[_gi - 1], "m")));
                        var _m_cur  = floor(real(variable_struct_get(_measure_starts[_gi],     "m")));
                        if (_m_cur == _m_prev) {
                            _drop_idx = _gi;
                            break;
                        }
                    }
                    // Fallback: shortest-gap if no same-m pair exists.
                    if (_drop_idx < 0) {
                    var _min_gap = 1000000000;
                    for (var _gi = 1; _gi < _nm; _gi++) {
                        var _gap = real(variable_struct_get(_measure_starts[_gi], "t"))
                            - real(variable_struct_get(_measure_starts[_gi - 1], "t"));
                        if (_gap < _min_gap) {
                            _min_gap = _gap;
                            _drop_idx = _gi;
                        }
                    }
                    }

                    if (_drop_idx < 0) break;

                    var _compact = [];
                    for (var _ki = 0; _ki < _nm; _ki++) {
                        if (_ki == _drop_idx) continue;
                        array_push(_compact, _measure_starts[_ki]);
                    }
                    _measure_starts = _compact;
                    _nm = array_length(_measure_starts);
                }

                // Too few starts: extend from the last known start using fallback measure duration.
                while (_nm < _target_map_count) {
                    var _last = _measure_starts[_nm - 1];
                    var _last_t = real(variable_struct_get(_last, "t"));
                    var _last_m = floor(real(variable_struct_get(_last, "m")));
                    array_push(_measure_starts, {
                        m: _last_m + 1,
                        p: floor(real(variable_struct_get(_last, "p"))),
                        b: 1,
                        t: _last_t + _fallback_measure_ms,
                        seq: _nm,
                        seg_idx: floor(real(variable_struct_get(_last, "seg_idx"))),
                        seg_title: string(variable_struct_get(_last, "seg_title")),
                        seg_start_ms: real(variable_struct_get(_last, "seg_start_ms")),
                        seg_end_ms: real(variable_struct_get(_last, "seg_end_ms"))
                    });
                    _nm = array_length(_measure_starts);
                }

                // Keep seq contiguous and authoritative for playback_to_image lookup.
                for (var _ri = 0; _ri < _nm; _ri++) {
                    variable_struct_set(_measure_starts[_ri], "seq", _ri);
                }
            }
            }

            if (!_score_layout_cache_hit && !_set_mode && !_single_tune_loop_runtime && _nm > 0) {
                global.timeline_state.score_lane_layout_cache_single = {
                    key: _score_layout_cache_key,
                    measure_starts: _measure_starts,
                    fallback_measure_ms: _fallback_measure_ms,
                    structural_measure_starts: variable_struct_exists(global.timeline_state, "structural_measure_starts")
                        ? global.timeline_state.structural_measure_starts
                        : []
                };
            }

            // Persist precomputed plan for subsequent frames.
            if (!_score_plan_cache_hit && _nm > 0) {
                global.timeline_state.score_render_plan = {
                    version: 1,
                    valid: true,
                    status: "ready",
                    reason: "draw_rebuild",
                    mode: _set_mode ? "set" : "tune",
                    built_for_loop: _single_tune_loop_runtime,
                    target_tune_channel: _score_target_tune_channel,
                    selected_channel_measure_count: (!_set_mode && !_single_tune_loop_runtime)
                        ? gv_count_selected_channel_score_measures(_events)
                        : -1,
                    source_event_count: is_array(_events) ? array_length(_events) : 0,
                    built_at_ms: timing_get_engine_now_ms(),
                    fallback_measure_ms: _fallback_measure_ms,
                    seg_raw_measure_counts: _seg_raw_measure_counts,
                    items: _measure_starts
                };
                global.timeline_state.score_render_plan_needs_rebuild = false;
                global.timeline_state.score_render_plan_pending_reason = "";
                _score_plan_stats.builds += 1;
                _score_plan_stats.last_reason = "draw_rebuild";
            }

            var _score_plan_debug_enabled = variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log")
                && global.timeline_cfg.score_render_plan_debug_log;
            static _score_draw_phase_last_log_ms = -1000000;
            var _canonical_seq_by_measure = is_struct(_plan_canonical_seq_by_measure)
                ? _plan_canonical_seq_by_measure
                : {};
            if (_single_tune_loop_runtime
                && !is_struct(_plan_canonical_seq_by_measure)
                && variable_struct_exists(global.timeline_state, "structural_measure_starts")
                && is_array(global.timeline_state.structural_measure_starts)) {
                var _canon_starts = global.timeline_state.structural_measure_starts;
                for (var _csi = 0; _csi < array_length(_canon_starts); _csi++) {
                    var _cs = _canon_starts[_csi];
                    if (!is_struct(_cs)) continue;
                    var _cm = floor(real(_cs[$ "m"] ?? -1));
                    var _cseq = floor(real(_cs[$ "seq"] ?? -1));
                    if (_cm < 0 || _cseq < 0) continue;
                    var _ck = string(_cm);
                    if (!variable_struct_exists(_canonical_seq_by_measure, _ck)) {
                        _canonical_seq_by_measure[$ _ck] = _cseq;
                    }
                }
            }
            if (_single_tune_loop_runtime
                && is_struct(_canonical_seq_by_measure)
                && variable_struct_exists(global.timeline_state, "score_render_plan")
                && is_struct(global.timeline_state.score_render_plan)) {
                var _plan_mut = global.timeline_state.score_render_plan;
                if (!variable_struct_exists(_plan_mut, "canonical_seq_by_measure")
                    || !is_struct(_plan_mut[$ "canonical_seq_by_measure"])) {
                    _plan_mut[$ "canonical_seq_by_measure"] = _canonical_seq_by_measure;
                }
            }

            var _score_phase_sample_this_frame = false;
            var _score_phase_interval_ms = variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log_interval_ms")
                ? max(250, real(global.timeline_cfg.score_render_plan_debug_log_interval_ms))
                : 2000;
            var _score_phase_now_ms = timing_get_engine_now_ms();
            if (_score_plan_debug_enabled && (_score_phase_now_ms - _score_draw_phase_last_log_ms) >= _score_phase_interval_ms) {
                _score_phase_sample_this_frame = true;
                _score_draw_phase_last_log_ms = _score_phase_now_ms;
            }
            var _score_phase_prep_us = 0;
            var _score_phase_loop_total_us = 0;
            var _score_phase_draw_us = 0;
            var _score_phase_views = 0;
            var _score_phase_prep_t0_us = 0;
            if (_score_plan_debug_enabled) {
                var _score_plan_debug_interval_ms = variable_struct_exists(global.timeline_cfg, "score_render_plan_debug_log_interval_ms")
                    ? max(250, real(global.timeline_cfg.score_render_plan_debug_log_interval_ms))
                    : 2000;
                var _score_plan_now_ms = timing_get_engine_now_ms();
                var _score_plan_last_log_ms = real(_score_plan_stats[$ "last_log_ms"] ?? 0);
                if ((_score_plan_now_ms - _score_plan_last_log_ms) >= _score_plan_debug_interval_ms) {
                    var _score_plan_log = "[SCORE_PLAN] hit=" + string(real(_score_plan_stats[$ "hits"] ?? 0));
                    _score_plan_log += " miss=" + string(real(_score_plan_stats[$ "misses"] ?? 0));
                    _score_plan_log += " build=" + string(real(_score_plan_stats[$ "builds"] ?? 0));
                    _score_plan_log += " inval=" + string(real(_score_plan_stats[$ "invalidations"] ?? 0));
                    _score_plan_log += " plan_hit=" + string(_score_plan_cache_hit);
                    _score_plan_log += " layout_hit=" + string(_score_layout_cache_hit);
                    _score_plan_log += " pending=" + string(bool(global.timeline_state[$ "score_render_plan_needs_rebuild"] ?? false));
                    _score_plan_log += " reason=" + string(global.timeline_state[$ "score_render_plan_pending_reason"] ?? _score_plan_stats[$ "last_reason"] ?? "");
                    _score_plan_log += " mode=" + (_set_mode ? "set" : "tune");
                    _score_plan_log += " loop=" + string(_single_tune_loop_runtime);
                    var _score_plan_mirror_output = variable_global_exists("PERF_DIAG_OUTPUT_WINDOW_ENABLED")
                        && bool(global.PERF_DIAG_OUTPUT_WINDOW_ENABLED);
                    diag_log_append_line(_score_plan_log, "perf_benchmark.log", _score_plan_mirror_output);
                    _score_plan_stats.last_log_ms = _score_plan_now_ms;
                }
            }

            if (_score_phase_sample_this_frame) {
                _score_phase_prep_t0_us = get_timer();
            }

            var _score_debug_enabled = variable_struct_exists(global.timeline_cfg, "score_lane_debug_log")
                && global.timeline_cfg.score_lane_debug_log;
            var _score_debug_boundary_window_ms = variable_struct_exists(global.timeline_cfg, "score_lane_debug_boundary_window_ms")
                ? max(0, real(global.timeline_cfg.score_lane_debug_boundary_window_ms))
                : 0;
            var _score_debug_focus_title = variable_struct_exists(global.timeline_cfg, "score_lane_debug_focus_title")
                ? string(global.timeline_cfg.score_lane_debug_focus_title)
                : "";
            var _score_debug_focus_ok = true;
            if (_score_debug_focus_title != "") {
                _score_debug_focus_ok = string_pos(string_lower(_score_debug_focus_title), string_lower(_seg_title)) > 0;
            }
            var _score_debug_near_boundary = true;
            if (_set_mode && _seg_start_ms >= 0 && _score_debug_boundary_window_ms > 0) {
                _score_debug_near_boundary = (abs(_playhead - _seg_start_ms) <= _score_debug_boundary_window_ms)
                    || (_seg_end_ms > _seg_start_ms && abs(_playhead - _seg_end_ms) <= _score_debug_boundary_window_ms);
            }
            _score_debug_enabled = _score_debug_enabled && _score_debug_focus_ok && _score_debug_near_boundary;
            var _score_debug_show_labels = _score_debug_enabled
                && (!variable_struct_exists(global.timeline_cfg, "score_lane_debug_show_labels")
                    || global.timeline_cfg.score_lane_debug_show_labels);
            var _score_debug_show_source = _score_debug_enabled
                && variable_struct_exists(global.timeline_cfg, "score_lane_debug_show_source")
                && global.timeline_cfg.score_lane_debug_show_source;
            var _score_debug_line = "";
            var _score_debug_views = 0;
            var _score_probe_has_now = false;
            var _score_probe_best_delta = 1000000000;
            var _score_probe_now_measure = -1;
            var _score_probe_now_part = -1;
            var _score_probe_now_img = -1;
            var _score_probe_now_k = 0;
            var _score_probe_now_start = 0;
            var _score_probe_now_end = 0;
            var _score_probe_warn_text = "";
            var _score_probe_boundary_margin_ms = variable_struct_exists(global.timeline_cfg, "score_lane_debug_warn_boundary_margin_ms")
                ? max(0, real(global.timeline_cfg.score_lane_debug_warn_boundary_margin_ms))
                : 32;
            var _visible_start_ms = _playhead - _ms_behind;
            var _visible_end_ms = _playhead + _ms_ahead;
            static _score_debug_last_line = "";
            static _score_debug_last_ms = -1000;
            static _score_debug_last_playhead = -1;
            static _score_debug_file_key = "";
            static _score_debug_file_ready = false;
            var _score_debug_collect = _score_debug_enabled && ((current_time - _score_debug_last_ms) >= 1000);
            var _score_debug_file_enabled = false;
            var _score_debug_file_path = "score_lane_debug.log";
            if (_score_debug_collect) {
                _score_debug_file_enabled = variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_log")
                    && global.timeline_cfg.score_lane_debug_file_log;
                _score_debug_file_path = variable_struct_exists(global.timeline_cfg, "score_lane_debug_file_path")
                    ? string(global.timeline_cfg.score_lane_debug_file_path)
                    : "score_lane_debug.log";
                if (_score_debug_file_path == "") {
                    _score_debug_file_path = "score_lane_debug.log";
                }
                var _score_debug_events_count = is_array(_events) ? array_length(_events) : 0;
                var _score_debug_run_end_ms = floor(gv_get_planned_end_ms());
                var _score_debug_file_run_key = string(_set_mode)
                    + "|" + string(_score_debug_events_count)
                    + "|" + string(_score_debug_run_end_ms);
                var _score_debug_playhead_reset = (_score_debug_last_playhead >= 0)
                    && ((_playhead + 250) < _score_debug_last_playhead);
                if (_score_debug_file_key != _score_debug_file_run_key || _score_debug_playhead_reset) {
                    _score_debug_file_key = _score_debug_file_run_key;
                    _score_debug_file_ready = false;
                }
                _score_debug_last_playhead = _playhead;
            }
            if (_score_phase_sample_this_frame) {
                _score_phase_prep_us = get_timer() - _score_phase_prep_t0_us;
            }
            var _score_phase_loop_t0_us = _score_phase_sample_this_frame ? get_timer() : 0;

            // Draw each measure whose time range overlaps the visible window
            for (var _mi = 0; _mi < _nm; _mi++) {
                var _ms = _measure_starts[_mi];
                var _t_start = _ms.t;
                var _t_end   = (_mi + 1 < _nm) ? _measure_starts[_mi + 1].t : (_t_start + _fallback_measure_ms);
                var _ms_seg_end = real(_ms[$ "seg_end_ms"] ?? -1);
                var _ms_seg_start = real(_ms[$ "seg_start_ms"] ?? -1);
                var _ms_seg_content_end = real(_ms[$ "seg_content_end_ms"] ?? _ms_seg_end);
                if (_set_mode && _ms_seg_end > _ms_seg_start) {
                    // Cap to content_end_ms (not end_ms) so images don't stretch into the hold window
                    _t_end = min(_t_end, _ms_seg_content_end);
                }
                var _spr_idx = _ms.seq;
                var _spr = undefined;
                var _meta = undefined;
                var _effective_spr_count = 0;
                var _override_bundle = undefined;
                var _override_local_seq = -1;

                var _base_sprites = global.score_lane_sprites;
                var _base_pbmap = global.score_playback_map;
                var _base_meta = variable_global_exists("score_lane_meta") ? global.score_lane_meta : [];
                if (_set_mode) {
                    var _ms_seg_idx = floor(real(_ms[$ "seg_idx"] ?? -1));
                    var _seg_cache = variable_global_exists("score_segments_sprites") ? global.score_segments_sprites : [];
                    if (is_array(_seg_cache) && _ms_seg_idx >= 0 && _ms_seg_idx < array_length(_seg_cache)) {
                        var _cache_entry = _seg_cache[_ms_seg_idx];
                        if (is_struct(_cache_entry)) {
                            _base_sprites = _cache_entry[$ "sprites"] ?? [];
                            _base_pbmap = _cache_entry[$ "pbmap"] ?? [];
                            _base_meta = _cache_entry[$ "meta"] ?? [];
                        }
                    }
                }
                _effective_spr_count = is_array(_base_sprites) ? array_length(_base_sprites) : 0;

                if (_set_mode
                    && floor(real(_ms[$ "seg_idx"] ?? -1)) == _seg_idx
                    && variable_global_exists("score_override_groups")
                    && is_struct(global.score_override_groups)) {
                    var _seg_count_for_override = _nm;
                    var _seg_idx_for_override = floor(real(_ms[$ "seg_idx"] ?? -1));
                    // Use the raw (pre-trim) count so the tail override anchor targets the
                    // original last measure slot (e.g. slot 32 of a 32-measure tune), not
                    // the trimmed last slot (slot 31 after a 1-measure tail cut).
                    if (is_array(_seg_raw_measure_counts)
                        && _seg_idx_for_override >= 0
                        && _seg_idx_for_override < array_length(_seg_raw_measure_counts)) {
                        _seg_count_for_override = max(0, floor(real(_seg_raw_measure_counts[_seg_idx_for_override] ?? _nm)));
                    }

                    var _head_bundle = variable_struct_exists(global.score_override_groups, "head") ? global.score_override_groups[$ "head"] : undefined;
                    var _tail_bundle = variable_struct_exists(global.score_override_groups, "tail") ? global.score_override_groups[$ "tail"] : undefined;
                    var _head_count = is_struct(_head_bundle) ? max(0, floor(real(_head_bundle[$ "count_measures"] ?? 0))) : 0;
                    var _tail_count = is_struct(_tail_bundle) ? max(0, floor(real(_tail_bundle[$ "count_measures"] ?? 0))) : 0;

                    if (_head_count > 0 && _ms.seq >= 0 && _ms.seq < _head_count) {
                        _override_bundle = _head_bundle;
                        _override_local_seq = _ms.seq;
                    } else if (_tail_count > 0) {
                        var _tail_start_seq = max(0, _seg_count_for_override - _tail_count);
                        if (_ms.seq >= _tail_start_seq) {
                            _override_bundle = _tail_bundle;
                            _override_local_seq = _ms.seq - _tail_start_seq;
                        }
                    }
                }

                if (is_struct(_override_bundle)) {
                    var _score_sprite_source = "override";
                    var _override_sprites = _override_bundle[$ "sprites"] ?? [];
                    var _override_meta = _override_bundle[$ "meta"] ?? [];
                    var _override_pbmap = _override_bundle[$ "playback_map"] ?? [];
                    _effective_spr_count = array_length(_override_sprites);
                    _spr_idx = _override_local_seq;
                    var _override_pbmap_len = array_length(_override_pbmap);
                    if (_override_pbmap_len > 0) {
                        _spr_idx = (_override_local_seq >= 0 && _override_local_seq < _override_pbmap_len)
                            ? _override_pbmap[_override_local_seq] : _override_local_seq;
                    }
                    if (_spr_idx < 0 || _spr_idx >= _effective_spr_count) continue;
                    _spr = _override_sprites[_spr_idx];
                    _meta = (_spr_idx < array_length(_override_meta)) ? _override_meta[_spr_idx] : undefined;
                } else {
                    var _score_sprite_source = "raw";
                    // Priority 1: explicit playback_to_image mapping (new pipeline).
                    // In loop runtime, key by canonical measure identity first so repeated
                    // passes reuse the same score image index as non-loop playback.
                    var _pbmap_len = is_array(_base_pbmap) ? array_length(_base_pbmap) : 0;
                    var _has_pickup_for_lookup = variable_global_exists("score_has_pickup")
                        && bool(global.score_has_pickup);
                    var _measure_for_lookup = floor(real(_ms[$ "m"] ?? -1));
                    if (_single_tune_loop_runtime) {
                        if (variable_struct_exists(_ms, "musical_measure_for_lookup")) {
                            _measure_for_lookup = floor(real(_ms[$ "musical_measure_for_lookup"] ?? _measure_for_lookup));
                        } else {
                            _measure_for_lookup = gv_tune_structure_model_resolve_musical_measure_at_time(_t_start, _measure_for_lookup);
                            variable_struct_set(_ms, "musical_measure_for_lookup", _measure_for_lookup);
                        }
                        // In loop mode, pickup rows are render-only metadata and should not
                        // consume a score image slot.
                        if (_measure_for_lookup <= 0) continue;
                    }
                    var _canonical_seq_from_measure = -1;
                    if (_single_tune_loop_runtime) {
                        if (variable_struct_exists(_ms, "canonical_seq_for_lookup")) {
                            _canonical_seq_from_measure = floor(real(_ms[$ "canonical_seq_for_lookup"] ?? -1));
                        } else {
                            var _canon_key = string(_measure_for_lookup);
                            if (variable_struct_exists(_canonical_seq_by_measure, _canon_key)) {
                                _canonical_seq_from_measure = floor(real(_canonical_seq_by_measure[$ _canon_key]));
                            }
                            variable_struct_set(_ms, "canonical_seq_for_lookup", _canonical_seq_from_measure);
                        }
                    }
                    if (_measure_for_lookup == 0) {
                        _canonical_seq_from_measure = 0;
                    } else if (_canonical_seq_from_measure < 0 && _measure_for_lookup > 0) {
                        _canonical_seq_from_measure = _measure_for_lookup - (_has_pickup_for_lookup ? 0 : 1);
                    }
                    var _primary_lookup_seq = _single_tune_loop_runtime
                        ? _canonical_seq_from_measure
                        : floor(real(_ms[$ "seq"] ?? -1));
                    if (_pbmap_len > 0) {
                        var _pb_lookup_seq = -1;
                        var _pb_candidate0 = floor(real(_primary_lookup_seq));
                        var _pb_candidate1 = floor(real(_canonical_seq_from_measure));
                        var _pb_candidate2 = floor(real(_ms[$ "seq"] ?? -1));
                        var _pb_candidate3 = _measure_for_lookup - 1;
                        if (_pb_candidate0 >= 0 && _pb_candidate0 < _pbmap_len) {
                            _pb_lookup_seq = _pb_candidate0;
                            _score_sprite_source = "pbmap_primary";
                        } else if (_pb_candidate1 >= 0 && _pb_candidate1 < _pbmap_len) {
                            _pb_lookup_seq = _pb_candidate1;
                            _score_sprite_source = "pbmap_measure_primary";
                        } else if (_pb_candidate2 >= 0 && _pb_candidate2 < _pbmap_len) {
                            _pb_lookup_seq = _pb_candidate2;
                            _score_sprite_source = "pbmap_seq";
                        } else if (_pb_candidate3 >= 0 && _pb_candidate3 < _pbmap_len) {
                            _pb_lookup_seq = _pb_candidate3;
                            _score_sprite_source = "pbmap_measure";
                        }
                        _spr_idx = (_pb_lookup_seq >= 0 && _pb_lookup_seq < _pbmap_len)
                            ? _base_pbmap[_pb_lookup_seq]
                            : _primary_lookup_seq;
                        if (_pb_lookup_seq < 0 || _pb_lookup_seq >= _pbmap_len) _score_sprite_source = "pbmap_raw";
                    } else {
                        // Priority 2: legacy measure_map (maps expanded full-measure seq to physical image index).
                        var _map_len = (variable_global_exists("score_measure_map")) ? array_length(global.score_measure_map) : 0;
                        if (_map_len > 0) {
                            var _has_pickup_start = _single_tune_loop_runtime
                                ? _has_pickup_for_lookup
                                : ((_nm > 0) && (_measure_starts[0].m == 0));
                            if (_measure_for_lookup == 0) {
                                // If map length == sprite count, image 0 already serves measure 1 (with pickup included).
                                // In that case, skip drawing synthetic measure 0 to avoid drawing the same image twice.
                                if (_effective_spr_count > _map_len) {
                                    _spr_idx = 0;
                                    _score_sprite_source = "map_pickup";
                                } else {
                                    continue;
                                }
                            } else {
                                var _map_candidate0 = floor(real(_primary_lookup_seq));
                                var _map_candidate1 = floor(real(_canonical_seq_from_measure));
                                var _map_candidate2 = floor(real(_ms[$ "seq"] ?? -1)) - (_has_pickup_start ? 1 : 0);
                                var _map_candidate3 = _measure_for_lookup - 1;
                                var _map_key = -1;
                                if (_map_candidate0 >= 0 && _map_candidate0 < _map_len) {
                                    _map_key = _map_candidate0;
                                    _score_sprite_source = "map_primary";
                                } else if (_map_candidate1 >= 0 && _map_candidate1 < _map_len) {
                                    _map_key = _map_candidate1;
                                    _score_sprite_source = "map_measure_primary";
                                } else if (_map_candidate2 >= 0 && _map_candidate2 < _map_len) {
                                    _map_key = _map_candidate2;
                                    _score_sprite_source = "map_seq";
                                } else if (_map_candidate3 >= 0 && _map_candidate3 < _map_len) {
                                    _map_key = _map_candidate3;
                                    _score_sprite_source = "map_measure";
                                }
                                _spr_idx = (_map_key >= 0 && _map_key < _map_len) ? global.score_measure_map[_map_key] : (_spr_idx);
                                if (_map_key < 0 || _map_key >= _map_len) _score_sprite_source = "raw";
                            }
                        }
                        // Priority 3 (fallback): raw seq — works for tunes with no repeats
                        // where playback order matches physical image order.
                    }
                    if (_spr_idx < 0 || _spr_idx >= _effective_spr_count) continue;
                    _meta = (is_array(_base_meta) && _spr_idx < array_length(_base_meta)) ? _base_meta[_spr_idx] : undefined;
                    _spr = _base_sprites[_spr_idx];
                }

                var _row_repeatable = !variable_struct_exists(_ms, "loop_repeatable") || bool(_ms[$ "loop_repeatable"]);
                var _k_start = (_use_loop_projection && _row_repeatable) ? _proj_min_k : 0;
                var _k_end = (_use_loop_projection && _row_repeatable) ? _proj_max_k : 0;

                if (!_use_loop_projection) {
                    if (_t_end < _visible_start_ms) continue;
                    if (_t_start > _visible_end_ms) break;
                }

                for (var _k = _k_start; _k <= _k_end; _k++) {
                    var _draw_t_start = _t_start + (_k * _loop_cycle_cached);
                    var _draw_t_end = _t_end + (_k * _loop_cycle_cached);

                    if (_draw_t_end < _visible_start_ms) continue;
                    if (_draw_t_start > _visible_end_ms) continue;

                    if (_score_debug_collect) {
                        if (_score_debug_views > 0) _score_debug_line += " | ";
                        var _dbg_seg_title = string(_ms[$ "seg_title"] ?? "");
                        if (_dbg_seg_title == "") _dbg_seg_title = _seg_title;
                        _score_debug_line += (_dbg_seg_title != "" ? _dbg_seg_title : "<no-seg>");
                        _score_debug_line += " seg=" + string(floor(real(_ms[$ "seg_idx"] ?? _seg_idx)));
                        _score_debug_line += " m=" + string(_ms.m);
                        _score_debug_line += " b=" + string(_ms.b);
                        _score_debug_line += " seq=" + string(_ms.seq);
                        _score_debug_line += " img=" + string(_spr_idx);
                        if (_score_debug_show_source) {
                            _score_debug_line += " src=" + _score_sprite_source;
                        }
                        _score_debug_line += " k=" + string(_k);
                        _score_debug_line += " t=" + string(floor(_draw_t_start)) + "-" + string(floor(_draw_t_end));
                        _score_debug_views++;
                    }

                    if (_score_debug_show_labels && _single_tune_loop_runtime && (_playhead >= _draw_t_start) && (_playhead < _draw_t_end)) {
                        var _probe_mid = (_draw_t_start + _draw_t_end) * 0.5;
                        var _probe_delta = abs(_playhead - _probe_mid);
                        if (!_score_probe_has_now || _probe_delta < _score_probe_best_delta) {
                            _score_probe_has_now = true;
                            _score_probe_best_delta = _probe_delta;
                            _score_probe_now_measure = floor(real(_ms[$ "m"] ?? -1));
                            _score_probe_now_part = floor(real(_ms[$ "p"] ?? 1));
                            _score_probe_now_img = _spr_idx;
                            _score_probe_now_k = _k;
                            _score_probe_now_start = _draw_t_start;
                            _score_probe_now_end = _draw_t_end;
                        }
                    }
                    var _score_phase_draw_t0_us = _score_phase_sample_this_frame ? get_timer() : 0;

                    var _px1 = gv_time_to_x(_draw_t_start, _playhead, x1, x2, now_ratio, _ms_behind, _ms_ahead);
                    var _px2 = gv_time_to_x(_draw_t_end,   _playhead, x1, x2, now_ratio, _ms_behind, _ms_ahead);
                    var _img_w = max(1, _px2 - _px1);
                    var _snap_score_pixels = variable_struct_exists(cfg, "score_lane_snap_pixels")
                        ? bool(variable_struct_get(cfg, "score_lane_snap_pixels"))
                        : false;

                    if (!sprite_exists(_spr)) continue;

                    var _spr_w  = sprite_get_width(_spr);
                    var _spr_h  = sprite_get_height(_spr);
                    var _content_left = 0;
                    var _content_right = _spr_w;
                    if (is_struct(_meta)) {
                        if (variable_struct_exists(_meta, "content_left_px")) {
                            var _meta_content_left = variable_struct_get(_meta, "content_left_px");
                            if (is_real(_meta_content_left)) {
                                _content_left = clamp(real(_meta_content_left), 0, _spr_w - 1);
                            }
                        }
                        if (variable_struct_exists(_meta, "content_right_px")) {
                            var _meta_content_right = variable_struct_get(_meta, "content_right_px");
                            if (is_real(_meta_content_right)) {
                                _content_right = clamp(real(_meta_content_right), _content_left + 1, _spr_w);
                            }
                        }
                    }
                    var _content_w = max(1, _content_right - _content_left);
                    var _scale_x = _img_w / _content_w;

                    var _draw_x1 = _px1;

                    // Clip to lane bounds
                    var _cx1 = max(_draw_x1, x1);
                    var _cx2 = min(_px2, x2);
                    if (_snap_score_pixels) {
                        _cx1 = round(_cx1);
                        _cx2 = round(_cx2);
                    }
                    if (_cx2 <= _cx1) continue;

                    // Scale to the full score-lane drawable height. Using staff-only anchors
                    // stretches symbols vertically when the lane is taller than the 5-line staff.
                    var _scale_y    = staff_h / _spr_h;
                    var _y_offset   = staff_y1;
                    var _part_x  = _content_left + ((_cx1 - _draw_x1) / _scale_x);
                    var _part_w  = (_cx2 - _cx1) / _scale_x;
                    if (abs(_part_x - _content_left) <= 0.001) _part_x = _content_left;
                    var _part_right = _part_x + _part_w;
                    if (abs(_part_right - _content_right) <= 0.001) {
                        _part_w = max(0, _content_right - _part_x);
                    }

                    draw_set_alpha(1);
                    draw_sprite_part_ext(_spr, 0, _part_x, 0, _part_w, _spr_h, _cx1, _y_offset, _scale_x, _scale_y, c_white, 1);

                    if (_score_debug_show_labels) {
                        var _label_m = floor(real(_ms[$ "m"] ?? -1));
                        var _label_p = floor(real(_ms[$ "p"] ?? 1));
                        var _label_txt = "P" + string(_label_p) + " M" + string(_label_m) + " I" + string(_spr_idx);
                        if (_use_loop_projection) {
                            _label_txt += " K" + string(_k);
                        }
                        // Keep labels readable: only annotate the image under the now-line.
                        if (now_x >= _cx1 && now_x <= _cx2) {
                            var _label_x = _cx1 + 2;
                            var _label_y = staff_y1 + 2;
                            var _label_w = string_width(_label_txt) + 4;
                            var _label_h = string_height(_label_txt) + 2;
                            draw_set_alpha(0.72);
                            draw_set_color(c_black);
                            draw_rectangle(_label_x - 1, _label_y - 1, _label_x + _label_w, _label_y + _label_h, false);
                            draw_set_alpha(1);
                            draw_set_color(make_color_rgb(246, 232, 164));
                            draw_text(_label_x, _label_y, _label_txt);
                        }
                    }

                    // Optional beat-anchor guides from score metadata.
                    // Anchors are emitted in image-space X coordinates and scale with the sprite.
                    var _anchors_enabled = !variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guides_enabled")
                        || global.timeline_cfg.score_lane_anchor_guides_enabled;
                    if (_anchors_enabled && is_struct(_meta)
                        && variable_struct_exists(_meta, "beat_anchors")
                        && is_array(_meta.beat_anchors)) {
                        var _anchors = _meta.beat_anchors;
                        var _guide_color = variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_color")
                            ? global.timeline_cfg.score_lane_anchor_guide_color
                            : make_color_rgb(246, 210, 94);
                        var _guide_alpha = variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_alpha")
                            ? clamp(real(global.timeline_cfg.score_lane_anchor_guide_alpha), 0, 1)
                            : 0.28;
                        var _guide_width = variable_struct_exists(global.timeline_cfg, "score_lane_anchor_guide_width")
                            ? max(1, real(global.timeline_cfg.score_lane_anchor_guide_width))
                            : 1;

                        draw_set_color(_guide_color);
                        draw_set_alpha(_guide_alpha);
                        for (var _ai = 0; _ai < array_length(_anchors); _ai++) {
                            var _anchor_x = _anchors[_ai];
                            if (is_undefined(_anchor_x)) continue;
                            if (is_string(_anchor_x) && string_lower(string(_anchor_x)) == "null") continue;
                            if (!is_real(_anchor_x)) continue;

                            var _anchor_screen_x = _draw_x1 + ((real(_anchor_x) - _content_left) * _scale_x);
                            if (_anchor_screen_x < _cx1 || _anchor_screen_x > _cx2) continue;

                            draw_line_width(_anchor_screen_x, staff_y1, _anchor_screen_x, staff_y2, _guide_width);
                        }
                        draw_set_alpha(1);
                    }
                    if (_score_phase_sample_this_frame) {
                        _score_phase_draw_us += (get_timer() - _score_phase_draw_t0_us);
                        _score_phase_views += 1;
                    }
                }
            }
            if (_score_phase_sample_this_frame) {
                _score_phase_loop_total_us = get_timer() - _score_phase_loop_t0_us;
            }

            if (_score_debug_show_labels && _single_tune_loop_runtime && _score_probe_has_now) {
                // Compare against the same loop-normalized playhead used for score-lane render.
                var _probe_resolved = gv_resolve_measure_context(_playhead);
                var _probe_expected_measure = floor(real(_probe_resolved.measure ?? -1));
                var _probe_boundary_dist = min(abs(_playhead - _score_probe_now_start), abs(_score_probe_now_end - _playhead));
                var _probe_near_boundary = (_probe_boundary_dist <= _score_probe_boundary_margin_ms);
                if (_probe_expected_measure >= 1
                    && _score_probe_now_measure >= 1
                    && _probe_expected_measure != _score_probe_now_measure
                    && !_probe_near_boundary) {
                    _score_probe_warn_text = "LOOP MAP WARN exp M" + string(_probe_expected_measure)
                        + " got P" + string(_score_probe_now_part) + " M" + string(_score_probe_now_measure)
                        + " I" + string(_score_probe_now_img)
                        + " K" + string(_score_probe_now_k);

                    var _warn_w = string_width(_score_probe_warn_text) + 8;
                    var _warn_h = string_height(_score_probe_warn_text) + 6;
                    var _warn_x2 = x2 - 4;
                    var _warn_x1 = max(x1 + 4, _warn_x2 - _warn_w);
                    var _warn_y1 = staff_y1 + 4;
                    var _warn_y2 = _warn_y1 + _warn_h;
                    draw_set_alpha(0.82);
                    draw_set_color(make_color_rgb(120, 24, 24));
                    draw_rectangle(_warn_x1, _warn_y1, _warn_x2, _warn_y2, false);
                    draw_set_alpha(1);
                    draw_set_color(make_color_rgb(255, 224, 144));
                    draw_text(_warn_x1 + 4, _warn_y1 + 2, _score_probe_warn_text);
                }
            }

            if (_score_debug_enabled) {
                var _score_log = "[SCORE_LANE] ph=" + string(floor(_playhead));
                _score_log += " raw=" + string(floor(_playhead_raw));
                _score_log += " vis=" + string(_score_debug_views);
                _score_log += " seg=" + string(_seg_idx);
                if (_seg_title != "") _score_log += " title=" + _seg_title;
                _score_log += " dbg_win=" + string(floor(_score_debug_boundary_window_ms));
                if (_score_debug_focus_title != "") _score_log += " focus=" + _score_debug_focus_title;
                if (_single_tune_loop_runtime) {
                    _score_log += " loop_anchor=" + string(floor(_iter1_start_cached));
                    _score_log += " loop_cycle=" + string(floor(_loop_cycle_cached));
                }
                _score_log += " sprites=" + string(_spr_count);
                _score_log += " map=" + string((variable_global_exists("score_measure_map")) ? array_length(global.score_measure_map) : 0);
                _score_log += " pbmap=" + string((variable_global_exists("score_playback_map")) ? array_length(global.score_playback_map) : 0);
                if (_seg_start_ms >= 0) _score_log += " seg_ms=" + string(floor(_seg_start_ms)) + "-" + string(floor(_seg_end_ms));
                if (_score_probe_warn_text != "") {
                    _score_log += " WARN=" + _score_probe_warn_text;
                }
                if (_score_debug_views > 0) {
                    _score_log += " :: " + _score_debug_line;
                }
                if (_score_log != _score_debug_last_line || (current_time - _score_debug_last_ms) >= 1000) {
                    show_debug_message(_score_log);

                    if (_score_debug_file_enabled) {
                        if (!_score_debug_file_ready) {
                            var _score_debug_reset_file = file_text_open_write(_score_debug_file_path);
                            file_text_write_string(_score_debug_reset_file, "[SCORE_LANE] file_log_start path=" + _score_debug_file_path + " key=" + _score_debug_file_key);
                            file_text_writeln(_score_debug_reset_file);
                            file_text_close(_score_debug_reset_file);
                            _score_debug_file_ready = true;
                        }

                        var _score_debug_append_file = file_text_open_append(_score_debug_file_path);
                        file_text_write_string(_score_debug_append_file, _score_log);
                        file_text_writeln(_score_debug_append_file);
                        file_text_close(_score_debug_append_file);
                    }

                    _score_debug_last_line = _score_log;
                    _score_debug_last_ms = current_time;
                }
            }

            if (_score_phase_sample_this_frame) {
                var _score_phase_filter_us = max(0, _score_phase_loop_total_us - _score_phase_draw_us);
                var _score_phase_log = "[SCORE_DRAW_PHASE] prep_ms=" + string_format(_score_phase_prep_us / 1000.0, 0, 3);
                _score_phase_log += " filter_ms=" + string_format(_score_phase_filter_us / 1000.0, 0, 3);
                _score_phase_log += " draw_ms=" + string_format(_score_phase_draw_us / 1000.0, 0, 3);
                _score_phase_log += " loop_ms=" + string_format(_score_phase_loop_total_us / 1000.0, 0, 3);
                _score_phase_log += " views=" + string(_score_phase_views);
                _score_phase_log += " nm=" + string(_nm);
                _score_phase_log += " mode=" + (_set_mode ? "set" : "tune");
                _score_phase_log += " loop=" + string(_single_tune_loop_runtime);
                perf_diag_emit(_score_phase_log);
            }
        }
    }

    // Scrolling beat ticks
    var _overlay_playhead_ms = variable_struct_exists(global.timeline_state, "playhead_ms")
        ? max(0, real(global.timeline_state.playhead_ms) + visual_cal_ms)
        : 0;
    gv_draw_beat_lane(x1, beat_y1, x2, beat_y2, _overlay_playhead_ms);

    // Keep the now-line on the beat lane only.
    // Do not draw it across the score lane because score images are not sample-accurate to timeline time.
    if (is_active) {
        draw_set_alpha(1);
        draw_set_color(c_yellow);
        draw_line_width(now_x, beat_y1, now_x, beat_y2, 2);
    }
}

/// @function gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2)
/// @description Draw the notebeam canvas with optional visual throttling (skips renders to hit target Hz). Delegates to gv_draw_notebeam_canvas_core.
/// @param {real} _x1/_y1/_x2/_y2  Canvas bounds.
/// @reads  global.timeline_cfg.notebeam_enabled/visual_throttle_enabled/visual_target_hz, global.NOTEBEAM_THROTTLE_LAST_MS
/// @writes global.NOTEBEAM_THROTTLE_LAST_MS
function gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    gv_ensure_timeline_cfg_defaults();

    var enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_enabled") || global.timeline_cfg.notebeam_enabled;
    if (!enabled) return;

    var throttle_enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_visual_throttle_enabled")
        || global.timeline_cfg.notebeam_visual_throttle_enabled;
    if (throttle_enabled) {
        var target_hz = variable_struct_exists(global.timeline_cfg, "notebeam_visual_target_hz")
            ? max(1, real(global.timeline_cfg.notebeam_visual_target_hz))
            : 60;
        var min_dt_ms = 1000.0 / target_hz;
        if (!variable_global_exists("NOTEBEAM_THROTTLE_LAST_MS")) {
            global.NOTEBEAM_THROTTLE_LAST_MS = -1;
        }
        var dt = current_time - real(global.NOTEBEAM_THROTTLE_LAST_MS);
        if (global.NOTEBEAM_THROTTLE_LAST_MS >= 0 && dt < min_dt_ms) {
            return;
        }
        global.NOTEBEAM_THROTTLE_LAST_MS = current_time;
    }

    gv_draw_notebeam_canvas_core(_x1, _y1, _x2, _y2);
}

/// @function gv_draw_notebeam_canvas_core(_x1, _y1, _x2, _y2)
/// @description Full notebeam canvas render: builds lane geometry, draws underlay surface (planned beams + emb boxes), renders live player layer, adds scoring panel and note popup overlays.
/// @param {real} _x1/_y1/_x2/_y2  Canvas bounds.
/// @reads  global.timeline_cfg.*, global.timeline_state.*, global.GV_ANCHOR_RECT_X_OFFSET/Y_OFFSET
/// @writes global.timeline_state.notebeam_player_hitboxes, global.notebeam_underlay_surface/signature/valid, global.notebeam_live_player_surface/valid
function gv_draw_notebeam_canvas_core(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;

    gv_ensure_timeline_cfg_defaults();

    var enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_enabled") || global.timeline_cfg.notebeam_enabled;
    if (!enabled) return;

    var x1 = _x1;
    var y1 = _y1;
    var x2 = _x2;
    var y2 = _y2;
    if (x2 <= x1 || y2 <= y1) return;

    // When rendering into a cached anchor surface, convert hitboxes back to
    // global screen space so click tests remain aligned.
    var hitbox_x_bias = variable_global_exists("GV_ANCHOR_RECT_X_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_X_OFFSET)
        : 0;
    var hitbox_y_bias = variable_global_exists("GV_ANCHOR_RECT_Y_OFFSET")
        ? -real(global.GV_ANCHOR_RECT_Y_OFFSET)
        : 0;

    var is_active = variable_global_exists("timeline_state") && is_struct(global.timeline_state) && global.timeline_state.active;

    var popup_clicks_enabled = variable_global_exists("timeline_state") && is_struct(global.timeline_state)
        && variable_struct_exists(global.timeline_state, "playback_complete")
        && global.timeline_state.playback_complete;

    var diag_enabled = variable_struct_exists(global.timeline_cfg, "notebeam_diag_enabled")
        && global.timeline_cfg.notebeam_diag_enabled;
    var diag_log_every = variable_struct_exists(global.timeline_cfg, "notebeam_diag_log_interval_frames")
        ? max(1, floor(real(global.timeline_cfg.notebeam_diag_log_interval_frames)))
        : 45;
    var diag_disable_planned = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_planned")
        && global.timeline_cfg.notebeam_diag_disable_planned;
    var diag_disable_player = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_player")
        && global.timeline_cfg.notebeam_diag_disable_player;
    var diag_disable_pending = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_pending")
        && global.timeline_cfg.notebeam_diag_disable_pending;
    var diag_disable_history = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_history")
        && global.timeline_cfg.notebeam_diag_disable_history;
    var diag_disable_beat_boxes = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_beat_boxes")
        && global.timeline_cfg.notebeam_diag_disable_beat_boxes;
    var diag_disable_emb_boxes = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_emb_boxes")
        && global.timeline_cfg.notebeam_diag_disable_emb_boxes;
    var diag_disable_popup_hitboxes = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_popup_hitboxes")
        && global.timeline_cfg.notebeam_diag_disable_popup_hitboxes;
    var diag_disable_popup_draw = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_popup_draw")
        && global.timeline_cfg.notebeam_diag_disable_popup_draw;
    var diag_disable_overlap_compare = diag_enabled
        && variable_struct_exists(global.timeline_cfg, "notebeam_diag_disable_overlap_compare")
        && global.timeline_cfg.notebeam_diag_disable_overlap_compare;

    if (diag_disable_popup_hitboxes) {
        popup_clicks_enabled = false;
    }

    var diag_frame_start_us = diag_enabled ? get_timer() : 0;
    var diag_ms_anchor_lookup = 0;
    var diag_ms_overlap = 0;
    var diag_ms_beat_boxes = 0;
    var diag_ms_emb_boxes = 0;
    var diag_ms_planned = 0;
    var diag_ms_player = 0;
    var diag_ms_pending = 0;
    var diag_ms_history = 0;
    var diag_ms_popup = 0;

    if (variable_global_exists("timeline_state") && is_struct(global.timeline_state)) {
        global.timeline_state.notebeam_player_hitboxes = [];
        if (!popup_clicks_enabled) {
            global.timeline_state.notebeam_note_popup = { visible: false };
        }
    }

    var base_now_ratio = variable_struct_exists(global.timeline_cfg, "now_ratio")
        ? real(global.timeline_cfg.now_ratio)
        : 0.33;
    var beam_now_ratio = variable_struct_exists(global.timeline_cfg, "notebeam_now_ratio")
        ? real(global.timeline_cfg.notebeam_now_ratio)
        : -1;
    var now_ratio = (beam_now_ratio >= 0) ? beam_now_ratio : base_now_ratio;
    now_ratio = clamp(now_ratio, 0.0, 1.0);

    var now_offset_px = variable_struct_exists(global.timeline_cfg, "notebeam_now_x_offset_px")
        ? real(global.timeline_cfg.notebeam_now_x_offset_px)
        : 0;

    var now_x = x1 + ((x2 - x1) * now_ratio) + now_offset_px;
    now_x = clamp(now_x, x1, x2);

    var lane_count = 9;
    var lane_h = (y2 - y1) / lane_count;
    var use_label_lane_layout = !variable_struct_exists(global.timeline_cfg, "notebeam_use_label_layout")
        || global.timeline_cfg.notebeam_use_label_layout;
    var use_lane_anchors = !variable_struct_exists(global.timeline_cfg, "notebeam_use_lane_anchors")
        || global.timeline_cfg.notebeam_use_lane_anchors;
    var lane_flip = variable_struct_exists(global.timeline_cfg, "notebeam_lane_flip")
        && global.timeline_cfg.notebeam_lane_flip;
    var lane_top_spacer_ratio = variable_struct_exists(global.timeline_cfg, "notebeam_lane_top_spacer_ratio")
        ? clamp(real(global.timeline_cfg.notebeam_lane_top_spacer_ratio), 0, 1)
        : 0;
    var lane_top_spacer_px = variable_struct_exists(global.timeline_cfg, "notebeam_lane_top_spacer_px")
        ? real(global.timeline_cfg.notebeam_lane_top_spacer_px)
        : 0;
    var lane_row_height_px = variable_struct_exists(global.timeline_cfg, "notebeam_lane_row_height_px")
        ? max(1, real(global.timeline_cfg.notebeam_lane_row_height_px))
        : 42;
    var lane_row_gap_px = variable_struct_exists(global.timeline_cfg, "notebeam_lane_row_gap_px")
        ? max(0, real(global.timeline_cfg.notebeam_lane_row_gap_px))
        : 20;
    var match_label_width = !variable_struct_exists(global.timeline_cfg, "notebeam_match_label_width")
        || global.timeline_cfg.notebeam_match_label_width;
    var match_label_width_scale = variable_struct_exists(global.timeline_cfg, "notebeam_match_label_width_scale")
        ? clamp(real(global.timeline_cfg.notebeam_match_label_width_scale), 0.1, 2.0)
        : 1.0;
    var lane_y_offset_px = variable_struct_exists(global.timeline_cfg, "notebeam_lane_y_offset_px")
        ? real(global.timeline_cfg.notebeam_lane_y_offset_px)
        : 0;

    var lane_anchor_y = array_create(lane_count, -1);
    var lane_anchor_h = array_create(lane_count, -1);
    var lane_anchor_found = 0;
    var diag_anchor_start_us = diag_enabled ? get_timer() : 0;
    if (use_lane_anchors) {
        for (var lane_scan_idx = 0; lane_scan_idx < lane_count; lane_scan_idx++) {
            var anchor_name = gv_get_notebeam_anchor_name_for_lane(lane_scan_idx, lane_flip);
            if (string_length(anchor_name) <= 0) continue;

            var anchor_rect = gv_get_anchor_rect_by_name(anchor_name);
            if (!is_struct(anchor_rect)) continue;

            lane_anchor_y[lane_scan_idx] = real(anchor_rect.y1 + (anchor_rect.h * 0.5));
            lane_anchor_h[lane_scan_idx] = max(1, real(anchor_rect.h));
            lane_anchor_found += 1;
        }
    }
    if (diag_enabled) {
        diag_ms_anchor_lookup = (get_timer() - diag_anchor_start_us) * 0.001;
    }
    var using_lane_anchors = use_lane_anchors && (lane_anchor_found > 0);

    var notebeam_line_width = variable_struct_exists(global.timeline_cfg, "notebeam_line_width")
        ? max(1, real(global.timeline_cfg.notebeam_line_width))
        : 1;
    var beam_width_px = notebeam_line_width;
    if (!using_lane_anchors && use_label_lane_layout && match_label_width) {
        beam_width_px = lane_row_height_px * match_label_width_scale;
    }
    var lane_center_y = array_create(lane_count, y1 + 1);
    var lane_beam_w = array_create(lane_count, beam_width_px);
    for (var lane_cfg_idx = 0; lane_cfg_idx < lane_count; lane_cfg_idx++) {
        var lane_center = -1;
        var lane_width = beam_width_px;
        if (using_lane_anchors && lane_anchor_y[lane_cfg_idx] >= 0) {
            lane_center = lane_anchor_y[lane_cfg_idx];
            if (lane_anchor_h[lane_cfg_idx] > 0) {
                lane_width = lane_anchor_h[lane_cfg_idx];
            }
        } else {
            var lane_visual_idx_cfg = lane_flip ? (lane_count - 1 - lane_cfg_idx) : lane_cfg_idx;
            lane_center = y1 + ((lane_visual_idx_cfg + 0.5) * lane_h);
            if (use_label_lane_layout) {
                var spacer_px_cfg = ((y2 - y1) * lane_top_spacer_ratio) + lane_top_spacer_px;
                lane_center = y1 + spacer_px_cfg + lane_row_gap_px
                    + (lane_visual_idx_cfg * (lane_row_height_px + lane_row_gap_px))
                    + (lane_row_height_px * 0.5);
            }
        }
        lane_center += lane_y_offset_px;
        lane_center_y[lane_cfg_idx] = clamp(lane_center, y1 + 1, y2 - 1);
        lane_beam_w[lane_cfg_idx] = lane_width;
    }
    var planned_beam_color = variable_struct_exists(global.timeline_cfg, "notebeam_planned_color")
        ? global.timeline_cfg.notebeam_planned_color
        : make_color_rgb(132, 168, 196);
    var planned_beam_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_planned_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_planned_alpha), 0, 1)
        : 0.75;
    var player_beam_color = variable_struct_exists(global.timeline_cfg, "notebeam_player_color")
        ? global.timeline_cfg.notebeam_player_color
        : make_color_rgb(190, 190, 196);
    var player_beam_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_player_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_player_alpha), 0, 1)
        : 0.88;
    var live_player_beam_color = variable_struct_exists(global.timeline_cfg, "notebeam_live_player_color")
        ? variable_struct_get(global.timeline_cfg, "notebeam_live_player_color")
        : make_color_rgb(78, 210, 255);
    var live_player_beam_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_live_player_alpha")
        ? clamp(real(variable_struct_get(global.timeline_cfg, "notebeam_live_player_alpha")), 0, 1)
        : 0.96;
    var player_overlap_colorize = !variable_struct_exists(global.timeline_cfg, "notebeam_player_overlap_colorize")
        || global.timeline_cfg.notebeam_player_overlap_colorize;
    var compare_version = variable_struct_exists(global.timeline_cfg, "notebeam_compare_version")
        ? clamp(floor(real(global.timeline_cfg.notebeam_compare_version)), 1, 3)
        : 1;
    var use_segmented_compare = (compare_version >= 2);
    var use_embellishment_mode = (compare_version >= 3);

    var player_beam_match_color = variable_struct_exists(global.timeline_cfg, "notebeam_player_match_color")
        ? global.timeline_cfg.notebeam_player_match_color
        : make_color_rgb(138, 118, 44);
    var player_beam_emb_match_color = variable_struct_exists(global.timeline_cfg, "notebeam_player_emb_match_color")
        ? global.timeline_cfg.notebeam_player_emb_match_color
        : make_color_rgb(60, 155, 70);
    var player_beam_segment_match_color = variable_struct_exists(global.timeline_cfg, "notebeam_player_segment_match_color")
        ? global.timeline_cfg.notebeam_player_segment_match_color
        : player_beam_emb_match_color;
    var player_beam_miss_color = variable_struct_exists(global.timeline_cfg, "notebeam_player_miss_color")
        ? global.timeline_cfg.notebeam_player_miss_color
        : make_color_rgb(112, 46, 46);
    var player_timing_slack_ms = variable_struct_exists(global.timeline_cfg, "notebeam_player_timing_slack_ms")
        ? max(0, real(global.timeline_cfg.notebeam_player_timing_slack_ms))
        : 50;
    var player_bleed_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_player_bleed_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_player_bleed_alpha), 0, 1)
        : 0.38;
    var player_emb_overlay_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_player_emb_overlay_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_player_emb_overlay_alpha), 0, 1)
        : 0.55;
    var overlap_match_count = -1;
    var overlap_miss_count = -1;
    var overlap_bleed_count = -1;
    var review_mode_active = false;
    var review_split_beams = false;
    var history_markers_enabled = false;
    var history_run_count = 0;
    var history_use_gap_band = !variable_struct_exists(global.timeline_cfg, "notebeam_history_use_gap_band")
        || global.timeline_cfg.notebeam_history_use_gap_band;
    var history_gap_band_active = false;
    var history_start_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_start_color")
        ? global.timeline_cfg.notebeam_history_start_color
        : make_color_rgb(255, 248, 153);
    var history_end_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_end_color")
        ? global.timeline_cfg.notebeam_history_end_color
        : make_color_rgb(255, 248, 153);
    var history_start_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_start_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_start_alpha), 0, 1)
        : 1.0;
    var history_end_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_end_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_end_alpha), 0, 1)
        : 1.0;
    var history_band_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_band_color")
        ? global.timeline_cfg.notebeam_history_band_color
        : make_color_rgb(220, 220, 220);
    var history_band_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_band_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_band_alpha), 0, 1)
        : 0.20;

    var dbg_playhead_ms = -1;

    if (is_active) {
        var base_playhead_ms = real(global.timeline_state.playhead_ms ?? 0);
        var view_offset_ms = variable_struct_exists(global.timeline_cfg, "notebeam_view_offset_ms")
            ? real(variable_struct_get(global.timeline_cfg, "notebeam_view_offset_ms"))
            : 0;
        var visual_cal_ms = variable_struct_exists(global.timeline_cfg, "visual_alignment_offset_ms")
            ? real(global.timeline_cfg.visual_alignment_offset_ms)
            : 0;
        var playhead_ms = max(0, base_playhead_ms + view_offset_ms + visual_cal_ms);
        if (variable_struct_exists(global.timeline_state, "playback_complete")
            && global.timeline_state.playback_complete
            && variable_struct_exists(global.timeline_state, "review_end_ms")) {
            playhead_ms = clamp(playhead_ms, 0, max(0, real(global.timeline_state.review_end_ms)));
        }
        dbg_playhead_ms = playhead_ms;
        var ms_behind = max(1, real(global.timeline_state.ms_behind ?? 1));
        var ms_ahead = max(1, real(global.timeline_state.ms_ahead ?? 1));
        var t_min = playhead_ms - ms_behind;
        var t_max = playhead_ms + ms_ahead;
        review_mode_active = variable_struct_exists(global.timeline_state, "playback_complete")
            && global.timeline_state.playback_complete;
        review_split_beams = review_mode_active
            && variable_struct_exists(global.timeline_cfg, "notebeam_review_split_beams")
            && global.timeline_cfg.notebeam_review_split_beams;
        var postplay_overlay_mode = variable_struct_exists(global.timeline_cfg, "notebeam_postplay_overlay_mode")
            ? floor(real(global.timeline_cfg.notebeam_postplay_overlay_mode))
            : 0;
        // Mode 0=raw, 1=segmented, 2=planned underlay, 3=history markers
        var use_live_blue_beams = review_mode_active && (postplay_overlay_mode != 1);
        var player_beam_render_color = use_live_blue_beams ? live_player_beam_color : player_beam_color;
        // Legacy matcher focus mode is retired in overlap-only flow; keep local flag for safe reads.
        var note_match_focus_enabled = false;
        var match_focus_active = false;
        var match_focus_player_span_index = -1;
        var match_focus_target_event_id = "";
        var match_focus_target_span_index = -1;
        var match_focus_source_kind = "";
        var match_focus_target_expected_ms = 0;
        var match_focus_target_lane_idx = -1;
        var match_focus_player_color = live_player_beam_color;
        var match_focus_player_dim_color = make_color_rgb(92, 98, 108);
        var match_focus_planned_color = make_color_rgb(234, 214, 94);
        var match_focus_planned_dim_color = make_color_rgb(188, 188, 192);
        history_markers_enabled = review_mode_active
            && (!variable_struct_exists(global.timeline_cfg, "notebeam_history_enabled") || global.timeline_cfg.notebeam_history_enabled)
            && !diag_disable_history
            && variable_struct_exists(global.timeline_state, "review_history_runs")
            && is_array(global.timeline_state.review_history_runs)
            && array_length(global.timeline_state.review_history_runs) > 0;
        if (postplay_overlay_mode != 3) history_markers_enabled = false;
        history_gap_band_active = history_markers_enabled && history_use_gap_band && !review_split_beams;
        history_run_count = history_markers_enabled
            ? array_length(global.timeline_state.review_history_runs)
            : 0;

        var player_offset_ms = variable_struct_exists(global.timeline_cfg, "input_capture_offset_ms")
            ? real(global.timeline_cfg.input_capture_offset_ms)
            : 0;

        var planned_spans = [];
        if (variable_struct_exists(global.timeline_state, "planned_spans") && is_array(global.timeline_state.planned_spans)) {
            planned_spans = global.timeline_state.planned_spans;
        }
        var planned_events = [];
        if (variable_struct_exists(global.timeline_state, "planned_events") && is_array(global.timeline_state.planned_events)) {
            planned_events = global.timeline_state.planned_events;
        }
        var can_compare_overlap = review_mode_active
            && (postplay_overlay_mode == 1)
            && use_segmented_compare
            && player_overlap_colorize
            && !diag_disable_overlap_compare
            && is_array(planned_spans)
            && array_length(planned_spans) > 0
            && gv_planned_spans_have_focus_channel(planned_spans);
        if (note_match_focus_enabled && match_focus_active) {
            can_compare_overlap = false;
        }
        overlap_match_count = 0;
        overlap_miss_count = 0;
        overlap_bleed_count = 0;

        var use_emb_classify = false;
        var player_emb_classify = undefined;
        if (use_embellishment_mode
            && can_compare_overlap
            && review_mode_active
            && variable_struct_exists(global.timeline_state, "emb_groups")
            && is_array(global.timeline_state.emb_groups)
            && array_length(global.timeline_state.emb_groups) > 0) {
            use_emb_classify = true;
            var diag_overlap_start_us = diag_enabled ? get_timer() : 0;
            player_emb_classify = gv_classify_player_spans_for_emb(
                global.timeline_state.emb_groups,
                variable_struct_exists(global.timeline_state, "player_in") ? global.timeline_state.player_in : [],
                variable_struct_exists(global.timeline_state, "pending_player") ? global.timeline_state.pending_player : {},
                playhead_ms,
                player_offset_ms
            );
            if (diag_enabled) {
                diag_ms_overlap += (get_timer() - diag_overlap_start_us) * 0.001;
            }
        }

        var ghost_parts_enabled = gv_use_tune_ghost_parts();
        var ghost_parts_alpha = gv_get_tune_other_parts_alpha();
        var nb_target_ch = gv_get_target_tune_channel();
        var planned_min_visible_px = variable_struct_exists(global.timeline_cfg, "notebeam_planned_min_visible_px")
            ? max(0, real(global.timeline_cfg.notebeam_planned_min_visible_px))
            : 1.0;
        var planned_view_pad_px = variable_struct_exists(global.timeline_cfg, "notebeam_planned_view_pad_px")
            ? max(0, real(global.timeline_cfg.notebeam_planned_view_pad_px))
            : 0.5;
        var emb_group_count = (variable_struct_exists(global.timeline_state, "emb_groups") && is_array(global.timeline_state.emb_groups))
            ? array_length(global.timeline_state.emb_groups)
            : 0;
        // Cache only in review mode (static playhead). Live mode scrolls every frame,
        // so drawing underlay directly avoids stale-step jitter from cached invalidation.
        var use_underlay_cache = (!diag_enabled)
            && review_mode_active
            && (!variable_struct_exists(global.timeline_cfg, "notebeam_underlay_cache_enabled")
                || global.timeline_cfg.notebeam_underlay_cache_enabled);

        var underlay_ctx = {
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            playhead_ms: playhead_ms,
            t_min: t_min,
            t_max: t_max,
            ms_behind: ms_behind,
            ms_ahead: ms_ahead,
            now_ratio: now_ratio,
            lane_count: lane_count,
            lane_h: lane_h,
            using_lane_anchors: using_lane_anchors,
            lane_anchor_y: lane_anchor_y,
            lane_anchor_h: lane_anchor_h,
            lane_center_y: lane_center_y,
            lane_beam_w: lane_beam_w,
            beam_width_px: beam_width_px,
            match_label_width: match_label_width,
            match_label_width_scale: match_label_width_scale,
            lane_flip: lane_flip,
            use_label_lane_layout: use_label_lane_layout,
            lane_top_spacer_ratio: lane_top_spacer_ratio,
            lane_top_spacer_px: lane_top_spacer_px,
            lane_row_height_px: lane_row_height_px,
            lane_row_gap_px: lane_row_gap_px,
            lane_y_offset_px: lane_y_offset_px,
            review_mode_active: review_mode_active,
            review_split_beams: review_split_beams,
            diag_disable_beat_boxes: diag_disable_beat_boxes,
            diag_disable_emb_boxes: diag_disable_emb_boxes,
            diag_disable_planned: diag_disable_planned,
            planned_spans: planned_spans,
            planned_span_count: is_array(planned_spans) ? array_length(planned_spans) : 0,
            planned_events: planned_events,
            planned_event_count: is_array(planned_events) ? array_length(planned_events) : 0,
            emb_group_count: emb_group_count,
            planned_beam_color: planned_beam_color,
            planned_beam_alpha: planned_beam_alpha,
            planned_min_visible_px: planned_min_visible_px,
            planned_view_pad_px: planned_view_pad_px,
            ghost_parts_enabled: ghost_parts_enabled,
            ghost_parts_alpha: ghost_parts_alpha,
            target_tune_channel: nb_target_ch
        };

        if (use_underlay_cache) {
            if (!variable_global_exists("notebeam_underlay_surface")) global.notebeam_underlay_surface = noone;
            if (!variable_global_exists("notebeam_underlay_surface_valid")) global.notebeam_underlay_surface_valid = false;
            if (!variable_global_exists("notebeam_underlay_surface_last_playhead_ms")) global.notebeam_underlay_surface_last_playhead_ms = -9999;
            if (!variable_global_exists("notebeam_underlay_surface_signature")) global.notebeam_underlay_surface_signature = "";

            var underlay_threshold_ms = variable_struct_exists(global.timeline_cfg, "notebeam_underlay_invalidation_ms")
                ? max(1, real(global.timeline_cfg.notebeam_underlay_invalidation_ms))
                : 33;
            var underlay_signature = gv_get_notebeam_underlay_surface_signature(underlay_ctx);
            var underlay_playhead_delta = abs(playhead_ms - real(global.notebeam_underlay_surface_last_playhead_ms));
            var underlay_cache_needs_redraw = !surface_exists(global.notebeam_underlay_surface)
                || !global.notebeam_underlay_surface_valid
                || string(global.notebeam_underlay_surface_signature) != underlay_signature
                || underlay_playhead_delta >= underlay_threshold_ms;

            if (underlay_cache_needs_redraw) {
                var underlay_w = max(1, x2 - x1);
                var underlay_h = max(1, y2 - y1);
                var underlay_surf = gv_ensure_notebeam_underlay_surface_cache(underlay_w, underlay_h);
                var lane_center_y_local = array_create(lane_count, 0);
                var lane_anchor_y_local = array_create(lane_count, -1);
                for (var ul_i = 0; ul_i < lane_count; ul_i++) {
                    lane_center_y_local[ul_i] = lane_center_y[ul_i] - y1;
                    if (lane_anchor_y[ul_i] >= 0) {
                        lane_anchor_y_local[ul_i] = lane_anchor_y[ul_i] - y1;
                    }
                }

                var underlay_local_ctx = {
                    x1: 0,
                    y1: 0,
                    x2: underlay_w,
                    y2: underlay_h,
                    playhead_ms: playhead_ms,
                    t_min: t_min,
                    t_max: t_max,
                    ms_behind: ms_behind,
                    ms_ahead: ms_ahead,
                    now_ratio: now_ratio,
                    lane_count: lane_count,
                    lane_h: lane_h,
                    using_lane_anchors: using_lane_anchors,
                    lane_anchor_y: lane_anchor_y_local,
                    lane_anchor_h: lane_anchor_h,
                    lane_center_y: lane_center_y_local,
                    lane_beam_w: lane_beam_w,
                    beam_width_px: beam_width_px,
                    match_label_width: match_label_width,
                    match_label_width_scale: match_label_width_scale,
                    lane_flip: lane_flip,
                    use_label_lane_layout: use_label_lane_layout,
                    lane_top_spacer_ratio: lane_top_spacer_ratio,
                    lane_top_spacer_px: lane_top_spacer_px,
                    lane_row_height_px: lane_row_height_px,
                    lane_row_gap_px: lane_row_gap_px,
                    lane_y_offset_px: lane_y_offset_px,
                    review_mode_active: review_mode_active,
                    review_split_beams: review_split_beams,
                    diag_disable_beat_boxes: diag_disable_beat_boxes,
                    diag_disable_emb_boxes: diag_disable_emb_boxes,
                    diag_disable_planned: diag_disable_planned,
                    planned_spans: planned_spans,
                    planned_span_count: is_array(planned_spans) ? array_length(planned_spans) : 0,
                    planned_events: planned_events,
                    planned_event_count: is_array(planned_events) ? array_length(planned_events) : 0,
                    emb_group_count: emb_group_count,
                    planned_beam_color: planned_beam_color,
                    planned_beam_alpha: planned_beam_alpha,
                    planned_min_visible_px: planned_min_visible_px,
                    planned_view_pad_px: planned_view_pad_px,
                    ghost_parts_enabled: ghost_parts_enabled,
                    ghost_parts_alpha: ghost_parts_alpha,
                    target_tune_channel: nb_target_ch
                };

                surface_set_target(underlay_surf);
                draw_clear_alpha(c_black, 0);
                gv_draw_notebeam_underlay_layers(underlay_local_ctx);
                surface_reset_target();

                global.notebeam_underlay_surface_valid = true;
                global.notebeam_underlay_surface_last_playhead_ms = playhead_ms;
                global.notebeam_underlay_surface_signature = underlay_signature;
            }

            if (surface_exists(global.notebeam_underlay_surface)) {
                draw_set_color(c_white);
                draw_set_alpha(1);
                draw_surface(global.notebeam_underlay_surface, x1, y1);
            }
        } else {
            gv_draw_notebeam_underlay_layers(underlay_ctx);
        }

        if (!diag_disable_player
            && variable_struct_exists(global.timeline_state, "player_in")
            && is_array(global.timeline_state.player_in)) {
            var diag_player_start_us = diag_enabled ? get_timer() : 0;
            var player_spans = global.timeline_state.player_in;
            // Keep hitbox indices aligned with scorer assignment indices:
            // scorer uses review_full_trace whenever available.
            var use_trace_for_matching = review_mode_active || popup_clicks_enabled || can_compare_overlap;
            if (use_trace_for_matching
                && variable_struct_exists(global.timeline_state, "review_full_trace")
                && is_array(global.timeline_state.review_full_trace)
                && array_length(global.timeline_state.review_full_trace) > 0) {
                player_spans = global.timeline_state.review_full_trace;
            }
            var live_player_cache_ok = !review_mode_active
                && !popup_clicks_enabled
                && !can_compare_overlap
                && !use_emb_classify;

            if (!variable_global_exists("notebeam_live_player_surface")) global.notebeam_live_player_surface = noone;
            if (!variable_global_exists("notebeam_live_player_surface_valid")) global.notebeam_live_player_surface_valid = false;
            if (!variable_global_exists("notebeam_live_player_surface_last_playhead_ms")) global.notebeam_live_player_surface_last_playhead_ms = -9999;
            if (!variable_global_exists("notebeam_live_player_surface_last_span_count")) global.notebeam_live_player_surface_last_span_count = -1;
            if (!variable_global_exists("notebeam_live_player_surface_last_ms_behind")) global.notebeam_live_player_surface_last_ms_behind = -1;
            if (!variable_global_exists("notebeam_live_player_surface_last_ms_ahead")) global.notebeam_live_player_surface_last_ms_ahead = -1;
            if (!variable_global_exists("notebeam_live_player_surface_last_now_ratio")) global.notebeam_live_player_surface_last_now_ratio = -1;
            if (!variable_global_exists("notebeam_live_player_surface_invalidation_threshold_ms")) global.notebeam_live_player_surface_invalidation_threshold_ms = 16;

            if (live_player_cache_ok) {
                var cache_w = max(1, x2 - x1);
                var cache_h = max(1, y2 - y1);
                var cache_span_count = array_length(player_spans);
                var cache_playhead_delta = abs(playhead_ms - real(global.notebeam_live_player_surface_last_playhead_ms));
                var cache_surface_missing = !surface_exists(global.notebeam_live_player_surface);
                var cache_window_changed = abs(real(global.notebeam_live_player_surface_last_ms_behind) - ms_behind) > 0.001
                    || abs(real(global.notebeam_live_player_surface_last_ms_ahead) - ms_ahead) > 0.001
                    || abs(real(global.notebeam_live_player_surface_last_now_ratio) - now_ratio) > 0.0001;
                var cache_needs_redraw = cache_surface_missing
                    || !global.notebeam_live_player_surface_valid
                    || cache_span_count != floor(real(global.notebeam_live_player_surface_last_span_count))
                    || cache_window_changed
                    || cache_playhead_delta >= real(global.notebeam_live_player_surface_invalidation_threshold_ms);

                if (cache_needs_redraw) {
                    var live_surf = gv_ensure_notebeam_live_player_surface_cache(cache_w, cache_h);
                    gv_render_notebeam_live_player_surface(
                        live_surf,
                        player_spans,
                        x1, y1, x2, y2,
                        playhead_ms, t_min, t_max, player_offset_ms, now_ratio, ms_behind, ms_ahead,
                        lane_count, lane_center_y, lane_beam_w,
                        live_player_beam_color, live_player_beam_alpha
                    );
                    global.notebeam_live_player_surface_valid = true;
                    global.notebeam_live_player_surface_last_playhead_ms = playhead_ms;
                    global.notebeam_live_player_surface_last_span_count = cache_span_count;
                    global.notebeam_live_player_surface_last_ms_behind = ms_behind;
                    global.notebeam_live_player_surface_last_ms_ahead = ms_ahead;
                    global.notebeam_live_player_surface_last_now_ratio = now_ratio;
                }

                if (surface_exists(global.notebeam_live_player_surface)) {
                    draw_set_color(c_white);
                    draw_set_alpha(1);
                    draw_surface(global.notebeam_live_player_surface, x1, y1);
                }
            } else {
                draw_set_alpha(player_beam_alpha);

                var n_player = array_length(player_spans);
                // Binary search: skip player spans that completed before t_min
                var _qbs_raw_tmin = t_min - player_offset_ms;
                var _qbs_lo = 0; var _qbs_hi = n_player;
                while (_qbs_lo < _qbs_hi) {
                    var _qbs_mid = (_qbs_lo + _qbs_hi) >> 1;
                    if (real(player_spans[_qbs_mid].end_ms ?? 0) < _qbs_raw_tmin) _qbs_lo = _qbs_mid + 1;
                    else _qbs_hi = _qbs_mid;
                }
                var player_first_j = _qbs_lo;
                for (var j = player_first_j; j < n_player; j++) {
                    var ps2 = player_spans[j];
                    if (!is_struct(ps2)) continue;
                    var q_start = real(ps2.start_ms ?? 0) + player_offset_ms;
                    var q_end = real(ps2.end_ms ?? q_start) + player_offset_ms;
                    if (q_start > t_max) break; // player_in is time-sorted; all later spans are future

                var lane_idx2 = real(ps2.lane_idx ?? -999);
                if (lane_idx2 == -999) {
                    lane_idx2 = gv_note_to_lane_index(ps2.note_canonical ?? "", ps2.note_midi ?? -1, ps2.channel ?? -1);
                }
                if (lane_idx2 < 0 || lane_idx2 >= lane_count) continue;

                var qx1 = gv_time_to_x(q_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var qx2 = gv_time_to_x(q_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var qlx = clamp(min(qx1, qx2), x1, x2);
                var qrx = clamp(max(qx1, qx2), x1, x2);
                if (qrx <= qlx) {
                    if (qlx >= x2) {
                        qlx = max(x1, x2 - 1);
                        qrx = x2;
                    } else {
                        qrx = min(x2, qlx + 1);
                    }
                }
                if (qrx <= qlx) continue;

                var qy = lane_center_y[lane_idx2];
                var lane_beam_width2 = lane_beam_w[lane_idx2];

                var qy_draw = qy;
                var lane_beam_draw_width2 = lane_beam_width2;
                if (review_split_beams) {
                    qy_draw = clamp(qy - (lane_beam_width2 * 0.25), y1 + 1, y2 - 1);
                    lane_beam_draw_width2 = max(1, lane_beam_width2 * 0.5);
                }

                var emb_j = (use_emb_classify && !is_undefined(player_emb_classify))
                    ? player_emb_classify.player_states[j] : -1;
                var emb_grace_ok_j = false;
                if (use_emb_classify && !is_undefined(player_emb_classify)
                    && variable_struct_exists(player_emb_classify, "player_grace_overlay")
                    && is_array(player_emb_classify.player_grace_overlay)
                    && j >= 0 && j < array_length(player_emb_classify.player_grace_overlay)) {
                    emb_grace_ok_j = player_emb_classify.player_grace_overlay[j];
                }

                if (use_emb_classify && emb_grace_ok_j && emb_j == 2) {
                    overlap_match_count += 1;
                    draw_set_alpha(player_emb_overlay_alpha);
                    draw_set_color(player_beam_emb_match_color);
                    draw_line_width(qlx, qy_draw, qrx, qy_draw, lane_beam_draw_width2);
                } else {
                    if (can_compare_overlap) {
                        // In review mode, use pre-classified match state (computed once at playback end)
                        // to avoid O(M) comparison per span per frame.
                        var player_tstate;
                        if (review_mode_active && variable_struct_exists(ps2, "review_match_state")) {
                            player_tstate = real(ps2.review_match_state);
                            if (player_tstate == 2) {
                                // Full match: solid green
                                draw_set_alpha(player_beam_alpha);
                                draw_set_color(player_beam_segment_match_color);
                                draw_line_width(qlx, qy_draw, qrx, qy_draw, lane_beam_draw_width2);
                            } else if (player_tstate == 0) {
                                // Full miss: solid red
                                draw_set_alpha(player_beam_alpha * 0.95);
                                draw_set_color(player_beam_miss_color);
                                draw_line_width(qlx, qy_draw, qrx, qy_draw, lane_beam_draw_width2);
                            } else {
                                // Bleed (partial): full draw for accurate segment colouring
                                player_tstate = gv_player_span_classify_and_draw(
                                    planned_spans, q_start, q_end, lane_idx2, player_timing_slack_ms,
                                    playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead,
                                    qy_draw, lane_beam_draw_width2, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                                );
                            }
                        } else {
                            player_tstate = gv_player_span_classify_and_draw(
                                planned_spans, q_start, q_end, lane_idx2, player_timing_slack_ms,
                                playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead,
                                qy_draw, lane_beam_draw_width2, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                            );
                        }
                        if (player_tstate == 2) overlap_match_count += 1;
                        else if (player_tstate == 1) overlap_bleed_count += 1;
                        else overlap_miss_count += 1;
                    } else {
                            var focus_player_hit = match_focus_active && (j == match_focus_player_span_index);
                            var focus_player_dim = match_focus_active && !focus_player_hit;
                            if (focus_player_hit) {
                                draw_set_alpha(player_beam_alpha);
                                draw_set_color(match_focus_player_color);
                            } else if (focus_player_dim) {
                                draw_set_alpha(player_beam_alpha * 0.72);
                                draw_set_color(match_focus_player_dim_color);
                            } else {
                                draw_set_alpha(player_beam_alpha);
                                draw_set_color(player_beam_render_color);
                            }
                        draw_line_width(qlx, qy_draw, qrx, qy_draw, lane_beam_draw_width2);
                    }
                }
                draw_set_alpha(player_beam_alpha);

                    if (popup_clicks_enabled) {
                        var hit_pad_y = max(4, lane_beam_draw_width2 * 0.5);
                        var hit_y1 = max(y1, qy_draw - hit_pad_y);
                        var hit_y2 = min(y2, qy_draw + hit_pad_y);

                        if (can_compare_overlap) {
                            var seg_overlaps = gv_collect_lane_overlap_segments(planned_spans, q_start, q_end, lane_idx2);
                            var seg_cursor = q_start;
                            var n_seg_overlaps = array_length(seg_overlaps);

                            for (var si = 0; si < n_seg_overlaps; si++) {
                                var seg = seg_overlaps[si];
                                var seg_s = max(seg_cursor, real(seg.start_ms ?? seg_cursor));
                                var seg_e = min(q_end, real(seg.end_ms ?? seg_s));
                                if (seg_e <= seg_s) continue;

                                if (seg_s > seg_cursor) {
                                    var miss_x1 = gv_time_to_x(seg_cursor, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                    var miss_x2 = gv_time_to_x(seg_s, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                    var miss_lx = clamp(min(miss_x1, miss_x2), x1, x2);
                                    var miss_rx = clamp(max(miss_x1, miss_x2), x1, x2);
                                    if (miss_rx > miss_lx) {
                                        var miss_span = {
                                            source: string(ps2.source ?? "player_midi_in"),
                                            start_ms: seg_cursor,
                                            end_ms: seg_s,
                                            dur_ms: max(0, seg_s - seg_cursor),
                                            note_midi: real(ps2.note_midi ?? -1),
                                            note_canonical: string(ps2.note_canonical ?? ""),
                                            note_letter: string(ps2.note_letter ?? ""),
                                            channel: real(ps2.channel ?? -1),
                                            lane_idx: lane_idx2
                                        };
                                        array_push(global.timeline_state.notebeam_player_hitboxes, {
                                            x1: miss_lx + hitbox_x_bias,
                                            y1: hit_y1 + hitbox_y_bias,
                                            x2: miss_rx + hitbox_x_bias,
                                            y2: hit_y2 + hitbox_y_bias,
                                            player_span: miss_span,
                                            player_span_index: j
                                        });
                                    }
                                }

                                var match_x1 = gv_time_to_x(seg_s, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                var match_x2 = gv_time_to_x(seg_e, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                var match_lx = clamp(min(match_x1, match_x2), x1, x2);
                                var match_rx = clamp(max(match_x1, match_x2), x1, x2);
                                if (match_rx > match_lx) {
                                    var match_span = {
                                        source: string(ps2.source ?? "player_midi_in"),
                                        start_ms: seg_s,
                                        end_ms: seg_e,
                                        dur_ms: max(0, seg_e - seg_s),
                                        note_midi: real(ps2.note_midi ?? -1),
                                        note_canonical: string(ps2.note_canonical ?? ""),
                                        note_letter: string(ps2.note_letter ?? ""),
                                        channel: real(ps2.channel ?? -1),
                                        lane_idx: lane_idx2
                                    };
                                    array_push(global.timeline_state.notebeam_player_hitboxes, {
                                        x1: match_lx + hitbox_x_bias,
                                        y1: hit_y1 + hitbox_y_bias,
                                        x2: match_rx + hitbox_x_bias,
                                        y2: hit_y2 + hitbox_y_bias,
                                        player_span: match_span,
                                        player_span_index: j
                                    });
                                }

                                seg_cursor = max(seg_cursor, seg_e);
                            }

                            if (seg_cursor < q_end) {
                                var tail_x1 = gv_time_to_x(seg_cursor, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                var tail_x2 = gv_time_to_x(q_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                                var tail_lx = clamp(min(tail_x1, tail_x2), x1, x2);
                                var tail_rx = clamp(max(tail_x1, tail_x2), x1, x2);
                                if (tail_rx > tail_lx) {
                                    var tail_span = {
                                        source: string(ps2.source ?? "player_midi_in"),
                                        start_ms: seg_cursor,
                                        end_ms: q_end,
                                        dur_ms: max(0, q_end - seg_cursor),
                                        note_midi: real(ps2.note_midi ?? -1),
                                        note_canonical: string(ps2.note_canonical ?? ""),
                                        note_letter: string(ps2.note_letter ?? ""),
                                        channel: real(ps2.channel ?? -1),
                                        lane_idx: lane_idx2
                                    };
                                    array_push(global.timeline_state.notebeam_player_hitboxes, {
                                        x1: tail_lx + hitbox_x_bias,
                                        y1: hit_y1 + hitbox_y_bias,
                                        x2: tail_rx + hitbox_x_bias,
                                        y2: hit_y2 + hitbox_y_bias,
                                        player_span: tail_span,
                                        player_span_index: j
                                    });
                                }
                            }
                        } else {
                            array_push(global.timeline_state.notebeam_player_hitboxes, {
                                x1: qlx + hitbox_x_bias,
                                y1: hit_y1 + hitbox_y_bias,
                                x2: qrx + hitbox_x_bias,
                                y2: hit_y2 + hitbox_y_bias,
                                player_span: ps2,
                                player_span_index: j
                            });
                        }
                    }
                }
                draw_set_alpha(1);
            }

            if (diag_enabled) {
                diag_ms_player += (get_timer() - diag_player_start_us) * 0.001;
            }
        }

        if (!diag_disable_pending
            && variable_struct_exists(global.timeline_state, "pending_player")
            && is_struct(global.timeline_state.pending_player)) {
            var diag_pending_start_us = diag_enabled ? get_timer() : 0;
            var pending_keys = variable_struct_get_names(global.timeline_state.pending_player);
            if (is_array(pending_keys) && array_length(pending_keys) > 0) {
                draw_set_alpha(player_beam_alpha);

                var n_pending = array_length(pending_keys);
                for (var k = 0; k < n_pending; k++) {
                    var pkey = pending_keys[k];
                    var pp = global.timeline_state.pending_player[$ pkey];
                    if (is_undefined(pp) || !is_struct(pp)) continue;

                    var r_start = real(pp.start_ms ?? playhead_ms) + player_offset_ms;
                    var r_end = max(r_start, playhead_ms + player_offset_ms);
                    if (r_end < t_min || r_start > t_max) continue;

                    var lane_idx3 = real(pp.lane_idx ?? -999);
                    if (lane_idx3 == -999) {
                        lane_idx3 = gv_note_to_lane_index(pp.note_canonical ?? "", pp.note_midi ?? -1, pp.channel ?? -1);
                    }
                    if (lane_idx3 < 0 || lane_idx3 >= lane_count) continue;

                    var rx1 = gv_time_to_x(r_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                    var rx2 = gv_time_to_x(r_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                    var rlx = clamp(min(rx1, rx2), x1, x2);
                    var rrx = clamp(max(rx1, rx2), x1, x2);
                    if (rrx <= rlx) continue;

                    var ry = lane_center_y[lane_idx3];
                    var lane_beam_width3 = lane_beam_w[lane_idx3];

                    var ry_draw = ry;
                    var lane_beam_draw_width3 = lane_beam_width3;
                    if (review_split_beams) {
                        ry_draw = clamp(ry - (lane_beam_width3 * 0.25), y1 + 1, y2 - 1);
                        lane_beam_draw_width3 = max(1, lane_beam_width3 * 0.5);
                    }

                    var emb_k = -1;
                    var emb_grace_ok_k = false;
                    if (use_emb_classify && !is_undefined(player_emb_classify)) {
                        if (variable_struct_exists(player_emb_classify.pending_states, pkey)) {
                            emb_k = real(player_emb_classify.pending_states[$ pkey]);
                        }
                        if (variable_struct_exists(player_emb_classify, "pending_grace_overlay")
                            && variable_struct_exists(player_emb_classify.pending_grace_overlay, pkey)) {
                            emb_grace_ok_k = player_emb_classify.pending_grace_overlay[$ pkey];
                        }
                    }

                    if (use_emb_classify && emb_grace_ok_k && emb_k == 2) {
                        overlap_match_count += 1;
                        draw_set_alpha(player_emb_overlay_alpha);
                        draw_set_color(player_beam_emb_match_color);
                        draw_line_width(rlx, ry_draw, rrx, ry_draw, lane_beam_draw_width3);
                    } else {
                        if (can_compare_overlap) {
                            var pending_tstate = gv_player_span_classify_and_draw(
                                planned_spans, r_start, r_end, lane_idx3, player_timing_slack_ms,
                                playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead,
                                ry_draw, lane_beam_draw_width3, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                            );
                            if (pending_tstate == 2) overlap_match_count += 1;
                            else if (pending_tstate == 1) overlap_bleed_count += 1;
                            else overlap_miss_count += 1;
                        } else {
                            draw_set_alpha(player_beam_alpha);
                            draw_set_color(live_player_beam_color);
                            draw_line_width(rlx, ry_draw, rrx, ry_draw, lane_beam_draw_width3);
                        }
                    }
                    draw_set_alpha(player_beam_alpha);
                }

                draw_set_alpha(1);
            }
            if (diag_enabled) {
                diag_ms_pending += (get_timer() - diag_pending_start_us) * 0.001;
            }
        }

        var diag_history_start_us = diag_enabled ? get_timer() : 0;
        if (history_markers_enabled) {
            var history_runs = global.timeline_state.review_history_runs;
            var n_history_runs = array_length(history_runs);
            var history_pad_ms = variable_struct_exists(global.timeline_cfg, "notebeam_history_window_pad_ms")
                ? max(0, real(variable_struct_get(global.timeline_cfg, "notebeam_history_window_pad_ms")))
                : 250;
            var history_raw_min = t_min - player_offset_ms - history_pad_ms;
            var history_raw_max = t_max - player_offset_ms + history_pad_ms;
                // Background band across the bottom half of every lane
                draw_set_alpha(history_band_alpha);
                draw_set_color(history_band_color);
                for (var bl = 0; bl < lane_count; bl++) {
                    var band_metrics = gv_get_notebeam_lane_metrics(
                        bl, lane_count, y1, y2, lane_h,
                        using_lane_anchors, lane_anchor_y, lane_anchor_h,
                        beam_width_px, match_label_width, match_label_width_scale,
                        lane_flip, use_label_lane_layout, lane_top_spacer_ratio, lane_top_spacer_px,
                        lane_row_height_px, lane_row_gap_px, lane_y_offset_px,
                        history_gap_band_active
                    );
                    if (!is_struct(band_metrics)) continue;
                    var by1 = clamp(real(band_metrics.history_y1), y1, y2);
                    var by2 = clamp(real(band_metrics.history_y2), y1, y2);
                    if (by2 > by1) draw_rectangle(x1, by1, x2, by2, false);
                }

            for (var hr = 0; hr < n_history_runs; hr++) {
                var history_run = history_runs[hr];
                if (!is_struct(history_run)
                    || !variable_struct_exists(history_run, "player_spans")
                    || !is_array(history_run.player_spans)) {
                    continue;
                }

                var run_alpha_scale = 1.0;
                if (n_history_runs > 1) {
                    run_alpha_scale = 1.0 - ((real(hr) / max(1, n_history_runs - 1)) * 0.45);
                }

                var history_spans = history_run.player_spans;
                var n_history_spans = array_length(history_spans);
                var hs_lo = 0;
                var hs_hi = n_history_spans;
                while (hs_lo < hs_hi) {
                    var hs_mid = (hs_lo + hs_hi) >> 1;
                    var hs_span = history_spans[hs_mid];
                    if (!is_struct(hs_span)) {
                        hs_lo = hs_mid + 1;
                        continue;
                    }
                    var hs_end = max(real(hs_span.start_ms ?? 0), real(hs_span.end_ms ?? 0));
                    if (hs_end < history_raw_min) hs_lo = hs_mid + 1;
                    else hs_hi = hs_mid;
                }

                for (var hs = hs_lo; hs < n_history_spans; hs++) {
                    var hspan = history_spans[hs];
                    if (!is_struct(hspan)) continue;

                    var h_start_raw = real(hspan.start_ms ?? 0);
                    var h_end_raw = real(hspan.end_ms ?? h_start_raw);
                    if (h_start_raw > history_raw_max) break;
                    var h_start = h_start_raw + player_offset_ms;
                    var h_end = max(h_start, h_end_raw + player_offset_ms);
                    if (h_end < t_min || h_start > t_max) continue;

                    var h_lane_idx = variable_struct_exists(hspan, "lane_idx")
                        ? floor(real(hspan.lane_idx))
                        : gv_note_to_lane_index(hspan.note_canonical ?? "", hspan.note_midi ?? -1, hspan.channel ?? -1);
                    if (h_lane_idx < 0 || h_lane_idx >= lane_count) continue;

                    var lane_metrics = gv_get_notebeam_lane_metrics(
                        h_lane_idx, lane_count, y1, y2, lane_h,
                        using_lane_anchors, lane_anchor_y, lane_anchor_h,
                        beam_width_px, match_label_width, match_label_width_scale,
                        lane_flip, use_label_lane_layout, lane_top_spacer_ratio, lane_top_spacer_px,
                        lane_row_height_px, lane_row_gap_px, lane_y_offset_px,
                        history_gap_band_active
                    );
                    if (!is_struct(lane_metrics)) continue;

                    var hx1 = clamp(gv_time_to_x(h_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead), x1, x2);
                    var hx2 = clamp(gv_time_to_x(h_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead), x1, x2);
                    var hy1 = clamp(real(lane_metrics.history_y1), y1 + 1, y2 - 1);
                    var hy2 = clamp(real(lane_metrics.history_y2), y1 + 1, y2 - 1);
                    if (hy2 < hy1) hy2 = hy1;
                    var hmid_y = clamp(real(lane_metrics.history_mid_y), y1 + 1, y2 - 1);

                    draw_set_alpha(clamp(history_start_alpha * run_alpha_scale, 0, 1));
                    draw_set_color(history_start_color);
                    draw_line_width(hx1, hy1, hx1, hy2, 1);

                    draw_set_alpha(clamp(history_end_alpha * run_alpha_scale, 0, 1));
                    draw_set_color(history_end_color);
                    draw_point(hx2, hmid_y);
                }
            }

            draw_set_alpha(1);
        }
        else if (review_mode_active && (postplay_overlay_mode == 2 || (note_match_focus_enabled && match_focus_active))) {
            // Mode 2: Planned notes Ã¢â‚¬â€ render planned spans in the history sub-row
            var _pov_n = array_length(planned_spans);
            for (var _pov_i = 0; _pov_i < _pov_n; _pov_i++) {
                var _pov_span = planned_spans[_pov_i];
                if (!is_struct(_pov_span)) continue;
                var _pov_ch = real(_pov_span.channel ?? -1);
                if (!gv_is_tune_focus_channel(_pov_ch)) continue;
                var _pov_start = real(_pov_span.start_ms ?? 0);
                var _pov_end   = real(_pov_span.end_ms ?? _pov_start);
                if (_pov_end < t_min || _pov_start > t_max) continue;
                var _pov_note  = real(_pov_span.note_midi ?? -1);
                var _pov_canon = _pov_span.note_canonical ?? "";
                var _pov_lane  = gv_note_to_lane_index(_pov_canon, _pov_note, _pov_ch);
                if (_pov_lane < 0 || _pov_lane >= lane_count) continue;
                var _pov_m = gv_get_notebeam_lane_metrics(
                    _pov_lane, lane_count, y1, y2, lane_h,
                    using_lane_anchors, lane_anchor_y, lane_anchor_h,
                    beam_width_px, match_label_width, match_label_width_scale,
                    lane_flip, use_label_lane_layout, lane_top_spacer_ratio, lane_top_spacer_px,
                    lane_row_height_px, lane_row_gap_px, lane_y_offset_px, false
                );
                if (!is_struct(_pov_m)) continue;
                var _pov_x1 = clamp(gv_time_to_x(_pov_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead), x1, x2);
                var _pov_x2 = clamp(gv_time_to_x(_pov_end,   playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead), x1, x2);
                var _pov_lx = clamp(min(_pov_x1, _pov_x2), x1, x2);
                var _pov_rx = clamp(max(_pov_x1, _pov_x2), x1, x2);
                if (_pov_rx <= _pov_lx) continue;
                var _pov_y1 = clamp(real(_pov_m.history_y1), y1 + 1, y2 - 1);
                var _pov_y2 = clamp(real(_pov_m.history_y2), y1 + 1, y2 - 1);
                if (_pov_y2 < _pov_y1) _pov_y2 = _pov_y1;
                var _pov_mid_y = clamp(real(_pov_m.history_mid_y), y1 + 1, y2 - 1);
                var _pov_w = max(1, _pov_y2 - _pov_y1);
                var _pov_is_focus = false;
                if (match_focus_active) {
                    if (match_focus_target_span_index >= 0 && _pov_i == match_focus_target_span_index) {
                        _pov_is_focus = true;
                    } else {
                        var _pov_event_id = string(_pov_span.event_id ?? "");
                        if (match_focus_target_event_id != "" && _pov_event_id == match_focus_target_event_id) {
                            _pov_is_focus = true;
                        } else if (match_focus_source_kind == "embellishment_unit" || match_focus_source_kind == "emb_cluster") {
                            var _pov_lane_idx = variable_struct_exists(_pov_span, "lane_idx")
                                ? floor(real(_pov_span.lane_idx))
                                : gv_note_to_lane_index(_pov_span.note_canonical ?? "", _pov_span.note_midi ?? -1, _pov_span.channel ?? -1);
                            var _pov_dist = abs(_pov_start - match_focus_target_expected_ms);
                            _pov_is_focus = (_pov_lane_idx == match_focus_target_lane_idx) && (_pov_dist <= 200);
                        }
                    }
                }

                if (match_focus_active) {
                    if (_pov_is_focus) {
                        draw_set_alpha(history_end_alpha);
                        draw_set_color(match_focus_planned_color);
                    } else {
                        draw_set_alpha(history_end_alpha * 0.58);
                        draw_set_color(match_focus_planned_dim_color);
                    }
                } else {
                    draw_set_alpha(history_end_alpha);
                    draw_set_color(history_end_color);
                }
                draw_line_width(_pov_lx, _pov_mid_y, _pov_rx, _pov_mid_y, _pov_w);
            }
            draw_set_alpha(1);
        }
        // Mode 3 (history markers) is handled by history_markers_enabled above.
        if (diag_enabled) {
            diag_ms_history += (get_timer() - diag_history_start_us) * 0.001;
        }
    }


    var show_outline = variable_struct_exists(global.timeline_cfg, "notebeam_show_debug_outline")
        && global.timeline_cfg.notebeam_show_debug_outline;
    var debug_log_enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_debug_log")
        || global.timeline_cfg.notebeam_debug_log;

    var dbg_planned = (is_active && variable_struct_exists(global.timeline_state, "planned_spans") && is_array(global.timeline_state.planned_spans))
        ? array_length(global.timeline_state.planned_spans)
        : -1;
    var dbg_player = (is_active && variable_struct_exists(global.timeline_state, "player_in") && is_array(global.timeline_state.player_in))
        ? array_length(global.timeline_state.player_in)
        : -1;
    var dbg_pending = -1;
    if (is_active && variable_struct_exists(global.timeline_state, "pending_player") && is_struct(global.timeline_state.pending_player)) {
        dbg_pending = 0;
        var dbg_pending_keys = variable_struct_get_names(global.timeline_state.pending_player);
        for (var pdi = 0; pdi < array_length(dbg_pending_keys); pdi++) {
            var dbg_p = global.timeline_state.pending_player[$ dbg_pending_keys[pdi]];
            if (!is_undefined(dbg_p) && is_struct(dbg_p)) {
                dbg_pending += 1;
            }
        }
    }
    var dbg_line = "NB " + string(floor(x2 - x1)) + "x" + string(floor(y2 - y1));
    dbg_line += " act=" + string(is_active);
    dbg_line += " P=" + string(dbg_planned);
    dbg_line += " R=" + string(dbg_player);
    dbg_line += " H=" + string(dbg_pending);
    dbg_line += " G=" + string(history_run_count);
    if (dbg_playhead_ms >= 0) {
        dbg_line += " PH=" + string(floor(dbg_playhead_ms));
    }
    if (overlap_match_count >= 0) {
        dbg_line += " Y=" + string(overlap_match_count);
        dbg_line += " B=" + string(overlap_bleed_count);
        dbg_line += " N=" + string(overlap_miss_count);
    }
    dbg_line += " A=" + (use_lane_anchors ? (string(lane_anchor_found) + "/" + string(lane_count)) : "off");
    dbg_line += " now_x=" + string(floor(now_x));
    if (using_lane_anchors && lane_anchor_found > 0) {
        dbg_line += " lh=";
        for (var _dli = 0; _dli < lane_count; _dli++) {
            if (_dli > 0) dbg_line += ",";
            dbg_line += string(floor(lane_anchor_h[_dli]));
        }
    }

    if (show_outline) {
        var outline_color = variable_struct_exists(global.timeline_cfg, "notebeam_debug_outline_color")
            ? global.timeline_cfg.notebeam_debug_outline_color
            : c_gray;
        var outline_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_debug_outline_alpha")
            ? clamp(real(global.timeline_cfg.notebeam_debug_outline_alpha), 0, 1)
            : 0.65;
        draw_set_alpha(outline_alpha);
        draw_set_color(outline_color);
        draw_rectangle(x1, y1, x2, y2, true);
        draw_set_alpha(1);

        draw_set_color(c_white);
        draw_text(x1 + 4, y1 + 4, dbg_line);
    }

    if (show_outline || debug_log_enabled) {
        if (!variable_global_exists("NOTEBEAM_DEBUG_LOG_MS")) {
            global.NOTEBEAM_DEBUG_LOG_MS = 0;
        }
        if ((current_time - real(global.NOTEBEAM_DEBUG_LOG_MS)) >= 1000) {
            show_debug_message("[NOTEBEAM] " + dbg_line);
            global.NOTEBEAM_DEBUG_LOG_MS = current_time;
        }
    }

    // Popup is rendered from Draw GUI so it always sits above world-space
    // notebeam content (chanter sprite, now-line overlays, etc.).
    if (diag_enabled) {
        diag_ms_popup += 0;
    }

    if (diag_enabled) {
        var diag_total_ms = (get_timer() - diag_frame_start_us) * 0.001;
        var diag_ms_nowline_pulse = variable_global_exists("NOTEBEAM_DIAG_NOWLINE_PULSE_MS")
            ? real(global.NOTEBEAM_DIAG_NOWLINE_PULSE_MS)
            : 0;
        global.NOTEBEAM_DIAG_NOWLINE_PULSE_MS = 0;
        if (!variable_global_exists("NOTEBEAM_DIAG") || !is_struct(global.NOTEBEAM_DIAG)) {
            global.NOTEBEAM_DIAG = {
                frames: 0,
                sum_total_ms: 0,
                max_total_ms: 0,
                sum_anchor_ms: 0,
                sum_overlap_ms: 0,
                sum_nowline_pulse_ms: 0,
                sum_beat_ms: 0,
                sum_emb_ms: 0,
                sum_planned_ms: 0,
                sum_player_ms: 0,
                sum_pending_ms: 0,
                sum_history_ms: 0,
                sum_popup_ms: 0
            };
        }

        global.NOTEBEAM_DIAG.frames += 1;
        global.NOTEBEAM_DIAG.sum_total_ms += diag_total_ms;
        global.NOTEBEAM_DIAG.max_total_ms = max(global.NOTEBEAM_DIAG.max_total_ms, diag_total_ms);
        global.NOTEBEAM_DIAG.sum_anchor_ms += diag_ms_anchor_lookup;
        global.NOTEBEAM_DIAG.sum_overlap_ms += diag_ms_overlap;
        global.NOTEBEAM_DIAG.sum_nowline_pulse_ms += diag_ms_nowline_pulse;
        global.NOTEBEAM_DIAG.sum_beat_ms += diag_ms_beat_boxes;
        global.NOTEBEAM_DIAG.sum_emb_ms += diag_ms_emb_boxes;
        global.NOTEBEAM_DIAG.sum_planned_ms += diag_ms_planned;
        global.NOTEBEAM_DIAG.sum_player_ms += diag_ms_player;
        global.NOTEBEAM_DIAG.sum_pending_ms += diag_ms_pending;
        global.NOTEBEAM_DIAG.sum_history_ms += diag_ms_history;
        global.NOTEBEAM_DIAG.sum_popup_ms += diag_ms_popup;

        if (global.NOTEBEAM_DIAG.frames >= diag_log_every) {
            var diag_frames = max(1, global.NOTEBEAM_DIAG.frames);
            show_debug_message("[NB_DIAG] avg=" + string_format(global.NOTEBEAM_DIAG.sum_total_ms / diag_frames, 0, 3)
                + "ms max=" + string_format(global.NOTEBEAM_DIAG.max_total_ms, 0, 3)
                + " anchor=" + string_format(global.NOTEBEAM_DIAG.sum_anchor_ms / diag_frames, 0, 3)
                + " overlap=" + string_format(global.NOTEBEAM_DIAG.sum_overlap_ms / diag_frames, 0, 3)
                + " nowpulse=" + string_format(global.NOTEBEAM_DIAG.sum_nowline_pulse_ms / diag_frames, 0, 3)
                + " beat=" + string_format(global.NOTEBEAM_DIAG.sum_beat_ms / diag_frames, 0, 3)
                + " emb=" + string_format(global.NOTEBEAM_DIAG.sum_emb_ms / diag_frames, 0, 3)
                + " planned=" + string_format(global.NOTEBEAM_DIAG.sum_planned_ms / diag_frames, 0, 3)
                + " player=" + string_format(global.NOTEBEAM_DIAG.sum_player_ms / diag_frames, 0, 3)
                + " pending=" + string_format(global.NOTEBEAM_DIAG.sum_pending_ms / diag_frames, 0, 3)
                + " history=" + string_format(global.NOTEBEAM_DIAG.sum_history_ms / diag_frames, 0, 3)
                + " popup=" + string_format(global.NOTEBEAM_DIAG.sum_popup_ms / diag_frames, 0, 3)
                + " off=[P" + string(diag_disable_planned)
                + " R" + string(diag_disable_player)
                + " H" + string(diag_disable_history)
                + " E" + string(diag_disable_emb_boxes)
                + " O" + string(diag_disable_overlap_compare)
                + "]");

            global.NOTEBEAM_DIAG.frames = 0;
            global.NOTEBEAM_DIAG.sum_total_ms = 0;
            global.NOTEBEAM_DIAG.max_total_ms = 0;
            global.NOTEBEAM_DIAG.sum_anchor_ms = 0;
            global.NOTEBEAM_DIAG.sum_overlap_ms = 0;
            global.NOTEBEAM_DIAG.sum_nowline_pulse_ms = 0;
            global.NOTEBEAM_DIAG.sum_beat_ms = 0;
            global.NOTEBEAM_DIAG.sum_emb_ms = 0;
            global.NOTEBEAM_DIAG.sum_planned_ms = 0;
            global.NOTEBEAM_DIAG.sum_player_ms = 0;
            global.NOTEBEAM_DIAG.sum_pending_ms = 0;
            global.NOTEBEAM_DIAG.sum_history_ms = 0;
            global.NOTEBEAM_DIAG.sum_popup_ms = 0;
        }
    }
}
