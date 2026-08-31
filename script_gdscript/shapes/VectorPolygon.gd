@tool
extends VectorShape
class_name VectorPolygon

@export var vertices: PackedVector2Array = []
@export var closed: bool = true

func _init() -> void:
	_register_doc_vertices("vertices")

func _draw() -> void:
	if vertices.is_empty():
		return
	if fill_color.a > 0:
		draw_colored_polygon(vertices, fill_color)
	if stroke_width > 0:
		var stroke_verts := PackedVector2Array(vertices)
		if closed:
			stroke_verts.append(vertices[0])
		# sin antialias por-primitiva (rompe el batching); el MSAA 2D lo cubre
		draw_polyline(stroke_verts, stroke_color, stroke_width, false)

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
	return "<polygon points=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%.4f\" />" % [
		",".join(pts), fill_color.to_html(), stroke_color.to_html(), stroke_width
	]
