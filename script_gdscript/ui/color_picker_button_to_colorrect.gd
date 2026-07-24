extends Control

@export var color_picker: ColorPickerButton
@export var color_rects: Array[ColorRect]

func _ready() -> void:
	# Verify color picker exists
	if not color_picker:
		push_error("ColorPickerButton not assigned!")
		return
	
	# Connect the color_changed signal
	color_picker.color_changed.connect(_on_color_picker_color_changed)
	
	# Validate color_rects array
	if color_rects.is_empty():
		push_warning("No ColorRect nodes assigned!")
	else:
		# Ensure all elements are valid ColorRect nodes
		for rect in color_rects:
			if not rect is ColorRect:
				push_error("Invalid node in color_rects array!")

func _on_color_picker_color_changed(color: Color) -> void:
	# Update color of all valid ColorRect nodes
	for rect in color_rects:
		if rect is ColorRect:
			rect.color = color
