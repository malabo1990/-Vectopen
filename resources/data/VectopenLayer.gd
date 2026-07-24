@tool
class_name VectopenLayer
extends Resource

@export var id: String = ""
@export var layer_name: String = "Layer"
@export var artboard_id: String = ""
@export var is_visible: bool = true
@export var is_locked: bool = false
@export var opacity: float = 1.0
@export var blend_mode: int = 0

var shapes: Array[VectopenShape] = []
var shape_ids: Array[String] = []

func get_shape(id: String) -> VectopenShape:
	for s in shapes:
		if s.id == id:
			return s
	return null

func add_shape(s: VectopenShape):
	shapes.append(s)
	shape_ids.append(s.id)

func remove_shape(id: String):
	for i in range(shapes.size()):
		if shapes[i].id == id:
			shapes.remove_at(i)
			shape_ids.erase(id)
			return
