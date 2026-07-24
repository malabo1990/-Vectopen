extends Panel

# --- Componentes ---
@export var color_rect: ColorRect
@export var line_edit: LineEdit
@export var light_slider: Slider  # 0: Negro, 0.5: Puro, 1: Blanco
@export var alpha_slider: Slider

signal color_changed(new_color: Color)

# --- Estado Interno (La Fuente de Verdad) ---
# Usamos estas variables para que el color NUNCA se pierda en los extremos
var current_h: float = 0.0
var current_s: float = 1.0
var current_l: float = 0.5
var current_a: float = 1.0

var radius: float = 100.0
var center: Vector2
var is_dragging: bool = false

func _ready():
	if light_slider: light_slider.value_changed.connect(_on_light_slider_moved)
	if alpha_slider: alpha_slider.value_changed.connect(_on_alpha_slider_moved)
	if line_edit: line_edit.text_submitted.connect(_on_hex_submitted)

	resized.connect(_on_resized)
	_on_resized()
	
	# Estado inicial desde los sliders (configurados en el inspector de la escena)
	if light_slider:
		current_l = light_slider.value
	if alpha_slider:
		current_a = alpha_slider.value
	_sync_ui()

# --- Lógica de Sincronización ---
func _parse_color(c: Color):
	current_h = c.h
	current_a = c.a
	# Convertimos el Brillo de Godot a nuestro sistema 0-1 (0.5 es puro)
	if c.v < 1.0: 
		current_l = c.v * 0.5
	else:
		current_l = 0.5 + ((1.0 - c.s) * 0.5)

func _get_final_color() -> Color:
	# Esta función traduce nuestro HSL interno a un Color de Godot
	var s = 1.0
	var v = 1.0
	if current_l < 0.5:
		v = current_l * 2.0
		s = 1.0
	else:
		v = 1.0
		s = 1.0 - ((current_l - 0.5) * 2.0)
	return Color.from_hsv(current_h, s, v, current_a)

func _sync_ui(ignore_text: bool = false):
	var final_color = _get_final_color()
	
	if color_rect: color_rect.color = final_color
	if light_slider: light_slider.set_value_no_signal(current_l)
	if alpha_slider: alpha_slider.set_value_no_signal(current_a)
	if line_edit and not ignore_text:
		line_edit.text = "#" + final_color.to_html(current_a < 1.0)
	
	color_changed.emit(final_color)
	queue_redraw()

# --- Interacción ---
func _draw():
	# Círculo Cromático de Fondo
	var res = 64
	for i in range(res):
		var a1 = TAU * i / res - PI/2
		var a2 = TAU * (i + 1) / res - PI/2
		var c1 = Color.from_hsv(float(i)/res, 1.0, 1.0)
		var c2 = Color.from_hsv(float(i+1)/res, 1.0, 1.0)
		draw_polygon([center, center+Vector2(cos(a1), sin(a1))*radius, center+Vector2(cos(a2), sin(a2))*radius], [c1, c1, c2])

	# Marcador (Usa current_h siempre, no se pierde)
	var marker_angle = (current_h * TAU) - PI/2
	var marker_pos = center + Vector2(cos(marker_angle), sin(marker_angle)) * radius
	draw_circle(marker_pos, 7, Color(0,0,0, 0.3))
	draw_circle(marker_pos, 5, Color.WHITE)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m_pos = event.position - global_position
		if event.pressed and m_pos.distance_to(center) <= radius + 10: # Margen de error
			is_dragging = true
			_update_h_from_mouse(event.position)
		else:
			is_dragging = false
	elif event is InputEventMouseMotion and is_dragging:
		_update_h_from_mouse(event.position)

func _update_h_from_mouse(m_pos: Vector2):
	var rel = m_pos - global_position - center
	current_h = fposmod(rel.angle() + PI/2, TAU) / TAU
	_sync_ui()

# --- Señales Externas ---
func _on_light_slider_moved(val: float):
	current_l = val
	_sync_ui()

func _on_alpha_slider_moved(val: float):
	current_a = val
	_sync_ui()

func _on_hex_submitted(txt: String):
	var new_c = Color.from_string(txt, Color.WHITE)
	_parse_color(new_c)
	_sync_ui()

func _on_resized():
	center = size / 2
	radius = min(size.x, size.y) * 0.42
	queue_redraw()
