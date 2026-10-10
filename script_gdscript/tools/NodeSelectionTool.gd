# =============================================================================
# RUTA: res://scripts/NodeSelectionTool.gd
# Vectopen — Edición Avanzada de Nodos Bézier, Inserción y Modo Grab (G)
# Sincronizado exactamente con el ecosistema de Artboards y BezierRenderPath
# =============================================================================
class_name NodeSelectionTool
extends ToolBase

# ── Estados Internos de la Herramienta ────────────────────────────────────────
enum EditMode { IDLE, DRAGGING_NODE, DRAGGING_HANDLE, DRAGGING_SEGMENT, GRAB_MODE, MARQUEE_SELECT }
var current_mode: EditMode = EditMode.IDLE

# ── Marquee / Lazo Selection ──────────────────────────────────────────────────
var marquee_start_local: Vector2 = Vector2.ZERO
var marquee_current_local: Vector2 = Vector2.ZERO
var marquee_start_canvas: Vector2 = Vector2.ZERO
var marquee_current_canvas: Vector2 = Vector2.ZERO

func get_class_name() -> String:
	return "NodeSelectionTool"

# ── Referencias del Ecosistema Vectopen ───────────────────────────────────────
var target_artboard: Node2D = null
var edit_path: Path2D = null 

# ── Selección y Hit-Testing ──────────────────────────────────────────────────
var selected_nodes: Array[int] = []
var selected_handle_type: String = "" # "", "in", "out"
var selected_handle_idx: int = -1

# ── Datos de Transformación Temporal (Espacio Local del Path para Evitar Saltos) ──
var transform_initial_mouse_local: Vector2 = Vector2.ZERO
var grab_axis: String = "" # "", "x", "y"
var grab_origin_mouse_local: Vector2 = Vector2.ZERO

# Estructuras de respaldo para transformaciones no destructivas
var snap_nodes_positions: Array[Vector2] = []
var snap_handles_in: Array[Vector2] = []
var snap_handles_out: Array[Vector2] = []

# Datos específicos para el arrastre/bombeo de segmentos directos
var seg_drag_idx: int = -1
var seg_drag_initial_pt: Vector2 = Vector2.ZERO
var hovered_segment_idx: int = -1
var hovered_segment_point: Vector2 = Vector2.ZERO
var hovered_segment_normal: Vector2 = Vector2.UP
var _pending_segment_press: bool = false
var _press_mouse_local: Vector2 = Vector2.ZERO

# ── Constantes de Precisión Visual ────────────────────────────────────────────
const NODE_RADIUS: float = 5.0
const HANDLE_RADIUS: float = 3.2
const CLICK_TOLERANCE: float = 10.0

const COLOR_NODE_FILL: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_NODE_STROKE: Color = Color(0.09, 0.37, 0.65, 1.0)
const COLOR_NODE_SELECTED: Color = Color(0.95, 0.20, 0.20, 1.0) # Rojo vivo pedido por el usuario
const COLOR_NODE_SELECTED_BORDER: Color = Color(0.45, 0.05, 0.05, 1.0)
const COLOR_TICK_BLUE: Color = Color(0.12, 0.55, 1.0, 1.0)
const COLOR_HANDLE_LINE: Color = Color(0.72, 0.46, 0.09, 0.5)   
const COLOR_GRAB_AXIS_X: Color = Color(0.94, 0.27, 0.27, 0.8)   
const COLOR_GRAB_AXIS_Y: Color = Color(0.13, 0.77, 0.37, 0.8)   

func activate() -> void:
	_refresh_artboard()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	current_mode = EditMode.IDLE
	grab_axis = ""

	# Auto-adquirir edit_path de SelectionManager si no está seteado
	if not is_instance_valid(edit_path):
		var sm = get_node_or_null("/root/SelectionManager")
		if is_instance_valid(sm) and sm.has_method("get_selected"):
			var sel = sm.get_selected()
			for obj in sel:
				if obj is Path2D and obj.curve is Curve2D:
					edit_path = obj
					break

	# Fallback: buscar en ArtboardsContainer / Canvas si no hay selección activa
	if not is_instance_valid(edit_path):
		var candidates: Array = []
		if is_instance_valid(canvas):
			var container := canvas.get_node_or_null("ArtboardsContainer")
			if is_instance_valid(container):
				_collect_paths(container, candidates)
			_collect_paths(canvas, candidates)
		if candidates.size() > 0:
			edit_path = candidates[candidates.size() - 1]
			var sm = get_node_or_null("/root/SelectionManager")
			if is_instance_valid(sm) and sm.has_method("set_selection"):
				sm.set_selection([edit_path])

	# Mostrar todos los nodos sin seleccionarlos todos a la vez (pedido explícito por el usuario)
	# Si ya venía con un nodo específico preseleccionado (ej. por doble clic), conservarlo.
	if selected_nodes.size() > 1 or not is_instance_valid(edit_path):
		selected_nodes.clear()

	if is_inside_tree():
		var ge = get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("request_bezier_panel"):
			ge.emit_safe("request_bezier_panel")

	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	current_mode = EditMode.IDLE
	selected_nodes.clear()
	grab_axis = ""
	hovered_segment_idx = -1
	_pending_segment_press = false
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _find_path_at_global(gm: Vector2) -> Path2D:
	if not is_instance_valid(canvas):
		return null
	var candidates: Array = []
	var container := canvas.get_node_or_null("ArtboardsContainer")
	if is_instance_valid(container):
		_collect_paths(container, candidates)
	_collect_paths(canvas, candidates)

	# 1. Prioridad: clic en el interior de polígono cerrado (de arriba a abajo en el árbol)
	for i in range(candidates.size() - 1, -1, -1):
		var p = candidates[i]
		if p is Path2D and p.curve is Curve2D and p.visible and p.is_visible_in_tree():
			var p_local: Vector2 = p.to_local(gm)
			var c: Curve2D = p.curve
			if c.point_count < 3:
				continue
			var is_closed: bool = p.closed if ("closed" in p) else (p.has_meta("is_closed") and bool(p.get_meta("is_closed")))
			if is_closed:
				var baked := c.get_baked_points()
				if baked.size() >= 3 and Geometry2D.is_point_in_polygon(p_local, baked):
					return p

	# 2. Clic cerca del contorno o puntos de la curva
	var found: Path2D = null
	var best_dist: float = 32.0
	for p in candidates:
		if p is Path2D and p.curve is Curve2D and p.visible and p.is_visible_in_tree():
			var p_local: Vector2 = p.to_local(gm)
			var c: Curve2D = p.curve
			if c.point_count == 0:
				continue
			var closest: Vector2 = c.get_closest_point(p_local)
			var dist_screen: float = p.to_global(closest).distance_to(gm)
			if dist_screen < best_dist:
				best_dist = dist_screen
				found = p
	return found

func _collect_paths(node: Node, out: Array) -> void:
	if node is Path2D and node.curve is Curve2D:
		out.append(node)
	for child in node.get_children():
		_collect_paths(child, out)

# ── Entrada de Eventos y Atajos de Teclado (Key Style) ───────────────────

func _get_event_gm(event: InputEvent) -> Vector2:
	if is_instance_valid(canvas) and ("position" in event):
		return canvas.get_canvas_transform().affine_inverse() * event.position
	elif is_instance_valid(canvas):
		return canvas.get_global_mouse_position()
	return Vector2.ZERO

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	var event_gm := _get_event_gm(event)

	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit_path := _find_path_at_global(event_gm)
				if is_instance_valid(hit_path):
					edit_path = hit_path
					selected_nodes.clear()
					var sm := get_node_or_null("/root/SelectionManager")
					if is_instance_valid(sm) and sm.has_method("set_selection"):
						sm.set_selection([edit_path])
					if is_instance_valid(canvas):
						canvas.queue_redraw()
					var hit_local_mouse := edit_path.to_local(event_gm)
					return _on_press(hit_local_mouse)
				else:
					current_mode = EditMode.MARQUEE_SELECT
					marquee_start_canvas = canvas.to_local(event_gm)
					marquee_current_canvas = marquee_start_canvas
					canvas.queue_redraw()
					return true
			else:
				if current_mode == EditMode.MARQUEE_SELECT:
					current_mode = EditMode.IDLE
					var m_min := Vector2(minf(marquee_start_canvas.x, marquee_current_canvas.x), minf(marquee_start_canvas.y, marquee_current_canvas.y))
					var m_sz := Vector2(absf(marquee_current_canvas.x - marquee_start_canvas.x), absf(marquee_current_canvas.y - marquee_start_canvas.y))
					var m_rect := Rect2(m_min, m_sz)
					if m_rect.size.length() > 5.0:
						var candidates: Array = []
						var container := canvas.get_node_or_null("ArtboardsContainer")
						if is_instance_valid(container):
							_collect_paths(container, candidates)
						_collect_paths(canvas, candidates)
						for p in candidates:
							if p is Path2D and p.curve is Curve2D and p.visible:
								var c_curve: Curve2D = p.curve
								var any_inside := false
								var hit_indices: Array[int] = []
								for i in range(c_curve.point_count):
									var pt_canvas = canvas.to_local(p.to_global(c_curve.get_point_position(i)))
									if m_rect.has_point(pt_canvas):
										any_inside = true
										hit_indices.append(i)
								if any_inside:
									edit_path = p
									selected_nodes = hit_indices
									var sm := get_node_or_null("/root/SelectionManager")
									if is_instance_valid(sm) and sm.has_method("set_selection"):
										sm.set_selection([edit_path])
									break
					else:
						# Clic simple en espacio vacío: saltar a MoveTool
						if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
							canvas.switch_tool("select")
							return true
					canvas.queue_redraw()
					return true
		elif event is InputEventMouseMotion:
			if current_mode == EditMode.MARQUEE_SELECT:
				marquee_current_canvas = canvas.to_local(event_gm)
				canvas.queue_redraw()
				return true
		return false

	# Ratón transformado al espacio local del Path de edición para un delta puro y libre de saltos
	var path_local_mouse := edit_path.to_local(event_gm)

	# 1. Procesamiento del Modo Grab (G) mediante teclado
	if current_mode == EditMode.GRAB_MODE:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_X:
					grab_axis = "" if grab_axis == "x" else "x"
					_apply_grab_logic(path_local_mouse)
					canvas.queue_redraw()
					return true
				KEY_Y:
					grab_axis = "" if grab_axis == "y" else "y"
					_apply_grab_logic(path_local_mouse)
					canvas.queue_redraw()
					return true
				KEY_ENTER, KEY_KP_ENTER:
					current_mode = EditMode.IDLE
					grab_axis = ""
					canvas.queue_redraw()
					return true
				KEY_ESCAPE:
					_cancel_grab_logic()
					current_mode = EditMode.IDLE
					grab_axis = ""
					canvas.queue_redraw()
					return true
		elif event is InputEventMouseMotion:
			_apply_grab_logic(path_local_mouse)
			return true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			current_mode = EditMode.IDLE
			grab_axis = ""
			canvas.queue_redraw()
			return true

	# 2. Atajos estándar fuera de Grab Mode
	if event is InputEventKey and event.pressed:
		if (event.keycode in [KEY_X, KEY_DELETE, KEY_BACKSPACE]) and not selected_nodes.is_empty():
			delete_selected_nodes()
			return true
		if event.keycode == KEY_G and not selected_nodes.is_empty():
			_start_grab_mode(path_local_mouse)
			return true
		if event.keycode == KEY_A:
			_toggle_select_all()
			return true
		if event.keycode == KEY_ESCAPE:
			var sm := get_node_or_null("/root/SelectionManager")
			if is_instance_valid(sm) and is_instance_valid(edit_path) and sm.has_method("set_selection"):
				sm.set_selection([edit_path])
			if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
				canvas.switch_tool("select")
				return true

	# 3. Ratón convencional: Clics y Doble Clic
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			return _on_double_click(path_local_mouse)
		elif event.pressed:
			return _on_press(path_local_mouse)
		else:
			return _on_release(path_local_mouse)

	if event is InputEventMouseMotion:
		return _on_motion(path_local_mouse)

	return false

# ── Lógica de Hit-Testing y Selección ─────────────────────────────────────────

func _on_press(path_local_mouse: Vector2) -> bool:
	var curve: Curve2D = edit_path.curve
	var vp := canvas.get_viewport() if is_instance_valid(canvas) else null
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var effective_scale: float = maxf(zoom * edit_path.global_scale.x, 0.0001)
	var tolerance: float = CLICK_TOLERANCE / effective_scale

	# Opción A: Probar Tiradores de TODOS los nodos con tiradores
	for idx in range(curve.point_count):
		var p_local = curve.get_point_position(idx)
		
		var h_in_local = p_local + curve.get_point_in(idx)
		var h_out_local = p_local + curve.get_point_out(idx)

		if curve.get_point_in(idx) != Vector2.ZERO and path_local_mouse.distance_to(h_in_local) <= tolerance:
			current_mode = EditMode.DRAGGING_HANDLE
			selected_handle_type = "in"
			selected_handle_idx = idx
			if idx not in selected_nodes:
				selected_nodes = [idx]
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			canvas.queue_redraw()
			return true
		if curve.get_point_out(idx) != Vector2.ZERO and path_local_mouse.distance_to(h_out_local) <= tolerance:
			current_mode = EditMode.DRAGGING_HANDLE
			selected_handle_type = "out"
			selected_handle_idx = idx
			if idx not in selected_nodes:
				selected_nodes = [idx]
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			canvas.queue_redraw()
			return true

	# Opción B: Probar Anclajes principales de los nodos
	for i in range(curve.point_count):
		var node_local = curve.get_point_position(i)
		if path_local_mouse.distance_to(node_local) <= tolerance:
			if Input.is_key_pressed(KEY_ALT):
				# Alt + arrastrar desde un nodo: extraer tiradores (curvar nodo inicial/final/intermedio)
				selected_nodes = [i]
				current_mode = EditMode.DRAGGING_HANDLE
				selected_handle_type = "out"
				selected_handle_idx = i
				transform_initial_mouse_local = path_local_mouse
				_save_snapshot()
				canvas.queue_redraw()
				return true

			if Input.is_key_pressed(KEY_SHIFT):
				if i in selected_nodes: selected_nodes.erase(i)
				else: selected_nodes.append(i)
			else:
				if not i in selected_nodes:
					selected_nodes = [i]
			
			current_mode = EditMode.DRAGGING_NODE
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			if is_inside_tree():
				var ge = get_node_or_null("/root/GlobalEvents")
				if ge and ge.has_signal("request_bezier_panel"):
					ge.emit_safe("request_bezier_panel")
			canvas.queue_redraw()
			return true

	# Opción C: Combar o insertar sobre segmento
	var closest_path_local = curve.get_closest_point(path_local_mouse)
	if path_local_mouse.distance_to(closest_path_local) <= tolerance * 1.5:
		var target_idx = _find_segment_index_by_point(closest_path_local)
		if target_idx != -1:
			_pending_segment_press = true
			_press_mouse_local = path_local_mouse
			seg_drag_idx = target_idx
			seg_drag_initial_pt = closest_path_local
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			return true

	# Opción D.0: Clic dentro del polígono relleno del edit_path actual
	var is_edit_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))
	if is_edit_closed and curve.point_count >= 3:
		var baked := curve.get_baked_points()
		if baked.size() >= 3 and Geometry2D.is_point_in_polygon(path_local_mouse, baked):
			if selected_nodes.is_empty():
				for j in range(curve.point_count):
					selected_nodes.append(j)
			canvas.queue_redraw()
			return true

	# Opción D: Si se pulsó sobre OTRO path, cambiar a ese path
	var mouse_global := edit_path.to_global(path_local_mouse)
	var other_path := _find_path_at_global(mouse_global)
	if is_instance_valid(other_path) and other_path != edit_path:
		edit_path = other_path
		selected_nodes.clear()
		var sm := get_node_or_null("/root/SelectionManager")
		if is_instance_valid(sm) and sm.has_method("set_selection"):
			sm.set_selection([edit_path])
		var new_local_mouse := edit_path.to_local(mouse_global)
		return _on_press(new_local_mouse)

	# Opción E: Clic en espacio vacío -> Iniciar selección por lazo/caja (Marquee)
	current_mode = EditMode.MARQUEE_SELECT
	marquee_start_local = path_local_mouse
	marquee_current_local = path_local_mouse
	marquee_start_canvas = canvas.to_local(edit_path.to_global(path_local_mouse)) if is_instance_valid(canvas) else path_local_mouse
	marquee_current_canvas = marquee_start_canvas
	if not Input.is_key_pressed(KEY_SHIFT):
		selected_nodes.clear()
	canvas.queue_redraw()
	return true

func _on_release(path_local_mouse: Vector2) -> bool:
	if current_mode == EditMode.MARQUEE_SELECT:
		marquee_current_local = path_local_mouse
		var min_x := minf(marquee_start_local.x, marquee_current_local.x)
		var min_y := minf(marquee_start_local.y, marquee_current_local.y)
		var max_x := maxf(marquee_start_local.x, marquee_current_local.x)
		var max_y := maxf(marquee_start_local.y, marquee_current_local.y)
		var rect := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		if rect.size.length() > 3.0:
			var found_in_current := false
			if is_instance_valid(edit_path) and edit_path.curve:
				var curve: Curve2D = edit_path.curve
				for i in range(curve.point_count):
					var pt := curve.get_point_position(i)
					if rect.has_point(pt):
						if not (i in selected_nodes):
							selected_nodes.append(i)
						found_in_current = true
			if not found_in_current:
				var m_min := Vector2(minf(marquee_start_canvas.x, marquee_current_canvas.x), minf(marquee_start_canvas.y, marquee_current_canvas.y))
				var m_sz := Vector2(absf(marquee_current_canvas.x - marquee_start_canvas.x), absf(marquee_current_canvas.y - marquee_start_canvas.y))
				var m_rect := Rect2(m_min, m_sz)
				var candidates: Array = []
				var container := canvas.get_node_or_null("ArtboardsContainer") if is_instance_valid(canvas) else null
				if is_instance_valid(container):
					_collect_paths(container, candidates)
				if is_instance_valid(canvas):
					_collect_paths(canvas, candidates)
				for p in candidates:
					if p is Path2D and p.curve is Curve2D and p.visible:
						var c_curve: Curve2D = p.curve
						var hit_indices: Array[int] = []
						for i in range(c_curve.point_count):
							var pt_canvas = canvas.to_local(p.to_global(c_curve.get_point_position(i)))
							if m_rect.has_point(pt_canvas):
								hit_indices.append(i)
						if not hit_indices.is_empty():
							edit_path = p
							selected_nodes = hit_indices
							var sm := get_node_or_null("/root/SelectionManager")
							if is_instance_valid(sm) and sm.has_method("set_selection"):
								sm.set_selection([edit_path])
							break
		else:
			# Clic simple en espacio vacío: saltar a MoveTool con el objeto seleccionado (comportamiento estándar de editores)
			current_mode = EditMode.IDLE
			selected_nodes.clear()
			var sm := get_node_or_null("/root/SelectionManager")
			if is_instance_valid(sm) and is_instance_valid(edit_path) and sm.has_method("set_selection"):
				sm.set_selection([edit_path])
			if is_instance_valid(canvas) and canvas.has_method("switch_tool"):
				canvas.switch_tool("select")
			return true

		current_mode = EditMode.IDLE
		if is_instance_valid(canvas):
			canvas.queue_redraw()
		return true

	if _pending_segment_press:
		_pending_segment_press = false
		if is_instance_valid(edit_path) and (edit_path.curve is Curve2D):
			var curve: Curve2D = edit_path.curve
			var ins_idx = seg_drag_idx + 1
			curve.add_point(seg_drag_initial_pt, Vector2.ZERO, Vector2.ZERO, ins_idx)
			var p_start = curve.get_point_position(seg_drag_idx)
			var p_end = curve.get_point_position((ins_idx + 1) % curve.point_count)
			var dist_total = p_start.distance_to(p_end)
			if dist_total > 0.1:
				var d_vector = (p_end - p_start).normalized() * (dist_total * 0.15)
				curve.set_point_in(ins_idx, -d_vector)
				curve.set_point_out(ins_idx, d_vector)
			selected_nodes = [ins_idx]
			_sync()
			current_mode = EditMode.IDLE
			seg_drag_idx = -1
			return true

	current_mode = EditMode.IDLE
	selected_handle_type = ""
	selected_handle_idx = -1
	seg_drag_idx = -1
	return true

# ── OPCIÓN 1: Doble Clic para Inserción Inteligente de Nodos ─────────────────

func _on_double_click(path_local_mouse: Vector2) -> bool:
	var curve: Curve2D = edit_path.curve
	var closest_path_local = curve.get_closest_point(path_local_mouse)

	if path_local_mouse.distance_to(closest_path_local) <= CLICK_TOLERANCE * 2.0:
		var seg_idx = _find_segment_index_by_point(closest_path_local)
		if seg_idx != -1:
			var p_start = curve.get_point_position(seg_idx)
			var p_end = curve.get_point_position((seg_idx + 1) % curve.point_count)
			
			curve.add_point(closest_path_local, Vector2.ZERO, Vector2.ZERO, seg_idx + 1)
			
			var dist_total = p_start.distance_to(p_end)
			if dist_total > 0.1:
				var d_vector = (p_end - p_start).normalized() * (dist_total * 0.15)
				curve.set_point_in(seg_idx + 1, -d_vector)
				curve.set_point_out(seg_idx + 1, d_vector)

			selected_nodes = [seg_idx + 1]
			_sync()
			return true
	return false

# ── Arrastre y Manipulación en Tiempo Real (Delta Homogéneo) ──────────────────

func _on_motion(path_local_mouse: Vector2) -> bool:
	if _pending_segment_press:
		if path_local_mouse.distance_to(_press_mouse_local) > 3.0:
			_pending_segment_press = false
			current_mode = EditMode.DRAGGING_SEGMENT
		else:
			return true

	if current_mode == EditMode.IDLE:
		_update_segment_hover(path_local_mouse)
		return false

	if current_mode == EditMode.MARQUEE_SELECT:
		marquee_current_local = path_local_mouse
		if is_instance_valid(canvas) and is_instance_valid(edit_path):
			marquee_current_canvas = canvas.to_local(edit_path.to_global(path_local_mouse))
			canvas.queue_redraw()
		return true

	var curve: Curve2D = edit_path.curve
	# Delta puro en espacio local del Path2D: Sin multiplicadores erróneos de matriz
	var path_delta: Vector2 = path_local_mouse - transform_initial_mouse_local

	match current_mode:
		EditMode.DRAGGING_NODE:
			for i in range(selected_nodes.size()):
				var idx = selected_nodes[i]
				curve.set_point_position(idx, snap_nodes_positions[idx] + path_delta)

		EditMode.DRAGGING_HANDLE:
			var idx = selected_handle_idx
			var initial_handle = snap_handles_in[idx] if selected_handle_type == "in" else snap_handles_out[idx]
			var current_handle_pos = initial_handle + path_delta

			if selected_handle_type == "in":
				curve.set_point_in(idx, current_handle_pos)
				if not Input.is_key_pressed(KEY_SHIFT):
					curve.set_point_out(idx, -current_handle_pos)
			else:
				curve.set_point_out(idx, current_handle_pos)
				if not Input.is_key_pressed(KEY_SHIFT):
					curve.set_point_in(idx, -current_handle_pos)

		EditMode.DRAGGING_SEGMENT:
			var idx_a = seg_drag_idx
			var idx_b = (seg_drag_idx + 1) % curve.point_count
			
			var p_a = curve.get_point_position(idx_a)
			var p_b = curve.get_point_position(idx_b)
			
			var base_out = snap_handles_out[idx_a]
			var base_in = snap_handles_in[idx_b]
			
			var len_total = p_a.distance_to(p_b)
			var t = 0.5 
			if len_total > 0.1:
				t = p_a.distance_to(seg_drag_initial_pt) / len_total
				t = clampf(t, 0.1, 0.9)
			
			var weight_a = (1.0 - t) * 0.75
			var weight_b = t * 0.75
			
			curve.set_point_out(idx_a, base_out + (path_delta * weight_a))
			curve.set_point_in(idx_b, base_in + (path_delta * weight_b))

	_sync()
	return true

# ── OPCIÓN 2: Modo Grab (G) con Restricciones de Sistema (Key Style) ──────

func _start_grab_mode(path_local_mouse: Vector2) -> void:
	current_mode = EditMode.GRAB_MODE
	grab_axis = ""
	grab_origin_mouse_local = path_local_mouse
	_save_snapshot()
	canvas.queue_redraw()

func _apply_grab_logic(path_local_mouse: Vector2) -> void:
	var curve: Curve2D = edit_path.curve
	var path_delta: Vector2 = path_local_mouse - grab_origin_mouse_local

	if grab_axis == "x": path_delta.y = 0
	if grab_axis == "y": path_delta.x = 0

	for i in range(selected_nodes.size()):
		var idx = selected_nodes[i]
		curve.set_point_position(idx, snap_nodes_positions[idx] + path_delta)

	_sync()

func _cancel_grab_logic() -> void:
	var curve: Curve2D = edit_path.curve
	for i in range(curve.point_count):
		curve.set_point_position(i, snap_nodes_positions[i])
		curve.set_point_in(i, snap_handles_in[i])
		curve.set_point_out(i, snap_handles_out[i])
	_sync()

# ── Helpers Geométricos y Sincronización Estricta ─────────────────────────────

func _save_snapshot() -> void:
	var curve: Curve2D = edit_path.curve
	snap_nodes_positions.resize(curve.point_count)
	snap_handles_in.resize(curve.point_count)
	snap_handles_out.resize(curve.point_count)
	
	# Usar mapeo indexado por posición absoluta en el array para evitar desalineaciones con múltiples nodos
	for idx in range(curve.point_count):
		snap_nodes_positions[idx] = curve.get_point_position(idx)
		snap_handles_in[idx] = curve.get_point_in(idx)
		snap_handles_out[idx] = curve.get_point_out(idx)

func _find_segment_index_by_point(path_local_pt: Vector2) -> int:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return -1
	var curve: Curve2D = edit_path.curve
	if curve.point_count < 2: return -1

	var is_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))
	var num_segs: int = curve.point_count if is_closed else curve.point_count - 1
	var best_idx: int = -1
	var min_dist: float = INF 

	for i in range(num_segs):
		for step in range(9):
			var t_val: float = float(step) / 8.0
			var pt := curve.sample(i, t_val)
			var d := path_local_pt.distance_to(pt)
			if d < min_dist:
				min_dist = d
				best_idx = i
	return best_idx

func _update_segment_hover(path_local_mouse: Vector2) -> void:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		if hovered_segment_idx != -1:
			hovered_segment_idx = -1
			if is_instance_valid(canvas):
				canvas.queue_redraw()
		return

	var curve: Curve2D = edit_path.curve
	if curve.point_count < 2:
		if hovered_segment_idx != -1:
			hovered_segment_idx = -1
			if is_instance_valid(canvas):
				canvas.queue_redraw()
		return

	var vp := canvas.get_viewport() if is_instance_valid(canvas) else null
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var effective_scale: float = maxf(zoom * edit_path.global_scale.x, 0.0001)
	var tolerance: float = (CLICK_TOLERANCE * 1.5) / effective_scale

	var closest_path_local: Vector2 = curve.get_closest_point(path_local_mouse)
	var dist: float = path_local_mouse.distance_to(closest_path_local)

	if dist <= tolerance:
		var is_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))
		var num_segs: int = curve.point_count if is_closed else curve.point_count - 1

		var best_idx: int = -1
		var best_t: float = 0.5
		var min_d: float = INF

		for i in range(num_segs):
			for step in range(11):
				var t_val: float = float(step) / 10.0
				var p_sample: Vector2 = curve.sample(i, t_val)
				var d_sample: float = path_local_mouse.distance_to(p_sample)
				if d_sample < min_d:
					min_d = d_sample
					best_idx = i
					best_t = t_val

		if best_idx != -1 and min_d <= tolerance * 1.2:
			var t_prev: float = maxf(best_t - 0.05, 0.0)
			var t_next: float = minf(best_t + 0.05, 1.0)
			var p_prev: Vector2 = curve.sample(best_idx, t_prev)
			var p_next: Vector2 = curve.sample(best_idx, t_next)
			var tangent: Vector2 = (p_next - p_prev).normalized()
			if tangent.length_squared() < 0.001:
				tangent = Vector2.RIGHT

			var normal: Vector2 = tangent.orthogonal().normalized()

			if hovered_segment_idx != best_idx or hovered_segment_point.distance_to(closest_path_local) > 0.5:
				hovered_segment_idx = best_idx
				hovered_segment_point = closest_path_local
				hovered_segment_normal = normal
				if is_instance_valid(canvas):
					canvas.queue_redraw()
			return

	if hovered_segment_idx != -1:
		hovered_segment_idx = -1
		if is_instance_valid(canvas):
			canvas.queue_redraw()

func _get_segment_highlight_color() -> Color:
	if is_instance_valid(edit_path):
		var col := Color.BLACK
		if "stroke_color" in edit_path and edit_path.stroke_color is Color:
			col = edit_path.stroke_color
		elif "fill_color" in edit_path and edit_path.fill_color is Color:
			col = edit_path.fill_color
		elif edit_path.has_meta("stroke_color"):
			col = edit_path.get_meta("stroke_color")
		elif edit_path.has_meta("fill_color"):
			col = edit_path.get_meta("fill_color")
		# Si el color del trazado o relleno es rojizo, usar azul celeste para contraste
		if col.r > 0.6 and col.g < 0.35 and col.b < 0.35:
			return Color(0.12, 0.55, 1.0, 1.0)
	return Color(0.95, 0.20, 0.20, 1.0)

func _toggle_select_all() -> void:
	var curve: Curve2D = edit_path.curve
	if selected_nodes.size() == curve.point_count:
		selected_nodes.clear()
	else:
		selected_nodes.clear()
		for i in range(curve.point_count):
			selected_nodes.append(i)
	canvas.queue_redraw()

func _sync() -> void:
	if is_instance_valid(edit_path):
		edit_path.queue_redraw()
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _refresh_artboard() -> void:
	if not is_instance_valid(canvas): return
	var container := canvas.get_node_or_null("ArtboardsContainer")
	if container and container.get_child_count() > 0:
		target_artboard = container.get_child(0)

# ── Operaciones Profesionales sobre Nodos y Curvas (Affinity / Illustrator) ───

func delete_selected_nodes() -> void:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return
	var curve: Curve2D = edit_path.curve
	if curve.point_count == 0 or selected_nodes.is_empty():
		return

	_save_snapshot()

	var to_remove = selected_nodes.duplicate()
	to_remove.sort()
	to_remove.reverse()

	for idx in to_remove:
		if idx >= 0 and idx < curve.point_count:
			curve.remove_point(idx)

	selected_nodes.clear()

	if curve.point_count < 3 and ("closed" in edit_path) and edit_path.closed:
		edit_path.closed = false

	if curve.point_count == 0:
		edit_path = null

	_sync()

func join_or_close_path() -> void:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return
	var curve: Curve2D = edit_path.curve
	if curve.point_count < 2:
		return

	_save_snapshot()
	if "closed" in edit_path:
		edit_path.closed = not edit_path.closed
	_sync()

func split_curve_at_selected() -> void:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return
	var curve: Curve2D = edit_path.curve
	if curve.point_count < 2:
		return

	_save_snapshot()

	var is_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))

	# Si hay un segmento sobrevolado activo, insertar un punto de división en ese segmento
	if hovered_segment_idx != -1 and hovered_segment_idx < (curve.point_count if is_closed else curve.point_count - 1):
		var ins_idx := hovered_segment_idx + 1
		curve.add_point(hovered_segment_point, Vector2.ZERO, Vector2.ZERO, ins_idx)
		selected_nodes = [ins_idx]
		hovered_segment_idx = -1

	if selected_nodes.is_empty():
		return

	var split_idx = selected_nodes[0]
	if is_closed:
		var new_curve := Curve2D.new()
		for i in range(curve.point_count):
			var idx = (split_idx + i) % curve.point_count
			new_curve.add_point(curve.get_point_position(idx), curve.get_point_in(idx), curve.get_point_out(idx))
		edit_path.curve = new_curve
		if "closed" in edit_path:
			edit_path.closed = false
		edit_path.set_meta("is_closed", false)
		selected_nodes = [0]
	elif curve.point_count >= 3 and split_idx > 0 and split_idx < curve.point_count - 1:
		var parent = edit_path.get_parent()
		if parent:
			var curve_b := Curve2D.new()
			for i in range(split_idx, curve.point_count):
				curve_b.add_point(curve.get_point_position(i), curve.get_point_in(i), curve.get_point_out(i))
			
			while curve.point_count > split_idx + 1:
				curve.remove_point(curve.point_count - 1)

			var new_p := Path2D.new()
			new_p.curve = curve_b
			if "closed" in edit_path:
				new_p.set("closed", false)
			if edit_path.get_script():
				new_p.set_script(edit_path.get_script())
			if "stroke_color" in edit_path:
				new_p.set("stroke_color", edit_path.get("stroke_color"))
			if "stroke_width" in edit_path:
				new_p.set("stroke_width", edit_path.get("stroke_width"))
			parent.add_child(new_p)
			new_p.global_transform = edit_path.global_transform
	_sync()

func set_selected_nodes_mode(mode: String) -> void:
	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return
	var curve: Curve2D = edit_path.curve
	if curve.point_count == 0 or selected_nodes.is_empty():
		return

	_save_snapshot()
	var n_pts = curve.point_count
	var is_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))

	for idx in selected_nodes:
		if idx < 0 or idx >= n_pts:
			continue

		var pos = curve.get_point_position(idx)
		var h_in = curve.get_point_in(idx)
		var h_out = curve.get_point_out(idx)

		var is_first: bool = (idx == 0) and not is_closed
		var is_last: bool = (idx == n_pts - 1) and not is_closed

		var prev_idx = (idx - 1 + n_pts) % n_pts
		var next_idx = (idx + 1) % n_pts
		var prev_pos = curve.get_point_position(prev_idx)
		var next_pos = curve.get_point_position(next_idx)

		var dir := Vector2.ZERO
		var base_len := 25.0

		if is_first:
			dir = (next_pos - pos).normalized()
			base_len = maxf((next_pos - pos).length() * 0.25, 10.0)
		elif is_last:
			dir = (pos - prev_pos).normalized()
			base_len = maxf((pos - prev_pos).length() * 0.25, 10.0)
		else:
			dir = (next_pos - prev_pos).normalized()
			base_len = maxf(((next_pos - pos).length() + (pos - prev_pos).length()) * 0.25, 10.0)

		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT

		match mode:
			"sharp":
				# Cúspide: tangentes independientes
				if is_first:
					var default_t = (next_pos - pos) * 0.2
					if default_t == Vector2.ZERO: default_t = Vector2(20, 0)
					curve.set_point_out(idx, default_t)
					curve.set_point_in(idx, -default_t)
				elif is_last:
					var default_t = (pos - prev_pos) * 0.2
					if default_t == Vector2.ZERO: default_t = Vector2(20, 0)
					curve.set_point_in(idx, -default_t)
					curve.set_point_out(idx, default_t)
				else:
					if h_in == Vector2.ZERO and h_out == Vector2.ZERO:
						var default_t = (next_pos - prev_pos) * 0.15
						if default_t == Vector2.ZERO: default_t = Vector2(20, 0)
						curve.set_point_in(idx, -default_t)
						curve.set_point_out(idx, default_t)
			"smooth":
				# Suave: tiradores en dirección opuesta (colineales), manteniendo magnitudes individuales
				var smooth_dir := dir
				if h_out != Vector2.ZERO and h_in != Vector2.ZERO:
					smooth_dir = (h_out - h_in).normalized()
				elif h_out != Vector2.ZERO:
					smooth_dir = h_out.normalized()
				elif h_in != Vector2.ZERO:
					smooth_dir = -h_in.normalized()

				var len_out = h_out.length() if h_out != Vector2.ZERO else base_len
				var len_in = h_in.length() if h_in != Vector2.ZERO else base_len
				curve.set_point_out(idx, smooth_dir * len_out)
				curve.set_point_in(idx, -smooth_dir * len_in)
			"symmetric":
				# Simétrico: tiradores opuestos y de idéntica longitud
				var sym_dir := dir
				var avg_len := base_len
				if h_out != Vector2.ZERO and h_in != Vector2.ZERO:
					sym_dir = (h_out - h_in).normalized()
					avg_len = (h_out.length() + h_in.length()) * 0.5
				elif h_out != Vector2.ZERO:
					sym_dir = h_out.normalized()
					avg_len = h_out.length()
				elif h_in != Vector2.ZERO:
					sym_dir = -h_in.normalized()
					avg_len = h_in.length()

				curve.set_point_out(idx, sym_dir * avg_len)
				curve.set_point_in(idx, -sym_dir * avg_len)
			"retract":
				# Retirar tiradores: convierte a vértice recto
				curve.set_point_in(idx, Vector2.ZERO)
				curve.set_point_out(idx, Vector2.ZERO)

	_sync()

# ── Renderizado Overlays en Pantalla ──────────────────────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c):
		return

	var vp := c.get_viewport()
	var zoom: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var inv: float = 1.0 / clampf(zoom, 0.0002, 100000.0)

	var base_h_radius: float = canvas.get_meta("bezier_handle_radius") if (is_instance_valid(canvas) and canvas.has_meta("bezier_handle_radius")) else HANDLE_RADIUS
	var r_node: float = maxf(NODE_RADIUS * inv, 3.5)
	var r_handle: float = maxf(base_h_radius * inv, 2.4)
	var thickness: float = maxf(1.5 * inv, 0.8)

	var force_all_handles: bool = bool(canvas.get_meta("bezier_show_all_handles")) if (is_instance_valid(canvas) and canvas.has_meta("bezier_show_all_handles")) else true

	# Marquee / Lazo selection box (visible siempre, incluso sin edit_path previo)
	if current_mode == EditMode.MARQUEE_SELECT:
		var m_min := Vector2(minf(marquee_start_canvas.x, marquee_current_canvas.x), minf(marquee_start_canvas.y, marquee_current_canvas.y))
		var m_sz := Vector2(absf(marquee_current_canvas.x - marquee_start_canvas.x), absf(marquee_current_canvas.y - marquee_start_canvas.y))
		var m_rect := Rect2(m_min, m_sz)
		c.draw_rect(m_rect, Color(0.12, 0.52, 0.95, 0.15), true)
		c.draw_rect(m_rect, Color(0.12, 0.52, 0.95, 0.9), false, thickness)

	if not is_instance_valid(edit_path) or not (edit_path.curve is Curve2D):
		return

	var curve: Curve2D = edit_path.curve

	# Dibujar líneas guía por teclado (Grab mode)
	if current_mode == EditMode.GRAB_MODE and grab_axis != "":
		var origin_canvas = c.to_local(edit_path.to_global(grab_origin_mouse_local))
		if grab_axis == "x":
			c.draw_line(Vector2(-10000, origin_canvas.y), Vector2(10000, origin_canvas.y), COLOR_GRAB_AXIS_X, thickness * 1.5)
		elif grab_axis == "y":
			c.draw_line(Vector2(origin_canvas.x, -10000), Vector2(origin_canvas.x, 10000), COLOR_GRAB_AXIS_Y, thickness * 1.5)

	# ── Resaltado de Segmento y Marca Azul Perpendicular (Tick Mark) ────────────
	if hovered_segment_idx >= 0 and is_instance_valid(edit_path) and (edit_path.curve is Curve2D):
		var is_closed: bool = edit_path.closed if ("closed" in edit_path) else (edit_path.has_meta("is_closed") and bool(edit_path.get_meta("is_closed")))
		var num_segs: int = curve.point_count if is_closed else curve.point_count - 1
		if hovered_segment_idx < num_segs:
			var hi_col: Color = _get_segment_highlight_color()
			var seg_pts: PackedVector2Array = PackedVector2Array()
			var num_samples := 24
			for s in range(num_samples + 1):
				var t_val := float(s) / float(num_samples)
				var pt_loc := curve.sample(hovered_segment_idx, t_val)
				seg_pts.append(c.to_local(edit_path.to_global(pt_loc)))
			if seg_pts.size() >= 2:
				c.draw_polyline(seg_pts, hi_col, maxf(thickness * 2.6, 2.2))

			# Marca perpendicular azul en la coordenada exacta del cursor sobre la curva
			var tick_canvas := c.to_local(edit_path.to_global(hovered_segment_point))
			var norm_world := edit_path.to_global(hovered_segment_point + hovered_segment_normal) - edit_path.to_global(hovered_segment_point)
			var norm_screen := norm_world.normalized()
			var tick_half_len: float = maxf(8.0 * inv, 7.0)
			var p_t1 := tick_canvas - norm_screen * tick_half_len
			var p_t2 := tick_canvas + norm_screen * tick_half_len
			c.draw_line(p_t1, p_t2, Color(0.0, 0.0, 0.0, 0.8), maxf(thickness * 3.0, 2.8))
			c.draw_line(p_t1, p_t2, COLOR_TICK_BLUE, maxf(thickness * 1.8, 1.6))
			c.draw_circle(tick_canvas, maxf(2.4 * inv, 2.0), COLOR_TICK_BLUE)

	# Nodos y Tiradores
	for i in range(curve.point_count):
		var p_local = curve.get_point_position(i)
		var p_canvas = c.to_local(edit_path.to_global(p_local))
		var is_selected = i in selected_nodes

		var h_in = curve.get_point_in(i)
		var h_out = curve.get_point_out(i)

		# Mostrar handles si el nodo está seleccionado O si force_all_handles está activo y la curva tiene tiradores
		var show_handles = is_selected or (force_all_handles and (h_in != Vector2.ZERO or h_out != Vector2.ZERO))

		if show_handles:
			var h_line_col = Color(0.12, 0.52, 0.95, 0.85) if is_selected else Color(0.12, 0.52, 0.95, 0.45)
			var h_stroke_col = Color(0.08, 0.44, 0.88, 1.0) if is_selected else Color(0.12, 0.52, 0.95, 0.7)

			if h_in != Vector2.ZERO:
				var h_in_canvas = c.to_local(edit_path.to_global(p_local + h_in))
				c.draw_line(p_canvas, h_in_canvas, h_line_col, thickness)
				c.draw_circle(h_in_canvas, r_handle, Color.WHITE)
				c.draw_arc(h_in_canvas, r_handle, 0.0, TAU, 20, h_stroke_col, thickness)

			if h_out != Vector2.ZERO:
				var h_out_canvas = c.to_local(edit_path.to_global(p_local + h_out))
				c.draw_line(p_canvas, h_out_canvas, h_line_col, thickness)
				c.draw_circle(h_out_canvas, r_handle, Color.WHITE)
				c.draw_arc(h_out_canvas, r_handle, 0.0, TAU, 20, h_stroke_col, thickness)

		# Dibujar puntos de anclaje (cuadrados estilo Illustrator/Figma) con halo de alto contraste
		var node_box = Rect2(p_canvas - Vector2(r_node, r_node), Vector2(r_node * 2.0, r_node * 2.0))
		c.draw_rect(node_box.grow(1.2 * inv), Color(0.0, 0.0, 0.0, 0.55), false, thickness)
		if is_selected:
			# Relleno rojo vivo para máxima visibilidad (pedido explícito por el usuario)
			c.draw_rect(node_box, COLOR_NODE_SELECTED, true)
			c.draw_rect(node_box, COLOR_NODE_SELECTED_BORDER, false, thickness)
		else:
			c.draw_rect(node_box, COLOR_NODE_FILL, true)
			c.draw_rect(node_box, COLOR_NODE_STROKE, false, thickness)
