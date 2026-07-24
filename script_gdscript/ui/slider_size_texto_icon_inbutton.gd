extends Node

# Exportar el array de botones y el slider
@export var target_buttons: Array[Button]
@export var size_slider: HSlider

# Diccionario para almacenar los íconos originales
var original_icons: Dictionary = {}

func _ready():
	# Verificar si el slider y los botones están asignados
	if not size_slider:
		print("Error: Slider no asignado en el editor.")
		return
	if target_buttons.size() == 0:
		print("Error: No se han asignado botones en el editor.")
		return
	
	# Almacenar íconos originales solo para botones con ícono
	for button in target_buttons:
		if button and button.icon:
			original_icons[button] = button.icon
	
	# Conectar la señal de cambio de valor del slider
	size_slider.value_changed.connect(_on_slider_value_changed)
	
	# Inicializar los botones con el valor inicial del slider
	_on_slider_value_changed(size_slider.value)

func _on_slider_value_changed(value: float):
	# Usar el valor del slider directamente como tamaño de texto
	var font_size = int(value)
	# Escalar el ícono proporcionalmente al valor del slider (usando un factor base)
	var icon_scale = value / 50.0  # Ajusta el divisor para controlar la sensibilidad del escalado
	
	# Aplicar los cambios a cada botón
	for button in target_buttons:
		if button and is_instance_valid(button):
			# Detectar y aplicar solo si el botón tiene texto
			if button.text != "":
				button.add_theme_font_size_override("font_size", font_size)
			
			# Ajustar tamaño del ícono solo si tiene ícono original
			if button in original_icons:
				var orig_tex = original_icons[button]
				var img = orig_tex.get_image()
				var new_size_x = max(1, int(img.get_width() * icon_scale))  # Evitar tamaño 0
				var new_size_y = max(1, int(img.get_height() * icon_scale))
				img.resize(new_size_x, new_size_y, Image.INTERPOLATE_BILINEAR)
				var new_tex = ImageTexture.create_from_image(img)
				button.icon = new_tex
			
			# Forzar actualización visual
			button.queue_redraw()
			button.update_minimum_size()
		else:
			print("Error: Uno de los botones en el array no está asignado.")
