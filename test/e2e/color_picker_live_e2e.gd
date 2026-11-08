# =============================================================================
# Selector de color en tiempo real: arrastrar sobre el selector con varias
# figuras y trazos seleccionados debe ir fluido, dejar UN solo paso de
# deshacer y guardar los recientes una vez (antes, uno por movimiento).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/color_picker_live_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(170.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	var api = root.get_node("PluginManager").api
	var shapes: Array = []
	for i in 30:
		shapes.append(api.add_rect(Vector2(40 + (i % 6) * 110, 60 + (i / 6) * 110), Vector2(90, 90)))
	api.select(shapes)
	await frames(10)
	# Abrir el selector con su botón real de la barra (Smart, «Color Picker»).
	var gestor: Node = null
	var bar := root.find_child("BARRA_VISUAL", true, false)
	if bar:
		for x in bar.find_children("*", "Button", true, false):
			if String((x as Button).tooltip_text).to_lower().contains("color"):
				(x as Button).button_pressed = true
				(x as Button).pressed.emit()
				break
	await frames(20)
	for n in root.find_children("*", "", true, false):
		if n is Control and n.get_script() and String(n.get_script().resource_path).ends_with("managercolor_pickrColor.gd") and (n as Control).is_visible_in_tree():
			gestor = n
			break
	check("selector de color visible", gestor != null and (gestor.picker_panel as Control).is_visible_in_tree())
	if gestor == null:
		quit(1)
		return
	var pp: Control = gestor.picker_panel
	var r := pp.get_global_rect()
	var cc = root.get_node("ColorCore")
	cc.set_target("fill")
	var hm = root.get_node("HistoryManager")
	var steps0: int = hm._undo_redo.undo_stack.size()
	var before_col: Color = shapes[0].fill_color
	var cfg := ProjectSettings.globalize_path("user://color_state.cfg")
	var mtime0 := FileAccess.get_modified_time(cfg) if FileAccess.file_exists(cfg) else 0
	var a := r.position + r.size * Vector2(0.3, 0.3)
	# Referencia: lo que tarda un fotograma moviendo el ratón SIN arrastrar
	# (incluye la espera de la pantalla, 16,7 ms a 60 Hz).
	var tb := Time.get_ticks_usec()
	for i in 60:
		var mmb := InputEventMouseMotion.new()
		mmb.position = r.position + r.size * Vector2(0.3 + i * 0.005, 0.3)
		mmb.global_position = mmb.position
		_send(mmb)
		await process_frame
	var base_ms := (Time.get_ticks_usec() - tb) / 1000.0 / 60.0
	var mm0 := InputEventMouseMotion.new()
	mm0.position = a
	mm0.global_position = a
	_send(mm0)
	await frames(2)
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await frames(2)
	var t0 := Time.get_ticks_usec()
	var nmoves := 60
	for i in nmoves:
		var t := i / float(nmoves - 1)
		var p := r.position + r.size * Vector2(0.3 + 0.5 * t, 0.3 + 0.4 * sin(t * PI))
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(mm)
		await process_frame
	var per_ms := (Time.get_ticks_usec() - t0) / 1000.0 / nmoves
	var live_seen: bool = cc.is_live()
	var mid_steps: int = hm._undo_redo.undo_stack.size() - steps0
	mb = mb.duplicate()
	mb.pressed = false
	mb.button_mask = 0
	_send(mb)
	await frames(6)
	var steps: int = hm._undo_redo.undo_stack.size() - steps0
	print("INFO %.1f ms por movimiento (sin arrastrar %.1f ms); pasos durante=%d, al soltar=%d" % [per_ms, base_ms, mid_steps, steps])
	check("arrastrar es en vivo", live_seen)
	check("fluido (≥ 45 fps con 30 figuras)", per_ms < 22.0, "%.1f ms" % per_ms)
	check("sin pasos de deshacer mientras se arrastra", mid_steps == 0, str(mid_steps))
	check("UN solo paso de deshacer al soltar", steps == 1, str(steps))
	var after_col: Color = shapes[0].fill_color
	check("el color llega a las figuras", not after_col.is_equal_approx(before_col) and shapes[29].fill_color.is_equal_approx(after_col))
	check("el color va a recientes", cc.recents.size() > 0 and cc.recents[0].is_equal_approx(after_col))
	hm.undo()
	await frames(4)
	check("un Ctrl+Z devuelve el color de antes", shapes[0].fill_color.is_equal_approx(before_col) and shapes[29].fill_color.is_equal_approx(before_col))
	# Perfil: coste de cada parte de un movimiento en vivo
	api.select(shapes)
	await frames(4)
	var mb2 := InputEventMouseButton.new()
	mb2.position = a
	mb2.global_position = a
	mb2.button_index = MOUSE_BUTTON_LEFT
	mb2.pressed = true
	mb2.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb2)
	var ic = root.get_node("InspectorCore")
	var tA := Time.get_ticks_usec()
	for i in 20:
		cc.set_color(Color(0.1 + i * 0.03, 0.3, 0.5))
	var tB := Time.get_ticks_usec()
	for i in 20:
		for sh in ic.selection():
			ic._write(sh, "fill_color", Color(0.5, 0.1 + i * 0.03, 0.5))
	var tC := Time.get_ticks_usec()
	for i in 20:
		gestor.establecer_color(Color(0.2, 0.2, 0.1 + i * 0.03), true)
	var tD := Time.get_ticks_usec()
	print("INFO por cambio: ColorCore.set_color=%.1f ms  solo escribir 30 figuras=%.1f ms  selector completo=%.1f ms" % [(tB - tA) / 20000.0, (tC - tB) / 20000.0, (tD - tC) / 20000.0])
	mb2 = mb2.duplicate()
	mb2.pressed = false
	_send(mb2)
	await frames(4)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
