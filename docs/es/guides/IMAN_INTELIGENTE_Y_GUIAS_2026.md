# Vectopen — Imán inteligente y guías de regla (Septiembre 2026)

> Documento vivo. Versión: 1.0
> Relacionado: `autoloads/SnapManager.gd`, `script_gdscript/tools/MoveTool.gd`,
> `script_gdscript/utils/regla.gd`, `docs/es/guides/REDISENO_ELEGANTE_UI_2026.md`

Sistema de imán al estilo Affinity / Figma / Illustrator: al arrastrar una
figura se alinea con otras figuras, con la mesa de trabajo y con las guías de
regla, mostrando líneas guía y medidas de separación.

---

## 1. `SnapManager` — el motor

Autoload. Todo en **coordenadas de mundo**; el umbral es constante en pantalla
(se divide por el zoom del viewport).

| Ajuste | Por defecto | Persiste en |
|---|---|---|
| `grid_enabled` / `grid_size` | off / 10 | `user://vectopen_snap.cfg` |
| `snap_to_objects` | **on** | idem |
| `snap_to_center` | **on** | idem |
| `snap_to_guides` | **on** | idem |

Constantes: `SMART_SNAP_PX = 11`, `SPACING_SNAP_PX = 9`, `SPACING_MATCH_EPS = 1.5`.

### `smart_snap(moving: Rect2, candidates: Array, zoom: float) -> Dictionary`

Devuelve `{ offset: Vector2, guides: Array, spacing: Array }`.

Estrategias por eje (la más cercana gana; 2 y 3 solo si el eje no se alineó por
borde):

1. **Alineación** — bordes izquierda/derecha/arriba/abajo y centros X/Y contra
   cada rect candidato + **las guías de regla** (`guide_x` / `guide_y`).
   `guide = { axis, coord, a, b, guide? }`.
2. **Igualar separación** (`_spacing_snap`) — si el hueco hacia el vecino
   coincide con otro hueco ya existente entre dos figuras de la misma fila /
   columna, engancha a esa misma distancia.
3. **Distribución** — centra la figura entre el vecino de un lado y el del otro.
   `spacing = { axis, perp, gap, segs: [[lo,hi], ...] }`.

La prioridad grid > imán: si `grid_enabled`, el imán inteligente no actúa
(manda la cuadrícula).

### Guías de regla

`regla.gd` publica sus guías con `SnapManager.set_guides(guias_verticales,
guias_horizontales)` en cada refresco:

- `guide_x` = líneas **verticales** (una coord X cada una)
- `guide_y` = líneas **horizontales** (una coord Y cada una)

---

## 2. `MoveTool` — integración con el arrastre

En la rama `is_dragging_shape` de `_on_motion`:

- Se construye `_macro_rect_inicial()` (rect de la selección al empezar el
  arrastre, desde `transform_initial_states[s]["gpos"]`).
- `_snap_candidates()` reúne las capas de primer nivel del/los artboard(s) que
  contienen la selección (vía `VectorDrawingLayer`), excluyendo la selección y
  sus ancestros/descendientes, más `mgr.world_rect(ab)`. Tope 240.
- `smart_snap(...)` ajusta el `delta`; se guardan `_snap_guides` y
  `_snap_spacing` para dibujarlos.

**Se suprime con:** `grid_enabled`, `Shift` / `Alt` / `Ctrl`, o un tirador de
eje del bounding box (`_axis_move != ""`).

### Dibujo (`_dibujar_guias_iman`, en `draw_preview`)

- **Alineación con figuras** → línea magenta (`COLOR_SNAP_GUIDE`) que cruza toda
  la vista (`ext = 4000` u. de mundo) + marcas en los bordes exactos.
- **Enganche a guía de regla** → línea azul (`COLOR_SNAP_RULE`), un poco más
  gruesa.
- **Separación / distribución** → barras rosas con la distancia en px
  (`ThemeDB.fallback_font`).

Se limpian en `_on_release` y en `_heal_stuck_gesture`.

---

## 3. `regla.gd` — guías estilo editor profesional

El sistema de arrastrar guías desde las reglas ya existía (crear, mover, borrar
soltando sobre la regla, destellos). Añadido:

- `_publicar_guias_al_snap()` — alimenta al `SnapManager` (ver arriba).
- `_snap_guia(coord)` — al crear o mover una guía, redondea al paso de
  cuadrícula (si `grid_enabled`) o al **píxel entero**. Nada de guías en
  `x = 347.8`.
- `_etiqueta_coord(...)` — pastilla oscura con la coordenada de mundo junto a la
  guía mientras se arrastra una nueva o se mueve una existente (como
  Figma / Illustrator).
- `get_guides_x()` / `get_guides_y()` — API pública (copia).

Colores de guía (exportados en `main.tscn`): normal = azul petróleo
`#0057~`, seleccionada = rojo `#DA002B`.

---

## 4. UI

**Ajustes › Snapping** (`SnapSection.gd` + `manager_windws_regla.tscn`):

- `Smart Snap (objects)` → `set_snap_to_objects`
- `Snap to Guides` → `set_snap_to_guides`
- `Grid Snap` + `Grid Size` (ya existían)

---

## 5. Verificación

- **gdUnit**: `test/autoloads/SnapManager_test.gd` — 12 casos: alineación de
  bordes, escala con el zoom, `snap_to_center` off, distribución, igualar
  separación, enganche a guía y guías desactivadas.
- MoveTool + regresión de transform: 28/28, sin regresiones.
- Escena en vivo: 0 errores; `SnapManager.snap_to_objects/guides = true`
  confirmado en runtime.
- ⚠️ El **tacto del arrastre y las líneas** no se pueden verificar por MCP
  (posición del ratón sintético congelada — ver
  `selection_manager_architecture`). Verificación con tests unitarios +
  confirmación del usuario con ratón real.

---

## 6. Pendiente / ideas

- Imantar la **guía** a bordes de figura al arrastrarla (hoy solo se redondea).
- Imán al **crear** figuras (herramientas de rectángulo, elipse, etc.), no solo
  al mover.
- Imán en **redimensionar** (hoy solo en mover).
