# System Review: Vectopen v0.1.1

## 1. Project Overview

| Metric | Value |
|--------|-------|
| **Engine** | Godot 4.7 (mono) |
| **Renderer** | gl_compatibility (OpenGL 3.3) |
| **Total scripts** | 130 (128 GDScript + 2 C#) |
| **Autoloads** | 11 registered |
| **Tools** | 18 tool scripts + 8 scene-based tools |
| **Scenes** | ~40 .tscn files |
| **Lines of code** | Estimated 40,000+ |

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     AUTOLOADS (11)                        │
│  GlobalEvents  DataRepository  ToolManager  SmartCursor  │
│  ObjectPool  PerformanceManager  ThemeManager            │
│  ImportExportManager  ExportCache  GlobalUI  MCPRuntime  │
└──────────┬──────────────────────────────────────────┬────┘
           │ signal bus                │ references
           ▼                          ▼
┌──────────────────────┐   ┌──────────────────────────┐
│   CANVAS (CanvasEditor)│   │   UI (Control nodes)     │
│  ├─ Camera2D          │   │  ├─ Toolbar              │
│  ├─ ArtboardsContainer│   │  ├─ ExportPanel           │
│  │  └─ ArtboardEditor │   │  ├─ LayerSystem           │
│  ├─ CanvasLayer (UI)  │   │  ├─ ColorPicker           │
│  └─ BoundingBox       │   │  └─ SmartCursorSettings   │
└──────────────────────┘   └──────────────────────────┘
           │                          ▲
           │ tool calls               │ signals
           ▼                          │
┌─────────────────────────────────────┴──────────────────┐
│                     TOOLS (18)                          │
│  MoveTool  CircleTool  RectangleTool  PenTool          │
│  BrushTool  TextTool  Star4/5Tool  TriangleTool        │
│  PentagonTool  WaterDropTool  NodeSelectionTool        │
│  ArtboardTool  BezierTool  ParagraphTool  Drawing       │
└────────────────────────────────────────────────────────┘
```

---

## 3. Data Layer

### 3.1 Resource-based data model
```
VectopenProject (Resource)
  ├── project_name: String
  ├── file_path: String
  ├── artboards: Dictionary<String, VectopenArtboard>
  └── layers: Dictionary<String, VectopenLayer>

VectopenArtboard (Resource)
  ├── id, name, position, size: Vector2
  └── metadata: Dictionary

VectopenLayer (Resource)
  ├── id, name, artboard_id
  ├── visible, locked: bool
  └── opacity: float

VectopenShape (Resource)
  ├── id, shape_type, position, rotation, scale
  ├── stroke_color, fill_color, stroke_width
  ├── points: PackedVector2Array
  └── text_content: String
```

### 3.2 Data Flow
```
User Input → Tool (GDScript) → DataRepository (autoload)
                                  ↕
                            VectopenProject (Resource)
                                  ↕
                            GlobalEvents (signals)
                                  ↕
                            UI updates / Canvas redraw
```

**Pattern: DataRepository** acts as a god-object — it handles:
- Project CRUD (artboards, layers, shapes)
- Undo/redo stack
- Serialization/deserialization
- Session management
- Auto-save

---

## 4. Tool Architecture

### 4.1 Two parallel tool systems

**System A: Scene-based tools (via ToolWrapper)**
```
tools/move_tool/move_tool.tscn → ToolWrapper → Tool (RefCounted)
tools/rectangle_tool/rectangle_tool.tscn → ToolWrapper → RectangleTool (RefCounted)
```
- Tools are `RefCounted`, not `Node` — no lifecycle
- Wrapped in a `ToolWrapper` (Node) that bridges to the scene tree
- Activated/deactivated via `activate()`/`deactivate()` methods
- Input via `handle_input(event)` → returns bool (handled or not)

**System B: Direct scripts (registered in ToolManager)**
```
autoloads/ToolManager.gd → _register_tool(name, display_name, scene_path, shortcut)
```
- Tools are loaded dynamically from scene paths
- Managed by ToolManager autoload
- Canvas calls `tool_manager.get_current_tool_instance()` to delegate input

### 4.2 Tool interface
```
Tool (RefCounted) / ToolNode (Node)
  ├── canvas: Node2D
  ├── _init(p_canvas)
  ├── activate()
  ├── deactivate()
  ├── handle_input(event) → bool
  ├── draw_preview(c: Node2D)
  └── get_class_name() → String
```

---

## 5. Scene Tree (main.tscn)

```
Control (root)
├── Panel_toolbar / ToolbarContainer
├── CanvasRoot (CanvasEditor) 
│   ├── Camera2D
│   ├── ArtboardsContainer
│   │   └── Artboard (ArtboardEditor)
│   ├── BoundingBox
│   └── CanvasLayer
│       └── main (main.tscn instance) ← recursive! See §7.2
├── Panel_layers / LayerSystem
├── ExportPanel
├── ColorPicker
├── SmartCursorSettings
└── ToolProperties
```

---

## 6. Signal Architecture

### 6.1 GlobalEvents bus signals
```
ARTBOARDS:  artboard_created/deleted/selected/moved/resized
            active_artboard_changed
COLOR:      gradient_changed, color_picker_opened/closed
LAYERS:     layer_created/deleted/selected/reordered
            layer_visibility_toggled, layer_locked_toggled
OBJECTS:    object_created/selected/deleted/transformed/style_changed
EFFECTS:    effect_parameter_updated
EXPORT:     export_finished/error, import_started/finished/error
SYSTEM:     performance_warning, renderer_changed, memory_pressure_high
PROJECT:    autosave_finished, project_saved/loaded
DATA:       data_project_loaded/saved/closed
            data_shape_created/deleted/changed/selected
            data_selection_changed/cleared
            data_layer_created/deleted/changed/reordered
            data_artboard_created/deleted/changed
            data_tool_changed/config_changed
            data_undo/redo_state_changed/performed
            data_session_state_changed
```

---

## 7. Issues & Risks

### 7.1 CRITICAL: Recursive scene instance
`main.tscn` is instanced inside `canvas.tscn` (line 29: `instance=ExtResource("7_1ckkv")` which points to `res://scenes/ui/main.tscn`). But `main.tscn` also references `CanvasRoot`. This creates a recursive dependency — `canvas.tscn` loads `main.tscn` and `main.tscn` expects `canvas.tscn` to exist. This works at runtime only because of Godot's lazy loading, but it's fragile.

### 7.2 High coupling to autoloads
Most scripts reference autoloads directly as globals:
```gdscript
GlobalEvents.emit_safe(...)
DataRepository.get_active_artboard()
ToolManager.get_current_tool_instance()
```
This is convenient but makes testing impossible and creates hidden dependencies. A dependency injection pattern would be better.

### 7.3 DataRepository is a god object
DataRepository (770+ lines) handles: CRUD for artboards/layers/shapes, undo/redo, serialization, session management, auto-save. This should be split into:
- `ProjectManager` — project CRUD, file I/O
- `UndoRedoManager` — undo/redo stack
- `SessionManager` — auto-save, recovery
- Keep DataRepository as a facade if needed

### 7.4 Two parallel tool systems
Tools are registered in both `ToolManager` (autoload) AND as direct children in `canvas.tscn`. Some tools use the `Tool` (RefCounted) pattern, others use `ToolNode` (Node). This dual system leads to:
- Duplicate registration logic
- Inconsistent input handling
- Confusion about which system a new tool should use

**Recommendation**: Standardize on one system. `RefCounted` + `ToolWrapper` is more performant (no Node overhead).

### 7.5 Missing asset files
- `res://scenes/canvas/shape_preview.tscn` — referenced by ObjectPool, doesn't exist
- `res://scenes/canvas/artboard_title.tscn` — referenced by ObjectPool, doesn't exist
- `res://scenes/canvas/selection_box.tscn` — referenced by ObjectPool, doesn't exist
- (These were removed from the pool config, but the scenes are still referenced elsewhere)

### 7.6 UI code duplication
Multiple button scripts (`button_circulo.gd`, `button_cuadrado.gd`, `button_star4.gd`, etc.) have nearly identical code (~45 lines each) with only the tool name changed. This is ~360 lines of duplicated code that could be a single parameterized script.

### 7.7 Mixed script locations
Scripts are spread across:
- `res://scripts/` — some tools, canvas core
- `res://script_gdscript/` — most tools, UI, system
- `res://scenes/canvas/` — scene-attached scripts
- `res://scenes/ui/` — UI scene scripts
- `res://Scene/` — base classes, utilities
- `res://tools/` — tool scenes + wrapper

This fragmentation makes navigation difficult. **Recommendation**: Consolidate to `res://scripts/` with `res://scripts/canvas/`, `res://scripts/tools/`, `res://scripts/ui/`, `res://scripts/system/`.

### 7.8 C# hybrid (unused)
The project has `Vectopen.csproj` + `Vectopen.sln` + 2 `.cs` files, but all gameplay code is GDScript. The C# project adds build complexity with no benefit currently. Either remove it or migrate critical paths to C# for performance.

### 7.9 Renderer: gl_compatibility
The project uses `gl_compatibility` which:
- ❌ No MSAA 2D support (causes the only remaining errors)
- ❌ No SDFGI, no volumetric fog
- ❌ Limited to OpenGL 3.3 features
- ✅ Runs on older hardware and web exports

**Recommendation**: Switch to `forward+` for development. Keep `gl_compatibility` as a mobile/web fallback.

### 7.10 PerformanceManager emits MSAA error every 5s
The adaptive quality system (`PerformanceManager.gd:284`) tries to apply MSAA settings every ~5 seconds, which fails on `gl_compatibility`. Either:
- Disable the adaptive quality system when on GLES3
- Or switch to forward+ where MSAA works

---

## 8. Strengths

### 8.1 Clean signal architecture
GlobalEvents provides a well-organized signal bus. The `emit_safe()` pattern prevents crashes when signals don't exist.

### 8.2 Resource-based data model
Using `Resource` for data (VectopenProject, VectopenShape, etc.) is the correct Godot pattern. Resources serialize natively, can be inspected in the editor, and are reference-counted.

### 8.3 RefCounted tool pattern
Tools as `RefCounted` (not Nodes) is the right choice for performance — no scene tree overhead, no lifecycle management, lightweight.

### 8.4 ObjectPool system
The ObjectPool for BoundingBox instances is a good optimization pattern, preventing allocation spikes.

### 8.5 Undo/redo system
DataRepository has a proper undo/redo stack using `undo_redo` methods with `_do_`/`_undo_` prefix pattern.

---

## 9. Recommendations (Priority Order)

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 🔴 P0 | Fix recursive scene (main.tscn ↔ canvas.tscn) | 1 day | Crash prevention |
| 🔴 P0 | Standardize tool architecture (one system) | 3 days | Maintainability |
| 🟡 P1 | Split DataRepository into subsystems | 5 days | Testability, maintainability |
| 🟡 P1 | Switch to forward+ renderer | 10 min | Visual quality, MSAA working |
| 🟡 P1 | Consolidate project folder structure | 1 day | Developer QoL |
| 🟢 P2 | Remove C# project or use it fully | 1 day | Build simplicity |
| 🟢 P2 | Parameterize duplicate button scripts | 1 day | 360 lines saved |
| 🟢 P2 | Add dependency injection for autoloads | 3 days | Testability |
| 🔵 P3 | GDExtension + Blend2D for vector rendering | 2-4 weeks | Professional quality |
| 🔵 P3 | Port critical paths to C# | 2 weeks | Performance |

---

## 10. Key Metrics

| Category | Count |
|----------|-------|
| Autoloads | 11 |
| Tools (scripts) | 18 |
| UI scripts | 33 |
| System scripts | 6 |
| Utility scripts | 9 |
| Data resources | 4 |
| Scene files | ~40 |
| Draw calls (estimate) | 50-200 |
| Debugger errors | 2 (both engine, not code) |

---

*Reviewed by: Agente de Desarrollo — Julio 2026*
