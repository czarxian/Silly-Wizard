🎯 Vision (End State)
**1. Purpose — Why this exists**
This project is a music‑training tool designed to give bagpipers objective, data‑driven feedback on timing, embellishment execution, and overall musical accuracy. Traditional practice relies heavily on subjective listening and instructor feedback; this tool provides measurable, repeatable analysis similar to rhythm‑game systems, but grounded in real bagpipe technique and musical structure.
The goal is to help pipers improve faster, practice more effectively, and understand their playing with unprecedented clarity.

**2. High‑Level Experience**
The finished system allows a player to:
• 	Select a tune from a rich, searchable library
• 	Configure tempo, metronome patterns, parts, and playback options
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
• 	Multi‑tune sets with seamless linking
Tunes originate from ABC notation, are edited in Excel, and exported as JSON containing metadata and event lists. Embellishments are represented as events and expanded into detailed timing sequences according to user‑configurable rules.

**4. Tune Pipeline (End‑State)**

`Key capabilities:`
• 	JSON includes metadata, parts, embellishments, and structural events
• 	Embellishments expand according to tune type, user preferences, and style rules
• 	Preprocessing converts musical durations into millisecond‑accurate timestamps
• 	All parts (pipes, drums, metronome, transitions) merge into a unified event stream
This ensures deterministic, real‑time playback with no per‑frame computation overhead.

**5. Gameplay Loop**
1. 	Select tune from a scrollable, sortable, filterable library
2. 	Configure options (tempo, metronome, parts, embellishment rules, transitions)
3. 	Preprocess into a unified play array
4. 	Enter Play Room
5. 	Play along with real‑time visual and audio feedback
6. 	Log MIDI input for scoring and analysis
7. 	Review results in a post‑play analysis window
8. 	Track progress over time

**6. Final Architecture Overview**
Core Systems
• 	Tune ingestion pipeline (ABC → Excel → JSON)
• 	Tune loader + metadata manager
• 	Preprocessing engine (play array builder)

⚠️ **Important architectural constraint:** Do NOT use ds_maps, ds_lists, or other GameMaker data structures. Use arrays and structs only. This keeps the code simpler, avoids memory management complexity, and makes the code more predictable.
• 	Playback engine (time‑source driven)
• 	MIDI input manager
• 	MIDI output manager
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

**7. Scoring & Analysis Vision**
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

8. Long‑Term Extensibility
The system is designed to support future enhancements:
• 	Additional instruments
• 	Custom scoring profiles
• 	Cloud sync of player history
• 	Exportable analysis reports
• 	Multiplayer / ensemble mode
• 	Backing tracks with other instruments
• 	AI‑assisted practice suggestions

9. Definition of Done
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
