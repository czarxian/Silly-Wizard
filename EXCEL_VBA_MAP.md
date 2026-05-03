# Excel VBA Pipeline Map

Reference document for the three VBA modules in `Silly Wizard Work.xlsm`.
Workspace copies of the VBA source are in `scripts/Excel - *.txt` (read-only mirrors; actual code lives in the workbook).

---

## 1. Pipeline Overview

```
ABC notation text
      │
      ▼
  [modParseABC]
  ParseAllParts()
      │  tokenise → expand repeats → write events → recalculate positions → renumber
      ▼
  Event grid (rows 51+, 23 columns) on each tune sheet
      │
      ├──► ExportEventsToJSON()        → datafiles/tunes/<TuneName>/tune.json
      ├──► ExportEmbellishmentsToJSON() → datafiles/embellishments.json
      └──► ExportMeasureImages()        → per-measure PNG files (optional)

  [modTuneExport]
  ExportCurrentTuneMetadata()
      │
      └──► performances/<TuneName>/<TuneName>_metadata.xlsx   (+ any JSON)

  [modTuneLoader]
  LoadTuneForAnalysis()
      │  reads metadata + performance CSV
      ├──► RebuildBeatStructure()
      ├──► RebuildTunePerformance()
      ├──► RebuildPlayerPerformance()
      └──► BuildMelodyMatchingSheet()
```

GameMaker reads `.json` files from `datafiles/` at runtime via `scr_tune_load_json`.

---

## 2. Normal Run Sequence

### Authoring a new tune (or updating ABC)
1. Open or create the tune sheet in the workbook.
2. Fill in the **Parts Table** (cols G/H/I, rows 2–25) — see §6.
3. **Run `ParseAllParts`** (modParseABC) → event grid rebuilt on the sheet.
4. Review the grid; optionally run `InferBrokenRhythms` if broken-rhythm detection is needed.
5. **Run `ExportTuneAll`** (modParseABC) → exports events JSON + embellishments JSON + source ABC + expanded score ABC + images in one shot.
   - Or run each export separately: `ExportEventsToJSON`, `ExportEmbellishmentsToJSON`, `ExportMeasureImages`.

### Exporting tune metadata to the performance folder
6. **Run `ExportCurrentTuneMetadata`** (modTuneExport) → writes metadata `.xlsx` to the performances root.

### Post-session analysis
7. **Run `LoadTuneForAnalysis`** (modTuneLoader) → prompts for metadata + CSV.
8. Use `RefreshAnalysis` to re-run all analysis sheets after loading.
9. Use `BuildMelodyMatchingSheet` / `BuildCoreMelodyMatching` for match-quality review.

---

## 3. Module: `modParseABC`

**Source:** `scripts/Excel - Parse_ABC.txt` (2 178 lines)

### 3.1 Public entry points

| Sub/Function | Line | Purpose |
|---|---|---|
| `ParseAllParts()` | 93 | **MAIN.** Reads Parts Table, runs full ABC→events pipeline for all parts in order |
| `ExportEventsToJSON()` | 1578 | Exports event grid on active sheet → JSON file in tune folder |
| `InferBrokenRhythms()` | 1732 | Second-pass broken-rhythm detection (run after `ParseAllParts` if needed) |
| `ExportEmbellishmentsToJSON()` | 1803 | Exports Embellishments Library sheet → `datafiles/embellishments.json` |
| `ExportMeasureImages()` | 1865 | Exports PNG per measure (requires abc2svg/abcjs on PATH) |
| `ExportTuneAll()` | 1975 | Runs full pipeline: `ExportEventsToJSON_ToFile` + source ABC write + expanded score ABC build + `ExportMeasureImages` |

### 3.2 Private pipeline stages (called in order by `ParseAllParts`)

```
CalculateRhythmicConstants
    └─ sets TimeSigNum/Den, UnitsPerBeat, BeatsPerMeasure, UnitsPerMeasure
DetectPickup
    └─ sets PickupOffsetUnits, PickupDetected
PrepareABCForVoice
TokenizeABC
    └─ produces token array from ABC text
ExpandRepeats
    └─ flattens repeat symbols into linear token list
BuildExpandedABCForScore
    ├─ extracts header lines from full ABC
    ├─ tokenizes body and expands repeats
    └─ serializes expanded tokens into score-only ABC for image rendering
WriteEventsFromTokens
    └─ appends rows to event grid; calls WriteNoteRow / WriteBarRow / WriteEmbellishmentRow
RecalculatePositions
    └─ fills COL_START_MS / COL_END_MS / COL_TEMPO_BPM
PopulateEmbellishmentTargets
    └─ fills COL_EMBELLISH_TARGET using lookahead
RenumberEventIds
    └─ sequential COL_EVENT_ID from AppendStartRow
```

Additional private helpers: `TagSectionEvents`, `GetMetadataValue`, `ParseFraction`, `ClearEventRows`, `IsVoiceHeaderLine`, `ParseVoiceId`, `IsMetadataHeaderLine`, `BuildMeasureMapFromFlat`, `GetNoteDurationUnits`, `GetNoteLetterOnly`, `HasBrokenGreater`, `HasBrokenLess`, `FindPrecedingNote`, `FindTargetNote`, `ParseABCMetadata`, `ClearABCHeaderMappedMetadata`, `WriteMetadataValue`, `ParseMeterToTimeSig`, `InferStructuralMetadata`, `BuildFullABC`, `ExportEventsToJSON_ToFile`, `BuildMeasureMap`, `CleanTuneName`.

### 3.3 Module-level state variables

| Variable | Description |
|---|---|
| `TimeSigNum` / `TimeSigDen` | Parsed time signature numerator / denominator |
| `UnitNoteFraction` | ABC unit note length (e.g. 1/8) |
| `UnitsPerBeat` | Rhythmic units per beat |
| `BeatsPerMeasure` | Beats per bar |
| `UnitsPerMeasure` | Total rhythmic units per bar |
| `PickupOffsetUnits` | Units in the pickup bar (0 if none) |
| `PickupDetected` | Boolean — whether a pickup was found |
| `AppendStartRow` | First sheet row to write on for the current part |
| `ActiveVoice` | Voice label for the current pass (e.g. `"pipes_melody"`) |

### 3.4 Event grid column constants

| Constant | Col | JSON field |
|---|---|---|
| `COL_EVENT_ID` | 1 | `event_ID` |
| `COL_TYPE` | 2 | `type` |
| `COL_STRUCTURE` | 3 | `structure` |
| `COL_PART` | 4 | `part` |
| `COL_MEASURE` | 5 | `measure` |
| `COL_BEAT` | 6 | `beat` |
| `COL_DIVISION` | 7 | `division` |
| `COL_PHRASE` | 8 | `phrase` |
| `COL_NOTE_LETTER` | 9 | `letter` |
| `COL_NOTE_MIDI` | 10 | `midi_value` |
| `COL_WRITTEN_UNITS` | 11 | `written` |
| `COL_ADJUSTED_UNITS` | 12 | `adjusted` |
| `COL_TOTAL_UNITS` | 13 | `total_units` |
| `COL_EMBELLISH_PRECEDING` | 14 | `preceding_note` |
| `COL_EMBELLISH_LITERAL` | 15 | `literal` |
| `COL_EMBELLISH_TARGET` | 16 | `target_note` |
| `COL_EMBELLISH_ALT_ANCHOR` | 17 | `alt_anchor` |
| `COL_EMBELLISH_ALT_TIMING` | 18 | `alt_timing` |
| `COL_BROKEN_DIR` | 19 | `broken_dir` |
| `COL_START_MS` | 20 | `start_time_ms` |
| `COL_END_MS` | 21 | `end_time_ms` |
| `COL_TEMPO_BPM` | 22 | `tempo_bpm` |
| `COL_VOICE` | 23 | `voice` |

Header row: **50**. First data row: **51**.

---

## 4. Module: `modTuneExport`

**Source:** `scripts/Excel - TuneExport.txt` (771 lines)

### 4.1 Public entry points

| Sub | Line | Purpose |
|---|---|---|
| `ExportCurrentTuneMetadata()` | 12 | **MAIN.** Exports active sheet → metadata `.xlsx` in performance folder |
| `ExportAllTuneMetadata()` | 114 | Batch export of all tune sheets |
| `ShowExportConfiguration()` | 246 | Diagnostic: prints current path config to debug output |
| `BuildCoreMelodyMatching()` | 287 | Builds/updates the core melody-matching analysis sheet |

### 4.2 Private helpers

`CleanFileName`, `GetTuneTitleFromSheet`, `FindNoteAheadMM`, `WriteMatchRow`, `UpdateMatchedEvents`

### 4.3 Config

```vba
Const PERFORMANCE_ROOT = "C:\Users\xian\AppData\Local\Silly_Wizard\datafiles\performances"
```

Set this constant if the performances folder is moved.

---

## 5. Module: `modTuneLoader`

**Source:** `scripts/Excel - Performance_Analysis.txt` (1 825 lines)

### 5.1 Public entry points

| Sub/Function | Line | Purpose |
|---|---|---|
| `GetConfigValue(settingName)` | 12 | Reads a value from the "VBA Setup" sheet by setting name |
| `LoadTuneForAnalysis()` | 131 | **MAIN.** Loads tune metadata + performance CSV; triggers rebuild |
| `FindTuneMetadataFile(...)` | 188 | Auto-detects tune metadata file in a performance folder |
| `LoadTuneMetadataFromFile(...)` | 216 | Loads tune metadata from a file path |
| `LoadTuneMetadataFromMaster(...)` | 265 | Loads tune metadata from the master workbook |
| `LoadPerformanceData(...)` | 339 | Loads performance CSV into the Performance Data sheet |
| `RebuildBeatStructure()` | 521 | Rebuilds the Beat Structure sheet |
| `RebuildTunePerformance()` | 616 | Rebuilds the Tune Performance sheet (Channel 2 only) |
| `RebuildPlayerPerformance()` | 733 | Rebuilds the Player Performance sheet |
| `BuildMelodyMatchingSheet()` | 877 | Builds the Melody Matching analysis sheet |
| `BuildCoreMelodyMatching()` | 1352 | Builds core melody-matching table with matched_event columns |
| `BrowseForTuneMetadata()` | 1243 | File picker for tune metadata |
| `BrowseForPerformanceCSV()` | 1260 | File picker for performance CSV |
| `RefreshAnalysis()` | 1292 | Re-runs all analysis rebuild steps |
| `ListAvailableSessions()` | 1312 | Lists available session files in the performance folder |

### 5.2 Private helpers

`SelectPerformanceFile`, `ImportCSVToSheet`, `CreatePerformanceDataTable`, `CalculateDuration`, `FindTuneEventByID`, `GetTuneTimestamp`, `GetTuneDuration`, `GetTuneNoteLetter`, `AssignMeasure`, `BuildMeasureSummary`, `GetNotesForMeasure`, `FindNoteAhead`, `WriteMatchingRow`, `UpdateMatchedEventColumns`

---

## 6. Sheet Conventions

### Parts Table (cols G / H / I, rows 2–25)

| Col G | Col H | Col I |
|---|---|---|
| Part type label | Voice/instrument tag (optional) | ABC text for this part |

**Recognised part type labels:**

| Label | Behaviour |
|---|---|
| `metadata` | Reads ABC headers only; no events written |
| `melody` | Clears event table, then writes events with voice `"pipes_melody"` |
| `harmony1` | Appends events with voice `"pipes_harmony1"` |
| `harmony2` | Appends events with voice `"pipes_harmony2"` |
| `transition_tail` | Appends transition tail events |
| `transition_head` | Appends transition head events |
| `bridge` | Appends bridge events |
| *(any other)* | Appended with col-I value as voice label |

### Required sheet names (expected by VBA)
- `"VBA Setup"` — config key/value pairs for modTuneLoader (cells B5:B8 = values)
- One sheet per tune (name = tune title, used by `ExportCurrentTuneMetadata`)
- `"Embellishments Library"` — source for `ExportEmbellishmentsToJSON`
- `"Beat Structure"`, `"Tune Performance"`, `"Player Performance"`, `"Melody Matching"`, `"Performance Data"` — analysis sheets managed by modTuneLoader

---

## 7. Output File Conventions

| File | Location | Written by |
|---|---|---|
| `tune.json` (events) | `datafiles/tunes/<TuneName>/` | `ExportEventsToJSON` |
| `embellishments.json` | `datafiles/` | `ExportEmbellishmentsToJSON` |
| Measure PNG images | `datafiles/tunes/<TuneName>/images/` | `ExportMeasureImages` |
| `<TuneName>_metadata.xlsx` | `<PERFORMANCE_ROOT>/<TuneName>/` | `ExportCurrentTuneMetadata` |
| Performance CSV | `<PERFORMANCE_ROOT>/<TuneName>/` | written by GameMaker; read back by `LoadPerformanceData` |

`<TuneName>` is derived by `CleanTuneName()` / `CleanFileName()` — strips illegal filename characters and normalises spaces.

---

## 8. Config Surface

### modParseABC — worksheet constants (top of module)
```vba
Const HEADER_ROW = 50          ' Row containing column headers
Const FIRST_DATA_ROW = 51      ' First event data row
Const PART_TABLE_TYPE_COL  = 7 ' Col G — part type label
Const PART_TABLE_VOICE_COL = 8 ' Col H — voice compound label (e.g. "pipes_melody", "pipes_harmony1")
Const PART_TABLE_ABC_COL   = 9 ' Col I — ABC text
Const PART_TABLE_FIRST_ROW = 2
Const PART_TABLE_MAX_ROW   = 25
```
Plus all 23 `COL_*` column constants — see §3.4.

### modTuneExport — root path
```vba
Const PERFORMANCE_ROOT = "C:\Users\xian\AppData\Local\Silly_Wizard\datafiles\performances"
```

### modTuneLoader — "VBA Setup" sheet
Cells A5:A8 hold setting names; adjacent column B holds values. Accessed via `GetConfigValue(settingName As String)`.

Typical settings stored here:
- Performance root folder path
- Master workbook path
- Default tune folder

To add a new config value: add a row to the VBA Setup sheet in the workbook; no code change needed.
