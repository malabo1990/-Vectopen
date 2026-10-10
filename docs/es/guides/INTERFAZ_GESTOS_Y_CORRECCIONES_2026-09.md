# Vectopen — Interfaz, gestos y correcciones (septiembre 2026)

> Documento vivo. Versión 1.0 — 23/09/2026.
> Relacionados: `MEJORAS_UI_Y_SISTEMAS_2026.md`, `VECTOPEN_PROFESSIONAL_UI.md`,
> `PANEL_DE_CAPAS_PROFESIONAL.md`, `RESOLUCION_DE_ERRORES.md`.

Resume los cambios de interfaz, los gestos nuevos y los errores corregidos en
la sesión del 23/09/2026. Estado de la suite gdUnit4 al cerrar: **547 casos,
1 fallo preexistente** (`ContextMenu_test.gd:341`, icono de `tool_in_mouse`,
sin relación con estos cambios) y **0 `SCRIPT ERROR`** en el log.

---

## 1. Gestos y atajos

### 1.1 Bounding box (herramienta de selección)

| Gesto | Resultado |
|---|---|
| Arrastrar dentro de la caja | Mover libre |
| **Ctrl** + arrastrar dentro | Mover solo en horizontal o vertical (el eje se decide una vez; con cuadrícula, el imán actúa solo en ese eje) |
| **Shift** + arrastrar dentro | Grosor de trazo en los 4 lados, sin mover la figura (derecha/arriba = más grueso) |
| **Alt** + arrastrar | Deja una copia en la posición inicial (en el mismo padre que el original, debajo de él) |
| Shift + clic sin arrastrar | Quitar la figura de la selección |
| Shift + arrastrar un handle de borde | Grosor solo de ese lado (rectángulos) |
| Shift + Alt + handle de borde | Grosor de los 4 lados |
| Flecha roja / verde | Mover solo en X / solo en Y (cursores propios) |
| Puntos de radio en las esquinas | Arrastrar = las 4 esquinas; **Alt** = solo esa; Shift redondea |
| Doble clic sobre texto | Editar el texto (también al iniciar la sesión) |

Todo lo anterior se deshace con Ctrl+Z en un solo paso.

### 1.2 Teclado

| Tecla | Acción |
|---|---|
| **1 … 9, 0** (con selección) | Opacidad 10 % … 90 %, 100 %. Dos dígitos rápidos = valor exacto (4, 5 → 45 %) |
| **5** (sin selección) | Reiniciar zoom (sin cambios) |
| Esc (cuentagotas activo) | Cancelar el cuentagotas |

### 1.3 Zoom (Smart y Modern)

- Un clic sobre el porcentaje **ya no** reinicia el zoom.
- **Doble clic** = 100 %.
- **Arrastrar** a izquierda/derecha sobre el porcentaje = zoom suave.

### 1.4 Clic derecho

- Cada modo tiene su menú: Smart (panel con pestañas), Modern (lista con
  iconos monocromos y atajos a la derecha), Pro (menú de escritorio con
  submenús Organizar / Alinear / Transformar).
- Al cambiar de modo se cierra el menú abierto.
- El panel de Smart abre en **la última pestaña elegida**; Ctrl + clic
  derecho abre directo el inspector completo.
- Solo se ofrecen acciones que funcionan (se quitaron las que no hacían nada).

---

## 2. Cambios por modo de interfaz

### 2.1 Pro
- Barra superior compacta (`ProTopBar`): deshacer/rehacer, alinear y
  distribuir, voltear, orden, configuración y selector de modo. Cubre la
  franja gris que quedaba sobre los paneles.
- Studio (`ProStudio`) compacto con dos grupos de pestañas: Color | Muestras |
  Trazo y Transformar | Texto | Efectos. Filas de 20 px, iconos SVG teñidos
  por tema, se reconstruye al cambiar de tema.
- Estilos comunes en `ProUIStyle`.

### 2.2 Modern
- Sin barra lateral izquierda; configuración en la barra superior.
- Barra superior sin controles rápidos que duplicaban el inspector.
- Barra inferior: iconos a contraste completo, separador reemplazado por
  espacio.
- Inspector: candado en X/Y (bloquea el objeto), sección **POLYGON** nueva,
  campos de círculo según el modo, un solo paso de deshacer por arrastre.

### 2.3 Smart
- El panel de Capas envuelve toda la columna de herramientas.
- Panel del clic derecho: iconos del selector de color correctos desde el
  inicio, cuentagotas, degradado sin franja blanca, paletas rediseñadas,
  tipografía con tema, reinicio de proporciones y lista de fuentes mejorada.
  La página Layout/Transformación mide 220 px como las demás.

### 2.4 Común a todos
- Iconos de alineación redibujados (cuadrícula de 16 px, mismo eje).
- Capas: líneas de jerarquía suaves en temas oscuros; color interactivo
  blanco en temas oscuros y azul en el claro
  (`ThemeManager.get_interactive_color()`).
- Esquina de las reglas con el color de la regla.
- Pincel: círculo del tamaño real siguiendo al puntero.
- Resaltado al pasar el mouse: contorno del objeto bajo el cursor (en textos,
  además la línea base).
- Bounding box: píldora "W × H", flechas de eje largas, radios interactivos.

---

## 3. Errores corregidos (causa raíz)

| Síntoma | Causa | Arreglo |
|---|---|---|
| `Cannot call method 'to_local' on a null value` al hacer doble clic | `target_artboard` es nulo al iniciar la sesión y con figuras fuera de un artboard; el doble clic de texto/párrafo lo usaba sin comprobar | `ToolBase._edit_frame_for()` resuelve el artboard dueño, el padre o el artboard bajo el punto; usado en `MoveTool`, `TextTool`, `ParagraphTool` |
| Errores `get_node() with absolute paths` al cerrar | Al salir, `ToolManager._exit_tree` limpia la selección y `InspectorCore` y tres paneles respondían fuera del árbol | Guardas `is_inside_tree()` en `InspectorCore._on_event`, `TransformPanel`, `effects.gd`, `panel_polygon.gd` |
| Alt + arrastrar no duplicaba al iniciar la sesión | Exigía `target_artboard` | La copia usa el padre del original |
| Arrastre con parpadeo | Posición del mouse en caché, un frame atrasada | Posición tomada del propio evento en el bounding box y el pincel |
| Handles de eje difíciles de agarrar | Sus zonas de clic solo se recolocaban al cambiar el zoom | También al cambiar el tamaño |
| Iconos diminutos del selector al iniciar | `clickrigth_nodo` pisaba sus botones con márgenes de 10 px | Respeta los botones del selector |
| Copiar/pegar texto perdía el estilo | `letter_proportions` y `rich_runs` no sobreviven a `duplicate()` | `WorldTextLabel` las restaura desde el contenedor |
| Opacidad de Capas en "1 %" | Escala 0–1 tratada como 0–100 | Conversión en ambos sentidos |
| "Bloquear" de los menús no hacía nada | `InspectorCore` no expone `locked` | `ContextMenuActions.set_locked()` con deshacer |
| Orden y voltear sin deshacer | Cambiaban la escena directo | `ContextMenuActions` con `HistoryManager` |
| Botones "Aplicar a selección" de polígonos sin deshacer | `apply()` comparaba después de escribir | `apply_multi()` y acción propia |

---

## 3b. Segunda ronda (misma fecha)

- **Smart · Transformación:** radios de esquina en cuadrícula 2×2 (TL TR /
  BL BR) encima de la rotación, con el enlace en la cabecera "Esquinas".
- **Smart · Alineación:** iconos de anclaje nuevos (marco + bloque, estilo de
  los preajustes de anclaje del editor de Godot) en `icon/UI/anchor/`, y dos
  filas nuevas: rotar ∓90°, voltear H/V, traer al frente / adelante / atrás /
  al fondo. Rotar 90° es relativo al ángulo de cada figura.
- **Smart · chip inferior izquierdo** (`InputHud`): exportar, panel de
  atajos, teclas pulsadas en vivo con modificadores y ratón con los 3
  botones en color semáforo.
- **Smart · barra de vista previa:** iconos de 16 px centrados.
- **Tipografía:** iconos de alineación vertical con el color del tema,
  slider vertical con tema, tooltips en los sliders; resaltado al pasar el
  mouse sobre textos también con la herramienta de Texto.
- **Error grave corregido:** `UndoRedoManager` no ejecuta la acción al hacer
  commit; `ContextMenuActions._commit` solo la registraba, así que voltear,
  organizar, bloquear y rotar desde menús y barra Pro no hacían nada. Ahora
  aplica y registra; hay test que lo cubre.
- **Selección:** `ContextMenuActions` lee primero `SelectionManager`.
- **Iconos convertidos a plantilla** guardan el archivo de origen en
  `resource_name`; con eso pasa el test que fallaba desde el inicio.
- Suite: **551 casos, 0 fallos, 0 SCRIPT ERROR**.

## 4. Archivos principales

- Nuevos: `script_gdscript/ui/pro/pro_ui_style.gd`, `pro_top_bar.gd`,
  `pro_context_menu.gd`, `script_gdscript/ui/context_menu_actions.gd`,
  `icon/UI/menu/*.svg`, `icon/UI/cursor/*.svg`.
- Reescritos: `pro_studio.gd`, `ListaColor.gd`.
- Modificados (principales): `MoveTool.gd`, `bounding_box.gd`,
  `VectorRectangle.gd` (`stroke_sides`), `adaptive_ui_manager.gd`,
  `modern_*.gd`, `docked_inspector.gd`, `transform_panel.gd`,
  `layers_system.gd`, `Layertree.gd`, `managercolor_pickrColor.gd`,
  `control_gradient.gd`, `ColorPaletteTool.gd`,
  `rich_text_label_slider_size.gd`, `world_text_label.gd`, `canvas.gd`,
  `brushtool.gd`, `ThemeManager.gd`, `ToolBase.gd`, `InspectorCore.gd`.

## 5. Tests nuevos

`test/ui/PanelsPolish_test.gd`, `test/tools/ModifierGestures_test.gd`,
`test/shapes/ParametricAudit_test.gd`, más casos en `ProStudio_test`,
`BoundingBox_test`, `ModernContextMenu_test`, `LayerSystem_test`,
`MoveTool_test`.

## 6. Pendiente

- Verificación con mouse real de los gestos nuevos.
- Ctrl + arrastrar mantiene el imán de cuadrícula en el eje bloqueado; si se
  prefiere solo el bloqueo de eje, es un cambio de una línea en
  `MoveTool._on_motion`.
- El servidor MCP embebido avisa si el puerto 6520 está ocupado (otra
  instancia abierta); no es un error del código.
- Nada de esto está en commit todavía.
