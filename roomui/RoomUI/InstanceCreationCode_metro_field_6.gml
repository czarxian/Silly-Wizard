// Initialize swing multiplier field
var swing_mult = 0;
if (is_array(global.current_set)) {
    var idx = global.current_set_item_index;
    if (!is_undefined(idx) && idx >= 0 && idx < array_length(global.current_set)) {
        var item = global.current_set[idx];
        if (is_struct(item) && !is_undefined(item.swing_mult)) {
            swing_mult = item.swing_mult;
        }
    }
}
if (swing_mult == 0 && instance_exists(global.tune) && global.tune.tune_data.is_loaded) {
    var meta = global.tune.tune_data.tune_metadata;
    swing_mult = real(meta.swing ?? 0);
}
field_value = swing_mult;
field_contents = string(swing_mult);
