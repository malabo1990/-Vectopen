# Colores: operaciones de color sobre la selección.
extends VectopenAddon

func _enable() -> void:
	add_operator("Aleatorios", aleatorios, "Un color distinto para cada objeto", "random")
	add_operator("Degradado", degradado, "Del color del primero al del último, en orden de selección", "blend")
	add_operator("Invertir", invertir, "Invierte relleno y trazo", "invert")
	add_operator("Grises", grises, "Pasa relleno y trazo a escala de grises", "gray")

func _sel() -> Array:
	var sel := api.selection()
	if sel.is_empty():
		api.warn("Colores: selecciona uno o más objetos")
	return sel

func aleatorios() -> void:
	var sel := _sel()
	var h := randf()
	for s in sel:
		h = fposmod(h + 0.618034, 1.0)   # proporción áurea: tonos bien separados
		api.set_fill(s, Color.from_hsv(h, 0.6, 0.95))

func degradado() -> void:
	var sel := _sel()
	if sel.size() < 3:
		api.warn("Degradado: selecciona 3 objetos o más")
		return
	var a: Color = api.get_prop(sel[0], "fill_color")
	var b: Color = api.get_prop(sel[-1], "fill_color")
	for i in range(1, sel.size() - 1):
		api.set_fill(sel[i], a.lerp(b, float(i) / (sel.size() - 1)))

func invertir() -> void:
	for s in _sel():
		_map(s, func(c: Color) -> Color: return Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a))

func grises() -> void:
	for s in _sel():
		_map(s, func(c: Color) -> Color:
			var l := c.get_luminance()
			return Color(l, l, l, c.a))

func _map(s: Node, f: Callable) -> void:
	for p in ["fill_color", "stroke_color"]:
		var c = api.get_prop(s, p)
		if c is Color:
			api.set_prop(s, p, f.call(c))
