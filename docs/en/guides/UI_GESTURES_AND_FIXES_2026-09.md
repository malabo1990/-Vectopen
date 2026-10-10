# Vectopen — UI, gestures and fixes (September 2026)

> Living document. Version 1.0 — 2026-09-23.
> Related: `UI_SYSTEMS_IMPROVEMENTS_2026.md`, `ELEGANT_UI_REDESIGN_2026.md`,
> `RESOLUCION_DE_ERRORES.md`. Spanish version:
> `docs/es/guides/INTERFAZ_GESTOS_Y_CORRECCIONES_2026-09.md`.

Summary of the UI changes, new gestures and fixed bugs from the 2026-09-23
session. gdUnit4 suite at the end: **547 cases, 1 pre-existing failure**
(`ContextMenu_test.gd:341`, a `tool_in_mouse` icon, unrelated) and **0
`SCRIPT ERROR`** in the log.

---

## 1. Gestures and shortcuts

### 1.1 Bounding box (select tool)

| Gesture | Result |
|---|---|
| Drag inside the box | Free move |
| **Ctrl** + drag inside | Horizontal/vertical only (axis decided once; with a grid, snapping only on that axis) |
| **Shift** + drag inside | Stroke width on all four sides, shape does not move (right/up = thicker) |
| **Alt** + drag | Leaves a copy at the start position (same parent as the original, just below it) |
| Shift + click without dragging | Remove the shape from the selection |
| Shift + drag an edge handle | Width of that side only (rectangles) |
| Shift + Alt + edge handle | Width of all four sides |
| Red / green arrow | Move on X only / Y only (custom cursors) |
| Corner radius dots | Drag = all corners; **Alt** = that corner; Shift rounds |
| Double-click a text | Edit it (also right after the session starts) |

Every gesture above is a single undo step.

### 1.2 Keyboard

| Key | Action |
|---|---|
| **1 … 9, 0** (with a selection) | Opacity 10% … 90%, 100%. Two quick digits = exact value (4, 5 → 45%) |
| **5** (no selection) | Reset zoom (unchanged) |
| Esc (eyedropper active) | Cancel the eyedropper |

### 1.3 Zoom (Smart and Modern)

- A single click on the percentage no longer resets the zoom.
- **Double-click** = 100%.
- **Drag** left/right on the percentage = smooth zoom.

### 1.4 Right-click

- Each UI mode has its own menu: Smart (tabbed panel), Modern (list with
  monochrome icons and right-aligned shortcuts), Pro (desktop menu with
  Arrange / Align / Transform submenus).
- Switching modes closes the open menu.
- The Smart panel reopens on the **last tab picked**; Ctrl + right-click opens
  the full inspector.
- Only working actions are listed.

---

## 2. Changes per UI mode

### 2.1 Pro
- Compact top bar (`ProTopBar`): undo/redo, align/distribute, flip, arrange,
  settings and mode switcher; it covers the grey strip above the panels.
- Compact Studio (`ProStudio`) with two tabbed groups: Color | Swatches |
  Stroke and Transform | Text | Effects. 20px rows, theme-tinted SVG icons,
  full rebuild on theme change.
- Shared styling in `ProUIStyle`.

### 2.2 Modern
- Left side rail removed; settings live in the top bar.
- Top bar no longer duplicates inspector controls.
- Bottom toolbar: full-contrast icons, divider replaced by a gap.
- Inspector: X/Y lock (locks the object), new **POLYGON** section, circle
  fields shown per mode, one undo step per field drag.

### 2.3 Smart
- The layers card wraps the whole tool column.
- Right-click panel: color picker icons correct from the start, eyedropper,
  gradient without the white strip, redesigned palettes, themed typography,
  letter-proportion reset and a better font list. The Layout/Transform page
  is 220px like the others.

### 2.4 All modes
- Alignment icons redrawn (16px grid, shared axis).
- Layers: soft hierarchy lines on dark themes; interactive highlight is white
  on dark themes and blue on the light one
  (`ThemeManager.get_interactive_color()`).
- Ruler corner uses the ruler color.
- Brush: real-size outline following the pointer.
- Hover highlight: outline of the shape under the pointer (plus a baseline
  cue on text).
- Bounding box: "W × H" pill, long axis arrows, interactive corner radii.

---

## 3. Fixed bugs (root cause)

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot call method 'to_local' on a null value` on double-click | `target_artboard` is null right after a session starts and for shapes outside any artboard; text/paragraph double-click used it unchecked | `ToolBase._edit_frame_for()` resolves the owning artboard, the parent, or the artboard under the point; used by `MoveTool`, `TextTool`, `ParagraphTool` |
| `get_node() with absolute paths` errors on exit | On shutdown `ToolManager._exit_tree` clears the selection and `InspectorCore` plus three panels reacted while leaving the tree | `is_inside_tree()` guards in `InspectorCore._on_event`, `TransformPanel`, `effects.gd`, `panel_polygon.gd` |
| Alt + drag did not duplicate after startup | Required `target_artboard` | Copy goes to the original's parent |
| Drag stutter | Cached mouse position one frame late | Position read from the event (bounding box, brush) |
| Axis handles hard to grab | Hit zones only moved on zoom change | Also on size change |
| Tiny color-picker icons on startup | `clickrigth_nodo` restyled them with 10px margins | Picker buttons are left alone |
| Copy/paste text lost its style | `letter_proportions` / `rich_runs` do not survive `duplicate()` | `WorldTextLabel` restores them from the container |
| Layers opacity showed "1%" | 0–1 value treated as 0–100 | Converted both ways |
| Menu "Lock" did nothing | `InspectorCore` has no `locked` prop | `ContextMenuActions.set_locked()` with undo |
| Arrange / flip not undoable | Mutated the scene directly | `ContextMenuActions` via `HistoryManager` |
| Polygon "Apply to selection" not undoable | `apply()` compared after writing | `apply_multi()` and a dedicated action |

---

## 3b. Second round (same day)

- **Smart · Transform:** corner radii as a 2×2 grid (TL TR / BL BR) above
  the rotation, link toggle in the "Corners" header.
- **Smart · Align:** new anchor icons (frame + block, like the Godot editor's
  anchor presets) in `icon/UI/anchor/`, plus rows for rotate ∓90°, flip H/V
  and arrange (front / forward / backward / back). Rotate 90° is relative to
  each shape's own angle.
- **Smart · bottom-left chip** (`InputHud`): export, shortcuts panel, live
  key caps with modifiers and a 3-button mouse lit in traffic-light colors.
- **Smart · preview bar:** 16px icons, centered.
- **Typography:** theme-colored vertical-align icons, themed vertical slider,
  slider tooltips; hover highlight on text with the Text tool too.
- **Serious fix:** the project's `UndoRedoManager` does not run an action on
  commit; `ContextMenuActions._commit` only registered it, so flip, arrange,
  lock and rotate from menus / Pro bar did nothing. It now applies and
  registers; covered by a test.
- **Selection:** `ContextMenuActions` reads `SelectionManager` first.
- **Stencil icons** keep their source file in `resource_name`, which fixes
  the long-standing failing test.
- Suite: **551 cases, 0 failures, 0 SCRIPT ERROR**.

## 4. Main files

- New: `script_gdscript/ui/pro/pro_ui_style.gd`, `pro_top_bar.gd`,
  `pro_context_menu.gd`, `script_gdscript/ui/context_menu_actions.gd`,
  `icon/UI/menu/*.svg`, `icon/UI/cursor/*.svg`.
- Rewritten: `pro_studio.gd`, `ListaColor.gd`.
- Modified (main): `MoveTool.gd`, `bounding_box.gd`, `VectorRectangle.gd`
  (`stroke_sides`), `adaptive_ui_manager.gd`, `modern_*.gd`,
  `docked_inspector.gd`, `transform_panel.gd`, `layers_system.gd`,
  `Layertree.gd`, `managercolor_pickrColor.gd`, `control_gradient.gd`,
  `ColorPaletteTool.gd`, `rich_text_label_slider_size.gd`,
  `world_text_label.gd`, `canvas.gd`, `brushtool.gd`, `ThemeManager.gd`,
  `ToolBase.gd`, `InspectorCore.gd`.

## 5. New tests

`test/ui/PanelsPolish_test.gd`, `test/tools/ModifierGestures_test.gd`,
`test/shapes/ParametricAudit_test.gd`, plus new cases in `ProStudio_test`,
`BoundingBox_test`, `ModernContextMenu_test`, `LayerSystem_test`,
`MoveTool_test`.

## 6. Open items

- Real-mouse verification of the new gestures.
- Ctrl + drag keeps the grid pull on the locked axis; axis-lock only is a
  one-line change in `MoveTool._on_motion`.
- The embedded MCP server warns when port 6520 is taken (another running
  instance); not a code error.
- Nothing is committed yet.
