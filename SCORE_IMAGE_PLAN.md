# Score Image Pipeline — Implementation Checklist

**Last updated:** 2026-04-23  
**Status:** Planning. None of the milestones below are complete.

---

## Pipeline overview (current state)

### Non-negotiable invariant (2026-05)

- The score export path must emit **one image per playback measure**.
- Export must **not deduplicate** repeated or visually identical measures.
- `playback_to_image` for normal bundles must be identity (`[0, 1, 2, ...]`) so runtime measure-seq and sprite index stay 1:1.
- If two playback measures look the same, they are still exported as separate images to preserve stable timeline placement.

```
ABC text (Excel sheet)
    │ ExportTuneAll (VBA)
    ├─► ExportEventsToJSON     → datafiles/tunes/<Tune>/tune.json
    ├─► writes .abc file       → datafiles/tunes/<Tune>/<Tune>.abc
    └─► ExportMeasureImages    → node abc_to_png.js → score/m001.png ... mNNN.png
                                                    → score/score_images.json
                                                       {tune, images:[...]}
         BuildMeasureMap (disabled) → would patch score_images.json with measure_map[]

Runtime (GML)
    scr_score_sprites_load(_filename)
        reads score/score_images.json
        sprite_add()s each PNG → global.score_lane_sprites[]
        reads measure_map[] → global.score_measure_map[]
    gv_draw_timeline_canvas_overlay  (disabled with "false && ...")
        uses global.score_lane_sprites + global.score_measure_map
        uses gv_time_to_x for scroll alignment
```

---

## Root causes of current problems

| Problem | Root cause |
|---|---|
| measure_map inaccurate | `abc_to_png.js` tokenises ABC naively (splits on `\|`) — doesn't expand repeats or first/second endings. Its image count doesn't match VBA's expanded measure count |
| Staff vertical inconsistency | `abcjs` re-renders each measure from scratch with identical padding settings, but staff height varies per measure content; no normalisation step |
| Margin/height variation | SVG `height` is content-driven by `abcjs`; `resvg --width` only pins width; height varies |
| Notes not beat-proportional | `abcjs` uses proportional-notation glyph spacing, not time-proportional spacing. No beat anchor data is emitted |
| No beat sync on scroll | Runtime scroll uses measure start/end ms from event timing, but stretches the image uniformly — no internal beat reference points |

---

## Milestone A — Get measure_map right

**Goal:** every playback measure resolves to the correct physical image without guessing.

### A-1  Understand the physical-measure numbering used by abc_to_png.js

The js script produces one image per "measure" found by its naive splitter. Count them for a known tune:

- Verification test: `Scotland the Brave` has 17 images. Manually count physical measures in the ABC source. Do they match? (Expected: yes for simple tunes, wrong for tunes with first/second endings.)
- Record the discrepancy type in this doc before writing any code.

### A-2  Re-enable `BuildMeasureMap` — the token-level approach is already correct

The existing `BuildMeasureMapFromFlat` (called by `BuildMeasureMap`) **already handles voltas correctly**. Here is why:

- `TagTokensWithPhysMeasure` assigns a `phys_measure` tag (element `tk(3)`) to every token in the ABC source *before* repeat expansion.
- `ExpandRepeats` duplicates tokens for each pass through a repeat, carrying the `phys_measure` tag along.
- `BuildMeasureMapFromFlat` walks the post-expansion flat token list and reads `tk(3)` for each measure — so it sees the correct physical image index for every expanded measure regardless of volta structure.

The event grid is the **wrong source** for this map: events don't carry a volta-pass tag and their measure numbers are already expanded. The token-level pipeline is the right source and already exists.

**Action: simply re-enable the call in `ExportTuneAll`:**

In `ExportTuneAll`, Step 4, change:
```vba
    ' ---- Step 4: Patch score_images.json with measure_map (disabled) ----
    ' Call BuildMeasureMap(abcFile, scoreDir)
```
to:
```vba
    ' ---- Step 4: Patch score_images.json with measure_map ----
    Call BuildMeasureMap(abcFile, scoreDir)
```

**Validation check** — add this Debug.Print at the end of `BuildMeasureMapFromFlat`:
```vba
Dim imgCount As Long
' Count images[] array in manifest for comparison
' (simple: count "m0" occurrences as a proxy)
Dim physCount As Long
physCount = 0
Dim tmpPos As Long: tmpPos = 1
Do
    tmpPos = InStr(tmpPos, manifestRaw, "\"m")
    If tmpPos = 0 Then Exit Do
    physCount = physCount + 1
    tmpPos = tmpPos + 1
Loop
Debug.Print "BuildMeasureMapFromFlat: expandedCount=" & expandedMap.Count & ", physImageCount=" & physCount & ", map=[" & mapArr & "]"
```
The `expandedCount` should equal the game's playable measure count. The `physImageCount` should equal the number of PNGs in the `score/` folder.

### A-3  Verify physical measure count matches abc_to_png.js image count

The one remaining risk: does `abc_to_png.js`'s naive barline splitter count the same number of physical measures as `TagTokensWithPhysMeasure`?

Potential mismatches:
- `abc_to_png.js` splits on every `|` character including `|:` and `:|`. The current regex `/(\|\]|\[\||\|\||\|:|:\||\|)/` may consume the colon side of a repeat barline as a separate token, creating a spurious empty measure.
- `TagTokensWithPhysMeasure` runs the full VBA tokeniser which correctly classifies `|:` and `:|` as single structural tokens.

**Verification procedure (do before coding):**
1. Run `ExportMeasureImages` on *Scotland the Brave*.
2. Count the PNGs in `score/` (should be 17 per current manifest).
3. In VBA: add a temporary Debug.Print in `BuildMeasureMap` to print `flatTagged.Count` and the distinct `phys_measure` values.
4. Confirm both counts agree. If not, the mismatch points to the specific barline token the js script miscounts.

If there is a mismatch, fix it in `abc_to_png.js` by replacing the naive `|` split with a proper ABC barline regex that matches `|:` and `:|` as single tokens before splitting on plain `|`.

### A-4  Acceptance check for A

For each test tune below, after re-running `ExportTuneAll`:
1. Print the measure_map array.
2. In the game, load the tune and confirm the first visible measure shows the correct image.
3. Advance to the repeat — confirm the first measure of the repeat shows the same image as measure 1 (i.e. map wrapped correctly).

Test tunes: Barnyards of Delgaty, Scotland the Brave, Jock Wilson's Ball (or any with first/second endings).

---

## Milestone B — Normalize image geometry

**Goal:** all images have the same staff anchor height and consistent margins, so runtime scaling is predictable.

### B-1  Extend score_images.json sidecar schema

Add per-image metadata entries. The new schema:

```json
{
  "tune": "TuneName",
  "images": ["m001.png", "m002.png"],
  "measure_map": [0, 1, 0, 1],
  "image_meta": [
    {
      "file": "m001.png",
      "width_px":  800,
      "height_px": 120,
      "staff_top_px":  12,
      "staff_bottom_px": 88,
      "content_left_px": 4,
      "content_right_px": 796
    }
  ]
}
```

Fields:
- `width_px`, `height_px` — actual PNG dimensions in pixels.
- `staff_top_px` — y pixel of the top staff line.
- `staff_bottom_px` — y pixel of the bottom staff line.
- `content_left_px`, `content_right_px` — horizontal content bbox (first notehead to last notehead).

### B-2  Extract staff geometry from SVG before converting to PNG

Modify `abc_to_png.js`. After `abcjs.renderAbc(div, snippet, ...)`, before writing SVG:

```js
// Staff top — confirmed class name (2026-04-23 live check)
const topLine = div.querySelector('.abcjs-top-line');
const staffTopPx = topLine ? parseFloat(topLine.getAttribute('y') || 0) : 0;

// Staff bottom — use all 5 .abcjs-staff-extra lines, take max y
// (.abcjs-bottom-line does NOT exist in this abcjs version)
const staffLines = [...div.querySelectorAll('.abcjs-staff-extra')];
const staffBottomPx = staffLines.length > 0
    ? Math.max(...staffLines.map(el => parseFloat(el.getAttribute('y') || 0)))
    : staffTopPx + 40;  // fallback

// Content horizontal bounds — use .abcjs-notehead (more precise than .abcjs-note)
const noteheads = [...div.querySelectorAll('.abcjs-notehead')];
let contentLeft = Infinity, contentRight = -Infinity;
noteheads.forEach(el => {
    const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
    // In jsdom, getBoundingClientRect returns zeros. Use SVG x/y transforms instead.
    // Walk up to the parent .abcjs-note group and read its transform="translate(x,y)"
    let parent = el.parentElement;
    while (parent && !parent.classList.contains('abcjs-note')) parent = parent.parentElement;
    if (parent) {
        const t = parent.getAttribute('transform') || '';
        const m = t.match(/translate\(([\d.]+)/);
        if (m) { const x = parseFloat(m[1]); contentLeft = Math.min(contentLeft, x); contentRight = Math.max(contentRight, x + 10); }
    }
});
if (!isFinite(contentLeft)) { contentLeft = 0; contentRight = svgEl.viewBox?.baseVal?.width || staffWidth; }
```

Emit all these values into the manifest's `image_meta` array for each image (see B-1 schema).

### B-3  Normalisation via SVG viewBox manipulation (before resvg conversion)

resvg has no crop flag — only `-w` / `-h`. **Normalise by rewriting the SVG `viewBox` before calling resvg**, so resvg renders the adjusted canvas directly.

Add this block in `abc_to_png.js` after extracting staff geometry and before `fs.writeFileSync(svgFile, ...)` :

```js
const STAFF_TOP_TARGET  = 20;   // px above top staff line in final image
const STAFF_BOT_PAD     = 20;   // px below bottom staff line in final image
const TOTAL_HEIGHT      = (staffBottomPx - staffTopPx) + STAFF_TOP_TARGET + STAFF_BOT_PAD;
// Desired viewBox: shift y origin so staffTopPx lands at STAFF_TOP_TARGET
const vbY      = staffTopPx - STAFF_TOP_TARGET;
const vbWidth  = parseFloat(svgEl.getAttribute('width')  || staffWidth);
const vbHeight = TOTAL_HEIGHT;
svgEl.setAttribute('viewBox', `0 ${vbY} ${vbWidth} ${vbHeight}`);
svgEl.setAttribute('width',  String(vbWidth));
svgEl.setAttribute('height', String(vbHeight));
```

Then call: `resvg --width ${staffWidth} --height ${Math.round(vbHeight)} "${svgFile}" "${pngFile}"`

This produces images of identical height with the staff at a fixed y position across all measures.
Update `image_meta` entries to record the post-normalisation `width_px` and `height_px`.

### B-4  GML: read image_meta and use staff_top_px for rendering

In `scr_score_sprites_load`:
- If `manifest.image_meta` exists, parse it and store in a new global array `global.score_lane_meta[]` — one struct per image with `{staff_top_px, staff_bottom_px, height_px}`.

In `gv_draw_timeline_canvas_overlay` (score image draw block):
- Instead of `_scale_y = staff_h / _spr_h`, compute scale from the staff height:
  ```gml
  var _meta   = (i < array_length(global.score_lane_meta)) ? global.score_lane_meta[_spr_idx] : undefined;
  var _staff_h_px = is_struct(_meta) ? (_meta.staff_bottom_px - _meta.staff_top_px) : _spr_h;
  var _scale_y    = target_staff_h / _staff_h_px;
  // Offset to align staff_top_px to the desired y position in the lane
  var _y_offset   = staff_y1 - (_meta.staff_top_px * _scale_y);
  ```

### B-5  Acceptance check for B

- Load a tune. In the debug overlay (see Milestone D), confirm all measure images show staffs aligned to the same y coordinate.
- Vary zoom (ms_behind/ms_ahead). Confirm the staff anchor position is stable regardless of horizontal stretch.

---

## Milestone C — Beat anchor alignment

**Goal:** scroll the score image so the current beat position within a measure aligns with the now-line, not just the measure start.

### C-1  Extract per-measure beat anchor x-positions from abcjs

`abcjs` assigns CSS classes including timing data to note elements. After rendering:

1. Query all elements with `.abcjs-note` on the rendered div.
2. For each note element, read:
   - Its `data-index` or `data-timing` attribute (abcjs exposes timing via the return value of `renderAbc` in its `timingCallbacks` or `animation` API — check abcjs docs for v6+ timing API).
   - Alternatively: read the `x` attribute of the notehead `<use>` element inside the note group.
3. Map each note's beat position (from the ABC token order) to its pixel x-coordinate.
4. Emit into the sidecar as `beat_anchors` per image:

```json
"image_meta": [
  {
    "file": "m001.png",
    ...
    "beat_anchors": [
      { "beat": 1,   "beat_frac": 0.0,  "x_px": 42 },
      { "beat": 1,   "beat_frac": 0.5,  "x_px": 148 },
      { "beat": 2,   "beat_frac": 0.0,  "x_px": 262 },
      { "beat": 2,   "beat_frac": 0.5,  "x_px": 379 }
    ]
  }
]
```

`beat_frac` is 0 for on-the-beat, 0.5 for the half-beat, etc. Use the tune's meter and unit note length from the header.

> **abcjs timing API \u2014 confirmed available (2026-04-23):** `renderAbc` returns an object with `engraver`, `setupEvents`, `setTiming`, `getBeatsPerMeasure`, `millisecondsPerMeasure`. Inspect `result[0].engraver` for per-note pixel positions. If that doesn't expose x-coords directly, parse the `transform="translate(x,y)"` on each `.abcjs-note` group in the SVG (same approach used in B-2 for content bbox). The `transform` parse approach is confirmed to work in this jsdom/abcjs setup.

> **Fallback (reliable regardless of API):** compute synthetic beat anchors from the event grid in VBA. For each measure, the event grid already has `COL_START_MS`, `COL_END_MS`, `COL_BEAT`, `COL_DIVISION`. Use these to compute what fraction of the measure duration each beat/division represents, then map that fraction to a linear x position across `content_left_px` to `content_right_px`. This is approximate but works reliably.

### C-2  VBA: emit beat anchors from event grid (fallback approach)

Add a sub `BuildBeatAnchorsFromEventGrid(ws, imageMetaArray)`:
- For each physical measure `p` (1..physCount), collect all events with that measure number in the **first** repeat pass.
- For each event, compute `beat_frac = (beat - 1 + (division - 1) / divisionsPerBeat) / beatsPerMeasure`.
- Map to pixel x: `x_px = content_left_px + round(beat_frac * (content_right_px - content_left_px))`.
- Add the resulting `beat_anchors[]` to the relevant entry in `image_meta`.

This VBA approach runs after `ExportMeasureImages` and before writing the final manifest. It requires `content_left_px` and `content_right_px` from Milestone B, so B must come first.

### C-3  GML: use beat anchors for scroll offset

In `gv_draw_timeline_canvas_overlay` score image draw:

1. Compute `_beat_now` = current beat within the measure at `global.timeline_state.playhead_ms`.
2. Look up the nearest beat anchor from `score_lane_meta[_spr_idx].beat_anchors`.
3. Compute the x offset within the image so the beat anchor pixel aligns with `now_x`:
   ```gml
   var _anchor_x_px  = _beat_anchor.x_px;          // notehead pixel in image coords
   var _anchor_time  = _beat_anchor_ms;             // absolute time of that beat
   // position image so _anchor_x_px * _scale_x == now_x (adjusted for anchor time)
   var _px1 = now_x - (_anchor_x_px * _scale_x)
              + gv_time_to_x(_t_start, ...);        // plus measure-start x for context
   ```
4. Use `draw_sprite_part_ext` with the adjusted `_px1` and `_part_x` offset.

### C-4  Acceptance check for C

- Play a tune with dotted rhythms (e.g. Barnyards of Delgaty). Pause at beat 2. The beat-2 notehead should appear at (or very near) the now-line.

---

## Milestone D — Debug overlay and re-enable

**Goal:** make alignment issues visible quickly; restore drawing.

### D-1  Enable the score lane

In `scr_game_viz.gml` ~line 6891, change:
```gml
if (false && staff_h > 8) {
```
to:
```gml
if (staff_h > 8) {
```
Do this only after Milestone A is complete and at least one tune's measure_map is verified correct.

### D-2  Add debug overlay toggle

Add `timeline_cfg` key: `score_debug_overlay` (default `false`).

When enabled, overlay per visible measure image:
- Measure UID text (measure index, image filename): top-left corner of the image lane.
- Horizontal tick marks at each beat anchor x position.
- Thin red horizontal line at `staff_top_px * _scale_y + staff_y1` and `staff_bottom_px * _scale_y + staff_y1`.
- Yellow vertical line at `now_x` (already drawn).

Toggle via a keybind (e.g. F5) wired to `global.timeline_cfg.score_debug_overlay` flip.

### D-3  Acceptance check for D

- Enable `score_debug_overlay`. Verify ticks align with visible noteheads. Verify staff lines are horizontal and at the same y across all visible measures. Disable overlay and confirm no visual garbage.

---

## Verification test matrix

| Tune | Structure | Checks |
|---|---|---|
| Barnyards of Delgaty | 4/4, simple 2-part repeat | map wraps, images match on both passes |
| Scotland the Brave | 4/4, first/second endings | volta handling, no crash on missing image |
| Jig of Slurs | 6/8 | meter doesn't break staff height, beat anchors at 6 positions |
| Jock Wilson's Ball | 2/4 | pickup bar (if present) handled without off-by-one |
| Any set tune | multi-tune set | score lane resets cleanly between tunes |

---

## Artifacts summary

| Artifact | Type | Location | Milestone |
|---|---|---|---|
| Re-enable `BuildMeasureMap` call | VBA change (1 line uncomment) | `ExportTuneAll` step 4 in workbook | A-2 |
| Verify js vs VBA physical measure count | Manual check + Debug.Print | `abc_to_png.js` + VBA | A-3 |
| `score_images.json` measure_map field | Schema addition | `datafiles/tunes/*/score/score_images.json` | A-2 |
| `image_meta[]` array in manifest | Schema addition | same | B-1 |
| SVG geometry extraction in abc_to_png.js | JS change | `C:\tools\abc_to_png.js` | B-2 |
| Staff normalisation (crop/pad) | JS change or new script | `C:\tools\` | B-3 |
| `global.score_lane_meta[]` | GML new global | `obj_game_controller/Create_0.gml` + `scr_score_sprites_load` | B-4 |
| `beat_anchors[]` per image in manifest | Schema addition | same as image_meta | C-1 |
| `BuildBeatAnchorsFromEventGrid` | VBA sub (new) | `modParseABC` | C-2 |
| Beat-anchor scroll offset in draw | GML change | `scr_game_viz.gml` draw block | C-3 |
| Re-enable score lane (`false &&` removed) | GML change | `scr_game_viz.gml` ~line 6891 | D-1 |
| `score_debug_overlay` toggle | GML + cfg change | `scr_game_viz.gml` + `obj_game_viz/Create_0.gml` | D-2 |

---

## Open questions — RESOLVED 2026-04-23

1. **abcjs SVG class names** ✓ CONFIRMED via live inspection:
   - `.abcjs-top-line` — top staff line element (use its `y` attribute for `staff_top_px`)
   - `.abcjs-staff-extra` — all 5 staff lines; query all 5, take `max(y)` for `staff_bottom_px`
   - `.abcjs-notehead` — individual note heads (more precise than `.abcjs-note` for x-position)
   - `.abcjs-bar` — barline elements
   - No `.abcjs-bottom-line` class exists — derive bottom from `.abcjs-staff-extra` max-y

2. **volta in event grid** ✓ RESOLVED: events do NOT carry a volta-pass tag, and this is fine. `BuildMeasureMapFromFlat` works at the token level (using `phys_measure` tags on tokens that survive `ExpandRepeats`), so volta handling is already correct without needing event-grid annotations. No changes needed to the event schema.

3. **resvg crop support** ✓ CONFIRMED: resvg only has `-w` / `-h` (pin final PNG dimensions). No crop or offset flag.
   - **Consequence for B-3**: normalisation must happen by manipulating the SVG `viewBox` attribute *before* passing to resvg, not after PNG conversion. Adjust the SVG `viewBox` to crop/offset the canvas so the staff anchor lands at the target y, then let resvg render the clipped result at a fixed height.

4. **abcjs timing API** ✓ CONFIRMED: `renderAbc` returns an object with:
   - `engraver` property — likely contains per-element pixel positions (needs one more inspection step below)
   - `setupEvents` / `setTiming` — can assign timing to rendered elements
   - `getBeatsPerMeasure`, `getBpm`, `millisecondsPerMeasure`, `getTotalBeats` — beat structure
   - **Action for C-1**: inspect `result[0].engraver` in a follow-up node snippet to confirm note x-pixel access. If available, use it. Otherwise fall back to the VBA event-grid beat-anchor approach in C-2.
   - To inspect: `node -e "... const r = abcjs.renderAbc(...); console.log(JSON.stringify(r[0].engraver, null, 2).slice(0,2000))"`
