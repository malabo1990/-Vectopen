## Mide el ARRANQUE del arrastre con Mover: coste del clic (seleccionar la
## figura) y fotogramas siguientes, y cuántos px hay que mover antes de que la
## figura empiece a seguir al ratón.
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

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://press_latency")
	if not await K.boot(OS.get_environment("PRESS_MODE") if OS.get_environment("PRESS_MODE") != "" else "modern"):
		quit(1)
		return
	api = K.api
	if OS.get_environment("NOVSYNC") == "1":
		# coste PURO (sin esperar al refresco): clic + fotograma siguiente
		var pm := root.get_node_or_null("PerformanceManager")
		if pm:
			pm.set_idle_render(false)
			if "low_latency_drag" in pm:
				pm.low_latency_drag = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var ab: Node2D = await K.artboard(Vector2(1200, 800), "Arranque", Color.WHITE)
	await K.look_at(ab)
	for i in 200:
		api.add_polygon(Vector2(40 + (i % 20) * 58, 420 + int(i / 20) * 36), 14.0, 6)
	var polys: Array = []
	for i in 4:
		polys.append(api.add_polygon(Vector2(200 + i * 250, 220), 80.0, 5 + i))
	await K.frames(10)
	K.canvas.switch_tool("move")
	await K.frames(3)
	var hide := OS.get_environment("HIDEUI")
	if hide != "":
		for nm in hide.split(","):
			for c in root.find_children(nm if not nm.ends_with(".gd") else "*", "Control", true, false):
				if nm.ends_with(".gd") and not (c.get_script() and String(c.get_script().resource_path).ends_with(nm)):
					continue
				if not (c as Control).is_visible_in_tree():
					continue
				(c as Control).visible = false
				print("OCULTO ", c.get_path())
		await K.frames(4)
	var di0 := root.find_children("DockedInspector", "Control", true, false)
	if not di0.is_empty() and OS.get_environment("SECTIONS") == "1":
		var lst: Array = []
		for c in di0[0].find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree() and c.get_child_count() > 3 and (c is VBoxContainer or c is PanelContainer or c is GridContainer):
				lst.append("%s(%d)" % [c.name, c.find_children("*", "Control", true, false).size()])
		print("SECCIONES ", lst)
		var big: Control = null
		for c in di0[0].find_children("*", "VBoxContainer", true, false):
			if big == null or c.find_children("*", "Control", true, false).size() > big.find_children("*", "Control", true, false).size():
				big = c
		var kids: Array = []
		var sc: Node = big.find_children("*", "ScrollContainer", false, false)[0] if not big.find_children("*", "ScrollContainer", false, false).is_empty() else big
		var inner: Node = sc.get_child(0) if sc.get_child_count() > 0 else sc
		for k in inner.get_children():
			if k is Control and (k as Control).visible:
				kids.append("%s:%s(%d)%s" % [k.name, k.get_class(), k.find_children("*", "Control", true, false).size(), String(k.get_script().resource_path.get_file()) if k.get_script() else ""])
		print("HIJOS ", kids)
	var sorts := {}
	var resz := {}
	if not di0.is_empty() and OS.get_environment("SORTS") == "1":
		for c in di0[0].find_children("*", "Control", true, false):
			var path := String(di0[0].get_path_to(c))
			if c is Container:
				c.sort_children.connect(func() -> void: sorts[path] = int(sorts.get(path, 0)) + 1)
			c.resized.connect(func() -> void: resz[path] = int(resz.get(path, 0)) + 1)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 4:
		var p: Node2D = polys[i]
		var at: Vector2 = K.canvas.get_viewport().get_canvas_transform() * p.global_position
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		var hover_ms := _send(mm)
		await K.frames(3)
		var b := InputEventMouseButton.new()
		b.position = at
		b.global_position = at
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = true
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
		var di := root.find_children("DockedInspector", "Control", true, false)
		var n_before := get_node_count()
		var ids_before := {}
		if not di.is_empty():
			for c in di[0].find_children("*", "", true, false):
				ids_before[c.get_instance_id()] = true
		sorts.clear()
		resz.clear()
		var press_ms := _send(b)
		var t := Time.get_ticks_usec()
		await process_frame
		var f1 := (Time.get_ticks_usec() - t) / 1000.0
		await RenderingServer.frame_post_draw
		if OS.get_environment("SORTS") == "1" and i == 2:
			print("SORTS n=%d resized=%d" % [sorts.size(), resz.size()])
			var ks: Array = resz.keys()
			ks.sort()
			for k in ks.slice(0, 60):
				print("  RESIZED ", k)
		if not di.is_empty():
			var nuevos := {}
			for c in di[0].find_children("*", "", true, false):
				if not ids_before.has(c.get_instance_id()):
					var k := String(c.get_parent().name) + "/" + c.get_class()
					nuevos[k] = int(nuevos.get(k, 0)) + 1
			print("NODOS clic%d total %d → %d; nuevos en inspector: %s" % [i, n_before, get_node_count(), str(nuevos).left(600)])
		print("RENDER clic%d cpu=%.2f gpu=%.2f" % [i, RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(vp)])
		t = Time.get_ticks_usec()
		await process_frame
		var f2 := (Time.get_ticks_usec() - t) / 1000.0
		var pos0 := p.global_position
		var first_px := -1
		var mv_ms := 0.0
		for k in range(1, 21):
			var m := InputEventMouseMotion.new()
			m.position = at + Vector2(k, 0)
			m.global_position = m.position
			m.relative = Vector2(1, 0)
			m.button_mask = MOUSE_BUTTON_MASK_LEFT
			mv_ms = maxf(mv_ms, _send(m))
			await process_frame
			if first_px < 0 and p.global_position.distance_to(pos0) > 0.01:
				first_px = k
		var lag: float = (at.x + 20) - (K.canvas.get_viewport().get_canvas_transform() * p.global_position).x
		var u := InputEventMouseButton.new()
		u.position = at + Vector2(20, 0)
		u.global_position = u.position
		u.button_index = MOUSE_BUTTON_LEFT
		u.pressed = false
		var rel_ms := _send(u)
		var t3 := Time.get_ticks_usec()
		await process_frame
		var f3 := (Time.get_ticks_usec() - t3) / 1000.0
		await K.frames(4)
		K.check("clic %d: pulsar sobre la figura ≤ 25 ms (0.2.3: 11 ms; antes 350 ms)" % i, press_ms <= 25.0, "%.1f ms" % press_ms)
		K.check("clic %d: soltar ≤ 45 ms (0.2.3: 27 ms; antes 540 ms)" % i, rel_ms <= 45.0, "%.1f ms" % rel_ms)
		K.check("clic %d: la figura sigue al ratón desde el primer píxel" % i, first_px == 1)
		print("BENCH clic%d hover=%.2f clic=%.2f fot1=%.2f fot2=%.2f mov_peor=%.2f empieza_a_px=%d retraso_px=%.1f soltar=%.2f fot_soltar=%.2f" % [i, hover_ms, press_ms, f1, f2, mv_ms, first_px, lag, rel_ms, f3])
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
