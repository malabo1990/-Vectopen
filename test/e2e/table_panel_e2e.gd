## E2E tablas v2 (VAL-56): opciones de la tabla en el inspector (Modern y
## Pro): cabecera, filas alternas, letra, alto, bordes, alineación y
## colores; con deshacer y sin perder el texto de las celdas.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func visible_ctrl(nm: String) -> Control:
	for n in root.find_children(nm, "", true, false):
		if n is Control and (n as Control).is_visible_in_tree():
			return n
	return null

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

func run_mode(mode: String) -> void:
	if not await K.boot(mode):
		K.check("%s arranca" % mode, false)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 600), "Tabla " + mode, Color.WHITE)
	var t: Node2D = api.add_table(Rect2(100, 100, 600, 0), 3, 3, [["A", "B", "C"], ["1", "2", "3"], ["4", "5", "6"]])
	await K.look_at(ab)
	api.select([t])
	await K.frames(8)
	var ic = root.get_node("InspectorCore")
	var props: Dictionary = ic.current_props()
	K.check("%s: el inspector ofrece las opciones de tabla" % mode, props.has("table_zebra") and props.has("table_header_bg") and props.has("table_align"))
	var cp := visible_ctrl("Color_table_header_bg") as ColorPickerButton
	if cp == null and mode == "professional":
		for b in root.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and String((b as Button).text).to_lower() in ["transformar", "transform"]:
				(b as Button).pressed.emit()
				await K.frames(4)
		cp = visible_ctrl("Color_table_header_bg") as ColorPickerButton
	K.check("%s: hay control «Fondo cabecera» visible" % mode, cp != null)
	if cp:
		cp.color = Color(0.8, 0.1, 0.2)
		cp.color_changed.emit(Color(0.8, 0.1, 0.2))
		await K.frames(3)
		var hb: Color = ic._read(t, "table_header_bg")
		K.check("%s: cambiar el color desde el control" % mode, _near(hb, Color(0.8, 0.1, 0.2)), str(hb))
		var row1: Node = t.find_child("Fila 1", false, false)
		K.check("%s: la fila de cabecera se repinta" % mode, row1 != null and _near(row1.fill_color, Color(0.8, 0.1, 0.2)))
	ic.apply("table_zebra", false)
	ic.apply("table_align", "center")
	ic.apply("table_font_size", 22)
	await K.frames(3)
	var s: Dictionary = t.get_meta("table")
	K.check("%s: filas alternas, alineación y letra" % mode, not bool(s["zebra"]) and String(s["align"][1]) == "center" and int(s["font_size"]) == 22)
	K.check("%s: el texto de las celdas se conserva" % mode, String(api.table_data(t)[2][1]) == "5")
	api.undo()
	await K.frames(3)
	K.check("%s: deshacer la letra (un paso)" % mode, int(t.get_meta("table")["font_size"]) == 16, str(t.get_meta("table")["font_size"]))
	await K.shot("panel_" + mode)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://table_panel")
	await run_mode("modern")
	await run_mode("professional")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
