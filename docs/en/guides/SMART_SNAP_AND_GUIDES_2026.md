# Vectopen — Smart magnet snap & ruler guides (September 2026)

> Living document. Version: 1.0
> Related: `autoloads/SnapManager.gd`, `script_gdscript/tools/MoveTool.gd`,
> `script_gdscript/utils/regla.gd`, `docs/en/guides/ELEGANT_UI_REDESIGN_2026.md`

Affinity / Figma / Illustrator style magnet: dragging a shape aligns it to other
shapes, to the artboard and to ruler guides, showing alignment lines and spacing
measurements.

---

## 1. `SnapManager` — the engine

Autoload. Everything in **world coordinates**; the threshold is constant in
screen space (divided by the viewport zoom).

| Setting | Default | Persisted in |
|---|---|---|
| `grid_enabled` / `grid_size` | off / 10 | `user://vectopen_snap.cfg` |
| `snap_to_objects` | **on** | idem |
| `snap_to_center` | **on** | idem |
| `snap_to_guides` | **on** | idem |

Constants: `SMART_SNAP_PX = 11`, `SPACING_SNAP_PX = 9`, `SPACING_MATCH_EPS = 1.5`.

### `smart_snap(moving: Rect2, candidates: Array, zoom: float) -> Dictionary`

Returns `{ offset: Vector2, guides: Array, spacing: Array }`.

Per-axis strategies (closest wins; 2 and 3 only run on an axis that did not
edge-align):

1. **Alignment** — left/right/top/bottom edges and X/Y centers against each
   candidate rect + **ruler guides** (`guide_x` / `guide_y`).
   `guide = { axis, coord, a, b, guide? }`.
2. **Equal spacing** (`_spacing_snap`) — if the gap to a neighbour matches
   another existing gap between two same-row/column shapes, snap to that
   distance.
3. **Distribution** — center the shape between the low-side and high-side
   neighbour. `spacing = { axis, perp, gap, segs: [[lo,hi], ...] }`.

Grid beats magnet: when `grid_enabled`, smart snap does not run.

### Ruler guides

`regla.gd` publishes its guides via `SnapManager.set_guides(guias_verticales,
guias_horizontales)` on every refresh:

- `guide_x` = **vertical** lines (one X coord each)
- `guide_y` = **horizontal** lines (one Y coord each)

---

## 2. `MoveTool` — drag integration

In the `is_dragging_shape` branch of `_on_motion`:

- `_macro_rect_inicial()` — selection rect at drag start (from
  `transform_initial_states[s]["gpos"]`).
- `_snap_candidates()` — top-level layers of the artboard(s) owning the
  selection (via `VectorDrawingLayer`), excluding the selection and its
  ancestors/descendants, plus `mgr.world_rect(ab)`. Capped at 240.
- `smart_snap(...)` adjusts `delta`; `_snap_guides` / `_snap_spacing` are stored
  for drawing.

**Suppressed by:** `grid_enabled`, `Shift` / `Alt` / `Ctrl`, or a bounding-box
axis handle (`_axis_move != ""`).

### Drawing (`_dibujar_guias_iman`, in `draw_preview`)

- **Shape alignment** → magenta line (`COLOR_SNAP_GUIDE`) spanning the whole
  view (`ext = 4000` world units) + ticks at the exact edges.
- **Ruler-guide snap** → blue line (`COLOR_SNAP_RULE`), slightly thicker.
- **Spacing / distribution** → pink bars with the distance in px
  (`ThemeDB.fallback_font`).

Cleared in `_on_release` and `_heal_stuck_gesture`.

---

## 3. `regla.gd` — pro-editor guides

The drag-from-ruler guide system already existed (create, move, delete by
dropping on the ruler, flashes). Added:

- `_publicar_guias_al_snap()` — feeds `SnapManager` (see above).
- `_snap_guia(coord)` — when creating or moving a guide, rounds to the grid step
  (if `grid_enabled`) or to the **whole pixel**. No more guides at `x = 347.8`.
- `_etiqueta_coord(...)` — dark pill with the world coordinate next to the guide
  while dragging a new one or moving an existing one (Figma / Illustrator style).
- `get_guides_x()` / `get_guides_y()` — public API (copy).

---

## 4. UI

**Settings › Snapping** (`SnapSection.gd` + `manager_windws_regla.tscn`):

- `Smart Snap (objects)` → `set_snap_to_objects`
- `Snap to Guides` → `set_snap_to_guides`
- `Grid Snap` + `Grid Size` (already there)

---

## 5. Verification

- **gdUnit**: `test/autoloads/SnapManager_test.gd` — 12 cases: edge alignment,
  zoom scaling, `snap_to_center` off, distribution, equal spacing, guide snap
  and guides-disabled.
- MoveTool + transform regression: 28/28, no regressions.
- Live scene: 0 errors; `SnapManager.snap_to_objects/guides = true` confirmed at
  runtime.
- ⚠️ The **drag feel and the lines** cannot be verified over MCP (synthetic
  mouse position is frozen — see `selection_manager_architecture`). Verified
  with unit tests + real-mouse confirmation from the user.

---

## 6. Backlog / ideas

- Snap the **guide itself** to shape edges while dragging it (today it only
  rounds).
- Snap while **creating** shapes (rectangle, ellipse, …), not only while moving.
- Snap while **resizing** (today only while moving).
