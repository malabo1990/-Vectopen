# =============================================================================
# UX-19 — «En el Inspector aparecen Script y Shader aunque no haya nada
# asignado: deben estar ocultas y solo mostrarse al pulsar su icono de la
# barra superior.» En Modern y Pro, con clics reales:
#   · con un rectángulo sin shader: ni SHADER ni SCRIPT se ven;
#   · pulsar el icono Shader / Script de la barra la muestra; volver a
#     pulsarlo la oculta;
#   · un objeto con shader asignado sí muestra SHADER (sin pulsar nada).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/fx_sections_hidden_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	root.push_input(mm)
	await process_frame
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mb)
		await process_frame
	await frames(8)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func panel_for(mode: String) -> Control:
	for n in root.find_children("*", "", true, false):
		if is_cls(n, "DockedInspector" if mode == "modern" else "ProStudio") and (n as Control).is_visible_in_tree():
			return n
	return null

func dump(panel: Control, node_name: String) -> String:
	var out := []
	for n in panel.find_children(node_name, "", true, false):
		out.append("%s vis=%s tree=%s" % [String(panel.get_path_to(n)).right(60), (n as CanvasItem).visible, (n as CanvasItem).is_visible_in_tree()])
	return "; ".join(out)

func shown(panel: Control, node_name: String) -> bool:
	for n in panel.find_children(node_name, "", true, false):
		if (n as CanvasItem).visible and (n as Control).get_parent() and ((n as Control).get_parent() as CanvasItem).is_visible_in_tree():
			return true
	return false

func icon(id: String) -> Button:
	for n in root.find_children("Fx_" + id, "Button", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	var sm = root.get_node("SelectionManager")
	var cv = get_first_node_in_group("_vectopen_canvas")
	var ab = cv.get_node("manager_script").get_active_artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Sin shader"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	var shaded: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	shaded.name = "Con shader"
	ab.add_child(shaded)
	shaded.owner = ab
	shaded.size = Vector2(120, 120)
	shaded.position = Vector2(700, 300)
	shaded.set_meta("custom_shader", {"code": "shader_type canvas_item;\nvoid fragment() { COLOR.r = 1.0; }", "params": {}})
	for mode in ["modern", "professional"]:
		gui.set_ui_mode(mode)
		await frames(30)
		sm.set_selection([rect])
		await frames(10)
		var panel := panel_for(mode)
		check("%s: panel visible" % mode, panel != null)
		if panel == null:
			continue
		if mode == "professional":
			panel._select_tab_b(2)   # Efectos (Transformar, Texto, Efectos)
			await frames(6)
		check("%s: sin shader asignado no se ve SHADER" % mode, not shown(panel, "SecShader"))
		check("%s: sin abrirlo no se ve SCRIPT" % mode, not shown(panel, "SecScript"))
		for id in ["shader", "script"]:
			var node := "SecShader" if id == "shader" else "SecScript"
			var b := icon(id)
			check("%s: icono %s en la barra" % [mode, id], b != null)
			if b == null:
				continue
			await click(b)
			check("%s: el icono %s la muestra" % [mode, id], shown(panel, node))
			await click(b)
			check("%s: volver a pulsarlo la oculta" % mode + " (" + id + ")", not shown(panel, node))
		sm.set_selection([shaded])
		await frames(10)
		if mode == "professional":
			panel._select_tab_b(2)
			await frames(6)
		check("%s: con shader asignado sí se ve SHADER" % mode, shown(panel, "SecShader"))
		check("%s: SCRIPT sigue oculto" % mode, not shown(panel, "SecScript"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
