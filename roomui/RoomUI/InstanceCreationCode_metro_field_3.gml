/// BPM field initialization (metro_field_3)
var bpm_default = 120;
if (variable_global_exists("current_bpm") && !is_undefined(global.current_bpm)) {
	bpm_default = global.current_bpm;
} else if (instance_exists(global.tune) && global.tune.tune_data.is_loaded) {
	var meta = global.tune.tune_data.tune_metadata;
	var tempo_str = string(meta.tempo_default ?? "");
	if (string_length(tempo_str) > 0) bpm_default = real(tempo_str);
}
field_value = bpm_default;
field_contents = string(bpm_default);
field_min_value = 30;
field_max_value = 240;
