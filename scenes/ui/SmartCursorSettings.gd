# =============================================================================
# VECTOPEN UI — SMART CURSOR SETTINGS PANEL
# RUTA: res://scenes/ui/SmartCursorSettings.gd
# =============================================================================
class_name SmartCursorSettings
extends Panel

## Panel de configuración para el sistema Smart Cursor
## Permite personalizar el comportamiento y apariencia del cursor inteligente

signal settings_changed

# --- Referencias a nodos UI ---
@export var size_slider: HSlider
@export var pulse_speed_slider: HSlider
@export var color_transition_slider: HSlider
@export var halo_size_slider: HSlider
@export var rotation_speed_slider: HSlider
@export var accessibility_toggle: CheckButton
@export var preview_button: Button
@export var reset_button: Button

# --- Referencia al sistema SmartCursor ---
@onready var smart_cursor = get_node("/root/SmartCursor")

# ==========================================
# CICLO DE VIDA
# ==========================================

func _ready() -> void:
	# Verificar nodos requeridos
	if not size_slider or not pulse_speed_slider or not accessibility_toggle:
		push_error("SmartCursorSettings: Nodos UI no asignados en el Inspector")
		return
	
	# Conectar señales
	_connect_signals()
	
	# Cargar configuración actual
	_load_current_settings()


func _connect_signals() -> void:
	# Sliders
	size_slider.value_changed.connect(_on_size_changed)
	pulse_speed_slider.value_changed.connect(_on_pulse_speed_changed)
	color_transition_slider.value_changed.connect(_on_color_transition_changed)
	halo_size_slider.value_changed.connect(_on_halo_size_changed)
	rotation_speed_slider.value_changed.connect(_on_rotation_speed_changed)
	
	# Toggle de accesibilidad
	accessibility_toggle.toggled.connect(_on_accessibility_toggled)
	
	# Botones
	preview_button.pressed.connect(_on_preview_pressed)
	reset_button.pressed.connect(_on_reset_pressed)


func _load_current_settings() -> void:
	"""
	Carga la configuración actual del SmartCursor.
	"""
	if not smart_cursor:
		return
	
	# Configurar sliders
	size_slider.value = smart_cursor.CURSOR_CONFIG["base_size"]
	pulse_speed_slider.value = smart_cursor.CURSOR_CONFIG["pulse_speed"]
	color_transition_slider.value = smart_cursor.CURSOR_CONFIG["color_transition_speed"] * 10.0
	halo_size_slider.value = smart_cursor.CURSOR_CONFIG["halo_size"] * 10.0
	rotation_speed_slider.value = smart_cursor.CURSOR_CONFIG["rotation_speed"] * 10.0
	
	# Configurar toggle de accesibilidad
	accessibility_toggle.set_pressed_no_signal(smart_cursor.CURSOR_CONFIG["accessibility_mode"])


# ==========================================
# MANEJO DE EVENTOS
# ==========================================

func _on_size_changed(value: float) -> void:
	if smart_cursor:
		smart_cursor.CURSOR_CONFIG["base_size"] = value
		smart_cursor.set_size(value)
		settings_changed.emit()


func _on_pulse_speed_changed(value: float) -> void:
	if smart_cursor:
		smart_cursor.CURSOR_CONFIG["pulse_speed"] = value
		settings_changed.emit()


func _on_color_transition_changed(value: float) -> void:
	if smart_cursor:
		smart_cursor.CURSOR_CONFIG["color_transition_speed"] = value / 10.0
		settings_changed.emit()


func _on_halo_size_changed(value: float) -> void:
	if smart_cursor:
		smart_cursor.CURSOR_CONFIG["halo_size"] = value / 10.0
		settings_changed.emit()


func _on_rotation_speed_changed(value: float) -> void:
	if smart_cursor:
		smart_cursor.CURSOR_CONFIG["rotation_speed"] = value / 10.0
		settings_changed.emit()


func _on_accessibility_toggled(toggled: bool) -> void:
	if smart_cursor:
		smart_cursor.set_accessibility_mode(toggled)
		settings_changed.emit()


func _on_preview_pressed() -> void:
	"""
	Muestra una vista previa de todos los estados del cursor.
	"""
	if not smart_cursor:
		return
	
	# Guardar estado actual
	var original_state = smart_cursor.get_current_state()
	
	# Mostrar todos los estados en secuencia
	var states = [
		CursorState.NEUTRAL,
		CursorState.ACTIVE,
		CursorState.CREATIVE,
		CursorState.CONFIRM,
		CursorState.WARNING,
		CursorState.DISABLED,
		CursorState.TEXT_EDIT,
		CursorState.DRAGGING,
		CursorState.PRECISION
	]
	
	for i in range(states.size()):
		smart_cursor.set_state(states[i])
		await get_tree().create_timer(0.8).timeout
	
	# Restaurar estado original
	smart_cursor.set_state(original_state)


func _on_reset_pressed() -> void:
	"""
	Restablece la configuración a los valores por defecto.
	"""
	if not smart_cursor:
		return
	
	# Restablecer valores por defecto
	smart_cursor.CURSOR_CONFIG["base_size"] = 24.0
	smart_cursor.CURSOR_CONFIG["pulse_speed"] = 1.5
	smart_cursor.CURSOR_CONFIG["color_transition_speed"] = 0.2
	smart_cursor.CURSOR_CONFIG["halo_size"] = 1.5
	smart_cursor.CURSOR_CONFIG["rotation_speed"] = 0.5
	smart_cursor.CURSOR_CONFIG["accessibility_mode"] = false
	
	# Actualizar UI
	_load_current_settings()
	
	# Emitir señal de cambio
	settings_changed.emit()