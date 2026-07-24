# Vectopen — Informe Técnico Final v1.0

> **Versión:** 0.2.0-dev | **Motor:** Godot 4.7 | **Render:** Forward Mobile (Vulkan) | **Tests:** 56/56 PASSED

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
│   ├── shapes/         VectorShape, VectorRectangle, VectorCircle, VectorPath
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
56 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 1 orphans
─────────────────────────────────────────────────────────────
UndoRedoManager_test.gd     17 tests    ✅
ToolBase_test.gd             9 tests    ✅
VectorShape_test.gd          8 tests    ✅
GestorColor_test.gd         10 tests    ✅
PaletteSaveGrid_test.gd      9 tests    ✅
BoundingBox_test.gd          3 tests    ✅
─────────────────────────────────────────────────────────────
TOTAL:                      56          ✅ ALL PASSED
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

*Generado por OpenCode — Julio 2026*
*Sección "Fase 5" y correcciones de esta pasada — Claude Code, Julio 2026*
