@tool
extends Node

@export var slider: Slider
@export var text_nodes: Array[Label]

@export_range(1, 100, 1) var min_font_size: int = 12
@export_range(1, 100, 1) var max_font_size: int = 48

func _ready():
	if slider:
		slider.min_value = min_font_size
		slider.max_value = max_font_size
		slider.value = min_font_size
		slider.value_changed.connect(_on_slider_value_changed)
	
	_update_text_sizes(min_font_size)

func _process(_delta):
	if slider:
		_update_text_sizes(slider.value)

func _on_slider_value_changed(value: float):
	_update_text_sizes(value)

func _update_text_sizes(size: float):
	for text_node in text_nodes:
		if text_node:
			text_node.add_theme_font_size_override("font_size", int(size))
