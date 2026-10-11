# Vectopen VOP para Godot

Importa archivos **.vop** (formato vectorial abierto de Vectopen) como escenas 2D
**nativas**: `Polygon2D` (rellenos, agujeros, degradados), `Line2D` (trazos),
`Label` (texto) y `Sprite2D` (imágenes). No necesita Vectopen ni sus scripts.

## Instalar
1. Copia la carpeta `addons/vectopen` en tu proyecto (`res://addons/vectopen`).
2. Proyecto → Ajustes del proyecto → Plugins → activa **Vectopen**.
3. Copia tus `.vop` al proyecto: aparecen como escenas. Arrástralos al editor 2D
   o instáncialos como cualquier `.tscn`. Si cambias el `.vop`, se reimporta solo.

Opciones de importación (pestaña Importar): incluir fondo, detalle de curvas, antialias.

## En el juego
```gdscript
var dibujo := VopReader.load_scene("res://logo.vop")   # Node2D
add_child(dibujo)
```

## Formato
Especificación: `docs/en/reference/VOP_FORMAT.md` en el repositorio de Vectopen.
Requiere Godot 4.2 o superior.

---

# Vectopen VOP for Godot (EN)

Imports **.vop** files as native 2D scenes (Polygon2D, Line2D, Label, Sprite2D), no
Vectopen scripts needed. Copy `addons/vectopen` into your project, enable the
**Vectopen** plugin, drop `.vop` files in. At runtime: `VopReader.load_scene(path)`.
