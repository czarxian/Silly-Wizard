// scr_tune_library — Tune library loader & picker helper
// Purpose: Loads `tunes/tune_library.json` and populates UI rows for the tune picker.
// Key functions: scr_load_tune_library, scr_tune_picker_populate
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

                return data;
            }
            else
            {
                show_debug_message("ERROR: Tune library JSON invalid in " + string(p));
            }
        }
    }

    show_debug_message("ERROR: Could not load tune library.");
    return { tunes: [] };
}

function scr_tune_picker_populate()
{
    var library = scr_load_tune_library();

    // Store globally so OK button can access it
    global.tune_library = library;

    // Also attach the library to the picker instance and reset selection
    var picker = instance_find(obj_tune_picker, 0);
    if (picker != noone)
    {
        picker.library = library;
        picker.selected_index = -1;
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
    with (obj_field_base)
    {
        if (ui_name != "" && string_pos("obj_tune_field_", ui_name) == 1) {
            if (tune_layer < 0 || ui_layer_num == tune_layer) {
                array_push(fields, id);
                // Prefer explicit editor-assigned field_ID (designer-controlled)
                if (variable_instance_exists(id, "field_ID")) {
                    var fk = string(field_ID);
                    // Check if key already exists in struct by trying to access it
                    if (is_undefined(field_map[$ fk])) {
                        field_map[$ fk] = id;
                    } else {
                        show_debug_message("Warning: duplicate field_ID in tune picker: " + fk);
                    }
                }
                // Fallback to ui_num if no explicit field_ID
                else if (variable_instance_exists(id, "ui_num")) {
                    var uk = string(ui_num);
                    if (is_undefined(field_map[$ uk])) {
                        field_map[$ uk] = id;
                    } else {
                        show_debug_message("Warning: duplicate ui_num for fields: " + uk);
                    }
                }
            }
        }
    }

    // Collect checkbox buttons
    with (obj_btn_check)
    {
        if (ui_name != "" && string_pos("obj_tune_checkbox_", ui_name) == 1) {
            if (tune_layer < 0 || ui_layer_num == tune_layer) {
                array_push(checks, id);
                // Prefer explicit designer-assigned button_ID
                if (variable_instance_exists(id, "button_ID")) {
                    var bk = string(button_ID);
                    if (is_undefined(check_map[$ bk])) {
                        check_map[$ bk] = id;
                    } else {
                        show_debug_message("Warning: duplicate button_ID in tune picker: " + bk);
                    }
                }
                // Fallback to ui_num if no explicit button_ID
                else if (variable_instance_exists(id, "ui_num")) {
                    var uk2 = string(ui_num);
                    if (is_undefined(check_map[$ uk2])) {
                        check_map[$ uk2] = id;
                    } else {
                        show_debug_message("Warning: duplicate ui_num for checks: " + uk2);
                    }
                }
            }
        }
    }

    // Sort by y-position so row 1 is top (fallback for un-keyed rows)
    array_sort(fields, function(a, b) { return a.y - b.y; });
    array_sort(checks, function(a, b) { return a.y - b.y; });

    var max_rows = max(array_length(fields), array_length(checks));
    var row_count = max(array_length(library.tunes), max_rows);

    // Populate rows using explicit ui_num mapping when available; otherwise fallback to positional pairing
    for (var i = 0; i < row_count; i++)
    {
        var row_key = string(i + 1); // ui_num expected to be 1-based
        var f = (!is_undefined(field_map[$ row_key])) ? field_map[$ row_key] : (i < array_length(fields) ? fields[i] : noone);
        var c = (!is_undefined(check_map[$ row_key])) ? check_map[$ row_key] : (i < array_length(checks) ? checks[i] : noone);

        if (i < array_length(library.tunes))
        {
            var t = library.tunes[i];

            if (f != noone) {
                with (f) {
                    field_contents = t.title;
                    field_value = i; // optional
                    visible = true;
                }
            }

            if (c != noone) {
                with (c) {
                    tune_filename = t.filename; // attach metadata for debugging
                    button_click_value = i;
                    button_checked = 0;
                    image_index = 0;
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
            meta = data.tune;
        }
        else if (is_array(data)) {
            // Older / minimal files containing only events array: proceed with empty metadata
            meta = {};
        }
        else if (is_struct(data) && variable_struct_exists(data, "events")) {
            // Has events but no named tune object
            if (variable_struct_exists(data, "tune")) meta = data.tune; else meta = {};
        }
        else {
            show_debug_message("WARNING: Invalid tune JSON (not 'tune' or 'events'): " + string(fp));
            continue;
        }

        var entry = {};

        // Store filename relative to root folder (e.g. "ScotlandTheBrave.json" or "subdir/track.json")
        entry.filename = string_replace(fp, _root_folder, "");

        // Preferred fields for display
        if (variable_struct_exists(meta, "title") && meta.title != "") entry.title = meta.title; else entry.title = string_replace(entry.filename, ".json", "");
        entry.composer = variable_struct_exists(meta, "composer") ? meta.composer : "";
        entry.rhythm = variable_struct_exists(meta, "rhythm") ? meta.rhythm : "";

        array_push(tunes, entry);
    }

    // Sort by title (case-insensitive) — simple insertion sort for compatibility
    for (var i = 1; i < array_length(tunes); i++) {
        var key = tunes[i];
        var keyTitle = string_lower(key.title);
        var j = i - 1;
        while (j >= 0 && string_lower(tunes[j].title) > keyTitle) {
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