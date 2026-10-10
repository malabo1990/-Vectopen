@tool
extends VectorShape
class_name VectorPolygon
const CornerRound = preload("res://script_gdscript/shapes/corner_round.gd")

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

## Polígono regular: giro de la forma (°) y proporción ancho/alto (1 =
## inscrito en un círculo). Con ellos el triángulo, el cuadrado o el rombo
## son el MISMO polígono regular (3 / 4 lados, giro 45°, proporción…).
@export var poly_angle: float = 0.0:
	set(v):
		poly_angle = v
		if is_regular:
			_recalculate_regular_polygon()

@export var poly_aspect: float = 1.0:
	set(v):
		poly_aspect = clampf(v, 0.05, 20.0)
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
	var off := deg_to_rad(poly_angle) - PI / 2.0
	for i in range(total_vertices):
		var angle: float = i * (TAU / float(total_vertices)) + off
		raw_points.append(Vector2(cos(angle) * radius * poly_aspect, sin(angle) * radius))

	if corner_radius > 0.05 and raw_points.size() >= 3:
		vertices = _round_polygon_corners(raw_points, corner_radius)
	else:
		vertices = raw_points

	set_doc_vertices(DVec2.array_from_v2(vertices))
	queue_redraw()

func _round_polygon_corners(raw_points: PackedVector2Array, c_radius: float) -> PackedVector2Array:
	return CornerRound.round(raw_points, PackedFloat32Array([c_radius]), 0.45)

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
