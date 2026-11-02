## E2E: el formato de letra se aplica SOLO a lo seleccionado (como Word /
## InDesign). Párrafo en edición, frase seleccionada, botón MAYÚSCULAS del
## panel Pro y cada propiedad de letra vía InspectorCore (la ruta de todos los
## paneles). El resto del texto no cambia; Ctrl+Z deshace.
extends SceneTree

var fails: Array[String] = []
const TEXT := "Primera frase normal. Segunda frase elegida. Tercera frase final."
const A := 22   # «Segunda frase elegida.»
const B := 44

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

## Valor de `key` en cada carácter según los tramos.
func _vals(runs: Array, key: String, def) -> Array:
	var out := []
	for r in runs:
		for i in int(r.get("length", 0)):
			out.append(r.get(key, def))
	return out

func _only_range(runs: Array, key: String, def, expect) -> bool:
	var v := _vals(runs, key, def)
	for i in v.size():
		var inside := i >= A and i < B
		var same: bool = (v[i] == expect) if not (expect is float) else is_equal_approx(float(v[i]), expect)
		if inside != same:
			print("   char %d %s=%s" % [i, key, v[i]])
			return false
	return true

func _find(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find(c, suffix)
		if r:
			return r
	return null

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	canvas.switch_tool("paragraph")
	await _frames()
	var p: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	p.set_meta("text", TEXT)
	var vrt = p.get_node("VectorRichText")
	vrt.set_text(TEXT)
	await _frames()
	canvas.switch_tool("paragraph")
	await _frames()
	canvas.current_tool._check_and_trigger_edit_at(p)
	await _frames(4)
	_check(vrt.is_editing(), "editando")
	vrt.set_selection_range(A, B)
	await _frames()

	# 1) MAYÚSCULAS con el botón del panel Pro (o su función).
	var pro = _find(root, "ui/pro/pro_studio.gd")
	if pro and pro.get("_btn_case_upper"):
		pro._btn_case_upper.pressed.emit()
	else:
		ic.apply_case("upper")
	await _frames(3)
	var t := String(vrt.get_text())
	_check(t.substr(A, B - A) == "SEGUNDA FRASE ELEGIDA.", "MAYÚSCULAS solo en la frase («%s»)" % t.substr(A, B - A))
	_check(t.substr(0, A) == TEXT.substr(0, A) and t.substr(B) == TEXT.substr(B), "el resto del párrafo NO cambia")
	_check(vrt.get_selection_range() == Vector2i(A, B), "la frase sigue seleccionada (%s)" % vrt.get_selection_range())
	await _key(KEY_Z, true)
	await _frames(2)
	_check(String(vrt.get_text()) == TEXT, "Ctrl+Z deshace las mayúsculas")
	vrt.set_selection_range(A, B)
	await _frames()

	# 2) Cada propiedad de letra, solo en la frase.
	var cases := [
		["font_weight", 700, "weight", 400, 700],
		["font_italic", true, "italic", false, true],
		["underline", true, "underline", false, true],
		["strikethrough", true, "strikethrough", false, true],
		["font_size", 40, "size", -1.0, 40.0],
		["fill_color", Color(1, 0, 0), "color", null, Color(1, 0, 0)],
		["letter_spacing", 3.0, "letter_spacing", 0.0, 3.0],
		["baseline_shift", 5.0, "baseline_shift", 0.0, 5.0],
		["font_family", "Liberation Serif", "family", "", "Liberation Serif"],
	]
	for c in cases:
		vrt.set_selection_range(A, B)
		ic.apply(c[0], c[1])
		await _frames(2)
		var runs: Array = vrt.get_runs_meta()
		_check(_only_range(runs, c[2], c[3], c[4]), "%s solo en la frase" % c[0])
		_check(_only_range(p.get_meta("runs", []), c[2], c[3], c[4]), "%s guardado en el texto (meta)" % c[0])
	# Contorno
	vrt.set_selection_range(A, B)
	ic.apply("stroke_width", 2.0)
	await _frames(2)
	_check(_only_range(vrt.get_runs_meta(), "stroke_width", 0.0, 2.0), "contorno solo en la frase")
	var shot := OS.get_environment("E2E_OUT")
	if shot != "":
		var cam: Camera2D = canvas.get_node_or_null("Camera2D")
		if cam:
			cam.global_position = p.global_position + Vector2(175, 60)
			cam.zoom = Vector2(2, 2)
		await _frames(6)
		root.get_texture().get_image().save_png(shot + "/seleccion.png")
	# Deshacer todo lo aplicado.
	var hm = root.get_node("HistoryManager")
	for i in 10:
		print("E2E UNDO %d → «%s» editando=%s" % [i, hm.get_undo_name(), vrt.is_editing()])
		await _key(KEY_Z, true)
	print("E2E tramos finales: %s" % [vrt.get_runs_meta().map(func(r): return [r["length"], r.get("weight"), r.get("italic"), r.get("family", "")])])
	await _frames(2)
	var runs_after: Array = vrt.get_runs_meta()
	_check(_only_range(runs_after, "weight", 400, 400 if false else 999) == false and _vals(runs_after, "weight", 400).all(func(w): return int(w) == 400), "Ctrl+Z ×10 devuelve el formato original")
	print("E2E RESULT %d fallos" % fails.size())
	quit(0 if fails.is_empty() else 1)
