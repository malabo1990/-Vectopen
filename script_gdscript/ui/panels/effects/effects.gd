extends PanelContainer

@onready var _effects_list: BoxContainer = get_node("MarginContainer/BoxContainer/VBoxContainer/lista menu")
@onready var _blur_params: VBoxContainer = $MarginContainer/BoxContainer/VBoxContainer2

func _ready() -> void:
	_connect_effects_list()
	_connect_blur_controls_all()

func _connect_effects_list() -> void:
	for child in _effects_list.get_children():
		var checkbox = child.get_node_or_null("CheckBox")
		var button = child.get_node_or_null("Button")
		if checkbox and button:
			checkbox.toggled.connect(_on_effect_toggled.bind(button.text))

func _connect_blur_controls_all() -> void:
	for child in _blur_params.get_children():
		if child.name.begins_with("blur"):
			_connect_blur_controls(child)

func _connect_blur_controls(blur_node: Node) -> void:
	for child in blur_node.get_children():
		if child is HBoxContainer:
			var control = child.get_node_or_null("Control")
			if control and control.has_signal("value_changed"):
				control.value_changed.connect(_on_effect_param_changed.bind(blur_node.name, "value"))

			var checkbox = child.get_node_or_null("CheckBox")
			if checkbox and checkbox.has_signal("toggled"):
				checkbox.toggled.connect(_on_effect_param_changed.bind(blur_node.name, "alpha"))

func _on_effect_toggled(active: bool, effect_name: String) -> void:
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, "enabled", active)

func _on_effect_param_changed(value: Variant, effect_name: String, property: String) -> void:
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, property, value)
