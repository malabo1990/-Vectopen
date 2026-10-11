# Export and import (file panel)

Bottom panel, two halves, **no "OK" dialogs**: pick a format and drag. Spanish version:
`docs/es/guides/exportar_e_importar.md`.

**Left · Files** — Recent, Files (real folders), Recover. Import by dragging files from the OS
onto the canvas or the panel, or a file from the list onto the canvas (dropped where you release,
one undo step). Imports SVG (full grammar, arcs, groups, transforms, styles, text, images),
PNG/JPG/WEBP, VOP, TSCN/SCN, GLB/GLTF, `.vectopen`.

**Right · Export** — Scope: Artboards · Layers · Selection. Each row has its format (and scale for
raster), remembered per object.
- Drag a row onto a folder in the list → exported there; onto **Recent** → saved to the Library
  (`Documents/Vectopen/Biblioteca`, VOP). Never overwrites (`logo (2).svg`).
- Drop files on a row → converted to that row's format next to the original (raster → vector is vectorized).
- Without dragging: double-click a row, or check rows and **Export checked (Ctrl+E)**.
- Status line with Open folder and Undo (deletes what was just written).

Formats: SVG, PDF, EPS (vector, from the real geometry), VOP (open vector format, see
`reference/VOP_FORMAT.md`), PNG/JPG/WEBP (raster, includes shaders/filters/effects), TSCN/SCN
(portable Godot scenes: native nodes only, no scripts). A VOP of a selection keeps the selection's own size and pivot; Godot plugin in `integrations/godot`. JPEG XL is not offered (Godot can't write it).

Engine: `script_gdscript/system/vector_export.gd` (SVG/PDF/EPS/VOP render layer),
`svg_import.gd`, `ImportExportManager` (`export_nodes`, `import_any`, `convert_file`),
UI `script_gdscript/ui/panels/export/export_rows.gd` + `scenes/ui/FileFlowLayout.gd`.
Tests: `test/core/VectorExport_test.gd`, `test/ui/ExportPanel_test.gd`, `test/ui/FileFlowLayout_test.gd`.
