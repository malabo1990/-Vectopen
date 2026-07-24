extends Control

@export var ui_elements: Array[Control] = []
@export var color_picker_button: ColorPickerButton

func _ready():
	# Verificar si color_picker_button está asignado
	if color_picker_button == null:
		push_error("ColorPickerButton no asignado. Por favor, asígnalo en el Inspector.")
		return
	
	# Conectar la señal color_changed de manera segura
	if not color_picker_button.color_changed.is_connected(_on_color_changed):
		var error = color_picker_button.color_changed.connect(_on_color_changed)
		if error != OK:
			push_error("No se pudo conectar la señal color_changed: ", error_string(error))
	
	# Verificar que ui_elements no contenga nodos nulos
	for element in ui_elements:
		if element == null:
			push_warning("Elemento nulo encontrado en ui_elements. Revisa la configuración en el Inspector.")

func _on_color_changed(new_color: Color):
	# Verificar que ui_elements no esté vacío
	if ui_elements.is_empty():
		push_warning("El arreglo ui_elements está vacío. No hay elementos para aplicar el color.")
		return
	
	# Aplicar el color a cada elemento
	for element in ui_elements:
		if element != null:  # Evitar procesar elementos nulos
			apply_color_to_element(element, new_color)
		else:
			push_warning("Elemento nulo en ui_elements durante _on_color_changed.")

func apply_color_to_element(element: Control, color: Color):
	# Manejar diferentes tipos de controles
	if element is ColorRect:
		element.color = color
	elif element is Panel or element is Button or element is PanelContainer:
		apply_stylebox_color(element, color)
	else:
		# Aplicar un StyleBoxFlat para otros controles
		var style = StyleBoxFlat.new()
		style.bg_color = color
		if element.has_theme_stylebox("normal"):
			element.add_theme_stylebox_override("normal", style)
		else:
			push_warning("El elemento ", element.name, " no soporta el estilo 'normal'.")
	
	# Forzar redibujado del elemento
	if element.is_inside_tree():  # Verificar que el elemento esté en el árbol de nodos
		element.queue_redraw()
	else:
		push_warning("El elemento ", element.name, " no está en el árbol de nodos.")

func apply_stylebox_color(element: Control, color: Color):
	var style_names = ["panel", "normal", "hover", "pressed", "focus", "disabled"]
	
	for style_name in style_names:
		if element.has_theme_stylebox(style_name):
			var style = element.get_theme_stylebox(style_name)
			
			# Si el estilo no es StyleBoxFlat, crear uno nuevo
			if not style is StyleBoxFlat:
				style = StyleBoxFlat.new()
			
			style.bg_color = color
			element.add_theme_stylebox_override(style_name, style)
		else:
			# Advertencia para estilos no soportados
			push_warning("El elemento ", element.name, " no soporta el estilo ", style_name)
