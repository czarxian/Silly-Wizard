Excel Tune Structure Specification

This document captures the complete metadata and event-grid structure used for tune definition in the Silly Wizard project. It consolidates the 48-row metadata block, the 19-column event structure, and the embellishment library into a single authoritative reference.

**Architecture Note**: This document reflects a pattern-based embellishment system (Model B) where ABC sequences remain literal in Excel, and GameMaker performs intelligent pattern matching to identify embellishment types, apply timing, and handle variants.

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

1.2 Metronome Metadata

enabled

beats_per_bar

subdivision

accent_note

accent2_note

normal_note

click_duration_ms

channel

velocity

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

2. Event Grid (Rows 49–50 onward)

Each row represents a musical event. These columns define timing, structure, ornamentation, and playback behavior.

**Note on Embellishments**: The embellishment columns use a hybrid approach:
- `literal`: stores the raw ABC sequence (e.g., "gCd", "ag", "GdGe") as extracted from source
- `preceding_note`: the note immediately before the embellishment (for context)
- `target_note`: the main melody note being embellished
- `alt_anchor`: optional per-instance override of anchor_index (blank = use library default)
- `alt_timing`: optional per-instance override of timing scaling multiplier (blank = use library default)

This structure enables both automated pattern matching and instance-specific customization.

2.1 Event Columns

part

measure

beat

division

type

note_letter

note_midi

written_duration_units

adjusted_duration_units

embellishment_literal

embellishment_preceding_note

embellishment_target_note

embellishment_alt_anchor

embellishment_alt_timing

structure

total_units

start_time_ms

end_time_ms

tempo_bpm

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