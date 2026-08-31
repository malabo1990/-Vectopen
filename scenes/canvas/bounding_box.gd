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

# Mapeo Panel de handle → código usado por MoveTool.
#   move_x / move_y → arrastrar mueve la selección SOLO en horizontal / vertical
#   (los Panels `x` y `Y` del .tscn, antes solo indicadores del modo Blender).
const _HANDLE_CODES := {
	"handle_IA": "tl", "handle_DA": "tr", "handle_IB": "bl", "handle_DB": "br",
	"handle_MA": "tc", "MB": "bc", "handle_IM": "lc", "handle_DM": "rc",
	"Rotation": "rot_handle",
	"x": "move_x", "Y": "move_y",
}
# Handles de redimensionado: posición como fracción del rect (0..1).
const _HANDLE_FRAC := {
	"handle_IA": Vector2(0, 0), "handle_DA": Vector2(1, 0),
	"handle_IB": Vector2(0, 1), "handle_DB": Vector2(1, 1),
	"handle_MA": Vector2(0.5, 0), "MB": Vector2(0.5, 1),
	"handle_IM": Vector2(0, 0.5), "handle_DM": Vector2(1, 0.5),
}
# Handles de eje (diseño del .tscn: `x` rojo a la derecha, `Y` verde debajo).
# Cuadros del color de sus StyleBox, separados del borde de la caja. Arrastrar
# uno mueve la selección SOLO en ese eje.
const _AXIS_GAP_PX: float = 20.0     # separación del borde de la caja (px pantalla)
const _AXIS_X_COLOR := Color(1, 0, 0, 1)        # rojo  (StyleBoxFlat_gxv5u)
const _AXIS_Y_COLOR := Color(0, 0.82, 0, 1)     # verde (StyleBoxFlat_lna83)

# ── Tamaño CONSTANTE en pantalla, a cualquier zoom (como Figma / Affinity) ────
# Los handles ya NO se ven vía sus StyleBox (el borde es entero y se escala con
# el canvas → en zoom fuerte/lejano quedaban enormes o invisibles). Ahora:
#   · el Panel de cada handle queda TRANSPARENTE y solo sirve de zona de clic
#   · el dibujo real (cuadros + contorno + tallo de rotación) lo hace _draw()
#     con medidas en PÍXELES DE PANTALLA divididas por el zoom.
const _OUTLINE_SCREEN_PX: float = 1.25   # grosor del contorno
const _OUTLINE_COLOR := Color(0.05, 0.55, 0.91, 1.0)   # azul Figma
const _HANDLE_FILL := Color(1, 1, 1, 1)                # relleno del handle
const _HANDLE_SCREEN_PX: float = 8.0     # lado visible del handle
const _HANDLE_HIT_PX: float = 16.0       # lado de la zona de clic (Panel)
const _ROT_STEM_SCREEN_PX: float = 20.0  # largo del tallo del handle de rotación
# Puntero del ratón por handle → identidad visual (como Figma / Affinity).
# Godot no trae cursor de rotación → CROSS para el de rotación.
const _HANDLE_CURSORS := {
	"handle_IA": Control.CURSOR_FDIAGSIZE, "handle_DB": Control.CURSOR_FDIAGSIZE,  # ╲ tl/br
	"handle_DA": Control.CURSOR_BDIAGSIZE, "handle_IB": Control.CURSOR_BDIAGSIZE,  # ╱ tr/bl
	"handle_MA": Control.CURSOR_VSIZE, "MB": Control.CURSOR_VSIZE,                  # ↕ tc/bc
	"handle_IM": Control.CURSOR_HSIZE, "handle_DM": Control.CURSOR_HSIZE,           # ↔ lc/rc
	"Rotation": Control.CURSOR_CROSS,
	"x": Control.CURSOR_HSIZE, "Y": Control.CURSOR_VSIZE,                           # gizmo de eje
}
var _handle_base_rects: Dictionary = {}    # nombre de nodo → Rect2 de offsets originales (a zoom 1.0)
var _last_zoom_scale: float = -1.0
var _outline_style: StyleBoxFlat = null    # copia única por instancia (no la compartida del .tscn)

## Factor de compensación de zoom, exacto (sin recorte visible). El clamp solo
## evita valores patológicos si el zoom se acerca a 0 o es absurdamente grande.
static func _zoom_comp(zoom: float) -> float:
	return 1.0 / clampf(zoom, 0.0002, 100000.0)

# ── Campos numéricos X/Y (posición doc-space de la figura seleccionada) ──────
var _fields_wrapper: Control = null
var _field_x: Control = null
var _field_y: Control = null
var _bound_shape: VectorShape = null

func _ready() -> void:
	# Permitir que los eventos de ratón fluyan libremente a través de las capas de control
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Conexión limpia usando la referencia del Inspector elegida por ti
	if is_instance_valid(drag_panel):
		drag_panel.gui_input.connect(_on_drag_panel_gui_input)

	# Conectar señales para actualización eficiente
	_connect_signals()
	_connect_handle_signals()
	_connect_field_signals()
	_capture_base_handle_geometry()
	_apply_zoom_compensation()
	_sync_fields_wrapper_transform()
	_update_axis_lock_indicators()

	# Notificar que el objeto está listo para ser usado
	bounding_box_ready.emit()
	_pool_initialized = true

## Guarda la geometría base de cada handle y deja sus Panels transparentes
## (pasan a ser solo zona de clic; el dibujo lo hace _draw()).
func _capture_base_handle_geometry() -> void:
	if not _handle_base_rects.is_empty():
		return  # ya capturado (instancia reciclada del pool)
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	var vacio := StyleBoxEmpty.new()
	for handle_name in _HANDLE_CODES:
		# `Y` cuelga de `MB` en el .tscn, no directamente del panel → find_child.
		var p := panel_interactivo.find_child(handle_name, true, false) as Control
		if is_instance_valid(p):
			_handle_base_rects[handle_name] = Rect2(
				p.offset_left, p.offset_top,
				p.offset_right - p.offset_left, p.offset_bottom - p.offset_top
			)
			p.add_theme_stylebox_override("panel", vacio)   # solo zona de clic; el dibujo lo hace _draw()
			if _HANDLE_CURSORS.has(handle_name):
				p.mouse_default_cursor_shape = _HANDLE_CURSORS[handle_name]
	# Arrastrar el cuerpo de la caja = mover libre → cursor de movimiento.
	if is_instance_valid(drag_panel):
		drag_panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var candle := panel_interactivo.get_node_or_null("candle")
	if is_instance_valid(candle):
		candle.add_theme_stylebox_override("panel", vacio)  # el tallo lo dibuja _draw()

	# El StyleBox del contorno del panel: le quitamos el borde (el contorno lo
	# dibuja _draw() con grosor CONSTANTE en pantalla — el borde de StyleBoxFlat
	# es entero y se escala con el zoom, así que en zoom fuerte/lejano quedaba
	# demasiado grueso o invisible).
	var current_style: StyleBox = panel_interactivo.get_theme_stylebox("panel")
	if current_style is StyleBoxFlat:
		_outline_style = current_style.duplicate()
		_outline_style.set_border_width_all(0)
		panel_interactivo.add_theme_stylebox_override("panel", _outline_style)

## Escala TOTAL con la que se ve en pantalla el contenido de esta caja:
##   zoom de cámara (viewport canvas transform)  ×  escala propia de la caja
##   (que copia la escala de la figura seleccionada, ver _sincronizar…).
## El código antiguo leía canvas.global_transform.get_scale(), que SIEMPRE es 1
## (la cámara no escala el nodo Canvas, escala el viewport) → la compensación no
## hacía nada y los handles/línea crecían/encogían con el zoom. Ese era el bug.
func _get_zoom_scale() -> float:
	var vp := get_viewport()
	var cam_s: float = vp.get_canvas_transform().get_scale().x if vp else 1.0
	var self_s: float = get_global_transform().get_scale().x   # escala propia + ancestros
	return maxf(cam_s * self_s, 0.0001)

## Coloca la ZONA DE CLIC de cada handle (un Panel transparente) centrada en su
## punto y con un tamaño constante en pantalla. El dibujo real lo hace _draw().
func _apply_zoom_compensation() -> void:
	if _handle_base_rects.is_empty():
		return
	var zoom: float = _get_zoom_scale()
	if is_equal_approx(zoom, _last_zoom_scale):
		return
	_last_zoom_scale = zoom
	var f: float = _zoom_comp(zoom)
	queue_redraw()

	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return

	var hit_half: float = _HANDLE_HIT_PX * 0.5 * f
	var gap: float = _AXIS_GAP_PX * f
	var cx: float = size.x * 0.5
	var cy0: float = size.y * 0.5
	for handle_name in _handle_base_rects:
		var p := panel_interactivo.find_child(handle_name, true, false) as Control
		if not is_instance_valid(p):
			continue
		if handle_name == "x":
			# `x` cuelga del panel (layout_mode 0): a la DERECHA del borde, centrado.
			var xc := Vector2(size.x + gap, cy0)
			p.offset_left = xc.x - hit_half
			p.offset_right = xc.x + hit_half
			p.offset_top = xc.y - hit_half
			p.offset_bottom = xc.y + hit_half
			continue
		if handle_name == "Y":
			# `Y` cuelga de `MB` (bottom-center, rect ±hit_half): centrado, DEBAJO.
			var yc_local := Vector2(hit_half, hit_half + gap)   # relativo al top-left de MB
			p.offset_left = yc_local.x - hit_half
			p.offset_right = yc_local.x + hit_half
			p.offset_top = yc_local.y - hit_half
			p.offset_bottom = yc_local.y + hit_half
			continue
		# Handles de resize/rotación: cuadrado centrado en su anchor.
		var cy: float = -_ROT_STEM_SCREEN_PX * f if handle_name == "Rotation" else 0.0
		p.offset_left = -hit_half
		p.offset_right = hit_half
		p.offset_top = cy - hit_half
		p.offset_bottom = cy + hit_half


## Dibuja el contorno, los handles y el tallo de rotación con medidas SIEMPRE
## constantes en pantalla, a cualquier zoom (como Figma / Affinity / Penpot).
## `_draw()` corre en el espacio local de la caja, que el canvas escala por el
## zoom → cada medida en px de pantalla se divide por ese zoom (`inv`).
func _draw() -> void:
	if not visible or size == Vector2.ZERO:
		return
	var inv: float = _zoom_comp(_get_zoom_scale())
	var lw: float = _OUTLINE_SCREEN_PX * inv
	var hs: float = _HANDLE_SCREEN_PX * inv
	var hb: float = maxf(_OUTLINE_SCREEN_PX * inv, 0.01)   # borde del handle = grosor de línea

	# Contorno
	draw_rect(Rect2(Vector2.ZERO, size), _OUTLINE_COLOR, false, lw)

	# Tallo + handle de rotación (por encima del centro superior)
	var top_c := Vector2(size.x * 0.5, 0.0)
	var rot_p := top_c + Vector2(0.0, -_ROT_STEM_SCREEN_PX * inv)
	draw_line(top_c, rot_p, _OUTLINE_COLOR, lw)
	draw_circle(rot_p, hs * 0.5, _HANDLE_FILL)
	draw_arc(rot_p, hs * 0.5, 0.0, TAU, 20, _OUTLINE_COLOR, hb)

	# 8 handles de redimensionado (esquinas + centros de lado)
	for handle_name in _HANDLE_FRAC:
		var frac: Vector2 = _HANDLE_FRAC[handle_name]
		var c := Vector2(frac.x * size.x, frac.y * size.y)
		var r := Rect2(c - Vector2(hs, hs) * 0.5, Vector2(hs, hs))
		draw_rect(r, _HANDLE_FILL, true)
		draw_rect(r, _OUTLINE_COLOR, false, hb)

	# Handles de eje (diseño del .tscn): cuadro ROJO a la derecha (mover solo X)
	# y cuadro VERDE debajo (mover solo Y). Con conector fino hasta el borde.
	var gap := _AXIS_GAP_PX * inv
	var x_c := Vector2(size.x + gap, size.y * 0.5)
	var y_c := Vector2(size.x * 0.5, size.y + gap)
	draw_line(Vector2(size.x, x_c.y), x_c, _AXIS_X_COLOR, hb)
	draw_line(Vector2(y_c.x, size.y), y_c, _AXIS_Y_COLOR, hb)
	_draw_handle_square(x_c, hs, hb, _AXIS_X_COLOR)
	_draw_handle_square(y_c, hs, hb, _AXIS_Y_COLOR)

func _draw_handle_square(center: Vector2, side: float, border: float, fill: Color) -> void:
	var r := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	draw_rect(r, fill, true)
	draw_rect(r, Color.WHITE, false, border)

## Los campos X/Y son texto: si heredaran la rotation/scale de esta caja (como
## los handles, a propósito) quedarían ilegibles cuando la figura está rotada
## o escalada. Se contra-rotan/escalan para mantenerse siempre horizontales y
## de tamaño constante en pantalla. A diferencia de _apply_zoom_compensation(),
## esto NO puede saltarse cuando el zoom no cambió: "rotation" (de esta caja)
## sí cambia en cada frame durante un arrastre de rotación, aunque el zoom de
## cámara se mantenga fijo — por eso se llama sin condición desde _process().
func _sync_fields_wrapper_transform() -> void:
	if not is_instance_valid(_fields_wrapper):
		return
	var f: float = _zoom_comp(_get_zoom_scale())
	_fields_wrapper.rotation = -rotation
	_fields_wrapper.scale = Vector2(f, f)

func _process(_delta: float) -> void:
	if not visible:
		return
	_apply_zoom_compensation()
	_sync_fields_wrapper_transform()
	queue_redraw()   # el contorno sigue a la figura (tamaño/rotación) y al zoom
	_update_axis_lock_indicators()

## Los Panels `x` / `Y` son ahora las ZONAS DE CLIC del gizmo de eje (mover solo
## en horizontal / vertical). Siempre visibles mientras haya selección; el
## dibujo del gizmo lo hace _draw().
func _update_axis_lock_indicators() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for n in ["x", "Y"]:
		var p := panel_interactivo.find_child(n, true, false) as Control
		if is_instance_valid(p) and not p.visible:
			p.visible = true

## Conecta cada Panel de handle (resize + rotación) para que dispare la
## transformación real en MoveTool, en vez de depender de su hit-testing manual.
func _connect_handle_signals() -> void:
	var panel_interactivo := get_node_or_null("PANEL_BOUNDINGBOX")
	if not is_instance_valid(panel_interactivo):
		return
	for handle_name in _HANDLE_CODES:
		var handle_panel := panel_interactivo.find_child(handle_name, true, false) as Control
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
		var m = move_tool_reference
		if m.resize_handle == handle_code and (m.is_resizing or m.is_rotating or m.is_dragging_shape):
			m._on_motion(m.canvas.get_global_mouse_position())

## Localiza los campos X/Y (FieldsWrapper/FieldX/FieldY, ver boundingbox.tscn)
## y conecta su señal value_committed a los handlers que mueven la figura.
func _connect_field_signals() -> void:
	_fields_wrapper = get_node_or_null("PANEL_BOUNDINGBOX/FieldsWrapper")
	if not is_instance_valid(_fields_wrapper):
		return
	_field_x = _fields_wrapper.get_node_or_null("FieldX")
	_field_y = _fields_wrapper.get_node_or_null("FieldY")
	if is_instance_valid(_field_x) and _field_x.has_signal("value_committed"):
		if not _field_x.value_committed.is_connected(_on_field_x_committed):
			_field_x.value_committed.connect(_on_field_x_committed)
	if is_instance_valid(_field_y) and _field_y.has_signal("value_committed"):
		if not _field_y.value_committed.is_connected(_on_field_y_committed):
			_field_y.value_committed.connect(_on_field_y_committed)

func _on_field_x_committed(v: float) -> void:
	if is_instance_valid(_bound_shape):
		_bound_shape.set_doc_position(DVec2.new(v, _bound_shape.doc_position.y))
		_sincronizar_dimensiones_en_canvas()

func _on_field_y_committed(v: float) -> void:
	if is_instance_valid(_bound_shape):
		_bound_shape.set_doc_position(DVec2.new(_bound_shape.doc_position.x, v))
		_sincronizar_dimensiones_en_canvas()

func _hide_position_fields() -> void:
	_bound_shape = null
	if is_instance_valid(_fields_wrapper):
		_fields_wrapper.hide()

func _show_position_fields_for(shape: VectorShape) -> void:
	_bound_shape = shape
	if is_instance_valid(_fields_wrapper):
		_fields_wrapper.show()
	if is_instance_valid(_field_x):
		_field_x.set_display_value(shape.doc_position.x)
	if is_instance_valid(_field_y):
		_field_y.set_display_value(shape.doc_position.y)

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
		_hide_position_fields()
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
			_hide_position_fields()
			return

		# Control no tiene global_position/global_rotation (eso es de Node2D):
		# convertimos manualmente al espacio local del padre (canvas).
		pivot_offset = Vector2.ZERO
		scale = shape.global_transform.get_scale()
		rotation = shape.global_rotation - parent_node.global_rotation
		size = local_rect.size
		position = parent_node.to_local(shape.to_global(local_rect.position))

		if not visible: show()

		# Campos X/Y: solo tienen sentido para una figura con doc-space (el
		# valor mostrado/editable es shape.doc_position, precisión doble).
		# Figuras sueltas (Polygon2D/Path2D/Line2D) no lo tienen — se ocultan.
		if shape is VectorShape:
			_show_position_fields_for(shape)
		else:
			_hide_position_fields()
	else:
		# Multi-selección.
		var mt = move_tool_reference
		var mid_rot: bool = is_instance_valid(mt) and mt.is_rotating
		var mid_scale: bool = is_instance_valid(mt) and mt.is_resizing
		if (mid_rot or mid_scale) and mt.transform_macro_rect.size != Vector2.ZERO:
			# DURANTE el gesto: la caja = el AABB de INICIO transformado por el
			# gesto en vivo (rota / escala con la selección). Así no "respira"
			# recalculando el AABB de las figuras ya rotadas cada frame.
			var r0: Rect2 = mt.transform_macro_rect
			var piv: Vector2 = mt.live_pivot
			var box_center: Vector2 = r0.get_center()
			var box_size: Vector2 = r0.size
			if mid_scale:
				box_size = Vector2(absf(box_size.x) * absf(mt.live_scale.x), absf(box_size.y) * absf(mt.live_scale.y))
				box_center = piv + (r0.get_center() - piv) * mt.live_scale
			var box_rot := 0.0
			if mid_rot:
				box_center = piv + (r0.get_center() - piv).rotated(mt.live_rot_angle)
				box_rot = mt.live_rot_angle
			pivot_offset = box_size * 0.5
			rotation = box_rot - parent_node.global_rotation
			scale = Vector2.ONE
			size = box_size
			position = parent_node.to_local(box_center) - box_size * 0.5
			if not visible: show()
			_hide_position_fields()
			return

		# En reposo: AABB alineado al mundo que envuelve toda la selección.
		var global_rect: Rect2 = _get_macro_rect_cloned(shapes_to_calculate)
		if global_rect.size == Vector2.ZERO:
			if visible: hide()
			_hide_position_fields()
			return

		var local_pos: Vector2 = parent_node.to_local(global_rect.position)
		var local_end: Vector2 = parent_node.to_local(global_rect.end)

		pivot_offset = Vector2.ZERO
		scale = Vector2.ONE
		rotation = 0.0
		position = local_pos
		size = local_end - local_pos

		if not visible: show()
		_hide_position_fields()

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
