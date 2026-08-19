# ==========================================
# RUTA: res://scripts/ColorPaletteTool.gd
# CONFIGURACIÓN: Asignar al nodo raíz de la herramienta de paletas
# ==========================================
extends Control
class_name ColorPaletteTool

# --- REFERENCIAS DE INTERFAZ ---
@export var slider_palette_size: HSlider       # Deslizador para elegir cantidad de colores
@export var label_palette_count: Label        # Texto numérico (ej: "5")
@export var container_samples: FlowContainer   # Contenedor auto-ajustable
@export var nodo_color_rect: ColorRect         # Tu color plano activo de referencia

# --- CONFIGURACIÓN DE DISEÑO MINIMALISTA (Estilo macOS/Figma) ---
@export var sample_min_size: Vector2 = Vector2(75, 95)
@export var font_size_hex: int = 11

# Variable interna para vigilar el color real en cada frame de forma ultra-precisa
var _color_anterior_referencia: Color = Color.TRANSPARENT

func _ready() -> void:
	_verificar_referencias()
	_configurar_componentes()
	
	# Conectar señales de cambio de color
	_connect_color_signals()
	
	# Forzar la primera construcción limpia de la interfaz
	_actualizar_paleta_interfaz(int(slider_palette_size.value))

func _process(_delta: float) -> void:
	# Poliar cambio de color como fallback para paleta dinámica en tiempo real
	if is_instance_valid(nodo_color_rect):
		var current := nodo_color_rect.color
		if current != _color_anterior_referencia:
			_color_anterior_referencia = current
			_actualizar_paleta_interfaz(int(slider_palette_size.value))

# Conectar con el sistema ToggleVisibility para regenerar la paleta al mostrar el panel
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_actualizar_paleta_interfaz(int(slider_palette_size.value))

func _connect_color_signals() -> void:
	# Conectar señales para actualizar la paleta cuando el color cambia
	if GlobalEvents:
		if GlobalEvents.has_signal("color_changed") and not GlobalEvents.color_changed.is_connected(_on_color_changed):
			GlobalEvents.color_changed.connect(_on_color_changed)
		if GlobalEvents.has_signal("gradient_changed") and not GlobalEvents.gradient_changed.is_connected(_on_gradient_changed):
			GlobalEvents.gradient_changed.connect(_on_gradient_changed)

func _on_color_changed(new_color: Color) -> void:
	if is_instance_valid(nodo_color_rect):
		nodo_color_rect.color = new_color
		_color_anterior_referencia = new_color
		_actualizar_paleta_interfaz(int(slider_palette_size.value))

func _on_gradient_changed(_gradient: Gradient) -> void:
	# Si el color actual es parte de un gradiente, actualizar
	if is_instance_valid(nodo_color_rect):
		_actualizar_paleta_interfaz(int(slider_palette_size.value))

# ── Configuración Inicial y Validaciones ──────────────────────────────────────

func _verificar_referencias() -> void:
	assert(slider_palette_size, "ERROR: Falta asignar 'slider_palette_size' en el Inspector.")
	assert(label_palette_count, "ERROR: Falta asignar 'label_palette_count' en el Inspector.")
	assert(container_samples, "ERROR: Falta asignar 'container_samples' en el Inspector.")
	assert(nodo_color_rect, "ERROR: Falta asignar 'nodo_color_rect' en el Inspector.")

func _configurar_componentes() -> void:
	slider_palette_size.min_value = 3 # Mínimo 3: [Blanco] [Color] [Negro]
	slider_palette_size.max_value = 11
	slider_palette_size.step = 1
	if not slider_palette_size.value_changed.is_connected(_on_slider_value_changed):
		slider_palette_size.value_changed.connect(_on_slider_value_changed)

func _on_slider_value_changed(value: float) -> void:
	if label_palette_count:
		label_palette_count.text = str(int(value))
	_actualizar_paleta_interfaz(int(value))

# ── Lógica Maestra de Renderizado (Blanco ➔ Color ➔ Negro) ───────────────────

func _actualizar_paleta_interfaz(cantidad: int) -> void:
	if not is_inside_tree() or not is_instance_valid(nodo_color_rect): 
		return
	
	# 1. Limpieza absoluta e inmediata de los hijos del FlowContainer
	for child in container_samples.get_children():
		child.queue_free()
		
	var color_base = nodo_color_rect.color
	
	# 2. Bucle matemático de interpolación lineal (.lerp)
	for i in range(cantidad):
		var color_calculado: Color
		var ratio := float(i) / float(cantidad - 1)
		
		if ratio < 0.5:
			# Tramo Izquierdo: De Blanco Puro a Color de Referencia
			var t = ratio / 0.5
			color_calculado = Color.WHITE.lerp(color_base, t)
		elif ratio > 0.5:
			# Tramo Derecho: De Color de Referencia a Negro Puro
			var t = (ratio - 0.5) / 0.5
			color_calculado = color_base.lerp(Color.BLACK, t)
		else:
			# Centro Perfecto
			color_calculado = color_base
			
		# 3. Creación del Nodo de Interfaz Inyectado
		var cell := PanelContainer.new()
		cell.custom_minimum_size = sample_min_size
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		# Fondo de la celda (Muestra visual del color)
		var color_box := ColorRect.new()
		color_box.color = color_calculado
		color_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		color_box.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(color_box)
		
		# Texto en formato HEX
		var label_hex := Label.new()
		label_hex.text = "#" + color_calculado.to_html(false).to_upper()
		label_hex.add_theme_font_size_override("font_size", font_size_hex)
		
		# Control de contraste inteligente: Evita texto negro sobre fondo oscuro
		var luminosidad = color_calculado.v
		label_hex.add_theme_color_override("font_color", Color.BLACK if luminosidad > 0.6 else Color.WHITE)
		
		label_hex.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_hex.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label_hex.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cell.add_child(label_hex)
		
		# Evento de clic: Si pulsas la muestra, se convierte en el nuevo color de referencia
		cell.gui_input.connect(func(event): _on_cell_clicked(event, color_box.color))
		
		container_samples.add_child(cell)

func _on_cell_clicked(event: InputEvent, color_seleccionado: Color) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_instance_valid(nodo_color_rect):
			nodo_color_rect.color = color_seleccionado
			_color_anterior_referencia = color_seleccionado
		
		if "object_style_changed" in GlobalEvents:
			GlobalEvents.object_style_changed.emit()
