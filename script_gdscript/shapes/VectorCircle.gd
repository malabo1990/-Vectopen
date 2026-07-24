@tool
extends VectorShape
class_name VectorCircle

@export var size: Vector2 = Vector2(100, 100)

const CIRCLE_QUALITY: int = 128

func _draw() -> void:
	if fill_color.a > 0:
		var verts = _generate_vertices()
		draw_colored_polygon(verts, fill_color)

	if stroke_width > 0:
		var verts = _generate_vertices()
		verts.append(verts[0])
		draw_polyline(verts, stroke_color, stroke_width, true)

func _generate_vertices() -> PackedVector2Array:
	var verts := PackedVector2Array()
	var half := size / 2.0
	for i in range(CIRCLE_QUALITY):
		var angle := (i * 2.0 * PI) / CIRCLE_QUALITY
		verts.append(half + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return verts

func to_svg() -> String:
	var center := position + size / 2.0
	var rx := size.x / 2.0
	var ry := size.y / 2.0
	return '<ellipse cx="%f" cy="%f" rx="%f" ry="%f" fill="%s" stroke="%s" stroke-width="%f" />' % [
		center.x, center.y, rx, ry,
		fill_color.to_html(), stroke_color.to_html(), stroke_width
	]

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "circle"
	s["size"] = size
	return s

func serialize() -> Dictionary:
	return get_state()
