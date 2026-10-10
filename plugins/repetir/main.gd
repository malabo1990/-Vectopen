# Repetir: copia la selección en cuadrícula o en círculo. Muestra cómo un
# complemento añade operadores, un panel de ajustes y guarda esos ajustes.
extends VectopenAddon

const DEFAULTS := {"columnas": 3, "filas": 3, "sep_x": 20.0, "sep_y": 20.0, "copias": 8, "radio": 150.0}

func _enable() -> void:
	add_operator("Cuadrícula", repetir_cuadricula, "Copia la selección en filas y columnas", "grid")
	add_operator("Círculo", repetir_circulo, "Copia la selección alrededor de un círculo", "circle")
	add_panel(_crear_panel())

func val(key: String) -> Variant:
	return get_setting(key, DEFAULTS[key])

## Filas × columnas; la separación es el hueco entre copias.
func repetir_cuadricula() -> void:
	var sel := api.selection()
	if sel.is_empty():
		api.warn("Repetir: selecciona algo primero")
		return
	var nuevas: Array = []
	for s in sel:
		var tam := _tam(s)
		for fila in int(val("filas")):
			for col in int(val("columnas")):
				if fila == 0 and col == 0:
					continue
				var off := Vector2(col * (tam.x + float(val("sep_x"))), fila * (tam.y + float(val("sep_y"))))
				nuevas.append(api.duplicate(s, off))
	api.select(sel + nuevas)

## Copias repartidas en un círculo cuyo centro es el objeto original.
func repetir_circulo() -> void:
	var sel := api.selection()
	if sel.is_empty():
		api.warn("Repetir: selecciona algo primero")
		return
	var n := int(val("copias"))
	var r := float(val("radio"))
	var nuevas: Array = []
	for s in sel:
		var centro := api.get_position(s)
		for i in n:
			var a := TAU * i / n - PI / 2.0
			var c := api.duplicate(s, Vector2.ZERO)
			api.set_position(c, centro + Vector2(cos(a), sin(a)) * r)
			api.set_rotation(c, float(api.get_prop(s, "rotation")) + rad_to_deg(a + PI / 2.0))
			nuevas.append(c)
	api.select(nuevas)

func _tam(s: Node) -> Vector2:
	var w = api.get_prop(s, "width")
	var h = api.get_prop(s, "height")
	return Vector2(float(w) if w != null else 50.0, float(h) if h != null else 50.0)

func _crear_panel() -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 6)
	for spec in [["columnas", "Columnas", 1, 50, 1], ["filas", "Filas", 1, 50, 1],
			["sep_x", "Hueco X", -500, 500, 1], ["sep_y", "Hueco Y", -500, 500, 1],
			["copias", "Copias", 2, 72, 1], ["radio", "Radio", 1, 2000, 1]]:
		var l := Label.new()
		l.text = spec[1]
		g.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = spec[2]
		sb.max_value = spec[3]
		sb.step = spec[4]
		sb.value = float(val(spec[0]))
		sb.custom_minimum_size = Vector2(70, 0)
		sb.value_changed.connect(func(v: float) -> void: set_setting(spec[0], v))
		g.add_child(sb)
	return g
