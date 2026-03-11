Bagpipe Tune Data Schema and Pipeline

This document captures the finalized, canonical structure for your ABC → Excel → JSON → GameMaker pipeline. It reflects the updated Excel layout, the corrected VBA exporter, and the JSON format validated from your sample output.

1. Metadata Schema

Metadata is stored in a simple key/value structure grouped by category.

Tune Fields

reference number

title

composer

rhythm

tempo_default

tempo_min

tempo_max

parts

measures_per_part

measures_total

unit_note_length

base_note_decimal

default_unit_ms

key

meter

time_sig_num

time_sig_den

abc_source

Metronome Fields

enabled

beats_per_bar

subdivision

accent_note

accent2_note

normal_note

click_duration_ms

channel

velocity

Performance Fields

channel

group

part

swing

humanize_ms

structure

ornaments

instrument_midi_note_base

Info Fields

area

book

discography

file name

history

information

notes

origin

source

words

transcription note

user defined

2. Event Schema (Canonical 21-Column Layout)

Each event row in Excel maps directly to JSON and then to a GML struct.

Column Groups and Fields

Group

Field

event

event_id

event

type

event

structure

location

part

location

measure

location

beat

location

division

location

phrase

note

letter

note

midi_value

duration

written

duration

adjusted

duration

total_units

embellishment

name

embellishment

positions

embellishment

alt_anchor

embellishment

alt_timing

timing

start_time_ms

timing

end_time_ms

timing

tempo

3. JSON Output Schema

Each event becomes a JSON object with the following structure:

{
  "event_id": <number>,
  "type": "note | embellishment | structure",
  "structure": "bar" or "",

  "part": <number>,
  "measure": <number>,
  "beat": <number>,
  "division": <number>,
  "phrase": "",

  "letter": "A–g" or "",
  "midi_value": <number>,

  "written": <number>,
  "adjusted": <number>,
  "total_units": <number>,

  "emb_preceding": "A" or "",
  "emb_literal": "{gBd}" or "",
  "emb_target": "B" or "",
  "emb_alt_anchor": <number> or "",
  "emb_alt_timing": <number> or "",

  "start_time_ms": <number>,
  "end_time_ms": <number>,
  "tempo": <number>
}

Rules

Missing numeric values become 0.

Missing string values become "".

JSON is always valid and GameMaker‑friendly.

4. Pipeline Overview

Step 1 — ABC → Excel (VBA)

Tokenizes ABC

Expands repeats

Handles broken rhythms

Computes durations

Computes total_units

Writes event rows

Second pass computes measure/beat/division

Step 2 — Excel → JSON (VBA)

Reads each event row

Applies numeric/string normalization

Outputs valid JSON array

Step 3 — JSON → GameMaker

Load with json_parse()

Produces:

tune struct

events[] array of structs

No type conversion required

5. Validation Notes

The sample JSON provided is valid.

All numeric fields correctly default to 0.

All string fields correctly default to "".

Optional override fields (`emb_alt_anchor`, `emb_alt_timing`) default to "" (empty = use library).

The schema is stable and ready for Q2 development.

6. Per-Instance Embellishment Overrides

GameMaker applies embellishment overrides with this precedence:

1. **Instance-level override** — if `emb_alt_anchor` or `emb_alt_timing` is non-empty, use that value
2. **Embellishment Library default** — fall back to the canonical library entry

Example events:
```
{
  "emb_literal": "{gCd}",
  "emb_target": "C",
  "emb_alt_anchor": "",
  "emb_alt_timing": ""
}
// Uses library default for both anchor and timing

{
  "emb_literal": "{GdGe}",
  "emb_target": "G",
  "emb_alt_anchor": 1,
  "emb_alt_timing": ""
}
// Overrides anchor to 1; timing from library

{
  "emb_literal": "{gBd}",
  "emb_target": "B",
  "emb_alt_anchor": "",
  "emb_alt_timing": 1.2
}
// Overrides timing multiplier to 1.2x; anchor from library
```


  
   


8. Next Steps



This page now serves as the authoritative reference for your tune data model.
```