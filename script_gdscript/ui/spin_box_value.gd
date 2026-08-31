extends Control
class_name SpinBoxValue

## Widget numérico reutilizable (spin_box.tscn).
## Salida:  value_changed(value) - se emite ante cualquier cambio de valor
##          (botones < >, arrastre vertical o set_value).
## Entrada: set_value(v) o la propiedad exportada `value` (inspector/código).
## Config:  min_value, max_value, step, sensitivity - exportadas y
##          sincronizadas con el ControlVertical interno.

signal value_changed(value: float)

@export_range(-1000000.0, 1000000.0, 0.01) var min_value: float = 0.0:
	set(v):
		min_value = v
		if _progress_bar:
			_progress_bar.min_value = v

@export_range(-1000000.0, 1000000.0, 0.01) var max_value: float = 100.0:
	set(v):
		max_value = v
		if _progress_bar:
			_progress_bar.max_value = v

@export_range(0.001, 100000.0, 0.001) var step: float = 1.0:
	set(v):
		step = v
		if _control_vertical:
			_control_vertical.paso_incremento = v

@export_range(0.01, 10.0, 0.01) var sensitivity: float = 0.5:
	set(v):
		sensitivity = v
		if _control_vertical:
			_control_vertical.sensibilidad_drag = v

@export var value: float = 0.0:
	set(v):
		value = clampf(v, min_value, max_value)
		if _progress_bar:
			_progress_bar.value = value

@onready var _progress_bar: ProgressBar = $BoxContainer/ProgressBar
@onready var _control_vertical: ControlVertical = $BoxContainer/Button

func _ready() -> void:
	_progress_bar.min_value = min_value
	_progress_bar.max_value = max_value
	_progress_bar.value = value
	_control_vertical.valor_minimo = min_value
	_control_vertical.valor_maximo = max_value
	_control_vertical.paso_incremento = step
	_control_vertical.sensibilidad_drag = sensitivity
	_progress_bar.value_changed.connect(_on_progress_changed)

func _on_progress_changed(new_value: float) -> void:
	value = new_value
	value_changed.emit(new_value)

func get_value() -> float:
	return _progress_bar.value if _progress_bar else value

func set_value(new_value: float) -> void:
	value = new_value
