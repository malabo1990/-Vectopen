# =============================================================================
# RUTA: res://scenes/canvas/canvas_overlay_controller.gd
# Enrutador de estado de herramienta activa (ArtboardsContainer)
# =============================================================================
extends Node2D

# NOTA: El bounding box de selección lo gestiona exclusivamente MoveTool
# (ver _acquire_bounding_box/_update_bounding_box/_release_bounding_box en
# MoveTool.gd) usando una instancia de res://scenes/canvas/boundingbox.tscn
# obtenida de ObjectPool. Este controlador ya no mantiene una instancia
# propia en la escena para evitar el bounding box duplicado/desincronizado.

var current_tool: String = ""
var active_tool_instance: Object = null

func set_active_tool(tool_name: String, tool_instance: Object = null) -> void:
	current_tool = tool_name
	active_tool_instance = tool_instance
