class_name RectangleTool
extends ToolBase

func activate() -> void:
	super()
	print("\n[RectangleTool]: Herramienta ACTIVADA.")

func deactivate() -> void:
	print("[RectangleTool]: Herramienta DESACTIVADA.")
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
			print("[RectangleTool]: Iniciando arrastre manual en pos global: ", gm)
			canvas.queue_redraw()
			return true
		else:
			if is_drawing:
				is_drawing = false
				print("[RectangleTool]: Suelto click izquierdo. Finalizando geometría...")
				_finalize_rectangle()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false


# ── Función: Crear en el centro del Artboard ──────────────────────────────────

func create_at_center() -> void:
	create_rectangle_at_center()

func create_rectangle_at_center() -> void:
	print("\n[RectangleTool]: Botón presionado -> Solicitando centrado en Artboard...")
	if not artboard: _refresh_dependencies()
	
	if not artboard:
		print("rectangulo no existe - Error: No se puede centrar porque 'artboard' es NULL")
		return
		
	# Tamaño predeterminado inicial
	var default_size: Vector2 = Vector2(160, 120)
	
	# Detectar tamaño real del artboard de forma segura
	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size
		
	# Calcular la esquina superior izquierda local para centrar la figura
	var local_pos: Vector2 = (ab_size / 2.0) - (default_size / 2.0)
	
	print("[RectangleTool]: Calculado centro local del Artboard en: ", local_pos, " con tamaño: ", default_size)
	_spawn_shape(local_pos, default_size)


# ── Lógica de Procesamiento Geométrico ────────────────────────────────────────

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	# [SHIFT] Cuadrados Perfectos
	if Input.is_key_pressed(KEY_SHIFT):
		var max_side: float = max(abs(delta.x), abs(delta.y))
		delta.x = max_side * sign(delta.x)
		delta.y = max_side * sign(delta.y)
		current = start + delta

	var top_left: Vector2
	var size: Vector2

	# [ALT] Dibujar desde el centro geométrico
	if Input.is_key_pressed(KEY_ALT):
		size = delta.abs() * 2.0
		top_left = start - delta.abs()
	else:
		size = delta.abs()
		top_left = Vector2(min(start.x, current.x), min(start.y, current.y))

	return {"top_left": top_left, "size": size}


func _finalize_rectangle() -> void:
	var geom: Dictionary = _calculate_geometry()
	var final_size: Vector2 = geom["size"]
	var final_top_left_global: Vector2 = geom["top_left"]

	if final_size.x > 3.0 and final_size.y > 3.0:
		var local_pos: Vector2 = artboard.to_local(final_top_left_global)
		_spawn_shape(local_pos, final_size)
	else:
		print("rectangulo no existe - El arrastre fue demasiado pequeño (menor de 3px).")


# ── Inyección DIRECTA en el Artboard (Evita intermediarios corruptos) ─────────

func _spawn_shape(local_pos: Vector2, size: Vector2) -> void:
	if not artboard:
		print("rectangulo no existe - Error Crítico: 'artboard' es NULL. No se puede instanciar.")
		return

	print("[RectangleTool]: Instanciando VectorRectangle en el Artboard...")

	var new_shape = VectorRectangle.new()
	new_shape.name = "Rectangulo_Vectorial"
	new_shape.set_doc_position(DVec2.from_v2(local_pos + size / 2.0))
	new_shape.set_doc_extent(DVec2.from_v2(size))
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH

	artboard.add_child(new_shape)
	new_shape.owner = artboard

	print("Crear Rectangulo - VectorRectangle [Pos: ", new_shape.position, " Size: ", size, "]")


# ── Renderizado de Guías en Pantalla ──────────────────────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c):
		return

	var geom: Dictionary = _calculate_geometry()
	var local_tl: Vector2 = c.to_local(geom["top_left"])
	var local_br: Vector2 = c.to_local(geom["top_left"] + geom["size"])
	var preview_rect: Rect2 = Rect2(local_tl, local_br - local_tl)

	var current_scale: float = c.global_transform.get_scale().x
	if current_scale <= 0.001: current_scale = 1.0
	var line_width: float = clampf(1.2 / current_scale, 0.6, 3.0)

	c.draw_rect(preview_rect, COLOR_PREVIEW_F, true)
	c.draw_rect(preview_rect, COLOR_PREVIEW_S, false, line_width)
