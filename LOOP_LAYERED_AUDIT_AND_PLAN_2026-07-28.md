# Loop Layered Audit and Execution Plan (2026-07-28)

## Scope
- Read-only audit (no runtime logic edits in this step).
- Targeted pipeline: loop selection -> loop generation -> scheduler dispatch -> measure indicator -> score image rendering.
- Reference architecture: three independent layers.

## Required Layer Model
1. Layer 1 - Metrical Timeline
- Time/beat/measure placement and durations.
- Governs scheduling, cursor x placement, image window placement.

2. Layer 2 - Musical Identity
- owner_nav_idx, owner_part, owner_measure.
- Governs inclusion identity, indicator identity, judging identities.

3. Layer 3 - Score-Image Identity
- Fragment identity and playback-to-image mapping.
- Governs which visual snippet is shown for a time window.

## Phase 1 Execution: As-Is Dataflow Map
1. Loop entry and handoff
- [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L3645): start_play chooses base or loop-expanded events, writes playback_events_active, passes start_events to scheduler start.
- [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L1286): loop generator builds selected window, expands passes, emits loop_session fields.

2. Identity annotation and relabeling
- [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L982): ownership annotation computes owner_nav_idx/owner_measure from marker-derived nav windows + fallback label map.
- [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L1099): optional relabel pass mutates measure/part from owner fields.

3. Scheduler consumption
- [scripts/scr_tune_scripts/scr_tune_scripts.gml](scripts/scr_tune_scripts/scr_tune_scripts.gml#L3404): tune_start groups events and anchors playback to absolute start time.
- [scripts/scr_tune_scripts/scr_tune_scripts.gml](scripts/scr_tune_scripts/scr_tune_scripts.gml#L3217): groups by timestamp and ordering metadata.
- [scripts/scr_tune_scripts/scr_tune_scripts.gml](scripts/scr_tune_scripts/scr_tune_scripts.gml#L3550): callback advances loop_session phase and emits current expected timeline time.

4. Loop selection references
- [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L4786): selected refs combine timeline nav table and ownership nav table; emits both nav_idx and owner_nav_idx in refs.

5. Indicator and score rendering consumers
- [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L7579): current planned measure uses loop_session pass normalization and selected_refs windows.
- [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L9650): score lane projection computes visible windows from time and loop cycle.
- [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L62): loop runtime cache constructs measure starts from marker starts and owner fields.

## Phase 2 Execution: Layer Mapping Table
| Module/Function | Key Fields | Intended Layer | Actual Use Today | Mismatch Risk |
|---|---|---|---|---|
| scr_button_loop_build_playback_events | selected_refs.start_ms/end_ms, owner_nav_idx, measure | Timeline + Identity | Time-sliced template with identity filter fallback by measure key | Medium |
| scr_button_apply_event_ownership_metadata | marker_type, beat, measure, owner_* | Identity | Builds identity from timeline-like marker windows | Medium |
| scr_button_canonicalize_event_measure_labels | measure <- owner_measure | Identity | Mutates label fields consumed elsewhere | High |
| tune_group_events_by_timestamp | time, type ordering | Timeline | Correct timeline batching | Low |
| script_tune_callback_batched | group.time, loop_session phase fields | Timeline + Iteration | Correct phase progression by expected timeline ms | Low |
| gv_get_current_planned_measure | loop_session.selected_refs start/end + measure/nav_idx | Identity + Timeline | Uses timeline windows but returns identity label | Medium |
| gv_build_loop_runtime_cache | marker starts, owner_measure, owner_part | Timeline + Identity | Derives measure starts from identity-aware markers | High |
| gv_draw_timeline_canvas_overlay | playhead, measure_starts, score_playback_map/score_measure_map, selected_refs.nav_idx | Timeline + Score-Image + Identity | Mixed fallback chain can cross identity/image namespaces | Critical |
| gv_loop_get_selected_measure_refs | timeline nav_idx + owner_nav_idx + start/end | Identity boundary contract | Correctly carries both namespaces, but downstream must not mix | Medium |

## Phase 3 Execution: Conflation Findings (Evidence-Backed)

1. Critical - Score-image lookup still permits identity/image namespace coupling
- Evidence: [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L10624) to [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L10665).
- What mixes: selected_refs nav identity is used to alter playback/image map lookup index.
- Why this breaks: score-image fragment identity is not guaranteed to be equal to nav identity sequence; internal pickups and partial fragments can misselect images.
- Confidence: High.

2. High - Identity is derived from marker windows that are themselves timeline artifacts
- Evidence: [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L982).
- What mixes: timeline boundary markers determine owner_measure windows; fallback by measure label remains present.
- Why this breaks: internal pickup boundaries with ambiguous marker labels can still produce identity drift if marker windows are not represented as dedicated timeline segments.
- Confidence: High.

3. High - Label mutation can hide source ambiguity instead of isolating layers
- Evidence: [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L1099).
- What mixes: rewrites measure/part labels to owner identity, which can make timeline-vs-identity discrepancies opaque to consumers.
- Why this breaks: consumers that should operate on timeline fragments may lose original timeline labeling context.
- Confidence: Medium-High.

4. High - Loop runtime cache for measure starts remains marker-driven
- Evidence: [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L62), especially marker filtering and measure_start building.
- What mixes: timeline projection cache uses marker-based starts with identity fields rather than explicit metrical segments.
- Why this breaks: borrowed-time/partial measures and pickup fragments are difficult to represent as first-class timeline regions.
- Confidence: High.

5. Medium - Current measure resolver uses identity windows for indicator, but not a dedicated timeline segment model
- Evidence: [scripts/scr_game_viz/scr_game_viz.gml](scripts/scr_game_viz/scr_game_viz.gml#L7579).
- What mixes: pass normalization by time is good, but measure identity is selected directly from refs without a separate timeline segment object for partial/pickup windows.
- Why this breaks: edge windows at support tails/spacers are handled procedurally instead of by explicit timeline objects.
- Confidence: Medium.

6. Medium - Loop selection window fallback can regress to measure-label based slicing
- Evidence: [scripts/scr_button_scripts/scr_button_scripts.gml](scripts/scr_button_scripts/scr_button_scripts.gml#L1286) fallback block resolving start/end from measure keys.
- What mixes: when start/end refs missing, selection can derive from measure labels.
- Why this breaks: raw measure labels are exactly where pickup boundary ambiguity appears.
- Confidence: Medium.

## Phase 4 Execution: Gap Analysis vs Current Proposal Sections

1. Identity rules
- Aligns: owner_nav_idx as primary identity is explicitly present.
- Gaps: identity can still be inferred from marker-derived windows and measure-label fallback.
- Break risk: internal pickup and borrowed-time cases where marker boundaries do not match visual fragments.

2. Inclusion rules
- Aligns: half-open window with closure note_off exists.
- Gaps: fallback inclusion by measure key remains, and no explicit metrical segment layer exists.
- Break risk: time slicing degrades when selected refs are incomplete or label-ambiguous.

3. Pass expansion
- Aligns: template pass plus iteration metadata and pass_manifest implemented.
- Gaps: template itself is not built from explicit timeline segments (partial/pickup objects).
- Break risk: borrowed-time and partial-measure semantics encoded indirectly.

4. Consumer contract
- Aligns: attempts to separate nav_idx and owner_nav_idx in selected refs.
- Gaps: score-image rendering still uses identity-derived remap heuristics in fallback chain.
- Break risk: incorrect pickup fragment image despite correct scheduled audio timing.

## Required Changes to Proposal (Add/Remove/Separate/Rewrite/Preserve)

### Add
1. Explicit metrical timeline layer artifact
- Build timeline_segments[] with fields: part, measure_timeline, beat_start, time_start_ms, time_end_ms, segment_kind (core, pickup, borrowed, partial).

2. Explicit score-image identity artifact
- Build image_fragments[] with fields: fragment_id, time_start_ms, time_end_ms, playback_seq_range, sprite_idx.

3. Explicit cross-layer mapping contracts
- timeline_segment -> musical_owner
- timeline_segment -> score_fragment

### Remove
1. Any rule that implies measure label alone determines timeline placement.
2. Any score-image index lookup keyed directly by owner_measure/measure label.

### Separate
1. Keep loop inclusion identity and loop time slicing as two separate passes:
- Pass A: slice timeline by time window.
- Pass B: identity filter on sliced events.

2. Keep indicator identity and score-image identity separate:
- Indicator reads musical owner fields.
- Score renderer reads score fragment mapping by time.

### Rewrite
1. Replace marker-derived measure_start cache for loop projection with timeline_segments in loop mode.
2. Replace score-image remap fallback chain with fragment-by-time resolution first, identity only as tie-break diagnostic.
3. Replace measure-key fallback for loop window construction with strict selected_refs start/end time contract.

### Preserve
1. Half-open [start,end) + closure note_off rule.
2. Deterministic same-timestamp ordering note_off -> marker -> note_on.
3. Pass expansion and pass_manifest model.
4. Scheduler absolute-time grouping model.

## Revised Loop-Generation Plan (Layered)

### Step 1 - Build timeline segments (Layer 1)
- Input: base planned events and tune timing metadata.
- Output: timeline_segments[] including explicit pickup/borrowed/partial regions.
- Invariant: placement and duration are time-derived only.

### Step 2 - Build owner map (Layer 2)
- Input: timeline_segments and ownership metadata.
- Output: owner_windows[] keyed by owner_nav_idx.
- Invariant: identity labels do not alter segment times.

### Step 3 - Build score fragment map (Layer 3)
- Input: score_playback_map, score lane metadata, snippet durations.
- Output: score_fragments[] with explicit time windows.
- Invariant: fragment selection uses time window first.

### Step 4 - Loop slicing
- Slice timeline_segments by selected loop time window.
- Include events whose event.time is in sliced segments, then identity-filter by owner_nav_idx.
- Keep closure rule for note_off at end.

### Step 5 - Pass expansion
- Expand sliced template into passes.
- Attach iteration metadata after template is fixed.
- Spacer stays metronome-only.

### Step 6 - Consumer routing
- Scheduler and cursor placement: timeline_segments.
- Measure indicator: owner identity layer.
- Score image rendering: score_fragments by time.

## Acceptance Matrix
1. Internal pickup loop
- Expected: no dropped selected measure; pickup events stay in prior-measure timeline but next-measure identity.

2. Borrowed-time measure
- Expected: partial-end and borrowed region both represented and loopable by time.

3. Partial-measure boundary
- Expected: indicator stable, no skipped second-to-last measure, no image jump.

4. Score-image fragment correctness
- Expected: pickup glyph/fragment shown by fragment time window, independent of owner_measure label.

5. Non-loop parity
- Expected: no regressions in unlooped playback timing and image placement.

## Execution Status
- Completed in this step:
  - Phase 1 as-is map
  - Phase 2 layer classification
  - Phase 3 conflation findings
  - Phase 4 proposal gap analysis
  - Revised layered plan and acceptance matrix
- Not executed in this step:
  - Code rewrite phases (approval required before implementation changes).
