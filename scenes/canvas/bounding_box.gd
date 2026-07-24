# =============================================================================
# RUTA: res://scenes/canvas/bounding_box.gd
# Sincronización Espacial de Precisión con Vinculación por Inspector (@export)
# =============================================================================
extends Control
class_name BoundingBox

@export_group("Referencias de Interfaz")
## Arrastra aquí el panel central o el contenedor que recibirá el arrastre (Drag)
@export var drag_panel: Control
## Arrastra aquí el nodo raíz de la escena (CanvasRoot) para una comunicación directa de alto rendimiento
@export var canvas_root: Node2D

var move_tool_reference: MoveTool = null
var target_node: Node2D = null # SOLUCIÓN AL CRASH: Satisface la verificación del controlador externo
var _is_dragging_canvas_area: bool = false
var _pool_initialized: bool = false

signal bounding_box_ready

# Mapeo Panel de handle → código usado por MoveTool (_apply_resize/_apply_rotation)
const _HANDLE_CODES := {
	"handle_IA": "tl", "handle_DA": "tr", "handle_IB": "bl", "handle_DB": "br",
	"handle_MA": "tc", "MB": "bc", "handle_IM": "lc", "handle_DM": "rc",
	"Rotation": "rot_handle",
}

# ── Compensación de zoom: los handles deben verse igual sin importar el zoom ──
const _ZOOM_SIZE_FACTOR_MIN: float = 0.45  # no encoger más allá de esto (zoom muy cercano)
const _ZOOM_SIZE_FACTOR_MAX: float = 2.2   # no agrandar más allá de esto (zoom muy alejado)
var _handle_base_rects: Dictionary = {}    # nombre de nodo → Rect2 de offsets originales (a zoom 1.0)
var _candle_base_rect: Rect2 = Rect2()
var _last_zoom_scale: float = -1.0
var _outline_style: StyleBoxFlat = null    # copia única por instancia (no la compartida del .tscn)
var _outline_base_border_width: float = 1.0
const _BORDER_WIDTH_MIN: float = 1.0
const _BORDER_WIDTH_MAX: float = 3.0

func _ready() -> void:
	# Permitir que los eventos de ratón fluyan libremente a través de las capas de control
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Conexión limpia usando la referencia del Inspector elegida por ti
	if is_instance_valid(drag_panel):
		drag_panel.gui_input.connect(_on_drag_panel_gui_input)

	# Conectar señales para actualización eficiente
	_connect_signals()
	_connect_handle_signals()
	_capture_base_handle_geometry()
	_apply_zoom_compensation()
	_update_axis_lock_indicators()

	# Notificar que el objeto está listo para ser usado
	bounding_box_ready.emit()
	_pool_initialized = true

## Guarda el tamaño/posición "de diseño" (a zoom 1.0) de cada handle y del "candle"
## (el tallo del handle de rotación), para poder recalcularlos proporcionalmente al zoom.
func _capture_base_handle_geometry() -> void:
	if not _handle_base_rects.is_empty():
		return  # ya capturado (instancia reciclada del pool)
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for handle_name in _HANDLE_CODES:
		var p := panel_interactivo.get_node_or_null(handle_name)
		if is_instance_valid(p):
			_handle_base_rects[handle_name] = Rect2(
				p.offset_left, p.offset_top,
				p.offset_right - p.offset_left, p.offset_bottom - p.offset_top
			)
	var candle := panel_interactivo.get_node_or_null("candle")
	if is_instance_valid(candle):
		_candle_base_rect = Rect2(
			candle.offset_left, candle.offset_top,
			candle.offset_right - candle.offset_left, candle.offset_bottom - candle.offset_top
		)

	# El StyleBox del contorno viene compartido (SubResource) entre todas las instancias
	# del pool; lo duplicamos para poder ajustar el grosor del borde solo en esta instancia.
	var current_style: StyleBox = panel_interactivo.get_theme_stylebox("panel")
	if current_style is StyleBoxFlat:
		_outline_base_border_width = current_style.border_width_left
		_outline_style = current_style.duplicate()
		panel_interactivo.add_theme_stylebox_override("panel", _outline_style)

func _get_zoom_scale() -> float:
	# Los handles son hijos de esta caja: si la caja tiene su propia escala
	# (porque copia la escala de la figura seleccionada, ver _sincronizar_dimensiones_en_canvas),
	# esa escala también agranda/achica los handles, así que hay que compensar el total:
	# zoom de cámara × escala propia de la caja.
	var total: float = 1.0
	if is_instance_valid(move_tool_reference) and is_instance_valid(move_tool_reference.canvas):
		var cam_s: float = move_tool_reference.canvas.global_transform.get_scale().x
		if cam_s > 0.001:
			total *= cam_s
	var own_s: float = absf(scale.x)
	if own_s > 0.001:
		total *= own_s
	return total

## Recalcula el tamaño local de cada handle (y del tallo del handle de rotación)
## para que su tamaño EN PANTALLA se mantenga constante sin importar el zoom del canvas.
func _apply_zoom_compensation() -> void:
	if _handle_base_rects.is_empty():
		return
	var zoom: float = _get_zoom_scale()
	if is_equal_approx(zoom, _last_zoom_scale):
		return
	_last_zoom_scale = zoom
	var f: float = clampf(1.0 / zoom, _ZOOM_SIZE_FACTOR_MIN, _ZOOM_SIZE_FACTOR_MAX)

	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return

	for handle_name in _handle_base_rects:
		var p := panel_interactivo.get_node_or_null(handle_name)
		if not is_instance_valid(p):
			continue
		var base: Rect2 = _handle_base_rects[handle_name]
		var center: Vector2 = base.position + base.size * 0.5
		var new_half: Vector2 = base.size * 0.5 * f
		p.offset_left = center.x - new_half.x
		p.offset_top = center.y - new_half.y
		p.offset_right = center.x + new_half.x
		p.offset_bottom = center.y + new_half.y

	if _candle_base_rect.size != Vector2.ZERO:
		var candle := panel_interactivo.get_node_or_null("candle")
		if is_instance_valid(candle):
			# El extremo inferior queda pegado al borde de la caja (no escala);
			# solo el largo hacia arriba y el ancho se compensan con el zoom.
			var half_w: float = (_candle_base_rect.size.x * 0.5) * f
			var cx: float = _candle_base_rect.position.x + _candle_base_rect.size.x * 0.5
			candle.offset_left = cx - half_w
			candle.offset_right = cx + half_w
			candle.offset_top = _candle_base_rect.position.y * f
			candle.offset_bottom = _candle_base_rect.end.y

	if is_instance_valid(_outline_style):
		var border: float = clampf(_outline_base_border_width * f, _BORDER_WIDTH_MIN, _BORDER_WIDTH_MAX)
		var border_px: int = roundi(border)
		_outline_style.border_width_left = border_px
		_outline_style.border_width_top = border_px
		_outline_style.border_width_right = border_px
		_outline_style.border_width_bottom = border_px

func _process(_delta: float) -> void:
	if not visible:
		return
	_apply_zoom_compensation()
	_update_axis_lock_indicators()

## Muestra el indicador rojo "x" o verde "Y" cuando el usuario está trasladando
## con el eje bloqueado (atajo Blender G + X / G + Y), oculta ambos en cualquier otro caso.
func _update_axis_lock_indicators() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	var x_panel := panel_interactivo.get_node_or_null("x")
	var y_panel := panel_interactivo.get_node_or_null("Y")

	var show_x := false
	var show_y := false
	if is_instance_valid(move_tool_reference) and move_tool_reference.current_blender_mode == MoveTool.BlenderMode.TRANSLATE:
		show_x = move_tool_reference.current_axis == MoveTool.AxisLock.X
		show_y = move_tool_reference.current_axis == MoveTool.AxisLock.Y

	if is_instance_valid(x_panel) and x_panel.visible != show_x:
		x_panel.visible = show_x
	if is_instance_valid(y_panel) and y_panel.visible != show_y:
		y_panel.visible = show_y

## Conecta cada Panel de handle (resize + rotación) para que dispare la
## transformación real en MoveTool, en vez de depender de su hit-testing manual.
func _connect_handle_signals() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for handle_name in _HANDLE_CODES:
		var handle_panel := panel_interactivo.get_node_or_null(handle_name)
		if is_instance_valid(handle_panel):
			var handle_code: String = _HANDLE_CODES[handle_name]
			var bound_callable := _on_handle_gui_input.bind(handle_code)
			if not handle_panel.gui_input.is_connected(bound_callable):
				handle_panel.gui_input.connect(bound_callable)

func _on_handle_gui_input(event: InputEvent, handle_code: String) -> void:
	if not is_instance_valid(move_tool_reference):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_tool_reference.start_handle_transform(handle_code)
		elif move_tool_reference.resize_handle == handle_code:
			move_tool_reference._on_release(Vector2.ZERO)
	elif event is InputEventMouseMotion:
		if move_tool_reference.resize_handle == handle_code and (move_tool_reference.is_resizing or move_tool_reference.is_rotating):
			move_tool_reference._on_motion(move_tool_reference.canvas.get_global_mouse_position())

## Método requerido por el controlador para inyectar objetivos individuales
func set_target(new_target: Node2D) -> void:
	target_node = new_target

func _sincronizar_dimensiones_en_canvas() -> void:
	# Agrupamos los elementos a calcular según el flujo de origen
	var shapes_to_calculate: Array[Node2D] = []
	if is_instance_valid(move_tool_reference) and not move_tool_reference.selected_shapes.is_empty():
		shapes_to_calculate = move_tool_reference.selected_shapes
	elif is_instance_valid(target_node):
		shapes_to_calculate = [target_node]

	if shapes_to_calculate.is_empty():
		if visible: hide()
		return

	var parent_node = get_parent()
	if not is_instance_valid(parent_node):
		return

	if shapes_to_calculate.size() == 1 and is_instance_valid(shapes_to_calculate[0]):
		# Selección única: la caja debe rotar/escalar EXACTAMENTE igual que la figura,
		# no solo envolverla con un rectángulo alineado al mundo.
		var shape: Node2D = shapes_to_calculate[0]
		var local_rect: Rect2 = _local_rect_cloned(shape)
		if local_rect.size == Vector2.ZERO:
			if visible: hide()
			return

		# Control no tiene global_position/global_rotation (eso es de Node2D):
		# convertimos manualmente al espacio local del padre (canvas).
		pivot_offset = Vector2.ZERO
		scale = shape.global_transform.get_scale()
		rotation = shape.global_rotation - parent_node.global_rotation
		size = local_rect.size
		position = parent_node.to_local(shape.to_global(local_rect.position))

		if not visible: show()
	else:
		# Multi-selección: sin una única rotación consistente, usamos AABB alineado al mundo.
		var global_rect: Rect2 = _get_macro_rect_cloned(shapes_to_calculate)
		if global_rect.size == Vector2.ZERO:
			if visible: hide()
			return

		var local_pos: Vector2 = parent_node.to_local(global_rect.position)
		var local_end: Vector2 = parent_node.to_local(global_rect.end)

		pivot_offset = Vector2.ZERO
		scale = Vector2.ONE
		rotation = 0.0
		position = local_pos
		size = local_end - local_pos

		if not visible: show()

# ── INTERACCIÓN: GESTIÓN DE RATÓN PARA DRAG DIRECTO DESDE PANEL ASIGNADO ─────
func _on_drag_panel_gui_input(event: InputEvent) -> void:
	if not is_instance_valid(move_tool_reference):
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging_canvas_area = true
			if "is_dragging_shape" in move_tool_reference:
				move_tool_reference.is_dragging_shape = true
				move_tool_reference.transform_initial_mouse = event.global_position
		else:
			_is_dragging_canvas_area = false
			if "is_dragging_shape" in move_tool_reference:
				move_tool_reference.is_dragging_shape = false

	elif event is InputEventMouseMotion and _is_dragging_canvas_area:
		if move_tool_reference.has_method("_update_transform_logic"):
			move_tool_reference._update_transform_logic(event.global_position)

# ── MÉTODOS DE GEOMETRÍA CLONADOS (Conserva tus funciones matemáticas aquí abajo) ──
func _get_macro_rect_cloned(selected_shapes_array: Array[Node2D]) -> Rect2:
	if selected_shapes_array.size() == 0: return Rect2()
	var valid_first_rect = false
	var r: Rect2 = Rect2()
	for shape in selected_shapes_array:
		if is_instance_valid(shape):
			if not valid_first_rect:
				r = _global_rect_cloned(shape)
				valid_first_rect = true
			else:
				r = r.merge(_global_rect_cloned(shape))
	return r

func _global_rect_cloned(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()
	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
		return Rect2(node.global_position, Vector2(w, h))
	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0: return Rect2(node.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = node.to_global(baked[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in baked:
			var g_pt: Vector2 = node.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = 6.0
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D: pad = max(pad, renderer.width * 0.5)
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
		if line.points.size() == 0: return Rect2(line.global_position - Vector2(10, 10), Vector2(20, 20))
		var first_gpt: Vector2 = line.to_global(line.points[0])
		var g_mn: Vector2 = first_gpt
		var g_mx: Vector2 = first_gpt
		for p in line.points:
			var g_pt: Vector2 = line.to_global(p)
			g_mn.x = min(g_mn.x, g_pt.x)
			g_mn.y = min(g_mn.y, g_pt.y)
			g_mx.x = max(g_mx.x, g_pt.x)
			g_mx.y = max(g_mx.y, g_pt.y)
		var pad: float = max(6.0, line.width * 0.5)
		return Rect2(g_mn, g_mx - g_mn).grow(pad)
	return Rect2(node.global_position - Vector2(20, 20), Vector2(40, 40))


## Igual que _global_rect_cloned(), pero en el espacio LOCAL/propio de la figura
## (sin aplicar su transform). Se usa para la caja orientada de selección única:
## al aplicar luego global_position/global_rotation/scale de la figura sobre este
## rect, el resultado queda pegado exactamente a su geometría real, ya rotada o no.
func _local_rect_cloned(node: Node2D) -> Rect2:
	if not is_instance_valid(node): return Rect2()
	if node.has_meta("shape_type") and (node.get_meta("shape_type") in ["text_paragraph", "text_title"]):
		var w: float = node.get_meta("width") if node.has_meta("width") else 350.0
		var h: float = node.get_meta("height") if node.has_meta("height") else 65.0
		return Rect2(Vector2.ZERO, Vector2(w, h))
	if node is Path2D:
		var curve: Curve2D = (node as Path2D).curve
		var baked = curve.get_baked_points()
		if baked.size() == 0: return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = baked[0]
		var mx: Vector2 = baked[0]
		for p in baked:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		var pad: float = 6.0
		var renderer = node.get_node_or_null("Render_Visual")
		if renderer is Line2D: pad = max(pad, renderer.width * 0.5)
		return Rect2(mn, mx - mn).grow(pad)
	if node is Polygon2D:
		var poly = node as Polygon2D
		if poly.polygon.size() > 0:
			var mn: Vector2 = poly.polygon[0]
			var mx: Vector2 = poly.polygon[0]
			for p in poly.polygon:
				mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
				mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
			return Rect2(mn, mx - mn)
	if "size" in node and (node is VectorRectangle or node is VectorCircle):
		var s: Vector2 = node.get("size")
		return Rect2(-s * 0.5, s)

	if "vertices" in node:
		var verts: PackedVector2Array = node.get("vertices")
		if verts.size() == 0:
			return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = verts[0]
		var mx: Vector2 = verts[0]
		for p in verts:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		return Rect2(mn, mx - mn)

	if "width" in node and "height" in node:
		var w: float = node.get("width")
		var h: float = node.get("height")
		var size_vec: Vector2 = Vector2(w, h)
		return Rect2(-size_vec * 0.5, size_vec)
	if node is Line2D:
		var line: Line2D = node as Line2D
		if line.points.size() == 0: return Rect2(Vector2(-10, -10), Vector2(20, 20))
		var mn: Vector2 = line.points[0]
		var mx: Vector2 = line.points[0]
		for p in line.points:
			mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
			mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		var pad: float = max(6.0, line.width * 0.5)
		return Rect2(mn, mx - mn).grow(pad)
	return Rect2(Vector2(-20, -20), Vector2(40, 40))


func _connect_signals() -> void:
	# Conectar señales para actualización eficiente
	if GlobalEvents:
		if GlobalEvents.has_signal("object_selected"):
			GlobalEvents.object_selected.connect(_on_object_selected)
		if GlobalEvents.has_signal("object_transformed"):
			GlobalEvents.object_transformed.connect(_on_object_transformed)
		if GlobalEvents.has_signal("object_style_changed"):
			GlobalEvents.object_style_changed.connect(_on_object_transformed)
		if GlobalEvents.has_signal("selection_changed"):
			GlobalEvents.selection_changed.connect(_on_selection_changed)

func _on_object_selected() -> void:
	_sincronizar_dimensiones_en_canvas()

func _on_object_transformed() -> void:
	_sincronizar_dimensiones_en_canvas()

func _on_selection_changed() -> void:
	_sincronizar_dimensiones_en_canvas()
