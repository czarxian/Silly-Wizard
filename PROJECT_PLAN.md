🎯 Vision (End State)
**1. Purpose — Why this exists**
This project is a music‑training tool designed to give bagpipers objective, data‑driven feedback on timing, embellishment execution, and overall musical accuracy in a game-like format. Traditional practice relies heavily on subjective listening and instructor feedback; this tool provides measurable, repeatable analysis similar to rhythm‑game systems, but grounded in real bagpipe technique and musical structure. The goal is to help pipers improve faster, practice more effectively, and understand their playing with unprecedented clarity.

**2. High‑Level Experience**
The finished system allows a player to:
• 	Select a tune from a rich, searchable library
• 	Configure tempo, metronome patterns, parts, and playback options
• 	Create multi tune sets, where each tune options (tempo, metronome, parts, ...) can be customized 
• 	Play along with the tune using a MIDI bagpipe chanter
• 	See real‑time visual feedback (piano‑roll bars, musical score, measure tracker)
• 	Hear synchronized playback of pipes, harmonies, drums, and metronome
• 	Receive detailed post‑play analysis of timing, embellishments, and technique
• 	Track performance trends over time
The experience should feel polished, musical, and intuitive — like a hybrid of a rhythm game and a professional practice tool.

**3. Musical Domain**
The system supports the full structure of pipe band music:
• 	Main bagpipe melody
• 	Additional bagpipe parts (harmonies, seconds, thirds)
• 	Drum corps parts (snare, tenor, bass)
• 	Configurable metronome patterns (beats, accents, subdivisions)
• 	Lead‑ins, pipe band drum rolls, initial E, and transitions
• 	Multi‑tune sets with seamless linking and customized transitions


**4. Tune Pipeline **
Tunes originate from ABC notation, are edited in Excel, and exported as JSON containing metadata and event lists. Embellishments are represented as events and expanded into detailed timing sequences according to user‑configurable rules, which can be customized.
• 	JSON includes metadata, parts, embellishments, and structural events
• 	Embellishments expand according to tune type, user preferences, and style rules
• 	Preprocessing converts musical durations into millisecond‑accurate timestamps
• 	All parts (pipes, drums, metronome, transitions) merge into a unified event stream
This ensures deterministic, real‑time playback with no per‑frame computation overhead.



## ⚡ 1-Minute UI Pre-Run Checklist

Before pressing **Run**:

- [ ] `obj_ui_controller` layer registration includes all active UI layers (exact names/case).
- [ ] No UI instance has `ui_layer_num = -1`.
- [ ] Every new UI instance has a unique `ui_num` (within its layer).
- [ ] Every UI element has a stable unique `ui_name` (recommended globally unique).
- [ ] Any renamed layer references in scripts were updated (e.g., old `gameinfo_UI_layer` names removed).
- [ ] New buttons have valid `button_script_index` and required `button_click_value`.
- [ ] New fields have expected defaults (`field_contents`, IDs/targets if used).
- [ ] Launch once and confirm no UI registration errors on Create.



**5. Gameplay Loop**
1. 	Select tune from a scrollable, sortable, filterable library
2. 	Configure tune options (tempo, metronome, parts, embellishment rules, transitions)
3. 	Preprocess into a unified play array
4. 	Enter Play Room
5. 	Play along with real‑time visual and audio feedback
6. 	Log MIDI input from player for scoring and analysis
7. 	Review results in a post‑play analysis window
8. 	Track progress over time

**6. Key Gameplay Data and Visualization Workflow** (in development)

**6.1 Play Event Workflow (during playback)**
During playback, runtime behavior is driven by two primary data sources:
1. Tune data (planned and played)
  a. Tune as planned: the expanded event list after preprocessing (main part, harmonies, drums, and backing notes).
  b. Tune as played: runtime execution of planned events; usually the same, but may vary slightly due to timing/output lag.
2. MIDI input (player)
  a. Live MIDI-in events from the player chanter (currently assumed to be one player).


Visual elements using tune data:
1. Score display (Panel B) uses tune as planned to show recent, current, and upcoming measures.
2. Note beams / piano roll (Panel F) use tune as planned for upcoming notes.
3. Text display in Panel B (note names, canntaireachd, lyrics, tips) also uses tune as planned when content exists.
4. At the moment of play, planned visuals can transition to played-state visuals where needed.

Event-driven outputs during runtime (tune as played + player MIDI in):
1. MIDI out is driven by event processing.
2. Basic event log captures tune-as-played events, metronome events, and player MIDI-in events.
3. Log expansion and heavy transforms are deferred to post-processing to minimize live-play lag risk.
4. Played-notes display is updated from both tune-as-played and player MIDI-in events.
5. Live performance effects are derived from tune-as-played vs player MIDI-in data, including calculated cues (for example crossing-noise detection from short MIDI-in durations, e.g., <15 ms or configured threshold).

**6.2 Panel Layout and Responsibilities**
1. Tune info window (Panel A)
2. Score window showing current and upcoming measures (Panel B)
3. Section in Panel B showing selectable text:
  a. note and embellishment names
  b. canntaireachd
  c. lyrics
  d. playing advice
4. Narrow header showing measure and beat information (Panel C)
5. Tune structure window with one box per measure for navigation, feedback color-coding, and practice-loop selection (Panel D)
6. Small settings window for runtime-safe settings (no preprocessing-impact changes) (Panel E)
7. Main performance area (Panel F) showing piano-roll style upcoming notes, play axis, tune/player played notes, and error color-coding cues.

**6.3 Panel Motion and Update Rules**
1. Panels B, C, and F scroll in sync with playback time (right-to-left, faster at higher BPM).
2. Display range is configurable (for example, prior + current + next measure, or wider look-ahead).
3. Other panels (for example Panel D) update during playback but do not time-scroll in sync with tune timing.

**6.4 Canonical Note Normalization (implemented)**
1. Runtime note identity is now split into three fields:
  a. `note_midi_raw`: raw MIDI value received from device input.
  b. `note_canonical`: shared musical note identity used across chanter types (for example G, A, B, =c, c, d, e, =f, f, g, a).
  c. `note_midi`: normalized/output MIDI value resolved from the active chanter profile.
2. Each chanter profile defines:
  a. Canonical-to-MIDI map (used for playback/output mapping).
  b. MIDI-in alias map (used to normalize incoming device-specific note values to canonical identity).
3. Normalization happens at MIDI ingest time to keep downstream systems simple.
4. Canonical data is propagated to timeline/event history so post-play comparison can use canonical identity later without rewriting ingest.

**6.5 Supporting Multiple Chanter Profiles (next steps)**
1. Add one profile entry per chanter in the profile registry:
  a. Profile name.
  b. Canonical-to-MIDI map.
  c. MIDI-in alias map (including any alternate device note numbers).
2. Add profile option to runtime settings (`global.MIDI_chanter_options`) and selection UI.
3. Verify round-trip mapping per profile:
  a. Device MIDI in -> canonical note.
  b. Canonical note -> playback/output MIDI.
4. Track unknown incoming notes during testing and add missing aliases to the relevant profile.
5. Keep scoring/judging logic profile-agnostic by comparing `note_canonical` first, with timing handled separately.

---

**6.6 Notebeam Visual Rendering System (implemented)**

The notebeam panel (Panel F) renders a piano-roll style view of planned and player note spans as horizontal beams. The rendering pipeline lives entirely in `scripts/scr_game_viz/scr_game_viz.gml` (~2200 lines). Configuration lives in `objects/obj_game_viz/Create_0.gml` inside `global.timeline_cfg`.

**6.6.1 Rendering Pipeline Overview**

1. On tune start, `gv_bind_timeline_on_tune_start(_planned_events, _bpm, _meter_text)` is called:
   - Calls `gv_build_planned_spans(_events)` to convert the preprocessed event list into `global.timeline_state.planned_spans[]` — an array of structs with `{start_ms, end_ms, note, channel, is_embellishment}`.
   - Calls `gv_build_emb_groups(_planned_spans)` to precompute embellishment groups into `global.timeline_state.emb_groups[]`. Each group covers a sequence of grace notes + a target note and includes a `note_set{}` struct for O(1) membership testing.
   - Stores BPM and meter for beat-guide and structure-row drawing.

2. Each draw frame, `gv_draw_notebeam_canvas(_x1, _y1, _x2, _y2)` is called:
   - Reads config from `global.timeline_cfg`.
   - Determines the visible time window from playhead position, `measures_ahead`, and `measures_behind`.
   - Draws background, beat guides, and the structure row.
   - Draws planned note beams (grey/blue by default).
   - Draws player note beams from `global.timeline_state.player_in[]` (completed spans) and `global.timeline_state.pending_player{}` (currently held notes).
   - Player beam color and style depend on the active **compare version** (see 6.6.2).

3. Time-to-pixel conversion is done by `gv_time_to_x(_ms, _now_x, _now_ms, _px_per_ms)` — a simple linear mapping.

4. Lane positions come from `gv_lane_y_for_note(_note, _cfg)` which maps canonical note names to vertical pixel positions.

**6.6.2 Compare Versions (notebeam_compare_version)**

The key that controls rendering mode is `notebeam_compare_version` in `global.timeline_cfg`. Set it to 1, 2, or 3.

**Version 1 — Basic overlay (default)**
- Planned spans draw in their planned color.
- Player spans draw on top in a single solid player color.
- No overlap analysis. Simple and reliable baseline.
- Use this to confirm the basic pipeline is working before testing v2/v3.

**Version 2 — Segmented overlap coloring**
- For each player span, `gv_collect_lane_overlap_segments()` is called to find all time segments where the player span overlaps any planned span on the same note lane.
- `gv_draw_split_normal_player_beam()` then draws the player span in two colors:
  - **Green** (configurable: `notebeam_player_segment_match_color`) for portions that overlap a planned span.
  - **Semi-transparent red** (configurable: `notebeam_player_miss_color`, alpha = `notebeam_player_alpha * 0.72`) for portions that fall outside any planned span (started early, held late, or wrong timing).
- Unmatched planned spans remain in their planned color (grey/blue) — notifying the player they missed those notes.
- This mode applies to all notes including those belonging to embellishment groups. In v2, embellishment notes are treated the same as melody notes.

**Version 3 — Segmented + embellishment grace overlay**
- Everything from v2, plus embellishment-aware grace note coloring.
- `gv_classify_player_spans_for_emb()` is called to classify each player span against the precomputed embellishment groups.
- Grace notes (all notes in an embellishment group except the final target note) that were played in the correct order within the embellishment timing window get a special **transparent green overlay** drawn on top of the v2 coloring.
  - Transparency alpha: `notebeam_player_emb_overlay_alpha` (default 0.55).
  - Color: `notebeam_player_emb_match_color`.
- The target note of the embellishment group follows v2 coloring (green overlap / red overhang).
- Only notes that belong to a `note_set{}` of an embellishment group are considered by the emb classifier; all other notes fall through to v2 split-rendering.

**6.6.3 Key Functions and Locations**

All functions are in `scripts/scr_game_viz/scr_game_viz.gml`.

| Function | Approx. Line | Purpose |
|---|---|---|
| `gv_build_planned_spans(_events)` | ~38 | Converts event list → `planned_spans[]` structs |
| `gv_bind_timeline_on_tune_start(...)` | ~119 | Entry point at tune start; builds spans + emb groups |
| `gv_build_emb_groups(_planned_spans)` | ~230 | Builds `emb_groups[]` with grace sequences + `note_set{}` |
| `gv_time_to_x(...)` | ~590 | Linear ms → pixel mapping |
| `gv_player_span_timing_state(...)` | ~595 | Returns 0/1/2 for miss / bleed / exact timing |
| `gv_collect_lane_overlap_segments(...)` | ~645 | Returns sorted merged overlap segments between a player span and all planned spans on the same lane |
| `gv_draw_split_normal_player_beam(...)` | ~709 | Draws a player beam split into green (overlap) + semi-transparent red (overhang) segments |
| `gv_classify_player_spans_for_emb(...)` | ~1030 | Classifies player spans against emb groups; returns `player_states[]`, `pending_states{}`, `player_grace_overlay[]`, `pending_grace_overlay{}` |
| `gv_draw_notebeam_canvas(...)` | ~1720 | Main per-frame draw function |

**Key lines inside `gv_draw_notebeam_canvas`:**
- Mode variables (`compare_version`, `use_segmented_compare`, `use_embellishment_mode`): ~lines 1848–1852
- Overlap gate + emb classify call: ~lines 1894–1920
- Planned spans draw loop: ~lines 1930–1960
- `player_in` draw loop with mode branches: ~lines 1970–2040
- `pending_player` draw loop with mode branches: ~lines 2060–2130

**6.6.4 Embellishment Group Structure**

`global.timeline_state.emb_groups[]` is an array of structs built by `gv_build_emb_groups`. Each struct has:
```
{
  note_set: {},          // struct used as a set — keys are note names; O(1) membership test
  spans: [],             // array of planned_span structs in group order (grace notes first, target last)
  window_start_ms: real, // start of allowable timing window (start of first grace note span)
  window_end_ms: real    // end of allowable timing window (end of target note span)
}
```
The last span in `spans[]` is always the target note; all preceding spans are grace notes.

**6.6.5 Config Keys Reference**

All keys live in `global.timeline_cfg` set in `objects/obj_game_viz/Create_0.gml`.

| Key | Default | Description |
|---|---|---|
| `notebeam_compare_version` | `1` | Rendering mode: 1=basic overlay, 2=segmented green/red, 3=+embellishment grace overlay |
| `notebeam_player_overlap_colorize` | `true` | Master enable for any player-vs-planned color comparison (v2/v3 require this true) |
| `notebeam_player_segment_match_color` | green (60,155,70) | Color for overlapping portion of player beam in v2/v3 |
| `notebeam_player_miss_color` | dark red (112,46,46) | Color for non-overlapping (early/late) portion of player beam |
| `notebeam_player_alpha` | `0.88` | Base alpha for player beams (red overhang drawn at `* 0.72`) |
| `notebeam_player_emb_match_color` | green (60,155,70) | Color for v3 embellishment grace overlay tint |
| `notebeam_player_emb_overlay_alpha` | `0.55` | Alpha for v3 embellishment grace overlay |
| `notebeam_player_timing_slack_ms` | `50` | Ms tolerance at note boundaries for overlap detection |
| `notebeam_player_color` | light grey | Fallback player beam color (used in v1, or when overlap colorize is off) |
| `notebeam_planned_color` | blue-grey | Planned span beam color |
| `notebeam_planned_alpha` | `0.75` | Planned span alpha |
| `notebeam_player_bleed_alpha` | `0.38` | Alpha for player spans that slightly miss planned timing (v1 timing state "bleed") |
| `notebeam_line_width` | `42` | Beam height in pixels |
| `notebeam_lane_row_height_px` | `42` | Height of each note lane row |
| `notebeam_lane_row_gap_px` | `20` | Vertical gap between note lane rows |

**6.6.6 How to Modify or Extend**

- **Change the overlap color or transparency:** Edit `notebeam_player_segment_match_color`, `notebeam_player_miss_color`, and `notebeam_player_alpha` (red overhang will auto-adjust as `_alpha * 0.72`) in `Create_0.gml`.
- **Add a new rendering version (e.g., v4):** Follow the pattern in `gv_draw_notebeam_canvas` — add a new `use_X_mode` boolean derived from `compare_version`, then add a new branch in the `player_in` and `pending_player` draw loops.
- **Change what counts as a grace note in v3:** Edit `gv_classify_player_spans_for_emb` — the line `var is_grace_overlay = (matched_at >= 0) && (matched_at < (n_exp - 1)) && (state == 2);` controls this. `n_exp - 1` means "all notes except the last (target) note in the group".
- **Adjust embellishment window tolerance:** Modify `window_start_ms` / `window_end_ms` logic in `gv_build_emb_groups`, or add a configurable slack key similar to `notebeam_player_timing_slack_ms`.
- **Debug emb groups at runtime:** After `gv_bind_timeline_on_tune_start`, add `show_debug_message(string(array_length(global.timeline_state.emb_groups)))` to confirm groups are being built.
- **Debug split segments:** Trace `gv_collect_lane_overlap_segments` output for a specific player span to verify overlap ranges are correct.

**6.6.7 Post-Play Alternating Beat Bands (implemented)**

To improve readability over busy background art, the notebeam canvas now supports alternating translucent beat bands in review mode.

Behavior:
- Bands are drawn between consecutive beat markers (one band per beat interval).
- Bands alternate even/odd styling by global beat index.
- Bands render behind planned/player beams so note content remains readable.
- Bands are only drawn when playback is complete (`global.timeline_state.playback_complete == true`).
- During live playback, this feature does not draw and adds no runtime visual cost.

Runtime draw function:
- `gv_draw_notebeam_beat_boxes(...)` in `scripts/scr_game_viz/scr_game_viz.gml`
- Called from `gv_draw_notebeam_canvas(...)` only when `review_split_beams` is enabled.

Config keys (source of truth):
- `notebeam_beat_box_even_color`
- `notebeam_beat_box_odd_color`
- `notebeam_beat_box_even_alpha`
- `notebeam_beat_box_odd_alpha`

These values are defined in `global.timeline_cfg` in `objects/obj_game_viz/Create_0.gml`.
Important: values in `gv_draw_notebeam_beat_boxes` are fallback defaults only and are ignored whenever the config keys above exist.

Current tuned defaults:
- `notebeam_beat_box_even_color: make_color_rgb(245, 245, 245)`
- `notebeam_beat_box_odd_color: make_color_rgb(35, 35, 35)`
- `notebeam_beat_box_even_alpha: 0.12`
- `notebeam_beat_box_odd_alpha: 0.28`

Contrast tuning guidance:
- Increase distinction by widening both color and alpha separation (light even band + dark odd band works best on tartan).
- If bands look washed out by history overlays, lower `notebeam_history_band_alpha` in the same config block.

Master toggle globals:
- `global.show_review_beat_bands` enables/disables the alternating post-play beat bands.
- `global.show_review_emb_boxes` enables/disables the embellishment window highlight boxes.
- These globals are initialized in `objects/obj_game_controller/Create_0.gml`.
- These are master on/off switches intended for future UI wiring.
- Visual style and color tuning still live in `global.timeline_cfg` in `objects/obj_game_viz/Create_0.gml`.

**6.6.8 Post-Play Embellishment Window Boxes (implemented)**

To make planned embellishment groups easier to read, the notebeam canvas now supports a boxed highlight for each full embellishment window.

Behavior:
- Each box covers the full embellishment time window: grace-note start through target-note end.
- Each box expands vertically to include all note lanes used by that embellishment plus its target note.
- Boxes render over beat bands but under planned/player note beams.
- Boxes only render for groups with a confirmed target note.
- Boxes can be limited to review mode and can also be master-toggled off globally.

Runtime draw function:
- `gv_draw_notebeam_emb_group_boxes(...)` in `scripts/scr_game_viz/scr_game_viz.gml`

Config keys:
- `notebeam_emb_box_enabled`
- `notebeam_emb_box_review_only`
- `notebeam_emb_box_fill_color`
- `notebeam_emb_box_fill_alpha`
- `notebeam_emb_box_border_color`
- `notebeam_emb_box_border_alpha`
- `notebeam_emb_box_lane_padding_px`
- `notebeam_emb_box_time_padding_ms`

**6.6.9 Centralized Visual Tuning Controls (implemented)**

Visual tuning for both notebeam history markers and tune-structure measure boxes is now centralized in one place:
- `objects/obj_game_viz/Create_0.gml` (inside `global.timeline_cfg`)

This means color/alpha adjustments no longer require editing draw logic in multiple functions.

Notebeam prior run marker controls (start/end yellow markers):
- `notebeam_history_start_color`
- `notebeam_history_end_color`
- `notebeam_history_start_alpha`
- `notebeam_history_end_alpha`

Current tuned defaults:
- `notebeam_history_start_color: make_color_rgb(255, 235, 70)`
- `notebeam_history_end_color: make_color_rgb(255, 218, 40)`
- `notebeam_history_start_alpha: 0.52`
- `notebeam_history_end_alpha: 0.95`

Tune-structure panel controls (measure boxes + separator line):
- `tune_structure_current_base_color`
- `tune_structure_current_base_alpha`
- `tune_structure_current_overlay_color`
- `tune_structure_current_overlay_alpha`
- `tune_structure_played_fill_color`
- `tune_structure_played_fill_alpha`
- `tune_structure_border_color`
- `tune_structure_border_alpha`
- `tune_structure_current_border_color`
- `tune_structure_current_border_alpha`
- `tune_structure_part_separator_color`
- `tune_structure_part_separator_alpha`

Current tuned defaults:
- `tune_structure_played_fill_alpha: 0.72` (played dark boxes more visible)
- `tune_structure_border_alpha: 0.58`
- `tune_structure_current_base_alpha: 0.55`
- `tune_structure_current_overlay_alpha: 0.35`

Implementation note:
- `scripts/scr_game_viz/scr_game_viz.gml` now reads these values from `global.timeline_cfg` inside `gv_draw_tune_structure_panel(...)`.
- Hardcoded visual constants were replaced with config lookups + fallback defaults.
- Result: one-stop runtime tuning for gameviz appearance.

---

**7. Post Gameplay Analytics**
1. After playback, the player can scroll forward/back in time or select a measure in Panel D to jump to that point.
2. Review mode shows tune-as-played and player performance (MIDI in), impacting note beams, score, and event log views.
3. Events and performance include additional cues, such as color coding.
4. Post-processing expands runtime events into a performance log exported as JSON.
5. Additional analysis is currently done in Excel as a prototype for future in-game analysis.
6. Future state: show current performance against prior performances and averages.

**8. Final Architecture Overview**
Core Systems
• 	Tune ingestion pipeline (ABC → Excel → JSON)
• 	Tune loader + metadata manager
• 	Preprocessing engine (play array builder)


⚠️ **Important architectural constraint:** Do NOT use ds_maps, ds_lists, or other GameMaker data structures. Use arrays and structs only. This keeps the code simpler, avoids memory management complexity, and makes the code more predictable.
• 	Playback engine (time‑source driven)
• 	MIDI input manager
• 	MIDI output manager
• 	Canonical note normalization + chanter profile mapping (see Sections 6.4 and 6.5)
• 	Scoring engine (real‑time + post‑play judges)
• 	Analysis engine (trend tracking, detailed breakdowns)
• 	Data persistence (settings, history, preferences)
UI Architecture
• 	Modular window system using GameMaker UI layers
• 	Flex‑panel layout engine for dynamic UI
• 	Windows for:
• 	Main menu
• 	Tune picker
• 	Settings
• 	Metronome
• 	Parts selection
• 	Play Room
• 	Analysis
Controllers
• 	 — tune data model
• 	 — playback engine
• 	 — MIDI I/O
• 	 — window + layout controller
• 	 — scoring + judge orchestration

**9. Scoring & Analysis Vision**
Real‑Time Scoring
• 	Basic correctness (right note near the right time)
• 	Immediate feedback indicators
Post‑Play Judges
Each judge focuses on a single musical dimension:
• 	Phantom notes / false fingering
• 	Embellishment timing accuracy
• 	Millisecond‑level note correctness
• 	Beat‑level timing consistency
• 	Phrase‑level rhythmic shape
• 	Overall tune accuracy score
Long‑Term Tracking
• 	Store play logs
• 	Track trends across sessions
• 	Identify strengths and weaknesses
• 	Provide practice recommendations (future)

10. Long‑Term Extensibility
The system is designed to support future enhancements:
• 	Additional instruments
• 	Custom scoring profiles
• 	Cloud sync of player history
• 	Exportable analysis reports
• 	Multiplayer / ensemble mode
• 	Backing tracks with other instruments
• 	AI‑assisted practice suggestions

11. Definition of Done
The project is “complete” when a player can:
• 	Load any tune from the library
• 	Configure all relevant musical and playback options
• 	Play along with synchronized audio and visual feedback
• 	Receive detailed, accurate scoring and analysis
• 	Track improvement over time
• 	Use the tool as a reliable, enjoyable part of their practice routine

📋 Roadmap
This roadmap is divided into Backlog, In Progress, and Done.
Move items between sections as development progresses.

Backlog (Planned but Not Started)
Tune & Data Pipeline
• 	Full metadata support in JSON
• 	Ornament expansion rules (default + tune‑type + user preferences)
• 	Multi‑tune set support
• 	Transition events (rolls, initial E, tune linking)
UI
• 	Scrollable tune picker
• 	Tune filtering, sorting, and tabs
• 	Parts selection window
• 	Metronome configuration window
• 	Analysis window
• 	UI theme system
• 	Dynamic flex‑panel improvements (scrolling, resizing)
Playback & Audio
• 	Multi‑part playback (pipes, harmonies, drums)
• 	Backing tracks
• 	Per‑part mute/solo controls
Scoring & Analysis
• 	Phantom note judge
• 	Embellishment timing judge
• 	Millisecond correctness judge
• 	Phrase‑level rhythm judge
• 	Trend tracking
• 	Exportable analysis reports
Persistence
• 	Save/load user settings
• 	Save play logs
• 	Save scoring history

In Progress
• 	JSON loader rewrite
• 	Play array design
• 	UI flex panel improvements
• 	Tune picker refactor
• 	Controller architecture cleanup

Done
• 	Git workflow fixed
• 	Workspace map created
• 	Controller architecture documented
• 	Basic tune loader working
• 	Project plan vision drafted

🔗 Integration Notes
These notes ensure new systems integrate cleanly with the existing architecture.
Tune Loader
• 	Must normalize events before preprocessing
• 	Must support metadata wrapper in future
• 	Must validate event structure
Preprocessing
• 	Must output a stable  schema
• 	Must handle all parts (pipes, drums, metronome, transitions)
• 	Must precompute all timing and note‑off events
Playback Engine
• 	Must be decoupled from UI
• 	Must use a deterministic time‑source
• 	Must support multiple tracks
UI
• 	All windows must use flex panels
• 	UI logic must be centralized in button scripts or a UI manager
• 	Windows should be modular and independent
Scoring
• 	Judges must operate on logged events, not raw MIDI
• 	Judges must be modular and pluggable
• 	Scoring output must be structured for visualization

🧱 Guiding Principles
• 	Data‑driven: tunes, embellishments, and scoring rules live in external data
• 	Modular controllers: tune, player, UI, MIDI, scoring are separate
• 	Deterministic playback: preprocessing ensures millisecond‑accurate timing
• 	Extensible: new tune types, embellishments, or judges can be added easily
• 	UI consistency: all windows use flex panels and shared components
• 	Maintainability: scripts and objects follow clear naming and separation

🎉 End of Project Plan
This document defines the destination, the architecture, and the path forward.
Your  now becomes the “current state,” while this plan becomes the “future state.”
