# Guía de Godot MCP — Conexión con Agentes IA

## ¿Qué es godot-mcp?

**godot-mcp** (tomyud1/godot-mcp v0.5.0) es un plugin para Godot 4 que permite conectar el editor de Godot con agentes de IA (Claude Code, OpenCode, Cursor, etc.) mediante el protocolo **Model Context Protocol (MCP)**.

Permite al agente IA:
- Leer y modificar el proyecto Godot
- Crear y editar scripts, escenas, recursos
- Ejecutar escenas, tomar screenshots, enviar input
- Inspeccionar errores del debugger
- Validar scripts

## Arquitectura

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│   Godot Editor   │◄───── 6505 ──────►│ godot-mcp-server │
│  (EditorPlugin)  │                    │   (Node.js)      │
└─────────────────┘                    └────────┬─────────┘
                                                │ MCP (stdio)
                                                ▼
                                        ┌──────────────────┐
                                        │   Agente IA       │
                                        │ (OpenCode, etc.)  │
                                        └──────────────────┘
```

El `godot-mcp-server` se ejecuta como un proceso Node.js. Actúa como puente entre el editor de Godot (conectado vía WebSocket) y el agente de IA (conectado vía MCP).

## Cómo Abrir el Proyecto con godot-mcp

### 1. Abrir Godot
Simplemente abrí Godot y cargá el proyecto `D:/2025/Godot/vectopen/project.godot`. El plugin `godot_mcp` se activa automáticamente.

### 2. Verificar conexión
En el editor de Godot, en la barra superior, deberías ver un indicador:
- `MCP: Connecting...` (amarillo) — conectándose
- `MCP: No Agent` (naranja) — conectado al servidor, esperando agente
- `MCP: Agent Active` (verde) — un agente IA está conectado

### 3. Conectar un agente IA (OpenCode)
El agente IA (OpenCode) se conecta automáticamente al abrirse en el proyecto. La configuración está en:
`C:\Users\User\.config\opencode\opencode.jsonc`

```json
"godot-mcp": {
  "type": "local",
  "command": ["C:\\Users\\User\\AppData\\Roaming\\npm\\godot-mcp-server.cmd"]
}
```

### 4. Herramientas Disponibles

El plugin expone **42 herramientas MCP**, incluyendo:

| Categoría | Herramientas |
|-----------|-------------|
| **Escenas** | `create_scene`, `read_scene`, `add_node`, `remove_node`, `instance_scene`, `rename_node`, `move_node` |
| **Scripts** | `create_script`, `edit_script`, `validate_script`, `read_file`, `list_scripts` |
| **Propiedades** | `set_node_properties`, `modify_node_property`, `get_node_properties` |
| **Recursos** | `get_resource_info`, `set_resource_property`, `set_sprite_texture`, `set_mesh`, `set_material`, `set_collision_shape` |
| **Depuración** | `get_errors`, `get_console_log`, `run_scene`, `stop_scene`, `take_screenshot`, `send_input` |
| **Consulta** | `get_project_settings`, `get_godot_status`, `search_project`, `classdb_query`, `get_node_spatial_info` |
| **Configuración** | `configure_input_map`, `get_input_map`, `setup_autoload`, `update_project_settings` |

## Solución de Problemas

### El indicador MCP no aparece
- Verificar que `res://addons/godot_mcp/plugin.cfg` esté en `editor_plugins/enabled` en `project.godot`
- Ir a *Project > Project Settings > Plugins* y confirmar que `godot_mcp` esté activo

### "Runtime helper is not connected"
- El Runtime Helper (`MCPRuntime`) permite al agente interactuar con el juego en ejecución (screenshots, input)
- Se registra automáticamente como autoload al activar el plugin
- Verificar que aparezca en *Project > Project Settings > Autoload* como `MCPRuntime`
- Si no aparece, registrarlo manualmente apuntando a `res://addons/godot_mcp/runtime/mcp_runtime.gd`

### El servidor MCP no responde
- Verificar que `godot-mcp-server.cmd` esté instalado: `npm install -g godot-mcp-server`
- Verificar que el puerto 6505 (WebSocket) no esté ocupado
- Si el servidor se cayó, reiniciar el agente IA

### Errores de conexión (ECONNREFUSED)
- El servidor MCP se comunica en 2 puertos:
  - `6505` — WebSocket para el plugin de Godot
  - `6506` — API primaria MCP para el agente IA
- Si uno falla, puede ser necesario matar procesos y reiniciar:
  ```powershell
  netstat -ano | findstr 6505
  netstat -ano | findstr 6506
  taskkill /PID <PID> /F
  ```

## Notas Técnicas

- **Versión del plugin**: v0.5.0
- **Ruta del servidor**: `C:\Users\User\AppData\Roaming\npm\godot-mcp-server.cmd`
- **Ruta del plugin**: `res://addons/godot_mcp/`
- **Puerto WebSocket**: 6505
- **Puerto MCP API**: 6506
- **Proyecto**: D:\2025\Godot\vectopen

---
*Documentado por: Agente de Desarrollo — Julio 2026*
