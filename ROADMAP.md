# Vectopen Roadmap

This file consolidates the planning that until now lived only inside
`docs/`. It is the single place to check "what's done, what's next".

**Source documents** (kept as the detailed reference):

| Area | Document |
|---|---|
| Architecture / tool system / interaction | [`docs/en/reports/VECTOPEN_TECHNICAL_REPORT.md`](docs/en/reports/VECTOPEN_TECHNICAL_REPORT.md) §11 |
| Performance & massive documents (21-section concept spec) | [`docs/es/guides/RENDIMIENTO_Y_CONTENIDOS_MASIVOS.md`](docs/es/guides/RENDIMIENTO_Y_CONTENIDOS_MASIVOS.md) |
| Multi-artboard + streaming + `.vtc` format + benchmarks | [`docs/es/reports/ARQUITECTURA_MULTI_ARTBOARD_Y_BENCHMARKS.md`](docs/es/reports/ARQUITECTURA_MULTI_ARTBOARD_Y_BENCHMARKS.md) |
| Zoom-limit comparison vs other editors | [`docs/es/reports/COMPARATIVA_ZOOM_EDITORES.md`](docs/es/reports/COMPARATIVA_ZOOM_EDITORES.md) |
| UI systems / theming | [`docs/es/guides/MEJORAS_UI_Y_SISTEMAS_2026.md`](docs/es/guides/MEJORAS_UI_Y_SISTEMAS_2026.md) |

**Legend:** ✅ done · 🟡 partial · ⬜ planned, not started · ❌ evaluated and
deliberately dropped

---

## 1. Done

### Architecture / tooling (branch history up to `2026-08`)
- ✅ All 15 tools migrated to a single `ToolBase` (removed the two dead base
  classes `Tool` / `ToolNode`).
- ✅ `DataRepository` god-object split into `ProjectManager` + `SessionManager`
  (thin facade kept).
- ✅ The two disconnected undo/redo stacks unified behind `HistoryManager`.
- ✅ Adaptive-quality boot bugs fixed; adaptive quality now off by default
  (forces high/ultra).
- ✅ Advanced-interaction **Phase 1**: Delete / Copy / Cut / Paste / Duplicate /
  Select All / arrow-key nudge, all registering real undo/redo (in `MoveTool`).

### Multi-artboard + streaming + document format (branch `multi-artboard-lazy-loading`)
- ✅ **Multi-artboard ownership** — `ArtboardManager` (node `manager_script`) is
  the single authority for "which artboard?"; removed the `get_child(0)`
  anti-pattern from 5 files. Shapes are created in the artboard they're drawn on;
  loose (outside-all) elements are recognised.
- ✅ **Artboard streaming / lazy loading** — off-screen pages serialize + free;
  reinstantiate on viewport approach (amortized `WAKE_BUDGET`/frame). Driven by
  `CullManager` with hysteresis. Never sleeps the active / selected /
  edited-with-live-undo page.
- ✅ **Scene-tree serializer** (`scripts/canvas/canvas_serializer.gd`) — the real
  source of truth (tools never populated the data model, so saves were empty).
  Covers `Vector*` / `Line2D` / `Polygon2D` / text / nested groups / images
  (embedded base64 or `res://`) / effects / CanvasItem visual state
  (`ShaderMaterial` code + uniforms, `clip_children`, `light_mask`, `modulate`,
  `z_index`, shadow/glow metas).
- ✅ **`.vtc` = VTC2 flat addressable container** — header + gzip manifest
  (per-artboard headers only) + concatenated per-artboard gzip chunks. Open reads
  only the manifest; a page loads with one `seek`. Save copies untouched pages'
  chunks byte-for-byte (already compressed). Read handle cached per document.
  Deliberately not a ZIP (`ZIPReader.read_file` is linear-scan → re-save O(N²)).
- ✅ **Stress-test harnesses** — `test/perf/`: `stress_book`, `stress_bezier`,
  `stress_scale`, `stress_10k`, `profile_real`, `idle_render`.
- ✅ **Tools are now in the scene tree** — `change_tool()` never called
  `add_child()`, so every tool's `get_tree()` was `null` and
  `ArtboardManager.find(get_tree())` always failed → multi-artboard resolution
  silently fell back to `container.get_child(0)` (the first artboard) in the
  real app. This was why the 2nd+ artboard couldn't be selected or dragged and
  why shapes never reparented between artboards live. Also fixes the tool
  ObjectDB leak (orphans 35 → 5).
- ✅ **Drag-to-reparent on canvas** — dropping a shape over another artboard makes
  it a child of that artboard (or a loose child of the container if dropped
  outside all), preserving world transform, in one undo action. `MoveTool` drags
  now register undo at all (they didn't before).
- ✅ **Layer panel: loose elements shown under a "Fuera de artboard" root group**
  instead of masquerading as top-level artboards; layer-tree drag-drop resync
  (`hierarchy_changed_by_user` was emitted but unheard); drop onto the loose
  group un-parents a shape.
- ✅ **Layer-panel toolbar buttons wired** — `+A` (new artboard, right of the
  last, made active), `+` (new group in the active artboard), `-` (delete the
  selected node). All undo-able. Live-validated via godot-mcp. `D` / `M` / `G`
  (duplicate / merge / group) still unwired.

### Performance fixes (measured, kept)
- ✅ `WorldTextLabel` extreme-zoom stampede (per-frame recompute + outline
  re-bake) — was ~1 FPS at zoom > 16×.
- ✅ RID leak of the shared `TextServer` font.
- ✅ Layer counter `O(N²)` → `O(N)` incremental (wired to the "Numer layer" label).
- ✅ Removed per-primitive antialiasing (it broke 2D batching); minimap
  re-render throttled to 6 Hz; 2D MSAA capped at 2×; idle render at 10 FPS after
  600 ms of no input.
- ❌ Manual spatial culling and geometric LOD — implemented, benchmarked,
  **reverted**: Godot 4 already does the equivalent, and the LOD variant measured
  *slower* (mixing `draw_rect` with `draw_colored_polygon` breaks batching).

**Benchmark — 1000 pages / 100,000 elements (RTX 3060):** RAM on open
1,863 → 614 MB · load 11.5 → 1.4 s · nodes 104,972 → 4,992 · file 22.7 → 1.30 MB ·
activate a far page 111 → 27 ms · save-after-lazy 3,700 → 34 ms · navigate FPS
~130 → 339 · save-after-lazy integrity OK (no page lost).

---

## 2. In progress / partial

| Item | State | Notes |
|---|---|---|
| Incremental rendering (spec §5) | 🟡 | Relies on Godot's `_draw` + `queue_redraw`; no custom dirty-region pass. |
| Extreme zoom (spec §6) | 🟡 | Text path fixed. Float32 camera precision far from origin still drifts — needs a floating-origin scheme. Camera zoom range already raised to 0.05–50000×. |
| Shared resources (spec §13) | 🟡 | Font RID sharing done. Curve baked-points and shape vertex caches exist. No global brush/gradient/texture pool yet. |
| Multi-level cache (spec §17) | 🟡 | Baked points, vertex cache, minimap throttle, per-document read handle. Not a unified, tiered cache. |
| Model/render separation (spec §8) | 🟡 | `canvas_serializer` is the scene-truth for save/load. `ProjectManager`'s CRUD data model still has no real UI caller — undo of live drawing works via `HistoryManager` callables, not the data model. |

---

## 3. Planned — Performance & scale

From `RENDIMIENTO_Y_CONTENIDOS_MASIVOS.md`. Do not start these speculatively —
pick one up only when a real document exposes the limit.

| # | Item | Priority | Notes |
|---|---|---|---|
| P-1 | Floating origin for camera precision at extreme zoom | 🟢 P2 | Only bites far from origin at very high zoom. Blocks nothing today. |
| P-2 | Manifest paging / side index for the `.vtc` | 🟢 P2 | The whole manifest is read on open. Fine to ~10k pages; 100k+ needs paging. |
| P-3 | Parallel processing — `WorkerThreadPool` for bake / serialize / import (spec §14) | 🔵 P3 | Not started. Serialize is already ~4 µs/elem so this is for import + curve bake. |
| P-4 | Custom dirty-region invalidation (spec §10) | 🔵 P3 | Only if profiling shows Godot's redraw is the bottleneck. Currently it is not. |
| P-5 | Own spatial index for hit-testing at 10k+ objects (spec §11) | ❌ / re-open only with evidence | Evaluated 2026-08 and dropped — Godot's culling + per-artboard scoping is enough so far. Re-open only if `_shape_at` shows up in a profile. |
| P-6 | Shader uniforms of type `Texture` in the serializer | 🟢 P2 | Currently skipped (rest of the shader is saved). Small, self-contained. |

---

## 3b. In progress — Bounding-box / transform bug-hunt (P0)

The selection + transform system is a foundational subsystem. Goal: it survives
long combined chains (select → move → scale → rotate → duplicate → delete →
undo → redo → multi-select → transform → undo → redo) with no state drift
between the model, the bounding box, the Inspector fields and the history.
Rule: **every bug found becomes a permanent test** in
`test/canvas/TransformRegression_test.gd`.

Done:
- ✅ Real undo/redo for move / resize / rotate / axis-move / G-S-R confirm
  (was: only nudge/delete/duplicate/paste). One action per gesture, full
  before/after state.
- ✅ `_restore_transform()` — one inverse used by undo/redo AND Escape-cancel
  (cancel used to leave a scaled shape half-transformed).
- ✅ Constant screen-size handles + axis-move gizmo (§3b handled the visuals).
- ✅ Delete key no longer globally hijacked by the layer tree (was irreversible
  `queue_free`).
- ✅ First regression batch (11): move/resize/rotate undo+redo, chain undo×3/
  redo×3, non-selected untouched, multi-select relative positions, delete
  multi, axis X/Y, rotated-shape resize, cancel mid-transform.

Pending (from the user's analysis doc — the full matrix):
- Every handle (8 corners+sides) individually, each object type
  (rect/ellipse/line/path/text/image/group), each zoom level (10%–800%).
- `scale → rotate → scale` again (classic coordinate-math bug spot).
- Multi-select rotate/scale about the group centroid; 2/3/10 shapes.
- Rotation values 0/45/90/180/270/360/−360/720/decimals; normalization.
- Numeric-precision drift after hundreds of ops; +0.1×3 vs +0.3.
- Tool-switch / new-selection / Escape mid-transform → safe finalize, no ghost
  box, no dangling undo entry.
- Inspector ↔ bounding box ↔ model value parity (invariant I6).
- Limits: 0-width/height, negative, huge/tiny scale, far-from-origin.
- Stress: transform under 1k–10k objects, timings for select/transform/undo.

## 3c. Inspector core system

`autoloads/InspectorCore.gd` — the central layer between the **selection** and
any property UI (the right-click `tool_in_Mouse` panel, a future side panel, the
bounding-box X/Y fields). Same role for properties that the bounding box plays
for transforms.

Done:
- ✅ Follows the live selection via `GlobalEvents.selection_changed` (new signal,
  emitted by MoveTool `_select`/`_deselect`/`_clear_selection`/`select_all`).
- ✅ One property model over all shape types: `pos_x/y` (doc-space, matches the
  bbox fields), `width/height`, `rotation`, `fill_color`, `stroke_color`,
  `stroke_width`, `opacity`, `corner_radius`, `visible`, `name`, `font_size`,
  `line_spacing`, `font_family` / `font_weight` / `font_italic` (text shapes:
  meta + `DisplayLabel` — `line_spacing` theme constant, font via [FontCore](#3d-font-core-system)).
- ✅ `current_props()` → `{prop: {value, mixed}}`; multi-select shows the common
  value or `mixed`.
- ✅ `apply(prop, value)` — writes to every selected shape in ONE undo action.
- ✅ `align(mode)` / `distribute(axis)` — left/center/right/top/middle/bottom and
  even h/v spacing, undo-able. Reference = selection bounds (2+) or the artboard
  (1). Wired to the `TOOLS ALINEACION` icon row in the context menu.
- ✅ `name` rename flow — inline `LineEdit` from the context-menu `name`/`Button6`.
- ✅ Colour swatches (`ListaColor.gd`, `apply_to` fill/stroke) → `InspectorCore`.
- ✅ Stroke panel (`Panel_trazos`) — `ColorPickerButton` + size `SpinBox` wired
  through `clickrigth_nodo.gd` to `stroke_color`/`stroke_width`, two-way synced
  via `InspectorCore.changed`.
- ✅ The 16-button align grid — 9-point + single-axis semantics, one undo per click.
- ✅ **Works across every shape type**, not just rect/circle:
  - Polygons (`VectorPolygon`), Line2D, Polygon2D and Bézier paths (`Path2D`) —
    `width`/`height` now scale the point list / curve points+handles about the
    local bbox centre (`_write_extent`), undo-able. Before, resizing any of
    these from the inspector was silently ignored.
  - Bézier paths are now editable at all: `VectorPath.gd` gained real
    `fill_color`/`stroke_color`/`stroke_width`/`closed` (were hard-coded consts),
    `_draw()` uses them, `closed` keeps the `is_closed` meta in sync.
  - `beziertool.gd` now emits a `Path2D` + `VectorPath.gd` (same type the
    serializer's loader builds) instead of a throwaway inner class — one type,
    one code path.
  - Serializer persists path style (`fill`/`stroke`/`stroke_w` on the `path` kind).
  - `Sprite2D` images resize by scaling the node (`_write_extent` → `scale`,
    bounds measured via a new scale-aware `_global_rect` Sprite2D branch), undo-able.
- ✅ **Text panel `Panel_tooltext` wired** — `rich_text_label_slider_size.gd`
  rewritten from a dead local-preview widget into a selection-driven controller:
  - `HSlider` (horizontal, by the glyph) → `font_size` [8–200]
  - `VSlider` (vertical, left)          → `line_spacing` [-20–80]
  - `HSlider2` / `VSlider2` reserved for tracking / word-spacing.
  - Drag → one undo entry on `drag_ended`; discrete key/click changes apply live.
  - Two-way synced via `InspectorCore.changed`. Kills the H-3 startup warning.
  - New `line_spacing` property in the core (meta + Label `line_spacing` theme
    constant), serialized on the `text` kind.
- ✅ **Font core system** (`autoloads/FontCore.gd`) — see §3d.
- ✅ Tests: `InspectorCore_test.gd` (16) incl. bbox parity, font_size/family,
  polygon style+resize, Bézier style, Line2D, Sprite2D resize, line_spacing;
  `ContextMenu_test.gd` (6) stroke panel + text-panel font_size + font browser;
  `CanvasSerializer_test.gd` Bézier-style + line_spacing + font round-trips;
  `BezierTool_test.gd` (1); `FontCore_test.gd` (8).

Pending:
- Resize of `Node2D` groups from the inspector — needs `_global_rect` (and the
  leaf-shape branches it calls) to be scale-aware first; that's a transform-system
  change, deferred with the group system (I-1). MoveTool doesn't resize groups by
  gesture either yet.
- Letter/word spacing sliders (`HSlider2`/`VSlider2`) — model + a `FontVariation`
  spacing path.
- Side panel UI bound to `InspectorCore.changed` (deferred — user wants the
  context menu, not a side panel).
- Boolean ops, effects, gradient fill.

## 3d. Font core system

`autoloads/FontCore.gd` — central layer between the fonts available on the
machine and any text UI / shape. Same role for typography that the bounding box
plays for transforms and InspectorCore for properties.

Done:
- ✅ **Enumerates families**: the user's OS fonts (`OS.get_system_fonts()`) +
  bundled (`assets/fonts/Inter-Regular.ttf`), deduped, natural-sorted.
  `search(query)` filters by substring.
- ✅ **Resolves a spec** `{family, weight, italic}` → a cached `Font`:
  `SystemFont` (with system fallback) for OS families, `FontFile` /
  `FontVariation` (embolden) for bundled. `spec_from_node(n)` reads the
  `font_family` / `font_weight` / `font_italic` metas.
- ✅ **`font_bytes(spec)` / `system_font_path(spec)`** — raw bytes for the
  text-to-shape outline builder. The TextServer font RID is now created and
  freed *per outline build* in `WorldTextLabel._build_outline_at` (was a leaky
  static `_manual_rid`) — no RID pool to leak.
- ✅ **`describe(spec)`** ("Inter · Bold Italic"), `sample_text()`, weight-name
  table, `STYLE_PRESETS`.
- ✅ **`WorldTextLabel`** delegates its font to FontCore: reads the metas from
  itself or its container, `apply_font_from_meta()` re-resolves + invalidates the
  outline cache. Dropped the shared static `_cached_font` / `_live_instances`
  machinery.
- ✅ **InspectorCore** props `font_family` / `font_weight` / `font_italic`
  (text shapes), one undo per change, applied to `DisplayLabel` + inline editor.
- ✅ **`Panel_tooltext` fully wired** (`rich_text_label_slider_size.gd`), against
  the node names the user gave the .tscn:
  - `Panel/Label/HSlider` → `font_size`, `line_space` → `line_spacing`,
    `letras_space` → `letter_spacing` (tracking via a `FontVariation` spacing
    layer in `WorldTextLabel._apply_font`).
  - `Button_font` / `Panel_font` → the system-font browser (list previewed in
    each face, search, apply).
  - `OptionButton` → font style (`Regular`…`Bold Italic`) → `font_weight` /
    `font_italic`.
  - `VBoxContainer/BoxContainer2` align icons → `text_align`
    (left/center/fill/right).
  - `VBoxContainer/BoxContainer4` "AA/Aa/aa/aA" → case transforms on the text.
- ✅ **Text is a first-class inspector object now** — `fill_color` /
  `stroke_color` / `stroke_width` on a text shape drive the `DisplayLabel`
  `font_color` / `font_outline_color` / `outline_size` (+ metas). So the colour
  picker, swatches and `ColorCore` all colour text with no new controls.
  `text` (content) and `text_align` are props too.
- ✅ All of the above serialised on the `text` kind and restored (colour,
  outline, align, line/letter spacing).

Pending:
- Per-family style enumeration (which weights/italics actually exist) — Godot's
  `SystemFont` doesn't expose it cheaply; today we offer generic presets.
- **Per-position letter styling** (`VBoxContainer/BoxContainer5` "Aaa/AaA/aaA/aAa"
  + the 3 bottom `HSlider`s). Per the user: the 4 buttons pick which letter of a
  run (first / middle / last) stays upper vs lower case; each of the 3 sliders
  scales the font-size of the first / middle / last letter — a per-position size
  gradient (decorative / custom small-caps). Needs a per-glyph render path in
  `WorldTextLabel` (RichText-style spans or a custom draw). Not started.
- Recently-used / favourite fonts; embedding used system fonts into `.vectopen`.
- Gradient / image fill on text (only solid + outline today).

## 3f. Transform panel (compact, editor profesional style)

`script_gdscript/ui/transform_panel.gd` + `scenes/ui/transform_panel.tscn` —
built from the user's HTML/CSS mock-up ("Compact Object Transformations").

Done:
- ✅ Self-drawing `PanelContainer` (no .tscn wiring needed): a 3×3 grid —
  `[radius TL] [Y] [radius TR] / [X] [ROT dial] [W] / [radius BL] [H] [radius BR]`
  + Reset, with the mock-up's dark card / accent palette.
- ✅ Custom `Dial` control (inner class): rotation dial (drag = angle, 0–360°) and
  4 radius dials (drag vertically, arc shows fraction).
- ✅ Custom `Field` control (inner class): **every X/Y/W/H field is a scrub field**
  — drag horizontally to change the value (scrub-field style, live preview +
  one undo on release), single click to type. W/H clamp to ≥ 1.
- ✅ Two-way bind to InspectorCore — X/Y → `pos_x`/`pos_y`, W/H → `width`/`height`,
  ROT → `rotation`, corner dials → `corner_tl/tr/br/bl`. `mixed` selections show
  "—", empty selection disables the fields.
- ✅ **Independent corner radii** on `VectorRectangle` (`corner_tl/tr/br/bl`,
  `get/set_corner_radii(Vector4)`; `corner_radius` kept as a uniform
  convenience — reads the average, writes all four). Live corners in
  `_generate_rounded_rect_vertices` (per-corner clamp, sharp corner at r=0).
  Serialised as `corners:[tl,tr,br,bl]` when not uniform.
- ✅ Drag = live preview (no undo spam) + one `InspectorCore.commit_live()` undo
  entry on release. Reset zeroes rotation + all four radii.
- ✅ Tests: `TransformPanel_test.gd` (4), `InspectorCore_test.gd` (+corner props),
  `CanvasSerializer_test.gd` (+per-corner round-trip).

Pending:
- The `Depth` field in the mock-up (a 2D editor has no depth) — mapped to `W`.
  If the user wants scale-X / scale-Y or skew instead, easy swap.
- Aspect-ratio lock (mock-up has no lock, but `tool_layout.tscn` shows a
  `lock.svg`); artboard-size presets from `tool_layout.tscn`.
- Replace / merge with the existing `Tool_LAYOUT` instance in `tool_in_mouse.tscn`
  (currently `visible = false`) — the user decides where it mounts.

## 3e. Colour & gradient system

`autoloads/ColorCore.gd` — unified *paint* model between any colour selector /
gradient editor and the selection. Peer of InspectorCore / FontCore.

Done:
- ✅ **Paint model**: `solid | linear | radial` as a plain dict
  (`make_solid` / `make_linear` / `make_radial`, `gradient_from_paint`).
- ✅ **Active colour + target** (fill / stroke), `set_color()` / `set_paint()` →
  route through `InspectorCore.apply` (undo, multi-select, mixed); two-way synced
  from `InspectorCore.changed`. A re-entrancy guard breaks the
  ColorCore→Inspector→`object_style_changed`→Inspector→ColorCore cycle.
- ✅ **Recents** (ring buffer) + **saved palette**, persisted to
  `user://color_state.cfg` (migrates the old `vectopen_palette.cfg`).
- ✅ **Advanced ops**: `hex` / `parse`, `harmony(c, mode)` (complementary /
  analogous / triadic / tetradic / split / monochromatic), `shades` / `tints`,
  `mix`, WCAG `luminance` / `contrast_ratio` / `best_text_on`, alpha `blend`,
  `sample_screen(vp, pos)` eyedropper.
- ✅ **HSV picker rewrite** (`hsl_colorpickr.gd`): hue **ring** + Saturation×Value
  **square** with markers + alpha — was hue-only, no saturation. Two-way with
  ColorCore.
- ✅ **Gradient fill on shapes** — `VectorShape.fill_gradient` (+ `_type`
  linear/radial, `_angle`). `draw_fill(points)` on VectorShape draws solid *or*
  gradient (UVs from the local bbox + angle / radial from centre), so
  rectangle / circle / polygon get it for free; any new VectorShape too.
  `Line2D` uses its native `gradient`. Picking a flat colour clears the gradient.
- ✅ **Serialised**: `fill_grad` (stops + type + angle) on rect / circle / poly /
  line, round-trips.
- ✅ Gradient editor (`control_gradient.gd`) pushes its `Gradient` to ColorCore →
  applied to the selection's fill with undo.
- ✅ `line_edit_data_color.gd` / `managercolor_pickrColor.gd` bridged to ColorCore.
- ✅ Tests: `ColorCore_test.gd` (7), `InspectorCore_test.gd` (+fill_paint),
  `CanvasSerializer_test.gd` (+gradient round-trip).

Pending:
- **On-canvas gradient line** (editor profesional/un editor profesional/estándar style) — an interactive
  overlay drawn on the canvas: the gradient axis with a draggable start/end
  (and centre for radial), plus stop handles you drag/add/remove directly on the
  line. This is a MoveTool-adjacent overlay + a "gradient tool" mode. Not started.
- Gradient fill on Bézier paths (`VectorPath`) and text; `Polygon2D` gradient
  *read* (write already sets a `GradientTexture2D`).
- Fill/stroke target toggle wired to the two swatches; eyedropper button
  (`detnerColor_cursor.gd` still calls a non-existent `pick_color_at`).
- Radial gradient centre/radius controls; conic gradients.
- Palette: harmony-generated palettes (`ColorPaletteTool`) feeding ColorCore.

## 4. Planned — Advanced interaction (Phases 2–4)

From `VECTOPEN_TECHNICAL_REPORT.md` §1.14 / §11. Backed by a ~60-section spec
("at editor profesional's level"). Phase 1 is done; the rest is multi-session scope and
**not started**.

| # | Item | Priority |
|---|---|---|
| I-1 | Group / ungroup with real hierarchy + undo | 🔵 P3 |
| I-2 | Visual transform controls (rotate/scale/skew handles) — incl. resizing an already-rotated shape in its *local* axes (`MoveTool._apply_resize` known limitation) | 🔵 P3 |
| I-3 | Align / distribute | 🔵 P3 |
| I-4 | Snapping, smart guides, grid, rulers — wired to real geometry | 🔵 P3 |
| I-5 | Node editing (path point add/remove/convert) | 🔵 P3 |
| I-6 | Centralized command system (replace the ad-hoc `HistoryManager.add_do/add_undo` calls scattered across tools) | 🔵 P3 |
| I-7 | Extend Phase 1 clipboard/keyboard shortcuts beyond `MoveTool` to all tools | 🟢 P2 |
| I-8 | Residual "shortcuts have no effect in long sessions" — investigated, not a logic bug, paused. Suspect it's a test-method artifact (synthetic events). | 🟢 P3 |

---

## 5. Planned — File format & export

| # | Item | Priority | Notes |
|---|---|---|---|
| F-1 | Real bidirectional SVG (bezier curves, not just polyline approximation) | 🔵 P3 | Current `import_svg` handles M/L/Z only. |
| F-2 | PDF shape export | 🔵 P3 | Enum entry only today. |
| F-3 | WEBP export | 🟢 P2 | Declared, not implemented. |
| F-4 | Real image tracing ("Image Trace") | 🔵 P3 | `vectorize_image` currently just imports the raster and warns. |
| F-5 | `.vop` vector interchange format — define it | 🔵 P3 | Reserved but unspecified. |

---

## 3g. Layers panel — modern UI + clip masks

Done:
- ✅ **Theme-aware, light by default** — `project.godot` `theme_mode` is now
  `"light"` (matches the rest of the app; dark is one click in theme config).
  `Layertree._pull_theme_colors()` fills its colour `@export`s from `ThemeManager`
  design tokens and re-applies on `theme_changed`; `layers_system._aplicar_tema_panel()`
  restyles the `Panel`, `Title` and `+/+A/-/D/M/G` buttons from the same tokens.
- ✅ **Icon rows** (not checkboxes) — visibility → `eye` / `eye-off`, lock →
  `lock` / `lock-slash`, mask → `crop`, all as `TreeItem` buttons, tinted by
  state. Each toggle is one undo entry.
- ✅ **Clip-mask button only on parents WITH drawable children** — cycles
  `clip_children` off ↔ `CLIP_CHILDREN_AND_DRAW`, like Godot's node clipping.
  Serialised via `_add_visual_state`.
- ✅ **Drag = reparent, undo-able** — `Layertree._finalizar_drop()` records the
  reorder / reparent as one `HistoryManager` action (drop-on = into child,
  drop-between = sibling, drop-on-"Fuera de artboard" = loose), like Godot's
  scene tree.
- ✅ **Compact rows** — `v_separation` 3, icons pre-scaled to 16 px + `icon_max_width`
  so the panel stops looking oversized.
- ✅ **No stray `>` fold arrow** — a leaf shape (rect/circle/text/path) is never
  recursed into; only real *layers* (`_es_capa()`: shape / group / artboard, not
  `Contorno_Stroke` / `Render_Visual` / render helpers) become sub-rows.
- ✅ `transform_panel.gd` is theme-aware too (light by default, follows the toggle).
- ✅ **Verified live** (MCP `run_scene` + screenshots): panel is now light, rows
  are readable (row colours come from tokens — was hard-coded near-white text),
  hierarchy indent + group accent colour work.
- ✅ `ThemeManager` default is **light** (`current_mode` + the `_ready` fallback +
  `project.godot`); the whole app opens light, dark is the theme toggle.
- ✅ `layout.tscn` layers `PanelContainer` height 489 → 336 (it was oversized).
- ✅ **Clean layer names** (`NameUtils.unique_child_name`): shapes / groups /
  artboards / text are named `Rectángulo`, `Grupo`, `Artboard`, `Texto`… and
  the number only appears to disambiguate — `Grupo`, `Grupo 2`, `Grupo 3` (space,
  estilo profesional), no invented timestamps (`Grupo_67285` → gone). Also drives
  paste/duplicate naming in MoveTool.
- ✅ Tests: `LayerSystem_test.gd` (+clip / eye / lock toggle undo, +panel tokens,
  +leaf-has-no-children); `NameUtils_test.gd` (4).
- ✅ **Verified live via MCP** (`run_scene` + `send_input` + screenshots):
  light theme, readable rows, `Grupo` / `Grupo 2` / `Artboard 2` clean names,
  proper indent, no stray fold arrow, compact panel.
- ✅ **Third-party product names removed** from the whole codebase and docs —
  comments, identifiers (the keyboard-transform enum and helpers), token names.
  Everything now uses neutral wording or the Vectopen name.

Pending:
- Blend-mode & opacity per layer/group in the row.
- Per-layer clip *to a sibling shape* (un editor profesional "use as mask") — today it clips to
  the group's own drawn content only.
- Migrate the remaining panels (`tool_in_mouse`, colour picker, …) to
  `ThemeManager` so the theme toggle really changes *everything*.

## 3h. Layers panel — professional Layer/Scene Tree (31-section concept)

Full concept + phased plan: [`docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md`](docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md).
Goal: the panel becomes *Scene Tree + Layer Manager + Selection Manager +
Hierarchy Editor*, single source of truth with Canvas / Artboard / Bounding Box.

| Phase | Scope | Status |
|---|---|---|
| 1 | `SelectionManager` autoload (single authority, `Array[Node2D]`, modes REPLACE/ADD/TOGGLE, `active`/`anchor`). Route MoveTool + LayerTree + bounding_box + InspectorCore through it. Bidirectional Canvas↔Layers↔BBox. Reveal-in-tree. Hierarchical-selection primitives. **13 tests, live-verified.** | ✅ done |
| 2 | Hierarchical selection (group vs child vs descendants) + pro multi-select (Shift range in panel, Ctrl across branches, select-branch). | ✅ primitives + row context-menu ("select children/descendants/branch") + `select_similar`; native Tree covers Shift/Ctrl. |
| 3 | Collective actions (lock/hide/group/ungroup/duplicate/delete/z-order/align) each as one undo · full context menu · keyboard nav ↑↓←→/Enter/Space. | ✅ context menu w/ all actions + align/distribute submenu · keyboard: ↑↓←→ native, Enter=rename, Space=visibility, Ctrl+G / Ctrl+Shift+G. All undo-able. |
| 4 | Advanced DnD: insertion preview line, sibling-vs-child affordance, extract-from-parent, multi-drag. | ✅ `LayerTree` drag/drop rewritten: multi-node drag, one-undo `mover_capas()`, extract-to-loose. Insertion line + sibling/child box are native (`drop_mode_flags=3`). |
| 5 | Type/state filters · real lock/visibility inheritance · Focus Mode · breadcrumb · smart-select-similar · per-type row icons · 10k–100k perf pass. | 🟡 done: per-type row icons, lock inheritance (`_selectable` walks ancestors + `locked_by_inheritance`), `is:oculto/bloqueado/grupo/texto/imagen/seleccionado` filter tokens, select-similar. Pending: Focus Mode, breadcrumb, visibility-inheritance display, big-doc perf pass. |
| 6 | Components / symbols (needs document-model support). | ⬜ blocked on document model |

## 6. Planned — Tooling & infra

| # | Item | Priority |
|---|---|---|
| T-1 | Turn `.github/workflows/build.yml` into a real CI: run the gdUnit4 suite on push + build the 4 export presets on tags | 🟢 P2 |
| T-2 | GitHub: create Milestones + label the backlog (`performance`, `enhancement`, `architecture`, `format`) so planning is visible outside `docs/` | 🟢 P2 |
| T-3 | Screenshots / short demo GIF in the README | 🟢 P2 |

---

## 7. Housekeeping / tech debt

| # | Item | Notes |
|---|---|---|
| H-1 | README + `CLAUDE.md` still say the project format is JSON `.vectopen` | It is now `.vtc` (VTC2). Update the docs. |
| H-2 | `scripts/` (legacy) vs `script_gdscript/` (primary) still both in use | e.g. `canvas_serializer.gd`, `artboard.gd`, `canvas.gd` live in `scripts/`. Long-term: consolidate. |
| H-2b | 3 half-built layer-panel implementations coexist | Live one: `Layertree.gd` + `layers_system.gd` (in `layers_system.tscn`). Dead: `layers_drop_handler.gd` (TreeItem-only clone, no reparent), `panel_tree_layers.gd` / `LayerPanel.gd` (pilot with fake layers). Delete the dead two. |
| H-3 | ~~`rich_text_label_slider_size.gd:44` warning on startup (×2)~~ | ✅ Fixed — script rewritten as the `Panel_tooltext` → `InspectorCore` controller (see §3c). No more unassigned exports. |
| H-4 | `ProjectManager` data-model CRUD has no UI caller | See §2. Either wire it or remove it. |
| H-5 | gdUnit4 leaves ~35 orphan nodes + 2 `ShapedTextDataAdvanced` RID allocs at exit | Cosmetic; investigate if it grows. |
| H-6 | Layer-panel `D` / `M` / `G` buttons unwired | Duplicate / merge / group. `+` / `+A` / `-` are done. |
| H-7 | godot-mcp plugin port was hard-coded to 6505, server on 6515 | Fixed to 6515 + `GODOT_MCP_URL` override; see `addons/godot_mcp/README.md`. |

---

## Open GitHub issues

| # | Title | Maps to |
|---|---|---|
| [#1](https://github.com/malabo1990/-Vectopen/issues/1) | Interactive Gradient Tool (editor profesional-style, tablet-optimized) | New tool — not yet in any doc. Suggest a `tools` label + a "Tools" milestone. |

---

*Maintained alongside the source documents listed at the top. When you finish a
roadmap item, tick it here and link the PR.*
