
draw_self();

var display_text = string(field_contents);
var draw_x = x + 10;
var draw_y = y;

var is_current_note_field = false;
if (variable_instance_exists(self, "ui_name")) {
	var name = string(ui_name);
	is_current_note_field = (name == "obj_last_measure_tune_notes"
		|| name == "obj_current_measure_tune_notes"
		|| name == "obj_next_measure_tune_notes"
		|| name == "obj_last_measure_player_notes"
		|| name == "obj_current_measure_player_notes"
		|| name == "obj_next_measure_player_notes");
}

if (is_current_note_field) draw_set_font(fnt_measure);
else draw_set_font(fnt_setting);

if (!is_current_note_field) {
	draw_set_colour(c_ltgray);
	draw_text(draw_x, draw_y, display_text);
	draw_set_colour(c_white);
	return;
}

var marker = "^";
if (variable_global_exists("current_note_panel") && is_struct(global.current_note_panel)) {
	marker = string(global.current_note_panel.filter_marker_symbol ?? "^");
	if (string_length(marker) <= 0) marker = "^";
}

var has_token_map = false;
var token_list = [];
if (is_current_note_field && variable_global_exists("current_note_panel") && is_struct(global.current_note_panel)) {
	if (is_struct(global.current_note_panel.render_tokens)) {
		token_list = global.current_note_panel.render_tokens[$ string(ui_name)];
		has_token_map = is_array(token_list);
	}
}

if (has_token_map) {
	for (var t = 0; t < array_length(token_list); t++) {
		var token = token_list[t];
		var token_text = string(token.text ?? "");
		var token_class = string(token.class ?? "normal");
		switch (token_class) {
			case "filtered_noise": draw_set_colour(c_red); break;
			case "short_noncore": draw_set_colour(c_yellow); break;
			default: draw_set_colour(c_ltgray); break;
		}
		draw_text(draw_x, draw_y, token_text);
		draw_x += string_width(token_text);
	}
	draw_set_colour(c_white);
	return;
}

for (var i = 1; i <= string_length(display_text); i++) {
	var ch = string_char_at(display_text, i);
	if (ch == marker) draw_set_colour(c_red);
	else draw_set_colour(c_ltgray);
	draw_text(draw_x, draw_y, ch);
	draw_x += string_width(ch);
}

draw_set_colour(c_white);