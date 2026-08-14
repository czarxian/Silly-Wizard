// Grid references (UIDs) for the tune pipeline.
// See TUNE_PIPELINE_CONTRACT.md §2.1 — UIDs derive from musical position, never from iteration order.

#macro TUNE_UID_SEP ":"
#macro TUNE_UID_COMPONENT_SEP "/"
#macro TUNE_UID_RUN_SEP "#"
#macro TUNE_UID_SIDE_LEAD "lead"
#macro TUNE_UID_SIDE_TRAIL "trail"
#macro TUNE_ANCHOR_LEAD "lead"
#macro TUNE_ANCHOR_TRAIL "trail"

/// @function tune_uid_sanitize_token(_token)
/// @description Strip UID delimiters from a token so a UID always splits back into the same field count.
/// @param {string} _token  Raw token (voice name, part label, tune slug)
/// @returns {string}  Token with ":", "/" and "#" replaced by "_"
function tune_uid_sanitize_token(_token) {
	var _s = string(_token);
	_s = string_replace_all(_s, TUNE_UID_SEP, "_");
	_s = string_replace_all(_s, TUNE_UID_COMPONENT_SEP, "_");
	_s = string_replace_all(_s, TUNE_UID_RUN_SEP, "_");
	return _s;
}

/// @function tune_uid_measure(_part_id, _expanded_index)
/// @description Build a measure grid reference: m:<part_id>:<expanded_index>.
/// @param {string} _part_id          ABC part label, or ordinal if the tune is unlabelled
/// @param {real}   _expanded_index   1-based index over the repeat-expanded measure sequence
/// @returns {string}  measure_uid
function tune_uid_measure(_part_id, _expanded_index) {
	return "m" + TUNE_UID_SEP
		+ tune_uid_sanitize_token(_part_id) + TUNE_UID_SEP
		+ string(floor(real(_expanded_index)));
}

/// @function tune_uid_beat(_measure_uid, _beat_index)
/// @description Build a beat grid reference: <measure_uid>:b<beat_index>.
/// @param {string} _measure_uid  Measure grid reference
/// @param {real}   _beat_index   1-based beat index within the measure
/// @returns {string}  beat_uid
function tune_uid_beat(_measure_uid, _beat_index) {
	return string(_measure_uid) + TUNE_UID_SEP + "b" + string(floor(real(_beat_index)));
}

/// @function tune_uid_event(_voice, _measure_uid, _beat_index, _units_from_beat_start, _ordinal)
/// @description Build an event grid reference: <voice>:<measure_uid>:b<beat>:d<units>:<ordinal>.
/// @param {string} _voice                  Voice name (pipes_melody, drums, …)
/// @param {string} _measure_uid            Measure grid reference
/// @param {real}   _beat_index             1-based beat index within the measure
/// @param {real}   _units_from_beat_start  Whole tune units after the beat start; never fractional
/// @param {real}   _ordinal                1-based disambiguator for simultaneous events
/// @returns {string}  event_uid
function tune_uid_event(_voice, _measure_uid, _beat_index, _units_from_beat_start, _ordinal) {
	return tune_uid_sanitize_token(_voice) + TUNE_UID_SEP
		+ string(_measure_uid) + TUNE_UID_SEP
		+ "b" + string(floor(real(_beat_index))) + TUNE_UID_SEP
		+ "d" + string(floor(real(_units_from_beat_start))) + TUNE_UID_SEP
		+ string(floor(real(_ordinal)));
}

/// @function tune_uid_side_from_anchor(_anchor)
/// @description Derive the ornament side from the anchor field. Side is never stored separately.
/// @param {real|string} _anchor  Component index 1..N, "lead", or "trail"
/// @returns {string}  TUNE_UID_SIDE_LEAD or TUNE_UID_SIDE_TRAIL
function tune_uid_side_from_anchor(_anchor) {
	if (is_string(_anchor) && string_lower(string_trim(_anchor)) == TUNE_ANCHOR_TRAIL) {
		return TUNE_UID_SIDE_TRAIL;
	}
	return TUNE_UID_SIDE_LEAD;
}

/// @function tune_uid_component(_host_event_uid, _anchor, _component_index)
/// @description Build an ornament component reference: <host_event_uid>/<side>:e<index>.
/// @param {string}      _host_event_uid  Grid reference of the note the ornament decorates
/// @param {real|string} _anchor          Component index 1..N, "lead", or "trail"
/// @param {real}        _component_index 1-based index in played order
/// @returns {string}  component uid
function tune_uid_component(_host_event_uid, _anchor, _component_index) {
	return string(_host_event_uid) + TUNE_UID_COMPONENT_SEP
		+ tune_uid_side_from_anchor(_anchor) + TUNE_UID_SEP
		+ "e" + string(floor(real(_component_index)));
}

/// @function tune_uid_run_ref(_segment_index, _iteration, _uid)
/// @description Build a run-space reference. Run refs exist only during playback and are never stored.
/// @param {real}   _segment_index  Set segment index; 0 for single-tune playback
/// @param {real}   _iteration      Loop iteration; 0 when not looping
/// @param {string} _uid            Any compile-time grid reference
/// @returns {string}  run_ref
function tune_uid_run_ref(_segment_index, _iteration, _uid) {
	return string(floor(real(_segment_index))) + TUNE_UID_RUN_SEP
		+ string(floor(real(_iteration))) + TUNE_UID_RUN_SEP
		+ string(_uid);
}

/// @function tune_uid_strip_run_ref(_run_ref)
/// @description Recover the compile-time grid reference from a run-space reference.
/// @param {string} _run_ref  Run-space reference, or a plain uid
/// @returns {string}  The grid reference portion
function tune_uid_strip_run_ref(_run_ref) {
	var _parts = string_split(string(_run_ref), TUNE_UID_RUN_SEP);
	if (array_length(_parts) < 3) return string(_run_ref);
	// Rejoin in case the uid itself was unexpectedly split.
	var _out = _parts[2];
	for (var _i = 3; _i < array_length(_parts); _i++) {
		_out += TUNE_UID_RUN_SEP + _parts[_i];
	}
	return _out;
}

/// @function tune_uid_parse_event(_event_uid)
/// @description Decompose an event grid reference back into its musical position fields.
/// @param {string} _event_uid  Event grid reference, with or without a component suffix
/// @returns {struct|undefined}  {voice, part_id, expanded_index, beat_index, units_from_beat_start, ordinal, measure_uid, beat_uid, side, component_index} or undefined if malformed
function tune_uid_parse_event(_event_uid) {
	var _raw = string(_event_uid);

	var _side = "";
	var _component_index = 0;
	var _slash = string_split(_raw, TUNE_UID_COMPONENT_SEP);
	if (array_length(_slash) == 2) {
		_raw = _slash[0];
		var _comp = string_split(_slash[1], TUNE_UID_SEP);
		if (array_length(_comp) != 2) return undefined;
		_side = _comp[0];
		_component_index = real(string_digits(_comp[1]));
	} else if (array_length(_slash) != 1) {
		return undefined;
	}

	var _f = string_split(_raw, TUNE_UID_SEP);
	if (array_length(_f) != 7) return undefined;
	if (_f[1] != "m") return undefined;

	var _part_id = _f[2];
	var _expanded_index = real(_f[3]);
	var _measure_uid = tune_uid_measure(_part_id, _expanded_index);
	var _beat_index = real(string_digits(_f[4]));

	return {
		voice: _f[0],
		part_id: _part_id,
		expanded_index: _expanded_index,
		beat_index: _beat_index,
		units_from_beat_start: real(string_digits(_f[5])),
		ordinal: real(_f[6]),
		measure_uid: _measure_uid,
		beat_uid: tune_uid_beat(_measure_uid, _beat_index),
		side: _side,
		component_index: _component_index
	};
}

/// @function tune_uid_parse_measure(_measure_uid)
/// @description Decompose a measure grid reference.
/// @param {string} _measure_uid  Measure grid reference
/// @returns {struct|undefined}  {part_id, expanded_index} or undefined if malformed
function tune_uid_parse_measure(_measure_uid) {
	var _f = string_split(string(_measure_uid), TUNE_UID_SEP);
	if (array_length(_f) != 3 || _f[0] != "m") return undefined;
	return { part_id: _f[1], expanded_index: real(_f[2]) };
}

/// @function tune_uid_ordinal_tracker()
/// @description Create a tracker that hands out deterministic ordinals for events sharing a position.
/// @returns {struct}  Opaque tracker; pass to tune_uid_next_ordinal
function tune_uid_ordinal_tracker() {
	return { counts: {} };
}

/// @function tune_uid_event_position_key(_voice, _measure_uid, _beat_index, _units_from_beat_start)
/// @description Build the event uid prefix that omits the ordinal, for ordinal tracking.
/// @param {string} _voice                  Voice name
/// @param {string} _measure_uid            Measure grid reference
/// @param {real}   _beat_index             1-based beat index within the measure
/// @param {real}   _units_from_beat_start  Whole tune units after the beat start
/// @returns {string}  Position key
function tune_uid_event_position_key(_voice, _measure_uid, _beat_index, _units_from_beat_start) {
	return tune_uid_sanitize_token(_voice) + TUNE_UID_SEP
		+ string(_measure_uid) + TUNE_UID_SEP
		+ "b" + string(floor(real(_beat_index))) + TUNE_UID_SEP
		+ "d" + string(floor(real(_units_from_beat_start)));
}

/// @function tune_uid_next_ordinal(_tracker, _position_key)
/// @description Return the next 1-based ordinal for a musical position, so simultaneous events differ.
/// @param {struct} _tracker       Tracker from tune_uid_ordinal_tracker
/// @param {string} _position_key  Key from tune_uid_event_position_key
/// @returns {real}  1-based ordinal
function tune_uid_next_ordinal(_tracker, _position_key) {
	var _counts = _tracker[$ "counts"];
	var _key = string(_position_key);
	var _n = variable_struct_exists(_counts, _key) ? real(variable_struct_get(_counts, _key)) : 0;
	_n += 1;
	variable_struct_set(_counts, _key, _n);
	return _n;
}
