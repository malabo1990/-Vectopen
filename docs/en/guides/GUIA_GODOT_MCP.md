# Godot MCP Guide — Connection with AI Agents

## What is godot-mcp?

**godot-mcp** (tomyud1/godot-mcp v0.5.0) is a plugin for Godot 4 that connects the Godot editor with AI agents (Claude Code, OpenCode, Cursor, etc.) through the **Model Context Protocol (MCP)**.

It allows the AI agent to:
- Read and modify the Godot project
- Create and edit scripts, scenes, resources
- Run scenes, take screenshots, send input
- Inspect debugger errors
- Validate scripts

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│   Godot Editor   │◄───── 6505 ──────►│ godot-mcp-server │
│  (EditorPlugin)  │                    │   (Node.js)      │
└─────────────────┘                    └────────┬─────────┘
                                                │ MCP (stdio)
                                                ▼
                                        ┌──────────────────┐
                                        │   AI Agent        │
                                        │ (OpenCode, etc.)  │
                                        └──────────────────┘
```

The `godot-mcp-server` runs as a Node.js process. It acts as a bridge between the Godot editor (connected via WebSocket) and the AI agent (connected via MCP).

## How to Open the Project with godot-mcp

### 1. Open Godot
Simply open Godot and load the project `D:/2025/Godot/vectopen/project.godot`. The `godot_mcp` plugin activates automatically.

### 2. Verify connection
In the Godot editor, on the top bar, you should see an indicator:
- `MCP: Connecting...` (yellow) — connecting
- `MCP: No Agent` (orange) — connected to server, waiting for agent
- `MCP: Agent Active` (green) — an AI agent is connected

### 3. Connect an AI agent (OpenCode)
The AI agent (OpenCode) connects automatically when opened in the project. The configuration is at:
`C:\Users\User\.config\opencode\opencode.jsonc`

```json
"godot-mcp": {
  "type": "local",
  "command": ["C:\\Users\\User\\AppData\\Roaming\\npm\\godot-mcp-server.cmd"]
}
```

### 4. Available Tools

The plugin exposes **42 MCP tools**, including:

| Category | Tools |
|-----------|-------------|
| **Scenes** | `create_scene`, `read_scene`, `add_node`, `remove_node`, `instance_scene`, `rename_node`, `move_node` |
| **Scripts** | `create_script`, `edit_script`, `validate_script`, `read_file`, `list_scripts` |
| **Properties** | `set_node_properties`, `modify_node_property`, `get_node_properties` |
| **Resources** | `get_resource_info`, `set_resource_property`, `set_sprite_texture`, `set_mesh`, `set_material`, `set_collision_shape` |
| **Debugging** | `get_errors`, `get_console_log`, `run_scene`, `stop_scene`, `take_screenshot`, `send_input` |
| **Query** | `get_project_settings`, `get_godot_status`, `search_project`, `classdb_query`, `get_node_spatial_info` |
| **Configuration** | `configure_input_map`, `get_input_map`, `setup_autoload`, `update_project_settings` |

## Troubleshooting

### The MCP indicator does not appear
- Verify that `res://addons/godot_mcp/plugin.cfg` is in `editor_plugins/enabled` in `project.godot`
- Go to *Project > Project Settings > Plugins* and confirm that `godot_mcp` is active

### "Runtime helper is not connected"
- The Runtime Helper (`MCPRuntime`) allows the agent to interact with the running game (screenshots, input)
- It registers automatically as an autoload when the plugin is activated
- Verify it appears in *Project > Project Settings > Autoload* as `MCPRuntime`
- If it does not appear, register it manually pointing to `res://addons/godot_mcp/runtime/mcp_runtime.gd`

### The MCP server does not respond
- Verify that `godot-mcp-server.cmd` is installed: `npm install -g godot-mcp-server`
- Verify that port 6505 (WebSocket) is not occupied
- If the server went down, restart the AI agent

### Connection errors (ECONNREFUSED)
- The MCP server communicates on 2 ports:
  - `6505` — WebSocket for the Godot plugin
  - `6506` — Primary MCP API for the AI agent
- If one fails, it may be necessary to kill processes and restart:
  ```powershell
  netstat -ano | findstr 6505
  netstat -ano | findstr 6506
  taskkill /PID <PID> /F
  ```

## Technical Notes

- **Plugin version**: v0.5.0
- **Server path**: `C:\Users\User\AppData\Roaming\npm\godot-mcp-server.cmd`
- **Plugin path**: `res://addons/godot_mcp/`
- **WebSocket port**: 6505
- **MCP API port**: 6506
- **Project**: D:\2025\Godot\vectopen

---
*Documented by: Development Agent — July 2026*
