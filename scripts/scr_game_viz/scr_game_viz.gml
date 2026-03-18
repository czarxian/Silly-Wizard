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

function gv_ensure_timeline_cfg_defaults() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) {
        global.timeline_cfg = {};
    }

    if (!variable_struct_exists(global.timeline_cfg, "enabled")) {
        variable_struct_set(global.timeline_cfg, "enabled", true);
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
    if (!variable_struct_exists(global.timeline_cfg, "now_ratio")) {
        variable_struct_set(global.timeline_cfg, "now_ratio", 0.33);
    }
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

    return global.timeline_cfg;
}

function gv_is_bagpipe_tune_channel(_channel) {
    var ch = floor(real(_channel));
    return (ch >= 2 && ch <= 5);
}

function gv_get_target_tune_channel() {
    var cfg = gv_ensure_timeline_cfg_defaults();

    var target = variable_struct_exists(cfg, "tune_channel")
        ? floor(real(cfg.tune_channel))
        : 2;

    if (!gv_is_bagpipe_tune_channel(target)) return 2;
    return target;
}

function gv_use_tune_ghost_parts() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(cfg, "tune_show_other_parts_ghost")) return false;
    return cfg.tune_show_other_parts_ghost;
}

function gv_get_tune_other_parts_alpha() {
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_struct_exists(cfg, "tune_other_parts_alpha")) return 0.18;
    return clamp(real(cfg.tune_other_parts_alpha), 0.02, 1);
}

function gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2) {
    var pad = 8;
    var left = _x1 + pad;
    var right = _x2 - pad;
    if (right <= left) right = left + 1;

    var panel_h = max(1, _y2 - _y1);
    var btn_h = clamp(round(panel_h * 0.30), 18, 56);

    var btn_y1 = _y1 + floor((panel_h - btn_h) * 0.5);
    var btn_y2 = min(_y2 - pad, btn_y1 + btn_h);
    if (btn_y2 <= btn_y1) btn_y2 = btn_y1 + 1;

    return {
        btn_toggle: [left, btn_y1, right, btn_y2]
    };
}

function gv_gameviz_controls_can_interact() {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return true;

    var active = variable_struct_exists(global.timeline_state, "active") && global.timeline_state.active;
    if (!active) return true;

    var review_mode = variable_struct_exists(global.timeline_state, "review_mode") && global.timeline_state.review_mode;
    return review_mode;
}

function gv_gameviz_point_in_rect(_mx, _my, _r) {
    if (!is_array(_r) || array_length(_r) < 4) return false;
    return (_mx >= _r[0] && _mx <= _r[2] && _my >= _r[1] && _my <= _r[3]);
}

function gv_is_gameviz_anchor(_inst) {
    if (!instance_exists(_inst)) return false;
    if (!variable_instance_exists(_inst, "ui_name")) return false;
    return string(variable_instance_get(_inst, "ui_name")) == "gameviz_canvas_anchor";
}

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

function gv_draw_gameviz_controls_panel(_x1, _y1, _x2, _y2) {
    var layout = gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2);
    var ghost_mode = gv_use_tune_ghost_parts();
    var can_interact = gv_gameviz_controls_can_interact();
    var label = ghost_mode ? "All Parts" : "Player Part";

    draw_set_font(fnt_setting);
    gv_gameviz_draw_toggle_button(layout.btn_toggle, label, ghost_mode, can_interact);
}

function gv_handle_gameviz_controls_click(_mx, _my, _x1, _y1, _x2, _y2) {
    var layout = gv_gameviz_controls_get_layout(_x1, _y1, _x2, _y2);
    if (!gv_gameviz_controls_can_interact()) return false;

    if (gv_gameviz_point_in_rect(_mx, _my, layout.btn_toggle)) {
        var cfg = gv_ensure_timeline_cfg_defaults();

        var ghost_mode = gv_use_tune_ghost_parts();
        variable_struct_set(cfg, "tune_show_other_parts_ghost", !ghost_mode);
        return true;
    }

    return false;
}

function scr_gameviz_set_ghost_mode(_enable_ghost) {
    var cfg = gv_ensure_timeline_cfg_defaults();
    variable_struct_set(cfg, "tune_show_other_parts_ghost", bool(_enable_ghost));
}

function scr_gameviz_get_ghost_mode() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return false;
    if (!variable_struct_exists(global.timeline_cfg, "tune_show_other_parts_ghost")) return false;
    return bool(global.timeline_cfg.tune_show_other_parts_ghost);
}

function scr_gameviz_init_config() {
    gv_ensure_timeline_cfg_defaults();
}

// Shared timeline tick so playhead/review input still work when timeline is drawn
// from RoomUI anchors without an obj_game_viz instance in the room.
function gv_timeline_step_tick() {
    if (!variable_global_exists("timeline_cfg") || !is_struct(global.timeline_cfg)) return false;
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;

    // Avoid duplicate processing when multiple instances call this in one frame.
    if (variable_global_exists("TIMELINE_STEP_LAST_MS")) {
        if (real(global.TIMELINE_STEP_LAST_MS) == current_time) {
            return false;
        }
    }
    global.TIMELINE_STEP_LAST_MS = current_time;

    var cfg = gv_ensure_timeline_cfg_defaults();

    if (!variable_struct_exists(cfg, "enabled") || !cfg.enabled) return false;
    if (!variable_struct_exists(global.timeline_state, "active") || !global.timeline_state.active) return false;

    if (mouse_check_button_pressed(mb_left)) {
        gv_review_handle_click(mouse_x, mouse_y);
    }

    var review_mode = variable_struct_exists(global.timeline_state, "review_mode") && global.timeline_state.review_mode;
    if (review_mode) return true;

    var playhead_lag_ms = 0;
    if (variable_struct_exists(cfg, "playhead_audio_lag_ms")) {
        playhead_lag_ms = max(0, real(cfg.playhead_audio_lag_ms));
    }

    if (variable_global_exists("tune_start_real")) {
        global.timeline_state.playhead_ms = max(0, current_time - real(global.tune_start_real) - playhead_lag_ms);
    } else {
        if (!variable_struct_exists(global.timeline_state, "start_clock_ms")) {
            global.timeline_state.start_clock_ms = current_time;
        }
        global.timeline_state.playhead_ms = max(0, current_time - real(global.timeline_state.start_clock_ms) - playhead_lag_ms);
    }

    return true;
}

// Returns visibility mode for tune-planned spans:
// 0 = hidden, 1 = ghost, 2 = focus/target part
function gv_get_tune_span_visibility_state(_channel) {
    var ch = floor(real(_channel));
    if (!gv_is_bagpipe_tune_channel(ch)) return 0;

    var target_ch = gv_get_target_tune_channel();
    if (ch == target_ch) return 2;

    if (gv_use_tune_ghost_parts()) return 1;
    return 0;
}

function gv_is_tune_focus_channel(_channel) {
    return (gv_get_tune_span_visibility_state(_channel) == 2);
}

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

    var _measure_nav = gv_build_measure_nav_map(_planned_events);
    global.timeline_state.measure_nav_entries = _measure_nav.entries;
    global.timeline_state.measure_nav_parts = _measure_nav.parts;
    global.timeline_state.measure_nav_pickup_by_part = _measure_nav.pickup_by_part;
    global.timeline_state.measure_nav_scroll_row = 0;
    global.timeline_state.measure_nav_total_rows = 0;
    global.timeline_state.measure_nav_view_rows = 0;
    global.timeline_state.measure_nav_tile_hitboxes = [];
    global.timeline_state.measure_nav_controls = {};

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
    global.timeline_state.review_history_runs = [];
    global.timeline_state.review_history_loaded = false;
    global.timeline_state.review_history_count = 0;
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

    // Fallback for notebeam label anchors when RoomUI instances were not given ui_name overrides.
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
    gv_refresh_review_history_cache();
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
                expected_notes: expected_notes,
                note_set: note_set,
                lane_indices: lane_indices,
                has_target: true
            });

            i = target_index + 1;
            continue;
        }

        // No target found – seal group at last grace end.
        var ls = (last_emb_index >= 0) ? _planned_spans[last_emb_index] : s;
        array_push(groups, {
            window_start_ms: window_start,
            window_end_ms: is_struct(ls) ? real(ls.end_ms ?? window_start) : window_start,
            expected_notes: expected_notes,
            note_set: note_set,
            lane_indices: lane_indices,
            has_target: false
        });

        i = max(i + 1, j + 1);
    }
    return groups;
}

function gv_build_measure_nav_map(_planned_events) {
    var result = {
        entries: [],
        parts: [],
        pickup_by_part: {}
    };
    if (!is_array(_planned_events)) return result;

    var measure_part = {};
    var measure_start_marker = {};
    var measure_start_any = {};
    var part_seen = {};

    var n = array_length(_planned_events);
    for (var i = 0; i < n; i++) {
        var ev = _planned_events[i];
        if (!is_struct(ev)) continue;

        var m = variable_struct_exists(ev, "measure")
            ? floor(real(ev.measure))
            : -9999;
        if (m < 1) continue;

        var p = variable_struct_exists(ev, "part")
            ? floor(real(ev.part))
            : 1;
        if (p < 1) p = 1;
        var t = gv_evt_time_ms(ev);

        var mkey = string(m);
        if (!variable_struct_exists(measure_part, mkey)) {
            measure_part[$ mkey] = p;
        }
        if (!variable_struct_exists(measure_start_any, mkey) || t < real(measure_start_any[$ mkey])) {
            measure_start_any[$ mkey] = t;
        }

        if (variable_struct_exists(ev, "type") && string(ev.type) == "marker") {
            var marker_type = variable_struct_exists(ev, "marker_type")
                ? string(ev.marker_type)
                : "";
            if (marker_type == "beat") {
                var beat = variable_struct_exists(ev, "beat")
                    ? floor(real(ev.beat))
                    : 0;
                var beat_fraction = 0;
                if (variable_struct_exists(ev, "beat_fraction")) beat_fraction = real(ev.beat_fraction);
                else if (variable_struct_exists(ev, "beat_frac")) beat_fraction = real(ev.beat_frac);

                if (beat == 1 && abs(beat_fraction) <= 0.001) {
                    if (!variable_struct_exists(measure_start_marker, mkey) || t < real(measure_start_marker[$ mkey])) {
                        measure_start_marker[$ mkey] = t;
                    }
                }
            }
        }

        var pkey = string(p);
        if (!variable_struct_exists(part_seen, pkey)) {
            part_seen[$ pkey] = true;
            array_push(result.parts, p);
        }
    }

    var parts_n = array_length(result.parts);
    var part_i = 1;
    for (; part_i < parts_n; part_i += 1) {
        var p_key = result.parts[part_i];
        var part_j = part_i - 1;
        while (part_j >= 0 && real(result.parts[part_j]) > real(p_key)) {
            result.parts[part_j + 1] = result.parts[part_j];
            part_j--;
        }
        result.parts[part_j + 1] = p_key;
    }

    var measure_keys = variable_struct_get_names(measure_part);
    if (!is_array(measure_keys) || array_length(measure_keys) <= 0) {
        var fallback_measure_ms = (variable_global_exists("timeline_state")
            && is_struct(global.timeline_state)
            && variable_struct_exists(global.timeline_state, "measure_ms"))
            ? max(1, real(global.timeline_state.measure_ms))
            : 1000;

        var fallback_end_ms = 0;
        for (var fei = 0; fei < n; fei++) {
            var f_ev = _planned_events[fei];
            if (!is_struct(f_ev)) continue;
            fallback_end_ms = max(fallback_end_ms, gv_evt_time_ms(f_ev));
        }
        fallback_end_ms = max(fallback_end_ms, gv_get_planned_end_ms());

        var fallback_count = max(1, ceil(max(1, fallback_end_ms) / fallback_measure_ms));
        result.parts = [1];
        result.pickup_by_part[$ "1"] = false;

        for (var fm = 1; fm <= fallback_count; fm++) {
            var fm_start = (fm - 1) * fallback_measure_ms;
            var fm_end = fm * fallback_measure_ms;
            array_push(result.entries, {
                measure: fm,
                part: 1,
                start_ms: fm_start,
                end_ms: fm_end,
                status: 0
            });
        }

        return result;
    }

    var measures = [];
    for (var mk = 0; mk < array_length(measure_keys); mk++) {
        array_push(measures, floor(real(measure_keys[mk])));
    }

    var n_measures = array_length(measures);
    for (var mi = 1; mi < n_measures; mi++) {
        var m_key = measures[mi];
        var mj = mi - 1;
        while (mj >= 0 && real(measures[mj]) > real(m_key)) {
            measures[mj + 1] = measures[mj];
            mj--;
        }
        measures[mj + 1] = m_key;
    }

    for (var me = 0; me < n_measures; me++) {
        var measure_num = measures[me];
        var measure_key = string(measure_num);
        var start_ms = variable_struct_exists(measure_start_marker, measure_key)
            ? real(measure_start_marker[$ measure_key])
            : real(measure_start_any[$ measure_key] ?? 0);
        var part_num = floor(real(measure_part[$ measure_key] ?? 1));
        if (part_num < 1) part_num = 1;

        array_push(result.entries, {
            measure: measure_num,
            part: part_num,
            start_ms: start_ms,
            end_ms: start_ms,
            status: 0
        });
    }

    var n_entries = array_length(result.entries);
    for (var ei = 0; ei < n_entries - 1; ei++) {
        var e = result.entries[ei];
        var e_next = result.entries[ei + 1];
        e.end_ms = max(real(e.start_ms), real(e_next.start_ms));
        result.entries[ei] = e;
    }
    if (n_entries > 0) {
        var e_last = result.entries[n_entries - 1];
        var fallback_end_ms = gv_get_planned_end_ms();
        if (fallback_end_ms <= real(e_last.start_ms)) {
            var fallback_measure_ms = (variable_global_exists("timeline_state")
                && is_struct(global.timeline_state)
                && variable_struct_exists(global.timeline_state, "measure_ms"))
                ? max(1, real(global.timeline_state.measure_ms))
                : 1000;
            fallback_end_ms = real(e_last.start_ms) + fallback_measure_ms;
        }
        e_last.end_ms = fallback_end_ms;
        result.entries[n_entries - 1] = e_last;
    }

    var first_start_by_part = {};
    for (var fs = 0; fs < n_entries; fs++) {
        var fe = result.entries[fs];
        var fkey = string(floor(real(fe.part ?? 1)));
        if (!variable_struct_exists(first_start_by_part, fkey)
            || real(fe.start_ms) < real(first_start_by_part[$ fkey])) {
            first_start_by_part[$ fkey] = real(fe.start_ms);
        }
        if (!variable_struct_exists(result.pickup_by_part, fkey)) {
            result.pickup_by_part[$ fkey] = false;
        }
    }

    for (var pe = 0; pe < n; pe++) {
        var p_ev = _planned_events[pe];
        if (!is_struct(p_ev)) continue;

        var part_num_ev = variable_struct_exists(p_ev, "part")
            ? floor(real(p_ev.part))
            : 1;
        if (part_num_ev < 1) part_num_ev = 1;
        var part_key_ev = string(part_num_ev);
        if (!variable_struct_exists(first_start_by_part, part_key_ev)) continue;

        var measure_ev = variable_struct_exists(p_ev, "measure")
            ? floor(real(p_ev.measure))
            : 1;
        if (measure_ev > 0) continue;

        var time_ev = gv_evt_time_ms(p_ev);
        if (time_ev <= real(first_start_by_part[$ part_key_ev]) + 0.001) {
            result.pickup_by_part[$ part_key_ev] = true;
        }
    }

    return result;
}

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

function gv_review_jump_to_measure(_measure) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;
    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries") || !is_array(global.timeline_state.measure_nav_entries)) return false;

    var target_measure = floor(real(_measure));
    if (target_measure < 1) return false;

    var entries = global.timeline_state.measure_nav_entries;
    var target_ms = undefined;
    var n = array_length(entries);
    for (var i = 0; i < n; i++) {
        var e = entries[i];
        if (!is_struct(e)) continue;
        if (floor(real(e.measure ?? -1)) != target_measure) continue;
        target_ms = real(e.start_ms ?? 0);
        break;
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

function gv_measure_nav_handle_click(_mx, _my) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    if (variable_struct_exists(global.timeline_state, "measure_nav_controls") && is_struct(global.timeline_state.measure_nav_controls)) {
        var ctrls = global.timeline_state.measure_nav_controls;
        var show_ctrls = variable_struct_exists(ctrls, "show") && ctrls.show;

        if (show_ctrls && variable_struct_exists(ctrls, "up") && is_struct(ctrls.up)) {
            var up = ctrls.up;
            if (_mx >= real(up.x1 ?? -1) && _mx <= real(up.x2 ?? -1)
                && _my >= real(up.y1 ?? -1) && _my <= real(up.y2 ?? -1)
                && variable_struct_exists(up, "enabled") && up.enabled) {
                return gv_measure_nav_scroll_rows(-1);
            }
        }
        if (show_ctrls && variable_struct_exists(ctrls, "down") && is_struct(ctrls.down)) {
            var down = ctrls.down;
            if (_mx >= real(down.x1 ?? -1) && _mx <= real(down.x2 ?? -1)
                && _my >= real(down.y1 ?? -1) && _my <= real(down.y2 ?? -1)
                && variable_struct_exists(down, "enabled") && down.enabled) {
                return gv_measure_nav_scroll_rows(1);
            }
        }
    }

    if (!variable_struct_exists(global.timeline_state, "measure_nav_tile_hitboxes")
        || !is_array(global.timeline_state.measure_nav_tile_hitboxes)) {
        return false;
    }

    var hits = global.timeline_state.measure_nav_tile_hitboxes;
    var n_hits = array_length(hits);
    for (var i = 0; i < n_hits; i++) {
        var h = hits[i];
        if (!is_struct(h)) continue;
        if (_mx < real(h.x1 ?? -1) || _mx > real(h.x2 ?? -1)) continue;
        if (_my < real(h.y1 ?? -1) || _my > real(h.y2 ?? -1)) continue;
        return gv_review_jump_to_measure(floor(real(h.measure ?? -1)));
    }

    return false;
}

function gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;

    // Lazy bootstrap in case timeline state was initialized before bind or reset during room transitions.
    // This keeps the panel resilient even if bind timing differs across play flows.
    var _has_entries = variable_struct_exists(global.timeline_state, "measure_nav_entries")
        && is_array(global.timeline_state.measure_nav_entries)
        && array_length(global.timeline_state.measure_nav_entries) > 0;
    if (!_has_entries) {
        // Use the same source resolution as timeline bind, then fall back to active scheduler groups.
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

        if (array_length(_source_events) > 0) {
            var _measure_nav = gv_build_measure_nav_map(_source_events);
            global.timeline_state.measure_nav_entries = _measure_nav.entries;
            global.timeline_state.measure_nav_parts = _measure_nav.parts;
            global.timeline_state.measure_nav_pickup_by_part = _measure_nav.pickup_by_part;
        } else {
            // Last-resort synthetic map so the panel remains usable even if source event arrays are unavailable.
            var _fallback_measure_ms = variable_struct_exists(global.timeline_state, "measure_ms")
                ? max(1, real(global.timeline_state.measure_ms))
                : 1000;
            var _fallback_end_ms = 0;
            if (variable_struct_exists(global.timeline_state, "review_end_ms")) {
                _fallback_end_ms = max(_fallback_end_ms, real(global.timeline_state.review_end_ms));
            }
            if (variable_struct_exists(global.timeline_state, "playhead_ms")) {
                _fallback_end_ms = max(_fallback_end_ms, real(global.timeline_state.playhead_ms));
            }
            _fallback_end_ms = max(_fallback_end_ms, _fallback_measure_ms);

            var _fallback_count = max(1, ceil(_fallback_end_ms / _fallback_measure_ms));
            var _fallback_entries = [];
            for (var _fm = 1; _fm <= _fallback_count; _fm++) {
                array_push(_fallback_entries, {
                    measure: _fm,
                    part: 1,
                    start_ms: (_fm - 1) * _fallback_measure_ms,
                    end_ms: _fm * _fallback_measure_ms,
                    status: 0
                });
            }

            var _pickup_struct = {};
            _pickup_struct[$ "1"] = false;

            global.timeline_state.measure_nav_entries = _fallback_entries;
            global.timeline_state.measure_nav_parts = [1];
            global.timeline_state.measure_nav_pickup_by_part = _pickup_struct;
        }

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

    if (!variable_struct_exists(global.timeline_state, "measure_nav_entries") || !is_array(global.timeline_state.measure_nav_entries)) {
        draw_set_font(fnt_setting);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_color(c_ltgray);
        draw_text(_x1 + 8, _y1 + 8, "Measure map unavailable");
        draw_set_color(c_white);
        return;
    }

    var entries = global.timeline_state.measure_nav_entries;
    if (array_length(entries) <= 0) {
        global.timeline_state.measure_nav_tile_hitboxes = [];
        global.timeline_state.measure_nav_controls = { show: false };
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

    var cols = 4;
    var col_gap = 4;
    var row_gap = 4;
    var left_margin_w = max(12, floor((x2 - x1) * 0.10));
    var content_x1 = x1 + left_margin_w + 4;
    var available_w = max(20, x2 - content_x1);
    var tile_w = floor((available_w - (col_gap * (cols - 1))) / cols);
    tile_w = min(max(12, tile_w), 54);
    var tile_h = tile_w;
    var row_step = tile_h + row_gap;
    var part_gap_rows = 1;

    // Section grouping: every 2 rows (= 8 measures at 4-wide) is a repeat section,
    // every 4 rows (= 16 measures) is a part (A→B) boundary.
    var section_rows    = 2;
    var repeat_sep_h    = max(2, floor(tile_h * 0.12));  // space between repeat groups
    var part_sep_h      = max(6, floor(tile_h * 0.30));  // space + line between tune parts

    var y_top = y1 + 2;
    var y_bottom = y2 - 2;
    // view_rows: conservative estimate accounting for separator overhead.
    // Average separator overhead ≈ repeat_sep_h / section_rows per row.
    var _avg_sep_per_row = repeat_sep_h / section_rows;
    var view_rows = max(1, floor(((y_bottom - y_top) + row_gap) / (row_step + _avg_sep_per_row)));

    // Tune-structure visual tuning comes from timeline config so appearance can be adjusted centrally.
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
    for (var pe = 0; pe < array_length(entries); pe++) {
        var e = entries[pe];
        if (!is_struct(e)) continue;
        var p = floor(real(e.part ?? 1));
        if (p < 1) p = 1;
        var pkey = string(p);
        if (!variable_struct_exists(part_entries, pkey)) {
            part_entries[$ pkey] = [];
        }
        var arr = part_entries[$ pkey];
        array_push(arr, e);
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
    var show_scroll_controls = playback_complete && (max_scroll > 0);

    var ctrl_x1 = x1 + 2;
    var ctrl_x2 = x1 + left_margin_w - 2;
    var ctrl_h = max(8, floor(tile_h * 0.45));
    var up_y1 = y1 + 2;
    var up_y2 = up_y1 + ctrl_h;
    var down_y2 = y2 - 2;
    var down_y1 = down_y2 - ctrl_h;

    var up_enabled = (scroll_row > 0);
    var down_enabled = (scroll_row < max_scroll);

    global.timeline_state.measure_nav_controls = {
        show: show_scroll_controls,
        up: { x1: ctrl_x1, y1: up_y1, x2: ctrl_x2, y2: up_y2, enabled: up_enabled },
        down: { x1: ctrl_x1, y1: down_y1, x2: ctrl_x2, y2: down_y2, enabled: down_enabled }
    };

    if (show_scroll_controls) {
        draw_set_alpha(0.85);
        draw_set_color(up_enabled ? make_color_rgb(78, 78, 84) : make_color_rgb(52, 52, 56));
        draw_rectangle(ctrl_x1, up_y1, ctrl_x2, up_y2, false);
        draw_set_color(down_enabled ? make_color_rgb(78, 78, 84) : make_color_rgb(52, 52, 56));
        draw_rectangle(ctrl_x1, down_y1, ctrl_x2, down_y2, false);
        draw_set_alpha(1);

        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_color(c_white);
        draw_text((ctrl_x1 + ctrl_x2) * 0.5, (up_y1 + up_y2) * 0.5, "^");
        draw_text((ctrl_x1 + ctrl_x2) * 0.5, (down_y1 + down_y2) * 0.5, "v");
    }

    var playhead_ms = real(global.timeline_state.playhead_ms ?? 0);
    var current_measure = gv_get_current_planned_measure(playhead_ms);
    // No forced fallback — current_measure=-1 means pickup/pre-tune phase; no tile highlighted.

    // Auto-scroll to keep the current measure in view during active playback.
    if (!playback_complete && current_measure >= 1 && max_scroll > 0) {
        var ags_count = 0;
        var ags_target_row = -1;
        for (var ags_pi = 0; ags_pi < n_parts && ags_target_row < 0; ags_pi++) {
            var ags_pk = string(floor(real(part_order[ags_pi])));
            var ags_pa = variable_struct_exists(part_entries, ags_pk) ? part_entries[$ ags_pk] : [];
            var ags_rp = max(2, ceil(max(1, array_length(ags_pa)) / cols));
            for (var ags_ri = 0; ags_ri < ags_rp && ags_target_row < 0; ags_ri++) {
                for (var ags_ci = 0; ags_ci < cols; ags_ci++) {
                    var ags_idx = (ags_ri * cols) + ags_ci;
                    if (ags_idx >= array_length(ags_pa)) break;
                    if (floor(real(ags_pa[ags_idx].measure ?? -1)) == current_measure) {
                        ags_target_row = ags_count + ags_ri;
                        break;
                    }
                }
            }
            ags_count += ags_rp;
            if (ags_pi < n_parts - 1) ags_count += part_gap_rows;
        }
        if (ags_target_row >= 0) {
            scroll_row = clamp(max(0, ags_target_row - floor(view_rows / 2)), 0, max_scroll);
            global.timeline_state.measure_nav_scroll_row = scroll_row;
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
                    var _line_hw = tile_w;  // half-width = 1 tile → total line = 2 tiles wide
                    draw_set_alpha(ts_part_sep_alpha);
                    draw_set_color(ts_part_sep_color);
                    draw_line(_line_cx - _line_hw, _line_y, _line_cx + _line_hw, _line_y);
                    draw_set_alpha(1);
                }
            }

            for (var c = 0; c < cols; c++) {
                var idx = (r * cols) + c;
                if (idx >= array_length(rows_part_entries)) continue;

                var entry = rows_part_entries[idx];
                if (!is_struct(entry)) continue;

                var tx1 = content_x1 + (c * (tile_w + col_gap));
                var ty1 = row_y;
                var tx2 = tx1 + tile_w;
                var ty2 = ty1 + tile_h;

                var entry_measure = floor(real(entry.measure ?? -1));
                var entry_end_ms = real(entry.end_ms ?? 0);
                var is_completed = (playhead_ms >= entry_end_ms);
                var is_current = (entry_measure == current_measure) && !is_completed;

                // Tile draw: unplayed=outline only, completed=dark fill, current=yellow highlight
                if (is_current) {
                    // Current measure: warm dark base + yellow tint overlay
                    draw_set_alpha(ts_current_base_alpha);
                    draw_set_color(ts_current_base_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                    draw_set_alpha(ts_current_overlay_alpha);
                    draw_set_color(ts_current_overlay_color);
                    draw_rectangle(tx1 + 1, ty1 + 1, tx2 - 1, ty2 - 1, false);
                } else if (is_completed) {
                    // Played: dark semi-transparent fill (spr_cell_dark style)
                    // TODO: tint by Judge accuracy once Judge settings are available
                    draw_set_alpha(ts_played_fill_alpha);
                    draw_set_color(ts_played_fill_color);
                    draw_rectangle(tx1, ty1, tx2, ty2, false);
                }

                var border_color = is_current ? ts_current_border_color : ts_border_color;
                var border_alpha = is_current ? ts_current_border_alpha : ts_border_alpha;
                draw_set_alpha(border_alpha);
                draw_set_color(border_color);
                draw_rectangle(tx1, ty1, tx2, ty2, true);

                draw_set_alpha(1);

                array_push(tile_hits, {
                    measure: entry_measure,
                    x1: tx1,
                    y1: ty1,
                    x2: tx2,
                    y2: ty2
                });
            }
        }

        global_row_cursor += rows_for_part2;
        if (pidx < n_parts - 1) global_row_cursor += part_gap_rows;
    }

    // Absolute fallback: if the normal layout produced zero visible tiles, draw a compact debug grid.
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
            draw_text((fx1 + fx2) * 0.5, (fy1 + fy2) * 0.5, "M" + string(fm));

            array_push(tile_hits, {
                measure: fm,
                x1: fx1,
                y1: fy1,
                x2: fx2,
                y2: fy2
            });
        }
    }

    global.timeline_state.measure_nav_tile_hitboxes = tile_hits;

    draw_set_alpha(1);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function gv_review_handle_click(_mx, _my) {
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return false;
    if (!variable_struct_exists(global.timeline_state, "playback_complete") || !global.timeline_state.playback_complete) return false;

    if (gv_measure_nav_handle_click(_mx, _my)) return true;

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

    history_runs = event_history_load_recent_summaries(
        export_info.clean_tune,
        export_info.bpm,
        export_info.swing,
        requested_count,
        require_same_bpm,
        require_same_swing
    );

    global.timeline_state.review_history_runs = history_runs;
    global.timeline_state.review_history_loaded = true;
    global.timeline_state.review_history_count = array_length(history_runs);

    show_debug_message("[REVIEW_HISTORY] loaded=" + string(global.timeline_state.review_history_count)
        + " tune=" + export_info.clean_tune
        + " bpm=" + string(export_info.bpm)
        + " swing=" + string(export_info.swing));

    return history_runs;
}

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
        if (!gv_is_tune_focus_channel(real(ps.channel ?? -999))) continue;

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
        if (!gv_is_tune_focus_channel(real(ps.channel ?? -999))) continue;

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
    return -1;  // No real measure active yet (pickup phase or pre-tune)
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

            var lx = clamp(min(x1, x2), _rx1, _rx2);
            var rx = clamp(max(x1, x2), _rx1, _rx2);

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
    var cfg = gv_ensure_timeline_cfg_defaults();

    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;

    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
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
        : 0.14;
    var border_color = variable_struct_exists(cfg, "notebeam_emb_box_border_color")
        ? cfg.notebeam_emb_box_border_color
        : fill_color;
    var border_alpha = variable_struct_exists(cfg, "notebeam_emb_box_border_alpha")
        ? clamp(real(cfg.notebeam_emb_box_border_alpha), 0, 1)
        : 0.90;
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
                _lane_row_height_px, _lane_row_gap_px, _lane_y_offset_px
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
    var cfg = gv_ensure_timeline_cfg_defaults();
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) return;
    if (!variable_struct_exists(cfg, "enabled") || !cfg.enabled) return;

    // Draw can be the only guaranteed active path in RoomUI-driven layouts, so
    // tick playhead here as a fallback when no Step-driven viz instance is active.
    if (global.timeline_state.active) {
        gv_timeline_step_tick();
    }
    var is_active = global.timeline_state.active;

    var pad = variable_struct_exists(cfg, "padding_px") ? real(cfg.padding_px) : 8;
    var gap = variable_struct_exists(cfg, "row_gap_px") ? real(cfg.row_gap_px) : 20;
    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);

    var x1 = _x1 + pad;
    var y1 = _y1 + pad;
    var x2 = _x2 - pad;
    var y2 = _y2 - pad;
    if (x2 <= x1 || y2 <= y1) return;

    var h = y2 - y1;
    var show_structure_row = !variable_struct_exists(cfg, "show_structure_row") || cfg.show_structure_row;
    var structure_h = variable_struct_exists(cfg, "structure_row_height_px")
        ? max(8, real(cfg.structure_row_height_px))
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

    var canvas_bg_color = variable_struct_exists(cfg, "canvas_bg_color")
        ? cfg.canvas_bg_color
        : c_black;
    var canvas_bg_alpha = variable_struct_exists(cfg, "canvas_bg_alpha")
        ? clamp(real(cfg.canvas_bg_alpha), 0, 1)
        : 0.90;
    var row_bg_tune_color = variable_struct_exists(cfg, "row_bg_tune_color")
        ? cfg.row_bg_tune_color
        : c_dkgray;
    var row_bg_player_color = variable_struct_exists(cfg, "row_bg_player_color")
        ? cfg.row_bg_player_color
        : c_dkgray;
    var row_bg_structure_color = variable_struct_exists(cfg, "row_bg_structure_color")
        ? cfg.row_bg_structure_color
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

    gv_ensure_timeline_cfg_defaults();

    var enabled = !variable_struct_exists(global.timeline_cfg, "notebeam_enabled") || global.timeline_cfg.notebeam_enabled;
    if (!enabled) return;

    var x1 = _x1;
    var y1 = _y1;
    var x2 = _x2;
    var y2 = _y2;
    if (x2 <= x1 || y2 <= y1) return;

    var is_active = variable_global_exists("timeline_state") && is_struct(global.timeline_state) && global.timeline_state.active;
    if (is_active) {
        // Keep notebeam motion alive when this canvas is drawn directly
        // (without timeline canvas or object Step participation).
        gv_timeline_step_tick();
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
    var review_mode_active = false;
    var review_split_beams = false;
    var history_markers_enabled = false;
    var history_run_count = 0;
    var history_use_gap_band = !variable_struct_exists(global.timeline_cfg, "notebeam_history_use_gap_band")
        || global.timeline_cfg.notebeam_history_use_gap_band;
    var history_gap_band_active = false;
    var history_start_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_start_color")
        ? global.timeline_cfg.notebeam_history_start_color
        : make_color_rgb(176, 198, 208);
    var history_end_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_end_color")
        ? global.timeline_cfg.notebeam_history_end_color
        : make_color_rgb(238, 220, 150);
    var history_start_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_start_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_start_alpha), 0, 1)
        : 0.26;
    var history_end_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_end_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_end_alpha), 0, 1)
        : 0.50;
    var history_band_color = variable_struct_exists(global.timeline_cfg, "notebeam_history_band_color")
        ? global.timeline_cfg.notebeam_history_band_color
        : make_color_rgb(220, 220, 220);
    var history_band_alpha = variable_struct_exists(global.timeline_cfg, "notebeam_history_band_alpha")
        ? clamp(real(global.timeline_cfg.notebeam_history_band_alpha), 0, 1)
        : 0.20;

    var dbg_playhead_ms = -1;

    if (is_active) {
        var playhead_ms = real(global.timeline_state.playhead_ms ?? 0);
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
        history_markers_enabled = review_mode_active
            && (!variable_struct_exists(global.timeline_cfg, "notebeam_history_enabled") || global.timeline_cfg.notebeam_history_enabled)
            && variable_struct_exists(global.timeline_state, "review_history_runs")
            && is_array(global.timeline_state.review_history_runs)
            && array_length(global.timeline_state.review_history_runs) > 0;
        history_gap_band_active = history_markers_enabled && history_use_gap_band && !review_split_beams;
        history_run_count = history_markers_enabled
            ? array_length(global.timeline_state.review_history_runs)
            : 0;

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
            && array_length(planned_spans) > 0
            && gv_planned_spans_have_focus_channel(planned_spans);
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

        // Draw alternating beat bands behind all beams, only in post-play review.
        if (review_mode_active) {
            gv_draw_notebeam_beat_boxes(x1, y1, x2, y2, playhead_ms, ms_behind, ms_ahead, now_ratio);
        }

        gv_draw_notebeam_emb_group_boxes(
            x1, y1, x2, y2, playhead_ms, ms_behind, ms_ahead, now_ratio,
            lane_count, lane_h,
            using_lane_anchors, lane_anchor_y, lane_anchor_h,
            beam_width_px, match_label_width, match_label_width_scale,
            lane_flip, use_label_lane_layout, lane_top_spacer_ratio, lane_top_spacer_px,
            lane_row_height_px, lane_row_gap_px, lane_y_offset_px
        );

        if (is_array(planned_spans) && array_length(planned_spans) > 0) {
            var ghost_parts_enabled = gv_use_tune_ghost_parts();
            var ghost_parts_alpha = gv_get_tune_other_parts_alpha();
            var planned_pass_count = ghost_parts_enabled ? 2 : 1;

            var n_planned = array_length(planned_spans);
            for (var pass_planned = 0; pass_planned < planned_pass_count; pass_planned++) {
                for (var i = 0; i < n_planned; i++) {
                    var ps = planned_spans[i];
                    if (!is_struct(ps)) continue;

                    var planned_channel = real(ps.channel ?? -999);
                    var vis_state = gv_get_tune_span_visibility_state(planned_channel);
                    if (vis_state <= 0) continue;

                    if (ghost_parts_enabled) {
                        if (pass_planned == 0 && vis_state != 1) continue;
                        if (pass_planned == 1 && vis_state != 2) continue;
                    } else {
                        if (vis_state != 2) continue;
                    }

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
                        if (lane_anchor_h[lane_idx] > 0) {
                            lane_beam_width = lane_anchor_h[lane_idx];
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

                    var py_draw = py;
                    var lane_beam_draw_width = lane_beam_width;
                    if (review_split_beams) {
                        py_draw = clamp(py - (lane_beam_width * 0.25), y1 + 1, y2 - 1);
                        lane_beam_draw_width = max(1, lane_beam_width * 0.5);
                    }

                    var alpha_scale = (vis_state == 1) ? ghost_parts_alpha : 1;
                    draw_set_alpha(planned_beam_alpha * alpha_scale);
                    draw_set_color(planned_beam_color);
                    draw_line_width(plx, py_draw, prx, py_draw, lane_beam_draw_width);
                }
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
                    if (lane_anchor_h[lane_idx2] > 0) {
                        lane_beam_width2 = lane_anchor_h[lane_idx2];
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
                            qy_draw, lane_beam_draw_width2, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                        );
                    } else {
                        draw_set_alpha(player_beam_alpha);
                        draw_set_color(player_beam_color);
                        draw_line_width(qlx, qy_draw, qrx, qy_draw, lane_beam_draw_width2);
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
                        if (lane_anchor_h[lane_idx3] > 0) {
                            lane_beam_width3 = lane_anchor_h[lane_idx3];
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
                                ry_draw, lane_beam_draw_width3, player_beam_segment_match_color, player_beam_miss_color, player_beam_alpha
                            );
                        } else {
                            draw_set_alpha(player_beam_alpha);
                            draw_set_color(player_beam_color);
                            draw_line_width(rlx, ry_draw, rrx, ry_draw, lane_beam_draw_width3);
                        }
                    }
                    draw_set_alpha(player_beam_alpha);
                }

                draw_set_alpha(1);
            }
        }

        if (history_markers_enabled) {
            var history_runs = global.timeline_state.review_history_runs;
            var n_history_runs = array_length(history_runs);
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
                for (var hs = 0; hs < n_history_spans; hs++) {
                    var hspan = history_spans[hs];
                    if (!is_struct(hspan)) continue;

                    var h_start_raw = real(hspan.start_ms ?? 0);
                    var h_end_raw = real(hspan.end_ms ?? h_start_raw);
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

