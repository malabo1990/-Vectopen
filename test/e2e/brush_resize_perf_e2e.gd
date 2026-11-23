## E2E RENDIMIENTO: Mayús + arrastrar en el lienzo (herramienta Pincel)
## cambia el grosor del pincel. Con un documento PESADO (2000 trazos):
## cada fotograma del gesto debe ir fluido y el grosor debe cambiar rápido
## (proporcional: ~200 px de arrastre de 5 a 100 px).
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func key(code: Key, down: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = down
	k.shift_pressed = down and code == KEY_SHIFT
	_send(k)

## Campo de grosor del inspector con 500 trazos seleccionados: Mayús +
## arrastrar = RÁPIDO y fluido.
func field_scrub_perf(ab: Node2D) -> void:
	K.canvas.switch_tool("move")
	await K.frames(3)
	var paths: Array = []
	for i in 500:
		var o := Vector2(40 + (i % 25) * 110, 1300 + int(i / 25) * 30)
		var p = api.add_path(PackedVector2Array([o, o + Vector2(40, 15), o + Vector2(80, 0)]), false, "T%d" % i)
		api.set_props(p, {"stroke_width": 2.0})
		paths.append(p)
	api.select(paths)
	await K.frames(10)
	var f: Control = null
	for n in root.find_children("StrokeWidthField", "", true, false):
		if (n as Control).is_visible_in_tree():
			f = n
	K.check("campo de grosor visible con 500 trazos seleccionados", f != null)
	if f == null:
		return
	var num: Control = f.num
	var sc: Node = num.get_parent()
	while sc and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc:
		(sc as ScrollContainer).ensure_control_visible(num)
		await K.frames(3)
	var a: Vector2 = num.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	_send(mm)
	await K.frames(2)
	key(KEY_SHIFT, true)
	await K.frames(1)
	var dn := InputEventMouseButton.new()
	dn.position = a
	dn.global_position = a
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.shift_pressed = true
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(dn)
	await K.frames(2)
	var worst := 0.0
	var t_all := Time.get_ticks_usec()
	for i in range(1, 31):
		var t0 := Time.get_ticks_usec()
		var m2 := InputEventMouseMotion.new()
		m2.position = a + Vector2(i * 2, 0)
		m2.global_position = m2.position
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		m2.shift_pressed = true
		_send(m2)
		await process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	var avg := (Time.get_ticks_usec() - t_all) / 1000.0 / 30.0
	var w_mid: float = float(paths[499].stroke_width)
	var up := InputEventMouseButton.new()
	up.position = a + Vector2(60, 0)
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	key(KEY_SHIFT, false)
	await K.frames(4)
	print("BENCH campo_grosor_500_trazos=%.2f ms_medio=%.1f ms_peor=%.1f" % [w_mid, avg, worst])
	K.check("Mayús + arrastrar el grosor es RÁPIDO (60 px: 2 → más de 20 px, sin dispararse al máximo)", w_mid > 20.0 and w_mid < 400.0, "%.2f px" % w_mid)
	K.check("con 500 trazos seleccionados va fluido (medio ≤ 34 ms)", avg <= 34.0, "%.1f ms" % avg)
	api.undo()
	await K.frames(4)
	K.check("un Ctrl+Z deshace el arrastre entero", is_equal_approx(float(paths[0].stroke_width), 2.0), str(paths[0].stroke_width))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://brush_resize")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(3000, 2000), "Pincel pesado", Color.WHITE)
	await K.look_at(ab)
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	for i in 2000:
		var l := Line2D.new()
		var o := Vector2(30 + (i % 50) * 58, 30 + int(i / 50) * 48)
		l.points = PackedVector2Array([o, o + Vector2(20, 12), o + Vector2(40, 0)])
		l.width = 4.0
		l.default_color = Color(0.2, 0.2, 0.2)
		l.set_meta("brush_style", "pen")
		ab.add_child(l)
		R.attach(l)
	await K.frames(20)
	K.canvas.switch_tool("brush")
	await K.frames(6)
	var bt = K.canvas.current_tool
	K.check("herramienta Pincel activa", bt != null and "brush_width" in bt)
	if bt == null:
		quit(1)
		return
	bt.brush_width = 5.0
	var c := root.get_visible_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = c
	mm.global_position = c
	_send(mm)
	await K.frames(3)
	var dn := InputEventMouseButton.new()
	dn.position = c
	dn.global_position = c
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.shift_pressed = true
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(dn)
	await K.frames(2)
	K.check("Mayús + clic arma el ajuste de grosor (no dibuja)", bool(bt.get("_is_resizing")))
	# 200 px a la derecha en 40 movimientos; tiempo de cada fotograma
	var worst := 0.0
	var t_all := Time.get_ticks_usec()
	for i in range(1, 41):
		var t0 := Time.get_ticks_usec()
		var m2 := InputEventMouseMotion.new()
		m2.position = c + Vector2(i * 5, 0)
		m2.global_position = m2.position
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		m2.shift_pressed = true
		_send(m2)
		await process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	var avg := (Time.get_ticks_usec() - t_all) / 1000.0 / 40.0
	var w_end: float = bt.brush_width
	print("BENCH pincel_grosor_fin=%.1f ms_medio=%.1f ms_peor=%.1f" % [w_end, avg, worst])
	var up := InputEventMouseButton.new()
	up.position = c + Vector2(200, 0)
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await K.frames(4)
	K.check("200 px de arrastre llevan el grosor de 5 a ~100 px (rápido)", w_end > 80.0, "%.1f px" % w_end)
	K.check("cada fotograma del gesto es fluido (medio ≤ 20 ms)", avg <= 20.0, "%.1f ms" % avg)
	K.check("ningún fotograma se atasca (peor ≤ 50 ms)", worst <= 50.0, "%.1f ms" % worst)
	K.check("no se ha dibujado ningún trazo con el gesto", ab.get_children().filter(func(n) -> bool: return n is Line2D).size() == 2000)
	await K.frames(4)
	await field_scrub_perf(ab)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
