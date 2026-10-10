@tool
extends VectorShape
class_name VectorStar

@export var size: Vector2 = Vector2(100, 100):
	set(v):
		size = v
		_verts_cache.clear()
		queue_redraw()

@export var points_count: int = 5:
	set(v):
		points_count = maxi(3, v)
		_verts_cache.clear()
		queue_redraw()

@export var inner_radius_ratio: float = 0.382:
	set(v):
		inner_radius_ratio = clampf(v, 0.05, 0.95)
		_verts_cache.clear()
		queue_redraw()

@export var corner_radius: float = 0.0:
	set(v):
		corner_radius = maxf(0.0, v)
		_verts_cache.clear()
		queue_redraw()

var _verts_cache: PackedVector2Array = PackedVector2Array()
var _verts_cache_size: Vector2 = Vector2(-1, -1)

func _init() -> void:
	_register_doc_extent("size")

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
	var raw_points: PackedVector2Array = PackedVector2Array()
	var half: Vector2 = target_size / 2.0
	var total_pts: int = points_count * 2

	for i in range(total_pts):
		var angle: float = i * (TAU / float(total_pts)) - (PI / 2.0)
		var r_ratio: float = 1.0 if (i % 2 == 0) else inner_radius_ratio
		var pt: Vector2 = Vector2(cos(angle) * half.x * r_ratio, sin(angle) * half.y * r_ratio)
		raw_points.append(pt)

	if corner_radius <= 0.001 or raw_points.size() < 3:
		return raw_points

	# Redondeo suave de esquinas
	var rounded: PackedVector2Array = PackedVector2Array()
	var n: int = raw_points.size()
	for i in range(n):
		var p_prev: Vector2 = raw_points[(i - 1 + n) % n]
		var p_curr: Vector2 = raw_points[i]
		var p_next: Vector2 = raw_points[(i + 1) % n]

		var d_prev: float = p_curr.distance_to(p_prev)
		var d_next: float = p_curr.distance_to(p_next)
		var max_r: float = minf(d_prev, d_next) * 0.4
		var r: float = clampf(corner_radius, 0.0, max_r)

		if r > 0.1:
			var v_before: Vector2 = p_curr + (p_prev - p_curr).normalized() * r
			var v_after: Vector2 = p_curr + (p_next - p_curr).normalized() * r
			# Aproximación bezier cuadrática (5 puntos de curvatura)
			for step in range(5):
				var t: float = float(step) / 4.0
				var bz: Vector2 = (1.0 - t) * (1.0 - t) * v_before + 2.0 * (1.0 - t) * t * p_curr + t * t * v_after
				rounded.append(bz)
		else:
			rounded.append(p_curr)

	return rounded

func to_svg() -> String:
	var verts: PackedVector2Array = _cached_vertices()
	if verts.is_empty():
		return ""
	var cx: float = doc_position.x
	var cy: float = doc_position.y
	var pts: PackedStringArray = PackedStringArray()
	for v in verts:
		pts.append("%.4f,%.4f" % [v.x + cx, v.y + cy])
	var filter_attr: String = get_svg_filter_attr()
	return '<polygon points="%s" fill="%s" stroke="%s" stroke-width="%.4f"%s />' % [
		" ".join(pts), fill_color.to_html(), stroke_color.to_html(), stroke_width, filter_attr
	]

func get_state() -> Dictionary:
	var s: Dictionary = super()
	s["type"] = "star"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["size"] = get_doc_extent().to_v2()
	s["points_count"] = points_count
	s["inner_radius_ratio"] = inner_radius_ratio
	s["corner_radius"] = corner_radius
	return s

func serialize() -> Dictionary:
	return get_state()
