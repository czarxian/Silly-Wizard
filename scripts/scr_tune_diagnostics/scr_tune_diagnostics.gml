// Compiler diagnostics as data.
// See TUNE_PIPELINE_CONTRACT.md §9 — diagnostics never halt and never use modal failure paths.

#macro TUNE_DIAG_ERROR "error"
#macro TUNE_DIAG_WARNING "warning"
#macro TUNE_DIAG_INFO "info"

/// @function tune_diagnostics_create()
/// @description Create an empty diagnostics collector.
/// @returns {struct}  {items: [], counts: {error, warning, info}}
function tune_diagnostics_create() {
	return {
		items: [],
		counts: { error: 0, warning: 0, info: 0 }
	};
}

/// @function tune_diagnostics_add(_diag, _severity, _code, _message, _opts)
/// @description Append a diagnostic. Never throws; unknown severities are recorded as info.
/// @param {struct} _diag      Collector from tune_diagnostics_create
/// @param {string} _severity  TUNE_DIAG_ERROR | TUNE_DIAG_WARNING | TUNE_DIAG_INFO
/// @param {string} _code      Stable machine-readable code (e.g. "emb_unknown")
/// @param {string} _message   Human-readable description
/// @param {struct} [_opts]    Optional {line, col, token, measure_uid, event_uid}
/// @returns {struct}  The appended diagnostic
function tune_diagnostics_add(_diag, _severity, _code, _message, _opts = undefined) {
	var _sev = string(_severity);
	if (_sev != TUNE_DIAG_ERROR && _sev != TUNE_DIAG_WARNING) _sev = TUNE_DIAG_INFO;

	var _o = is_struct(_opts) ? _opts : {};
	var _item = {
		severity: _sev,
		code: string(_code),
		message: string(_message),
		line: real(_o[$ "line"] ?? 0),
		col: real(_o[$ "col"] ?? 0),
		token: string(_o[$ "token"] ?? ""),
		measure_uid: string(_o[$ "measure_uid"] ?? ""),
		event_uid: string(_o[$ "event_uid"] ?? "")
	};

	array_push(_diag[$ "items"], _item);
	var _counts = _diag[$ "counts"];
	variable_struct_set(_counts, _sev, real(variable_struct_get(_counts, _sev)) + 1);
	return _item;
}

/// @function tune_diagnostics_has_errors(_diag)
/// @description Whether any error-severity diagnostic was recorded.
/// @param {struct} _diag  Collector
/// @returns {bool}
function tune_diagnostics_has_errors(_diag) {
	if (!is_struct(_diag)) return false;
	var _counts = _diag[$ "counts"];
	return is_struct(_counts) && real(_counts[$ "error"] ?? 0) > 0;
}

/// @function tune_diagnostics_merge(_target, _source)
/// @description Append every diagnostic from one collector into another.
/// @param {struct} _target  Collector to append into
/// @param {struct} _source  Collector to read from
/// @returns {struct}  _target
function tune_diagnostics_merge(_target, _source) {
	if (!is_struct(_source)) return _target;

	var _src_items = _source[$ "items"];
	if (!is_array(_src_items)) return _target;

	var _dst_items = _target[$ "items"];
	var _dst_counts = _target[$ "counts"];
	for (var _i = 0; _i < array_length(_src_items); _i++) {
		var _it = _src_items[_i];
		var _sev = string(_it[$ "severity"]);
		array_push(_dst_items, _it);
		variable_struct_set(_dst_counts, _sev, real(variable_struct_get(_dst_counts, _sev)) + 1);
	}
	return _target;
}

/// @function tune_diagnostics_filter(_diag, _severity)
/// @description Return the diagnostics matching one severity.
/// @param {struct} _diag      Collector
/// @param {string} _severity  Severity to keep
/// @returns {array}  Matching diagnostic structs
function tune_diagnostics_filter(_diag, _severity) {
	var _out = [];
	if (!is_struct(_diag)) return _out;

	var _items = _diag[$ "items"];
	if (!is_array(_items)) return _out;

	for (var _i = 0; _i < array_length(_items); _i++) {
		if (string(_items[_i][$ "severity"]) == string(_severity)) array_push(_out, _items[_i]);
	}
	return _out;
}

/// @function tune_diagnostics_format_item(_item)
/// @description Render one diagnostic as a single line.
/// @param {struct} _item  Diagnostic
/// @returns {string}
function tune_diagnostics_format_item(_item) {
	var _s = "[" + string(_item[$ "severity"]) + "] "
		+ string(_item[$ "code"]) + ": " + string(_item[$ "message"]);
	if (real(_item[$ "line"] ?? 0) > 0) {
		_s += " (line " + string(_item[$ "line"]) + ", col " + string(_item[$ "col"]) + ")";
	}
	if (string(_item[$ "token"] ?? "") != "") _s += " token='" + string(_item[$ "token"]) + "'";
	if (string(_item[$ "event_uid"] ?? "") != "") _s += " at " + string(_item[$ "event_uid"]);
	else if (string(_item[$ "measure_uid"] ?? "") != "") _s += " at " + string(_item[$ "measure_uid"]);
	return _s;
}

/// @function tune_diagnostics_log(_diag, _label)
/// @description Write all diagnostics plus a summary to the debug output.
/// @param {struct} _diag    Collector
/// @param {string} [_label] Prefix identifying the compile that produced them
/// @returns {undefined}
/// @reads   none
/// @writes  none (debug output only)
/// @objects none
/// @callers scr_tune_compile
function tune_diagnostics_log(_diag, _label = "tune_compile") {
	if (!is_struct(_diag)) return;

	var _items = _diag[$ "items"];
	if (!is_array(_items)) return;

	for (var _i = 0; _i < array_length(_items); _i++) {
		show_debug_message(string(_label) + " " + tune_diagnostics_format_item(_items[_i]));
	}

	var _counts = _diag[$ "counts"];
	show_debug_message(string(_label) + " diagnostics: "
		+ string(_counts[$ "error"]) + " error, "
		+ string(_counts[$ "warning"]) + " warning, "
		+ string(_counts[$ "info"]) + " info");
}
