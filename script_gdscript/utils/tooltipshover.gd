extends Control

@export var target_node: Control
@export var tooltip: Control
@export var tooltip_label: Label
@export var tooltip_texture: TextureRect

func _ready():
	# Ocultar el tooltip al inicio
	tooltip.visible = false
	# Conectar señales de entrada de mouse
	target_node.connect("gui_input", Callable(self, "_on_gui_input"))

func _process(delta):
	if tooltip.visible:
		var mouse_position = get_global_mouse_position()
		tooltip.rect_global_position = mouse_position + Vector2(10, 10) # Ajuste para que no esté justo debajo del mouse

func _on_gui_input(event):
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if target_node.get_rect().has_point(event.position):
			_show_tooltip(event.position)
		else:
			tooltip.visible = false

func _show_tooltip(position):
	# Configurar el texto del tooltip
	tooltip_label.text = "Información del nodo"
	
	# Configurar la imagen del tooltip si es necesario
	# var img_texture = ImageTexture.new()
	# img_texture.load("res://ruta/a/tu/imagen.png")
	# tooltip_texture.texture = img_texture
	
	tooltip.rect_global_position = position
	tooltip.visible = true
