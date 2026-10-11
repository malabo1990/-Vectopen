# VOP — Vectopen open vector format (version 2)

`.vop` is Vectopen's **vector interchange format**, in the same family as SVG and EPS.
`.vectopen` stays the working project file (all artboards, history-free); `.vop` holds
**one artboard or a selection** and is meant to be read by other tools (Blender, Godot,
web, OS previewers…).

A VOP file is UTF-8 JSON with two layers:

| Layer | Who reads it | Content |
|---|---|---|
| `render` | **any** reader | Resolved drawing: Bézier outlines in artboard coordinates, fills, strokes, gradients, text, images. Enough to display or convert the file. |
| `elements` | Vectopen | Lossless native data: parametric shapes (stars, polygons, rounded corners), effects, filters, shaders, rich text. |

A reader that only needs to **show** the file implements `render`. Only an editor that wants
full editability needs `elements`.

## Top level

```json
{
  "format": "vop",
  "version": 2,
  "generator": "Vectopen 0.1.1",
  "name": "Artboard",
  "size": [794, 1123],
  "anchor": [0, 0],
  "render": { ... },
  "elements": [ ... ]
}
```

- Readers must check `format == "vop"` and `version`. Same major version = compatible;
  unknown keys must be ignored.
- `size` is the size of the content box. For a whole artboard it is the artboard size and
  `anchor` is `[0, 0]`. For a **selection**, `size` is the selection's own bounding box and
  `anchor` is where its top-left corner was in the artboard; `render` coordinates are relative
  to that box (0,0 = its top-left), so the selection is its own pivot, not the page.

## Readers

- **Godot 4.2+:** `integrations/godot/addons/vectopen` in the Vectopen repo — an editor import
  plugin (`.vop` → native scene: Polygon2D, Line2D, Label, Sprite2D, no scripts) plus
  `VopReader.load_scene(path)` for runtime loading.

## `render`

```json
{ "units": "px", "origin": "top-left", "y_down": true,
  "background": "#ffffffff" | null,
  "items": [ ... drawn in order, first = bottom ... ] }
```

Colors are `"#rrggbbaa"` strings; `null` means "none".

### `path`

```json
{ "type": "path",
  "subpaths": [ { "ops": [["M",x,y], ["L",x,y], ["C",c1x,c1y,c2x,c2y,x,y]], "closed": true } ],
  "fill": "#e63333ff" | null,
  "stroke": "#000000ff" | null, "stroke_width": 2, "cap": "butt|round|square",
  "fill_rule": "nonzero|evenodd",
  "opacity": 1.0,
  "gradient": { "kind": "linear|radial", "angle": 0.0, "units": "bbox",
                "stops": [[0.0, "#ff0000ff"], [1.0, "#0000ffff"]] } }
```

- Coordinates are absolute in artboard space (transforms already applied).
- `C` is a cubic Bézier: two control points, then the end point.
- Several subpaths with `evenodd` = shapes with holes.
- `gradient` (optional) replaces `fill`; `angle` in radians, `bbox` = relative to the path bounds.
- Line joins are round.

### `text`

```json
{ "type": "text", "transform": [a, b, c, d, e, f], "text": "Line 1\nLine 2",
  "size": 24, "color": "#000000ff", "family": "Inter", "bold": false, "italic": false,
  "line_height": 1.2, "opacity": 1.0 }
```

`transform` maps the text box (origin at its top-left) to artboard space:
`x' = a·x + c·y + e`, `y' = b·x + d·y + f`. Line *i* has its baseline at
`y = size·0.8 + i·size·line_height`.

### `image`

```json
{ "type": "image", "transform": [a, b, c, d, e, f], "width": 64, "height": 64,
  "png_base64": "iVBORw0…", "opacity": 1.0 }
```

The image covers `(0,0)–(width,height)` before `transform`.

## `elements`

Vectopen's own serialization (same as `.vectopen`). Not specified for other tools; it can
change between Vectopen versions while `render` stays stable.

## Not included

Shaders, filters and effects other than the drop shadow are raster-only: they live in
`elements` but not in `render`. Export PNG if they must be seen elsewhere.
