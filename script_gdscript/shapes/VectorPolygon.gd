@tool
extends VectorShape
class_name VectorPolygon

@export var vertices: PackedVector2Array = []
@export var closed: bool = true

func _init() -> void:
	_register_doc_vertices("vertices")

func get_effect_points() -> PackedVector2Array:
	return vertices

func _draw() -> void:
	if vertices.is_empty():
		return
	draw_effects_shadows(vertices)
	draw_fill(vertices)
	if stroke_width > 0:
		draw_stroke_ring(vertices)
	draw_effects_overlays(vertices)

func set_vertices_from_center(center: Vector2, points: PackedVector2Array) -> void:
	set_doc_position(DVec2.from_v2(center))
	set_doc_vertices(DVec2.array_from_v2(points))

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "polygon"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["vertices"] = vertices
	s["closed"] = closed
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
