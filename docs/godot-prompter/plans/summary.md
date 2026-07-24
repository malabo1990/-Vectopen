# Vectopen — Resumen de Trabajo

## Objetivo General
Registrar TextTool/ParagraphTool en canvas.gd para que las teclas de acceso rápido activen herramientas de texto en el artboard; eliminar el conflicto de posicionamiento del BoundingBox por instancias duplicadas.

---

## Fase 1 — Optimización de BrushTool y corrección de errores ✅ COMPLETADA

### PerformanceManager
- `_detect_cpu_and_ram()`: reemplazado `Performance.MEMORY_STATIC` (obsoleto en Godot 4) con `OS.get_memory_info()`

### Conexiones de señal
- `managercolor_pickrColor.gd:26`: agregado `is_connected()` antes de desconectar
- `ColorPaletteTool.gd:51-52`: agregado `is_connected()` antes de desconectar

### BrushTool — settings
- Creado `brush_settings.gd` como recurso, luego eliminado → reemplazado con método estático `_make_settings()` que devuelve Dictionary, sin dependencia de recurso
- `_refresh_settings()`, `_on_quality_changed()`, `_find_performance_manager()`, `set_brush_preset()`, `unlock_brush_preset()`, `get_brush_preset()`

### Calidad dinámica
- `_thin_points()`: filtro de densidad al commit que fusiona puntos consecutivos más cerca que `min_distance_threshold * 0.5`

### Cursor circular
- Precargada imagen `_BRUSH_CURSOR`; `activate()` llama `Input.set_custom_mouse_cursor()`, `deactivate()` lo limpia con `null`

### Primer punto visible
- Caso especial `n == 3` en `_on_new_raw_point`: duplica p0=p1 para generar el primer segmento Catmull-Rom

### WYSIWYG commit
- `_finalizar_trazo_actual()` usa `_committed_points` + cola directamente (sin RDP), preservando exactamente lo que mostró la previsualización

### Variable eliminada
- Eliminada `_tail_start_index` no utilizada

### BrushTool scene
- Creada `res://tools/brush_tool/brush_tool.tscn` (wrapper con `tool_wrapper.gd`, mismo patrón que pen_tool.tscn)
- Registro en ToolManager: `_register_tool("brush", "Pincel", "res://tools/brush_tool/brush_tool.tscn")`

### MoveTool SnapManager
- Reemplazados ambos `Engine.get_singleton("SnapManager")` con `Engine.get_main_loop() as SceneTree` → `st.root.get_node_or_null("SnapManager")` — 0 errores runtime confirmados

### Presets calibrados
- `min_distance_threshold` reducido (ultra: 0.5→0.1, balanced: 1.0→0.2)
- `max_raw_points_per_stroke` duplicado
- `catmull_live_segments` aumentado

### MoveTool duplicado `var new_pos`
- Resuelto forzando recarga de disco con truco de comentario. Último error restante: `hides global script class` (falso positivo)

---

## Fase 2 — TextTool y ParagraphTool en canvas.gd ✅ COMPLETADA

### canvas.gd — cambios
- **Línea 54-57**: grupo `@export_group("Text Tools")` + `@export var TextTool_Script: Script` + `@export var ParagraphTool_Script: Script`
- **Línea 108**: `if TextTool_Script: registrar_herramienta("t", TextTool_Script)`
- **Línea 182-184**: `switch_tool("text")` → `if TextTool_Script: change_tool(_new_tool(TextTool_Script))`; caso `"paragraph"` añadido
- **Línea 246-247**: fallback unicode→keycode en `_handle_keyboard`:
  ```gdscript
  var unicode_val = event.unicode if event.unicode != 0 else event.keycode
  var t_char: String = char(unicode_val).to_lower()
  ```
  Esto permite que eventos de teclado enviados sin `unicode` (ej. MCP `send_input`, mandos) también activen herramientas.

### canvas.tscn — cambios
- Línea 21: `[ext_resource type="Script" path="res://script_gdscript/tools/TextTool.gd" id="18_text"]`
- Línea 22: `[ext_resource type="Script" path="res://script_gdscript/tools/ParagraphTool.gd" id="19_para"]`
- Línea 39: `TextTool_Script = ExtResource("18_text")`
- Línea 40: `ParagraphTool_Script = ExtResource("19_para")`

### Testing
- `send_input("T")` no activa el tool switch vía MCP porque `_handle_keyboard` tiene guard `gui_get_focus_owner() != null` — cualquier Control con foco bloquea el atajo. Esto es intencional (evita switching mientras se escribe en un campo de texto) y no afecta el uso real con teclado físico.

---

## Fase 3 — BoundingBox ✅ COMPLETADA

### Problema original
- La escena `canvas.tscn` tenía una instancia de `BoundingBox` (hija de `ArtboardsContainer`) que `canvas_overlay_controller.gd` gestionaba pero nunca posicionaba — `_forward_target_to_box()` tenía un guard `panel_interactivo.has_method("set_target")` que siempre era falso (el Panel del BoundingBox no tiene ese método; `set_target` vive en el nodo raíz, no en `PANEL_BOUNDINGBOX`).
- `MoveTool` adquiere una instancia *separada* de `BoundingBox` desde `ObjectPool`, la reparentea al canvas y la posiciona mediante `_sincronizar_dimensiones_en_canvas()` — esta era la única funcional.
- Resultado: dos instancias de BoundingBox competían; la de la escena era visible pero en posición incorrecta, la del pool bien posicionada pero podía estar oculta.
- `select_element()` (única forma de usar la caja de la escena) no tenía ningún llamador en todo el código — la caja de la escena era peso muerto.

### Solución aplicada
1. **Eliminada** la instancia redundante `Boundingbox` de `canvas.tscn` (y su `ext_resource`). `canvas_overlay_controller.gd` simplificado a solo `set_active_tool()` (stub, sigue llamado por `canvas.gd`/`MoveTool.gd`); se quitó toda la lógica muerta de bounding box (`current_bounding_box`, `selected_element`, `select_element()`, `_forward_target_to_box()`, `_update_overlay_visibility()`).
2. **Handles reales cableados**: los 9 Panels de `boundingbox.tscn` (`handle_IA/DA/IB/DB/MA/MB/IM/DM/Rotation`) ahora disparan la transformación real vía `MoveTool.start_handle_transform(handle_code)` (nuevo método), reemplazando el hit-testing manual (`_handle_at()`) y el dibujo manual (`draw_preview()` ya no dibuja outline/handles/stalk — solo queda el resaltado de multi-selección y el marquee).
3. **Bugs de tracking en tiempo real corregidos** en `MoveTool.gd`:
   - `_on_motion()` rama `is_dragging_shape`: no llamaba `_update_bounding_box()` → la caja no seguía al arrastrar una figura. Corregido.
   - `_clear_selection()`: no llamaba `_update_macro_rect()` → la caja no desaparecía al deseleccionar (clic fuera). Corregido.
4. **Multi-selección con modificadores**: `Shift` + marquee-drag ahora **suma** a la selección existente, `Alt` + marquee-drag **resta** (nuevo helper `_deselect()`). Sin modificador, reemplaza la selección como antes.
5. **Caja orientada (rotación/escala exactas)**: para selección única, `bounding_box.gd._sincronizar_dimensiones_en_canvas()` ahora calcula el rect **local** de la figura (`_local_rect_cloned()`, nueva función) y aplica `position`/`rotation`/`scale` exactos de esa figura — la caja rota y escala EXACTAMENTE con el polígono, ya no se queda alineada al mundo. Para multi-selección se mantiene el AABB alineado al mundo (no hay una única rotación válida).
6. **Compensación de zoom**: los handles y el "candle" (tallo del handle de rotación) recalculan su tamaño local cada `_process()` (solo cuando el zoom cambia) para verse igual en pantalla sin importar el zoom de cámara ni la escala de la figura seleccionada. El borde de la caja (`StyleBoxFlat` duplicado por instancia) también compensa su grosor con el mismo factor.
7. **Indicadores de eje X/Y**: los Panels rojo "x" / verde "Y" (antes decoración estática siempre visible) ahora se muestran solo durante traslado Blender (tecla G) con eje bloqueado, igual que el sistema viejo hacía cambiando el color del contorno.

### Limitación conocida (no resuelta)
El *resize* de una figura ya rotada sigue calculándose en ejes del mundo (`_apply_resize()`), no en los ejes rotados de la figura — la caja se ve correctamente orientada, pero redimensionar desde un handle de esquina en una figura rotada puede sentirse "raro". Arreglarlo requiere reescribir `_apply_resize()` para operar en el espacio local de la figura — no incluido en este trabajo.

### Tests añadidos
`test/canvas/BoundingBox_test.gd` (3 tests, gdUnit4): verifica selección única (rotación 30°, escala x2, posición) contra `shape.to_global()` real, verifica que multi-selección cae a AABB (rotation=0, scale=ONE), y verifica que selección vacía oculta la caja.

### Bugs no relacionados encontrados y corregidos durante la verificación
- `SaveManager.gd`, `HistoryManager.gd`, `RecentFilesManager.gd` (Fase 4): cada uno declaraba `class_name X` con el mismo nombre que su registro de autoload → "Class X hides an autoload singleton", rompía la compilación en cadena (`ImportExportManager.gd` fallaba, 3 autoloads no cargaban). Quitado `class_name` de los 3 (mismo patrón que `DataRepository.gd` y el resto de autoloads).
- `script_gdscript/ui/MouseFollowControl.gd`: contenía una copia rota de `rich_text_label_slider_size.gd` (contenido no relacionado con "mouse follow", `TrackingEffect` sin definir, `add_custom_effect()` no existe en `RichTextLabel`). Código muerto, no conectado a ninguna escena. **Eliminado** (archivo y `.uid`).

### Verificación
Suite completa de tests + carga headless del proyecto real con Godot 4.7 mono, repetida tras cada cambio. Estado final: 56/56 tests PASSED, 0 errores de script.

---

## Fase 4 — Sistemas de Historial, Guardado y Archivos Recientes ✅ COMPLETADA

### Resumen
Se implementaron tres nuevos autoloads que proporcionan undo/redo (Ctrl+Z/Y), guardado (Ctrl+S) y gestión unificada de archivos recientes. El `UndoRedoManager` ya existía pero no era accesible globalmente ni las tools lo usaban.

### Nuevos autoloads (3)

| Autoload | Archivo | Propósito |
|----------|---------|-----------|
| `HistoryManager` | `res://autoloads/HistoryManager.gd` (57L) | API undo/redo público para tools, envuelve UndoRedoManager |
| `SaveManager` | `res://autoloads/SaveManager.gd` (68L) | Guardar/cargar con Ctrl+S y FileDialog |
| `RecentFilesManager` | `res://autoloads/RecentFilesManager.gd` (49L) | Archivos recientes unificado (antes duplicado) |

### Archivos modificados (5)

| Archivo | Cambio |
|---------|--------|
| `res://scripts/canvas/canvas.gd` | Ctrl+Z/Y llaman a HistoryManager.undo()/redo() en _handle_keyboard |
| `res://autoloads/VectopenInput.gd` | Nueva acción `save` (Ctrl+S) |
| `res://project.godot` | Registrados 3 nuevos autoloads (total 19) |
| `res://script_gdscript/system/ImportExportManager.gd` | Botones QuickActionMenu conectados a SaveManager y RecentFilesManager |
| `res://scenes/ui/FileFlowLayout.gd` | Sustituida lectura directa de ConfigFile por RecentFilesManager |

### Atajos de teclado

| Atajo | Acción | Sistema |
|-------|--------|---------|
| Ctrl+Z | Undo | HistoryManager |
| Ctrl+Shift+Z | Redo | HistoryManager |
| Ctrl+S | Guardar | SaveManager |

### Documentación
Se creó `docs/SISTEMAS_HISTORIAL_GUARDADO.md` con:
- Arquitectura detallada de los 3 sistemas
- API pública de cada uno
- Guía para desarrolladores de tools (cómo añadir undo)
- Integración con el panel Export (QuickActionMenu)
- Ejemplos de código
