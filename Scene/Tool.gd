# ==========================================
# RUTA: res://scripts/Tool.gd
# ==========================================
# @deprecated Use tools/ToolBase.gd (class_name ToolBase extends Node) instead.
# Tool was the original RefCounted-based base class for stateless tools.
# Kept for reference; DO NOT use in new code.
class_name Tool
extends RefCounted

var canvas: Node2D = null

func _init(p_canvas: Node2D) -> void:
	canvas = p_canvas

func activate() -> void:
	pass

func deactivate() -> void:
	pass

func handle_input(_event: InputEvent) -> bool:
	return false
