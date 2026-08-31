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

## 4. Planned — Advanced interaction (Phases 2–4)

From `VECTOPEN_TECHNICAL_REPORT.md` §1.14 / §11. Backed by a ~60-section spec
("at Affinity's level"). Phase 1 is done; the rest is multi-session scope and
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
| H-3 | `rich_text_label_slider_size.gd:44` warning on startup (×2) | Two attachments in `scenes/ui/panel_tooltext.tscn` with no node-path wiring for the script's 4 exports. Needs a design decision, not a blind fix. |
| H-4 | `ProjectManager` data-model CRUD has no UI caller | See §2. Either wire it or remove it. |
| H-5 | gdUnit4 leaves ~30 orphan nodes + 2 `ShapedTextDataAdvanced` RID allocs at exit | Cosmetic; investigate if it grows. |

---

## Open GitHub issues

| # | Title | Maps to |
|---|---|---|
| [#1](https://github.com/malabo1990/-Vectopen/issues/1) | Interactive Gradient Tool (Affinity-style, tablet-optimized) | New tool — not yet in any doc. Suggest a `tools` label + a "Tools" milestone. |

---

*Maintained alongside the source documents listed at the top. When you finish a
roadmap item, tick it here and link the PR.*
