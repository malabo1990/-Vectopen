@tool
extends VectorShape
class_name VectorPolygon

@export var vertices: PackedVector2Array = []
@export var closed: bool = true

func _draw() -> void:
	if vertices.is_empty():
		return
	if fill_color.a > 0:
		draw_colored_polygon(vertices, fill_color)
	if stroke_width > 0:
		var stroke_verts := PackedVector2Array(vertices)
		if closed:
			stroke_verts.append(vertices[0])
		draw_polyline(stroke_verts, stroke_color, stroke_width, true)

func set_vertices_from_center(center: Vector2, points: PackedVector2Array) -> void:
	position = center
	vertices = points

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "polygon"
	s["vertices"] = vertices
	s["closed"] = closed
	return s

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	if vertices.is_empty():
		return ""
	var pts := PackedStringArray()
	for v in vertices:
		pts.append("%f,%f" % [v.x, v.y])
	return "<polygon points=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%f\" />" % [
		",".join(pts), fill_color.to_html(), stroke_color.to_html(), stroke_width
	]
