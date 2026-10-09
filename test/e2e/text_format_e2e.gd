## E2E del formato de texto sobre la APP REAL (escena principal renderizada):
## crea un párrafo, entra a editar, selecciona palabras y pulsa Ctrl+B / I / U
## con eventos de teclado REALES (Input.parse_input_event → foco del editor),
## y guarda capturas en E2E_OUT (por defecto user://e2e/).
##   godot --path . -s res://test/e2e/text_format_e2e.gd
## No es una suite gdUnit (necesita ventana para las capturas).
extends SceneTree

var out_dir := "user://e2e"
var fails: Array[String] = []

func _initialize() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "":
		out_dir = env_out
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _shot(tag: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, tag])
	print("E2E shot: ", tag)

func _key(code: Key, ctrl := false, shift := false) -> void:
	for pressed in [true, false]:
		print("E2E KEY %s ctrl=%s pressed=%s (frame %d)" % [OS.get_keycode_string(code), ctrl, pressed, Engine.get_process_frames()])
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

## ¿Todos los caracteres [a, b) de `runs` cumplen key=true?
func _range_has(runs: Array, a: int, b: int, key: String) -> bool:
	var pos := 0
	for r in runs:
		var l := int(r.get("length", 0))
		if pos + l > a and pos < b and not bool(r.get(key, false)):
			return false
		pos += l
	return true

## Estado real para diagnosticar (foco, editor, selección, visibilidad).
func _diag(tag: String, shape: Node2D) -> void:
	var fo = root.gui_get_focus_owner()
	var vrt = shape.get_node_or_null("VectorRichText")
	var dl: Control = shape.get_node_or_null("DisplayLabel")
	var me: Control = shape.get_node_or_null("MultiLineEdit")
	var cv = get_first_node_in_group("_vectopen_canvas")
	print("E2E DIAG [%s] focus=%s tool=%s" % [tag, fo.get_path() if fo else "null", cv.current_tool.get_script().resource_path.get_file() if cv and cv.current_tool else "null"])
	if vrt:
		print("  vrt visible=%s editing=%s sel=%s size=%s runs=%s" % [vrt.visible, vrt.is_editing(), vrt.get_selection_range(), vrt.size, vrt.get_runs_meta()])
	if dl:
		print("  label visible=%s self_mod=%s vratio=%s" % [dl.visible, dl.self_modulate, (dl as Label).visible_ratio])
	if me:
		print("  multiedit visible=%s" % me.visible)
	print("  meta runs=%s" % [shape.get_meta("runs", [])])

func _select(shape: Node2D, a: int, b: int) -> void:
	var vrt = shape.get_node_or_null("VectorRichText")
	if vrt and vrt.is_editing():
		vrt.set_selection_range(a, b)
	else:
		var ed: TextEdit = shape.get_node("MultiLineEdit")
		ed.grab_focus()
		ed.select(0, a, 0, b)
	await _frames(2)

func _run() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(20)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	_check(canvas != null, "canvas cargado")
	if canvas == null:
		quit(1)
		return
	var vrt_ok := ClassDB.class_exists("VectorRichText")
	print("E2E modo: ", "VectorRichText (nativo)" if vrt_ok else "TextEdit (GDScript)")

	canvas.switch_tool("paragraph")
	await _frames()
	var p: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	p.set_meta("text", "Hola mundo feliz de Vectopen")
	(p.get_node("DisplayLabel") as Label).text = "Hola mundo feliz de Vectopen"
	# Encuadre: cámara centrada en el párrafo, zoom 2x.
	var cam: Camera2D = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.global_position = p.global_position + Vector2(175, 50)
		cam.zoom = Vector2(2, 2)
	await _frames()

	await _shot("0a_creado")
	canvas.switch_tool("paragraph")
	await _frames()
	var tool = canvas.current_tool
	tool._check_and_trigger_edit_at(p)
	await _frames()
	_check(bool(tool.is_editing), "entra en edición")
	await _shot("0b_editando_sin_cambios")

	var vrt_n = p.get_node_or_null("VectorRichText")
	if vrt_n:
		vrt_n.editing_finished.connect(func(): print("E2E EVENT vrt.editing_finished (frame %d)" % Engine.get_process_frames()))
		vrt_n.focus_exited.connect(func():
			print("E2E EVENT vrt.focus_exited (frame %d) nuevo foco=%s" % [Engine.get_process_frames(), root.gui_get_focus_owner()])
			for fr in get_stack():
				print("    at %s:%d %s()" % [fr["source"], fr["line"], fr["function"]]))
	# 1) "mundo" (5..10) → Ctrl+B
	await _select(p, 5, 10)
	_diag("tras seleccionar mundo", p)
	await _key(KEY_B, true)
	_diag("tras Ctrl+B mundo", p)
	await _shot("1_bold_mundo_editando")
	var runs: Array = p.get_meta("runs", [])
	_check(_range_has(runs, 5, 10, "bold"), "Ctrl+B pone negrita en 'mundo'")
	_check(not _range_has(runs, 0, 4, "bold"), "'Hola' sigue sin negrita")

	# 2) SEGUNDA palabra "feliz" (11..16) → Ctrl+B debe PONER negrita también
	await _select(p, 11, 16)
	_diag("tras seleccionar feliz", p)
	await _key(KEY_B, true)
	_diag("tras Ctrl+B feliz", p)
	await _shot("2_bold_feliz_editando")
	runs = p.get_meta("runs", [])
	_check(_range_has(runs, 11, 16, "bold"), "2º Ctrl+B pone negrita en 'feliz'")
	_check(_range_has(runs, 5, 10, "bold"), "'mundo' conserva la negrita")

	# 3) Ctrl+I y Ctrl+U sobre "Hola"
	await _select(p, 0, 4)
	await _key(KEY_I, true)
	await _key(KEY_U, true)
	runs = p.get_meta("runs", [])
	_check(_range_has(runs, 0, 4, "italic"), "Ctrl+I pone cursiva en 'Hola'")
	_check(_range_has(runs, 0, 4, "underline"), "Ctrl+U subraya 'Hola'")

	# 4) Ctrl+B sobre algo YA en negrita la quita
	await _select(p, 5, 10)
	await _key(KEY_B, true)
	runs = p.get_meta("runs", [])
	_check(not _range_has(runs, 5, 10, "bold"), "Ctrl+B sobre negrita la quita")
	await _select(p, 5, 10)
	await _key(KEY_B, true)

	# 5) Salir de edición (Escape) → el texto renderizado muestra el formato
	await _key(KEY_ESCAPE)
	await _frames(6)
	await _shot("3_tras_salir_de_edicion")
	_check(not (canvas.current_tool == tool and is_instance_valid(tool) and bool(tool.is_editing)), "Escape sale de edición")
	runs = p.get_meta("runs", [])
	_check(_range_has(runs, 11, 16, "bold") and _range_has(runs, 5, 10, "bold"), "formato conservado al salir")
	var dl: WorldTextLabel = p.get_node("DisplayLabel")
	_check(dl.has_rich_runs(), "el label renderiza runs enriquecidos")

	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
