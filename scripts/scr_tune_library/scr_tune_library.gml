// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function scr_load_tune_library()
{
    var raw = string_load("tunes/tune_library.json");

    if (raw == "")
    {
        show_debug_message("ERROR: Could not load tune library.");
        return { tunes: [] };
    }

    var data = json_parse(raw);

    if (!is_struct(data))
    {
        show_debug_message("ERROR: Tune library JSON invalid.");
        return { tunes: [] };
    }

    return data;
}

function scr_tune_picker_populate()
{
    var library = scr_load_tune_library();

    // Store globally so OK button can access it
    global.tune_library = library;

    // Get all row instances on the tune window layer
    var rows = array_create(0);

    with (obj_tune_row)
    {
        array_push(rows, id);
    }

    // Sort rows by y-position so row 1 is top
    array_sort(rows, function(a, b) { return a.y - b.y; });

    // Populate up to 6 rows
    for (var i = 0; i < array_length(rows); i++)
    {
        var row = rows[i];

        if (i < array_length(library.tunes))
        {
            var t = library.tunes[i];

            row.visible = true;
            row.tune_filename = t.filename;
            row.tune_title = t.title;

            // Update the text field inside the row
            with (row.field_instance)
            {
                text = t.title;
            }
        }
        else
        {
            // Hide unused rows
            row.visible = false;
        }
    }
}