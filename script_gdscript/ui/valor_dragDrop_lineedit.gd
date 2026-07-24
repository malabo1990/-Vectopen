@tool
extends Control

# --- CONFIGURACIÓN DE APARIENCIA EN EL INSPECTOR ---
@export_group("Configuración Numérica")
@export var value: float = 0.0: set = _set_value
@export var step: float = 0.1          # Cuánto cambia el valor al arrastrar
@export var min_value: float = -1000.0
@export var max_value: float = 1000.0
@export var decimals: int = 2          # Número de decimales a mostrar

@export_group("Componentes del Layout")
@export var line_edit: LineEdit        # Tu nodo LineEdit interno
@export var panel: Panel              # Tu nodo Panel que hace de caja contenedora
@export var line_edit_size: Vector2 = Vector2(60, 24)

# --- VARIABLES DE CONTROL INTERNO ---
var is_dragging: bool = false
var is_editing: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if not line_edit or not panel:
		push_error("Por favor, asigna el LineEdit y el Panel en el Inspector.")
		return
		
	# 1. Configuración de dimensiones iniciales
	line_edit.size = line_edit_size
	line_edit.custom_minimum_size = line_edit_size
	_actualizar_texto_ui()
	
	# Asegurar que el panel procese inputs del ratón de forma prioritaria
	panel.mouse_filter = MOUSE_FILTER_STOP
	# El LineEdit ignora el mouse al inicio para dejar pasar el Drag
	line_edit.mouse_filter = MOUSE_FILTER_IGNORE
	
	# 2. Conexión limpia de señales
	line_edit.text_submitted.connect(_on_line_edit_text_submitted)
	line_edit.focus_exited.connect(_on_line_edit_focus_exited)
	panel.gui_input.connect(_on_panel_gui_input)

# --- INTERCEPCIÓN GLOBAL DE CLICS (Para cerrar al hacer clic fuera) ---
func _input(event: InputEvent) -> void:
	if not is_editing: return
	
	# Si el usuario hace clic con el botón izquierdo en cualquier parte de la pantalla
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Comprobamos si el clic ha sido FUERA del cuadro del LineEdit
		if not line_edit.get_global_rect().has_point(event.global_position):
			# Forzamos la pérdida de foco para cerrar la edición de inmediato
			_desactivar_modo_edicion(true)

# --- CAPTURA DE EVENTOS DENTRO DEL PANEL ---
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				_activar_modo_edicion()
			else:
				if not is_editing:
					is_dragging = true
					drag_start_pos = event.position
		else:
			is_dragging = false
			
	elif event is InputEventMouseMotion and is_dragging and not is_editing:
		var delta_y = drag_start_pos.y - event.position.y
		if abs(delta_y) > 1.0:
			value += step * delta_y
			drag_start_pos = event.position

# --- CONTROL DEL MODO EDICIÓN ---
func _activar_modo_edicion() -> void:
	is_editing = true
	is_dragging = false
	
	line_edit.mouse_filter = MOUSE_FILTER_STOP
	line_edit.grab_focus()
	line_edit.select_all()

func _desactivar_modo_edicion(guardar_cambios: bool) -> void:
	if not is_editing: return
	is_editing = false
	
	line_edit.mouse_filter = MOUSE_FILTER_IGNORE
	
	if guardar_cambios:
		_validar_y_aplicar_texto(line_edit.text)
	else:
		_actualizar_texto_ui()
		
	line_edit.release_focus()

# --- VALIDACIÓN Y SEÑALES ---
func _validar_y_aplicar_texto(texto: String) -> void:
	if texto.is_valid_float():
		value = float(texto)
	else:
		_actualizar_texto_ui()

func _on_line_edit_text_submitted(_new_text: String) -> void:
	_desactivar_modo_edicion(true)

func _on_line_edit_focus_exited() -> void:
	_desactivar_modo_edicion(true)

# --- SETTERS Y FORMATEO ---
func _set_value(new_value: float) -> void:
	value = clampf(new_value, min_value, max_value)
	_actualizar_texto_ui()

func _actualizar_texto_ui() -> void:
	if line_edit:
		line_edit.text = ("%." + str(decimals) + "f") % value
