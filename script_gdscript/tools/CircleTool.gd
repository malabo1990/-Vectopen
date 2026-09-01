class_name CircleTool
extends ToolBase

# Definimos 128 lados para que la curva sea lo más suave posible en el Polygon2D
const CIRCLE_QUALITY: int = 128

func activate() -> void:
	super()
	print("\n[CircleTool]: Herramienta ACTIVADA (Arquitectura Estándar Vectopen).")

func deactivate() -> void:
	print("[CircleTool]: Herramienta DESACTIVADA.")
	super()


# ── Entrada Delegada del Canvas ───────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false
		
	if not canvas or not artboard: _refresh_dependencies()
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
				_finalize_circle()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false


# ── Función: Crear en el centro del Artboard ──────────────────────────────────

func create_at_center() -> void:
	create_circle_at_center()

func create_circle_at_center() -> void:
	if not artboard: _refresh_dependencies()
	if not artboard:
		print("circulo no existe - Error: No se puede centrar porque 'artboard' es NULL")
		return
		
	var default_size: Vector2 = Vector2(140, 140)
	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size
		
	var local_pos: Vector2 = (ab_size / 2.0) - (default_size / 2.0)
	_spawn_shape(local_pos, default_size)


# ── Lógica de Procesamiento Geométrico ────────────────────────────────────────

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	# [SHIFT] Bloqueo de proporciones para círculo perfecto
	if Input.is_key_pressed(KEY_SHIFT):
		var max_side: float = max(abs(delta.x), abs(delta.y))
		delta.x = max_side * sign(delta.x)
		delta.y = max_side * sign(delta.y)
		current = start + delta

	var top_left: Vector2
	var size: Vector2

	# [ALT] Dibujar desde el centro
	if Input.is_key_pressed(KEY_ALT):
		size = delta.abs() * 2.0
		top_left = start - delta.abs()
	else:
		size = delta.abs()
		top_left = Vector2(min(start.x, current.x), min(start.y, current.y))

	return {"top_left": top_left, "size": size}


func _finalize_circle() -> void:
	var geom: Dictionary = _calculate_geometry()
	var final_size: Vector2 = geom["size"]
	var final_top_left_global: Vector2 = geom["top_left"]

	if final_size.x > 3.0 and final_size.y > 3.0:
		_retarget_artboard_at(final_top_left_global + final_size / 2.0)
		var local_pos: Vector2 = artboard.to_local(final_top_left_global)
		_spawn_shape(local_pos, final_size)
	else:
		print("circulo no existe - El arrastre fue demasiado pequeño.")


# ── Inyección Estándar de Nodos (Polygon2D + Line2D) ──────────────────────────

func _spawn_shape(local_pos: Vector2, size: Vector2) -> void:
	if not artboard:
		return

	print("[CircleTool]: Instanciando VectorCircle en el Artboard...")

	var new_shape = VectorCircle.new()
	new_shape.name = NameUtils.unique_child_name(artboard, "Círculo")
	new_shape.set_doc_position(DVec2.from_v2(local_pos + size / 2.0))
	new_shape.set_doc_extent(DVec2.from_v2(size))
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH

	artboard.add_child(new_shape)
	new_shape.owner = artboard

	print("Crear Círculo - VectorCircle [Pos: ", new_shape.position, " Size: ", size, "]")


# ── Renderizado de Guías ──────────────────────────────────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c):
		return

	var geom: Dictionary = _calculate_geometry()
	var size: Vector2 = geom["size"]
	var tl: Vector2 = c.to_local(geom["top_left"])
	
	var center_local = tl + (size / 2.0)
	var radius = size / 2.0
	
	var vertices_preview = PackedVector2Array()
	for i in range(CIRCLE_QUALITY):
		var angle = (i * 2.0 * PI) / CIRCLE_QUALITY
		var vertex = center_local + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		vertices_preview.append(vertex)

	var current_scale: float = c.global_transform.get_scale().x
	if current_scale <= 0.001: current_scale = 1.0
	var line_width: float = clampf(1.2 / current_scale, 0.6, 3.0)

	c.draw_colored_polygon(vertices_preview, COLOR_PREVIEW_F)
	
	var points_outline = Array(vertices_preview)
	points_outline.append(vertices_preview[0])
	c.draw_polyline(PackedVector2Array(points_outline), COLOR_PREVIEW_S, line_width, true)
