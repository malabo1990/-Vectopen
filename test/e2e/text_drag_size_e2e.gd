## UX-02: con la herramienta Texto, el tamaño previsualizado al arrastrar es
## el que queda al soltar, y mover el texto después no lo cambia.
##   godot --path . --screen 1 -s res://test/e2e/text_drag_size_e2e.gd
extends SceneTree

var fails: Array[String] = []

func _initialize() -> void:
	create_timer(150).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _btn(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.warp_mouse(pos)
	Input.parse_input_event(ev)

func _move(pos: Vector2, held := true) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(mv)

func _state(t: Node2D) -> Dictionary:
	var vrt = t.get_node_or_null("VectorRichText")
	return {
		"meta_fs": int(t.get_meta("font_size", -1)),
		"vrt_fs": float(vrt.get_font_size()) if vrt else -1.0,
		"content": vrt.get_content_size() if vrt else Vector2.ZERO,
		"scale": t.scale,
		"h": float(t.get_meta("height", 0.0)),
	}

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var gui = root.get_node_or_null("GlobalUI")
	var api = root.get_node("PluginManager").api
	for mode in ["smart", "modern", "professional"]:
		if gui and gui.has_method("set_ui_mode"):
			gui.set_ui_mode(mode)
		await _frames(15)
		var ab: Node2D = api.artboard()
		var before := ab.get_children().size()
		canvas.switch_tool("text")
		await _frames(3)
		var vp := root.get_visible_rect().size
		var a := vp * Vector2(0.35, 0.4)
		var b := a + Vector2(30, 90)
		_btn(a, true)
		await _frames(2)
		for i in range(1, 9):
			_move(a.lerp(b, i / 8.0))
			await _frames(1)
		var preview: int = canvas.current_tool.drag_font_size
		_btn(b, false)
		await _frames(8)
		var created: Array = ab.get_children().slice(before)
		var t: Node2D = null
		for c in created:
			if String(c.get_meta("shape_type", "")).begins_with("text_"):
				t = c
		_check(t != null, "%s: se crea el texto al soltar" % mode)
		if t == null:
			continue
		var s0 := _state(t)
		print("E2E %s: previsualización %d pt → %s" % [mode, preview, s0])
		_check(s0["meta_fs"] == preview and is_equal_approx(s0["vrt_fs"], preview), "%s: el tamaño al soltar = el previsualizado (%d)" % [mode, preview])
		_check(is_equal_approx(t.scale.x, 1.0), "%s: sin escala oculta (%s)" % [mode, t.scale])
		# Mover con la herramienta Mover (arrastre real).
		canvas.switch_tool("move")
		await _frames(3)
		root.get_node("SelectionManager").select(t)
		await _frames(3)
		var vrt = t.get_node("VectorRichText")
		var grab: Vector2 = vrt.get_global_transform_with_canvas() * (vrt.get_line_rect(0) as Rect2).get_center()
		_btn(grab, true)
		await _frames(2)
		for i in range(1, 9):
			_move(grab + Vector2(12 * i, 6 * i))
			await _frames(1)
		_btn(grab + Vector2(96, 48), false)
		await _frames(8)
		var s1 := _state(t)
		print("E2E %s: tras mover → %s" % [mode, s1])
		_check(s1["meta_fs"] == s0["meta_fs"] and is_equal_approx(s1["vrt_fs"], s0["vrt_fs"]), "%s: mover no cambia el tamaño de letra" % mode)
		_check((s1["content"] as Vector2).is_equal_approx(s0["content"]) and is_equal_approx(t.scale.x, 1.0), "%s: mover no cambia la caja (%s → %s)" % [mode, s0["content"], s1["content"]])
		api.delete([t])
		await _frames(4)
	# Párrafo de 40 pt SIN tramos: entrar a editar no debe devolverlo a 24.
	canvas.switch_tool("paragraph")
	await _frames()
	var p: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	p.set_meta("font_size", 40)
	p.remove_meta("runs")
	p.get_node("VectorRichText").set_font_size(40.0)
	canvas.switch_tool("paragraph")
	await _frames()
	canvas.current_tool._check_and_trigger_edit_at(p)
	await _frames(4)
	var pv = p.get_node("VectorRichText")
	_check(pv.is_editing() and is_equal_approx(float(pv.get_font_size()), 40.0), "párrafo de 40 pt sigue a 40 al editarlo (%s)" % pv.get_font_size())
	print("E2E RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
