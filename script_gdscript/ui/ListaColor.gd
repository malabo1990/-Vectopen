extends FlowContainer

## Paleta de muestras de color del menú contextual (inspector). Genera el
## degradado HSV y, al hacer clic en una muestra, aplica ese color de RELLENO
## a la selección vía InspectorCore (con undo).

@export var saturation: float = 0.8
@export var value: float = 0.9
## "fill" (por defecto) o "stroke" — qué propiedad cambia esta paleta.
@export_enum("fill", "stroke") var apply_to: String = "fill"

func _ready() -> void:
	await get_tree().process_frame
	actualizar_colores_hsl_extendido()
	_conectar_muestras()

func _conectar_muestras() -> void:
	for hijo in get_children():
		if hijo is ColorRect:
			hijo.mouse_filter = Control.MOUSE_FILTER_STOP
			if not hijo.gui_input.is_connected(_on_muestra_gui_input):
				hijo.gui_input.connect(_on_muestra_gui_input.bind(hijo))

func _on_muestra_gui_input(event: InputEvent, muestra: ColorRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ic := get_node_or_null("/root/InspectorCore")
		if ic:
			ic.apply("stroke_color" if apply_to == "stroke" else "fill_color", muestra.color)

func actualizar_colores_hsl_extendido() -> void:
	var hijos = get_children().filter(func(node): return node is ColorRect)
	var total_hijos = hijos.size()
	
	if total_hijos == 0:
		return

	# Definimos cuántos colores especiales queremos al final
	var especiales = 3 
	var rango_gradiente = total_hijos - especiales

	for i in range(total_hijos):
		var hijo = hijos[i]
		
		if i < rango_gradiente:
			# Gradiente de Rojo a Rojo para los primeros hijos
			var hue = float(i) / float(rango_gradiente)
			hijo.color = Color.from_hsv(hue, saturation, value)
		else:
			# Colores fijos para los últimos 3
			var posicion_final = i - rango_gradiente
			match posicion_final:
				0: hijo.color = Color(0.5, 0.5, 0.5) # Gris
				1: hijo.color = Color.WHITE          # Blanco
				2: hijo.color = Color.BLACK          # Negro
