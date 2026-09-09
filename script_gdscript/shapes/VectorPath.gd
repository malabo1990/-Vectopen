# =============================================================================
# RUTA: res://script_gdscript/shapes/VectorPath.gd
# Trazo Bézier editable (Path2D).
#
# El estilo se expone con los MISMOS nombres que VectorShape
# (fill_color / stroke_color / stroke_width) para que InspectorCore y el panel
# de trazos lo traten igual que a un rectángulo o un polígono, sin ramas
# especiales. `closed` mantiene sincronizada la meta "is_closed" que ya usan
# el serializador y MoveTool.
# =============================================================================
@tool
extends Path2D
class_name VectorPath

@export var fill_color: Color = Color(0.09, 0.37, 0.65, 0.06):
	set(v):
		fill_color = v
		queue_redraw()

@export var stroke_color: Color = Color(0.22, 0.22, 0.22, 1.0):
	set(v):
		stroke_color = v
		queue_redraw()

@export var stroke_width: float = 2.0:
	set(v):
		stroke_width = maxf(0.0, v)
		queue_redraw()

@export var closed: bool = false:
	set(v):
		closed = v
		set_meta("is_closed", v)
		queue_redraw()

var effects: Array = []

## 0: Butt (Plano), 1: Round (Redondo), 2: Square (Cuadrado)
@export var stroke_cap_start: int = 0:
	set(v):
		stroke_cap_start = v
		queue_redraw()

@export var stroke_cap_end: int = 0:
	set(v):
		stroke_cap_end = v
		queue_redraw()

## 0: Solid, 1: Dashed, 2: Dotted, 3: Tapered, 4: Double
@export var stroke_style: int = 0:
	set(v):
		stroke_style = v
		queue_redraw()

## 0: None, 1: Arrow, 2: Triangle, 3: Circle, 4: Square
@export var stroke_pointer_start: int = 0:
	set(v):
		stroke_pointer_start = v
		queue_redraw()

@export var stroke_pointer_end: int = 0:
	set(v):
		stroke_pointer_end = v
		queue_redraw()

@export var stroke_dash_len: float = 12.0:
	set(v):
		stroke_dash_len = maxf(1.0, v)
		queue_redraw()

@export var stroke_dash_gap: float = 8.0:
	set(v):
		stroke_dash_gap = maxf(1.0, v)
		queue_redraw()

func _ready() -> void:
	# Compat: los trazos cargados de disco traen el estado como meta.
	if has_meta("is_closed"):
		closed = bool(get_meta("is_closed"))
	if has_meta("stroke_cap_start"):
		stroke_cap_start = int(get_meta("stroke_cap_start"))
	if has_meta("stroke_cap_end"):
		stroke_cap_end = int(get_meta("stroke_cap_end"))
	if has_meta("stroke_style"):
		stroke_style = int(get_meta("stroke_style"))
	if has_meta("stroke_pointer_start"):
		stroke_pointer_start = int(get_meta("stroke_pointer_start"))
	if has_meta("stroke_pointer_end"):
		stroke_pointer_end = int(get_meta("stroke_pointer_end"))
	if has_meta("stroke_dash_len"):
		stroke_dash_len = float(get_meta("stroke_dash_len"))
	if has_meta("stroke_dash_gap"):
		stroke_dash_gap = float(get_meta("stroke_dash_gap"))
	if curve and not curve.changed.is_connected(_solicitar_redibuja):
		curve.changed.connect(_solicitar_redibuja)
	queue_redraw()

func _solicitar_redibuja() -> void:
	queue_redraw()

func _draw() -> void:
	if not curve or curve.point_count < 2:
		return
	var baked: PackedVector2Array = curve.get_baked_points()
	if baked.size() < 2:
		return

	if closed:
		draw_effects_shadows(baked)
		if fill_color.a > 0.0 and baked.size() >= 3 \
				and not Geometry2D.triangulate_polygon(baked).is_empty():
			draw_colored_polygon(baked, fill_color)
		if stroke_width > 0.0:
			var ring := PackedVector2Array(baked)
			ring.append(baked[0])
			_draw_stroke_polyline(ring, true)
		draw_effects_overlays(baked)
	elif stroke_width > 0.0:
		_draw_stroke_polyline(baked, false)
		_draw_caps(baked)
		_draw_pointers(baked)

## Calcula el ancho de trazo y color con atenuación subpíxel para evitar que líneas < 1px se vean punteadas o desaparezcan.
func _get_rendered_stroke_params(w: float = -1.0, col: Color = Color(-1, -1, -1, -1)) -> Array:
	var req_w: float = stroke_width if w < 0.0 else w
	var req_col: Color = stroke_color if col.r < 0.0 else col
	if req_w < 1.0 and req_w > 0.0:
		var c := req_col
		c.a *= req_w
		return [1.0, c]
	return [req_w, req_col]

func _draw_stroke_polyline(points: PackedVector2Array, _is_closed_path: bool) -> void:
	if points.size() < 2:
		return
	var sp := _get_rendered_stroke_params()
	var rend_w: float = sp[0]
	var rend_col: Color = sp[1]
	match stroke_style:
		0: # Solid
			draw_polyline(points, rend_col, rend_w, false)
		1: # Dashed
			_draw_dashed(points, rend_w, rend_col)
		2: # Dotted
			_draw_dotted(points, rend_col)
		3: # Tapered
			_draw_tapered(points, rend_col)
		4: # Double
			_draw_double(points, rend_col)
		_:
			draw_polyline(points, rend_col, rend_w, false)

func _draw_dashed(points: PackedVector2Array, rend_w: float = -1.0, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_w: float = stroke_width if rend_w < 0.0 else rend_w
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var dash: float = maxf(stroke_dash_len, 2.0)
	var gap: float = maxf(stroke_dash_gap, 2.0)
	var drawing: bool = true
	var rem: float = dash
	var cur_dash_pts: PackedVector2Array = []

	for i in range(points.size() - 1):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var seg_len: float = p1.distance_to(p2)
		if seg_len <= 0.0001:
			continue
		var dir: Vector2 = (p2 - p1) / seg_len
		var curr_d: float = 0.0

		while curr_d < seg_len:
			var step: float = minf(rem, seg_len - curr_d)
			var next_p: Vector2 = p1 + dir * (curr_d + step)
			if drawing:
				if cur_dash_pts.is_empty():
					cur_dash_pts.append(p1 + dir * curr_d)
				cur_dash_pts.append(next_p)
			curr_d += step
			rem -= step
			if rem <= 0.0001:
				if drawing:
					if cur_dash_pts.size() >= 2:
						draw_polyline(cur_dash_pts, use_col, use_w, false)
					cur_dash_pts.clear()
					drawing = false
					rem = gap
				else:
					drawing = true
					rem = dash

	if drawing and cur_dash_pts.size() >= 2:
		draw_polyline(cur_dash_pts, use_col, use_w, false)

func _draw_dotted(points: PackedVector2Array, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var dot_radius: float = maxf(1.0, stroke_width * 0.5)
	var spacing: float = maxf(stroke_dash_gap + stroke_width, stroke_width * 2.5)
	var dist_accum: float = 0.0
	draw_circle(points[0], dot_radius, use_col)

	for i in range(points.size() - 1):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var seg_len: float = p1.distance_to(p2)
		if seg_len <= 0.0001:
			continue
		var dir: Vector2 = (p2 - p1) / seg_len
		var d: float = 0.0
		while d < seg_len:
			var needed: float = spacing - dist_accum
			if d + needed <= seg_len:
				d += needed
				draw_circle(p1 + dir * d, dot_radius, use_col)
				dist_accum = 0.0
			else:
				dist_accum += (seg_len - d)
				break

func _draw_double(points: PackedVector2Array, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var sub_w: float = maxf(1.0, stroke_width * 0.35)
	var off: float = stroke_width * 0.45
	var l1: PackedVector2Array = []
	var l2: PackedVector2Array = []
	for i in range(points.size()):
		var tangent: Vector2
		if i == 0:
			tangent = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			tangent = (points[i] - points[i - 1]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()
		var n: Vector2 = Vector2(-tangent.y, tangent.x)
		l1.append(points[i] + n * off)
		l2.append(points[i] - n * off)
	draw_polyline(l1, use_col, sub_w, false)
	draw_polyline(l2, use_col, sub_w, false)

func _draw_tapered(points: PackedVector2Array, rend_col: Color = Color(-1, -1, -1, -1)) -> void:
	var use_col: Color = stroke_color if rend_col.r < 0.0 else rend_col
	var n_pts: int = points.size()
	for i in range(n_pts - 1):
		var t_mid: float = (float(i) + 0.5) / float(maxi(1, n_pts - 1))
		var factor: float = sin(t_mid * PI)
		var seg_w: float = stroke_width * (0.2 + 0.8 * factor)
		var seg_sp := _get_rendered_stroke_params(seg_w, use_col)
		draw_line(points[i], points[i + 1], seg_sp[1], seg_sp[0], false)

func _draw_caps(points: PackedVector2Array) -> void:
	if closed or points.size() < 2:
		return
	var half_w: float = stroke_width * 0.5

	# Inicio
	if stroke_cap_start == 1: # Round
		draw_circle(points[0], half_w, stroke_color)
	elif stroke_cap_start == 2: # Square
		var t: Vector2 = (points[1] - points[0]).normalized()
		var n: Vector2 = Vector2(-t.y, t.x)
		var c1: Vector2 = points[0] - t * half_w + n * half_w
		var c2: Vector2 = points[0] - t * half_w - n * half_w
		var c3: Vector2 = points[0] - n * half_w
		var c4: Vector2 = points[0] + n * half_w
		draw_colored_polygon(PackedVector2Array([c1, c2, c3, c4]), stroke_color)

	# Fin
	var last_idx: int = points.size() - 1
	if stroke_cap_end == 1: # Round
		draw_circle(points[last_idx], half_w, stroke_color)
	elif stroke_cap_end == 2: # Square
		var t: Vector2 = (points[last_idx] - points[last_idx - 1]).normalized()
		var n: Vector2 = Vector2(-t.y, t.x)
		var c1: Vector2 = points[last_idx] + n * half_w
		var c2: Vector2 = points[last_idx] - n * half_w
		var c3: Vector2 = points[last_idx] + t * half_w - n * half_w
		var c4: Vector2 = points[last_idx] + t * half_w + n * half_w
		draw_colored_polygon(PackedVector2Array([c1, c2, c3, c4]), stroke_color)

func _draw_pointers(points: PackedVector2Array) -> void:
	if closed or points.size() < 2:
		return
	if stroke_pointer_start > 0:
		var dir_start: Vector2 = (points[0] - points[1]).normalized()
		_draw_pointer_shape(points[0], dir_start, stroke_pointer_start)
	if stroke_pointer_end > 0:
		var last_idx: int = points.size() - 1
		var dir_end: Vector2 = (points[last_idx] - points[last_idx - 1]).normalized()
		_draw_pointer_shape(points[last_idx], dir_end, stroke_pointer_end)

func _draw_pointer_shape(pos: Vector2, tangent: Vector2, pointer_type: int) -> void:
	var n: Vector2 = Vector2(-tangent.y, tangent.x)
	var sz: float = maxf(stroke_width * 3.5, 12.0)

	match pointer_type:
		1: # Arrow (V-shape)
			var l1: Vector2 = pos - tangent * sz + n * (sz * 0.5)
			var l2: Vector2 = pos - tangent * sz - n * (sz * 0.5)
			var pw: float = maxf(1.5, stroke_width)
			draw_line(pos, l1, stroke_color, pw, false)
			draw_line(pos, l2, stroke_color, pw, false)
		2: # Triangle (filled)
			var t1: Vector2 = pos
			var t2: Vector2 = pos - tangent * sz + n * (sz * 0.5)
			var t3: Vector2 = pos - tangent * sz - n * (sz * 0.5)
			draw_colored_polygon(PackedVector2Array([t1, t2, t3]), stroke_color)
		3: # Circle
			draw_circle(pos, sz * 0.4, stroke_color)
		4: # Square
			var half_sz: float = sz * 0.35
			var center: Vector2 = pos - tangent * half_sz
			var c1: Vector2 = center + tangent * half_sz + n * half_sz
			var c2: Vector2 = center - tangent * half_sz + n * half_sz
			var c3: Vector2 = center - tangent * half_sz - n * half_sz
			var c4: Vector2 = center + tangent * half_sz - n * half_sz
			draw_colored_polygon(PackedVector2Array([c1, c2, c3, c4]), stroke_color)

func is_path_closed() -> bool:
	return closed

## Exporta este path como elemento <path> SVG a partir de los puntos horneados
## (misma fuente que _draw()).
func to_svg() -> String:
	if not curve or curve.point_count < 2:
		return ""
	var baked_pts: PackedVector2Array = curve.get_baked_points()
	if baked_pts.size() < 2:
		return ""

	var d := "M %f,%f " % [position.x + baked_pts[0].x, position.y + baked_pts[0].y]
	for i in range(1, baked_pts.size()):
		d += "L %f,%f " % [position.x + baked_pts[i].x, position.y + baked_pts[i].y]
	if closed:
		d += "Z"

	var fill: String = fill_color.to_html() if (closed and fill_color.a > 0.0) else "none"
	var cap_str: String = "butt"
	if stroke_cap_end == 1: cap_str = "round"
	elif stroke_cap_end == 2: cap_str = "square"

	var dash_str: String = "none"
	if stroke_style == 1:
		dash_str = "%f,%f" % [stroke_dash_len, stroke_dash_gap]
	elif stroke_style == 2:
		dash_str = "2,%f" % [maxf(4.0, stroke_dash_gap)]

	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%f" stroke-linecap="%s" stroke-dasharray="%s" />' % [
		d, fill, stroke_color.to_html(), stroke_width, cap_str, dash_str
	]

func draw_effects_shadows(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		return
	for fx in effects:
		if not (fx is Dictionary) or not bool(fx.get("enabled", true)):
			continue
		var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
		if type == "drop_shadow":
			_render_drop_shadow(points, fx)

func draw_effects_overlays(points: PackedVector2Array) -> void:
	if effects.is_empty() or points.size() < 3:
		return
	for fx in effects:
		if not (fx is Dictionary) or not bool(fx.get("enabled", true)):
			continue
		var type: String = String(fx.get("type", "")).to_lower().replace(" ", "_")
		match type:
			"inner_shadow":
				_render_inner_shadow(points, fx)
			"outline":
				_render_outline_effect(points, fx)
			"color_overlay":
				_render_color_overlay(points, fx)

func _parse_fx_color(val: Variant, default_col: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		return Color.from_string(val, default_col)
	if val is Array and val.size() >= 3:
		var a: float = float(val[3]) if val.size() >= 4 else 1.0
		return Color(float(val[0]), float(val[1]), float(val[2]), a)
	return default_col

func _render_drop_shadow(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 4.0)), float(fx.get("offset_y", 4.0)))
	var blur := maxf(0.0, float(fx.get("blur", 6.0)))
	var spread := float(fx.get("spread", 0.0))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.4))
	if base_col.a <= 0.001:
		return

	if blur <= 0.5:
		var shifted := PackedVector2Array()
		for p in points:
			shifted.append(p + offset)
		if spread != 0.0:
			var polys := Geometry2D.offset_polygon(shifted, spread, Geometry2D.JOIN_ROUND)
			for poly in polys:
				if poly.size() >= 3:
					draw_colored_polygon(poly, base_col)
		else:
			draw_colored_polygon(shifted, base_col)
		return

	var passes: int = clampi(int(blur * 0.75), 4, 8)
	var max_expand: float = blur * 1.25 + spread
	var min_expand: float = spread - blur * 0.25

	for i in range(passes):
		var t: float = float(i) / float(passes - 1)
		var exp_dist: float = lerpf(min_expand, max_expand, t)
		var factor: float = exp(-2.2 * t * t)
		var pass_alpha: float = (base_col.a / float(passes)) * factor * 1.6
		pass_alpha = clampf(pass_alpha, 0.005, 1.0)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, pass_alpha)

		var offset_pts := Geometry2D.offset_polygon(points, exp_dist, Geometry2D.JOIN_ROUND)
		if offset_pts.is_empty():
			continue
		for poly in offset_pts:
			if poly.size() >= 3:
				var translated := PackedVector2Array()
				for pt in poly:
					translated.append(pt + offset)
				draw_colored_polygon(translated, pass_col)

func _render_inner_shadow(points: PackedVector2Array, fx: Dictionary) -> void:
	var offset := Vector2(float(fx.get("offset_x", 2.0)), float(fx.get("offset_y", 2.0)))
	var blur := maxf(0.5, float(fx.get("blur", 4.0)))
	var base_col := _parse_fx_color(fx.get("color", null), Color(0.0, 0.0, 0.0, 0.5))
	if base_col.a <= 0.001:
		return

	var passes: int = clampi(int(blur * 0.75), 3, 6)
	for i in range(passes):
		var t: float = float(i) / float(passes)
		var inward: float = lerpf(0.5, blur + 2.0, t)
		var alpha: float = (base_col.a / float(passes)) * (1.0 - t * 0.5)
		var pass_col := Color(base_col.r, base_col.g, base_col.b, alpha)

		var inners := Geometry2D.offset_polygon(points, -inward, Geometry2D.JOIN_ROUND)
		if inners.is_empty():
			continue
		for inner_poly in inners:
			var clipped := Geometry2D.clip_polygons(points, inner_poly)
			for ring in clipped:
				if ring.size() >= 3:
					var shifted := PackedVector2Array()
					for pt in ring:
						shifted.append(pt + offset * (1.0 - t))
					draw_colored_polygon(shifted, pass_col)

func _render_outline_effect(points: PackedVector2Array, fx: Dictionary) -> void:
	var width := maxf(0.5, float(fx.get("width", 2.0)))
	var col := _parse_fx_color(fx.get("color", null), Color.BLACK)
	if col.a <= 0.001:
		return
	var ring := PackedVector2Array(points)
	if not ring[0].is_equal_approx(ring[-1]):
		ring.append(ring[0])
	draw_polyline(ring, col, width, false)

func _render_color_overlay(points: PackedVector2Array, fx: Dictionary) -> void:
	var col := _parse_fx_color(fx.get("color", null), Color(1.0, 0.0, 0.0, 1.0))
	var opacity := clampf(float(fx.get("opacity", 1.0)), 0.0, 1.0)
	var final_col := Color(col.r, col.g, col.b, col.a * opacity)
	if final_col.a <= 0.001:
		return
	draw_colored_polygon(points, final_col)
