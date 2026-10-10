# =============================================================================
# RUTA: res://script_gdscript/tools/move/move_tool_3d.gd
# Modo edición 3D: órbita, zoom con rueda y arrastre con botón central sobre
# modelos 3D.
# Parte de la herramienta Mover (MoveTool), dividida por capas de herencia:
#   move_tool_core → transform → ops → threading → keyboard → 3d → draw → MoveTool
# El código se movió TAL CUAL desde MoveTool.gd (sin cambios de comportamiento).
# =============================================================================
extends "res://script_gdscript/tools/move/move_tool_keyboard.gd"


func _enter_3d_mode(model: Node2D) -> void:
	if is_instance_valid(active_3d_model) and active_3d_model != model:
		_exit_3d_mode()
	if not selected_shapes.has(model):
		_clear_selection()
		_select(model)
	active_3d_model = model
	if active_3d_model.has_method("set_3d_editing"):
		active_3d_model.set_3d_editing(true)
	if is_instance_valid(canvas) and canvas.has_method("pause_canvas_zoom"):
		canvas.pause_canvas_zoom(true)
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func is_3d_focused(gm: Vector2 = Vector2.INF) -> bool:
	if is_instance_valid(active_3d_model) or is_middle_dragging_3d or _is_dragging_3d:
		return true
	if gm == Vector2.INF:
		if is_instance_valid(canvas):
			gm = canvas.get_global_mouse_position()
		else:
			return false
	if selected_shapes.size() == 1 and is_instance_valid(selected_shapes[0]) and selected_shapes[0].has_method("zoom_camera"):
		var s: Node2D = selected_shapes[0]
		if _node_contains_point(s, gm) or _global_rect(s).grow(24.0).has_point(gm):
			return true
	var hit: Node2D = _shape_at(gm)
	if is_instance_valid(hit) and hit.has_method("zoom_camera"):
		return true
	return false

func handle_middle_click_3d(event: InputEventMouseButton, gm: Vector2) -> bool:
	if event.pressed:
		var target: Node2D = null
		if is_instance_valid(active_3d_model):
			target = active_3d_model
		elif selected_shapes.size() == 1 and is_instance_valid(selected_shapes[0]) and selected_shapes[0].has_method("rotate_orbit"):
			if _node_contains_point(selected_shapes[0], gm) or _global_rect(selected_shapes[0]).grow(24.0).has_point(gm):
				target = selected_shapes[0]
		
		if not is_instance_valid(target):
			var hit: Node2D = _shape_at(gm)
			if is_instance_valid(hit) and hit.has_method("rotate_orbit"):
				target = hit

		if is_instance_valid(target):
			if not selected_shapes.has(target):
				_clear_selection()
				_select(target)
			is_middle_dragging_3d = true
			_mmb_3d_target = target
			_last_mmb_3d_pos = gm
			if is_instance_valid(canvas) and canvas.has_method("pause_canvas_zoom"):
				canvas.pause_canvas_zoom(true)
			if target.has_method("begin_interactive_orbit"):
				target.begin_interactive_orbit()
			Input.set_default_cursor_shape(Input.CURSOR_MOVE)
			return true
		return false
	else:
		if is_middle_dragging_3d:
			end_middle_drag_3d()
			return true
		return false

func handle_middle_motion_3d(gm: Vector2) -> bool:
	if not is_middle_dragging_3d or not is_instance_valid(_mmb_3d_target):
		return false
	var delta: Vector2 = gm - _last_mmb_3d_pos
	_last_mmb_3d_pos = gm
	if _mmb_3d_target.has_method("rotate_orbit"):
		_mmb_3d_target.rotate_orbit(delta.x, delta.y)
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	return true

func handle_wheel_3d(event: InputEventMouseButton, gm: Vector2) -> bool:
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return false
	# Consumir el evento de soltar la rueda para evitar que canvas zoom se dispare
	if not event.pressed:
		return is_3d_focused(gm)

	var target: Node2D = null
	if is_instance_valid(active_3d_model):
		target = active_3d_model
	elif selected_shapes.size() == 1 and is_instance_valid(selected_shapes[0]) and selected_shapes[0].has_method("zoom_camera"):
		var s: Node2D = selected_shapes[0]
		if _node_contains_point(s, gm) or _global_rect(s).grow(24.0).has_point(gm):
			target = s
	
	if not is_instance_valid(target):
		var hit: Node2D = _shape_at(gm)
		if is_instance_valid(hit) and hit.has_method("zoom_camera"):
			target = hit

	if is_instance_valid(target):
		var dir: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		target.zoom_camera(dir)
		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return true
	return false
