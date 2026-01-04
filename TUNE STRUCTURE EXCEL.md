Excel Tune Structure Specification

This document captures the complete metadata and event-grid structure used for tune definition in the Silly Wizard project. It consolidates the 48-row metadata block and the 19-column event structure into a single authoritative reference.

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

Each row represents a musical event. These 19 columns define timing, structure, ornamentation, and playback behavior.

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

embellishment_name

embellishment_anchor

embellishment_duration_units

embellishment_pattern

embellishment_relative_positions

structure

total_units

start_time_ms

end_time_ms

tempo_bpm

3. Notes

start_time_ms and end_time_ms are intentionally named to avoid reserved words in GameMaker.

This structure is stable and intended for direct conversion into JSON.

The event grid feeds directly into the tune loader and note/tempo/structure maps in the game.

This page serves as the canonical reference for all tooling, converters, and runtime systems that consume the Excel tune definition.