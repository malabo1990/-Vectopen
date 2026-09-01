@tool
extends Control

## Emitido cada vez que "value" cambia por una acción real del usuario (arrastre
## o texto confirmado) — no cuando otro script llama set_display_value() para
## reflejar un valor externo. Dispara en cada paso del arrastre, no solo al
## soltar, para permitir mover la figura en vivo mientras se arrastra el campo.
signal value_committed(new_value: float)

# --- CONFIGURACIÓN DE APARIENCIA EN EL INSPECTOR ---
@export_group("Configuración Numérica")
@export var value: float = 0.0: set = _set_value
@export var step: float = 0.1          # Cuánto cambia el valor al arrastrar
@export var min_value: float = -1000.0
@export var max_value: float = 1000.0
@export var decimals: int = 2          # Número de decimales a mostrar

@export_group("Componentes del Layout")
@export var line_edit: LineEdit        # Tu nodo LineEdit interno
@export var panel: Control            # Caja contenedora (Panel o PanelContainer)
@export var line_edit_size: Vector2 = Vector2(60, 24)

# --- VARIABLES DE CONTROL INTERNO ---
var is_dragging: bool = false
var is_editing: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var _suppress_emit: bool = false

func _ready() -> void:
	# Fallback: los exports tipados @export var x: LineEdit resueltos vía
	# node_paths en el .tscn a veces no llegan asignados cuando el nodo se
	# instancia dentro de un pool (ObjectPool duplica boundingbox.tscn 20
	# veces al arrancar) — la escena en sí está bien formada (line_edit =
	# NodePath("LineEdit"), panel = NodePath(".")), así que si el export no
	# llegó, se resuelve a mano con la misma ruta relativa antes de rendirse.
	if not line_edit:
		var maybe_line_edit: Node = get_node_or_null("LineEdit")
		if maybe_line_edit is LineEdit:
			line_edit = maybe_line_edit
	if not panel:
		# La caja contenedora es el propio nodo raíz del campo (Panel o
		# PanelContainer, según la versión de boundingbox.tscn). `get_node(".")`
		# lo da como Control genérico sin problemas de compilación.
		var maybe_panel: Node = get_node_or_null(".")
		if maybe_panel is Control:
			panel = maybe_panel
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
	if not _suppress_emit:
		value_committed.emit(value)

## Refleja un valor externo (p.ej. la posición actual de la figura seleccionada)
## sin disparar value_committed y sin pisar lo que el usuario esté escribiendo
## o arrastrando en este mismo instante.
func set_display_value(v: float) -> void:
	if is_editing or is_dragging:
		return
	_suppress_emit = true
	value = v
	_suppress_emit = false

func _actualizar_texto_ui() -> void:
	if line_edit:
		line_edit.text = ("%." + str(decimals) + "f") % value
