## E2E de CONSISTENCIA VISUAL del texto sobre la app real: el texto debe
## verse IGUAL (misma caja de tinta: posición, tamaño, nº de líneas) sin
## editar (A), editando (B), al salir de editar (C) y tras guardar/recargar (D).
## Mide los píxeles oscuros de una captura real en cada estado; tolerancia 2px.
##   godot --path . -s res://test/e2e/text_consistency_e2e.gd
## (E2E_OUT=carpeta para las capturas; por defecto user://e2e_consistency)
extends SceneTree

var CS = null   # canvas_serializer (load() en runtime: con preload no compila en -s)
const TOL := 2

var out_dir := "user://e2e_consistency"
var fails: Array[String] = []
var canvas: Node2D
var cam: Camera2D

func _initialize() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "":
		out_dir = env_out
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

## Caja de tinta (píxeles casi negros) dentro de `region` de la pantalla.
## Excluye azules (selección, caret, caja de selección) y blancos.
func _ink(tag: String, region: Rect2i) -> Rect2i:
	await _frames(6)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, tag])
	var r := region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var minp := Vector2i(1 << 30, 1 << 30)
	var maxp := Vector2i(-1, -1)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			# Casi negro: excluye el gris del espacio de trabajo (~0.29),
			# azules de selección/caret y blancos.
			if c.r < 0.2 and c.g < 0.2 and c.b < 0.2:
				minp = Vector2i(mini(minp.x, x), mini(minp.y, y))
				maxp = Vector2i(maxi(maxp.x, x), maxi(maxp.y, y))
	if maxp.x < 0:
		return Rect2i()
	return Rect2i(minp, maxp - minp + Vector2i.ONE)

func _dump(tag: String, sh: Node2D) -> void:
	var v = sh.get_node_or_null("VectorRichText")
	var l = sh.get_node_or_null("DisplayLabel")
	print("  %s pos=%s meta=%sx%s fs=%s vrt=%s lab=%s" % [tag, sh.global_position, sh.get_meta("width", "-"), sh.get_meta("height", "-"), sh.get_meta("font_size", "-"),
		("pos%s size%s vis%s" % [v.position, v.size, v.visible]) if v else "-",
		("pos%s size%s vis%s mod%s" % [l.position, l.size, l.visible, l.self_modulate.a]) if l else "-"])

func _same(a: Rect2i, b: Rect2i) -> bool:
	return a.size != Vector2i.ZERO and b.size != Vector2i.ZERO \
		and absi(a.position.x - b.position.x) <= TOL and absi(a.position.y - b.position.y) <= TOL \
		and absi(a.size.x - b.size.x) <= TOL and absi(a.size.y - b.size.y) <= TOL

## Rect de pantalla del área del shape (crecido) para medir.
func _screen_region(shape: Node2D) -> Rect2i:
	var w := float(shape.get_meta("width", 350.0))
	var h := float(shape.get_meta("height", 100.0))
	var xf := canvas.get_viewport().get_canvas_transform()
	var p0: Vector2 = xf * shape.global_position
	var p1: Vector2 = xf * (shape.global_position + Vector2(w, h))
	return Rect2i(Rect2(p0, p1 - p0).grow(60.0))

func _frame_on(shape: Node2D, zoom: float) -> void:
	if cam:
		cam.zoom = Vector2(zoom, zoom)
		var w := float(shape.get_meta("width", 350.0))
		var h := float(shape.get_meta("height", 100.0))
		cam.global_position = shape.global_position + Vector2(w, h) * 0.5
	await _frames(4)

func _tool_for(shape: Node2D):
	var para := String(shape.get_meta("shape_type", "")) == "text_paragraph"
	canvas.switch_tool("paragraph" if para else "text")
	await _frames()
	return canvas.current_tool

func _edit(shape: Node2D) -> void:
	var t = await _tool_for(shape)
	if String(shape.get_meta("shape_type", "")) == "text_paragraph":
		t._check_and_trigger_edit_at(shape)
	else:
		t.target_artboard = shape.get_parent()
		t._check_and_trigger_edit_at(shape.get_parent().to_local(shape.global_position + Vector2(5, 5)))
	await _frames(3)
	# Sin selección ni caret parpadeando encima de la tinta: caret al final.
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt and vrt.is_editing():
		var n := String(shape.get_meta("text", "")).length()
		vrt.set_caret_index(n)
		vrt.set_selection_range(n, n)
	else:
		for n in ["MultiLineEdit", "TitleEdit"]:
			var ed := shape.get_node_or_null(n) as TextEdit
			if ed and ed.visible:
				ed.deselect()
				ed.set_caret_line(ed.get_line_count() - 1)
				ed.set_caret_column(ed.get_line(ed.get_line_count() - 1).length())
	await _frames(3)

## Un caso: crea el texto, mide A/B/C/D y compara.
func _case(name: String, para: bool, fs: int, txt: String, zoom: float, extra := {}) -> void:
	print("E2E CASO ", name)
	var probe := _dummy(para)
	var t = await _tool_for(probe)
	probe.free()
	var shape: Node2D = t.create_at_center()
	await _frames()
	var ic = root.get_node("InspectorCore")
	root.get_node("SelectionManager").select(shape)
	ic.apply("text", txt)
	ic.apply("font_size", fs)
	for k in extra:
		ic.apply(k, extra[k])
	await _frames(3)
	await _frame_on(shape, zoom)
	var reg := _screen_region(shape)

	_dump("A", shape)
	var a := await _ink(name + "_A_sin_editar", reg)
	await _edit(shape)
	var b := await _ink(name + "_B_editando", reg)
	await _key(KEY_ESCAPE)
	await _frames(4)
	var c := await _ink(name + "_C_tras_salir", reg)
	print("  A=%s B=%s C=%s" % [a, b, c])
	_check(a.size != Vector2i.ZERO, name + ": se ve texto sin editar")
	var align := String(extra.get("text_align", "left"))
	if not ClassDB.class_exists("VectorRichText") and align != "left":
		# Limitación CONOCIDA del modo sin extensión nativa (Web): el TextEdit
		# de Godot no tiene alineación horizontal → edita alineado a la izq.
		print("E2E KNOWN %s: sin extensión nativa el editor no centra/alinea a la derecha (A=%s B=%s)" % [name, a, b])
	else:
		_check(_same(a, b), name + ": EDITANDO se ve igual que sin editar (A=%s B=%s)" % [a, b])
	_check(_same(a, c), name + ": al SALIR se ve igual que antes (A=%s C=%s)" % [a, c])

	# D) guardar y recargar ESTE elemento (mismo camino que el .vectopen):
	#    serializar → borrar → reconstruir en el mismo artboard.
	var ab: Node = shape.get_parent()
	var data: Dictionary = CS._serialize_element(shape)
	shape.free()
	await _frames(2)
	var reloaded: Node2D = CS._element_from(data)
	if reloaded:
		ab.add_child(reloaded)
		CS._apply_transform(reloaded, data)
	await _frames(6)
	_check(reloaded != null, name + ": existe tras recargar")
	if reloaded:
		await _frame_on(reloaded, zoom)
		_dump("D", reloaded)
		var d := await _ink(name + "_D_recargado", _screen_region(reloaded))
		print("  D=%s" % [d])
		_check(_same(a, d), name + ": tras GUARDAR/RECARGAR se ve igual (A=%s D=%s)" % [a, d])
		reloaded.queue_free()
	await _frames(3)

func _dummy(para: bool) -> Node2D:
	var n := Node2D.new()
	n.set_meta("shape_type", "text_paragraph" if para else "text_title")
	return n

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	canvas = get_first_node_in_group("_vectopen_canvas")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	cam = canvas.get_node_or_null("Camera2D") if canvas else null
	print("E2E modo: ", "VectorRichText (nativo)" if ClassDB.class_exists("VectorRichText") else "TextEdit (GDScript)")

	await _case("titulo_24", false, 24, "Titulo de prueba", 1.0)
	await _case("titulo_64", false, 64, "Grande", 1.0)
	await _case("titulo_zoom3", false, 24, "Zoom tres", 3.0)
	await _case("parrafo_24", true, 24, "Un parrafo con varias palabras que debe envolver en varias lineas.", 1.0)
	await _case("parrafo_40", true, 40, "Parrafo grande que envuelve.", 1.0)
	await _case("parrafo_interlineado", true, 24, "Linea uno y mas texto. Linea dos y mas texto.", 1.0, {"line_spacing": 14})
	await _case("parrafo_centrado", true, 24, "Texto centrado en el marco del parrafo.", 1.0, {"text_align": "center"})

	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
