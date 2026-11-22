# =============================================================================
# RUTA: res://script_gdscript/shapes/light_shadow_node.gd
# SOMBRA EXTERIOR de una figura (iluminación 2D): la proyección de la figura
# desde cada luz con sombra, dibujada DETRÁS de la figura (show_behind_parent)
# y encima de lo que hay debajo. La figura sigue iluminada (antes el oclusor de
# Godot la dejaba oscura por dentro: «solo sombra interior»).
# Borde difuminado por capas crecientes cada vez más transparentes.
# Nodo interno: no se guarda (se rehace) ni se selecciona.
# =============================================================================
extends Node2D

## [{"polys": Array[PackedVector2Array], "color": Color, "soft": float}]
var shadows: Array = []

func _init() -> void:
	name = "_LightShadow"
	show_behind_parent = true
	light_mask = 1
	set_meta(&"_vectopen_internal", true)

func _draw() -> void:
	for s in shadows:
		var col: Color = s["color"]
		var soft: float = float(s["soft"])
		var steps := 1 if soft < 0.5 else 6
		for poly in s["polys"]:
			if steps == 1:
				draw_colored_polygon(poly, col)
				continue
			# núcleo + anillos difuminados
			for k in range(steps, 0, -1):
				var grow := soft * float(k) / steps
				var a := col.a / float(steps)
				for g in Geometry2D.offset_polygon(poly, grow - soft * 0.5, Geometry2D.JOIN_ROUND):
					if not Geometry2D.is_polygon_clockwise(g) and g.size() >= 3:
						draw_colored_polygon(g, Color(col, a))

## Proyección de `pts` (contorno cerrado, coordenadas locales) desde la luz.
## `src` = posición de la luz (puntual) o dirección (direccional, `dir_mode`).
static func project(pts: PackedVector2Array, src: Vector2, length: float, dir_mode: bool) -> Array:
	if pts.size() < 3 or length <= 0.0:
		return []
	var acc: Array = [pts]
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var da := src.normalized() if dir_mode else (a - src).normalized()
		var db := src.normalized() if dir_mode else (b - src).normalized()
		var quad := PackedVector2Array([a, b, b + db * length, a + da * length])
		if absf((b - a).cross(quad[3] - a)) < 0.0001:
			continue
		var merged: Array = []
		var added := false
		for poly in acc:
			if not added:
				var m := Geometry2D.merge_polygons(poly, quad)
				var outer := m.filter(func(p) -> bool: return not Geometry2D.is_polygon_clockwise(p))
				if outer.size() == 1:
					merged.append(outer[0])
					added = true
					continue
			merged.append(poly)
		if not added:
			merged.append(quad)
		acc = merged
	return acc
