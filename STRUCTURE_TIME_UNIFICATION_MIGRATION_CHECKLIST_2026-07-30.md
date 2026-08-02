# Structure-Time Unification Migration Checklist (2026-07-30)

This checklist operationalizes the architecture review in:
- `STRUCTURE_TIME_UNIFICATION_REVIEW_2026-07-30.md`

Execution goal:
- Improve structure/time interoperability without regressing ms-accurate playback or overlap scoring.

---

## Phase A - Identity Carry-Through (Do First)

## A1. Preprocess output preserves part
File:
- `scripts/scr_preprocess_tune/scr_preprocess_tune.gml`

Tasks:
- Add `part` to every emitted planned event struct in `tune_build_playable_events`:
  - marker
  - note_on
  - note_off
  - embellishment note_on/note_off (library and fallback paths)
- Ensure sort/group behavior unchanged.

Acceptance:
- Planned events contain `part` for all tune channels.
- No change to event count/timestamps/order for same input.

## A2. Planned spans preserve part and canonical key seed
File:
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
- In `gv_build_planned_spans`, include `part` on output span rows.
- Add `measure_ref_key_seed` as `part:measure` where available.

Acceptance:
- Every planned span with measure>=1 has part>=1 and a non-empty key seed.

## A3. Ownership annotation trusts preserved part
File:
- `scripts/scr_button_scripts/scr_button_scripts.gml`

Tasks:
- Verify `scr_button_apply_event_ownership_metadata` uses event part when present.
- Keep fallback defaulting only for malformed events.

Acceptance:
- Ownership stats show expected part distribution on multi-part tune replay.

---

## Phase B - Key Migration (Dual-Write)

## B1. Canonical measure key helpers
File:
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Add helper to construct canonical keys:
  - preferred `part:measure:nav_idx`
  - fallback `part:measure`
- Add helper to extract measure key from measure-entry / span structs.

Acceptance:
- Helpers are pure and covered by debug assertions in dev logs.

## B2. Score map dual-write
File:
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Extend `scoring_measure_results_to_map` to produce:
  - legacy measure-only map (existing behavior)
  - new key-based map
- Store both under `timeline_state`:
  - `score_measure_maps` (legacy)
  - `score_measure_maps_by_key` (new)

Acceptance:
- Existing UI remains functional.
- New key map is populated for all scored measures.

## B3. Lookup prefers key map with fallback
File:
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Update lookup/read paths (`scoring_get_measure_visual_style`, `scoring_find_measure_result`, popup helpers) to:
  1) query key-based map
  2) fallback to measure-only map

Acceptance:
- Same score values as baseline in single-part tunes.
- Correct disambiguation in repeated-measure multi-part cases.

---

## Phase C - UI Selection Identity

## C1. Hit-test returns full identity
File:
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
- In `gv_measure_nav_hit_test`, include `part` and `nav_idx` in returned measure hit struct.

Acceptance:
- Click handlers receive stable part-aware identity.

## C2. Score popup selection stores canonical key
File:
- `scripts/scr_game_viz/scr_game_viz.gml`
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Add `timeline_state.score_popup_measure_key`.
- Keep `score_popup_measure` as compatibility mirror during migration.
- Update review click path to set both fields.

Acceptance:
- Clicking same visual tile toggles reliably.
- No wrong-measure popup when parts reuse measure numbers.

---

## Phase D - Canonical Mapping API

## D1. Introduce mapper helpers
File:
- `scripts/scr_game_viz/scr_game_viz.gml` (or new dedicated script module)

Tasks:
- Add:
  - `map_time_to_context(_time_ms)`
  - `map_context_to_window(_measure_ref_key)`
- Primary source order:
  1) loop session segments/refs (if active)
  2) measure_nav_entries
  3) structural fallback

Acceptance:
- Resolver parity with existing `gv_get_current_planned_measure` in baseline cases.

## D2. Migrate current-measure and popup resolution
Files:
- `scripts/scr_game_viz/scr_game_viz.gml`
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Route highlight and popup selection through mapper output.
- Keep legacy path behind safety fallback.

Acceptance:
- No regressions in live highlight, review jumps, loop spacer behavior.

---

## Phase E - Cleanup

## E1. Reduce measure-only internals
Files:
- `scripts/scr_game_viz/scr_game_viz.gml`
- `scripts/scr_scoring/scr_scoring.gml`

Tasks:
- Remove now-redundant measure-only assumptions in internal lookups.
- Keep import/export compatibility only where required.

Acceptance:
- All acceptance matrix tests pass; no use of measure-only key in active decision paths.

---

## Cross-Phase Test Plan

## T1. Baseline parity (single tune)
- Same event count and timing distribution before/after Phase A.
- Same overlap score values for tune with no repeated part numbering.

## T2. Repeated measure numbers by part
- Verify tile click, style color, popup scores map to correct part.

## T3. Loop mode
- `jump` on/off, `spacer` on/off, multi-pass iteration.
- Measure highlight and score image remain aligned through boundaries.

## T4. Pickup structures
- Initial pickup and internal pickup samples.
- Confirm context mapping for measure 0 / first full measure transition.

## T5. Set mode
- Segment transitions while playing and in review.
- Confirm score lookup uses active segment + canonical key.

---

## Instrumentation to keep while migrating
- Existing ownership logs (`[OWNERSHIP] base/loop ...`).
- Add temporary `[CTX_MAP]` debug lines for key resolution mismatches.
- Add temporary `[SCORE_KEY]` logs for lookup fallback hits (key miss -> legacy hit).

---

## Rollback Strategy
- Dual-write and fallback strategy keeps user-visible behavior stable.
- Any phase can be paused without data loss because legacy measure-only maps remain until Phase E.

---

## Suggested execution order for next coding session
1. A1 + A2 + C1 (small, high-value correctness)
2. B1 + B2 (write new map paths)
3. B3 + C2 (switch reads to key-first)
4. D1 + D2 (centralized mapper)
5. E1 cleanup after validation window
