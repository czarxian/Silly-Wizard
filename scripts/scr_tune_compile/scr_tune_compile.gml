// Compile pipeline stage registry and compiled-tune validator.
// See TUNE_PIPELINE_CONTRACT.md §6 (compile/run boundary) and §10 (stage ordering).
//
// Every stage below is a no-op stub. Stages are filled in by later phases; a deferred
// feature stays a no-op in the list rather than being absent from it.

/// @function tune_compiled_create_empty(_tune_uid)
/// @description Create the compiled-tune envelope with all layers empty.
/// @param {string} [_tune_uid]  Stable tune identity (folder slug)
/// @returns {struct}  Compiled tune carrying layers L0, L1, L2 and L4
function tune_compiled_create_empty(_tune_uid = "") {
	return {
		schema_version: TUNE_PIPELINE_SCHEMA_VERSION,
		tune_uid: tune_uid_sanitize_token(_tune_uid),
		provenance: undefined,

		meter: "",
		voices: [],

		structure: { parts: [], measures: [] },   // L0
		beat_grid: { beats: [] },                 // L1 — unit space only; ms is a run-time projection
		events: {},                               // L2 — voice name -> array of events
		annotations: []                           // L4
	};
}

/// @function tune_compile_context(_abc_text, _tune_config, _tune_uid)
/// @description Build the mutable context threaded through every compile stage.
/// @param {string} _abc_text     ABC source text
/// @param {struct} _tune_config  Resolved tune configuration
/// @param {string} [_tune_uid]   Stable tune identity
/// @returns {struct}  {abc_text, config, compiled, diagnostics, tokens}
function tune_compile_context(_abc_text, _tune_config, _tune_uid = "") {
	return {
		abc_text: string(_abc_text),
		config: is_struct(_tune_config) ? _tune_config : {},
		compiled: tune_compiled_create_empty(_tune_uid),
		diagnostics: tune_diagnostics_create(),
		tokens: []
	};
}

// ---------------------------------------------------------------------------
// tune_compile stages (§10) — pure, cacheable, stored
// ---------------------------------------------------------------------------

/// @function tune_compile_stage_parse_abc(_ctx)
/// @description Stage 1: tokenise and validate the ABC source. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_parse_abc(_ctx) { }

/// @function tune_compile_stage_expand_repeats(_ctx)
/// @description Stage 2: flatten repeats into the expanded measure sequence. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_expand_repeats(_ctx) { }

/// @function tune_compile_stage_build_structure(_ctx)
/// @description Stage 3: build L0, including pickup beat budget and voice inventory. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_structure(_ctx) { }

/// @function tune_compile_stage_build_beat_grid(_ctx)
/// @description Stage 4: build L1 in unit space. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_beat_grid(_ctx) { }

/// @function tune_compile_stage_build_events(_ctx)
/// @description Stage 5: build L2 per voice with unexpanded embellishment attachments. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_build_events(_ctx) { }

/// @function tune_compile_stage_attach_annotations(_ctx)
/// @description Stage 6: attach L4 from tune meta and report re-keyed targets. Not yet implemented.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_attach_annotations(_ctx) { }

/// @function tune_compile_stage_stamp_provenance(_ctx)
/// @description Stage 7: stamp provenance onto the compiled tune.
/// @param {struct} _ctx  Compile context
/// @returns {undefined}
function tune_compile_stage_stamp_provenance(_ctx) {
	var _compiled = _ctx[$ "compiled"];
	_compiled[$ "provenance"] = tune_provenance_create(_ctx[$ "abc_text"], _ctx[$ "config"]);
}

/// @function tune_compile_stages()
/// @description The ordered compile stage list. Order is contractual — see §10.
/// @returns {array}  Array of {name, fn}
function tune_compile_stages() {
	return [
		{ name: "parse_abc",          fn: tune_compile_stage_parse_abc },
		{ name: "expand_repeats",     fn: tune_compile_stage_expand_repeats },
		{ name: "build_structure",    fn: tune_compile_stage_build_structure },
		{ name: "build_beat_grid",    fn: tune_compile_stage_build_beat_grid },
		{ name: "build_events",       fn: tune_compile_stage_build_events },
		{ name: "attach_annotations", fn: tune_compile_stage_attach_annotations },
		{ name: "stamp_provenance",   fn: tune_compile_stage_stamp_provenance }
	];
}

/// @function tune_compile(_abc_text, _tune_config, _tune_uid)
/// @description Run the compile stage list. Pure: same inputs produce the same layers.
///              Never runs during active playback — see contract invariant 13.
/// @param {string} _abc_text     ABC source text
/// @param {struct} _tune_config  Resolved tune configuration
/// @param {string} [_tune_uid]   Stable tune identity
/// @returns {struct}  {compiled, diagnostics, ok}
/// @reads   none
/// @writes  none
/// @objects none
/// @callers not yet wired; will be called from tune load
function tune_compile(_abc_text, _tune_config, _tune_uid = "") {
	var _ctx = tune_compile_context(_abc_text, _tune_config, _tune_uid);
	var _diagnostics = _ctx[$ "diagnostics"];
	var _stages = tune_compile_stages();

	for (var _i = 0; _i < array_length(_stages); _i++) {
		var _stage = _stages[_i];
		var _fn = _stage[$ "fn"];
		_fn(_ctx);
		if (tune_diagnostics_has_errors(_diagnostics)) break;
	}

	var _compiled = _ctx[$ "compiled"];
	tune_diagnostics_merge(_diagnostics, tune_compiled_validate(_compiled));

	return {
		compiled: _compiled,
		diagnostics: _diagnostics,
		ok: !tune_diagnostics_has_errors(_diagnostics)
	};
}

// ---------------------------------------------------------------------------
// run_build stages (§10) — per play, never stored
// ---------------------------------------------------------------------------

/// @function run_build_stage_resolve_config(_ctx)
/// @description Stage 1: resolve the rule chain defaults -> tune -> player -> set segment. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_resolve_config(_ctx) { }

/// @function run_build_stage_apply_rhythm_rules(_ctx)
/// @description Stage 2: apply note pointing in unit space, before any ms exists. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_apply_rhythm_rules(_ctx) { }

/// @function run_build_stage_compose_performance(_ctx)
/// @description Stage 3: concatenate set segments and expand cuts, repeats and loops. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_compose_performance(_ctx) { }

/// @function run_build_stage_project_to_ms(_ctx)
/// @description Stage 4: project the unit grid onto ms and apply beat pulse weights. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_project_to_ms(_ctx) { }

/// @function run_build_stage_apply_timing_map(_ctx)
/// @description Stage 5: apply the expressive timing map. Deferred; intentionally a no-op.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_apply_timing_map(_ctx) { }

/// @function run_build_stage_resolve_embellishments(_ctx)
/// @description Stage 6: expand attachments against final host ms and declared anchor.
///              Ornament components do not exist before this stage. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_resolve_embellishments(_ctx) { }

/// @function run_build_stage_emit_run_events(_ctx)
/// @description Stage 7: assign MIDI channels and emit the ordered run event list. Not yet implemented.
/// @param {struct} _ctx  Run context
/// @returns {undefined}
function run_build_stage_emit_run_events(_ctx) { }

/// @function run_build_stages()
/// @description The ordered run-build stage list. Order is contractual — see §10.
/// @returns {array}  Array of {name, fn}
function run_build_stages() {
	return [
		{ name: "resolve_config",         fn: run_build_stage_resolve_config },
		{ name: "apply_rhythm_rules",     fn: run_build_stage_apply_rhythm_rules },
		{ name: "compose_performance",    fn: run_build_stage_compose_performance },
		{ name: "project_to_ms",          fn: run_build_stage_project_to_ms },
		{ name: "apply_timing_map",       fn: run_build_stage_apply_timing_map },
		{ name: "resolve_embellishments", fn: run_build_stage_resolve_embellishments },
		{ name: "emit_run_events",        fn: run_build_stage_emit_run_events }
	];
}

// ---------------------------------------------------------------------------
// Validation — the acceptance gate for every later phase
// ---------------------------------------------------------------------------

/// @function tune_compiled_validate(_compiled)
/// @description Check a compiled tune against the contract. Tolerates empty layers so that
///              stub compiles pass; reports structural violations once layers are populated.
/// @param {struct} _compiled  Compiled tune
/// @returns {struct}  Diagnostics collector describing any violations
function tune_compiled_validate(_compiled) {
	var _d = tune_diagnostics_create();

	if (!is_struct(_compiled)) {
		tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "compiled_not_struct", "Compiled tune is not a struct.");
		return _d;
	}

	var _required = ["schema_version", "tune_uid", "structure", "beat_grid", "events", "annotations"];
	for (var _i = 0; _i < array_length(_required); _i++) {
		if (!variable_struct_exists(_compiled, _required[_i])) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "compiled_missing_field",
				"Compiled tune is missing required field '" + _required[_i] + "'.");
		}
	}
	if (tune_diagnostics_has_errors(_d)) return _d;

	if (real(_compiled[$ "schema_version"]) != TUNE_PIPELINE_SCHEMA_VERSION) {
		tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "schema_version_mismatch",
			"Compiled schema_version " + string(_compiled[$ "schema_version"])
			+ " does not match compiler version " + string(TUNE_PIPELINE_SCHEMA_VERSION) + ".");
	}

	tune_compiled_validate_measures(_compiled, _d);
	tune_compiled_validate_events(_compiled, _d);
	tune_compiled_validate_annotations(_compiled, _d);

	return _d;
}

/// @function tune_compiled_validate_measures(_compiled, _d)
/// @description Check measure uid uniqueness and pickup beat-budget pairing in L0.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_measures(_compiled, _d) {
	var _structure = _compiled[$ "structure"];
	if (!is_struct(_structure)) return;

	var _measures = _structure[$ "measures"];
	if (!is_array(_measures)) return;

	var _seen = {};
	for (var _i = 0; _i < array_length(_measures); _i++) {
		var _m = _measures[_i];
		if (!is_struct(_m) || !variable_struct_exists(_m, "measure_uid")) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "measure_missing_uid",
				"Measure at index " + string(_i) + " has no measure_uid.");
			continue;
		}

		var _uid = string(_m[$ "measure_uid"]);
		if (variable_struct_exists(_seen, _uid)) {
			tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "measure_uid_duplicate",
				"Duplicate measure_uid.", { measure_uid: _uid });
		}
		variable_struct_set(_seen, _uid, true);

		// A pickup measure must name the measure that completes its beat budget.
		var _role = string(_m[$ "pickup_role"] ?? "none");
		if (_role == "pickup_head" || _role == "pickup_complement") {
			if (string(_m[$ "complement_uid"] ?? "") == "") {
				tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "pickup_missing_complement",
					"Measure has pickup_role '" + _role + "' but no complement_uid.",
					{ measure_uid: _uid });
			}
		}
	}
}

/// @function tune_compiled_validate_events(_compiled, _d)
/// @description Check event uid uniqueness per voice and that voices are declared in L2.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_events(_compiled, _d) {
	var _events = _compiled[$ "events"];
	if (!is_struct(_events)) return;

	var _voices = variable_struct_get_names(_events);
	for (var _v = 0; _v < array_length(_voices); _v++) {
		var _voice = _voices[_v];
		var _list = variable_struct_get(_events, _voice);
		if (!is_array(_list)) continue;

		var _seen = {};
		for (var _i = 0; _i < array_length(_list); _i++) {
			var _e = _list[_i];
			if (!is_struct(_e) || !variable_struct_exists(_e, "event_uid")) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_missing_uid",
					"Event at index " + string(_i) + " in voice '" + _voice + "' has no event_uid.");
				continue;
			}

			var _uid = string(_e[$ "event_uid"]);
			if (variable_struct_exists(_seen, _uid)) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_uid_duplicate",
					"Duplicate event_uid; ordinals must disambiguate simultaneous events.",
					{ event_uid: _uid });
			}
			variable_struct_set(_seen, _uid, true);

			if (is_undefined(tune_uid_parse_event(_uid))) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_uid_malformed",
					"event_uid does not parse as a grid reference.", { event_uid: _uid });
			}

			// Components are generated at run_build stage 6 and must not be stored.
			if (variable_struct_exists(_e, "components")) {
				tune_diagnostics_add(_d, TUNE_DIAG_ERROR, "event_has_components",
					"Compiled events store ornament attachments, not expanded components.",
					{ event_uid: _uid });
			}
		}
	}
}

/// @function tune_compiled_validate_annotations(_compiled, _d)
/// @description Check that every annotation targets a grid reference that exists.
/// @param {struct} _compiled  Compiled tune
/// @param {struct} _d         Diagnostics collector to append to
/// @returns {undefined}
function tune_compiled_validate_annotations(_compiled, _d) {
	var _annotations = _compiled[$ "annotations"];
	if (!is_array(_annotations)) return;

	for (var _i = 0; _i < array_length(_annotations); _i++) {
		var _a = _annotations[_i];
		var _t = is_struct(_a) ? _a[$ "target"] : undefined;
		if (!is_struct(_t)) {
			tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "annotation_no_target",
				"Annotation at index " + string(_i) + " has no target.");
			continue;
		}

		var _has = variable_struct_exists(_t, "measure_uid")
			|| variable_struct_exists(_t, "beat_uid")
			|| variable_struct_exists(_t, "event_uid");
		if (!_has) {
			tune_diagnostics_add(_d, TUNE_DIAG_WARNING, "annotation_target_empty",
				"Annotation target names no measure, beat or event.");
		}
	}
}
