# =============================================================================
# RUTA: res://scripts/BezierTool.gd
# Vectopen — Herramienta Bézier profesional
# Lógica portada desde prototipo HTML validado.
# =============================================================================
extends ToolBase

# ── Referencias ───────────────────────────────────────────────────────────────
var target_artboard: Node2D = null
var current_path: Path2D = null
var _last_path: Path2D = null

# ── Estado de la Pluma ────────────────────────────────────────────────────────
var is_creating: bool = false
var is_dragging_handle: bool = false   # El usuario arrastra tras añadir el punto
var breaking_symmetry: bool = false    # ALT presionado → handle libre
var mouse_canvas: Vector2 = Vector2.ZERO  # Posición del ratón en espacio artboard
var close_snap_active: bool = false    # El ratón está sobre el primer nodo

# ── Constantes ────────────────────────────────────────────────────────────────
const CLOSE_SNAP_RADIUS: float = 12.0
const PREVIEW_COLOR     := Color(0.09, 0.37, 0.65, 0.7)
const HANDLE_COLOR      := Color(0.72, 0.46, 0.09, 1.0)
const HANDLE_LINE_COLOR := Color(0.72, 0.46, 0.09, 0.4)
const NODE_COLOR        := Color(0.09, 0.37, 0.65, 1.0)
const CLOSE_COLOR       := Color(0.06, 0.43, 0.33, 1.0)
const NODE_SIZE: float  = 5.0
const HANDLE_SIZE: float = 4.0
# Renombrada desde STROKE_WIDTH: ToolBase ya declara ese nombre (valor 1.0).
const BEZIER_STROKE_WIDTH: float = 1.5

# ═══════════════════════════════════════════════════════════════════════════════
# NODO DE RENDERIZADO
# El trazo persistente es un Path2D con VectorPath.gd — el MISMO tipo que produce
# el cargador del serializador, y con estilo editable desde el Inspector
# (fill_color / stroke_color / stroke_width / closed).
# ═══════════════════════════════════════════════════════════════════════════════
const VectorPathScript := preload("res://script_gdscript/shapes/VectorPath.gd")

# ═══════════════════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ═══════════════════════════════════════════════════════════════════════════════

func activate() -> void:
	_reset_state(true)
	_refresh_artboard()
	var sm := get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("get_selected"):
		for item in sm.get_selected():
			if item is Path2D and is_instance_valid(item.curve) and item.is_inside_tree():
				_last_path = item
				break
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if canvas:
		canvas.queue_redraw()

func deactivate() -> void:
	_finalize(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRADA
# ═══════════════════════════════════════════════════════════════════════════════

func _get_event_gm(event: InputEvent) -> Vector2:
	if is_instance_valid(canvas) and ("position" in event):
		return canvas.get_canvas_transform().affine_inverse() * event.position
	elif is_instance_valid(canvas):
		return canvas.get_global_mouse_position()
	return Vector2.ZERO

func handle_input(event: InputEvent) -> bool:
	# ── Teclado ───────────────────────────────────────────────────────────────
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			breaking_symmetry = event.pressed
			return false

		if event.pressed:
			match event.keycode:
				KEY_X, KEY_BACKSPACE, KEY_DELETE:
					if is_creating and is_instance_valid(current_path) and is_instance_valid(current_path.curve):
						var c_pts = current_path.curve.point_count
						if c_pts > 0:
							current_path.curve.remove_point(c_pts - 1)
							if current_path.curve.point_count == 0:
								_reset_state(true)
							_sync()
							return true
				KEY_ENTER, KEY_KP_ENTER:
					if is_creating:
						_finalize(false)
						return true
				KEY_ESCAPE:
					if is_creating:
						_finalize(false)
						return true
		return false

	if not is_instance_valid(canvas):
		return false
	if not is_instance_valid(target_artboard):
		_refresh_artboard()
	if not target_artboard:
		return false

	var gm := _get_event_gm(event)
	var local := target_artboard.to_local(gm)

	# ── Movimiento del ratón ──────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		mouse_canvas = local
		_update_close_snap(local)

		if is_dragging_handle and is_creating and is_instance_valid(current_path):
			_drag_handle(local)

		if is_instance_valid(canvas):
			canvas.queue_redraw()

		if is_creating:
			return true

	# ── Botones del ratón ─────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				return _on_left_press(local)
			else:
				if is_dragging_handle:
					is_dragging_handle = false
					_sync()
					return true

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_creating:
				_finalize(false)
				return true

	return false

# ─── Clic izquierdo ──────────────────────────────────────────────────────────

func _on_left_press(local: Vector2) -> bool:
	# Cerrar path: el ratón está sobre el primer nodo
	if is_creating and close_snap_active and is_instance_valid(current_path):
		if current_path.curve.point_count >= 2:
			_close_path()
			return true

	# Iniciar nuevo path si no hay uno activo
	if not is_creating or not is_instance_valid(current_path):
		_start_new_path()

	# Añadir punto
	var c := current_path.curve
	c.add_point(local, Vector2.ZERO, Vector2.ZERO)
	is_dragging_handle = true
	_sync()
	return true

# ─── Arrastrar handle del último punto ───────────────────────────────────────

func _drag_handle(local: Vector2) -> void:
	if not is_instance_valid(current_path):
		return
	var c := current_path.curve
	var idx := c.point_count - 1
	if idx < 0:
		return

	var anchor := c.get_point_position(idx)
	var handle_out := local - anchor
	# Un clic con temblor (< 4 px en pantalla) no es un arrastre: sin
	# manejadores, la esquina queda en punta (antes quedaban de 2–3 px y la
	# curva hacía un bucle diminuto que rompía los trazos gruesos).
	var zoom := 1.0
	var cam := current_path.get_viewport().get_camera_2d() if current_path.is_inside_tree() else null
	if cam:
		zoom = maxf(cam.zoom.x, 0.0001)
	if handle_out.length() * zoom < 4.0:
		c.set_point_out(idx, Vector2.ZERO)
		if not breaking_symmetry:
			c.set_point_in(idx, Vector2.ZERO)
		_sync()
		return

	if breaking_symmetry:
		# Solo modifica el handle de salida (crea esquina/cúspide)
		c.set_point_out(idx, handle_out)
	else:
		# Handles simétricos
		c.set_point_out(idx, handle_out)
		c.set_point_in(idx, -handle_out)

	_sync()

# ─── Cierre automático del path ──────────────────────────────────────────────

func _close_path() -> void:
	if not is_instance_valid(current_path):
		return
	var c := current_path.curve
	if c.point_count < 2:
		_finalize(false)
		return

	# Si el último punto no coincide con el primero, añadimos el cierre
	var fp := c.get_point_position(0)
	var lp := c.get_point_position(c.point_count - 1)
	if not lp.is_equal_approx(fp):
		var fi := c.get_point_in(0)
		var fo := c.get_point_out(0)
		c.add_point(fp, fi, fo)

	current_path.closed = true
	_sync()
	_finalize(true)

# ═══════════════════════════════════════════════════════════════════════════════
# PREVIEW — dibujado sobre el canvas principal
# ═══════════════════════════════════════════════════════════════════════════════

func _get_active_path() -> Path2D:
	if is_creating and is_instance_valid(current_path):
		return current_path
	if is_instance_valid(_last_path) and is_instance_valid(_last_path.curve) and _last_path.is_inside_tree():
		return _last_path
	var sm := get_node_or_null("/root/SelectionManager")
	if is_instance_valid(sm) and sm.has_method("get_selected"):
		for item in sm.get_selected():
			if item is Path2D and is_instance_valid(item.curve) and item.is_inside_tree():
				return item
	return null

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	var path_to_draw: Path2D = null
	if is_creating and is_instance_valid(current_path):
		path_to_draw = current_path
	else:
		path_to_draw = _get_active_path()

	if not is_instance_valid(path_to_draw) or not (path_to_draw.curve is Curve2D):
		return

	var curve := path_to_draw.curve
	if curve.point_count == 0:
		return

	var vp := c.get_viewport()
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var inv: float = 1.0 / clampf(zoom, 0.0002, 100000.0)
	var lw: float = maxf(1.5 * inv, 0.6)
	var base_h_radius: float = canvas.get_meta("bezier_handle_radius") if (is_instance_valid(canvas) and canvas.has_meta("bezier_handle_radius")) else 3.2
	var node_half: float = maxf(4.5 * inv, 3.0)
	var handle_radius: float = maxf(base_h_radius * inv, 2.4)
	var handle_border: float = maxf(1.2 * inv, 0.6)

	var path_or_ab: Node2D = path_to_draw if is_instance_valid(path_to_draw) else target_artboard

	# ── Línea elástica de preview (solo mientras se está creando) ────────────────
	if is_creating and is_instance_valid(current_path):
		var last_idx := curve.point_count - 1
		var anchor_local := curve.get_point_position(last_idx)
		var handle_out_local := curve.get_point_out(last_idx)
		var start_c := c.to_local(path_or_ab.to_global(anchor_local))

		var target_local := mouse_canvas
		if close_snap_active:
			target_local = curve.get_point_position(0)
		var end_c := c.to_local(path_or_ab.to_global(target_local))

		if handle_out_local != Vector2.ZERO or close_snap_active:
			var temp := Curve2D.new()
			var h_out_c := c.to_local(path_or_ab.to_global(anchor_local + handle_out_local))
			temp.add_point(start_c, Vector2.ZERO, h_out_c - start_c)
			temp.add_point(end_c, Vector2.ZERO, Vector2.ZERO)
			var baked := temp.get_baked_points()
			if baked.size() >= 2:
				c.draw_polyline(baked, PREVIEW_COLOR, lw, true)
		else:
			c.draw_line(start_c, end_c, PREVIEW_COLOR, lw)

	# ── Handles de todos los nodos con curvas en el trazo ──────────────────────
	var handle_line_col := Color(0.12, 0.52, 0.95, 0.9)
	var handle_ring_col := Color(0.08, 0.44, 0.88, 1.0)
	for i in range(curve.point_count):
		var p_local := curve.get_point_position(i)
		var p_c := c.to_local(path_or_ab.to_global(p_local))
		var h_out := curve.get_point_out(i)
		var h_in := curve.get_point_in(i)

		if h_out != Vector2.ZERO:
			var h_out_c := c.to_local(path_or_ab.to_global(p_local + h_out))
			c.draw_line(p_c, h_out_c, handle_line_col, lw)
			c.draw_circle(h_out_c, handle_radius, Color.WHITE)
			c.draw_arc(h_out_c, handle_radius, 0.0, TAU, 24, handle_ring_col, handle_border)

		if h_in != Vector2.ZERO:
			var h_in_c := c.to_local(path_or_ab.to_global(p_local + h_in))
			c.draw_line(p_c, h_in_c, handle_line_col, lw)
			c.draw_circle(h_in_c, handle_radius, Color.WHITE)
			c.draw_arc(h_in_c, handle_radius, 0.0, TAU, 24, handle_ring_col, handle_border)

	# ── Todos los nodos del path activo con doble contorno de contraste ─────────
	for i in range(curve.point_count):
		var pt_c := c.to_local(path_or_ab.to_global(curve.get_point_position(i)))
		var r := Rect2(pt_c - Vector2(node_half, node_half), Vector2(node_half * 2.0, node_half * 2.0))
		# Halo exterior oscuro para contraste sobre fondos de cualquier color
		c.draw_rect(r.grow(1.2 * inv), Color(0.0, 0.0, 0.0, 0.5), false, lw)
		# Relleno blanco brillante
		c.draw_rect(r, Color.WHITE, true)
		# Borde azul profesional
		c.draw_rect(r, NODE_COLOR, false, lw)

	# ── Indicador de cierre (anillo verde de alto contraste) ──────────────────
	if is_creating and close_snap_active and curve.point_count >= 2:
		var fp_c := c.to_local(path_or_ab.to_global(curve.get_point_position(0)))
		c.draw_arc(fp_c, CLOSE_SNAP_RADIUS * inv, 0, TAU, 28, CLOSE_COLOR, lw * 1.5)

# ═══════════════════════════════════════════════════════════════════════════════
# UTILIDADES INTERNAS
# ═══════════════════════════════════════════════════════════════════════════════

func _start_new_path() -> void:
	is_creating = true
	close_snap_active = false
	is_dragging_handle = false
	_last_path = null

	current_path = Path2D.new()
	current_path.set_script(VectorPathScript)
	current_path.name = NameUtils.unique_child_name(target_artboard, "Trazo")
	current_path.curve = Curve2D.new()
	current_path.closed = false

	var cc := get_node_or_null("/root/ColorCore")
	if is_instance_valid(cc):
		var sc: Color = cc.stroke_color
		if sc.a < 0.15: sc.a = 1.0
		current_path.stroke_color = sc
		var fc: Color = cc.fill_color
		if fc.a < 0.15: fc.a = 1.0
		current_path.fill_color = fc

	var layer := target_artboard.get_node_or_null("VectorDrawingLayer")
	if layer:
		layer.add_child(current_path)
	else:
		target_artboard.add_child(current_path)

func _update_close_snap(local: Vector2) -> void:
	close_snap_active = false
	if not is_creating or not is_instance_valid(current_path):
		return
	var c := current_path.curve
	if c.point_count < 2:
		return

	var vp := canvas.get_viewport() if is_instance_valid(canvas) else null
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var inv: float = 1.0 / clampf(zoom, 0.0002, 100000.0)

	var first := c.get_point_position(0)
	close_snap_active = local.distance_to(first) <= (CLOSE_SNAP_RADIUS * inv)

	if close_snap_active:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func _finalize(was_closed: bool) -> void:
	if is_creating and is_instance_valid(current_path):
		current_path.closed = was_closed
		_last_path = current_path
		_sync()
		var sm := get_node_or_null("/root/SelectionManager")
		if is_instance_valid(sm) and sm.has_method("set_selection"):
			sm.set_selection([current_path])

	_reset_state(false)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _reset_state(clear_last: bool = true) -> void:
	is_creating = false
	is_dragging_handle = false
	breaking_symmetry = false
	close_snap_active = false
	current_path = null
	if clear_last:
		_last_path = null

func _sync() -> void:
	if is_instance_valid(current_path):
		current_path.queue_redraw()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _refresh_artboard() -> void:
	var container := canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)
