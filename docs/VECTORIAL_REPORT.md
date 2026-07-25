# Vectopen — Informe Técnico Final v1.0

> **Versión:** 0.2.0-dev | **Motor:** Godot 4.7 | **Render:** Forward Mobile (Vulkan) | **Tests:** 80/80 PASSED

---

## Resumen Ejecutivo

Vectopen ha pasado de v0.1.1 a v0.2.0-dev con una refactorización arquitectónica completa (Fase 3), un conjunto de features profesionales (Fase 4: Historial/Guardado/Recientes) y una estabilización del sistema de selección (Fase 5: BoundingBox). El proyecto ahora cuenta con 19 autoloads, panel de configuración unificado con 5 pestañas, internacionalización en 10 idiomas, export multi-plataforma, y tests automatizados.

---

## Autoloads (19)

| # | Nombre | Función |
|---|--------|---------|
| 1 | `GlobalEvents` | Bus de señales (~52 señales) |
| 2 | `GlobalUI` | Flag `is_mouse_over_ui` |
| 3 | `DataRepository` | Modelo de datos, CRUD, persistencia |
| 4 | `ToolManager` | Registro y gestión de herramientas |
| 5 | `PerformanceManager` | FPS, calidad adaptativa |
| 6 | `ThemeManager` | 16 slots color UI + dark/light |
| 7 | `ImportExportManager` | Export/import 11 formatos |
| 8 | `ExportCache` | LRU cache exportación |
| 9 | `MCPRuntime` | Bridge godot-mcp |
| 10 | `SmartCursor` | Cursor contextual 9 estados |
| 11 | `ObjectPool` | Pooling BoundingBox |
| 12 | `LanguageManager` | i18n 10 idiomas |
| 13 | `VectopenInput` | 17 acciones + InputMap |
| 14 | `SnapManager` | Grid snap |
| 15 | `PluginManager` | Plugins extensibles |
| 16 | `DrawPreferences` | Color relleno/trazo/texto, tamaño texto |
| 17 | **`HistoryManager`** | **Undo/redo público para tools, Ctrl+Z/Y** |
| 18 | **`SaveManager`** | **Guardar/cargar, Ctrl+S, FileDialog** |
| 19 | **`RecentFilesManager`** | **Archivos recientes unificado** |

---

## Fase 3 — Refactorización Arquitectónica

| Tarea | Archivo | Resultado |
|-------|---------|-----------|
| Unificar Tool base | `tools/ToolBase.gd` | 7 herramientas migradas: Triangle, Star4/5, Pentagon, WaterDrop, Rectangle, Circle |
| VectorShape base | `script_gdscript/shapes/VectorShape.gd` | VectorRectangle+Circle extienden VectorShape |
| Extraer UndoRedoManager | `autoloads/UndoRedoManager.gd` | Clase independiente con clase interna Action, señal `version_changed` |
| Deprecar Tool/ToolNode | `Scene/Tool.gd`, `Scene/ToolNode.gd` | @deprecated → usar ToolBase |
| Tests gdUnit4 | `res://test/` | 34/34 PASSED (0 failures) |

---

## Fase 4 — Features y Polish

| Tarea | Archivos clave | Estado |
|-------|---------------|--------|
| **Temas avanzados** | `ThemeManager.gd` v2, `ThemeConfigPanel.tscn` (40 nodos estáticos) | ✅ |
| **i18n 10 idiomas** | `LanguageManager.gd`, `translations/vectopen.csv` (100+ entradas EN/ES/FR/DE/PT/RU/ZH/JA/AR/HI) | ✅ |
| **Render optimization** | `project.godot` → `rendering_method="mobile"`, MSAA 2D x2, Vulkan | ✅ |
| **Export pipeline** | `export_presets.cfg` (Linux/macOS/Web), `.github/workflows/build.yml` | ✅ |
| **C# → GDScript** | `ToggleVisibility.gd`, eliminado `.csproj` | ✅ |
| **InputMap configurable** | `VectopenInput.gd` (16 acciones), `InputConfigPanel.gd` en Panel_keyboard | ✅ |
| **Snapping avanzado** | `SnapManager.gd`, grid snap + UI en panel | ✅ |
| **Sistema plugins** | `PluginManager.gd`, `plugins/hello_world.gd` | ✅ |
| **DrawPreferences** | Color relleno/trazo/texto + tamaño texto, persistente | ✅ |
| **HistoryManager** | Undo/redo público (Ctrl+Z/Y), API para tools, envuelve UndoRedoManager | ✅ |
| **SaveManager** | Guardar (Ctrl+S), cargar, FileDialog, wrapper DataRepository | ✅ |
| **RecentFilesManager** | Archivos recientes unificado, 20 máximo, reemplaza lógica duplicada | ✅ |

---

## Panel de Configuración (`manager_windws_regla.tscn`)

Extraído como escena independiente. Accesible vía `Button_panelsettings` en `windows_ recla`.

| Pestaña | Contenido | Sistema |
|---------|-----------|---------|
| **Ventana** | Modo ventana, Fullscreen, Borderless, Maximizar, Resolución | `DisplayServer` |
| **Reglas** | Visibilidad H/V, Guías, Ajustar, 5 colores guía, Limpiar guías | `regla.gd` |
| **Paneles** | Toggle: Efectos, Vista previa, Color picker, Export, Numérico | `find_child` main.tscn |
| **Tema** | Color relleno/trazo/texto, Tamaño texto, 10 idiomas, 16 colores UI | `DrawPreferences` + `ThemeManager` + `LanguageManager` |
| **Ajuste** | Grid Snap, Grid Size | `SnapManager` |

---

## Estructura de Archivos Clave

```
vectopen/
├── autoloads/          (16 singletons)
├── script_gdscript/
│   ├── core/           DVec2 (coordenadas doc-space de 64 bits)
│   ├── shapes/         VectorShape, VectorRectangle, VectorCircle, VectorPolygon, VectorPath
│   ├── tools/          7 tools + MoveTool, BrushTool, PenTool, etc.
│   ├── ui/             ThemeConfigPanel, RulerSettings, WindowSettings,
│   │                   SnapSection, PanelVisibility, InputConfigPanel,
│   │                   TabManager, TogglePanelSetting, LangSelector
│   ├── system/         ThemeManager, PerformanceManager, ImportExportManager
│   └── utils/          regla.gd (reglas + guías + API pública)
├── scenes/ui/
│   ├── main.tscn       UI principal
│   ├── panels/         manager_windws_regla.tscn (panel configuración)
│   └── theme_config_panel.tscn (40 nodos estáticos)
├── tools/              ToolBase.gd
├── test/               3 suites, 34 tests
├── translations/       vectopen.csv (10 idiomas)
├── plugins/            hello_world.gd
└── docs/               VECTORIAL_REPORT.md (este informe)
```

---

## Tests

```
80 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 1 orphans
─────────────────────────────────────────────────────────────
UndoRedoManager_test.gd     17 tests    ✅
ToolBase_test.gd             9 tests    ✅
VectorShape_test.gd         13 tests    ✅
GestorColor_test.gd         10 tests    ✅
PaletteSaveGrid_test.gd      9 tests    ✅  (1 orphan preexistente, no relacionado)
BoundingBox_test.gd          8 tests    ✅
DVec2_test.gd                11 tests   ✅
MoveTool_test.gd              3 tests   ✅
─────────────────────────────────────────────────────────────
TOTAL:                      80          ✅ ALL PASSED
```

---

## Errores Resueltos (20+)

| Error | Solución |
|-------|----------|
| `find_canvas()` no encontrado | → `_refresh_dependencies()` en ToolBase |
| `get_children` on null | → null checks + exports fijos en .tscn |
| `assert_vector(Color)` | → `assert_that(Color)` (gdUnit4) |
| `weakref()` Godot 4 | → `WeakRef` class |
| `Engine.get_singleton()` no funciona | → `get_node("/root/...")` |
| `name` shadowing Node.name | → `p_name`, `node_name` |
| `extends Control` en nodo `Node` | → `extends Node` |
| Godot borra NodePath arrays | → variables individuales |
| ext_resource IDs rotos | → corregidos manualmente |
| TabManager no alternaba pestañas | → `_update_tab_buttons()` añadido |
| MANAGER WINDWS_REGLA invisible | → `visible = false` + toggle script |
| Tema vacío en editor | → 40 nodos estáticos en .tscn |
| CSV no cargaba | → `ResourceLoader.exists()` + graceful fallback |
| MSAA 2D en gl_compatibility | → `rendering_method="mobile"` |
| `_ready()` timing con autoloads | → `await get_tree().process_frame` |
| BoundingBox duplicado (escena + pool) | → eliminada instancia de escena, unificado en pool (ver Fase 5) |
| `class_name X` == nombre de autoload `X` (SaveManager/HistoryManager/RecentFilesManager) | → quitado `class_name`, igual que el resto de autoloads |
| `MouseFollowControl.gd` con contenido roto/no relacionado a su nombre | → eliminado (código muerto, duplicaba mal `rich_text_label_slider_size.gd`) |

---

## Fase 5 — BoundingBox: Tracking en Tiempo Real y Rotación Exacta

| Tarea | Resultado |
|-------|-----------|
| Eliminar BoundingBox duplicado de `canvas.tscn` | ✅ Solo queda la instancia del `ObjectPool` |
| Cablear handles reales de `boundingbox.tscn` | ✅ `MoveTool.start_handle_transform()`, reemplaza hit-testing manual |
| Bounding box sigue a la figura al arrastrar/deseleccionar | ✅ `_update_bounding_box()`/`_update_macro_rect()` en los puntos que faltaban |
| Multi-selección con Shift (suma) / Alt (resta) en marquee | ✅ `_deselect()` nuevo |
| Caja rota y escala EXACTO con la figura (selección única) | ✅ `_local_rect_cloned()` + transform real de la figura |
| Compensación de zoom (handles, tallo de rotación, borde) | ✅ Factor zoom-cámara × escala-figura, con topes min/max |
| Indicadores de eje X/Y (rojo/verde) durante traslado con eje bloqueado | ✅ Cableado a `MoveTool.current_axis`/`current_blender_mode` |
| Tests nuevos | ✅ `test/canvas/BoundingBox_test.gd` (3 tests) |

**Limitación conocida:** el resize de una figura ya rotada sigue calculándose en ejes del mundo, no en los ejes propios de la figura (ver `docs/godot-prompter/plans/summary.md` para detalle).

---

## Fase 6 — Precisión de Doble Punto Flotante y Edición Numérica

**Motivo:** `Vector2`/`Node2D.position`/`Rect2`/`Transform2D` de Godot usan `real_t` = float de 32 bits (~7 dígitos significativos). `MoveTool` releía y reescribía esa geometría en cada operación de arrastre/resize/rotación, así que el error se acumulaba operación tras operación aunque cada frame individual no lo hiciera. El `float` nativo de GDScript ya es de 64 bits, así que la solución no requirió recompilar Godot con `precision=double`: bastó con dejar de usar `Vector2` como fuente de verdad para las coordenadas del documento.

| Tarea | Archivos clave | Resultado |
|-------|----------------|-----------|
| **`DVec2`** — vector 2D de 64 bits, API explícita (sin sobrecarga de operadores, no soportada en GDScript de scripts) | `script_gdscript/core/DVec2.gd` (nuevo) | ✅ |
| **`VectorShape` dueño de la sincronización doc-space** — `doc_position`/`doc_rotation` siempre presentes, slots opcionales `doc_extent`/`doc_vertices`; una figura nueva solo necesita `_register_doc_extent()`/`_register_doc_vertices()` una vez | `script_gdscript/shapes/VectorShape.gd` | ✅ |
| **VectorRectangle/VectorCircle/VectorPolygon migrados** — `to_svg()` exporta con `%.4f` desde doc-space | `script_gdscript/shapes/*.gd` | ✅ |
| **`MoveTool` con despacho genérico** — `shape is VectorShape`, sin `is VectorRectangle or is VectorCircle or ...` en ningún punto; tamaño/extent escala sobre el valor doble exacto en cada resize, no sobre el `Vector2` ya redondeado del paso anterior | `script_gdscript/tools/MoveTool.gd` | ✅ |
| **7 herramientas de creación migradas** a `set_doc_position`/`set_doc_extent`/`set_doc_vertices` | Rectangle/Circle/Triangle/Pentagon/Star4/Star5/WaterDrop Tool | ✅ |
| **Bug real: `corner_radius`/`stroke_width` truncados a entero** — `StyleBoxFlat.border_width`/`corner_radius` son `int` en el motor; se reemplazó por un polígono propio (mismo patrón que `VectorCircle`) | `VectorRectangle.gd::_draw_custom_rounded_rect` | ✅ |
| **Bug real: `VectorCircle` desalineado con su bounding box** — `CircleTool` trataba `position` como centro, pero `_draw()`/`to_svg()` sumaban `size/2` de más (esquina superior-izquierda). Alineado con la convención de `VectorRectangle` (posición = centro) | `VectorCircle.gd::_generate_vertices/to_svg` | ✅ |
| **Campos X/Y editables en el BoundingBox** — muestran/editan `doc_position` de la figura única seleccionada, con contra-rotación/escala para seguir legibles con la figura rotada o escalada | `boundingbox.tscn` (`FieldsWrapper`/`FieldX`/`FieldY`), `bounding_box.gd`, `script_gdscript/ui/valor_dragDrop_lineedit.gd` (+ señal `value_committed`) | ✅ |
| **Snap a grilla desactivado por defecto** — venía `grid_enabled=true`/`grid_size=10.0` de fábrica, causando saltos visibles al arrastrar que se agrandaban con el zoom | `autoloads/SnapManager.gd` | ✅ |
| **Zoom máximo 2000% → 5.000.000%** — `camera.zoom` sigue siendo float32; documentado como el mismo tipo de límite, a nivel de cámara en vez de figura | `scripts/canvas/canvas.gd::zoom_max` | ✅ |
| Tests nuevos | `test/core/DVec2_test.gd` (11), `test/tools/MoveTool_test.gd` (3, incluye round-trip de resize que prueba que `100.00001234` sobrevive 40 ciclos), ampliación de `VectorShape_test.gd` (8→13) y `BoundingBox_test.gd` (3→8) | ✅ |

**Fuera de alcance (decisión explícita, pendiente):** rutas bézier (`Path2D`/`Curve2D` crudo vía `beziertool.gd`/`NodeSelectionTool.gd`) y pincel (`Line2D` crudo vía `brushtool.gd`) no tienen clase propia como `VectorShape`, así que no se migraron a doc-space — queda para una sesión dedicada, del mismo tamaño que esta fase.

**Hallazgos anotados, sin tocar (no relacionados a esta fase):** exportación PDF no exporta figuras (`_collect_shapes()` filtra por `get_bounds()`, que ninguna clase implementa), texto ausente de la exportación SVG, sistema de guardado `DataRepository.ShapeData`/JSON huérfano (sin conexión al árbol de escena real), rutas `ext_resource` rotas apuntando a `res://scripts/...` en varios `.tscn` (los archivos reales viven en `res://script_gdscript/...`).

---

*Generado por OpenCode — Julio 2026*
*Sección "Fase 5" y correcciones de esa pasada — Claude Code, Julio 2026*
*Sección "Fase 6" — Claude Code, Julio 2026*
