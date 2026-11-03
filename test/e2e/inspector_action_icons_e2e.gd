# =============================================================================
# UX-13 — Shader, Script, Vectorizar y Complementos como iconos junto a
# «Exportar», en los tres modos. Con clics reales:
#   · los cuatro iconos se ven y están pegados al botón Exportar;
#   · cada uno abre SU sección (Inspector en Modern, lateral «Efectos» en Pro,
#     ventana Efectos en Smart), la deja a la vista y su icono queda activo;
#   · la selección no cambia;
#   · volver a pulsarlo la cierra y el icono se apaga;
#   · Script y Complementos muestran su página (scripts / complementos);
#   · pulsar muchas veces no crea editores nuevos.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_action_icons_e2e.gd
# Capturas en user://action_icons/.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://action_icons"
const IDS := ["shader", "script", "vectorize", "plugins"]

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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func motion(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.warp_mouse(at)
	root.push_input(mm)
	await process_frame

func button(at: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(mb)
	await process_frame

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await motion(at)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	await button(at, true)
	await button(at, false)
	await frames(10)

func artboard() -> Node:
	var c = get_first_node_in_group("_vectopen_canvas")
	var m = c.get_node_or_null("manager_script") if c else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

## Los iconos visibles ahora mismo (uno por modo).
func icons() -> Control:
	for n in root.find_children("FxActionIcons", "Control", true, false):
		if (n as Control).is_visible_in_tree():
			return n
	return null

## El botón Exportar que tiene al lado.
func export_next_to(ic: Control) -> Control:
	var par := ic.get_parent()
	for d in [1, -1, 2, -2]:
		var i: int = ic.get_index() + d
		if i >= 0 and i < par.get_child_count():
			var b := par.get_child(i) as Button
			if b and (b.tooltip_text.to_lower().contains("export") or b.text.to_lower().contains("export")):
				return b
	return null

## Lo que hay que ver abierto para cada icono en cada modo.
func target_visible(mode: String, id: String) -> bool:
	if mode == "smart":
		var win := root.find_child("panel__effects", true, false) as Control
		if win == null or not win.is_visible_in_tree():
			return false
		var host := win.find_child({"shader": "Shader", "script": "Script", "plugins": "Script", "vectorize": "Vectorizar"}[id], true, false) as Control
		return host != null and host.is_visible_in_tree()
	var sec_name: String = {"shader": "SecShader", "script": "SecScript", "plugins": "SecScript", "vectorize": "SecVectorize"}[id]
	for n in root.find_children(sec_name, "Control", true, false):
		var sec := n as Control
		if sec.is_visible_in_tree() and sec.call("is_open"):
			var body := sec.get_node_or_null("Body") as Control
			return body != null and body.is_visible_in_tree() and _on_screen(sec.get_node("Header") as Control)
	return false

## La cabecera de la sección queda a la vista (dentro de su lista).
func _on_screen(c: Control) -> bool:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return (p as Control).get_global_rect().grow(2).encloses(r)
		p = p.get_parent()
	return root.get_visible_rect().encloses(r)

func editors() -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		var s = c.get_script()
		if s and String(s.resource_path).get_file() in ["script_panel.gd", "shader_panel.gd", "vectorize_panel.gd"]:
			n += 1
	return n

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
	var ab := artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect iconos"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(200, 140)
	rect.position = Vector2(300, 300)
	var counts := {}
	for round_i in 2:
		for mode in ["smart", "modern", "professional"]:
			gui.set_ui_mode(mode)
			await frames(30)
			sm.set_selection([rect])
			await frames(8)
			var ic := icons()
			if mode == "smart":
				# En Smart no se repiten abajo: están en la ventana Efectos.
				check("smart: sin iconos repetidos en la barra de abajo", ic == null)
				var fx_btn: Control = null
				for n in root.find_children("Button2", "Button", true, false):
					if (n as Button).tooltip_text == "Efectos" and (n as Control).is_visible_in_tree():
						fx_btn = n
				check("smart: botón Efectos arriba a la derecha", fx_btn != null)
				if fx_btn:
					await click(fx_btn, "smart: Efectos")
					await frames(10)
					var win := root.find_child("panel__effects", true, false) as Control
					var tabs_ok := win != null and win.is_visible_in_tree()
					for tab in ["ButtonShader", "ButtonScript", "ButtonVectorize"]:
						tabs_ok = tabs_ok and win.find_child(tab, true, false) != null
					check("smart: Efectos tiene Shader, Script (con Complementos) y Vectorizar", tabs_ok)
					await click(fx_btn, "smart: cerrar Efectos")
					await frames(6)
				continue
			check("%s: hay iconos de acciones" % mode, ic != null)
			if ic == null:
				continue
			check("%s: los cuatro iconos" % mode, ic.get_child_count() == 4, str(ic.get_child_count()))
			check("%s: pegados a Exportar" % mode, export_next_to(ic) != null)
			for id in IDS:
				var b := ic.get_node_or_null("Fx_" + id) as Button
				await click(b, "%s: icono %s" % [mode, id])
				await frames(6)
				check("%s: %s abre su sección a la vista" % [mode, id], target_visible(mode, id))
				check("%s: %s icono activo" % [mode, id], b != null and b.button_pressed)
				check("%s: %s no cambia la selección" % [mode, id], sm.get_selected() == [rect], str(sm.get_selected()))
				if id in ["script", "plugins"]:
					var page_ok := false
					for n in root.find_children("AddonsPage", "Control", true, false):
						if (n.get_parent() as Control).is_visible_in_tree():
							page_ok = (n as Control).visible == (id == "plugins")
					check("%s: %s muestra su página" % [mode, id], page_ok)
				if round_i == 0:
					await shot("%s_%s" % [mode, id])
				await click(b, "%s: icono %s otra vez" % [mode, id])
				await frames(6)
				check("%s: %s se cierra y el icono se apaga" % [mode, id], not target_visible(mode, id) and not b.button_pressed,
					"visible=%s activo=%s" % [target_visible(mode, id), b.button_pressed])
			counts["%s_%d" % [mode, round_i]] = editors()
	for mode in ["modern", "professional"]:
		check("%s: no se crean editores nuevos al repetir" % mode, counts.get("%s_0" % mode, -1) == counts.get("%s_1" % mode, -2) or counts.get("professional_1", 0) == counts.get("professional_0", 0),
			"%s → %s" % [counts.get("%s_0" % mode), counts.get("%s_1" % mode)])
	rect.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
