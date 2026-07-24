# GradientGrabber.gd
# Adjunta este script a un ColorRect que actúa como "agarrador" del gradiente.
# Emite señales al padre (GradientEditor) cuando se selecciona o se mueve.

extends ColorRect

signal grabbed(index: int)
signal moved(index: int, new_pos: float)

var index: int = 0
var dragging: bool = false

func _ready():
	# Tamaño mínimo del grabber
	custom_minimum_size = Vector2(14, 28)
	# El mouse puede interactuar con este nodo
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				grabbed.emit(index)

	if event is InputEventMouseMotion and dragging:
		var parent = get_parent()
		if parent == null:
			return
		var new_x = clamp(position.x + event.relative.x, 0.0, parent.size.x)
		position.x = new_x
		moved.emit(index, new_x / parent.size.x)

# Actualiza el aspecto visual según si está seleccionado o no
func set_selected(is_selected: bool) -> void:
	if is_selected:
		scale = Vector2(1.3, 1.3)
		modulate = Color(1, 1, 1, 1)
	else:
		scale = Vector2(1.0, 1.0)
		modulate = Color(0.8, 0.8, 0.8, 1)
