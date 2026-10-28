# =============================================================================
# VECTOPEN — DEGRADADO EN EL TRAZO
# RUTA: res://script_gdscript/shapes/stroke_paint.gd
#
# Color por vértice para dibujar un trazo con degradado (lineal o radial)
# sobre la caja del propio trazo. Lo usan VectorShape (contornos de
# rectángulo, círculo, polígono, estrella) y VectorPath (trazos Bézier).
# Antes el trazo solo admitía un color plano: ColorCore convertía cualquier
# degradado en su primer color.
# =============================================================================

extends RefCounted

const LINEAR := 0
const RADIAL := 1

## Colores de `points` según el degradado. `angle` en radianes (lineal).
static func colors_for(points: PackedVector2Array, g: Gradient, type: int, angle: float) -> PackedColorArray:
	var out := PackedColorArray()
	if g == null or points.is_empty():
		return out
	var bb := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bb = bb.expand(p)
	var c := bb.get_center()
	out.resize(points.size())
	if type == RADIAL:
		var r := maxf(bb.size.length() * 0.5, 0.001)
		for i in points.size():
			out[i] = g.sample(clampf(points[i].distance_to(c) / r, 0.0, 1.0))
		return out
	var dir := Vector2.from_angle(angle)
	# Proyección de las esquinas de la caja: el degradado cubre todo el trazo.
	var lo := INF
	var hi := -INF
	for k in [bb.position, bb.end, Vector2(bb.position.x, bb.end.y), Vector2(bb.end.x, bb.position.y)]:
		var d: float = (k - c).dot(dir)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var span := maxf(hi - lo, 0.001)
	for i in points.size():
		out[i] = g.sample(clampf(((points[i] - c).dot(dir) - lo) / span, 0.0, 1.0))
	return out
