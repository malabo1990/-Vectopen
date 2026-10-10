# =============================================================================
# RUTA: res://script_gdscript/text/stroke_fx_geom.gd
# Geometría de un trazo de PINCEL (Line2D) para los efectos del panel
# "Efectos" (TextFx). Expone la misma interfaz que WorldTextLabel usa con
# TextFx (_get_triangle_polys / _get_stroke_polys …): así sombra, brillo,
# contorno, superposiciones, desenfoque y extrusión funcionan igual en un
# trazo que en un texto. Antes los efectos de un trazo se guardaban en su
# meta "effects" pero no se dibujaba nada.
#
# La silueta es la línea engordada (Geometry2D.offset_polyline) con sus
# uniones y extremos; se recalcula solo si cambian puntos, grosor o estilo.
# =============================================================================
extends RefCounted

const TextFx = preload("res://script_gdscript/text/text_fx.gd")

var line: Line2D = null
## TextFx escala los polígonos por font_size / _outline_fs: en un trazo, 1.
var _outline_fs := 1

var _key := ""
var _tris: Array = []      # [{poly, run}] polígonos simples (huecos unidos)
var _strokes: Array = []   # [{contours, run}] contornos reales (exterior + huecos)
var _bounds := Rect2()

func _init(l: Line2D) -> void:
	line = l

# ── interfaz que usa TextFx ──────────────────────────────────────────────────
func _get_triangle_polys() -> Array:
	_update()
	return _tris

func _get_stroke_polys() -> Array:
	_update()
	return _strokes

func _effective_runs() -> Array:
	return []

func get_theme_font_size(_n: StringName) -> int:
	return 1

## Los polígonos ya están en el espacio local del Line2D (= el de las capas).
func get_transform() -> Transform2D:
	return Transform2D.IDENTITY

func get_theme_color(_n: StringName) -> Color:
	if is_instance_valid(line):
		if line.gradient is Gradient and line.gradient.get_point_count() > 0:
			return line.gradient.get_color(0)
		return line.default_color
	return Color.BLACK

func bounds() -> Rect2:
	_update()
	return _bounds

# ── silueta ──────────────────────────────────────────────────────────────────
func _update() -> void:
	if not is_instance_valid(line):
		_tris = []
		_strokes = []
		return
	var w := _avg_width()
	var key := "%d|%s|%d|%d|%d|%s" % [hash(line.points), w, line.joint_mode, line.begin_cap_mode,
		line.end_cap_mode, line.closed]
	if key == _key:
		return
	_key = key
	# Arrays NUEVOS: TextFx detecta el cambio de geometría por identidad.
	_tris = []
	_strokes = []
	_bounds = Rect2()
	var pts := line.points
	if pts.size() < 2 or w <= 0.0:
		return
	var join := Geometry2D.JOIN_ROUND
	if line.joint_mode == Line2D.LINE_JOINT_SHARP:
		join = Geometry2D.JOIN_MITER
	elif line.joint_mode == Line2D.LINE_JOINT_BEVEL:
		join = Geometry2D.JOIN_SQUARE
	var end := Geometry2D.END_JOINED if line.closed else _end_type(line.begin_cap_mode)
	var polys: Array = Geometry2D.offset_polyline(pts, w * 0.5, join, end)
	if polys.is_empty():
		return

	# Exteriores y huecos por anidamiento (profundidad par = exterior).
	var outers: Array = []
	var holes: Array = []
	for i in polys.size():
		var p: PackedVector2Array = polys[i]
		var depth := 0
		for j in polys.size():
			if i != j and Geometry2D.is_point_in_polygon(p[0], polys[j]):
				depth += 1
		if depth % 2 == 0:
			outers.append(p)
		else:
			holes.append(p)
	_strokes.append({"contours": polys, "run": 0})

	for o in outers:
		var poly: PackedVector2Array = o
		for h in holes:
			if Geometry2D.is_point_in_polygon((h as PackedVector2Array)[0], o):
				poly = TextFx._bridge(poly, h)
		if not Geometry2D.triangulate_polygon(poly).is_empty():
			_tris.append({"poly": poly, "run": 0})
		else:
			for c in Geometry2D.decompose_polygon_in_convex(poly):
				_tris.append({"poly": c, "run": 0})

	var first := true
	for p in polys:
		for v in p:
			if first:
				_bounds = Rect2(v, Vector2.ZERO)
				first = false
			else:
				_bounds = _bounds.expand(v)

## Grosor medio (el pincel con presión usa width_curve).
func _avg_width() -> float:
	var w := line.width
	if line.width_curve:
		var acc := 0.0
		for i in 9:
			acc += line.width_curve.sample(i / 8.0)
		w *= acc / 9.0
	return w

static func _end_type(cap: int) -> int:
	match cap:
		Line2D.LINE_CAP_ROUND:
			return Geometry2D.END_ROUND
		Line2D.LINE_CAP_BOX:
			return Geometry2D.END_SQUARE
	return Geometry2D.END_BUTT
