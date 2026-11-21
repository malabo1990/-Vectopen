## E2E: defectos leves acumulados del §2 de PENDIENTE (VAL-05, 10, 13, 17, 18).
extends SceneTree

var fails := 0

func _initialize() -> void:
	create_timer(200).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func check(msg: String, cond: bool, extra: String = "") -> void:
	print(("PASS " if cond else "FAIL ") + msg + ("" if extra == "" else "  [" + extra + "]"))
	if not cond:
		fails += 1

func _run() -> void:
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var api = root.get_node("PluginManager").api
	var ui = root.get_node("GlobalUI")
	var canvas = get_first_node_in_group("_vectopen_canvas")
	ui.set_ui_mode("smart")
	await frames(40)
	var ab: Node2D = api.artboard()

	# ── VAL-05: el rótulo de la página dice su nombre ─────────────────────────
	ab.name = "Portada"
	await frames(3)
	var lbl := ab.get_node_or_null("ArtboardTitle") as Label
	check("VAL-05: el rótulo sigue el nombre de la página", lbl != null and lbl.text.contains("Portada"), lbl.text if lbl else "-")

	# ── VAL-13: cambiar a A1 reencuadra la vista ──────────────────────────────
	canvas.zoom_percentage = 400.0
	await frames(3)
	var win: Control = (load("res://scenes/ui/panel_config_windows_element.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(win)
	await frames(4)
	win.target_mode = 2
	win.apply_preset(2245, 3179, "A1")
	await frames(4)
	var vp: Vector2 = canvas.get_viewport_rect().size
	var cam: Camera2D = canvas.camera
	var view := Rect2(cam.position - vp / (2.0 * cam.zoom.x), vp / cam.zoom.x)
	var page := Rect2(ab.global_position, ab.artboard_size)
	check("VAL-13: la página A1 cabe entera en la vista", view.encloses(page), "vista %s página %s" % [view, page])
	check("VAL-13: y ocupa buena parte (no diminuta)", page.size.y >= view.size.y * 0.7, "%.0f / %.0f" % [page.size.y, view.size.y])
	layer.queue_free()

	# ── VAL-17 / VAL-18: elipse en Smart → «Forma de la figura…» ──────────────
	var el = api.add_ellipse(Vector2(400, 400), Vector2(300, 300), "Círculo")
	api.select([el])
	await frames(8)
	var host: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("smart_menu_extras.gd"):
			host = n.get_parent()
	check("VAL-17: menú contextual de Smart encontrado", host != null)
	if host:
		host.visible = true
		await frames(3)
		var b := host.find_child("EditShape", true, false) as Control
		check("VAL-17: el menú ofrece «Forma de la figura…» con una elipse", b != null and b.visible)
		host.visible = false
		ContextMenuActions.execute("edit_shape", host)
		await frames(8)
	var panel: Control = null
	for n in root.find_children("polygon", "", true, false):
		if n.has_method("set_kind") and (n as Control).is_visible_in_tree():
			panel = n
	check("VAL-17: se abre el panel Figuras con la forma de la elipse", panel != null and panel._fields.has("shape_mode"))
	if panel:
		var t: String = panel._title.text
		check("VAL-18: título acorde a la elipse", t.contains("ELIPSE") and not t.contains("POLÍGONOS"), t)

	# ── VAL-10: marco de varias columnas, editar y deshacer = mismo alto ───────
	api.clear_selection()
	var fr = api.add_text_box(Rect2(80, 600, 500, 200), "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ".repeat(6), 14, Color.BLACK, 2, 20.0)
	await frames(12)
	var h0 := float(api.get_prop(fr, "height"))
	api.set_prop(fr, "text", String(api.get_prop(fr, "text")) + " Más texto añadido al final.")
	await frames(8)
	api.undo()
	await frames(12)
	var h1 := float(api.get_prop(fr, "height"))
	check("VAL-10: editar y deshacer un marco de 2 columnas conserva el alto", absf(h1 - h0) < 1.0, "%.1f → %.1f" % [h0, h1])

	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
