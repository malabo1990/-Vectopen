extends Control

@export var color_rect: ColorRect
@export var line_edit: LineEdit
signal color_changed(new_color: Color) # Señal para notificar cambios desde el LineEdit

func _ready():
	# Validar que los nodos estén asignados
	if not color_rect or not line_edit:
		push_error("ColorRect o LineEdit no están asignados en el Inspector")
		return
	# Conectar señales
	line_edit.text_changed.connect(_on_line_edit_text_changed)
	line_edit.text_submitted.connect(_on_line_edit_submitted)
	# Establecer color inicial
	update_line_edit_from_color()
	# Sincronía con ColorCore (aplica a la selección con undo).
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_signal("changed") and not cc.changed.is_connected(_on_colorcore_changed):
		cc.changed.connect(_on_colorcore_changed)

func _on_line_edit_submitted(txt: String) -> void:
	var c := Color.from_string(txt.strip_edges(), color_rect.color if color_rect else Color.WHITE)
	if color_rect:
		color_rect.color = c
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_color"):
		cc.set_color(c)

func _on_colorcore_changed(fill: Color, _stroke: Color, _target: String) -> void:
	if color_rect and color_rect.color != fill:
		color_rect.color = fill
		update_line_edit_from_color()

# Actualiza el ColorRect cuando cambia el texto del LineEdit en tiempo real
func _on_line_edit_text_changed(new_text: String):
	if not color_rect or not line_edit:
		return
	# Formato esperado: "#RRGGBB" (ejemplo: "#1100FF") o entrada parcial
	var clean_text = new_text.strip_edges().to_upper()
	if clean_text.begins_with("#"):
		clean_text = clean_text.substr(1) # Quitar el '#'
	
	# Validar formato hexadecimal (hasta 6 caracteres)
	if clean_text.length() <= 6 and (clean_text.is_valid_hex_number() or clean_text.length() == 0):
		# Solo actualizar si es un color válido completo
		if clean_text.length() == 6:
			var color = Color.from_string("#" + clean_text, color_rect.color) # Usar color actual como fallback
			if color != color_rect.color: # Evitar bucles innecesarios
				color_rect.color = color
				emit_signal("color_changed", color) # Emitir señal para el Panel
	# Si el texto no es válido, no actualizar el LineEdit para evitar sobrescribir la entrada del usuario

# Actualiza el LineEdit cuando cambia el color del ColorRect
func update_line_edit_from_color():
	if not color_rect or not line_edit:
		return
	var hex_color = color_rect.color.to_html(false) # false para omitir canal alfa
	if line_edit.text != "#" + hex_color.to_upper():
		line_edit.text = "#" + hex_color.to_upper() # Solo actualizar si es diferente

# Se llama cuando el Panel (color picker) cambia el color
func _on_color_picker_color_changed(new_color: Color):
	if not color_rect:
		return
	if color_rect.color != new_color: # Evitar bucles innecesarios
		color_rect.color = new_color
		update_line_edit_from_color()
