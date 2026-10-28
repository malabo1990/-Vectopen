# =============================================================================
# RUTA: res://script_gdscript/WaterDropTool.gd
# =============================================================================
extends ToolBase
class_name WaterDropTool


func activate() -> void:
	super()
	print("\n[WaterDropTool]: Herramienta Gota de Agua SVG-Replica ACTIVADA.")


func deactivate() -> void:
	print("[WaterDropTool]: Herramienta DESACTIVADA.")
	super()


# ── Entrada Delegada del Canvas ───────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	# Solo el ratón sobre un panel se ignora; el teclado (Esc, Supr, flechas…)
	# funciona esté donde esté el puntero.
	if event is InputEventMouse and "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
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
				_finalize_drop()
				canvas.queue_redraw()
				return true

	if event is InputEventMouseMotion and is_drawing:
		box_current_global = gm
		canvas.queue_redraw()
		return true

	return false


# ── Crear en el centro del Artboard ──────────────────────────────────────────

func create_at_center() -> void:
	create_drop_at_center()

func create_drop_at_center() -> void:
	_refresh_dependencies()
	if not artboard:
		return

	var default_radius: float = 50.0
	var ab_size: Vector2 = Vector2(800.0, 600.0)
	if "artboard_size" in artboard:
		ab_size = artboard.artboard_size

	_spawn_shape(ab_size / 2.0, default_radius, 0.0)


# ── Geometría ─────────────────────────────────────────────────────────────────

func _calculate_geometry() -> Dictionary:
	var start: Vector2 = box_start_global
	var current: Vector2 = box_current_global
	var delta: Vector2 = current - start

	var radius: float = start.distance_to(current)
	var rotation_angle: float = delta.angle() + (PI / 2.0)

	if Input.is_key_pressed(KEY_SHIFT):
		rotation_angle = 0.0

	return {"center": start, "radius": radius, "rotation": rotation_angle}


func _quad_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return (u * u * p0) + (2.0 * u * t * p1) + (t * t * p2)


# ── Generador de Puntos — Réplica exacta de SVG Nativo ────────────────────────

## Contorno de la gota (sistema local: origen = centro del arco).
## `curvature` 0..1: 0 = lados rectos (punta muy afilada), 0.5 = la gota
## original del SVG, 1 = lados muy curvos.
static func drop_points(radius: float, rotation_angle: float = 0.0, curvature: float = 0.5) -> PackedVector2Array:
	var t := new()
	var pts: PackedVector2Array = t._generate_drop_points(Vector2.ZERO, radius, rotation_angle, curvature)
	t.free()
	return pts

func _generate_drop_points(center: Vector2, radius: float, rotation_angle: float, curvature: float = 0.5) -> PackedVector2Array:
	var puntos := PackedVector2Array()
	var r: float = radius

	# ── Puntos clave (sistema local, origen = centro del arco)
	var tip: Vector2 = Vector2(0.0, -1.796093 * r)
	var p_right: Vector2 = Vector2(0.781250 * r, -0.624218 * r)
	var p_left: Vector2 = Vector2(-0.781250 * r, -0.624218 * r)

	# Controles de las curvas Q
	# Control de las curvas laterales según la curvatura (0.5 = el original).
	var c := clampf(curvature, 0.0, 1.0)
	var qx := lerpf(0.0, 0.117188, c * 2.0) if c <= 0.5 else lerpf(0.117188, 0.6, (c - 0.5) * 2.0)
	var qy := -1.499218 if c <= 0.5 else lerpf(-1.499218, -1.2, (c - 0.5) * 2.0)
	var qc_r: Vector2 = Vector2(qx * r, qy * r)
	var qc_l: Vector2 = Vector2(-qc_r.x, qc_r.y)

	# ── Segmento 1: Q derecha — tip → p_right
	var segs_q: int = 48
	for i: int in range(segs_q):
		var t: float = float(i) / float(segs_q)
		var p: Vector2 = _quad_bezier(tip, qc_r, p_right, t)
		puntos.append(center + p.rotated(rotation_angle))

	# ── Segmento 2: Arco circular — p_right → p_left (CW)
	var a_start: float = atan2(p_right.y, p_right.x)
	var a_end: float = atan2(p_left.y, p_left.x) + TAU

	var segs_arc: int = 96
	# Optimizamos a "segs_arc" en lugar de "segs_arc + 1" para no duplicar el punto de anclaje final p_left
	for i: int in range(segs_arc):
		var t: float = float(i) / float(segs_arc)
		var angle: float = lerpf(a_start, a_end, t) # SOLUCIÓN: Uso estricto de lerpf para tipos float puros
		var p: Vector2 = Vector2(cos(angle) * r, sin(angle) * r)
		puntos.append(center + p.rotated(rotation_angle))

	# ── Segmento 3: Q izquierda — p_left → tip
	for i: int in range(segs_q):
		var t: float = float(i) / float(segs_q)
		var p: Vector2 = _quad_bezier(p_left, qc_l, tip, t)
		puntos.append(center + p.rotated(rotation_angle))

	return puntos


func _finalize_drop() -> void:
	var geom: Dictionary = _calculate_geometry()

	if geom["radius"] > 3.0:
		_retarget_artboard_at(geom["center"])
		var local_center: Vector2 = artboard.to_local(geom["center"])
		_spawn_shape(local_center, geom["radius"], geom["rotation"])


# ── Inyección en el Artboard ──────────────────────────────────────────────────

func _spawn_shape(local_center: Vector2, radius: float, rotation_angle: float) -> void:
	if not artboard:
		return

	print("[WaterDropTool]: Instanciando VectorPolygon en el Artboard...")

	var new_shape = VectorPolygon.new()
	new_shape.name = NameUtils.unique_child_name(artboard, "Gota")
	new_shape.set_doc_position(DVec2.from_v2(local_center))
	var curv := float(PanelPolygon.setting("drop_curvature", 0.5))
	new_shape.set_doc_vertices(DVec2.array_from_v2(_generate_drop_points(Vector2.ZERO, radius, rotation_angle, curv)))
	# Paramétrica: el panel de Polígonos cambia la curvatura de la cola.
	new_shape.set_meta("shape_kind", "drop")
	new_shape.set_meta("drop_radius", radius)
	new_shape.set_meta("drop_rotation", rotation_angle)
	new_shape.set_meta("drop_curvature", curv)
	new_shape.fill_color = FILL_COLOR
	new_shape.stroke_color = STROKE_COLOR
	new_shape.stroke_width = STROKE_WIDTH
	new_shape.closed = true

	artboard.add_child(new_shape)
	new_shape.owner = artboard
	# Con deshacer y seleccionada (antes no se podía deshacer).
	var hm = Engine.get_main_loop().root.get_node_or_null("HistoryManager") if Engine.get_main_loop() else null
	if hm and hm.has_method("record_create"):
		hm.record_create(new_shape)
	var sm = Engine.get_main_loop().root.get_node_or_null("SelectionManager") if Engine.get_main_loop() else null
	if sm and sm.has_method("set_selection"):
		sm.set_selection([new_shape])


# ── Preview Elástico ──────────────────────────────────────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_drawing or not is_instance_valid(c):
		return

	var geom: Dictionary = _calculate_geometry()
	var local_center: Vector2 = c.to_local(geom["center"])
	var pts: PackedVector2Array = _generate_drop_points(
		local_center, geom["radius"], geom["rotation"], float(PanelPolygon.setting("drop_curvature", 0.5))
	)

	c.draw_colored_polygon(pts, COLOR_PREVIEW_F)

	var stroke_pts := PackedVector2Array(pts)
	stroke_pts.append(pts[0])

	var scale_x: float = c.global_transform.get_scale().x
	if scale_x <= 0.001:
		scale_x = 1.0
	var lw: float = clampf(1.2 / scale_x, 0.6, 3.0)

	c.draw_polyline(stroke_pts, COLOR_PREVIEW_S, lw, true)



