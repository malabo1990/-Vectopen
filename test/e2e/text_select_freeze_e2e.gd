## E2E: seleccionar palabras de un texto en edición (ratón y teclado) NO debe
## congelar la app, en los tres modos de interfaz (smart, modern, professional).
## Imprime «E2E TICK» cada pocos frames: si se congela, deja de imprimir.
extends SceneTree

var fails: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _mouse(pos: Vector2, pressed: bool, double := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.double_click = double and pressed
	ev.position = pos
	ev.global_position = pos
	Input.warp_mouse(pos)
	Input.parse_input_event(ev)

func _drag(a: Vector2, b: Vector2) -> void:
	_mouse(a, true)
	await _frames(2)
	for i in range(1, 11):
		var mv := InputEventMouseMotion.new()
		mv.position = a.lerp(b, i / 10.0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await _frames(1)
	_mouse(b, false)
	await _frames(3)

func _key(code: Key, shift := false, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.shift_pressed = shift
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var gui = root.get_node_or_null("GlobalUI")
	for mode in ["professional", "modern", "smart"]:
		if gui and gui.has_method("set_ui_mode"):
			gui.set_ui_mode(mode)
		await _frames(20)
		print("E2E MODO %s" % mode)
		var t: Node2D = api.add_text(Vector2(100, 120), "Unas palabras para seleccionar con el ratón", 40)
		await _frames(4)
		var cam: Camera2D = canvas.get_node_or_null("Camera2D")
		if cam:
			cam.global_position = t.global_position + Vector2(380, 30)
			cam.zoom = Vector2(1.2, 1.2)
		canvas.switch_tool("text")
		await _frames(2)
		var tt = canvas.current_tool
		tt._check_and_trigger_edit_at(tt.target_artboard.to_local(t.global_position + Vector2(10, 10)))
		await _frames(4)
		var vrt = t.get_node("VectorRichText")
		var xf: Transform2D = vrt.get_global_transform_with_canvas()
		var r: Rect2 = vrt.get_line_rect(0)
		var y := r.position.y + r.size.y * 0.5
		var t0 := Time.get_ticks_msec()
		await _drag(xf * Vector2(r.position.x + 5, y), xf * Vector2(r.position.x + r.size.x * 0.45, y))
		print("E2E TICK arrastre %d ms sel=%s" % [Time.get_ticks_msec() - t0, vrt.get_selection_range()])
		_mouse(xf * Vector2(r.position.x + r.size.x * 0.6, y), true, true)
		await _frames(2)
		_mouse(xf * Vector2(r.position.x + r.size.x * 0.6, y), false)
		await _frames(4)
		print("E2E TICK doble clic sel=%s" % [vrt.get_selection_range()])
		for i in 4:
			await _key(KEY_RIGHT, true, true)
		print("E2E TICK teclado sel=%s" % [vrt.get_selection_range()])
		# Lápiz: pulsar y arrastrar SIN que llegue el «soltar»; luego el
		# puntero se mueve sin botón → la selección NO debe seguirle.
		_mouse(xf * Vector2(r.position.x + 5, y), true)
		await _frames(2)
		var mv := InputEventMouseMotion.new()
		mv.position = xf * Vector2(r.position.x + r.size.x * 0.3, y)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await _frames(2)
		var sel_pen: Vector2i = vrt.get_selection_range()
		for k in 5:
			var hv := InputEventMouseMotion.new()
			hv.position = xf * Vector2(r.position.x + r.size.x * (0.5 + k * 0.08), y)
			hv.global_position = hv.position
			hv.button_mask = 0
			Input.parse_input_event(hv)
			await _frames(1)
		_check(vrt.get_selection_range() == sel_pen, "%s: sin botón pulsado la selección no sigue al puntero (%s → %s)" % [mode, sel_pen, vrt.get_selection_range()])
		var t1 := Time.get_ticks_msec()
		await _frames(30)
		var ms := Time.get_ticks_msec() - t1
		_check(ms < 3000, "%s: la app sigue respondiendo (30 frames en %d ms)" % [mode, ms])
		_check(String(vrt.get_text()) == "Unas palabras para seleccionar con el ratón", "%s: el texto no cambia al seleccionar" % mode)
		vrt.stop_editing()
		await _frames(4)
	print("E2E RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
