# Vectopen — Elegant UI Redesign (September 2026)

> Living document. Version: 1.0
> Related: `docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md`,
> `docs/en/guides/UI_SYSTEMS_IMPROVEMENTS_2026.md`,
> `script_gdscript/system/ThemeManager.gd`

An "Apple / Figma / Sketch" styling pass over the layers panel and the tools
toolbar: white surfaces with no border and no shadow, button chips, tintable
icons and clear states. Every color comes from `ThemeManager` tokens (no
hard-coded whites/blacks), so dark mode is inherited for free.

---

## 1. Layers panel (`script_gdscript/ui/layers_system.gd`, `Layertree.gd`)

### Container
- `_aplicar_tema_panel()`: `Panel` stylebox = `PANEL_SURFACE`, radius 14,
  **no border, no shadow**, inner margins 16/14. `VBox` separation 10px so the
  "LAYERS" title, the search field, the button bar and the tree breathe.
- Title: `TEXT_SECONDARY`, 12px, no own stylebox (invisible frame).
- Rebuilt on `theme_changed` (`_on_theme_changed`).

### Layer search
- `LineEdit` `SearchLayers` (in the `.tscn`, between title and bar).
- Style `_btn_sb(INPUT_BG, INPUT_BORDER)` normal / `_btn_sb(INPUT_BG, ACCENT)` on
  focus; `text_changed` → `actualizar_filtro_busqueda()` (supports `is:oculto`,
  `is:grupo`).

### Button bar (`ButtonsBar`)
- Each icon sits **inside a chip** (light grey, rounded — `_chip_sb`, radius 7,
  no border): visible on hover and on press.
- `custom_minimum_size = 28×28`, separation 6.

### Tree colors (`Layertree.gd`)
- **Near-white hierarchy lines**: `relationship_line_color`,
  `parent_hl_line_color`, `children_hl_line_color` = `Color(0.87, 0.87, 0.90)`.
  No blue branch line (it was confused with the selection).
- **Selected row**: `ACCENT_SOFT` fill + `ACCENT` border (never black).
- **Hover**: green `AFFIRMATIVE` at 20%.
- Tighter spacing: `v_separation` 3, `indent_size` 15, 1px lines.
- `drop_position_color` = solid blue (drag & drop insertion marker).

### Row buttons (eye / lock / mask)
- **Every** row carries the 3 buttons in fixed columns (1 eye, 2 lock, 3 mask).
- Unified color: **ENGAGED = black** (`PANEL_TEXT`), **DEFAULT/OFF = near-white
  grey** `(0.87, 0.87, 0.90)`.
  - Eye: visible → black, hidden → grey.
  - Lock: closed (locked) → black, open → grey.
  - Mask: active → black, inactive → grey.
- **White icons** (`_icon_blanco`): the project SVGs are black and
  `set_button_color` **multiplies** (modulate) — black can't be lightened. They
  are re-baked to white (same alpha) so they can be tinted to any shade.
- The mask uses **different icons** for OFF vs ON, not just a color change:
  - ON = `res://icon/UI/exclude.svg` (two overlapping shapes = clip)
  - OFF = `res://icon/UI/frame-alt-empty.svg` (empty frame)

---

## 2. Stencil clipping mask (groups and text)

**Problem**: in Godot 4, `clip_children` clips descendants to the shape the node
itself **draws**. A shape works; a bare `Node2D` group or a text node
(`Node2D` + `WorldTextLabel` "DisplayLabel") draw nothing → the clip region is
empty and children vanish. That's why "text couldn't mask its children".

**Solution** (Illustrator / Affinity): the top shape/letters clip the rest. No
new helper node — the content is reparented **under** the mask node and
`clip_children = CLIP_CHILDREN_ONLY` is set on it.

- `_es_contenedor_sin_cuerpo(n)` — picks the route (shape-with-body vs group/text).
- `_nodo_mascara_de(c)` — group: last shape child (highest Z); text:
  `DisplayLabel` child.
- `_activar_mascara(item, c)` / `_desactivar_mascara(item, c)` — reparent + undo
  via `_accion_undo("Máscara de recorte", do_fn, undo_fn)` (same pattern as
  `_agrupar_seleccion`). Metadata `clip_mask` / `clip_mask_target`.
- `_desagrupar()` disables the mask before ungrouping.

### Serializer (`scripts/canvas/canvas_serializer.gd`)
- **Latent bug fixed**: `_serialize_element()` returned per shape/text kind
  **without serializing children** → nested shapes were lost on save. Now
  `base["children"]` for all kinds; `_apply_transform()` rebuilds recursively.
- `_add_visual_state` stores `clip_mask` / `clip_mask_target`; the loader
  re-runs the reparent-under-mask on load.

---

## 3. Tools toolbar (`scenes/ui/tool.tscn`, `script_gdscript/ui/toolbar.gd`)

Same visual language as the layers panel.

### Scene
- All buttons are `Button` (there were mixed `TextureButton`s before) → uniform
  styling.
- Dead node `button_toolmover` (`visible = false`) **removed**.
- Missing icons, now assigned from the project set:
  | Button | Icon |
  |---|---|
  | select | `navigation.svg` |
  | move | `navigation_BLACK.svg` |
  | bezier | `design_nodoblack.svg` (curve with control nodes) |
  | draw / brush | `draw.svg` (freehand stroke) |
  | image | `media-image.svg` |
  | shapes | `hexagon-plus.svg` → opens `polygon` panel |
  | text | `text-square.svg` → opens `text` panel |
  | artboard | `frame-alt.svg` |
  | layers | `folder-tree.svg` → opens `Selector` panel |
- Panel: white `StyleBoxFlat`, radius 14 (`toolbar.gd` overrides it at runtime
  from `PANEL_SURFACE`, no border, no shadow).

### `toolbar.gd` (was an empty stub)
- `_aplicar_tema()` — panel + chips + icons, rebuilt on `theme_changed`.
- `_preparar_iconos()` — `focus_mode = NONE`, `icon_alignment = CENTER`
  (icons are **centered** in the button), re-bake to white (`_blanco`).
- ACTIVE tool state: **light-grey chip** (`SURFACE_RAISED`) + **black** icon.
  Inactive: mid-grey icon `(0.44)`. Hover: black icon. **No blue.**
- Active-state sync:
  - button click → `pressed` signal (covers tools + panel toggles).
  - keyboard shortcuts (V/M/B/T…) → `GlobalEvents.data_tool_changed`
    (emitted by `ToolManager` for the tools it manages).
  - panel-toggle buttons are marked active while their panel is visible.
- `actualizar_botones_visuales(...)` kept for compatibility with
  `canvas.gd::_sincronizar_ui_toolbar` (tolerates an object or a `String`).

> Note: `class_name ToolbarContainer` was dropped — the validator flagged it as
> "hides a global script class" and nothing used it as a type (all duck typing
> via `has_method`).

---

## 4. UI tokens (`ThemeManager.Slot`)

Palette review. **2 semantic tokens were added** (the `enum` only grows — zero
risk to existing code) to stop computing colors by hand in several places:

| Slot | Light | Dark | Use |
|---|---|---|---|
| `SURFACE_RAISED` | `#E6E6EB` (`0.902`) | `rgba(255,255,255,0.10)` | raised chip/row: active tool in the toolbar, soft selection |
| `ACCENT_SOFT` | `rgba(0,122,255,0.14)` | `rgba(10,132,255,0.20)` | selection fill (tree row, `Tree.selected_color`) |

- `toolbar.gd` uses `SURFACE_RAISED` for the active-tool chip.
- `ACCENT_SOFT` is the canonical token for selection tints going forward
  (`Layertree.gd` and the theme `Tree` still compute `Color(ACCENT, 0.2)` inline;
  migrate to `ACCENT_SOFT` when they're next touched).

The rest of the light palette is unchanged (already user-approved):
`PANEL_SURFACE #F8F8FA`, `ACCENT #007AFF`, `AFFIRMATIVE #34C759`,
`BUTTON_HOVER #F0F0F4`, `BUTTON_PRESSED #E5E5EA`, `TEXT_SECONDARY #6C6C70`,
`TEXT_DISABLED #8E8E93`, `BORDER #D1D1D6`.

`ThemeConfigPanel` picks up the 2 new slots automatically (it iterates
`SLOT_NAMES`) — editable and persistable like any other.

---

## 5. Verification

- **Live (MCP)**: toolbar and layers panel render correctly in light mode;
  active tool highlighted in black (not blue); icons centered; the active state
  follows each button press. `get_errors` = 0.
- **Mask**: circle clipped to a rectangle / shape visible only through the
  letters — correct live, 0 errors.
- **gdUnit4**: `CanvasEditor_test` + `LayerSystem_test` → 21/21, 0 errors,
  0 failures. Full suite with no regressions.

---

## 6. Synthetic-input limitations (reminder)

Verified and documented this session: `Viewport.get_mouse_position()` (and thus
`Node2D.get_global_mouse_position()`) is **never** updated by synthetic events
(`Input.parse_input_event` / MCP `send_input`). Canvas clicks/drags and `Tree`
drag & drop **cannot** be verified live over MCP — validate them with unit tests
+ real-mouse confirmation from the user.
