# Transition Tune Template

Purpose: standard authoring pattern for transition tunes that trim neighboring tunes and insert bridge material.

## Behavior Model

- A transition tune sits between two normal tunes in a set.
- Transition metadata applies to neighboring tunes, not to the transition tune itself.
- `tail_cut_beats` trims the end of the previous tune.
- `head_cut_beats` trims the start of the next tune.
- Transition tune notes provide replacement/bridge content as one continuous timeline.

## Required Metadata

Set these in the transition tune metadata table:

- `is_transition = true` (recommended naming marker)
- `tail_cut_beats = <number>`
- `head_cut_beats = <number>`

Recommended defaults while drafting:

- `tail_cut_beats = 0`
- `head_cut_beats = 0`

Then increase in half-beat or beat increments while listening in the target set.

## Set Ordering Rule

Use this order in the set:

1. Tune A (normal)
2. Transition tune (T_...)
3. Tune B (normal)

Do not place a transition tune first or last if it is expected to trim neighbors.

## ABC Writing Patterns

Assuming `M:C` and `L:1/8`:

- Two quarter notes in a beat-pair feel: `e2e2`
- One sustained half-note feel: `e4`
- Tied sustain with visible split: `e2-e2`

Avoid premature ending markers in the middle of replacement phrases:

- Avoid: `e2|]e2`
- Prefer: keep phrase continuous and place final bar/end at the actual tune end.

## Authoring Procedure

1. Create transition tune title with `T_<From>_to_<To>` naming.
2. Enter transition melody that includes:
   - replacement tail idea
   - bridge material
   - replacement head pickup
3. Set `tail_cut_beats` and `head_cut_beats` in metadata.
4. Export tune JSON.
5. Build set in order: A, Transition, B.
6. Play and adjust cut beats by ear.

## Quick Verification Checklist

- Previous tune ends earlier by `tail_cut_beats` amount.
- Next tune starts later by `head_cut_beats` amount.
- Transition phrase is fully audible (not self-trimmed).
- No hanging visual note beams at cut boundaries.
- No orphan note-offs in audible playback.

## Troubleshooting

If no cut happens:

- Confirm transition tune is in the middle of the set.
- Confirm metadata values export into transition JSON.
- Confirm `tail_cut_beats` and `head_cut_beats` are numeric.

If replacement sounds incomplete:

- Lower one cut value at a time and retest.
- Check ABC ending markers (`|]`) are not closing early.

If visuals stretch past heard notes:

- Re-export and retest; boundary note-off repair is handled in preprocess.
