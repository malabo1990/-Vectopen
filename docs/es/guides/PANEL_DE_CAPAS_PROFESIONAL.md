# Panel de Capas Profesional — Concepto y Plan de Implementación

> Informe de concepto del usuario (31 secciones) + plan de ejecución por fases.
> Estado vivo del desarrollo al final del documento.

---

## 1. Objetivo

El panel de capas debe ser un **sistema central de organización, selección y
manipulación**, no una lista visual. Un *Layer / Scene Tree* moderno, jerárquico
y escalable, sincronizado de forma permanente con Artboard, Canvas, Bounding Box,
Inspector y sistema de selección.

> **Todo objeto que existe en el Canvas debe tener una representación clara,
> navegable y manipulable dentro del árbol de capas.**

Principio de diseño rector (§31):

> **La jerarquía del panel y la jerarquía real del documento deben ser
> exactamente la misma estructura. Una única fuente de verdad.**

---

## 2. Requisitos (resumen de las 31 secciones del informe)

| §  | Requisito | Resumen |
|----|-----------|---------|
| 2  | Árbol jerárquico ilimitado | Cualquier profundidad; cualquier nodo puede ser padre. |
| 3  | Padre / hijo | Los grupos son contenedores reales (vectores, texto, imágenes, máscaras, símbolos, otros grupos). La jerarquía es parte del modelo, no solo visual. |
| 4  | Drag & drop avanzado | Mover, crear hijo, sacar hijo, reordenar entre hermanos, cambiar de nivel sin restricciones. |
| 5  | Indicadores visuales de jerarquía | Indentación progresiva, líneas guía verticales, iconos de expansión/grupo, resaltado, estados oculto/bloqueado, indicador "tiene hijos". |
| 6  | Multiselección profesional | Shift+clic, Ctrl/Cmd+clic, rango, varios hermanos, entre grupos, ramas completas, padre+hijos — coherente entre Canvas y panel. |
| 7  | Selección jerárquica | Distinguir *seleccionar grupo* vs *seleccionar hijo* vs *seleccionar todos los descendientes*. |
| 8  | Bloqueo / visibilidad por grupo | Herencia padre→hijos; distinguir bloqueo directo vs heredado. |
| 9  | Acciones colectivas | Bloquear, ocultar, agrupar, desagrupar, mover, duplicar, eliminar, copiar/cortar/pegar, ordenar, alinear, distribuir, renombrar, convertir en componente, mover a otro grupo. |
| 10 | Sincronización en tiempo real con Canvas | Bidireccional: Canvas→Layers y Layers→Canvas, sin estados inconsistentes. |
| 11 | Sincronización con Bounding Box | La selección del panel alimenta directamente el Bounding Box (individual y múltiple). |
| 12 | Orden Z | Traer al frente/adelante, enviar atrás/al fondo, mover encima/debajo; el Canvas se actualiza al instante. |
| 13 | Renombrado inteligente | Nombres automáticos semánticos, doble clic para renombrar, Enter/Escape, nombres únicos opcionales, búsqueda por nombre. |
| 14 | Búsqueda y filtrado | Buscar por nombre + filtros por tipo/estado (texto, imágenes, grupos, bloqueados, ocultos, seleccionados, componentes). |
| 15 | Expandir / contraer inteligente | Expandir/contraer todo, expandir hasta el seleccionado, *reveal in tree*. |
| 16 | Selección por rama | Seleccionar rama completa, solo descendientes, todos los visibles. |
| 17 | Menú contextual profesional | Opciones adaptadas al tipo y estado del objeto. |
| 18 | Atajos de teclado | Integración con el sistema global de comandos + navegación ↑↓←→, Enter, Espacio. |
| 19 | Drag & drop con preview | Línea de inserción; distinguir *insertar como hermano* vs *insertar como hijo*. |
| 20 | Componentes y símbolos | Preparado desde el principio para símbolos, componentes, instancias, grupos reutilizables, elementos vinculados. |
| 21 | Estados visuales avanzados | Indicadores pequeños (bloqueado, oculto, vinculado, componente, estilo, efecto, animación, instancia) que no saturen la UI. |
| 22 | Rendimiento para documentos enormes | 1k / 10k / 100k objetos: virtualización, actualización incremental, lazy expansion, render de solo lo visible, selección por IDs, operaciones por lotes. |
| 23 | Arquitectura conceptual | El panel no es dueño de la lógica. Modelo del documento → Scene/Layer Tree → (Layer Panel, Canvas, Inspector) → Selection Manager → Bounding Box. |
| 24 | Sistema de selección centralizado | `SelectionManager` independiente: `selectedIds[]`, `activeId`, `selectionMode`, `anchorId`. |
| 25 | Undo / Redo estructural | Todas las operaciones del árbol como comandos (MoveNode, ReparentNode, ReorderNode, GroupNodes, …). Un arrastre = un Undo. |
| 26 | Modo de navegación profesional | Recorrer la jerarquía solo con teclado. |
| 27 | Smart Selection | Seleccionar similares (mismo tipo, color, estilo, grupo). |
| 28 | Focus Mode | Entrar en un grupo y trabajar solo con su contenido; el resto atenuado/bloqueado. |
| 29 | Breadcrumb de jerarquía | `Document > Character > Body > Arm > Hand`, clic para volver a cualquier nivel. |
| 30 | Resultado esperado | *Scene Tree + Layer Manager + Selection Manager + Hierarchy Editor* integrado con Canvas y Artboard. |
| 31 | Principio de diseño | Única fuente de verdad: la jerarquía del panel **es** la jerarquía del documento. |

---

## 3. Plan de implementación por fases

### Fase 1 — Fundación de selección  ⏳ EN CURSO

- `SelectionManager` autoload: única autoridad sobre la selección viva
  (`Array[Node2D]`), con `active`, `anchor`, y modos `REPLACE / ADD / TOGGLE /
  RANGE`. Emite `changed(selected)` y mantiene compatibilidad con
  `GlobalEvents.selection_changed`.
- Enrutar `MoveTool`, `LayerTree` / `LayerSystem`, `bounding_box` e
  `InspectorCore` a través de él.
- Sincronización **bidireccional** Canvas ↔ Capas ↔ Bounding Box.
- *Reveal in tree*: al seleccionar en Canvas, el panel abre los padres y hace
  scroll hasta la fila.
- Primitivas de selección jerárquica: `select_children`, `select_descendants`,
  `select_branch`.

Cubre: §6 (base), §7 (base), §10, §11, §23, §24, §30, §31.

### Fase 2 — Selección jerárquica + multiselección pro

- Grupo vs hijo vs descendientes en la interacción del panel.
- Rango con Shift dentro del panel, Ctrl/Cmd para sumar entre ramas.
- Seleccionar rama completa desde el menú/atajo.

Cubre: §6, §7, §16.

### Fase 3 — Acciones colectivas + menú contextual + atajos

- Operaciones en lote (bloquear, ocultar, agrupar, desagrupar, duplicar,
  eliminar, z-order, alinear/distribuir) — cada una **un solo** Undo vía
  `HistoryManager`.
- Menú contextual completo adaptado al tipo/estado.
- Navegación por teclado: ↑↓ moverse, → entrar, ← salir al padre, Enter
  renombrar, Espacio visibilidad.

Cubre: §9, §12, §17, §18, §25, §26.

### Fase 4 — Drag & drop avanzado

- Línea de inserción de preview durante el arrastre.
- Afordancia visual *hermano vs hijo*.
- Sacar hijo del padre; arrastre de multiselección.

Cubre: §4 (completo), §19.

### Fase 5 — Organización a gran escala

- Filtros por tipo/estado (además de la búsqueda por nombre ya existente).
- Herencia real de bloqueo/visibilidad + indicador "heredado".
- Focus Mode + Breadcrumb.
- Smart Selection (seleccionar similares).
- Iconos por tipo en cada fila; estados visuales avanzados.
- Revisión de rendimiento con documentos de 10k–100k (virtualización si hace
  falta).

Cubre: §5 (completo), §8, §13 (nombres semánticos), §14, §21, §22, §27, §28, §29.

### Fase 6 — Componentes y símbolos

- Modelo de componente/instancia; identidad visual en el panel.
- Requiere soporte en el modelo del documento.

Cubre: §20.

---

## 4. Arquitectura objetivo

```text
             Document (escena viva Node2D + modelo .vtc)
                   │
            Scene / Layer Tree  (jerarquía real = única fuente de verdad)
                   │
        ┌──────────┼──────────┐
        ↓          ↓          ↓
   Layer Panel   Canvas    Inspector
        │          │          │
        └──── SelectionManager (autoload) ────┐
                                              ↓
                                        Bounding Box
```

`SelectionManager` conoce: `selected: Array[Node2D]`, `active`, `anchor`,
`mode`. Gestiona selección simple, múltiple, jerárquica, por rango, desde
cualquier superficie, más navegación por teclado. Sustituye a los dos sistemas
de selección paralelos actuales (`Node2D` en `MoveTool` e IDs de `ShapeData` en
`DataRepository`/`ProjectManager`).

---

## 5. Estado vivo

| Fase | Estado | Notas |
|------|--------|-------|
| 1 | ✅ Hecha | `SelectionManager` autoload + `MoveTool` / `LayerSystem` / `bounding_box` / `InspectorCore` enrutados. Sync bidireccional Canvas↔Capas↔BBox verificada en vivo. 15 tests. |
| 2 | ✅ Hecha | Primitivas jerárquicas (`select_children/descendants/branch`) + `seleccionar similares`, expuestas en el menú contextual de fila. Rango con Shift y Ctrl entre ramas: nativo del `Tree` en `SELECT_MULTI`. |
| 3 | ✅ Hecha | Menú contextual completo (Agrupar / Desagrupar / Duplicar / Eliminar / Visibilidad / Bloqueo / Orden Z / Alinear+Distribuir) — cada acción = **un** Undo. Teclado: ↑↓←→ nativo, Enter renombra, Espacio visibilidad, Ctrl+G / Ctrl+Shift+G agrupa/desagrupa. |
| 4 | ✅ Hecha | `LayerTree` drag&drop reescrito: arrastre de multiselección, `mover_capas()` = un Undo, sacar del padre (a "Fuera de artboard" o a nivel superior). Línea de inserción + caja hermano/hijo = nativas (`drop_mode_flags = 3`). |
| 5 | 🟡 Parcial | Hecho: iconos por tipo en cada fila, herencia de bloqueo (`_selectable` sube por ancestros + `locked_by_inheritance`), fichas de filtro `is:oculto/bloqueado/grupo/texto/imagen/seleccionado`, seleccionar similares. Falta: Focus Mode, breadcrumb, indicador de visibilidad heredada, pase de rendimiento 10k–100k. |
| 6 | ⬜ | Bloqueado por el modelo de documento (componentes / símbolos / instancias). |

### Detalle Fases 2–5

- **Menú contextual de fila** (`layers_system.gd`, `PopupMenu` en código, sin
  tocar `.tscn`): Seleccionar · Seleccionar hijos/descendientes/rama ·
  Seleccionar similares · Renombrar · Duplicar · Eliminar · Mostrar/Ocultar ·
  Bloquear/Desbloquear · Agrupar · Desagrupar · Orden Z (frente/adelante/atrás/
  fondo) · submenú Alinear/Distribuir (con 2+ figuras).
- **Agrupar / desagrupar / orden Z / alinear / distribuir**: todo con Undo real
  (`HistoryManager`), conservando el transform global.
- **Teclado** (`Layertree.gd`, solo con el árbol enfocado — `focus_mode` pasó de
  NONE a `FOCUS_CLICK`): ↑↓ y ←→ nativos del `Tree`; Enter → `edit_selected`;
  Espacio → señal `key_toggle_visibility`; Ctrl+G / Ctrl+Shift+G → señales
  `key_group_request` / `key_ungroup_request`.
- **Drag & drop** (`Layertree.gd`): `_nodos_para_arrastrar()` decide 1 fila vs
  toda la multiselección y descarta descendientes redundantes; `mover_capas()`
  reparenta N nodos como una acción; `_can_drop_data()` impide soltar sobre un
  descendiente propio o meter un artboard dentro de otra fila.
- **Iconos por tipo**: `_clave_icono()` → `square` / `circle-spark` / `triangle`
  / `pentagon` / `star` / `hexagon` / `pen` / `text-square` / `media-image` /
  `folder` / `frame-alt`, en la columna del nombre.
- **Herencia de bloqueo**: `SelectionManager._selectable()` recorre los
  ancestros; un grupo/artboard bloqueado protege todo su contenido.
- **Fichas de filtro** en el buscador: `is:oculto`, `is:bloqueado`, `is:grupo`,
  `is:texto`, `is:imagen`, `is:seleccionado` (además de la subcadena por nombre).

### Bugs de tiempo real encontrados y arreglados (prueba en vivo con MCP)

1. **El menú contextual no aparecía** — `get_item_at_position()` devolvía null
   con la fila; ahora cae a `get_selected()` y posiciona el menú desde
   `get_item_area_rect()` en coords de pantalla.
2. **Menú oscuro sobre tema claro** — `_tema_menu()` aplica los tokens del
   `ThemeManager` (panel / hover / font) al `PopupMenu` y su submenú.
3. **Menú se salía de la pantalla** — se ajusta con `clampf` contra
   `DisplayServer.window_get_size()`.
4. **Duplicar / Eliminar del menú no hacían nada** — dependían de
   `_move_tool()` (que fallaba por un `find_child("*anvas*")` que pillaba el
   nodo equivocado). Reescritos como `_duplicar_seleccion()` /
   `_eliminar_seleccion()` directos, con Undo, independientes de la herramienta.
5. **Teclado (Espacio / Enter / Ctrl+G) no respondía** — (a) el árbol no tomaba
   el foco al hacer clic en una fila → `grab_focus()` en `item_mouse_selected`
   y `multi_selected`; (b) se comparaba `event.keycode` (0 en algunos eventos)
   en vez de `event.physical_keycode`.

### 2ª ronda de bugs en vivo

6. **Ctrl+G / agrupar / desagrupar / duplicar / eliminar / orden Z no
   actualizaban el panel** — mutaban los nodos pero nunca pedían una
   reconstrucción del árbol. Ahora cada `do_fn` / `undo_fn` llama a
   `_marcar_arbol_sucio()` (`sincronizar_arbol_completo` diferido).
7. **"Falta el botón del ojo" en las filas anidadas** — el ojo vivía en la
   columna 0, que se **indenta por nivel** → en los hijos quedaba recortado.
   Los TRES botones (ojo · candado · máscara) se movieron a la columna 2
   (derecha), que no se ve afectada por la sangría.
8. **Iconos de botón invisibles en tema claro** — `_tintar_boton` los teñía de
   blanco 90 %. Ahora `_color_boton()` usa `PANEL_TEXT` / `TEXT_DISABLED` del
   tema (trazo oscuro sobre panel claro).
9. **"Padre e hijo no se ven en la jerarquía"** — combinación del bug 6 (el
   árbol no se rebuildeaba tras agrupar) + líneas de relación casi
   transparentes (alpha 0.35 → 0.6, grosor 1 → 2).
10. **El grupo nuevo salía "fuera del artboard"** — `_agrupar_seleccion` ponía
    `grupo.global_position = Vector2.ZERO`. Ahora lo coloca sobre la primera
    figura del grupo (dentro del artboard).
11. **Botón de máscara / clip** — ya estaba pero en la columna del nombre;
    movido a la columna 2 con los demás. Se muestra en artboards y grupos con
    contenido.

### 3ª ronda

12. **Ctrl+G solo funcionaba con el panel enfocado** — ahora
    `LayersSystem._unhandled_key_input` lo captura desde CUALQUIER sitio (como
    el árbol de escena de Godot). Ctrl+Shift+G desagrupa. Ignora si el foco
    está en un `LineEdit`/`TextEdit`.
13. **Ctrl+G justo tras el clic no agrupaba** — el envío de la selección a
    `SelectionManager` es diferido. `_seleccion_nodos()` ahora cae a la
    selección viva del `Tree` si el manager aún está vacío.
14. **Jerarquía "no se ve nada"** — las líneas de relación estaban casi
    transparentes. Ahora: alpha 0.85, grosor 2 px, sangría 28 px/nivel, sin
    rayas horizontales. La jerarquía se lee como en el árbol de escena de Godot
    (verificado en vivo: "Grupo" claramente anidado bajo "Grupo 3" con su línea
    vertical de enlace).

### 4ª ronda — la CAUSA RAÍZ de la sangría

15. **"La posición a la derecha del hijo no funciona"** — CAUSA RAÍZ: el nombre
    se dibujaba en la **columna 1**. En un `Tree` multi-columna de Godot la
    **sangría por nivel solo se aplica al contenido de la columna 0**. Se movió
    TODO lo visible (flecha · líneas · sangría · icono · nombre) a la columna 0;
    la columna 1 solo guarda la referencia al nodo (sin ancho); los 3 botones
    van a la columna 2. Ahora los hijos SÍ se ven desplazados a la derecha,
    como el árbol de escena de Godot (verificado: "Grupo" 2 niveles dentro de
    "Grupo 4", con conectores `├──` / `└──`).
16. **El botón "G" de la barra no hacía nada** — estaba sin cablear (el usuario
    esperaba que agrupara). Cableado: **G** = agrupar selección · **D** =
    duplicar · **M** = desagrupar. "+" sigue siendo "grupo nuevo vacío".
    Tooltips añadidos a todos.
17. **"Un elemento que ya es hijo/nieto no se puede arrastrar"** — el filtro
    de arrastre usaba `is_selected(columna 1)`, que nunca estaba seleccionada.
    Con el nombre en la columna 0, `is_selected(0)` funciona y los items
    anidados se arrastran (test `test_item_anidado_se_puede_arrastrar`).

### 5ª ronda — iconos + hover/selección + coger figuras dentro de grupos

18. **Los botones eran letras (+/+A/-/D/M/G)** — ahora ICONOS: nuevo grupo
    (`plus-square-dashed`) · nuevo artboard (`frame-plus-in`) · eliminar
    (`trash` — descargado de iconoir; el `x.svg` de antes era el logo de X.com,
    inaceptable en un editor profesional) · duplicar (`copy`) · desagrupar
    (`arrow-separate`) · agrupar (`folder`). Con tooltip cada uno.
19. **Hover y selección se confundían (ambos azulados)** — ahora la fila bajo
    el cursor es **VERDE** (`AFFIRMATIVE`) y la seleccionada es **AZUL**
    (`ACCENT`) con borde azul. Styleboxes `hovered` / `selected` /
    `hovered_selected` distintos.
20. **Al pulsar el relleno de una figura DENTRO de un grupo, se deseleccionaba**
    — `_shape_at` solo miraba hijos directos del artboard. Ahora recorre la
    rama y devuelve el GRUPO de primer nivel (clic sencillo = seleccionar el
    grupo); si ya hay una figura de esa rama seleccionada, arrastra esa figura.
    Tests `test_hit_test_encuentra_figura_dentro_de_grupo`.
21. **Botón de máscara/clip** — ahora se muestra en TODOS los grupos y
    artboards (antes solo en los que ya tenían contenido) para poder
    activarlo/desactivarlo por adelantado.

### 6ª ronda — anidado de ELEMENTOS (no solo grupos) + prueba profunda

22. **`_construir_nodo_recursivo` solo recurría en grupos/artboards** — ahora
    recurre también en cualquier figura/texto que contenga otras figuras
    (rectángulo padre → rectángulo hijo → dibujo nieto, cualquier profundidad).
23. **Verificado en vivo con un volcado de diagnóstico (tecla F9)** que escribe
    la estructura REAL del árbol al log. Anidado de 4 niveles vía Ctrl+G:
    `Artboard > Grupo 2 > Grupo > Grupo 2 > Grupo`, cada fila con sus 3 botones.
24. **Líneas de jerarquía NEGRAS** (alpha 1.0, grosor 2, sin transparencia) —
    la escalera de sangría se lee como en el árbol de escena de Godot.
25. **Tests nuevos** (`LayerHierarchy_test.gd`, +2 en `LayerTree_test.gd`):
    cadena rect>círculo>polígono en el árbol · reparentar figura dentro de
    figura con undo · sacar un NIETO al nivel superior · hit-test en figura
    anidada 3 niveles · agrupar dentro de una rama anidada · `_can_drop_data`
    rechaza soltar en descendiente propio.

**Límite conocido de la automatización:** el drag&drop del `Tree` NO se puede
completar con `Input.parse_input_event` (probado: `_drop_data` no llega a
ejecutarse ni con `button_mask`). La lógica (`mover_capas`, `_drop_data`,
`_can_drop_data`, `_nodos_para_arrastrar`) está cubierta por 8 tests unitarios.
Verificación final del drag con ratón real pendiente del usuario.

### 7ª ronda — CAUSA RAÍZ de por qué clic/drag en el LIENZO tampoco se puede
### verificar por MCP (no es un bug de MoveTool)

26. Se crearon 3 rectángulos reales (`VectorRectangle`) en modo juego, se
    activó la herramienta `move` (confirmado por `ToolManager._current_tool_name
    == "move"`) y se intentó clic simple + clic-arrastrar directamente sobre el
    cuerpo visible del rectángulo (confirmado por captura de pantalla que el
    punto de clic caía dentro del rectángulo). `SelectionManager._selected`
    seguía vacío y `global_position` no cambiaba tras el "arrastre".
27. **Diagnóstico con `print` temporal** en `MoveTool.handle_input`/`_on_press`
    (revertido tras la prueba) reveló la causa exacta: `event.position` /
    `event.global_position` del `InputEventMouseButton` sintético SÍ llevan la
    posición correcta que se envía por `send_input` — pero
    `canvas.get_viewport().get_mouse_position()` (y por tanto
    `Node2D.get_global_mouse_position()`, que es lo que usa `MoveTool` en TODA
    su lógica de hit-test/arrastre) se queda **congelado** en un valor
    obsoleto sin importar qué posición se envíe (probado con dos posiciones de
    pantalla muy distintas — `viewport.get_mouse_position()` no cambió).
28. **Causa raíz confirmada:** `Viewport.get_mouse_position()` sólo se
    actualiza con eventos de puntero reales entregados por el sistema
    operativo — `Input.parse_input_event()` (lo que usa el runtime MCP para
    inyectar eventos sintéticos) actualiza el propio `InputEvent` pero NO el
    caché interno del `Viewport`. Es el mismo tipo de límite duro ya probado
    con el drag&drop del `Tree` (bug 21/22 más arriba), pero afectando esta vez
    a **todo** clic o arrastre sobre el lienzo, no sólo al panel de capas.
29. **No es un bug de código:** con un ratón real (eventos OS genuinos) el
    caché del `Viewport` se actualiza con normalidad y `MoveTool` funciona
    igual que siempre. La lógica de hit-test/arrastre ya está cubierta y en
    verde por `test_hit_test_figura_anidada_3_niveles` (`LayerHierarchy_test.gd`)
    y `test_hit_test_encuentra_figura_dentro_de_grupo` (`MoveTool_test.gd`),
    ambos con figuras reales (`VectorRectangle`) y coordenadas reales, no dobles
    de test.

**Límite conocido de la automatización (extensión):** ningún clic ni arrastre
sobre el LIENZO (no sólo el `Tree` del panel de capas) se puede verificar de
extremo a extremo vía `send_input` de MCP, por la misma razón de fondo: el
`Viewport` no actualiza `get_mouse_position()` con eventos sintéticos. La
selección y el arrastre de figuras deben verificarse con los tests unitarios
de hit-test/arrastre (arriba) y, para la confirmación final "se mueve de
verdad en pantalla", con un ratón real — pendiente del usuario, igual que el
drag&drop del panel de capas.

### 8ª ronda — regresión: "ya no puedo meter una capa dentro de otra"

30. **Causa:** el rework a `select_mode = SELECT_MULTI` + sync lienzo↔panel
    dejó de hacer el viejo `deselect_all()` de `_get_drag_data`. Resultado: si
    la fila DESTINO seguía en la selección (muy fácil con el sync), aparecía
    en `_drag_nodes(data)` y `_can_drop_data` la veía dentro de `nodos` → el
    bucle de ancestros devolvía `false` SIEMPRE → el drop se rechazaba y no se
    podía anidar nada.
31. **Arreglo** (`Layertree.gd`): nuevo `_nodos_efectivos(nodos, destino)` que
    quita del conjunto arrastrado el propio `destino` y sus descendientes.
    `_can_drop_data` y `_drop_data` operan sobre `efectivos`: arrastrar la fila
    A sobre la fila B mueve el resto a B en vez de bloquear el drop; si lo
    único arrastrado es el propio destino, el drop se ignora sin más.
32. **Tests** (`LayerTree_test.gd`): `test_nodos_efectivos_excluye_el_destino_
    y_sus_descendientes`, `test_meter_capa_en_otra_ya_seleccionada_via_efectivos`
    (mete A dentro de B con A+B seleccionados, C intacto, con undo). 8/8 verde.

### 9ª ronda — CRÍTICO: "tras el primer anidado se bloquea TODO"

Reporte: al crear el primer padre/hijo por drag, el editor se congela — no se
puede anidar más NI arrastrar en el lienzo NI mover el artboard.

33. **Causa raíz — gesto atascado.** `bounding_box._on_drag_panel_gui_input`
    pone `move_tool.is_dragging_shape = true` (y su propio
    `_is_dragging_canvas_area`) al PULSAR el interior del gizmo. El gizmo
    persigue a la figura cada frame (`_process`); si se aleja bajo el cursor,
    la SUELTA nunca llega a ese `gui_input` → `is_dragging_shape` se queda en
    `true` para siempre. Con ese flag, `MoveTool._on_motion` entra en su rama
    de arrastre y hace `return true` en CADA evento → `canvas._unhandled_input`
    marca el evento como consumido → nada más del editor recibe input. Lo
    mismo con `is_resizing` / `is_rotating` (suelta perdida de un handle).
34. **Arreglo — autocuración triple:**
    - `MoveTool._heal_stuck_gesture()` (llamado desde `MoveTool._process`, cada
      frame): si hay un gesto en curso PERO el botón izquierdo NO está pulsado
      de verdad (`Input.is_mouse_button_pressed`), cierra `is_dragging_shape /
      is_marquee / is_dragging_artboard / is_resizing_artboard / is_resizing /
      is_rotating`, limpia `transform_initial_states` y el flag del gizmo.
    - `bounding_box._heal_stuck_drag()` (desde su `_process`): mismo criterio
      para `_is_dragging_canvas_area` + `move_tool.is_dragging_shape`.
    - `bounding_box._on_drag_panel_gui_input`: en un `mouse_motion` sin el bit
      izquierdo en `button_mask`, cierra el gesto ahí mismo (más rápido que
      esperar al `_process`).
35. **Watchdog de `_bloquear_sincronizacion`** (`LayerSystem`, timer 0.5 s): ese
    flag solo debe estar `true` DENTRO de una llamada síncrona; si un error de
    ejecución aborta `sincronizar_arbol_completo` / `_process_pending_changes` a
    mitad, se queda `true` y el panel NO vuelve a sincronizarse jamás. Si sigue
    bloqueado 2 ticks seguidos, se fuerza a `false` + resync.
36. **Tests:** `MoveTool_test.gd::test_heal_stuck_gesture_*` (cierra sin botón /
    respeta con botón), `LayerSystem_test.gd::test_dos_anidados_seguidos_por_
    drag_no_bloquean_el_panel` (dos anidados + sacar de nuevo, sin trabarse).
    Suites de regresión de transformación (`TransformRegression_test.gd`) y
    `BoundingBox_test.gd` siguen 100% verde — la cura solo actúa sin botón.

### 10ª ronda — consola de diagnóstico en tiempo real

Los bugs de arrastre no lanzan errores del motor → hacen falta invariantes
vigiladas. `DebugConsola` (autoload, `script_gdscript/system/DebugConsola.gd`):

- Barre cada 0.3 s los tres subsistemas y saca SOLO anomalías (con umbral de
  persistencia para no dar falsos positivos de un frame) + eventos clave.
- Prefijos grepables: `[DBG:BBOX]` `[DBG:CAPAS]` `[DBG:JERARQUIA]` `[DBG:EVENTO]`.
- Salida doble: `print()` (lo ve `get_console_log`) y
  `MCPRuntime.push_runtime_log` (lo ve `get_runtime_log`, con `since_ms`).
- **F10** en el juego → alterna verboso + vuelca un informe completo.
- Vigila: gesto zombi (`is_dragging_shape`/… activo sin botón), gizmo con
  padre no-CanvasItem, gizmo visible sin selección, `_bloquear_sincronizacion`
  atascado, `_pending_changes` que no drena, `_node_to_item_map` con refs
  muertas, y desajuste árbol↔escena en la jerarquía.
- Tests: `test/system/DebugConsola_test.gd` (dedupe + persistencia).

### 15ª ronda — limpieza visual del panel (estilo Apple)

49. **Tema claro** — `user://vectopen_theme.cfg` estaba en `mode="dark"`. Se
    puso en `light` (la `LIGHT_PALETTE` ya es estilo Apple). Causa de que
    volviera: `ThemeManager_test.gd` llamaba `set_mode("dark")` y no lo
    restauraba, y `_save_overrides()` machacaba la sección `[theme]`. Ambos
    arreglados.
50. **Botones duplicados** — `layout.tscn` tenía una cabecera con un
    `TextEdit` de búsqueda sin cablear + 5 botones-icono muertos
    (`BoxContainer2` / `BoxContainer3` bajo un `Control` de 85 px). Se eliminó
    todo el `Control`. También se quitaron el `Tree` invisible y los
    `layer_custom*` (prototipo antiguo).
51. **Búsqueda** — nuevo `LineEdit SearchLayers` en `layers_system.tscn`
    (entre `TitleBar` y `ButtonsBar`), cableado en
    `layers_system.gd::_conectar_botones` → `_on_buscar_capas` →
    `layer_tree.actualizar_filtro_busqueda`. Estilado con tokens del tema.
    Test: `LayerSystem_test.gd::test_buscar_capas_filtra_el_arbol`.
52. **`_aplicar_tema_panel`** — panel SIN marco y SIN sombra, esquinas 14,
    márgenes internos 16/14, `separation` 10 (aire para "LAYERS"). Los 6
    botones de acción van en "chips" gris claro redondeados (`_chip_sb`),
    28×28, para que se vea que son botones.
53. **`Layertree._apply_theme` — colores y espaciado del árbol** (varias
    iteraciones con el usuario, resultado final estilo Figma/Sketch):
    - Líneas de jerarquía = **gris casi blanco** `(0.87,0.87,0.90)`, grosor 1.
    - **NO hay línea azul de "rama seleccionada"**: `parent_hl` / `children_hl`
      van del mismo gris casi blanco y grosor 1 (la línea azul confundía con
      la selección).
    - Fila **SELECCIONADA** = relleno azul (`ACCENT` α 0.20) + **borde azul**
      1 px (nada de negro).
    - **Hover** = **verde claro** (`AFFIRMATIVE` α 0.20).
    - Espaciado ajustado: `v_separation` 3 (filas juntas), `indent_size` 15
      (sangría corta por nivel).
54. **Botones de fila (ojo/candado/máscara)** — ahora TODAS las filas (hoja o
    grupo) llevan los **3 botones en el mismo orden y columna** (1 ojo · 2
    candado · 3 máscara), así se alinean. Color: **activo/normal = negro**
    (`PANEL_TEXT`); **desactivado = gris casi blanco** `(0.87,0.87,0.90)`, el
    mismo de las líneas de jerarquía → el hueco se ve pero el icono casi no.
    `_color_boton` y `_refrescar_boton_clip` unificados (la máscara ya no usa
    azul). Test: `test_todas_las_filas_tienen_los_tres_botones`.
55. **Icono de máscara distinto por estado** — antes activa/inactiva usaban el
    mismo icono (solo cambiaba el color) y confundía. Ahora:
    inactiva = `frame-alt-empty.svg` (marco vacío, gris casi blanco),
    activa = `crop.svg` (recorte, negro). `_refrescar_boton_clip` cambia icono
    Y color según `clip_children`.

### 16ª ronda — máscara stencil para grupos y texto + iconos correctos

56. **Iconos de fila BLANCOS** — `set_button_color` MULTIPLICA (modulate): un
    icono negro NO se puede aclarar. `_icon_blanco()` pinta los píxeles a
    blanco (mismo alfa) → se puede teñir a cualquier tono. Así:
    ENGAGED = negro, DEFECTO/OFF = gris casi blanco `(0.87,0.87,0.90)` — se
    ve la diferencia. Candado: cerrado=negro, **abierto=gris** (invertido).
    Máscara ON = `exclude.svg`, OFF = `frame-alt-empty.svg`.
57. **Bug latente del serializador** — `_serialize_element` salía antes en cada
    `kind` de figura/texto → los hijos anidados NO se guardaban. Ahora recoge
    `base["children"]` para TODOS los tipos y `_apply_transform` los reconstruye
    recursivamente. (El anidado figura-en-figura ya estaba roto al guardar.)
58. **Máscara STENCIL** (grupos + texto) SIN nodo auxiliar: se reparenta el
    contenido BAJO el nodo-máscara y se le pone `clip_children` a ÉSTE.
    - grupo → máscara = último hijo-figura ("el de arriba"); texto → máscara =
      `DisplayLabel`.
    - `M.clip_children = CLIP_CHILDREN_ONLY` (M invisible, recorta al resto).
    - `_activar_mascara` / `_desactivar_mascara` en `layers_system.gd`, con undo
      (patrón de `_agrupar_seleccion`). El handler `_BTN_CLIP` enruta: figura
      con cuerpo propio → `clip_children` directo; grupo/texto → stencil.
    - metas `clip_mask` / `clip_mask_target` en el contenedor, serializadas.
    - `_desagrupar` desactiva la máscara antes de desagrupar.
    - Verificado en vivo por MCP: círculo recortado a un rectángulo. Tests:
      `LayerSystem_test.gd::test_mascara_stencil_de_grupo_*`,
      `CanvasSerializer_test.gd::test_roundtrip_figuras_anidadas_y_texto_con_hijo`.

### 14ª ronda — doble clic para entrar al hijo (estilo Affinity)

Para seleccionar un hijo anidado directamente en el lienzo (sin pasar por el
panel): **doble clic** desciende un nivel hacia la hoja bajo el cursor.

46. `MoveTool._on_double_click` → `_entrar_en_hijo(gm)`: toma el nodo de
    referencia (el seleccionado que esté en la rama del contenedor bajo el
    cursor, o el propio contenedor de primer nivel) y selecciona su **hijo
    directo** cuyo cuerpo/rama contiene el punto. Repetir el doble clic baja
    más. Clic sencillo sigue seleccionando el contenedor de primer nivel.
47. Muestra el bounding box del hijo → a partir de ahí se puede arrastrar,
    redimensionar, etc. (ver 13ª ronda).
48. **Verificado en vivo por MCP** (`DebugConsola` F1 = `_paso_doble_click`):
    clic → `[Rectángulo]`; doble clic #1 → `[Rectángulo 2]` (bajó=true);
    doble clic #2 → sin cambio (no hay más abajo); `bounding box visible=true`.
    Test: `LayerHierarchy_test.gd::test_doble_click_entra_al_hijo_anidado`.

### 13ª ronda — "los hijos no se pueden arrastrar en el lienzo"

Una figura anidada dentro de otra figura (rectángulo → rectángulo hijo) no se
podía coger y mover en el lienzo: el clic la deseleccionaba y seleccionaba el
padre.

42. **Causa:** `MoveTool._es_grupo_movetool()` devolvía `false` para cualquier
    `VectorShape`, aunque tuviera figuras anidadas dentro. Entonces
    `_hit_top_level` la trataba como HOJA (solo su propio rect) y `_on_press`
    nunca llegaba a la rama `_primer_seleccionado_en_rama` que arrastra el hijo
    ya seleccionado.
43. **Arreglo** (`MoveTool.gd`):
    - `_es_grupo_movetool(n)`: ahora `true` para cualquier `Node2D` con hijos
      `Node2D` de usuario (una figura CON figuras dentro es un contenedor a
      efectos de hit-test). `VectorShape` dibuja por `_draw()` sin nodos hijos
      de render, así que cualquier hijo `Node2D` es una figura del usuario.
    - `_rama_contiene_punto(n)`: comprueba también el CUERPO propio de `n`
      (`_tiene_cuerpo_propio`), no solo sus hijos → el padre-figura sigue
      clicable sobre su propio relleno.
44. **Resultado:** con el hijo seleccionado (p.ej. desde el panel), clic +
    arrastre sobre él en el lienzo lo mueve sin deseleccionar. Clic sobre un
    hijo NO seleccionado selecciona el contenedor (convención de editor pro;
    para entrar al hijo: seleccionarlo en el panel).
45. **Verificado en vivo por MCP** (`DebugConsola` F2 =
    `_paso_drag_hijo`): `_shape_at` sobre el hijo → padre (`_es_grupo=true`);
    `_on_press` → `selected=[hijo]`, `is_dragging_shape=true`; `_on_motion` →
    `hijo.global_position` Δ = (60,40) exacto. Test:
    `LayerHierarchy_test.gd::test_arrastrar_figura_dentro_de_figura_no_deselecciona`.

### 12ª ronda — CAUSA RAÍZ REAL de "1er anidado OK, el 2º saca las figuras"

La consola de diagnóstico capturó los arrastres REALES del usuario en su
instancia (los `[DBG:EVENTO] drop` salen de `_drop_data`, con ratón de verdad):

```
drop · [Rectángulo 4] → Rectángulo 2   (sección 0, idx 0)     ← anidó, OK
drop · [Rectángulo 3] → Artboard        (sección -100, idx 1)  ← ¡sección -100!
drop · [Rectángulo 4] → Artboard        (sección -100, idx 2)  ← SACÓ la figura
...
```

39. **`Tree.get_drop_section_at_position()` devuelve `-100`** ("no lo sé")
    después del PRIMER reparent + rebuild del árbol. Con -100, `_drop_data`
    caía siempre en la rama "hermano" → `dest_parent = nodo_destino.get_parent()`
    = el **Artboard** → cada drop posterior NO anidaba y encima **sacaba** las
    figuras al nivel del artboard. De ahí "el primero funciona y luego todo se
    rompe".
40. **Arreglo:**
    - `Layertree._seccion_drop(pos, item)`: si el motor devuelve algo fuera de
      `[-1,1]`, recalcula la zona desde el rect de la fila
      (`_seccion_por_rect`, static y testeable): 30 % arriba / 40 % centro
      (= DENTRO) / 30 % abajo. `_can_drop_data` y `_drop_data` la usan.
    - `LayerSystem.sincronizar_arbol_completo`: re-afirma
      `layer_tree.drop_mode_flags = 3` tras cada `clear()` (posible causa de
      que el motor perdiera el modo de drop).
41. **Tests:** `LayerTree_test.gd::test_seccion_drop_recalcula_cuando_el_motor_
    no_lo_sabe`.

### 11ª ronda — "1er anidado OK, el 2º bloquea" — timing de la re-sync

Con la consola de diagnóstico (F3/F6/F5 en `DebugConsola`) se probó en el juego
real: `mover_capas` + `_get_drag_data` + re-sync, **dos veces seguidas**, y NO se
bloquea nada por ese lado (`gui_is_dragging=false`, flags limpios,
`_bloquear_sincronizacion=false`, `pending=0`, panel↔escena OK las dos veces).
→ El bloqueo vive en la máquina de drag&drop del `Viewport` de Godot con
captura real del ratón del SO, algo que MCP no puede provocar.

Dos causas probables corregidas:

37. **`_get_drag_data` devolvía el `TreeItem` (`origin_item`) en `data`.** La
    re-sync tras el drop hace `layer_tree.clear()` → libera ese TreeItem; si el
    sistema de drag de Godot aún retiene el dict `data`, queda una referencia
    colgante → el SEGUNDO arrastre no arranca. Ahora `_get_drag_data` devuelve
    solo `{"nodes": [...]}` (nodos reales, sobreviven al clear).
38. **La re-sync corría DEMASIADO pronto.** `hierarchy_changed_by_user` se
    emite DENTRO de `_drop_data`, es decir mientras Godot sigue en su gestión
    del drop. `_on_hierarchy_changed_by_user` hacía
    `sincronizar_arbol_completo.call_deferred()` → el `layer_tree.clear()` podía
    ejecutarse antes de que Godot terminara con el drag → punteros colgantes.
    Ahora `_resync_tras_drag()` espera DOS `process_frame` (frame limpio, drag
    ya terminado) antes de reconstruir.

### Fase 1 — detalle de lo hecho

- `autoloads/SelectionManager.gd` (nuevo autoload, registrado en `project.godot`
  justo tras `GlobalUI`). API: `select(node, Mode)`, `select_many`, `deselect`,
  `clear`, `set_selection`, `select_children/descendants/branch`, `begin_batch/
  end_batch`, `get_selected/get_active/get_anchor/set_anchor`, `is_selected`,
  `count`, `is_empty`. Señales `changed(selected)` y `active_changed(node)`.
  Filtra nodos no-capa (nombres de render internos) y bloqueados; depura
  referencias liberadas. Re-emite `GlobalEvents.selection_changed` (compat).
- `MoveTool`: `selected_shapes` es ahora un ESPEJO local que
  `_emit_selection_changed()` refleja hacia `SelectionManager`; cuando la
  selección cambia desde otra superficie, `_on_external_selection_changed()`
  la copia de vuelta y reconstruye el bounding box.
- `LayerSystem`: sync bidireccional. `_on_canvas_selection_changed()` marca las
  filas, abre los padres y hace scroll. `_empujar_seleccion_del_arbol()`
  (diferido) envía la selección del árbol a `SelectionManager`. Guarda
  `_reflejando_seleccion` contra el eco.
- `bounding_box`: sale antes si su padre no es `CanvasItem` (instancias
  zombis del pool); ruta de `FieldsWrapper` corregida a `PANEL_BOUNDINGBOX/MB/…`.
- `LayerTree`: `SELECT_MULTI` (varias filas a la vez), sin el forzado de color
  de texto blanco permanente.
