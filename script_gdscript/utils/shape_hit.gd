# =============================================================================
# RUTA: res://script_gdscript/utils/shape_hit.gd
# ¿El clic toca de VERDAD la figura? (herramienta Mover, como Illustrator /
# Affinity). Antes, curvas y trazos de pincel se comprobaban con su recuadro:
# un clic en el hueco de una curva o junto a un trazo seleccionaba ese objeto
# en vez del que había debajo. Las imágenes contaban también lo transparente.
#   · trazo de pincel → su forma pintada (eje ± medio grosor; figuras y
#     texto en trazado, por su malla);
#   · curva → su relleno (si lo tiene) o su línea;
#   · figura sin relleno → solo su borde;
#   · imagen → solo los píxeles no transparentes.
# `tol` = margen en unidades del lienzo (unos píxeles de pantalla).
# =============================================================================
extends RefCounted

const R = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
const StrokeGeom = preload("res://script_gdscript/shapes/stroke_geom.gd")

## Distancia de `q` a una polilínea (cerrada o no).
static func dist_to_polyline(q: Vector2, pts: PackedVector2Array, closed: bool) -> float:
	var n := pts.size()
	if n == 0:
		return INF
	if n == 1:
		return q.distance_to(pts[0])
	var best := INF
	var segs := n if closed else n - 1
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ab := b - a
		var f := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * f))
	return best

static func _scale_of(n: Node2D) -> float:
	var s := n.get_global_transform().get_scale()
	return maxf((absf(s.x) + absf(s.y)) * 0.5, 1e-6)

## Trazo de pincel (Line2D).
static func line_hit(line: Line2D, gpos: Vector2, tol: float) -> bool:
	if line.points.size() == 0:
		return false
	var q := line.to_local(gpos)
	var tl := tol / _scale_of(line)
	var half := line.width * 0.5
	if line.width_curve and line.width_curve.point_count > 0:
		var mx := 0.0
		for i in line.width_curve.point_count:
			mx = maxf(mx, line.width_curve.get_point_position(i).y)
		half *= maxf(mx, 0.0001)
	var style := String(line.get_meta("brush_style", ""))
	if style != "object":
		return dist_to_polyline(q, line.points, line.closed) <= half + tl
	# Figuras / texto en trazado: por la malla dibujada.
	var r := line.get_node_or_null(R.NODE_NAME)
	if r and r.has_method("visual_mesh"):
		var m: Dictionary = r.visual_mesh()
		if not m.is_empty():
			var v: PackedVector2Array = m["points"]
			var idx: PackedInt32Array = m["indices"]
			for t in range(0, idx.size(), 3):
				if Geometry2D.point_is_inside_triangle(q, v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]):
					return true
			# cerca de una letra (margen de pantalla)
			if tl > 0.0:
				for t in range(0, idx.size(), 3):
					var a := v[idx[t]]
					if a.distance_to(q) <= tl * 2.0:
						return true
			return false
	return dist_to_polyline(q, line.points, false) <= half + tl

## Curva (Path2D / VectorPath).
static func path_hit(path: Path2D, gpos: Vector2, tol: float) -> bool:
	var curve: Curve2D = path.curve
	if curve == null or curve.point_count == 0:
		return false
	var q := path.to_local(gpos)
	var tl := tol / _scale_of(path)
	var closed: bool = bool(path.get("closed")) if "closed" in path else false
	var VP = load("res://script_gdscript/shapes/VectorPath.gd")
	var pts: PackedVector2Array = VP.closed_points(curve) if closed else StrokeGeom.curve_points(curve)
	if pts.size() < 2:
		return q.distance_to(curve.get_point_position(0)) <= tl
	var fill_on := closed and "fill_color" in path and (path.get("fill_color") as Color).a > 0.01
	if path.has_method("has_gradient_fill") and closed and path.has_gradient_fill():
		fill_on = true
	if fill_on:
		for poly in VP.fill_polygons(pts):
			if Geometry2D.is_point_in_polygon(q, poly):
				return true
	var sw := float(path.get("stroke_width")) if "stroke_width" in path else 0.0
	var stroke_on := sw > 0.0 and (not ("stroke_color" in path) or (path.get("stroke_color") as Color).a > 0.01)
	var reach := (sw * 0.5 if stroke_on else 0.0) + tl
	# Las subrutas (agujeros) también tienen línea.
	if dist_to_polyline(q, pts, closed) <= reach:
		return true
	if "subpaths" in path:
		for c in path.get("subpaths"):
			if c and (c as Curve2D).point_count >= 2 and dist_to_polyline(q, VP.closed_points(c), true) <= reach:
				return true
	return false

## Figura SIN relleno (rectángulo, elipse, polígono…): solo su borde.
static func outline_hit(node: Node2D, gpos: Vector2, tol: float) -> bool:
	if not node.has_method("get_evaluated_geometry"):
		return false
	var q := node.to_local(gpos)
	var tl := tol / _scale_of(node)
	var sw := float(node.get("stroke_width")) if "stroke_width" in node else 0.0
	var reach := sw * 0.5 + tl
	for poly in node.get_evaluated_geometry():
		if dist_to_polyline(q, poly, true) <= reach:
			return true
	return false

## ¿La figura tiene relleno visible?
static func has_visible_fill(node: Object) -> bool:
	if node.has_method("has_gradient_fill") and node.has_gradient_fill():
		return true
	if "fill_color" in node:
		return (node.get("fill_color") as Color).a > 0.01
	return true

## Imagen: dentro del rectángulo y sobre un píxel no transparente.
static func sprite_hit(sp: Sprite2D, gpos: Vector2) -> bool:
	var lp := sp.to_local(gpos)
	if not sp.get_rect().has_point(lp):
		return false
	return sp.is_pixel_opaque(lp)

# ── Marquee: ¿el rectángulo (global) pisa la forma? ──────────────────────────
## Polilínea (local) que toca un polígono convexo `rp` (el rectángulo en local).
static func polyline_touches(pts: PackedVector2Array, closed: bool, rp: PackedVector2Array) -> bool:
	var n := pts.size()
	for q in pts:
		if Geometry2D.is_point_in_polygon(q, rp):
			return true
	var segs := n if closed else n - 1
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		for k in 4:
			if Geometry2D.segment_intersects_segment(a, b, rp[k], rp[(k + 1) % 4]) != null:
				return true
	return false

static func _rect_local(node: Node2D, r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([node.to_local(r.position), node.to_local(Vector2(r.end.x, r.position.y)),
		node.to_local(r.end), node.to_local(Vector2(r.position.x, r.end.y))])

static func rect_hit(node: Node2D, r: Rect2, tol: float = 0.0) -> bool:
	var sc := _scale_of(node)
	if node is Line2D:
		var line := node as Line2D
		var style := String(line.get_meta("brush_style", ""))
		if style == "object":
			var rd := line.get_node_or_null(R.NODE_NAME)
			if rd and rd.has_method("visual_mesh"):
				var m: Dictionary = rd.visual_mesh()
				if not m.is_empty():
					var rp0 := _rect_local(line, r.grow(tol))
					for v in (m["points"] as PackedVector2Array):
						if Geometry2D.is_point_in_polygon(v, rp0):
							return true
					return false
		var rp := _rect_local(line, r.grow(line.width * 0.5 * sc + tol))
		return polyline_touches(line.points, line.closed, rp)
	if node is Path2D:
		var path := node as Path2D
		if path.curve == null or path.curve.point_count == 0:
			return false
		var closed: bool = bool(path.get("closed")) if "closed" in path else false
		var VP = load("res://script_gdscript/shapes/VectorPath.gd")
		var pts: PackedVector2Array = VP.closed_points(path.curve) if closed else StrokeGeom.curve_points(path.curve)
		var sw := float(path.get("stroke_width")) if "stroke_width" in path else 0.0
		var rp := _rect_local(path, r.grow(sw * 0.5 * sc + tol))
		if polyline_touches(pts, closed, rp):
			return true
		if closed and has_visible_fill(path):
			for poly in VP.fill_polygons(pts):
				for c in rp:
					if Geometry2D.is_point_in_polygon(c, poly):
						return true
		return false
	if node.has_method("get_evaluated_geometry"):
		var sw2 := float(node.get("stroke_width")) if "stroke_width" in node else 0.0
		var rp2 := _rect_local(node, r.grow(sw2 * 0.5 * sc + tol))
		for poly in node.get_evaluated_geometry():
			if polyline_touches(poly, true, rp2):
				return true
		return false
	return true
