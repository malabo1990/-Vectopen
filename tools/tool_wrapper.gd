extends Node
class_name ToolWrapper

@export var tool_script: Script
var tool_instance = null
var canvas_node: Node2D = null

func _ready():
	if not tool_script:
		push_warning("ToolWrapper: No tool_script assigned")
		return
	canvas_node = _find_canvas()
	if not canvas_node:
		push_warning("ToolWrapper: No Canvas found")
		return
	_create_tool()

func _find_canvas() -> Node2D:
	var n = get_parent()
	while n:
		if n.is_in_group("_vectopen_canvas"):
			return n
		n = n.get_parent()
	if get_tree():
		return get_tree().get_first_node_in_group("_vectopen_canvas")
	return null

func _create_tool():
	var base_type = tool_script.get_instance_base_type()
	if base_type == "RefCounted":
		tool_instance = tool_script.new(canvas_node)
	else:
		tool_instance = tool_script.new()
		add_child(tool_instance)
		if "canvas" in tool_instance and not tool_instance.canvas:
			tool_instance.canvas = canvas_node

func activate():
	if tool_instance and tool_instance.has_method("activate"):
		tool_instance.activate()

func deactivate():
	if tool_instance and tool_instance.has_method("deactivate"):
		tool_instance.deactivate()

func handle_input(event: InputEvent, _canvas_position: Vector2 = Vector2.ZERO) -> bool:
	if tool_instance and tool_instance.has_method("handle_input"):
		return tool_instance.handle_input(event)
	return false

func draw_preview(c: Node2D) -> void:
	if tool_instance and tool_instance.has_method("draw_preview"):
		tool_instance.draw_preview(c)

func get_class_name() -> String:
	if tool_instance and tool_instance.has_method("get_class_name"):
		return tool_instance.get_class_name()
	return "ToolWrapper"
