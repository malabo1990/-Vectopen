extends Control

# Variables exportadas para el editor
@export var text_size: float = 16.0 : set = _set_text_size
@export var target_nodes: Array[NodePath]  # Array de nodos objetivo
@export var slider_path: NodePath  # Camino al slider
@export var min_size: float = 8.0  # Tamaño mínimo del texto
@export var max_size: float = 72.0  # Tamaño máximo del texto
@export var show_value: bool = false  # Mostrar valor numérico en el texto
@export var size_step: float = 1.0  # Incremento del slider

# Referencias a nodos
@onready var slider = get_node_or_null(slider_path) if slider_path else $HSlider
var target_refs: Array = []

func _ready():
	# Obtener referencias a nodos objetivo
	for path in target_nodes:
		var node = get_node_or_null(path)
		if node:
			target_refs.append(node)
	
	# Configurar slider
	if slider:
		slider.min_value = min_size
		slider.max_value = max_size
		slider.value = text_size
		slider.step = size_step
		slider.connect("value_changed", _on_slider_value_changed)
	
	_update_text_size()

# Setter para text_size
func _set_text_size(new_size: float):
	text_size = clamp(new_size, min_size, max_size)
	if slider:
		slider.value = text_size
	_update_text_size()

# Actualizar tamaño de texto en todos los nodos
func _update_text_size():
	for node in target_refs:
		if node is Label or node is RichTextLabel or node is Button:
			node.set("theme_override_font_sizes/font_size", int(text_size))
			if show_value and node is Label:
				node.text = "Size: " + str(int(text_size))

# Callback del slider
func _on_slider_value_changed(value: float):
	text_size = value

# Opcional: Actualizar cuando cambian propiedades en el editor
func _process(_delta):
	if Engine.is_editor_hint():
		_update_text_size()
