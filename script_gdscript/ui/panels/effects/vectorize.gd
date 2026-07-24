extends Control

@onready var _generate_button: Button = $PanelContainer/MarginContainer/BoxContainer2/BoxContainer/Button2
@onready var _pixel_size_control: Control = $PanelContainer/MarginContainer/BoxContainer2/BoxContainer/BoxContainer/Control

func _ready() -> void:
	_generate_button.pressed.connect(_on_generate_pressed)

func _on_generate_pressed() -> void:
	var params = {
		"pixel_size": _pixel_size_control.get_value() if _pixel_size_control.has_method("get_value") else 1.0
	}
	GlobalEvents.emit_safe("vectorization_started", params)
