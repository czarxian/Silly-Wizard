// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information

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

function gv_measure_ms(_bpm, _meter_num, _meter_den) {
    var _quarter_ms = 60000 / max(1, real(_bpm));
    return _quarter_ms * real(_meter_num) * (4 / real(_meter_den));
}


function gv_evt_time_ms(_e) {
    if (!is_struct(_e)) return 0;
    if (variable_struct_exists(_e, "time_ms")) return real(_e.time_ms);
    if (variable_struct_exists(_e, "time")) return real(_e.time);
    if (variable_struct_exists(_e, "timestamp_ms")) return real(_e.timestamp_ms);
    if (variable_struct_exists(_e, "expected_ms")) return real(_e.expected_ms);
    return 0;
}

function gv_note_key(_ch, _note) {
    return string(_ch) + ":" + string(_note);
}

function gv_build_planned_spans(_events) {
    var _spans = [];
    var _active = {}; // key -> stack of note_on structs

    if (!is_array(_events)) return _spans;

    var _n = array_length(_events);
    for (var i = 0; i < _n; i++) {
        var e = _events[i];
        if (!is_struct(e) || !variable_struct_exists(e, "type")) continue;

        var _type = string(e.type);
        if (_type != "note_on" && _type != "note_off") continue;

        var _t = gv_evt_time_ms(e);
        var _ch = variable_struct_exists(e, "channel") ? real(e.channel) : 0;

        var _note = -1;
        if (variable_struct_exists(e, "note")) _note = real(e.note);
        else if (variable_struct_exists(e, "note_midi")) _note = real(e.note_midi);
        if (_note < 0) continue;

        var _measure = variable_struct_exists(e, "measure") ? real(e.measure) : -1;
        var _beat = variable_struct_exists(e, "beat") ? real(e.beat) : -1;
        var _bf = 0;
        if (variable_struct_exists(e, "beat_fraction")) _bf = real(e.beat_fraction);
        else if (variable_struct_exists(e, "beat_frac")) _bf = real(e.beat_frac);
        var _eid = variable_struct_exists(e, "event_id") ? e.event_id : "";
        var _is_emb = variable_struct_exists(e, "is_embellishment") && e.is_embellishment;
        var _canonical = chanter_midi_to_canonical(_note, global.MIDI_chanter ?? "default", _ch);

        var _k = gv_note_key(_ch, _note);

        if (_type == "note_on") {
            var _on = {
                start_ms: _t,
                note_midi: _note,
                note_canonical: _canonical,
                note_letter: chanter_canonical_to_display(_canonical),
                is_embellishment: _is_emb,
                channel: _ch,
                measure: _measure,
                beat: _beat,
                beat_fraction: _bf,
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
                is_embellishment: _on2.is_embellishment,
                channel: _on2.channel,
                measure: _on2.measure,
                beat: _on2.beat,
                beat_fraction: _on2.beat_fraction,
                event_id: _on2.event_id
            });
        }
    }

    return _spans;
}

// Replace your existing function with this version.
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
    global.timeline_state.bpm = _bpm_safe;
    global.timeline_state.meter_num = _meter_num;
    global.timeline_state.meter_den = _meter_den;
    global.timeline_state.measure_ms = _measure_ms;
    global.timeline_state.ms_ahead = _measure_ms * _ahead_measures;
    global.timeline_state.ms_behind = _measure_ms * _behind_measures;

    global.timeline_state.planned_events = _planned_events;
    global.timeline_state.planned_spans = gv_build_planned_spans(_planned_events);
    global.timeline_state.emb_groups    = gv_build_emb_groups(global.timeline_state.planned_spans);

    global.timeline_state.tune_played = [];
    global.timeline_state.player_in = [];
    global.timeline_state.pending_tune = {};
    global.timeline_state.pending_player = {};

    global.timeline_state.planned_i0 = 0;
    global.timeline_state.planned_i1 = -1;
    global.timeline_state.planned_span_i0 = 0;
    global.timeline_state.planned_span_i1 = -1;
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
    global.timeline_state.review_measure_offset = 0;
    global.timeline_state.review_buttons = [];
}


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



function gv_get_planned_events_for_viz() {
    // Priority 1 (canonical at play time): preprocessed playback stream
    if (variable_global_exists("playback_events")
        && is_array(global.playback_events)
        && array_length(global.playback_events) > 0) {
        return global.playback_events;
    }

    // Fallbacks
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



function gv_bind_from_loaded_tune() {
    var _events = gv_get_planned_events_for_viz();
    var _timing = gv_resolve_loaded_tune_timing();
    gv_bind_timeline_on_tune_start(_events, _timing.bpm, _timing.meter);
}

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
    return noone;
}

function gv_find_timeline_anchor_id() {
    return gv_find_anchor_id_by_name("timeline_canvas_anchor");
}

function gv_get_anchor_rect_by_name(_ui_name) {
    var anchor_id = gv_find_anchor_id_by_name(_ui_name);
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
}

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
    return true;
}

// Scans planned_spans (in time order) and groups each consecutive run of
// is_embellishment=true spans plus the immediately following melody note into
// an embellishment window struct used for live player feedback.
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
        var ch = real(s.channel ?? 0);
        if (require_tune_channel && ch != tune_channel) { i++; continue; }
        var is_emb = variable_struct_exists(s, "is_embellishment") && s.is_embellishment;
        if (!is_emb) { i++; continue; }

        var window_start = real(s.start_ms ?? 0);
        var expected_notes = [];
        var note_set = {};

        while (i < n) {
            var si = _planned_spans[i];
            if (!is_struct(si)) break;
            if (require_tune_channel && real(si.channel ?? 0) != tune_channel) break;
            if (!(variable_struct_exists(si, "is_embellishment") && si.is_embellishment)) break;
            var canon = string(si.note_canonical ?? "");
            array_push(expected_notes, canon);
            note_set[$ canon] = true;
            i++;
        }

        // Target note (first non-emb span on same channel)
        if (i < n) {
            var tgt = _planned_spans[i];
            if (is_struct(tgt)) {
                var tch = real(tgt.channel ?? 0);
                var tgt_emb = variable_struct_exists(tgt, "is_embellishment") && tgt.is_embellishment;
                if ((!require_tune_channel || tch == tune_channel) && !tgt_emb) {
                    array_push(expected_notes, string(tgt.note_canonical ?? ""));
                    note_set[$ string(tgt.note_canonical ?? "")] = true;
                    array_push(groups, {
                        window_start_ms: window_start,
                        window_end_ms: real(tgt.end_ms ?? real(tgt.start_ms ?? window_start)),
                        expected_notes: expected_notes,
                        note_set: note_set
                    });
                    i++;
                    continue;
                }
            }
        }

        // No target found – seal group at last grace end
        if (array_length(expected_notes) > 0) {
            var ls = _planned_spans[i - 1];
            array_push(groups, {
                window_start_ms: window_start,
                window_end_ms: is_struct(ls) ? real(ls.end_ms ?? window_start) : window_start,
                expected_notes: expected_notes,
                note_set: note_set
            });
        }
    }
    return groups;
}

function gv_review_handle_click(_mx, _my) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;
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

function gv_note_label_from_midi(_midi) {
    var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    var idx = clamp(floor(_midi), 0, 127) mod 12;
    return names[idx];
}

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

// Returns timing match state for a player span vs planned spans on the same lane:
//   0 = wrong lane / no overlap at all
//   1 = correct note, overlaps, but starts too early or ends too late
//   2 = correct note and fully within planned bounds (+/- slack)
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

        var lane = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
        if (lane != _lane_idx) continue;

        var b1 = min(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        var b2 = max(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));

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

        var lane = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
        if (lane != _lane_idx) continue;

        var b1 = min(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
        var b2 = max(real(ps.start_ms ?? 0), real(ps.end_ms ?? 0));
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

function gv_draw_split_normal_player_beam(_planned_spans, _start_ms, _end_ms, _lane_idx,
    _playhead_ms, _x1, _x2, _now_ratio, _ms_behind, _ms_ahead,
    _y, _line_width, _match_color, _miss_color, _alpha) {

    var a1 = min(real(_start_ms), real(_end_ms));
    var a2 = max(real(_start_ms), real(_end_ms));
    if (a2 <= a1) return;

    var overlaps = gv_collect_lane_overlap_segments(_planned_spans, a1, a2, _lane_idx);
    var n_overlaps = array_length(overlaps);
    var cursor = a1;
    var miss_alpha = clamp(real(_alpha) * 0.72, 0, 1);

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

function gv_compact_note_label(_label) {
    var s = string(_label ?? "");
    if (string_length(s) <= 1) return s;
    if (string_copy(s, 1, 1) == "=") {
        return string_copy(s, 2, 1);
    }
    return string_copy(s, 1, 1);
}

function gv_get_current_planned_measure(_playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return -1;
    if (!variable_struct_exists(global.timeline_state, "planned_spans")) return -1;

    var spans = global.timeline_state.planned_spans;
    if (!is_array(spans)) return -1;

    var skip_metronome = variable_global_exists("METRONOME_CONFIG") && is_struct(global.METRONOME_CONFIG);
    var met_channel = skip_metronome ? real(global.METRONOME_CONFIG.channel) : -999;

    var best_measure = -1;
    var best_time = -1000000000000;
    var next_measure = -1;
    var next_time = 1000000000000;

    var n = array_length(spans);
    for (var i = 0; i < n; i++) {
        var s = spans[i];
        if (!is_struct(s)) continue;

        var ch = real(s.channel ?? 0);
        if (skip_metronome && ch == met_channel) continue;

        var m = real(s.measure ?? -1);
        if (m < 1) continue;

        var st = real(s.start_ms ?? 0);
        if (st <= _playhead_ms) {
            if (st >= best_time) {
                best_time = st;
                best_measure = m;
            }
        } else {
            if (st < next_time) {
                next_time = st;
                next_measure = m;
            }
        }
    }

    if (best_measure >= 1) return best_measure;
    return next_measure;
}

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
            seq += "…";
            break;
        }
    }

    if (in_emb_group) {
        seq += "}";
    }

    return seq;
}

function gv_draw_planned_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    if (!variable_struct_exists(global.timeline_state, "planned_spans")) return;

    var spans = global.timeline_state.planned_spans;
    if (!is_array(spans)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = global.timeline_cfg.now_ratio;
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

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var n = array_length(spans);
    for (var i = 0; i < n; i++) {
        var s = spans[i];
        if (!is_struct(s)) continue;

        if (skip_metronome && real(s.channel ?? -999) == met_channel) continue;
        if (s.end_ms < t_min) continue;
        if (s.start_ms > t_max) continue;

        var x1 = gv_time_to_x(s.start_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
        var x2 = gv_time_to_x(s.end_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);

        if (x2 < _rx1 || x1 > _rx2) continue;

        var lx = clamp(min(x1, x2), _rx1, _rx2);
        var rx = clamp(max(x1, x2), _rx1, _rx2);

        var is_emb = variable_struct_exists(s, "is_embellishment") && s.is_embellishment;
        draw_set_alpha(bar_alpha);
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

            draw_set_color(is_emb ? embell_text_color : melody_text_color);
            draw_text_transformed(text_x, text_y, draw_label, note_text_scale, note_text_scale, 0);
        }
    }
}

function gv_player_channel_matches(_channel) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return true;
    if (!variable_struct_exists(global.timeline_cfg, "player_channel")) return true;

    var target = real(global.timeline_cfg.player_channel);
    if (target < 0) return true;
    return (real(_channel) == target);
}

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
    global.timeline_state.pending_player[$ key] = {
        start_ms: real(_time_ms),
        note_midi: note,
        note_canonical: canonical,
        note_letter: chanter_canonical_to_display(canonical),
        channel: real(_channel),
        velocity: real(_velocity)
    };
}

// Pre-classifies every player span against embellishment groups for the draw frame.
// Returns:
// {
//   player_states: int[], pending_states: struct,
//   player_grace_overlay: bool[], pending_grace_overlay: struct
// }
// State: -1=not in emb window, 0=in window wrong/unmatched, 1=correct but bleeds, 2=correct in-window.
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
        : 15;

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

    array_push(global.timeline_state.player_in, {
        source: "player_midi_in",
        start_ms: start_ms,
        end_ms: end_ms,
        dur_ms: duration_ms,
        note_midi: note,
        note_canonical: final_canonical,
        note_letter: chanter_canonical_to_display(final_canonical),
        channel: real(_channel)
    });
}

function gv_draw_player_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = global.timeline_cfg.now_ratio;
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var player_offset_ms = variable_struct_exists(global.timeline_cfg, "player_time_offset_ms")
        ? real(global.timeline_cfg.player_time_offset_ms)
        : 0;
    var player_bar_color = variable_struct_exists(global.timeline_cfg, "player_bar_color")
        ? global.timeline_cfg.player_bar_color
        : make_color_rgb(78, 78, 84);
    var player_pending_bar_color = variable_struct_exists(global.timeline_cfg, "player_pending_bar_color")
        ? global.timeline_cfg.player_pending_bar_color
        : make_color_rgb(92, 92, 98);
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
                var label = variable_struct_exists(s, "note_letter")
                    ? string(s.note_letter)
                    : "";
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

    // Draw currently-held notes (note_on without note_off yet)
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
                var p_label = variable_struct_exists(p, "note_letter")
                    ? string(p.note_letter)
                    : "";
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
}

function gv_draw_beat_guides(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    if (!variable_struct_exists(global.timeline_state, "planned_events")) return;

    if (variable_struct_exists(global.timeline_cfg, "show_beat_guides") && !global.timeline_cfg.show_beat_guides) return;

    var events = global.timeline_state.planned_events;
    if (!is_array(events)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = global.timeline_cfg.now_ratio;
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var show_countin = !variable_struct_exists(global.timeline_cfg, "show_countin") || global.timeline_cfg.show_countin;

    var major_color = variable_struct_exists(global.timeline_cfg, "beat_guide_major_color")
        ? global.timeline_cfg.beat_guide_major_color
        : c_gray;
    var minor_color = variable_struct_exists(global.timeline_cfg, "beat_guide_minor_color")
        ? global.timeline_cfg.beat_guide_minor_color
        : c_dkgray;
    var major_alpha = variable_struct_exists(global.timeline_cfg, "beat_guide_major_alpha")
        ? clamp(real(global.timeline_cfg.beat_guide_major_alpha), 0, 1)
        : 0.28;
    var minor_alpha = variable_struct_exists(global.timeline_cfg, "beat_guide_minor_alpha")
        ? clamp(real(global.timeline_cfg.beat_guide_minor_alpha), 0, 1)
        : 0.16;
    var major_width = variable_struct_exists(global.timeline_cfg, "beat_guide_major_width")
        ? max(1, real(global.timeline_cfg.beat_guide_major_width))
        : 1;
    var minor_width = variable_struct_exists(global.timeline_cfg, "beat_guide_minor_width")
        ? max(1, real(global.timeline_cfg.beat_guide_minor_width))
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

function gv_draw_structure_row(_rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    if (!variable_struct_exists(global.timeline_state, "planned_events")) return;

    var events = global.timeline_state.planned_events;
    if (!is_array(events)) return;

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = global.timeline_cfg.now_ratio;
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;

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

    var last_label_x = -1000000;

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

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

        draw_set_color(is_major ? major_color : minor_color);
        var y_from = is_major ? _ry1 : (_ry1 + 4);
        draw_line_width(x_tick, y_from, x_tick, _ry2, is_major ? 2 : 1);

        if (!is_major) continue;

        var beat_num = floor(real(ev.beat ?? 0));
        if (beat_num < 1) continue;

        var measure_num = floor(real(ev.measure ?? 0));
        var label = "";
        if (beat_num == 1) {
            label = "M" + string(measure_num) + "B1";
        } else if (label_every_beat) {
            label = "B" + string(beat_num);
        }

        if (string_length(label) <= 0) continue;
        if ((x_tick - last_label_x) < label_spacing) continue;

        draw_set_color(text_color);
        draw_text(x_tick + 2, _ry1 + 1, label);
        last_label_x = x_tick;
    }
}

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

function gv_draw_timeline_canvas(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!global.timeline_cfg.enabled) return;
    var is_active = global.timeline_state.active;

    var pad = variable_struct_exists(global.timeline_cfg, "padding_px") ? real(global.timeline_cfg.padding_px) : 8;
    var gap = variable_struct_exists(global.timeline_cfg, "row_gap_px") ? real(global.timeline_cfg.row_gap_px) : 20;
    var now_ratio = variable_struct_exists(global.timeline_cfg, "now_ratio") ? real(global.timeline_cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);

    var x1 = _x1 + pad;
    var y1 = _y1 + pad;
    var x2 = _x2 - pad;
    var y2 = _y2 - pad;
    if (x2 <= x1 || y2 <= y1) return;

    var h = y2 - y1;
    var show_structure_row = !variable_struct_exists(global.timeline_cfg, "show_structure_row") || global.timeline_cfg.show_structure_row;
    var structure_h = variable_struct_exists(global.timeline_cfg, "structure_row_height_px")
        ? max(8, real(global.timeline_cfg.structure_row_height_px))
        : 18;

    var tune_top = y1;
    var tune_bottom = y2;
    var player_top = y1;
    var player_bottom = y2;
    var structure_top = y2;
    var structure_bottom = y2;

    if (show_structure_row) {
        var row_h = floor((h - (gap * 2) - structure_h) * 0.5);
        if (row_h < 8) {
            structure_h = max(8, floor(h * 0.2));
            row_h = floor((h - (gap * 2) - structure_h) * 0.5);
        }
        row_h = max(6, row_h);

        tune_bottom = min(y2, tune_top + row_h);
        player_top = min(y2, tune_bottom + gap);
        player_bottom = min(y2, player_top + row_h);
        structure_top = min(y2, player_bottom + gap);
        structure_bottom = y2;
    } else {
        var row_h2 = floor((h - gap) * 0.5);
        row_h2 = max(10, row_h2);

        tune_bottom = min(y2, tune_top + row_h2);
        player_top = min(y2, tune_bottom + gap);
        player_bottom = y2;
    }

    var canvas_bg_color = variable_struct_exists(global.timeline_cfg, "canvas_bg_color")
        ? global.timeline_cfg.canvas_bg_color
        : c_black;
    var canvas_bg_alpha = variable_struct_exists(global.timeline_cfg, "canvas_bg_alpha")
        ? clamp(real(global.timeline_cfg.canvas_bg_alpha), 0, 1)
        : 0.90;
    var row_bg_tune_color = variable_struct_exists(global.timeline_cfg, "row_bg_tune_color")
        ? global.timeline_cfg.row_bg_tune_color
        : c_dkgray;
    var row_bg_player_color = variable_struct_exists(global.timeline_cfg, "row_bg_player_color")
        ? global.timeline_cfg.row_bg_player_color
        : c_dkgray;
    var row_bg_structure_color = variable_struct_exists(global.timeline_cfg, "row_bg_structure_color")
        ? global.timeline_cfg.row_bg_structure_color
        : c_dkgray;
    var row_bg_alpha = variable_struct_exists(global.timeline_cfg, "row_bg_alpha")
        ? clamp(real(global.timeline_cfg.row_bg_alpha), 0, 1)
        : 1;

    draw_set_alpha(canvas_bg_alpha);
    draw_set_color(canvas_bg_color);
    draw_rectangle(x1, y1, x2, y2, false);

    draw_set_alpha(row_bg_alpha);
    draw_set_color(row_bg_tune_color);
    draw_rectangle(x1, tune_top, x2, tune_bottom, false);
    draw_set_color(row_bg_player_color);
    draw_rectangle(x1, player_top, x2, player_bottom, false);
    if (show_structure_row) {
        draw_set_color(row_bg_structure_color);
        draw_rectangle(x1, structure_top, x2, structure_bottom, false);
    }
    draw_set_alpha(1);

    if (is_active) {
        gv_draw_beat_guides(x1, y1, x2, y2, global.timeline_state.playhead_ms);
    }

    var now_x = x1 + ((x2 - x1) * now_ratio);
    draw_set_color(c_yellow);
    draw_line_width(now_x, y1, now_x, y2, 2);

    if (is_active) {
        gv_draw_planned_row(x1, tune_top, x2, tune_bottom, global.timeline_state.playhead_ms);
        gv_draw_player_row(x1, player_top, x2, player_bottom, global.timeline_state.playhead_ms);
        if (show_structure_row) {
            gv_draw_structure_row(x1, structure_top, x2, structure_bottom, global.timeline_state.playhead_ms);
        }
    }

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var show_seq_debug = variable_struct_exists(global.timeline_cfg, "debug_planned_sequence")
        && global.timeline_cfg.debug_planned_sequence;
    if (is_active && show_seq_debug) {
        var dbg_measure = gv_get_current_planned_measure(global.timeline_state.playhead_ms);
        var dbg_max_notes = variable_struct_exists(global.timeline_cfg, "debug_sequence_max_notes")
            ? max(1, real(global.timeline_cfg.debug_sequence_max_notes))
            : 24;
        var dbg_seq = gv_get_planned_sequence_for_measure(dbg_measure, dbg_max_notes);

        draw_set_color(c_ltgray);
        if (dbg_measure >= 1) {
            draw_text(x1 + 110, tune_top + 2, "M" + string(dbg_measure) + ": " + dbg_seq);
        } else {
            draw_text(x1 + 110, tune_top + 2, "M?: (no planned measure)");
        }
    }

    if (is_active) {
        gv_draw_review_controls(x1, y1, x2, y2);
    }

    var draw_notebeam_from_timeline = !variable_struct_exists(global.timeline_cfg, "notebeam_draw_from_timeline")
        || global.timeline_cfg.notebeam_draw_from_timeline;
    if (draw_notebeam_from_timeline) {
        var nb_rect = gv_get_anchor_rect_by_name("notebeam_canvas_anchor");
        var used_fallback_rect = false;
        if (!is_struct(nb_rect) || real(nb_rect.w ?? 0) < 8 || real(nb_rect.h ?? 0) < 8) {
            nb_rect = {
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2,
                w: max(1, x2 - x1),
                h: max(1, y2 - y1)
            };
            used_fallback_rect = true;
        }
        if (is_struct(nb_rect)) {
            gv_draw_notebeam_canvas(nb_rect.x1, nb_rect.y1, nb_rect.x2, nb_rect.y2);

            var route_debug = !variable_struct_exists(global.timeline_cfg, "notebeam_debug_log")
                || global.timeline_cfg.notebeam_debug_log;
            if (route_debug) {
                if (!variable_global_exists("NOTEBEAM_ROUTE_LOG_MS")) {
                    global.NOTEBEAM_ROUTE_LOG_MS = 0;
                }
                if ((current_time - real(global.NOTEBEAM_ROUTE_LOG_MS)) >= 1000) {
                    show_debug_message("[NOTEBEAM_ROUTE] rect=" + string(floor(nb_rect.w)) + "x" + string(floor(nb_rect.h))
                        + " fallback=" + string(used_fallback_rect)
                        + " active=" + string(is_active));
                    global.NOTEBEAM_ROUTE_LOG_MS = current_time;
                }
            }
        }
    }

    if (!is_active) {
        draw_set_color(c_ltgray);
        draw_text(x2 - 110, y1 + 2, "timeline idle");
    }
}

function gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return;

    var enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_enabled") || global.timeline_cfg.notebeam_enabled;
    if (!enabled) return;

    var x1 = _x1;
    var y1 = _y1;
    var x2 = _x2;
    var y2 = _y2;
    if (x2 <= x1 || y2 <= y1) return;

    var is_active = variable_global_exists("timeline_state") && is_struct(global.timeline_state) && global.timeline_state.active;

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
    var using_lane_anchors = use_lane_anchors && (lane_anchor_found > 0);

    var notebeam_line_width = variable_struct_exists(global.timeline_cfg, "notebeam_line_width")
        ? max(1, real(global.timeline_cfg.notebeam_line_width))
        : 1;
    var beam_width_px = notebeam_line_width;
    if (!using_lane_anchors && use_label_lane_layout && match_label_width) {
        beam_width_px = lane_row_height_px * match_label_width_scale;
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

    if (is_active) {
        var playhead_ms = real(global.timeline_state.playhead_ms ?? 0);
        var ms_behind = max(1, real(global.timeline_state.ms_behind ?? 1));
        var ms_ahead = max(1, real(global.timeline_state.ms_ahead ?? 1));
        var t_min = playhead_ms - ms_behind;
        var t_max = playhead_ms + ms_ahead;

        var player_offset_ms = variable_struct_exists(global.timeline_cfg, "player_time_offset_ms")
            ? real(global.timeline_cfg.player_time_offset_ms)
            : 0;

        var planned_spans = [];
        if (variable_struct_exists(global.timeline_state, "planned_spans") && is_array(global.timeline_state.planned_spans)) {
            planned_spans = global.timeline_state.planned_spans;
        }
        var can_compare_overlap = use_segmented_compare
            && player_overlap_colorize
            && is_array(planned_spans)
            && array_length(planned_spans) > 0;
        overlap_match_count = 0;
        overlap_miss_count = 0;
        overlap_bleed_count = 0;

        var use_emb_classify = false;
        var player_emb_classify = undefined;
        if (use_embellishment_mode
            && can_compare_overlap
            && variable_struct_exists(global.timeline_state, "emb_groups")
            && is_array(global.timeline_state.emb_groups)
            && array_length(global.timeline_state.emb_groups) > 0) {
            use_emb_classify = true;
            player_emb_classify = gv_classify_player_spans_for_emb(
                global.timeline_state.emb_groups,
                variable_struct_exists(global.timeline_state, "player_in") ? global.timeline_state.player_in : [],
                variable_struct_exists(global.timeline_state, "pending_player") ? global.timeline_state.pending_player : {},
                playhead_ms,
                player_offset_ms
            );
        }

        if (is_array(planned_spans) && array_length(planned_spans) > 0) {
            draw_set_alpha(planned_beam_alpha);
            draw_set_color(planned_beam_color);

            var n_planned = array_length(planned_spans);
            for (var i = 0; i < n_planned; i++) {
                var ps = planned_spans[i];
                if (!is_struct(ps)) continue;
                var p_start = real(ps.start_ms ?? 0);
                var p_end = real(ps.end_ms ?? p_start);
                if (p_end < t_min || p_start > t_max) continue;

                var lane_idx = gv_note_to_lane_index(ps.note_canonical ?? "", ps.note_midi ?? -1, ps.channel ?? -1);
                if (lane_idx < 0 || lane_idx >= lane_count) continue;

                var px1 = gv_time_to_x(p_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var px2 = gv_time_to_x(p_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var plx = clamp(min(px1, px2), x1, x2);
                var prx = clamp(max(px1, px2), x1, x2);
                if (prx <= plx) continue;

                var py = -1;
                var lane_beam_width = beam_width_px;
                if (using_lane_anchors && lane_anchor_y[lane_idx] >= 0) {
                    py = lane_anchor_y[lane_idx];
                    if (match_label_width && lane_anchor_h[lane_idx] > 0) {
                        lane_beam_width = lane_anchor_h[lane_idx] * match_label_width_scale;
                    }
                } else {
                    var lane_visual_idx = lane_flip ? (lane_count - 1 - lane_idx) : lane_idx;
                    py = y1 + ((lane_visual_idx + 0.5) * lane_h);
                    if (use_label_lane_layout) {
                        var spacer_px = ((y2 - y1) * lane_top_spacer_ratio) + lane_top_spacer_px;
                        py = y1 + spacer_px + lane_row_gap_px
                            + (lane_visual_idx * (lane_row_height_px + lane_row_gap_px))
                            + (lane_row_height_px * 0.5);
                    }
                }
                py += lane_y_offset_px;
                py = clamp(py, y1 + 1, y2 - 1);
                draw_line_width(plx, py, prx, py, lane_beam_width);
            }
            draw_set_alpha(1);
        }

        if (variable_struct_exists(global.timeline_state, "player_in") && is_array(global.timeline_state.player_in)) {
            var player_spans = global.timeline_state.player_in;
            draw_set_alpha(player_beam_alpha);

            var n_player = array_length(player_spans);
            for (var j = 0; j < n_player; j++) {
                var ps2 = player_spans[j];
                if (!is_struct(ps2)) continue;
                var q_start = real(ps2.start_ms ?? 0) + player_offset_ms;
                var q_end = real(ps2.end_ms ?? q_start) + player_offset_ms;
                if (q_end < t_min || q_start > t_max) continue;

                var lane_idx2 = gv_note_to_lane_index(ps2.note_canonical ?? "", ps2.note_midi ?? -1, ps2.channel ?? -1);
                if (lane_idx2 < 0 || lane_idx2 >= lane_count) continue;

                var qx1 = gv_time_to_x(q_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var qx2 = gv_time_to_x(q_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                var qlx = clamp(min(qx1, qx2), x1, x2);
                var qrx = clamp(max(qx1, qx2), x1, x2);
                if (qrx <= qlx) continue;

                var qy = -1;
                var lane_beam_width2 = beam_width_px;
                if (using_lane_anchors && lane_anchor_y[lane_idx2] >= 0) {
                    qy = lane_anchor_y[lane_idx2];
                    if (match_label_width && lane_anchor_h[lane_idx2] > 0) {
                        lane_beam_width2 = lane_anchor_h[lane_idx2] * match_label_width_scale;
                    }
                } else {
                    var lane_visual_idx2 = lane_flip ? (lane_count - 1 - lane_idx2) : lane_idx2;
                    qy = y1 + ((lane_visual_idx2 + 0.5) * lane_h);
                    if (use_label_lane_layout) {
                        var spacer_px2 = ((y2 - y1) * lane_top_spacer_ratio) + lane_top_spacer_px;
                        qy = y1 + spacer_px2 + lane_row_gap_px
                            + (lane_visual_idx2 * (lane_row_height_px + lane_row_gap_px))
                            + (lane_row_height_px * 0.5);
                    }
                }
                qy += lane_y_offset_px;
                qy = clamp(qy, y1 + 1, y2 - 1);

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
                    draw_line_width(qlx, qy, qrx, qy, lane_beam_width2);
                } else {
                    var player_tstate = can_compare_overlap
                        ? gv_player_span_timing_state(planned_spans, q_start, q_end, lane_idx2, player_timing_slack_ms)
                        : -1;
                    if (can_compare_overlap) {
                        if (player_tstate == 2) overlap_match_count += 1;
                        else if (player_tstate == 1) overlap_bleed_count += 1;
                        else overlap_miss_count += 1;
                    }
                    if (can_compare_overlap) {
                        gv_draw_split_normal_player_beam(
                            planned_spans, q_start, q_end, lane_idx2,
                            playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead,
                            qy, lane_beam_width2, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                        );
                    } else {
                        draw_set_alpha(player_beam_alpha);
                        draw_set_color(player_beam_color);
                        draw_line_width(qlx, qy, qrx, qy, lane_beam_width2);
                    }
                }
                draw_set_alpha(player_beam_alpha);
            }
            draw_set_alpha(1);
        }

        if (variable_struct_exists(global.timeline_state, "pending_player") && is_struct(global.timeline_state.pending_player)) {
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

                    var lane_idx3 = gv_note_to_lane_index(pp.note_canonical ?? "", pp.note_midi ?? -1, pp.channel ?? -1);
                    if (lane_idx3 < 0 || lane_idx3 >= lane_count) continue;

                    var rx1 = gv_time_to_x(r_start, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                    var rx2 = gv_time_to_x(r_end, playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead);
                    var rlx = clamp(min(rx1, rx2), x1, x2);
                    var rrx = clamp(max(rx1, rx2), x1, x2);
                    if (rrx <= rlx) continue;

                    var ry = -1;
                    var lane_beam_width3 = beam_width_px;
                    if (using_lane_anchors && lane_anchor_y[lane_idx3] >= 0) {
                        ry = lane_anchor_y[lane_idx3];
                        if (match_label_width && lane_anchor_h[lane_idx3] > 0) {
                            lane_beam_width3 = lane_anchor_h[lane_idx3] * match_label_width_scale;
                        }
                    } else {
                        var lane_visual_idx3 = lane_flip ? (lane_count - 1 - lane_idx3) : lane_idx3;
                        ry = y1 + ((lane_visual_idx3 + 0.5) * lane_h);
                        if (use_label_lane_layout) {
                            var spacer_px3 = ((y2 - y1) * lane_top_spacer_ratio) + lane_top_spacer_px;
                            ry = y1 + spacer_px3 + lane_row_gap_px
                                + (lane_visual_idx3 * (lane_row_height_px + lane_row_gap_px))
                                + (lane_row_height_px * 0.5);
                        }
                    }
                    ry += lane_y_offset_px;
                    ry = clamp(ry, y1 + 1, y2 - 1);

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
                        draw_line_width(rlx, ry, rrx, ry, lane_beam_width3);
                    } else {
                        var pending_tstate = can_compare_overlap
                            ? gv_player_span_timing_state(planned_spans, r_start, r_end, lane_idx3, player_timing_slack_ms)
                            : -1;
                        if (can_compare_overlap) {
                            if (pending_tstate == 2) overlap_match_count += 1;
                            else if (pending_tstate == 1) overlap_bleed_count += 1;
                            else overlap_miss_count += 1;
                        }
                        if (can_compare_overlap) {
                            gv_draw_split_normal_player_beam(
                                planned_spans, r_start, r_end, lane_idx3,
                                playhead_ms, x1, x2, now_ratio, ms_behind, ms_ahead,
                                ry, lane_beam_width3, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                            );
                        } else {
                            draw_set_alpha(player_beam_alpha);
                            draw_set_color(player_beam_color);
                            draw_line_width(rlx, ry, rrx, ry, lane_beam_width3);
                        }
                    }
                    draw_set_alpha(player_beam_alpha);
                }

                draw_set_alpha(1);
            }
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
    if (overlap_match_count >= 0) {
        dbg_line += " Y=" + string(overlap_match_count);
        dbg_line += " B=" + string(overlap_bleed_count);
        dbg_line += " N=" + string(overlap_miss_count);
    }
    dbg_line += " A=" + (use_lane_anchors ? (string(lane_anchor_found) + "/" + string(lane_count)) : "off");

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
            show_debug_message("[NOTEBEAM] " + dbg_line + " now_x=" + string(floor(now_x)));
            global.NOTEBEAM_DEBUG_LOG_MS = current_time;
        }
    }

    var show_now_line = !variable_struct_exists(global.timeline_cfg, "notebeam_show_now_line")
        || global.timeline_cfg.notebeam_show_now_line;
    if (show_now_line) {
        var now_line_color = variable_struct_exists(global.timeline_cfg, "notebeam_now_line_color")
            ? global.timeline_cfg.notebeam_now_line_color
            : c_yellow;
        var now_line_width = variable_struct_exists(global.timeline_cfg, "notebeam_now_line_width")
            ? max(1, real(global.timeline_cfg.notebeam_now_line_width))
            : 2;

        draw_set_color(now_line_color);
        draw_line_width(now_x, y1, now_x, y2, now_line_width);
    }
}

