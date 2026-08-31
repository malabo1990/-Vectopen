# Vectopen — UI, Systems & Performance Improvements (August 2026)

> Living document of recent changes. Version: 1.0
> Related: `docs/design/UI_DESIGN.md`, `docs/design/design-tokens.json`

---

## 1. Managed File System (`FileFlowLayout`)

The export panel (`panel_export.tscn`) now includes a full file manager:

- **Views**: Recent (recent files), Recover (autosaves/backups from `user://`) and Files (system browser, starts at Desktop).
- **Dynamic header** (light gray) showing the active view; switched via buttons.
- **Details ↔ Icon**: exclusive toggle; Icon shows a **grid** (`ItemList`, 64px icon + name below, adjustable `fixed_column_width`).
- **Zoom slider** (16–96): scales content icons/type only (not panel chrome).
- **Folder navigation**: Back / Forward / Up with real history and edge disabling.
- **Desktop drag & drop** (OS → `{"files": [...]}`) and internal recent-file drag.
- **Preview**: right panel with selected image; **Space** opens the big centered viewer (fullscreen overlay; Esc/click closes).
- **Localized empty message**: "No documents exist".
- **Guaranteed contrast**: all buttons with explicit `font_color/hover/pressed/focus` (black on light, white on dark).

### Performance (very fast)
- **Thumbnails on `WorkerThreadPool`** (8 native workers) with parallel PNG/JPEG decoding; `ImageTexture` created on the main thread.
- **Disk cache** (`user://thumb_cache/`) — second visit decodes nothing.
- **Directory listing cache** (`_dir_cache`) — instant navigation.
- **Progressive rendering**: first 12 items immediate, rest in 30-item/frame batches.
- Files > 4 MB skipped from thumbnailing.

## 2. Export Panel

- Format selector with **contextual configuration** (`FormatConfigPanel`): each format reconfigures the `OptionButton` (Color/Quality/Page/Color Space/Style) and toggles Resolution visibility (raster only).
- **Save / Save As** buttons wired to `SaveManager`.
- **Red X** (top-left, macOS style) closes the panel; the Export button (keyboard) toggles it.

## 3. Keyboard & Mouse configuration (`InputConfigPanel`)

- **57 shortcuts** organized (tools, canvas, file, edit, object, alignment, layers, text).
- **Per-binding chips** (pills) with `×`, `+` for multiple bindings, and **Reset** (text link).
- **Input capture** (keyboard or mouse): "Listening for input..." hint, **Esc cancels**.
- Persistence in `user://vectopen_inputmap.cfg` (keys + mouse buttons; `VectopenInput` loads on startup).
- **Styles live in `.tscn`** (variations `BindChip`, `ResetLink`, `BindRowLabel`, `CaptureHint`) — editor-editable, not code.
- Search filter; macOS dark popup with shadow.

## 4. Settings Panel (`manager_windws_regla`)

- macOS window: translucent dark glass, subtle border, 12px radius, shadow.
- **Borderless tabs** (minimal): subtle normal, hover, gray selected, uniform width.
- **macOS switches** (green `#30D158` / gray) for all CheckButtons (global theme).
- SpinBoxes replaced by **`spin_boxblack.tscn`** (dark variant with `SpinBoxValue`).
- Compact language selector (no duplicates, with margins).
- **Hidden at startup** (window toggle button) and drawn above the logo.

## 5. Pro Theme (`ThemeManager` — `script_gdscript/system/ThemeManager.gd`)

- macOS tokens in **dark and light modes** (source: `docs/design/design-tokens.json`).
- **Semantic buttons**: `AffirmativeButton` (green) and `NegativeButton` (red) variations — white text.
- Inputs with **accent focus ring** + glow; panels with border/shadow; dark scrollbars with **content separation** (8px).
- Global toggle icons; `default_font_size` 14.
- User overrides persisted in `user://vectopen_theme.cfg`; slot API for `ThemeConfigPanel`.

## 6. Numeric Widgets

- **`spin_box.tscn`** (light, black text) and **`spin_boxblack.tscn`** (dark, white text) — both with `class_name SpinBoxValue`:
  exports `value/min_value/max_value/step/sensitivity`, `value_changed` signal, isolated from the global theme.

## 7. Zoom & Canvas

- **Pointer-centered zoom** — fixed `zoom_at_point` formula:
  `camera.position = world_point + (camera.position - world_point) * (old_zoom / new_zoom)`.
- **Blocked over panels**: `GlobalUI.is_mouse_over_ui` updates in `_process` via `gui_get_hovered_control()`; the canvas ignores the wheel over UI (panel scrolling works) and re-enables zoom outside.
- **Text crispness** (artboard title and world texts):
  - `msaa_2d = 4x`, text antialiasing on, subpixel positioning off (pixel-aligned)
  - 2D snap of transforms/vertices to pixel, Light font hinting
  - title `draw_string` pixel-aligned (`.floor()`)

## 8. Localization

- File panel and config texts use `tr()` + keys in `translations/vectopen.csv` (en/es minimum; live re-translation via `NOTIFICATION_TRANSLATION_CHANGED`).

## 9. Quality (gdUnit4 tests)

- **118 test cases | 0 errors | 0 failures** (1 pre-existing orphan).
- Coverage: FileFlowLayout (views, empty states, navigation, preview, grid), InputConfigPanel (key/mouse capture, Esc, reset, save), ThemeManager (tokens & variations), zoom (pointer invariant), keyboard panel (populated list).

## 10. Notable fixed bugs

- Missing `node_paths=PackedStringArray(...)` → NodePath exports resolved as strings (empty list / null nodes).
- `Tree` has no `drag_data/can_drop_data/drop_data` signals (they are virtual methods) → delegation via `RecentFilesTree.gd`.
- `InputMap.action_get_events()` returns `Array` (not `Array[InputEvent]`) in 4.7.
- `DirAccess.open()` without `access_flags` in 4.7; `Tree.icon_max_width` doesn't exist.
- Duplicated `ThemeManager.gd` — the autoload uses `script_gdscript/system/`.
- Tree rebuild inside mouse-selection events → `call_deferred`.
- `is_mouse_over_ui` was never updated.
- Inverted zoom formula (cursor didn't stay fixed).
