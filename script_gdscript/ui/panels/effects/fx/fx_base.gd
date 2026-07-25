extends PanelContainer
class_name EffectFxBase

## Base class for every effect entry added to the Effects panel's "+" list.
## Subclasses set effect_name in _ready() before calling super._ready(),
## then wire their own parameter controls via _emit_param().

signal remove_requested(fx_node: Node)

var effect_name: String = ""

@onready var _enabled_checkbox: CheckBox = %Enabled
@onready var _remove_button: Button = %Remove

func _ready() -> void:
	_enabled_checkbox.toggled.connect(_on_enabled_toggled)
	_remove_button.pressed.connect(_on_remove_pressed)

func _on_enabled_toggled(active: bool) -> void:
	_emit_param("enabled", active)

func _on_remove_pressed() -> void:
	remove_requested.emit(self)

func _emit_param(property: String, value: Variant) -> void:
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, property, value)
