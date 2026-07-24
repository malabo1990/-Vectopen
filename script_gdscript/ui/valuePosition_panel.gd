extends Control

@export var drag_control: Control
@export var value_lineedit: LineEdit
@export var increment_button: Button
@export var decrement_button: Button

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var step: float = 1.0

var current_value: float = 0.0
var is_dragging: bool = false

func _ready():
	# Conectar señales
	if drag_control:
		drag_control.gui_input.connect(_on_drag_control_gui_input)
	if value_lineedit:
		value_lineedit.text_submitted.connect(_on_lineedit_text_submitted)
	if increment_button:
		increment_button.pressed.connect(_on_increment_pressed)
	if decrement_button:
		decrement_button.pressed.connect(_on_decrement_pressed)
	
	# Inicializar LineEdit
	update_lineedit()

func _on_drag_control_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
		else:
			is_dragging = false
	elif event is InputEventMouseMotion and is_dragging:
		# Mover hacia la izquierda reduce, hacia la derecha aumenta
		var delta = event.relative.x * 0.1  # Sensibilidad del arrastre
		update_value(current_value + delta)

func _on_lineedit_text_submitted(new_text: String):
	var new_value = float(new_text)
	update_value(new_value)

func _on_increment_pressed():
	update_value(current_value + step)

func _on_decrement_pressed():
	update_value(current_value - step)

func update_value(new_value: float):
	# Limitar el valor entre min y max
	current_value = clamp(new_value, min_value, max_value)
	# Redondear según el paso
	current_value = round(current_value / step) * step
	# Actualizar LineEdit
	update_lineedit()

func update_lineedit():
	if value_lineedit:
		value_lineedit.text = str(current_value)
