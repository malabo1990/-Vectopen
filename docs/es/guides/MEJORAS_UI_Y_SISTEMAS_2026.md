# Vectopen — Mejoras UI, Sistemas y Rendimiento (Agosto 2026)

> Documento vivo de los cambios recientes. Versión: 1.0
> Relacionado: `docs/design/UI_DESIGN.md`, `docs/design/design-tokens.json`

---

## 1. Sistema de archivos gestionado (`FileFlowLayout`)

El panel de exportación (`panel_export.tscn`) incluye ahora un gestor de archivos completo:

- **Vistas**: Recent (archivos recientes), Recover (autosaves/backups de `user://`) y Files (explorador del sistema, arranca en el Escritorio).
- **Título dinámico** (encabezado gris claro) que indica la vista activa; selector por botones (Recent/Files/Recover) o tabs.
- **Detalles ↔ Icono**: toggle exclusivo; Icono muestra un **grid** (`ItemList`, icono 64px + nombre debajo, `fixed_column_width` ajustable).
- **Slider de zoom** (16–96): escala iconos y tipografía del contenido (no la UI del panel).
- **Navegación de carpetas**: Atrás / Adelante / Subir con historial real y desactivación en los extremos.
- **Drag & drop del escritorio** (OS → `{"files": [...]}`) y arrastre interno de archivos recientes.
- **Vista previa**: panel derecho con la imagen seleccionada; **Espacio** abre el visor gigante centrado (overlay fullscreen; Esc/clic cierra).
- **Mensaje de vacío** localizado: "No existe documentos".
- **Contraste garantizado**: todos los botones con `font_color/hover/pressed/focus` explícitos (negro en claro, blanco en oscuro).

### Rendimiento (muy rápido)
- **Thumbnails en `WorkerThreadPool`** (8 hilos nativos) con decodificación PNG/JPEG en paralelo; `ImageTexture` se crea en el hilo principal.
- **Caché en disco** (`user://thumb_cache/`) — la segunda visita no decodifica nada.
- **Caché de listado de directorios** (`_dir_cache`) — navegar es instantáneo.
- **Renderizado progresivo**: primeros 12 items inmediatos, resto en lotes de 30/frame.
- Archivos > 4 MB se omiten del thumbnailing.

## 2. Panel de exportación

- Selector de formato con **configuración contextual** (`FormatConfigPanel`): cada formato reconfigura el `OptionButton` (Color/Calidad/Página/Espacio de color/Estilo) y muestra/oculta Resolución (solo ráster).
- Botones **Save / Save As** conectados a `SaveManager`.
- **X rojo** (esquina superior izquierda, estilo macOS) cierra el panel; el botón Export (keyboard) lo abre (toggle, z-order correcto).

## 3. Configuración de teclado y ratón (`InputConfigPanel`)

- **57 atajos** organizados (herramientas, canvas, archivo, edición, objeto, alineación, capas, texto).
- **Chips por binding** (píldoras) con botón `×`, `+` para añadir múltiples atajos y **Restablecer** (texto discreto).
- **Captura de entrada** (teclado o ratón): aviso "Escuchando entrada...", **Esc cancela**.
- Persistencia en `user://vectopen_inputmap.cfg` (teclas y botones de ratón, `VectopenInput` los carga al inicio).
- **Estilos en el `.tscn`** (variaciones `BindChip`, `ResetLink`, `BindRowLabel`, `CaptureHint`) — editables en el editor, no en código.
- Búsqueda con filtro; popup oscuro macOS con sombra.

## 4. Panel de configuración (Settings — `manager_windws_regla`)

- Ventana estilo macOS: cristal oscuro translúcido, borde sutil, radio 12px, sombra.
- Pestañas **sin bordes** (minimalistas): normal sutil, hover, seleccionada gris, ancho uniforme.
- **Switches macOS** (toggle verde `#30D158` / gris) para todos los CheckButton (tema global).
- SpinBoxes sustituidos por el widget **`spin_boxblack.tscn`** (variante oscura con `SpinBoxValue`).
- Selector de idioma compacto (sin duplicados, con márgenes).
- Panel **invisible al inicio** (toggle del botón de ventanas) y por delante del logo.

## 5. Tema Pro (`ThemeManager` — `script_gdscript/system/ThemeManager.gd`)

- Tokens macOS en **modo oscuro y claro** (fuente: `docs/design/design-tokens.json`).
- **Botones semánticos**: variaciones `AffirmativeButton` (verde) y `NegativeButton` (rojo) — texto blanco.
- Inputs con **anillo de foco accent** + glow; paneles con borde/sombra; scrollbars oscuras con **separación del contenido** (8px).
- Toggle icons globales; `default_font_size` 14.
- Overrides de usuario persistidos en `user://vectopen_theme.cfg`; API de slots para `ThemeConfigPanel`.

## 6. Widgets numéricos

- **`spin_box.tscn`** (claro, texto negro) y **`spin_boxblack.tscn`** (oscuro, texto blanco) — ambos con `class_name SpinBoxValue`:
  exports `value/min_value/max_value/step/sensitivity`, señal `value_changed`, aislados del tema global.

## 7. Zoom y canvas

- **Zoom centrado en el puntero** — corregida la fórmula de `zoom_at_point`:
  `camera.position = world_point + (camera.position - world_point) * (old_zoom / new_zoom)`.
- **Bloqueo sobre paneles**: `GlobalUI.is_mouse_over_ui` se actualiza en `_process` vía `gui_get_hovered_control()`; el canvas ignora la rueda sobre la UI (el scroll del panel funciona) y reactiva el zoom fuera.
- **Nitidez de texto** (título de artboard y textos del mundo):
  - `msaa_2d = 4x`, antialiasing de texto activo, subpixel positioning desactivado (alineado a píxel)
  - snap 2D de transforms y vértices a píxel, hinting de fuente Light
  - `draw_string` del título alineado a píxel (`.floor()`)

## 8. Localización

- Textos del panel de archivos y configuración con `tr()` + claves en `translations/vectopen.csv` (en/es mínimo; retraducción en vivo con `NOTIFICATION_TRANSLATION_CHANGED`).

## 9. Calidad (tests gdUnit4)

- **118 test cases | 0 errors | 0 failures** (1 orphan preexistente).
- Cobertura: FileFlowLayout (vistas, vacío, navegación, preview, grid), InputConfigPanel (captura tecla/ratón, Esc, reset, guardado), ThemeManager (tokens y variaciones), zoom (invariante del puntero), panel keyboard (lista poblada).

## 10. Errores corregidos destacados

- `node_paths=PackedStringArray(...)` faltante → exports NodePath se resolvían como string (lista vacía / nodos null).
- `Tree` no tiene señales `drag_data/can_drop_data/drop_data` (son métodos virtuales) → delegación vía `RecentFilesTree.gd`.
- `InputMap.action_get_events()` devuelve `Array` (no `Array[InputEvent]`) en 4.7.
- `DirAccess.open()` sin `access_flags` en 4.7; `Tree.icon_max_width` inexistente.
- Dos `ThemeManager.gd` duplicados — el autoload usa `script_gdscript/system/`.
- Rebuild del Tree dentro de eventos de selección → `call_deferred`.
- `is_mouse_over_ui` nunca se actualizaba.
- Fórmula de zoom invertida (el cursor no permanecía fijo).
