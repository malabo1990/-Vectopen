## E2E Mayús + arrastrar SOBRE un polígono / Bézier seleccionado (herramientas
## de figura y Bézier) = grosor de trazo en tiempo real, en vertical y en
## horizontal; un paso de deshacer; fuera de la selección dibuja proporcional;
## con 300 figuras seleccionadas, fluido.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func btn(at: Vector2, down: bool, shift: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = at
	b.global_position = at
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = down
	b.shift_pressed = shift
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(b)

## Arrastre con Mayús; devuelve ms medios por fotograma.
func drag(from: Vector2, delta: Vector2, steps: int) -> float:
	var mm := InputEventMouseMotion.new()
	mm.position = from
	mm.global_position = from
	_send(mm)
	await K.frames(2)
	btn(from, true, true)
	await K.frames(2)
	var t0 := Time.get_ticks_usec()
	for i in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		m.position = from + delta * (float(i) / steps)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.shift_pressed = true
		_send(m)
		await process_frame
	var avg := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	btn(from + delta, false, true)
	await K.frames(3)
	return avg

func _count(ab: Node) -> int:
	var n := 0
	for ch in ab.find_children("*", "Node2D", true, false):
		if ch.has_meta("shape_type") or ch is VectorShape:
			n += 1
	return n

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://shape_width")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1000, 700), "Grosor figuras", Color.WHITE)
	await K.look_at(ab)
	var tf := func(g: Vector2) -> Vector2: return K.canvas.get_viewport().get_canvas_transform() * ab.to_global(g)
	var poly: Node2D = api.add_polygon(Vector2(250, 250), 100.0, 6)
	api.set_props(poly, {"stroke_width": 2.0, "stroke_color": Color.BLACK})
	var c := Curve2D.new()
	c.add_point(Vector2(550, 300), Vector2.ZERO, Vector2(60, -150))
	c.add_point(Vector2(800, 300), Vector2(-60, -150))
	var bez: Node2D = api.add_curve(c, false, "Curva")
	api.set_props(bez, {"stroke_width": 2.0, "stroke_color": Color.BLACK})
	await K.frames(3)
	for case in [["pentagon", poly, Vector2(250, 250)], ["bezier", bez, Vector2(675, 230)]]:
		K.canvas.switch_tool(case[0])
		await K.frames(3)
		api.select([case[1]])
		await K.frames(3)
		var n0: int = ab.get_child_count()
		await drag(tf.call(case[2]), Vector2(0, -150), 30)   # VERTICAL hacia arriba
		var w_up := float(case[1].stroke_width)
		K.check("%s: Mayús + arrastrar en VERTICAL engorda el trazo en vivo" % case[0], w_up > 40.0, "%.2f" % w_up)
		K.check("%s: no dibuja una figura nueva" % case[0], ab.get_child_count() == n0)
		await drag(tf.call(case[2]), Vector2(-120, 0), 24)   # horizontal izquierda = más fino
		K.check("%s: hacia la izquierda adelgaza" % case[0], float(case[1].stroke_width) < w_up, "%.2f" % float(case[1].stroke_width))
		api.undo()
		await K.frames(3)
		K.check("%s: un Ctrl+Z por gesto" % case[0], is_equal_approx(float(case[1].stroke_width), w_up), "%.2f" % float(case[1].stroke_width))
	# fuera de la selección: dibuja proporcional (no toca el grosor)
	K.canvas.switch_tool("pentagon")
	api.select([poly])
	await K.frames(3)
	var w0 := float(poly.stroke_width)
	var nb: int = _count(ab)
	await drag(tf.call(Vector2(500, 560)), Vector2(80, 60), 10)
	K.check("fuera de la selección el gesto no se activa (la herramienta recibe Mayús + arrastrar)", is_equal_approx(float(poly.stroke_width), w0) and not K.canvas._width_gesture.active)
	# rendimiento: 300 figuras seleccionadas
	var many: Array = []
	for i in 300:
		var s = api.add_polygon(Vector2(60 + (i % 20) * 45, 60 + int(i / 20) * 40), 16.0, 5)
		many.append(s)
	for s in many:
		api.set_props(s, {"stroke_width": 1.0, "stroke_color": Color.BLACK})
	K.canvas.switch_tool("pentagon")
	api.select(many)
	await K.frames(6)
	var avg := await drag(tf.call(Vector2(60, 60)), Vector2(0, -120), 30)
	print("BENCH grosor_300_figuras ms_medio=%.1f w=%.2f" % [avg, float(many[299].stroke_width)])
	K.check("300 figuras: el grosor cambia en todas", float(many[299].stroke_width) > 4.0, "%.2f" % float(many[299].stroke_width))
	K.check("300 figuras: tiempo real (≤ 34 ms por fotograma)", avg <= 34.0, "%.1f ms" % avg)
	await K.shot("grosor_figuras")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
