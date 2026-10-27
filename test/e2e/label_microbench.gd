## Micro-benchmark: coste del PRIMER frame de 40 etiquetas según variante.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _bench(name: String, make: Callable) -> void:
	var holder := Node2D.new()
	root.add_child(holder)
	for i in 40:
		var l: Control = make.call(i)
		l.position = Vector2((i % 8) * 220, int(i / 8) * 120)
		holder.add_child(l)
	var t := Time.get_ticks_usec()
	await process_frame
	print("BENCH %-34s %8.1f ms" % [name, (Time.get_ticks_usec() - t) / 1000.0])
	holder.queue_free()
	await process_frame

func _run() -> void:
	if OS.get_environment("BENCH_APP") != "":
		# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
		DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
		change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
		# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
		for _w in 600:
			if Engine.has_meta(&"vectopen_startup_done"): break
			await process_frame
		for i in 20: await process_frame
		var pm = root.get_node_or_null("PerformanceManager")
		if pm: pm.target_fps = 0; pm.set_idle_render(false)
		Engine.max_fps = 0
	await process_frame
	var fc = root.get_node("FontCore")
	var inter: Font = fc.get_font(fc.make_spec("Inter", 400, false))
	var txt := "Parrafo 12 con negrita, color y varias palabras para envolver."
	var plain := func(font: Font, wrap: bool, fs: int) -> Callable:
		return func(i):
			var l := Label.new()
			l.text = txt + str(i)
			l.add_theme_font_override("font", font)
			l.add_theme_font_size_override("font_size", fs)
			l.size = Vector2(200, 100)
			if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return l
	await _bench("Label fallback_font 24", plain.call(ThemeDB.fallback_font, true, 24))
	await _bench("Label Inter(MSDF) 24", plain.call(inter, true, 24))
	await _bench("Label Inter(MSDF) 24 sin wrap", plain.call(inter, false, 24))
	var nomsdf := FontFile.new()
	nomsdf.load_dynamic_font("res://assets/fonts/Inter-Regular.ttf")
	await _bench("Label Inter SIN MSDF 24", plain.call(nomsdf, true, 24))
	await _bench("WorldTextLabel", func(i):
		var t := Node2D.new()
		t.set_meta("width", 200.0); t.set_meta("height", 100.0)
		var l := WorldTextLabel.new()
		l.text = txt + str(i)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_child(l)
		var c := Control.new(); c.add_child(t); return c)
	if OS.get_environment("BENCH_APP") != "":
		var CS = load("res://scripts/canvas/canvas_serializer.gd")
		var canvas = get_first_node_in_group("_vectopen_canvas")
		var ab: Node2D = canvas.get_node("ArtboardsContainer").get_child(0)
		var d := {"kind": "text", "text_kind": "text_paragraph", "text": txt, "font_size": 24, "width": 200.0, "height": 100.0, "name": "B", "pos": [0, 0], "rot": 0.0, "scale": [1, 1], "visible": true}
		for where in ["holder", "artboard"]:
			var made: Array = []
			for i in 40:
				var dd := d.duplicate(); dd["name"] = "B%d" % i
				made.append(CS._element_from(dd))
			for m in made:
				if where == "artboard": ab.add_child(m)
				else: root.add_child(m)
			var t := Time.get_ticks_usec()
			await process_frame
			print("BENCH %-34s %8.1f ms" % ["_element_from en " + where, (Time.get_ticks_usec() - t) / 1000.0])
			for m in made: m.queue_free()
			await process_frame
	quit()
