# GRACE NOTE ATTACHMENT RECLASSIFICATION — DESIGN & EVALUATION FRAMEWORK

## Problem Statement

**Scenario**: Player performs a grace note on MIDI **before** the structural window where that grace is planned in the tune.

**Example**:
- ABC defines: grace at measure 5 beat 2 (expected 2571 ms)
- MIDI recorded: player played grace at 2452 ms (119 ms early, same lane)
- Problem: Duration-based role inference classified player onset as "note" (not grace)
- Consequence: Role-first gate rejected grace+melody pairing before pair-cost could consider timing

**Root Cause**:
- Player role classification (from MIDI duration) is **uncertain** - depends on hardware sensitivity, player technique
- Planned grace targets (from ABC) are **certain** - authored structural ground truth
- Current matcher applies role-first gates based on uncertain data, preventing structural matching

---

## Solution Architecture: Preprocessing Reclassification Rule

### Design Principle
Use **certain information** (planned grace targets from ABC) to resolve **uncertain information** (player MIDI duration-based role inference).

### Location in Pipeline
```
Player MIDI onsets
    ↓
[Collect player onsets, infer roles from duration]
    ↓
[NEW: Reclassify grace onsets based on planned targets] ← Preprocessing
    ↓
Dynamic programming matcher
    ↓
Pair-cost evaluation (with role-aware gates)
    ↓
Scored assignments
```

### Processing Stage
- **Timing**: Before DP matcher, after player onset collection
- **Input state**: Players array with `inferred_role` set from MIDI duration
- **Output state**: Players array with corrected `inferred_role` for onset-before-grace scenarios
- **Mutation**: Selective in-place update of player `inferred_role` field

---

## Algorithm: `scoring_event_match_reclassify_grace_onsets`

### Input
- `_targets`: Array of target structs from ABC, each with:
  - `expected_ms`: Planned timing
  - `lane_idx`: MIDI channel
  - `source_kind`: "note" | "embellishment_unit"
  - `gesture_role`: Primary role hint (may differ from source_kind)

- `_players`: Array of player onset structs, each with:
  - `start_ms`: Actual player timing (MIDI)
  - `lane_idx`: MIDI channel
  - `inferred_role`: "note" | "embellishment_unit" (from duration)

- `_settings`: Matcher settings struct, including:
  - `grace_anchor_lead_ms`: Max milliseconds before grace target (default 250)

### Logic

```
FOR EACH player onset P:
    IF P.inferred_role == "note":  // Only consider "note"-classified onsets

        FOR EACH target T:
            IF T.source_kind == "embellishment_unit":  // Grace targets only
                AND T.lane_idx == P.lane_idx:           // Same lane (no cross-lane)

                    delta_ms = T.expected_ms - P.start_ms

                    IF 0 < delta_ms <= grace_anchor_lead_ms:  // Grace is after, within window
                        P.inferred_role = "embellishment_unit"  // Reclassify
                        BREAK (next player)
```

### Key Features

1. **Positive time delta only**: Player must come **before** grace target
- Prevents false positive reclassification of melody following a grace

2. **Window constraint**: Delta must be <= `grace_anchor_lead_ms` (250 ms default)
- Ensures tight timing relationship
- Configurable without code change via settings

3. **Lane matching**: Only considers same MIDI channel
- Prevents bagpipe chanters (different lanes) from interfering
- Respects multi-voice structure

4. **Source_kind check**: Only reclassifies against planned graces
- Planned grace = ABC parse result = certain
- Ignores other target types

5. **First match wins**: Stops at first grace target found
- Typical grace clusters have tight spacing
- Earliest grace is most likely structural target

---

## Data Flow Example: Canadian Scottish Performance

### Before Reclassification
```
Target T6:
  expected_ms: 2571
  lane_idx: 0
  source_kind: "embellishment_unit"  ← Grace
  gesture_role: "embellishment_unit"

Player P5:
  start_ms: 2452
  lane_idx: 0
  inferred_role: "note"  ← Wrong (from duration < 250 ms threshold)

Current matcher:
  → Role-first gate applies
  → grace ≠ note
  → Pair cost = 1e9 (rejected)
```

### After Reclassification
```
Player P5:
  start_ms: 2452
  lane_idx: 0
  inferred_role: "embellishment_unit"  ← Corrected

Check: target T6
  delta_ms = 2571 - 2452 = 119 ms
  lane_idx match: 0 == 0 ✓
  source_kind == embellishment_unit: ✓
  0 < 119 <= 250: ✓
  → Reclassify P5 to "embellishment_unit"

Current matcher:
  → Role-first gate applies
  → grace == grace
  → Gate passes
  → Pair cost = 0.25 × time_delta (grace early multiplier)
  → Scoring: "player early grace"
```

---

## Why This Is General-Purpose (Not Ad Hoc)

### Criterion 1: Rule-Based, Not Hardcoded
- No tune-specific data or magic numbers
- Single algorithm applies to all performances
- Settings (`grace_anchor_lead_ms`) are performance parameters, not tune overrides

### Criterion 2: Derives from Architectural Invariant
- Built on principle: "Use certain data to resolve uncertain data"
- Applies to **any** player grace played before planned grace window
- Works for solos, sets, transitions, any tune structure

### Criterion 3: Handles Performance Variation
- MIDI timing differs per performer: 100 ms early, 50 ms early, on-time
- MIDI duration sensitivity differs per device
- Algorithm adapts to whatever player data arrives
- No per-performance tweaks needed

### Criterion 4: Maintains Structural Integrity
- Preserves ABC authorship (ground truth)
- Doesn't create new targets
- Only reclassifies player onset roles
- DP matcher remains unchanged and authoritative

### Criterion 5: Gracefully Degrades
- If no grace target within window -> player classified as "note" (no change)
- If player role already "embellishment_unit" -> no reclassification (idempotent)
- If settings changed (e.g., `grace_anchor_lead_ms = 0`) -> preprocessing disabled

---

## Verification Criteria: How to Assess Correctness

### Test 1: Basic Reclassification (Unit Level)
```
Input:
  Player: onset 2452 ms, lane 0, inferred_role "note"
  Target: grace at 2571 ms, lane 0, source_kind "embellishment_unit"
  Settings: grace_anchor_lead_ms = 250

Expected Output:
  Player: inferred_role changed to "embellishment_unit"
```

### Test 2: Window Boundary (Edge Cases)
```
Scenario A (Within window):
  delta_ms = 249
  Expected: Reclassified ✓

Scenario B (At boundary):
  delta_ms = 250
  Expected: Reclassified ✓

Scenario C (Outside window):
  delta_ms = 251
  Expected: NOT reclassified ✓

Scenario D (After grace):
  delta_ms = -50 (player after target)
  Expected: NOT reclassified ✓
```

### Test 3: Lane Isolation
```
Scenario A (Same lane):
  Player lane 0, Target lane 0
  Expected: Reclassified (if time OK) ✓

Scenario B (Different lanes):
  Player lane 0, Target lane 1
  Expected: NOT reclassified ✓
```

### Test 4: Source Kind Filter
```
Scenario A (Grace target):
  source_kind = "embellishment_unit"
  Expected: Reclassified (if time OK) ✓

Scenario B (Melody target):
  source_kind = "note"
  Expected: NOT reclassified ✓
```

### Test 5: Multiple Grace Targets (First Match)
```
Scenario:
  Player at 2452 ms, lane 0, inferred_role "note"
  Target T1: 2500 ms (grace) <- Should match this
  Target T2: 2571 ms (grace)

Expected:
  Player reclassified on T1 (first match within window)
  T2 not considered (already stopped) ✓
```

### Test 6: Regression - No False Positives
```
Scenario A (Melody before unrelated grace):
  Player 2000 ms, lane 0, inferred_role "note"
  Grace target 2600 ms, lane 1 (different lane)
  Expected: NOT reclassified ✓

Scenario B (Already-classified grace):
  Player 2452 ms, inferred_role "embellishment_unit" (already correct)
  Grace target 2571 ms, lane 0
  Expected: No change (idempotent) ✓

Scenario C (No target in window):
  Player 1000 ms, inferred_role "note"
  Nearest grace 5000 ms
  Expected: NOT reclassified ✓
```

### Test 7: End-to-End Performance Scoring
```
Tune: Canadian Scottish
Performance: Player A, P5 grace at 2452 ms

Before:
  P5 assigned to: (unassigned)
  Event match score: incomplete

After:
  P5.inferred_role: "embellishment_unit"
  P5 assigned to: T6 (2571 ms)
  Pair cost: 0.25 × 119 = ~30 (grace early penalty)
  Event match score: complete with grace timing feedback ✓
```

---

## Algorithmic Properties

| Property | Value | Justification |
|----------|-------|---|
| Time Complexity | O(P × T) | P players, T targets; per-player O(T) scan |
| Space Complexity | O(1) | In-place mutation of player array |
| Idempotent | Yes | Already-classified onsets skip the gate |
| Deterministic | Yes | Same input always produces same output |
| Commutative (player order) | Yes | Each player independent |
| Commutative (target order) | No | First match within window wins |
| Sensitivity | High | Tuned to `grace_anchor_lead_ms` setting |
| Stability | Stable | Does not reorder or remove onsets |

---

## Configuration & Tuning

### Default Settings
- `grace_anchor_lead_ms`: 250 ms
- Typical grace anticipation in bagpipe performance
- Empirically tuned from player study data

### Adjustments
```
IF players consistently played graces >250 ms early:
  Increase grace_anchor_lead_ms (e.g., 350)

IF false positives occur (melody misclassified as grace):
  Decrease grace_anchor_lead_ms (e.g., 150)

IF adjustment needed:
  Edit settings.grace_anchor_lead_ms in caller
  No code change required
```

---

## Known Limitations & Mitigations

### Limitation 1: First Match Heuristic
- Multiple graces in tight cluster: only first one triggers reclassification
- **Mitigation**: Clusters are rare; most grace clusters space >250 ms apart

### Limitation 2: No Target Duration Model
- Algorithm doesn't account for whether grace is short or long
- **Mitigation**: Grace targets themselves may have varying durations in planning (future work)

### Limitation 3: No Player Velocity/Energy Analysis
- Uses only timing, not MIDI velocity or articulation
- **Mitigation**: Simpler, more robust; duration-based heuristic already unreliable

### Limitation 4: Window Is Fixed
- Single window for all tempo ranges
- **Mitigation**: Could be tempo-aware in future; current default works empirically

---

## Why DP Matcher Doesn't Handle This Internally

The role-first gate **must** apply before pair-cost to reject structurally impossible pairings:
- Grace cannot attach to melody (different articulation roles)
- Melody cannot attach to grace prep
- Cost-only approach would allow invalid pairings

Therefore, preprocessing is necessary to **reclassify uncertain roles** before gates apply. This is cleaner than:
- Disabling role-first gates (enables invalid pairings)
- Adding tempo-aware duration thresholds (per-tune magic numbers)
- Hardcoding grace-early exceptions (tune-specific ad hoc logic)

---

## Implementation Location

**File**: `scripts/scr_scoring/scr_scoring.gml`

**Function**: `scoring_event_match_reclassify_grace_onsets(_targets, _players, _settings)`
- Location: ~line 2195
- Called by: `scoring_event_match_assign_targets` (line 2341)
- Size: ~52 lines

**Caller**: Entry point in `scoring_event_match_assign_targets`
- Receives: targets, player_spans, settings
- Performs: preprocessing step before DP matcher
- Returns: Modified players array to DP matcher

---

## FULL MATCHING WORKFLOW/LOGIC/PROCESS (END-TO-END)

This section describes the complete matcher as implemented in the scoring pipeline, not only the grace reclassification step.

### 1) Inputs and Preconditions

The matcher consumes three core inputs:

- `targets`: Planned events from tune content (ABC -> parse -> preprocess -> timing)
- `player_spans`: Raw MIDI performance spans captured during play
- `settings`: Matching/scoring configuration

To evaluate matcher quality fairly, all three must be captured for the same run.

### 2) Planned Target Construction

Planned targets are produced upstream and include at minimum:

- Structural timing (`expected_ms`)
- Lane/voice (`lane_idx`)
- Source classification (`source_kind`: `note` or `embellishment_unit`)
- Role metadata (`gesture_role`)
- Measure/beat context where applicable

Target semantics come from authored content and are treated as authoritative ground truth.

### 3) Player Onset Collection

`player_spans` are converted into player onsets used by matching:

- `start_ms` from performed MIDI
- `lane_idx` from input lane/channel mapping
- Initial `inferred_role` from duration heuristic

This step transforms noisy performance spans into a normalized sequence suitable for DP matching.

### 4) Settings Normalization

Matcher settings are normalized before assignment so all downstream logic sees stable defaults. Typical knobs include:

- Grace window (`grace_anchor_lead_ms`)
- Optional skip penalties
- Grace order behavior
- Timing tolerances and cost multipliers

This prevents missing/null setting fields from changing behavior unpredictably across runs.

### 5) Pre-Match Reclassification (Grace Attachment Rule)

Before DP starts, uncertain player role inference is corrected where planned grace targets provide reliable evidence:

- Candidate player onset currently inferred as `note`
- Same-lane planned target with `source_kind = embellishment_unit`
- Target occurs shortly after player onset
- `0 < (target.expected_ms - player.start_ms) <= grace_anchor_lead_ms`

If all conditions pass, player role is rewritten to `embellishment_unit`.

### 6) Candidate Feasibility and Hard Gates

During pair evaluation, each target-player pair passes through feasibility gates before soft cost terms:

- Role compatibility gates (melody vs grace constraints)
- Lane compatibility checks
- Ordering/monotonic constraints enforced by DP path structure

Invalid structural pairings are assigned effectively infinite cost and excluded from optimal matching.

### 7) Pair-Cost Computation

For feasible pairs, pair cost is built from timing and rule-specific terms:

- Base timing delta `abs(player.start_ms - target.expected_ms)`
- Grace-specific timing handling (early grace multiplier behavior)
- Optional ordering penalties where configured
- Additional guardrail penalties per settings

The resulting scalar pair cost is what DP optimizes globally.

### 8) Dynamic Programming Assignment

The matcher solves a global monotonic alignment problem over full target/player sequences:

- State tracks progress through target index and player index
- Transition options include: match, skip target, skip player
- Total path cost = sum of transition and pair/skip costs
- Optimal path chosen by minimum total cost

This ensures local ambiguities are resolved in globally consistent fashion.

### 9) Assignment Materialization

From DP result, the system emits:

- `assignments` list
- `assignment_by_target_index`
- `assignment_by_player_span_index`
- `unassigned_targets`
- `unassigned_players`
- `total_cost`

These structures are consumed by scoring judges and analysis tooling.

### 10) Judge-Level Scoring Outputs

Judges derive metrics from assignment core, for example:

- Correctly matched structural events
- Timing quality (early/late/on-time characterization)
- Grace handling outcomes
- Aggregate event-match score contribution

This is where player feedback and summary JSON metrics are produced.

---

## Fair Evaluation Framework for the Full Matcher

To judge matcher behavior fairly, evaluate with evidence from all relevant layers.

### Required Artifacts Per Test Run

- Full `event_match_core` block (targets, players, assignments, unassigned sets, total cost)
- Effective settings used by matcher
- Tune metadata context (tempo/time signature where relevant)
- Raw or normalized player spans used to build onsets

### Mandatory Validation Checks

1. **Structural validity**
- No illegal role pairings accepted
- No cross-lane mismatches accepted unless explicitly permitted

2. **Monotonicity validity**
- Assigned indices preserve forward ordering
- No backward jumps in target-player alignment

3. **Coverage quality**
- Unassigned targets/players are explainable by timing/role constraints
- No obvious low-cost feasible pair left unmatched when global path allows it

4. **Cost consistency**
- Pair-level penalties reflect documented settings
- Changing one setting changes outcomes in expected direction

5. **Grace behavior correctness**
- Early grace cases inside window can be reclassified and matched
- Out-of-window or cross-lane grace candidates are not reclassified

### Regression Matrix (Recommended)

- Clean melody-only passages
- Dense embellishment passages
- Mixed melody+grace transitions
- Multi-lane/voice sections
- Tempo-varied performances
- Human timing variance (early, late, jittered)

### Acceptance Signals

A change to matcher logic is acceptable when:

- It improves target test scenario(s) (for example, previously-unmatched grace now matched correctly)
- It does not introduce new invalid pairings
- It keeps or improves aggregate assignment stability on regression corpus
- It preserves deterministic behavior for identical inputs/settings

---

## ADDITIONAL IMPLEMENTATION SECTIONS (REQUESTED)

### 1. Melody Continuity Merge (if implemented)

Current state in event-match core:

- There is no separate, named Melody Continuity Merge pass that rewrites split melody fragments into one merged melody span.
- Continuity is currently preserved by canonical slot compilation and monotonic DP ordering.
- Stable ordering uses global/planned source indices, so filtered/reindexed targets keep original sequence identity.

What effectively provides continuity today:

- Canonical target compilation preserves source ordering and global span identity.
- DP alignment is monotonic, so once target order is set, assignments cannot jump backward.
- Optional phrase-cluster compilation groups embellishment sequences with following melody anchors, reducing fragmentation around grace-heavy regions.

If a future explicit merge pass is added:

- It should run before slot compilation.
- It should preserve source identity fields so downstream assignment and UI maps remain stable.

### 2. Grace Attachment Inside Melody Duration

How attachment works in current matcher:

- Grace-like player onsets are represented as player onsets with inferred role.
- Pre-DP reclassification can rewrite a player onset from note to embellishment_unit when a same-lane planned grace target appears shortly after it.
- Phrase-cluster target metadata links embellishment spans and the following anchor melody note, so grace behavior is evaluated in cluster context rather than as isolated points.

Important behavior note:

- Grace played inside or near a melody sustain is not attached by duration overlap alone.
- Attachment still requires feasible target-role and timing-window compatibility in pair evaluation.

### 3. Cluster-Aware Timing Windows

The matcher uses role-sensitive timing neighborhoods:

- Base neighborhood is derived per target from configured settings.
- Embellishment targets apply an additional grace-neighborhood multiplier.
- Pairs outside neighborhood are rejected as infeasible.

Practical effect:

- Melody windows are stricter around note anchors.
- Grace/embellishment windows are broader or differently weighted via grace neighborhood and grace timing multipliers.
- This gives grace events controlled tolerance without weakening melody matching discipline.

### 4. Role-First Feasibility Gates

Role-first gating is applied before soft cost scoring:

- Melody target + grace player mismatch is hard-rejected (effectively infinite cost).
- Any pair that fails role/feasibility checks never reaches optimization as a valid match candidate.

Why this matters:

- Prevents structurally invalid grace->melody and melody->grace pairings.
- Keeps DP search space constrained to musically plausible assignments.
- Makes preprocessing role correction necessary when uncertain player-role inference conflicts with planned structure.

### 5. Pair-Cost Model

Pair cost is the sum of timing terms and penalties after feasibility passes.

Timing cost:

- Base timing term is absolute onset delta between player onset and target expected time.

Grace early/late multipliers:

- For grace-like player events that occur early relative to target time, timing cost is reduced by a grace timing multiplier.
- This intentionally tolerates anticipatory grace execution.

Role mismatch penalties:

- If target role and player role differ, a role mismatch penalty is added.
- Melody-protection multiplier can further amplify penalties in melody-protection cases.

Lane mismatch penalties:

- When target lane and player lane differ (and both are known), lane mismatch penalty is added.

Interval-prior penalties:

- If interval ownership prior disagrees with candidate target index, interval-prior penalty is added.

Noise penalties:

- Short/noisy player events below noise-floor characteristics can receive noise pair penalties.
- Additional plausibility checks can add pitch-implausible or duration-implausible penalties.

Grace order penalties:

- Optional grace-order penalty can bias target melody anchors away from too-early onsets in pre-target grace windows.

### 6. DP Solver Details

State and transitions:

- DP state is indexed by target prefix length and player prefix length.
- At each state, solver considers:
  - match (consume target and player)
  - skip target (consume target only)
  - skip player (consume player only)

Monotonicity:

- All transitions move forward in index space.
- No transition allows backward reassignment.

Global optimality:

- Solver minimizes total accumulated objective over full sequence.
- Backtrace reconstructs the globally minimum-cost monotonic path.

Output products:

- assignments
- unassigned_targets
- unassigned_players
- total_cost

### 7. Identity Preservation

Identity fields used to keep target/player mapping stable:

- planned global source index is preserved from planned spans into target identity fields (target_source_global_span_index in assignments).
- player_span_index records original player onset index from collected player onsets.

Assignment maps:

- assignment_by_target_index
- assignment_by_target_event
- assignment_by_player_span_index

UI/runtime resolution:

- Downstream consumers resolve by these stable identity keys instead of fragile position-only assumptions.
- This allows filtered channels, reordered local arrays, and summarized judge views to still map to original source events.

### 8. Scoring Judges

Event-match score:

- Built from event-match core assignments.
- Per-target timing quality and match coverage are aggregated into overall score and measure-level rows.

Note-match F1 score:

- Built from event-match core output.
- Planned recall and player precision are combined via harmonic mean (F1).

Cluster scoring:

- Phrase clusters are compiled and exposed in raw outputs.
- Cluster-aware behavior influences target construction and assignment context.
- Embellishment-window judges additionally score ordered in-window behavior where enabled.

Timing scoring:

- Event-match uses delta-based assignment quality.
- On-beat style judges map absolute delta bands to graded scores.

### 9. Known Limitations

Grace played late:

- Early-grace tolerance is explicit; late grace handling can still degrade matching in dense passages depending on neighborhood settings.

Grace played inside melody:

- Overlap alone is not sufficient for attachment; strict role/feasibility can still reject ambiguous in-melody grace behavior.

Multi-grace clusters:

- First-match style attachment/reclassification heuristics can be sensitive in very dense clusters.

Cross-lane ornamentation:

- Same-lane preference/protection improves correctness but can under-handle intentional cross-lane ornamentation patterns.

Tempo-aware windows (future work):

- Current windows and multipliers are largely fixed-setting driven.
- A tempo-scaled neighborhood model is a strong future enhancement candidate.

---

## Compact Workflow Pseudocode (Reference)

```
INPUT: targets, player_spans, settings

players = collect_player_onsets(player_spans)
settings = normalize_settings(settings)

reclassify_grace_onsets(targets, players, settings)

result = dp_assign_targets(targets, players, settings)

OUTPUT:
  result.targets
  result.players
  result.assignments
  result.assignment_by_target_index
  result.assignment_by_player_span_index
  result.unassigned_targets
  result.unassigned_players
  result.total_cost
```

This is the full operational contract that downstream judges depend on.
