## UX-01: editar un párrafo con el panel de tipografía abierto. Escribir 200
## caracteres no pierde el cursor; cambiar tamaño y color desde el panel no
## cancela la edición. En los tres modos de interfaz.
##   godot --path . --screen 1 -s res://test/e2e/paragraph_panel_e2e.gd
extends SceneTree

var fails: Array[String] = []

func _initialize() -> void:
	create_timer(220).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _type(ch: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		var code := OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
		ev.keycode = code
		ev.physical_keycode = code
		ev.unicode = ch.unicode_at(0)
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await process_frame

func _find(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find(c, suffix)
		if r:
			return r
	return null

func _show(c: Control) -> void:
	var a: Node = c
	while a is CanvasItem:
		(a as CanvasItem).visible = true
		a = a.get_parent()

func _mouse(pos: Vector2, pressed: bool, mask := 0) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.warp_mouse(pos)
	Input.parse_input_event(ev)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame

## Cambia el tamaño con el control REAL del panel (ratón/teclado). Devuelve
## una descripción de lo usado o "" si no hay control visible.
func _find_path(n: Node, tail: String) -> Node:
	if String(n.get_path()).ends_with(tail):
		return n
	for c in n.get_children():
		var r := _find_path(c, tail)
		if r:
			return r
	return null

func _panel_size(mode: String) -> String:
	if mode == "professional":
		var pro = _find(root, "ui/pro/pro_studio.gd")
		var nf = pro.get("_spin_font_size") if pro else null
		if not (nf is Control):
			return ""
		_show(nf)
		await _frames(4)
		var c: Vector2 = (nf as Control).get_global_rect().get_center()
		_mouse(c, true)
		await _frames(2)
		_mouse(c, false)
		await _frames(3)
		var le: LineEdit = nf.get("_line_edit")
		if le:
			le.select_all()
		for ch in "44":
			await _type(ch)
		await _key(KEY_ENTER)
		await _frames(3)
		return "campo numérico Pro"
	var sl := _find_path(root, "Row_font_size/HSlider") as HSlider
	if sl == null:
		return ""
	_show(sl)
	await _frames(4)
	var r := sl.get_global_rect()
	var a := Vector2(r.position.x + r.size.x * 0.2, r.get_center().y)
	var b := Vector2(r.position.x + r.size.x * 0.4, r.get_center().y)
	_mouse(a, true)
	await _frames(2)
	for i in range(1, 6):
		var mv := InputEventMouseMotion.new()
		mv.position = a.lerp(b, i / 5.0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await _frames(1)
	_mouse(b, false)
	await _frames(3)
	return "deslizador del panel de tipografía"

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
	var ic = root.get_node("InspectorCore")
	for mode in ["smart", "modern", "professional"]:
		if gui and gui.has_method("set_ui_mode"):
			gui.set_ui_mode(mode)
		await _frames(15)
		canvas.switch_tool("paragraph")
		await _frames()
		var p: Node2D = canvas.current_tool.create_at_center()
		await _frames()
		canvas.switch_tool("paragraph")
		await _frames()
		var tool = canvas.current_tool
		tool._check_and_trigger_edit_at(p)
		await _frames(4)
		var vrt = p.get_node("VectorRichText")
		_check(vrt.is_editing(), "%s: entra a editar" % mode)
		vrt.set_caret_index(int(vrt.get_char_count()))
		await _frames()
		var n0: int = int(vrt.get_char_count())
		var t0 := Time.get_ticks_msec()
		var words := "hola mundo vectopen "
		for i in 200:
			await _type(words[i % words.length()])
		var ms := Time.get_ticks_msec() - t0
		var n1: int = int(vrt.get_char_count())
		print("E2E %s: escritos %d caracteres en %d ms, caret=%d" % [mode, n1 - n0, ms, vrt.get_caret_index()])
		_check(n1 - n0 == 200, "%s: se escriben los 200 caracteres (%d)" % [mode, n1 - n0])
		_check(int(vrt.get_caret_index()) == n1, "%s: el cursor sigue al final (%d/%d)" % [mode, vrt.get_caret_index(), n1])
		_check(vrt.is_editing() and bool(tool.is_editing), "%s: sigue editando tras escribir" % mode)
		var f = root.gui_get_focus_owner()
		_check(f == vrt, "%s: el foco sigue en el editor (%s)" % [mode, f.get_path() if f else "null"])
		# Cambiar tamaño y color desde el panel (la ruta de todos los paneles).
		ic.apply("font_size", 30)
		await _frames(3)
		ic.apply("fill_color", Color(0.8, 0.1, 0.1))
		await _frames(3)
		_check(vrt.is_editing() and bool(tool.is_editing), "%s: cambiar tamaño y color no cancela la edición" % mode)
		await _type("x")
		_check(int(vrt.get_char_count()) == n1 + 1, "%s: se puede seguir escribiendo después" % mode)
		_check(int(p.get_meta("font_size", 0)) == 30 or is_equal_approx(float(vrt.get_font_size()), 30.0), "%s: el tamaño se aplicó (%s)" % [mode, vrt.get_font_size()])
		# Con los CONTROLES REALES del panel (ratón y teclado).
		var fs_before := float(vrt.get_font_size())
		var used: String = await _panel_size(mode)
		print("E2E %s: control usado: %s; tamaño %s → %s; editando=%s foco=%s" % [mode, used, fs_before, vrt.get_font_size(), vrt.is_editing(), root.gui_get_focus_owner()])
		_check(used != "", "%s: hay control de tamaño en el panel" % mode)
		_check(vrt.is_editing() and bool(tool.is_editing), "%s: usar el control del panel no cancela la edición" % mode)
		_check(not is_equal_approx(float(vrt.get_font_size()), fs_before), "%s: el control cambia el tamaño (%s → %s)" % [mode, fs_before, vrt.get_font_size()])
		# Volver a escribir: el cursor debe seguir en su sitio.
		var nb: int = int(vrt.get_char_count())
		await _type("z")
		_check(int(vrt.get_char_count()) == nb + 1, "%s: tras usar el panel se sigue escribiendo en el párrafo" % mode)
		vrt.stop_editing()
		await _frames(4)
	print("E2E RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
