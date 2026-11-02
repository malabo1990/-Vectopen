# =============================================================================
# UX-10 — Borrar con X, Supr/Delete y Retroceso en TODOS los contextos.
# («Supr» es la tecla Delete en los teclados españoles: mismo código.)
# Para cada tecla y cada contexto, con el teclado de verdad:
#   · lienzo: objeto seleccionado → se borra (y Ctrl+Z lo recupera);
#   · nodos: nodo seleccionado de un trazado → se quita el nodo;
#   · capas: fila seleccionada con el árbol enfocado → se borra la capa;
#   · páginas: página seleccionada con el panel enfocado → se borra;
#   · puntos de degradado: punto seleccionado → se quita;
#   · guías: guía activa → se quita.
# Y que NO borran nada mientras se escribe en un campo de texto o numérico.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/delete_keys_matrix_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const KEYS := {"X": KEY_X, "Supr/Delete": KEY_DELETE, "Retroceso": KEY_BACKSPACE}

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func key(code: Key, ctrl := false) -> void:
	for p in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.ctrl_pressed = ctrl
		k.unicode = 0x78 if code == KEY_X and not ctrl else 0
		k.pressed = p
		root.push_input(k)
		await process_frame

func motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func canvas() -> Node:
	return get_first_node_in_group("_vectopen_canvas")

func artboard() -> Node:
	var c = canvas()
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

func api():
	return root.get_node("PluginManager").api

func release_focus() -> void:
	var fo := root.gui_get_focus_owner()
	if fo:
		fo.release_focus()
	await frames(2)

func ctx_canvas(kname: String, code: Key) -> void:
	# Un editor de degradado abierto con un punto seleccionado (el del selector
	# de color) no debe quedarse con las teclas del lienzo.
	var ge: Control = load("res://scenes/ui/gradient.tscn").instantiate()
	ge.position = Vector2(1200, 900)
	ge.size = Vector2(240, 50)
	root.add_child(ge)
	await frames(3)
	var r: Node2D = api().add_rect(Vector2(400, 400), Vector2(120, 90))
	canvas().switch_tool("select")
	api().select(r)
	await release_focus()
	await motion(Vector2(900, 500))
	if OS.has_environment("UX10_DEBUG"):
		print("DBG sel=%s tool=%s focus=%s typing=%s hover=%s" % [root.get_node("SelectionManager").get_selected(), canvas().current_tool.get_script().resource_path.get_file(), root.gui_get_focus_owner(), root.get_node("VectopenInput").is_typing(), root.gui_get_hovered_control()])
	await key(code)
	await frames(4)
	var gone := not is_instance_valid(r) or not r.is_inside_tree()
	check("lienzo: %s borra el objeto seleccionado" % kname, gone)
	if gone:
		await key(KEY_Z, true)
		await frames(4)
		check("lienzo: Ctrl+Z lo recupera tras %s" % kname, is_instance_valid(r) and r.is_inside_tree())
	if is_instance_valid(r):
		r.queue_free()
		await frames(2)
	ge.queue_free()

func ctx_nodes(kname: String, code: Key) -> void:
	var cv := Curve2D.new()
	for p in [Vector2(0, 0), Vector2(100, 40), Vector2(200, 0), Vector2(300, 40)]:
		cv.add_point(p)
	var path: Node2D = api().add_curve(cv, false)
	api().select(path)
	canvas().switch_tool("nodeselection")
	await frames(4)
	var tool = canvas().current_tool
	if "edit_path" in tool:
		tool.edit_path = path
	tool.selected_nodes = [1] as Array[int]
	await release_focus()
	await key(code)
	await frames(4)
	check("nodos: %s quita el nodo seleccionado" % kname, path.curve.point_count == 3, str(path.curve.point_count))
	canvas().switch_tool("select")
	path.queue_free()
	await frames(2)

func ctx_layers(kname: String, code: Key) -> void:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == tr("Capas") and (n as Button).is_visible_in_tree():
			(n as Button).pressed.emit()
	await frames(4)
	var r: Node2D = api().add_rect(Vector2(500, 300), Vector2(80, 60))
	api().select(r)
	await frames(6)
	var tree: Tree = null
	for n in root.find_children("*", "Tree", true, false):
		if n.get_script() and String(n.get_script().resource_path).get_file() == "Layertree.gd" and (n as Control).is_visible_in_tree():
			tree = n
	check("capas: árbol de capas visible", tree != null)
	if tree == null:
		r.queue_free()
		return
	tree.grab_focus()
	await frames(2)
	await key(code)
	await frames(6)
	check("capas: %s borra la capa seleccionada" % kname, not is_instance_valid(r) or not r.is_inside_tree())
	if is_instance_valid(r):
		r.queue_free()
	await release_focus()

func ctx_pages(kname: String, code: Key) -> void:
	var pp: Control = null
	for n in root.find_children("*", "Control", true, false):
		if n.get_script() and String(n.get_script().resource_path).get_file() == "pages_panel.gd":
			pp = n
	if pp == null:
		check("páginas: panel encontrado", false)
		return
	var ab2 = api().add_artboard(Vector2(400, 300), "Página prueba")
	await frames(6)
	pp.call("refresh")
	await frames(4)
	var before: int = pp.call("pages").size()
	pp.set("selected", {ab2: true})
	var grid := pp.get("grid") as Control
	grid.focus_mode = Control.FOCUS_ALL
	grid.grab_focus()
	await frames(2)
	await key(code)
	await frames(8)
	var after: int = pp.call("pages").size()
	check("páginas: %s borra la página seleccionada" % kname, after == before - 1, "%d → %d" % [before, after])
	if is_instance_valid(ab2) and ab2.is_inside_tree():
		ab2.queue_free()
	await release_focus()

func ctx_gradient(kname: String, code: Key) -> void:
	var ge: Control = load("res://scenes/ui/gradient.tscn").instantiate()
	ge.position = Vector2(500, 500)
	ge.size = Vector2(300, 60)
	root.add_child(ge)
	await frames(4)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	ge.call("set_gradient_resource", g)
	await frames(4)
	var n0: int = (ge.get("stops") as Array).size()
	ge.call("_select_stop", (ge.get("stops") as Array)[1])
	await release_focus()
	# Clic real en el punto (así el editor sabe que el usuario está en él).
	var st: Control = (ge.get("stops") as Array)[1]
	var at := st.get_global_rect().get_center()
	await motion(at)
	for pr in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pr
		root.push_input(mb)
		await process_frame
	await frames(2)
	ge.call("_select_stop", (ge.get("stops") as Array)[1])
	await key(code)
	await frames(4)
	var n1: int = (ge.get("stops") as Array).size()
	check("degradado: %s quita el punto seleccionado" % kname, n1 == n0 - 1, "%d → %d" % [n0, n1])
	ge.queue_free()
	await frames(2)

func ctx_guides(kname: String, code: Key) -> void:
	var rg: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).get_file() == "regla.gd":
			rg = n
	if rg == null:
		check("guías: reglas encontradas", false)
		return
	var gh: Array = rg.get("guias_horizontales")
	gh.append(250.0)
	rg.set("indice_guia_activa", gh.size() - 1)
	rg.set("hover_es_horizontal", true)
	var n0 := gh.size()
	await release_focus()
	await key(code)
	await frames(4)
	var n1: int = (rg.get("guias_horizontales") as Array).size()
	check("guías: %s quita la guía activa" % kname, n1 == n0 - 1, "%d → %d" % [n0, n1])

func ctx_typing(kname: String, code: Key) -> void:
	var r: Node2D = api().add_rect(Vector2(420, 420), Vector2(100, 80))
	api().select(r)
	await frames(6)
	var le: LineEdit = null
	for n in root.find_children("*", "LineEdit", true, false):
		if (n as LineEdit).is_visible_in_tree() and (n as LineEdit).editable:
			le = n
			break
	if le:
		le.grab_focus()
		if le.has_method("edit"):
			le.call("edit")
		await frames(2)
		await key(code)
		await frames(4)
	check("escribiendo en un campo: %s no borra el objeto" % kname, is_instance_valid(r) and r.is_inside_tree())
	await release_focus()
	if is_instance_valid(r):
		r.queue_free()
	await frames(2)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
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
	for kname in KEYS:
		var code: Key = KEYS[kname]
		await ctx_canvas(kname, code)
		await ctx_nodes(kname, code)
		await ctx_layers(kname, code)
		await ctx_gradient(kname, code)
		await ctx_guides(kname, code)
		await ctx_typing(kname, code)
	# Páginas: en el panel de Páginas (pestaña de Capas).
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == tr("Páginas") and (n as Button).is_visible_in_tree():
			(n as Button).pressed.emit()
	await frames(6)
	for kname in KEYS:
		await ctx_pages(kname, KEYS[kname])
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
