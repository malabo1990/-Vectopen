# =============================================================================
# RUTA: res://scripts/BezierTool.gd
# Vectopen — Herramienta Bézier profesional
# Lógica portada desde prototipo HTML validado.
# =============================================================================
extends ToolBase

# ── Referencias ───────────────────────────────────────────────────────────────
var target_artboard: Node2D = null
var current_path: Path2D = null

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
	_reset_state()
	_refresh_artboard()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if canvas:
		canvas.queue_redraw()

func deactivate() -> void:
	_finalize(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRADA
# ═══════════════════════════════════════════════════════════════════════════════

func handle_input(event: InputEvent) -> bool:
	if not is_instance_valid(canvas):
		return false
	if not is_instance_valid(target_artboard):
		_refresh_artboard()
	if not target_artboard:
		return false

	var local := target_artboard.to_local(canvas.get_global_mouse_position())

	# ── Teclado ───────────────────────────────────────────────────────────────
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			breaking_symmetry = event.pressed
			return false

		if event.pressed:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					if is_creating:
						_finalize(false)
						return true
				KEY_ESCAPE:
					if is_creating:
						_finalize(false)
						return true

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

	# Añadimos el primer punto al final para cerrar visualmente la curva baked
	var fp := c.get_point_position(0)
	var fi := c.get_point_in(0)
	var fo := c.get_point_out(0)
	c.add_point(fp, fi, fo)

	current_path.closed = true
	_sync()
	_finalize(true)

# ═══════════════════════════════════════════════════════════════════════════════
# PREVIEW — dibujado sobre el canvas principal
# ═══════════════════════════════════════════════════════════════════════════════

func draw_preview(c: Node2D) -> void:
	if not is_creating or not is_instance_valid(current_path) or not is_instance_valid(c):
		return

	var curve := current_path.curve
	if curve.point_count == 0:
		return

	var scale := c.global_transform.get_scale().x
	if scale <= 0.001:
		scale = 1.0
	var lw := clampf(BEZIER_STROKE_WIDTH / scale, 0.5, 3.0)

	var last_idx := curve.point_count - 1
	var anchor_local := curve.get_point_position(last_idx)
	var handle_out_local := curve.get_point_out(last_idx)

	# Convertir puntos a espacio del canvas
	var start_c := c.to_local(target_artboard.to_global(anchor_local))

	# Destino de la línea elástica: primer nodo si snap activo, sino el ratón
	var target_local := mouse_canvas
	if close_snap_active:
		target_local = curve.get_point_position(0)
	var end_c := c.to_local(target_artboard.to_global(target_local))

	# ── Línea elástica de preview ─────────────────────────────────────────────
	if handle_out_local != Vector2.ZERO or close_snap_active:
		# Usamos Curve2D temporal para baked bezier exacto
		var temp := Curve2D.new()
		var h_out_c := c.to_local(target_artboard.to_global(anchor_local + handle_out_local))
		temp.add_point(start_c, Vector2.ZERO, h_out_c - start_c)
		temp.add_point(end_c, Vector2.ZERO, Vector2.ZERO)
		var baked := temp.get_baked_points()
		if baked.size() >= 2:
			c.draw_polyline(baked, PREVIEW_COLOR, lw, true)
	else:
		c.draw_line(start_c, end_c, PREVIEW_COLOR, lw)

	# ── Handles del último punto (visible mientras se arrastra) ───────────────
	if is_dragging_handle and handle_out_local != Vector2.ZERO:
		var h_in_local := curve.get_point_in(last_idx)
		var h_out_c := c.to_local(target_artboard.to_global(anchor_local + handle_out_local))
		var h_in_c  := c.to_local(target_artboard.to_global(anchor_local + h_in_local))
		c.draw_line(start_c, h_out_c, HANDLE_LINE_COLOR, lw)
		c.draw_line(start_c, h_in_c,  HANDLE_LINE_COLOR, lw)
		c.draw_circle(h_out_c, HANDLE_SIZE / scale, HANDLE_COLOR)
		c.draw_circle(h_in_c,  HANDLE_SIZE / scale, HANDLE_COLOR)

	# ── Todos los nodos del path activo ──────────────────────────────────────
	for i in range(curve.point_count):
		var pt_c := c.to_local(target_artboard.to_global(curve.get_point_position(i)))
		var half := NODE_SIZE / scale
		c.draw_rect(Rect2(pt_c - Vector2(half, half), Vector2(half * 2, half * 2)),
					Color(1, 1, 1), true)
		c.draw_rect(Rect2(pt_c - Vector2(half, half), Vector2(half * 2, half * 2)),
					NODE_COLOR, false, lw)

	# ── Indicador de cierre (anillo verde) ───────────────────────────────────
	if close_snap_active and curve.point_count >= 2:
		var fp_c := c.to_local(target_artboard.to_global(curve.get_point_position(0)))
		c.draw_arc(fp_c, CLOSE_SNAP_RADIUS / scale, 0, TAU, 24, CLOSE_COLOR, lw)

# ═══════════════════════════════════════════════════════════════════════════════
# UTILIDADES INTERNAS
# ═══════════════════════════════════════════════════════════════════════════════

func _start_new_path() -> void:
	is_creating = true
	close_snap_active = false
	is_dragging_handle = false

	current_path = Path2D.new()
	current_path.set_script(VectorPathScript)
	current_path.name = NameUtils.unique_child_name(target_artboard, "Trazo")
	current_path.curve = Curve2D.new()
	current_path.closed = false

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

	var scale := 1.0
	if is_instance_valid(canvas):
		scale = canvas.global_transform.get_scale().x
	if scale <= 0.001:
		scale = 1.0

	var first := c.get_point_position(0)
	close_snap_active = local.distance_to(first) <= (CLOSE_SNAP_RADIUS / scale)

	if close_snap_active:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func _finalize(was_closed: bool) -> void:
	if is_creating and is_instance_valid(current_path):
		current_path.closed = was_closed
		_sync()

	_reset_state()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _reset_state() -> void:
	is_creating = false
	is_dragging_handle = false
	breaking_symmetry = false
	close_snap_active = false
	current_path = null

func _sync() -> void:
	if is_instance_valid(current_path):
		current_path.queue_redraw()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _refresh_artboard() -> void:
	var container := canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)
