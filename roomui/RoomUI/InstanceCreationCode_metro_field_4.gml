// Initialize Count-In field (measures)
var count_default = 1;
if (variable_global_exists("count_in_measures") && !is_undefined(global.count_in_measures)) {
	count_default = global.count_in_measures;
}
field_value = count_default;
field_contents = string(count_default);
field_min_value = 0;
field_max_value = 2;