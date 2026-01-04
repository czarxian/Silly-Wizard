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

anchor

embellishment

duration

embellishment

pattern

embellishment

positions

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

  "emb_name": "{g}" or "",
  "emb_anchor": "",
  "emb_duration": <number>,
  "emb_pattern": "",
  "emb_positions": "",

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

The schema is stable and ready for Q2 development.

6. Next Steps

Build the GML JSON loader

Build the event timeline processor

Build the ornament expander

Build the playback engine

This page now serves as the authoritative reference for your tune data model.