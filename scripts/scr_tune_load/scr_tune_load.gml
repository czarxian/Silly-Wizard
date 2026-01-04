/// @function scr_tune_load_json(_filename)
/// @description Loads a tune JSON file and stores it in obj_tune.

function scr_tune_load_json(_filename)
{
    // Try to open the file
    var f = file_text_open_read(_filename);

    if (f < 0)
    {
        show_debug_message("ERROR: Could not open JSON file: " + string(_filename));
        return false;
    }

    // Read entire file into a string
    var raw = "";
    while (!file_text_eof(f))
    {
        raw += file_text_read_string(f);
        file_text_readln(f);
    }

    file_text_close(f);

    // Parse JSON
    var data = json_parse(raw);

    if (!is_struct(data))
    {
        show_debug_message("ERROR: JSON parse failed for: " + string(_filename));
        return false;
    }

    if (!variable_struct_exists(data, "tune") || !variable_struct_exists(data, "events"))
    {
        show_debug_message("ERROR: JSON missing tune or events fields.");
        return false;
    }

    // Store into obj_tune
    with (obj_tune)
    {
        tune_metadata = data.tune;
        events = data.events;
        event_count = array_length(events);
        is_loaded = true;
        filename = _filename;
    }

    show_debug_message("Tune loaded successfully: " + string(_filename));
    return true;
}




