@tool
extends VectorShape
class_name VectorCircle

@export var size: Vector2 = Vector2(100, 100):
	set(v):
		size = v
		_verts_cache.clear()
		queue_redraw()

## Modos geométricos paramétricos (Sección 16 de especificación):
## "whole" (círculo completo), "arc" (arco abierto), "pie" (sector),
## "chord" (segmento/cuerda), "donut" (anillo)
@export var shape_mode: String = "whole":
	set(v):
		shape_mode = v
		_verts_cache.clear()
		queue_redraw()

@export var start_angle_deg: float = 0.0:
	set(v):
		start_angle_deg = v
		_verts_cache.clear()
		queue_redraw()

@export var end_angle_deg: float = 360.0:
	set(v):
		end_angle_deg = v
		_verts_cache.clear()
		queue_redraw()

@export var inner_radius_ratio: float = 0.5:
	set(v):
		inner_radius_ratio = clampf(v, 0.01, 0.95)
		_verts_cache.clear()
		queue_redraw()

const CIRCLE_QUALITY: int = 128

var _verts_cache: PackedVector2Array = PackedVector2Array()
var _verts_cache_size: Vector2 = Vector2(-1, -1)

func _init() -> void:
	_register_doc_extent("size")

func get_shape_type_code() -> int:
	return 1

func get_shape_size() -> Vector2:
	return size

func get_effect_points() -> PackedVector2Array:
	return _cached_vertices()

func _draw() -> void:
	if fill_color.a <= 0 and stroke_width <= 0 and not has_gradient_fill() and effects.is_empty():
		return
	var verts: PackedVector2Array = _cached_vertices()
	if verts.is_empty():
		return
	draw_effects_shadows(verts)

	if maybe_render_blur(verts):
		draw_effects_overlays(verts)
		return

	if shape_mode == "arc":
		if stroke_width > 0 and verts.size() >= 2:
			var sp: Array = _get_rendered_stroke_params(stroke_width, stroke_color)
			draw_polyline(verts, sp[1], sp[0], true)
	else:
		draw_fill(verts)
		if stroke_width > 0:
			var ring_verts: PackedVector2Array = verts
			if stroke_align == 1: # Inside
				var s_size: Vector2 = Vector2(maxf(0.0, size.x - stroke_width), maxf(0.0, size.y - stroke_width))
				ring_verts = _generate_vertices_for_size(s_size)
			elif stroke_align == 2: # Outside
				var s_size: Vector2 = size + Vector2(stroke_width, stroke_width)
				ring_verts = _generate_vertices_for_size(s_size)
			draw_stroke_ring(ring_verts)

	draw_effects_overlays(verts)

func _cached_vertices() -> PackedVector2Array:
	if _verts_cache.is_empty() or _verts_cache_size != size:
		_verts_cache = _generate_vertices()
		_verts_cache_size = size
	return _verts_cache

func _generate_vertices() -> PackedVector2Array:
	return _generate_vertices_for_size(size)

func _generate_vertices_for_size(target_size: Vector2) -> PackedVector2Array:
	var verts: PackedVector2Array = PackedVector2Array()
	var half: Vector2 = target_size / 2.0
	if half.x <= 0.0 or half.y <= 0.0:
		return verts

	if shape_mode == "whole":
		for i in range(CIRCLE_QUALITY):
			var angle: float = (i * 2.0 * PI) / CIRCLE_QUALITY
			verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
		return verts

	var s_rad: float = deg_to_rad(start_angle_deg)
	var e_rad: float = deg_to_rad(end_angle_deg)
	var span: float = fposmod(e_rad - s_rad, TAU)
	if is_zero_approx(span) and not is_equal_approx(start_angle_deg, end_angle_deg):
		span = TAU
	elif is_zero_approx(span):
		span = TAU

	var steps: int = maxi(8, int(round((span / TAU) * CIRCLE_QUALITY)))

	match shape_mode:
		"arc":
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"pie":
			verts.append(Vector2.ZERO)
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"chord":
			for i in range(steps + 1):
				var t: float = float(i) / float(steps)
				var a: float = s_rad + span * t
				verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
		"donut":
			var inner: Vector2 = half * clampf(inner_radius_ratio, 0.01, 0.95)
			if is_equal_approx(span, TAU):
				for i in range(CIRCLE_QUALITY):
					var a: float = (i * 2.0 * PI) / CIRCLE_QUALITY
					verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
				verts.append(Vector2(cos(0.0) * half.x, sin(0.0) * half.y))
				verts.append(Vector2(cos(0.0) * inner.x, sin(0.0) * inner.y))
				for i in range(CIRCLE_QUALITY, -1, -1):
					var a: float = (i * 2.0 * PI) / CIRCLE_QUALITY
					verts.append(Vector2(cos(a) * inner.x, sin(a) * inner.y))
			else:
				for i in range(steps + 1):
					var t: float = float(i) / float(steps)
					var a: float = s_rad + span * t
					verts.append(Vector2(cos(a) * half.x, sin(a) * half.y))
				for i in range(steps, -1, -1):
					var t: float = float(i) / float(steps)
					var a: float = s_rad + span * t
					verts.append(Vector2(cos(a) * inner.x, sin(a) * inner.y))
		_:
			for i in range(CIRCLE_QUALITY):
				var angle: float = (i * 2.0 * PI) / CIRCLE_QUALITY
				verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))

	return verts

func to_svg() -> String:
	var extent: DVec2 = get_doc_extent()
	var cx: float = doc_position.x
	var cy: float = doc_position.y
	var rx: float = extent.x / 2.0
	var ry: float = extent.y / 2.0
	var filter_attr: String = get_svg_filter_attr()
	if shape_mode == "whole":
		return '<ellipse cx="%.4f" cy="%.4f" rx="%.4f" ry="%.4f" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
			cx, cy, rx, ry,
			fill_color.to_html(), stroke_color.to_html(), stroke_width,
			filter_attr
		]
	var verts: PackedVector2Array = _cached_vertices()
	if verts.is_empty():
		return ""
	var d_parts: PackedStringArray = PackedStringArray()
	for i in range(verts.size()):
		var p: Vector2 = verts[i] + Vector2(cx, cy)
		if i == 0:
			d_parts.append("M %.4f %.4f" % [p.x, p.y])
		else:
			d_parts.append("L %.4f %.4f" % [p.x, p.y])
	if shape_mode != "arc":
		d_parts.append("Z")
	var fill_str: String = "none" if shape_mode == "arc" else fill_color.to_html()
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
		" ".join(d_parts), fill_str, stroke_color.to_html(), stroke_width, filter_attr
	]

func get_state() -> Dictionary:
	var s: Dictionary = super()
	s["type"] = "circle"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["size"] = get_doc_extent().to_v2()
	s["shape_mode"] = shape_mode
	s["start_angle_deg"] = start_angle_deg
	s["end_angle_deg"] = end_angle_deg
	s["inner_radius_ratio"] = inner_radius_ratio
	return s

func serialize() -> Dictionary:
	return get_state()
