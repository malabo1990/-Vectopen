@tool
extends VectorShape
class_name VectorCircle

@export var size: Vector2 = Vector2(100, 100)

const CIRCLE_QUALITY: int = 128

func _init() -> void:
	_register_doc_extent("size")

func _draw() -> void:
	if fill_color.a > 0:
		var verts = _generate_vertices()
		draw_colored_polygon(verts, fill_color)

	if stroke_width > 0:
		var verts = _generate_vertices()
		verts.append(verts[0])
		draw_polyline(verts, stroke_color, stroke_width, true)

## Vértices centrados en el origen local (-size/2 .. +size/2), igual que
## VectorRectangle. "position" es el CENTRO de la figura en ambas clases —
## antes este método sumaba "half" a cada vértice, tratando position como
## esquina superior-izquierda, lo que desalineaba el círculo respecto al
## bounding box (que sí asume position = centro, ver MoveTool._global_rect()).
func _generate_vertices() -> PackedVector2Array:
	var verts := PackedVector2Array()
	var half := size / 2.0
	for i in range(CIRCLE_QUALITY):
		var angle := (i * 2.0 * PI) / CIRCLE_QUALITY
		verts.append(Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return verts

func to_svg() -> String:
	var extent: DVec2 = get_doc_extent()
	var cx: float = doc_position.x
	var cy: float = doc_position.y
	var rx: float = extent.x / 2.0
	var ry: float = extent.y / 2.0
	return '<ellipse cx="%.4f" cy="%.4f" rx="%.4f" ry="%.4f" fill="%s" stroke="%s" stroke-width="%.4f" />' % [
		cx, cy, rx, ry,
		fill_color.to_html(), stroke_color.to_html(), stroke_width
	]

func get_state() -> Dictionary:
	var s := super()
	s["type"] = "circle"
	s["position"] = doc_position.to_v2()
	s["rotation"] = doc_rotation
	s["size"] = get_doc_extent().to_v2()
	return s

func serialize() -> Dictionary:
	return get_state()
