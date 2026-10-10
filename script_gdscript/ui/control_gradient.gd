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

var _active_dragging_handle: StopHandle = null

# ── Clase interna del Stop Handle Avanzado ──────────────────────────────────────
class StopHandle extends Control:
	signal grabbed(handle: StopHandle)
	signal moved(handle: StopHandle, new_pos: float)
	signal duplicate_requested(handle: StopHandle)
	signal double_clicked(handle: StopHandle)

	var pos_ratio: float = 0.0
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()
			
	var dragging: bool = false
	var is_selected: bool = false

	func _ready() -> void:
		custom_minimum_size = Vector2(24, 24) # Zona interactiva amplia
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					double_clicked.emit(self)
					accept_event()
					return
				dragging = true
				grabbed.emit(self)
				if event.alt_pressed:
					duplicate_requested.emit(self)
				accept_event()
			else:
				dragging = false

	# Dibujo estético del Handle con feedback visual nítido
	func _draw() -> void:
		var center := size * 0.5
		if is_selected:
			draw_circle(center, 9.0, Color(0, 0, 0, 0.22), true) # Sombra sutil
			draw_circle(center, 8.0, Color(0.04, 0.52, 1.0, 1.0), true) # Anillo de selección azul
			draw_circle(center, 6.5, Color.WHITE, true) # Aro blanco
			draw_circle(center, 4.5, color, true) # Color de la muestra
		else:
			draw_circle(center, 7.5, Color(0, 0, 0, 0.16), true) # Sombra sutil
			draw_circle(center, 6.5, Color.WHITE, true) # Aro blanco
			draw_circle(center, 6.5, Color(0.70, 0.72, 0.78, 1.0), false, 1.0) # Borde gris
			draw_circle(center, 4.5, color, true) # Color de la muestra

	func set_selected(selected: bool) -> void:
		is_selected = selected
		z_index = 2 if selected else 1
		queue_redraw()

signal stop_selected(color: Color)
## Cada edición del degradado (siempre). Con `emit_global = false` SOLO se
## emite esto: un editor embebido (p.ej. en el efecto Superposición de
## degradado) no debe cambiar el relleno de la figura vía ColorCore.
signal gradient_edited(gradient: Gradient)
var emit_global: bool = true

# ── Métodos Principales del Editor ─────────────────────────────────────────────
func _ready() -> void:
	if btn_add:
		btn_add.pressed.connect(_add_new_stop_at_center)
	if btn_remove:
		btn_remove.pressed.connect(_remove_selected)
	if color_picker:
		color_picker.color_changed.connect(_on_color_changed)
	color_rect.draw.connect(_draw_gradient)
	
	# Permitir clics directos en la barra para crear nuevos puntos
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	color_rect.gui_input.connect(_on_color_rect_gui_input)

	# Inicialización de extremos fijos (Negro y Blanco)
	_create_stop_node(0.0, Color.BLACK)
	_create_stop_node(1.0, Color.WHITE)
	_select_stop(stops[0])

	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)

func _on_theme_changed(_mode: String) -> void:
	_apply_theme()

## The scene hardcodes a white panel and white +/- buttons, which showed as a
## bright bar under the gradient on dark themes. Follow ThemeManager instead.
func _apply_theme() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for b in [btn_add, btn_remove]:
		if not is_instance_valid(b):
			continue
		var sb := ProUIStyle.flat(ProUIStyle.col("BUTTON_BG"), 4, ProUIStyle.col("BORDER"), 4, 1)
		var hov := ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER"), 4, 1)
		var prs := ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 4, 1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", prs)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(key, ProUIStyle.col("PANEL_TEXT"))

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
	handle.double_clicked.connect(_on_handle_double_clicked)
	
	stops.append(handle)
	_reposition_single(handle)
	return handle

func _on_handle_double_clicked(handle: StopHandle) -> void:
	_select_stop(handle)
	if is_instance_valid(color_picker):
		var pop = color_picker.get_popup()
		if pop: pop.popup_centered()

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
	_emit_gradient()

func _input(event: InputEvent) -> void:
	if _active_dragging_handle != null:
		if event is InputEventMouseMotion:
			if is_instance_valid(color_rect) and color_rect.size.x > 0:
				var local_x = color_rect.get_local_mouse_position().x
				var new_ratio = clampf(local_x / color_rect.size.x, 0.0, 1.0)
				# SNAP Magnético (0%, 25%, 50%, 75%, 100%)
				for snap_val in SNAP_VALUES:
					if abs(new_ratio - snap_val) < SNAP_THRESHOLD:
						new_ratio = snap_val
						break
				_active_dragging_handle.pos_ratio = new_ratio
				_reposition_single(_active_dragging_handle)
				color_rect.queue_redraw()
				_emit_gradient()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_instance_valid(_active_dragging_handle):
				_active_dragging_handle.dragging = false
				if is_instance_valid(color_rect):
					var local_y := color_rect.get_local_mouse_position().y
					# Arrastrar parada fuera de la barra (> 35px vertical): elimina parada
					if (local_y < -35.0 or local_y > color_rect.size.y + 35.0) and stops.size() > 2:
						_remove_stop(_active_dragging_handle)
			_active_dragging_handle = null

func _on_duplicate_requested(handle: StopHandle) -> void:
	var clone = _create_stop_node(handle.pos_ratio, handle.color)
	clone.dragging = true
	_select_stop(clone)
	_active_dragging_handle = clone
	_emit_gradient()

func _select_stop(handle: StopHandle) -> void:
	selected_handle = handle
	if handle and handle.dragging:
		_active_dragging_handle = handle
	else:
		_active_dragging_handle = null
	if is_instance_valid(color_picker):
		color_picker.color = handle.color
	for stop in stops:
		stop.set_selected(stop == handle)
	stop_selected.emit(handle.color)
	var idx := stops.find(handle)
	if idx >= 0 and GlobalEvents and GlobalEvents.has_signal("gradient_stop_selected"):
		GlobalEvents.gradient_stop_selected.emit(handle.color, idx)

func select_stop_by_index(idx: int) -> void:
	if idx >= 0 and idx < stops.size():
		var handle := stops[idx]
		selected_handle = handle
		_active_dragging_handle = null
		if is_instance_valid(color_picker):
			color_picker.color = handle.color
		for stop in stops:
			stop.set_selected(stop == handle)
		stop_selected.emit(handle.color)

func _on_color_changed(new_color: Color) -> void:
	if is_instance_valid(selected_handle):
		selected_handle.color = new_color
		color_rect.queue_redraw()
		_emit_gradient()

func _add_new_stop_at_center() -> void:
	var c := color_picker.color if is_instance_valid(color_picker) else Color.GRAY
	var new_handle = _create_stop_node(0.5, c)
	_select_stop(new_handle)
	color_rect.queue_redraw()
	_emit_gradient()

func _remove_selected() -> void:
	if not is_instance_valid(selected_handle):
		return
	_remove_stop(selected_handle)

func _remove_stop(handle: StopHandle) -> void:
	if not is_instance_valid(handle) or stops.size() <= 2:
		return
	stops.erase(handle)
	handle.queue_free()
	if selected_handle == handle:
		_select_stop(stops[0])
	color_rect.queue_redraw()
	_emit_gradient()

## 9.2 Invertir gradiente con un solo clic
func invert_gradient() -> void:
	if stops.size() < 2:
		return
	for stop in stops:
		stop.pos_ratio = 1.0 - stop.pos_ratio
	stops.sort_custom(func(a: StopHandle, b: StopHandle): return a.pos_ratio < b.pos_ratio)
	_reposition_all()
	color_rect.queue_redraw()
	_emit_gradient()

# ── Posicionamiento y Matemáticas del Renderizado ──────────────────────────────
func _reposition_all() -> void:
	if not is_inside_tree(): return
	for handle in stops:
		_reposition_single(handle)

func _reposition_single(handle: StopHandle) -> void:
	if is_instance_valid(handle) and is_instance_valid(color_rect):
		handle.size = Vector2(24, color_rect.size.y)
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
## 0 = Linear, 1 = Radial, 2 = Conic / Espiral
var gradient_type: int = 0
## Puntos de control (0..1) en el espacio de la caja de la figura.
var gradient_p0: Vector2 = Vector2(-1, -1)
var gradient_p1: Vector2 = Vector2(-1, -1)

## Difunde el degradado actual: al bus global (compatibilidad) y a ColorCore,
## que lo aplica al relleno de la selección con undo.
func _emit_gradient() -> void:
	var g := get_gradient()
	gradient_edited.emit(g)
	if not emit_global:
		return
	if GlobalEvents.has_signal("gradient_changed"):
		GlobalEvents.gradient_changed.emit(g)
	if not is_inside_tree():
		return
	var tree := get_tree()
	var cc := tree.root.get_node_or_null("ColorCore") if tree and tree.root else null
	if cc and cc.has_method("set_paint"):
		var p: Dictionary = {}
		if gradient_type == 1:
			p = cc.make_radial(g, Vector2(0.5, 0.5), 0.5, gradient_p0, gradient_p1)
		elif gradient_type == 2:
			p = cc.make_conic(g, Vector2(0.5, 0.5), gradient_angle, gradient_p0, gradient_p1)
		elif gradient_type == 3:
			p = cc.make_diamond(g, Vector2(0.5, 0.5), gradient_angle, gradient_p0, gradient_p1)
		elif gradient_type == 4:
			p = cc.make_box(g, Vector2(0.5, 0.5), gradient_angle, gradient_p0, gradient_p1)
		elif gradient_type == 5:
			p = cc.make_spiral(g, Vector2(0.5, 0.5), gradient_angle, gradient_p0, gradient_p1)
		elif gradient_type == 6:
			p = cc.make_reflected(g, Vector2(0.5, 0.5), gradient_angle, gradient_p0, gradient_p1)
		else:
			p = cc.make_linear(g, gradient_angle, gradient_p0, gradient_p1)
		cc.set_paint(p, "fill")

const PRESETS: Dictionary = {
	"Sunset": [Color(0.98, 0.35, 0.2), Color(0.95, 0.15, 0.5), Color(0.35, 0.1, 0.6)],
	"Ocean": [Color(0.1, 0.75, 0.9), Color(0.1, 0.45, 0.85), Color(0.05, 0.15, 0.45)],
	"Cyber Neon": [Color(0.0, 0.95, 0.85), Color(0.65, 0.05, 0.95), Color(0.95, 0.05, 0.55)],
	"Gold": [Color(0.95, 0.85, 0.45), Color(0.85, 0.65, 0.25), Color(0.55, 0.35, 0.1)],
	"Glass": [Color(1.0, 1.0, 1.0, 0.85), Color(0.85, 0.92, 1.0, 0.4), Color(0.7, 0.85, 1.0, 0.15)],
	"Vignette": [Color(0.1, 0.1, 0.1, 0.0), Color(0.05, 0.05, 0.05, 0.85)]
}

func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	var colors: Array = PRESETS[preset_name]
	var g := Gradient.new()
	for i in range(colors.size()):
		var off := float(i) / float(colors.size() - 1) if colors.size() > 1 else 0.0
		if i < g.get_point_count():
			g.set_offset(i, off)
			g.set_color(i, colors[i])
		else:
			g.add_point(off, colors[i])
	while g.get_point_count() > colors.size() and g.get_point_count() > 1:
		g.remove_point(g.get_point_count() - 1)
	set_gradient_resource(g, gradient_type, gradient_angle, false, gradient_p0, gradient_p1)
	_emit_gradient()

func get_selected_stop_ratio() -> float:
	if is_instance_valid(selected_handle):
		return selected_handle.pos_ratio
	return 0.0

func set_selected_stop_ratio(ratio: float) -> void:
	if is_instance_valid(selected_handle):
		selected_handle.pos_ratio = clampf(ratio, 0.0, 1.0)
		_reposition_single(selected_handle)
		color_rect.queue_redraw()
		_emit_gradient()

func update_selected_stop_color(c: Color) -> void:
	if is_instance_valid(selected_handle):
		selected_handle.color = c
		color_rect.queue_redraw()
		_emit_gradient()

func set_gradient_resource(g: Gradient, type: int = 0, angle: float = 0.0, keep_selection: bool = true, p0: Vector2 = Vector2(-1, -1), p1: Vector2 = Vector2(-1, -1)) -> void:
	if not is_instance_valid(g) or g.get_point_count() == 0:
		return
	gradient_type = type
	gradient_angle = angle
	if p0 != Vector2(-1, -1): gradient_p0 = p0
	if p1 != Vector2(-1, -1): gradient_p1 = p1

	var prev_idx: int = -1
	if keep_selection and is_instance_valid(selected_handle):
		prev_idx = stops.find(selected_handle)

	# Si el número de paradas coincide, actualizamos in-place para no destruir nodos ni perder selección
	if stops.size() == g.get_point_count():
		for i in g.get_point_count():
			stops[i].pos_ratio = g.get_offset(i)
			stops[i].color = g.get_color(i)
			_reposition_single(stops[i])
		if prev_idx >= 0 and prev_idx < stops.size():
			_select_stop(stops[prev_idx])
		elif not stops.is_empty():
			_select_stop(stops[0])
		color_rect.queue_redraw()
		return

	for s in stops:
		if is_instance_valid(s):
			s.queue_free()
	stops.clear()
	for i in g.get_point_count():
		_create_stop_node(g.get_offset(i), g.get_color(i))
	if not stops.is_empty():
		var sel_idx := clampi(prev_idx if prev_idx >= 0 else 0, 0, stops.size() - 1)
		_select_stop(stops[sel_idx])
	color_rect.queue_redraw()


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
	
	while g.get_point_count() > sorted_stops.size() and g.get_point_count() > 1:
		g.remove_point(g.get_point_count() - 1)
		
	return g
