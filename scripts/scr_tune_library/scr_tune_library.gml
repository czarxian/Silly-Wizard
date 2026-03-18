// scr_tune_library — Tune library loader & picker helper
// Purpose: Loads `tunes/tune_library.json` and populates UI rows for the tune picker.
// Key functions: scr_load_tune_library, scr_tune_picker_populate, scr_tune_picker_rebuild_view_model
// Related objects: obj_tune_picker, obj_tune_row, obj_ui_controller

// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function scr_load_tune_library()
{
    var candidates = array_create(0);
    array_push(candidates, "tunes/tune_library.json");
    array_push(candidates, "datafiles/tunes/tune_library.json");

    for (var i = 0; i < array_length(candidates); i++)
    {
        var p = candidates[i];
        var f = file_text_open_read(p);
        if (f >= 0)
        {
            var raw = "";
            while (!file_text_eof(f))
            {
                raw += file_text_read_string(f);
                file_text_readln(f);
            }
            file_text_close(f);

            var data = json_parse(raw);
            if (is_struct(data) && variable_struct_exists(data, "tunes"))
            {
                // Ensure library has a root folder for resolving filenames
                if (!variable_struct_exists(data, "root"))
                {
                    var last = 0;
                    for (var j = 1; j <= string_length(p); j++)
                    {
                        if (string_copy(p, j, 1) == "/") last = j;
                    }
                    if (last > 0) data.root = string_copy(p, 1, last);
                }

                var library_tunes = variable_struct_get(data, "tunes");
                var needs_part_rebuild = false;
                if (is_array(library_tunes)) {
                    for (var k = 0; k < array_length(library_tunes); k++) {
                        var tune_entry = library_tunes[k];
                        if (!is_struct(tune_entry)) continue;
                        if (!variable_struct_exists(tune_entry, "player_part_channels")) {
                            needs_part_rebuild = true;
                            break;
                        }
                    }
                }

                if (needs_part_rebuild && is_undefined(scr_build_tune_library) == false) {
                    show_debug_message("scr_load_tune_library: rebuilding tune library to add player part metadata");
                    return scr_build_tune_library(string(variable_struct_get(data, "root")));
                }

                data = scr_tune_library_merge_history(data);

                return data;
            }
            else
            {
                show_debug_message("ERROR: Tune library JSON invalid in " + string(p));
            }
        }
    }

    show_debug_message("ERROR: Could not load tune library.");
    return { tunes: [], root: "tunes/" };
}

function scr_tune_picker_get_tune_id(_entry)
{
    if (!is_struct(_entry)) return "";

    if (variable_struct_exists(_entry, "id")) {
        var explicit_id = string_lower(string_trim(string(variable_struct_get(_entry, "id"))));
        if (string_length(explicit_id) > 0) return explicit_id;
    }

    if (variable_struct_exists(_entry, "filename")) {
        var filename_id = string_lower(string_trim(string(variable_struct_get(_entry, "filename"))));
        if (is_undefined(event_history_make_tune_history_id) == false) {
            var normalized_id = event_history_make_tune_history_id(variable_struct_get(_entry, "filename"));
            if (string_length(normalized_id) > 0) return normalized_id;
        }
        if (string_length(filename_id) > 0) return filename_id;
    }

    if (variable_struct_exists(_entry, "title")) {
        var title_id = string_lower(string_trim(string(variable_struct_get(_entry, "title"))));
        if (string_length(title_id) > 0) return "title:" + title_id;
    }

    return "";
}

function scr_tune_picker_voice_to_part_channel(_voice)
{
    var v = string_lower(string(_voice ?? ""));
    switch (v) {
        case "pipes": return 2;
        case "harmony1": return 3;
        case "harmony2": return 4;
        case "harmony3": return 5;
        default: return -1;
    }
}

function scr_tune_picker_collect_player_part_channels(_data)
{
    var channels = [];
    var seen = {};
    var events = [];

    if (is_array(_data)) {
        events = _data;
    }
    else if (is_struct(_data)
        && variable_struct_exists(_data, "events")
        && is_array(variable_struct_get(_data, "events"))) {
        events = variable_struct_get(_data, "events");
    }

    var event_count = array_length(events);
    for (var i = 0; i < event_count; i++) {
        var ev = events[i];
        if (!is_struct(ev)) continue;

        var part_channel = -1;
        if (variable_struct_exists(ev, "voice")) {
            part_channel = scr_tune_picker_voice_to_part_channel(variable_struct_get(ev, "voice"));
        }

        if (part_channel < 2 || part_channel > 5) {
            if (variable_struct_exists(ev, "channel")) {
                var ev_channel = floor(real(variable_struct_get(ev, "channel")));
                if (ev_channel >= 2 && ev_channel <= 5) {
                    part_channel = ev_channel;
                }
            }
        }

        if (part_channel < 2 || part_channel > 5) continue;

        var key = string(part_channel);
        if (!is_undefined(seen[$ key])) continue;
        seen[$ key] = true;
        array_push(channels, part_channel);
    }

    if (array_length(channels) <= 0) {
        channels = [2];
    }

    array_sort(channels, function(a, b) {
        return real(a) - real(b);
    });

    return channels;
}

function scr_tune_picker_get_entry_part_channels(_entry)
{
    if (is_struct(_entry) && variable_struct_exists(_entry, "player_part_channels")) {
        var part_channels = variable_struct_get(_entry, "player_part_channels");
        if (is_array(part_channels) && array_length(part_channels) > 0) {
            return part_channels;
        }
    }

    if (is_struct(_entry) && variable_struct_exists(_entry, "player_part_count")) {
        var part_count = max(1, floor(real(variable_struct_get(_entry, "player_part_count"))));
        var fallback_channels = [];
        for (var i = 0; i < part_count && i < 4; i++) {
            array_push(fallback_channels, 2 + i);
        }
        if (array_length(fallback_channels) > 0) return fallback_channels;
    }

    return [2];
}

function scr_tune_picker_get_entry_part_count(_entry)
{
    return array_length(scr_tune_picker_get_entry_part_channels(_entry));
}

function scr_tune_picker_get_selected_part_channel()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) {
        if (variable_global_exists("selected_player_tune_channel")) {
            return floor(real(global.selected_player_tune_channel));
        }
        return -1;
    }

    return floor(real(scr_tune_picker_get_instance_var(picker, "selected_part_channel", -1)));
}

function scr_tune_picker_find_part_index(_entry, _channel)
{
    var part_channels = scr_tune_picker_get_entry_part_channels(_entry);
    var target_channel = floor(real(_channel));

    for (var i = 0; i < array_length(part_channels); i++) {
        if (floor(real(part_channels[i])) == target_channel) return i;
    }

    return -1;
}

function scr_tune_picker_get_part_label(_entry, _channel)
{
    var part_index = scr_tune_picker_find_part_index(_entry, _channel);
    if (part_index < 0) return "";
    return "P" + string(part_index + 1);
}

function scr_tune_picker_set_selected_part_channel(_entry, _channel = -1)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var part_channels = scr_tune_picker_get_entry_part_channels(_entry);
    if (!is_array(part_channels) || array_length(part_channels) <= 0) {
        part_channels = [2];
    }

    var part_channel = floor(real(_channel));
    if (scr_tune_picker_find_part_index(_entry, part_channel) < 0) {
        part_channel = floor(real(part_channels[0]));
    }

    scr_tune_picker_set_instance_var(picker, "selected_part_channel", part_channel);
    global.selected_player_tune_channel = part_channel;
    return true;
}

function scr_tune_library_find_history_index(_history_index, _tune_id)
{
    if (!is_struct(_history_index)
        || !variable_struct_exists(_history_index, "tunes")
        || !is_array(_history_index.tunes)) {
        return -1;
    }

    var target_id = string_lower(string_trim(string(_tune_id ?? "")));
    if (string_length(target_id) <= 0) return -1;

    for (var i = 0; i < array_length(_history_index.tunes); i++) {
        var entry = _history_index.tunes[i];
        if (!is_struct(entry)) continue;

        var entry_id = string_lower(string_trim(string(entry.id ?? "")));
        if (string_length(entry_id) > 0 && entry_id == target_id) {
            return i;
        }

        var filename_id = string_lower(string_trim(string(entry.filename ?? "")));
        if (string_length(filename_id) > 0 && filename_id == target_id) {
            return i;
        }
    }

    return -1;
}

function scr_tune_library_apply_history_entry(_entry, _history_entry)
{
    if (!is_struct(_entry) || !is_struct(_history_entry)) return _entry;

    variable_struct_set(_entry, "id", scr_tune_picker_get_tune_id(_entry));

    if (variable_struct_exists(_history_entry, "plays_count")) {
        var plays_count = floor(max(0, real(variable_struct_get(_history_entry, "plays_count"))));
        variable_struct_set(_entry, "plays_count", plays_count);
        variable_struct_set(_entry, "times_played", plays_count);
    }

    if (variable_struct_exists(_history_entry, "last_played_utc")) {
        var last_played_utc = string(variable_struct_get(_history_entry, "last_played_utc"));
        variable_struct_set(_entry, "last_played_utc", last_played_utc);
        variable_struct_set(_entry, "last_played", last_played_utc);
    }

    if (variable_struct_exists(_history_entry, "last_play_date")) {
        variable_struct_set(_entry, "last_play_date", string(variable_struct_get(_history_entry, "last_play_date")));
    }

    if (variable_struct_exists(_history_entry, "last_score")) {
        var last_score = string(variable_struct_get(_history_entry, "last_score"));
        variable_struct_set(_entry, "last_score", last_score);
        variable_struct_set(_entry, "score", last_score);
    }

    if (variable_struct_exists(_history_entry, "best_score")) {
        variable_struct_set(_entry, "best_score", string(variable_struct_get(_history_entry, "best_score")));
    }

    if (variable_struct_exists(_history_entry, "last_bpm")) {
        variable_struct_set(_entry, "last_bpm", variable_struct_get(_history_entry, "last_bpm"));
    }

    if (variable_struct_exists(_history_entry, "last_swing")) {
        variable_struct_set(_entry, "last_swing", string(variable_struct_get(_history_entry, "last_swing")));
    }

    return _entry;
}

function scr_tune_library_merge_history(_library)
{
    var library_tunes = scr_tune_library_get_tunes(_library);
    if (!is_array(library_tunes)) {
        return _library;
    }

    var history_index = undefined;
    if (is_undefined(event_history_load_tune_history_index) == false) {
        history_index = event_history_load_tune_history_index();
    }

    var history_tunes = scr_tune_library_get_tunes(history_index);

    for (var i = 0; i < array_length(library_tunes); i++) {
        var entry = library_tunes[i];
        if (!is_struct(entry)) continue;

        var entry_id = scr_tune_picker_get_tune_id(entry);
        variable_struct_set(entry, "id", entry_id);

        var history_idx = scr_tune_library_find_history_index(history_index, entry_id);
        if (is_array(history_tunes) && history_idx >= 0 && history_idx < array_length(history_tunes)) {
            entry = scr_tune_library_apply_history_entry(entry, history_tunes[history_idx]);
        }

        library_tunes[i] = entry;
    }

    variable_struct_set(_library, "tunes", library_tunes);

    return _library;
}

function scr_tune_picker_find_index_by_id(_library, _tune_id)
{
    var tunes = scr_tune_library_get_tunes(_library);
    if (!is_array(tunes)) {
        return -1;
    }

    var target_id = string_lower(string_trim(string(_tune_id ?? "")));
    if (string_length(target_id) <= 0) return -1;

    for (var i = 0; i < array_length(tunes); i++) {
        if (scr_tune_picker_get_tune_id(tunes[i]) == target_id) {
            return i;
        }
    }

    return -1;
}

function scr_tune_library_get_tunes(_library)
{
    if (!is_struct(_library)) return undefined;
    if (!variable_struct_exists(_library, "tunes")) return undefined;

    var tunes = variable_struct_get(_library, "tunes");
    if (!is_array(tunes)) return undefined;

    return tunes;
}

function scr_tune_struct_get(_struct, _key, _default = undefined)
{
    if (!is_struct(_struct)) return _default;
    if (!variable_struct_exists(_struct, _key)) return _default;
    return variable_struct_get(_struct, _key);
}

function scr_tune_picker_get_instance_var(_picker, _name, _default = undefined)
{
    if (_picker == noone) return _default;
    if (!variable_instance_exists(_picker, _name)) return _default;
    return variable_instance_get(_picker, _name);
}

function scr_tune_picker_set_instance_var(_picker, _name, _value)
{
    if (_picker == noone) return false;
    variable_instance_set(_picker, _name, _value);
    return true;
}

function scr_tune_instance_get(_inst, _name, _default = undefined)
{
    if (_inst == noone || !instance_exists(_inst)) return _default;
    if (!variable_instance_exists(_inst, _name)) return _default;
    return variable_instance_get(_inst, _name);
}

function scr_tune_instance_set(_inst, _name, _value)
{
    if (_inst == noone || !instance_exists(_inst)) return false;
    variable_instance_set(_inst, _name, _value);
    return true;
}

function scr_tune_picker_find_instance_by_ui_name(_obj, _ui_name)
{
    var count = instance_number(_obj);
    for (var i = 0; i < count; i++) {
        var inst = instance_find(_obj, i);
        if (inst == noone) continue;
        var inst_ui_name = string(scr_tune_instance_get(inst, "ui_name", ""));
        if (inst_ui_name == _ui_name) return inst;
    }
    return noone;
}

function scr_tune_picker_get_library(_picker)
{
    var library = scr_tune_picker_get_instance_var(_picker, "library", undefined);
    if (!is_struct(library)) return undefined;
    if (!is_array(scr_tune_library_get_tunes(library))) return undefined;
    return library;
}

function scr_tune_picker_clear_selection()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) {
        if (variable_global_exists("tune_selection")) global.tune_selection = -1;
        global.selected_player_tune_channel = -1;
        return false;
    }

    scr_tune_picker_set_instance_var(picker, "selected_index", -1);
    scr_tune_picker_set_instance_var(picker, "selected_tune_id", "");
    scr_tune_picker_set_instance_var(picker, "selected_tune_filename", "");
    scr_tune_picker_set_instance_var(picker, "selected_part_channel", -1);
    if (variable_global_exists("tune_selection")) global.tune_selection = -1;
    global.selected_player_tune_channel = -1;
    return true;
}

function scr_tune_picker_set_selected_by_index(_index, _part_channel = -1)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) {
        return scr_tune_picker_clear_selection();
    }

    var idx = floor(real(_index));
    if (idx < 0 || idx >= array_length(tunes)) {
        return scr_tune_picker_clear_selection();
    }

    var entry = tunes[idx];

    scr_tune_picker_set_instance_var(picker, "selected_index", idx);
    scr_tune_picker_set_instance_var(picker, "selected_tune_id", scr_tune_picker_get_tune_id(entry));
    scr_tune_picker_set_instance_var(picker, "selected_tune_filename", variable_struct_exists(entry, "filename")
        ? string(variable_struct_get(entry, "filename"))
        : "");
    scr_tune_picker_set_selected_part_channel(entry, _part_channel);

    if (variable_global_exists("tune_selection")) global.tune_selection = idx;
    return true;
}

function scr_tune_picker_set_selected_by_id(_tune_id)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var idx = scr_tune_picker_find_index_by_id(scr_tune_picker_get_library(picker), _tune_id);
    if (idx < 0) return scr_tune_picker_clear_selection();

    return scr_tune_picker_set_selected_by_index(idx);
}

function scr_tune_picker_get_selected_entry()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return undefined;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) {
        return undefined;
    }

    // Prefer ID-based selection so selection survives reordering/filtering.
    var selected_id = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "selected_tune_id", ""))));
    if (string_length(selected_id) > 0) {
        var idx_by_id = scr_tune_picker_find_index_by_id(library, selected_id);
        if (idx_by_id >= 0 && idx_by_id < array_length(tunes)) {
            scr_tune_picker_set_instance_var(picker, "selected_index", idx_by_id);
            return tunes[idx_by_id];
        }
    }

    var idx = floor(real(scr_tune_picker_get_instance_var(picker, "selected_index", -1)));
    if (idx < 0 || idx >= array_length(tunes)) return undefined;

    var entry = tunes[idx];
    scr_tune_picker_set_instance_var(picker, "selected_tune_id", scr_tune_picker_get_tune_id(entry));
    scr_tune_picker_set_instance_var(picker, "selected_tune_filename", variable_struct_exists(entry, "filename")
        ? string(variable_struct_get(entry, "filename"))
        : "");

    var selected_part_channel = scr_tune_picker_get_selected_part_channel();
    if (scr_tune_picker_find_part_index(entry, selected_part_channel) < 0) {
        scr_tune_picker_set_selected_part_channel(entry, selected_part_channel);
    }
    return entry;
}

function scr_tune_picker_get_tune_title(_entry)
{
    if (!is_struct(_entry)) return "";

    if (variable_struct_exists(_entry, "title")) {
        var title = string_trim(string(variable_struct_get(_entry, "title")));
        if (string_length(title) > 0) return title;
    }

    if (variable_struct_exists(_entry, "filename")) {
        return string(variable_struct_get(_entry, "filename"));
    }

    return "";
}

function scr_tune_picker_get_tune_rhythm_key(_entry)
{
    if (!is_struct(_entry)) return "unknown";

    var rhythm = "";
    if (variable_struct_exists(_entry, "rhythm")) {
        rhythm = string(variable_struct_get(_entry, "rhythm"));
    }

    rhythm = string_lower(string_trim(rhythm));
    if (string_length(rhythm) <= 0) return "unknown";

    return rhythm;
}

function scr_tune_picker_format_label(_raw)
{
    var text = string_trim(string(_raw ?? ""));
    if (string_length(text) <= 0) return "";

    text = string_lower(string_replace_all(text, "_", " "));

    var out = "";
    var cap_next = true;

    for (var i = 1; i <= string_length(text); i++) {
        var ch = string_char_at(text, i);
        if (cap_next && ch >= "a" && ch <= "z") {
            ch = string_upper(ch);
        }

        out += ch;
        cap_next = (ch == " " || ch == "-" || ch == "/" || ch == "(");
    }

    return out;
}

function scr_tune_picker_get_rhythm_label(_rhythm_key)
{
    var key = string_lower(string_trim(string(_rhythm_key ?? "all")));
    if (string_length(key) <= 0 || key == "all") return "All Rhythms";
    if (key == "unknown") return "Unknown Rhythm";
    return scr_tune_picker_format_label(key);
}

function scr_tune_picker_get_sort_mode_label(_sort_mode)
{
    var mode = string_lower(string_trim(string(_sort_mode ?? "title_asc")));
    return (mode == "title_desc") ? "Title Z-A" : "Title A-Z";
}

function scr_tune_picker_get_tune_meta_line(_entry)
{
    if (!is_struct(_entry)) return "";

    var rhythm = scr_tune_picker_get_rhythm_label(scr_tune_picker_get_tune_rhythm_key(_entry));
    var meter = string_trim(string(scr_tune_picker_get_struct_value(_entry, ["meter"], "")));
    if (string_length(meter) <= 0) meter = "--";

    return rhythm + "  |  " + meter;
}

function scr_tune_picker_get_struct_value(_entry, _keys, _fallback = "--")
{
    if (!is_struct(_entry) || !is_array(_keys)) return string(_fallback);

    for (var i = 0; i < array_length(_keys); i++) {
        var key = string(_keys[i]);
        if (variable_struct_exists(_entry, key)) {
            var value = string_trim(string(variable_struct_get(_entry, key)));
            if (string_length(value) > 0) return value;
        }
    }

    return string(_fallback);
}

function scr_tune_picker_get_tune_meta_cells(_entry, _part_label = "")
{
    var rhythm = scr_tune_picker_get_rhythm_label(scr_tune_picker_get_tune_rhythm_key(_entry));
    if (rhythm == "Unknown Rhythm") rhythm = "--";

    var meter = scr_tune_picker_get_struct_value(_entry, ["meter"], "--");
    var plays = scr_tune_picker_get_struct_value(_entry, ["plays_count", "times_played", "play_count"], "--");
    var last_play = scr_tune_picker_get_struct_value(_entry, ["last_play_date", "last_played_utc", "last_played", "last_play", "last_play_ymd"], "--");
    var score_value = scr_tune_picker_get_struct_value(_entry, ["last_score", "best_score", "score"], "--");

    if (last_play != "--" && string_length(last_play) >= 8 && string_pos("-", last_play) == 0) {
        last_play = string_copy(last_play, 1, 4) + "-" + string_copy(last_play, 5, 2) + "-" + string_copy(last_play, 7, 2);
    }

    return [
        rhythm,
        meter,
        "P " + plays,
        last_play,
        score_value,
        string(_part_label ?? "")
    ];
}

function scr_tune_picker_fit_text(_text, _max_width)
{
    var text = string(_text ?? "");
    if (_max_width <= 0) return "";
    if (string_width(text) <= _max_width) return text;

    var ellipsis = "...";
    var clipped = text;
    while (string_length(clipped) > 0 && string_width(clipped + ellipsis) > _max_width) {
        clipped = string_delete(clipped, string_length(clipped), 1);
    }

    if (string_length(clipped) <= 0) return ellipsis;
    return clipped + ellipsis;
}

function scr_tune_picker_fit_text_scaled(_text, _max_width, _scale_x)
{
    var text = string(_text ?? "");
    var scale_x = max(real(_scale_x), 0.05);
    if (_max_width <= 0) return "";
    if ((string_width(text) * scale_x) <= _max_width) return text;

    var ellipsis = "...";
    var clipped = text;
    while (string_length(clipped) > 0 && ((string_width(clipped + ellipsis) * scale_x) > _max_width)) {
        clipped = string_delete(clipped, string_length(clipped), 1);
    }

    if (string_length(clipped) <= 0) return ellipsis;
    return clipped + ellipsis;
}

function scr_tune_picker_draw_text_scaled(_x, _y, _text, _scale_x, _scale_y)
{
    var sx = max(real(_scale_x), 0.05);
    var sy = max(real(_scale_y), 0.05);
    draw_text_transformed(_x, _y, string(_text ?? ""), sx, sy, 0);
}

function scr_tune_picker_make_rect(_x1, _y1, _x2, _y2)
{
    var x1 = floor(min(_x1, _x2));
    var y1 = floor(min(_y1, _y2));
    var x2 = floor(max(_x1, _x2));
    var y2 = floor(max(_y1, _y2));

    return {
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        w: max(0, x2 - x1),
        h: max(0, y2 - y1)
    };
}

function scr_tune_picker_rect_contains(_rect, _x, _y)
{
    if (!is_struct(_rect)) return false;
    return (_x >= _rect.x1 && _x <= _rect.x2 && _y >= _rect.y1 && _y <= _rect.y2);
}

function scr_tune_picker_get_mouse_gui_x()
{
    if (is_undefined(device_mouse_x_to_gui) == false) return device_mouse_x_to_gui(0);
    return display_mouse_get_x();
}

function scr_tune_picker_get_mouse_gui_y()
{
    if (is_undefined(device_mouse_y_to_gui) == false) return device_mouse_y_to_gui(0);
    return display_mouse_get_y();
}

function scr_tune_picker_collect_canvas_anchor_bounds(_tune_layer)
{
    var result = {
        left: 1000000,
        top: 1000000,
        right: -1000000,
        bottom: -1000000,
        close_bottom: -1000000,
        metro_top: 1000000,
        ok_top: 1000000,
        count: 0
    };

    var inst_count = instance_number(obj_UI_parent);
    for (var i = 0; i < inst_count; i++) {
        var inst = instance_find(obj_UI_parent, i);
        if (inst == noone) continue;

        var ui_name = string(scr_tune_instance_get(inst, "ui_name", ""));
        if (string_length(ui_name) <= 0) continue;

        var is_legacy_row = (string_pos("obj_tune_field_", ui_name) == 1)
            || (string_pos("obj_tune_checkbox_", ui_name) == 1);
        if (is_legacy_row) continue;

        var is_tune_anchor = (string_pos("obj_tune_", ui_name) == 1)
            || (string_pos("metro_", ui_name) == 1);
        if (!is_tune_anchor) continue;

        var inst_layer = real(scr_tune_instance_get(inst, "ui_layer_num", -1));
        if (_tune_layer >= 0 && inst_layer != _tune_layer) continue;

        var bx1 = real(scr_tune_instance_get(inst, "bbox_left", 0));
        var by1 = real(scr_tune_instance_get(inst, "bbox_top", 0));
        var bx2 = real(scr_tune_instance_get(inst, "bbox_right", 0));
        var by2 = real(scr_tune_instance_get(inst, "bbox_bottom", 0));
        if (bx2 <= bx1 || by2 <= by1) continue;

        result.left = min(result.left, bx1);
        result.top = min(result.top, by1);
        result.right = max(result.right, bx2);
        result.bottom = max(result.bottom, by2);
        result.count += 1;

        if (ui_name == "obj_tune_win_close_button") {
            result.close_bottom = max(result.close_bottom, by2);
        }

        if (ui_name == "obj_tune_ok_button") {
            result.ok_top = min(result.ok_top, by1);
        }

        if (string_pos("metro_", ui_name) == 1) {
            result.metro_top = min(result.metro_top, by1);
        }
    }

    return result;
}

function scr_tune_picker_get_explicit_canvas_anchor(_tune_layer)
{
    var anchor = scr_tune_picker_find_instance_by_ui_name(obj_UI_parent, "tune_library_canvas_anchor");

    if (anchor == noone || !instance_exists(anchor)) return undefined;

    var ax1 = real(scr_tune_instance_get(anchor, "bbox_left", 0));
    var ay1 = real(scr_tune_instance_get(anchor, "bbox_top", 0));
    var ax2 = real(scr_tune_instance_get(anchor, "bbox_right", ax1 + 1));
    var ay2 = real(scr_tune_instance_get(anchor, "bbox_bottom", ay1 + 1));
    if (ax2 <= ax1 || ay2 <= ay1) return undefined;

    return scr_tune_picker_make_rect(ax1, ay1, ax2, ay2);
}

function scr_tune_picker_get_canvas_fallback_bounds(_tune_layer, _prefer_window_bounds = false)
{
    var explicit_anchor = scr_tune_picker_get_explicit_canvas_anchor(_tune_layer);
    if (is_struct(explicit_anchor)
        && real(scr_tune_struct_get(explicit_anchor, "w", 0)) > 120
        && real(scr_tune_struct_get(explicit_anchor, "h", 0)) > 90) {
        // Designer-controlled path: the anchor rectangle is the full canvas area.
        return explicit_anchor;
    }

    var prefer_window_bounds = (_prefer_window_bounds == true);

    var gui_w = display_get_gui_width();
    var gui_h = display_get_gui_height();
    if (gui_w <= 0) gui_w = display_get_width();
    if (gui_h <= 0) gui_h = display_get_height();
    if (gui_w <= 0) gui_w = 1920;
    if (gui_h <= 0) gui_h = 1080;

    var win_left = floor(gui_w * 0.15);
    var win_top = floor(gui_h * 0.10);
    var win_w = max(260, floor(gui_w * 0.50));
    var win_h = max(320, floor(gui_h * 0.80));
    var win_right = win_left + win_w;

    var frame_margin_x = max(4, floor(win_w * 0.02));
    var frame_left = win_left + frame_margin_x;
    var frame_right = win_right - frame_margin_x;
    var frame_top_min = win_top + floor(win_h * 0.10);
    var frame_bottom_max = win_top + floor(win_h * 0.66);

    var anchor_bounds = scr_tune_picker_collect_canvas_anchor_bounds(_tune_layer);
    var anchor_count = floor(real(scr_tune_struct_get(anchor_bounds, "count", 0)));
    var min_anchor_count = prefer_window_bounds ? 3 : 1;

    if (anchor_count >= min_anchor_count) {
        var left = real(scr_tune_struct_get(anchor_bounds, "left", 0)) - 10;
        var right = real(scr_tune_struct_get(anchor_bounds, "right", 0)) + 10;
        var top = real(scr_tune_struct_get(anchor_bounds, "top", 0)) + 14;
        var bottom = real(scr_tune_struct_get(anchor_bounds, "bottom", 0)) - 8;

        var close_bottom = real(scr_tune_struct_get(anchor_bounds, "close_bottom", -1000000));
        if (close_bottom > -900000) {
            top = max(top, close_bottom + 8);
        }

        var metro_top = real(scr_tune_struct_get(anchor_bounds, "metro_top", 1000000));
        if (metro_top < 900000) {
            bottom = min(bottom, metro_top - 6);
        } else {
            var ok_top = real(scr_tune_struct_get(anchor_bounds, "ok_top", 1000000));
            if (ok_top < 900000) {
                bottom = min(bottom, ok_top - 10);
            }
        }

        // Clamp to the expected tune-window frame to avoid drifting outside the panel.
        left = max(left, frame_left);
        right = min(right, frame_right);
        top = max(top, frame_top_min);
        bottom = min(bottom, frame_bottom_max);

        if (right > left + 120 && bottom > top + 90) {
            return scr_tune_picker_make_rect(left, top, right, bottom);
        }
    }

    var list_left = frame_left;
    var list_right = frame_right;
    var list_top = frame_top_min;
    var list_bottom = frame_bottom_max;

    if (list_right <= list_left || list_bottom <= list_top) return undefined;

    return scr_tune_picker_make_rect(list_left, list_top, list_right, list_bottom);
}

function scr_tune_picker_sync_selected_entry_ui()
{
    var entry = scr_tune_picker_get_selected_entry();
    if (!is_struct(entry)) return false;

	var selected_part_channel = scr_tune_picker_get_selected_part_channel();
	if (scr_tune_picker_find_part_index(entry, selected_part_channel) < 0) {
		scr_tune_picker_set_selected_part_channel(entry, selected_part_channel);
	}

    if (variable_global_exists("obj_gameinfo_win_title") && instance_exists(global.obj_gameinfo_win_title)) {
        scr_tune_instance_set(global.obj_gameinfo_win_title, "field_contents", scr_tune_picker_get_tune_title(entry));
    }

    var tempo_str = string(scr_tune_struct_get(entry, "tempo_default", "120"));
    var metro_field_3_inst = scr_tune_picker_find_instance_by_ui_name(obj_field_base, "metro_field_3");
    if (string_length(tempo_str) > 0 && instance_exists(metro_field_3_inst)) {
        scr_tune_instance_set(metro_field_3_inst, "field_value", real(tempo_str));
        scr_tune_instance_set(metro_field_3_inst, "field_contents", tempo_str);
    }

    var time_sig = string(scr_tune_struct_get(entry, "meter", "4/4"));
    global.selected_tune_time_sig = time_sig;
    metronome_update_pattern_list(time_sig);

    var metro_field_2_inst = scr_tune_picker_find_instance_by_ui_name(obj_field_base, "metro_field_2");
    if (instance_exists(metro_field_2_inst) && array_length(global.metronome_pattern_options) > 0) {
        scr_tune_instance_set(metro_field_2_inst, "field_value", global.metronome_pattern_selection);
        scr_tune_instance_set(metro_field_2_inst, "field_contents", global.metronome_pattern_options[global.metronome_pattern_selection]);
    }

    return true;
}

function scr_tune_picker_select_index(_index)
{
    if (!scr_tune_picker_set_selected_by_index(_index)) return false;

    scr_tune_picker_sync_selected_entry_ui();
    scr_tune_picker_refresh_visible_rows();
    return true;
}

function scr_tune_picker_activate_index(_index)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) return scr_tune_picker_clear_selection();

    var idx = floor(real(_index));
    if (idx < 0 || idx >= array_length(tunes)) return scr_tune_picker_clear_selection();

    var entry = tunes[idx];
    var tune_id = scr_tune_picker_get_tune_id(entry);
    var selected_id = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "selected_tune_id", ""))));

    if (string_length(selected_id) <= 0 || tune_id != selected_id) {
        return scr_tune_picker_select_index(idx);
    }

    var part_channels = scr_tune_picker_get_entry_part_channels(entry);
    var current_channel = scr_tune_picker_get_selected_part_channel();
    var current_part_index = scr_tune_picker_find_part_index(entry, current_channel);
    if (current_part_index < 0) current_part_index = 0;

    var next_part_index = current_part_index + 1;
    if (next_part_index >= array_length(part_channels)) {
        scr_tune_picker_clear_selection();
        scr_tune_picker_refresh_visible_rows();
        return true;
    }

    if (!scr_tune_picker_set_selected_by_index(idx, part_channels[next_part_index])) return false;
    scr_tune_picker_sync_selected_entry_ui();
    scr_tune_picker_refresh_visible_rows();
    return true;
}

function scr_tune_picker_get_visible_source_index(_row_idx)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return -1;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) {
        return -1;
    }

    var row_idx = floor(real(_row_idx));
    if (row_idx < 0) return -1;

    var filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", undefined);
    if (!is_array(filtered_indices)) {
        return -1;
    }

    var scroll_offset = max(0, floor(real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0))));
    var source_pos = scroll_offset + row_idx;
    if (source_pos < 0 || source_pos >= array_length(filtered_indices)) return -1;

    var source_idx = floor(real(filtered_indices[source_pos]));
    if (source_idx < 0 || source_idx >= array_length(tunes)) return -1;

    return source_idx;
}

function scr_tune_picker_rebuild_view_model()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) {
        scr_tune_picker_set_instance_var(picker, "view_filtered_indices", []);
        scr_tune_picker_set_instance_var(picker, "view_rhythm_options", ["all"]);
        scr_tune_picker_set_instance_var(picker, "view_scroll_offset", 0);
        return false;
    }

    var filter_key = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_filter_rhythm", "all"))));
    if (string_length(filter_key) <= 0) filter_key = "all";
    scr_tune_picker_set_instance_var(picker, "view_filter_rhythm", filter_key);

    var sort_mode = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_sort_mode", "title_asc"))));
    if (string_length(sort_mode) <= 0) sort_mode = "title_asc";
    scr_tune_picker_set_instance_var(picker, "view_sort_mode", sort_mode);

    var rhythm_seen = {};
    var rhythm_keys = array_create(0);
    var filtered_indices = array_create(0);

    for (var i = 0; i < array_length(tunes); i++) {
        var entry = tunes[i];
        var rhythm_key = scr_tune_picker_get_tune_rhythm_key(entry);

        if (is_undefined(rhythm_seen[$ rhythm_key])) {
            rhythm_seen[$ rhythm_key] = true;
            array_push(rhythm_keys, rhythm_key);
        }

        if (filter_key == "all" || rhythm_key == filter_key) {
            array_push(filtered_indices, i);
        }
    }

    array_sort(rhythm_keys, function(a, b) {
        if (a == b) return 0;
        return (a < b) ? -1 : 1;
    });

    var rhythm_options = ["all"];
    for (var rk = 0; rk < array_length(rhythm_keys); rk++) {
        array_push(rhythm_options, rhythm_keys[rk]);
    }
    scr_tune_picker_set_instance_var(picker, "view_rhythm_options", rhythm_options);

    var sort_desc = (sort_mode == "title_desc");
    for (var si = 1; si < array_length(filtered_indices); si++) {
        var key_index = filtered_indices[si];
        var key_title = string_lower(scr_tune_picker_get_tune_title(tunes[key_index]));
        var sj = si - 1;

        while (sj >= 0) {
            var scan_index = filtered_indices[sj];
            var scan_title = string_lower(scr_tune_picker_get_tune_title(tunes[scan_index]));
            var should_shift = sort_desc
                ? (scan_title < key_title)
                : (scan_title > key_title);

            if (!should_shift && scan_title == key_title) {
                should_shift = sort_desc
                    ? (scan_index < key_index)
                    : (scan_index > key_index);
            }

            if (!should_shift) break;

            filtered_indices[sj + 1] = filtered_indices[sj];
            sj--;
        }

        filtered_indices[sj + 1] = key_index;
    }

    scr_tune_picker_set_instance_var(picker, "view_filtered_indices", filtered_indices);

    var visible_rows = max(1, floor(real(scr_tune_picker_get_instance_var(picker, "view_visible_rows", 14))));
    scr_tune_picker_set_instance_var(picker, "view_visible_rows", visible_rows);

    var max_scroll = max(array_length(filtered_indices) - visible_rows, 0);
    var current_scroll = floor(real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0)));
    scr_tune_picker_set_instance_var(picker, "view_scroll_offset", clamp(current_scroll, 0, max_scroll));

    return true;
}

function scr_tune_picker_set_filter_rhythm(_rhythm_key)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var key = string_lower(string_trim(string(_rhythm_key ?? "all")));
    if (string_length(key) <= 0) key = "all";

    scr_tune_picker_set_instance_var(picker, "view_filter_rhythm", key);
    scr_tune_picker_set_instance_var(picker, "view_scroll_offset", 0);
    return scr_tune_picker_refresh_visible_rows();
}

function scr_tune_picker_set_sort_mode(_sort_mode)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var mode = string_lower(string_trim(string(_sort_mode ?? "title_asc")));
    if (string_length(mode) <= 0) mode = "title_asc";

    scr_tune_picker_set_instance_var(picker, "view_sort_mode", mode);
    return scr_tune_picker_refresh_visible_rows();
}

function scr_tune_picker_scroll_rows(_delta_rows)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", undefined);
    if (!is_array(filtered_indices)) {
        scr_tune_picker_rebuild_view_model();
        filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", []);
    }

    var delta = floor(real(_delta_rows));
    if (delta == 0) return true;

    var visible_rows = max(1, floor(real(scr_tune_picker_get_instance_var(picker, "view_visible_rows", 14))));
    var max_scroll = max(array_length(filtered_indices) - visible_rows, 0);
    var next_offset = floor(real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0))) + delta;
    scr_tune_picker_set_instance_var(picker, "view_scroll_offset", clamp(next_offset, 0, max_scroll));

    return true;
}

function scr_tune_picker_cycle_filter_rhythm(_delta)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var options = scr_tune_picker_get_instance_var(picker, "view_rhythm_options", undefined);
    if (!is_array(options) || array_length(options) <= 0) {
        scr_tune_picker_rebuild_view_model();
        options = scr_tune_picker_get_instance_var(picker, "view_rhythm_options", []);
    }

    var option_count = array_length(options);
    if (option_count <= 0) return false;

    var current_key = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_filter_rhythm", "all"))));
    var current_idx = 0;
    for (var i = 0; i < option_count; i++) {
        if (string_lower(string(options[i])) == current_key) {
            current_idx = i;
            break;
        }
    }

    var delta = floor(real(_delta));
    if (delta == 0) delta = 1;
    var next_idx = (current_idx + delta + (option_count * 4)) mod option_count;
    return scr_tune_picker_set_filter_rhythm(options[next_idx]);
}

function scr_tune_picker_cycle_sort_mode(_delta)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var modes = ["title_asc", "title_desc"];
    var current_mode = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_sort_mode", "title_asc"))));
    var current_idx = (current_mode == "title_desc") ? 1 : 0;

    var delta = floor(real(_delta));
    if (delta == 0) delta = 1;

    var next_idx = (current_idx + delta + 8) mod array_length(modes);
    return scr_tune_picker_set_sort_mode(modes[next_idx]);
}

function scr_tune_picker_update_canvas_layout()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var tune_layer = -1;
    if (is_undefined(GetLayerIndexFromName) == false) tune_layer = GetLayerIndexFromName("tune_window_layer");

    var legacy_fields = array_create(0);
    var legacy_checks = array_create(0);

    var field_count = instance_number(obj_field_base);
    for (var fi = 0; fi < field_count; fi++) {
        var field_inst = instance_find(obj_field_base, fi);
        if (field_inst == noone) continue;
        var field_ui_name = string(scr_tune_instance_get(field_inst, "ui_name", ""));
        var field_ui_layer = real(scr_tune_instance_get(field_inst, "ui_layer_num", -1));
        if (field_ui_name != "" && string_pos("obj_tune_field_", field_ui_name) == 1) {
            if (tune_layer < 0 || field_ui_layer == tune_layer) {
                array_push(legacy_fields, field_inst);
            }
        }
    }

    var check_count = instance_number(obj_btn_check);
    for (var ci = 0; ci < check_count; ci++) {
        var check_inst = instance_find(obj_btn_check, ci);
        if (check_inst == noone) continue;
        var check_ui_name = string(scr_tune_instance_get(check_inst, "ui_name", ""));
        var check_ui_layer = real(scr_tune_instance_get(check_inst, "ui_layer_num", -1));
        if (check_ui_name != "" && string_pos("obj_tune_checkbox_", check_ui_name) == 1) {
            if (tune_layer < 0 || check_ui_layer == tune_layer) {
                array_push(legacy_checks, check_inst);
            }
        }
    }

    var has_legacy_rows = (array_length(legacy_fields) > 0 || array_length(legacy_checks) > 0);
    var use_legacy_bounds = has_legacy_rows;

    if (has_legacy_rows) {
        var legacy_row_ids = {};
        var legacy_row_count = 0;
        var legacy_row_min = 1000000;
        var legacy_row_max = -1000000;

        for (var lid_f = 0; lid_f < array_length(legacy_fields); lid_f++) {
            var legacy_field = legacy_fields[lid_f];
            if (!instance_exists(legacy_field)) continue;

            var field_id_raw = scr_tune_instance_get(legacy_field, "field_ID", undefined);
            if (is_undefined(field_id_raw)) continue;

            var field_id = floor(real(field_id_raw));
            if (field_id <= 0) continue;

            var field_key = string(field_id);
            if (is_undefined(legacy_row_ids[$ field_key])) {
                legacy_row_ids[$ field_key] = true;
                legacy_row_count += 1;
                legacy_row_min = min(legacy_row_min, field_id);
                legacy_row_max = max(legacy_row_max, field_id);
            }
        }

        for (var lid_c = 0; lid_c < array_length(legacy_checks); lid_c++) {
            var legacy_check = legacy_checks[lid_c];
            if (!instance_exists(legacy_check)) continue;

            var check_id_raw = scr_tune_instance_get(legacy_check, "button_ID", undefined);
            if (is_undefined(check_id_raw)) continue;

            var check_id = floor(real(check_id_raw));
            if (check_id <= 0) continue;

            var check_key = string(check_id);
            if (is_undefined(legacy_row_ids[$ check_key])) {
                legacy_row_ids[$ check_key] = true;
                legacy_row_count += 1;
                legacy_row_min = min(legacy_row_min, check_id);
                legacy_row_max = max(legacy_row_max, check_id);
            }
        }

        // If legacy rows are only partially present (for example 8-14 with 1-7 removed),
        // ignore their bounds and use anchor/gui fallback bounds for full-window canvas layout.
        if (legacy_row_count > 0 && !(legacy_row_min == 1 && legacy_row_max == legacy_row_count)) {
            use_legacy_bounds = false;
        }
    }

    var left = 1000000;
    var top = 1000000;
    var right = -1000000;
    var bottom = -1000000;

    if (has_legacy_rows) {
        if (use_legacy_bounds) {
            for (var fi = 0; fi < array_length(legacy_fields); fi++) {
                var field_inst = legacy_fields[fi];
                if (!instance_exists(field_inst)) continue;
                left = min(left, real(scr_tune_instance_get(field_inst, "bbox_left", left)));
                top = min(top, real(scr_tune_instance_get(field_inst, "bbox_top", top)));
                right = max(right, real(scr_tune_instance_get(field_inst, "bbox_right", right)));
                bottom = max(bottom, real(scr_tune_instance_get(field_inst, "bbox_bottom", bottom)));
            }

            for (var ci = 0; ci < array_length(legacy_checks); ci++) {
                var check_inst = legacy_checks[ci];
                if (!instance_exists(check_inst)) continue;
                left = min(left, real(scr_tune_instance_get(check_inst, "bbox_left", left)));
                top = min(top, real(scr_tune_instance_get(check_inst, "bbox_top", top)));
                right = max(right, real(scr_tune_instance_get(check_inst, "bbox_right", right)));
                bottom = max(bottom, real(scr_tune_instance_get(check_inst, "bbox_bottom", bottom)));
            }
        }

        for (var fhide = 0; fhide < array_length(legacy_fields); fhide++) {
            var hide_field = legacy_fields[fhide];
            if (!instance_exists(hide_field)) continue;
            with (hide_field) {
                visible = false;
                field_script_index = -1;
            }
        }

        for (var chide = 0; chide < array_length(legacy_checks); chide++) {
            var hide_check = legacy_checks[chide];
            if (!instance_exists(hide_check)) continue;
            with (hide_check) {
                visible = false;
                button_script_index = -1;
                button_checked = 0;
                image_index = 0;
            }
        }
    }

    if (right <= left || bottom <= top) {
        var fallback_bounds = scr_tune_picker_get_canvas_fallback_bounds(tune_layer, !use_legacy_bounds);
        if (is_struct(fallback_bounds)) {
            left = real(scr_tune_struct_get(fallback_bounds, "x1", left));
            top = real(scr_tune_struct_get(fallback_bounds, "y1", top));
            right = real(scr_tune_struct_get(fallback_bounds, "x2", right));
            bottom = real(scr_tune_struct_get(fallback_bounds, "y2", bottom));
        }
    }

    if (right <= left || bottom <= top) {
        scr_tune_picker_set_instance_var(picker, "view_layout", undefined);
        return false;
    }

    var bounds = scr_tune_picker_make_rect(left, top, right, bottom);
    var pad = 8;
    var control_scale = 0.58;
    var info_scale = 0.50;
    var title_scale = 0.87;
    var meta_scale = 0.75;

    draw_set_font(fnt_button);
    var control_text_h = ceil(string_height("Ag") * control_scale);
    draw_set_font(fnt_setting);
    var title_text_h = ceil(string_height("Ag") * title_scale);
    draw_set_font(fnt_measure);
    var meta_text_h = ceil(string_height("Ag") * meta_scale);

    var row_pad_top = 6;
    var row_line_gap = 0;
    var row_pad_bottom = 6;

    var control_h = max(40, control_text_h + 14);
    var control_gap = 10;
    var row_h = max(56, row_pad_top + max(title_text_h, meta_text_h) + row_pad_bottom);
    var row_gap = 6;
    var arrow_w = 24;
    var sort_w = clamp(floor(bounds.w * 0.20), 140, 200);
    var filter_value_w = clamp(floor(bounds.w * 0.38), 170, 330);
    var row_split_ratio = 0.50;
    var meta_column_ratios = [0.25, 0.11, 0.12, 0.20, 0.10, 0.22];

    var controls_y1 = bounds.y1 + 2;
    var controls_y2 = controls_y1 + control_h;
    var filter_prev_rect = scr_tune_picker_make_rect(bounds.x1 + pad, controls_y1, bounds.x1 + pad + arrow_w, controls_y2);
    var filter_value_rect = scr_tune_picker_make_rect(filter_prev_rect.x2 + 4, controls_y1, filter_prev_rect.x2 + 4 + filter_value_w, controls_y2);
    var filter_next_rect = scr_tune_picker_make_rect(filter_value_rect.x2 + 4, controls_y1, filter_value_rect.x2 + 4 + arrow_w, controls_y2);
    var sort_rect = scr_tune_picker_make_rect(bounds.x2 - pad - sort_w, controls_y1, bounds.x2 - pad, controls_y2);
    var info_rect = scr_tune_picker_make_rect(filter_next_rect.x2 + 8, controls_y1, sort_rect.x1 - 8, controls_y2);

    var list_rect = scr_tune_picker_make_rect(bounds.x1 + pad, controls_y2 + control_gap, bounds.x2 - pad, bounds.y2 - 4);
    var scrollbar_rect = scr_tune_picker_make_rect(list_rect.x2 - 14, list_rect.y1, list_rect.x2, list_rect.y2);
    var rows_rect = scr_tune_picker_make_rect(list_rect.x1, list_rect.y1, scrollbar_rect.x1 - 6, list_rect.y2);

    var visible_rows = max(1, floor((rows_rect.h + row_gap) / (row_h + row_gap)));
    scr_tune_picker_set_instance_var(picker, "view_row_height", row_h);
    scr_tune_picker_set_instance_var(picker, "view_row_gap", row_gap);
    scr_tune_picker_set_instance_var(picker, "view_visible_rows", visible_rows);
    scr_tune_picker_set_instance_var(picker, "view_layout", {
        bounds: bounds,
        filter_prev_rect: filter_prev_rect,
        filter_value_rect: filter_value_rect,
        filter_next_rect: filter_next_rect,
        sort_rect: sort_rect,
        info_rect: info_rect,
        list_rect: list_rect,
        rows_rect: rows_rect,
        scrollbar_rect: scrollbar_rect,
        control_scale: control_scale,
        info_scale: info_scale,
        title_scale: title_scale,
        meta_scale: meta_scale,
        title_text_h: title_text_h,
        meta_text_h: meta_text_h,
        row_pad_top: row_pad_top,
        row_line_gap: row_line_gap,
        row_pad_bottom: row_pad_bottom,
        row_split_ratio: row_split_ratio,
        meta_column_ratios: meta_column_ratios,
        row_height: row_h,
        row_gap: row_gap,
        visible_rows: visible_rows
    });

    return true;
}

function scr_tune_picker_draw_box(_rect, _sprite, _hovered = false, _selected = false, _outline = true)
{
    if (!is_struct(_rect) || _rect.w <= 0 || _rect.h <= 0) return;

    var border_col = make_color_rgb(122, 125, 127);
    var border_alpha = (160 / 255);
    var selection_col = make_color_rgb(124, 197, 118);

    draw_set_alpha(1);
    draw_set_color(c_white);

    if (!is_undefined(_sprite) && _sprite != noone) {
        draw_sprite_stretched(_sprite, 0, _rect.x1, _rect.y1, _rect.w, _rect.h);
    } else {
        // Custom fill scales cleanly for two-line rows unlike 1-line sprite assets.
        draw_set_alpha(0.92);
        draw_set_color(make_color_rgb(39, 44, 56));
        draw_rectangle(_rect.x1, _rect.y1, _rect.x2, _rect.y2, false);
        draw_set_alpha(1);
        draw_set_color(c_white);
    }

    if (_selected) {
        draw_set_alpha(0.16);
        draw_set_color(selection_col);
        draw_rectangle(_rect.x1, _rect.y1, _rect.x2, _rect.y2, false);
    }
    else if (_hovered) {
        draw_set_alpha(0.10);
        draw_set_color(border_col);
        draw_rectangle(_rect.x1, _rect.y1, _rect.x2, _rect.y2, false);
    }

    if (_outline) {
        draw_set_alpha(border_alpha);
        draw_set_color(border_col);
        draw_rectangle(_rect.x1, _rect.y1, _rect.x2, _rect.y2, true);
        draw_set_alpha(1);
    }

    draw_set_color(c_white);
}

function scr_tune_picker_draw_center_text(_rect, _text, _font, _colour, _scale = 1)
{
    if (!is_struct(_rect)) return;

    var scale = max(real(_scale), 0.05);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_font(_font);
    draw_set_color(_colour);

    var label = string(_text ?? "");
    var tw = string_width(label) * scale;
    var th = string_height(label) * scale;
    var tx = _rect.x1 + max(4, floor((_rect.w - tw) * 0.5));
    var ty = _rect.y1 + max(3, floor((_rect.h - th) * 0.5));
    scr_tune_picker_draw_text_scaled(tx, ty, label, scale, scale);
    draw_set_color(c_white);
}

function scr_tune_picker_is_pointer_over_list(_x, _y)
{
    var picker = instance_find(obj_tune_picker, 0);
    var layout = scr_tune_picker_get_instance_var(picker, "view_layout", undefined);
    if (picker == noone || !is_struct(layout)) return false;

    var rows_rect = scr_tune_struct_get(layout, "rows_rect", undefined);
    var scrollbar_rect = scr_tune_struct_get(layout, "scrollbar_rect", undefined);

    return scr_tune_picker_rect_contains(rows_rect, _x, _y)
        || scr_tune_picker_rect_contains(scrollbar_rect, _x, _y);
}

function scr_tune_picker_handle_click(_gui_x, _gui_y)
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var layout = scr_tune_picker_get_instance_var(picker, "view_layout", undefined);
    if (!is_struct(layout)) {
        if (!scr_tune_picker_refresh_visible_rows()) return false;
        layout = scr_tune_picker_get_instance_var(picker, "view_layout", undefined);
    }
    if (!is_struct(layout)) return false;

    var filter_prev_rect = scr_tune_struct_get(layout, "filter_prev_rect", undefined);
    var filter_value_rect = scr_tune_struct_get(layout, "filter_value_rect", undefined);
    var filter_next_rect = scr_tune_struct_get(layout, "filter_next_rect", undefined);
    var sort_rect = scr_tune_struct_get(layout, "sort_rect", undefined);
    var scrollbar_rect = scr_tune_struct_get(layout, "scrollbar_rect", undefined);
    var rows_rect = scr_tune_struct_get(layout, "rows_rect", undefined);
    var bounds = scr_tune_struct_get(layout, "bounds", undefined);
    var row_height = real(scr_tune_struct_get(layout, "row_height", 0));
    var row_gap = real(scr_tune_struct_get(layout, "row_gap", 0));
    var layout_visible_rows = floor(real(scr_tune_struct_get(layout, "visible_rows", 1)));

    if (scr_tune_picker_rect_contains(filter_prev_rect, _gui_x, _gui_y)) {
        scr_tune_picker_cycle_filter_rhythm(-1);
        return true;
    }

    if (scr_tune_picker_rect_contains(filter_value_rect, _gui_x, _gui_y)
        || scr_tune_picker_rect_contains(filter_next_rect, _gui_x, _gui_y)) {
        scr_tune_picker_cycle_filter_rhythm(1);
        return true;
    }

    if (scr_tune_picker_rect_contains(sort_rect, _gui_x, _gui_y)) {
        scr_tune_picker_cycle_sort_mode(1);
        return true;
    }

    if (scr_tune_picker_rect_contains(scrollbar_rect, _gui_x, _gui_y)) {
        var filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", []);
        var total = array_length(filtered_indices);
        var visible_rows = max(1, floor(real(scr_tune_picker_get_instance_var(picker, "view_visible_rows", 1))));
        var max_scroll = max(total - visible_rows, 0);

        if (max_scroll > 0) {
            var scrollbar_h = real(scr_tune_struct_get(scrollbar_rect, "h", 0));
            var scrollbar_y1 = real(scr_tune_struct_get(scrollbar_rect, "y1", 0));
            var handle_h = max(24, floor((scrollbar_h * visible_rows) / max(total, 1)));
            handle_h = min(handle_h, scrollbar_h);

            var handle_y = scrollbar_y1;
            if (scrollbar_h > handle_h) {
                handle_y += floor((scrollbar_h - handle_h) * (real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0)) / max_scroll));
            }

            if (_gui_y < handle_y) scr_tune_picker_scroll_rows(-visible_rows);
            else if (_gui_y > handle_y + handle_h) scr_tune_picker_scroll_rows(visible_rows);
            scr_tune_picker_refresh_visible_rows();
        }

        return true;
    }

    if (scr_tune_picker_rect_contains(rows_rect, _gui_x, _gui_y)) {
        var row_stride = row_height + row_gap;
        var local_y = _gui_y - real(scr_tune_struct_get(rows_rect, "y1", 0));
        var row_idx = floor(local_y / row_stride);

        if (row_idx >= 0 && row_idx < layout_visible_rows) {
            var row_top = real(scr_tune_struct_get(rows_rect, "y1", 0)) + (row_idx * row_stride);
            if (_gui_y <= row_top + row_height) {
                var source_idx = scr_tune_picker_get_visible_source_index(row_idx);
                if (source_idx >= 0) {
                    scr_tune_picker_activate_index(source_idx);
                    return true;
                }
            }
        }

        return true;
    }

    return scr_tune_picker_rect_contains(bounds, _gui_x, _gui_y);
}

function scr_tune_picker_draw_canvas()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var tune_layer_id = layer_get_id("tune_window_layer");
    if (tune_layer_id == -1 || !layer_get_visible(tune_layer_id)) return false;

    var layout = scr_tune_picker_get_instance_var(picker, "view_layout", undefined);
    if (!is_struct(layout)) {
        if (!scr_tune_picker_refresh_visible_rows()) return false;
        layout = scr_tune_picker_get_instance_var(picker, "view_layout", undefined);
    }
    if (!is_struct(layout)) return false;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) return false;

    var filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", undefined);
    if (!is_array(filtered_indices)) {
        scr_tune_picker_rebuild_view_model();
        filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", []);
    }

    var filter_prev_rect = scr_tune_struct_get(layout, "filter_prev_rect", undefined);
    var filter_value_rect = scr_tune_struct_get(layout, "filter_value_rect", undefined);
    var filter_next_rect = scr_tune_struct_get(layout, "filter_next_rect", undefined);
    var sort_rect = scr_tune_struct_get(layout, "sort_rect", undefined);
    var info_rect = scr_tune_struct_get(layout, "info_rect", undefined);
    var rows_rect = scr_tune_struct_get(layout, "rows_rect", undefined);
    var scrollbar_rect = scr_tune_struct_get(layout, "scrollbar_rect", undefined);
    var row_height = real(scr_tune_struct_get(layout, "row_height", 56));
    var row_gap = real(scr_tune_struct_get(layout, "row_gap", 6));
    var layout_visible_rows = floor(real(scr_tune_struct_get(layout, "visible_rows", 1)));

    var gui_x = scr_tune_picker_get_mouse_gui_x();
    var gui_y = scr_tune_picker_get_mouse_gui_y();
    var filter_key = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_filter_rhythm", "all"))));
    var sort_mode = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "view_sort_mode", "title_asc"))));
    var selected_id = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "selected_tune_id", ""))));
    var total_visible = array_length(filtered_indices);
    var total_tunes = array_length(tunes);
    var visible_rows = max(1, floor(real(scr_tune_picker_get_instance_var(picker, "view_visible_rows", layout_visible_rows))));
    var scroll_offset = max(0, floor(real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0))));
    var control_scale = real(scr_tune_struct_get(layout, "control_scale", 0.58));
    var info_scale = real(scr_tune_struct_get(layout, "info_scale", 0.50));
    var title_scale = real(scr_tune_struct_get(layout, "title_scale", 0.87));
    var meta_scale = real(scr_tune_struct_get(layout, "meta_scale", 0.75));
    var row_pad_top = real(scr_tune_struct_get(layout, "row_pad_top", 7));
    var row_line_gap = real(scr_tune_struct_get(layout, "row_line_gap", 4));
    var row_pad_bottom = real(scr_tune_struct_get(layout, "row_pad_bottom", 7));
    var row_split_ratio = real(scr_tune_struct_get(layout, "row_split_ratio", 0.50));
    var meta_column_ratios = scr_tune_struct_get(layout, "meta_column_ratios", [0.25, 0.11, 0.12, 0.20, 0.10, 0.22]);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    var filter_prev_hover = scr_tune_picker_rect_contains(filter_prev_rect, gui_x, gui_y);
    var filter_value_hover = scr_tune_picker_rect_contains(filter_value_rect, gui_x, gui_y);
    var filter_next_hover = scr_tune_picker_rect_contains(filter_next_rect, gui_x, gui_y);
    var sort_hover = scr_tune_picker_rect_contains(sort_rect, gui_x, gui_y);

    scr_tune_picker_draw_box(filter_prev_rect, spr_cell_dark, filter_prev_hover, false);
    scr_tune_picker_draw_box(filter_value_rect, spr_cell_dark, filter_value_hover, filter_key != "all");
    scr_tune_picker_draw_box(filter_next_rect, spr_cell_dark, filter_next_hover, false);
    scr_tune_picker_draw_box(sort_rect, spr_cell_dark, sort_hover, false);

    scr_tune_picker_draw_center_text(filter_prev_rect, "<", fnt_button, c_white, control_scale);
    scr_tune_picker_draw_center_text(filter_next_rect, ">", fnt_button, c_white, control_scale);

    var filter_label = "Rhythm: " + scr_tune_picker_get_rhythm_label(filter_key);
    draw_set_font(fnt_button);
    filter_label = scr_tune_picker_fit_text_scaled(filter_label, real(scr_tune_struct_get(filter_value_rect, "w", 0)) - 12, control_scale);
    scr_tune_picker_draw_center_text(filter_value_rect, filter_label, fnt_button, c_ltgray, control_scale);

    var sort_label = scr_tune_picker_fit_text_scaled(scr_tune_picker_get_sort_mode_label(sort_mode), real(scr_tune_struct_get(sort_rect, "w", 0)) - 12, control_scale);
    scr_tune_picker_draw_center_text(sort_rect, sort_label, fnt_button, c_ltgray, control_scale);

    var start_display = (total_visible > 0) ? (scroll_offset + 1) : 0;
    var end_display = min(scroll_offset + visible_rows, total_visible);
    var info_text = string(start_display) + "-" + string(end_display) + " of " + string(total_visible);
    if (total_visible != total_tunes) {
        info_text += " filtered";
    }

    var selected_entry = scr_tune_picker_get_selected_entry();
    if (is_struct(selected_entry)) {
        info_text += " | " + scr_tune_picker_get_tune_title(selected_entry);
		var selected_part_label = scr_tune_picker_get_part_label(selected_entry, scr_tune_picker_get_selected_part_channel());
		if (string_length(selected_part_label) > 0) {
			info_text += " | " + selected_part_label;
		}
    }

    draw_set_font(fnt_button);
    draw_set_color(c_ltgray);
    info_text = scr_tune_picker_fit_text_scaled(info_text, real(scr_tune_struct_get(info_rect, "w", 0)) - 4, info_scale);
    scr_tune_picker_draw_text_scaled(real(scr_tune_struct_get(info_rect, "x1", 0)) + 2, real(scr_tune_struct_get(info_rect, "y1", 0)) + 7, info_text, info_scale, info_scale);

    if (total_visible <= 0) {
        draw_set_font(fnt_setting);
        draw_set_color(c_ltgray);
        var empty_text = "No tunes match this rhythm filter.";
        var empty_scale = 0.40;
        var empty_w = string_width(empty_text) * empty_scale;
        var empty_h = string_height(empty_text) * empty_scale;
        var empty_x = real(scr_tune_struct_get(rows_rect, "x1", 0)) + max(8, floor((real(scr_tune_struct_get(rows_rect, "w", 0)) - empty_w) * 0.5));
        var empty_y = real(scr_tune_struct_get(rows_rect, "y1", 0)) + max(12, floor((real(scr_tune_struct_get(rows_rect, "h", 0)) - empty_h) * 0.5));
        scr_tune_picker_draw_text_scaled(empty_x, empty_y, empty_text, empty_scale, empty_scale);
        draw_set_color(c_white);
        return true;
    }

    var row_stride = row_height + row_gap;
    var row_x_pad = 10;

    for (var row = 0; row < visible_rows; row++) {
        var source_idx = scr_tune_picker_get_visible_source_index(row);
        if (source_idx < 0 || source_idx >= total_tunes) break;

        var rows_x1 = real(scr_tune_struct_get(rows_rect, "x1", 0));
        var rows_x2 = real(scr_tune_struct_get(rows_rect, "x2", 0));
        var rows_y1 = real(scr_tune_struct_get(rows_rect, "y1", 0));
        var row_y1 = rows_y1 + (row * row_stride);
        var row_rect = scr_tune_picker_make_rect(rows_x1, row_y1, rows_x2, row_y1 + row_height);
        var hovered = scr_tune_picker_rect_contains(row_rect, gui_x, gui_y);
        var entry = tunes[source_idx];
        var tune_id = scr_tune_picker_get_tune_id(entry);
        var is_selected = (string_length(selected_id) > 0 && tune_id == selected_id);

        scr_tune_picker_draw_box(row_rect, noone, hovered, is_selected, true);

        if (is_selected) {
            draw_set_alpha(1);
            draw_set_color(make_color_rgb(124, 197, 118));
            draw_rectangle(row_rect.x1 + 4, row_rect.y1 + 4, row_rect.x1 + 8, row_rect.y2 - 4, false);
            draw_set_color(c_white);
        }

        var inner_left = row_rect.x1 + row_x_pad;
        var inner_right = row_rect.x2 - row_x_pad;
        var split_x = inner_left + floor((inner_right - inner_left) * row_split_ratio);
        var title_left = inner_left;
        var title_right = max(title_left + 40, split_x - 8);
        var meta_left = min(inner_right - 40, split_x + 8);
        var meta_right = inner_right;

        var title_h = max(1, floor(string_height("Ag") * title_scale));
        var meta_h = max(1, floor(string_height("Ag") * meta_scale));
        var line_h = max(title_h, meta_h);
        var line_y = row_rect.y1 + max(row_pad_top, floor((row_rect.h - line_h) * 0.5));
        var title_line_y = line_y + floor((line_h - title_h) * 0.5);
        var meta_line_y = line_y + floor((line_h - meta_h) * 0.5);

        draw_set_font(fnt_setting);
        draw_set_color(c_white);
        var title_width = max(20, title_right - title_left);
        var title_text = scr_tune_picker_fit_text_scaled(scr_tune_picker_get_tune_title(entry), title_width, title_scale);
        scr_tune_picker_draw_text_scaled(title_left, title_line_y, title_text, title_scale, title_scale);

        // Right half reserves fixed columns for future tune stats fields.
        draw_set_font(fnt_measure);
        draw_set_color(make_color_rgb(162, 168, 178));

        var part_label = is_selected
            ? scr_tune_picker_get_part_label(entry, scr_tune_picker_get_selected_part_channel())
            : "";
        var meta_cells = scr_tune_picker_get_tune_meta_cells(entry, part_label);
        var col_x = meta_left;
        var divider_col = make_color_rgb(122, 125, 127);
        draw_set_alpha(160 / 255);
        for (var ci = 0; ci < array_length(meta_column_ratios) && ci < array_length(meta_cells); ci++) {
            var ratio = real(meta_column_ratios[ci]);
            var col_w = floor((meta_right - meta_left) * ratio);
            var col_x2 = (ci == array_length(meta_column_ratios) - 1) ? meta_right : min(meta_right, col_x + col_w);

            if (ci > 0) {
                draw_set_color(divider_col);
                draw_line(col_x, row_rect.y1 + 6, col_x, row_rect.y2 - 6);
            }

            draw_set_alpha(1);
            draw_set_color(make_color_rgb(162, 168, 178));
            var cell_pad = 4;
            var cell_text_max = max(10, (col_x2 - col_x) - (cell_pad * 2));
            var cell_text = scr_tune_picker_fit_text_scaled(meta_cells[ci], cell_text_max, meta_scale);
            scr_tune_picker_draw_text_scaled(col_x + cell_pad, meta_line_y, cell_text, meta_scale, meta_scale);

            draw_set_alpha(160 / 255);
            col_x = col_x2;
        }
        draw_set_alpha(1);
    }

    scr_tune_picker_draw_box(scrollbar_rect, spr_cell_dark, scr_tune_picker_rect_contains(scrollbar_rect, gui_x, gui_y), false);

    var max_scroll = max(total_visible - visible_rows, 0);
    if (max_scroll > 0) {
        var scrollbar_h = real(scr_tune_struct_get(scrollbar_rect, "h", 0));
        var scrollbar_y1 = real(scr_tune_struct_get(scrollbar_rect, "y1", 0));
        var scrollbar_x1 = real(scr_tune_struct_get(scrollbar_rect, "x1", 0));
        var scrollbar_x2 = real(scr_tune_struct_get(scrollbar_rect, "x2", 0));
        var handle_h = max(24, floor((scrollbar_h * visible_rows) / total_visible));
        handle_h = min(handle_h, scrollbar_h);
        var handle_y = scrollbar_y1;
        if (scrollbar_h > handle_h) {
            handle_y += floor((scrollbar_h - handle_h) * (scroll_offset / max_scroll));
        }

        var handle_rect = scr_tune_picker_make_rect(scrollbar_x1 + 2, handle_y, scrollbar_x2 - 2, handle_y + handle_h);
        scr_tune_picker_draw_box(handle_rect, spr_cell_dark, scr_tune_picker_rect_contains(handle_rect, gui_x, gui_y), false, true);
    }

    draw_set_color(c_white);
    draw_set_alpha(1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    return true;
}

function scr_tune_picker_refresh_visible_rows()
{
    var picker = instance_find(obj_tune_picker, 0);
    if (picker == noone) return false;

    var library = scr_tune_picker_get_library(picker);
    var tunes = scr_tune_library_get_tunes(library);
    if (!is_array(tunes)) {
        return false;
    }

    var has_custom_canvas = scr_tune_picker_update_canvas_layout();
    scr_tune_picker_rebuild_view_model();

    if (has_custom_canvas) {
        return true;
    }

    // Find field and checkbox instances belonging to the tune window layer
    var fields = array_create(0);
    var checks = array_create(0);

    // Maps to pair fields and checkboxes: keyed by field_ID/button_ID (preferred), then ui_num (fallback)
    var field_map = {};
    var check_map = {};

    // Determine tune window layer index (if available)
    var tune_layer = -1;
    if (is_undefined(GetLayerIndexFromName) == false) tune_layer = GetLayerIndexFromName("tune_window_layer");

    // Collect fields
    var field_count = instance_number(obj_field_base);
    for (var fi = 0; fi < field_count; fi++) {
        var field_inst = instance_find(obj_field_base, fi);
        if (field_inst == noone) continue;

        var field_ui_name = string(scr_tune_instance_get(field_inst, "ui_name", ""));
        var field_ui_layer = real(scr_tune_instance_get(field_inst, "ui_layer_num", -1));
        if (field_ui_name != "" && string_pos("obj_tune_field_", field_ui_name) == 1) {
            if (tune_layer < 0 || field_ui_layer == tune_layer) {
                array_push(fields, field_inst);

                var field_id_raw = scr_tune_instance_get(field_inst, "field_ID", undefined);
                if (!is_undefined(field_id_raw)) {
                    var fk = string(field_id_raw);
                    if (is_undefined(field_map[$ fk])) {
                        field_map[$ fk] = field_inst;
                    } else {
                        show_debug_message("Warning: duplicate field_ID in tune picker: " + fk);
                    }
                }
                else {
                    var ui_num_raw = scr_tune_instance_get(field_inst, "ui_num", undefined);
                    if (!is_undefined(ui_num_raw)) {
                        var uk = string(ui_num_raw);
                        if (is_undefined(field_map[$ uk])) {
                            field_map[$ uk] = field_inst;
                        } else {
                            show_debug_message("Warning: duplicate ui_num for fields: " + uk);
                        }
                    }
                }
            }
        }
    }

    // Collect checkbox buttons
    var check_count = instance_number(obj_btn_check);
    for (var ci = 0; ci < check_count; ci++) {
        var check_inst = instance_find(obj_btn_check, ci);
        if (check_inst == noone) continue;

        var check_ui_name = string(scr_tune_instance_get(check_inst, "ui_name", ""));
        var check_ui_layer = real(scr_tune_instance_get(check_inst, "ui_layer_num", -1));
        if (check_ui_name != "" && string_pos("obj_tune_checkbox_", check_ui_name) == 1) {
            if (tune_layer < 0 || check_ui_layer == tune_layer) {
                array_push(checks, check_inst);

                var button_id_raw = scr_tune_instance_get(check_inst, "button_ID", undefined);
                if (!is_undefined(button_id_raw)) {
                    var bk = string(button_id_raw);
                    if (is_undefined(check_map[$ bk])) {
                        check_map[$ bk] = check_inst;
                    } else {
                        show_debug_message("Warning: duplicate button_ID in tune picker: " + bk);
                    }
                }
                else {
                    var ui_num_raw2 = scr_tune_instance_get(check_inst, "ui_num", undefined);
                    if (!is_undefined(ui_num_raw2)) {
                        var uk2 = string(ui_num_raw2);
                        if (is_undefined(check_map[$ uk2])) {
                            check_map[$ uk2] = check_inst;
                        } else {
                            show_debug_message("Warning: duplicate ui_num for checks: " + uk2);
                        }
                    }
                }
            }
        }
    }

    // Sort by y-position so row 1 is top (fallback for un-keyed rows)
    array_sort(fields, function(a, b) {
        return real(scr_tune_instance_get(a, "y", 0)) - real(scr_tune_instance_get(b, "y", 0));
    });
    array_sort(checks, function(a, b) {
        return real(scr_tune_instance_get(a, "y", 0)) - real(scr_tune_instance_get(b, "y", 0));
    });

    scr_tune_picker_set_instance_var(picker, "view_visible_rows", max(1, max(array_length(fields), array_length(checks))));
    scr_tune_picker_rebuild_view_model();

    var selected_tune_id = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "selected_tune_id", ""))));

    var filtered_indices = array_create(0);
    var scroll_offset = 0;
    var picker_filtered_indices = scr_tune_picker_get_instance_var(picker, "view_filtered_indices", undefined);
    if (is_array(picker_filtered_indices)) {
        filtered_indices = picker_filtered_indices;
        scroll_offset = max(0, floor(real(scr_tune_picker_get_instance_var(picker, "view_scroll_offset", 0))));
    } else {
        for (var fi = 0; fi < array_length(tunes); fi++) {
            array_push(filtered_indices, fi);
        }
    }

    var max_rows = max(array_length(fields), array_length(checks));

    // Populate rows using explicit ui_num mapping when available; otherwise fallback to positional pairing
    for (var i = 0; i < max_rows; i++)
    {
        var row_key = string(i + 1); // ui_num expected to be 1-based
        var f = (!is_undefined(field_map[$ row_key])) ? field_map[$ row_key] : (i < array_length(fields) ? fields[i] : noone);
        var c = (!is_undefined(check_map[$ row_key])) ? check_map[$ row_key] : (i < array_length(checks) ? checks[i] : noone);

        var source_idx = -1;
        var source_pos = scroll_offset + i;
        if (source_pos >= 0 && source_pos < array_length(filtered_indices)) {
            source_idx = floor(real(filtered_indices[source_pos]));
        }

        if (source_idx >= 0 && source_idx < array_length(tunes))
        {
            var t = tunes[source_idx];
            var tune_id = scr_tune_picker_get_tune_id(t);
            var row_selected = (string_length(selected_tune_id) > 0 && tune_id == selected_tune_id);

            if (f != noone) {
                with (f) {
                    field_contents = scr_tune_picker_get_tune_title(t);
                    field_value = source_idx;
                    visible = true;
                }
            }

            if (c != noone) {
                with (c) {
                    tune_filename = variable_struct_exists(t, "filename") ? string(variable_struct_get(t, "filename")) : ""; // attach metadata for debugging
                    button_click_value = source_idx;
                    button_checked = row_selected ? 1 : 0;
                    image_index = row_selected ? 3 : 0;
                    visible = true;
                }
            }
        }
        else
        {
            if (f != noone) with (f) { visible = false; }
            if (c != noone) with (c) { button_checked = 0; image_index = 0; visible = false; }
        }
    }

    return true;
}

function scr_tune_picker_populate()
{
    var library = scr_load_tune_library();
    var library_tunes = scr_tune_library_get_tunes(library);

    // Store globally so OK button can access it
    global.tune_library = library;

    // Also attach the library to the picker instance and reset selection
    var picker = instance_find(obj_tune_picker, 0);
    var previous_selected_id = "";
    if (picker != noone)
    {
        previous_selected_id = string_lower(string_trim(string(scr_tune_picker_get_instance_var(picker, "selected_tune_id", ""))));
        var previous_selected_part_channel = floor(real(scr_tune_picker_get_instance_var(picker, "selected_part_channel", -1)));

        if (string_length(previous_selected_id) <= 0
            && is_array(scr_tune_library_get_tunes(scr_tune_picker_get_library(picker)))) {
            var old_tunes = scr_tune_library_get_tunes(scr_tune_picker_get_library(picker));
            var old_idx = floor(real(scr_tune_picker_get_instance_var(picker, "selected_index", -1)));
            if (old_idx >= 0 && old_idx < array_length(old_tunes)) {
                previous_selected_id = scr_tune_picker_get_tune_id(old_tunes[old_idx]);
            }
        }

        scr_tune_picker_set_instance_var(picker, "library", library);
        scr_tune_picker_set_instance_var(picker, "selected_index", -1);
        scr_tune_picker_set_instance_var(picker, "selected_tune_id", "");
        scr_tune_picker_set_instance_var(picker, "selected_tune_filename", "");
        scr_tune_picker_set_instance_var(picker, "selected_part_channel", -1);
    }

    if (picker != noone && string_length(previous_selected_id) > 0) {
        var restored = scr_tune_picker_set_selected_by_id(previous_selected_id);
        if (restored && previous_selected_part_channel >= 2) {
            var restored_entry = scr_tune_picker_get_selected_entry();
            if (is_struct(restored_entry)) {
                scr_tune_picker_set_selected_part_channel(restored_entry, previous_selected_part_channel);
            }
        }
    } else if (picker != noone && variable_global_exists("tune_selection") && global.tune_selection >= 0) {
        scr_tune_picker_set_selected_by_index(global.tune_selection);
    }

    if (picker != noone) {
        scr_tune_picker_sync_selected_entry_ui();
    }

    return scr_tune_picker_refresh_visible_rows();
}


// Helper: Recursively scan a folder and return an array of JSON file paths
function scr_tune_scan_dir(_folder)
{
    var found = array_create(0);

    // Ensure folder path ends with '/'
    if (string_copy(_folder, string_length(_folder), 1) != "/") _folder += "/";

    var search = _folder + "*";
    var entry = file_find_first(search, 0);

    if (entry != "") {
        while (entry != "") {
            show_debug_message("  found entry: " + entry + " | is_dir: " + string(directory_exists(_folder + entry)));
            if (string_copy(entry, 1, 1) == ".") {
                entry = file_find_next();
                continue;
            }

            var fp = _folder + entry;

            if (directory_exists(fp)) {
                show_debug_message("    -> is subdirectory, recursing");
                var sub = scr_tune_scan_dir(fp);
                for (var k = 0; k < array_length(sub); k++) array_push(found, sub[k]);
            }
            else {
                var ext = string_lower(string_copy(entry, string_length(entry) - 4, 5));
                if (ext == ".json" && entry != "tune_library.json") {
                    array_push(found, fp);
                }
            }

            entry = file_find_next();
        }
        file_find_close();
    }

    return found;
}


// Build a tune library JSON file by scanning a folder (and subfolders) for tune JSONs
// Example: scr_build_tune_library("tunes/");
function scr_build_tune_library(_root_folder)
{
    // Default folder if not provided
    if (is_undefined(_root_folder) || _root_folder == "") _root_folder = "tunes/";
    // Normalize folder path
    if (string_copy(_root_folder, string_length(_root_folder), 1) != "/") _root_folder += "/";
    var files = scr_tune_scan_dir(_root_folder);
    var tunes = array_create(0);
	show_debug_message(string(files));
    for (var i = 0; i < array_length(files); i++) {
        var fp = files[i];

        var f = file_text_open_read(fp);
        if (f < 0) {
            show_debug_message("WARNING: Could not open tune file: " + string(fp));
            continue;
        }

        var raw = "";
        while (!file_text_eof(f)) {
            raw += file_text_read_string(f);
            file_text_readln(f);
        }
        file_text_close(f);

        // Skip empty files
        if (raw == "" || string_trim(raw) == "") {
            show_debug_message("WARNING: Empty tune file: " + string(fp));
            continue;
        }

        var data = 0;
        try {
            data = json_parse(raw);
        } catch (e) {
            show_debug_message("WARNING: Invalid JSON in tune file: " + string(fp) + " - " + string(e));
            continue;
        }
        var meta = {};

        // Support multiple tune file formats:
        // - { "tune": { ... }, "events": [ ... ] }  (preferred)
        // - [ ... ]  (events array only)
        if (is_struct(data) && variable_struct_exists(data, "tune")) {
            meta = variable_struct_get(data, "tune");
        }
        else if (is_array(data)) {
            // Older / minimal files containing only events array: proceed with empty metadata
            meta = {};
        }
        else if (is_struct(data) && variable_struct_exists(data, "events")) {
            // Has events but no named tune object
            if (variable_struct_exists(data, "tune")) meta = variable_struct_get(data, "tune"); else meta = {};
        }
        else {
            show_debug_message("WARNING: Invalid tune JSON (not 'tune' or 'events'): " + string(fp));
            continue;
        }

        var entry = {};

        // Store filename relative to root folder (e.g. "ScotlandTheBrave.json" or "subdir/track.json")
        variable_struct_set(entry, "filename", string_replace(fp, _root_folder, ""));
        variable_struct_set(entry, "id", scr_tune_picker_get_tune_id(entry));

        // Preferred fields for display
        var entry_filename = string(scr_tune_struct_get(entry, "filename", ""));
        var meta_title = string(scr_tune_struct_get(meta, "title", ""));
        if (meta_title != "") variable_struct_set(entry, "title", meta_title); else variable_struct_set(entry, "title", string_replace(entry_filename, ".json", ""));
        variable_struct_set(entry, "composer", scr_tune_struct_get(meta, "composer", ""));
        variable_struct_set(entry, "rhythm", scr_tune_struct_get(meta, "rhythm", ""));
        var player_part_channels = scr_tune_picker_collect_player_part_channels(data);
        variable_struct_set(entry, "player_part_channels", player_part_channels);
        variable_struct_set(entry, "player_part_count", array_length(player_part_channels));
        
        // Add tempo and time signature for tune window
        variable_struct_set(entry, "tempo_default", scr_tune_struct_get(meta, "tempo_default", "120"));
        variable_struct_set(entry, "meter", scr_tune_struct_get(meta, "meter", "4/4"));

        array_push(tunes, entry);
    }

    // Sort by title (case-insensitive) — simple insertion sort for compatibility
    for (var i = 1; i < array_length(tunes); i++) {
        var key = tunes[i];
        var keyTitle = string_lower(string(scr_tune_struct_get(key, "title", "")));
        var j = i - 1;
        while (j >= 0 && string_lower(string(scr_tune_struct_get(tunes[j], "title", ""))) > keyTitle) {
            tunes[j + 1] = tunes[j];
            j -= 1;
        }
        tunes[j + 1] = key;
    }

    var library = { tunes: tunes, root: _root_folder };

    // Write out JSON
    var out = json_stringify(library);
    var out_file = _root_folder + "tune_library.json";
    var w = file_text_open_write(out_file);
    if (w < 0) {
        show_debug_message("ERROR: Could not open " + out_file + " for writing");
        return library;
    }

    file_text_write_string(w, out);
    file_text_close(w);

    show_debug_message("scr_build_tune_library: wrote " + out_file + " (" + string(array_length(tunes)) + " tunes)");

    return library;
}