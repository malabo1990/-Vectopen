@tool
extends VectorShape
class_name VectorPolygon

@export var vertices: PackedVector2Array = []
@export var closed: bool = true

@export var is_regular: bool = false:
	set(v):
		is_regular = v
		if is_regular:
			_recalculate_regular_polygon()

@export var sides: int = 5:
	set(v):
		sides = maxi(3, v)
		if is_regular:
			_recalculate_regular_polygon()

@export var radius: float = 70.0:
	set(v):
		radius = maxf(1.0, v)
		if is_regular:
			_recalculate_regular_polygon()

@export var base_vertices: PackedVector2Array = PackedVector2Array()

@export var corner_radius: float = 0.0:
	set(v):
		corner_radius = maxf(0.0, v)
		if is_regular:
			_recalculate_regular_polygon()
		else:
			_recalculate_custom_polygon()

func _recalculate_custom_polygon() -> void:
	if base_vertices.is_empty() and not vertices.is_empty():
		base_vertices = vertices.duplicate()
	if base_vertices.size() >= 3 and corner_radius > 0.05:
		vertices = _round_polygon_corners(base_vertices, corner_radius)
	elif not base_vertices.is_empty():
		vertices = base_vertices.duplicate()
	set_doc_vertices(DVec2.array_from_v2(vertices))
	queue_redraw()

func _init() -> void:
	_register_doc_vertices("vertices")

func _recalculate_regular_polygon() -> void:
	var raw_points := PackedVector2Array()
	var total_vertices := maxi(3, sides)
	for i in range(total_vertices):
		var angle: float = i * (TAU / float(total_vertices)) - (PI / 2.0)
		raw_points.append(Vector2(cos(angle), sin(angle)) * radius)

	if corner_radius > 0.05 and raw_points.size() >= 3:
		vertices = _round_polygon_corners(raw_points, corner_radius)
	else:
		vertices = raw_points

	set_doc_vertices(DVec2.array_from_v2(vertices))
	queue_redraw()

func _round_polygon_corners(raw_points: PackedVector2Array, c_radius: float) -> PackedVector2Array:
	var rounded := PackedVector2Array()
	var n: int = raw_points.size()
	for i in range(n):
		var p_prev: Vector2 = raw_points[(i - 1 + n) % n]
		var p_curr: Vector2 = raw_points[i]
		var p_next: Vector2 = raw_points[(i + 1) % n]

		var d_prev: float = p_curr.distance_to(p_prev)
		var d_next: float = p_curr.distance_to(p_next)
		var max_r: float = minf(d_prev, d_next) * 0.45
		var r: float = clampf(c_radius, 0.0, max_r)

		if r > 0.1:
			var v_before: Vector2 = p_curr + (p_prev - p_curr).normalized() * r
			var v_after: Vector2 = p_curr + (p_next - p_curr).normalized() * r
			for step in range(5):
				var t: float = float(step) / 4.0
				var bz: Vector2 = (1.0 - t) * (1.0 - t) * v_before + 2.0 * (1.0 - t) * t * p_curr + t * t * v_after
				rounded.append(bz)
		else:
			rounded.append(p_curr)
	return rounded

func get_effect_points() -> PackedVector2Array:
	return vertices

func _draw() -> void:
	if vertices.is_empty():
		return
	draw_effects_shadows(vertices)
	if maybe_render_blur(vertices):
		draw_effects_overlays(vertices)
		return
	draw_fill(vertices)
	if stroke_width > 0:
		draw_stroke_ring(vertices)
	draw_effects_overlays(vertices)

func set_vertices_from_center(center: Vector2, points: PackedVector2Array) -> void:
	base_vertices = points.duplicate()
	set_doc_position(DVec2.from_v2(center))
	if corner_radius > 0.05 and points.size() >= 3:
		vertices = _round_polygon_corners(points, corner_radius)
	else:
		vertices = points
	set_doc_vertices(DVec2.array_from_v2(vertices))

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "polygon"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["vertices"] = vertices
	s["base_vertices"] = base_vertices
	s["closed"] = closed
	s["is_regular"] = is_regular
	s["sides"] = sides
	s["radius"] = radius
	s["corner_radius"] = corner_radius
	return s

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	var doc_verts: Array[DVec2] = get_doc_vertices()
	if doc_verts.is_empty():
		return ""
	var pts := PackedStringArray()
	for v in doc_verts:
		pts.append("%.4f,%.4f" % [v.x, v.y])
	var filter_attr: String = get_svg_filter_attr()
	return "<polygon points=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%.4f\"%s />" % [
		",".join(pts), fill_color.to_html(), stroke_color.to_html(), stroke_width, filter_attr
	]
