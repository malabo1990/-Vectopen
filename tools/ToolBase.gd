class_name ToolBase
extends Node

@export var shape_manager: Node
@export var artboard: Node

var canvas: Node2D = null
var box_start_global: Vector2 = Vector2.ZERO
var box_current_global: Vector2 = Vector2.ZERO
var is_drawing: bool = false

const STROKE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const STROKE_WIDTH: float = 1.0
const FILL_COLOR: Color = Color(0.88, 0.88, 0.88, 1.0)
const COLOR_PREVIEW_F: Color = Color(0.05, 0.55, 0.91, 0.05)
const COLOR_PREVIEW_S: Color = Color(0.05, 0.55, 0.91, 0.85)

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_refresh_dependencies()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	is_drawing = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func handle_input(_event: InputEvent) -> bool:
	return false

func draw_preview(_c: Node2D) -> void:
	pass

func get_class_name() -> String:
	return ""

func _refresh_dependencies() -> void:
	if not is_instance_valid(canvas):
		var parent_node = get_parent()
		if parent_node is Node2D:
			canvas = parent_node
		elif get_tree():
			canvas = get_tree().get_first_node_in_group("_vectopen_canvas")

	if is_instance_valid(canvas):
		if not is_instance_valid(artboard):
			var container = canvas.get_node_or_null("ArtboardsContainer")
			if container and container.get_child_count() > 0:
				artboard = container.get_child(0)

		if not is_instance_valid(shape_manager):
			shape_manager = canvas.get_node_or_null("ShapeManager")
