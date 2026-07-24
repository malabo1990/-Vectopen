@tool
class_name VectopenShape
extends Resource

@export var id: String = ""
@export var shape_type: String = "rectangle"
@export var shape_name: String = "Shape"
@export var position: Vector2 = Vector2.ZERO
@export var rotation: float = 0.0
@export var scale: Vector2 = Vector2.ONE
@export var stroke_color: Color = Color.BLACK
@export var stroke_width: float = 1.0
@export var fill_color: Color = Color.WHITE
@export var is_filled: bool = true
@export var size: Vector2 = Vector2(100, 100)
@export var text_content: String = ""

var points: PackedVector2Array = []

func get_rect() -> Rect2:
	if points.is_empty():
		return Rect2(position, size)
	var r = Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r
