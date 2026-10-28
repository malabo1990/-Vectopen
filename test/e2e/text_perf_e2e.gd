## Benchmark de RENDIMIENTO del texto sobre la app real (render de verdad).
## Crea N títulos + N párrafos con formato mixto y mide: creación, frame en
## reposo, frame durante zoom/paneo, tecleo en un párrafo largo y
## guardar/cargar. Imprime "E2E PERF <métrica> <valor>" para comparar.
##   godot --path . -s res://test/e2e/text_perf_e2e.gd   (E2E_N=cantidad)
extends SceneTree

var n := 150
var canvas: Node2D
var cam: Camera2D

func _initialize() -> void:
	if OS.get_environment("E2E_N") != "":
		n = int(OS.get_environment("E2E_N"))
	_run.call_deferred()

func _frames(k: int = 1) -> void:
	for i in k:
		await process_frame

func _perf(name: String, v: float, unit: String) -> void:
	print("E2E PERF %-28s %10.2f %s" % [name, v, unit])

## Frame time medio y peor (ms) de `k` frames mientras corre `step`.
func _measure_frames(k: int, step: Callable) -> Array:
	var times: Array[float] = []
	var t0 := Time.get_ticks_usec()
	for i in k:
		step.call(i)
		await process_frame
		var t1 := Time.get_ticks_usec()
		times.append((t1 - t0) / 1000.0)
		t0 = t1
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= maxf(1.0, times.size())
	return [avg, times[int(times.size() * 0.95) - 1] if times.size() > 1 else avg]

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	canvas = get_first_node_in_group("_vectopen_canvas")
	cam = canvas.get_node_or_null("Camera2D")
	# La app limita FPS / modo bajo consumo: quitarlo para medir de verdad.
	var pm = root.get_node_or_null("PerformanceManager")
	if pm:
		pm.target_fps = 0
		pm.set_idle_render(false)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	var ab: Node2D = canvas.get_node("ArtboardsContainer").get_child(0)
	print("E2E modo: ", "nativo" if ClassDB.class_exists("VectorRichText") else "GDScript", "  N=", n)

	# 1) Creación
	canvas.switch_tool("paragraph")
	await _frames()
	var ptool = canvas.current_tool
	ptool.target_artboard = ab
	var t0 := Time.get_ticks_usec()
	var shapes: Array = []
	for i in n:
		var p: Node2D = ptool._create_new_paragraph_at(Vector2((i % 10) * 380, int(i / 10) * 160))
		var txt := "Parrafo %d con negrita, color y varias palabras para envolver." % i
		p.set_meta("text", txt)
		p.set_meta("runs", [{"length": 8, "bold": true, "color": Color.RED, "size": 0.0},
			{"length": txt.length() - 8, "bold": false, "color": Color.BLACK, "size": 0.0}])
		var dl = p.get_node("DisplayLabel")
		dl.text = txt
		dl.set_rich_runs(p.get_meta("runs"))
		var v = p.get_node_or_null("VectorRichText")
		if v:
			v.set_text(txt)
			ptool._safe_set_runs_meta(v, p.get_meta("runs"))
		shapes.append(p)
	canvas.switch_tool("text")
	await _frames()
	var ttool = canvas.current_tool
	ttool.target_artboard = ab
	for i in n:
		shapes.append(ttool._create_new_title_at(Vector2((i % 10) * 380, 100 + int(i / 10) * 160), 32))
	var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_perf("crear %d textos" % (n * 2), create_ms, "ms")
	_perf("crear por texto", create_ms / (n * 2), "ms")
	var mt_script = load("res://script_gdscript/tools/MoveTool.gd")
	var tc := Time.get_ticks_usec()
	for i in 20:
		canvas.change_tool(canvas._new_tool(mt_script))
	_perf("· change_tool(MoveTool)", (Time.get_ticks_usec() - tc) / 20000.0, "ms")
	tc = Time.get_ticks_usec()
	for i in 20:
		root.get_node("SelectionManager").select(shapes[i])
	_perf("· SelectionManager.select", (Time.get_ticks_usec() - tc) / 20000.0, "ms")
	await _frames(10)

	if cam:
		cam.zoom = Vector2(0.35, 0.35)
		cam.global_position = Vector2(1900, 1300)
	await _frames(10)

	# 2) Reposo
	var r := await _measure_frames(120, func(_i): pass)
	_perf("frame reposo (media)", r[0], "ms")
	_perf("frame reposo (p95)", r[1], "ms")

	# 3) Zoom continuo (0.35 → 3 → 0.35)
	r = await _measure_frames(120, func(i):
		var z := 0.35 + 2.65 * (0.5 - 0.5 * cos(i / 120.0 * TAU))
		cam.zoom = Vector2(z, z))
	_perf("frame zoom (media)", r[0], "ms")
	_perf("frame zoom (p95)", r[1], "ms")

	# 4) Paneo
	r = await _measure_frames(120, func(i):
		cam.global_position = Vector2(1900 + 1500 * sin(i / 120.0 * TAU), 1300))
	_perf("frame paneo (media)", r[0], "ms")
	_perf("frame paneo (p95)", r[1], "ms")

	# 5) Tecleo en un párrafo largo (editor real, eventos de teclado reales)
	cam.zoom = Vector2(1, 1)
	var big: Node2D = shapes[0]
	var long_txt := ""
	for i in 40:
		long_txt += "palabra%d " % i
	root.get_node("SelectionManager").select(big)
	root.get_node("InspectorCore").apply("text", long_txt)
	cam.global_position = big.global_position + Vector2(175, 100)
	canvas.switch_tool("paragraph")
	await _frames(3)
	canvas.current_tool._check_and_trigger_edit_at(big)
	await _frames(3)
	var vrt = big.get_node_or_null("VectorRichText")
	if vrt and vrt.is_editing():
		vrt.set_caret_index(10)
		vrt.set_selection_range(10, 10)
	var tk := Time.get_ticks_usec()
	var keys := 30
	for i in keys:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = KEY_A
			ev.unicode = 97
			ev.pressed = pressed
			Input.parse_input_event(ev)
		await process_frame
	_perf("tecla en párrafo largo", (Time.get_ticks_usec() - tk) / 1000.0 / keys, "ms/tecla")
	# Desglose de UNA pulsación (qué cuesta cada paso)
	if vrt:
		var t := Time.get_ticks_usec()
		for i in 10:
			vrt.insert_text_at_caret("b") if vrt.has_method("insert_text_at_caret") else vrt.set_text(vrt.get_text() + "b")
		_perf("· nativo set_text/insert", (Time.get_ticks_usec() - t) / 10000.0, "ms")
		var pt = canvas.current_tool
		var txt2: String = vrt.get_text()
		t = Time.get_ticks_usec()
		for i in 10:
			big.set_meta("runs", vrt.get_runs_meta())
		_perf("· get_runs_meta", (Time.get_ticks_usec() - t) / 10000.0, "ms")
		var dl2 = big.get_node("DisplayLabel")
		t = Time.get_ticks_usec()
		for i in 10:
			dl2.text = txt2 + str(i)
			dl2.set_rich_runs(big.get_meta("runs", []))
		_perf("· label.text + set_rich_runs", (Time.get_ticks_usec() - t) / 10000.0, "ms")
		t = Time.get_ticks_usec()
		for i in 10:
			pt._fit_height_to_text(big, txt2)
		_perf("· _fit_height_to_text", (Time.get_ticks_usec() - t) / 10000.0, "ms")
		t = Time.get_ticks_usec()
		for i in 10:
			root.get_node("GlobalEvents").emit_safe("object_transformed")
		_perf("· emit object_transformed", (Time.get_ticks_usec() - t) / 10000.0, "ms")
		var rr := await _measure_frames(20, func(_i): pass)
		_perf("· frame normal (editando)", rr[0], "ms")
		rr = await _measure_frames(20, func(_i): root.get_node("GlobalEvents").emit_safe("object_transformed"))
		_perf("· frame con object_transformed", rr[0], "ms")
		var ge = root.get_node("GlobalEvents")
		for con in ge.object_transformed.get_connections():
			var cb: Callable = con["callable"]
			var who := "%s.%s" % [(cb.get_object().get_script().resource_path.get_file() if cb.get_object() and cb.get_object().get_script() else str(cb.get_object())), cb.get_method()]
			ge.object_transformed.disconnect(cb)
			var r2 := await _measure_frames(10, func(_i): ge.emit_safe("object_transformed"))
			ge.object_transformed.connect(cb)
			_perf("  sin " + who, r2[0], "ms")
		rr = await _measure_frames(20, func(_i): pt._on_vrt_text_changed(vrt.get_text()))
		_perf("· frame con _on_vrt_text_changed", rr[0], "ms")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(5)

	# 6) Guardar / cargar
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	var cont: Node = canvas.get_node("ArtboardsContainer")
	var ts := Time.get_ticks_usec()
	var data: Dictionary = CS.serialize_container(cont)
	_perf("serializar", (Time.get_ticks_usec() - ts) / 1000.0, "ms")
	# Desglose de reconstruir UN texto
	var one: Dictionary = CS._serialize_element(shapes[1])
	var TC = load("res://script_gdscript/text/text_core.gd")
	var tt := Time.get_ticks_usec()
	var made: Array = []
	for i in 20:
		made.append(CS._element_from(one))
	_perf("· _element_from texto", (Time.get_ticks_usec() - tt) / 20000.0, "ms")
	tt = Time.get_ticks_usec()
	for m in made:
		TC.sync_vrt_from_meta(m, m.get_node("VectorRichText")) if m.get_node_or_null("VectorRichText") else null
	_perf("· sync_vrt_from_meta", (Time.get_ticks_usec() - tt) / 20000.0, "ms")
	tt = Time.get_ticks_usec()
	for m in made:
		TC.apply_vrt_fonts(m.get_node("VectorRichText"), m) if m.get_node_or_null("VectorRichText") else null
	_perf("· apply_vrt_fonts", (Time.get_ticks_usec() - tt) / 20000.0, "ms")
	tt = Time.get_ticks_usec()
	for m in made:
		ab.add_child(m)
	_perf("· add_child (entrar al árbol)", (Time.get_ticks_usec() - tt) / 20000.0, "ms")
	await process_frame
	for m in made:
		m.queue_free()
	await process_frame
	var probe: Node2D = CS._element_from(one)
	ab.add_child(probe)
	await process_frame
	var pl = probe.get_node("DisplayLabel")
	var tq := Time.get_ticks_usec()
	var ob = pl._outline_font_bytes()
	_perf("· _outline_font_bytes", (Time.get_ticks_usec() - tq) / 1000.0, "ms")
	tq = Time.get_ticks_usec()
	var oc = pl._build_outline_at(512)
	_perf("· _build_outline_at(512)", (Time.get_ticks_usec() - tq) / 1000.0, "ms")
	if oc: oc.free()
	pl._polys_baked = false
	pl._outline_dirty = true
	tq = Time.get_ticks_usec()
	pl._bake_glyph_data()
	_perf("· _bake_glyph_data total", (Time.get_ticks_usec() - tq) / 1000.0, "ms")
	_perf("· override activo", 1.0 if pl.is_vector_override_active() else 0.0, "")
	probe.queue_free()
	await process_frame
	for variant in ["todo", "sin_vrt", "sin_label", "label_sin_runs", "label_oculta", "label_sin_process", "label_sin_autowrap"]:
		var batch: Array = []
		for i in 40:
			var m: Node2D = CS._element_from(one)
			if variant == "sin_vrt" and m.get_node_or_null("VectorRichText"):
				var vv = m.get_node("VectorRichText"); m.remove_child(vv); vv.free()
			if variant == "sin_label":
				var ll = m.get_node("DisplayLabel"); m.remove_child(ll); ll.free()
			if variant == "label_sin_runs":
				m.remove_meta("runs")
				var vv2 = m.get_node_or_null("VectorRichText")
				if vv2: m.remove_child(vv2); vv2.free()
			if variant in ["label_sin_process", "label_sin_autowrap"]:
				m.remove_meta("runs")
				var vv3 = m.get_node_or_null("VectorRichText")
				if vv3: m.remove_child(vv3); vv3.free()
				if variant == "label_sin_process":
					m.get_node("DisplayLabel").set_process(false)
				else:
					m.get_node("DisplayLabel").autowrap_mode = TextServer.AUTOWRAP_OFF
			if variant == "label_oculta":
				m.get_node("DisplayLabel").visible = false
			batch.append(m)
		for m in batch:
			ab.add_child(m)
		var tf := Time.get_ticks_usec()
		await process_frame
		_perf("· 1er frame 40 textos " + variant, (Time.get_ticks_usec() - tf) / 1000.0, "ms")
		for m in batch:
			m.queue_free()
		tf = Time.get_ticks_usec()
		await process_frame
		_perf("· liberar 40 textos " + variant, (Time.get_ticks_usec() - tf) / 1000.0, "ms")
	ts = Time.get_ticks_usec()
	CS.rebuild_container(cont, data)
	_perf("reconstruir (síncrono)", (Time.get_ticks_usec() - ts) / 1000.0, "ms")
	var ts2 := Time.get_ticks_usec()
	await process_frame
	_perf("reconstruir (1er frame)", (Time.get_ticks_usec() - ts2) / 1000.0, "ms")
	ts2 = Time.get_ticks_usec()
	await process_frame
	_perf("reconstruir (2º frame)", (Time.get_ticks_usec() - ts2) / 1000.0, "ms")
	_perf("reconstruir", (Time.get_ticks_usec() - ts) / 1000.0, "ms")
	await _frames(10)
	r = await _measure_frames(60, func(_i): pass)
	_perf("frame tras cargar (media)", r[0], "ms")

	_perf("memoria estática", OS.get_static_memory_usage() / 1048576.0, "MB")
	_perf("nodos", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "")
	print("E2E RESULT: DONE")
	quit(0)
