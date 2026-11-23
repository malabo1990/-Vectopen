## Mide el COSTE por movimiento (ms de CPU dentro del manejador) y el tiempo
## de fotograma sin vsync al: arrastrar un polígono sobre otro (Mover) y
## Mayús + arrastrar el grosor de un polígono seleccionado. Documento con
## 200 figuras de fondo.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> float:
	var t := Time.get_ticks_usec()
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	return (Time.get_ticks_usec() - t) / 1000.0

func btn(at: Vector2, down: bool, shift := false) -> void:
	var b := InputEventMouseButton.new()
	b.position = at
	b.global_position = at
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.shift_pressed = shift
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(b)

func drag(label: String, from: Vector2, delta: Vector2, steps: int, shift := false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = from
	mm.global_position = from
	_send(mm)
	await K.frames(2)
	btn(from, true, shift)
	await K.frames(2)
	var pm := root.get_node_or_null("PerformanceManager")
	if pm and pm.has_method("set_idle_render"):
		pm.set_idle_render(false)
	if pm and "low_latency_drag" in pm:
		pm.low_latency_drag = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ev_ms := PackedFloat32Array()
	var fr_ms := PackedFloat32Array()
	for i in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		m.position = from + delta * (float(i) / steps)
		m.global_position = m.position
		m.relative = delta / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.shift_pressed = shift
		ev_ms.append(_send(m))
		var t := Time.get_ticks_usec()
		await process_frame
		fr_ms.append((Time.get_ticks_usec() - t) / 1000.0)
	var e_avg := 0.0
	var e_max := 0.0
	for v in ev_ms:
		e_avg += v
		e_max = maxf(e_max, v)
	var f_avg := 0.0
	for v in fr_ms:
		f_avg += v
	print("DIAG max_fps=%d vsync=%d process_ms=%.2f physics_ms=%.2f draw_calls=%d objetos=%d fps=%d" % [Engine.max_fps, DisplayServer.window_get_vsync_mode(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Engine.get_frames_per_second()])
	print("BENCH %s evento_ms_medio=%.2f evento_ms_peor=%.2f fotograma_ms=%.2f" % [label, e_avg / steps, e_max, f_avg / steps])

func _proc_during_drag(from: Vector2) -> float:
	var mm := InputEventMouseMotion.new()
	mm.position = from
	mm.global_position = from
	_send(mm)
	await K.frames(2)
	btn(from, true)
	await K.frames(2)
	var acc := 0.0
	for i in range(1, 31):
		var m := InputEventMouseMotion.new()
		m.position = from + Vector2(i * 4 if i <= 15 else (30 - i) * 4, 0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m)
		await process_frame
		if i > 5:
			acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	btn(from, false)
	await K.frames(3)
	var timers := root.find_children("*", "Timer", true, false).size()
	print("DIAG tweens=%d timers=%d nodos=%d ab_hijos=%d undo=%s" % [get_processed_tweens().size(), timers, get_node_count(), K.api.get("_last_ab").get_child_count() if false else 0, str(root.get_node("HistoryManager").get("undo_stack").size() if root.get_node_or_null("HistoryManager") and "undo_stack" in root.get_node("HistoryManager") else "-")])
	return acc / 25.0

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://drag_cost")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1200, 800), "Latencia", Color.WHITE)
	await K.look_at(ab)
	for i in 200:
		api.add_polygon(Vector2(40 + (i % 20) * 58, 420 + int(i / 20) * 36), 14.0, 6)
	var a: Node2D = api.add_polygon(Vector2(250, 220), 90.0, 6)
	var b: Node2D = api.add_polygon(Vector2(600, 220), 90.0, 5)
	api.set_props(a, {"stroke_width": 2.0, "stroke_color": Color.BLACK})
	await K.frames(10)
	var tf := func(g: Vector2) -> Vector2: return K.canvas.get_viewport().get_canvas_transform() * ab.to_global(g)
	var counts := {}
	for n in root.find_children("*", "", true, false):
		if n.is_processing() and n.get_script():
			var k := String(n.get_script().resource_path).get_file()
			counts[k] = int(counts.get(k, 0)) + 1
	print("DIAG procesando: ", counts)
	K.canvas.switch_tool("move")
	api.select([])
	await K.frames(3)
	await drag("mover_poligono", tf.call(Vector2(250, 220)), Vector2(350, 0), 60)
	await drag("mover_poligono_2", tf.call(Vector2(600, 220)), Vector2(-300, 40), 60)
	K.canvas.switch_tool("pentagon")
	api.select([a])
	await K.frames(3)
	await drag("grosor_poligono", tf.call(Vector2(600, 220)), Vector2(0, -120), 60, true)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
