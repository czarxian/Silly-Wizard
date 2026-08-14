// Provenance stamps for derived pipeline artifacts.
// See TUNE_PIPELINE_CONTRACT.md §8 — without these, caches cannot be safely invalidated
// and stored scores cannot be interpreted.

#macro TUNE_PIPELINE_SCHEMA_VERSION 1
#macro TUNE_COMPILER_VERSION 1

/// @function tune_provenance_hash(_text)
/// @description Hash a string for cache-identity comparison.
/// @param {string} _text  Text to hash
/// @returns {string}  SHA-1 hex digest
function tune_provenance_hash(_text) {
	return sha1_string_utf8(string(_text));
}

/// @function tune_provenance_string_gt(_a, _b)
/// @description Ordinal string comparison. GML has no built-in string comparator.
/// @param {string} _a  Left operand
/// @param {string} _b  Right operand
/// @returns {bool}  True when _a sorts after _b
function tune_provenance_string_gt(_a, _b) {
	var _sa = string(_a);
	var _sb = string(_b);
	var _la = string_length(_sa);
	var _lb = string_length(_sb);
	var _n = min(_la, _lb);

	for (var _i = 1; _i <= _n; _i++) {
		var _ca = string_ord_at(_sa, _i);
		var _cb = string_ord_at(_sb, _i);
		if (_ca != _cb) return (_ca > _cb);
	}
	return (_la > _lb);
}

/// @function tune_provenance_sort_names(_names)
/// @description Sort an array of struct member names in place, ascending.
/// @param {array} _names  Array of strings
/// @returns {array}  The same array, sorted
function tune_provenance_sort_names(_names) {
	var _n = array_length(_names);
	for (var _i = 1; _i < _n; _i++) {
		var _key = _names[_i];
		var _j = _i - 1;
		while (_j >= 0 && tune_provenance_string_gt(_names[_j], _key)) {
			_names[_j + 1] = _names[_j];
			_j -= 1;
		}
		_names[_j + 1] = _key;
	}
	return _names;
}

/// @function tune_provenance_canonical(_value)
/// @description Serialise a value deterministically, with struct members in sorted order.
///              GameMaker does not guarantee member ordering, so json_stringify is unsafe for hashing.
/// @param {any} _value  Struct, array, string, number, bool or undefined
/// @returns {string}  Canonical text form
function tune_provenance_canonical(_value) {
	if (is_undefined(_value)) return "null";
	if (is_bool(_value)) return _value ? "true" : "false";
	if (is_real(_value)) return string(_value);
	if (is_string(_value)) return "\"" + string_replace_all(_value, "\"", "\\\"") + "\"";

	if (is_array(_value)) {
		var _out = "[";
		for (var _i = 0; _i < array_length(_value); _i++) {
			if (_i > 0) _out += ",";
			_out += tune_provenance_canonical(_value[_i]);
		}
		return _out + "]";
	}

	if (is_struct(_value)) {
		var _names = tune_provenance_sort_names(variable_struct_get_names(_value));
		var _out = "{";
		for (var _i = 0; _i < array_length(_names); _i++) {
			if (_i > 0) _out += ",";
			_out += "\"" + string(_names[_i]) + "\":"
				+ tune_provenance_canonical(variable_struct_get(_value, _names[_i]));
		}
		return _out + "}";
	}

	return string(_value);
}

/// @function tune_provenance_now_iso()
/// @description Current local time as a sortable ISO-8601-style stamp.
/// @returns {string}  "YYYY-MM-DDTHH:MM:SS"
function tune_provenance_now_iso() {
	var _d = date_current_datetime();
	var _pad = function(_v) { return (_v < 10) ? "0" + string(_v) : string(_v); };
	return string(date_get_year(_d))
		+ "-" + _pad(date_get_month(_d))
		+ "-" + _pad(date_get_day(_d))
		+ "T" + _pad(date_get_hour(_d))
		+ ":" + _pad(date_get_minute(_d))
		+ ":" + _pad(date_get_second(_d));
}

/// @function tune_provenance_create(_abc_text, _tune_config)
/// @description Stamp a compiled artifact with the identity of the inputs that produced it.
/// @param {string} _abc_text     ABC source text
/// @param {struct} _tune_config  Resolved tune configuration
/// @returns {struct}  {schema_version, compiler_version, abc_sha, config_sha, compiled_at}
function tune_provenance_create(_abc_text, _tune_config) {
	return {
		schema_version: TUNE_PIPELINE_SCHEMA_VERSION,
		compiler_version: TUNE_COMPILER_VERSION,
		abc_sha: tune_provenance_hash(_abc_text),
		config_sha: tune_provenance_hash(tune_provenance_canonical(_tune_config)),
		compiled_at: tune_provenance_now_iso()   // excluded from identity comparison
	};
}

/// @function tune_provenance_matches(_provenance, _abc_text, _tune_config)
/// @description Whether a cached artifact was produced by these exact inputs and this compiler.
///              Ignores compiled_at, which is a record of when rather than of what.
/// @param {struct} _provenance   Stamp read from a cached artifact
/// @param {string} _abc_text     Current ABC source text
/// @param {struct} _tune_config  Current resolved tune configuration
/// @returns {bool}  True when the cache is safe to reuse
function tune_provenance_matches(_provenance, _abc_text, _tune_config) {
	if (!is_struct(_provenance)) return false;

	var _required = ["schema_version", "compiler_version", "abc_sha", "config_sha"];
	for (var _i = 0; _i < array_length(_required); _i++) {
		if (!variable_struct_exists(_provenance, _required[_i])) return false;
	}

	return real(_provenance[$ "schema_version"]) == TUNE_PIPELINE_SCHEMA_VERSION
		&& real(_provenance[$ "compiler_version"]) == TUNE_COMPILER_VERSION
		&& string(_provenance[$ "abc_sha"]) == tune_provenance_hash(_abc_text)
		&& string(_provenance[$ "config_sha"]) == tune_provenance_hash(tune_provenance_canonical(_tune_config));
}
