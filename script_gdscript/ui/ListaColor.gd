extends FlowContainer

@export var saturation: float = 0.8
@export var value: float = 0.9

func _ready() -> void:
	await get_tree().process_frame
	actualizar_colores_hsl_extendido()

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
