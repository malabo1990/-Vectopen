## E2E (VAL-24): fila «Estilo» de los paneles de texto en Smart, Modern y Pro.
## Crear un estilo con la selección, aplicarlo a otro texto desde la lista,
## redefinirlo (cambian los dos), marca «*» de retoque, deshacer, y que se
## guarde y vuelva al abrir el .vtp.
extends SceneTree

var fails := 0
const TS = preload("res://script_gdscript/text/text_styles.gd")

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func check(msg: String, cond: bool, extra: String = "") -> void:
	print(("PASS " if cond else "FAIL ") + msg + ("" if extra == "" else "  [" + extra + "]"))
	if not cond:
		fails += 1

func _panel_script(mode: String) -> String:
	return {"smart": "rich_text_label_slider_size.gd", "modern": "docked_inspector.gd", "professional": "pro_studio.gd"}[mode]

## Fila «Estilo» del panel del modo (la hace visible si su página está oculta).
func style_row(mode: String) -> Node:
	for r in root.find_children("TextStyleRow", "", true, false):
		# El panel de texto de Smart (rich_text_label_slider_size.gd) también va
		# incrustado en el inspector de Modern y en el estudio de Pro.
		var p := r.get_parent()
		var owner_ok := false
		while p:
			var s = p.get_script()
			if s and String(s.resource_path).get_file() == _panel_script(mode):
				owner_ok = true
				break
			p = p.get_parent()
		if not owner_ok:
			continue
		if mode != "smart" and String(r.get_path()).contains("LegacyHidden"):
			continue
		var was_visible: bool = (r as Control).is_visible_in_tree()
		var hid := ""
		var z: Node = r
		while z and z is CanvasItem:
			if not (z as CanvasItem).visible:
				hid += String(z.name) + " < "
			z = z.get_parent()
		print("INFO %s: fila visible sin forzar = %s  ocultos: %s" % [mode, was_visible, hid])
		if mode != "smart":
			check("%s: la fila se ve sin forzar (texto seleccionado)" % mode, was_visible, hid)
		var q: Node = r
		while q and q is CanvasItem:
			(q as CanvasItem).visible = true
			q = q.get_parent()
		return r
	return null

func pick(row: Node, label_prefix: String) -> bool:
	var opt: OptionButton = row.option
	for i in opt.item_count:
		if opt.get_item_text(i).begins_with(label_prefix):
			opt.select(i)
			opt.item_selected.emit(i)
			return true
	return false

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
	for mode in ["smart", "modern", "professional"]:
		ui.set_ui_mode(mode)
		await frames(40)
		TS.from_data(TS.container(), [])
		var a = api.add_text(Vector2(60, 60), "Título %s" % mode, 44, Color("#c0392b"))
		var b = api.add_text(Vector2(60, 160), "Otro %s" % mode, 16)
		api.set_prop(a, "font_weight", 700)
		api.select([a])
		await frames(8)
		if mode == "professional":
			for n in root.find_children("*", "", true, false):
				if n.get_script() and String(n.get_script().resource_path).ends_with("pro_studio.gd") and n.has_method("_select_tab_b"):
					n._select_tab_b(1)   # pestaña Texto
			await frames(6)
		var row := style_row(mode)
		check("%s: hay fila «Estilo» en el panel de texto" % mode, row != null)
		if row == null:
			continue
		await frames(4)
		if OS.has_environment("TS_SHOT"):
			api.add_text_style("Cuerpo", {"font_size": 14})
			row.refresh()
			await frames(10)
			var img := root.get_texture().get_image()
			var rr: Rect2 = (row as Control).get_global_rect().grow(140)
			img.get_region(Rect2i(rr.intersection(Rect2(Vector2.ZERO, img.get_size())))).save_png(OS.get_environment("HOME") + "/.cache/vectopen_tests/ts_row_%s.png" % mode)
			TS.from_data(TS.container(), [])
			row.refresh()
		# Crear «Título» desde la selección (menú ⋯ → nombre)
		row._dialog_mode = row.M_NEW
		row.submit_name("Título")
		await frames(3)
		var st: Array = api.text_styles()
		check("%s: estilo creado desde la selección" % mode, st.size() == 1 and st[0]["name"] == "Título", str(st))
		check("%s: la lista muestra el estilo elegido" % mode, row.option.get_item_text(row.option.selected) == "Título",
			row.option.get_item_text(row.option.selected))
		# Aplicar a b desde la lista
		api.select([b])
		await frames(6)
		check("%s: b empieza sin estilo" % mode, row.option.selected == 0)
		pick(row, "Título")
		await frames(4)
		check("%s: aplicar desde la lista: tamaño 44 y negrita" % mode,
			is_equal_approx(float(api.get_prop(b, "font_size")), 44.0) and int(api.get_prop(b, "font_weight")) == 700,
			"%s / %s" % [api.get_prop(b, "font_size"), api.get_prop(b, "font_weight")])
		# Retoque local → «*»
		api.set_prop(b, "font_size", 30)
		row.refresh()
		check("%s: retoque local marcado con *" % mode, row.option.get_item_text(row.option.selected).ends_with("*"))
		# Redefinir desde a con tamaño 60: b tenía retoque de tamaño → lo conserva
		api.select([a])
		await frames(4)
		api.set_prop(a, "font_size", 60)
		api.set_prop(a, "fill_color", Color("#1e7d45"))
		row._on_menu(row.M_REDEFINE)
		await frames(4)
		check("%s: redefinir actualiza el color de b" % mode, (api.get_prop(b, "fill_color") as Color).is_equal_approx(Color("#1e7d45")))
		check("%s: redefinir respeta el tamaño retocado de b" % mode, is_equal_approx(float(api.get_prop(b, "font_size")), 30.0))
		api.undo()
		await frames(3)
		check("%s: deshacer la redefinición" % mode, (api.get_prop(b, "fill_color") as Color).is_equal_approx(Color("#c0392b")))
		# Sin estilo → desvincula
		api.select([b])
		await frames(4)
		pick(row, "Sin estilo")
		await frames(3)
		check("%s: «Sin estilo» desvincula" % mode, api.text_style_of(b) == "")
		api.clear_selection()
		api.delete([a, b])
		await frames(6)
	# Guardar y abrir (.vtp)
	TS.from_data(TS.container(), [])
	var t = api.add_text(Vector2(60, 60), "Persistente", 28)
	api.add_text_style("Cuerpo", t, [t])
	var path := OS.get_environment("HOME") + "/.cache/vectopen_tests/text_styles_e2e.vtp"
	var pm = root.get_node("ProjectManager")
	var saved: String = pm.save_project(path) if pm.has_method("save_project") else ""
	check("guardar .vtp", saved != "" or FileAccess.file_exists(path), saved)
	TS.from_data(TS.container(), [])
	var ok: bool = pm.load_project(path)
	await frames(20)
	var names: Array = api.text_styles().map(func(s): return s["name"])
	check("al abrir vuelve el estilo «Cuerpo»", ok and names == ["Cuerpo"], str(names))
	var t2 = api.find("Texto")
	check("y el texto sigue vinculado", t2 != null and api.text_style_of(t2) != "")
	print("RESULT: %s (%d fallos)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
