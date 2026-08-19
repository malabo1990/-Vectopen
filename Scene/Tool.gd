# ==========================================
# RUTA: res://Scene/Tool.gd
# ==========================================
# @deprecated for NEW tools — use tools/ToolBase.gd (class_name ToolBase) instead.
# Restored 2026-08-19: this file was deleted in commit 12ae156 assuming all
# consumers had migrated to ToolBase, but 8 tools still `extends Tool` (MoveTool,
# PenTool, brushtool, TextTool, ArtboardTool, NodeSelectionTool, ParagraphTool,
# beziertool) — deleting it broke canvas.gd and the whole tool-loading chain.
# DO NOT delete again without first migrating those 8 tools to ToolBase.
# See docs/en/reports/VECTOPEN_TECHNICAL_REPORT.md §1 for the full incident.
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
