# Exportar e importar (panel de archivos)

Panel inferior, en dos partes, **sin diálogos de Aceptar**: eliges el formato y arrastras.

## Izquierda · Archivos
- **Recientes**, **Archivos** (navega carpetas reales), **Recuperar** (autoguardados).
- **Importar:** arrastra archivos desde el explorador del sistema al lienzo o al panel,
  o arrastra un archivo de la lista al lienzo: se importa donde lo sueltas (un Ctrl+Z).
- Formatos que se importan: SVG (completo: trazados, arcos, grupos, transformaciones,
  estilos, texto, imágenes), PNG/JPG/WEBP, **VOP**, TSCN/SCN, GLB/GLTF (3D) y `.vectopen`.

## Derecha · Exportar
- Ámbito: **Artboards · Capas · Selección**. Cada fila tiene su **formato** (y escala 0,5×–4×
  en PNG/JPG/WEBP). Se recuerda por objeto.
- **Arrastra una fila** a una carpeta de la lista → se exporta ahí. Soltarla en
  **Recientes** la guarda en la **Biblioteca** (`Documentos/Vectopen/Biblioteca`, VOP) para reutilizarla.
- Nunca sobrescribe: `logo.svg`, `logo (2).svg`…
- **Suelta archivos sobre una fila** (desde el explorador o la lista) → se **convierten** al
  formato de la fila junto al original. Una imagen a SVG/PDF/EPS/VOP se **vectoriza**.
- Sin arrastrar: **doble clic** en una fila, o marca filas y **Exportar marcados (Ctrl+E)**
  → carpeta de destino (botón de carpeta).
- **Sin fondo**: PNG, WEBP, SVG, PDF y EPS sin el fondo del artboard.
- Resultado: `✓ logo.svg → Descargas · Abrir carpeta · Deshacer` (deshacer borra lo exportado).

## Formatos

| Formato | Tipo | Notas |
|---|---|---|
| SVG | vectorial | Bézier reales, grupos, transformaciones, degradados, sombra, texto, imágenes |
| PDF | vectorial | PDF 1.4, transparencias, texto Helvetica, imágenes con alfa |
| EPS | vectorial | PostScript real (sin transparencia: no existe en PS) |
| VOP | vectorial | De una selección guarda SU tamaño (la selección es el eje). Plugin para Godot: `integrations/godot`. Formato propio y abierto: capa `render` para cualquier programa + datos sin pérdidas. Ver `reference/VOP_FORMAT.md` |
| PNG · JPG · WEBP | imagen | Incluye shaders, filtros y efectos |
| TSCN · SCN | escena Godot | Solo nodos nativos (Polygon2D, Line2D, Label, Sprite2D), sin scripts: se ve en cualquier proyecto de Godot |

Shaders, filtros y efectos (salvo la sombra) solo existen en imagen: para verlos fuera, exporta PNG.
JPEG XL no está disponible (Godot no puede escribirlo).

## Desde scripts
`await api.export("ruta.svg", artboard, {"scale": 2, "transparent": true, "quality": 90})`.
