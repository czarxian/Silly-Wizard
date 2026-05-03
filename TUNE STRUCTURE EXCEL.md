Excel Tune Structure Specification

This document captures the complete metadata and event-grid structure used for tune definition in the Silly Wizard project. It consolidates the 48-row metadata block, the 23-column event structure, and the embellishment library into a single authoritative reference.

**Architecture Note**: This document reflects a pattern-based embellishment system (Model B) where ABC sequences remain literal in Excel, and GameMaker performs intelligent pattern matching to identify embellishment types, apply timing, and handle variants.

For transition-tune authoring rules (cut metadata, set ordering, ABC phrase patterns, and validation), see `TRANSITION_TUNE_TEMPLATE.md`.

1. Metadata Block (Rows 1–48)

Metadata is organized by category. Each row contains:

Category

Variable

Value

ABC Code (if applicable)

Required (1 = required, 0 = optional)

1.1 Tune Metadata

reference number (X)

title (T)

composer (C)

rhythm (R)

tempo_default (Q)

tempo_min

tempo_max

parts (P)

measures_per_part

measures_total

unit_note_length (L)

base_note_decimal

default_unit_ms

key (K)

meter (M)

time_sig_num

time_sig_den

abc_source

1.2 Metronome Metadata (legacy block)

enabled

beats_per_bar

subdivision

accent_note

accent2_note

normal_note

click_duration_ms

channel

velocity

Note: These rows are currently exported/loaded but not consumed by runtime metronome logic. Transition metadata now uses the dedicated Transition category rows described below.

1.3 Performance Metadata

channel

group (G)

part

swing

humanize_ms

structure

ornaments

instrument_midi_note_base

1.4 Info Metadata

area (A)

book (B)

discography (D)

file name (F)

history (H)

information (I)

notes (N)

origin (O)

source (S)

words (W)

transcription note (Z)

user defined (U)

1.5 Parts Table (Columns G-K, rows 2-25)

The parts table sits alongside the metadata block in the same rows. Each used row defines one voice part for the parser to process.

| Column | Field | Purpose |
|---|---|---|
| G | Type | Part role: `metadata` (ABC header block), `melody`, `harmony1`, `harmony2`, etc. |
| H | Voice | Instrument label: `pipes_melody`, `pipes_harmony1`, etc. |
| I | ABC | Main part ABC (for transition tunes this is the bridge segment) |
| J | Tail Add | Optional transition-tail replacement ABC (borrowed from prior tune context) |
| K | Head Add | Optional transition-head replacement ABC (borrowed from following tune context) |

Rules:
- The row with Type=`metadata` provides the ABC header block (`X:`, `T:`, `M:`, `L:`, `R:`, `C:`, `Q:`, `K:` fields). Required exactly once.
- Non-transition tunes use column I only (columns J/K blank).
- Transition tunes use explicit segmented authoring on the melody row: `Tail Add` (col J), bridge (`ABC`, col I), `Head Add` (col K).
- For transition tunes, parser order is tail -> bridge -> head.
- The VBA parser (`ParseAllParts`) scans rows 2-25 and reads columns G/H/I/J/K.
- The parts table is populated manually when setting up a new tune sheet.

1.6 Transition Metadata Rows

Transition rows are authored in the metadata block (rows 2-48) under category `Transition`.

| Variable | Purpose |
|---|---|
| prior_tune | Required reference to the prior tune worksheet name/code |
| following_tune | Required reference to the following tune worksheet name/code |
| tail_cut_measures | Number of whole measures replaced at the prior tune tail |
| head_cut_measures | Number of whole measures replaced at the following tune head |

Rules:
- `prior_tune` and `following_tune` are authoritative references; key/meter context for Tail Add and Head Add is resolved from those referenced tune sheets.
- `tail_cut_measures` and `head_cut_measures` are measure counts (not beats).
- Bridge length is inferred from parsed bridge ABC; no separate `bridge_measures` field is required.

2. Event Grid (Header row 50, data from row 51)

Each row represents a musical event. These columns define timing, structure, ornamentation, and playback behavior.

**Note on Embellishments**: The embellishment columns use a hybrid approach:
- `literal`: stores the raw ABC sequence (e.g., "gCd", "ag", "GdGe") as extracted from source
- `preceding_note`: the note immediately before the embellishment (for context)
- `target_note`: the main melody note being embellished
- `alt_anchor`: optional per-instance override of anchor_index (blank = use library default)
- `alt_timing`: optional per-instance override of timing scaling multiplier (blank = use library default)

This structure enables both automated pattern matching and instance-specific customization.

2.1 Event Columns (23-column schema)

Columns are in order left-to-right. VBA constant names are in `Excel - Parse_ABC.txt`.

| Col | Group | Field | Notes |
|---|---|---|---|
| 1 | event | event_ID | Sequential integer |
| 2 | event | type | `note`, `embellishment`, `structure` |
| 3 | event | structure | `bar` for barlines, blank otherwise |
| 4 | location | part | Part number (1-based) |
| 5 | location | measure | Measure number within part |
| 6 | location | beat | Beat position (0-based within measure) |
| 7 | location | division | Sub-beat offset (fractional beat, e.g. 0.75) |
| 8 | location | phrase | Phrase tag (currently unpopulated) |
| 9 | note | letter | Note letter A–g, blank for embellishments/bars |
| 10 | note | midi_value | MIDI note number, blank for embellishments/bars |
| 11 | duration | written | Written duration units |
| 12 | duration | adjusted | Adjusted duration units (after broken rhythm, etc.) |
| 13 | duration | total_units | Running total of units from tune start |
| 14 | embellishment | preceding_note | Note letter immediately before embellishment |
| 15 | embellishment | literal | Raw ABC grace sequence e.g. `{gBd}` |
| 16 | embellishment | target_note | Main melody note being embellished |
| 17 | embellishment | alt_anchor | Per-instance override of library anchor_index (blank = use library) |
| 18 | embellishment | alt_timing | Per-instance override of timing multiplier (blank = use library) |
| 19 | timing | broken_dir | Broken rhythm direction: `>` (dotted), `<` (cut), blank |
| 20 | timing | start_time_ms | Note on time in milliseconds from tune start |
| 21 | timing | end_time_ms | Note off time in milliseconds from tune start |
| 22 | timing | tempo_bpm | Tempo at this event |
| 23 | voice | voice | Voice/instrument: `pipes`, or other identifier |

3. Embellishment Library Sheet

This sheet contains the canonical embellishment patterns that GameMaker uses for pattern matching. It is small, stable, and never expanded with note-specific variants.

3.1 Embellishment Library Columns

| column | purpose | example |
|---|---|---|
| emb_id | unique identifier | 1 |
| emb_name | human-friendly name | B doubling |
| pattern | literal ABC without braces | gBd |
| target_note | required target letter ("" = any) | B |
| notes | playback note letters (comma-separated) | g,B,d |
| timing | relative durations (comma-separated) | 1,3,1 |
| anchor_index | 1-based note that sits on the beat (N+1 can mean target) | 1 |
| category | grouping/tag | doubling |

**Key Principle**: Each embellishment pattern is defined once. GameMaker handles:
- Matching literal ABC sequences (e.g., "{gBd}") to `pattern` plus `target_note`
- Applying anchor-based timing: notes before anchor steal from preceding note; anchor and after steal from target note
- Scaling timing by actual preceding/target durations and tempo
- Using variants by adding more rows (same name, different pattern/target)

4. Notes

- **Literal ABC sequences**: The `embellishment_literal` column preserves the exact ABC notation from the source file.
  
- **Decomposed structure**: `preceding_note` and `target_note` provide structural context for each embellishment, enabling GameMaker to understand the melodic relationship.

- **Hybrid classification**: The `embellishment_type` field can be populated either:
  - **Automatically** by GameMaker's pattern-matching function
  - **Manually** during ABC→Excel conversion or verification
  - This flexibility supports both automated workflows and expert overrides

- **Pattern matching workflow**: GameMaker loads the literal sequence and matches it against the Embellishment Library using `pattern` + `target_note`, then expands with anchor-based timing. Instance-level overrides (`alt_anchor`, `alt_timing`) are checked first; if present, they replace the library values for that specific occurrence.

- **No embellishment expansion in Excel**: The ABC-to-Excel importer outputs literal grace-note sequences without expanding them into individual note events.

- **JSON conversion is straightforward**: Excel→JSON export preserves all embellishment columns for GameMaker processing.

- **Embellishment library export**: Use `ExportEmbellishmentsToJSON` (VBA) to write `embellishments.json`; GameMaker loads this at startup.

- `start_time_ms` and `end_time_ms` are intentionally named to avoid reserved words in GameMaker.

- This structure is stable and designed for the full pipeline: ABC → Excel (literal) → JSON (identity) → GameMaker (pattern matching + playback with per-instance overrides).

- The Embellishment Library sheet is the single source of truth for all embellishment pattern definitions; `alt_anchor` and `alt_timing` provide surgical per-instance customization without modifying the library.