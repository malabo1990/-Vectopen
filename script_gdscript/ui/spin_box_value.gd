extends Control
class_name SpinBoxValue

## Public value API for the spin_box.tscn numeric widget. ProgressBar
## (Range) already emits value_changed no matter which input path wrote
## to it - drag/buttons via ControlVertical, or direct entry via the
## calculator popup - so relaying that one signal covers all of them.

signal value_changed(value: float)

@onready var _progress_bar: ProgressBar = $BoxContainer/ProgressBar

func _ready() -> void:
	_progress_bar.value_changed.connect(func(v): value_changed.emit(v))

func get_value() -> float:
	return _progress_bar.value

func set_value(new_value: float) -> void:
	_progress_bar.value = new_value
