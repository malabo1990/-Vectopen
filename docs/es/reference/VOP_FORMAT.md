# VOP — formato vectorial abierto de Vectopen (versión 2)

`.vop` es el **formato vectorial de intercambio** de Vectopen, de la familia de SVG y EPS.
`.vectopen` sigue siendo el archivo de proyecto para trabajar; `.vop` guarda **un artboard o
una selección** y está pensado para que lo lean otras herramientas (Blender, Godot, web,
visores del sistema…).

Es JSON en UTF-8 con dos capas:

| Capa | Quién la lee | Contenido |
|---|---|---|
| `render` | **cualquier** lector | Dibujo resuelto: contornos Bézier en coordenadas del artboard, rellenos, trazos, degradados, texto, imágenes. Suficiente para mostrar o convertir. |
| `elements` | Vectopen | Datos nativos sin pérdidas: figuras paramétricas (estrellas, polígonos, esquinas), efectos, filtros, shaders, texto enriquecido. |

Un lector que solo **muestra** el archivo implementa `render`; solo un editor que quiera
editarlo todo necesita `elements`.

La especificación completa (estructura, `path`, `text`, `image`, coordenadas y colores) está
en [`docs/en/reference/VOP_FORMAT.md`](../../en/reference/VOP_FORMAT.md). Resumen:

- Nivel superior: `format: "vop"`, `version: 2`, `generator`, `name`, `size`, `render`, `elements`.
  Misma versión mayor = compatible; las claves desconocidas se ignoran.
- `size` = caja del contenido. Artboard entero: su tamaño y `anchor` `[0, 0]`. **Selección**:
  la caja de la selección y `anchor` = dónde estaba su esquina; `render` va relativa a esa caja
  (la selección es su propio eje, no la página).
- Lectores: **Godot 4.2+** → `integrations/godot/addons/vectopen` (plugin de importación:
  `.vop` → escena nativa sin scripts; y `VopReader.load_scene(ruta)` en el juego).
- Colores `"#rrggbbaa"`; `null` = ninguno. Coordenadas en px, origen arriba-izquierda, y hacia abajo.
- `path`: subtrazados con operaciones `M`, `L`, `C` (Bézier cúbica) ya transformadas;
  `fill_rule` evenodd para agujeros; `gradient` opcional.
- `text` e `image`: `transform` = matriz `[a, b, c, d, e, f]` desde su esquina superior izquierda.
- Shaders, filtros y efectos (salvo la sombra) solo existen al rasterizar: van en `elements`, no en `render`.
