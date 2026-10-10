# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_keyboard.gd
# Atajos de teclado: G/R/S (mover/rotar/escalar), bloqueo de eje X/Y, etc.
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_threading.gd"


# ── KEYBOARD SHORTCUT LOGIC (Shift+G/R/S move/rotate/scale, X/Y axis, X=delete) ──

func _handle_key_shortcuts(keycode: int, shift_pressed: bool = false) -> bool:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner() if canvas and canvas.get_viewport() else null
	if focus_owner is TextEdit or focus_owner is LineEdit:
		return false

	# Shift+G/R/S = move/rotate/scale from the keyboard (Blender-style). Bare
	# G/R/S are left free for single-letter tool switching (see canvas.gd
	# TOOL_SWITCH_KEYS) — explicit user request to cluster tool shortcuts
	# near the hand without colliding with bare G, which is already "toggle
	# gradient" (see below) and was left untouched.
	if shift_pressed and selected_shapes.size() > 0:
		match keycode:
			KEY_G:
				_start_key_mode(KeyMode.TRANSLATE)
				return true
			KEY_R:
				_start_key_mode(KeyMode.ROTATE)
				return true
			KEY_S:
				_start_key_mode(KeyMode.SCALE)
				return true

	if keycode == KEY_G and not shift_pressed:
		# Atajo estilo Affinity Designer / Illustrator: Activar/conmutar herramienta/modo degradado
		if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
			_toggle_gradient_mode()
			return true

	if (keycode in [KEY_X, KEY_DELETE, KEY_BACKSPACE]) and current_key_mode == KeyMode.NONE and not shift_pressed:
		if selected_shapes.size() > 0:
			delete_selected()
			return true
		return false

	if keycode == KEY_V:
		if is_gradient_mode:
			is_gradient_mode = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			if is_instance_valid(_bounding_box):
				_bounding_box.is_gradient_tool_active = false
				if _bounding_box.has_method("deactivate_gradient_mode"):
					_bounding_box.deactivate_gradient_mode()
				_bounding_box.queue_redraw()
			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true

	if keycode == KEY_ESCAPE:
		if is_gradient_mode:
			is_gradient_mode = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			if is_instance_valid(_bounding_box):
				_bounding_box.is_gradient_tool_active = false
				if _bounding_box.has_method("deactivate_gradient_mode"):
					_bounding_box.deactivate_gradient_mode()
				_bounding_box.queue_redraw()
			if is_instance_valid(canvas):
				canvas.queue_redraw()
			return true
		if current_key_mode != KeyMode.NONE:
			_cancel_key_transform()
			return true

	if selected_shapes.size() == 0:
		return false

	match keycode:
		KEY_X:
			if current_key_mode != KeyMode.NONE:
				current_axis = AxisLock.X if current_axis != AxisLock.X else AxisLock.NONE
				canvas.queue_redraw()
				return true
		KEY_Y:
			if current_key_mode != KeyMode.NONE:
				current_axis = AxisLock.Y if current_axis != AxisLock.Y else AxisLock.NONE
				canvas.queue_redraw()
				return true
	return false

func _toggle_gradient_mode() -> void:
	is_gradient_mode = !is_gradient_mode
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if is_gradient_mode else Input.CURSOR_ARROW)
	if is_gradient_mode:
		for s in selected_shapes:
			# Trazo de pincel: su render tiene el degradado 2D (dos puntos).
			if is_instance_valid(s) and s is Line2D:
				var rr = load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(s)
				if rr and not rr.has_gradient_fill():
					rr.ensure_default_gradient()
					if GlobalEvents.has_signal("object_style_changed"):
						GlobalEvents.object_style_changed.emit()
					if GlobalEvents.has_signal("gradient_changed"):
						GlobalEvents.gradient_changed.emit(rr.fill_gradient)
				continue
			if is_instance_valid(s) and s is VectorShape:
				if not s.has_gradient_fill():
					var g := Gradient.new()
					var base_col: Color = s.fill_color if s.fill_color.a > 0.0 else Color(0.2, 0.5, 0.9, 1.0)
					g.set_color(0, base_col)
					g.set_color(1, Color.WHITE if base_col.get_luminance() < 0.6 else Color(0.1, 0.1, 0.1, 1.0))
					s.fill_gradient = g
					s.set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
					s.queue_redraw()
					if GlobalEvents.has_signal("object_style_changed"):
						GlobalEvents.object_style_changed.emit()
					if GlobalEvents.has_signal("gradient_changed"):
						GlobalEvents.gradient_changed.emit(s.fill_gradient)
	if is_instance_valid(_bounding_box):
		_bounding_box.is_gradient_tool_active = is_gradient_mode
		if not is_gradient_mode and _bounding_box.has_method("deactivate_gradient_mode"):
			_bounding_box.deactivate_gradient_mode()
		_bounding_box.queue_redraw()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _on_colorcore_paint_changed(paint: Dictionary) -> void:
	if paint.get("type", "solid") == "solid":
		if is_gradient_mode:
			is_gradient_mode = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(_bounding_box):
			_bounding_box.is_gradient_tool_active = false
			if _bounding_box.has_method("deactivate_gradient_mode"):
				_bounding_box.deactivate_gradient_mode()
			else:
				_bounding_box.queue_redraw()
	else:
		# Si ya estamos en modo degradado (activado con la tecla G), redibujar para reflejar cambios de stops/color.
		# ¡NUNCA activar is_gradient_mode aquí! La selección de un objeto con degradado NO debe
		# conmutar la herramienta a degradado; debe permanecer en selección normal para que el usuario
		# pueda arrastrar y mover el elemento sobre su relleno con total libertad (estilo Figma/Illustrator).
		if is_instance_valid(_bounding_box) and is_gradient_mode:
			_bounding_box.queue_redraw()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _start_key_mode(mode: KeyMode) -> void:
	current_key_mode = mode
	current_axis = AxisLock.NONE
	transform_initial_mouse = canvas.get_global_mouse_position()
	transform_macro_rect = _get_macro_rect()
	initial_macro_center = transform_macro_rect.get_center()
	transform_initial_states.clear()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			transform_initial_states[shape] = _snapshot(shape)

func _confirm_key_transform() -> void:
	# G / S / R (modo por teclado) también son transformaciones reales → undo.
	var accion := "Transformar"
	match current_key_mode:
		KeyMode.TRANSLATE: accion = "Mover selección"
		KeyMode.SCALE: accion = "Redimensionar"
		KeyMode.ROTATE: accion = "Rotar"
	if not selected_shapes.is_empty():
		_commit_transform(accion, selected_shapes.duplicate(),
			current_key_mode != KeyMode.TRANSLATE)
	transform_initial_states.clear()
	_clear_key_transform()

func _cancel_key_transform() -> void:
	# Restaura el estado COMPLETO (posición/rotación/tamaño/vértices/…), no solo
	# posición+rotación+texto como antes — cancelar un escalado dejaba la figura
	# a medio transformar.
	for shape in selected_shapes:
		if is_instance_valid(shape) and transform_initial_states.has(shape):
			_restore_transform(shape, transform_initial_states[shape])
	_clear_key_transform()
	_update_bounding_box()
	canvas.queue_redraw()

func _clear_key_transform() -> void:
	current_key_mode = KeyMode.NONE
	current_axis = AxisLock.NONE
