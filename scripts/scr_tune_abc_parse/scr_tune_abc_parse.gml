// ABC notation parser — tokeniser, repeat expansion and unit-space event construction.
// See TUNE_PIPELINE_CONTRACT.md §4 (parser rules) and §10 (tune_compile stages 1-2).
//
// Reproduces the semantics of the Excel VBA module modParseABC so that Phase 2 can diff
// this parser's output against the exported tune.json before the runtime switches over.

/// @function abc_is_digit(_ch)
/// @description Whether a single character is 0-9.
/// @param {string} _ch  Single character
/// @returns {bool}
function abc_is_digit(_ch) {
	var _o = ord(_ch);
	return (_o >= 48 && _o <= 57);
}

/// @function abc_is_letter(_ch)
/// @description Whether a single character is A-Z or a-z.
/// @param {string} _ch  Single character
/// @returns {bool}
function abc_is_letter(_ch) {
	var _o = ord(_ch);
	return (_o >= 65 && _o <= 90) || (_o >= 97 && _o <= 122);
}

/// @function abc_parse_fraction(_text)
/// @description Parse "1/8", "3/2" or a bare number into a decimal.
/// @param {string} _text  Fraction text
/// @returns {real}  Decimal value; 0 when empty or malformed
function abc_parse_fraction(_text) {
	var _s = string_trim(string(_text));
	if (_s == "") return 0;

	var _parts = string_split(_s, "/");
	if (array_length(_parts) == 1) {
		return real(_parts[0]);
	}
	if (array_length(_parts) == 2) {
		var _den = real(_parts[1]);
		if (_den == 0) return 0;
		return real(_parts[0]) / _den;
	}
	return 0;
}

/// @function abc_meter_to_timesig(_meter)
/// @description Convert an ABC meter field into numerator/denominator.
/// @param {string} _meter  "4/4", "C", "C|", "6/8" …
/// @returns {struct}  {num, den}
function abc_meter_to_timesig(_meter) {
	var _m = string_trim(string(_meter));
	if (_m == "C")  return { num: 4, den: 4 };
	if (_m == "C|") return { num: 2, den: 2 };

	var _parts = string_split(_m, "/");
	if (array_length(_parts) == 2) {
		return { num: real(_parts[0]), den: real(_parts[1]) };
	}
	return { num: 4, den: 4 };
}

/// @function abc_normalise_lines(_abc_text)
/// @description Split ABC text into lines with normalised line endings.
/// @param {string} _abc_text  Raw ABC source
/// @returns {array}  Array of line strings
function abc_normalise_lines(_abc_text) {
	var _t = string_replace_all(string(_abc_text), "\r\n", "\n");
	_t = string_replace_all(_t, "\r", "\n");
	return string_split(_t, "\n");
}

/// @function abc_line_is_header(_line)
/// @description Whether a line is an ABC information field (single letter followed by ':').
/// @param {string} _line  Trimmed line
/// @returns {bool}
function abc_line_is_header(_line) {
	var _s = string_trim(string(_line));
	if (string_length(_s) < 2) return false;
	return abc_is_letter(string_char_at(_s, 1)) && string_char_at(_s, 2) == ":";
}

/// @function abc_parse_headers(_abc_text)
/// @description Read ABC information fields into a struct keyed by lowercase field letter.
/// @param {string} _abc_text  Raw ABC source
/// @returns {struct}  Header fields, e.g. {t: "Aros Park", m: "4/4", l: "1/8", q: "85", k: "HP"}
function abc_parse_headers(_abc_text) {
	var _out = {};
	var _lines = abc_normalise_lines(_abc_text);

	for (var _i = 0; _i < array_length(_lines); _i++) {
		var _line = string_trim(_lines[_i]);
		if (_line == "" || string_char_at(_line, 1) == "%") continue;
		if (!abc_line_is_header(_line)) continue;

		var _key = string_lower(string_char_at(_line, 1));
		if (_key == "v") continue;   // voice headers are structure, not metadata

		var _value = string_trim(string_delete(_line, 1, 2));
		if (!variable_struct_exists(_out, _key)) {
			variable_struct_set(_out, _key, _value);
		}
	}
	return _out;
}

/// @function abc_list_voices(_abc_text)
/// @description Collect voice ids declared by V: header lines, in order of first appearance.
/// @param {string} _abc_text  Raw ABC source
/// @returns {array}  Voice id strings; empty when the tune is single-voice
function abc_list_voices(_abc_text) {
	var _out = [];
	var _lines = abc_normalise_lines(_abc_text);

	for (var _i = 0; _i < array_length(_lines); _i++) {
		var _line = string_trim(_lines[_i]);
		if (string_lower(string_copy(_line, 1, 2)) != "v:") continue;

		var _id = abc_parse_voice_id(_line);
		var _found = false;
		for (var _j = 0; _j < array_length(_out); _j++) {
			if (_out[_j] == _id) { _found = true; break; }
		}
		if (!_found) array_push(_out, _id);
	}
	return _out;
}

/// @function abc_parse_voice_id(_line)
/// @description Extract the voice id from a "V:<id> …" line.
/// @param {string} _line  Voice header line
/// @returns {string}  Voice id
function abc_parse_voice_id(_line) {
	var _payload = string_trim(string_delete(string_trim(string(_line)), 1, 2));
	var _n = string_length(_payload);
	for (var _i = 1; _i <= _n; _i++) {
		var _ch = string_char_at(_payload, _i);
		if (_ch == " " || _ch == chr(9)) return string_copy(_payload, 1, _i - 1);
	}
	return _payload;
}

/// @function abc_voice_name(_abc_text, _voice_id, _index)
/// @description Resolve the pipeline voice name for a declared ABC voice.
///              Uses `name=` from the V: header when present, otherwise maps by declaration order.
/// @param {string} _abc_text  Raw ABC source
/// @param {string} _voice_id  Voice id from the V: header
/// @param {real}   _index     0-based declaration order
/// @returns {string}  Voice name, e.g. "pipes_melody"
function abc_voice_name(_abc_text, _voice_id, _index) {
	var _lines = abc_normalise_lines(_abc_text);
	for (var _i = 0; _i < array_length(_lines); _i++) {
		var _line = string_trim(_lines[_i]);
		if (string_lower(string_copy(_line, 1, 2)) != "v:") continue;
		if (abc_parse_voice_id(_line) != string(_voice_id)) continue;

		var _pos = string_pos("name=", string_lower(_line));
		if (_pos > 0) {
			var _rest = string_trim(string_delete(_line, 1, _pos + 4));
			_rest = string_replace_all(_rest, "\"", "");
			var _sp = string_pos(" ", _rest);
			if (_sp > 0) _rest = string_copy(_rest, 1, _sp - 1);
			if (_rest != "") return string_lower(_rest);
		}
		break;
	}

	switch (_index) {
		case 0:  return "pipes_melody";
		case 1:  return "pipes_harmony1";
		case 2:  return "pipes_harmony2";
		case 3:  return "pipes_harmony3";
		default: return "voice_" + tune_uid_sanitize_token(_voice_id);
	}
}

/// @function abc_extract_body(_abc_text, _voice_id)
/// @description Flatten ABC body lines into one string, optionally keeping a single voice.
/// @param {string} _abc_text   Raw ABC source
/// @param {string} [_voice_id] Voice to keep; empty keeps every body line
/// @returns {string}  Body text with headers and comments removed
function abc_extract_body(_abc_text, _voice_id = "") {
	var _lines = abc_normalise_lines(_abc_text);
	var _has_voices = (array_length(abc_list_voices(_abc_text)) > 0);
	var _current_voice = "";
	var _out = "";

	for (var _i = 0; _i < array_length(_lines); _i++) {
		var _line = string_trim(_lines[_i]);
		if (_line == "" || string_char_at(_line, 1) == "%") continue;

		if (string_lower(string_copy(_line, 1, 2)) == "v:") {
			_current_voice = abc_parse_voice_id(_line);
			continue;
		}
		if (abc_line_is_header(_line)) continue;

		if (_has_voices && string(_voice_id) != "" && _current_voice != string(_voice_id)) continue;

		if (_out != "") _out += " ";
		_out += _line;
	}
	return string_trim(_out);
}

/// @function abc_tokenize(_body, _diag)
/// @description Single-pass left-to-right tokenise of an ABC body line.
/// @param {string} _body   Flattened ABC body
/// @param {struct} [_diag] Diagnostics collector for unrecognised input
/// @returns {array}  Tokens as {type, text, pos}
function abc_tokenize(_body, _diag = undefined) {
	var _tokens = [];
	var _s = string(_body);
	var _n = string_length(_s);
	var _i = 1;

	while (_i <= _n) {
		var _ch = string_char_at(_s, _i);

		if (_ch == " " || _ch == chr(9) || _ch == chr(10) || _ch == chr(13)) { _i++; continue; }

		// Embellishment: {...}
		if (_ch == "{") {
			var _close = string_pos_ext("}", _s, _i);
			if (_close <= 0) {
				if (is_struct(_diag)) {
					tune_diagnostics_add(_diag, TUNE_DIAG_ERROR, "abc_unclosed_brace",
						"Embellishment brace opened but never closed.", { col: _i });
				}
				break;
			}
			array_push(_tokens, {
				type: "embellishment",
				text: string_copy(_s, _i, _close - _i + 1),
				pos: _i
			});
			_i = _close + 1;
			continue;
		}

		// Bar lines and voltas
		if (_ch == "|") {
			var _next = (_i < _n) ? string_char_at(_s, _i + 1) : "";
			if (_next == ":")      { array_push(_tokens, { type: "repeat_start", text: "|:", pos: _i }); _i += 2; continue; }
			if (_next == "1")      { array_push(_tokens, { type: "ending1",      text: "|1", pos: _i }); _i += 2; continue; }
			if (_next == "2")      { array_push(_tokens, { type: "ending2",      text: "|2", pos: _i }); _i += 2; continue; }
			if (_next == "|")      { array_push(_tokens, { type: "double_bar",   text: "||", pos: _i }); _i += 2; continue; }
			if (_next == "]")      { array_push(_tokens, { type: "end_bar",      text: "|]", pos: _i }); _i += 2; continue; }
			array_push(_tokens, { type: "bar", text: "|", pos: _i });
			_i++;
			continue;
		}

		if (_ch == ":") {
			if (_i < _n && string_char_at(_s, _i + 1) == "|") {
				array_push(_tokens, { type: "repeat_end", text: ":|", pos: _i });
				_i += 2;
				continue;
			}
			_i++;
			continue;
		}

		// Tuplet: (3, (2, (3:2 …
		if (_ch == "(") {
			var _j = _i + 1;
			while (_j <= _n) {
				var _cj = string_char_at(_s, _j);
				if (abc_is_digit(_cj) || _cj == ":") _j++; else break;
			}
			if (_j > _i + 1) {
				array_push(_tokens, { type: "tuplet", text: string_copy(_s, _i, _j - _i), pos: _i });
				_i = _j;
				continue;
			}
			_i++;
			continue;
		}

		if (_ch == ")") {
			array_push(_tokens, { type: "tuplet_end", text: ")", pos: _i });
			_i++;
			continue;
		}

		if (_ch == "[") {
			var _n1 = (_i < _n) ? string_char_at(_s, _i + 1) : "";
			var _n2 = (_i + 1 < _n) ? string_char_at(_s, _i + 2) : "";
			if (_n1 == "|" && _n2 == ":") { array_push(_tokens, { type: "repeat_start", text: "[|:", pos: _i }); _i += 3; continue; }
			if (_n1 == "|")               { array_push(_tokens, { type: "start_bar",    text: "[|",  pos: _i }); _i += 2; continue; }
			if (_n1 == "1")               { array_push(_tokens, { type: "ending1",      text: "[1",  pos: _i }); _i += 2; continue; }
			if (_n1 == "2")               { array_push(_tokens, { type: "ending2",      text: "[2",  pos: _i }); _i += 2; continue; }
			_i++;
			continue;
		}

		if (_ch == "]") {
			if (_i < _n && string_char_at(_s, _i + 1) == "|") {
				array_push(_tokens, { type: "end_bar", text: "]|", pos: _i });
				_i += 2;
				continue;
			}
			_i++;
			continue;
		}

		// Decorations (drum rolls etc.) carry no duration and no grid position.
		if (_ch == "~") {
			array_push(_tokens, { type: "decoration", text: "~", pos: _i });
			_i++;
			continue;
		}

		// Note: letter plus octave markers, accidentals, duration, tie and broken-rhythm marks
		if (abc_is_letter(_ch)) {
			var _k = _i + 1;
			while (_k <= _n) {
				var _ck = string_char_at(_s, _k);
				if (abc_is_digit(_ck) || _ck == "/" || _ck == ">" || _ck == "<"
					|| _ck == "-" || _ck == "'" || _ck == ",") {
					_k++;
				} else {
					break;
				}
			}
			array_push(_tokens, { type: "note", text: string_copy(_s, _i, _k - _i), pos: _i });
			_i = _k;
			continue;
		}

		if (is_struct(_diag)) {
			tune_diagnostics_add(_diag, TUNE_DIAG_WARNING, "abc_unknown_char",
				"Unrecognised character in ABC body; skipped.", { col: _i, token: _ch });
		}
		_i++;
	}

	return _tokens;
}

/// @function abc_note_letter(_token_text)
/// @description Extract the note letter. Rests ("z") return an empty string.
/// @param {string} _token_text  Note token text
/// @returns {string}  Note letter, or "" for a rest
function abc_note_letter(_token_text) {
	var _letter = string_char_at(string(_token_text), 1);
	if (string_lower(_letter) == "z") return "";
	return _letter;
}

/// @function abc_note_duration_units(_token_text)
/// @description Parse the duration suffix of a note token into unit-note multiples.
/// @param {string} _token_text  Note token text, e.g. "c3/2"
/// @returns {real}  Duration in units; 1 when no suffix is present
function abc_note_duration_units(_token_text) {
	var _s = string(_token_text);
	var _n = string_length(_s);
	var _num = "";
	var _den = "";
	var _i = 2;

	while (_i <= _n) {
		var _ch = string_char_at(_s, _i);
		if (abc_is_digit(_ch)) {
			_num += _ch;
			_i++;
		} else if (_ch == "/") {
			_i++;
			while (_i <= _n) {
				var _cd = string_char_at(_s, _i);
				if (abc_is_digit(_cd)) { _den += _cd; _i++; } else break;
			}
			break;
		} else if (_ch == "'" || _ch == ",") {
			_i++;   // octave markers do not affect duration
		} else {
			break;
		}
	}

	if (_num != "" && _den == "") return real(_num);
	if (_num == "" && _den != "") return 1 / real(_den);
	if (_num != "" && _den != "") return real(_num) / real(_den);
	return 1;
}

/// @function abc_note_has_tie(_token_text)
/// @description Whether the note carries a forward tie marker.
/// @param {string} _token_text  Note token text
/// @returns {bool}
function abc_note_has_tie(_token_text) {
	return string_pos("-", string(_token_text)) > 0;
}

/// @function abc_note_strip_tie(_token_text)
/// @description Remove tie markers from a note token.
/// @param {string} _token_text  Note token text
/// @returns {string}
function abc_note_strip_tie(_token_text) {
	return string_replace_all(string(_token_text), "-", "");
}

/// @function abc_note_broken_dir(_token_text)
/// @description Broken-rhythm direction carried by a note token.
/// @param {string} _token_text  Note token text
/// @returns {string}  "dotcut" for '>', "cutdot" for '<', otherwise ""
function abc_note_broken_dir(_token_text) {
	if (string_pos(">", string(_token_text)) > 0) return "dotcut";
	if (string_pos("<", string(_token_text)) > 0) return "cutdot";
	return "";
}

/// @function abc_expand_repeats(_tokens)
/// @description Flatten repeat blocks and first/second endings into a linear token stream.
/// @param {array} _tokens  Tokens from abc_tokenize
/// @returns {array}  Expanded tokens
function abc_expand_repeats(_tokens) {
	var _flat = [];
	var _main = [];
	var _end1 = [];
	var _end2 = [];

	var _in_repeat = false;
	var _pending_second = false;
	var _has_endings = false;
	var _mode = "main";

	var _synthetic_bar = function() { return { type: "double_bar", text: "||", pos: -1 }; };

	for (var _i = 0; _i < array_length(_tokens); _i++) {
		var _t = _tokens[_i];
		var _type = _t.type;

		if (_type == "repeat_start") {
			_main = [];
			_end1 = [];
			_end2 = [];
			_in_repeat = true;
			_pending_second = false;
			_has_endings = false;
			_mode = "main";
			continue;
		}

		if (_type == "ending1") {
			if (_in_repeat) { _mode = "end1"; _has_endings = true; }
			else if (_pending_second) { _mode = "end2"; }
			continue;
		}

		if (_type == "ending2") {
			if (_pending_second) _mode = "end2";
			continue;
		}

		if (_type == "repeat_end") {
			if (_in_repeat) {
				if (_has_endings) {
					_flat = array_concat(_flat, _main);
					_flat = array_concat(_flat, _end1);
					array_push(_flat, _synthetic_bar());
					_pending_second = true;
					_mode = "end2";
				} else {
					_flat = array_concat(_flat, _main);
					array_push(_flat, _synthetic_bar());
					_flat = array_concat(_flat, _main);
					array_push(_flat, _synthetic_bar());
				}
				_in_repeat = false;
			}
			continue;
		}

		if (_in_repeat) {
			if (_mode == "end1") array_push(_end1, _t); else array_push(_main, _t);
			continue;
		}

		if (_pending_second) {
			if (_mode == "end2") {
				array_push(_end2, _t);
				// Second pass flushes only on a strong close.
				if (_type == "double_bar" || _type == "end_bar") {
					_flat = array_concat(_flat, _main);
					_flat = array_concat(_flat, _end2);
					_end2 = [];
					_pending_second = false;
					_mode = "main";
				}
			}
			continue;
		}

		array_push(_flat, _t);
	}

	if (_pending_second && array_length(_end2) > 0) {
		_flat = array_concat(_flat, _main);
		_flat = array_concat(_flat, _end2);
	}

	return _flat;
}

/// @function abc_rhythmic_constants(_headers)
/// @description Derive the rhythmic constants from ABC header fields.
/// @param {struct} _headers  Header struct from abc_parse_headers
/// @returns {struct}  {time_sig_num, time_sig_den, unit_note_fraction, units_per_beat, beats_per_measure, units_per_measure, meter, unit_note_length}
function abc_rhythmic_constants(_headers) {
	var _meter_text = string(_headers[$ "m"] ?? "4/4");
	var _unit_text  = string(_headers[$ "l"] ?? "1/8");

	var _sig = abc_meter_to_timesig(_meter_text);
	var _unit_fraction = abc_parse_fraction(_unit_text);
	if (_unit_fraction <= 0) _unit_fraction = 0.125;

	var _num = (_sig[$ "num"] > 0) ? _sig[$ "num"] : 4;
	var _den = (_sig[$ "den"] > 0) ? _sig[$ "den"] : 4;

	var _beat_fraction = 1 / _den;
	var _units_per_beat = _beat_fraction / _unit_fraction;

	return {
		meter: _meter_text,
		unit_note_length: _unit_text,
		time_sig_num: _num,
		time_sig_den: _den,
		unit_note_fraction: _unit_fraction,
		beats_per_measure: _num,
		units_per_beat: _units_per_beat,
		units_per_measure: _units_per_beat * _num
	};
}

/// @function abc_build_flat_events(_tokens, _consts, _voice, _diag)
/// @description Convert expanded tokens into unit-space events, accumulating total_units.
///              Mirrors the legacy WriteEventsFromTokens pass, including ties, tuplets and
///              broken rhythm, so output can be diffed against exported tune.json.
/// @param {array}  _tokens  Expanded tokens
/// @param {struct} _consts  Rhythmic constants
/// @param {string} _voice   Voice label written onto note and embellishment events
/// @param {struct} [_diag]  Diagnostics collector
/// @returns {array}  Flat events {type, structure, letter, written, total_units, emb_literal, broken_dir, voice}
function abc_build_flat_events(_tokens, _consts, _voice = "pipes_melody", _diag = undefined) {
	var _events = [];
	var _total_units = 0;

	var _in_tuplet = false;
	var _tuplet_ratio = 1;
	var _tuplet_remaining = 0;

	var _i = 0;
	var _count = array_length(_tokens);

	while (_i < _count) {
		var _t = _tokens[_i];
		var _type = _t.type;

		if (_type == "tuplet") {
			// Only the leading count matters; "(3:2" must not read as 32.
			var _digits = "";
			var _tt = _t.text;
			for (var _c = 2; _c <= string_length(_tt); _c++) {
				var _cc = string_char_at(_tt, _c);
				if (abc_is_digit(_cc)) _digits += _cc; else break;
			}
			var _tn = (_digits == "") ? 3 : real(_digits);
			_in_tuplet = true;
			_tuplet_remaining = _tn;
			if (_tn == 3)      _tuplet_ratio = 2 / 3;
			else if (_tn == 2) _tuplet_ratio = 3 / 2;
			else if (_tn == 4) _tuplet_ratio = 3 / 4;
			else               _tuplet_ratio = (_tn - 1) / _tn;
			_i++;
			continue;
		}

		if (_type == "tuplet_end") {
			_in_tuplet = false;
			_i++;
			continue;
		}

		if (_type == "bar" || _type == "double_bar" || _type == "end_bar" || _type == "start_bar") {
			array_push(_events, {
				type: "structure",
				structure: "bar",
				letter: "",
				written: 0,
				total_units: _total_units,
				emb_literal: "",
				broken_dir: "",
				voice: ""
			});
			_in_tuplet = false;
			_tuplet_remaining = 0;
			_i++;
			continue;
		}

		if (_type == "embellishment") {
			// {null} is an explicit "no ornament here" placeholder in drum notation.
			var _inner = string_lower(string_replace_all(string_replace_all(_t.text, "{", ""), "}", ""));
			if (_inner == "null") { _i++; continue; }

			array_push(_events, {
				type: "embellishment",
				structure: "",
				letter: "",
				written: 0,
				total_units: _total_units,
				emb_literal: _t.text,
				broken_dir: "",
				voice: _voice
			});
			_i++;
			continue;
		}

		if (_type != "note") { _i++; continue; }

		var _raw = _t.text;
		var _clean = abc_note_strip_tie(_raw);
		var _base = abc_note_duration_units(_clean);

		if (_in_tuplet) {
			_base *= _tuplet_ratio;
			_tuplet_remaining--;
			if (_tuplet_remaining <= 0) _in_tuplet = false;
		}

		// Tie: absorb following tied notes of the same letter into one event.
		if (abc_note_has_tie(_raw)) {
			var _merged = _base;
			var _letter = abc_note_letter(_clean);
			var _j = _i + 1;
			while (_j < _count && _tokens[_j].type == "note") {
				var _next_raw = _tokens[_j].text;
				var _next_clean = abc_note_strip_tie(_next_raw);
				if (abc_note_letter(_next_clean) != _letter) break;

				var _next_dur = abc_note_duration_units(_next_clean);
				if (_in_tuplet) {
					_next_dur *= _tuplet_ratio;
					_tuplet_remaining--;
					if (_tuplet_remaining <= 0) _in_tuplet = false;
				}
				_merged += _next_dur;

				var _continues = abc_note_has_tie(_next_raw);
				_j++;
				if (!_continues) break;
			}

			array_push(_events, {
				type: "note",
				structure: "",
				letter: _letter,
				written: _merged,
				total_units: _total_units,
				emb_literal: "",
				broken_dir: "",
				voice: _voice
			});
			_total_units += _merged;
			_i = _j;
			continue;
		}

		// Broken rhythm: '>' lengthens this note and shortens the next; '<' is the reverse.
		var _broken = abc_note_broken_dir(_clean);
		if (_broken != "" && (_i + 1) < _count && _tokens[_i + 1].type == "note") {
			var _second_clean = abc_note_strip_tie(_tokens[_i + 1].text);
			var _second_base = abc_note_duration_units(_second_clean);

			var _dur1 = (_broken == "dotcut") ? _base * 1.5 : _base * 0.5;
			var _dur2 = (_broken == "dotcut") ? _second_base * 0.5 : _second_base * 1.5;

			if (_in_tuplet) {
				_dur2 *= _tuplet_ratio;
				_tuplet_remaining--;
				if (_tuplet_remaining <= 0) _in_tuplet = false;
			}

			array_push(_events, {
				type: "note",
				structure: "",
				letter: abc_note_letter(_clean),
				written: _dur1,
				total_units: _total_units,
				emb_literal: "",
				broken_dir: _broken,
				voice: _voice
			});
			_total_units += _dur1;

			array_push(_events, {
				type: "note",
				structure: "",
				letter: abc_note_letter(_second_clean),
				written: _dur2,
				total_units: _total_units,
				emb_literal: "",
				broken_dir: "",
				voice: _voice
			});
			_total_units += _dur2;

			_i += 2;
			continue;
		}

		array_push(_events, {
			type: "note",
			structure: "",
			letter: abc_note_letter(_clean),
			written: _base,
			total_units: _total_units,
			emb_literal: "",
			broken_dir: "",
			voice: _voice
		});
		_total_units += _base;
		_i++;
	}

	return _events;
}

/// @function abc_build_bar_phase_map(_events, _consts)
/// @description Locate downbeat anchors from bar events so pickups (initial and internal)
///              can be measured. Mirrors the legacy BuildBarPhaseMap.
/// @param {array}  _events  Flat events from abc_build_flat_events
/// @param {struct} _consts  Rhythmic constants
/// @returns {struct}  {downbeats, effective_measure_units, pickup_offset_units, pickup_detected}
function abc_build_bar_phase_map(_events, _consts) {
	var _eps = 0.0001;
	var _units_per_measure = _consts[$ "units_per_measure"];

	var _bar_units = [];
	for (var _i = 0; _i < array_length(_events); _i++) {
		var _e = _events[_i];
		if (_e.type != "structure") continue;

		var _u = _e.total_units;
		if (_u <= _eps) continue;
		if (array_length(_bar_units) > 0 && abs(_u - _bar_units[array_length(_bar_units) - 1]) <= _eps) continue;
		array_push(_bar_units, _u);
	}

	var _bar_count = array_length(_bar_units);
	var _effective = _units_per_measure;
	if (_bar_count >= 2) {
		var _first_gap = _bar_units[1] - _bar_units[0];
		if (_first_gap > _eps) _effective = _first_gap;
	}

	var _has_initial_pickup = (_bar_count > 0) && (_bar_units[0] < _effective - _eps);
	var _tol = max(0.2, _effective * 0.2);

	var _downbeats = [];
	if (!_has_initial_pickup) array_push(_downbeats, 0);

	for (var _i = 0; _i < _bar_count; _i++) {
		var _is_downbeat = false;

		if (_i == 0 && _has_initial_pickup) {
			_is_downbeat = true;
		} else {
			if (_i > 0 && abs((_bar_units[_i] - _bar_units[_i - 1]) - _effective) <= _tol) _is_downbeat = true;
			if (!_is_downbeat && _i < _bar_count - 1
				&& abs((_bar_units[_i + 1] - _bar_units[_i]) - _effective) <= _tol) _is_downbeat = true;
		}

		if (_is_downbeat) array_push(_downbeats, _bar_units[_i]);
	}

	if (array_length(_downbeats) == 0) array_push(_downbeats, 0);

	var _pickup_offset = _downbeats[0];
	return {
		downbeats: _downbeats,
		effective_measure_units: _effective,
		pickup_offset_units: _pickup_offset,
		pickup_detected: (_pickup_offset > _eps)
	};
}

/// @function abc_position_from_units(_total_units, _phase, _consts)
/// @description Convert a running unit total into measure/beat/division using downbeat anchors.
///              Measure 0 means the position lies inside a pickup.
/// @param {real}   _total_units  Units from the start of the tune
/// @param {struct} _phase        Bar phase map from abc_build_bar_phase_map
/// @param {struct} _consts       Rhythmic constants
/// @returns {struct}  {measure, beat, division}
function abc_position_from_units(_total_units, _phase, _consts) {
	var _eps = 0.0001;
	var _units_per_beat = _consts[$ "units_per_beat"];
	var _downbeats = _phase[$ "downbeats"];
	var _count = array_length(_downbeats);

	if (_count > 0) {
		if (_total_units < _downbeats[0] - _eps) {
			var _beat_p = floor(_total_units / _units_per_beat) + 1;
			return {
				measure: 0,
				beat: _beat_p,
				division: (_total_units - (_beat_p - 1) * _units_per_beat) / _units_per_beat
			};
		}

		var _anchor = 0;
		for (var _i = 1; _i < _count; _i++) {
			if (_total_units >= _downbeats[_i] - _eps) _anchor = _i; else break;
		}

		var _into = max(0, _total_units - _downbeats[_anchor]);
		var _beat = floor(_into / _units_per_beat) + 1;
		return {
			measure: _anchor + 1,
			beat: _beat,
			division: (_into - (_beat - 1) * _units_per_beat) / _units_per_beat
		};
	}

	var _units_per_measure = _consts[$ "units_per_measure"];
	var _measure_f = floor(_total_units / _units_per_measure) + 1;
	var _into_m = _total_units - (_measure_f - 1) * _units_per_measure;
	var _beat_f = floor(_into_m / _units_per_beat) + 1;
	return {
		measure: _measure_f,
		beat: _beat_f,
		division: (_into_m - (_beat_f - 1) * _units_per_beat) / _units_per_beat
	};
}

/// @function abc_annotate_positions(_events, _phase, _consts)
/// @description Stamp measure/beat/division onto every flat event, in place.
/// @param {array}  _events  Flat events
/// @param {struct} _phase   Bar phase map
/// @param {struct} _consts  Rhythmic constants
/// @returns {array}  The same array
function abc_annotate_positions(_events, _phase, _consts) {
	for (var _i = 0; _i < array_length(_events); _i++) {
		var _e = _events[_i];
		var _pos = abc_position_from_units(_e.total_units, _phase, _consts);
		_e.measure = _pos[$ "measure"];
		_e.beat = _pos[$ "beat"];
		_e.division = _pos[$ "division"];
	}
	return _events;
}

/// @function abc_populate_embellishment_targets(_events)
/// @description Fill each embellishment's preceding and target note letters by scanning neighbours.
/// @param {array} _events  Flat events with positions
/// @returns {array}  The same array
function abc_populate_embellishment_targets(_events) {
	var _n = array_length(_events);
	for (var _i = 0; _i < _n; _i++) {
		var _e = _events[_i];
		if (_e.type != "embellishment") continue;

		var _preceding = "";
		for (var _j = _i - 1; _j >= 0; _j--) {
			if (_events[_j].type == "note") { _preceding = _events[_j].letter; break; }
		}

		var _target = "";
		for (var _k = _i + 1; _k < _n; _k++) {
			if (_events[_k].type == "note") { _target = _events[_k].letter; break; }
		}

		_e.emb_preceding = _preceding;
		_e.emb_target = _target;
	}
	return _events;
}

/// @function abc_parse_to_flat_events(_abc_text, _voice, _diag)
/// @description Full ABC -> unit-space flat event pipeline for one voice.
/// @param {string} _abc_text  Raw ABC source
/// @param {string} [_voice]   Voice label for emitted events
/// @param {struct} [_diag]    Diagnostics collector
/// @returns {struct}  {headers, consts, tokens, expanded, events, phase}
function abc_parse_to_flat_events(_abc_text, _voice = "pipes_melody", _diag = undefined) {
	var _headers = abc_parse_headers(_abc_text);
	var _consts = abc_rhythmic_constants(_headers);
	var _body = abc_extract_body(_abc_text, "");
	var _tokens = abc_tokenize(_body, _diag);
	var _expanded = abc_expand_repeats(_tokens);
	var _events = abc_build_flat_events(_expanded, _consts, _voice, _diag);
	var _phase = abc_build_bar_phase_map(_events, _consts);

	abc_annotate_positions(_events, _phase, _consts);
	abc_populate_embellishment_targets(_events);

	return {
		headers: _headers,
		consts: _consts,
		tokens: _tokens,
		expanded: _expanded,
		events: _events,
		phase: _phase
	};
}

/// @function abc_parse_tune(_abc_text, _diag, _voice_filter)
/// @description Parse every declared voice. Each voice is an independent stream: `total_units`
///              and measure numbering restart at the top of each voice, matching how the legacy
///              pipeline ran one pass per part.
/// @param {string} _abc_text      Raw ABC source
/// @param {struct} [_diag]        Diagnostics collector
/// @param {array}  [_voice_filter] Voice names to keep; empty keeps every declared voice
/// @returns {struct}  {headers, consts, voices, events}  where `events` is every voice concatenated
function abc_parse_tune(_abc_text, _diag = undefined, _voice_filter = []) {
	var _headers = abc_parse_headers(_abc_text);
	var _consts = abc_rhythmic_constants(_headers);
	var _voice_ids = abc_list_voices(_abc_text);

	// No V: headers: the whole body is one implicit melody voice.
	if (array_length(_voice_ids) == 0) {
		var _single = abc_parse_to_flat_events(_abc_text, "pipes_melody", _diag);
		return {
			headers: _headers,
			consts: _consts,
			voices: [{
				voice_id: "1",
				voice_name: "pipes_melody",
				events: _single[$ "events"],
				phase: _single[$ "phase"]
			}],
			events: _single[$ "events"]
		};
	}

	var _voices = [];
	var _all = [];

	for (var _v = 0; _v < array_length(_voice_ids); _v++) {
		var _id = _voice_ids[_v];
		var _name = abc_voice_name(_abc_text, _id, _v);

		if (array_length(_voice_filter) > 0) {
			var _keep = false;
			for (var _f = 0; _f < array_length(_voice_filter); _f++) {
				if (string(_voice_filter[_f]) == _name) { _keep = true; break; }
			}
			if (!_keep) continue;
		}

		var _body = abc_extract_body(_abc_text, _id);
		var _tokens = abc_tokenize(_body, _diag);
		var _expanded = abc_expand_repeats(_tokens);
		var _events = abc_build_flat_events(_expanded, _consts, _name, _diag);
		var _phase = abc_build_bar_phase_map(_events, _consts);

		abc_annotate_positions(_events, _phase, _consts);
		abc_populate_embellishment_targets(_events);

		array_push(_voices, {
			voice_id: _id,
			voice_name: _name,
			events: _events,
			phase: _phase
		});
		_all = array_concat(_all, _events);
	}

	return {
		headers: _headers,
		consts: _consts,
		voices: _voices,
		events: _all
	};
}
