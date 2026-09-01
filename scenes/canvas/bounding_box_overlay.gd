# =============================================================================
# RUTA: res://scenes/canvas/bounding_box_overlay.gd
# Contenedor raíz pasivo en CanvasLayer
# =============================================================================
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func update_overlay(macro_rect: Rect2, rotation_rad: float, key_mode: int, axis_lock: int, transform_scale: float) -> void:
	# Dejamos que el panel interno PANEL_BOUNDINGBOX gestione su propia posición 
	# mediante transformaciones de cámara nativas para evitar parpadeos duplicados.
	pass
