# Loop Mutation Only Checklist

## Scope
- Use existing pipeline as source of truth: ABC -> VBA export -> JSON -> preprocess -> planned events.
- Focus only on loop mutation stage and immediate consumers.
- Do not re-audit or rewrite upstream pipeline unless non-loop baseline proves broken.

## Stage 0 - Baseline Lock
1. Confirm non-loop playback for target tune remains correct.
2. Freeze preprocess output contract for loop input.
3. No edits in ABC/VBA/export paths for this loop fix track.

## Stage 1 - Loop Input Contract
1. Loop builder reads only:
- planned events array
- selected refs (timeline + identity coordinates)
- loop settings
2. Selected refs must carry:
- timeline start/end
- owner start/end
- nav_idx and owner_nav_idx
3. No musical reinterpretation in loop builder.

## Stage 2 - Loop Mutation Responsibilities
1. Slice by timeline time window.
2. Include/filter by musical identity.
3. Expand by iteration/pass metadata.
4. Apply closure note_off at loop end.
5. Preserve deterministic same-time ordering.

## Stage 3 - Loop Builder Gates
1. Template gate:
- selected time-window content is correct before repeats.
2. Inclusion gate:
- only intended owner identities included.
3. Expansion gate:
- each pass equals template plus offset (plus configured spacer policy).
4. No fallback to raw measure labels when timeline/owner coordinates exist.

## Stage 4 - Scheduler Contract (No New Logic)
1. Scheduler dispatches grouped loop output as-is.
2. No new owner/timeline inference in callback path.
3. Preserve existing play engine behavior.

## Stage 5 - Consumer Contracts
1. Indicator resolves musical identity from loop mapping.
2. Score images resolve by time/fragment mapping.
3. Cursor/playhead placement resolves by timeline time.
4. Avoid cross-layer fallback unless explicitly degraded.

## Stage 6 - Internal Pickup Rule
1. Timeline placement may remain in prior timeline region.
2. Musical ownership may map to next measure identity.
3. This dual representation is valid and must be preserved.

## Stage 7 - Change Order
1. Change loop builder contract only.
2. Change indicator resolver only if needed.
3. Change score-image resolver only if needed.
4. Touch preprocess only if non-loop baseline fails.

## Stage 8 - Acceptance Criteria
1. Non-loop remains unchanged.
2. Internal-pickup loop has no dropped selected measure.
3. Indicator does not skip second-to-last selected measure.
4. Pickup image aligns during loop playback.
5. Behavior is reproducible over repeated runs.
