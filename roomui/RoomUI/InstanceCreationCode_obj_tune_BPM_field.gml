// Initialize BPM field
var bpm_default = 90;
if (instance_exists(global.tune) && global.tune.tune_data.is_loaded) {
	var meta = global.tune.tune_data.tune_metadata;
	var tempo_str = string(meta.tempo_default ?? "");
	if (string_length(tempo_str) > 0) bpm_default = real(tempo_str);
}
field_value = bpm_default;
field_contents = string(bpm_default);