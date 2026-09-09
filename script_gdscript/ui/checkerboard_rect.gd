# =============================================================================
# RUTA: res://script_gdscript/ui/checkerboard_rect.gd
# Cuadrícula ajedrezada gris claro / oscuro para indicar transparencia visual
# =============================================================================
@tool
extends Control
class_name CheckerboardRect

@export var tile_size: float = 4.0
@export var color_light: Color = Color(0.94, 0.94, 0.96, 1.0)
@export var color_dark: Color = Color(0.76, 0.77, 0.82, 1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var cols := int(ceil(size.x / tile_size))
	var rows := int(ceil(size.y / tile_size))
	for r in range(rows):
		for c in range(cols):
			var p := Vector2(c * tile_size, r * tile_size)
			var sz := Vector2(minf(tile_size, size.x - p.x), minf(tile_size, size.y - p.y))
			var col := color_light if ((r + c) % 2 == 0) else color_dark
			draw_rect(Rect2(p, sz), col)
