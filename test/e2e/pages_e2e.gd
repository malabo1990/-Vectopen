# =============================================================================
# PRUEBA DE INTERFAZ REAL del panel de PÁGINAS con un documento GRANDE
# (500 páginas):
#   · contador «n de 500», rejilla virtualizada, solo miniaturas visibles;
#   · «Ir a» 250; clic en una miniatura = ir a esa página;
#   · reordenar arrastrando (y la fila del lienzo se recoloca), con deshacer;
#   · duplicar y borrar páginas, con deshacer;
#   · desplazarse por la rejilla sigue fluido.
#   flatpak run --command=godot org.godotengine.Godot --path . \
#       -s res://test/e2e/pages_e2e.gd
# =============================================================================
extends SceneTree

const N := 500
var fails := 0

func _init() -> void:
	_run.call_deferred()

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

func _btn(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e)
	await process_frame

func _mv(at: Vector2, down: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e)
	await process_frame

func _run() -> void:
	Input.use_accumulated_input = false
	# la prueba cambia la pestaña del panel de capas: restaurar la del usuario
	var ui_cfg := "user://vectopen_layers_ui.cfg"
	var ui_backup := FileAccess.get_file_as_string(ui_cfg) if FileAccess.file_exists(ui_cfg) else ""
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await frames(20)
	var api = root.get_node("PluginManager").api
	var hm = root.get_node("HistoryManager")
	var t0 := Time.get_ticks_msec()
	for i in N - 1:
		var ab: Node2D = api.add_artboard(Vector2(794, 1123), "Página")
		if i % 7 == 0:
			var r: Node2D = api.add_rect(Vector2(397, 300 + (i % 5) * 120), Vector2(300, 200))
			api.set_fill(r, Color.from_hsv(float(i % 12) / 12.0, 0.6, 0.9))
	print("creadas %d páginas en %d ms" % [N, Time.get_ticks_msec() - t0])
	await frames(5)
	var ls = current_scene.find_child("LayersSystem", true, false)
	ls._switch_left_tab("paginas")
	await frames(10)
	var panel = current_scene.find_child("PagesPanel", true, false)
	check("panel de páginas visible", panel != null and panel.is_visible_in_tree())
	if panel == null:
		quit(1)
		return
	check("hay %d páginas" % N, panel.pages().size() == N, str(panel.pages().size()))
	# miniaturas: solo las visibles
	await frames(90)
	var vr: Vector2i = panel._visible_range()
	var visible_n := vr.y - vr.x + 1
	check("solo genera las miniaturas visibles", panel._cache.size() > 0 and panel._cache.size() <= visible_n + 4,
		"%d en caché, %d visibles" % [panel._cache.size(), visible_n])

	# Ir a 250
	var goto: LineEdit = panel.find_child("GoTo", true, false)
	goto.text = "250"
	goto.text_submitted.emit("250")
	await frames(4)
	check("«Ir a 250» activa la página 250", panel.pages().find(panel.active()) == 249, str(panel.pages().find(panel.active()) + 1))
	check("contador «250 de 500»", String(panel.find_child("Count", true, false).text) == "250 de %d" % N, panel.find_child("Count", true, false).text)
	var cam: Camera2D = get_first_node_in_group("_vectopen_canvas").get("camera")
	var ab250: Node2D = panel.active()
	check("el lienzo se centra en la página 250", cam.global_position.distance_to(ab250.global_position + ab250.artboard_size * 0.5) < 1.0)

	# Fluido al desplazarse por la rejilla
	var scroll: ScrollContainer = panel._scroll
	var worst := 0.0
	var tprev := Time.get_ticks_usec()
	for i in 60:
		scroll.scroll_vertical += 120
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - tprev) / 1000.0)
		tprev = now
	check("desplazarse por 500 páginas es fluido", worst < 60.0, "peor fotograma %.1f ms" % worst)

	# Clic en la 1.ª miniatura visible
	scroll.scroll_vertical = 0
	await frames(3)
	var grid: Control = panel.grid
	var c0: Vector2 = grid.get_global_transform() * panel._cell_rect(2).get_center()
	await _mv(c0, false)
	await _btn(c0, true)
	await _btn(c0, false)
	await frames(3)
	check("clic en la miniatura 3 = ir a la página 3", panel.pages().find(panel.active()) == 2, str(panel.pages().find(panel.active()) + 1))

	# Reordenar arrastrando: la página 1 detrás de la 3
	hm.clear()
	var p1: Node2D = panel.pages()[0]
	var x_before: float = panel.pages()[0].global_position.x
	var a1: Vector2 = grid.get_global_transform() * panel._cell_rect(0).get_center()
	var a3: Vector2 = grid.get_global_transform() * (panel._cell_rect(2).end - Vector2(2, panel._cell_rect(2).size.y * 0.5))
	await _mv(a1, false)
	await _btn(a1, true)
	for i in 10:
		await _mv(a1.lerp(a3, (i + 1) / 10.0), true)
	await _btn(a3, false)
	await frames(3)
	check("arrastrar la página 1 detrás de la 3", panel.pages().find(p1) == 2, "ahora es la %d" % (panel.pages().find(p1) + 1))
	check("la fila del lienzo se recoloca en el nuevo orden", panel.pages()[0].global_position.x == x_before and p1.global_position.x > panel.pages()[1].global_position.x)
	hm.undo()
	await frames(3)
	check("deshacer reordenar", panel.pages().find(p1) == 0, str(panel.pages().find(p1) + 1))

	# Duplicar y borrar con deshacer
	panel.go_to_page(0)
	await frames(2)
	panel.duplicate_selected()
	await frames(3)
	check("duplicar añade una página", panel.pages().size() == N + 1, str(panel.pages().size()))
	panel.selected = {panel.pages()[1]: true}
	panel.delete_selected()
	await frames(3)
	check("borrar quita la página", panel.pages().size() == N, str(panel.pages().size()))
	hm.undo()
	await frames(3)
	check("deshacer el borrado", panel.pages().size() == N + 1, str(panel.pages().size()))

	if ui_backup != "":
		var f := FileAccess.open(ui_cfg, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit(1 if fails > 0 else 0)
