# =============================================================================
# Panel «Teclado y ratón» (Smart, abajo a la izquierda): pestañas, teclado
# simulado con estados, filtro desde una tecla, captura de tecla, que el panel
# quepa en pantalla y que se lea en tema claro y oscuro.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/keyboard_panel_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://keyboard_panel"
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

func shot(name: String, panel: Control) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var r := Rect2i(panel.get_global_rect().grow(12)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(OUT.path_join(name + ".png"))

func contrast(a: Color, b: Color) -> float:
	var la := a.get_luminance() + 0.05
	var lb := b.get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)

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
	var gui = root.get_node("GlobalUI")
	var tm = root.get_node("ThemeManager")
	gui.set_ui_mode("smart")
	await frames(20)
	var panel = root.find_child("Panel_keyboard", true, false)
	check("existe el panel", panel != null)
	if panel == null:
		quit(1)
		return
	var btn := panel.get_parent() as Button
	for theme in ["light", "dark"]:
		tm.set_mode(theme)
		await frames(10)
		if not panel.visible:
			btn.emit_signal("pressed")
			if not panel.visible:
				panel.visible = true
		await frames(12)
		check("[%s] el panel se abre" % theme, panel.is_visible_in_tree())
		var vp: Vector2 = root.get_visible_rect().size
		var r: Rect2 = panel.get_global_rect()
		check("[%s] el panel cabe en pantalla" % theme, r.position.x >= 0 and r.position.y >= 0 and r.end.x <= vp.x and r.end.y <= vp.y, "%s en %s" % [r, vp])
		check("[%s] tamaño útil" % theme, r.size.x >= 760 and r.size.y >= 480, str(r.size))
		# Lista: nombres legibles en español y buen contraste.
		panel.show_tab("list")
		await frames(6)
		var ac: VBoxContainer = panel.action_container
		var names: Array = []
		for row in ac.get_children():
			if row.has_meta("action"):
				names.append((row.get_child(0) as Label).text)
		check("[%s] nombres claros (Agrupar, Restablecer el zoom)" % theme, "Agrupar" in names and "Restablecer el zoom" in names, str(names.slice(0, 6)))
		var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
		var lab := ac.find_children("*", "Label", true, false).filter(func(l): return l.get_parent().has_meta("action"))[0] as Label
		var cr := contrast(lab.get_theme_color("font_color"), sb.bg_color) if sb else 0.0
		check("[%s] texto legible (contraste ≥ 4.5)" % theme, cr >= 4.5, "%.1f" % cr)
		await shot("%s_atajos" % theme, panel)
		# Teclado simulado.
		panel.show_tab("keys")
		panel.set_modifier("ctrl")
		await frames(6)
		check("[%s] Ctrl+G → configurable" % theme, panel.key_state(KEY_G) == "assigned")
		check("[%s] Ctrl+J → libre" % theme, panel.key_state(KEY_J) == "free")
		check("[%s] Ctrl+Y → fijo" % theme, panel.key_state(KEY_Y) == "fixed")
		check("[%s] describe Ctrl+G" % theme, panel.describe(KEY_G, "G").contains("Agrupar"), panel.describe(KEY_G, "G"))
		var kb: Control = panel.find_child("Keyboard", true, false)
		var kr: Rect2 = kb.get_global_rect()
		var keys_out := 0
		for k in kb.get_children():
			if not r.encloses((k as Control).get_global_rect()):
				keys_out += 1
		check("[%s] todas las teclas dentro del panel" % theme, keys_out == 0, "%d fuera; teclado %s" % [keys_out, kr])
		await shot("%s_teclado_ctrl" % theme, panel)
		panel.set_modifier("")
		await frames(4)
		check("[%s] 5 sin modificador → zoom (opacidad solo con selección)" % theme, panel.key_state(KEY_5) == "assigned" and panel.describe(KEY_5, "5").contains("con selección"), panel.describe(KEY_5, "5"))
		await shot("%s_teclado" % theme, panel)
		panel.show_tab("mouse")
		await frames(6)
		await shot("%s_raton" % theme, panel)
	# Clic en una tecla ocupada → filtra en Atajos.
	panel.show_tab("keys")
	panel.set_modifier("ctrl")
	panel.open_key(KEY_G)
	await frames(6)
	var rows: Array = panel.action_container.get_children().filter(func(c): return c.has_meta("action"))
	check("clic en Ctrl+G muestra «Agrupar» en Atajos", panel._tab == "list" and rows.size() >= 1 and String(rows[0].get_meta("action")) == "group", "%d filas" % rows.size())
	panel.filter_line_edit.text = ""
	panel._build_action_list("")
	# Captura: un modificador solo no se asigna; Ctrl+J sí.
	var before: int = InputMap.action_get_events("group").size()
	panel._start_capture("group", -1)
	var ev := InputEventKey.new()
	ev.keycode = KEY_CTRL
	ev.pressed = true
	panel._input(ev)
	check("pulsar solo Ctrl no asigna nada", InputMap.action_get_events("group").size() == before and panel._capture_action == "group")
	ev = InputEventKey.new()
	ev.keycode = KEY_J
	ev.ctrl_pressed = true
	ev.pressed = true
	panel._input(ev)
	check("Ctrl+J se añade a Agrupar", InputMap.action_get_events("group").size() == before + 1)
	check("Ctrl+J ya no está libre", panel.key_state(KEY_J, "ctrl") == "assigned")
	panel._reset_action("group")
	check("restablecer devuelve Agrupar a su tecla", InputMap.action_get_events("group").size() == before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://vectopen_inputmap.cfg"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
