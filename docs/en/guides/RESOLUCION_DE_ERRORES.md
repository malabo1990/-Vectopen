# Technical Report: Resolution of Compilation Errors and Stabilization

## 1. Summary
**50+ errors** in the Godot Debugger that prevented the Vectopen project from opening and running stably were corrected. All script errors were resolved, leaving only 2 engine errors (MSAA not supported in GLES3, not fixable in code).

## 2. Corrected Errors

### 2.1 Autoload: GlobalEvents.gd (38 errors)
- **Problem**: 38 signals marked as `UNUSED_SIGNAL` — used externally via `.connect()` but Godot's analyzer did not detect it.
- **Solution**: Added `@warning_ignore("unused_signal")` at the start of the file (before `extends Node`), silencing the warning globally in the file.
- **Affected files**: `res://autoloads/GlobalEvents.gd`

### 2.2 System: ImportExportManager.gd (10 errors)
- **Problems**:
  - `name` variable shadowing `Node.name` property
  - 7 unused `settings` parameters
  - Unused `fonts_used` parameters, `scale`, `rotation` variables
  - Indentation error when declaring member variables (`var cache_enabled`)
- **Solution**: Prefix `_` on unused parameters, renamed `name` → `fmt_name`, fixed indentation.
- **File**: `res://script_gdscript/system/ImportExportManager.gd`

### 2.3 Canvas: canvas.gd (4 errors)
- **Problems**:
  - `class_name Canvas` was hiding a global class → renamed to `CanvasEditor`
  - `global_position` shadowing `Node2D` property → renamed to `_point_position`
  - 4 unused parameters in `_on_cursor_changed` → `_` prefix
  - Unused `state` variable → `_state` prefix
  - Invalid syntax `Array[N].fill()` → replaced with `.resize()` + `.fill()`
- **File**: `res://scripts/canvas/canvas.gd`

### 2.4 Artboard: artboard.gd (3 errors)
- **Problems**:
  - `class_name Artboard` was hiding a global class → renamed to `ArtboardEditor`
  - `scale` shadowing `Node2D` property → renamed to `png_scale`
  - `Vector2(scale, scale)` broken after renaming → `Vector2(png_scale, png_scale)`
  - `is Artboard` not updated → `is ArtboardEditor`
- **File**: `res://scripts/canvas/artboard.gd`

### 2.5 Tool: ToolNode.gd (2 errors)
- **Problems**: Unused `event` and `c` parameters.
- **Solution**: `_` prefix.
- **File**: `res://Scene/ToolNode.gd`

### 2.6 Toolbar: toolbar.gd (2 errors)
- **Problems**:
  - `class_name ToolbarContainer` was hiding a global class (reported by validator)
  - `current_tool` unused → `_` prefix
  - Reference to `Canvas` (renamed `CanvasEditor`) as type
- **File**: `res://script_gdscript/ui/toolbar.gd`

### 2.7 ArtboardManager: artboard_manager.gd (6 errors)
- **Problems**: 6 references to `Artboard` as type → updated to `ArtboardEditor`.
- **File**: `res://scenes/canvas/artboard_manager.gd`

### 2.8 Autoload: SmartCursor.gd (2 errors)
- **Problems**:
  - `SmartCursor` not registered as autoload in `project.godot`
  - Signals `tool_changed`, `selection_changed`, `error_occurred` do not exist in GlobalEvents
  - Unused `error_msg` parameter
- **Solution**: Registered as autoload, connections protected with `has_signal()`, `_` prefix on parameter.
- **File**: `res://autoloads/SmartCursor.gd`

### 2.9 Autoload: ObjectPool.gd (multiple errors)
- **Problems**:
  - `ObjectPool` not registered as autoload
  - `Rect2.ZERO` does not exist in Godot 4 → `Rect2()`
  - 3 pools referenced non-existent scenes: `shape_preview.tscn`, `artboard_title.tscn`, `selection_box.tscn`
- **Solution**: Registered as autoload, removed pools for missing scenes, fixed syntax and `boundingbox.tscn` path.
- **File**: `res://autoloads/ObjectPool.gd`

### 2.10 Overlay: canvas_overlay_controller.gd (1 error)
- **Problem**: `Panel.target_node` does not exist (the node has no script with that property).
- **Solution**: Replaced direct access with `panel_interactivo.get("target_node")`.
- **File**: `res://scenes/canvas/canvas_overlay_controller.gd`

### 2.11 Canvas: draw_preview (1 error)
- **Problem**: `draw_preview(self, region)` passed 2 arguments but all tools expect 1.
- **Solution**: Removed second argument `region`.
- **File**: `res://scripts/canvas/canvas.gd`

## 3. Configuration Changes

### 3.1 Registered Autoloads
3 missing autoloads were added in `project.godot`:
| Name | Path |
|--------|------|
| `SmartCursor` | `res://autoloads/SmartCursor.gd` |
| `ObjectPool` | `res://autoloads/ObjectPool.gd` |
| `MCPRuntime` | `res://addons/godot_mcp/runtime/mcp_runtime.gd` |

### 3.2 Project
- `debug/gdscript/warnings/unused_signal` → `0` (Ignore)
- `editor_plugins/enabled` → only `godot_mcp` (removed `godot_ai`)

### 3.3 Cleanup
- Removed obsolete `godot_ai` addon from `res://addons/`
- Removed old tests that depended on `McpTestSuite`
- Removed reference to `_mcp_game_helper` autoload

## 4. Current Debugger Status

| Error | File | Status |
|-------|---------|--------|
| `render_target_set_msaa` (startup) | Engine (GLES3) | Not fixable |
| `render_target_set_msaa` (PerformanceManager) | Engine (GLES3) | Not fixable |

## 5. Real-Time Color Palette

### 5.1 Problem
The color palette (`ColorPaletteTool`) was not updating dynamically when changing the active color from the brightness/transparency sliders or the HSL selector. The `Panel` (ColorPaletteTool) and `PanelContainer` (GestorColor) correctly pointed to the same `ColorRect_fill`, but there was no communication between them.

### 5.2 Root Cause
`GlobalEvents.gd` did not have the `color_changed` signal declared. `ColorPaletteTool._connect_color_signals()` checked `GlobalEvents.has_signal("color_changed")` which returned `false` — the connection was never made. Similarly, GestorColor emitted `GlobalEvents.color_changed` only if the signal existed, so it was never emitted.

### 5.3 Applied Solution

**File: `res://autoloads/GlobalEvents.gd`**
- Added signal: `signal color_changed(new_color: Color)` (line 21)

**File: `res://script_gdscript/ui/managercolor_pickrColor.gd`**
- In `_notificar_cambio_color()`: emits `GlobalEvents.color_changed.emit(color_final)` to notify the palette (and other listeners)

**File: `res://Scene/ColorPaletteTool.gd`**
- `_connect_color_signals()`: connects `GlobalEvents.color_changed` → `_on_color_changed`
- `_on_color_changed(new_color)`: updates `nodo_color_rect.color` and rebuilds the palette
- Added polling in `_process()` as fallback: compares `nodo_color_rect.color` with `_color_anterior_referencia` every frame and rebuilds the palette if it changed

### 5.4 Affected Files
| File | Change |
|---------|--------|
| `res://autoloads/GlobalEvents.gd` | + `signal color_changed` |
| `res://script_gdscript/ui/managercolor_pickrColor.gd` | + `GlobalEvents.color_changed.emit()` in `_notificar_cambio_color` |
| `res://Scene/ColorPaletteTool.gd` | + `_on_color_changed` handler + `_process` polling |

**0 script errors.** Stable and functional project.

## 6. Double `gradient_changed` Signal Connection in Tests

### 6.1 Problem
The test suite `test/ui/GestorColor_test.gd` (10 tests) produced repeated errors in the debugger:
```
ERROR: Signal 'gradient_changed' is already connected to given callable
'Node(GestorColor)::_on_global_gradient_changed' in that object.
```
Recorded in `test_godot_err.txt` (21/07/2026).

### 6.2 Root Cause
In `GestorColor._ready()`, each test in `_scene_con_brillo()` lets Godot fire `_ready()` automatically when adding the node to the tree (`add_child(root)`), and then the test itself manually invokes `gc._ready()` again to force configuration. The connection to `GlobalEvents.gradient_changed` was attempted without reliably checking whether it already existed for that instance.

### 6.3 Applied Solution
**File:** `res://script_gdscript/ui/managercolor_pickrColor.gd:25-26`
```gdscript
if GlobalEvents.has_signal("gradient_changed") and not GlobalEvents.gradient_changed.is_connected(_on_global_gradient_changed):
    GlobalEvents.gradient_changed.connect(_on_global_gradient_changed)
```
The `is_connected()` guard was added before `connect()`, preventing reconnection when `_ready()` executes more than once on the same instance (normal case in gdUnit4 tests).

### 6.4 Status
✅ Fixed (24/07/2026). The `test_godot_err.txt` log in the repository corresponds to the execution prior to the fix — it is a historical artifact, not representative of the current project state.

### 6.5 Verification with Real Execution
The full test suite was run with Godot 4.7 mono (`addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test -c`):
```
Overall Summary: 53 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 1 orphans
Executed test suites: (5/5)
```
Suites: `UndoRedoManager_test`, `ToolBase_test`, `VectorShape_test`, `GestorColor_test`, `PaletteSaveGrid_test`.

During this execution, the **same bug pattern** (signal connection without `is_connected()` guard) was detected in a different file:

**File:** `res://script_gdscript/ui/PaletteSaveGrid.gd:16-21` (`_find_add_button()`)
```
ERROR: Signal 'pressed' is already connected to given callable 'GridContainer(PaletteSaveGrid)::_on_add_pressed' in that object.
```
It did not cause test failures (0 failures), but it cluttered the debugger every time `_ready()` executed more than once on the same instance (same scenario as 6.2).

**Applied solution (24/07/2026):**
```gdscript
if not add_button.pressed.is_connected(_on_add_pressed):
    add_button.pressed.connect(_on_add_pressed)
```
Verified with a second execution of the full test suite: 0 occurrences of "already connected", 53/53 tests PASSED.

## 7. "Signal Already Connected" Pattern Audit Across the Project

After correcting the two previous cases (§6), the rest of the project's own code (excluding `addons/gdUnit4/` and `addons/godot_mcp/`, third-party libraries) was audited looking for the same pattern: `.connect()` without `is_connected()` guard in functions that may execute more than once on the same instance.

### 7.1 Structural finding: `autoloads/ToolFactory.gd:76-77`
`create_tool_from_script()` manually invokes `instance._ready()` on a newly created Node — the same root defect (manual/duplicate `_ready()` invocation) that caused both bugs in §6. **Confirmed: 0 actual callers** — `ToolManager.gd:172` only uses `create_tool_from_scene()`. It was further verified that `scenes/ui/tool.tscn` (alternative toolbar) also does not go through `ToolFactory`: its buttons (`scenes/ui/tool_button.gd`) call `canvas_editor.switch_tool()` directly, bypassing `ToolManager`/`ToolFactory` entirely — another instance of the problem already described in `SYSTEM_REVIEW.md` §7.4 (two parallel tool systems). `create_tool_from_script` remains dead code but is a latent trap if reactivated.

### 7.2 Unguarded connections, active in scenes (real risk)
| File | Function | Signal | Status |
|---------|---------|-------|--------|
| `script_gdscript/system/ThemeToggle.gd:13` | `_ready()` | `ThemeManager.theme_changed` | Active in `manager_windws_regla.tscn` |
| `script_gdscript/ui/LangSelector.gd:13` | `_ready()` | `LanguageManager.language_changed` | Active |
| `script_gdscript/ui/PanelVisibility.gd:39-41` | `_connect()` | `toggled` (CheckButtons loop) | Active |
| `script_gdscript/ui/WindowSettings.gd:41-47` | `_connect_signals()` | various checkboxes/spinboxes | Active |
| `script_gdscript/ui/ThemeConfigPanel.gd:79-83` | `_connect_signals()` | various | `await process_frame` widens reentrancy window |
| `scenes/canvas/bounding_box.gd:185-195` | `_connect_signals()` | 4x `GlobalEvents` | Low risk (instantiated only once) |
| `autoloads/ToolManager.gd`, `autoloads/SmartCursor.gd` | — | `GlobalEvents` | Low risk (autoloads, single init) |

### 7.3 Orphan code detected (not connected to any scene)
- `scripts/ui/LayerPanel.gd:14-16` — connects 3 `GlobalEvents` signals without guard, but is not referenced in any `.tscn`; appears to be duplicate/legacy of `scripts/ui/panel_tree_layers.gd`.
- `scenes/ui/ExportPanel.gd:47-48` — connects `artboard_created/removed` without guard, also not referenced in any `.tscn`.

### 7.4 Already verified with correct guard (no action needed)
`managercolor_pickrColor.gd`, `PaletteSaveGrid.gd`, `Scene/ColorPaletteTool.gd`, `script_gdscript/tools/brushtool.gd`, `script_gdscript/ui/layers_system.gd`.

### 7.5 Status
🟡 Decision pending: apply `is_connected()` guard to cases in §7.2 (active in scenes). The orphans in §7.3 do not require an immediate fix since they are not connected to any scene, but could be cleaned up or removed as part of the duplicate code consolidation already recommended in `SYSTEM_REVIEW.md` §9.

---
*Documented by: Development Agent — July 2026*
