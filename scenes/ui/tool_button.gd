extends Button

@export var tool_name: String = ""
@export var create_at_center: bool = false

var canvas_editor: Node = null


func _ready() -> void:
	pressed.connect(_on_pressed)
	_find_canvas_editor()


func _find_canvas_editor() -> void:
	if is_instance_valid(canvas_editor):
		return
	if get_tree():
		canvas_editor = get_tree().get_first_node_in_group("_vectopen_canvas")
	if not canvas_editor:
		var parent = get_parent()
		while parent:
			if parent.has_method("switch_tool") or parent is CanvasEditor:
				canvas_editor = parent
				return
			parent = parent.get_parent()


func _on_pressed() -> void:
	if tool_name.is_empty():
		return
	if not is_instance_valid(canvas_editor):
		_find_canvas_editor()
	if not is_instance_valid(canvas_editor):
		return
	if canvas_editor.has_method("switch_tool"):
		canvas_editor.switch_tool(tool_name)
	if create_at_center:
		if canvas_editor.has_method("get_current_tool"):
			var tool_instance = canvas_editor.get_current_tool()
			if tool_instance and tool_instance.has_method("create_at_center"):
				tool_instance.create_at_center()
