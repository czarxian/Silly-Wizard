// Initialize metronome pattern field
field_value = global.metronome_pattern_selection;
field_contents = (field_value < array_length(global.metronome_pattern_options)) 
    ? global.metronome_pattern_options[field_value] 
    : "Auto";