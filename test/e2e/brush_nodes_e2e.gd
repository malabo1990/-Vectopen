# =============================================================================
# NODOS DE UN TRAZO DE PINCEL: doble clic con Mover → modo nodos con una curva
# ajustada (pocos nodos); arrastrar un nodo cambia el trazo (con su presión);
# Ctrl+Z lo devuelve; al salir no queda nada auxiliar y deshacer sigue yendo.
#   test/run_e2e.sh brush_nodes_e2e
# =============================================================================
extends SceneTree

const OUT := "user://brush_nodes"
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
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
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

func mouse(at: Vector2, held: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	await process_frame

func button(at: Vector2, down: bool, dbl: bool = false) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.double_click = dbl
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(mb)
	await process_frame

func key(code: Key, ctrl: bool = false) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.ctrl_pressed = ctrl
		k.pressed = down
		_send(k)
		await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var sm = root.get_node("SelectionManager")
	var hm = root.get_node("HistoryManager")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	cam.zoom = Vector2.ONE
	cam.position = ab.to_global(ac)
	var cur = canvas.get_current_tool()
	if cur == null or not cur.has_method("get_class_name") or cur.get_class_name() != "MoveTool":
		canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/MoveTool.gd")))
	await frames(4)
	# Trazo de pincel en «S» con 120 muestras y presión variable
	var l := Line2D.new()
	l.name = "Pincel S"
	var pts := PackedVector2Array()
	for i in 120:
		var t := i / 119.0
		pts.append(ac + Vector2(-250 + 500 * t, sin(t * TAU) * 90.0))
	l.points = pts
	l.width = 10.0
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0.3))
	wc.add_point(Vector2(0.5, 1.0))
	wc.add_point(Vector2(1, 0.3))
	l.width_curve = wc
	l.default_color = Color(0.1, 0.1, 0.12)
	l.set_meta("brush_style", "pen")
	ab.add_child(l)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
	await frames(6)
	sm.clear()
	await frames(2)
	var pts0 := l.points
	# Doble clic sobre el trazo
	var on_stroke: Vector2 = ab.to_global(pts[30])
	var s0 := scr(on_stroke)
	await mouse(s0, false)
	await button(s0, true)
	await button(s0, false)
	await button(s0, true, true)
	await button(s0, false)
	await frames(6)
	var tool = canvas.get_current_tool()
	var is_node_tool: bool = tool != null and tool.has_method("get_class_name") and tool.get_class_name() == "NodeSelectionTool"
	check("doble clic en un trazo de pincel abre el modo nodos", is_node_tool, str(tool.get_class_name() if tool and tool.has_method("get_class_name") else tool))
	if not is_node_tool:
		quit(1)
		return
	var proxy: Path2D = tool.edit_path
	check("edita ESE trazo (curva ajustada a él)", proxy != null and proxy.has_meta("proxy_for") and proxy.get_meta("proxy_for") == l)
	var n_nodes: int = proxy.curve.point_count if proxy else 0
	check("pocos nodos editables (2–20 para 120 muestras)", n_nodes >= 2 and n_nodes <= 20, str(n_nodes))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("1_nodos.png"))
	# Arrastrar un nodo intermedio con el ratón
	var k := int(n_nodes / 2)
	var node_g: Vector2 = proxy.to_global(proxy.curve.get_point_position(k))
	var a := scr(node_g)
	var b := scr(node_g + Vector2(0, 80))
	await mouse(a, false)
	await button(a, true)
	for i in range(1, 9):
		await mouse(a.lerp(b, i / 8.0), true)
	await button(b, false)
	await frames(6)
	var moved := 0.0
	for i in mini(pts0.size(), l.points.size()):
		pass
	var near_new := INF
	for q in l.points:
		near_new = minf(near_new, ab.to_global(q).distance_to(node_g + Vector2(0, 80)))
	check("arrastrar el nodo cambia el trazo (pasa por el nuevo sitio)", near_new < 3.0, "%.2f" % near_new)
	check("la presión se conserva (misma curva de grosor)", l.width_curve == wc)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("2_movido.png"))
	# Ctrl+Z
	await key(KEY_Z, true)
	await frames(4)
	check("Ctrl+Z devuelve el trazo como estaba", l.points == pts0 or _same(l.points, pts0), "%d vs %d puntos" % [l.points.size(), pts0.size()])
	hm.redo()
	await frames(4)
	var pts1 := l.points
	check("rehacer vuelve a mover", not _same(pts1, pts0))
	# Salir del modo nodos (Esc): sin auxiliar, el trazo seleccionado
	await key(KEY_ESCAPE)
	await frames(6)
	var left := 0
	for n in canvas.find_children("_BrushNodeProxy*", "", true, false):
		left += 1
	check("al salir no queda la curva auxiliar", left == 0, str(left))
	check("al salir queda seleccionado el trazo", sm.get_selected().has(l), str(sm.get_selected()))
	hm.undo()
	await frames(4)
	check("deshacer después de salir sigue funcionando", _same(l.points, pts0))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)

func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.01:
			return false
	return true
