## E2E del CURSOR y la SELECCIÓN de texto en la app real, con eventos de
## teclado y ratón reales (como un usuario de Office / InDesign):
## flechas, Ctrl/Alt+flechas, Inicio/Fin, Shift para seleccionar, clic,
## doble y triple clic, arrastrar y Shift+clic. El objeto NO debe moverse.
##   godot --path . --screen 1 -s res://test/e2e/text_caret_e2e.gd
extends SceneTree

var fails: Array[String] = []
var vrt
var shape: Node2D

const TEXT := "Uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce\nSegundo párrafo con más palabras para probar"

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _key(code: Key, ctrl := false, shift := false, alt := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.alt_pressed = alt
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _caret() -> int:
	return int(vrt.get_caret_index())

func _sel() -> Vector2i:
	return vrt.get_selection_range()

## Posición en PANTALLA del carácter `idx` (centro de su línea).
func _screen_of(idx: int) -> Vector2:
	var best := Vector2.ZERO
	var n: int = int(vrt.get_line_count())
	# Buscar el punto por prueba: recorremos la línea con hit_test.
	for li in n:
		var r: Rect2 = vrt.get_line_rect(li)
		var y := r.position.y + r.size.y * 0.5
		var x := r.position.x
		while x <= r.end.x + 1.0:
			if int(vrt.hit_test(Vector2(x, y))) == idx:
				best = Vector2(x + 1.0, y)
				return vrt.get_global_transform_with_canvas() * best
			x += 1.0
	return vrt.get_global_transform_with_canvas() * best

func _click(pos: Vector2, count := 1, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.double_click = count == 2 and pressed
		ev.position = pos
		ev.global_position = pos
		ev.shift_pressed = shift
		Input.warp_mouse(pos)
		Input.parse_input_event(ev)
		await _frames(2)

func _drag(a: Vector2, b: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = a
	ev.global_position = a
	Input.warp_mouse(a)
	Input.parse_input_event(ev)
	await _frames(2)
	for i in range(1, 9):
		var mv := InputEventMouseMotion.new()
		mv.position = a.lerp(b, i / 8.0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await _frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	Input.parse_input_event(up)
	await _frames(3)

func _line_of(idx: int) -> int:
	var c: Vector2 = vrt.get_global_transform_with_canvas().affine_inverse() * _screen_of(idx)
	for li in int(vrt.get_line_count()):
		if (vrt.get_line_rect(li) as Rect2).grow(0.5).has_point(c):
			return li
	return -1

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	canvas.switch_tool("paragraph")
	await _frames()
	shape = canvas.current_tool.create_at_center()
	await _frames()
	shape.set_meta("text", TEXT)
	vrt = shape.get_node_or_null("VectorRichText")
	if vrt == null:
		_check(false, "hay VectorRichText (motor nativo)")
		quit(1)
		return
	vrt.set_text(TEXT)
	var cam: Camera2D = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.global_position = shape.global_position + Vector2(175, 80)
		cam.zoom = Vector2(2, 2)
	await _frames(4)
	canvas.switch_tool("paragraph")
	await _frames()
	canvas.current_tool._check_and_trigger_edit_at(shape)
	await _frames(4)
	_check(vrt.is_editing(), "entra en edición")
	var pos0 := shape.global_position
	var lines: int = int(vrt.get_line_count())
	print("E2E líneas=%d" % lines)
	_check(lines >= 3, "el párrafo ocupa varias líneas (%d)" % lines)

	# ── teclado ─────────────────────────────────────────────────────────
	vrt.set_caret_index(0)
	await _frames()
	await _key(KEY_RIGHT)
	_check(_caret() == 1, "→ avanza 1 (%d)" % _caret())
	await _key(KEY_LEFT)
	_check(_caret() == 0, "← retrocede 1 (%d)" % _caret())
	await _key(KEY_RIGHT, true)
	_check(_caret() == 4, "Ctrl+→ salta al inicio de la siguiente palabra (%d, esperado 4)" % _caret())
	await _key(KEY_RIGHT, true)
	_check(_caret() == 8, "Ctrl+→ otra vez (%d, esperado 8)" % _caret())
	await _key(KEY_LEFT, true)
	_check(_caret() == 4, "Ctrl+← vuelve al inicio de la palabra (%d, esperado 4)" % _caret())
	await _key(KEY_RIGHT, false, false, true)
	_check(_caret() == 8, "Alt+→ también salta palabra (estilo Mac) (%d)" % _caret())
	vrt.set_caret_index(2)
	await _frames()
	await _key(KEY_DOWN)
	var after_down := _caret()
	_check(_line_of(after_down) == 1, "↓ baja a la línea 2 (caret %d, línea %d)" % [after_down, _line_of(after_down)])
	await _key(KEY_UP)
	_check(_caret() == 2, "↑ vuelve a la misma columna de la línea 1 (%d, esperado 2)" % _caret())
	await _key(KEY_END)
	var end1 := _caret()
	_check(_line_of(end1) == 0 and end1 > 10, "Fin va al final de la línea (%d)" % end1)
	await _key(KEY_HOME)
	_check(_caret() == 0, "Inicio vuelve al principio de la línea (%d)" % _caret())
	await _key(KEY_END, true)
	_check(_caret() == TEXT.length(), "Ctrl+Fin al final del texto (%d/%d)" % [_caret(), TEXT.length()])
	await _key(KEY_HOME, true)
	_check(_caret() == 0, "Ctrl+Inicio al principio (%d)" % _caret())
	await _key(KEY_DOWN, true)
	var p2 := TEXT.find("\n") + 1
	_check(_caret() == p2, "Ctrl+↓ salta al siguiente párrafo (%d, esperado %d)" % [_caret(), p2])
	await _key(KEY_UP, true)
	_check(_caret() == 0, "Ctrl+↑ vuelve al párrafo anterior (%d)" % _caret())
	await _key(KEY_RIGHT, false, true)
	await _key(KEY_RIGHT, false, true)
	await _key(KEY_RIGHT, false, true)
	_check(_sel() == Vector2i(0, 3), "Shift+→ ×3 selecciona 3 letras (%s)" % _sel())
	await _key(KEY_RIGHT, true, true)
	_check(_sel() == Vector2i(0, 4), "Shift+Ctrl+→ amplía hasta la palabra (%s)" % _sel())
	await _key(KEY_LEFT)
	_check(_caret() == 0 and _sel().x == _sel().y, "← con selección va a su inicio y la quita (%d %s)" % [_caret(), _sel()])
	await _key(KEY_PAGEDOWN)
	_check(_caret() > 0, "AvPág baja (%d)" % _caret())
	_check(shape.global_position.is_equal_approx(pos0), "el objeto NO se mueve con las flechas (%s → %s)" % [pos0, shape.global_position])

	# ── ratón ───────────────────────────────────────────────────────────
	var p_dos := _screen_of(5)
	await _click(p_dos)
	_check(abs(_caret() - 5) <= 1, "clic coloca el cursor en el punto (%d, esperado 5)" % _caret())
	await _click(_screen_of(9), 2)
	_check(_sel() == Vector2i(8, 12), "doble clic selecciona la palabra 'tres' (%s)" % _sel())
	await _click(_screen_of(9), 3)
	_check(_sel().x == 0 and _sel().y >= TEXT.find("\n"), "triple clic selecciona el párrafo (%s)" % _sel())
	await _drag(_screen_of(4), _screen_of(12))
	var s := _sel()
	_check(s.x == 4 and abs(s.y - 12) <= 1, "arrastrar selecciona 'dos tres' (%s)" % s)
	await _click(_screen_of(4))
	await _click(_screen_of(19), 1, true)
	s = _sel()
	_check(s.x == 4 and abs(s.y - 19) <= 1, "Shift+clic amplía la selección (%s)" % s)
	_check(vrt.is_editing(), "sigue editando tras usar el ratón")
	_check(shape.global_position.is_equal_approx(pos0), "el objeto no se movió con el ratón")

	# ── TEXTO ARTÍSTICO (título) con varias líneas ──────────────────────
	var cur = canvas.current_tool
	if cur and cur.has_method("_stop_editing"):
		cur._stop_editing()
	elif vrt.is_editing():
		vrt.stop_editing()
	await _frames(4)
	var api = root.get_node("PluginManager").api
	var title: Node2D = api.add_text(shape.position + Vector2(0, 260), "Línea uno\nLínea dos más larga\nTres", 32)
	await _frames(4)
	canvas.switch_tool("text")
	await _frames()
	var tt = canvas.current_tool
	tt._check_and_trigger_edit_at(tt.target_artboard.to_local(title.global_position + Vector2(12, 12)))
	await _frames(4)
	vrt = title.get_node_or_null("VectorRichText")
	_check(vrt != null and vrt.is_editing(), "título: entra en edición")
	if vrt and vrt.is_editing():
		var tpos := title.global_position
		print("E2E título líneas=%d" % int(vrt.get_line_count()))
		vrt.set_caret_index(3)
		await _frames()
		await _key(KEY_DOWN)
		var d1 := _caret()
		_check(d1 > 9 and d1 < 30, "título: ↓ baja a la línea 2 (%d)" % d1)
		await _key(KEY_DOWN)
		_check(_caret() > 30, "título: ↓ baja a la línea 3 (%d)" % _caret())
		await _key(KEY_UP)
		await _key(KEY_UP)
		_check(_caret() == 3, "título: ↑↑ vuelve a la línea 1, misma columna (%d)" % _caret())
		await _key(KEY_RIGHT, true)
		_check(_caret() == 6, "título: Ctrl+→ salta palabra (%d)" % _caret())
		await _click(_screen_of(14))
		_check(abs(_caret() - 14) <= 1, "título: clic coloca el cursor (%d)" % _caret())
		await _click(_screen_of(14), 2)
		_check(_sel() == Vector2i(10, 15), "título: doble clic selecciona 'Línea' (%s)" % _sel())
		_check(title.global_position.is_equal_approx(tpos), "título: el objeto no se mueve")

	# ── CAMINO REAL: herramienta Mover + DOBLE CLIC sobre el texto ─────────
	if vrt and vrt.is_editing():
		vrt.stop_editing()
	await _frames(4)
	canvas.switch_tool("move")
	await _frames(4)
	vrt = title.get_node_or_null("VectorRichText")
	# Centro de la 1.ª línea del título en pantalla.
	var r0: Rect2 = vrt.get_line_rect(0)
	var spot: Vector2 = vrt.get_global_transform_with_canvas() * (r0.position + Vector2(r0.size.x * 0.3, r0.size.y * 0.5))
	await _click(spot)
	await _click(spot, 2)
	await _frames(6)
	_check(vrt.is_editing(), "doble clic con Mover entra a editar el título")
	if vrt.is_editing():
		var tpos2 := title.global_position
		vrt.set_caret_index(2)
		await _frames()
		await _key(KEY_DOWN)
		_check(_caret() > 9, "doble clic → ↓ baja de línea (%d)" % _caret())
		await _key(KEY_UP)
		_check(_caret() == 2, "doble clic → ↑ sube de línea (%d)" % _caret())
		await _key(KEY_RIGHT)
		_check(_caret() == 3, "doble clic → → avanza (%d)" % _caret())
		_check(title.global_position.is_equal_approx(tpos2), "doble clic → el texto no se mueve con las flechas (%s → %s)" % [tpos2, title.global_position])
		var f = root.gui_get_focus_owner()
		print("E2E foco=%s" % [f.get_path() if f else "null"])

	print("E2E RESULT %d fallos" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
