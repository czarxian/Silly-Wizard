# Notebeam Visualization System

## Overview
The notebeam visualization renders bagpipe notes as horizontal beams on a scrolling timeline. The system compares **planned notes** (from the tune sheet) against **player input** (what the musician actually plays), painting beams green where they match and red where they don't.

---

## Three Visualization Layers

### 1. **Planned Spans** (Tune Notes)
- Source: `global.timeline_state.planned_spans` array (time-sorted by start time)
- Purpose: Display the intended note sequence from the tune JSON
- Drawing: Beamed in a single color (`planned_beam_color`, typically dark/neutral)
- Two passes:
  - **Pass 0**: Ghost parts (enabled branches, 72% alpha)
  - **Pass 1**: Focus part (player's tuning, full opacity)

### 2. **Player Input Spans** (Completed Notes)
- Source: `global.timeline_state.player_in` array (time-sorted by note-off time)
- Purpose: Show what notes the musician has finished playing
- Drawing: Split into two colors:
  - **Green** (match): Overlaps perfectly with a planned note (within slack)
  - **Red** (miss/bleed): Doesn't match, or partially overlaps

### 3. **Pending Player Note** (In-Progress)
- Source: `global.timeline_state.pending_player` struct (keyed by note pitch)
- Purpose: Show the note currently being played (from note-on to now)
- Drawing: Same green/red logic as completed player notes

---

## State Detection: Match vs Bleed vs Miss

Each player span's state is determined by a single scan of `planned_spans`:

```
Timing State = 0 (MISS)          [red beam]
            = 1 (BLEED)          [red beam, partial overlap]
            = 2 (MATCH)          [green beam, full containment]
```

**Match** (state 2): Player note starts ≥ (planned_start - slack_ms) AND ends ≤ (planned_end + slack_ms)
- Indicates the musician played the right note at roughly the right time
- `player_timing_slack_ms` typically ~50ms to accommodate human timing variance

**Bleed/Miss** (states 0–1): Anything else — overlaps without full containment, or no overlap at all

---

## Split-Beam Rendering (Overlap Details)

When a player note has a planned note to compare against, the beam is **split horizontally** into segments:

- **Red segments**: Time windows where player spans don't overlap any planned note
- **Green segments**: Time windows where player spans do overlap planned notes

This requires collecting all overlapping planned segments, merging contiguous ones, then painting gaps red and overlaps green.

---

## Visibility Culling (On-Screen Focus)

### Viewport Bounds
- Canvas displays ~5 seconds of music (configurable by zoom/scroll)
- Time range: `[t_min, t_max]` in milliseconds
- Pixel range: `[x1, x2]` (canvas left/right edges)

### Four-Level Filtering

**Level 1 — Time Domain (Planned & Player)**
```
if (q_end < t_min) continue;       // Note finished before viewport
if (q_start > t_max) break;        // Note starts after viewport (and all future notes too)
```
Split into `continue`/`break` so time-sorted arrays can exit early.

**Level 2 — Pixel Domain (Planned)**
```
if (px_right < planned_draw_x_min) continue;   // Rendered off-screen left
if (px_left > planned_draw_x_max) break;       // Off-screen right → break (time-sorted)
```

**Level 3 — Minimum Visible Pixel (Planned)**
```
if ((prx - plx) < notebeam_planned_min_visible_px) continue;  // Sub-pixel width, skip
```
Avoids drawing hundreds of tiny stubs for short notes when zoomed out.

**Level 4 — Lane Index**
```
if (lane_idx < 0 || lane_idx >= lane_count) continue;
```
Bagpipe has 9 playable lanes; skip notes outside valid range.

---

## Performance Optimizations (Lag & Jitter Reduction)

### 1. **Early-Exit Breaks** (Time-Sorted Assumption)
- Both `planned_spans` and `player_in` are sorted by start/end time
- Combined time check split into separate `continue` (left-off-screen) and `break` (right-off-screen)
- Saves ~O(n_past) iterations when playhead is mid-tune
- **Benefit**: Planned cost dropped from ~2.8ms → ~1.66ms

### 2. **Combined Classify-and-Draw Function**
- Replaced two separate O(n_planned) scans per player span (one for state, one for segments)
- New `gv_player_span_classify_and_draw()` does both in a single pass
- **Benefit**: Halved per-span inner-loop cost; player cost stable at ~0.001ms idle

### 3. **Binary Search Skip-Ahead** (NEW — just applied)
Three independent binary searches find the first visible entry in sorted arrays:

**a) Planned Draw Loop**
```
Binary search planned_spans for first span where end >= t_min
→ Start iteration from planned_first_i instead of index 0
→ Skip all past-completed planned notes in O(log n) instead of O(n)
```

**b) Player Draw Loop**
```
Binary search player_in for first span where end >= t_min (adjusted for player offset)
→ Start iteration from player_first_j instead of index 0
→ Current bottleneck: player_in grows with every note played
```

**c) Inner Planned Scan (inside classify-and-draw)**
```
Binary search for first planned span overlapping player window
→ Reduces inner scan from index 0 to first-relevant index
→ Compounds with outer break logic
```

**Impact**: Transforms O(n_total) loops into O(log n_total + n_visible):
- For a 5-second viewport in a 5-minute tune: ~50 visible notes out of 300 total
- Planned outer loop: ~8 binary search iterations + ~50 visible spans instead of ~300
- Player loop: ~8 binary search iterations + ~5 visible player notes instead of all 300+ historical notes

### 4. **Min-Visible-Pixel Threshold**
```
if ((prx - plx) < notebeam_planned_min_visible_px) continue;
```
When zoomed out to full-tune view, 300 notes compress to ~30 pixels screen-wide. Skipping sub-pixel stubs saves GPU raster work.

### 5. **Diagnostics (In-Flight Toggle)**
```gml
notebeam_diag_enabled: true/false
notebeam_diag_disable_planned: true/false
notebeam_diag_disable_player: true/false
```
Measure per-component cost in real-time; identify bottlenecks per frame. Disable components to isolate lag sources.

---

## Current Costs (Post-Binary-Search)

From your latest telemetry:
```
avg=1.767ms  planned=1.611ms  player=0.001ms (idle)
```

At rest:
- **Planned**: ~1.6ms (300 spans, search + visible-only iteration)
- **Player**: Near-zero (no input yet)
- **Pending**: Near-zero (no active notes)

Under player input (multiple notes/sec):
- **Planned**: Stays ~1.6–1.8ms (mostly viewport-independent now)
- **Player**: Grows to 0.1–1.2ms (depends on how many player notes have fired)
  - Each player span triggers ONE binary search (~8 ops) + ONE inner scan + ONE draw
  - Binary search cost is negligible; remaining cost is the inner scan's segment-merge + draw

---

## Remaining Growth Path

**Why player cost still climbs with note count:**

`player_in` array **grows unbounded** (all completed notes appended). Even with binary search:
- First N notes: binary search finds early, scans 0 visible → cost ~0
- 50th+ notes: binary search finds past index ~250, scans ~50 visible → cost grows

**Potential future fix** (not yet applied):
- Prune `player_in` periodically (remove notes >10 seconds in the past)
- Or use a ring buffer instead of append-only array
- Would cap player loop at O(log n_total + n_visible) regardless of tune length

---

## Summary Table

| Layer | Source | Color Logic | Visible Focus | Optimization |
|-------|--------|-------------|---------------|--------------|
| **Planned** | tune JSON | Single (dark) | Time + pixel bounds | Binary search + min-pixel skip |
| **Player (done)** | input notes | Green/red splits | Time bounds | Combined classify-and-draw |
| **Player (pending)** | active note | Green/red splits | Time bounds | Early-exit break on future notes |

The system is now **bounded by the visible note count** rather than total tune length, thanks to time-sorted breaks and binary search. Remaining jitter comes from per-note overhead (segment merging, drawing calls) which is linear in visible count.

---

## Next-Scale Architecture (For Sets, Longer Pieces, More Parts)

### Why change again if current performance is good?
Current optimization has made the system much faster, but the planned direction (sets, longer arrangements, more parts/channels) will increase note count and session duration. The current model still performs repeated per-frame filtering over source arrays.

For larger content, a better long-term model is:
- Keep tune data immutable and preprocessed
- Maintain small active windows for drawing
- Bound runtime player history using a ring buffer

This preserves visual behavior while keeping frame cost stable as content grows.

### Core idea
Treat playback as two data streams with different behavior:

1. Planned stream (deterministic)
- Known at load time
- Can be fully precomputed, sorted, and indexed
- Should not be mutated during playback

2. Player stream (unpredictable)
- Arrives live from MIDI input
- Must be handled incrementally at runtime
- Must be bounded (time horizon or fixed capacity)

### Data model to target

#### Planned (immutable, precomputed)
At load/preprocess time, build planned spans with all draw-time metadata already present:
- `start_ms`, `end_ms`
- `channel`, `part_id`
- `lane_idx` (precomputed once)
- optional style flags (ghost/focus eligibility)

Store as sorted arrays by time, optionally per part/channel for future color/layer expansion.

#### Runtime windows (mutable cursors, no copying)
For each active planned stream, maintain cursor/index state:
- `first_visible_idx`
- `last_visible_idx` (or `first_future_idx`)

As playhead moves, advance cursors forward only. Draw only within the active index range.

#### Player history (ring buffer)
Replace unbounded append-only `player_in` with bounded storage:
- Keep notes in a time window, e.g. `[now - past_window_ms, now + margin]`
- Remove/overwrite old entries automatically
- Maintain sorted time order for fast overlap checks

#### Pending notes (live map)
Keep currently-held notes in a small map keyed by note/channel. On note-off, finalize into the player history ring.

### Draw behavior with this model

#### Planned beams
- Draw from active planned window only
- Per-frame work is mostly position mapping + draw calls
- No full-array scanning needed

#### Player beams
- Draw from recent player window only
- Split green/red segments against planned active window
- Use two-pointer overlap within active ranges instead of rescanning from index 0

### Why this is better than rebuilding dedicated draw arrays every step
Dedicated draw arrays are conceptually good, but rebuilding/copying arrays often can add allocation and churn costs.

Using immutable source arrays + moving window indices gives the same visual result with lower memory churn and more predictable frame time.

---

## Implementation Plan (Phased)

### Phase 1 - Data Foundations
Goal: Move expensive per-span lookup work out of the frame loop.

Changes:
1. Extend planned span build/preprocess to include `lane_idx` and any other draw metadata.
2. Ensure planned spans are guaranteed sorted by time and documented as such.
3. Add timeline state fields for window cursors per stream.

Validation:
- Visual output unchanged.
- `planned` time should drop modestly because lane mapping no longer happens every draw.

### Phase 2 - Planned Windowed Rendering
Goal: Stop scanning planned arrays outside visible window.

Changes:
1. Add a window-update function that advances `first_visible_idx`/`last_visible_idx` from playhead.
2. Draw planned beams strictly from `[first_visible_idx, last_visible_idx)`.
3. Keep existing pixel culling/min-visible-px checks as secondary guards.

Validation:
- `planned` cost remains stable as tune length increases.
- No popping at window boundaries.

### Phase 3 - Player Ring Buffer
Goal: Eliminate unbounded growth in player processing cost.

Changes:
1. Replace append-only `player_in` growth with ring buffer or time-pruned queue.
2. Keep only the configurable recent horizon needed for rendering/review.
3. Preserve pending-note flow (note_on -> pending map, note_off -> history ring).

Validation:
- `player` and `pending` costs stop drifting upward during long sessions.
- Visual behavior at the Now line unchanged.

### Phase 4 - Active-Window Overlap Engine
Goal: Reduce split-beam overlap work to active ranges only.

Changes:
1. Use active planned/player windows as overlap input.
2. Implement two-pointer overlap traversal for segment creation.
3. Keep existing match/bleed/miss semantics and timing slack rules.

Validation:
- Green/red split behavior unchanged.
- Lower and more stable overlap classification cost.

### Phase 5 - Set-Level Timeline Support
Goal: Scale to merged sets without giant monolithic per-frame scans.

Changes:
1. Store per-item (per tune) planned data with global time offsets.
2. Maintain active windows across set boundaries.
3. Ensure transitions between tunes are seamless for planned and player overlays.

Validation:
- No visual discontinuity at set transitions.
- Performance remains bounded with longer set duration.

---

## Risks and guardrails

1. Boundary errors at window edges
- Guardrail: keep secondary pixel/time culls and add debug asserts around index bounds.

2. Visual regressions at Now line
- Guardrail: preserve current split-beam logic and test with dense short notes.

3. Sync drift between MIDI timing and draw timing
- Guardrail: keep one authoritative playhead time source and convert all windows from that source.

---

## Suggested order for actual coding
1. Phase 1
2. Phase 2
3. Phase 3
4. Re-profile
5. Phase 4
6. Phase 5

This sequence keeps risk low and lets each phase show measurable performance gains before moving on.

---

## Concrete Implementation Checklist (File/Function Map)

This section maps each phase to the specific scripts and functions already in the project.

### Known integration points

- Planned span build:
  - `scripts/scr_game_viz/scr_game_viz.gml`
  - `gv_build_planned_spans()`
- Timeline bind/start state:
  - `scripts/scr_game_viz/scr_game_viz.gml`
  - `gv_bind_timeline_on_tune_start()`
  - `gv_bind_from_loaded_tune()`
- Main draw loop:
  - `scripts/scr_game_viz/scr_game_viz.gml`
  - `gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2)`
- Player overlap helpers:
  - `gv_player_span_classify_and_draw()`
  - `gv_player_span_timing_state()` (legacy path)
  - `gv_collect_lane_overlap_segments()` (legacy path)
- Tune playback time source callback:
  - `scripts/scr_tune_scripts/scr_tune_scripts.gml`
  - `tune_start()`
  - `script_tune_callback_batched()`
- Preprocess/load entry points:
  - `scripts/scr_preprocess_tune/scr_preprocess_tune.gml` (`scr_preprocess_tune`)
  - `scripts/scr_tune_load/scr_tune_load.gml` (`scr_tune_load_json`)

### Runtime contracts (current)

1. Post-play overlay modes (`timeline_cfg.notebeam_postplay_overlay_mode`):
  - `0 = Raw`
  - `1 = Segmented`
  - `2 = Planned`
  - `3 = History`

2. Coordinate-space contract for click handling:
  - Notebeam and gameviz click handlers use GUI-space mouse coordinates.
  - Tune-structure click handler uses room/screen-space mouse coordinates.

3. Cached anchor render contract:
  - During cached surface draws for notebeam and tune-structure, anchor offsets are set to `-bbox_left/-bbox_top`.
  - Hitboxes are rebased back to global screen space when written, so hit tests remain aligned regardless of local surface coordinates.
  - Anchor surface cache setup/storage is centralized with `gv_anchor_cache_get_or_create()` and `gv_anchor_cache_store()` to keep timeline/notebeam/tune-structure cache behavior consistent.

4. Synthetic measure-nav fallback contract:
  - When measure metadata is unavailable, both bind-time and tune-structure panel bootstrap use `gv_build_synthetic_measure_nav_map()`.
  - This keeps fallback measure counts/part defaults consistent across startup and recovery paths.
  - Shared state wiring uses `gv_measure_nav_apply_to_timeline_state()` and `gv_measure_nav_ensure_state_defaults()` so both code paths keep identical measure-nav state fields.
  - Source event selection/flattening uses `gv_measure_nav_resolve_source_events()` so panel bootstrap follows one canonical fallback chain.
  - Fallback end-time resolution uses `gv_measure_nav_resolve_end_ms_from_events()` and `gv_measure_nav_resolve_end_ms_from_state()` so synthetic-map sizing stays consistent between bind-time and panel bootstrap paths.

5. Popup layering contract:
  - Note popup draws from Draw GUI to remain above world-space notebeam and chanter imagery.

6. Tune-structure rendering contract:
  - Tune-structure panel draws through `tunestructure_canvas_anchor` (anchor path) and no longer uses the legacy fallback panel draw from `obj_game_viz` Draw_0.

---

### Phase 1 checklist - Data foundations

Files:
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
1. In `gv_build_planned_spans()`, add precomputed fields to each span struct:
   - `lane_idx`
   - optional `is_focus_channel_default` / `is_ghost_eligible` (if useful)
2. Ensure spans are sorted by time if not already guaranteed by input ordering.
3. In `gv_bind_timeline_on_tune_start()`, add runtime window state fields for planned streams.
4. Document assumptions near data build: sorted order and immutable planned span intent.

Acceptance:
- No visual change.
- Draw loop can read `ps.lane_idx` directly.

---

### Phase 2 checklist - Planned windowed rendering

Files:
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
1. Add helper function(s):
   - `gv_update_planned_window_indices(...)`
   - optional `gv_find_first_span_end_ge_time(...)` binary search helper
2. In `gv_draw_notebeam_canvas()`, replace broad planned iteration with:
   - update window indices from `playhead_ms`, `t_min`, `t_max`
   - iterate only `[planned_i0, planned_i1)` (or equivalent)
3. Keep current pixel-domain culling/min-visible-px checks as guardrails.

Acceptance:
- No popping artifacts at viewport edges.
- `planned` cost remains stable as content grows.

---

### Phase 3 checklist - Player ring buffer / bounded history

Files:
- `scripts/scr_game_viz/scr_game_viz.gml`
- `scripts/scr_tune_scripts/scr_tune_scripts.gml` (if callback-driven ingestion helpers are needed)
- `scripts/scr_MIDI/scr_MIDI.gml` (only if note ingest path updates are needed)

Tasks:
1. Replace unbounded `global.timeline_state.player_in` growth with bounded storage:
   - ring buffer OR time-pruned queue
2. Add config defaults in `gv_ensure_timeline_cfg_defaults()`:
   - `player_history_window_ms`
   - optional `player_ring_capacity`
3. Ensure pending-note finalize flow writes into bounded history.
4. Keep existing behavior for `pending_player` map.

Acceptance:
- Long sessions do not increase `player` cost indefinitely.
- No loss of near-term review visuals.

---

### Phase 4 checklist - Active-window overlap engine

Files:
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
1. Add overlap traversal based on active window ranges (planned + player).
2. Replace remaining broad overlap scans with two-pointer/range-limited scans.
3. Preserve semantics:
   - timing slack behavior
   - match/bleed/miss counters
   - green/red segment drawing behavior

Acceptance:
- Visual output matches current split-beam behavior.
- Lower overlap compute under dense note sections.

---

### Phase 5 checklist - Set-level timeline support

Files:
- `scripts/scr_tune_scripts/scr_tune_scripts.gml`
- `scripts/scr_button_scripts/scr_button_scripts.gml`
- `scripts/scr_game_viz/scr_game_viz.gml`

Tasks:
1. Introduce per-set-item timing offsets when building merged playback plans.
2. Store planned span collections with item metadata (source tune/part) but unified global timeline time.
3. Update window management to handle cross-item transitions.
4. Verify `gv_bind_from_loaded_tune()` / bind flow supports set context.

Acceptance:
- Seamless visuals across tune boundaries in a set.
- Planned/player windows remain bounded and stable.

---

## Recommended execution slices (small PR-sized steps)

1. Slice A:
- Phase 1 only (`lane_idx` precompute + state fields)

2. Slice B:
- Phase 2 planned window helper + draw loop window iteration

3. Slice C:
- Phase 3 bounded player history (time-pruned queue first)

4. Slice D:
- Phase 4 overlap traversal refinement

5. Slice E:
- Phase 5 set-level offsets and cross-item windows

Each slice should include a before/after diagnostics capture from `[NB_DIAG]` to confirm the expected gain.

---

## Reset Scope (Realtime Engine Timing)

### Updated goal
Keep realtime playback behavior tight and predictable during active play:
- tune planned events send when due
- MIDI-in events are processed and timestamped consistently
- log entries use a single authoritative game-time source
- visuals follow the same playhead clock used for scheduling

### Explicitly out of scope for now
- post-play scoring/comparison analysis quality
- player-vs-planned musical accuracy metrics

### Current status snapshot
1. Notebeam draw path has major culling and windowing optimizations in place.
2. MIDI polling is in Begin Step.
3. Core playback paths now share Begin Step sampled time (`timing_get_engine_now_ms`).
4. MIDI timing diagnostics include clamped delay plus signed skew (`raw_skew_ms`).
5. Remaining work is to quantify end-to-end realtime timing error budget, then optimize largest contributor.

---

## Step 9 - Realtime Timing Budget Instrumentation

Goal: move from component guesses to one measurable timing budget for active playback.

### Budget dimensions to log (same clock domain)
1. Scheduler dispatch error:
  - `planned_due_ms`
  - `planned_sent_ms`
  - `planned_late_ms = planned_sent_ms - planned_due_ms`
2. MIDI input processing error:
  - existing `raw_skew_ms` and clamped processing delay
3. Visual alignment error:
  - playhead used for draw minus current scheduler elapsed time
4. Logging write latency:
  - event-handled time minus event-history write time (if different path)

### Acceptance targets (initial)
- `planned_late_ms` p95 <= 2 ms, p99 <= 4 ms during active playback.
- MIDI processing delay p95 <= 3 ms on stable runs.
- Visual/playhead alignment p95 <= 2 ms.

### Suggested implementation order
1. Add scheduler lateness diagnostics in `script_tune_callback_batched()`.
2. Add visual-playhead delta diagnostic in timeline tick.
3. Keep current MIDI skew logs as-is (already useful).
4. Run A/B captures at current gameplay speed and rendering settings.

---

## Relative Grid vs Absolute Grid (Runtime Event Timeline)

For realtime scheduling/logging, prefer an absolute event grid.

### Absolute grid (recommended runtime source)
- Store and process event due times as absolute milliseconds from tune start.
- Compare all realtime timestamps against the same absolute axis.
- Benefits:
  - easier lateness math (`sent - due`)
  - simpler diagnostics and percentile reporting
  - less cumulative drift from chained delta adds

### Relative grid (keep only as optional derived view)
- Relative event spacing is still useful for compact storage or UI representation.
- Do not use relative intervals as primary realtime scheduler truth.

### Practical policy
1. Runtime scheduler/logging/visual sync use absolute ms.
2. Relative representation may be generated for export or analysis views.
3. If both exist, absolute timestamps are authoritative whenever values disagree.
