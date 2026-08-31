# Godot MCP — editor bridge for AI assistants

This addon lets an AI assistant (Claude Code, or any MCP client) drive the Godot
**editor** and the **running game**: read/edit scripts and scenes, add nodes,
run a scene, take screenshots, synthesize input, inspect live nodes.

If you are an AI assistant and MCP calls are failing, read **Troubleshooting**
below first — it is almost always the port.

---

## Architecture

```
AI client (Claude Code, …)
      │  stdio (MCP protocol)
      ▼
godot-mcp server        ← a separate process, spawned by the AI client.
      │                    Listens on a WebSocket port (see below).
      │  WebSocket
      ├─────────────────────────────► addons/godot_mcp/plugin.gd   (EDITOR)
      │                                mcp_client.gd — edits files, runs scenes,
      │                                queries the open scene tree.
      │
      └─────────────────────────────► MCPRuntime autoload            (RUNNING GAME)
                                       runtime/mcp_runtime.gd — screenshots,
                                       send_input, query_runtime_node. Only
                                       present while the game is playing AND the
                                       plugin was toggled on at least once.
```

Two independent WebSocket clients (`mcp_client.gd` in the editor,
`mcp_runtime.gd` in the game) connect to the **same** godot-mcp server and
identify with `role="editor"` / `role="runtime"`.

---

## Connection config

Both clients connect to:

| | Value |
|---|---|
| Default URL | `ws://127.0.0.1:6515` |
| Override | environment variable `GODOT_MCP_URL` (e.g. `ws://127.0.0.1:6505`) |

Defined once in `mcp_client.gd` (`DEFAULT_URL`) and mirrored in
`runtime/mcp_runtime.gd` (`DEFAULT_SERVER_URL`). **Keep them equal.**

> The port has moved before (`6505` → `6515`). If the AI client's godot-mcp
> server reports a different port, set `GODOT_MCP_URL` or update both constants.

---

## Enabling

1. **Project → Project Settings → Plugins →** enable **"Godot MCP"**.
   - Toggling it *on* also registers the `MCPRuntime` autoload
     (`_enable_plugin()` in `plugin.gd`). Toggling it *off* removes it.
2. A status label appears in the **editor toolbar** (top bar). Its text is the
   fastest way to see what's happening:

   | Label | Meaning |
   |---|---|
   | `MCP: Connecting...` (yellow) | trying to reach the server; server not up or wrong port |
   | `MCP: No Agent` (orange) | connected to the server, but no AI client attached |
   | `MCP: Agent Active` / `Agents (N)` (green) | an AI client is attached — you're good |
   | `MCP: Disconnected` (red) | was connected, lost it |
   | `… + Runtime` suffix | the running game's `MCPRuntime` is also connected |

3. The **Output** panel prints `[MCP] Connecting to ws://127.0.0.1:6515...` and
   then `[Godot MCP] Connected to MCP server`.

---

## Troubleshooting

### The status label is stuck on `MCP: Connecting...`

The plugin can't reach the server. In order of likelihood:

1. **Port mismatch.** The godot-mcp server the AI client spawned is on a
   different port than `DEFAULT_URL`. Fixes:
   - Ask the AI client / check its logs for the actual port, then
     `set GODOT_MCP_URL=ws://127.0.0.1:<port>` (Windows) /
     `export GODOT_MCP_URL=ws://127.0.0.1:<port>` before launching Godot, **or**
   - edit `DEFAULT_URL` in `mcp_client.gd` and `DEFAULT_SERVER_URL` in
     `runtime/mcp_runtime.gd`.
2. **The server isn't running.** It's spawned by the AI client — restart that
   client. An `ECONNREFUSED` in the AI client's tool output means the server
   died; restarting the client respawns it.
3. **Plugin didn't reload after a code change.** Toggle the plugin off/on in
   Project Settings → Plugins, or restart the editor. `mcp_client.gd` is a
   `@tool` script; the editor caches it.

### `get_godot_status` from the AI side says `connected: false`

The server is up (the AI can reach it) but no editor is attached. Open this
project in the Godot **editor** with the plugin enabled. A headless
`--script`/`--play` run does **not** attach the editor plugin.

### Screenshots / `send_input` / `query_runtime_node` fail

Those need `MCPRuntime` in the **running** game:
- Run the scene via `run_scene({wait_for_runtime: true})` (or the play button).
- The autoload only exists if the plugin was toggled **on** at least once
  (check `project.godot` for `autoload/MCPRuntime`).
- The label should show `… + Runtime`.

### Editor calls work, but `run_scene` never reaches "playing"

Autoload-heavy project → bump `startup_timeout_ms` (15000–20000).

---

## Tool groups (`tools/`)

| File | Tools |
|---|---|
| `script_tools.gd` | read/create/edit/validate `.gd`, attach/detach |
| `scene_tools.gd` | create/read scenes, add/move/remove nodes, set properties, connect signals |
| `project_tools.gd` | project settings, input map, autoloads, run/stop scene, errors, console log, screenshots, send_input, query_runtime_node |
| `asset_tools.gd` | generate 2D assets, materials, meshes, sprite textures |
| `file_tools.gd` | list/read/rename/delete files, rescan filesystem |
| `visualizer_tools.gd` | editor viewport helpers |

`tool_executor.gd` dispatches by name; `runtime/mcp_runtime.gd` handles the
`role="runtime"` subset from inside the game.

---

## Files

```
plugin.gd            EditorPlugin entry point; status label; autoload (un)register
mcp_client.gd        editor-side WebSocket client  (DEFAULT_URL)
tool_executor.gd     name → tool dispatch
tools/*.gd           tool implementations
runtime/mcp_runtime.gd   in-game autoload  (DEFAULT_SERVER_URL — keep == DEFAULT_URL)
utils/               path + Variant<->JSON helpers
cache/screenshots/   take_screenshot output (git-ignored)
```
