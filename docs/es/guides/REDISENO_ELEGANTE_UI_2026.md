# Vectopen — Rediseño elegante de UI (Septiembre 2026)

> Documento vivo. Versión: 1.0
> Relacionado: `docs/es/guides/PANEL_DE_CAPAS_PROFESIONAL.md`,
> `docs/es/guides/MEJORAS_UI_Y_SISTEMAS_2026.md`,
> `script_gdscript/system/ThemeManager.gd`

Pasada de estilo "Apple / Figma / Sketch" sobre el panel de capas y la barra de
herramientas: superficies blancas sin marco ni sombra, chips de botón, iconos
teñibles y estados claros. Todo el color sale de los tokens de `ThemeManager`
(sin blancos/negros fijos), así que el modo oscuro se hereda solo.

---

## 1. Panel de capas (`script_gdscript/ui/layers_system.gd`, `Layertree.gd`)

### Contenedor
- `_aplicar_tema_panel()`: stylebox del `Panel` = `PANEL_SURFACE`, radio 14,
  **sin borde, sin sombra**, márgenes internos 16/14. Separación del `VBox` 10px
  para que el título "LAYERS", el buscador, la barra de botones y el árbol
  respiren.
- Título: `TEXT_SECONDARY`, 12px, sin stylebox propio (marco invisible).
- Se rehace en `theme_changed` (`_on_theme_changed`).

### Buscador de capas
- `LineEdit` `SearchLayers` (en el `.tscn`, entre el título y la barra).
- Estilo `_btn_sb(INPUT_BG, INPUT_BORDER)` normal / `_btn_sb(INPUT_BG, ACCENT)`
  al foco; `text_changed` → `actualizar_filtro_busqueda()` (soporta
  `is:oculto`, `is:grupo`).

### Barra de botones (`ButtonsBar`)
- Cada icono va **dentro de un chip** gris claro redondeado (`_chip_sb`,
  radio 7, sin borde): se ve al pasar el ratón y al pulsar.
- `custom_minimum_size = 28×28`, separación 6.

### Colores del árbol (`Layertree.gd`)
- **Líneas de jerarquía casi blancas**: `relationship_line_color`,
  `parent_hl_line_color`, `children_hl_line_color` = `Color(0.87, 0.87, 0.90)`.
  Sin línea azul de rama (confundía con la selección).
- **Fila seleccionada**: relleno `ACCENT_SOFT` + borde `ACCENT` (nunca negro).
- **Hover**: verde `AFFIRMATIVE` al 20%.
- Espaciado más justo: `v_separation` 3, `indent_size` 15, líneas de 1px.
- `drop_position_color` = azul sólido (marca de inserción del drag & drop).

### Botones de fila (ojo / candado / máscara)
- **Todas** las filas llevan los 3 botones en columnas fijas (1 ojo, 2 candado,
  3 máscara).
- Color unificado: **ENGAGED = negro** (`PANEL_TEXT`), **DEFECTO/OFF = gris casi
  blanco** `(0.87, 0.87, 0.90)`.
  - Ojo: visible → negro, oculto → gris.
  - Candado: cerrado (bloqueado) → negro, abierto → gris.
  - Máscara: activa → negro, inactiva → gris.
- **Iconos blancos** (`_icon_blanco`): los SVG del proyecto son negros y
  `set_button_color` **multiplica** (modulate) — un negro no se puede aclarar.
  Se reconvierten a blanco (mismo alfa) para poder teñirlos a cualquier tono.
- La máscara usa **iconos distintos** para OFF vs ON, no solo un cambio de color:
  - ON = `res://icon/UI/exclude.svg` (dos formas solapadas = recorte)
  - OFF = `res://icon/UI/frame-alt-empty.svg` (marco vacío)

---

## 2. Máscara de recorte tipo *stencil* (grupos y texto)

**Problema**: en Godot 4, `clip_children` recorta los descendientes a la forma
que **dibuja el propio nodo**. Una figura funciona; un grupo (`Node2D` pelado) o
un texto (`Node2D` + `WorldTextLabel` "DisplayLabel") no dibujan nada → el
recorte queda vacío y los hijos desaparecen. Por eso "el texto no podía
enmascarar a sus hijos".

**Solución** (Illustrator / Affinity): la figura/letras de arriba recortan al
resto. Sin nodo auxiliar nuevo — se reparenta el contenido **bajo** el
nodo-máscara y se pone `clip_children = CLIP_CHILDREN_ONLY` en éste.

- `_es_contenedor_sin_cuerpo(n)` — decide la ruta (figura con cuerpo vs grupo/texto).
- `_nodo_mascara_de(c)` — grupo: último hijo-figura (Z más alto); texto: hijo
  `DisplayLabel`.
- `_activar_mascara(item, c)` / `_desactivar_mascara(item, c)` — reparent + undo
  con `_accion_undo("Máscara de recorte", do_fn, undo_fn)` (mismo patrón que
  `_agrupar_seleccion`). Metadatos `clip_mask` / `clip_mask_target`.
- `_desagrupar()` desactiva la máscara antes de desagrupar.

### Serializador (`scripts/canvas/canvas_serializer.gd`)
- **Bug latente corregido**: `_serialize_element()` hacía `return` por cada tipo
  de figura/texto **sin serializar los hijos** → las figuras anidadas se perdían
  al guardar. Ahora `base["children"]` para todos los tipos; `_apply_transform()`
  reconstruye recursivamente.
- `_add_visual_state` guarda `clip_mask` / `clip_mask_target`; el loader
  re-ejecuta el reparentado bajo la máscara al cargar.

---

## 3. Barra de herramientas (`scenes/ui/tool.tscn`, `script_gdscript/ui/toolbar.gd`)

Mismo lenguaje visual que el panel de capas.

### Escena
- Todos los botones son `Button` (antes había `TextureButton` mezclados) →
  estilo uniforme.
- Nodo muerto `button_toolmover` (`visible = false`) **eliminado**.
- Iconos que faltaban, ahora asignados desde el set del proyecto:
  | Botón | Icono |
  |---|---|
  | selección | `navigation.svg` |
  | mover | `navigation_BLACK.svg` |
  | bézier | `design_nodoblack.svg` (curva con nodos de control) |
  | dibujar / pincel | `draw.svg` (trazo libre) |
  | imagen | `media-image.svg` |
  | formas | `hexagon-plus.svg` → abre panel `polygon` |
  | texto | `text-square.svg` → abre panel `text` |
  | mesa de trabajo | `frame-alt.svg` |
  | capas | `folder-tree.svg` → abre panel `Selector` |
- Panel: `StyleBoxFlat` blanco, radio 14 (el `toolbar.gd` lo sobrescribe en
  runtime desde `PANEL_SURFACE`, sin borde ni sombra).

### `toolbar.gd` (antes era un stub vacío)
- `_aplicar_tema()` — panel + chips + iconos, reconstruido en `theme_changed`.
- `_preparar_iconos()` — `focus_mode = NONE`, `icon_alignment = CENTER`
  (los iconos van **centrados** en el botón), reconversión a blanco (`_blanco`).
- Estado de herramienta ACTIVA: **chip gris claro** (`SURFACE_RAISED`) + icono
  **negro**. Inactiva: icono gris medio `(0.44)`. Hover: icono negro. **Sin azul.**
- Sincronización del estado activo:
  - clic en un botón → señal `pressed` (cubre herramientas + toggles de panel).
  - atajos de teclado (V/M/B/T…) → `GlobalEvents.data_tool_changed`
    (lo emite `ToolManager` para las herramientas que gestiona).
  - Los botones-panel (bézier-toggle) se marcan activos mientras su panel está
    visible.
- API `actualizar_botones_visuales(...)` mantenida por compatibilidad con
  `canvas.gd::_sincronizar_ui_toolbar` (tolera objeto o `String`).

> Nota: `class_name ToolbarContainer` se retiró — el validador lo marcaba como
> "hides a global script class" y nada lo usaba como tipo (todo es *duck typing*
> vía `has_method`).

---

## 4. Tokens de UI (`ThemeManager.Slot`)

Revisión de la paleta. Se **añadieron 2 tokens semánticos** (el `enum` solo
crece, cero riesgo para lo existente) para dejar de calcular colores a mano en
varios sitios:

| Slot | Claro | Oscuro | Uso |
|---|---|---|---|
| `SURFACE_RAISED` | `#E6E6EB` (`0.902`) | `rgba(255,255,255,0.10)` | chip/fila resaltada: herramienta activa en la barra, selección suave |
| `ACCENT_SOFT` | `rgba(0,122,255,0.14)` | `rgba(10,132,255,0.20)` | relleno de selección (fila del árbol, `Tree.selected_color`) |

- `toolbar.gd` usa `SURFACE_RAISED` para el chip de la herramienta activa.
- `ACCENT_SOFT` es el token canónico para tintes de selección de aquí en
  adelante (hoy `Layertree.gd` y el `Tree` del tema calculan `Color(ACCENT, 0.2)`
  en línea; migrar a `ACCENT_SOFT` cuando se toquen).

El resto de la paleta clara se mantiene (ya validada por el usuario):
`PANEL_SURFACE #F8F8FA`, `ACCENT #007AFF`, `AFFIRMATIVE #34C759`,
`BUTTON_HOVER #F0F0F4`, `BUTTON_PRESSED #E5E5EA`, `TEXT_SECONDARY #6C6C70`,
`TEXT_DISABLED #8E8E93`, `BORDER #D1D1D6`.

`ThemeConfigPanel` recoge los 2 slots nuevos automáticamente (itera
`SLOT_NAMES`) — son editables y persistibles como cualquier otro.

---

## 5. Verificación

- **En vivo (MCP)**: barra de herramientas y panel de capas renderizan correctos
  en modo claro; herramienta activa resaltada en negro (no azul); iconos
  centrados; el estado activo salta al pulsar cada botón. `get_errors` = 0.
- **Máscara**: círculo recortado a un rectángulo / figura vista solo a través de
  las letras — correcto en vivo, 0 errores.
- **gdUnit4**: `CanvasEditor_test` + `LayerSystem_test` → 21/21, 0 errores,
  0 fallos. Suite completa sin regresiones.

---

## 6. Limitaciones de la entrada sintética (recordatorio)

Verificado y documentado en esta sesión: `Viewport.get_mouse_position()` (y por
tanto `Node2D.get_global_mouse_position()`) **nunca** se actualiza con eventos
sintéticos (`Input.parse_input_event` / MCP `send_input`). Los clics y arrastres
sobre el lienzo y el drag & drop del `Tree` **no** se pueden verificar en vivo
por MCP — se validan con tests unitarios + confirmación del usuario con ratón
real.
