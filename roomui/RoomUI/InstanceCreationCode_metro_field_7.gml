// Initialize gracenote override field (ms)
var default_ms = global.EMBELLISHMENT_CONFIG.gracenote_unit_ms_base;
var override_ms = 0;
if (variable_global_exists("gracenote_override_ms") && global.gracenote_override_ms > 0) {
    override_ms = global.gracenote_override_ms;
}
if (is_array(global.current_set)) {
    var idx = global.current_set_item_index;
    if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
        var item = global.current_set[idx];
        if (override_ms == 0 && is_struct(item) && !is_undefined(item.gracenote_override_ms)) {
            override_ms = item.gracenote_override_ms;
        }
    }
}
if (override_ms == 0 && instance_exists(global.tune) && global.tune.tune_data.is_loaded) {
    var meta = global.tune.tune_data.tune_metadata;
    override_ms = real(meta.gracenote_override_ms ?? meta.gracenote_ms ?? 0);
}
var display_ms = (override_ms > 0) ? override_ms : default_ms;
field_value = display_ms;
field_contents = string(display_ms);
