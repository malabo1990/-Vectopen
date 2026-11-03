# =============================================================================
# Cambiar de tema (menú contextual ▸ Tema) con muchos trazos de pincel y
# mucho zoom no debe congelar la app (lo vio el usuario a 1071 %).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/theme_switch_strokes_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(150.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT (congelado)")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

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
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var styles := ["pen", "pencil", "marker", "airbrush", "calligraphy"]
	for k in 40:
		var l := Line2D.new()
		l.name = "Dibujo %d" % k
		l.width = 12.0 + (k % 4) * 6.0
		l.default_color = Color(0.1, 0.1, 0.1, 0.65 if k % 3 == 0 else 1.0)
		l.set_meta("brush_style", styles[k % styles.size()])
		var pts := PackedVector2Array()
		for i in 300:
			var t := i / 299.0
			pts.append(Vector2(100 + (k % 8) * 80 + t * 200, 100 + (k / 8) * 150 + sin(t * TAU * 2.0) * 40))
		l.points = pts
		ab.add_child(l)
		R.attach(l)
	await frames(10)
	var cam: Camera2D = canvas.camera
	cam.zoom *= 10.0
	await frames(10)
	var tm = root.get_node("ThemeManager")
	# Los botones REALES del menú contextual de Smart (Tema: claro / oscuro…).
	var menu: Node = null
	for n in root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and sc.resource_path.ends_with("clickrigth_nodo.gd"):
			menu = n
			break
	check("menú contextual de Smart", menu != null)
	if menu == null:
		quit(1)
		return
	for tip in ["Oscuro", "Claro", "Oscuro"]:
		menu._build_theme_switcher()
		await frames(2)
		var b: Button = null
		for x in root.find_children("*", "Button", true, false):
			if (x as Button).tooltip_text == tip and x.get_parent() and x.get_parent().get_parent() and String(x.get_parent().get_parent().name) == "ThemeSwitcherContainer":
				b = x
		check("botón de tema «%s» en el menú" % tip, b != null)
		if b == null:
			continue
		var t0 := Time.get_ticks_msec()
		b.pressed.emit()
		await frames(3)
		var dt := Time.get_ticks_msec() - t0
		var want := "dark" if tip == "Oscuro" else "light"
		check("tema «%s» aplicado sin congelarse" % tip, tm.current_mode == want and dt < 3000, "%s, %d ms" % [tm.current_mode, dt])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
