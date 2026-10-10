# =============================================================================
# RUTA: res://script_gdscript/PentagonTool.gd
# =============================================================================
extends ToolBase
class_name PentagonTool

@export var sides_count: int = 5:
	set(v):
		sides_count = maxi(3, v)

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


# Generador matemático de los vértices de un polígono regular por CPU
func _generate_pentagon_points(center: Vector2, radius: float, rotation_angle: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var total_vertices: int = _sides()
	var off := deg_to_rad(float(PanelPolygon.setting("poly_angle", 0.0))) + rotation_angle
	var aspect := float(PanelPolygon.setting("poly_aspect", 1.0))
	for i in range(total_vertices):
		# Dividimos los 360° en total_vertices partes. Restamos PI/2 para apuntar hacia arriba.
		var angle: float = i * (PI * 2.0 / total_vertices) - (PI / 2.0) + off
		points.append(center + Vector2(cos(angle) * aspect, sin(angle)) * radius)
	return points

## Lados: los del panel de Polígonos (o `sides_count` sin panel).
func _sides() -> int:
	return maxi(3, int(PanelPolygon.setting("sides", sides_count)))


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

	# Polígono REGULAR paramétrico (lados, giro, proporción y redondeo del
	# panel): sigue siendo editable desde el panel después de dibujarlo.
	var new_shape = VectorPolygon.new()
	var sides := _sides()
	new_shape.name = NameUtils.unique_child_name(artboard, PanelPolygon._poly_name(sides))
	new_shape.set_doc_position(DVec2.from_v2(local_center))
	new_shape.radius = radius
	new_shape.poly_angle = float(PanelPolygon.setting("poly_angle", 0.0)) + rad_to_deg(rotation_angle)
	new_shape.poly_aspect = float(PanelPolygon.setting("poly_aspect", 1.0))
	new_shape.corner_radius = float(PanelPolygon.setting("corner_radius", 0.0))
	new_shape.sides = sides
	new_shape.is_regular = true
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH
	new_shape.closed = true

	artboard.add_child(new_shape)
	new_shape.owner = artboard
	_commit_new_shape(new_shape)


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



