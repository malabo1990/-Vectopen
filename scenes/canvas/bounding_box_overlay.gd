# =============================================================================
# RUTA: res://scenes/canvas/bounding_box_overlay.gd
# Contenedor raíz pasivo en CanvasLayer
# =============================================================================
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func update_overlay(_macro_rect: Rect2, _rotation_rad: float, _key_mode: int, _axis_lock: int, _transform_scale: float) -> void:
	# Dejamos que el panel interno PANEL_BOUNDINGBOX gestione su propia posición 
	# mediante transformaciones de cámara nativas para evitar parpadeos duplicados.
	pass
