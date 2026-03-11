# UI Setup How-To (Layers, Flex Panels, UI Items)

## Purpose
Quick checklist for safely adding new UI layers, root flex-panel windows, and UI elements without registration errors.

---

## 1) Add / Rename a UI Layer in RoomUI
1. Create (or rename) the room UI layer (example: `gameplay_layer`).
2. Keep the layer name exact/case-consistent.

---

## 2) Register the Layer in `obj_ui_controller`
1. Update the layer registration list (example: `global.ui_layer_names`).
2. Ensure the index matches what UI instances use as `ui_layer_num`.
3. Confirm `obj_ui_controller` initializes before other UI objects create.

> If this mapping is wrong, UI instances can get `ui_layer_num = -1` and crash registration.

---

## 3) Add a Root Flex Panel Window
For each root window (`fp_*`):
- Place it on the correct room UI layer.
- Set `ui_layer_num` to the registered index for that layer.
- Set `ui_num` unique within that layer.
- Set `ui_name` unique (recommended globally unique).

---

## 4) Add UI Object Items (fields, buttons, etc.)
For every `obj_UI_parent`-based instance:
- `ui_layer_num`: valid index (not `-1`)
- `ui_num`: unique per layer
- `ui_name`: stable unique string

### Field items (`obj_field_base`)
- `field_contents`: default text (`""` is fine)
- `field_ID`: unique if used by field scripts
- `field_target / field_value / field_script_index`: set only if needed

### Button items (`obj_btn_*`)
- `button_script_index`: required
- `button_click_value`: required if script uses it
- `button_target` / `field_ref`: optional by handler design

---

## 5) Single-Layer Pattern (Recommended for Gameplay UI)
If using one UI layer (`gameplay_layer`) with multiple windows:
- Keep all gameplay UI instances on the same `ui_layer_num`.
- Show/hide windows by flex panel/root object state, not by adding many UI layers.
- This reduces registration complexity.

---

## 6) Validation Checklist (after edits)
- Game launches with no UI Create crash.
- No error like:
  - `Variable Index [-1] out of range ... ui_assets(...,-1)`
- New controls respond and update expected data.
- Layer rename references updated in code and room data.

Useful search:
- `gameinfo_UI_layer` (old name)
- `gameplay_layer` (new name)
- `ui_layer_num`

---

## 7) Common Failure Modes
1. **`ui_layer_num = -1`**  
   Cause: layer-name mapping missing or wrong index.
2. **Duplicate `ui_num` in same layer**  
   Cause: copy/paste without renumbering.
3. **Stale layer name after rename**  
   Cause: scripts still referencing old layer.
4. **Controller init order wrong**  
   Cause: UI instances create before layer map exists.

---