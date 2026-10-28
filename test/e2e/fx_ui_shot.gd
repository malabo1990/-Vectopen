## Capturas del panel Efectos y de la pestaña Filters (revisión de diseño).
##   godot --path . -s res://test/e2e/fx_ui_shot.gd   (E2E_OUT=carpeta, FX_THEME=light|dark)
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _find_script_node(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find_script_node(c, suffix)
		if r:
			return r
	return null

func _shot(win: Control, path: String) -> void:
	await _frames(8)
	var img := root.get_texture().get_image()
	var r := Rect2i(win.get_global_rect().grow(16)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(path)

func _run() -> void:
	var out := OS.get_environment("E2E_OUT")
	if out == "": out = "user://fx_ui"
	DirAccess.make_dir_recursive_absolute(out)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	var th := OS.get_environment("FX_THEME")
	root.get_node("ThemeManager").set_mode(th if th != "" else "light")
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var sm = root.get_node("SelectionManager")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var rect = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.size = Vector2(160, 110)
	rect.fill_color = Color(0.2, 0.5, 0.9)
	ab.add_child(rect)
	rect.position = Vector2(200, 200)
	await _frames(3)
	var fx_panel = _find_script_node(root, "panels/effects/effects.gd")
	await _frames(2)
	var content: Node = fx_panel.get_parent()
	var win: Control = content.owner
	var anc: Node = win
	while anc is CanvasItem:
		(anc as CanvasItem).visible = true
		anc = anc.get_parent()
	var header: Node = content.get_parent().get_node("MarginContainer/HBoxContainer")
	sm.select(rect); ic._sync_selection()
	await _frames(2)
	(header.get_node("ButtonEffects") as Button).pressed.emit()
	fx_panel._sync_from_inspector()
	for e in (OS.get_environment("FX_LIST") if OS.get_environment("FX_LIST") != "" else "Drop Shadow,Outline,Blur,3D").split(","):
		fx_panel._add_new_effect(e)
		await _frames(2)
	fx_panel._sync_from_inspector()
	await _shot(win, out + "/ui_effects.png")
	var sc := fx_panel._effects_list.get_parent() as ScrollContainer
	if sc:
		await _frames(3)
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		await _shot(win, out + "/ui_effects_bottom.png")
		# plegar todas las tarjetas
		for card in fx_panel._effects_list.get_children():
			var chev = card.find_child("Collapse", true, false)
			if chev: chev.pressed.emit()
		sc.scroll_vertical = 0
		await _shot(win, out + "/ui_effects_folded.png")
		for card in fx_panel._effects_list.get_children():
			var chev = card.find_child("Collapse", true, false)
			if chev: chev.pressed.emit()
	sm.set_selection([]); ic._sync_selection()
	await _shot(win, out + "/ui_effects_empty.png")
	sm.select(rect); ic._sync_selection()
	(header.get_node("ButtonFilters") as Button).pressed.emit()
	var fp = content.get_node("Filters")
	fp.sync_from_selection()
	for f in ["glass", "duotone", "neon"]:
		fp.add_filter(f)
		await _frames(2)
	await _shot(win, out + "/ui_filters.png")
	sm.set_selection([]); ic._sync_selection()
	await _shot(win, out + "/ui_filters_empty.png")
	print("E2E RESULT: PASS")
	quit(0)
