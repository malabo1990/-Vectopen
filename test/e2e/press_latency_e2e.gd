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
		var press_ms := _send(b)
		var t := Time.get_ticks_usec()
		await process_frame
		var f1 := (Time.get_ticks_usec() - t) / 1000.0
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
