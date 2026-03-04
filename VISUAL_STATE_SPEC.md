# Visual State Spec (Single Source of Truth for On-Screen Music Visuals)

## Purpose
Define a **single central runtime structure** that powers all music visuals with minimal latency:
- current note panel text/tokens
- note beams (piano-roll-like)
- crossing-noise effects
- future staff/score rendering

This state is intentionally separate from `EVENT_HISTORY` (analytics/export log), but field names are aligned where practical.

---

## Goals
- One canonical runtime view model for all visual systems
- Event timing with both **start** and **end**
- Cheap incremental writes during callbacks
- Cheap query by time window and/or measure
- Human-readable, array/struct based (no DS maps required)

---

## Non-Goals
- Replacing the event log export pipeline
- Recomputing tune theory in draw events
- Hard-coupling visuals to one specific UI layout

---

## Proposed Root Structure

```gml
global.visual_state = {
  version: 1,
  session_id: 0,

  settings: {
    noise_min_ms: 15,
    core_min_ms: 100,
    marker_symbol: "^"
  },

  timeline: {
    events: [],          // Array<VisualEvent>
    next_id: 1,
    finalized_count: 0
  },

  pending: {
    // key: "source:channel:note_midi"
    notes: {}            // Struct map of PendingNote
  },

  index: {
    by_measure: [],      // Array<Array<event_id>> 1-based measure buckets
    by_time_bin: [],     // Optional: Array<Array<event_id>> for fast time-window queries
    bin_ms: 50
  },

  ui: {
    current_measure: 1,
    refs_bound: false
  }
};
```

---

## Event Model

## `VisualEvent` (Array-of-Struct)
Each timeline entry is one drawable/eventful item.

```gml
{
  id: 123,
  source: "tune_plan" | "tune_played" | "player" | "system",
  kind: "note" | "marker" | "fx",

  start_ms: 3015,
  end_ms: 3150,          // for note/fx; marker can equal start_ms
  duration_ms: 135,

  measure: 1,
  beat: 1,
  beat_frac: 0.5,

  note_midi: 65,
  note_letter: "e",
  channel: 2,

  note_class: "core_melody" | "short_noncore" | "filtered_noise" | "embellishment" | "cut_note" | "planned",

  flags: {
    is_embellishment: false,
    is_cut_note: false,
    is_crossing_noise: false,
    is_filtered: false
  },

  meta: {
    event_id: 23,        // source event id from tune JSON/preprocess when available
    marker_type: "",    // e.g. beat, countin_beat
    tie_group: -1        // optional future field
  }
}
```

## `PendingNote`
Stored between note_on and note_off.

```gml
{
  source: "tune_played" | "player",
  note_midi: 65,
  channel: 2,
  start_ms: 3015,
  measure: 1,
  beat: 1,
  beat_frac: 0.5,
  event_id: 23,
  hint_class: "planned" // optional hint
}
```

---

## Lifecycle

### 1) Session Init
Call once per tune start:
- reset `timeline.events`, `pending.notes`, indexes
- set `session_id += 1`
- copy runtime thresholds into `settings`

### 2) Planned Tune Seed
When preprocessed tune is available:
- write `source="tune_plan"` events
- include markers and note entries with start/end
- set initial classes (`planned`, embellishment/cut flags if known)

### 3) Runtime Played Feed
- `note_on`:
  - write/update `pending.notes[key]`
- `note_off`:
  - compute duration
  - classify (`filtered_noise`, `short_noncore`, `core_melody`)
  - append finalized `VisualEvent`
  - update indexes
  - remove pending entry

### 4) Marker Feed
On beat/countin marker:
- append marker event (`kind="marker"`)
- this preserves strict ordering for display and beam separators

### 5) Query + Draw
Visual systems request subsets by measure or time window and draw from same canonical event rows.

---

## Classification Rules (Current)
1. `duration_ms < noise_min_ms` => `filtered_noise` (`is_crossing_noise=true`, `is_filtered=true`)
2. `noise_min_ms <= duration_ms < core_min_ms` => `short_noncore`
3. `duration_ms >= core_min_ms` => `core_melody`

Planned note-specific labels (`embellishment`, `cut_note`) should come from preprocess/JSON tags, not re-inferred in draw.

---

## Indexing Strategy

### `index.by_measure`
- 1-based array where each slot is array of `event_id`
- fast retrieval for panel/score by local measure

### `index.by_time_bin` (optional but recommended)
- bin size: `bin_ms` (default 50)
- event id inserted for all bins overlapped by `[start_ms, end_ms]`
- fast beam rendering in visible time window

---

## Core Query Helpers (Proposed)

```gml
visual_get_events_by_measure(_measure, _source_filter, _kind_filter)
visual_get_events_in_time_window(_start_ms, _end_ms, _source_filter, _kind_filter)
visual_get_latest_measure()
visual_get_note_density(_measure)
```

All helpers return arrays of `VisualEvent` structs (or ids + lazy lookup).

---

## Relationship to Existing Systems

- **Current note panel**:
  - can be fed by measure-filtered `VisualEvent` rows
  - token classes map directly to panel colors
- **Beams**:
  - uses start/end/channel/note_midi/class for lane + color + width
- **Crossing-noise FX**:
  - trigger from `filtered_noise` entries
- **Staff view**:
  - uses measure/beat/time + note_letter + class tags
- **Event log**:
  - stays separate (analysis/export)
  - optional cross-reference by `meta.event_id`

---

## Migration Plan (Safe)
1. Add `visual_state` in parallel with existing `current_note_panel`
2. Write adapters from existing callbacks into `visual_state`
3. Build read-only query helpers
4. Move one renderer at a time (panel first, then beams, then staff)
5. Remove duplicated classification paths once parity confirmed

---

## Minimal First Implementation Scope
- root init/reset functions
- note_on/note_off pending + finalize
- marker append
- by-measure index
- simple time-window query (linear fallback; bins optional phase 2)
- markdown docs/examples (this file)

---

## Example: Boundary Tie Ordering
At same timestamp, process in this order:
1. note_off
2. marker
3. note_on

This keeps end-of-beat notes visually before separator markers when times are equal.

---

## Worked Example (One Measure)

This example shows measure 1 with:
- one planned note,
- one played note finalized from note_on/note_off,
- one beat marker at the same timestamp as a note boundary.

### Step A: Planned Seed (`source="tune_plan"`)

```gml
// Added during visual seed from preprocessed tune
{
  id: 1,
  source: "tune_plan",
  kind: "note",
  start_ms: 2400,
  end_ms: 2860,
  duration_ms: 460,
  measure: 1,
  beat: 1,
  beat_frac: 0,
  note_midi: 63,
  note_letter: "d",
  channel: 2,
  note_class: "planned",
  flags: { is_embellishment: false, is_cut_note: false, is_crossing_noise: false, is_filtered: false },
  meta: { event_id: 2, marker_type: "", tie_group: -1 }
}
```

### Step B: Runtime note_on (`source="tune_played"`)

```gml
// Pending only, not yet in timeline.events
pending.notes[$ "tune_played:2:63"] = {
  source: "tune_played",
  note_midi: 63,
  channel: 2,
  start_ms: 2490,
  measure: 1,
  beat: 1,
  beat_frac: 0,
  event_id: 2,
  hint_class: "planned"
};
```

### Step C: Runtime note_off finalize

```gml
// note_off arrives at 2531 -> duration 41ms
// with noise_min_ms=15 and core_min_ms=100 => short_noncore
{
  id: 2,
  source: "tune_played",
  kind: "note",
  start_ms: 2490,
  end_ms: 2531,
  duration_ms: 41,
  measure: 1,
  beat: 1,
  beat_frac: 0,
  note_midi: 63,
  note_letter: "d",
  channel: 2,
  note_class: "short_noncore",
  flags: { is_embellishment: false, is_cut_note: false, is_crossing_noise: false, is_filtered: false },
  meta: { event_id: 2, marker_type: "", tie_group: -1 }
}
```

### Step D: Same-time marker at boundary

```gml
// marker at 3015
{
  id: 3,
  source: "system",
  kind: "marker",
  start_ms: 3015,
  end_ms: 3015,
  duration_ms: 0,
  measure: 1,
  beat: 1,
  beat_frac: 0.5,
  note_midi: 0,
  note_letter: "",
  channel: 0,
  note_class: "planned",
  flags: { is_embellishment: false, is_cut_note: false, is_crossing_noise: false, is_filtered: false },
  meta: { event_id: 0, marker_type: "beat", tie_group: -1 }
}
```

### Step E: Index Updates

```gml
index.by_measure[1] = [1, 2, 3];

// if bin_ms = 50:
// id=2 (2490-2531) occupies bins 49..50
// id=3 (3015) occupies bin 60
index.by_time_bin[49] -> [2]
index.by_time_bin[50] -> [2]
index.by_time_bin[60] -> [3]
```

### Step F: Query Examples

```gml
// Measure render pass
var m1 = visual_get_events_by_measure(1, "all", "all");

// Beam draw window
var visible = visual_get_events_in_time_window(2400, 3200, "all", "note");

// Crossing-noise FX in window
var fx_src = visual_get_events_in_time_window(2400, 3200, "all", "note");
// then filter note_class == "filtered_noise"
```

This concrete flow is the same pattern for player notes, planned notes, and marker-driven separators.

---

## Why Arrays + Structs (No DS Maps)
- consistent with current code style
- easy debugging via output and JSON-like inspection
- lower cognitive overhead for future contributors
- fast enough for expected event volumes in this project

---

## Open Design Questions
1. Keep `beat_frac` as float or switch to rational numerator/denominator?
2. Should `source="tune_plan"` include synthetic `end_ms` from adjacent note starts when explicit durations are absent?
3. Should `note_class` be recomputed when thresholds change, or kept immutable per session?
4. Should crossings create dedicated `kind="fx"` events or derive effects from note-class at render time?

---

## Glossary
- **core melody**: note that is not filtered crossing noise and meets core threshold; planned-side excludes embellishment/cut by tags.
- **short_noncore**: retained note between noise and core thresholds.
- **filtered_noise**: note below noise threshold, used for markers/effects.
- **pending note**: note_on captured before note_off finalizes duration/class.
