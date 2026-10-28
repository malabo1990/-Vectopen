## Rendimiento de "Letras avanzadas" sobre la app real (con y sin extensión):
## aplicar un preajuste, cada paso de un arrastre (curva / campos), frames
## con efectos, y desglose de las piezas.
##   godot --path . -s res://test/e2e/letter_fx_perf_e2e.gd
extends SceneTree

var canvas: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _perf(label: String, v: float, unit := "ms") -> void:
	print("E2E PERF %-44s %8.2f %s" % [label, v, unit])

func _frame_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	await _frames(n)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var pm = root.get_node_or_null("PerformanceManager")
	if pm:
		pm.target_fps = 0
		if pm.has_method("set_idle_render"):
			pm.set_idle_render(false)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var sm = root.get_node("SelectionManager")
	print("E2E modo: ", "nativo" if ClassDB.class_exists("VectorRichText") else "GDScript")
	canvas.switch_tool("text")
	await _frames()
	var t: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(t)
	ic._sync_selection()
	ic.apply("text", "Letras avanzadas con muchos efectos")
	ic.apply("font_size", 48)
	await _frames(5)
	_perf("frame sin efectos", await _frame_ms(60))

	var typo_root: Control = root.find_child("Panel_tooltext", true, false)
	var n: Node = typo_root
	while n and n != root:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
		n = n.get_parent()
	await _frames(3)
	var typo = typo_root.get_node("BoxContainer")
	typo.get_node("Panel/VBoxContainer/RowAdvanced").pressed.emit()
	await _frames(3)
	var pop = root.find_child("LetterFxPopover", true, false)

	# Preajustes (clic)
	var tt := Time.get_ticks_usec()
	for i in 10:
		pop._prop_btns["Aaa" if i % 2 == 0 else "aAa"].pressed.emit()
	_perf("clic en preajuste (aplicar + undo)", (Time.get_ticks_usec() - tt) / 10000.0)
	await _frames(3)
	_perf("frame con proporciones", await _frame_ms(60))

	# Arrastre de la curva: un paso de ratón
	var cv: Control = pop._curve
	var p0: Vector2 = pop._curve_pt(0, 1.0)
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = p0
	cv.gui_input.emit(down)
	tt = Time.get_ticks_usec()
	for i in 40:
		var mv := InputEventMouseMotion.new(); mv.position = p0 - Vector2(0, (i % 20) * 2)
		cv.gui_input.emit(mv)
	_perf("paso de arrastre de la curva", (Time.get_ticks_usec() - tt) / 40000.0)
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = p0
	cv.gui_input.emit(up)
	await _frames(2)
	# frames reales mientras se arrastra (paso + render)
	cv.gui_input.emit(down)
	var t0 := Time.get_ticks_usec()
	for i in 30:
		var mv := InputEventMouseMotion.new(); mv.position = p0 - Vector2(0, (i % 20) * 2)
		cv.gui_input.emit(mv)
		await process_frame
	_perf("frame arrastrando la curva (paso+render)", (Time.get_ticks_usec() - t0) / 30000.0)
	cv.gui_input.emit(up)
	await _frames(2)

	# Onda: arrastre del campo de amplitud
	pop._wave_btns["wave"].pressed.emit()
	await _frames(2)
	t0 = Time.get_ticks_usec()
	for i in 30:
		pop._on_wave_field_live(5.0 + i, "amount")
		await process_frame
	_perf("frame arrastrando amplitud de onda", (Time.get_ticks_usec() - t0) / 30000.0)
	pop._on_wave_field(35.0, "amount")
	# Interletra progresiva
	t0 = Time.get_ticks_usec()
	for i in 30:
		pop._on_ramp_field_live(float(i), "end")
		await process_frame
	_perf("frame arrastrando interletra progresiva", (Time.get_ticks_usec() - t0) / 30000.0)
	pop._on_ramp_field(29.0, "end")
	await _frames(3)
	_perf("frame con los 3 efectos", await _frame_ms(60))

	# Desglose de piezas
	var vrt = t.get_node_or_null("VectorRichText")
	var TextCore = load("res://script_gdscript/text/text_core.gd")
	var LetterFx = load("res://script_gdscript/text/letter_fx.gd")
	tt = Time.get_ticks_usec()
	for i in 50:
		LetterFx.derive_runs(t, t.get_meta("runs", []), String(t.get_meta("text")))
	_perf("· derive_runs", (Time.get_ticks_usec() - tt) / 50000.0)
	if vrt:
		tt = Time.get_ticks_usec()
		for i in 20:
			TextCore.set_vrt_runs(vrt, t.get_meta("runs", []))
			vrt.get_content_size()
		_perf("· set_vrt_runs + layout nativo", (Time.get_ticks_usec() - tt) / 20000.0)
	tt = Time.get_ticks_usec()
	for i in 20:
		ic._write(t, "letter_tracking_ramp", {"start": 0.0, "end": float(i)})
	_perf("· InspectorCore._write (efecto)", (Time.get_ticks_usec() - tt) / 20000.0)
	tt = Time.get_ticks_usec()
	for i in 20:
		ic._post_write()
	_perf("· InspectorCore._post_write (avisos)", (Time.get_ticks_usec() - tt) / 20000.0)
	# Oyentes de los avisos (qué cuesta cada uno)
	var props: Dictionary = ic.current_props()
	var ge = root.get_node("GlobalEvents")
	for pair in [[ic, "changed", [props]], [ge, "object_style_changed", []]]:
		for c in pair[0].get_signal_connection_list(pair[1]):
			var cb: Callable = c["callable"]
			var tc := Time.get_ticks_usec()
			for k in 5:
				cb.callv(pair[2])
			var tgt = cb.get_object()
			var nm: String = (tgt.get_script().resource_path.get_file() if tgt and tgt.get_script() else str(tgt))
			var ms := (Time.get_ticks_usec() - tc) / 5000.0
			if ms > 0.3:
				_perf("  oyente %s %s.%s" % [pair[1], nm, cb.get_method()], ms)
	tt = Time.get_ticks_usec()
	for i in 20:
		ic._refit_text_shape(t)
	_perf("· _refit_text_shape", (Time.get_ticks_usec() - tt) / 20000.0)
	var dl = t.get_node_or_null("DisplayLabel")
	if dl and not vrt:
		tt = Time.get_ticks_usec()
		for i in 5:
			dl.invalidate_layout()
			dl._get_triangle_polys()
		_perf("· overlay: rebake contorno+triangulación", (Time.get_ticks_usec() - tt) / 5000.0)
		dl.set_draft(true)
		tt = Time.get_ticks_usec()
		for i in 5:
			dl.invalidate_layout()
			dl._get_outline()
		_perf("· overlay borrador: solo contorno", (Time.get_ticks_usec() - tt) / 5000.0)
		tt = Time.get_ticks_usec()
		for i in 5:
			dl.invalidate_layout()
			dl._get_triangle_polys()
		_perf("· overlay borrador: contorno+triangulación", (Time.get_ticks_usec() - tt) / 5000.0)
		dl.set_draft(false)
		tt = Time.get_ticks_usec()
		for i in 5:
			dl.invalidate_layout()
			dl._get_outline()
		_perf("· overlay 512: solo contorno", (Time.get_ticks_usec() - tt) / 5000.0)
	quit(0)
