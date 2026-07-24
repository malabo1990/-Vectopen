# GEVISUAL — Informe Técnico Vectográfica

## Editor Vectorial de Escritorio Nativo sobre Godot 4
### Arquitectura, Renderizado y Catálogo de Herramientas

**Julio 2026 — Revisión 3 — Documento técnico para desarrolladores y agentes IA**

---

## 1. Resumen ejecutivo

**Vectográfica** (nombre de proyecto: **Vectopen**) es un editor de gráficos vectoriales de escritorio, nativo y de código abierto, construido íntegramente sobre **Godot 4.7**. Es, hasta donde se ha podido establecer, el único editor vectorial de su categoría construido sobre un motor de videojuegos en tiempo real — una elección arquitectónica que define todas las decisiones técnicas descritas en este documento.

La premisa central es aprovechar el pipeline de renderizado acelerado por GPU de Godot (`CanvasItem`) para la edición interactiva, reservando cálculo preciso en CPU únicamente para las operaciones donde la exactitud matemática importa más que la velocidad de refresco: exportación final, *hit-testing* y operaciones booleanas.

Esta revisión **(v3)** incorpora:
- El mapa completo del proyecto validado contra código real (128 scripts GDScript, ~40 escenas, 11 autoloads)
- El catálogo completo de herramientas (21 herramientas, 2 sistemas de registro paralelos)
- Problemas conocidos detectados en la auditoría de código (18 hallazgos clasificados por criticidad)
- Flujo de trabajo para agentes IA que se incorporen al proyecto

---

## 2. Ficha del proyecto

| Campo | Valor |
|---|---|
| **Nombre** | Vectopen |
| **Marca** | GEVISUAL / Vectográfica |
| **Versión** | 0.1.1 |
| **Motor** | Godot 4.7 (config_version=5, mono) |
| **Renderer** | `gl_compatibility` (OpenGL ES 3.0 / GL Compatibility) |
| **MSAA 2D** | ❌ Deshabilitado (no soportado en gl_compatibility — corregido en C24c5f4) |
| **Resolución objetivo** | 1920×1080 (maximizada, modo ventana) |
| **Escena principal** | `res://scenes/canvas/canvas.tscn` |
| **Lenguajes** | GDScript (128 arch.) + C# .NET 8 (2 arch., híbrido no utilizado) |
| **SDK .NET** | Godot.NET.Sdk/4.5.1, net8.0 |
| **Export preset** | Windows Desktop x86_64 |
| **Autoloads** | 11 singletons registrados |
| **Archivos totales** | 128 `.gd`, ~40 `.tscn`, 376 `.svg` (iconos), 2 `.cs`, 1 `.gdshader` |
| **Líneas de código** | ~40,000+ |
| **Plugin editor** | godot-mcp v0.5.0 (tomyud1) |
| **Formato proyecto** | `.vectopen` (JSON) + `.vectres` (Resource binario) |
| **Tests** | ❌ 0 cobertura |

---

## 3. Arquitectura general

El proyecto adopta una arquitectura híbrida GPU/CPU:

| Capa | Responsable | Tecnología |
|------|-------------|------------|
| Edición interactiva (preview, drag, zoom) | GPU en tiempo real | CanvasItem / shaders GLSL |
| Formas geométricas finales (primitivas) | GPU, geometría teselada | Polygon2D + Line2D (128 segmentos) |
| Paths libres (pluma, pincel) | GPU con antialiasing | Line2D con antialiased=true |
| Exportación / cálculo exacto | CPU | Matemática vectorial pura, sin aproximación por píxel |
| *Alternativa futura:* primitivas SDF | GPU analítica | Shader canvas_item con fwidth() |

### 3.1 Diagrama de capas

```
┌─────────────────────────────────────────────────────────────────────┐
│                         UI Layer (main.tscn)                        │
│  toolbar | layers | color picker | panels | rulers | preview        │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ GlobalUI.is_mouse_over_ui
┌───────────────────────────▼─────────────────────────────────────────┐
│                        Event Bus (GlobalEvents)                      │
│  ~52 señales: artboard_*, layer_*, object_*, data_*, export_*, etc. │
└──────────┬──────────────────────────┬──────────────────┬─────────────┘
           │                          │                  │
┌──────────▼──────────┐   ┌───────────▼──────────┐   ┌──▼──────────────┐
│   DataRepository     │   │     ToolManager      │   │  Performance    │
│  (Model/Estado)      │   │  (Herramientas mod.) │   │   Manager       │
│                      │   │                      │   │                 │
│  • ProjectData       │   │  • 21 herramientas   │   │ • FPS monitor   │
│  • SessionData       │   │  • 2 sistemas paral. │   │ • DeviceClass   │
│  • UndoRedoManager   │   │  • Input forwarding  │   │ • Calidad adap. │
│  • Auto-save/Recovery│   │  • Tool config       │   │                 │
│  • Grid/Snap         │   │                      │   │                 │
└──────────────────────┘   └──────────────────────┘   └────────────────┘
           │                          │
           ▼                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Canvas Layer (canvas.tscn)                       │
│                                                                      │
│  CanvasEditor (Node2D)                                               │
│  ├── CanvasLayer → main.tscn (UI superpuesta) ⚠️ circular           │
│  ├── ArtboardsContainer (Node2D)                                     │
│  │   └── ArtboardEditor (Node2D, A4 794×1123)                       │
│  │       └── [shapes: Polygon2D, Line2D, Path2D, TextEdit...]       │
│  ├── Camera2D (zoom 5%-2000%, pan, z-drag)                          │
│  ├── BoundingBox (overlay, z_index 100)                              │
│  └── CanvasOverlayController                                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Sistema de autoloads (singletons)

Los 11 autoloads se cargan en el orden exacto de `project.godot`:

### 4.1 Tabla de autoloads

| # | Singleton | Ruta | Líneas | Rol | Dependencias |
|---|---|---|---|---|---|
| 1 | **GlobalEvents** | `autoloads/GlobalEvents.gd` | 111 | Bus de señales central (~52 señales). Método `emit_safe()` | Ninguna |
| 2 | **GlobalUI** | `autoloads/GlobalUI.gd` | 8 | Flag `is_mouse_over_ui` para enrutamiento input canvas↔UI | Ninguna |
| 3 | **DataRepository** | `autoloads/DataRepository.gd` | 1349 | **God object.** ProjectData, SessionData, UndoRedoManager custom, auto-save (300s), recovery, snap | GlobalEvents |
| 4 | **ToolManager** | `autoloads/ToolManager.gd` | 381 | Registro y cambio de herramientas. Input forwarding | GlobalEvents, DataRepository |
| 5 | **PerformanceManager** | `script_gdscript/system/PerformanceManager.gd` | 453 | DeviceClass (POTATO→ULTRA), escalado dinámico, overlay FPS | GlobalEvents |
| 6 | **ThemeManager** | `script_gdscript/system/ThemeManager.gd` | 38 | Toggle dark/light theme | GlobalEvents |
| 7 | **ImportExportManager** | `script_gdscript/system/ImportExportManager.gd` | 672 | Export/Import a 11 formatos | GlobalEvents, Artboard |
| 8 | **ExportCache** | `autoloads/ExportCache.gd` | 182 | LRU cache (max 20, TTL 300s), hash MD5 | GlobalEvents |
| 9 | **SmartCursor** | `autoloads/SmartCursor.gd` | 349 | Cursor contextual: 9 estados, 5 formas, 5 animaciones | GlobalEvents, DataRepository, ToolManager |
| 10 | **ObjectPool** | `autoloads/ObjectPool.gd` | 214 | Pooling BoundingBox (initial 20, max 100). `acquire()` / `release()` | Ninguna |
| 11 | **MCPRuntime** | `res://addons/godot_mcp/runtime/mcp_runtime.gd` | — | Runtime bridge para conexión agente IA vía godot-mcp | Ninguna |

### 4.2 Riesgo de orden de carga

**SmartCursor (#9)** referencia a `ToolManager` (#4) y `DataRepository` (#3) en su `_ready()`. Si el orden en `project.godot` se modifica, SmartCursor falla silenciosamente. El orden actual es correcto pero no hay protección contra reordenamiento.

---

## 5. Modelo de datos

### 5.1 Capa interna (DataRepository — clases internas GDScript)

El modelo completo vive dentro del archivo `DataRepository.gd` como clases internas.

```
ProjectData
├── name: String
├── file_path: String
├── artboards: Dictionary<String, ArtboardData>
├── layers: Dictionary<String, LayerData>
├── created_at, modified_at: int
├── serialize() → Dictionary
└── deserialize(data)

ArtboardData          LayerData              ShapeData
├── id                ├── id                 ├── id
├── name              ├── name               ├── type ("path", "rect", etc.)
├── position: Vector2 ├── artboard_id        ├── position, rotation, scale
├── size: Vector2     ├── is_visible         ├── stroke_color, stroke_width
├── bg_color: Color   ├── is_locked          ├── fill_color, is_filled
└── is_visible        ├── opacity, blend     ├── points: PackedVector2Array
                      ├── shapes: Array[]    ├── size: Vector2
                      └── shape_ids: Array[] └── text_content: String

SessionData
├── camera_zoom, camera_offset
├── rulers_visible, grid_visible
├── open_panels: Array[String]
├── tool_configs: Dictionary
└── clipboard_shapes: Array[ShapeData]
```

### 5.2 Capa Resource (Godot Resources)

Además de las clases internas, existen Resources con `class_name`:
- `CurveResource` (Data/CurveResource.gd) — puntos, handles_in/out, curve_type
- `VectopenProject`, `VectopenArtboard`, `VectopenLayer`, `VectopenShape` — bridge via `DataResourceManager`

### 5.3 Undo/Redo (UndoRedoManager)

- Clase interna en `DataRepository.gd` (líneas 1157-1239)
- `undo_stack` / `redo_stack`: `Array[Dictionary]` de acciones `{name, do_methods, undo_methods}`
- Cada acción almacena `Callable[]` — **riesgo**: referencias inválidas si un objeto se libera antes de hacer undo (tiene check `is_valid()`)
- `max_history`: 100 pasos
- `version_changed` signal conectada a `GlobalEvents.data_undo_state_changed`

### 5.4 Formato de archivo

| Formato | Extensión | Contenido | Método |
|---------|-----------|-----------|--------|
| Proyecto | `.vectopen` | `{version, project, session, timestamp}` | JSON.stringify / parse |
| Resource | `.vectres` | Resource binario | ResourceSaver / ResourceLoader |
| Auto-save | `user://backups/` | JSON incremental o completo | Timer 300s |
| Recovery | `user://recovery/last_session.json` | Estado completo + timestamp | Al cerrar proyecto |

---

## 6. Sistema de renderizado

### 6.1 Diagnóstico: aliasing y limitaciones del renderer

El renderer `gl_compatibility` de Godot 4 (backend OpenGL 3.3 / GLES3) **no soporta MSAA en 2D**. El proyecto tiene configurado MSAA 2D x4 en `project.godot`, lo que genera 2 errores de engine al iniciar:
- `render_target_set_msaa` (startup)
- `render_target_set_msaa` (PerformanceManager)

**Solución adoptada:** evitar la dependencia de MSAA, resolviendo el antialiasing por tipo de contenido:

### 6.2 Antialiasing actual por tipo de forma

| Tipo | Nodo/Método | Antialiasing |
|------|-------------|-------------|
| Path libre (PenTool, BrushTool) | Line2D | ✅ `antialiased=true` |
| Path libre (draw) | `draw_polyline(antialiased=true)` | ✅ |
| Curva Bézier | Path2D (Curve2D) | ✅ nativo |
| Círculo (CircleTool) | Polygon2D (128 lados) + Line2D | ❌ Polygon2D no expone antialiased |
| Triángulo (TriangleTool) | Polygon2D | ❌ |
| Rectángulo (RectangleTool) | ShapeManager → Polygon2D | ❌ |
| Estrella (Star4Tool, Star5Tool) | Polygon2D | ❌ |

**⚠️ Inconsistencia detectada:** CircleTool y TriangleTool no activan `antialiased=true` en su preview de arrastre, mientras que RectangleTool y StarTool sí.

### 6.3 VectoSDF — Renderizado de primitivas por campos de distancia (futuro)

El informe v2 documentó VectoSDF como reemplazo de Polygon2D, usando un shader `canvas_item` que calcula Signed Distance Fields. Pendiente de implementar en el código real.

**Ventajas documentadas:**
- No requiere MSAA ni cambio de renderer
- Antialiasing analítico con `fwidth()` independiente del zoom
- Operaciones booleanas no destructivas en shader (unión: `min()`, intersección: `max()`, sustracción: `max(a, -b)`)

**Riesgo técnico no documentado en v2:** `max(sdf_a, -sdf_b)` no equivale a una diferencia booleana poligonal clásica (tipo Weiler-Atherton). El interior del resultado SDF no es el mismo que el "recorte" que un usuario de Illustrator espera.

---

## 7. Canvas y viewport

### 7.1 Scene tree de canvas.tscn

```
CanvasEditor (Node2D) — scripts/canvas/canvas.gd (529L)
├── Camera2D
│   └── zoom: 0.05 – 20x
│   └── pan: clic medio / espacio + arrastre
│   └── z-drag: tecla Z + arrastre vertical
├── ArtboardsContainer (Node2D)
│   └── ArtboardEditor (Node2D) — A4 794×1123
│       ├── [shapes hijos variables]
│       └── ArtboardTitle (Label)
├── CanvasLayer
│   └── main (main.tscn instance) ⚠️ dependencia circular
├── BoundingBox (overlay selección, z_index 100)
│   └── Renderiza handles de transformación
└── CanvasOverlayController
    └── Enruta visibilidad del BoundingBox
```

### 7.2 Dependencia circular canvas.tscn ↔ main.tscn ⚠️

`canvas.tscn` tiene una instancia de `main.tscn` en su interior (vía `CanvasLayer`). Pero `main.tscn` también referencia `CanvasRoot`. Esto crea una dependencia circular que funciona solo por el lazy loading de Godot. Es frágil: un cambio en la estructura de cualquiera de las dos escenas puede romper la carga.

### 7.3 Responsabilidades de CanvasEditor

- **Registro de herramientas:** `_registrar_herramientas_iniciales()` conecta scripts por tecla (V→MoveTool, B→BrushTool, M→RectangleTool, P→PenTool, A→ArtboardTool)
- **Lifecycle de herramientas:** `change_tool(instancia)` — desactiva tool anterior, activa nueva
- **Input routing:** `_unhandled_input()` → detecta tecla → cambia tool o delega input
- **Dirty regions:** `_dirty_regions: Array[Rect2]` para redibujado selectivo
- **Smart cursor:** se conecta a `SmartCursor` autoload

### 7.4 Responsabilidades de ArtboardEditor

- Renderizado: fondo blanco, borde gris/azul, handles de resize (8), título flotante tipo pill
- Interacción: drag (mover artboard), resize 8 direcciones, selección / deselección
- Export: `export_to_svg()`, `export_to_png()`, `import_svg()`, `vectorize_image()`, `get_state()`

---

## 8. Catálogo de herramientas

### 8.1 Dos sistemas paralelos (inconsistencia arquitectónica)

**Sistema A — Scene-based (ToolManager):**
- ToolManager registra 8 tools base con rutas `res://tools/*/tool.tscn`
- Cada .tscn contiene un `ToolWrapper` (Nodo) que instancia el tool script
- Se activan vía `ToolManager.switch_tool(nombre)` → carga escena → wrapper → `.activate()`
- Input: `forward_input_to_tool(event, canvas_position)` incluye posición del canvas

**Sistema B — Direct script (CanvasEditor):**
- CanvasEditor registra tools vía `registrar_herramienta(tecla, script)`
- Se instancian directamente: `script.new(canvas)` (RefCounted) o `Node.new()` (Node)
- Se activan vía `CanvasEditor.change_tool(instancia)`
- Input: `handle_input(event)` sin posición

### 8.2 Clases base

| Clase | Extiende | Archivo | Líneas | Instanciación |
|-------|----------|---------|--------|--------------|
| `Tool` | `RefCounted` | `Scene/Tool.gd` | 19 | `Tool.new(canvas)` — no va al árbol |
| `ToolNode` | `Node` | `Scene/ToolNode.gd` | 44 | `ToolNode.new()` + `add_child()` |
| `ToolWrapper` | `Node` | `tools/tool_wrapper.gd` | 58 | Detecta `get_instance_base_type()` y maneja ambos casos |

### 8.3 Catálogo completo (21 herramientas)

| Herramienta | Clase base | Archivo | Líneas | Atajo | class_name |
|------------|-----------|---------|--------|-------|------------|
| **MoveTool** | `Tool` | `script_gdscript/tools/MoveTool.gd` | 1125 | V | `MoveTool` |
| **BrushTool** | `Tool` | `script_gdscript/tools/BrushTool.gd` | ~200 | B | `BrushTool` |
| **PenTool** | `Tool` | `script_gdscript/tools/PenTool.gd` | ~800 | P | `PenTool` |
| **BezierTool** | `Tool` | `script_gdscript/tools/beziertool.gd` | ~350 | — | *none* |
| **CircleTool** | `ToolNode` | `script_gdscript/tools/CircleTool.gd` | ~170 | — | `CircleTool` |
| **RectangleTool** | `ToolNode` | `script_gdscript/tools/RectangleTool.gd` | ~180 | M | `RectangleTool` |
| **NodeSelectionTool** | `Tool` | `NodeSelectionTool.gd` | ~420 | — | `NodeSelectionTool` |
| **ArtboardTool** | `Tool` | `script_gdscript/tools/ArtboardTool.gd` | ~140 | A | `ArtboardTool` |
| **TextTool** | `Tool` | `script_gdscript/tools/TextTool.gd` | ~280 | — | *none* |
| **ParagraphTool** | `Tool` | `script_gdscript/tools/ParagraphTool.gd` | 181 | — | *none* |
| **TriangleTool** | `Node` | `script_gdscript/tools/TriangleTool.gd` | 250 | — | `TriangleTool` |
| **Star4Tool** | `Node` | `script_gdscript/tools/Star4Tool.gd` | 247 | — | `Star4Tool` |
| **Star5Tool** | `Node` | `script_gdscript/tools/Star5Tool.gd` | 252 | — | `Star5Tool` |
| **PentagonTool** | `Node` | `script_gdscript/tools/PentagonTool.gd` | 209 | — | `PentagonTool` |
| **WaterDropTool** | `Node` | `script_gdscript/tools/WaterDropTool.gd` | 243 | — | `WaterDropTool` |
| **drawing** (básico) | `Node2D` | `script_gdscript/tools/drawing.gd` | 42 | — | *none* |
| **Select** | scene | `res://tools/select_tool/` | — | — | — |
| **Hand** | scene | `res://tools/hand_tool/` | — | H | — |
| **Ellipse** | scene | `res://tools/ellipse_tool/` | — | E | — |
| **Rectangle** (scene) | scene | `res://tools/rectangle_tool/` | — | R | — |
| **Eraser** | integrado | VectorDrawer en canvas.gd | — | — | — |

### 8.4 Tool más compleja: MoveTool (1125 líneas)

MoveTool es la herramienta de referencia del proyecto. Capacidades:
- **Selección:** clic individual, marquee (arrastre de selección)
- **Transformación:** drag, resize (8 handles), rotate (handle superior)
- **Blender modes:** G (grab/trasladar), R (rotar), S (escalar) con axis lock X/Y
- **Bounding box:** pooled via ObjectPool, con 8 handles + rotate handle + stalk
- **Colores:** estilo Figma (azul `#0E8CF7`), marquee semi-transparente

---

## 9. UI (main.tscn)

### 9.1 Estructura

El archivo `scenes/ui/main.tscn` tiene ~55K caracteres — **monolítico**, con posicionamiento absoluto (NO responsive).

Contiene:
- Toolbar completa con botones para cada herramienta
- Logo Vectopen, regla, SliderRange
- Paneles laterales: Layers, ExportPanel, ColorPicker, Effects, Trazos, ToolProperties
- SmartCursorSettings
- Layout fijo 1920×1080

### 9.2 Botones de herramienta duplicados ⚠️

Existen 12+ scripts de botón con ~45 líneas de código casi idéntico cada uno, variando solo el nombre de la herramienta que activan:

```
button_circulo.gd   → DataRepository.set_current_tool("CircleTool")
button_cuadrado.gd  → DataRepository.set_current_tool("RectangleTool")
button_star4.gd     → DataRepository.set_current_tool("Star4Tool")
button_star5.gd     → DataRepository.set_current_tool("Star5Tool")
button_waterdrop.gd → DataRepository.set_current_tool("WaterDropTool")
button_text.gd      → DataRepository.set_current_tool("TextTool")
button_paragraph.gd → DataRepository.set_current_tool("ParagraphTool")
BotonBrush.gd       → ...
BotonBezier.gd      → ...
ButtonNodeSelection.gd → ...
ButtonArtboard.gd   → ...
BotonMover.gd       → ...
```

~540 líneas de código duplicado que podrían ser un solo script parametrizado.

---

## 10. Señales de GlobalEvents

### 10.1 Catálogo completo (~52 señales)

| Categoría | Señales |
|-----------|---------|
| **Artboard** (6) | `artboard_created`, `artboard_deleted`, `artboard_selected`, `artboard_moved`, `artboard_resized`, `active_artboard_changed` |
| **Color** (3) | `gradient_changed(gradient)`, `color_picker_opened`, `color_picker_closed` |
| **Capas** (6) | `layer_created`, `layer_deleted(index)`, `layer_selected(index)`, `layer_reordered`, `layer_visibility_toggled(index, visible)`, `layer_locked_toggled` |
| **Objetos** (5) | `object_created`, `object_selected`, `object_deleted`, `object_transformed`, `object_style_changed` |
| **Efectos/UI** (12) | `effect_parameter_updated(name, prop, value)`, `export_finished`, `export_error`, `import_started`, `import_finished`, `import_error`, `performance_warning`, `renderer_changed`, `memory_pressure_high`, `effect_applied`, `shader_applied`, `autosave_finished(path)`, `project_saved/loaded`, `filter_applied`, `vectorization_started/progress/finished` |
| **DataRepository** (21) | `data_project_loaded/saved/closed/auto_save_triggered/auto_save_restored`, `data_shape_created/deleted/changed/selected`, `data_selection_changed/cleared`, `data_layer_created/deleted/changed/reordered`, `data_artboard_created/deleted/changed/active_changed`, `data_undo_state_changed/performed/redo_performed`, `data_tool_changed/config_changed`, `data_session_state_changed`, `data_recovery_saved`, `data_grid_settings_changed` |
| **Otros** (2) | `theme_changed(mode)`, `data_session_state_changed` |

### 10.2 Señales referenciadas pero no declaradas

Dos señales son conectadas por SmartCursor pero **no existen** en GlobalEvents:
- `action_confirmed` — no declarada, conexión protegida con `has_signal()`
- `interactive_element_hovered` — no declarada, conexión protegida

No causan crash pero nunca se emiten, por lo que la funcionalidad asociada (halo de interacción, confirmación visual) está inactiva.

---

## 11. Importación y exportación

### 11.1 Formatos

| Formato | Export | Import | Estado real |
|---------|--------|--------|-------------|
| SVG | ✅ | ✅ | Export: `artboard.export_to_svg()`. Import: parser XML Godot (M/L/Z, sin curvas bezier reales) |
| PNG | ✅ | ✅ (Sprite2D) | Export: SubViewport temporal + captura async |
| PDF | 🟡 | ❌ | `_export_pdf()` existe, funcionalidad básica |
| JPEG | 🟡 | ✅ (Sprite2D) | Export solo PNG, no JPEG real |
| WEBP | 🟡 | ❌ | Declarado en enum, sin case en match |
| EPS | 🟡 | 🟡 | Declarado, sin implementación |
| TSCN/SCN | 🟡 | 🟡 | Declarado, sin implementación |
| JSON | ✅ | ✅ | `project.serialize()` → JSON |
| VOP | 🟡 | 🟡 | Propietario, no implementado |
| AI | ❌ | ❌ | Emite error |
| DXF | ❌ | ❌ | Emite error |

### 11.2 Pipeline de exportación SVG

`artboard.gd` → recorre hijos del artboard → para cada nodo:
1. Si tiene método `to_svg()`, lo llama
2. Si no, fallback por tipo: `Polygon2D` → `<polygon>`, `Line2D` → `<polyline>`, `Path2D` → `<path>`

---

## 12. Problemas conocidos y riesgos

### 12.1 Críticos

| # | Problema | Archivo | Detalle |
|---|----------|---------|---------|
| **C1** | Dependencia circular canvas.tscn ↔ main.tscn | `scenes/canvas/canvas.tscn` + `scenes/ui/main.tscn` | Cada una referencia a la otra. Funciona por lazy loading, pero cualquier cambio estructural puede romper la carga |
| **C2** | Dos sistemas de herramientas paralelos | `ToolManager.gd` vs `canvas.gd` | ToolManager espera `handle_input(event, pos)`, CanvasEditor espera `handle_input(event)`. Confusión sobre dónde registrar una tool nueva |
| **C3** | DataRepository es god object (1349L) | `autoloads/DataRepository.gd` | CRUD + undo/redo + auto-save + recovery + snap + serialización. Viola SRP |
| **C4** | ~~ToolManager.get_available_tools() bug~~ | ✅ Corregido: `name` → `tool_name` | |
| **C5** | Sin tests | todo el proyecto | 0 cobertura en 128 scripts, 40K+ LOC |
| **C6** | ~~SmartCursor señales inexistentes~~ | ✅ Corregido: conexiones y handlers eliminados | |

### 12.2 Medios

| # | Problema | Detalle |
|---|----------|---------|
| **M1** | Scripts en 6 directorios distintos | `scripts/`, `script_gdscript/`, `scenes/canvas/`, `scenes/ui/`, `Scene/`, `tools/` |
| **M2** | Mezcla de idiomas | Español (`regla.gd`, `button_circulo.gd`) e inglés (`MoveTool.gd`, `BrushTool.gd`) |
| **M3** | Modelo de datos dual | Clases internas + Resources. `DataResourceManager` es bridge frágil |
| **M4** | ~~ObjectPool referencia escenas eliminadas~~ | ✅ Corregido: branches `SelectionBox`/`ShapePreview`/`ArtboardTitle` eliminados | |
| **M5** | ~~MSAA 2D deshabilitado~~ | ✅ Corregido: `anti_aliasing/quality/msaa_2d=0` — sin errores de engine | |
| **M6** | PerformanceManager emite cada 5s | `_process()` verifica FPS constantemente aunque no haya cambios |
| **M7** | ~~CircleTool/TriangleTool sin antialiasing en preview~~ | ✅ Corregido: `draw_polyline(..., true)` en ambos | |
| **M8** | main.tscn no responsive | 55K chars de layout con posicionamiento absoluto (`offset_*`), no usa Containers |

### 12.3 Menores

| # | Problema |
|---|----------|
| **m1** | MoveTool referencia `Canvas` global en vez de `CanvasEditor` |
| **m2** | `ArtboardTool.gd` usa `is Artboard` → debería ser `is ArtboardEditor` |
| **m3** | ~~`ObjectPool._reset_instance()` usa `call("set_target", null)` en vez de `has_method()` → Ahora usa `reset_pooled()` por convención~~ ✅ |
| **m4** | ~~12+ botones de UI con ~540L duplicados → 1 `tool_button.gd` parametrizado~~ ✅ |
| **m5** | Archivos C# `.csproj.old` y `.af~lock~` aún presentes |
| **m6** | 102 scripts en `script_gdscript/` plano — mantenimiento imposible |
| **m7** | ~~Paneles (Polygon/Text/Selector) inline en tool.tscn → extraídos a scenes/ui/panels/~~ ✅ |

---

## 13. Shaders

### 13.1 sdf_circle.gdshader (único shader del proyecto)

- Tipo: `canvas_item`
- 37 líneas
- SDF de círculo con antialiasing por `fwidth(d)`
- Uniforms: `fill_color`, `stroke_color`, `stroke_width_px`
- Precisión perfecta a cualquier zoom, sin dependencia del renderer

---

## 14. Archivos C# (híbrido no utilizado)

El proyecto tiene infraestructura .NET:
- `Vectopen.csproj` + `Vectopen.sln`
- 2 archivos `.cs`: `ToggleVisibility.cs`, `MouseFollowControl.cs`
- Toda la lógica de gameplay está en GDScript

El C# añade complejidad de build sin beneficio actual. Recomendación: eliminarlo o migrar paths críticos a C# para rendimiento.

---

## 15. Hoja de ruta priorizada

### 15.1 Inmediato (1-2 días)

| Prioridad | Acción | Esfuerzo | Estado |
|-----------|--------|----------|--------|
| P0 | Corregir ToolManager.get_available_tools() (bug C4) | 5 min | ✅ |
| P0 | Activar antialiased=true en CircleTool y TriangleTool preview (M7) | 15 min | ✅ |
| P0 | Deshabilitar MSAA 2D en gl_compatibility (M5) | 2 min | ✅ |
| P1 | Limpiar ObjectPool._reset_instance() (M4) | 15 min | ✅ |
| P1 | Eliminar conexiones a señales inexistentes en SmartCursor (C6) | 10 min | ✅ |

### 15.2 Fase 1 — UI Overhaul (Completado ✅)

| Prioridad | Acción | Esfuerzo | Estado |
|-----------|--------|----------|--------|
| P1 | Parametrizar scripts de botón de UI (Phase 1.1: 14 scripts → `tool_button.gd`) | 1 día | ✅ |
| P1 | Extraer paneles inline de tool.tscn a PackedScene (Phase 1.2-1.3) | 1 día | ✅ |
| P1 | Reparar tool.tscn (corrupción `\n` literal, cabecera StyleBoxFlat) | 30 min | ✅ |

### 15.3 Fase 2 — Arquitectura (Completado ✅)

| Prioridad | Acción | Esfuerzo | Estado |
|-----------|--------|----------|--------|
| P0 | ToolFactory.gd — patrón Factory para instanciación de herramientas (C5) | 30 min | ✅ |
| P0 | ObjectPool dicecionario dinámico: `reset_pooled()` por convención (C7) | 15 min | ✅ |
| P0 | SmartCursor: extraer FSM + animaciones a CursorStateMachine (C8) | 1 hr | ✅ |
| P0 | ToolManager: limpiar `_scan_tools_directory` redundante (C9) | 30 min | ✅ |
| P1 | ErrorHandler.gd — sistema centralizado de errores (M3) | 30 min | ✅ |

### 15.4 Corto plazo (3-5 días)

| Prioridad | Acción | Esfuerzo |
|-----------|--------|----------|
| P0 | Romper dependencia circular canvas.tscn ↔ main.tscn (C1) | 1 día |
| P0 | Unificar sistema de herramientas: elegir ToolManager como estándar (C2) | 2 días |
| P1 | main.tscn → migrar a Containers (M8) | 2 días |

### 15.5 Medio plazo (1-2 semanas)

| Prioridad | Acción | Esfuerzo |
|-----------|--------|----------|
| P1 | Separar DataRepository en ProjectManager + UndoRedoManager + SessionManager (C3) | 5 días |
| P1 | Consolidar directorios: unificar scripts/ + script_gdscript/ + Scene/ (M1) | 1 día |
| P1 | Agregar suite de tests gdUnit4 (C5) | 3 días |
| P2 | Implementar VectoSDF o migrar a forward+ para MSAA real (M5) | 2-4 días |

### 15.6 Largo plazo (2-4 semanas)

| Prioridad | Acción | Esfuerzo |
|-----------|--------|----------|
| P2 | Exportación SVG bidireccional completa (curvas bezier) | 1 semana |
| P2 | Exportación .tscn nativa de Godot | 3 días |
| P2 | Sistema de plugins sobre EditorPlugin / @tool | 1 semana |
| P3 | Colaboración en tiempo real (CRDT/OT sobre árbol de nodos) | 2-4 semanas |

---

## 16. Flujo de trabajo para agentes IA

### 16.1 Para arreglar una herramienta existente

1. Determinar el sistema de registro:
   - ¿Está en `ToolManager._register_available_tools()`? → scene-based (`res://tools/<name>/`)
   - ¿Está en `CanvasEditor._registrar_herramientas_iniciales()`? → direct script (`script_gdscript/tools/`)
2. Leer el script correspondiente
3. Verificar clase base: `Tool` (RefCounted) o `ToolNode` (Node) — determina si recibe `canvas` en constructor
4. La firma de `handle_input` difiere entre sistemas

### 16.2 Para agregar una herramienta nueva

1. Crear script en `script_gdscript/tools/` que extienda `Tool` (RefCounted)
2. Crear escena en `res://tools/<nombre>/<nombre>.tscn` con ToolWrapper como root
3. Registrar en `ToolManager._register_available_tools()`
4. Agregar botón en toolbar (preferiblemente parametrizado, no script duplicado)

### 16.3 Para modificar el modelo de datos

1. Todo pasa por `DataRepository.gd`
2. Agregar propiedades en la clase interna correspondiente
3. Actualizar `serialize()` y `deserialize()`
4. Emitir señal via `GlobalEvents.emit_safe()`
5. Registrar en UndoRedoManager si es mutación reversible

### 16.4 Para mejorar el renderizado

1. Opción rápida: activar `antialiased=true` donde falte (draw_polyline/draw_polygon)
2. Opción correcta: migrar a forward+ en project.godot
3. Opción arquitectónica: implementar VectoSDF (shader SDF unificado)
4. Polygon2D no tiene antialiased → migrar a draw_polygon o a SDF

---

## 17. Archivos clave por función

| Para entender... | Archivos a leer |
|-----------------|-----------------|
| Arquitectura general | `docs/VECTORIAL_REPORT.md`, `docs/SYSTEM_REVIEW.md` |
| Modelo de datos | `autoloads/DataRepository.gd:919-1150` (clases internas) |
| Bus de señales | `autoloads/GlobalEvents.gd` |
| Canvas core | `scripts/canvas/canvas.gd` (529L) |
| Artboard | `scripts/canvas/artboard.gd` (522L) |
| ToolManager | `autoloads/ToolManager.gd` (381L) |
| Clases base | `Scene/Tool.gd` (19L), `Scene/ToolNode.gd` (44L), `tools/tool_wrapper.gd` (58L) |
| MoveTool (referencia) | `script_gdscript/tools/MoveTool.gd` (1125L) — tool más completa |
| Export/Import | `script_gdscript/system/ImportExportManager.gd` (672L) |
| Performance | `script_gdscript/system/PerformanceManager.gd` (453L) |
| Smart Cursor | `autoloads/SmartCursor.gd` (349L) |
| Object Pool | `autoloads/ObjectPool.gd` (214L) |
| Paint engine | `scripts/canvas/VectorDrawer.gd` (103L) |
| Shader SDF | `shader/sdf_circle.gdshader` (37L) |
| Config proyecto | `project.godot` |
| Docs render | `docs/RENDERIZADO_VECTORIAL.md` |
| Fixes anteriores | `docs/RESOLUCION_DE_ERRORES.md` |
| MCP setup | `docs/GUIA_GODOT_MCP.md` |

---

*Generado por OpenCode — Revisión técnica v3 / 2026-07-18*
*Este documento debe ser leído por Claude como contexto único del proyecto Vectopen.*
