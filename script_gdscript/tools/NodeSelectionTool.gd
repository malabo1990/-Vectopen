# =============================================================================
# RUTA: res://scripts/NodeSelectionTool.gd
# Vectopen — Edición Avanzada de Nodos Bézier, Inserción y Modo Grab (G)
# Sincronizado exactamente con el ecosistema de Artboards y BezierRenderPath
# =============================================================================
class_name NodeSelectionTool
extends ToolBase

# ── Estados Internos de la Herramienta ────────────────────────────────────────
enum EditMode { IDLE, DRAGGING_NODE, DRAGGING_HANDLE, DRAGGING_SEGMENT, GRAB_MODE }
var current_mode: EditMode = EditMode.IDLE

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

# ── Constantes de Precisión Visual ────────────────────────────────────────────
const NODE_RADIUS: float = 6.0
const HANDLE_RADIUS: float = 4.5
const CLICK_TOLERANCE: float = 10.0

const COLOR_NODE_FILL: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_NODE_STROKE: Color = Color(0.09, 0.37, 0.65, 1.0)
const COLOR_NODE_SELECTED: Color = Color(0.06, 0.43, 0.33, 1.0) 
const COLOR_HANDLE_LINE: Color = Color(0.72, 0.46, 0.09, 0.5)   
const COLOR_GRAB_AXIS_X: Color = Color(0.94, 0.27, 0.27, 0.8)   
const COLOR_GRAB_AXIS_Y: Color = Color(0.13, 0.77, 0.37, 0.8)   

func activate() -> void:
	_refresh_artboard()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	current_mode = EditMode.IDLE
	grab_axis = ""
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func deactivate() -> void:
	current_mode = EditMode.IDLE
	selected_nodes.clear()
	grab_axis = ""
	if is_instance_valid(canvas):
		canvas.queue_redraw()

# ── Entrada de Eventos y Atajos de Teclado (Blender Style) ───────────────────

func handle_input(event: InputEvent) -> bool:
	if "is_mouse_over_ui" in GlobalUI and GlobalUI.is_mouse_over_ui:
		return false

	if not is_instance_valid(target_artboard):
		_refresh_artboard()
	if not target_artboard or not is_instance_valid(edit_path):
		return false

	# Ratón transformado al espacio local del Path de edición para un delta puro y libre de saltos
	var path_local_mouse := edit_path.to_local(canvas.get_global_mouse_position())

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
		if event.keycode == KEY_G and not selected_nodes.is_empty():
			_start_grab_mode(path_local_mouse)
			return true
		if event.keycode == KEY_A:
			_toggle_select_all()
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
	var scale: float = canvas.global_transform.get_scale().x if is_instance_valid(canvas) else 1.0
	if scale <= 0.001: scale = 1.0
	var tolerance: float = CLICK_TOLERANCE / scale

	# Opción A: Probar Tiradores de nodos ya seleccionados
	for idx in selected_nodes:
		var p_local = curve.get_point_position(idx)
		
		var h_in_local = p_local + curve.get_point_in(idx)
		var h_out_local = p_local + curve.get_point_out(idx)

		if path_local_mouse.distance_to(h_in_local) <= tolerance:
			current_mode = EditMode.DRAGGING_HANDLE
			selected_handle_type = "in"
			selected_handle_idx = idx
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			return true
		if path_local_mouse.distance_to(h_out_local) <= tolerance:
			current_mode = EditMode.DRAGGING_HANDLE
			selected_handle_type = "out"
			selected_handle_idx = idx
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			return true

	# Opción B: Probar Anclajes principales de los nodos
	for i in range(curve.point_count):
		var node_local = curve.get_point_position(i)
		if path_local_mouse.distance_to(node_local) <= tolerance:
			if Input.is_key_pressed(KEY_SHIFT):
				if i in selected_nodes: selected_nodes.erase(i)
				else: selected_nodes.append(i)
			else:
				if not i in selected_nodes:
					selected_nodes = [i]
			
			current_mode = EditMode.DRAGGING_NODE
			transform_initial_mouse_local = path_local_mouse
			_save_snapshot()
			canvas.queue_redraw()
			return true

	# Opción C: Combar segmento directamente (Estilo Affinity / Adobe)
	var closest_path_local = curve.get_closest_point(path_local_mouse)
	if path_local_mouse.distance_to(closest_path_local) <= tolerance * 1.5:
		var target_idx = _find_segment_index_by_point(closest_path_local)
		if target_idx != -1:
			current_mode = EditMode.DRAGGING_SEGMENT
			seg_drag_idx = target_idx
			transform_initial_mouse_local = path_local_mouse
			seg_drag_initial_pt = closest_path_local
			_save_snapshot()
			return true

	# Limpieza si hace clic en el vacío sin Shift
	if not Input.is_key_pressed(KEY_SHIFT):
		selected_nodes.clear()
	canvas.queue_redraw()
	return false

func _on_release(_path_local_mouse: Vector2) -> bool:
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
	if current_mode == EditMode.IDLE:
		return false

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

# ── OPCIÓN 2: Modo Grab (G) con Restricciones de Sistema (Blender Style) ──────

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
	var curve: Curve2D = edit_path.curve
	if curve.point_count < 2: return -1
	
	var best_idx: int = -1
	var min_dist: float = INF 
	
	for i in range(curve.point_count - 1):
		var p_mid = (curve.get_point_position(i) + curve.get_point_position(i + 1)) * 0.5
		var d = path_local_pt.distance_to(p_mid)
		if d < min_dist:
			min_dist = d
			best_idx = i
	return best_idx

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

# ── Renderizado Overlays en Pantalla ──────────────────────────────────────────

func draw_preview(c: Node2D) -> void:
	if not is_instance_valid(c) or not is_instance_valid(target_artboard) or not is_instance_valid(edit_path):
		return

	var curve: Curve2D = edit_path.curve
	var scale: float = c.global_transform.get_scale().x
	if scale <= 0.001: scale = 1.0

	var r_node: float = NODE_RADIUS / scale
	var r_handle: float = HANDLE_RADIUS / scale
	var thickness: float = 1.2 / scale

	# Dibujar líneas guía estilo Blender
	if current_mode == EditMode.GRAB_MODE and grab_axis != "":
		var origin_canvas = c.to_local(edit_path.to_global(grab_origin_mouse_local))
		if grab_axis == "x":
			c.draw_line(Vector2(-10000, origin_canvas.y), Vector2(10000, origin_canvas.y), COLOR_GRAB_AXIS_X, thickness * 1.5)
		elif grab_axis == "y":
			c.draw_line(Vector2(origin_canvas.x, -10000), Vector2(origin_canvas.x, 10000), COLOR_GRAB_AXIS_Y, thickness * 1.5)

	# Nodos y Tiradores
	for i in range(curve.point_count):
		var p_local = curve.get_point_position(i)
		var p_canvas = c.to_local(edit_path.to_global(p_local))
		var is_selected = i in selected_nodes

		if is_selected:
			var h_in_canvas = c.to_local(edit_path.to_global(p_local + curve.get_point_in(i)))
			var h_out_canvas = c.to_local(edit_path.to_global(p_local + curve.get_point_out(i)))

			if curve.get_point_in(i) != Vector2.ZERO:
				c.draw_line(p_canvas, h_in_canvas, COLOR_HANDLE_LINE, thickness)
				c.draw_circle(h_in_canvas, r_handle, COLOR_NODE_STROKE)
			if curve.get_point_out(i) != Vector2.ZERO:
				c.draw_line(p_canvas, h_out_canvas, COLOR_HANDLE_LINE, thickness)
				c.draw_circle(h_out_canvas, r_handle, COLOR_NODE_STROKE)

			c.draw_circle(p_canvas, r_node, COLOR_NODE_SELECTED)
		else:
			c.draw_circle(p_canvas, r_node, COLOR_NODE_STROKE)
			c.draw_circle(p_canvas, r_node * 0.7, COLOR_NODE_FILL)
