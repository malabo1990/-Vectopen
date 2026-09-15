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

## Key Autoloads (28 — see `project.godot` [autoload] for the full list)
- `GlobalEvents` — Central signal bus (~50 typed signals, use `emit_safe()`)
- `DataRepository` — Central data model (project data, session data, auto-save)
- `ToolManager` — Tool switching and input forwarding
- `HistoryManager` — Undo/redo history stack
- `SaveManager` — Project save/load operations
- `MCPRuntime` (`addons/godot_mcp/runtime/mcp_runtime.gd`) — added by the
  `godot_mcp` plugin; connects to `ws://127.0.0.1:6515`. **Reconnect-loops and
  spams `push_error` into `user://logs/` if that server isn't running** — see
  the disk-hygiene section below.
- `VectopenMCPServer` (`script_gdscript/system/VectopenMCPServer.gd`) — embedded
  MCP HTTP server, opt-in via `user://vectopen_mcp.cfg` (`enabled`, port 6520).

## ⚠️ godot-mcp / disk hygiene — READ BEFORE agent-driven Godot work

**Real incident (2026-09):** left running with the `godot_mcp` plugin enabled,
no MCP server up, and ~7 zombie `Godot_v4.7*.exe` processes, this project wrote
**~250 GB** of error logs to `%APPDATA%\Godot\app_userdata\Vectopen\logs\`
(13 files × ~19 GB). Play then hung (port 6520 held by a zombie) and free disk
swung ±150 GB as logs rotated.

Rules:
- **Normal editing:** keep the `godot_mcp` editor plugin **disabled**
  (Project → Project Settings → Plugins) and `vectopen_mcp.cfg` → `enabled=false`.
  Turn them on only for an actual agent session, then off again.
- **Do NOT run `claude.bat`** unless actively doing agent-driven Godot dev — it
  spawns the `godot-mcp-server` node processes the plugin then loops against when
  they die.
- **One Godot editor instance at a time.** Kill stale `Godot_v4*` and
  `node … godot-mcp-server` processes before and after any MCP session.
- Play hangs / slow load → check for zombie Godot processes and the size of
  `%APPDATA%\Godot\app_userdata\Vectopen\logs\`; delete it if over ~1 GB.
- `project.godot` `[debug]` has `file_logging/max_log_files=3` to cap the damage.
- Full playbook: the `godot-mcp-hygiene` Claude Code skill.

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
- Use `script_gdscript/` over `scripts/` (latter is legacy)
- The old `Scene/` directory was removed (code was deprecated)
- C# support was removed — project is 100% GDScript. No .NET SDK required.
- Export presets in `export_presets.cfg` (Windows, Linux, macOS, Web)
- Docs: `docs/en/` (English: guides/, reports/, reference/), `docs/es/` (Spanish: guías/, informes/, referencia/)
