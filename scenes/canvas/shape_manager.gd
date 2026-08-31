# ==========================================
# RUTA: res://scenes/canvas/shape_manager.gd
# CAMBIOS RESPECTO AL ORIGINAL:
#   - create_shape_explicit() ahora recibe pos en coordenadas LOCALES
#     del artboard (el caller, RectangleTool, hace la conversión).
#     Se añade comentario claro para evitar confusión futura.
#   - get_active_artboard() expuesto como método público (ya lo era,
#     pero se añade documentación).
#   - @onready corregido para ser más robusto con get_node_or_null.
# ==========================================
extends Node2D
class_name ShapeManager

class VectopenRect extends Node2D:
	var width: float
	var height: float
	var color: Color
	
	var is_selected: bool = false:
		set(v):
			is_selected = v
			queue_redraw()

	const HANDLE_SIZE := 8.0

	func _init(p_pos: Vector2, w: float, h: float, col: Color) -> void:
		position = p_pos
		width = w
		height = h
		color = col

	func _draw() -> void:
		var rect = Rect2(-width / 2, -height / 2, width, height)
		
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0.15, 0.15, 0.15, 0.6), false, 1.0)
		
		if is_selected:
			var border_color = Color("#7000ff")
			draw_rect(rect, border_color, false, 1.5)
			
			var handles = _get_handles_dict()
			for name in handles:
				var h_pos = handles[name]
				var h_rect = Rect2(h_pos - Vector2.ONE * (HANDLE_SIZE / 2), Vector2.ONE * HANDLE_SIZE)
				draw_rect(h_rect, Color.WHITE, true)
				draw_rect(h_rect, border_color, false, 1.2)

	func _get_handles_dict() -> Dictionary:
		var half_w = width / 2
		var half_h = height / 2
		return {
			"top_left":      Vector2(-half_w, -half_h),
			"top_center":    Vector2(0, -half_h),
			"top_right":     Vector2(half_w, -half_h),
			"right_center":  Vector2(half_w, 0),
			"bottom_right":  Vector2(half_w, half_h),
			"bottom_center": Vector2(0, half_h),
			"bottom_left":   Vector2(-half_w, half_h),
			"left_center":   Vector2(-half_w, 0)
		}

	func get_handle_at_pos(local_mouse: Vector2) -> String:
		var handles = _get_handles_dict()
		for name in handles:
			if local_mouse.distance_to(handles[name]) < (HANDLE_SIZE / 2) + 4.0:
				return name
		return ""

# ─── CORRECCIÓN BUG 4: @onready más robusto ──────────────────────
# Si ShapeManager se mueve en el árbol, la ruta relativa podría fallar.
# Usamos _ready() para buscarlo de forma explícita.
var artboards_container: Node2D = null

func _ready() -> void:
	# Intento 1: ruta relativa directa
	artboards_container = get_node_or_null("../ArtboardsContainer")
	# Intento 2: buscar en la escena raíz por nombre
	if not artboards_container:
		artboards_container = get_tree().current_scene.find_child("ArtboardsContainer", true, false)
	if not artboards_container:
		push_warning("ShapeManager: ArtboardsContainer no encontrado.")

## Crea un rectángulo vectorial en el artboard activo.
## IMPORTANTE: p_pos debe estar en coordenadas LOCALES del artboard,
## con el centro del rectángulo como origen (no la esquina superior-izquierda).
## RectangleTool hace la conversión antes de llamar a este método.
func create_shape_explicit(p_pos: Vector2, w: float, h: float) -> VectopenRect:
	var artboard = get_active_artboard()
	if not artboard:
		push_error("ShapeManager: No hay ningún Artboard activo.")
		return null
	
	var new_rect = VectopenRect.new(p_pos, w, h, Color(0.2, 0.55, 0.9, 0.6))
	new_rect.name = "Rectangulo_%d" % (artboard.get_child_count() + 1)
	
	artboard.add_child(new_rect)
	print("ShapeManager: Rectángulo creado en pos local ", p_pos, " tamaño ", Vector2(w, h))
	return new_rect

## Retorna el artboard ACTIVO. Autoridad: ArtboardManager (soporta
## multi-artboard). Fallback al primer hijo del contenedor si no hay manager.
func get_active_artboard() -> Node2D:
	var mgr := ArtboardManager.find(get_tree()) if get_tree() else null
	if mgr:
		var act := mgr.get_active_artboard()
		if is_instance_valid(act):
			return act
	if not artboards_container or artboards_container.get_child_count() == 0:
		return null
	return artboards_container.get_child(0) as Node2D
