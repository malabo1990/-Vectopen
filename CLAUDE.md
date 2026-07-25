# Vectopen — Godot 4.7 Vector Graphics Editor

## Project Context
- Engine: Godot 4.7 (GL Compatibility renderer, `rendering_method=mobile`)
- Language: GDScript (~98%), C# (~2%, legacy)
- Main scene: `res://scenes/canvas/canvas.tscn` (via UID)
- Window: 1920x1080 maximized
- Version: 0.1.1
- Testing: gdUnit4 (tests in `test/`)
- Format: `.vectopen` (JSON-based project files)

## Architecture (MVC-like)
- UI (`main.tscn`) → Signals → GlobalEvents (EventBus) → DataRepository (Model)
- ToolManager → Canvas (View)
- All data mutations must go through DataRepository for undo/redo

## Key Autoloads (21)
- `GlobalEvents` — Central signal bus (~50 typed signals, use `emit_safe()`)
- `DataRepository` — Central data model (project data, session data, auto-save)
- `ToolManager` — Tool switching and input forwarding
- `HistoryManager` — Undo/redo history stack
- `SaveManager` — Project save/load operations
- See `project.godot` [autoload] section for full list

## Code Conventions
- Files: `snake_case.gd` | Classes: `PascalCase` | Vars: `snake_case`
- Use `%UniqueName` for node access (not `get_node()`)
- Prefer `GlobalEvents.emit_safe()` over direct `emit_signal()`
- Tools must implement: `activate()`, `deactivate()`, `handle_input(event) -> bool`
- Canvas rendering: `queue_redraw()` + `_draw()`
- Static typing required on all function signatures

## Important Notes
- Do NOT modify `.tscn` files directly — use godot-mcp scene tools
- UID files (`*.uid`) are tracked in git (do not delete)
- The old `Scene/` directory contains deprecated files — avoid using them
- Use `script_gdscript/` over `scripts/` (latter is legacy)
- Export presets in `export_presets.cfg` (Windows, Linux, macOS, Web)
