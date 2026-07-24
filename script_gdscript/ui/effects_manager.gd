extends Control

# Centraliza los datos del panel de efectos y conecta la UI con el sistema GlobalEvents

func _ready() -> void:
	_connect_ui_signals()

func _connect_ui_signals() -> void:
	# 1. BotÃ³n de generaciÃ³n -> Vectorization Started
	var btn_gen = get_node_or_null("%Button2")
	if btn_gen:
		btn_gen.pressed.connect(_on_generation_vectorizer_pressed)
	
	# 2. Lista de efectos (activaciÃ³n)
	var effects_list = get_node_or_null("%lista menu")
	if effects_list:
		for child in effects_list.get_children():
			var checkbox = child.get_node_or_null("CheckBox")
			var button = child.get_node_or_null("Button")
			if checkbox and button:
				checkbox.toggled.connect(_on_effect_toggled.bind(button.text))
				
	# 3. Conectar sliders/controles de parÃ¡metros dentro de los contenedores de blur
	var blur_container = get_node_or_null("%VBoxContainer2")
	if blur_container:
		for child in blur_container.get_children():
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

func _on_generation_vectorizer_pressed() -> void:
	var p1 = get_node_or_null("%Control")
	var params = {
		"pixel_size": p1.get_value() if p1 and p1.has_method("get_value") else 1.0
	}
	GlobalEvents.emit_safe("vectorization_started", params)

func _on_effect_toggled(active: bool, effect_name: String) -> void:
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, "enabled", active)

func _on_effect_param_changed(value: Variant, effect_name: String, property: String) -> void:
	GlobalEvents.emit_safe("effect_parameter_updated", effect_name, property, value)
