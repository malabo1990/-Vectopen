# =============================================================================
# RUTA: res://script_gdscript/Star4Tool.gd
# =============================================================================
extends ToolBase
class_name Star4Tool

func activate() -> void:
	super()
	print("\n[Star4Tool]: Herramienta ACTIVADA.")

func deactivate() -> void:
	print("[Star4Tool]: Herramienta DESACTIVADA.")
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
			print("[Star4Tool]: Iniciando arrastre manual de estrella 4 puntas en pos global: ", gm)
			canvas.queue_redraw()
			return true
		else:
			if is_drawing:
				is_drawing = false
				print("[Star4Tool]: Suelto click izquierdo. Finalizando estrella 4 puntas...")
				_finalize_star()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false


# ── Función: Crear en el centro del Artboard ──────────────────────────────────

func create_at_center() -> void:
	create_star_at_center()

func create_star_at_center() -> void:
	print("\n[Star4Tool]: Botón presionado -> Solicitando centrado de estrella 4 puntas en Artboard...")
	_refresh_dependencies()
	
	if not artboard:
		print("estrella4 no existe - Error: No se puede centrar porque 'artboard' es NULL")
		return
		
	var default_radius: float = 60.0
	
	# Detectar tamaño real del artboard de forma segura
	var ab_size: Vector2 = Vector2(800, 600)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size
		
	# Calcular el centro exacto del artboard en espacio local
	var local_center: Vector2 = ab_size / 2.0
	
	print("[Star4Tool]: Calculado centro local del Artboard para estrella 4 puntas en: ", local_center, " con radio exterior: ", default_radius)
	_spawn_shape(local_center, default_radius, 0.0)


# ── Lógica de Procesamiento Geométrico y Matemático ───────────────────────────

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	var center: Vector2 = start
	var radius_out: float = start.distance_to(current)
	var rotation_angle: float = delta.angle()

	# [SHIFT] Bloquea la rotación pura y mantiene los ejes ortogonales perfectos
	if Input.is_key_pressed(KEY_SHIFT):
		rotation_angle = 0.0

	return {"center": center, "radius_out": radius_out, "rotation": rotation_angle}


# Generador de los 8 vértices vectoriales alternos por CPU (4 puntas, 4 valles)
func _generate_star_points(center: Vector2, r_out: float, rotation: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var total_points = 8
	var r_in: float = r_out * 0.5 # Proporción 0.5 ideal para el diseño de 4 puntas (estilo brújula/brillo)
	
	for i in range(total_points):
		# Dividimos entre total_points (8) implicando saltos de 45 grados por vértice
		var angle: float = i * (PI * 2.0 / total_points) - (PI / 2.0) + rotation
		var current_r: float = r_out if (i % 2 == 0) else r_in
		points.append(center + Vector2(cos(angle), sin(angle)) * current_r)
		
	return points


func _finalize_star() -> void:
	var geom: Dictionary = _calculate_geometry()
	var final_radius: float = geom["radius_out"]
	var final_center_global: Vector2 = geom["center"]
	var final_rotation: float = geom["rotation"]

	if final_radius > 3.0:
		_retarget_artboard_at(final_center_global)
		var local_center: Vector2 = artboard.to_local(final_center_global)
		_spawn_shape(local_center, final_radius, final_rotation)
	else:
		print("estrella4 no existe - El radio de arrastre fue demasiado pequeño (menor de 3px).")


# ── Inyección DIRECTA en el Artboard (Polygon2D + Line2D) ─────────────────────

func _spawn_shape(local_center: Vector2, radius_out: float, rotation_angle: float) -> void:
	if not artboard:
		print("estrella4 no existe - Error Crítico: 'artboard' es NULL. No se puede instanciar.")
		return

	print("[Star4Tool]: Instanciando VectorPolygon en el Artboard...")

	var new_shape = VectorPolygon.new()
	new_shape.name = "Estrella_4_Puntas"
	new_shape.set_doc_position(DVec2.from_v2(local_center))
	new_shape.set_doc_vertices(DVec2.array_from_v2(_generate_star_points(Vector2.ZERO, radius_out, rotation_angle)))
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH
	new_shape.closed = true

	artboard.add_child(new_shape)
	new_shape.owner = artboard

	print("Crear Estrella 4P - VectorPolygon [Centro: ", local_center, " Radio: ", radius_out, "]")


# ── Renderizado de Guías en Pantalla (Previsualización elástica) ──────────────

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c):
		return

	var geom: Dictionary = _calculate_geometry()
	
	# Generamos los vértices transformados al plano local del lienzo dinámico
	var local_center: Vector2 = c.to_local(geom["center"])
	var points_preview = _generate_star_points(local_center, geom["radius_out"], geom["rotation"])

	# Render del relleno translúcido de la guía
	c.draw_colored_polygon(points_preview, COLOR_PREVIEW_F)
	
	# Render del contorno de la guía
	var stroke_preview = points_preview
	stroke_preview.append(points_preview[0])
	
	var current_scale: float = c.global_transform.get_scale().x
	if current_scale <= 0.001: current_scale = 1.0
	var line_width: float = clampf(1.2 / current_scale, 0.6, 3.0)
	
	c.draw_polyline(stroke_preview, COLOR_PREVIEW_S, line_width, true)



