extends Panel

# Variables exportadas para nodos
@export var gradient_node: Control  # Nodo para el gradiente (ej. TextureRect)
@export var color_display_node: Control  # Nodo para mostrar el color (ej. ColorRect)
@export var text_display_node: Control  # Nodo para mostrar el texto (ej. Label)

# Variables exportadas para configuración
@export var gradient_size: Vector2 = Vector2(400, 50)  # Tamaño del gradiente
@export var show_hex: bool = true  # Mostrar valor HEX
@export var label_prefix: String = "Color:"  # Prefijo para el texto

func _ready():
	# Verificar que los nodos exportados estén asignados
	if not gradient_node or not color_display_node or not text_display_node:
		push_error("Faltan nodos exportados en el Inspector")
		return
	
	# Ajustar el tamaño del nodo del gradiente
	gradient_node.size = gradient_size
	
	# Crear y asignar la textura de gradiente arcoíris
	if gradient_node is TextureRect:
		gradient_node.texture = create_rainbow_gradient()
	else:
		push_warning("gradient_node no es TextureRect, no se asignó textura")
	
	# Asegurarse de que el nodo del gradiente reciba eventos de ratón
	gradient_node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Conectar la señal de entrada
	gradient_node.gui_input.connect(_on_gradient_input)

func create_rainbow_gradient() -> ImageTexture:
	# Crear una imagen para el gradiente
	var image = Image.create(int(gradient_size.x), int(gradient_size.y), false, Image.FORMAT_RGBA8)
	
	# Llenar con un gradiente arcoíris (variando el tono HSV)
	for x in range(int(gradient_size.x)):
		var hue = float(x) / gradient_size.x
		var color = Color.from_hsv(hue, 1.0, 1.0)  # Saturación y valor al 100%
		for y in range(int(gradient_size.y)):
			image.set_pixel(x, y, color)
	
	# Convertir a textura
	var texture = ImageTexture.create_from_image(image)
	return texture

func _on_gradient_input(event: InputEvent):
	# Verificar si es un clic del ratón
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Obtener la posición del clic relativa al nodo del gradiente
		var local_pos = gradient_node.get_local_mouse_position()
		
		# Asegurarse de que el clic esté dentro del nodo
		if local_pos.x >= 0 and local_pos.x <= gradient_node.size.x:
			# Calcular el tono (hue)
			var hue = local_pos.x / gradient_node.size.x
			var color = Color.from_hsv(hue, 1.0, 1.0)
			
			# Actualizar el nodo de color (si es ColorRect)
			if color_display_node is ColorRect:
				color_display_node.color = color
			else:
				push_warning("color_display_node no es ColorRect")
			
			# Actualizar el nodo de texto (si es Label)
			if text_display_node is Label:
				var hsl_text = "%s HSL: %.2f, 100%%, 100%%" % [label_prefix, hue * 360]
				if show_hex:
					hsl_text += "\nHEX: %s" % color.to_html(false)
				text_display_node.text = hsl_text
			else:
				push_warning("text_display_node no es Label")
