## E2E de «Convertir a curvas» en la app real: un texto de 2 líneas y 2 colores
## → Ctrl+Mayús+O → grupo con una forma por letra en la misma posición; Ctrl+Z
## lo deshace. Captura antes/después en E2E_OUT.
extends SceneTree

var fails: Array[String] = []

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _run() -> void:
	var out := OS.get_environment("E2E_OUT")
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var t: Node2D = api.add_text(Vector2(120, 160), "Hola Vectopen\nCurvas", 72, Color(0.1, 0.3, 0.8))
	await _frames(4)
	var vrt = t.get_node_or_null("VectorRichText")
	vrt.start_editing()
	vrt.set_selection_range(5, 13)
	vrt.apply_color_to_selection(Color(0.9, 0.2, 0.1))
	vrt.stop_editing()
	await _frames(4)
	var cam: Camera2D = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.global_position = t.global_position + Vector2(260, 90)
		cam.zoom = Vector2(1.5, 1.5)
	canvas.switch_tool("move")
	root.get_node("SelectionManager").select(t)
	await _frames(6)
	if out != "":
		root.get_texture().get_image().save_png(out + "/curvas_antes.png")
	var parent := t.get_parent()
	var n_before := parent.get_child_count()
	var tpos := t.global_position
	await _key(KEY_O, true, true)
	await _frames(6)
	var g: Node2D = null
	for c in parent.get_children():
		if String(c.name).ends_with("(curvas)"):
			g = c
	_check(g != null, "Ctrl+Mayús+O crea el grupo «(curvas)»")
	_check(not is_instance_valid(t) or t.get_parent() == null, "el texto se reemplaza")
	if g:
		var letters := g.get_children().filter(func(c): return c is Path2D)
		print("E2E letras=%d" % letters.size())
		_check(letters.size() == 18, "una forma por letra visible (%d, esperado 18)" % letters.size())
		var reds := letters.filter(func(c): return (c.fill_color as Color).r > 0.8)
		_check(reds.size() == 8, "las letras de 'Vectopen' conservan su color rojo (%d)" % reds.size())
		_check(g.global_position.is_equal_approx(tpos), "misma posición que el texto")
		if out != "":
			await _frames(4)
			root.get_texture().get_image().save_png(out + "/curvas_despues.png")
	await _key(KEY_Z, true)
	await _frames(4)
	_check(is_instance_valid(t) and t.get_parent() == parent and parent.get_child_count() == n_before, "Ctrl+Z devuelve el texto")
	print("E2E RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
