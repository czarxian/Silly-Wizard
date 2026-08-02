# Musical Structure <-> Time Structure Unification Review (2026-07-30)

## Scope
This review covers runtime and pipeline behavior across:
- Tune load and preprocess
- Playback scheduling and callback dispatch
- Timeline/nav mapping and loop runtime model
- Score lane mapping and review interactions
- Overlap scoring data flow

Primary objective:
- Preserve millisecond-accurate playback/scoring while making musical structure and time structure fully interoperable.

---

## Executive Summary
The current architecture is close to the right model:
- Time-dispatched playback is already authoritative for runtime correctness.
- The project has added robust ownership metadata and loop session descriptors.
- Many systems now map time back to measure reliably.

The main remaining issue is identity loss between layers:
- Part-aware musical identity is dropped in key transforms.
- Several score/review lookups are still keyed by measure number only.

This creates hidden ambiguity whenever measure numbering repeats across parts, and makes some behavior harder than necessary to reason about.

Recommended direction:
1. Keep time as execution authority.
2. Introduce one canonical timeline index (precomputed, immutable per run).
3. Preserve structure identity fields end-to-end (part/measure/nav/ref key).
4. Route all time<->structure queries through shared mapping APIs.

---

## Confirmed Runtime Model (Today)

### 1) Load and preprocess
- JSON load/validation stores tune metadata + event arrays into `global.tune`.
- Preprocess converts unit-space events into ms-timed playable events.
- Pickup normalization and cut handling are performed before build.

Relevant code:
- `scripts/scr_tune_load/scr_tune_load.gml`
- `scripts/scr_preprocess_tune/scr_preprocess_tune.gml`

### 2) Playback scheduler
- Events are grouped by exact timestamp.
- Stable same-time ordering is enforced as `note_off -> marker -> note_on`.
- Callback dispatch uses expected elapsed ms (plus configured output offset).
- Runtime sidecars capture planned/player records for export/scoring reconstruction.

Relevant code:
- `scripts/scr_tune_scripts/scr_tune_scripts.gml`
- `scripts/scr_event_log/scr_event_log.gml`

### 3) Timeline/nav and loop model
- `timeline_state` holds active planned spans, nav entries, and playback/review state.
- Loop path builds explicit `loop_session` with selected refs and timeline segments.
- Current-measure resolver prioritizes loop session segments in loop runtime.

Relevant code:
- `scripts/scr_game_viz/scr_game_viz.gml`
- `scripts/scr_button_scripts/scr_button_scripts.gml`

### 4) Scoring model
- Active production scoring is overlap-based (`ms_overlap`, `ms_overlap_uncal`).
- Scoring windows are derived from measure-nav entries.
- Player/planned spans are compared in ms space (correct design direction).

Relevant code:
- `scripts/scr_scoring/scr_scoring.gml`

---

## Confirmed Structural Gaps

### Gap A: Part identity is not preserved in preprocess output
In `tune_build_playable_events`, emitted marker/note events include measure/beat but often do not carry part.

Effect:
- Later ownership annotation defaults part to 1 when missing.
- Multi-part tune identity can collapse silently.

Primary files:
- `scripts/scr_preprocess_tune/scr_preprocess_tune.gml`
- `scripts/scr_button_scripts/scr_button_scripts.gml`

### Gap B: Planned span structs do not carry part
`gv_build_planned_spans` preserves measure/beat/channel/lane, but not part.

Effect:
- Time-to-structure remains lossy after span conversion.
- Downstream scoring/review cannot fully disambiguate repeated measure numbers.

Primary file:
- `scripts/scr_game_viz/scr_game_viz.gml`

### Gap C: Score maps are keyed by measure only
`scoring_measure_results_to_map` and related lookup paths use `"<measure>"` keys.

Effect:
- Collisions across parts (same measure number in different parts).
- Wrong style/score resolution in part-repeated structures.

Primary file:
- `scripts/scr_scoring/scr_scoring.gml`

### Gap D: Tile hit test discards part/nav metadata
Draw path stores hitboxes with measure+part+nav_idx, but hit-test result currently returns only measure.

Effect:
- Click routing loses canonical selection identity early.
- Additional logic has to recover identity indirectly.

Primary file:
- `scripts/scr_game_viz/scr_game_viz.gml`

---

## Target Architecture

## Principle 1: Single execution authority
- Playback, audio, and runtime scoring timing stay ms-driven.
- No frame-driven timing for note scheduling decisions.

## Principle 2: Structure identity never dropped
All planned/player-derived records that participate in mapping/scoring/UI must carry:
- `part`
- `measure`
- `nav_idx` where known
- `measure_ref_key` (canonical key)

Recommended canonical key format:
- `part:measure:nav_idx` when nav index is known
- fallback `part:measure` only in explicitly degraded contexts

## Principle 3: Canonical timeline index per run
At bind/start, build one immutable index table consumed by all systems.

Suggested row schema (struct array):
- `row_id` (stable integer)
- `event_id` (source event id if available)
- `time_ms`
- `end_ms` (for spans/windows)
- `event_kind` (`note_on|note_off|marker|span|window`)
- `segment_idx`
- `loop_iteration`
- `phase` (`prelude|pass|spacer|complete`)
- `part`
- `measure`
- `beat`
- `beat_fraction`
- `nav_idx`
- `owner_nav_idx`
- `measure_ref_key`

## Principle 4: Shared mapping API only
All conversions should route through two shared functions:
- `map_time_to_context(_time_ms)` -> `{segment_idx, part, measure, beat, beat_fraction, nav_idx, owner_nav_idx, loop_iteration, phase, measure_ref_key}`
- `map_context_to_window(_measure_ref_key)` -> `{start_ms, end_ms, timeline_start_ms, timeline_end_ms, owner_start_ms, owner_end_ms}`

No subsystem should recompute custom mapping from raw arrays if these are available.

---

## Invariants
1. For every dispatched planned event timestamp, mapping must resolve to exactly one context row (or explicit degraded status).
2. `measure_ref_key` must be stable for the run and identical across:
- structure panel tile
- current-measure highlight
- score-lane fragment lookup
- scoring measure result lookup
3. During spacer phase, mapping returns `measure_ref_key=""` and measure `-1` by contract.
4. Ownership windows remain half-open `[start,end)`.
5. Same-timestamp event ordering remains `note_off -> marker -> note_on`.

---

## Proposed Migration Plan

### Phase A (Low risk): Identity carry-through
- Add `part` to all preprocess-emitted planned events.
- Add `part` + `measure_ref_key` to planned spans.
- Keep legacy behavior untouched otherwise.

### Phase B (Low/Medium): Mapping key dual-write
- Keep measure-only maps for compatibility.
- Add parallel maps keyed by `measure_ref_key`.
- Update lookup callers to prefer key-based map with fallback.

### Phase C (Medium): Hit-test and review selection identity
- Return `part` and `nav_idx` from measure hit tests.
- Store score popup selection by `measure_ref_key` (with temporary measure mirror).

### Phase D (Medium): Canonical mapping helpers
- Introduce `map_time_to_context` and `map_context_to_window`.
- Migrate current-measure resolver, popup selection, and score lookup to these helpers.

### Phase E (Medium/High): Remove degraded measure-only dependencies
- After verification window, remove measure-only internal paths where key path is present.
- Keep minimal fallback for malformed legacy content only.

---

## Validation Matrix

### Core mapping
- Any ms in playback returns deterministic context.
- Repeated measure numbers across parts select correct part-aware tile and score.

### Loop runtime
- Loop pass/spacer phase mapping remains stable.
- End-of-pass boundary still includes cleanup note_off semantics.

### Pickup structures
- Initial/internal pickup tunes preserve consistent mapping and highlight behavior.

### Set mode
- Segment transitions keep correct measure_ref identity and score-map lookups.

### Scoring
- Overlap score parity: no numerical drift from baseline after key migration.

---

## Why this aligns with project principles
- Keeps ms accuracy as the execution/scoring foundation.
- Uses preprocessing/indexing to reduce runtime ambiguity and branching.
- Avoids ds_* usage (structs + arrays only).
- Supports current functionality while creating a stronger base for future judges and analytics.

---

## Recommended immediate implementation slice
Start with Phase A + first half of Phase C:
1. Preserve `part` in preprocess output events.
2. Preserve `part` in planned spans.
3. Return `part` and `nav_idx` in nav hit-test result.

This yields immediate structural correctness with minimal behavioral risk and creates a clean base for map-key migration.
