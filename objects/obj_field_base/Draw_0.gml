var ui_name_value = "";
if (variable_instance_exists(id, "ui_name")) {
	ui_name_value = string(variable_instance_get(id, "ui_name"));
}

if (ui_name_value == "timeline_canvas_anchor") {
	gv_draw_timeline_canvas(bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

if (ui_name_value == "notebeam_canvas_anchor") {
	var draw_direct = true;
	if (variable_global_exists("timeline_cfg") && is_struct(global.timeline_cfg)) {
		if (variable_struct_exists(global.timeline_cfg, "notebeam_draw_from_timeline")
			&& global.timeline_cfg.notebeam_draw_from_timeline) {
			draw_direct = false;
		}
	}
	if (draw_direct) {
		gv_draw_notebeam_canvas(bbox_left, bbox_top, bbox_right, bbox_bottom);
	}
	exit;
}

if (ui_name_value == "tunestructure_canvas_anchor") {
	gv_draw_tune_structure_panel(bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}


if (ui_name_value == "gameviz_canvas_anchor") {
	if (sprite_index == noone) {
		sprite_index = spr_field_item;
		mask_index = spr_field_item;
	}
	gv_draw_gameviz_controls_panel(bbox_left, bbox_top, bbox_right, bbox_bottom);
	exit;
}

draw_self();

var display_text = "";
if (variable_instance_exists(id, "field_contents")) {
	display_text = string(variable_instance_get(id, "field_contents"));
}
var draw_x = x + 10;
var draw_y = y;

var is_current_note_field = false;
is_current_note_field = (ui_name_value == "obj_last_measure_tune_notes"
	|| ui_name_value == "obj_current_measure_tune_notes"
	|| ui_name_value == "obj_next_measure_tune_notes"
	|| ui_name_value == "obj_last_measure_player_notes"
	|| ui_name_value == "obj_current_measure_player_notes"
	|| ui_name_value == "obj_next_measure_player_notes");

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
		token_list = global.current_note_panel.render_tokens[$ ui_name_value];
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