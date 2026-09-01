# GradientEditor.gd
# Herramienta de degradado profesional integrada con el sistema de eventos globales
extends Control

@export var color_rect: ColorRect
@export var btn_add: Button
@export var btn_remove: Button
@export var color_picker: ColorPickerButton

var stops: Array[StopHandle] = []
var selected_handle: StopHandle = null

# Configuración de comportamiento Avanzado (Estilo editor vectorial)
const SNAP_THRESHOLD: float = 0.025 # Distancia magnética para el Snap (2.5%)
const SNAP_VALUES: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]

# ── Clase interna del Stop Handle Avanzado ──────────────────────────────────────
class StopHandle extends Control:
	signal grabbed(handle: StopHandle)
	signal moved(handle: StopHandle, new_pos: float)
	signal duplicate_requested(handle: StopHandle)

	var pos_ratio: float = 0.0
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()
			
	var dragging: bool = false
	var drag_offset: float = 0.0
	var is_selected: bool = false

	func _ready() -> void:
		custom_minimum_size = Vector2(20, 20) # Zona de clic óptima y amplia
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		
		# Anclaje para centrar verticalmente respecto al padre de forma automática
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = event.position.x
				grabbed.emit(self)
				
				# Clonar estilo vectorial/un editor profesional: Alt / Option presionado al arrastrar
				if event.alt_pressed:
					duplicate_requested.emit(self)
			else:
				dragging = false

		if event is InputEventMouseMotion and dragging:
			# Bloquear movimiento en los extremos absolutos 0 y 1 para estabilidad
			if is_equal_approx(pos_ratio, 0.0) or is_equal_approx(pos_ratio, 1.0):
				return

			var parent = get_parent() as Control
			if not parent: return
			
			var mouse_x = parent.get_local_mouse_position().x
			var target_x = mouse_x - drag_offset
			var max_x = parent.size.x - size.x
			
			target_x = clamp(target_x, 0.0, max_x)
			position.x = target_x
			
			pos_ratio = (target_x + size.x * 0.5) / parent.size.x
			moved.emit(self, pos_ratio)

	# Dibujo estético del Handle (premium Blanco)
	func _draw() -> void:
		var center := size * 0.5
		
		if is_selected:
			# Círculo seleccionado: Más grande, más grueso, borde blanco puro y sombra
			var radius_sel := 8.0
			draw_circle(center, radius_sel + 3.0, Color(0, 0, 0, 0.25), true) # Sombra fina
			draw_circle(center, radius_sel + 2.0, Color.WHITE, true)          # Borde blanco grueso
			draw_circle(center, radius_sel - 1.0, color, true)                # Color interno
		else:
			# Círculo normal: Tamaño estándar discreto
			var radius_norm := 6.0
			draw_circle(center, radius_norm + 1.0, Color(0, 0, 0, 0.2), false, 1.0) # Contorno sutil
			draw_circle(center, radius_norm, Color.WHITE, true)                     # Anillo exterior
			draw_circle(center, radius_norm - 2.0, color, true)                     # Color interno

	func set_selected(selected: bool) -> void:
		is_selected = selected
		z_index = 2 if selected else 1
		queue_redraw()

# ── Métodos Principales del Editor ─────────────────────────────────────────────
func _ready() -> void:
	assert(color_rect and btn_add and btn_remove and color_picker, "Faltan referencias en GradientEditor.")

	btn_add.pressed.connect(_add_new_stop_at_center)
	btn_remove.pressed.connect(_remove_selected)
	color_picker.color_changed.connect(_on_color_changed)
	color_rect.draw.connect(_draw_gradient)
	
	# Permitir clics directos en la barra para crear nuevos puntos
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	color_rect.gui_input.connect(_on_color_rect_gui_input)

	# Inicialización de extremos fijos (Negro y Blanco)
	_create_stop_node(0.0, Color.BLACK)
	_create_stop_node(1.0, Color.WHITE)
	_select_stop(stops[0])
	
	# Emitir estado inicial al sistema global
	GlobalEvents.gradient_changed.emit(get_gradient())

# Entrada de teclado global para eliminar con "Supr" o "Backspace"
func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(selected_handle) and event.is_pressed():
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_remove_selected()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_reposition_all")

func _create_stop_node(pos: float, color: Color) -> StopHandle:
	var handle := StopHandle.new()
	color_rect.add_child(handle)
	
	handle.color = color
	handle.pos_ratio = pos
	
	handle.grabbed.connect(_select_stop)
	handle.moved.connect(_on_grabber_moved)
	handle.duplicate_requested.connect(_on_duplicate_requested)
	
	stops.append(handle)
	_reposition_single(handle)
	return handle

# ── Lógica de Interacción Avanzada ────────────────────────────────────────────

# Hacer clic en la barra del gradiente crea un stop exactamente en esa posición
func _on_color_rect_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_mouse_x = event.position.x
		var target_ratio = clamp(local_mouse_x / color_rect.size.x, 0.0, 1.0)
		
		# Evitar crear puntos encima de otros existentes
		var click_near_handle: bool = false
		for stop in stops:
			if abs(stop.pos_ratio - target_ratio) * color_rect.size.x < 14.0:
				click_near_handle = true
				break
				
		if not click_near_handle:
			var sample_color = _sample_gradient_at(target_ratio)
			var new_handle = _create_stop_node(target_ratio, sample_color)
			_select_stop(new_handle)
			color_rect.queue_redraw()
			_emit_gradient()

func _on_grabber_moved(handle: StopHandle, raw_pos: float) -> void:
	# Sistema de SNAP Magnético (0%, 25%, 50%, 75%, 100%)
	var final_pos = raw_pos
	for snap_val in SNAP_VALUES:
		if abs(raw_pos - snap_val) < SNAP_THRESHOLD:
			final_pos = snap_val
			break
			
	handle.pos_ratio = final_pos
	_reposition_single(handle)
	color_rect.queue_redraw()
	GlobalEvents.gradient_changed.emit(get_gradient())

func _on_duplicate_requested(handle: StopHandle) -> void:
	# Duplicación con Alt+Arrastrar (bloqueada en extremos fijos)
	if is_equal_approx(handle.pos_ratio, 0.0) or is_equal_approx(handle.pos_ratio, 1.0):
		return
		
	var clone = _create_stop_node(handle.pos_ratio, handle.color)
	clone.dragging = true
	clone.drag_offset = handle.drag_offset
	_select_stop(clone)

func _select_stop(handle: StopHandle) -> void:
	selected_handle = handle
	color_picker.color = handle.color
	for stop in stops:
		stop.set_selected(stop == handle)

func _on_color_changed(new_color: Color) -> void:
	if is_instance_valid(selected_handle):
		selected_handle.color = new_color
		color_rect.queue_redraw()
		_emit_gradient()

func _add_new_stop_at_center() -> void:
	var new_handle = _create_stop_node(0.5, color_picker.color)
	_select_stop(new_handle)
	color_rect.queue_redraw()
	GlobalEvents.gradient_changed.emit(get_gradient())

func _remove_selected() -> void:
	if not is_instance_valid(selected_handle):
		return
		
	# Impedir la eliminación de los extremos obligatorios
	if is_equal_approx(selected_handle.pos_ratio, 0.0) or is_equal_approx(selected_handle.pos_ratio, 1.0):
		return
		
	var to_remove = selected_handle
	stops.erase(to_remove)
	to_remove.queue_free()
	_select_stop(stops[0])
	color_rect.queue_redraw()
	GlobalEvents.gradient_changed.emit(get_gradient())

# ── Posicionamiento y Matemáticas del Renderizado ──────────────────────────────
func _reposition_all() -> void:
	if not is_inside_tree(): return
	for handle in stops:
		_reposition_single(handle)

func _reposition_single(handle: StopHandle) -> void:
	if is_instance_valid(handle):
		handle.size = Vector2(20, color_rect.size.y)
		var target_x = handle.pos_ratio * color_rect.size.x - handle.size.x * 0.5
		handle.position = Vector2(target_x, 0)

func _draw_gradient() -> void:
	if stops.size() < 2: return
	var w: float = color_rect.size.x
	var h: float = color_rect.size.y

	var sorted_stops = stops.duplicate()
	sorted_stops.sort_custom(func(a, b): return a.pos_ratio < b.pos_ratio)

	for i in range(sorted_stops.size() - 1):
		var s1 = sorted_stops[i]
		var s2 = sorted_stops[i + 1]
		var x1: float = s1.pos_ratio * w
		var x2: float = s2.pos_ratio * w

		color_rect.draw_polygon(
			PackedVector2Array([Vector2(x1, 0), Vector2(x2, 0), Vector2(x2, h), Vector2(x1, h)]),
			PackedColorArray([s1.color, s2.color, s2.color, s1.color])
		)

# Interpolación de color para muestreo en clics vacíos
func _sample_gradient_at(ratio: float) -> Color:
	if stops.is_empty(): return Color.WHITE
	var sorted_stops = stops.duplicate()
	sorted_stops.sort_custom(func(a, b): return a.pos_ratio < b.pos_ratio)
	
	if ratio <= sorted_stops.front().pos_ratio: return sorted_stops.front().color
	if ratio >= sorted_stops.back().pos_ratio: return sorted_stops.back().color
	
	for i in range(sorted_stops.size() - 1):
		var s1 = sorted_stops[i]
		var s2 = sorted_stops[i + 1]
		if ratio >= s1.pos_ratio and ratio <= s2.pos_ratio:
			var t = (ratio - s1.pos_ratio) / (s2.pos_ratio - s1.pos_ratio)
			return s1.color.lerp(s2.color, t)
	return Color.WHITE

## Ángulo del degradado lineal en radianes (editable por fuera si se quiere).
var gradient_angle: float = 0.0

## Difunde el degradado actual: al bus global (compatibilidad) y a ColorCore,
## que lo aplica al relleno de la selección con undo.
func _emit_gradient() -> void:
	var g := get_gradient()
	if GlobalEvents.has_signal("gradient_changed"):
		GlobalEvents.gradient_changed.emit(g)
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_paint"):
		cc.set_paint(cc.make_linear(g, gradient_angle), "fill")

# ── Exportar Recurso Nativo Sincronizado (Sin Advertencias C++) ────────────────
func get_gradient() -> Gradient:
	var g := Gradient.new()
	
	var sorted_stops = stops.duplicate()
	sorted_stops.sort_custom(func(a, b): return a.pos_ratio < b.pos_ratio)
	
	for i in range(sorted_stops.size()):
		var s = sorted_stops[i]
		if i < g.get_point_count():
			g.set_offset(i, s.pos_ratio)
			g.set_color(i, s.color)
		else:
			g.add_point(s.pos_ratio, s.color)
	
	while g.get_point_count() > sorted_stops.size():
		g.remove_point(g.get_point_count() - 1)
		
	return g
