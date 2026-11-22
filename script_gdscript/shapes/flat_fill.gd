# =============================================================================
# RUTA: res://script_gdscript/shapes/flat_fill.gd
# Relleno de UN color con la orden de dibujo más ligera (memoria, VAL-39).
# Medido en Godot 4.7: draw_colored_polygon reserva ~8 KB por polígono en el
# servidor de render; un rectángulo alineado con draw_rect ~0 KB; el resto,
# triangulado aquí y enviado como lista de triángulos, ~3 KB. Mismo resultado
# en pantalla. Lo usan VectorShape (y sus figuras) y VectorPath.
# =============================================================================
extends RefCounted

static func draw(ci: CanvasItem, points: PackedVector2Array, col: Color) -> void:
	if points.size() < 3:
		return
	if points.size() == 4 and is_axis_rect(points):
		var r := Rect2(points[0], Vector2.ZERO)
		for p in points:
			r = r.expand(p)
		ci.draw_rect(r, col, true)
		return
	var idx := Geometry2D.triangulate_polygon(points)
	if idx.size() >= 3:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, points, PackedColorArray([col]))
		return
	# Contorno que se CRUZA consigo mismo (p. ej. esquinas en zigzag con
	# mucho redondeo en una figura estrecha: los dientes de dos esquinas se
	# pisan). Ni Godot ni la triangulación lo rellenan → desaparecía el
	# relleno. Se limpia uniéndolo consigo mismo y se rellena cada trozo.
	for poly in triangulable_polys(points):
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(),
			Geometry2D.triangulate_polygon(poly), poly, PackedColorArray([col]))

## Trozos de `points` que SÍ se pueden triangular: el propio contorno; si se
## cruza, su unión consigo mismo; si aún hay puntos que se tocan (dientes de
## sierra), cada trozo con un desplazamiento mínimo de Clipper.
static func triangulable_polys(points: PackedVector2Array) -> Array:
	if Geometry2D.triangulate_polygon(points).size() >= 3:
		return [points]
	var out: Array = []
	for poly in simple_polys(points):
		if Geometry2D.triangulate_polygon(poly).size() >= 3:
			out.append(poly)
			continue
		for g in Geometry2D.offset_polygon(poly, 0.01, Geometry2D.JOIN_MITER):
			if not Geometry2D.is_polygon_clockwise(g) and Geometry2D.triangulate_polygon(g).size() >= 3:
				out.append(g)
	return out

## Contornos simples (sin cruces) que cubren `points`: la unión consigo mismo.
## Solo los exteriores (sentido antihorario en Godot); los huecos que deja un
## cruce también se rellenan, como haría un relleno «no cero».
static func simple_polys(points: PackedVector2Array) -> Array:
	var out: Array = []
	for p in Geometry2D.merge_polygons(points, points):
		if not Geometry2D.is_polygon_clockwise(p) and p.size() >= 3:
			out.append(p)
	return out

static func is_axis_rect(p: PackedVector2Array) -> bool:
	for i in 4:
		var a := p[i]
		var b := p[(i + 1) % 4]
		if not (is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)):
			return false
	return true
