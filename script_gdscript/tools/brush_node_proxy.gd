# =============================================================================
# RUTA: res://script_gdscript/tools/brush_node_proxy.gd
# Editar los NODOS de un trazo de pincel (Line2D) con la herramienta de nodos.
# Un trazo de pincel son cientos de muestras; para editarlo se le ajusta una
# curva Bézier con pocos nodos (como Illustrator), que vive en un Path2D
# auxiliar fuera del documento (no se guarda). Cada cambio de la curva
# regenera los puntos del trazo; la presión (grosor variable) se conserva
# porque va repartida a lo largo de la longitud del trazo.
# Los nodos se recuerdan en la meta "brush_nodes" del trazo (para volver a
# editarlo sin reajustar).
# =============================================================================
extends RefCounted

const CurveFit = preload("res://script_gdscript/shapes/curve_fit.gd")
const PROXY_NAME := "_BrushNodeProxy"
const META_NODES := "brush_nodes"

## ¿Se pueden editar los nodos de este trazo? (no el texto en trazado ni
## los pinceles de figuras, que dependen de otra cosa)
static func is_editable(n: Object) -> bool:
	return n is Line2D and is_instance_valid(n) and not n.has_meta("brush_ref") \
		and String(n.get_meta("brush_style", "")) != "object" and (n as Line2D).points.size() >= 2

static func line_of(proxy: Object) -> Line2D:
	if proxy == null or not is_instance_valid(proxy) or not proxy.has_meta("proxy_for"):
		return null
	var l = proxy.get_meta("proxy_for")
	return l if l is Line2D and is_instance_valid(l) else null

static func curve_to_data(c: Curve2D) -> Array:
	var out: Array = []
	for i in c.point_count:
		out.append([c.get_point_position(i), c.get_point_in(i), c.get_point_out(i)])
	return out

static func curve_from_data(d: Array) -> Curve2D:
	var c := Curve2D.new()
	for e in d:
		if e is Array and e.size() >= 3:
			c.add_point(e[0], e[1], e[2])
	return c

static func _poly_len(pts: PackedVector2Array) -> float:
	var t := 0.0
	for i in range(1, pts.size()):
		t += pts[i].distance_to(pts[i - 1])
	return t

## Crea el Path2D auxiliar con la curva del trazo. `px` = unidades del lienzo
## por píxel de pantalla (precisión del ajuste: ~1,5 px).
static func make(line: Line2D, host: Node, px: float) -> Path2D:
	var curve: Curve2D = null
	if line.has_meta(META_NODES):
		curve = curve_from_data(line.get_meta(META_NODES))
	if curve == null or curve.point_count < 2:
		var err := maxf(px * 1.5, maxf(line.width * 0.05, 0.0001))
		curve = CurveFit.fit(line.points, err)
	if curve == null or curve.point_count < 2:
		curve = Curve2D.new()
		curve.add_point(line.points[0])
		curve.add_point(line.points[line.points.size() - 1])
	var p := Path2D.new()
	p.name = PROXY_NAME
	p.curve = curve
	p.set_meta("proxy_for", line)
	var n := line.points.size()
	p.set_meta("spacing", _poly_len(line.points) / maxf(float(n - 1), 1.0))
	host.add_child(p)
	p.global_transform = line.global_transform
	curve.changed.connect(apply.bind(p))
	return p

## La curva del auxiliar → puntos del trazo (espaciado parecido al original).
static func apply(proxy: Path2D) -> void:
	var line := line_of(proxy)
	if line == null or proxy.curve == null or proxy.curve.point_count < 2:
		return
	var c: Curve2D = proxy.curve
	var total := c.get_baked_length()
	var spacing := float(proxy.get_meta("spacing", 1.0))
	spacing = clampf(spacing, maxf(total / 4000.0, 0.0001), maxf(total / 8.0, 0.0001))
	var pts := c.tessellate_even_length(6, spacing)
	if pts.size() >= 2:
		line.points = pts
		line.set_meta(META_NODES, curve_to_data(c))

## Quita el auxiliar (al salir del modo nodos).
static func release(proxy: Object) -> void:
	if proxy and is_instance_valid(proxy) and proxy.has_meta("proxy_for"):
		var pa = (proxy as Node).get_parent()
		if pa:
			pa.remove_child(proxy)
		(proxy as Node).queue_free()
