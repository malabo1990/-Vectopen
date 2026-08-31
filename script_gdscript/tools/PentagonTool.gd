# =============================================================================
# RUTA: res://script_gdscript/PentagonTool.gd
# =============================================================================
extends ToolBase
class_name PentagonTool

func activate() -> void:
	super()
	print("\n[PentagonTool]: Herramienta Pentágono ACTIVADA.")

func deactivate() -> void:
	print("[PentagonTool]: Herramienta DESACTIVADA.")
	super()


# ── Entrada Delegada del Canvas ───────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false
		
	_refresh_dependencies()
	if not canvas or not artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_drawing = true
			box_start_global = gm
			box_current_global = gm
			canvas.queue_redraw()
			return true
		else:
			if is_drawing:
				is_drawing = false
				_finalize_pentagon()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false


# ── Función: Crear en el centro del Artboard ──────────────────────────────────

func create_at_center() -> void:
	create_pentagon_at_center()

func create_pentagon_at_center() -> void:
	_refresh_dependencies()
	if not artboard: return
		
	var default_radius: float = 55.0
	var ab_size: Vector2 = Vector2(800.0, 600.0)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size
		
	var local_center: Vector2 = ab_size / 2.0
	_spawn_shape(local_center, default_radius, 0.0)


# ── Lógica Matemática y Trigonométrica ────────────────────────────────────────

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	var center: Vector2 = start
	var radius: float = start.distance_to(current)
	var rotation_angle: float = delta.angle()

	# [SHIFT] Bloquea la rotación manteniendo la base perfectamente horizontal
	if Input.is_key_pressed(KEY_SHIFT):
		rotation_angle = 0.0

	return {"center": center, "radius": radius, "rotation": rotation_angle}


# Generador matemático de los 5 vértices de un pentágono regular por CPU
func _generate_pentagon_points(center: Vector2, radius: float, rotation_angle: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var total_vertices = 5
	
	for i in range(total_vertices):
		# Dividimos los 360° en 5 partes (pasos de 72°). Restamos PI/2 para apuntar hacia arriba.
		var angle: float = i * (PI * 2.0 / total_vertices) - (PI / 2.0) + rotation_angle
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		
	return points


func _finalize_pentagon() -> void:
	var geom: Dictionary = _calculate_geometry()
	var final_radius: float = geom["radius"]
	var final_center_global: Vector2 = geom["center"]
	var final_rotation: float = geom["rotation"]

	if final_radius > 3.0:
		_retarget_artboard_at(final_center_global)
		var local_center: Vector2 = artboard.to_local(final_center_global)
		_spawn_shape(local_center, final_radius, final_rotation)


# ── Inyección DIRECTA en el Artboard (Polygon2D + Line2D Seguro) ──────────────

func _spawn_shape(local_center: Vector2, radius: float, rotation_angle: float) -> void:
	if not artboard: return

	print("[PentagonTool]: Instanciando VectorPolygon en el Artboard...")

	var new_shape = VectorPolygon.new()
	new_shape.name = "Pentagono_Vectorial"
	new_shape.set_doc_position(DVec2.from_v2(local_center))
	new_shape.set_doc_vertices(DVec2.array_from_v2(_generate_pentagon_points(Vector2.ZERO, radius, rotation_angle)))
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH
	new_shape.closed = true

	artboard.add_child(new_shape)
	new_shape.owner = artboard


# ── Renderizado de Guías en Pantalla (Previsualización elástica) ──────────────

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c): return

	var geom: Dictionary = _calculate_geometry()
	var local_center: Vector2 = c.to_local(geom["center"])
	var points_preview = _generate_pentagon_points(local_center, geom["radius"], geom["rotation"])

	c.draw_colored_polygon(points_preview, COLOR_PREVIEW_F)
	
	var stroke_preview := PackedVector2Array(points_preview)
	stroke_preview.append(points_preview[0])
	
	var current_scale: float = c.global_transform.get_scale().x
	if current_scale <= 0.001: current_scale = 1.0
	var line_width: float = clampf(1.2 / current_scale, 0.6, 3.0)
	
	c.draw_polyline(stroke_preview, COLOR_PREVIEW_S, line_width, true)



