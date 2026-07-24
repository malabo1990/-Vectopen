---
name: vectopen-report
description: >
  Contexto técnico completo del editor vectorial Vectopen (Godot 4.7).
  Arquitectura, issues conocidos, roadmap y recomendaciones.
  Cargar automáticamente al trabajar en este proyecto.
---

# Vectopen — Contexto Técnico para IA

> **Cargar este skill antes de implementar cualquier cambio en Vectopen.**

## Resumen Ejecutivo

Vectopen es un editor vectorial 2D (similar a Illustrator / Figma) construido en **Godot 4.7** con **GDScript** (~98%) y **C# .NET 8** (~2%). Usa renderer `gl_compatibility`.

- **Versión:** 0.1.1
- **Escena principal:** `res://scenes/canvas/canvas.tscn`
- **Resolución:** 1920×1080 (maximizada)
- **Formato de proyecto:** `.vectopen` (JSON)
- **Autoloads (4):** `GlobalEvents`, `GlobalUI`, `DataRepository`, `ToolManager`

## Arquitectura (MVC-like)

```
UI (main.tscn) ──señales──► EventBus (GlobalEvents) ──► DataRepository (Modelo)
                                   │
                                   ▼
                            ToolManager ──► Canvas (Vista)
```

- **DataRepository:** 1166 líneas. Modelo central con `ProjectData`, `SessionData`, `UndoRedoManager` custom, auto-save, recovery, snap-to-grid.
- **ToolManager:** 379 líneas. Sistema modular con `ToolInfo`, carga dinámica desde escenas, input forwarding.
- **GlobalEvents:** 113 líneas. ~50 señales tipadas con `emit_safe()`.

## Issues Críticos Conocidos

1. ✅ **`res://tools/`** — 8 escenas `.tscn` creadas (select, move, pen, bezier, rectangle, ellipse, text, hand) con `ToolWrapper` Node. ToolManager puede cargarlas. Falta conectar ToolManager al Canvas (exportar tool scripts vs cargar desde ToolManager).
2. **102 scripts planos** ~~en `script_gdscript/`~~ ✅ **Reorganizado** en subcarpetas: `tools/`, `shapes/`, `canvas/`, `ui/`, `data/`, `system/`, `utils/`.
3. **`Tool.gd` extiende `RefCounted`** — no puede ir al scene tree, inconsistente con herramientas que operan sobre nodos.
4. **`main.tscn` monolítica** — 1000+ líneas, posicionamiento absoluto, no responsive.
5. **Sin tests** — 0 cobertura.
6. **Archivos obsoletos:** `.csproj.old`, `.af~lock~`, `tooltipshover 2.gd`.

## Convenciones de Código

- **Nomenclatura:** Archivos en `snake_case.gd` (ej: `bezier_tool.gd`), clases en `PascalCase`.
- **Señales:** Usar `GlobalEvents.emit_safe()` en vez de `emit_signal()` directo.
- **Herramientas:** Toda tool debe implementar `activate()`, `deactivate()`, `handle_input(event) -> bool`.
- **Data:** Toda modificación de datos debe pasar por `DataRepository` (para undo/redo).
- **Canvas:** Usar `queue_redraw()` + `_draw()` para rendering vectorial.

## Referencia Rápida

| Sistema | Archivo clave | Líneas |
|---|---|---|
| Event Bus | `autoloads/GlobalEvents.gd` | 113 |
| Modelo/Estado | `autoloads/DataRepository.gd` | 1166 |
| Tool Manager | `autoloads/ToolManager.gd` | 379 |
| GlobalUI | `autoloads/GlobalUI.gd` | 8 |
| Canvas principal | `scripts/canvas/canvas.gd` | 321 |
| Bezier tool | `script_gdscript/tools/beziertool.gd` | 337 |
| Node editor | `script_gdscript/tools/NodeSelectionTool.gd` | 413 |
| Layer system | `script_gdscript/ui/layers_system.gd` | 205 |
| Bounding box | `scenes/canvas/bounding_box.gd` | 171 |
| SDF shader | `shader/sdf_circle.gdshader` | 37 |
| Export manager | `script_gdscript/system/ImportExportManager.gd` | 72 |

## Roadmap Priorizado

1. ✅ **Fase 1** — Limpiar archivos obsoletos
2. ✅ **Fase 2** — Reorganizar `script_gdscript/` en subcarpetas ✅ y crear `res://tools/` ✅
3. **Fase 3** — Refactorizar Tool base class, main.tscn, UndoRedoManager, agregar tests
4. **Fase 4** — Plugins, i18n, export cruzado, temas

> Para el detalle completo, ver `docs/VECTORIAL_REPORT.md`.

## Acceso a godot-ai (MCP) — instrucciones correctas (verificado 2026-07-15)

`addons/godot_ai` ya está instalado y habilitado en `project.godot`
(`[autoload] _mcp_game_helper=...` + `[editor_plugins] enabled=...plugin.cfg`).
No hay que tocar esa configuración — el resto de esta sección es sobre cómo
levantar y usar la conexión correctamente.

### 1. Abrir el editor (obligatorio con `--editor` / `-e`)

```powershell
"C:\Users\User\Downloads\godot47_std\Godot_v4.7-stable_win64.exe" --path D:/2025/Godot/vectopen --editor
```

Sin `--editor`/`-e` se ejecuta el juego en vez del editor, y `godot_ai` es un
`EditorPlugin` — nunca carga en modo juego. Señal de que se abrió mal: el
título de la ventana dice `"Vectopen (DEBUG)"`. El correcto es
`"<escena> - Vectopen - Godot Engine"`.

### 2. Puertos

Configuración global (`editor_settings-4.7.tres`, compartida por cualquier
instalación de Godot 4.7 en esta máquina, no por proyecto):
`godot_ai/http_port = 8002`, `godot_ai/ws_port = 9500`. El puerto 8000 por
defecto está ocupado por un proceso Python ajeno — no cambiar de vuelta a 8000.

### 3. Si el Output muestra `MCP | reconnecting` en loop

No asumir que el servidor está roto — puede haberse caído tras un primer
arranque fallido puntual (visto una vez: sin razón aparente, el proceso
lanzado por el propio editor murió justo después de conectar, con
`disconnected (code -1)`). El servidor en sí funciona bien — probado
lanzándolo a mano con el comando exacto del log y conectó sin problema.

Fix que funcionó: relanzar el servidor manualmente en segundo plano (no
con timeout/temporal, tiene que quedar vivo) con el comando exacto que
aparece en el Output tras `"MCP | started server..."`, por ejemplo:

```powershell
& "C:\Users\User\.local\bin\uvx.exe" --from godot-ai==2.9.2 godot-ai `
    --transport streamable-http --port 8002 --ws-port 9500 `
    --pid-file "C:\Users\User\AppData\Roaming\Godot\app_userdata\Vectopen\godot_ai_server.pid"
```

El editor (con su loop de reintentos exponencial ya corriendo, hasta 60s
entre intentos) se reconecta solo apenas detecta el puerto vivo — no hace
falta reiniciar el editor. Verificar con:

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in @(8002, 9500) }
```

Nota aparte, no bloqueante: el editor también intenta usar `pwsh.exe`
(PowerShell Core) para una verificación de puerto interna y falla
(`Could not create child process: pwsh.exe...`) porque no está instalado en
esta máquina — no impide que el servidor arranque, se puede ignorar.

### 4. Acceso desde agentes AI

- **OpenCode:** vía bridge stdio (`C:\Users\User\.config\opencode\mcp-servers\godot-ai-bridge.py`,
  configurado en `opencode.jsonc`) — necesario porque el cliente MCP de
  OpenCode no soporta `streamable-http` directo.
- **Claude Code:** puede conectarse directo a `http://127.0.0.1:8002/mcp`
  vía transporte `streamable-http`, sin necesitar el bridge — no configurado
  todavía en este proyecto (pendiente si se necesita).

Prerrequisito para ambos: el servidor godot-ai debe estar corriendo (puerto
8002 activo) **antes** de que el agente intente listar/llamar sus tools.

### 5. Bug real encontrado y corregido en el bridge (2026-07-15)

Causa raíz de por qué OpenCode perdía las tools tras reiniciar el servidor
godot-ai (no era el proceso que se mató, ni el servidor — ambos estaban
bien): `godot-ai-bridge.py` guardaba el `mcp-session-id` en una variable
global y lo reutilizaba en cada request. Si el servidor godot-ai se
reinicia, esa sesión deja de existir del lado del servidor (responde
`404` con `"MCP session expired or was not found"`), pero el bridge
**no se daba cuenta** y seguía mandando el id viejo para siempre — por eso
hacía falta reiniciar OpenCode completo, la única forma de resetear esa
variable a `None`.

**Corregido:** el bridge ahora detecta la respuesta 400/404 de sesión
inválida, limpia el `session_id` y reintenta automáticamente esa misma
llamada como sesión nueva — sin intervención manual. Ya **no hace falta
reiniciar OpenCode** cuando el servidor godot-ai se reinicia a mitad de
sesión. Verificado con pruebas directas contra el servidor real (confirmado
`404` + `"reason":"stale_streamable_http_session"` para sesión obsoleta).

Nota de corrección: en un diagnóstico anterior se descartó el PID de un
proceso Python "no relacionado" por estar en un puerto alto random — en
realidad **sí era el bridge** (un bridge stdio→http hace conexiones
salientes desde un puerto efímero hacia el 8002, no escucha en un puerto
fijo, por eso no aparecía junto a 8002/9500 en `Get-NetTCPConnection`).
Al identificar procesos Python para matar/reiniciar, **no guiarse solo por
el puerto** — revisar el `CommandLine` real
(`Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Select
CommandLine`) para no confundir el bridge con ComfyUI, video-audio-mcp, u
otros procesos Python que corren en esta máquina simultáneamente.

Log de diagnóstico del bridge (nuevo, no existía antes):
`C:\Users\User\.config\opencode\mcp-servers\godot-ai-bridge.log`
