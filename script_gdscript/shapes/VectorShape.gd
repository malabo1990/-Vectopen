@tool
extends Node2D
class_name VectorShape

@export var object_id: String = ""
@export var fill_color: Color = Color.WHITE
@export var stroke_color: Color = Color.BLACK
@export var stroke_width: float = 2.0

var is_selected: bool = false
var effects: Array = []

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selected:
		modulate = Color(1.2, 1.2, 1.2, 1.0)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	queue_redraw()

func get_state() -> Dictionary:
	return {
		"id": object_id,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"fill_color": fill_color,
		"stroke_color": stroke_color,
		"stroke_width": stroke_width,
	}

func serialize() -> Dictionary:
	return get_state()

func to_svg() -> String:
	return ""

func _draw() -> void:
	pass
