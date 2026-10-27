## Rendimiento de los efectos: 100 textos + 100 rectángulos con sombra
## (más contorno / 3D / desenfoque en parte), frames en reposo, zoom y paneo,
## y arrastre en vivo de un parámetro desde el panel.
##   godot --path . -s res://test/e2e/effects_perf_e2e.gd
extends SceneTree

var canvas: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _perf(label: String, v: float) -> void:
	print("E2E PERF %-44s %8.2f ms" % [label, v])

func _frame_ms(n: int, step := Callable()) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		if step.is_valid():
			step.call(i)
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _find_script_node(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find_script_node(c, suffix)
		if r:
			return r
	return null

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
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
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var cam = canvas.get_node_or_null("Camera2D")
	_perf("frame vacío", await _frame_ms(60))
	var shadow := {"type": "Drop Shadow", "enabled": true, "offset_x": 4.0, "offset_y": 4.0, "blur": 6.0, "spread": 0.0, "color": Color(0, 0, 0, 0.4)}
	var texts: Array = []
	var n_text := int(OS.get_environment("FX_TEXTS")) if OS.get_environment("FX_TEXTS") != "" else 100
	var n_rect := int(OS.get_environment("FX_RECTS")) if OS.get_environment("FX_RECTS") != "" else 100
	for i in n_text:
		canvas.switch_tool("text")
		var t: Node2D = canvas.current_tool.create_at_center()
		t.position = Vector2(40 + (i % 10) * 75, 40 + (i / 10) * 60)
		sm.select(t); ic._sync_selection()
		ic.apply("text", "Texto %d" % i)
		var fx := [shadow.duplicate()]
		if i % 3 == 0:
			fx.append({"type": "Outline", "enabled": true, "width": 1.5, "color": Color(1, 1, 1)})
		if i % 5 == 0:
			fx.append({"type": "3D", "enabled": true, "depth": 4.0, "angle": 45.0, "shadow": 60.0})
		ic.apply("effects", fx)
		texts.append(t)
	var rect_script = load("res://script_gdscript/shapes/VectorRectangle.gd")
	for i in n_rect:
		var r = rect_script.new()
		r.size = Vector2(50, 35)
		r.fill_color = Color(0.2, 0.5, 0.9)
		ab.add_child(r)
		r.position = Vector2(60 + (i % 10) * 75, 680 + (i / 10) * 45)
		r.effects = [shadow.duplicate()]
	canvas.switch_tool("move")
	sm.set_selection([]); ic._sync_selection()
	await _frames(20)
	if cam:
		cam.zoom = Vector2(0.8, 0.8)
		cam.global_position = ab.global_position + Vector2(420, 520)
	await _frames(10)
	_perf("frame reposo (100 textos + 100 rects con efectos)", await _frame_ms(120))
	if OS.get_environment("FX_DIAG") != "":
		for t in texts:
			var c = t.get_node_or_null("TextFx")
			if c: c.set_process(false)
		_perf("  diag: reposo SIN _process", await _frame_ms(120))
		_perf("  diag: zoom SIN _process", await _frame_ms(60, func(i): if cam: cam.zoom = Vector2(0.8, 0.8) * (1.0 + 0.4 * sin(i * 0.2))))
		for t in texts:
			for nm in ["TextFxBack", "TextFxFront"]:
				var l = t.get_node_or_null(nm)
				if l: l.visible = false
		_perf("  diag: reposo SIN capas visibles", await _frame_ms(120))
		_perf("  diag: zoom SIN capas ni _process", await _frame_ms(60, func(i): if cam: cam.zoom = Vector2(0.8, 0.8) * (1.0 + 0.4 * sin(i * 0.2))))
		quit(0)
		return
	var z0: Vector2 = cam.zoom if cam else Vector2.ONE
	_perf("frame zoom continuo", await _frame_ms(60, func(i): if cam: cam.zoom = z0 * (1.0 + 0.4 * sin(i * 0.2))))
	if cam: cam.zoom = z0
	var p0: Vector2 = cam.global_position if cam else Vector2.ZERO
	_perf("frame paneo", await _frame_ms(60, func(i): if cam: cam.global_position = p0 + Vector2(sin(i * 0.1) * 200, 0)))
	if cam: cam.global_position = p0
	await _frames(5)

	if texts.is_empty():
		quit(0)
		return
	# Arrastre en vivo del desenfoque de la sombra de UN texto desde el panel
	var panel = _find_script_node(root, "panels/effects/effects.gd")
	var t0: Node2D = texts[0]
	sm.select(t0); ic._sync_selection()
	panel._sync_from_inspector()
	await _frames(3)
	var entry = panel._effects_list.get_child(0)
	var blur_spin = entry.find_child("Blur", true, false)
	_perf("frame arrastrando 'blur' de una sombra", await _frame_ms(60, func(i): blur_spin.value = 2.0 + float(i % 20)))
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 700:
		await process_frame
	# Cambiar el TEXTO de uno con efectos (se rehace su sombra)
	var tt := Time.get_ticks_usec()
	for i in 20:
		ic.apply("text", "Cambio %d" % i)
		await process_frame
	_perf("frame cambiando el texto de uno con efectos", (Time.get_ticks_usec() - tt) / 20000.0)
	quit(0)
