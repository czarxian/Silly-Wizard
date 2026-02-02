// Initialize metronome pattern field
field_value = global.metronome_pattern_selection;
if (array_length(global.metronome_pattern_options) > field_value) {
	field_contents = global.metronome_pattern_options[field_value];
} else {
	field_contents = "Auto";
}