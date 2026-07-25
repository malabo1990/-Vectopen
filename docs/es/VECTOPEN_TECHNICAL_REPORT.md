# Vectopen — Informe Técnico Completo para Claude

> **Versión:** 0.1.1 | **Motor:** Godot 4.7 (mono) | **Renderer:** gl_compatibility (OpenGL ES 3.0)
> **Propósito:** Editor de gráficos vectoriales de escritorio, nativo, de código abierto
> **Escena principal:** `res://scenes/canvas/canvas.tscn` (CanvasEditor/Node2D)

---

## 1. MAPA DEL PROYECTO

```
vectopen/
├── autoloads/                ← 5 singletons críticos
│   ├── GlobalEvents.gd       (111L) Bus de señales central
│   ├── GlobalUI.gd           (8L)   Flag is_mouse_over_ui
│   ├── DataRepository.gd     (1349L) Modelo, undo/redo, auto-save, recovery
│   ├── SmartCursor.gd        (349L) Cursor contextual con 9 estados
│   └── ObjectPool.gd         (214L) Pooling (BoundingBox, 20-100)
├── scenes/
│   ├── canvas/               ← Viewport principal + artboards
│   │   ├── canvas.tscn       (CanvasEditor) Nodo raíz del editor
│   │   ├── artboard.tscn     (ArtboardEditor) A4 794×1123
│   │   ├── artboard_manager.gd  (28L)
│   │   ├── shape_manager.gd  (105L)
│   │   ├── artboard_container.gd (39L)
│   │   └── canvas_overlay_controller.gd (67L)
│   └── ui/                   ← 18 .tscn + 11 .gd
│       ├── main.tscn         (55K chars) Toolbar, layout, panels
│       ├── ExportPanel.gd    (413L)
│       ├── layers_system.gd  (282L @tool)
│       └── ...                (ColorPicker, SliderRange, etc.)
├── scripts/
│   └── canvas/
│       ├── canvas.gd         (529L) Core Engine
│       ├── artboard.gd       (522L) Artboard Editor
│       └── VectorDrawer.gd   (103L) Pincel/borrador vectorial
├── script_gdscript/
│   ├── tools/                ← 19 herramientas
│   ├── shapes/               ← VectorPath, VectorCircle, VectorRectangle
│   ├── system/               ← PerformanceManager, ImportExportManager
│   ├── ui/                   ← toolbar, layers, color tools
│   └── canvas/               ← canvas_layer.gd (stub)
├── Scene/                    ← Clases base
│   ├── Tool.gd               (19L) extends RefCounted
│   └── ToolNode.gd           (44L) extends Node
├── tools/                    ← Scene-based tools (ToolWrapper)
│   └── tool_wrapper.gd       (58L) Bridge RefCounted ↔ Node
├── Data/
│   └── CurveResource.gd      (11L) Resource para curvas Bézier
├── shader/
│   └── sdf_circle.gdshader   (37L) SDF canvas_item con fwidth()
├── docs/                     ← 7 archivos de documentación
└── project.godot
```

---

## 2. AUTOLOADS — Orden de Carga y Responsabilidades

Los 11 autoloads se cargan en el orden exacto que aparece en `project.godot`:

| # | Singleton | Archivo | Líneas | Rol | Dependencias |
|---|-----------|---------|--------|-----|--------------|
| 1 | **GlobalEvents** | `autoloads/GlobalEvents.gd` | 111 | Bus central: ~52 señales. Método `emit_safe()` para emisión segura | Ninguna |
| 2 | **GlobalUI** | `autoloads/GlobalUI.gd` | 8 | Variable global `is_mouse_over_ui` para enrutamiento input canvas↔UI | Ninguna |
| 3 | **DataRepository** | `autoloads/DataRepository.gd` | 1349 | **God object.** Modelo completo: ProjectData, SessionData, UndoRedoManager, auto-save cada 300s, recovery, snap. CRUD shapes/layers/artboards | GlobalEvents |
| 4 | **ToolManager** | `autoloads/ToolManager.gd` | 381 | Registro y cambio de herramientas. Carga desde `res://tools/*/`, fallback a `script_gdscript/tools/`. Input forwarding | GlobalEvents, DataRepository |
| 5 | **PerformanceManager** | `script_gdscript/system/PerformanceManager.gd` | 453 | DeviceClass detection (POTATO→ULTRA), escalado dinámico, overlay FPS, calidad adaptativa | GlobalEvents |
| 6 | **ThemeManager** | `script_gdscript/system/ThemeManager.gd` | 38 | Toggle dark/light theme | GlobalEvents |
| 7 | **ImportExportManager** | `script_gdscript/system/ImportExportManager.gd` | 672 | Export (SVG/PDF/PNG/JPEG/WEBP/EPS/TSCN/JSON) + Import (SVG/EPS/PNG/JPEG) | GlobalEvents, Artboard |
| 8 | **ExportCache** | `autoloads/ExportCache.gd` | 182 | LRU cache (max 20, TTL 300s). Hash MD5 de datos para evitar re-exportar | GlobalEvents |
| 9 | **SmartCursor** | `autoloads/SmartCursor.gd` | 349 | Cursor contextual: 9 estados (NEUTRAL→PRECISION), 5 formas, 5 animaciones (pulse/halo/rotation). Color transition lerp | GlobalEvents, DataRepository, ToolManager |
| 10 | **ObjectPool** | `autoloads/ObjectPool.gd` | 214 | Pooling: BoundingBox (initial 20, max 100). `acquire()` / `release()` | Ninguna |
| 11 | **MCPRuntime** | `res://addons/godot_mcp/runtime/mcp_runtime.gd` | — | Runtime bridge para godot-mcp (conexión agente IA) | Ninguna |

**⚠️ Advertencia:** SmartCursor (`#9`) referencia a ToolManager (`#4`) en `_on_tool_changed` y `_restore_state`. Si ToolManager no está cargado aún cuando SmartCursor hace `_ready()`, falla silenciosamente. El orden de carga en `project.godot` es correcto, pero si alguien lo cambia, se rompe.

---

## 3. MODELO DE DATOS

### 3.1 Capa Interna (DataRepository — clases internas)

```
ProjectData
├── name: String
├── file_path: String
├── artboards: Dictionary<String, ArtboardData>
├── layers: Dictionary<String, LayerData>
├── created_at / modified_at: int
├── serialize() → Dictionary
└── deserialize(data)

ArtboardData
├── id, name, position, size (Vector2, default 1920×1080)
├── background_color: Color
├── is_visible: bool
├── serialize() / deserialize()

LayerData
├── id, name, artboard_id
├── is_visible, is_locked: bool
├── opacity: float, blend_mode: int
├── shapes: Array<ShapeData>
├── shape_ids: Array<String>
├── serialize() / deserialize()

ShapeData
├── id, type (String: "path"/"rect"/"ellipse"/"text"), name
├── position, rotation, scale
├── stroke_color, stroke_width, fill_color, is_filled
├── points: PackedVector2Array
├── size: Vector2 (100×100 default)
├── text_content: String
├── serialize() / deserialize()

SessionData
├── camera_zoom, camera_offset
├── rulers_visible, grid_visible
├── open_panels: Array[String]
├── tool_configs: Dictionary
├── clipboard_shapes: Array[ShapeData]
└── serialize() / deserialize()
```

### 3.2 Capa Resource (Godot Resources)

| Resource | Archivo | Props | Propósito |
|----------|---------|-------|-----------|
| `CurveResource` | `Data/CurveResource.gd` | points, handles_in, handles_out, curve_type | Curvas Bézier exportables |
| `VectopenProject` | `DataResourceManager.gd` | name, artboards{Dict}, layers{Dict} | Bridge interno↔Resource |
| `VectopenArtboard` | `DataResourceManager.gd` | id, name, position, size | Serialización .vectres |
| `VectopenLayer` | `DataResourceManager.gd` | id, name, artboard_id, visible, locked | Serialización .vectres |
| `VectopenShape` | `DataResourceManager.gd` | id, type, position, rotation, scale, etc. | Serialización .vectres |

### 3.3 Undo/Redo (UndoRedoManager — clase interna)

- `undo_stack: Array[Dictionary]`, `redo_stack: Array[Dictionary]`
- `max_history: int = 100`
- Cada acción: `{name, do_methods: [Callable], undo_methods: [Callable]}`
- **Problema conocido:** `Callable` arrays pueden tener referencias inválidas si un objeto es liberado antes de hacer undo. `is_valid()` check existe pero silent failure.

### 3.4 Formato de Archivo

- `.vectopen`: JSON con `{version, project, session, timestamp, app_version}`
- `.vectres`: Resource binario via `ResourceSaver`
- Auto-save: `user://backups/<project>_<timestamp>.save`
- Recovery: `user://recovery/last_session.json`

---

## 4. ARQUITECTURA DEL CANVAS

### 4.1 Scene Tree (canvas.tscn)

```
CanvasEditor (Node2D) — scripts/canvas/canvas.gd (529L)
├── Camera2D (zoom 0.05–20x, pan, z-drag)
├── ArtboardsContainer (Node2D)
│   └── ArtboardEditor (Node2D) — A4 794×1123
│       ├── (shapes hijos: Polygon2D, Line2D, Path2D, TextEdit, etc.)
│       └── ArtboardTitle
├── CanvasLayer
│   └── main (main.tscn instance) ← UI superpuesta
├── BoundingBox (overlay selección, z_index 100)
└── CanvasOverlayController (Node2D)
```

### 4.2 Responsabilidades de CanvasEditor

- **Cámara:** Pan con clic medio/espacio, zoom con rueda o Z-drag (arrastre vertical con Z)
- **Tool lifecycle:** `_registrar_herramientas_iniciales()` conecta scripts de herramientas por tecla (v→MoveTool, b→BrushTool, m→RectangleTool, p→PenTool, a→ArtboardTool)
- **Input routing:** `_unhandled_input()` → detecta tecla → `change_tool()` → delega a tool activa
- **Redraw:** `queue_redraw()` + regiones sucias (`_dirty_regions`)
- **Smart cursor:** se conecta a `SmartCursor` autoload para feedback visual
- **Pincel/borrador:** `VectorDrawer.gd` maneja `BrushTool` y `EraserTool`

### 4.3 Responsabilidades de ArtboardEditor

- Renderizado visual: fondo blanco, borde (gris normal / azul activo), handles de resize (8)
- Interacción: drag (mover artboard), resize (8 direcciones), selección/deselección
- Título flotante tipo pill sobre el artboard
- `_unhandled_input()`: detección de clics en bordes/handles
- Export methods: `export_to_svg()`, `export_to_png()`, `import_svg()`, `vectorize_image()`, `get_state()`

---

## 5. SISTEMA DE HERRAMIENTAS

### 5.1 Dos Sistemas Paralelos (Inconsistencia Arquitectónica #1)

**Sistema A — Scene-based (ToolManager):**
- ToolManager registra 8 herramientas base con rutas `res://tools/*/select_tool.tscn`
- Cada .tscn → ToolWrapper (wrapper universal) → instancia tool script
- Se activan vía `ToolManager.switch_tool(nombre)`

**Sistema B — Direct script (CanvasEditor):**
- CanvasEditor registra herramientas vía `registrar_herramienta(tecla, script)`
- Se instancian directamente con `script.new(canvas)` (RefCounted) o `Node.new()` (si extiende Node)
- Se activan vía `CanvasEditor.change_tool(instancia)`

### 5.2 Clases Base

| Clase | Extiende | Archivo | Métodos | Usada por |
|-------|----------|---------|---------|-----------|
| `Tool` | `RefCounted` | `Scene/Tool.gd` (19L) | `_init(canvas)`, `activate()`, `deactivate()`, `handle_input(event)` | MoveTool, BrushTool, PenTool, BezierTool, NodeSelectionTool, ArtboardTool, TextTool, ParagraphTool |
| `ToolNode` | `Node` | `Scene/ToolNode.gd` (44L) | `activate()`, `deactivate()`, `handle_input()`, `draw_preview()`, `find_canvas()`, `find_artboard()` | CircleTool, RectangleTool |
| `ToolWrapper` | `Node` | `tools/tool_wrapper.gd` (58L) | Wrapper que detecta `get_instance_base_type()`: `.new(canvas)` si RefCounted, `add_child()` si Node | Scene-based tools |

### 5.3 Catálogo Completo (21 herramientas)

| Tool | Clase base | Archivo | Líneas | Tecla | class_name | Notas |
|------|-----------|---------|--------|-------|------------|-------|
| MoveTool | `Tool` | `script_gdscript/tools/MoveTool.gd` | 1125 | V | `MoveTool` | Selección, drag, resize, rotate, marquee, Blender modes (G/R/S), axis lock |
| BrushTool | `Tool` | `script_gdscript/tools/BrushTool.gd` | ~200 | B | `BrushTool` | Pincel, estabilización (factor 0.22), RDP simplification (1.2px) |
| PenTool | `Tool` | `script_gdscript/tools/PenTool.gd` | ~800 | P | `PenTool` | Poligonal con Line2D |
| BezierTool | `Tool` | `script_gdscript/tools/beziertool.gd` | ~350 | — | *none* | Curvas Bézier con BezierRenderPath (Path2D) |
| CircleTool | `ToolNode` | `script_gdscript/tools/CircleTool.gd` | ~170 | — | `CircleTool` | 128 lados para círculo |
| RectangleTool | `ToolNode` | `script_gdscript/tools/RectangleTool.gd` | ~180 | M | `RectangleTool` | Usa ShapeManager.create_shape_explicit() |
| NodeSelectionTool | `Tool` | `NodeSelectionTool.gd` | ~420 | — | `NodeSelectionTool` | Edición nodos Bézier, G=grab mode, segment bend |
| ArtboardTool | `Tool` | `script_gdscript/tools/ArtboardTool.gd` | ~140 | A | `ArtboardTool` | Creación artboards |
| TextTool | `Tool` | `script_gdscript/tools/TextTool.gd` | ~280 | — | *none* | Edición texto sincrónica. MIN 8, MAX 300 font size |
| ParagraphTool | `Tool` | `script_gdscript/tools/ParagraphTool.gd` | 181 | — | *none* | MultiLineEdit, doble clic |
| TriangleTool | `Node` | `script_gdscript/tools/TriangleTool.gd` | 250 | — | `TriangleTool` | Polígono 3 lados |
| Star4Tool | `Node` | `script_gdscript/tools/Star4Tool.gd` | 247 | — | `Star4Tool` | Estrella 4 puntas |
| Star5Tool | `Node` | `script_gdscript/tools/Star5Tool.gd` | 252 | — | `Star5Tool` | Estrella 5 puntas |
| PentagonTool | `Node` | `script_gdscript/tools/PentagonTool.gd` | 209 | — | `PentagonTool` | Pentágono regular |
| WaterDropTool | `Node` | `script_gdscript/tools/WaterDropTool.gd` | 243 | — | `WaterDropTool` | Gota (curvas Bézier + arcos) |
| drawing | `Node2D` | `script_gdscript/tools/drawing.gd` | 42 | — | *none* | Line2D simple |
| Select | scene | `res://tools/select_tool/` | — | — | — | ToolManager solo |
| Hand | scene | `res://tools/hand_tool/` | — | H | — | Navegación canvas |
| Ellipse | scene | `res://tools/ellipse_tool/` | — | E | — | ToolManager solo |
| Eraser | (integrado) | En CanvasEditor + VectorDrawer | — | — | — | No es tool independiente |

**Nota:** `res://tools/*/` tiene escenas .tscn (8 tools scene-based) pero **no hay código GDScript independiente** allí — son escenas que apuntan a ToolWrapper + scripts en `script_gdscript/tools/`.

---

## 6. UI (main.tscn)

El archivo `scenes/ui/main.tscn` tiene ~55K caracteres (monolítico). Contiene:

- **Toolbar:** Botones para cada herramienta, logo Vectopen, regla
- **Paneles laterales:** Layers, ExportPanel, ColorPicker, Effects
- **Layout:** Posicionamiento absoluto (NO responsive — usa `offset_*` en vez de Containers)
- **Botones de herramienta:** Scripts individuales (~45L c/u, código casi idéntico): `button_circulo.gd`, `button_cuadrado.gd`, `button_star4.gd`, `button_star5.gd`, `button_waterdrop.gd`, `button_text.gd`, `button_paragraph.gd`, `BotonMover.gd`, `BotonBrush.gd`, `BotonBezier.gd`, `ButtonNodeSelection.gd`, `ButtonArtboard.gd`

**⚠️ 360+ líneas duplicadas** en botones de herramienta que difieren solo en el nombre de tool que activan.

---

## 7. PIPELINE DE RENDERIZADO

### 7.1 Estado Actual

| Aspecto | Valor |
|---------|-------|
| Renderer | `gl_compatibility` (OpenGL 3.3 / GLES 3.0) |
| MSAA 2D configurado | x4 (MSAA 2D = 3 en project.godot) |
| MSAA 2D real | ❌ **No soportado** en este renderer |
| Error persistente | `render_target_set_msaa` — 2 ocurrencias al iniciar |
| Anti-aliasing alternativo | `draw_polyline(antialiased=true)`, shader SDF con `fwidth()` |
| SDF Shader | `shader/sdf_circle.gdshader` — canvas_item, 37L, signed distance field |

### 7.2 Renderizado de Formas

| Tipo de forma | Cómo se renderiza | Anti-aliasing |
|--------------|-------------------|---------------|
| Círculo/elipse | Polygon2D (128 lados) + Line2D | ❌ Polygon2D no tiene antialiased |
| Rectángulo | ShapeManager → Polygon2D | ❌ |
| Path libre (PenTool, BrushTool) | Line2D | ✅ antialiased=true |
| Curva Bézier | Path2D (Curve2D) | ✅ nativo de Path2D |
| SDFShape2D (futuro) | Shader canvas_item con ColorRect | ✅ fwidth() analítico |

**⚠️ Inconsistencia:** CircleTool y TriangleTool no activan `antialiased=true` en su preview de arrastre (RectangleTool y StarTool sí).

### 7.3 Alternativa Futura Documentada (VectoSDF)

El informe `vectografica_informe_tecnico_v2.docx` propone migrar las primitivas a SDF (Signed Distance Fields) con un shader unificado `sdf_shape.gdshader`, abandonando Polygon2D. Esto resolvería:
- Anti-aliasing perfecto a cualquier zoom (sin MSAA)
- Operaciones booleanas no destructivas (unión/intersección/sustracción en shader)
- Portabilidad a GPU móvil (GLSL estándar)

**Riesgo:** Operaciones booleanas SDF no equivalen a booleanos poligonales reales. `max(sdf_a, -sdf_b)` ≠ diferencia booleana clásica.

---

## 8. PROBLEMAS CONOCIDOS Y RIESGOS

### 8.1 Críticos

| # | Problema | Archivo | Impacto |
|---|----------|---------|---------|
| 1 | **main.tscn instanciada dentro de canvas.tscn** y viceversa | `canvas.tscn` ↔ `main.tscn` | Dependencia circular. Funciona por lazy loading de Godot, pero frágil |
| 2 | **Dos sistemas de herramientas paralelos** (ToolManager scene-based vs CanvasEditor direct script) | `ToolManager.gd` + `canvas.gd` | Confusión: ¿dónde registro una tool nueva? Inconsistencia en `handle_input(event, position)` vs `handle_input(event)` |
| 3 | **DataRepository es un god object** (1349L) | `DataRepository.gd` | CRUD + undo/redo + auto-save + recovery + snap + serialización. Violación SRP |
| 4 | **ToolManager.get_available_tools() bug:** itera `_available_tools` pero agrega `name` (de ToolManager) en vez del nombre real | `ToolManager.gd:258` | Devuelve array de strings "ToolManager" repetido |
| 5 | **Sin tests** | todo el proyecto | 0 cobertura en 128 scripts, 40K+ LOC |

### 8.2 Medios

| # | Problema | Detalle |
|---|----------|---------|
| 6 | **Scripts dispersos en 6 directorios** | `scripts/`, `script_gdscript/`, `scenes/canvas/`, `scenes/ui/`, `Scene/`, `tools/` |
| 7 | **Mezcla de idiomas** | Nombres en español (`regla.gd`, `button_circulo.gd`, `btn_ab_list.gd`) e inglés (`MoveTool.gd`, `PenTool.gd`) |
| 8 | **Modelo de datos dual** | Clases internas (DataRepository) + Resources (Vectopen*). `DataResourceManager.gd` es bridge pero frágil |
| 9 | **ObjetPool referencia escenas eliminadas** | `_reset_instance()` aún tiene casos para `SelectionBox`, `ShapePreview`, `ArtboardTitle` que fueron eliminados del POOL_CONFIG |
| 10 | **SmartCursor señales inexistentes** | `action_confirmed` e `interactive_element_hovered` no están declaradas en GlobalEvents (conexión protegida con `has_signal()` pero no emiten nunca) |
| 11 | **Project.godot MSAA 2D = 3** (x4) pero renderer `gl_compatibility` no lo soporta | Error de engine al iniciar, no reparable en código |
| 12 | **PerformanceManager.**`_process()` emite `performance_degraded` cada 5s | FSP verificaciones constantes aunque no haya cambios |

### 8.3 Menores

| # | Problema |
|---|----------|
| 13 | `MoveTool.gd` referencia `Canvas` (global) en vez de `CanvasEditor` (class_name corregido) |
| 14 | `ArtboardTool.gd` usa `is Artboard` → debería ser `is ArtboardEditor` |
| 15 | `ObjectPool._reset_instance()` usa `call("set_target", null)` en vez de `has_method()` + `.set_target()` |
| 16 | Varios scripts en `script_gdscript/` plano (102 archivos en una carpeta) |
| 17 | Archivos C# `.csproj.old`, `.af~lock~` aún presentes |
| 18 | `button_circulo.gd` y similares: 12 botones con ~45L duplicados cada uno (~540L total) |

---

## 9. SEÑALES DE GLOBALEVENTS (52 totales)

### Categorías

| Categoría | Señales | Propósito |
|-----------|---------|-----------|
| **Artboard** (6) | `artboard_created/deleted/selected/moved/resized`, `active_artboard_changed` | Ciclo de vida de artboards |
| **Color** (3) | `gradient_changed`, `color_picker_opened/closed` | Sistema de color |
| **Capas** (6) | `layer_created/deleted/selected/reordered`, `layer_visibility_toggled`, `layer_locked_toggled` | Sistema de capas |
| **Objetos** (5) | `object_created/selected/deleted/transformed/style_changed` | Shapes vectoriales |
| **Efectos/UI** (12) | `effect_parameter_updated`, `export_finished/error`, `import_started/finished/error`, `performance_warning`, `renderer_changed`, `memory_pressure_high`, `effect_applied`, `shader_applied`, `autosave_finished`, `project_saved/loaded`, `filter_applied`, `vectorization_*` (3) | Sistema, exportación, efectos |
| **DataRepository** (21) | `data_project_*` (5), `data_shape_*` (5), `data_selection_*` (2), `data_layer_*` (4), `data_artboard_*` (4), `data_undo_*` (2), `data_tool_*` (2), `data_session_*` (2), `data_grid_*` | Modelo de datos |
| **Otros** (4) | `theme_changed`, `data_recovery_saved`, `autosave_finished`, `filter_applied` | Misc |

**Método `emit_safe()`:** Verifica `has_signal()` antes de emitir. Acepta 0-3 argumentos. Previene crashes cuando una señal es emitida pero no declarada.

---

## 10. IMPORTACIÓN/EXPORTACIÓN

### 10.1 Formatos Soportados

| Formato | Export | Import | Estado |
|---------|--------|--------|--------|
| SVG | ✅ | ✅ | Export: `artboard.export_to_svg()`. Import: parser XML Godot (M/L/Z, sin curvas bezier reales) |
| PNG | ✅ | ✅ (como Sprite2D) | Export: SubViewport temporal + captura |
| PDF | 🟡 | ❌ | `_export_pdf()` existe, funcionalidad básica |
| JPEG | 🟡 | ✅ (como Sprite2D) | Export: match solo PNG, no JPEG |
| WEBP | 🟡 | ❌ | Export declarado, no implementado |
| EPS | 🟡 | 🟡 | Export/import declarados, sin case en match |
| TSCN/SCN | 🟡 | 🟡 | Export declarado, sin implementación real |
| JSON | ✅ | ✅ | `project.serialize()` → JSON.stringify |
| VOP | 🟡 | 🟡 | Formato propietario, no implementado |
| AI | ❌ | ❌ | En enum, emite error |
| DXF | ❌ | ❌ | En enum, emite error |

### 10.2 Pipeline de Exportación SVG

`artboard.gd` → recorre hijos → `to_svg()` si existe → fallback por tipo de nodo:
- `Polygon2D` → `<polygon points="...">`
- `Line2D` → `<polyline points="...">`
- `Path2D` → `<path d="M...L...Z">`
- Círculo con shader SDF → **no traducible directamente** (necesita caer a CPU)

---

## 11. HOJA DE RUTA HASTA v0.2.0

### Prioridad Inmediata

- [ ] **BUG:** ToolManager.get_available_tools() devuelve strings incorrectos (usa `name` en vez de `tool_name`)
- [ ] **BUG:** CircleTool/TriangleTool preview sin antialiasing
- [ ] **BUG:** ObjectPool._reset_instance() referencia tipos eliminados
- [ ] **REFACTOR:** Unificar sistema de herramientas (elegir ToolManager como fuente única de verdad)
- [ ] **REFACTOR:** main.tscn → extraer paneles a PackedScene hijas, migrar a Containers

### Corto Plazo

- [ ] Agregar `data_export_started` signal a GlobalEvents (no existe, se emite directamente en ImportExportManager)
- [ ] Agregar case JPEG/EPS/WEBP/TSCN/JSON en export_artboard() match
- [ ] Eliminar scripts duplicados en botones de UI (parametrizar)
- [ ] Consolidar directorios: unificar `scripts/` + `script_gdscript/` + `Scene/`
- [ ] Agregar tests con gdUnit4 para DataRepository (CRUD + undo/redo)

### Medio Plazo

- [ ] Migrar a forward+ (MSAA 2D real) o implementar VectoSDF completo
- [ ] Separar DataRepository en: ProjectManager + UndoRedoManager + SessionManager
- [ ] Exportación SVG bidireccional real (curvas bezier completas)
- [ ] Exportación .tscn nativa

---

## 12. FLUJO DE TRABAJO TÍPICO PARA CLAUDE

### Si te piden "arregla herramienta X":
1. Revisa `ToolManager.gd` — ¿la tool está registrada ahí (scene-based) o en `CanvasEditor._registrar_herramientas_iniciales()` (direct script)?
2. Según el sistema, busca el script en `script_gdscript/tools/` (direct) o `tools/<tool_name>/` (scene + wrapper)
3. Verifica la clase base: `Tool` (RefCounted) o `ToolNode` (Node)
4. La firma de handle_input difiere: `handle_input(event, canvas_position)` (ToolManager) vs `handle_input(event)` (direct)

### Si te piden "agrega funcionalidad al modelo de datos":
1. Todo pasa por `DataRepository.gd`
2. Agrega propiedades a la clase interna correspondiente (ProjectData/ArtboardData/LayerData/ShapeData)
3. Actualiza `serialize()` / `deserialize()`
4. Emite señal via `GlobalEvents.emit_safe()`
5. NO olvides registrar en UndoRedoManager si es una mutación

### Si te piden "agrega una herramienta nueva":
- **Opción recomendada:** sigue el patrón ToolManager + ToolWrapper + script en `script_gdscript/tools/`
- Crea el script que extienda `Tool` (en Scene/Tool.gd)
- Agrega la escena en `res://tools/<nombre>/<nombre>.tscn` con ToolWrapper como root
- Registra en `ToolManager._register_available_tools()`
- Agrega botón en toolbar (main.tscn o extraído)

### Si te piden "mejora el renderizado":
- El proyecto usa `gl_compatibility` sin MSAA 2D real
- Las opciones son: migrar a forward+ (rápido) o implementar VectoSDF (correcto)
- Para antialiasing inmediato: activar `antialiased=true` en draw_polyline/draw_polygon donde falte
- Polygon2D no tiene antialiased → migrar a SDF o a draw_polygon con antialiased=true

---

## 13. ARCHIVOS CLAVE POR FUNCIÓN

| Para entender... | Lee estos archivos |
|-----------------|-------------------|
| Arquitectura general | `docs/VECTORIAL_REPORT.md`, `docs/SYSTEM_REVIEW.md` |
| Modelo de datos | `autoloads/DataRepository.gd:919-1150` (clases internas) |
| Bus de señales | `autoloads/GlobalEvents.gd` (todo) |
| Canvas core | `scripts/canvas/canvas.gd` (todo, 529L) |
| Artboard | `scripts/canvas/artboard.gd` (todo, 522L) |
| ToolManager | `autoloads/ToolManager.gd` (todo, 381L) |
| Tool base | `Scene/Tool.gd`, `Scene/ToolNode.gd`, `tools/tool_wrapper.gd` |
| Export/Import | `script_gdscript/system/ImportExportManager.gd` |
| Performance | `script_gdscript/system/PerformanceManager.gd` |
| Smart Cursor | `autoloads/SmartCursor.gd` |
| Object Pool | `autoloads/ObjectPool.gd` |
| Paint/Brush engine | `scripts/canvas/VectorDrawer.gd` |
| MoveTool (reference) | `script_gdscript/tools/MoveTool.gd` (1125L, tool más completa) |
| Shader SDF | `shader/sdf_circle.gdshader` |
| Project config | `project.godot` |
| Render doc | `docs/RENDERIZADO_VECTORIAL.md` |
| Error fixes | `docs/RESOLUCION_DE_ERRORES.md` |
| MCP setup | `docs/GUIA_GODOT_MCP.md` |

---

*Generado por OpenCode — Revisión técnica completa del proyecto Vectopen v0.1.1*
*Destinado a ser leído por Claude como contexto único del proyecto.*
