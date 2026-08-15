# WORKSPACE_MAP.md

**Purpose:** Structured navigation guide for AI coding agents. Read this before planning any change. Prefer existing globals, structs, and functions documented here over creating new ones.

**Maintenance rule:** When adding or changing any function — update its `/// @` header block in code AND update its row in the Script Registry below.

## Script Registry (Scoring Addendum)

### Tune Pipeline Foundation (2026-08-14)

Contract: **`TUNE_PIPELINE_CONTRACT.md`** — read it before touching any of these.
All stages below are no-op stubs; they define the ordering contract, not behaviour yet.

| Script | Function | Purpose | Reads | Writes | Callers |
|---|---|---|---|---|---|
| `scr_tune_uid.gml` | `tune_uid_measure`, `tune_uid_beat`, `tune_uid_event`, `tune_uid_component`, `tune_uid_run_ref` | Build grid references from musical position (contract §2.1). Never derive a UID from iteration or row order. | function params | none | pipeline stages, validator |
| `scr_tune_uid.gml` | `tune_uid_parse_event`, `tune_uid_parse_measure`, `tune_uid_strip_run_ref` | Decompose grid references back into position fields. | function params | none | `tune_compiled_validate_events` |
| `scr_tune_uid.gml` | `tune_uid_side_from_anchor` | Derive ornament side (`lead`/`trail`) from the single `anchor` field (§2.1.2). Side is never stored separately. | function params | none | `tune_uid_component` |
| `scr_tune_uid.gml` | `tune_uid_ordinal_tracker`, `tune_uid_next_ordinal`, `tune_uid_event_position_key` | Deterministic ordinals so simultaneous events (chords, unisons) get distinct UIDs. | tracker struct | tracker struct | `build_events` stage (future) |
| `scr_tune_diagnostics.gml` | `tune_diagnostics_create`, `tune_diagnostics_add`, `tune_diagnostics_merge`, `tune_diagnostics_filter` | Diagnostics as data (§9). No modal failure paths anywhere in the pipeline. | function params | collector struct | all compile stages |
| `scr_tune_diagnostics.gml` | `tune_diagnostics_has_errors`, `tune_diagnostics_format_item`, `tune_diagnostics_log` | Query and render diagnostics; logs to debug output until a diagnostics panel exists. | collector struct | debug output only | `tune_compile` |
| `scr_tune_provenance.gml` | `tune_provenance_create`, `tune_provenance_matches` | Stamp and verify artifact identity (§8) so caches invalidate safely. `compiled_at` is excluded from comparison. | ABC text, tune config | none | `tune_compile_stage_stamp_provenance`, cache load (future) |
| `scr_tune_provenance.gml` | `tune_provenance_canonical`, `tune_provenance_sort_names`, `tune_provenance_string_gt`, `tune_provenance_hash` | Deterministic struct serialisation for hashing. GameMaker does not guarantee member order, so `json_stringify` is unsafe here. | any value | none | `tune_provenance_create` |
| `scr_tune_compile.gml` | `tune_compiled_create_empty`, `tune_compile_context` | Compiled-tune envelope (layers L0/L1/L2/L4) and the mutable stage context. | function params | none | `tune_compile` |
| `scr_tune_compile.gml` | `tune_compile_stages`, `tune_compile` | Ordered compile stage list and runner (§10). L2 preserves explicit broken-rhythm pairs with stable pair UID, long/short roles and conserved pair units. | ABC text, tune config | none | authoring compile |
| `scr_tune_compile.gml` | `tune_compiled_voice_map`, `tune_compiled_melody_map`, `tune_voice_is_bagpipe`, `tune_voice_map_apply_rhythm` | Per-voice compiled views and independent run working copies. Bagpipe parts are marked for rhythm/embellishment rules; backing voices remain direct-MIDI. Identity rhythm is used until rules are configured. | compiled tune, run config | returned views | run-build context, visualizer/scoring (future) |
| `scr_tune_compile.gml` | `tune_rhythm_registry_load`, `tune_rhythm_profile_find`, `tune_rhythm_resolve`, `tune_pulse_normalize`, `run_build_warp_units` | Resolve pointing/pulse profiles. Pulse meter and slot count must match; weights normalize and warp within each actual measure without moving its boundaries. | rhythm registry, compiled L0/L1, run config | resolved profiles, projected units | run-build resolve/ms projection |
| `scr_tune_compile.gml` | `run_build`, `run_build_stages` + `run_build_stage_*` | Compiled unit-space events become scheduler events at selected BPM with resolved pointing and meter-safe pulse. Logs `[RHYTHM]` profile IDs; embellishments remain deferred. | compiled tune, run config | returned playback events | `scr_button_prepare_single_tune_playback_events` |
| `scr_tune_compile.gml` | `tune_compiled_validate` (+ `_measures`, `_events`, `_annotations`) | Acceptance gate for every later phase: UID uniqueness, pickup complement pairing, no stored ornament components, annotation targets resolve. | compiled tune | none | `tune_compile`, phase acceptance tests |
| `scr_tune_abc_parse.gml` | `abc_tokenize`, `abc_expand_repeats` | ABC text -> tokens -> repeat-flattened tokens. Reproduces `TokenizeABC` / `ExpandRepeats` semantics. | ABC body text | none | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_parse_headers`, `abc_extract_body`, `abc_list_voices`, `abc_parse_voice_id` | ABC information fields, voice inventory, and body flattening per voice. | ABC source | none | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_rhythmic_constants`, `abc_parse_fraction`, `abc_meter_to_timesig` | Meter/unit-length maths: units per beat, beats per measure, units per measure. | header struct | none | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_build_flat_events` | Tokens -> unit-space events with running `total_units`, handling ties, tuplets and broken rhythm. | tokens, rhythmic constants | none | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_infer_broken_rhythms` | Infer explicit pair semantics from curated ABC duration pairs (`1.5/0.5` or `0.5/1.5`), skipping ornaments and stopping at bars. | flat voice events | `broken_dir` on first pair note | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_build_bar_phase_map`, `abc_position_from_units`, `abc_annotate_positions` | Downbeat anchors for initial and internal pickups; measure/beat/division from unit totals. Measure 0 means inside a pickup. | flat events, constants | event position fields | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_populate_embellishment_targets` | Fill each embellishment's preceding and target note letters. | flat events | event emb fields | `abc_parse_to_flat_events` |
| `scr_tune_abc_parse.gml` | `abc_parse_to_flat_events` | Full ABC -> unit-space event pipeline for one voice. | ABC source | none | `tune_shadow_diff_tune` |
| `scr_tune_shadow_diff.gml` | `tune_shadow_diff_tune`, `tune_shadow_diff_all` | **Phase 2 validation only.** Diff parser output against exported `tune.json`. Bound to dev key **P** in `obj_game_controller` Step. Delete at cutover. | tune `.abc` + `.json` | debug output only | manual (key P) |
| `scr_tune_manifest.gml` | `tune_manifest_exists`, `tune_manifest_read`, `tune_manifest_path` | **Tune discovery.** A folder is a tune iff it contains `tune.meta.json` (contract §7, invariant 15). Presence test, never a glob. | `<folder>/tune.meta.json` | none | library scan (future), authoring |
| `scr_tune_load.gml` | `scr_tune_load_compiled_json` | Load and validate a manifest-backed compiled tune plus authored profile choices into `obj_tune.tune_data`. | compiled artifact, sibling manifest | `global.tune.tune_data.compiled`, `.authored` | `scr_button_try_load_tune_candidate` |
| `scr_tune_manifest.gml` | `tune_manifest_build`, `tune_manifest_write`, `tune_manifest_detect_artifacts` | Build/refresh a manifest: identity + descriptive metadata + asset map. Authored fields (`tune_uid`, `authored`, `annotations`, `tags`) are preserved across rebuilds. | folder contents, ABC headers, legacy JSON | `<folder>/tune.meta.json` | `tune_author_create_from_abc`, `tune_manifest_backfill_all` |
| `scr_tune_manifest.gml` | `tune_manifest_backfill_all` | One-shot: write a manifest into every tune folder, inventorying existing assets including `legacy_events`. Bound to dev key **I**. | tunes root | manifests | manual (key I) |
| `scr_tune_authoring.gml` | `tune_author_create_from_abc`, `tune_author_create_from_staged` | **New-tune workflow.** ABC in -> folder with `.abc`, `.compiled.json`, `tune.meta.json`. Never writes legacy `.json` or `score/`. Bound to dev key **N**. | `datafiles/tunes/_incoming/*.abc` | tune folders | manual (key N) |
| `scr_tune_authoring.gml` | `tune_author_index_entry`, `tune_author_log_summary` | Build a `tune_library` index row and print a structure summary. Index row is not yet persisted. | compiled tune, diagnostics | none | `tune_author_create_from_abc` |
| `scr_tune_authoring.gml` | `tune_author_log_compiled_detail` | Read-only debug dump of L0 structure, L1 beat grid and unexpanded L2 events. Bound to dev key **V**. | loaded compiled tune | debug output only | manual (key V) |

### Structure-Time Unification Addendum (2026-07-30)

| Script | Function | Purpose | Reads | Writes | Callers |
|---|---|---|---|---|---|
| `scr_preprocess_tune.gml` | `tune_build_playable_events(_tune, _tempo, _unit_ms, _base_midi, _channel, _events, _grace_override_ms)` | Builds ms-timed planned playback events and now preserves `part` identity on emitted marker/note_on/note_off rows (including embellishment paths) so downstream ownership/nav/scoring can map structure without defaulting to part 1. | tune event structs, embellishment library/config | returned playable event array | `scr_preprocess_tune` |
| `scr_game_viz.gml` | `gv_build_planned_spans(_events)` | Converts planned note_on/note_off events into planned spans and now carries `part` + `measure_ref_key_seed` (`part:measure`) for key-based structure lookup migration. | planned events, chanter note mapping helpers | returned planned span array | `gv_bind_timeline_on_tune_start` |
| `scr_game_viz.gml` | `gv_measure_nav_hit_test(_mx, _my)` | Hit-tests tune-structure panel and returns full tile identity (`measure`, `part`, `nav_idx`, `struct_idx`, `segment_id`, `display_row`, `display_col`, `display_kind`) for canonical display mapping and click routing. | `global.timeline_state.measure_nav_controls`, `global.timeline_state.measure_nav_tile_hitboxes` | none | `gv_measure_nav_handle_click`, `gv_review_handle_click` |
| `scr_game_viz.gml` | `gv_build_tune_structure_model_from_measure_nav(_measure_nav)` | Builds Stage-1 canonical tune-structure model (segment identity + display metadata hints) from measure-nav entries and enriches segments with ownership windows from `scr_button_build_measure_nav_map_for_ownership(global.playback_events)` when available (`owner_nav_idx`, `owner_start_ms`, `owner_end_ms`, plus timeline windows). | `global.timeline_state.measure_ms`, measure-nav fields, `global.playback_events`, ownership-nav builder | returned model struct | `gv_tune_structure_refresh_model_from_measure_nav` |
| `scr_game_viz.gml` | `gv_build_measure_nav_map(_planned_events)` | Builds canonical structural segments directly from event-bar boundaries (`marker` bar anchors) and stamps monotonic `struct_idx` order; snippet/image metadata is intentionally excluded from structural authority. | `global.playback_context`, `global.loop_runtime_active`, marker metadata on planned events (`owner_measure`, `owner_part`, `loop_iteration`, bar-anchor fields), timeline measure defaults | returned measure-nav map (`entries` include `struct_idx`) | `gv_bind_timeline_on_tune_start` |
| `scr_game_viz.gml` | `gv_tune_structure_refresh_model_from_measure_nav(_measure_nav, _reason)` | Refreshes cached canonical tune-structure model and parity summary on measure-nav updates; optional parity log output behind config flag. | `global.timeline_cfg.tune_structure_model_build_enabled`, `global.timeline_cfg.tune_structure_model_parity_log` | `global.timeline_state.tune_structure_model`, `global.timeline_state.tune_structure_model_parity`, `global.timeline_state.tune_structure_model_reason` | `gv_measure_nav_apply_to_timeline_state` |
| `scr_game_viz.gml` | `gv_tune_structure_rule_classify_segment(_entry, _measure_ms)` + rule helpers | Human-readable Stage-1 inference rules for segment classification (`full`/`pickup`/`partial`) and display row-kind derivation (`full_row`/`pickup_row`) used by canonical model build. | measure-nav entry timing/measure fields | returned rule outputs | `gv_build_tune_structure_model_from_measure_nav` |
| `scr_game_viz.gml` | `gv_tune_structure_model_resolve_musical_measure_at_time(_time_ms, _fallback_measure)` | Resolves timeline measure labels from canonical model (`musical_measure_idx`) when model is enabled, with deterministic fallback to legacy event measure labels. | `global.timeline_state.tune_structure_model` | none | `gv_draw_structure_row` |
| `scr_game_viz.gml` | `gv_tune_structure_model_resolve_musical_measure_for_nav_idx(_source_nav_idx, _fallback_measure)` | Resolves tune-structure panel section/fallback labels from canonical model by source nav index, preserving legacy labels when model data is absent. | `global.timeline_state.tune_structure_model` | none | `gv_draw_tune_structure_panel` |
| `scr_game_viz.gml` | `gv_tune_structure_model_build_panel_entries(_fallback_entries)` | Stage-2 panel source bridge: when canonical model flag is enabled, projects tune-structure tile source rows from model segments (with legacy fallback) while preserving source nav identity mapping for click/selection paths. | `global.timeline_cfg.use_canonical_tune_structure_model`, `global.timeline_state.tune_structure_model` | none | `gv_draw_tune_structure_panel` |
| `scr_game_viz.gml` | `gv_tune_structure_model_resolve_context_at_time(_time_ms)` | Resolves structural context (`part`, `source_measure`, `source_nav_idx`, canonical key) directly from canonical tune-structure model windows when the model flag is enabled. | `global.timeline_cfg.use_canonical_tune_structure_model`, `global.timeline_state.tune_structure_model` | none | `gv_resolve_measure_context` |
| `scr_game_viz.gml` | `gv_tune_structure_model_find_segment(_part, _measure, _nav_idx)` / `gv_tune_structure_model_find_next_segment(_part, _measure, _nav_idx)` | Canonical model lookup helpers for exact/current segment and following segment resolution by structural identity; used to unify structural window lookup and loop end-boundary metadata. | `global.timeline_state.tune_structure_model` | none | `map_context_to_window`, `gv_loop_resolve_boundary_endpoints` |
| `scr_game_viz.gml` | `gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2)` | Tune-structure panel now projects canonical display slots with deterministic tile metadata. Pickup rows (`display_row_kind=pickup_row`) render as first-tile entries plus spacer tiles, preserving fixed grid geometry while keeping pickup identity explicit. Current-tile highlight and auto-follow prefer canonical `segment_id`, then source-nav fallback from normalized panel time (`nav_display_ms`). | `global.timeline_cfg.tune_structure_show_pickup_rows`, `global.timeline_state.measure_nav_entries`, canonical model helpers | `global.timeline_state.measure_nav_tile_hitboxes` (includes `segment_id` + display metadata), controls/scroll state | RoomUI tune-structure anchor draw path |
| `scr_scoring.gml` | `scoring_measure_ref_key(_part_num, _measure_num, _nav_idx)` | Builds canonical structural score key (`part:measure[:nav_idx]`) for map storage/lookup. | function params | none | scoring key-map helpers + style/result lookup paths |
| `scr_scoring.gml` | `scoring_measure_results_to_key_map(_measure_results)` | Builds canonical key-based score map from per-measure scoring results for runtime lookup/persistence. | measure result array | none | `scoring_apply_run_to_runtime`, set-segment summary build |
| `scr_scoring.gml` | `scoring_measure_result_matches(_m, _measure_num, _part_num, _nav_idx, _measure_key)` | Compares lookup context against measure results with key-first, then part/measure fallback matching. | measure result row + lookup context | none | `scoring_find_measure_result` |
| `scr_scoring.gml` | `scoring_apply_run_to_runtime(_run_summary, _promote_selected)` | Persists scoring run outputs to canonical key maps (`timeline_state.score_measure_maps_by_key`) including per-segment merge. | scoring summary + timeline state | `global.timeline_state.score_measure_maps_by_key`, score globals | `scoring_build_ms_overlap_summary` |
| `scr_scoring.gml` | `scoring_get_measure_visual_style(_measure, _default_color, _default_alpha, [_part_num], [_nav_idx], [_measure_key])` | Resolves measure tile style from canonical key-based maps using key-first then part/measure seed fallback. | `global.timeline_state.score_measure_maps_by_key`, playback context | none | tune-structure panel draw path |
| `scr_game_viz.gml` | `gv_scoring_get_selected_measure_context()` | Resolves current scoring selection context (`measure`, `part`, `nav_idx`, `measure_key`) from canonical selection key (`score_popup_measure_key`) with nav fallback from state. | `global.timeline_state.score_popup_measure_key`, `global.timeline_state.score_popup_nav_idx` | none | scoring panel wrappers (`gv_scoring_get_judge_rows`, `gv_scoring_get_panel_focus`, `gv_scoring_get_popup_lines`) |
| `scr_game_viz.gml` | `gv_scoring_set_selected_measure_key(_measure_key, [_nav_idx])` | Writes canonical score selection identity and derives legacy numeric selection field from parsed key for compatibility. | function params | `global.timeline_state.score_popup_measure_key`, `global.timeline_state.score_popup_nav_idx`, `global.timeline_state.score_popup_measure` | review click flow, now-line sync |
| `scr_scoring.gml` | `scoring_get_judge_table_rows(_measure_num, _judge_id, [_part_num], [_nav_idx], [_measure_key])` | Builds judge rows for selected scope; per-measure rows use canonical key-aware lookup and post-play overall rows are window-scoped to the selected loop iteration when active. | scoring summary/state, lookup context, `timeline_state.review_selected_loop_window` | none | scoring panel table |
| `scr_scoring.gml` | `scoring_get_detail_popup_rows(_measure_num, _judge_id, [_part_num], [_nav_idx], [_measure_key])` | Builds detail popup rows for selected scope using key-aware measure lookup; overall scope is window-scoped to selected loop iteration in post-play loop review. | scoring summary/state, playback context, lookup context, `timeline_state.review_selected_loop_window` | none | scoring detail popup UI |
| `scr_scoring.gml` | `scoring_get_panel_focus(_measure_num, _judge_id, [_part_num], [_nav_idx], [_measure_key])` | Builds panel header focus (score/subtitle) with key-aware measure resolution; overall score/subtitle switch to selected loop iteration window in post-play loop review. | scoring summary/state, playback context, lookup context, `timeline_state.review_selected_loop_window` | none | scoring panel header |
| `scr_scoring.gml` | `scoring_get_review_selected_loop_window()` | Returns validated selected loop review window (`iteration,start_ms,end_ms`) only when post-play loop-iteration context is active. | `global.timeline_state.playback_complete`, `global.timeline_state.loop_iteration_scores`, `global.timeline_state.review_selected_loop_iteration`, `global.timeline_state.review_selected_loop_window` | none | loop-window scoped scoring panel helpers |
| `scr_scoring.gml` | `scoring_window_aggregate_from_measure_results(_measure_results, _start_ms, _end_ms, _judge_id)` | Aggregates overlap metrics and score from measure-results rows that overlap a window; used to compute selected-loop-iteration overall scores. | measure result arrays, overlap settings | none | `scoring_get_judge_table_rows`, `scoring_get_panel_focus`, `scoring_get_detail_popup_rows` |
| `scr_scoring.gml` | `scoring_get_measure_popup_rows(_measure_num, [_judge_id], [_part_num], [_nav_idx], [_measure_key])` | Compatibility wrapper to detail popup builder; now accepts forwarded key context. | timeline selected judge, lookup context | none | popup fallback path |
| `scr_game_viz.gml` | `gv_review_handle_click(_mx, _my)` | Review selection stores canonical popup identity (`score_popup_measure_key` as `part:measure[:nav]`) + `score_popup_nav_idx`, uses canonical key identity for select/deselect toggle behavior, and delegates jumps to `gv_review_jump_to_measure` for part-aware navigation. | measure hit identity, timeline state, canonical mapping helpers | `global.timeline_state.score_popup_measure`, `global.timeline_state.score_popup_measure_key`, `global.timeline_state.score_popup_nav_idx`, `global.timeline_state.playhead_ms` | post-play review click flow |
| `scr_game_viz.gml` | `map_time_to_context(_time_ms)` | Canonical context resolver that maps timeline time to structural identity (`part`, `measure`, `nav_idx`, `measure_ref_key`) with source priority: loop-session windows -> measure-nav -> legacy fallback. | `global.timeline_state`, `global.playback_context`, loop runtime globals | none | `gv_resolve_measure_context` |
| `scr_game_viz.gml` | `gv_resolve_measure_context(_time_ms)` | Central structural resolver: prefers canonical tune-structure model windows when enabled, then mapper output, then legacy measure fallback, normalizing reads (`measure`, `part`, `nav_idx`, `struct_idx`, `measure_ref_key`, `segment_id`) in one place. | `gv_tune_structure_model_resolve_context_at_time`, `map_time_to_context`, `gv_get_current_planned_measure`, highlight cache globals | none | `gv_sync_now_line_display`, tune-structure panel draw, world overlay draw, segment-transition reseed, score-lane probe |
| `scr_game_viz.gml` | `map_context_to_window(_measure_ref_key)` | Canonical window resolver for structural keys (`part:measure[:nav]`) returning time bounds and source metadata; priority is active loop-session refs, then canonical tune-structure model windows, then legacy measure-nav/state fallbacks. | loop session refs/segments, canonical model helpers, `measure_nav_entries`, `structural_measure_starts` | none | mapping API consumers (Phase D migration) |
| `scr_game_viz.gml` | `gv_review_jump_to_measure(_measure, [_part], [_nav_idx], [_measure_key])` | Review jump helper resolves target time via canonical key/window mapping first, then part/nav-consistent local nav fallback (no measure-only cross-occurrence fallback). | `map_context_to_window`, `measure_nav_entries`, review timing state | `global.timeline_state.playhead_ms`, `global.timeline_state.review_measure_offset`, `global.timeline_state.review_mode` | `gv_measure_nav_handle_click`, `gv_review_handle_click` |
| `scr_game_viz.gml` | `gv_draw_timeline_canvas_overlay(_x1, _y1, _x2, _y2)` | Score-lane draw now uses unified sprite mapping precedence (primary structural candidate -> seq -> measure) across loop/non-loop/set paths; in single-tune structural mode, caps structural snippet windows to selected-channel playable measure extent to avoid non-playing tail images; optional debug source tagging via `timeline_cfg.score_lane_debug_show_source`. | planned events, score caches/maps, loop session, timeline cfg/debug flags | timeline score debug output/log lines | runtime timeline/score lane rendering |
| `scr_tune_load.gml` | `scr_score_manifest_resolve_source(_manifest, _part_channel)` | Canonical score-image source resolver for multi-part tunes: exact channel match, explicit default group/channel, marked default group, then base-manifest fallback. Prevents unmatched channel selection from drifting to the wrong harmony group. | score manifest groups/default fields, selected part channel | none | `scr_score_sprites_load`, `scr_score_manifest_select_group` |
| `scr_tune_load.gml` | `scr_score_sprites_load(_filename, _manifest)` | Loads score sprites using centralized score-source resolution so single-tune reload, set preloads, and part-switch reloads share one deterministic part-to-score mapping contract. | score manifest, selected part channel, resolved source metadata | `global.score_lane_sprites`, `global.score_playback_map`, `global.score_measure_map`, `global.score_lane_meta`, `global.score_transition_images`, `global.score_snippet_durations`, `global.score_has_pickup` | tune load/reload + set segment preloads |
| `scr_tune_load.gml` | `scr_score_segment_runtime_cache_clear()` | Deletes dynamic score and transition-override sprites retained by all prior set segment runtime caches before cache replacement. | `global.score_segments_sprites` | `global.score_segments_sprites`, `global.score_override_groups`, dynamic sprite assets | `scr_goto_playroom` set preload |

| Script | Function | Purpose | Reads | Writes | Callers |
|---|---|---|---|---|---|
| `scr_scoring.gml` | `scoring_judge_profile_get(_judge_id)` | Returns judge profile metadata (name, description, variable list, compact row order) for detail popup rendering. | none | none | `scoring_get_detail_popup_rows` |
| `scr_scoring.gml` | `scoring_judge_normalize_id(_judge_id)` | Normalizes deprecated/non-production judge IDs (`note_match`, `event_match*`, `on_beat*`, legacy emb-window) to active overlap equivalents. | judge id input | none | judge settings load, judge dispatch, note popup scoring |
| `scr_scoring.gml` | `scoring_judge_settings_get_registry()` | Builds descriptor-driven active judge registry (overlap-only: calibrated + uncalibrated), merges shared overlap bucket settings, and returns enabled/stateful rows for UI/execution. | `global.judge_settings_store` | none | scoring settings UI, judge table, playback-finish execution |
| `scr_scoring.gml` | `scoring_struct_get_or_default(_s, _key, _default)` | Centralized struct field read with explicit existence check and default fallback. | input struct field | none | scoring helpers, event-match normalization |
| `scr_scoring.gml` | `scoring_struct_get_real_default(_s, _key, _default)` | Typed numeric wrapper for guarded struct field reads. | input struct field | none | event-match target/player/settings normalization |
| `scr_scoring.gml` | `scoring_struct_get_int_default(_s, _key, _default)` | Integer wrapper for guarded struct field reads (`floor(real(...))`). | input struct field | none | event-match target/player normalization |
| `scr_scoring.gml` | `scoring_struct_get_bool_default(_s, _key, _default)` | Boolean wrapper for guarded struct field reads. | input struct field | none | event-match settings/target filtering |
| `scr_scoring.gml` | `scoring_struct_get_string_default(_s, _key, _default)` | String wrapper for guarded struct field reads. | input struct field | none | event-match target normalization |
| `scr_scoring.gml` | `scoring_struct_require_real(_s, _key, _context)` | Fail-fast required numeric field accessor with context-rich error messages. | input struct field | none | event-match player/target normalization |
| `scr_scoring.gml` | `scoring_event_match_normalize_settings(_settings)` | Produces a complete event-match settings contract (all keys populated, clamped ranges) for reusable matcher internals. | judge settings struct | none | `scoring_build_event_match_summary`, `scoring_event_match_collect_targets`, `scoring_event_match_pair_cost`, `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_judge_get_setting_defs(_judge_id)` | Returns edit metadata for active overlap judge settings UI rows. | judge id input | none | settings UI, judge profile popup |
| `scr_scoring.gml` | `scoring_on_beat_build_intervals(_targets, _lead_in_ms, _tail_out_ms)` | Builds midpoint ownership intervals around sorted expected target onsets for deterministic target assignment. | target array | none | `scoring_build_on_beat_summary` |
| `scr_scoring.gml` | `scoring_on_beat_find_interval_index(_intervals, _time_ms)` | Binary-searches interval ownership for a player onset timestamp. | interval array | none | `scoring_build_on_beat_summary` |
| `scr_scoring.gml` | `scoring_on_beat_note_has_preceding_embellishment(_planned_spans, _note_index, _lookback_ms)` | Detects whether a beat-start non-emb note is a grace-led target (immediately preceded by embellishment spans) so it can be excluded from On Beat note targets. | planned spans | none | `scoring_on_beat_collect_targets` |
| `scr_scoring.gml` | `scoring_build_on_beat_summary(_export_info, _judge_id, _apply_to_runtime)` | Archived compatibility wrapper for retired On Beat judge path; delegates to overlap summary. | export context, overlap scorer globals | `global.timeline_state` (via `scoring_apply_run_to_runtime`) | direct/manual only |
| `scr_scoring.gml` | `scoring_event_match_collect_player_onsets(_player_spans)` | Builds sorted player-onset rows (`start_ms`, lane, measure, duration, inferred role) for shared post-play target matching. | player spans, `global.gracenote_override_ms` | none | `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_target_neighborhood_ms(_target, _settings)` | Computes tempo-scaled per-target candidate neighborhood radius (beat-scaled with min clamp) used to gate plausible matches. | target row, matcher settings, `global.current_bpm` | none | `scoring_event_match_pair_cost` |
| `scr_scoring.gml` | `scoring_event_match_build_phrase_cluster_index(_planned_spans)` | Builds phrase-cluster metadata by grouping consecutive embellishment spans and the following target melody note. | planned spans | none | `scoring_event_match_compile_slots` |
| `scr_scoring.gml` | `scoring_event_match_compile_slots(_planned_spans, _settings)` | Compiles canonical matcher slots (note slots + phrase-cluster embellishment slots) with cluster/role metadata, per-slot tempo hints, and stable global planned-span identity fields for downstream UI mapping. | planned spans, matcher settings | none | `scoring_event_match_collect_targets`, `scoring_build_event_match_summary` |
| `scr_scoring.gml` | `scoring_event_match_collect_targets(_planned_spans, _settings)` | Compatibility wrapper that returns compiled canonical matcher slots from `scoring_event_match_compile_slots`. | planned spans, matcher settings | none | `scoring_build_event_match_summary` |
| `scr_scoring.gml` | `scoring_event_match_classify_pair(_target, _player, _settings)` | Classifies candidate target-player pairs for pitch/duration plausibility, noise tagging, and envelope class labels shared by costing and output diagnostics. | target/player rows, matcher settings, `global.gracenote_override_ms` | none | `scoring_event_match_pair_cost`, `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_pair_cost(_target, _player, _settings, _interval_owner_idx, _target_index)` | Computes per-pair alignment cost for DP matching (tempo-scaled neighborhood gate, timing, role mismatch, lane mismatch, interval prior, plausibility, grace-order). | target/player rows, matcher settings | none | `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_build_assignment(_target, _player, _settings, _target_index, _player_match_index, _pair_cost, _delta_ms)` | Builds a normalized canonical assignment row shared by anchor reservation and DP matching, including local and global planned-span identity keys. | target/player rows, matcher settings | none | `scoring_event_match_assign_targets_dp`, `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_collect_measure_keys(_targets)` | Collects sorted unique measure keys present in canonical matcher targets for measure-window execution. | matcher targets | none | `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_find_anchor_candidate(_target, _players, _candidate_player_indices, _player_claimed, _settings)` | Selects the best unclaimed player onset for a note target, strongly preferring exact-lane anchors before residual matching. | target/player rows, claimed-player state, matcher settings | none | `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_assign_targets_dp(_targets, _players, _settings)` | Internal monotonic DP assignment over already-normalized local target/player rows, used as the residual matcher inside measure windows. | local matcher targets, local player rows, matcher settings | none | `scoring_event_match_assign_targets` |
| `scr_scoring.gml` | `scoring_event_match_assign_targets(_targets, _player_spans, _settings)` | Canonical matcher wrapper executing full-problem monotonic DP (no anchor-first pre-pruning), preserving global optimality and stable identity maps. | matcher targets, player spans, matcher settings | none | `scoring_build_event_match_summary`, `scoring_build_on_beat_summary` |
| `scr_scoring.gml` | `scoring_build_event_match_summary(_export_info, _judge_id, _apply_to_runtime)` | Archived compatibility wrapper for retired event-match judge path; delegates to overlap summary. | export context, overlap scorer globals | `global.timeline_state` (via `scoring_apply_run_to_runtime`) | direct/manual only |
| `scr_scoring.gml` | `scoring_build_note_match_summary(_export_info, _judge_id, _apply_to_runtime)` | Archived compatibility wrapper for retired note-match judge path; delegates to overlap summary. | export context, overlap scorer globals | `global.timeline_state` (via `scoring_apply_run_to_runtime`) | direct/manual only |
| `scr_game_viz.gml` | `gv_handle_notebeam_click(_mx, _my, _x1, _y1, _x2, _y2)` | Handles post-play notebeam click selection and resolves planned context via overlap-based span overlap fallback (no matcher assignment dependency). | `global.timeline_state.playback_complete`, `global.timeline_state.notebeam_player_hitboxes`, `global.timeline_state.planned_spans` | `global.timeline_state.notebeam_note_popup` | review click flow |
| `scr_scoring.gml` | `scoring_build_on_beat_rollup_summary(_export_info, _apply_to_runtime)` | Archived compatibility wrapper for retired On Beat rollup path; delegates to overlap summary. | export context, overlap scorer globals | `global.timeline_state` (via `scoring_apply_run_to_runtime`) | direct/manual only |
| `scr_scoring.gml` | `scoring_run_judge_summary(_export_info, _judge_id, _apply_to_runtime)` | Dispatches runtime judge execution in overlap-only mode (`ms_overlap` + `ms_overlap_uncal`) while preserving registry-driven architecture. | judge id + export context | `global.timeline_state` (via delegated scorer) | `gv_on_tune_playback_finished` |
| `scr_scoring.gml` | `scoring_get_note_popup_score_summary(_player_span, _planned_span, _judge_id)` | Builds the current selected judge score summary for the clicked note popup using overlap-mode measure score context. | `global.timeline_state`, span structs | none | `gv_draw_notebeam_note_popup` |
| `scr_scoring.gml` | `scoring_detail_metric_format(_label, _value, _format)` | Formats detail metric values for popup row text output. | none | none | `scoring_get_detail_popup_rows` |
| `scr_scoring.gml` | `scoring_get_detail_popup_rows(_measure_num, _judge_id, [_part_num], [_nav_idx], [_measure_key])` | Builds profile-driven detail popup rows for selected judge and scope, now accepting optional canonical key context for part-aware lookup. | `global.scoring_last_run`, `global.timeline_state`, `global.playback_context` | none | scoring detail popup UI |
| `scr_event_log.gml` | `event_history_get_export_info(_timestamp)` | Builds shared export metadata and benchmark context (device names, scheduler mode, manual run labels) for CSV/summary exports. | `global.current_tune_name`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.current_player_id`, `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS`, `global.PERF_BENCHMARK_*`, MIDI device globals | none | `event_history_export_csv`, `event_history_export_summary_json`, `event_history_export_loop_session_json` |
| `scr_event_log.gml` | `event_history_export_csv(_filename_or_path)` | Exports event history CSV from the effective event stream with optional export-time filter to omit planned `source=game` rows. | `event_history_get_effective_events`, `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS` | CSV file output | manual export / end-of-tune export |
| `scr_event_log.gml` | `event_history_export_summary_json(_filename_or_path, _export_info)` | Exports summary JSON including `export_filter` and `benchmark_context` metadata for objective run comparisons, sampling timing data from the effective event stream. | `event_history_get_effective_events`, `global.timeline_state`, export info fields | summary JSON file output | end-of-tune export |
| `scr_event_log.gml` | `event_runtime_clear()` | Resets minimal runtime player/planned sidecar arrays between runs. | `global.EVENT_RUNTIME_PLAYER`, `global.EVENT_RUNTIME_PLANNED` | `global.EVENT_RUNTIME_PLAYER`, `global.EVENT_RUNTIME_PLANNED` | `event_history_clear` |
| `scr_event_log.gml` | `event_runtime_capture_player(_event_type, _timestamp_ms, _note_midi, _channel, _velocity, _loop_iteration)` | Appends minimal per-input player runtime records for later reconstruction, avoiding export-only payload work in the hot path. | `global.EVENT_RUNTIME_CAPTURE_ENABLED`, `global.loop_runtime_*` | `global.EVENT_RUNTIME_PLAYER` | `MIDI_process_messages` |
| `scr_event_log.gml` | `event_runtime_capture_planned(_event_id, _actual_time_ms, _loop_iteration)` | Appends minimal planned-dispatch runtime records keyed by `event_id` and loop iteration directly from the playback callback, removing planned-history work from the deferred queue. | `global.EVENT_RUNTIME_CAPTURE_ENABLED`, `global.loop_runtime_*` | `global.EVENT_RUNTIME_PLANNED` | `script_tune_callback_batched` |
| `scr_game_viz.gml` | `gv_on_tune_playback_finished(_final_time_ms)` | Finalizes playback, enters review mode, and executes enabled overlap judges from scoring registry via `scoring_run_judge_summary` before restoring preferred selected judge. | `global.timeline_state`, `global.judge_settings_store` | `global.timeline_state` scoring maps/selection | tune end flow |
| `scr_event_log.gml` | `event_history_build_from_runtime()` | Reconstructs legacy-style event-history rows from minimal runtime sidecar stores plus the active playback-event table. | `global.EVENT_RUNTIME_PLAYER`, `global.EVENT_RUNTIME_PLANNED`, `global.playback_events_active`, `global.playback_events`, `global.timeline_cfg`, `global.current_tune_name`, `global.MIDI_chanter`, `global.METRONOME_CONFIG` | none | future export/scoring compatibility path |
| `scr_event_log.gml` | `event_history_get_effective_events()` | Returns the export/scoring event stream, preferring runtime-sidecar reconstruction and merging non-runtime legacy rows such as tune-structure follow events. | `global.EVENT_HISTORY`, `global.EVENT_RUNTIME_PLAYER`, `global.EVENT_RUNTIME_PLANNED` | none | `event_history_update_tune_history_index`, `event_history_export_csv`, `event_history_export_summary_json`, `event_history_export_loop_session_json`, `scoring_build_loop_iteration_scores` |
| `scr_MIDI.gml` | `MIDI_enable_manual_polling()` | Central helper to enable manual MIDI message/error polling for active play/calibration sessions. | none | none | `MIDI_start_manual_check_messages`, `timing_calibration_start_midi_loopback`, `start_play` |
| `scr_MIDI.gml` | `MIDI_disable_manual_polling()` | Central helper to disable manual MIDI message/error polling when runs end or services stop. | none | none | `MIDI_stop_checking_messages_and_errors`, `timing_calibration_finish_midi_loopback`, tune finish callbacks |
| `scr_MIDI.gml` | `MIDI_process_messages()` | Processes buffered MIDI input for the frame, with fast empty-frame exit, direct byte fetches, canonical note mapping, optional legacy history fallback, and MIDI-thru output. | `global.midi_input_device`, `global.midi_output_device`, `global.chanter_channel`, `global.midi_input_clock_offset_ms`, `global.MIDI_chanter`, `global.tune_start_real`, `global.EVENT_HISTORY_ENABLED`, `global.EVENT_RUNTIME_CAPTURE_ENABLED`, `global.enable_current_note_layer`, `global.current_tune_name`, `global.timeline_cfg` | `global.midi_input_clock_offset_ms` | `obj_game_controller` Begin Step |
| `scr_game_viz.gml` | `gv_draw_tune_structure_panel(_x1, _y1, _x2, _y2)` | Draws tune-structure grid and drives playback auto-follow scroll from local measure-nav entry windows; in single-tune loop paths it projects to canonical one-pass display slots with pickup-row spacers, then writes nav+segment-aware tile hitboxes used by click/highlight/overlay (`measure`, `part`, `nav_idx`, `segment_id`, display row/col/kind). | `global.timeline_state.*`, `global.playback_context`, `global.timeline_cfg` | `global.timeline_state.measure_nav_scroll_row`, `global.timeline_state.measure_nav_total_rows`, `global.timeline_state.measure_nav_view_rows`, `global.timeline_state.measure_nav_tile_hitboxes`, `global.timeline_state.measure_nav_controls`, `global.timeline_state.measure_nav_auto_follow_last_ms` | gameviz panel draw pipeline |
| `scr_game_viz.gml` | `gv_build_loop_runtime_cache(_events)` | Builds loop runtime cache for single-tune looping; when `loop_session.timeline_segments[]` is available, uses those explicit time segments as primary measure-start source (timeline layer) before marker-derived fallback, reducing pickup/partial-measure ambiguity in loop projection. | planned loop events (`global.playback_events_active`), `global.timeline_state.loop_session.timeline_segments` | `global.timeline_state.loop_runtime_cache` (via caller) | loop score/image projection + loop measure highlighting |
| `scr_game_viz.gml` | `gv_loop_get_selected_measure_refs()` | Returns part-aware loop selection refs carrying separate timeline and ownership windows: `timeline_start/end_ms` + `owner_start/end_ms`, with effective `start/end_ms` now set to the envelope of timeline/ownership windows when both exist, and preserves distinct `nav_idx` (timeline table) vs `owner_nav_idx` (ownership table). | `global.timeline_state.loop_selected_measures`, `global.timeline_state.measure_nav_entries`, `global.playback_events` | none | `scr_button_loop_build_playback_events` |
| `scr_game_viz.gml` | `gv_loop_resolve_boundary_endpoints(_selected_refs)` | Resolves canonical loop start/end boundary endpoints from selected refs (`time_ms` + part/measure/nav metadata), preferring timeline windows but now expanding the first/last selected boundaries to the envelope of timeline and ownership windows when ownership extends beyond the display window. Uses effective-window fallback otherwise; applies optional beat-level endpoint refinement from `timeline_state.loop_boundary_refinement` when enabled. End-boundary metadata now prefers the following canonical model segment when available before falling back to raw nav adjacency, but the resolved end time remains the exclusive cutoff at the selected boundary. For internal-pickup bars missing the final explicit beat marker, start-side implied final beat (`max_seen+1`) maps to the last in-measure marker time so pickup notes are included rather than skipped. | `global.timeline_state.measure_nav_entries`, canonical model helpers, `global.timeline_state.loop_boundary_refinement`, `global.playback_events`, selected refs | none | `scr_button_loop_build_playback_events` |
| `scr_game_viz.gml` | `gv_loop_clear_selected_measures()` | Clears loop measure selection state and resets the optional beat-level endpoint refinement payload to disabled defaults so stale refined endpoints cannot survive a new selection. | `global.timeline_state` | `global.timeline_state.loop_selected_measures`, `global.timeline_state.loop_last_selected_*`, `global.timeline_state.loop_boundary_refinement` | loop selection handlers, `scr_button_reset_loop_state` |
| `scr_game_viz.gml` | `gv_loop_sync_boundary_refinement_from_selection()` | Derives default boundary refinement endpoints from current selected measure refs using baseline boundary resolution (refinement disabled during derivation), then writes enabled start/end part+measure+beat defaults for backend/UI handoff. The resolved end boundary remains the exclusive cutoff, so the selected range does not include the first beat of the next measure. | `global.timeline_state.loop_selected_measures`, `global.timeline_state.loop_boundary_refinement` | `global.timeline_state.loop_boundary_refinement` | `gv_loop_select_measure`, `gv_loop_select_measure_range`, `gv_loop_select_nav_range` |
| `scr_game_viz.gml` | `gv_loop_select_measure(_measure, _selected, _part, _sync_defaults)` | Sets selection state for one measure tile and refreshes boundary-refinement defaults unless suppressed for bulk range operations. | `global.timeline_state.loop_selected_measures` | `global.timeline_state.loop_selected_measures`, `global.timeline_state.loop_last_selected_*`, `global.timeline_state.loop_boundary_refinement` | measure/nav selection handlers |
| `scr_game_viz.gml` | `gv_loop_select_measure_range(_m1, _m2, _additive, _part1, _part2)` | Applies inclusive measure range selection and then seeds boundary-refinement defaults from resulting selection. | `global.timeline_state.loop_selected_measures` | `global.timeline_state.loop_selected_measures`, `global.timeline_state.loop_last_selected_*`, `global.timeline_state.loop_boundary_refinement` | measure click/range flow |
| `scr_game_viz.gml` | `gv_loop_select_nav_range(_nav_idx_a, _nav_idx_b, _additive)` | Applies local nav-index range selection (part-aware) and then seeds boundary-refinement defaults from resulting selection. | `global.timeline_state.measure_nav_entries`, `global.timeline_state.loop_selected_measures` | `global.timeline_state.loop_selected_measures`, `global.timeline_state.loop_last_selected_*`, `global.timeline_state.loop_boundary_refinement` | measure click/shift-click flow |
| `scr_game_viz.gml` | `gv_log_measure_nav_page_turn(_playhead_ms, _measure_num, _from_scroll, _to_scroll, _target_row, _view_rows, _page_rows, _follow_mode)` | Records tune-structure follow row/page changes as structured `page_turn` events in `EVENT_HISTORY` and debug output. | `global.EVENT_HISTORY_ENABLED`, `global.current_tune_name`, `global.playback_context` | `global.EVENT_HISTORY` | `gv_draw_tune_structure_panel` |
| `scr_game_viz.gml` | `gv_measure_nav_find_local_idx(_ms, _measure_num)` | Resolves a panel-local measure-nav index for a wall-clock time and measure number; used to keep highlight indices in the same namespace as `measure_nav_entries`. | `global.timeline_state.measure_nav_entries` | none | `gv_get_current_planned_measure` |
| `scr_game_viz.gml` | `gv_get_current_planned_measure(_playhead_ms)` | Resolves active measure from playhead time; in single-tune loop mode normalizes to loop phase then resolves from `loop_session.timeline_segments[]` first (time placement), returning owner measure identity from the segment. Falls back to selected refs/nav logic when timeline segments are unavailable. | `global.timeline_state`, `global.playback_set_measure_nav_all`, `global.playback_context`, `global.timeline_cfg`, `global.timeline_state.loop_session.timeline_segments` | `global.timeline_state.measure_highlight_last_measure`, `global.timeline_state.measure_highlight_last_nav_idx`, `global.timeline_state.current_measure` | tune-structure panel draw/overlay, score sync |
| `scr_game_viz.gml` | `gv_count_selected_channel_score_measures(_events)` | Counts distinct playable measures on selected tune channel from planned note_on ownership labels, used to cap single-tune structural score rendering to actual selected-part playback extent. | `global.timeline_cfg.tune_channel`, planned events ownership fields | none | `gv_score_plan_prebuild_single_tune`, `gv_draw_timeline_canvas_overlay` |
| `scr_game_viz.gml` | `gv_notebeam_sync_window_from_cfg()` | Synchronizes timeline notebeam ms window from cfg by converting the current measure window into ms and refreshing the player-surface cache. | `global.timeline_state`, `global.timeline_cfg.measures_ahead`, `global.timeline_cfg.measures_behind`, `global.playback_context` | `global.timeline_state.ms_ahead`, `global.timeline_state.ms_behind` | `gv_notebeam_zoom_by_steps`, set transition sync path |
| `scr_game_viz.gml` | `gv_apply_cached_segment_runtime(_seg_idx)` | Applies preloaded score/override references, trimmed measure-nav, and canonical structure model for a set segment without file I/O or model rebuilding. | `global.score_segments_sprites` | score globals, timeline nav/model fields | live set boundary, start bind, review navigation |
| `scr_game_viz.gml` | `gv_score_plan_prebuild_single_tune(_planned_events)` | Prebuilds single-tune (non-set, non-loop) score render plan at bind/start so first draw can reuse cached measure starts immediately; in structural-duration mode, caps planned structural snippet count to selected-channel playable measure extent (pickup-aware) and keys cache/plan by target channel for deterministic part switching. | `global.timeline_state`, `global.timeline_cfg`, `global.loop_runtime_active`, `global.METRONOME_CONFIG`, `global.score_snippet_durations`, `global.score_playback_map`, `global.score_has_pickup`, `global.score_units_per_measure` | `global.timeline_state.score_render_plan`, `global.timeline_state.score_render_plan_needs_rebuild`, `global.timeline_state.score_render_plan_pending_reason`, `global.timeline_state.score_render_plan_stats`, `global.timeline_state.score_lane_layout_cache_single`, `global.timeline_state.structural_measure_starts` | `gv_bind_timeline_on_tune_start` |
| `scr_game_viz.gml` | `gv_draw_timeline_canvas_overlay(_x1, _y1, _x2, _y2)` | Draws active timeline overlays and score lane. Score-image time mapping must use per-image content bounds (`score_lane_meta[].content_left_px/right_px`) rather than full sprite width, otherwise variable exported whitespace causes apparent scrolling jumps and inconsistent image framing. In single-tune loop mode, playback-image lookup is sequence-first (aligned with non-loop path) so loop projection does not remap primary image identity through measure/nav aliases. In single-tune non-loop structural mode, rendering is capped to selected-channel playable measure extent (pickup-aware) to prevent drawing non-playing trailing part images. Also emits throttled `[SCORE_PLAN]` counters and sampled `[SCORE_DRAW_PHASE]` prep/filter/draw timings to `perf_benchmark.log` when score-plan debug is enabled. | `global.timeline_cfg`, `global.timeline_state`, `global.playback_context`, `global.score_lane_sprites`, `global.score_playback_map`, `global.score_measure_map`, `global.score_lane_meta` | none | `obj_game_viz` Draw pipeline |
| `scr_game_viz.gml` | `gv_perf_summary_get_latest(_force_refresh)` | Returns `global.PERF_REPORT_LATEST` immediately when available, with schema-v3 latest-JSONL cache fallback. | `global.PERF_REPORT_LATEST`, performance JSONL | local static cache | perf tile and detail panel |
| `scr_game_viz.gml` | `gv_perf_summary_is_warn(_summary)` | Reads centralized schema-v3 classification. | summary struct fields | none | `gv_gameviz_draw_perf_summary_button` |
| `scr_game_viz.gml` | `gv_perf_summary_select_scope(_summary, _scope_mode)` | Resolves schema-v3 overall or active-set-segment detail scope without creating a second review selection model. | `global.playback_context.active_segment` | none | `gv_gameviz_draw_perf_summary_popup` |
| `scr_game_viz.gml` | `gv_perf_summary_build_lines(_summary, _report)` | Builds schema-v3 selected-scope status/reason, accuracy, workload, component, render-total, and incident rows. | selected scope and report structs | none | `gv_gameviz_draw_perf_summary_popup` |
| `scr_game_viz.gml` | `gv_gameviz_draw_perf_summary_button(_rect, _summary, _enabled)` | Draws compact overall `OK`/`CAUTION`/`WARN`/`N/A` tile with cadence p95, scheduler p95, and incidents. | completed report | none | `gv_draw_gameviz_controls_panel` |
| `scr_game_viz.gml` | `gv_perf_summary_popup_visible()` | Returns whether the performance summary popup is currently visible. | `global.timeline_state.perf_summary_popup` | none | `gv_draw_notebeam_scoring_panel`, `gv_handle_notebeam_scoring_panel_click` |
| `scr_game_viz.gml` | `gv_gameviz_draw_perf_summary_popup(_x1, _y1, _x2, _y2, _summary, _replace_panel)` | Draws selected-scope report details in the judge-panel region and provides Tune/Set Overall controls for set review. | `global.timeline_state.perf_summary_popup`, completed report | `global.timeline_state.perf_summary_popup` | `gv_draw_notebeam_scoring_panel` |
| `scr_scoring.gml` | `scoring_loop_overview_select_iteration(_iteration, _focus_playhead)` | Persists selected loop iteration and publishes review projection window (`review_selected_loop_window`) used by post-play tune-structure filtering; optionally seeks review playhead to window start. | `global.timeline_state.loop_iteration_scores` | `global.loop_score_overview_ui_state.selected_iteration`, `global.timeline_state.review_selected_loop_iteration`, `global.timeline_state.review_selected_loop_window`, `global.timeline_state.playhead_ms` | `scoring_build_loop_iteration_scores`, `scoring_loop_overview_handle_click` |
| `scr_scoring.gml` | `scoring_loop_overview_handle_click(_mx, _my, _bx1, _by1, _bx2, _by2)` | Handles loop overview row clicks, preferring draw-derived row hitboxes for exact screen-space selection and falling back to scroll-aware row geometry, then delegates selection/focus to iteration selector. | `global.timeline_state.loop_iteration_scores`, `global.timeline_state.loop_score_row_hitboxes`, `global.loop_score_overview_ui_state.scroll_row` | `global.loop_score_overview_ui_state.selected_iteration`, `global.timeline_state.review_selected_loop_iteration`, `global.timeline_state.review_selected_loop_window`, `global.timeline_state.playhead_ms` | `obj_field_base` Step (`loop_score_matrix_canvas`) |
| `scr_scoring.gml` | `scoring_tune_override_apply_current(_tune_filename)` | Applies per-player tune override values for single-tune runtime (bpm, swing, gracenote override, notebeam zoom ahead/behind) and syncs timeline notebeam window from cfg. | `global.player_tune_overrides`, `global.timeline_cfg` | `global.current_tune_filename`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.timeline_cfg.measures_ahead`, `global.timeline_cfg.measures_behind` | single-tune load flow (`scr_button_try_load_tune_candidate`), player switch (`scr_select_player`) |
| `scr_scoring.gml` | `scoring_tune_override_save_current(_tune_filename)` | Saves current single-tune runtime values (bpm, swing, gracenote override, notebeam zoom ahead/behind) into per-player tune overrides and persists to disk. | `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.timeline_cfg.measures_ahead`, `global.timeline_cfg.measures_behind` | `global.current_tune_filename`, `global.player_tune_overrides` | tune settings +/- handlers, notebeam zoom button |
| `scr_tune_library.gml` | `scr_data_paths_is_ide_runtime()` | Detects IDE VM execution (`GMS2TEMP`) so read/write roots can follow IDE-specific contracts. | `working_directory` | none | `scr_data_paths_get_user_data_root`, `scr_data_paths_get_content_root` |
| `scr_tune_library.gml` | `scr_data_paths_get_ide_project_content_root()` | Returns the developer-authoritative project content root used for tune reads during IDE runs. | none | none | `scr_data_paths_get_content_root` |
| `scr_tune_library.gml` | `scr_data_paths_get_local_app_data_user_root()` | Resolves LocalAppData runtime root used for writable data during IDE runs (`%LOCALAPPDATA%/Silly_Wizard/datafiles/`). | `LOCALAPPDATA` env var | none | `scr_data_paths_get_user_data_root` |
| `scr_tune_library.gml` | `scr_data_paths_get_user_data_root()` | Resolves canonical writable runtime data root: IDE uses LocalAppData; packaged/non-IDE uses user override when set, else fallback candidates. | `global.primary_data_root_override` | none | `scr_data_paths_get_primary_root`, `scr_data_paths_get_category_root`, config save |
| `scr_tune_library.gml` | `scr_data_paths_get_content_root()` | Resolves tune content root from optional override; IDE defaults to project datafiles root, non-IDE falls back through runtime candidates. | `global.primary_data_root_override`, `global.tune_library_root_override` | none | `scr_data_paths_get_category_root`, `scr_tune_library_get_runtime_root`, settings UI |
| `scr_tune_library.gml` | `scr_data_paths_load_primary_root_from_config()` | Loads optional tune content root override from runtime paths config; user-data canonical config is checked first, legacy mirrors are fallback-only. | `<user_data_root>/config/runtime_paths.json`, legacy runtime mirrors | none | `obj_game_controller` Create |
| `scr_tune_library.gml` | `scr_data_paths_save_primary_root_to_config(_root)` | Persists tune content root override to canonical runtime config (`<user_data_root>/config/runtime_paths.json`). | none | canonical runtime paths JSON | settings UI handlers (`scr_settings_data_root_set`, `scr_settings_data_root_reset_auto`) |
| `scr_tune_library.gml` | `scr_tune_library_get_runtime_root()` | Resolves the tune-library root from category path `tunes/` (content root) with fallback probe. | `global.primary_data_root_override` | none | `scr_load_tune_library`, `obj_game_controller` Create, `scr_regenerate_tune_library` |
| `scr_tune_library.gml` | `scr_load_tune_library()` | Loads `tune_library.json` from runtime root candidate(s) and returns library struct with merged history stats. | `global.current_player_id` (via history merge) | none | `obj_ui_controller` Create, `scr_regenerate_tune_library` |
| `scr_button_scripts.gml` | `scr_regenerate_tune_library()` | Rebuilds tune library from runtime root, reloads global library, and refreshes picker rows. | none | `global.tune_library` | button index 12 (`scr_handle_button_click`) |
| `scr_button_scripts.gml` | `scr_button_bpm_debug_log(_line)` | Writes BPM diagnostics to debug output and runtime-relative `datafiles/debug/bpm_trace.log`. | none | `datafiles/debug/bpm_trace.log` | BPM change + start-play diagnostics |
| `scr_button_scripts.gml` | `scr_button_debug_get_root_dir()` | Resolves/creates debug output directory for planned-event loop comparison exports. | `diag_log_get_debug_root` (optional) | filesystem debug directory | `scr_button_export_planned_events_snapshot` |
| `scr_button_scripts.gml` | `scr_button_export_planned_events_snapshot(_events, _label, _run_id)` | Exports planned events and per-measure summaries (`loop_compare_events_*.csv`, `loop_compare_summary_*.csv`) including ownership fields for side-by-side base vs loop diagnostics. | `global.current_tune_name`, planned event fields/ownership fields | CSV files under `datafiles/debug/` | `start_play` |
| `scr_preprocess_tune.gml` | `scr_preprocess_tune(_tune, _overrides)` | Resolves canonical `tune_data` from direct data, wrapper structs, or `obj_tune`, then builds sorted playable events; unloaded/invalid input returns an empty array. | tune data, overrides, embellishment library/config, chanter profile | returned playable event array, lazy chanter cache | single-tune and set preprocessing |
| `scr_metronome.gml` | `metronome_generate_events(_tune, _settings)` | Resolves tune metadata from direct data, playable-events wrappers, or `obj_tune`, then generates metronome events using effective settings. | tune metadata/events, metronome globals/settings | returned metronome event array, metronome config velocities/mode | single-tune and set preprocessing |
| `scr_button_scripts.gml` | `scr_button_prepare_single_tune_playback_events()` | Rebuilds single-tune playback from canonical `tune_data`, merges metronome/count-in events, and fails fast with an empty global array when preprocessing yields no tune events. | loaded `global.tune`, effective playback settings | `global.playback_events`, playback-context BPM mirror | room-entry rebuild, settings changes, `start_play` |
| `scr_button_scripts.gml` | `start_play()` | Opens MIDI, requires successful single-tune preparation, activates the prepared/loop-expanded event array, starts the scheduler, and binds timeline state. | MIDI settings, loaded tune/set, `global.playback_events`, loop/playback context | MIDI polling, `global.playback_events_active`, scheduler/timeline runtime state | Play button |
| `scr_loop_manifest.gml` | `loop_build_manifest(_start_ref, _end_ref, _options)` | Builds a canonical loop manifest from structural refs with strict half-open time-window payload (`[start_ms,end_ms)`), explicit end-boundary cleanup note_off generation, minimal loop spans/segments metadata, and pass-1 note_on parity assertions versus base-window events. End cutoff uses a small epsilon guard so events stamped at the boundary cannot leak into the payload due to floating-point accumulation jitter. | boundary refs, `global.playback_events`, `global.METRONOME_CONFIG` | none | `scr_button_loop_build_playback_events` |
| `scr_button_scripts.gml` | `scr_settings_logs_toggle(_ctx)` | Toggles the settings Logs control and now synchronizes both score-lane debug flags and runtime performance diagnostic gates (`RT_BUDGET_DIAG_ENABLED`, `MIDI_TIMING_DIAG_ENABLED`, `PLAYBACK_DEBUG_GROUP_TIMING`). | `global.timeline_cfg.score_lane_debug_log`, `global.timeline_cfg.score_lane_debug_file_log`, `global.RT_BUDGET_DIAG_ENABLED`, `global.MIDI_TIMING_DIAG_ENABLED` | `global.timeline_cfg.score_lane_debug_log`, `global.timeline_cfg.score_lane_debug_file_log`, `global.RT_BUDGET_DIAG_ENABLED`, `global.MIDI_TIMING_DIAG_ENABLED`, `global.PLAYBACK_DEBUG_GROUP_TIMING` | button index 30 (`scr_handle_button_click`) |
| `scr_button_scripts.gml` | `scr_button_reset_loop_state()` | Clears loop runtime globals and resets timeline loop session/cache state so room transitions never inherit stale loop-phase data; also clears optional boundary refinement state. | `global.timeline_state` | `global.loop_mode_enabled`, `global.loop_runtime_*`, `global.playback_events_active`, `global.timeline_state.loop_runtime_cache`, `global.timeline_state.loop_session`, `global.timeline_state.loop_boundary_refinement`, loop UI selection fields | `scr_goto_playroom`, `scr_goto_mainmenu` |
| `scr_button_scripts.gml` | `scr_button_apply_event_ownership_metadata(_events)` | Annotates planned events with canonical ownership metadata (`owner_nav_idx`, owner part/measure/start/end, `boundary_role`, `exec_rank`) using a marker-derived ownership nav map and time-window-first ownership resolution (label fallback only), preventing internal-pickup measure drift from snippet-linear assumptions. Loop-expanded payloads are iteration-aware (`loop_iteration`) so ownership windows and fallback label matches do not collapse later passes into one terminal measure. | `global.timeline_state.measure_ms`, `_events` marker/boundary timing | `_events[]` ownership fields | `scr_button_prepare_single_tune_playback_events`, `scr_button_loop_build_playback_events` |
| `scr_button_scripts.gml` | `scr_button_canonicalize_event_measure_labels(_events)` | Rewrites event `measure`/`part` from ownership-resolved fields (`owner_measure`/`owner_part`) after annotation so downstream consumers do not see conflicting pickup-boundary labels at identical timestamps. | `_events[]` ownership fields | `_events[]` `measure`, `part`, `source_measure` | `scr_button_prepare_single_tune_playback_events`, `scr_button_loop_build_playback_events` |
| `scr_button_scripts.gml` | `scr_button_loop_build_playback_events(_base_events)` | Expands selected measure refs into repeated playback events and writes authoritative `timeline_state.loop_session` descriptor for phase-driven consumers; Loop V3 manifest (`loop_build_manifest`) is now mandatory for loop payload construction and provides strict half-open payload + boundary cleanup note_offs. If manifest build is unavailable/invalid, loop payload build aborts (no legacy loop fallback path). Resolves loop window from canonical boundary endpoints (`loop_start_boundary`/`loop_end_boundary`) when available, with timeline-window fallback, and supports optional beat-level endpoint refinement via `timeline_state.loop_boundary_refinement` (no UI dependency). When projecting session refs/segments, clips first/last selected windows to resolved loop boundaries so partial-beat starts/ends render correctly (no full-measure compression). Publishes explicit pass-0 `loop_session.timeline_segments[]` (time segments with identity metadata) and stores `loop_session.boundary_refinement`. Spacer mode is metronome-only and session stores per-pass expected-event manifest (`pass_manifest[]`). | loop settings globals, selected refs, boundary markers in `_base_events`, `global.score_has_pickup`, `global.timeline_state.loop_boundary_refinement` | `global.loop_runtime_*`, `global.timeline_state.loop_session` | `start_play` |
| `scr_tune_scripts.gml` | `script_tune_callback_batched()` | Batched scheduler callback: dispatches one timestamp group and updates loop session runtime phase/progress (`prelude`/`pass`/`spacer`/`complete`) from grouped loop metadata. | `global.tune_event_groups`, `global.tune_group_index`, `global.loop_runtime_*`, `global.timeline_state.loop_session`, playback/midi globals | `global.loop_runtime_current_iteration`, `global.tune_group_index`, `global.tune_scheduler_active`, `global.loop_runtime_active`, `global.timeline_state.current_measure`, `global.timeline_state.last_dispatched_expected_ms`, `global.timeline_state.loop_session` | scheduler callback + `tune_scheduler_step_tick` |
| `scr_game_viz.gml` | `gv_bind_timeline_on_tune_start(_planned_events, _bpm, _meter_text)` | Initializes per-run timeline state and now guarantees `timeline_state.loop_session` exists/reset for non-loop playback; also ensures `timeline_state.loop_boundary_refinement` defaults are always present for backend-only beat endpoint wiring. | `global.timeline_cfg` | `global.timeline_state` (all runtime fields including `loop_session`, `loop_boundary_refinement`) | `gv_bind_timeline_from_current_tune`, play-start flow |
| `scr_tune_scripts.gml` | `diag_log_get_debug_root()` | Resolves and creates the runtime debug directory with a normalized trailing slash path for all diagnostics. | none | filesystem (debug directory) | `diag_log_append_line`, `perf_diag_emit` |
| `scr_tune_scripts.gml` | `diag_log_detect_channel(_file_name)` | Infers a diagnostic channel label from log filename for structured JSONL records. | none | none | `diag_log_build_record` |
| `scr_tune_scripts.gml` | `diag_log_detect_event(_msg)` | Infers coarse event tags (play start/stop, RT budget, BPM, calibration) from message text for structured logs. | none | none | `diag_log_build_record` |
| `scr_tune_scripts.gml` | `diag_log_build_record(_line, _file_name)` | Builds structured diagnostic records with timestamp, channel, event, tune/config metadata, and message text. | `global.current_tune_name`, `global.current_bpm`, `global.swing_mult`, `global.gracenote_override_ms`, `global.playback_run_id` | none | `diag_log_append_line`, `perf_diag_emit` |
| `scr_tune_scripts.gml` | `diag_session_get_run_uuid()` | Lazily creates and returns a stable per-process run UUID for correlating startup and play markers. | `global.DIAG_SESSION_RUN_UUID` | `global.DIAG_SESSION_RUN_UUID` | `diag_session_marker_write` |
| `scr_tune_scripts.gml` | `diag_session_marker_write(_kind, _play_id)` | Appends explicit startup/play markers with resolved working/content/user-data roots to `debug/session_markers.jsonl` for unambiguous runtime path tracing. | `global.DIAG_SESSION_RUN_UUID`, path helper scripts | `debug/session_markers.jsonl` | `obj_game_controller` Create, `tune_start` |
| `scr_tune_scripts.gml` | `diag_log_get_max_lines()` | Resolves max retained lines per diagnostic log before rollover from global override/default. | `global.DIAG_LOG_MAX_LINES` | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_get_max_backups()` | Resolves retained backup generation count per diagnostic log from global override/default. | `global.DIAG_LOG_MAX_BACKUPS` | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_count_lines_upto(_path, _stop_after)` | Counts log lines with early stop for rollover checks. | none | none | `diag_log_rotate_if_needed` |
| `scr_tune_scripts.gml` | `diag_log_rotate_if_needed(_log_path)` | Performs throttled line-count-based log rollover to numbered backups (`.1`, `.2`, ...), avoiding per-append file scans during heavy playback logging. | `global.DIAG_LOG_MAX_LINES`, `global.DIAG_LOG_MAX_BACKUPS` | diagnostic log files and backups | `diag_log_append_line` |
| `scr_tune_scripts.gml` | `diag_log_append_line(_line, _file_name, _mirror_output, _output_prefix)` | Shared append writer used by perf/BPM/calibration diagnostics; writes one JSON object per line (JSONL). | none | `datafiles/debug/*.log` | `perf_diag_emit`, `scr_button_bpm_debug_log`, `scoring_calibration_debug_log` |
| `scr_tune_scripts.gml` | `perf_diag_emit(_line)` | Central perf-diagnostic append helper; now respects `RT_BUDGET_DIAG_ENABLED` as the master runtime gate so performance logging can be disabled without affecting scoring/export systems. | `global.RT_BUDGET_DIAG_ENABLED`, `global.PERF_DIAG_LOG_PATH`, `global.PERF_DIAG_OUTPUT_WINDOW_ENABLED` | `datafiles/debug/perf_benchmark.log` or explicit perf log path | RT budget and MIDI timing diagnostic recorders |
| `scr_tune_scripts.gml` | `perf_run_summary_get_performances_root()` | Resolves and creates the performances folder used for compact run summary output. | none | `datafiles/performances/` (directory create) | `perf_run_summary_append_latest` |
| `scr_tune_scripts.gml` | `perf_run_summary_prune(_path, _max_records)` | Rewrites the compact report ledger only when needed, retaining its newest bounded set of non-empty records. | performance JSONL | performance JSONL | `perf_run_summary_append_latest` |
| `scr_tune_scripts.gml` | `perf_run_summary_append_latest(_jitter_summary)` | Appends one schema-v3 completed report per play ID to `run_summaries.jsonl` and caps the ledger at 200 records. | completed schema-v3 report | performance JSONL, duplicate-write play ID | `tune_cleanup_after_finish` |
| `scr_tune_scripts.gml` | `perf_report_metric_buffer_create(_capacity)` / `perf_report_metrics_create()` | Allocate fixed-capacity ring buffers for all always-on report metrics. | none | returned structs | report scope creation |
| `scr_tune_scripts.gml` | `perf_report_scheduler_accuracy_create()` | Allocates fixed whole-run signed/absolute scheduler histograms and exact accuracy-band counters. | none | returned accumulator | report scope creation |
| `scr_tune_scripts.gml` | `perf_report_scope_create(...)` / `perf_report_begin_run(_play_id)` | Build one run-local overall scope, ordered tune-segment scopes, transition scope, and immutable runtime context. | `global.playback_context`, runtime configuration | `global.perf_report_state`, clears latest report | `tune_start` |
| `scr_tune_scripts.gml` | `perf_report_scheduler_incident_category(_scheduled_ms)` | Categorizes dispatches/incidents as startup, segment start, tune content, or transition from scheduled time; accuracy recording extends startup only across an initial >=20 ms scheduler backlog. | report segment windows, startup grace/backlog state | report startup-backlog state | scheduler accuracy/spike recording |
| `scr_tune_scripts.gml` | `perf_report_scope_store_worst_incident(...)` / `perf_report_scope_record_scheduler_accuracy(...)` | Maintains exact whole-run counters/histograms and bounded top-12 timestamped incidents per scope. | scope accuracy state | scope accuracy state | scheduler accuracy recorder |
| `scr_tune_scripts.gml` | `perf_report_record_scheduler_accuracy(...)` | Records every dispatched timestamp group into overall plus scheduled-time tune/transition scope, excluding startup only from steady-state bands. | scheduler/timeline context | report scope accuracy | batched scheduler callback |
| `scr_tune_scripts.gml` | `perf_report_histogram_percentile(...)` / `perf_report_scheduler_accuracy_summarize(...)` | Produces 0.5 ms-bin absolute percentiles, exact threshold percentages/min/max, histograms, and sorted worst incidents. | completed scope accuracy | returned schema-v3 summary | report completion |
| `scr_tune_scripts.gml` | `perf_report_scope_record(...)` / `perf_report_record_sample(...)` | Append allocation-free samples to overall plus scheduled/current-time segment or transition scope. | active report, `global.tune_start_real` | report ring buffers | RT metric recorders, controller Step |
| `scr_tune_scripts.gml` | `perf_report_resolve_segment_index(_time_ms)` | Maps playback-relative time to `[start_ms, content_end_ms)` tune ownership; returns transition/unowned outside those windows. | report segment timing | none | report sample/spike attribution |
| `scr_tune_scripts.gml` | `perf_report_record_spike(_time_ms)` | Attributes cooldown-approved severe incidents to overall plus tune or transition scope. | active report | scope incident counts | scheduler spike tracer |
| `scr_tune_scripts.gml` | `perf_report_record_segment_switch(...)` | Persists bounded per-boundary cache/enqueue/total timing and cache-hit records without removing work from Step/cadence metrics. | active report | `perf_report_state.segment_switches` | live set segment switch |
| `scr_tune_scripts.gml` | `perf_report_render_component_add(...)` / `perf_report_render_frame_complete(_draw_gui_ms)` | Accumulate participating world/UI visual owners and finalize one total instrumented render sample at Draw GUI boundary. | active report | component and `render_total_ms` buffers | anchor recorder, `obj_game_viz` Draw GUI |
| `scr_tune_scripts.gml` | `perf_report_classify_scope(_summary)` | Pure centralized validity and four-state classification using cadence, scheduler, and category-specific content/boundary incident thresholds while excluding startup incidents. | completed scope metrics | returned status/reasons | scope summarizer |
| `scr_tune_scripts.gml` | `perf_report_scope_summarize(_scope)` / `perf_report_complete()` | Compute post-play percentiles, whole-run accuracy, workload context, classifications, overall/per-tune/transition schema-v3 record, and immediate runtime publication. | report state, run totals/settings | `global.PERF_REPORT_LATEST`, completed report state | final scheduler group, cleanup |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_reset_for_new_run()` | Clears all legacy/report sampling heads, counts, phase stats, and prior-step timestamps before accepted playback. | none | RT diagnostic state | `tune_start` |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_scheduler_late_ms(...)` / `tune_rt_budget_diag_record_scheduler_group(...)` | Retain legacy diagnostics while forwarding scheduled-time lateness, callback, and MIDI-send samples to report scopes. | scheduler state | legacy and report buffers | batched scheduler callback |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_controller_step_interval_ms(...)` / `tune_rt_budget_diag_record_controller_step_ms(...)` | Record controller cadence and owned Step duration into legacy and report buffers. | RT gates, active report | legacy and report buffers | controller Step |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_midi_step_ms(...)` / `tune_rt_budget_diag_record_draw_ms(...)` / `tune_rt_budget_diag_record_anchor_draw_ms(...)` | Record MIDI, narrow legacy Game Viz Draw, and instrumented visual owner costs; visual owners feed render total accumulation. | RT gates, active report | legacy and report buffers | MIDI Begin Step and Draw owners |
| `scr_tune_scripts.gml` | `tune_cleanup_after_finish(_scheduled_play_id)` | Rejects stale callbacks, refreshes legacy calibration data, finalizes the current report, and persists it once. | current play ID and report state | JSONL summary | scheduled cleanup callback |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_controller_phase_ms(_phase_kind, _phase_ms)` | Records keyed per-phase controller-step timings (`scheduler_tick`, `timeline_tick`, `deferred_tick`) and emits `[RT_BUDGET] controller_phase_ms` summaries for bottleneck isolation. | `global.RT_BUDGET_DIAG_ENABLED`, `global.RT_BUDGET_DIAG_LOG_INTERVAL_MS`, `global.RT_BUDGET_SCHED_WARMUP_MS`, `global.tune_start_real` | `global.rt_budget_controller_phase_stats` | `obj_game_controller` Step event |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_record_draw_interval_ms(_draw_dt_ms)` | Records draw-to-draw frame interval timing (`[RT_BUDGET] draw_interval_ms`) to separate frame pacing jitter from draw runtime cost. | `global.RT_BUDGET_DIAG_ENABLED`, `global.RT_BUDGET_DIAG_LOG_INTERVAL_MS`, `global.RT_BUDGET_SCHED_WARMUP_MS`, `global.tune_start_real` | `global.rt_budget_draw_dt_buf/head/count/last_log_ms` | `obj_game_viz` Draw event |
| `scr_tune_scripts.gml` | `tune_rt_budget_diag_trace_scheduler_spike(_late_ms, _real_elapsed, _scheduled_elapsed)` | Emits cooldown-limited `[SCHED_SPIKE]` traces with scheduler/deferred/segment context when lateness crosses threshold, to correlate spike moments with runtime state. | `global.RT_BUDGET_DIAG_ENABLED`, `global.tune_group_index`, `global.tune_event_groups`, `global.tune_deferred_queue`, `global.tune_deferred_head`, `global.PLAYBACK_SCHEDULER_*`, `global.playback_context`, `global.timeline_state` | `global.rt_budget_sched_spike_last_log_ms`, `global.rt_budget_sched_spike_count` | `script_tune_callback_batched` |
| `scr_tune_scripts.gml` | `playback_audio_backend_get()` | Returns normalized output backend key (`midi` or `hybrid_metronome_sample`) with safe fallback to MIDI. | `global.PLAYBACK_AUDIO_BACKEND` | none | `tune_start`, `script_tune_callback_batched`, backend routing helpers |
| `scr_tune_scripts.gml` | `playback_should_use_metronome_sample_sink()` | Reports whether metronome-channel note events should use sample sink routing. | `global.PLAYBACK_AUDIO_BACKEND` | none | `script_tune_callback_batched` |
| `scr_tune_scripts.gml` | `playback_emit_metronome_sample(_velocity)` | Plays configured metronome sample asset based on velocity/accent and returns false when unavailable so caller can fall back to MIDI. | `global.METRONOME_SAMPLE_SOUND_EMPHASIS`, `global.METRONOME_SAMPLE_SOUND_NORMAL`, `global.METRONOME_SAMPLE_PRIORITY` | audio voice playback (metronome sample) | `script_tune_callback_batched` |
| `scr_button_scripts.gml` | `scr_settings_data_root_set(_ctx)` | Captures a custom tune content root, validates `<root>/tunes`, persists canonical runtime config, regenerates library, and refreshes settings field display. | `global.primary_data_root_override` | `global.primary_data_root_override`, `global.tune_library` | button index 38 (`scr_handle_button_click`) |
| `scr_button_scripts.gml` | `scr_settings_data_root_reset_auto(_ctx)` | Clears custom tune content root override, persists AUTO mode to canonical runtime config, regenerates library, and refreshes settings field display. | `global.primary_data_root_override` | `global.primary_data_root_override`, `global.tune_library` | button index 39 (`scr_handle_button_click`) |
| `scr_game_viz.gml` | `gv_draw_gameinfo_timeline_visibility_panel(_x1, _y1, _x2, _y2)` | In loop mode, draws compact resolved boundary summary (`M# B# - M# B#`) in game-info body and records clickable beat hitboxes for endpoint refinement. | `global.loop_mode_enabled`, `global.timeline_state`, boundary resolver helpers | `global.timeline_state.loop_boundary_ui_controls` | `obj_field_base` draw branch (`gameinfo_timeline_visibility_anchor`) |
| `scr_game_viz.gml` | `gv_handle_gameinfo_timeline_visibility_click(_mx, _my, _x1, _y1, _x2, _y2)` | Handles game-info boundary-beat clicks: start beat advances forward, end beat steps backward; updates refinement only when resulting endpoints remain valid. | `global.loop_mode_enabled`, `global.timeline_state.loop_boundary_ui_controls` | `global.timeline_state.loop_boundary_refinement` | `obj_field_base` mouse branch (`gameinfo_timeline_visibility_anchor`) |
| `scr_game_viz.gml` | `gv_loop_get_ui_resolved_boundaries()` | Resolves start/end boundary measure+beat view data for loop UI from selected refs and active refinement state. | loop selection refs, boundary resolver | none | `gv_draw_gameinfo_timeline_visibility_panel`, `gv_handle_gameinfo_timeline_visibility_click` |
| `scr_game_viz.gml` | `gv_loop_get_measure_beat_count(_part, _measure)` | Computes per-measure beat count from canonical marker events (`global.playback_events`) with meter fallback, used for beat-cycling limits. | `global.playback_events`, `global.timeline_state.meter_num` | none | `gv_loop_adjust_boundary_refinement_beat` |
| `scr_game_viz.gml` | `gv_loop_adjust_boundary_refinement_beat(_which, _delta)` | Cycles start/end refinement beat fields and revalidates ordering through boundary resolver; reverts if adjustment becomes invalid. | `global.timeline_state.loop_boundary_refinement`, selected refs, boundary resolver | `global.timeline_state.loop_boundary_refinement` | `gv_handle_gameinfo_timeline_visibility_click` |
| `scr_game_viz.gml` | `gv_get_gameinfo_loop_boundary_layout(_x1, _y1, _x2, _y2, _summary)` | Builds text and beat-button hitbox layout for compact game-info boundary line rendering/clicking. | none | none | `gv_draw_gameinfo_timeline_visibility_panel`, `gv_handle_gameinfo_timeline_visibility_click` |

**Last full review:** 2026-04-15

---

## Export File Locations (Quick Reference)

When a tune playback completes, exports are written to:
- **CSV (event history):** `datafiles/performances/{clean_tune_name}/{clean_tune_name}_{timestamp}_{bpm}_{swing}_{grace_override_ms}.csv`
- **Summary JSON:** `datafiles/performances/{clean_tune_name}/{clean_tune_name}_{timestamp}_{bpm}_{swing}_{grace_override_ms}_summary.json`

Example for "Jock Wilson's Ball" (90 BPM, 0 swing, 30ms grace):
- `datafiles/performances/Jock Wilsons Ball/Jock Wilsons Ball_20260510-183441_90_0_30.csv`
- `datafiles/performances/Jock Wilsons Ball/Jock Wilsons Ball_20260510-183441_90_0_30_summary.json`

**Entry point:** `event_history_get_export_info()` in `scr_event_log.gml` builds the paths. Trigger: `export_event_history()` (button 13). Auto-export is available through `global.EVENT_HISTORY_AUTO_EXPORT` but defaults to false so ordinary runs do not accumulate large CSV/JSON history.

**Phase-1 experimental toggle:** `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS`
- `true` (default): CSV export includes planned `source="game"` and player rows.
- `false`: CSV export omits planned `source="game"` rows while live history ingestion remains unchanged for scoring correctness.

**Benchmark run metadata:** summary export includes `benchmark_context` (manual power-mode/MIDI-activity labels, notes, MIDI device names, scheduler mode, FPS) and `export_filter` state for each run.

---

## Documentation Index

| File | Purpose |
|---|---|
| `WORKSPACE_MAP.md` | **This file.** Script registry, globals, struct schemas, UI architecture, playback flow. |
| `PROJECT_PLAN.md` | Implementation log, cleanup batches, pending work items. |
| `BETA_RELEASE_PLAN.md` | Beta packaging hardening plan for zipped Windows distribution (Steam-compatible workflow). |
| `EXCEL_VBA_MAP.md` | VBA module reference: pipeline stages, entry points, 23-column constants, sheet conventions, output paths, config. |
| `TUNE STRUCTURE JSON.md` | `tune.json` schema consumed by `scr_tune_load_json`. |
| `TUNE STRUCTURE EXCEL.md` | 23-column event grid layout inside the Excel workbook. |
| `TRANSITION_TUNE_TEMPLATE.md` | How to author transition tunes (ABC patterns, set ordering, verification checklist). |
| `METRONOME.md` | Metronome scheduling design and implementation notes. |
| `PERFORMANCE_REPORTING.md` | Post-play runtime-health reporting workflow, metric definitions, current limitations, and recommended targets. |
| `UI_SETUP_HOWTO.md` | How to wire up new UI layers and instances. |
| `Giavapps MIDI documentation.md` | API reference for the `midi_*` extension functions. |
| `TUNE GAMEPLAY VISUALS.md` | Notebeam / game-viz visual design notes. |
| `scripts/Excel - Parse_ABC.txt` | Read-only VBA mirror: `modParseABC` (ABC → event grid pipeline). |
| `scripts/Excel - TuneExport.txt` | Read-only VBA mirror: `modTuneExport` (tune metadata export). |
| `scripts/Excel - Performance_Analysis.txt` | Read-only VBA mirror: `modTuneLoader` (post-session analysis). |

Performance runtime note:
- Timeline overlay redraw cadence can be throttled independently from step rate via `global.GV_TIMELINE_OVERLAY_REFRESH_MS` (default 11 ms, ~90 Hz). `obj_field_base` timeline anchor caches base and overlay surfaces separately and blits cached overlay each frame.

---

## Function annotation template

All functions use `/// @` headers (GameMaker IDE renders these as tooltips). Four custom tags (`@reads`, `@writes`, `@objects`, `@callers`) are not rendered by the IDE but are greppable for cross-system navigation.

**Full template** (any function that touches globals, objects, or is a cross-system integration point):
```gml
/// @function function_name(_param1, _param2)
/// @description One-line description.
/// @param {type} _param1  Description
/// @param {type} _param2  Description
/// @returns {type}  Description   (omit tag if void)
/// @reads   global.var_name, global.other_var   (or "none")
/// @writes  global.var_name                     (or "none")
/// @objects obj_name (read|write), obj_other    (or "none")
/// @callers caller_function, other_caller
```

**Minimal template** (pure utility — no globals, no objects touched):
```gml
/// @function function_name(_param)
/// @description One-line description.
/// @param {type} _param  Description
/// @returns {type}  Description
```

---

---

## Project overview (current state)

- **What it does today:** The game loads tune data (JSON/CSV) and plays scheduled MIDI events. Playback events are sent via Giavapps MIDI. The UI uses GameMaker layers and a set of UI objects (buttons, fields) to control playback and settings.

- **Current workflow:** The game starts in `Room_main_menu` with `main_menu_layer` visible. From there:
  - **Play** navigates to `Room_play` and starts playback.
  - **Settings** lets the user pick MIDI input/output devices (via `scr_button_scripts` and `scr_MIDI` helpers).
  - **Tune** opens the tune picker; visible rows are populated from `global.tune_library` and the selection is stored in `global.tune_selection`. Pressing the tune OK button triggers `scr_tune_load_json()` and the build → start playback flow.

- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order`
- **Project root files:** `Silly-Wizard.yyp`, `Silly-Wizard.resource_order`
- **Documentation highlights:**
  - `PROJECT_PLAN.md` — implementation log, cleanup batches, and planning updates.
  - `EXCEL_VBA_MAP.md` — VBA module reference: pipeline stages, entry points, column constants, sheet conventions, output paths, config surface.
  - `TUNE STRUCTURE JSON.md` — `tune.json` schema consumed by `scr_tune_load_json`.
  - `TUNE STRUCTURE EXCEL.md` — 23-column event grid layout used inside the Excel workbook.
  - `TRANSITION_TUNE_TEMPLATE.md` — standard transition-tune authoring guide (metadata, ABC patterns, set ordering, verification checklist).
  - `METRONOME.md` — metronome scheduling design and implementation notes.
  - `UI_SETUP_HOWTO.md` — how to wire up new UI layers and instances.
- **Major folders:**
  - `scripts/` — game logic scripts (UI, tune loading, midi, etc.)
  - `objects/` — GameMaker objects with events and instance scripts
  - `roomui/` — UI layouts and layers (in-game windows)
  - `datafiles/` — external content (`tunes/` JSON/CSV files — **generated by Excel VBA pipeline, not hand-authored**)
  - `extensions/` — third-party integrations (`GiavappsMIDI`)
  - `scripts/Excel - *.txt` — read-only VBA source mirrors for the Excel workbook (`Silly Wizard Work.xlsm`); see `EXCEL_VBA_MAP.md`

---

---

## Important Architectural Constraints

⚠️ **No GameMaker data structures (ds_maps, ds_lists, ds_grids, etc.)**
- Use **structs** for key-value lookup and complex data
- Use **arrays** for sequences and lists
- Avoid all `ds_*` functions — they introduce unnecessary memory management overhead and complexity
- This keeps code simpler, more predictable, and easier to debug

⚠️ **Score image export invariant (do not regress)**
- Export pipeline must produce **one score image per playback measure**.
- Do **not** deduplicate repeated/identical-looking measures during score snippet generation.
- `playback_to_image` must be an identity map for normal bundles (`[0, 1, 2, ...]`) so score-lane `seq` aligns directly to sprite index.

⚠️ **Transition metadata must fail loudly (no silent runtime fallback)**
- Authoring mismatches (for example transition tail/head content present but cut metadata missing, or vice versa) must be surfaced by validation/export warnings in the VBA pipeline.
- Runtime GML should consume explicit metadata and avoid heuristic fallbacks that can mask bad workbook/source data.

⚠️ **Fix root causes, keep runtime logic lightweight**
- When an issue is found, prefer identifying and fixing the underlying source/data/logic mismatch over adding special-case runtime workarounds for one instance.
- Keep fixes small, readable, and reusable so behavior is understandable and maintainable across all tunes/sets.

---

## Key scripts (current responsibilities)

- **`scripts/scr_button_scripts/`** — UI button dispatcher and handlers (window toggles, settings changes, tune OK, start play).
- **`scripts/scr_MIDI/`** — MIDI device scanning/opening and message utilities; processes input messages and provides helper functions for playback.
- **`scripts/scr_tune_library/`** — Loads `tunes/tune_library.json` and populates tune picker rows.
- **`scripts/scr_tune_load/`** — Loads and validates tune JSON files into the `obj_tune` instance; loads score manifests/sprites and normalizes `image_meta.beat_anchors` for runtime score-lane consumption.
- **`scripts/scr_preprocess_tune/`** — Converts raw tune events into playable timelines (embellishments, swing, timing) and normalizes legacy pickup structure so measure 1 starts after any anacrusis.
- **`scripts/scr_tune_scripts/`** — Merges tune events and metronome events, starts playback using a `time_source`, and implements the playback callback `script_tune_callback()` that sends MIDI and logs events.
- **`scripts/scr_event_log/`** — Event history logging system. Tracks all playback events (timing, note, source) for analysis. Exports to CSV for performance debugging and player feedback.
- **`scripts/scr_UI_scripts/`** — UI layer helpers (`GetLayerNameFromIndex`, `scr_update_fields`, `scr_ui_refresh`).

---

## Playback Callback Flow (Detailed)

This describes how a tune is triggered and how events flow through the system:

### 1. **User Action → Button Press**
- User clicks "Play" button in tune picker or main menu
- Button handler calls function from `scr_button_scripts.gml`

### 2. **Tune Selection & Loading**
- Button handler → `scr_tune_load_json()` (from `scr_tune_load.gml`)
- Loads tune JSON file and validates structure
- Populates `obj_tune.tune_data` with `tune_metadata`, `performance`, and `events[]`

### 3. **Preprocessing**
- `scr_preprocess_tune()` (from `scr_preprocess_tune.gml`)
- Converts tune JSON events into a playable MIDI event array
- Each event includes: `time_ms`, `type` ("note_on"/"note_off"), `note` (MIDI), `velocity`, `channel`
- Handles embellishment expansion, gracenote timing, and unit-to-millisecond conversion

### 4. **Playback Start**
- `tune_start()` (from `scr_tune_scripts.gml`)
- Creates a `time_source` that fires at millisecond intervals
- Iterates through the preprocessed playable events array
- **Callback function:** `script_tune_callback()` fires whenever an event's `time_ms` is reached

### 5. **Event Playback & Logging**
- `script_tune_callback()` executes:
  1. Sends MIDI note via `midi_output_message_send_short()` (Giavapps MIDI)
  2. Updates display: `obj_currentnote_field_1.note_text = letter` 
  3. **Logs event to history:** `event_history_add()` (from `scr_event_log.gml`)
  
### 6. **Event History Storage**
- `event_history_add()` logs the event with:
  - Timing data: `expected_time_ms`, `actual_time_ms`, `delta_ms`
  - Beat context: `measure`, `beat`, `beat_fraction` (0 for now, populated when metronome added)
  - Event data: `event_type`, `source` ("game"), `note_midi`, `note_letter`, etc.
  - Context: `tune_name`, `is_embellishment`, etc.
  
### 7. **Analysis & Export**
- After playback ends, user can export history:
  - `event_history_export_csv("tune_name")` 
  - Generates `datafiles/event_history_tune_name.csv`
  - Columns include timing, beat, MIDI notes, and quality metrics
  - Import into Excel for analysis

### 8. **Player Input & Metronome Context**
- Player MIDI input logging remains an active enhancement target (`source: "player"`, actual timing from input device)
- Metronome generation is currently implemented and contributes beat/measure marker context during playback
- CSV/export analysis is designed to compare expected/game/player timing as player-input logging expands

### Calibration Handoff (Current)
- Split timing domains (two active): `audio_output_offset_ms`, `visual_alignment_offset_ms` (reserved for future: `input_capture_offset_ms`).
- Scoring offset removed to keep player feedback honest.
- Calibration APIs in `scr_tune_scripts.gml` (per-device profile hydrate/store and offset apply).
- Player settings persist `settings.timing_calibration` via `scr_scoring.gml` save/load.
- Scheduler timing applies `audio_output_offset_ms` in both timesource and step scheduler paths.
- Script dispatcher keeps calibration hooks at cases `32` (manual nudge audio/visual) and `37` (apply saved profile); cases `31/33/34/35/36` are intentionally inactive.

---

## BPM Authority & Propagation Path

`global.current_bpm` is the authoritative runtime BPM. It is written by UI controls and must flow through every downstream consumer consistently.

### BPM sources (precedence order at play time)
1. **Live BPM field value** — resolved from the BPM +/- bound field in `scr_button_get_bpm_from_bound_field()` (highest priority)
2. **Active settings segment bpm** — `set_item.bpm` in set mode, or the single-tune virtual set item (`global.current_set[0].bpm`) in single-tune mode
3. **`global.current_bpm`** — runtime mirror/fallback when field and segment value are unavailable
4. **`tune_metadata.tempo_default`** — value from `tune.json`; used as fallback only (lowest priority)

### VBA / Excel pipeline
`RecalculatePositions` bakes `start_time_ms`, `end_time_ms`, and `tempo_bpm` into the event grid using the ABC `Q:` header BPM. These values are exported to `tune.json` and stored as `tune_metadata.tempo_default`. At runtime, **`scr_preprocess_tune` recalculates all timing from scratch** and ignores the stored ms values — so the VBA pipeline is BPM-neutral at runtime.

### Single-tune mode BPM lifecycle
| Step | Location | Notes |
|------|----------|-------|
| Tune selected | `scr_goto_playroom()` | Reads `global.current_bpm`; calls `scr_preprocess_tune` with that override |
| Virtual 1-tune set initialized | `scr_button_try_load_tune_candidate()` | Single-tune load creates/updates `global.current_set[0]` (virtual set item), then mirrors it into `playback_context.segments[0]` |
| User changes settings (BPM/swing/grace/metro) | `scr_tune_bpm_change()` and related handlers in `scr_button_scripts` | Writes globals + active virtual set item, then rebuilds single-tune playback events immediately |
| Effective settings resolved | `scr_button_resolve_effective_settings()` | Central authority resolver used by single-tune preprocess/play; overlays live field values and syncs mirrors |
| User presses Play | `start_play()` | Reads effective settings through resolver, rebuilds `global.playback_events`, then binds timeline timing |

> **Critical:** `playback_context` can be rebuilt from tune metadata and become stale; single-tune runtime settings remain authoritative in the virtual set item (`global.current_set[0]`) and are mirrored back into `playback_context.segments[0]` before play.

### Set mode BPM lifecycle
In set mode, `scr_set_preprocess_and_build_playback()` reads BPM from each `active_set.segments[].bpm` which is populated fresh from the current override state at room entry. `scr_playback_context_build_for_set()` then copies those segment BPMs into `playback_context`, so the context is always current — no separate override needed.

---

## Core controller objects (current state)

- **`obj_game_controller`**
  - Location: `objects/obj_game_controller/Create_0.gml`
  - Role: Initializes global IDs and MIDI/game defaults. Holds `global.*` vars used across the app.

- **`obj_player`**
  - Location: `objects/obj_player/Create_0.gml`
  - Role: Tracks live player input state (note on/off arrays, current note) used by UI and logging.

- **`obj_tune`**
  - Location: `objects/obj_tune/Create_0.gml`
  - Role: Data model instance for the currently loaded tune (`tune_metadata`, `events[]`, `event_count`, `filename`, `is_loaded`). Populated by `scr_tune_load_json()`.

- **`obj_tune_picker`**
  - Location: `objects/obj_tune_picker/Create_0.gml`
  - Role: Tune picker UI controller; maintains `selected_index` and references the library used to populate rows.

- **`obj_ui_controller`**
  - Location: `objects/obj_ui_controller/Create_0.gml`
  - Role: Registers UI layers, assets and fields (`global.ui_layer_names`, `global.ui_assets`, `global.ui_fields`) and holds basic tune library defaults used by the UI.

> Short notes about ongoing improvements are tracked in `PROJECT_PLAN.md` (stable documentation and design proposals live there).

---

## UI architecture (current state)

- **UI Layers:** `main_menu_layer`, `settings_window_layer`, `tune_window_layer`, `calibration_window_layer` (each layer contains backgrounds, flex panels and instances such as buttons and fields).
- **Flex panels:** Used for layout and row stacking in tune window and other panels.
- **UI Script Flow:** `scripts/scr_button_scripts/` centralizes button actions and toggles windows; it calls `scr_ui_refresh()` / `scr_update_fields()` as needed.

---

## UI system details (how it works)

This section documents the concrete runtime UI architecture and how UI instances are configured and wired together.

### Base UI objects
- `obj_UI_parent` — Base class for all UI instances.
  - Registers every instance in `global.ui_assets` during Create (stores pairs `[ui_num, id]` indexed by layer number). This allows `scr_ui_refresh()` to repair or re-link instances if IDs change.
  - Stores `ui_name`, `ui_layer`, `ui_layer_num`, `ui_group`, `ui_num` and common visual properties (`ui_sprite`, `ui_sprite_frame`).
- `obj_btn_base` — Button base object (inherits `obj_UI_parent`).
  - Key properties: `button_ID`, `button_label`, `button_target`, `button_click_value`, `button_script_index`.
  - Mouse click calls `scr_handle_button_click(self.button_script_index)` (see `scripts/scr_button_scripts/`) so the button's `button_script_index` drives which action runs. `button_target` and `button_click_value` are used by handlers (e.g., `scr_checkbox_click`, `scr_open_window`, or settings handlers).
- `obj_field_base` — Field / text label (inherits `obj_UI_parent`).
  - Key properties: `field_ID`, `field_target`, `field_value`, `field_contents`.
  - `scr_update_fields(_layer)` reads `field_target` (string name or array) and updates `field_contents` from `field_value`.

### Registration & refresh
- Instances are placed manually in the Room UI (`roomui/RoomUI/RoomUI.yy`). The Create event of `obj_UI_parent` registers each instance into `global.ui_assets[layer_num]` as `[ui_num, id]`.
- `scr_ui_refresh(layer)` inspects `global.ui_assets[layer]` and if an ID is missing, it finds a matching `obj_UI_parent` with the same `ui_num` and re-links the pair.

### Buttons & interactions
- Buttons are fully configured in the Room UI editor by overriding properties on instances (see `RoomUI.yy` for examples). Typical configuration sets `button_script_index` and `button_click_value` (and sometimes `button_target`).
- `scr_handle_button_click(index)` maps indices to high-level actions (open window, start play, save settings, etc.). Handlers use `self` (the button instance) to read `button_target` / `button_click_value` where needed.
- Checkboxes are `obj_btn_check` + `scr_checkbox_click()` which sets global state (e.g., `global.tune_selection`) and unchecks other boxes as needed using `scr_uncheck_all()`.
- Passive tune-picker canvas anchor clicks can route through the no-action path (`scr_script_not_set`); `tune_library_canvas_anchor` is intentionally treated as no-op noise and exits early without logging.

### Timeline/notebeam anchor runtime contract
- Anchor rendering and click routing are split by coordinate space:
  - GUI-space clicks: gameviz/notebeam handlers (`obj_field_base` Mouse_7 -> `gv_handle_gameviz_controls_click` / `gv_handle_notebeam_click`).
  - Room/screen-space clicks: tune-structure handler (`obj_field_base` Mouse_7 -> `gv_measure_nav_handle_click(mouse_x, mouse_y)`).
- Anchor cache setup/storage is centralized via `gv_anchor_cache_get_or_create()` and `gv_anchor_cache_store()` in `scr_game_viz` and reused by timeline/notebeam/tune-structure anchor draw paths.
- Synthetic measure navigation fallback is centralized via `gv_build_synthetic_measure_nav_map()` so both bind-time and panel bootstrap paths share identical fallback measure grid behavior.
- Measure-nav state wiring is centralized via `gv_measure_nav_apply_to_timeline_state()` and `gv_measure_nav_ensure_state_defaults()` so bind-time and lazy panel bootstrap use the same state shape.
- Measure-nav source event selection/flattening is centralized via `gv_measure_nav_resolve_source_events()` to keep bootstrap behavior consistent when falling back from planned arrays to scheduler group events.
- Measure-nav fallback end-time selection is centralized via `gv_measure_nav_resolve_end_ms_from_events()` and `gv_measure_nav_resolve_end_ms_from_state()` to keep synthetic-map sizing consistent across paths.
- Set segment runtime restoration is centralized via `gv_apply_cached_segment_runtime()`: score/override references, trimmed measure-nav, and canonical structure model are prebuilt before Play and swapped at boundaries without file I/O or reconstruction.
- `gv_rebuild_measure_nav_for_segment()` remains an offline/manual fallback; live set playback does not invoke it. Single-tune playback keeps bind-time nav built from active playback events so loop-runtime structure tiles stay aligned with looped audio/notebeam timing.
- Set-mode measure tracking uses a prebuilt flat table (`global.playback_set_measure_nav_all`) rather than per-segment rebuild so `gv_get_current_planned_measure()` is never stale at segment boundaries. Built once by `gv_build_set_measure_nav_all()` after sprite cache population; per-segment `measure_nav_entries` continues to serve the structure-panel UI display only. Pickup entries (`measure=0`) remain authoritative no-highlight windows, so later pickup segments do not inherit the previous segment's measure number.
- Single-tune loop score-lane rendering normalizes playhead time to the loop-cycle window (derived from loop iteration marker boundaries) before score image range tests, so measure-window clipping and `playback_to_image` lookup stay stable across loop restarts.
- Score-lane image mapping uses manifest `image_meta[].content_left_px` / `content_right_px` as the authoritative drawable content window. Do not scale time across the full PNG width: exported measures can carry different left/right whitespace, and using full-sprite width causes apparent traveling jitter even when playhead timing is smooth.
- **Pickup data flow (authoritative source):** `has_pickup` is computed by the VBA ABC parser (`PickupDetected`) and written into `<TuneName>.score_snippets.json` at export time. At runtime, `scr_score_manifest_read()` reads `score/score_images.json` then merges `has_pickup` and `snippets[]` from the sibling `.score_snippets.json` onto the manifest struct. `scr_score_sprites_load()` extracts `snippets[].duration_units` into the flat `global.score_snippet_durations` array and sets `global.score_has_pickup`. All measure-numbering paths consume these globals — no runtime heuristics from duration arithmetic.
- **score_images.json vs score_snippets.json:** `score/score_images.json` holds sprite filenames, `image_meta`, `beats_per_measure`, `units_per_measure`. `<TuneName>.score_snippets.json` (sibling to the tune JSON, not in score/) holds `has_pickup`, per-snippet `duration_units`, `is_pickup`, and `playback_to_image`. Always check both files when debugging pickup or measure-numbering issues.
- Tune-structure panel rendering is anchor-driven (`tunestructure_canvas_anchor` in `obj_field_base` Draw_0); the legacy Draw_0 fallback panel path in `obj_game_viz` is retired.
- Cached anchor rendering (`obj_field_base` Draw_0) sets `global.GV_ANCHOR_RECT_X_OFFSET/Y_OFFSET` to `-bbox_left/-bbox_top` while drawing notebeam and tune-structure into local surfaces.
- `scr_game_viz` hitbox writes use those offsets (via hitbox bias) so stored hitboxes remain in global screen space and align with click tests.
- Notebeam popup draws in GUI (`obj_game_viz` Draw_64) to ensure it stays above world-space notebeam/chanter visuals.

### Fields & dynamic text
- Fields use `field_target` to reference either a global array (like `tune_library`) or a global variable name (string). `scr_update_fields()` pulls the value and fills `field_contents` to change the visible label.
- Fields also have `field_script_index` to allow scripted actions when interacted with.

### Tune picker specifics (tune_window_layer)
- The tune window contains six manual rows `fp_tune_row_1..fp_tune_row_6`. Each row contains:
  - `obj_btn_check` instances (radio/checkbox) with `button_script_index` set to the checkbox handler and `button_click_value` equal to the row index (used to set `global.tune_selection`).
  - `obj_field_base` instances with `field_target` set to `tune_library` and `field_value` set to the index; `scr_tune_picker_populate()` (in `scr_tune_library/`) updates the visible rows and associated text when a library is loaded.

  Note: The population routine **pairs** each field and checkbox **preferentially by explicit editor-assigned IDs** (use `field_ID` on fields and `button_ID` on checkboxes — e.g., 1..10). If those are not set it falls back to `ui_num` (the runtime registration number), and as a last resort it pairs by on-screen order (sorted by Y). This lets you safely add rows (7–10) and control their mapping via the `field_ID`/`button_ID` properties.
- The `obj_tune_ok_button` calls `scr_handle_button_click` with its `button_script_index` (mapped to `scr_tune_OK`) which loads the selected tune and initiates build→start playback flow.
  - `scr_tune_OK` now resolves picker/library/entry state through `scr_button_resolve_picker_selection()` before loading candidate tune paths.
  - Candidate tune paths are assembled via `scr_button_build_tune_load_candidates()`.
  - Each candidate load/apply attempt runs through `scr_button_try_load_tune_candidate()`.
  - Runtime per-tune overrides from UI fields are applied via `scr_button_apply_set_item_from_ui_fields()`.
  - Runtime globals for playback/metronome/count-in/swing/gracenote are applied via `scr_button_apply_globals_from_set_item()`.
  - Post-load UI updates (window visibility + game info title) are applied via `scr_button_apply_post_tune_load_ui()`.
  - Created-set summary logging is emitted via `scr_button_log_created_set_item()`.
  - The tune button label is restored once at the end of `scr_tune_OK` (single restore point).

### Per-layer summaries (current content)
Below are the actual UI layers and the important instances placed on each (based on `roomui/RoomUI/RoomUI.yy`). All instances are manually placed in the Room UI editor and configured by overriding object properties there.

- `settings_window_layer` — Settings window
  - Title: `fp_Title_text` (text "Settings").
  - Close: `obj_settings_win_close_button` (instance of `obj_btn_winClose`, often with `button_ID = 3`).
  - MIDI In row: `setting_Lbutton_1` (left arrow `obj_btn_fieldL`), `setting_field_1` (`obj_field_base`) — field for MIDI IN device.
  - MIDI Out row: `setting_Lbutton_2`/`setting_Rbutton_2`, `setting_field_2` (`obj_field_base`) — field for MIDI OUT device.
  - Logs row: `setting_Lbutton_logs`/`setting_Rbutton_logs`, `setting_field_logs` (`obj_field_base`) — OFF/ON toggle for runtime score-lane debug logging.
  - Calibration launcher: `obj_settings_calibration_button` (`obj_btn_main`) — opens `calibration_window_layer` via `scr_open_window` (layer index 8).
  - OK: `obj_setting_ok_button` (`obj_btn_main`) — typically configured to run the settings OK handler (`scr_settings_OK`).

- `calibration_window_layer` — Calibration prototype window
  - Title: `text_calibration_title` (text "Calibration").
  - Close: `obj_calibration_win_close_button` (`obj_btn_winClose`).
  - Mode row: `calibration_mode_left_button`, `calibration_mode_field`, `calibration_mode_right_button` (button ID/script index 31).
  - Audio row: `calibration_audio_left_button`, `setting_field_cal_audio`, `calibration_audio_right_button` (button ID/script index 32).
  - Visual row: `calibration_visual_left_button`, `setting_field_cal_visual`, `calibration_visual_right_button` (button ID/script index 32).
  - Status rows: `calibration_summary_field`, `calibration_status_field` populated by `scr_button_calibration_refresh_ui()`.

- `tune_window_layer` — Tune picker window
  - Title: `fp_Title_text` (text "Tune Library").
  - Close: `obj_tune_win_close_button` (`obj_btn_winClose`).
  - Tune rows (1..6): each row has a checkbox and a field:
    - `obj_tune_checkbox_1..obj_tune_checkbox_6` (instances of `obj_btn_check`) — configured with `button_script_index = 2` (checkbox handler), `button_target = global.tune_selection`, and `button_click_value = row index`.
    - `obj_tune_field_1..obj_tune_field_6` (instances of `obj_field_base`) — set with `field_target = tune_library` and `field_value = row index`; populated at runtime by `scr_tune_picker_populate()`.
  - OK: `obj_tune_ok_button` (`obj_btn_main`) — typically configured to `scr_tune_OK()` (loads the selected tune).

- `loop_score_overview_layer` — Post-loop scoring overview panel
  - Title: `loop_score_title_text` (text "Loop Scores").
  - Close: `obj_loop_score_win_close_button` (`obj_btn_winClose`, `button_script_index = 29` → `scr_toggle_loop_score_overview`).
  - Canvas: `loop_score_matrix_canvas_anchor` (`obj_field_base`, `ui_name = "loop_score_matrix_canvas"`) — draws the loop×judge matrix via `scoring_loop_overview_draw_canvas()`.
  - Positioned at `positionLeft = 57%`, `width = 35%`, `height = 80%` (to the right of `judge_settings_layer`).
  - Toggle button `obj_button_loop_scores` on `main_menu_layer` (inside `fp_loop_scores_button`, `button_script_index = 29`).

- `gameinfo_window_layer` — Informational window
  - Title field: `obj_gameinfo_win_title` (`obj_field_base`) — shows selected tune or status (default: "No tune selected").
  - Back / OK buttons: `obj_gameinfo_back_button`, `obj_gameinfo_ok_button` (`obj_btn_main`) with appropriate `button_script_index` values for navigation.

- `current_note_layer` — Current note display
  - `obj_currentnote_field_1` (`obj_field_base`) — updated at runtime by `script_tune_callback()` to show the currently played note.

- `main_menu_layer` — Main menu
  - Buttons: `obj_button_play` (`obj_btn_main`, `button_script_index = 1`), `obj_button_settings` (`obj_btn_main`, `button_script_index = 3`, `button_target = settings_window_layer`), `obj_button_tune` (`obj_btn_main`, `button_script_index = 3`, `button_target = tune_window_layer`), plus exit/back buttons.

> Note: For all UI instances the important configuration is done in the Room UI editor via overridden properties (e.g., `button_script_index`, `button_target`, `field_target`, `field_value`). `obj_UI_parent` registers each instance into `global.ui_assets` so scripts can refresh or re-link instances at runtime.

---

## Global State Inventory

All globals are initialized by the owning script/object at startup. **Do not create new globals without adding a row here.**

| Global | Type | Shape summary | Owner (initialized in) | Key consumers |
|--------|------|---------------|------------------------|---------------|
| `global.emb_library` | array | `[{emb_id, emb_name, pattern, target_note, notes, timing, anchor_index, category}]` | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_embellishments` |
| `global.EMBELLISHMENT_CONFIG` | struct | BPM-aware gracenote timing constants — see struct schema below | `obj_game_controller` Create | `scr_embellishments` `embellishment_to_notes()` |
| `global.METRONOME_DRUM_PROFILES` | struct | Named drum note-mapping profiles: `{"General MIDI": {kick, snare, hi_hat, …}}` | `obj_game_controller` Create | `scr_metronome` |
| `global.current_metronome_drum_profile` | string | Active profile key (e.g. `"General MIDI"`) | `obj_game_controller` Create | `scr_metronome` |
| `global.timeline_cfg` | struct | Viz/timing config: `{enabled, tune_channel, tune_show_other_parts_ghost, tune_other_parts_alpha, timeline_score_visibility_mode, audio_output_offset_ms, visual_alignment_offset_ms, input_capture_offset_ms, scoring_compare_offset_ms, score_lane_debug_log, score_lane_debug_boundary_window_ms, score_lane_debug_focus_title, score_lane_debug_file_log, score_lane_debug_file_path, score_lane_anchor_guides_enabled, score_lane_anchor_guide_color, score_lane_anchor_guide_alpha, score_lane_anchor_guide_width, ...}` | `obj_game_controller` Create | `scr_game_viz` |
| `global.timeline_state` | struct | Full runtime playback/viz state — see struct schema below | `obj_game_viz` Create | `scr_game_viz`, `scr_scoring`, `scr_tune_scripts` |
| `global.active_set` | struct | Loaded set metadata + segments + score override plan — see struct schema below | `scr_set_scripts` `scr_set_init_global()` | `scr_set_scripts`, `scr_button_scripts`, `scr_scoring` |
| `global.playback_events` | array | Stitched MIDI + marker event array (shared by single-tune and set paths) | `scr_set_scripts` / `scr_button_scripts` | `scr_tune_scripts`, `scr_game_viz`, `scr_scoring` |
| `global.playback_context` | struct | Thin navigation wrapper: `{mode, display_title, active_segment, segments[], score_override_plan[]}` | `scr_set_scripts` `scr_playback_context_init()` | `scr_game_viz`, `scr_scoring`, event export |
| `global.current_set` | array | Array of `set_item` structs (playlist for current session) | `obj_game_controller` Create | `scr_button_scripts`, `scr_set_scripts` |
| `global.current_set_item_index` | real | Index into `global.current_set`; -1 = none | `obj_game_controller` Create | `scr_button_scripts` |
| `global.tune` | instance id | The `obj_tune` instance (single tune data model) | `obj_game_controller` Create | `scr_tune_load`, `scr_tune_scripts`, `scr_button_scripts` |
| `global.tune_library` | struct | `{tunes: [{filename, title, …}]}` | `obj_ui_controller` Create | `scr_tune_library`, tune picker UI |
| `global.primary_data_root_override` | string | Optional absolute/relative data root override (`.../datafiles/` style); IDE uses project read root + LocalAppData write root by default, while packaged/non-IDE can use this override as category base. | `obj_game_controller` Create | `scr_data_paths_get_content_root`, `scr_data_paths_get_user_data_root`, category path helpers |
| `global.tune_selection` | real | Index of selected tune in picker; -1 = none | `obj_ui_controller` Create | `scr_button_scripts`, checkboxes |
| `global.selected_tune_time_sig` | string | Time-sig string of tune highlighted in picker (before OK) | `obj_ui_controller` Create | `scr_button_scripts` |
| `global.score_transition_images` | struct | Current tune transition score groups from `score_images.json`: `{prior_replace?, bridge?, follow_replace?}` | `scr_tune_load` `scr_score_sprites_load()` | future score override planning / score-lane runtime |
| `global.score_has_pickup` | bool | True when the current tune's first snippet is an opening pickup bar | `scr_tune_load` `scr_score_sprites_load()` | `gv_build_measure_nav_map`, score-lane structural path, `gv_restore_score_segment_cache` |
| `global.score_segments_sprites` | array | Per-segment runtime cache: score sprites/maps/meta, durations/pickup, override bundles, trimmed measure-nav, canonical model/parity | `scr_set_scripts` `scr_set_init_global()` | `scr_button_scripts`, `gv_build_set_measure_nav_all`, `gv_apply_cached_segment_runtime` |
| `global.SET_PREP_LAST_TOTAL_MS` / `global.SET_PREP_LAST_SCORE_MS` / `global.SET_PREP_LAST_NAV_MS` | real | Most recent pre-play set preparation timings; context-only because work completes before playback | `scr_button_scripts` `scr_goto_playroom` | performance report context/popup |
| `global.playback_set_measure_nav_all` | array | Flat sorted measure-nav table across all set segments: `[{measure, part, start_ms, end_ms, status, segment_idx}]`; built once at load time | `scr_set_scripts` `scr_set_init_global()` | `gv_get_current_planned_measure` (Priority 0 in set mode), `gv_build_set_measure_nav_all` |
| `global.EVENT_HISTORY` | array | Append-only event log during playback — see struct schema below | `scr_event_log` (lazy init) | `scr_event_log`, export functions |
| `global.EVENT_RUNTIME_PLAYER` | array | Minimal player-input sidecar log: `[{event_type, timestamp_ms, note_midi, channel, velocity, loop_iteration}]` | `scr_event_log` (lazy init) | `scr_event_log`, future runtime reconstruction/export |
| `global.EVENT_RUNTIME_PLANNED` | array | Minimal planned-dispatch sidecar log: `[{event_id, actual_time_ms, loop_iteration}]` | `scr_event_log` (lazy init) | `scr_event_log`, future runtime reconstruction/export |
| `global.EVENT_HISTORY_ENABLED` | bool | Master on/off for event logging | `scr_event_log` (lazy init) | `scr_event_log` |
| `global.EVENT_RUNTIME_CAPTURE_ENABLED` | bool | Master on/off for minimal runtime sidecar capture used by the reconstruction path | `scr_event_log` (lazy init) | `scr_event_log` |
| `global.EVENT_HISTORY_AUTO_EXPORT` | bool | Auto-export CSV/summary after playback ends; defaults false, manual export remains available | `scr_event_log` (lazy init) | `scr_event_log` |
| `global.EVENT_HISTORY_EXPORT_INCLUDE_GAME_EVENTS` | bool | Export-time filter toggle for planned `source="game"` rows (live history unchanged) | `scr_event_log` (lazy init) | `event_history_export_csv`, `event_history_export_summary_json` |
| `global.PERF_BENCHMARK_POWER_MODE_LABEL` | string | Manual benchmark tag for power plan (`balanced`, `high_performance`, etc.) | `scr_event_log` (lazy init) | export metadata |
| `global.PERF_BENCHMARK_MIDI_ACTIVITY_LABEL` | string | Manual benchmark tag for input activity (`idle`, `active_input`, etc.) | `scr_event_log` (lazy init) | export metadata |
| `global.PERF_BENCHMARK_NOTES` | string | Freeform benchmark notes attached to summary exports | `scr_event_log` (lazy init) | export metadata |
| `global.perf_run_last_elapsed_ms` | real | Most recent run elapsed time captured at PLAY_STOP for compact performance summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.perf_run_last_groups_total` | real | Most recent run event-group count captured for compact summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.perf_run_last_events_total` | real | Most recent run event count captured for compact summary output | `scr_tune_scripts` `tune_start`/PLAY_STOP | `perf_run_summary_append_latest` |
| `global.rt_budget_sched_spike_count` | real | Count of emitted scheduler spike traces for the current run | `scr_tune_scripts` `tune_start`/`tune_rt_budget_diag_trace_scheduler_spike` | `perf_run_summary_append_latest` |
| `global.perf_run_summary_last_written_play_id` | real | Last play ID written to `run_summaries.jsonl`, used to avoid duplicate append on cleanup reentry | `scr_tune_scripts` `perf_run_summary_append_latest` | `perf_run_summary_append_latest` |
| `global.perf_report_state` | struct\|undefined | Active schema-v3 report: run identity/context, fixed overall/segment/transition buffers, whole-run accuracy histograms, render accumulator, completed summary | `obj_game_controller` Create; contents rebuilt by `perf_report_begin_run` | `scr_tune_scripts`, Draw owners |
| `global.PERF_REPORT_LATEST` | struct\|undefined | Immutable latest completed schema-v3 report published at the final playback group for zero-delay post-play UI | `obj_game_controller` Create; updated by `perf_report_complete` | `scr_game_viz`, JSONL persistence |
| `global.scoring_last_run` | struct\|undefined | Result of most recent scoring run; undefined until first run | `scr_scoring` (lazy init) | `scr_scoring`, UI display |
| `global.timing_calibration` | struct | Two-offset calibration state: `{active, status, active_device_key, device_profiles, audio_offset_ms, visual_offset_ms, input_offset_ms (reserved), last_message, jitter_summary, calibration_mode_index, calibration_advanced_open, calibration_preview, calibration_logs, calibration_result}` | `scr_tune_scripts` (lazy init) | `scr_tune_scripts` timing calibration functions, `scr_button_scripts` calibration UI refresh/actions |
| `global.metronome_mode` | real | 0=None 1=Click 2=Drums | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts`, `scr_scoring` |
| `global.metronome_pattern_selection` | real | Index into `global.metronome_pattern_options` | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts` |
| `global.metronome_volume` | real | MIDI velocity 0–127 | `obj_game_controller` Create | `scr_metronome`, `scr_button_scripts` |
| `global.single_tune_runtime_bpm` | real | Single-tune authoritative BPM mirror used when UI field binding is unavailable at play time | `scr_button_scripts` (lazy set in tune load/BPM changes) | `scr_button_scripts` |
| `global.swing_mult` | real | Swing multiplier; 0 = use default | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_button_scripts` |
| `global.gracenote_override_ms` | real | Gracenote duration override; 0 = BPM-derived | `obj_game_controller` Create | `scr_preprocess_tune`, `scr_embellishments` |
| `global.MIDI_chanter` | string | Chanter mapping preset (`"default"` or `"blair"`) | `obj_game_controller` Create | `scr_MIDI`, `scr_scoring` |
| `global.midi_input_device` | real | Device index for MIDI input | `obj_game_controller` Create | `scr_MIDI`, `scr_button_scripts` |
| `global.midi_output_device` | real | Device index for MIDI output | `obj_game_controller` Create | `scr_MIDI`, `scr_button_scripts` |
| `global.RT_BUDGET_DIAG_ENABLED` | bool | Master runtime sampling gate for post-play jitter/scheduler summaries | `obj_game_viz` Create | `scr_tune_scripts` |
| `global.PERF_DIAG_FILE_LOG_ENABLED` | bool | When false, perf diagnostics stay in memory for post-play summaries and do not write longform JSONL/output logs during playback | `obj_game_viz` Create | `scr_tune_scripts` |
| `global.GAME_STEP_FPS` | real | Game step rate (game_set_speed); higher = less scheduler jitter | `obj_game_controller` Create | `obj_game_controller` only |
| `global.PLAYBACK_SCHEDULER_MODE` | string | `"timesource"` or `"step"` | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_DRAIN_MS` | real | Time-source startup slack used to inline the first near-due group instead of arming a late first callback | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_ARM_DELAY_MS` | real | Extra startup delay applied only to the first time-source arm; tune start is re-anchored so scheduler timing stays aligned | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_SCHEDULER_STARTUP_SPIKE_GRACE_MS` | real | Startup grace window that suppresses scheduler spike trace emission near tune start | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.PLAYBACK_AUDIO_BACKEND_OPTIONS` | array | Allowed output backend values (`["midi", "hybrid_metronome_sample"]`) for safe runtime mode selection | `obj_game_controller` Create | settings/debug tooling (future), `scr_tune_scripts` helpers |
| `global.PLAYBACK_AUDIO_BACKEND` | string | Active output backend key; default `"midi"` keeps legacy behavior, `"hybrid_metronome_sample"` enables metronome sample routing | `obj_game_controller` Create | `scr_tune_scripts` (`tune_start`, `script_tune_callback_batched`) |
| `global.METRONOME_SAMPLE_SOUND_EMPHASIS` | real | Sound asset id for accented metronome click (`-1` = unconfigured) | `obj_game_controller` Create | `scr_tune_scripts` `playback_emit_metronome_sample` |
| `global.METRONOME_SAMPLE_SOUND_NORMAL` | real | Sound asset id for normal metronome click (`-1` = unconfigured) | `obj_game_controller` Create | `scr_tune_scripts` `playback_emit_metronome_sample` |
| `global.METRONOME_SAMPLE_PRIORITY` | real | Audio playback priority for metronome sample sink | `obj_game_controller` Create | `scr_tune_scripts` `playback_emit_metronome_sample` |
| `global.game_state` | string | `"menu"` \| `"playing"` \| …  | `obj_game_controller` Create | `scr_button_scripts`, various |
| `global.ID_game_handler` | instance id | Self-reference for `obj_game_controller` | `obj_game_controller` Create | global access |
| `global.ui_assets` | array | UI instance registry by layer: `[[ui_num, id], …]` per layer index | `obj_ui_controller` Create | `obj_UI_parent`, `scr_UI_scripts` |
| `global.ui_fields` | array | Registered field instances per layer | `obj_ui_controller` Create | `scr_UI_scripts` |
| `global.ui_layer_names` | array | Layer name strings indexed by layer num | `obj_ui_controller` Create | `scr_UI_scripts` |
| `global.show_review_beat_bands` | bool | Overlay toggle: beat bands in post-play review | `obj_game_controller` Create | `scr_game_viz` |
| `global.show_review_emb_boxes` | bool | Overlay toggle: embellishment boxes in post-play review | `obj_game_controller` Create | `scr_game_viz` |
| `global.loop_mode_enabled` | bool | Loop playback on/off | `obj_game_controller` Create | `scr_tune_scripts`, `scr_button_scripts` |
| `global.loop_repeat_total` | real | How many times to loop | `obj_game_controller` Create | `scr_tune_scripts` |
| `global.LOOP_COMPARE_DUMP_ENABLED` | bool | Enables planned-event snapshot exports at play start for loop/non-loop compare diagnostics | `obj_game_controller` Create | `scr_button_scripts` (`start_play` dump hook) |
| `global.timeline_state.loop_session` | struct | Authoritative single-tune loop descriptor/state: `{active, selected_refs[], loop_start_boundary{}, loop_end_boundary{}, boundary_refinement{}, start_ms, end_ms, pass_duration_ms, passes_total, passes_completed, spacer_enabled, spacer_duration_ms, jump_enabled, phase, current_pass_index, phase_start_ms, phase_end_ms, pickup_mode, degraded}` | `scr_button_scripts` (`scr_button_loop_build_playback_events`, `scr_button_reset_loop_state`) | `scr_tune_scripts` (`script_tune_callback_batched`), `scr_game_viz` |
| `global.timeline_state.loop_boundary_refinement` | struct | Optional backend loop endpoint refinement state (no UI dependency): `{enabled, start_part, start_measure, start_beat, start_beat_fraction, end_part, end_measure, end_beat, end_beat_fraction}`; when enabled, loop boundary resolver snaps start/end to the selected beat markers while keeping the end boundary exclusive. | `scr_game_viz` (`gv_bind_timeline_on_tune_start`) | `scr_game_viz` (`gv_loop_resolve_boundary_endpoints`, `gv_loop_clear_selected_measures`), `scr_button_scripts` (`scr_button_reset_loop_state`) |
| `global.loop_score_overview_ui_state` | struct | UI state for loop score overview panel: `{scroll_row, selected_iteration}` | `scr_scoring` (lazy init via `scoring_loop_overview_ensure_state`) | `scr_scoring` draw/scroll/click helpers |
| `global.timeline_state.loop_iteration_scores` | array | Per-iteration score results from last loop session: `[{iteration, score, grade, start_ms, end_ms}]` — field on `timeline_state` | `scr_scoring` `scoring_build_loop_iteration_scores()` | `scoring_loop_overview_draw_canvas`, overview panel |
| `global.timeline_state.loop_score_row_hitboxes` | array | Draw-derived loop overview click hitboxes: `[{iteration, x1, y1, x2, y2}]` used so row clicks match painted rows exactly. | `scr_scoring` `scoring_loop_overview_draw_canvas()` | `scoring_loop_overview_handle_click()` |
| `global.timeline_state.review_selected_loop_iteration` | real | Currently selected post-play loop iteration (`>0`) used to project review UI to one pass; `-1` means none selected. | `scr_scoring` (`scoring_loop_overview_select_iteration`, `scoring_build_loop_iteration_scores`) | `scr_scoring`, `scr_game_viz` tune-structure projection |
| `global.timeline_state.review_selected_loop_window` | struct | Selected post-play loop window: `{iteration, start_ms, end_ms}` used for tune-structure/notebeam projection without mutating canonical nav arrays. | `scr_scoring` (`scoring_loop_overview_select_iteration`, `scoring_build_loop_iteration_scores`) | `scr_game_viz` (`gv_draw_tune_structure_panel`) |
| `global.DIAG_SESSION_RUN_UUID` | string | Per-process UUID used to correlate startup and play marker entries in `debug/session_markers.jsonl`. | `scr_tune_scripts` `diag_session_get_run_uuid()` | `diag_session_marker_write` |

---

## Zoom Mode Toggle — Architecture Testing

**Status:** Experimental side-by-side comparison enabled. Both measure-based (legacy) and time-based zoom paths are fully implemented and accessible via internal toggle.

**Config Fields (all in `global.timeline_cfg`):**
- `notebeam_zoom_mode` (string): `"time"` (default) or `"measures"` (legacy fallback)
  - When `"measures"`: uses `measures_ahead` / `measures_behind` converted to milliseconds
  - When `"time"`: uses direct millisecond window (ignores measure config)
- `measures_ahead` (real): lookahead in measures (only used when mode=`"measures"`)
- `measures_behind` (real): lookbehind in measures (only used when mode=`"measures"`)
- `time_ahead_ms` (real, default 4500): lookahead in milliseconds (only used when mode=`"time"`)
- `time_behind_ms` (real, default 2250): lookbehind in milliseconds (only used when mode=`"time"`) — **internally locked to exactly 0.5 × time_ahead_ms**
  - User-facing control is ahead-only; behind is automatically derived for visual stability
  - Enforced in `scr_button_scripts::scr_viewport_ahead_change()` and `scr_game_viz::gv_notebeam_sync_window_from_cfg()`
  - Behind UI row removed from settings (2026-06-22 cleanup)

**How to test:**
1. Default startup mode is time-based (`global.timeline_cfg.notebeam_zoom_mode = "time"`)
2. To test legacy behavior: set `global.timeline_cfg.notebeam_zoom_mode = "measures"` before tune start
3. The active mode is stored in `global.timeline_state.zoom_mode_active` for UI/debug inspection

**Decision path:**
- If time-based feels natural across set transitions → propose removing measure-based and making time-based primary
- If measure-based remains better for phrase learning → keep both and add UI toggle for user choice
- If hybrid benefits are clear → document both modes and keep toggle as permanent user-facing feature

**Performance note:** Switching modes has neutral-to-slight performance benefit (simpler math, fewer conversions). No new allocations or cache invalidation beyond standard sync.

---

## Key Struct Schemas

These are the shared data "vocabulary" of the codebase. When reading/writing these structs, match these field names exactly.

### `set_item` — single tune entry in a set/playlist
Created by `create_set_item()` in `scr_tune_scripts`.
```
{
    tune_filename:         string,   // relative path e.g. "tunes/Foo/Foo.json"
    bpm:                   real|undefined,  // undefined = use tune metadata default
    metronome_mode:        real,     // 0=None 1=Click 2=Drums
    metronome_pattern:     real,     // index into pattern_options
    metronome_volume:      real,     // 0-127
    count_in_measures:     real,     // number of count-in bars before tune
    loop_jump_to_selection: bool,
    include_drum_roll:     bool,
    drum_roll_variant:     string|undefined
}
```

### `tune_data` — loaded tune (on `obj_tune` instance)
Populated by `scr_tune_load_json()`.
```
{
    tune_metadata:  struct,   // title, tempo_default, meter, part, …
  score_manifest: struct,   // parsed score/score_images.json (flat or transition-grouped)
    events:         array,    // raw ABC/JSON event structs
    performance:    struct,   // performance-level settings from JSON
    event_count:    real,
    is_loaded:      bool,
    filename:       string
}
```

### `timeline_state` — runtime playback + visualization state
Initialized in `obj_game_viz` Create. Owns the live playhead and all span arrays.
```
{
    active:             bool,
    playhead_ms:        real,
    start_clock_ms:     real,
    bpm:                real,
    meter_num:          real,
    meter_den:          real,
    measure_ms:         real,
    ms_ahead:           real,    // lookahead window for notebeam
    ms_behind:          real,    // lookbehind window for notebeam
    planned_events:     array,   // ref to preprocessed event array
    planned_spans:      array,   // [{start_ms, end_ms, note, channel, is_embellishment}]
    tune_played:        array,   // append-only game note_on/off events
    player_in:          array,   // append-only player note_on/off events
    pending_tune:       struct,  // open note_on pairs awaiting note_off (keyed by "ch:note")
    pending_player:     struct,
    planned_i0:         real,    // cached visible window start index into planned_events
    planned_i1:         real,    // cached visible window end index
    planned_span_i0:    real,
    planned_span_i1:    real,
    measure_nav_entries:    array,
    measure_nav_parts:      array,
    loop_session:       struct,  // authoritative loop lifecycle descriptor/state (phase, pass, boundaries, pickup mode)
    measure_nav_tile_hitboxes: array,
    measure_nav_scroll_row: real,
    measure_nav_total_rows: real,
    measure_nav_view_rows:  real,
    measure_nav_controls:   struct,
    anchor_id:          noone|instance_id
}
```

### `planned_span` — one note span for visualization
Elements of `global.timeline_state.planned_spans[]`. Created by `gv_build_planned_spans()`.
```
{
    source:           string,  // "tune_planned"
    start_ms:         real,
    end_ms:           real,
    dur_ms:           real,
    note_midi:        real,
    note_canonical:   string,
    note_letter:      string,
    lane_idx:         real,
    channel:          real,
    is_embellishment: bool,
    measure:          real,
    beat:             real,
    beat_fraction:    real,
    event_id:         any
}
```
**Important:** `planned_spans` contains spans for the *entire set* (all tunes), including transition tunes. Spans are NOT pre-clipped to segment boundaries. When computing per-segment scores or overlays, always pass spans through `scoring_filter_spans_in_window()` which clips `start_ms`/`end_ms` to the window — a span that merely overlaps the window boundary is returned with its times clamped, not its original full length.

### `active_set` — loaded musical set metadata
Initialized by `scr_set_init_global()`, populated by `scr_set_load_json()`.
```
{
    is_loaded:       bool,
    filename:        string,
    title:           string,
    id:              string,
    description:     string,
    tunes:           array,   // raw tune entries from JSON
    segments:        array,   // preprocessed segment structs (end_ms includes boundary lead-in)
  score_override_plan: array, // per-segment tail/bridge/head score override metadata
  boundary_plan:       array, // transition-authoritative boundary plan (scr_set_build_boundary_plan)
    active_segment_index: real,
    first_bpm:       real,
    first_meter:     string,
    set_bpm_percent:           real,      // 1.0 = normal speed
    set_gracenote_override_ms: real|undefined,
    set_count_in_measures:     real
}
```
**Boundary lead-in note:** `segments[i].end_ms` now includes any fallback lead-in duration appended to tune i's content (Option 2 model). The next segment's `start_ms` equals the previous `end_ms`, so the hold window is attributed to the tune whose note is held.

### `playback_context` — thin navigation wrapper for viz/scoring/export
```
{
    mode:           string,   // "none" | "tune" | "set"
    display_title:  string,
    active_segment: real,
  score_override_plan: array,
    segments: [{
        tune_index:  real,
        filename:    string,
        title:       string,
        bpm:         real,
        meter:       string,
        start_ms:    real,
        end_ms:      real,
    bar_events:  array,   // marker events with type "bar"|"beat"
    score_manifest: struct|undefined
    }]
}
```

### `EVENT_HISTORY` entry — one logged playback event
Elements of `global.EVENT_HISTORY[]`. Appended by `event_history_add()`.
```
{
    timestamp_ms:      real,
    expected_time_ms:  real,
    actual_time_ms:    real,
    delta_ms:          real,
    measure:           real,
    beat:              real,
    beat_fraction:     real,
    event_type:        string,   // "note_on" | "note_off"
    source:            string,   // "game" | "player" | "metronome"
    note_midi:         real,
    note_letter:       string,
    tune_name:         string,
    is_embellishment:  bool
}
```

  ### `EVENT_RUNTIME_PLAYER` entry — minimal player runtime record
  Elements of `global.EVENT_RUNTIME_PLAYER[]`. Appended by `event_runtime_capture_player()`.
  ```
  {
    event_type:     string,
    timestamp_ms:   real,
    note_midi:      real,
    channel:        real,
    velocity:       real,
    loop_iteration: real
  }
  ```

  ### `EVENT_RUNTIME_PLANNED` entry — minimal planned runtime record
  Elements of `global.EVENT_RUNTIME_PLANNED[]`. Appended by `event_runtime_capture_planned()`.
  ```
  {
    event_id:       real,
    actual_time_ms: real,
    loop_iteration: real
  }
  ```

### `EMBELLISHMENT_CONFIG` — gracenote timing constants
```
{
    gracenote_unit_ms_base:     real,   // base unit at reference_bpm
    min_gracenote_ms:           real,
    max_gracenote_ms:           real,
    bpm_scaling_factor:         real,   // ms per BPM increase (negative)
    reference_bpm:              real,
    max_emb_percent:            real,   // max fraction of target note stolen
    fallback_min_ms:            real,
    fallback_max_ms:            real,
    fallback_fast_bpm_threshold: real,
    fallback_slow_bpm_threshold: real
}
```

---

## Tune subsystem (current state)

### File Organization
- **Source:** `datafiles/tunes/` contains tune JSON files (e.g., `Jig_of_Slurs.json`, `Scotland_the_Brave.json`).
- **Runtime:** Files must be marked as **Included Files** in the GameMaker project so they're copied to the runtime directory (`tunes/` at game runtime, not `datafiles/tunes/`).

### Library Building & Loading
- **Build process:** `scr_build_tune_library(_folder)` scans a folder recursively for `*.json` files (excluding `tune_library.json`, `score_images.json`, and score sidecar files `*.score_snippets.json`, `*.score_groups.json`, `*.score_part*.json`), parses tune metadata, and writes an index file `tune_library.json` containing all discovered tunes.
  - Called automatically from `obj_game_controller` Create event on startup.
  - Also callable manually via button case 12 (regenerate button in settings panel) for debugging/testing.
  - Handles multiple tune JSON formats: flat structure (`{"tune": {...}}`) or array-only (`[...]`).
  - Skips empty files and logs warnings for invalid JSON (uses try-catch for robustness).
  
- **Library loading:** `scr_tune_picker_populate()` reads the generated `tune_library.json` index and populates the UI rows with tune titles, composers, and rhythms for the picker.

### Tune JSON Format
Each tune file should have a flat structure with `"tune"` at the root:
```json
{
  "tune": {
    "title": "Scotland the Brave",
    "composer": "trad.",
    "rhythm": "March",
    "reference number": "1",
    ...metadata fields...
  },
  "metronome": { ... },
  "performance": { ... },
  "info": { ... },
  "events": [ ... ]
}
```
The nested `"metadata"` wrapper structure is **not supported** and will cause the tune to be skipped.

### Tune Loader
- `scr_tune_load_json(_filename)` parses a tune JSON file and populates the `obj_tune` instance with metadata, events, and state flags.

### Playback
- `tune_start()` initiates playback using a GameMaker `time_source`.
- `script_tune_callback()` is the playback callback that sends MIDI events at runtime.

### UI Integration
- `roomui/RoomUI/` provides the tune picker window with up to 10 rows.
- `scr_tune_picker_populate()` populates the UI rows from `global.tune_library`.

### Debugging
- Use the **Regenerate Tune Library button** (button case 12, placed in settings panel) to manually trigger library rebuild and see debug output like:
  ```
  scr_build_tune_library: wrote tunes/tune_library.json (2 tunes)
  ```
  This helps isolate timing and scope of the build process without restarting the game.

### Log locations (runtime)
- **General debug stream (`show_debug_message`)**:
  - Goes to the GameMaker/IDE Output stream.
  - Includes BPM diagnostics such as `[BPM-CHANGE]`, `[BPM-REBUILD]`, `[START-PLAY]`, and `[START-PLAY-BPM]`.
  - When Logs is ON, these BPM lines are mirrored to the score-lane debug file by `scr_button_bpm_debug_log`.
- **Settings > Logs toggle (`setting_field_logs`)**:
  - Enables `global.timeline_cfg.score_lane_debug_log` and `global.timeline_cfg.score_lane_debug_file_log`.
  - This is specifically for score-lane diagnostics in `scr_game_viz`, not a global redirect of all `show_debug_message` output.
- **IncludedFiles hygiene (critical for fresh diagnostics):**
  - Do not register mutable runtime outputs under IncludedFiles (`datafiles/debug/*`, `datafiles/performances/**`).
  - Including generated outputs reseeds stale artifacts into each IDE VM run and breaks fresh-run traceability.
- **Score-lane debug file path**:
  - Config key: `global.timeline_cfg.score_lane_debug_file_path`.
  - Default fallback in code: `score_lane_debug.log` (relative to GameMaker `working_directory`).
  - Current workspace example file: `datafiles/debug/score_lane_debug.latest.log`.
- **Event history and performance exports**:
  - Event CSV export writes under `datafiles/` via `event_history_export_csv` and includes split timing columns (`canonical_time_ms`, `audio_target_time_ms`, `visual_target_time_ms`, `input_aligned_time_ms`, plus offset columns).
  - Session/performance artifacts write under `datafiles/performances/`.

Troubleshooting tip: for BPM issues you can use either Output or the score-lane log file (Logs ON). For score/image mapping issues, use the score-lane file log.

---

## Playback preprocessing (note)
- A playback preprocessing / "play array" design exists in `PROJECT_PLAN.md`. That file contains design notes and implementation suggestions for normalizing and optimizing event lists for runtime use.

---

## MIDI & extensions
- `extensions/GiavappsMIDI/` provides MIDI utilities used by playback and input code.
- MIDI device selection is exposed through the settings UI and tracked in global variables (e.g., `global.midi_input_device`, `global.midi_output_device`).

---

## Other systems
- UI components live under `objects/obj_btn_*`, `objects/obj_field_base`, `objects/obj_UI_parent`.
- Main rooms: `rooms/Room_main_menu`, `rooms/Room_play`.

---

## Known issues (current)
- **Path contract reminders:** IDE runs execute from `GMS2TEMP`, but this project now enforces split roots: reads from project content root and writes to `%LOCALAPPDATA%/Silly_Wizard/datafiles/` in IDE mode. For packaged/non-IDE runs, configure the data root override and use category-relative subfolders (`tunes/`, `debug/`, `performances/`, etc.).

---

*Created by GitHub Copilot (Raptor mini (Preview)).*

---

## Notebeam draw architecture

The notebeam canvas is rendered frame-by-frame inside `scr_game_viz.gml` (the main draw function called from `obj_game_viz` Draw event). There are **three distinct note-beam categories**, each drawn separately:

### 1. Planned spans (tune as written)
- Source: `global.timeline_state.planned_spans` (full set, built by `gv_build_planned_spans` at `gv_bind_timeline_on_tune_start`).
- Drawn by: `gv_draw_planned_row()` (row view) and `gv_draw_notebeam_underlay_layers()` (lane view).
- Colour: `planned_bar_color` / `timeline_cfg.planned_bar_color` (default aqua).
- **Dangling tail rule:** unmatched `note_on` events (e.g. transition tune's last note) get a 90 ms synthetic tail — NOT extended to the last event in the set. See `_dangling_tail_ms = 90` in `gv_build_planned_spans`.

### 2. Completed player spans (`player_in`)
- Source: `global.timeline_state.player_in` (committed after note_off) or `review_full_trace` in review mode.
- Drawn by: `gv_render_notebeam_live_player_surface()` (cached; live mode only) or the main per-span loop.
- Colour during live play (non-review, non-overlay): `player_beam_render_color` = `live_player_beam_color` when `review_mode_active`, else `player_beam_color`.
- Colour in review mode with `postplay_overlay_mode==1`: coloured green/red/split by `review_match_state` (pre-classified in `gv_on_tune_playback_finished`).

### 3. Pending (in-progress) player span
- Source: `global.timeline_state.pending_player` — a struct keyed by note key; one entry per currently-held note.
- Drawn by: the `pending_player` loop at end of main draw step (`draw_line_width` directly to canvas).
- Colour: **always `live_player_beam_color`** (the same blue as completed beams) — do NOT change this to `player_beam_render_color`, which is grey during live play.
- `overlay_mode==1` path: uses `gv_player_span_classify_and_draw()` same as completed spans.

### `player_beam_render_color` gotcha
`player_beam_render_color = use_live_blue_beams ? live_player_beam_color : player_beam_color`  
where `use_live_blue_beams = review_mode_active && (postplay_overlay_mode != 1)`.  
This means `player_beam_render_color` is **grey** (`player_beam_color`) during live play. Do not use it for the pending span — use `live_player_beam_color` directly.

### Pre-classification (`review_match_state`)
Computed once in `gv_on_tune_playback_finished` after scoring. Stored on each span in `review_full_trace`. Values: 0=miss, 1=bleed (partial overlap), 2=match. Used by the draw loop to avoid O(N×M) comparison per frame. Only valid when `can_compare_overlap` is true (requires `postplay_overlay_mode==1`).


---

## How To Do X � Integration Patterns Cookbook

Recurring patterns for extending the project. Read the relevant pattern before adding new code.

---

### Pattern 1: Adding a new button

**Use case:** A new clickable button in any UI window/layer.

**Steps:**

1. **Place the instance in RoomUI** (Room UI editor ? target layer ? drag in `obj_btn_main` or another button object). Set these override properties:
   - `button_script_index` � the index in the `button_scripts[]` dispatch array (see step 2).
   - `button_target` � layer name or value passed to the handler (optional; set to `""` if unused).
   - `button_ID` � unique integer in the layer (used for stable pairing; avoids reliance on runtime registration order).

2. **Register the handler** in `scr_button_scripts.gml` ? `scr_handle_button_click()` dispatch array. Add a new `case` for the index you chose, or append a new entry to the `button_scripts` array at initialization.

3. **Write the handler function** in `scr_button_scripts.gml`. Follow the naming convention `scr_<action>()`. Annotate with the full `/// @` template (include `@reads`, `@writes`, and `@callers`).

4. **Update WORKSPACE_MAP.md** � add a row to the `scr_button_scripts` function table.

**Key functions:** `scr_handle_button_click()`, `scr_button_scripts` dispatch table.  
**Key globals:** `global.ui_assets` (registered at runtime by `obj_UI_parent`).

---

### Pattern 2: Adding a new global variable

**Use case:** A new piece of shared runtime state needed by more than one script.

**Rules:**
- Globals are **owned by one script** (the one that initializes them). Document the owner in `@writes`.
- Prefer a **struct field** on an existing global struct (`global.timeline_cfg`, `global.timeline_state`, `global.playback_context`) over a new top-level global wherever the new value is conceptually part of that system.
- Use a **top-level global scalar** only for system-wide flags, caches, or values that belong to no existing struct.
- Never use `ds_map` / `ds_list` � use structs and arrays.

**Steps:**

1. **Choose ownership:** decide which script initializes it (Create event of an object, or a `scr_*_init` / `gv_ensure_*_defaults` function).
2. **Initialize defensively:** use `if (!variable_global_exists("my_var")) global.my_var = <default>` at the top of the owning function, or declare it in the object's Create event.
3. **Check existence before reading** in non-owning scripts: `if (variable_global_exists("my_var") && ...)`.
4. **Annotate:** every function that reads it gets `@reads global.my_var`; every function that writes it gets `@writes global.my_var`.
5. **Add to the Global State Inventory table** in this file.

**Avoid:** writing to globals inside pure-utility or drawing functions � route writes through a dedicated setter or the owning init function.

---

### Pattern 3: Adding a new tune event type

**Use case:** A new kind of event that appears in a tune's event list and needs to trigger behavior during playback.

The pipeline has four stages. Touch all four.

**Stage 1 � Preprocess (`scr_preprocess_tune.gml`)**
- Open `preprocess_tune()` and add a new `case` (or condition) for your event type string.
- Compute any derived fields (e.g., `time_ms`, canonical note name) and store them in the event struct.
- Add a `@reads`/`@writes` annotation update if you touch new globals.

**Stage 2 � Playback callback (`scr_tune_scripts.gml` ? `script_tune_callback()`)**
- Add a new `case` in the callback's event-type dispatch.
- Call the appropriate action: send MIDI via `midi_send_*()`, update a global, call a viz binding function like `gv_on_player_note_on()`.
- Keep the callback fast � defer any heavy work to the post-play or step phases.

**Stage 3 � Event log (`scr_event_log.gml`)**
- If the event should appear in the performance history (for CSV export or review overlay), add it to `event_history_log_entry()` or call `event_history_append()` with an appropriate struct.
- Follow the existing `event_history_entry` shape: `{ time_ms, beat_fraction, event_type, source, note_midi, note_letter, tune_name, is_embellishment }`.

**Stage 4 � Visualization (optional, `scr_game_viz.gml`)**
- If the event needs a visual representation in the notebeam or timeline canvas, add it to `gv_get_planned_events_for_viz()` (filter) and/or `gv_build_planned_spans()` (span conversion).
- For a new overlay element, follow the pattern of `gv_draw_notebeam_emb_group_boxes()` � build a data array at bind time, draw from it each frame.
- Structure-row measure labels in `gv_draw_structure_row()` use `marker_type="bar"` as the authoritative source; `marker_type="beat"` labels are fallback-only when bar markers are unavailable.

---

### Pattern 4: Adding a new UI window or layer

**Use case:** A new modal panel or persistent overlay (e.g., a help screen, a new settings group, a score summary window).

**Steps:**

1. **Create the layer in RoomUI** (Room UI editor ? add layer ? name it `<name>_layer` by convention). Set initial visibility to hidden (`layer_set_visible(layer, false)` or unchecked in editor).

2. **Populate the layer** with the relevant `obj_field_base`, `obj_btn_main`, `obj_btn_winClose`, etc. instances. Set `button_ID` / `field_ID` overrides for stable registration ordering.

3. **Add a close button** (`obj_btn_winClose` with `button_script_index` mapped to `scr_toggle_window_visibility` or a dedicated close handler). The close handler typically calls `layer_set_visible(layer_name, false)`.

4. **Add an open trigger** � usually a new button on an existing layer (see Pattern 1) with `button_target` = `"<name>_layer"` and `button_script_index` mapped to `scr_toggle_window_visibility` (the generic show/hide handler in `scr_button_scripts`).

5. **Register any fields** that need runtime data via `scr_update_fields()`. If the window shows tune or set data, hook into the post-load flow via `scr_button_apply_post_tune_load_ui()` or call `scr_ui_refresh()` from the opener.

6. **Document the layer** in the "Per-layer summaries" section of this file.

**Key functions:** `scr_toggle_window_visibility()`, `scr_ui_refresh()`, `scr_update_fields()`.  
**Key globals:** `global.ui_assets` (all registered UI instances), layer functions `layer_set_visible()`.
