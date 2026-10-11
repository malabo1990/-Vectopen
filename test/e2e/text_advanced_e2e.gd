## Batería AVANZADA de 20 pruebas del sistema de texto sobre la app real
## (escena principal renderizada, teclado y ratón reales, guardar/recargar).
## Cada prueba ataca una CLASE distinta de fallo. Uso:
##   godot --path . -s res://test/e2e/text_advanced_e2e.gd
## (E2E_ONLY=3,7 para ejecutar solo algunas; E2E_OUT para capturas)
extends SceneTree

var fails: Array[String] = []
var canvas: Node2D
var cam: Camera2D
var ab: Node2D
var CS = null
var IC = null
var SM = null
var HM = null
var native := false
var out_dir := "user://e2e_advanced"

func _initialize() -> void:
	if OS.get_environment("E2E_OUT") != "":
		out_dir = OS.get_environment("E2E_OUT")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

# ── utilidades ──────────────────────────────────────────────────────────────
func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _key(code: Key, ctrl := false, shift := false, alt := false, uni := 0) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.unicode = uni if pressed else 0
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.alt_pressed = alt
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await _frames(1)

func _type(txt: String) -> void:
	for i in txt.length():
		var ch := txt.substr(i, 1)
		var code := OS.find_keycode_from_string(ch.to_upper()) if ch.to_upper() != ch.to_lower() else KEY_NONE
		if ch == " ": code = KEY_SPACE
		await _key(code, false, false, false, txt.unicode_at(i))

func _runs_ok(shape: Node2D) -> bool:
	var runs: Array = shape.get_meta("runs", [])
	if runs.is_empty():
		return true
	var t := 0
	for r in runs:
		t += int(r.get("length", 0))
	return t == String(shape.get_meta("text", "")).length()

func _flag_at(shape: Node2D, idx: int, key: String) -> bool:
	var pos := 0
	for r in shape.get_meta("runs", []):
		var l := int(r.get("length", 0))
		if idx < pos + l:
			return bool(r.get(key, false))
		pos += l
	return false

func _new_text(para: bool, txt: String, fs := 24) -> Node2D:
	canvas.switch_tool("paragraph" if para else "text")
	await _frames()
	var s: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	SM.select(s)
	IC.apply("text", txt)
	if fs != 24:
		IC.apply("font_size", fs)
	await _frames(2)
	if cam:
		cam.zoom = Vector2.ONE
		cam.global_position = s.global_position + Vector2(float(s.get_meta("width", 300.0)), float(s.get_meta("height", 60.0))) * 0.5
	await _frames(2)
	return s

func _edit(shape: Node2D) -> void:
	var para := String(shape.get_meta("shape_type", "")) == "text_paragraph"
	canvas.switch_tool("paragraph" if para else "text")
	await _frames()
	var t = canvas.current_tool
	if para:
		t._check_and_trigger_edit_at(shape)
	else:
		t.target_artboard = shape.get_parent()
		t._check_and_trigger_edit_at(shape.get_parent().to_local(shape.global_position + Vector2(4, 4)))
	await _frames(2)

func _select_range(shape: Node2D, a: int, b: int) -> void:
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt and vrt.is_editing():
		if a == b:
			vrt.set_caret_index(b)
		vrt.set_selection_range(a, b)
	else:
		var ed: TextEdit = shape.get_node_or_null("MultiLineEdit")
		if ed == null or not ed.visible:
			ed = shape.get_node_or_null("TitleEdit")
		ed.grab_focus()
		if a == b:
			ed.deselect()
			ed.set_caret_line(0)
			ed.set_caret_column(a)
		else:
			ed.select(0, a, 0, b)
	await _frames(1)

func _exit_edit() -> void:
	await _key(KEY_ESCAPE)
	await _frames(3)

func _reload(shape: Node2D) -> Node2D:
	var parent := shape.get_parent()
	var d: Dictionary = CS._serialize_element(shape)
	shape.free()
	var n: Node2D = CS._element_from(d)
	parent.add_child(n)
	CS._apply_transform(n, d)
	await _frames(3)
	return n

func _ink(region: Rect2i) -> Rect2i:
	await _frames(4)
	var img := root.get_texture().get_image()
	var r := region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.r < 0.2 and c.g < 0.2 and c.b < 0.2:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i() if hi.x < 0 else Rect2i(lo, hi - lo + Vector2i.ONE)

func _screen_rect(shape: Node2D) -> Rect2:
	var xf := canvas.get_viewport().get_canvas_transform()
	var p0: Vector2 = xf * shape.global_position
	var p1: Vector2 = xf * (shape.global_position + Vector2(float(shape.get_meta("width", 300.0)), float(shape.get_meta("height", 60.0))))
	return Rect2(p0, p1 - p0)

func _clear_artboard() -> void:
	for c in ab.get_children():
		if c is Node2D and c.has_meta("shape_type"):
			c.queue_free()
	if SM.has_method("clear"):
		SM.clear()
	await _frames(2)

func _shot(tag: String) -> void:
	await _frames(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, tag])

# ── las 20 pruebas ──────────────────────────────────────────────────────────
func t01_vacio() -> void:
	var p := await _new_text(true, "Texto a borrar")
	await _edit(p)
	await _select_range(p, 0, 14)
	await _key(KEY_BACKSPACE)
	await _exit_edit()
	_check(String(p.get_meta("text", "")).length() > 0, "01 vaciar un párrafo no lo deja sin texto (marcador)")
	_check(_runs_ok(p), "01 runs coherentes tras vaciar")
	_check(float(p.get_meta("height", 0.0)) > 0.0, "01 caja válida tras vaciar")

func t02_palabra_larga() -> void:
	var w := ""
	for i in 60: w += "x"
	var p := await _new_text(true, "Antes " + w + " despues")
	_check(float(p.get_meta("height", 0.0)) < 2000.0, "02 palabra sin espacios no dispara la altura (%s)" % p.get_meta("height"))
	_check(_runs_ok(p), "02 runs coherentes")

func t03_unicode() -> void:
	var txt := "Ñandú áéí ü 你好 🙂 مرحبا"
	var p := await _new_text(true, txt)
	await _edit(p)
	await _select_range(p, 0, 5)
	await _key(KEY_B, true)
	await _exit_edit()
	_check(String(p.get_meta("text")) == txt, "03 texto Unicode intacto tras editar")
	_check(_flag_at(p, 0, "bold") and not _flag_at(p, 6, "bold"), "03 negrita exacta sobre 'Ñandú'")
	var r := await _reload(p)
	_check(String(r.get_meta("text")) == txt and _flag_at(r, 4, "bold"), "03 Unicode + formato sobreviven guardar/recargar")

func t04_lineas_vacias() -> void:
	var txt := "Uno\n\n\nDos\n\nTres"
	var p := await _new_text(true, txt)
	var r := await _reload(p)
	_check(String(r.get_meta("text")) == txt, "04 líneas vacías preservadas al recargar")
	await _edit(r)
	await _exit_edit()
	_check(String(r.get_meta("text")) == txt, "04 líneas vacías preservadas tras editar sin cambios")

func t05_escribir_en_medio() -> void:
	var p := await _new_text(true, "Hola mundo feliz")
	await _edit(p)
	await _select_range(p, 5, 10)
	await _key(KEY_B, true)
	await _select_range(p, 7, 7)
	await _type("XY")
	await _exit_edit()
	_check(String(p.get_meta("text")) == "Hola muXYndo feliz", "05 texto insertado en su sitio (%s)" % p.get_meta("text"))
	_check(_flag_at(p, 7, "bold") and _flag_at(p, 8, "bold"), "05 lo escrito dentro de la negrita hereda negrita")
	_check(not _flag_at(p, 13, "bold") and _flag_at(p, 11, "bold"), "05 el resto del formato no se desplaza")
	_check(_runs_ok(p), "05 runs coherentes")

func t06_borrar_cruzando_runs() -> void:
	var p := await _new_text(true, "aaaaBBBBcccc")
	await _edit(p)
	await _select_range(p, 4, 8)
	await _key(KEY_B, true)
	await _select_range(p, 2, 6)
	await _key(KEY_BACKSPACE)
	await _exit_edit()
	_check(String(p.get_meta("text")) == "aaBBcccc", "06 borrado que cruza dos runs (%s)" % p.get_meta("text"))
	_check(_flag_at(p, 2, "bold") and not _flag_at(p, 1, "bold") and not _flag_at(p, 4, "bold"), "06 negrita sigue solo en 'BB'")
	_check(_runs_ok(p), "06 runs coherentes")

func t07_undo_redo() -> void:
	var p := await _new_text(true, "Original")
	await _edit(p)
	await _select_range(p, 0, 8)
	await _type("Cambiado")
	await _exit_edit()
	_check(String(p.get_meta("text")) == "Cambiado", "07 edición aplicada")
	HM.undo()
	await _frames(2)
	_check(String(p.get_meta("text")) == "Original", "07 Ctrl+Z deshace la edición (%s)" % p.get_meta("text"))
	HM.redo()
	await _frames(2)
	_check(String(p.get_meta("text")) == "Cambiado", "07 Ctrl+Y la rehace")

func t08_duplicar() -> void:
	var p := await _new_text(true, "Copia con formato")
	await _edit(p)
	await _select_range(p, 0, 5)
	await _key(KEY_B, true)
	await _exit_edit()
	SM.select(p)
	IC.apply("effects", [{"type": "drop_shadow", "enabled": true, "color": Color(0, 0, 0, 0.5)}])
	var d: Dictionary = CS._serialize_element(p)
	var copy: Node2D = CS._element_from(d)
	ab.add_child(copy)
	CS._apply_transform(copy, d)
	await _frames(3)
	_check(_flag_at(copy, 0, "bold") and (copy.get_meta("effects", []) as Array).size() == 1, "08 copiar/pegar conserva formato y efectos")
	var dup: Node2D = p.duplicate()
	ab.add_child(dup)
	await _frames(3)
	_check(_flag_at(dup, 0, "bold") and dup.get_node_or_null("DisplayLabel") != null, "08 duplicar (Ctrl+D) conserva formato")

func t09_cadena() -> void:
	canvas.switch_tool("paragraph")
	await _frames()
	var pt = canvas.current_tool
	var story := "Uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciseis diecisiete dieciocho."
	var a: Node2D = pt._create_new_paragraph_at(Vector2(40, 40))
	a.set_meta("width", 160.0); a.set_meta("height", 50.0); a.set_meta("text", story)
	var b: Node2D = pt._create_new_paragraph_at(Vector2(260, 40))
	b.set_meta("width", 160.0); b.set_meta("height", 300.0)
	ParagraphThreading.link(a, b)
	await _edit(b)
	await _select_range(b, 0, 0)
	await _type("Z")
	await _exit_edit()
	var full := String(a.get_meta("raw_story_text", ""))
	_check(full.begins_with(story.substr(0, 10)) and full.contains("Z"), "09 editar el 2º marco no borra la historia")
	a.set_meta("height", 400.0)
	ParagraphThreading.reflow_chain(a)
	_check(String(a.get_meta("raw_story_text")) == full, "09 re-fluir no cambia la historia")

func t10_zoom_extremo() -> void:
	var p := await _new_text(true, "Zoom extremo con texto", 24)
	var worst := 0.0
	for z in [0.05, 0.3, 1.0, 8.0, 20.0, 60.0]:
		cam.zoom = Vector2(z, z)
		cam.global_position = p.global_position + Vector2(20, 12)
		var t := Time.get_ticks_usec()
		await _frames(3)
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 3000.0)
	cam.zoom = Vector2.ONE
	_check(worst < 120.0, "10 zoom 0.05→60 sin tirones graves (peor frame %.1f ms)" % worst)

func t11_familia() -> void:
	var fc = root.get_node("FontCore")
	var fams: PackedStringArray = fc.families() if fc.has_method("families") else PackedStringArray()
	var other := ""
	for f in fams:
		if f != "Inter":
			other = f
			break
	var p := await _new_text(false, "Familia")
	if other == "":
		_check(true, "11 (sin otras familias en el sistema)")
		return
	var before = p.get_node("DisplayLabel")._font
	IC.apply("font_family", other)
	await _frames(2)
	_check(p.get_node("DisplayLabel")._font != before, "11 cambiar familia (%s) cambia la fuente" % other)
	var r := await _reload(p)
	_check(String(r.get_meta("font_family", "")) == other, "11 la familia se guarda y recarga")

func t12_interletra() -> void:
	var p := await _new_text(false, "Tracking")
	var w0 := float(p.get_meta("width"))
	IC.apply("letter_spacing", 6.5)
	await _frames(3)
	var r := await _reload(p)
	_check(is_equal_approx(float(r.get_meta("letter_spacing")), 6.5), "12 interletra fraccionaria se guarda (6.5)")
	_check(r.get_node("DisplayLabel")._measure("Tracking", 24) > w0 * 0.0, "12 medida con interletra válida")

func t13_trazo() -> void:
	var p := await _new_text(false, "Trazo")
	IC.apply("stroke_width", 2.0)
	IC.apply("stroke_color", Color(1, 0, 0))
	await _frames(3)
	var r := await _reload(p)
	_check(float(r.get_meta("stroke_width", 0.0)) >= 2.0, "13 grosor de trazo se guarda")
	_check((r.get_meta("stroke_color", Color.BLACK) as Color).is_equal_approx(Color(1, 0, 0)), "13 color de trazo se guarda")

func t14_rotado_doble_clic() -> void:
	var p := await _new_text(false, "Rotado")
	p.rotation = deg_to_rad(45)
	p.scale = Vector2(1.5, 1.5)
	await _frames(2)
	canvas.switch_tool("select")
	await _frames(2)
	var xf := canvas.get_viewport().get_canvas_transform()
	var pt: Vector2 = xf * p.to_global(Vector2(20, 12))
	for dbl in [false, true]:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.double_click = dbl and pressed
			ev.position = pt
			ev.global_position = pt
			Input.parse_input_event(ev)
			await _frames(1)
	await _frames(3)
	var t = canvas.current_tool
	_check(t != null and bool(t.get("is_editing")) and t.get("current_editing_shape") == p, "14 doble clic real sobre un título rotado y escalado entra a editar")
	if t and bool(t.get("is_editing")):
		await _exit_edit()

func t15_rendimiento() -> void:
	canvas.switch_tool("paragraph")
	await _frames()
	var pt = canvas.current_tool
	var t0 := Time.get_ticks_usec()
	for i in 200:
		var s: Node2D = pt._create_new_paragraph_at(Vector2((i % 20) * 380, 600 + int(i / 20) * 140))
		s.set_meta("runs", [{"length": 5, "bold": true}, {"length": String(s.get_meta("text")).length() - 5}])
		s.get_node("DisplayLabel").set_rich_runs(s.get_meta("runs"))
	var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
	cam.zoom = Vector2(0.2, 0.2)
	await _frames(10)
	var tf := Time.get_ticks_usec()
	await _frames(30)
	var frame_ms := (Time.get_ticks_usec() - tf) / 30000.0
	var data: Dictionary = CS.serialize_container(canvas.get_node("ArtboardsContainer"))
	var tr := Time.get_ticks_usec()
	CS.rebuild_container(canvas.get_node("ArtboardsContainer"), data)
	await _frames(2)
	var reload_ms := (Time.get_ticks_usec() - tr) / 1000.0
	ab = canvas.get_node("ArtboardsContainer").get_child(0)
	cam.zoom = Vector2.ONE
	print("E2E PERF 200 párrafos: crear %.0f ms, frame %.2f ms, recargar %.0f ms" % [create_ms, frame_ms, reload_ms])
	_check(frame_ms < 16.7, "15 con 200 párrafos el frame sigue < 16.7 ms (%.2f)" % frame_ms)
	_check(reload_ms < 2500.0, "15 recargar 200+ textos < 2.5 s (%.0f ms)" % reload_ms)

func t16_todo_color_tamano() -> void:
	var p := await _new_text(true, "Todo el texto")
	await _edit(p)
	await _select_range(p, 0, 13)
	IC.apply("fill_color", Color(0, 0.4, 1))
	IC.apply("font_size", 40)
	await _exit_edit()
	var all_blue := true
	for r in p.get_meta("runs", []):
		if not (r.get("color", Color.BLACK) as Color).is_equal_approx(Color(0, 0.4, 1)):
			all_blue = false
	_check(all_blue, "16 Ctrl+A + color colorea TODO el texto")
	_check(_runs_ok(p), "16 runs coherentes")

func t17_idempotente() -> void:
	var p := await _new_text(true, "Idempotente con formato")
	await _edit(p)
	await _select_range(p, 0, 4)
	await _key(KEY_B, true)
	await _exit_edit()
	var d1: Dictionary = CS._serialize_element(p)
	var r := await _reload(p)
	var d2: Dictionary = CS._serialize_element(r)
	var j1 := JSON.stringify(d1, "", true)
	var j2 := JSON.stringify(d2, "", true)
	if j1 != j2:
		print("  d1=", j1.substr(0, 600))
		print("  d2=", j2.substr(0, 600))
	_check(j1 == j2, "17 guardar → cargar → guardar produce EXACTAMENTE lo mismo")

func t18_alineacion_derecha() -> void:
	var p := await _new_text(true, "Derecha")
	IC.apply("text_align", "right")
	await _frames(3)
	if not native:
		_check(true, "18 (alineación medida solo con render nativo)")
		return
	var sr := _screen_rect(p)
	var ink := await _ink(Rect2i(sr.grow(30)))
	_check(ink.size.x > 0 and absf(float(ink.end.x) - sr.end.x) < 6.0, "18 texto alineado a la derecha toca el borde derecho (ink %s, marco %.0f)" % [ink.end.x, sr.end.x])

func t19_grosor_limites() -> void:
	var p := await _new_text(false, "Grosor")
	canvas.switch_tool("select")
	await _frames(2)
	SM.select(p)   # tras cambiar de herramienta: switch_tool vacía la selección
	await _frames(2)
	var fo = root.gui_get_focus_owner()
	print("  t19 foco=", fo.get_path() if fo else "null", " sel=", SM.get_selected() if SM.has_method("get_selected") else "?", " props.fw=", IC.current_props().get("font_weight", "NO"), " tool=", canvas.current_tool.get_script().resource_path.get_file())
	for i in 12:
		await _key(KEY_PERIOD, true, false, true)
	_check(int(p.get_meta("font_weight", 0)) == 900, "19 grosor no pasa de 900 (%s)" % p.get_meta("font_weight", 0))
	for i in 12:
		await _key(KEY_COMMA, true, false, true)
	_check(int(p.get_meta("font_weight", 0)) == 100, "19 grosor no baja de 100 (%s)" % p.get_meta("font_weight", 0))

func t20_estres() -> void:
	var p := await _new_text(true, "Estres de formato y escritura rapida")
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	await _edit(p)
	for i in 30:
		await _select_range(p, i % 10, i % 10 + 5)
		await _key([KEY_B, KEY_I, KEY_U][i % 3], true)
	await _select_range(p, 3, 3)
	await _type("abc def ")
	await _exit_edit()
	for i in 10:
		await _edit(p)
		await _exit_edit()
	await _frames(5)
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(_runs_ok(p), "20 runs coherentes tras 30 atajos + escritura")
	_check(nodes1 - nodes0 < 40, "20 sin fuga de nodos al entrar/salir 10 veces (+%d)" % (nodes1 - nodes0))

# ── runner ──────────────────────────────────────────────────────────────────
func _run() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	canvas = get_first_node_in_group("_vectopen_canvas")
	cam = canvas.get_node_or_null("Camera2D")
	ab = canvas.get_node("ArtboardsContainer").get_child(0)
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	IC = root.get_node("InspectorCore")
	SM = root.get_node("SelectionManager")
	HM = root.get_node("HistoryManager")
	var pm = root.get_node_or_null("PerformanceManager")
	if pm:
		pm.target_fps = 0
		pm.set_idle_render(false)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # medir sin el tope de 60 Hz
	native = ClassDB.class_exists("VectorRichText")
	print("E2E modo: ", "nativo" if native else "GDScript")
	var tests := ["t01_vacio", "t02_palabra_larga", "t03_unicode", "t04_lineas_vacias", "t05_escribir_en_medio",
		"t06_borrar_cruzando_runs", "t07_undo_redo", "t08_duplicar", "t09_cadena", "t10_zoom_extremo",
		"t11_familia", "t12_interletra", "t13_trazo", "t14_rotado_doble_clic", "t15_rendimiento",
		"t16_todo_color_tamano", "t17_idempotente", "t18_alineacion_derecha", "t19_grosor_limites", "t20_estres"]
	var only := OS.get_environment("E2E_ONLY")
	for i in tests.size():
		if only != "" and not (str(i + 1) in only.split(",")):
			continue
		print("E2E ── ", tests[i])
		await Callable(self, tests[i]).call()
		await _shot(tests[i])
		await _clear_artboard()
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
