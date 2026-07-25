# =============================================================================
# RUTA: res://script_gdscript/MoveTool.gd
# Vectopen — Selección y transformación general de figuras (Estilo Figma + Blender)
# Versión Pro Avanzada con soporte geométrico de precisión para vectores y texto.
# =============================================================================
class_name MoveTool
extends Tool

# ── Referencias ───────────────────────────────────────────────────────────────
var target_artboard: Node2D = null

# ── Selección ─────────────────────────────────────────────────────────────────
var selected_shapes: Array[Node2D] = []
var _bounding_box: Node = null  # Referencia al bounding box del pool

# ── Estado de arrastre de objetos ─────────────────────────────────────────────
var is_dragging_shape: bool = false

# ── Estado de transformación avanzada ─────────────────────────────────────────
var is_resizing: bool = false
var is_rotating: bool = false
var resize_handle: String = ""
var transform_initial_mouse: Vector2 = Vector2.ZERO
var transform_macro_rect: Rect2 = Rect2()
var transform_initial_states: Dictionary = {}
var initial_macro_center: Vector2 = Vector2.ZERO

# ── Estado marquee ─────────────────────────────────────────────────────────────
var is_marquee: bool = false
var marquee_start: Vector2 = Vector2.ZERO
var marquee_end: Vector2 = Vector2.ZERO

# ── Estado artboard ───────────────────────────────────────────────────────────
var is_dragging_artboard: bool = false
var is_resizing_artboard: bool = false
var artboard_resize_edge: Vector2 = Vector2.ZERO
var artboard_drag_start_mouse: Vector2 = Vector2.ZERO
var artboard_drag_start_pos: Vector2 = Vector2.ZERO

# ── Modos de Transformación Estilo Blender ────────────────────────────────────
enum BlenderMode { NONE, TRANSLATE, SCALE, ROTATE }
var current_blender_mode: BlenderMode = BlenderMode.NONE

enum AxisLock { NONE, X, Y }
var current_axis: AxisLock = AxisLock.NONE

# ── Constantes visuales profesionales ─────────────────────────────────────────
const HANDLE_SIZE: float = 8.0
const CLICK_TOLERANCE: float = 12.0
const ROTATE_ZONE: float = 18.0
const STALK_LENGTH: float = 24.0 
const MIN_LINE_PAD: float = 6.0

# Colores de alta fidelidad (Estilo Figma)
const COLOR_BBOX: Color = Color(0.05, 0.55, 0.91, 1.0)        # Azul Figma original
const COLOR_HANDLE_F: Color = Color(1.0, 1.0, 1.0, 1.0)      # Fondo tiradores
const COLOR_MARQUEE_F: Color = Color(0.05, 0.55, 0.91, 0.07)  # Relleno marquee
const COLOR_MARQUEE_S: Color = Color(0.05, 0.55, 0.91, 0.60)  # Contorno marquee

# ── Métodos del Ciclo de Vida ────────────────────────────────────────────────

func _init(p_canvas: Node2D) -> void:
	super(p_canvas)

func get_class_name() -> String:
	return "MoveTool"

func activate() -> void:
	# Actualizar estado del cursor inteligente
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
	
	_clear_blender_transform()
	_notificar_cambio_al_overlay()
	_acquire_bounding_box()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	_clear_selection()
	_clear_blender_transform()
	is_dragging_shape = false
	is_resizing = false
	is_rotating = false
	is_marquee = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	_release_bounding_box()
	_notificar_limpieza_al_overlay()
	
	# Restaurar estado del cursor
	if SmartCursor:
		SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)
	
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Entrada Principal ──────────────────────────────────────────────────────────

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	_refresh_artboard()
	if not target_artboard:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()

	# Atajos de Teclado Estilo Blender (G, S, R, X, Y, ESC)
	if event is InputEventKey and event.pressed:
		if _handle_blender_shortcuts(event.keycode):
			return true

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if current_blender_mode != BlenderMode.NONE:
				_confirm_blender_transform()
				return true
				
			if event.double_click:
				return _on_double_click(gm)
			return _on_press(gm)
		else:
			return _on_release(gm)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_blender_mode != BlenderMode.NONE:
			_cancel_blender_transform()
			return true

	if event is InputEventMouseMotion:
		return _on_motion(gm)

	return false

# ── LÓGICA DE ATAJO BLENDER (G, S, R, X, Y) ──────────────────────────────────

func _handle_blender_shortcuts(keycode: int) -> bool:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner()
	if focus_owner is TextEdit or focus_owner is LineEdit:
		return false

	if selected_shapes.size() == 0:
		return false

	match keycode:
		KEY_G:
			_start_blender_mode(BlenderMode.TRANSLATE)
			return true
		KEY_S:
			_start_blender_mode(BlenderMode.SCALE)
			return true
		KEY_R:
			_start_blender_mode(BlenderMode.ROTATE)
			return true
		KEY_X:
			if current_blender_mode != BlenderMode.NONE:
				current_axis = AxisLock.X if current_axis != AxisLock.X else AxisLock.NONE
				canvas.queue_redraw()
				return true
		KEY_Y:
			if current_blender_mode != BlenderMode.NONE:
				current_axis = AxisLock.Y if current_axis != AxisLock.Y else AxisLock.NONE
				canvas.queue_redraw()
				return true
		KEY_ESCAPE:
			if current_blender_mode != BlenderMode.NONE:
				_cancel_blender_transform()
				return true
	return false

func _start_blender_mode(mode: BlenderMode) -> void:
	current_blender_mode = mode
	current_axis = AxisLock.NONE
	transform_initial_mouse = canvas.get_global_mouse_position()
	transform_macro_rect = _get_macro_rect()
	initial_macro_center = transform_macro_rect.get_center()
	transform_initial_states.clear()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			transform_initial_states[shape] = _snapshot(shape)

func _confirm_blender_transform() -> void:
	_clear_blender_transform()

func _cancel_blender_transform() -> void:
	for shape in selected_shapes:
		if is_instance_valid(shape) and transform_initial_states.has(shape):
			var snap = transform_initial_states[shape]
			shape.global_position = snap["gpos"]
			_sync_doc_position_from_native(shape)
			if shape is VectorShape and snap.has("doc_rot"):
				shape.set_doc_rotation(snap["doc_rot"])
			else:
				shape.global_rotation = snap["grot"]
			if snap.has("w"):
				shape.set_meta("width", snap["w"])
				_update_text_node_sizes(shape, snap["w"], snap.get("h", 80.0))
			if snap.has("h") and shape.has_meta("height"):
				shape.set_meta("height", snap["h"])
	_clear_blender_transform()
	canvas.queue_redraw()

func _clear_blender_transform() -> void:
	current_blender_mode = BlenderMode.NONE
	current_axis = AxisLock.NONE

# ── LÓGICA DE DOBLE CLIC ──────────────────────────────────────────────────────

func _on_double_click(gm: Vector2) -> bool:
	var hit: Node2D = _shape_at(gm)
	# Usamos is_instance_valid para mayor seguridad de memoria en Godot 4
	if not is_instance_valid(hit) or not canvas.has_method("change_tool"): 
		return false
	
	if hit.has_meta("shape_type"):
		var type = hit.get_meta("shape_type")
		
		# 1. BLINDAJE PARA PÁRRAFOS DE TEXTO
		if type == "text_paragraph":
			_clear_selection()
			var script_para = load("res://script_gdscript/tools/ParagraphTool.gd")
			if script_para == null:
				push_error("Vectopen Error: No se pudo cargar 'ParagraphTool.gd'. Revisa su sintaxis interna o ruta.")
				return false
				
			var para_tool = script_para.new(canvas)
			canvas.change_tool(para_tool)
			
			var local_pos = target_artboard.to_local(gm)
			para_tool._check_and_trigger_edit_at(local_pos)
			return true
			
		# 2. BLINDAJE PARA TÍTULOS DE TEXTO
		elif type == "text_title":
			_clear_selection()
			var script_text = load("res://script_gdscript/tools/TextTool.gd")
			if script_text == null:
				push_error("Vectopen Error: No se pudo cargar 'TextTool.gd'. Revisa su sintaxis interna o ruta.")
				return false
				
			var title_tool = script_text.new(canvas)
			canvas.change_tool(title_tool)
			
			if title_tool.has_method("_check_and_trigger_edit_at"):
				var local_pos = target_artboard.to_local(gm)
				title_tool._check_and_trigger_edit_at(local_pos)
			return true
			
	# 3. BLINDAJE PARA EDICIÓN DE NODOS COLES (VECTORES Y CURVAS BEZIER)
	if hit is Path2D or hit is Line2D or hit is Polygon2D or hit.has_meta("curve") or hit.name.contains("Bezier"):
		_clear_selection()
		var script_nodes = load("res://script_gdscript/tools/NodeSelectionTool.gd")
		if script_nodes == null:
			push_error("Vectopen Error: No se pudo cargar 'NodeSelectionTool.gd'. Revisa su sintaxis interna o ruta.")
			return false
			
		var herramienta_nodos = script_nodes.new(canvas)
		if hit is Path2D:
			herramienta_nodos.edit_path = hit
		else:
			var parent = hit.get_parent()
			if parent is Path2D:
				herramienta_nodos.edit_path = parent
				
		canvas.change_tool(herramienta_nodos)
		return true
			
	return false

# ── Press ──────────────────────────────────────────────────────────────────────

func _on_press(gm: Vector2) -> bool:
	var ab_local: Vector2 = target_artboard.to_local(gm)
	var ab_rect: Rect2 = Rect2(Vector2.ZERO, target_artboard.artboard_size)

	if target_artboard.is_selected and target_artboard.is_on_handle(ab_local):
		var edge: Vector2 = target_artboard.get_resize_edge(ab_local)
		if edge != Vector2.ZERO:
			is_resizing_artboard = true
			artboard_resize_edge = edge
			return true

	# NOTA: El inicio de resize/rotate ya no se detecta aquí por hit-testing manual.
	# Lo dispara boundingbox.gd al pulsar uno de sus handles reales, vía start_handle_transform().

	var hit: Node2D = _shape_at(gm)
	if hit:
		if not selected_shapes.has(hit):
			if not Input.is_key_pressed(KEY_SHIFT):
				_clear_selection()
			_select(hit)
		
		is_dragging_shape = true
		transform_initial_mouse = gm
		transform_initial_states.clear()
		
		for s in selected_shapes:
			if is_instance_valid(s):
				transform_initial_states[s] = _snapshot(s)
		
		canvas.queue_redraw()
		return true

	if ab_rect.has_point(ab_local):
		_force_text_loss_focus()
		_clear_selection()
		if target_artboard.is_selected:
			is_dragging_artboard = true
			artboard_drag_start_mouse = gm
			artboard_drag_start_pos = target_artboard.global_position
			return true
		return false

	_force_text_loss_focus()
	# Shift/Alt mantienen la selección actual para sumar o restar con el marquee;
	# sin modificador, el marquee reemplaza la selección como antes.
	if not Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_ALT):
		_clear_selection()
	is_marquee = true
	marquee_start = gm
	marquee_end = gm
	canvas.queue_redraw()
	return true

# ── Release ────────────────────────────────────────────────────────────────────

func _on_release(_gm: Vector2) -> bool:
	if is_marquee:
		is_marquee = false
		_apply_marquee()

	is_dragging_shape = false
	is_resizing = false
	is_rotating = false
	is_dragging_artboard = false
	is_resizing_artboard = false
	resize_handle = ""
	artboard_resize_edge = Vector2.ZERO
	transform_initial_states.clear()

	canvas.queue_redraw()
	return true

# ── Motion ─────────────────────────────────────────────────────────────────────

func _on_motion(gm: Vector2) -> bool:
	if is_marquee:
		marquee_end = gm
		canvas.queue_redraw()
		return true

	if current_blender_mode != BlenderMode.NONE and selected_shapes.size() > 0:
		_process_blender_motion(gm)
		return true

	# Detectar elementos interactivos
	var interactive_element = false
	if selected_shapes.size() > 0 and not is_resizing and not is_rotating and not is_dragging_shape:
		var macro: Rect2 = _get_macro_rect()
		var h: String = _handle_at(macro, gm)
		_set_cursor(h)
		
		# Detectar si el cursor está sobre un handle
		interactive_element = h != ""
	
	# Actualizar estado del cursor inteligente
	if SmartCursor:
		if interactive_element:
			SmartCursor.set_interactive_element(true)
		else:
			SmartCursor.set_interactive_element(false)
			
			# Cambiar estado según el modo actual
			if is_resizing or is_rotating:
				SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
			elif selected_shapes.size() > 0:
				SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
			else:
				SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)

	if is_resizing and selected_shapes.size() > 0:
		_apply_resize(gm)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_rotating and selected_shapes.size() > 0:
		_apply_rotation(gm)
		_update_bounding_box()
		canvas.queue_redraw()
		return true

	if is_dragging_shape:
		var delta: Vector2 = gm - transform_initial_mouse
		if Input.is_key_pressed(KEY_SHIFT):
			if abs(delta.x) > abs(delta.y):
				delta.y = 0.0
			else:
				delta.x = 0.0

		for s in selected_shapes:
			if is_instance_valid(s) and transform_initial_states.has(s):
				var snap: Dictionary = transform_initial_states[s]
				var _skip = null
				var new_pos: Vector2 = snap["gpos"] + delta
				var st := Engine.get_main_loop() as SceneTree
				if st:
					var sm := st.root.get_node_or_null("SnapManager")
					if sm and sm.has_method("snap_position"):
						new_pos = sm.snap_position(new_pos)
				s.global_position = new_pos
				_sync_doc_position_from_native(s)
		_update_bounding_box()  # el bounding box debe seguir a las figuras mientras se arrastran
		canvas.queue_redraw()
		return true

	if is_resizing_artboard and is_instance_valid(target_artboard):
		target_artboard.call("_apply_resize", artboard_resize_edge, gm)
		return true

	if is_dragging_artboard and is_instance_valid(target_artboard):
		target_artboard.global_position = artboard_drag_start_pos + (gm - artboard_drag_start_mouse)
		return true

	return false

func _process_blender_motion(gm: Vector2) -> void:
	var delta: Vector2 = gm - transform_initial_mouse
	match current_blender_mode:
		BlenderMode.TRANSLATE:
			if current_axis == AxisLock.X:
				delta.y = 0.0
			elif current_axis == AxisLock.Y:
				delta.x = 0.0
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var new_pos: Vector2 = transform_initial_states[s]["gpos"] + delta
					var st := Engine.get_main_loop() as SceneTree
					if st:
						var sm := st.root.get_node_or_null("SnapManager")
						if sm and sm.has_method("snap_position"):
							new_pos = sm.snap_position(new_pos)
					s.global_position = new_pos
					_sync_doc_position_from_native(s)
			var factor_x: float = 1.0 + (delta.x / 200.0)
			var factor_y: float = 1.0 + (delta.y / 200.0)
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var snap = transform_initial_states[s]
					if s.has_meta("shape_type"):
						var nw = max(40.0, snap["w"] * (factor_x if current_axis != AxisLock.Y else 1.0))
						var nh = max(20.0, snap["h"] * (factor_y if current_axis != AxisLock.X else 1.0))
						s.set_meta("width", nw)
						s.set_meta("height", nh)
						_update_text_node_sizes(s, nw, nh)
					elif "width" in s and "height" in s:
						s.set("width", max(2.0, snap["w"] * factor_x))
						s.set("height", max(2.0, snap["h"] * factor_y))
					elif s is VectorShape and snap.has("doc_extent"):
						var orig_extent: DVec2 = snap["doc_extent"]
						var nx: float = max(2.0, orig_extent.x * (factor_x if current_axis != AxisLock.Y else 1.0))
						var ny: float = max(2.0, orig_extent.y * (factor_y if current_axis != AxisLock.X else 1.0))
						s.set_doc_extent(DVec2.new(nx, ny))

		BlenderMode.ROTATE:
			var angle_offset = delta.x * 0.01
			for s in selected_shapes:
				if is_instance_valid(s) and transform_initial_states.has(s):
					var snap = transform_initial_states[s]
					s.global_rotation = snap["grot"] + angle_offset

	_update_bounding_box()
	canvas.queue_redraw()

# ── Redimensionado Geométrico Avanzado de Vectores y Texto ────────────────────

func _apply_resize(gm: Vector2) -> void:
	var delta: Vector2 = gm - transform_initial_mouse
	var ow: float = transform_macro_rect.size.x
	var oh: float = transform_macro_rect.size.y
	if ow < 1.0: ow = 1.0
	if oh < 1.0: oh = 1.0

	var rect_pos: Vector2 = transform_macro_rect.position
	var rect_end: Vector2 = transform_macro_rect.end
	var rect_center: Vector2 = transform_macro_rect.get_center()

	var pivot: Vector2 = rect_center
	var sx: float = 1.0
	var sy: float = 1.0

	match resize_handle:
		"rc":
			sx = (ow + delta.x) / ow
			pivot = Vector2(rect_pos.x, rect_center.y)
		"lc":
			sx = (ow - delta.x) / ow
			pivot = Vector2(rect_end.x, rect_center.y)
		"bc":
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_center.x, rect_pos.y)
		"tc":
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_center.x, rect_end.y)
		"br":
			sx = (ow + delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = rect_pos
		"bl":
			sx = (ow - delta.x) / ow
			sy = (oh + delta.y) / oh
			pivot = Vector2(rect_end.x, rect_pos.y)
		"tr":
			sx = (ow + delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = Vector2(rect_pos.x, rect_end.y)
		"tl":
			sx = (ow - delta.x) / ow
			sy = (oh - delta.y) / oh
			pivot = rect_end

	if Input.is_key_pressed(KEY_ALT):
		pivot = rect_center
		if resize_handle in ["rc", "lc", "br", "bl", "tr", "tl"]:
			sx = (ow + (delta.x if resize_handle in ["rc", "br", "tr"] else -delta.x) * 2.0) / ow
		if resize_handle in ["bc", "tc", "br", "bl", "tr", "tl"]:
			sy = (oh + (delta.y if resize_handle in ["bc", "br", "bl"] else -delta.y) * 2.0) / oh

	if Input.is_key_pressed(KEY_SHIFT) and resize_handle not in ["rc", "lc", "bc", "tc"]:
		var uniform_scale: float = max(abs(sx), abs(sy))
		sx = uniform_scale * sign(sx)
		sy = uniform_scale * sign(sy)

	if abs(sx) < 0.01: sx = 0.01 * sign(sx)
	if abs(sy) < 0.01: sy = 0.01 * sign(sy)

	var scale_vec: Vector2 = Vector2(sx, sy)

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		if shape.has_meta("shape_type") and (shape.get_meta("shape_type") in ["text_paragraph", "text_title"]):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var calculated_width: float = max(40.0, snap["w"] * abs(sx))
			var calculated_height: float = max(20.0, snap["h"] * abs(sy))
			
			shape.set_meta("width", calculated_width)
			shape.set_meta("height", calculated_height)
			
			_update_text_node_sizes(shape, calculated_width, calculated_height)
			continue

		if shape is Path2D and snap.has("g_path_nodes"):
			var curve: Curve2D = shape.curve
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var data_nodes: Array = snap["g_path_nodes"]
			for i in range(curve.point_count):
				var node_data = data_nodes[i]
				var new_g_pos: Vector2 = pivot + (node_data["node"] - pivot) * scale_vec
				curve.set_point_position(i, shape.to_local(new_g_pos))
				
				var new_g_in: Vector2 = pivot + (node_data["in"] - pivot) * scale_vec
				var new_g_out: Vector2 = pivot + (node_data["out"] - pivot) * scale_vec
				
				curve.set_point_in(i, shape.to_local(new_g_in) - curve.get_point_position(i))
				curve.set_point_out(i, shape.to_local(new_g_out) - curve.get_point_position(i))
				
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = curve.get_baked_points()
			shape.queue_redraw()

		elif shape is Polygon2D and snap.has("g_poly_pts"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			
			var orig_g_poly: PackedVector2Array = snap["g_poly_pts"]
			var new_poly_pts = PackedVector2Array()
			for g_pt in orig_g_poly:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_poly_pts.append(shape.to_local(new_g_pt))
			shape.polygon = new_poly_pts
			
			if snap.has("g_stroke_pts"):
				var stroke = shape.get_node_or_null("Contorno_Stroke")
				if stroke is Line2D:
					var orig_g_stroke: PackedVector2Array = snap["g_stroke_pts"]
					var new_stroke_pts = PackedVector2Array()
					for g_pt in orig_g_stroke:
						var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
						new_stroke_pts.append(shape.to_local(new_g_pt))
					stroke.points = new_stroke_pts
			
			var l_min = new_poly_pts[0]
			var l_max = new_poly_pts[0]
			for p in new_poly_pts:
				l_min.x = min(l_min.x, p.x)
				l_min.y = min(l_min.y, p.y)
				l_max.x = max(l_max.x, p.x)
				l_max.y = max(l_max.y, p.y)
			shape.set_meta("size", l_max - l_min)
			shape.queue_redraw()

		elif snap.has("w") and snap.has("h") and not shape.has_meta("shape_type"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			shape.set("width", max(2.0, snap["w"] * abs(sx)))
			shape.set("height", max(2.0, snap["h"] * abs(sy)))
			shape.queue_redraw()

		elif snap.has("size"):
			var orig_gpos: Vector2 = snap["gpos"]
			shape.global_position = pivot + (orig_gpos - pivot) * scale_vec
			_sync_doc_position_from_native(shape)
			if shape is VectorShape and snap.has("doc_extent"):
				# Precisión doble real: el nuevo tamaño se calcula desde el valor
				# EXACTO capturado en _snapshot(), no desde el Vector2 float32 que
				# quedó guardado en .size tras el resize anterior — así el error
				# no se acumula operación tras operación.
				var orig_extent: DVec2 = snap["doc_extent"]
				var new_extent := DVec2.new(
					max(2.0, orig_extent.x * absf(sx)),
					max(2.0, orig_extent.y * absf(sy))
				)
				shape.set_doc_extent(new_extent)
			else:
				var new_size: Vector2 = Vector2(
					max(2.0, snap["size"].x * abs(sx)),
					max(2.0, snap["size"].y * abs(sy))
				)
				shape.set("size", new_size)
			shape.queue_redraw()

		elif snap.has("g_verts"):
			var orig_g_verts: PackedVector2Array = snap["g_verts"]
			var new_verts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_verts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_verts.append(shape.to_local(new_g_pt))
			if shape is VectorShape and shape.has_doc_vertices():
				shape.set_doc_vertices(DVec2.array_from_v2(new_verts))
			else:
				shape.set("vertices", new_verts)
			shape.queue_redraw()

		elif shape is Line2D and snap.has("g_pts"):
			var orig_g_pts: PackedVector2Array = snap["g_pts"]
			var new_pts: PackedVector2Array = PackedVector2Array()
			for g_pt in orig_g_pts:
				var new_g_pt: Vector2 = pivot + (g_pt - pivot) * scale_vec
				new_pts.append(shape.to_local(new_g_pt))
			shape.points = new_pts
			shape.queue_redraw()

func _update_text_node_sizes(shape: Node2D, w: float, h: float) -> void:
	var display_label: Label = shape.get_node_or_null("DisplayLabel")
	var multi_edit: Control = shape.get_node_or_null("MultiLineEdit")
	if not multi_edit: multi_edit = shape.get_node_or_null("LineEdit")
	
	if display_label:
		display_label.custom_minimum_size = Vector2(w, h)
		display_label.size = Vector2(w, h)
	if multi_edit:
		multi_edit.custom_minimum_size = Vector2(w, h)
		multi_edit.size = Vector2(w, h)

# ── Lógica de Rotación Pro ──────────────────────────────────────────────────

func _apply_rotation(gm: Vector2) -> void:
	var angle_current: float = initial_macro_center.angle_to_point(gm)
	var angle_initial: float = initial_macro_center.angle_to_point(transform_initial_mouse)
	var angle_delta: float = angle_current - angle_initial

	if Input.is_key_pressed(KEY_SHIFT):
		var snap_step: float = deg_to_rad(15.0)
		angle_delta = round(angle_delta / snap_step) * snap_step

	for shape in selected_shapes:
		if not is_instance_valid(shape) or not transform_initial_states.has(shape):
			continue
		var snap: Dictionary = transform_initial_states[shape]

		var orig_gpos: Vector2 = snap["gpos"]
		var offset: Vector2 = orig_gpos - initial_macro_center
		shape.global_position = initial_macro_center + offset.rotated(angle_delta)
		_sync_doc_position_from_native(shape)
		if shape is VectorShape and snap.has("doc_rot"):
			# Precisión doble real: el ángulo nuevo se acumula sobre el valor
			# EXACTO capturado en _snapshot(), no sobre el float32 que dejó
			# guardado la rotación anterior — evita que el error se acumule
			# rotación tras rotación (solo válido si el padre no está rotado,
			# caso habitual en este proyecto; ver nota de alcance del plan).
			shape.set_doc_rotation(snap["doc_rot"] + angle_delta)
		else:
			shape.global_rotation = snap["grot"] + angle_delta

		if shape is Path2D:
			var renderer = shape.get_node_or_null("Render_Visual")
			if renderer is Line2D:
				renderer.points = shape.curve.get_baked_points()
		shape.queue_redraw()

# ── Gestión de Selección Avanzada ──────────────────────────────────────────────

func _select(shape: Node2D) -> void:
	if not selected_shapes.has(shape):
		selected_shapes.append(shape)
	_update_macro_rect()          # ← esta línea faltaba
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _deselect(shape: Node2D) -> void:
	if selected_shapes.has(shape):
		selected_shapes.erase(shape)
		_update_macro_rect()
		if is_instance_valid(canvas):
			canvas.queue_redraw()

func _clear_selection() -> void:
	selected_shapes.clear()
	transform_initial_states.clear()
	_update_macro_rect()  # oculta el bounding box (selected_shapes ahora está vacío)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _force_text_loss_focus() -> void:
	var focus_owner = canvas.get_viewport().gui_get_focus_owner()
	if focus_owner and (focus_owner is TextEdit or focus_owner is LineEdit):
		focus_owner.release_focus()

func _apply_marquee() -> void:
	var mr: Rect2 = Rect2(marquee_start, marquee_end - marquee_start).abs()
	if not target_artboard:
		return

	# Alt resta del marquee (quita de la selección lo que toca el rectángulo);
	# sin Alt, suma (comportamiento normal / con Shift, ver _on_press).
	var subtract: bool = Input.is_key_pressed(KEY_ALT)

	var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if dl:
		for v_node in dl.get_children():
			if v_node is Node2D and mr.intersects(_global_rect(v_node)):
				if subtract:
					_deselect(v_node)
				else:
					_select(v_node)

	for node in target_artboard.get_children():
		if not (node is Node2D) or node.name in ["ArtboardTitle", "VectorDrawingLayer"]:
			continue
		if mr.intersects(_global_rect(node)):
			if subtract:
				_deselect(node)
			else:
				_select(node)

	canvas.queue_redraw()

# ── Motor de Hit-Testing e Intersección de Precisión Geométrica ───────────────

func _shape_at(gpos: Vector2) -> Node2D:
	if not target_artboard:
		return null

	var dl: Node = target_artboard.get_node_or_null("VectorDrawingLayer")
	if dl:
		var vector_nodes: Array = dl.get_children()
		for i in range(vector_nodes.size() - 1, -1, -1):
			var v_node = vector_nodes[i]
			if v_node is Node2D and _global_rect(v_node).has_point(gpos):
				return v_node

	var ab_nodes: Array = target_artboard.get_children()
	for i in range(ab_nodes.size() - 1, -1, -1):
		var node = ab_nodes[i]
		if not (node is Node2D) or node.name in ["ArtboardTitle", "VectorDrawingLayer"]:
			continue
		if _global_rect(node).has_point(gpos):
			return node

	return null

# ── Cálculo Dinámico del Bounding Box Pro (Soporte Títulos y Párrafos) ─────────

func _global_rect(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()

	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
		return Rect2(node.global_position, Vector2(w, h))

	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0:
			return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		
		var first_gpt: Vector2 = node.to_global(baked[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in baked:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
			
		var pad: float = MIN_LINE_PAD
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D:
			pad = max(pad, renderer.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)

	if node is Polygon2D:
		var poly = node as Polygon2D
		if poly.polygon.size() > 0:
			var first_gpt: Vector2 = poly.to_global(poly.polygon[0])
			var g_mn: Vector2 = first_gpt
			var g_mx: Vector2 = first_gpt
			for p in poly.polygon:
				var g_pt: Vector2 = poly.to_global(p)
				g_mn.x = min(g_mn.x, g_pt.x)
				g_mn.y = min(g_mn.y, g_pt.y)
				g_mx.x = max(g_mx.x, g_pt.x)
				g_mx.y = max(g_mx.y, g_pt.y)
			return Rect2(g_mn, g_mx - g_mn)

	if "size" in node and (node is VectorRectangle or node is VectorCircle):
		var s: Vector2 = node.get("size")
		return Rect2(node.global_position - s * 0.5, s)

	if "vertices" in node:
		var verts: PackedVector2Array = node.get("vertices")
		if verts.size() == 0:
			return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = node.to_global(verts[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in verts:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		return Rect2(g_mn, g_mx - g_mn)

	if "width" in node and "height" in node:
		var w: float = node.get("width")
		var h: float = node.get("height")
		var size_vec: Vector2 = Vector2(w, h)
		return Rect2(node.global_position - size_vec * 0.5, size_vec)

	if node is Line2D:
		var line: Line2D = node as Line2D
		if line.points.size() == 0:
			return Rect2(line.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = line.to_global(line.points[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in line.points:
			var g_pt: Vector2 = line.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = max(MIN_LINE_PAD, line.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)

	return Rect2(node.global_position - Vector2(20, 20), Vector2(40, 40))

func _get_macro_rect() -> Rect2:
	if selected_shapes.size() == 0: return Rect2()
	var valid_first_rect = false
	var r: Rect2 = Rect2()
	
	for shape in selected_shapes:
		if is_instance_valid(shape):
			if not valid_first_rect:
				r = _global_rect(shape)
				valid_first_rect = true
			else:
				r = r.merge(_global_rect(shape))
	return r

# ── Renderizado del Bounding Box Pro (Estilo Figma) ─────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	if is_marquee:
		var sl: Vector2 = c.to_local(marquee_start)
		var el: Vector2 = c.to_local(marquee_end)
		var r: Rect2 = Rect2(sl, el - sl)
		c.draw_rect(r, COLOR_MARQUEE_F, true)
		c.draw_rect(r, COLOR_MARQUEE_S, false, 1.0)
		return

	# NOTA: El recuadro principal + handles de resize/rotate ya no se dibujan aquí.
	# Los renderiza boundingbox.tscn (instancia real del pool), ver bounding_box.gd.
	if selected_shapes.size() > 1:
		var outline_width: float = clampf(0.8 / maxf(c.global_transform.get_scale().x, 0.001), 0.4, 2.0)
		for shape in selected_shapes:
			if is_instance_valid(shape):
				var s_rect: Rect2 = _global_rect(shape)
				var s_lrect: Rect2 = Rect2(c.to_local(s_rect.position), c.to_local(s_rect.end) - c.to_local(s_rect.position))
				c.draw_rect(s_lrect, Color(COLOR_BBOX.r, COLOR_BBOX.g, COLOR_BBOX.b, 0.3), false, outline_width)

# ── Snapshot Riguroso de Estructuras Complejas ────────────────────────────────

## Reescribe doc_position (doble precisión) desde la posición nativa (float32)
## tras cualquier escritura directa a shape.global_position en este archivo.
## No toca doc_rotation — cada punto de llamada que cambia rotación decide
## explícitamente si usa set_doc_rotation() (precisión doble real) o debe
## re-sincronizar desde el nativo (ver _apply_rotation/_cancel_blender_transform).
func _sync_doc_position_from_native(shape: Node2D) -> void:
	if shape is VectorShape:
		shape.doc_position = DVec2.from_v2(shape.position)

func _snapshot(shape: Node2D) -> Dictionary:
	var snap: Dictionary = {
		"gpos": shape.global_position,
		"grot": shape.global_rotation
	}

	# Captura en doble precisión para figuras VectorShape (Rectángulo/Círculo/
	# Polígono). No sustituye la captura "gpos"/"grot" de arriba (se sigue
	# usando para el resto de ramas/figuras), solo añade la fuente exacta que
	# usan las nuevas rutas de traslación/resize/rotación más abajo.
	if shape is VectorShape:
		snap["doc_pos"] = shape.get_doc_position()
		snap["doc_rot"] = shape.get_doc_rotation()
		if shape.has_doc_extent():
			snap["doc_extent"] = shape.get_doc_extent()

	if shape.has_meta("shape_type") and (shape.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		snap["w"] = shape.get_meta("width") if shape.has_meta("width") else 350.0
		snap["h"] = shape.get_meta("height") if shape.has_meta("height") else 65.0
		return snap
	
	if shape is Path2D:
		var curve: Curve2D = shape.curve
		var nodes_data = []
		for i in range(curve.point_count):
			var n_pos = curve.get_point_position(i)
			nodes_data.append({
				"node": shape.to_global(n_pos),
				"in": shape.to_global(n_pos + curve.get_point_in(i)),
				"out": shape.to_global(n_pos + curve.get_point_out(i))
			})
		snap["g_path_nodes"] = nodes_data
	
	elif shape is Polygon2D:
		var g_poly = PackedVector2Array()
		for p in shape.polygon:
			g_poly.append(shape.to_global(p))
		snap["g_poly_pts"] = g_poly
		
		var stroke = shape.get_node_or_null("Contorno_Stroke")
		if stroke is Line2D:
			var g_stroke = PackedVector2Array()
			for p in stroke.points:
				g_stroke.append(stroke.to_global(p))
			snap["g_stroke_pts"] = g_stroke
	
	elif "size" in shape and (shape is VectorRectangle or shape is VectorCircle):
		snap["size"] = shape.get("size")

	elif "vertices" in shape:
		var verts: PackedVector2Array = shape.get("vertices")
		var g_verts = PackedVector2Array()
		for v in verts:
			g_verts.append(shape.to_global(v))
		snap["g_verts"] = g_verts

	elif "width" in shape and "height" in shape:
		snap["w"] = shape.get("width")
		snap["h"] = shape.get("height")
		
	elif shape is Line2D:
		var g_pts = PackedVector2Array()
		for p in shape.points:
			g_pts.append(shape.to_global(p))
		snap["g_pts"] = g_pts
		
	return snap

func _refresh_artboard() -> void:
	var container: Node = canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

# ── Detección de Handles Basada en Tolerancia de Zoom ────────────────────────

func _handle_at(macro: Rect2, gm: Vector2) -> String:
	var transform_scale: float = canvas.global_transform.get_scale().x
	if transform_scale <= 0.001: transform_scale = 1.0

	var t: float = CLICK_TOLERANCE / transform_scale
	var r_zone: float = ROTATE_ZONE / transform_scale
	var stalk: float = STALK_LENGTH / transform_scale

	var center: Vector2 = macro.get_center()
	var cx: float = center.x
	var cy: float = center.y

	var pt_tl: Vector2 = macro.position
	var pt_tr: Vector2 = Vector2(macro.end.x, macro.position.y)
	var pt_bl: Vector2 = Vector2(macro.position.x, macro.end.y)
	var pt_br: Vector2 = macro.end
	var pt_tc: Vector2 = Vector2(cx, macro.position.y)
	var pt_bc: Vector2 = Vector2(cx, macro.end.y)
	var pt_lc: Vector2 = Vector2(macro.position.x, cy)
	var pt_rc: Vector2 = Vector2(macro.end.x, cy)
	var pt_rot: Vector2 = Vector2(cx, macro.position.y - stalk)

	if gm.distance_to(pt_rot) <= t: return "rot_handle"

	if gm.distance_to(pt_tl) <= r_zone and gm.distance_to(pt_tl) > t: return "rot_tl"
	if gm.distance_to(pt_tr) <= r_zone and gm.distance_to(pt_tr) > t: return "rot_tr"
	if gm.distance_to(pt_bl) <= r_zone and gm.distance_to(pt_bl) > t: return "rot_bl"
	if gm.distance_to(pt_br) <= r_zone and gm.distance_to(pt_br) > t: return "rot_br"

	if gm.distance_to(pt_tl) <= t: return "tl"
	if gm.distance_to(pt_tr) <= t: return "tr"
	if gm.distance_to(pt_bl) <= t: return "bl"
	if gm.distance_to(pt_br) <= t: return "br"
	if gm.distance_to(pt_tc) <= t: return "tc"
	if gm.distance_to(pt_bc) <= t: return "bc"
	if gm.distance_to(pt_lc) <= t: return "lc"
	if gm.distance_to(pt_rc) <= t: return "rc"

	return ""

func _set_cursor(h: String) -> void:
	if not SmartCursor:
		# Fallback al sistema tradicional si SmartCursor no está disponible
		if h.begins_with("rot"):
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			return

		match h:
			"tl", "br": Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
			"tr", "bl": Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)
			"lc", "rc": Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
			"tc", "bc": Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
			_: Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	
	# Usar SmartCursor para manejar los estados
	if h.begins_with("rot"):
		SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		return

	match h:
		"tl", "br": 
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"tr", "bl":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"lc", "rc":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		"tc", "bc":
			SmartCursor.set_state(CursorStateMachine.CursorState.PRECISION)
		_:
			if selected_shapes.size() > 0:
				SmartCursor.set_state(CursorStateMachine.CursorState.ACTIVE)
			else:
				SmartCursor.set_state(CursorStateMachine.CursorState.NEUTRAL)

func _notificar_cambio_al_overlay() -> void:
	if is_instance_valid(canvas) and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("movetool", self)

func _notificar_limpieza_al_overlay() -> void:
	if is_instance_valid(canvas) and is_instance_valid(canvas.artboards_container):
		if canvas.artboards_container.has_method("set_active_tool"):
			canvas.artboards_container.set_active_tool("other", null)

func _update_macro_rect() -> void:
	if selected_shapes.is_empty():
		transform_macro_rect = Rect2()
		if _bounding_box:
			_update_bounding_box()
		return

	# 1. Inicializar dimensiones con el primer elemento seleccionado
	var first_shape = selected_shapes[0]
	var rect: Rect2
	
	if first_shape.has_method("get_global_rect"):
		rect = first_shape.get_global_rect()
	elif "size" in first_shape:
		rect = Rect2(first_shape.global_position, first_shape.size)
	else:
		rect = Rect2(first_shape.global_position, Vector2(100, 100))

	var min_x = rect.position.x
	var min_y = rect.position.y
	var max_x = rect.position.x + rect.size.x
	var max_y = rect.position.y + rect.size.y

	# 2. Envolver el resto de figuras en caso de selección múltiple
	for i in range(1, selected_shapes.size()):
		var s = selected_shapes[i]
		if not is_instance_valid(s): 
			continue
			
		var r: Rect2
		if s.has_method("get_global_rect"):
			r = s.get_global_rect()
		elif "size" in s:
			r = Rect2(s.global_position, s.size)
		else:
			r = Rect2(s.global_position, Vector2(100, 100))
			
		min_x = min(min_x, r.position.x)
		min_y = min(min_y, r.position.y)
		max_x = max(max_x, r.position.x + r.size.x)
		max_y = max(max_y, r.position.y + r.size.y)

	# 3. Guardar estado macro vectorial puro
	transform_macro_rect = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	initial_macro_center = transform_macro_rect.position + transform_macro_rect.size / 2.0
	
	# Actualizar bounding box
	if _bounding_box:
		_update_bounding_box()


# ==========================================
# TRANSFORMACIÓN INICIADA DESDE LOS HANDLES REALES (boundingbox.tscn)
# ==========================================

func start_handle_transform(handle_code: String) -> bool:
	"""
	Llamado por bounding_box.gd cuando el usuario presiona uno de sus
	Panels de handle (resize o rotate). Reemplaza el hit-testing manual
	que antes hacía _on_press()/_handle_at().
	"""
	if selected_shapes.size() == 0:
		return false

	var gm: Vector2 = canvas.get_global_mouse_position()
	var macro: Rect2 = _get_macro_rect()

	if handle_code.begins_with("rot"):
		is_rotating = true
	else:
		is_resizing = true
	resize_handle = handle_code

	transform_initial_mouse = gm
	transform_macro_rect = macro
	initial_macro_center = macro.get_center()
	transform_initial_states.clear()

	for shape in selected_shapes:
		if is_instance_valid(shape):
			transform_initial_states[shape] = _snapshot(shape)

	canvas.queue_redraw()
	return true

# ==========================================
# POOLING DE OBJETOS
# ==========================================

func _acquire_bounding_box() -> void:
	"""
	Obtiene un bounding box del pool de objetos.
	"""
	if _bounding_box:
		return  # Ya tenemos uno
	
	if not ObjectPool:
		push_error("MoveTool: ObjectPool no disponible")
		return
	
	_bounding_box = ObjectPool.acquire("BoundingBox")
	if _bounding_box:
		# Configurar el bounding box
		if "set_target" in _bounding_box:
			_bounding_box.set_target(null)
		if "move_tool_reference" in _bounding_box:
			_bounding_box.move_tool_reference = self
		
		# Reparentear al canvas (el objeto está en Pool_BoundingBox)
		if is_instance_valid(canvas):
			_bounding_box.reparent(canvas)
			
		# Actualizar posición
		_update_bounding_box()
	else:
		push_warning("MoveTool: No se pudo obtener bounding box del pool")


func _release_bounding_box() -> void:
	"""
	Devuelve el bounding box al pool de objetos.
	"""
	if not _bounding_box:
		return
	
	if ObjectPool:
		ObjectPool.release("BoundingBox", _bounding_box)
		_bounding_box = null
	else:
		# Si no hay pool, destruir manualmente
		if is_instance_valid(_bounding_box):
			_bounding_box.queue_free()
		_bounding_box = null


func _update_bounding_box() -> void:
	"""
	Actualiza la posición y tamaño del bounding box.
	"""
	if not _bounding_box or not is_instance_valid(_bounding_box):
		return
	
	if selected_shapes.size() == 0:
		if "hide" in _bounding_box:
			_bounding_box.hide()
		return
	
	# Actualizar el bounding box
	if "_sincronizar_dimensiones_en_canvas" in _bounding_box:
		_bounding_box._sincronizar_dimensiones_en_canvas()
