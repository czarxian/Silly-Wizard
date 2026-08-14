# Tune Pipeline Contract

**Status:** Authoritative design contract. Written 2026-08-14.
**Supersedes:** the implicit contract of the Excel VBA pipeline (`EXCEL_VBA_MAP.md`) and the ad-hoc
structure reconstruction described in `STRUCTURE_TIME_UNIFICATION_REVIEW_2026-07-30.md`.

This document defines *what the pieces are and how they relate*. It does not define
implementation order — see `PROJECT_PLAN.md` for phases.

---

## 1. The metaphor

> **ABC plus rules produce layers. Every layer is pinned to the same musical grid.
> Playing a tune is projecting that stack onto a clock.**

Think of old paper maps: a base sheet with transparent overlays laid on top. The overlays are
only useful because they all register to the same coordinate grid. Ours is musical position.

Two kinds of thing exist:

- **Layers** — registered data. Everything in a layer is addressable by a grid reference.
- **Rules** — the legend. Rules produce or transform layers. **Rules never rewrite the source.**

The ABC source is the survey notes. It is read-only. Any transformation produces a layer.

---

## 2. Coordinates

**Musical position is the coordinate system. Milliseconds are a projection, not a coordinate.**

Re-projecting (changing tempo, applying a timing map) changes ms and changes nothing else.
This is the single most important rule in the document.

### 2.1 Grid references (UIDs)

UIDs are **derived from musical position, never from iteration order**. A sequential row counter
(today's `RenumberEventIds`) is forbidden: inserting a note in bar 3 would silently re-key every
annotation, timing-map entry and stored score in the tune.

| Reference | Format | Notes |
|---|---|---|
| `tune_uid` | folder-name slug | Stable tune identity |
| `part_id` | ABC part label (`A`, `B`, …) or ordinal if unlabelled | |
| `measure_uid` | `m:<part_id>:<expanded_index>` | `expanded_index` is 1-based over the **repeat-expanded** measure sequence of the whole tune |
| `beat_uid` | `<measure_uid>:b<beat_index>` | `beat_index` 1-based within the measure |
| `event_uid` | `<voice>:<measure_uid>:b<beat_index>:d<units_from_beat_start>:<ordinal>` | `ordinal` disambiguates simultaneous events (chords, unisons); 1-based |

`units_from_beat_start` is an **integer in tune units**, never a float. Exact equality comparisons
must always work; fractional beats are forbidden in UIDs.

Scope of a source edit: editing a measure re-keys only that measure's events. Editing measure
*counts* (adding/removing bars or repeats) re-keys everything after it — this is unavoidable and
is why `tune_compile` reports a re-key diff (see §9).

### 2.1.1 Ornament components

A grid reference addresses a **musical position**, and one position commonly carries many sounded
notes. "Measure 17, beat 1 is a heavy throw to D" is one musical statement; playing it produces
several notes, one of which is a `c` that must sound fourth.

**Terminology.** Two distinct things, deliberately named apart:

- **Host note** — the melody (or principal) note the ornament decorates. In `{GdGc}D`, the host is
  the `D`. The host owns the grid reference.
- **Anchor** — the note that actually lands *on the beat*. This may be a component of the ornament
  or the host itself. A single `anchor` field also determines which note is the host. See §2.1.2.

Ornament components are **not** separate grid positions. Grace notes have no unit position of
their own — they steal time from the neighbouring notes, and how many there are and how long they
last depends on the variant, grace ms and tempo, none of which are known at compile time. So
components are addressed **relative to their host**:

```
<host_event_uid>/<side>:e<component_index>            // side = lead | trail; index 1-based, played order

pipes_melody:m:A:17:b1:d0:1                           // the host note D — one compiled event
pipes_melody:m:A:17:b1:d0:1/lead:e4                   // the c, fourth thing played in the throw
```

`side` is **derived from `anchor`**, not stored separately: `trail` when `anchor = "trail"`,
otherwise `lead`. It appears in the address so that a host carrying both a leading and a trailing
ornament keeps them in separate numbering spaces — adding one never renumbers the other, and
annotations survive.

Consequences:

- The host's own UID never changes because an ornament precedes or follows it, or because the
  anchor moves. The D is still at `b1:d0` even when the ornament delays when it actually sounds —
  the UID is a grid reference, not a time. This is §2 restated.
- Changing grace duration, tempo or anchor re-keys nothing. Changing the *variant* re-keys only
  the components under that one host and side.
- An annotation (§9.1) can target the host — "judge this throw" — or a single component.

Note the division of labour: `ordinal` in the base UID disambiguates **simultaneous** events
(chords, unisons, voices landing together), while `/<side>:eN` disambiguates **sequential**
components of one ornament. Different problems, different mechanisms.

### 2.1.2 Anchor — what lands on the beat, and which note is the host

`anchor` is a **single field** with three forms. It determines both where the beat falls and which
note the ornament belongs to.

| `anchor` | Host is | On the beat | Ornament sits | Steals from |
|---|---|---|---|---|
| `1..N` | the **following** note | component *N* | straddling the beat | preceding note (components before *N*) + host (component *N* onward) |
| `"lead"` | the **following** note | the host | entirely before the beat | preceding note |
| `"trail"` | the **preceding** note | the host | entirely after the beat | host's tail |

For `{GdGc}D`, the same written ornament played three ways:

- `anchor: 1` — the first `G` lands on the beat; the whole ornament sits inside the D's time.
  The common pipe band interpretation, and what current library data uses.
- `anchor: 4` — the `c` lands on the beat; `G d G` steal from the preceding note.
- `anchor: "lead"` — the `D` lands on the beat; the entire ornament precedes it.

This replaces the current overloaded numeric encoding, where a negative `anchor_index` meant "all
steal from target" and a value `>= count` meant "all steal from preceding". It also replaces the
need for a separate placement field.

**Why `anchor` decides the host.** Standard ABC writes grace notes *before* a note, so a trailing
ornament is physically written ahead of the **next** melody note even though it musically decorates
the **previous** one. `anchor: "trail"` is what tells the parser to bind backwards. Without it, a
naive forward scan for "the next note" attaches the ornament to the wrong host — which is exactly
what `FindTargetNote` and the lookahead loop in `tune_build_playable_events` do today.

**Where anchor comes from.** ABC has no notation for any of this. `anchor` is declared by the
embellishment library record (per pattern + variant), with the per-event override (`alt_anchor`)
retained as the exception hatch. This is a known **notational** gap, not a data-model gap — the
model expresses all three cases; the ABC cannot.

A `"trail"` ornament with no preceding note in the same voice (start of tune, start of a part
after a cut) is a diagnostic warning, and falls back to `"lead"` on the following note.

**When components exist.** Compiled files (L2) store the *attachment*, not the components. An
ornament is a single opaque marker on one host event until `run_build` stage 6, which is where
components — and their UIDs — are generated. Therefore:

- Compile-time consumers (structure panel, score images, library index) see one event carrying
  `has_ornament` and its sides. They never enumerate components and never need to.
- Run-time consumers (scheduler, notebeam, scoring, MIDI) see the expanded components.

Nothing upstream of stage 6 may iterate ornament components, because the component count is not
known until the variant is resolved.

### 2.2 Run-space references

Set segments and loop iterations exist only at run time and are **never stored** in a tune file:

```
run_ref = <segment_index>#<iteration>#<event_uid>
```

`measure_ref_key` from the earlier structure-time work maps onto this as
`<segment_index>#<iteration>#<measure_uid>`.

---

## 3. Layers

| # | Layer | Map analogue | Contents | Built by |
|---|---|---|---|---|
| L0 | **Structure** | Base sheet | Parts, expanded measures, canonical numbers, labels, repeats, pickup/beat budget, voices present, per-measure ABC | Parser rules |
| L1 | **Beat grid** | Graticule | Nominal beat positions in units; resolved per-beat pulse weights | Parser rules + meter; weights from pulse profile at run time |
| L2 | **Events** | Map features | Notes per voice, in unit space, with embellishment *attachments* (unexpanded) | Parser rules |
| L3 | **Timing** | Terrain relief | Expressive per-beat base + sparse per-event ms deltas | Authored or captured |
| L4 | **Annotations** | Pins and margin notes | Judging criteria, practice markers, anything pinned to a grid reference | Authoring UI |
| L5 | **Performance** | Route traced after the walk | What the player actually played | Runtime capture |

Notes:

- **L2 is multi-voice.** `pipes_melody`, `pipes_harmony1..3`, `drums`, and future backing
  instruments are separate event streams sharing L0 and L1. Voice awareness is not optional and
  not deferrable.
- **L4 is a layer, not metadata.** Judging criteria are annotations pinned to grid references,
  so they inherit UID stability, set composition, loop handling and provenance for free.
  See §9.1 for the envelope.
- **L5 is a layer, and it shares L2's record shape.** A captured performance event carries the same
  fields as a planned one (grid reference, time, duration, voice) so visualisation, scoring and
  export code can treat planned and played uniformly, and so timing-map capture can consume L5
  directly. Scoring is "compare two registered sheets", not a separate subsystem.

---

## 4. Rules

| Rule set | Produces / transforms | Scoped by | Storage |
|---|---|---|---|
| **Parser rules** | L0, L1, L2 from ABC source | global | code |
| **Rhythm rules** | `note_pointing`: transforms L2 durations (unit space)<br>`beat_pulse`: per-beat weights applied to L1 during ms projection | tune type + meter → tune → player | `datafiles/config/rhythm_rules.json` |
| **Embellishment library** | expands attachments in L2 into events | pattern + host note + **voice** + variant; each record declares **`anchor`** | `datafiles/embellishments.json` |
| **Timing rules** | projects the grid onto ms | player → tune → set segment | player prefs + tune meta |

Constraints:

1. **Rules never rewrite the source.** Rhythm rules do not modify parsing — they transform the
   Events layer after it exists. The ABC remains a faithful, renderable score at all times.
2. **The embellishment library is keyed by voice.** A drum flam and a pipe doubling are different
   rulebooks sharing one mechanism. Lookup key is `pattern + host_note + voice + variant`.
3. **`anchor` is declared, not inferred.** One field per library record (§2.1.2) fixes both which
   note is the host and what lands on the beat. ABC can express neither. The parser must never
   bind an ornament by blindly scanning forward for the next note.
4. **Rules are resolvable to a chain and the chain is recorded.** Every applied rule contributes
   to the run's provenance (§8), so a stored score can be interpreted later.

### 4.1 Pulse profiles

Pulse is represented as **per-beat weight multipliers**, selected by a **named profile keyed on
tune type + time signature** — not hand-authored per tune. Example, a 4/4 march pulsing 1 and 3:

```
{ profile_id: "march_4_4_pulse_1_3", meter: "4/4", weights: [1.05, 0.95, 1.05, 0.95] }
```

Several profiles may exist for the same meter (`march_4_4_pulse_1`, `march_4_4_pulse_1_3`,
`pointed_reel_2_2`, …); the tune type selects one and the player may override it.

**Weights must normalise to the beat count** (`1.05+0.95+1.05+0.95 = 4.0`). Pulse redistributes
time *within* a measure; it never changes measure duration. Without this, pulsing would drift
tempo and break loops, set timing and metronome alignment.

Pulse therefore applies during **ms projection**, not in unit space — it moves beats in time while
leaving the unit grid untouched (§10, `run_build` stage 4).

### 4.2 Agreed initial simplifications

These reduce scope without constraining the schema:

- Rhythm rules: **tune-type default + per-tune override only.** No à-la-carte, no per-measure.
- Timing rules: **BPM, gracenote duration, and the existing BPM-scaling curve only.**
- Embellishment variants: **per-tune variant set only** (`embellishment_variant_set` in tune meta).
  Per-event `alt_anchor` / `alt_timing` remain the exception hatch.

---

## 5. Sets are the route, not a layer

A set is an ordered traverse across multiple tune sheets, with cuts and transitions at the joins.
It sits **above** the layer stack and is composed at run time:

```
performance = [ segment{ tune_ref, cuts, repeats, transition_ref, settings_override } ]
```

Set composition never mutates a tune file. It concatenates compiled tunes and resolves boundaries.

---

## 6. The compile / run boundary

Two functions, one boundary rule:

```
tune_compile(abc_text, tune_config)      -> compiled_tune   // pure, cacheable, stored
run_build(compiled_tune[], run_config)   -> run_events      // per play, never stored
```

> **Boundary rule: anything a player can change without re-authoring belongs to `run_build`.
> Anything derived purely from the ABC belongs to `tune_compile`.**

| Concern | Side | Why |
|---|---|---|
| Structure layer (L0) | compile | Pure function of ABC |
| Beat grid **in units** (L1) | compile | Pure function of ABC + meter |
| Beat grid **in ms** | run | Depends on BPM |
| Events in unit space (L2) | compile | Pure function of ABC |
| Embellishment *attachments* | compile | The ABC says an ornament is there |
| Embellishment *expansion* | run | Needs grace ms, which is player- and tempo-dependent |
| Rhythm rule application | run | Player/tune configurable — but operates in **unit space** |
| ms projection | run | Tempo |
| Timing map application (L3) | run | Player configurable |
| Annotations (L4) | compile (stored) | Authored against the ABC |
| Head/tail cuts, count-in, metronome | run | Session settings |
| Set concatenation, loop expansion | run | Session structure |
| MIDI channel assignment | run | Device/config dependent |

Note that `run_build` has **unit-space stages before its ms stages**. Order matters — see §10.

---

## 7. Artifacts on disk

Per tune, in `datafiles/tunes/<Tune>/`:

| File | Role | Authority |
|---|---|---|
| `<Tune>.abc` | Source | **Source of truth** |
| `<Tune>.meta.json` | What ABC cannot hold: variant set, rhythm-rule override, annotations (L4), judging config | **Source of truth** |
| `<Tune>.compiled.json` | Compiled layers L0–L2 + provenance | **Cache** — safe to delete, rebuilt on hash mismatch |
| `score/` + `*.score_snippets.json` | Rendered notation images | Derived, out of critical path |

A tune is a **folder of files**, not a single file. That is accepted: grouping by folder keeps
related artifacts together and each file has a single clear owner and authority.

`datafiles/tunes/tune_library.json` is a **pure index** — derived, rebuildable, and containing only
what the picker needs. Adding sort/filter features touches only the index, never the pipeline.

Index fields: `tune_uid`, `title`, `composer`, `rhythm_type`, `meter`, `parts`, `measures_total`,
`voices[]`, `has_pickup`, `tags[]`, `last_played`, `best_score`, `compiled_ok`, `diagnostic_counts`.

Because the index is generated from compile output, new filterable fields appear for free.

---

## 8. Provenance

Every derived artifact carries provenance. Without it, caches cannot be safely invalidated and
stored scores cannot be interpreted.

```
provenance = {
  schema_version,      // this contract's version
  compiler_version,    // parser/stage-registry version
  abc_sha,             // sha1_string_utf8 of the ABC source
  config_sha,          // sha1 of the resolved tune_config
  compiled_at
}
```

Run records additionally carry the **resolved rule chain**: rhythm rule ids, embellishment variant
set, grace ms, BPM, timing map id + source. A score without this is not comparable across sessions.

---

## 9. Diagnostics

The compiler returns diagnostics as data. It **never** halts on a message box and never aborts on
an unknown embellishment.

```
diagnostic = { severity, code, line, col, token, message, measure_uid, event_uid }
```

- `error` — no usable layers produced.
- `warning` — usable output with a documented fallback (e.g. unknown embellishment → literal
  expansion, plus an entry in the per-tune "missing embellishments" report).
- `info` — including the **re-key diff** when a recompile changes existing UIDs, so annotations
  and timing maps that no longer resolve can be reported rather than silently lost.

Early phases surface diagnostics via `show_debug_message` and a log file. A diagnostics panel is
deferred to the authoring UI phase.

### 9.1 Annotation envelope (L4)

Defined now so later work needs no schema change; the criteria library itself is deferred.

```
annotation = {
  annotation_id,
  target,          // { measure_uid } | { beat_uid } | { event_uid }
  kind,            // "judging_criterion" | "practice_marker" | ...
  criterion_id,    // resolved against a criteria library (future)
  judge_ref,       // which judge applies it; empty = general
  params,          // struct, criterion-specific (e.g. { pre_ms: 100, post_ms: 100 })
  note             // human text
}
```

---

## 10. Stage registry and ordering

`tune_compile` and `run_build` are each an **ordered list of stages**. A deferred feature is a
no-op stage. This is what makes §4.2's simplifications and the timing map free to defer.

### tune_compile
1. `parse_abc` — tokenise, validate, diagnostics
2. `expand_repeats` — flatten to expanded measure sequence
3. `build_structure` — L0, incl. pickup beat budget and voice inventory
4. `build_beat_grid` — L1 in units
5. `build_events` — L2 per voice, unit space, embellishment attachments
6. `attach_annotations` — L4 from `<Tune>.meta.json`, with re-key reporting
7. `stamp_provenance` + `validate`

### run_build
1. `resolve_config` — rule chain: defaults → tune → player → set segment
2. `apply_rhythm_rules` — **unit space**
3. `compose_performance` — set segments, cuts, repeats, loop expansion
4. `project_to_ms` — beat grid and events gain ms; **beat pulse weights applied here** (§4.1)
5. `apply_timing_map` — L3 warp *(deferrable no-op)*
6. `resolve_embellishments` — expand attachments relative to the final host ms and declared anchor
7. `assign_channels` + `emit_run_events`

**Ordering rationale — three decisions that must not be reordered:**

1. **Rhythm rules before ms.** Pointing/swing is a notational redistribution of duration within a
   beat. Doing it in unit space keeps the beat grid intact.
2. **Timing map after ms, before embellishments.** The timing map is expressive (a beat lands late);
   it must not stretch grace notes, which are near-constant ms under rubato.
3. **Embellishments last, anchored.** Attachments resolve against the *final* host time.
   This replaces today's interleaved expansion and its backward mutation of an already-emitted
   `note_off` in `tune_build_playable_events`.

---

## 11. Scoring semantics

**The player is scored against the warped (expressive) timeline** — the goal is to imitate the
intended musical style, not a metronomic grid.

Consequences, all binding:

1. **Tolerance windows are expressed in beat fractions, not absolute ms.** They then scale with
   tempo automatically and move with the grid when pulsing shifts beat positions.
2. **Stored scores record the run's rule provenance** (§8). Otherwise a score from before a pulse
   change is not comparable with one after.
3. **Deviation is measured against both the nominal grid and the warped grid**, so "the player
   rushed" can be distinguished from "the beat map moved". Cheap while both exist; impossible to
   reconstruct later.
4. Most rules barely move the grid — rhythm rules redistribute *within* a beat. **Pulsing and the
   beat map are the exceptions**, and are the reason for (3).

---

## 12. Invariants

1. Milliseconds are never a coordinate. No layer is keyed by time.
2. UIDs derive from musical position only; never from iteration or row order.
3. The ABC source is read-only. Rules produce layers; they never rewrite the source.
4. `tune_compile` is pure: same ABC + same tune_config ⇒ byte-identical compiled output.
5. `<Tune>.compiled.json` is a cache. Deleting it is always safe.
6. Every planned event maps to exactly one grid reference, or reports an explicit degraded status.
7. Ownership windows are half-open `[start, end)`.
8. Same-timestamp run event ordering is `note_off → marker → note_on`.
9. During set spacer phases, mapping returns an explicit empty reference, not measure 0.
10. Diagnostics are data. No modal failure paths.
11. No GameMaker `ds_*` structures — structs and arrays only (project-wide constraint).
12. Pulse weights normalise to the beat count; pulse never changes measure duration.
13. **No `tune_compile` or `run_build` work occurs during active playback.** Compilation happens at
    load; run building happens on Play, before the scheduler starts. Neither is in the frame loop.
14. Ornament components do not exist before `run_build` stage 6. No compile-time consumer iterates
    them.

---

## 13. Deliberately deferred

Deferring these costs nothing provided §2, §6 and §10 are honoured.

| Item | Deferred because |
|---|---|
| Timing map (L3) authoring and capture | Stage 5 of `run_build` is a no-op until needed |
| Judging criteria library | Envelope defined in §9.1; contents are later work |
| Score image rendering strategy (PNG vs sprite notation) | Off the critical path; drawing is currently disabled. L0 must retain ABC beam-grouping to keep sprite notation possible |
| Tune authoring UI, diagnostics panel, library sort/filter | Index (§7) decouples these from the pipeline |
| Per-measure and à-la-carte rhythm rules | §4.2 |
| Porting Excel `modTuneLoader` offline analysis | Not on the runtime path |

---

## 14. Resolved decisions

The questions raised on 2026-08-14 are settled as follows and folded into the sections above.

1. **Pulse** — per-beat weight multipliers, selected by a named profile keyed on tune type + meter,
   normalised to beat count, applied during ms projection. See §4.1.
2. **`<Tune>.meta.json`** — kept as a separate file. A tune is a folder of files. See §7.
3. **Compiled cache** — stored beside the source as `<Tune>.compiled.json`. Nothing compiles during
   playback; see invariant 13.
4. **L5 Performance** — persisted in the same record shape as L2 planned events. See §3.

### Remaining open items

- Judging criteria library contents (envelope fixed in §9.1).
- Score image rendering strategy: PNG pipeline vs sprite-based notation (§13).
- Whether player-specific rhythm/timing settings ever need precompilation. Current answer: no —
  a game instance has one primary player, and keeping these at run time lets a setting change be
  heard immediately without recompiling.
- **Notational gaps in ABC** (§2.1.2): ABC cannot express which ornament component lands on the
  beat, nor that an ornament decorates the preceding note rather than the following one. Both are
  carried by the library's `anchor` field. If a tune ever needs two different anchors for the same
  pattern, that is what the per-event `alt_anchor` override is for; if it becomes common, the ABC
  will need an extension.
