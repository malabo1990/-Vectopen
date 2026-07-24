# @deprecated Use tools/ToolBase.gd (class_name ToolBase) instead.
# ToolNode was the original Node-based base class for tools.
# All tools now extend ToolBase. Kept for reference; DO NOT use in new code.
class_name ToolNode
extends Node

var canvas: Node2D
var artboard: Node2D

func activate() -> void:
	pass

func deactivate() -> void:
	pass

func handle_input(_event: InputEvent) -> bool:
	return false

func draw_preview(_c: Node2D) -> void:
	pass

func get_class_name() -> String:
	return ""

func find_canvas() -> Node2D:
	if is_instance_valid(canvas):
		return canvas
	var p = get_parent()
	while p:
		if p is Node2D and p.has_method("get_global_mouse_position"):
			canvas = p
			return canvas
		p = p.get_parent()
	return null

func find_artboard() -> Node2D:
	if is_instance_valid(artboard):
		return artboard
	var c = find_canvas()
	if not c:
		return null
	if c.has_method("get_node_or_null"):
		var container = c.get_node_or_null("ArtboardsContainer")
		if container and container.get_child_count() > 0:
			artboard = container.get_child(0)
			return artboard
	return null
