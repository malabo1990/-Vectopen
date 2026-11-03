# =============================================================================
# Ventana del logo (Acerca de + comunidad + actualizaciones) en los 3 modos.
# Simula una release nueva: punto rojo en el logo y «Descargar e instalar».
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/about_update_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://about"
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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

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
	await frames(6)

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
	var up = root.get_node("Updater")
	for mode in ["smart", "modern", "professional"]:
		root.get_node("GlobalUI").set_ui_mode(mode)
		await frames(30)
		var logo: Control = null
		var panel: Control = null
		if mode == "smart":
			for n in root.find_children("Logo", "Control", true, false):
				if n.get_node_or_null("Panel") and (n as Control).is_visible_in_tree():
					logo = n
		else:
			for n in root.find_children("BrandLogo", "Control", true, false):
				if (n as Control).is_visible_in_tree():
					logo = n
		check("%s: el logo de Vectopen está a la vista" % mode, logo != null)
		if logo == null:
			continue
		if mode == "smart":
			panel = logo.get_node("Panel")
			await click(logo.get_node("Button"))
		else:
			await click(logo)
			panel = root.find_child("AboutPanel", true, false)
		await frames(4)
		check("%s: clic en el logo abre la ventana" % mode, panel != null and panel.is_visible_in_tree())
		if panel == null:
			continue
		check("%s: muestra la versión real (%s)" % [mode, ProjectSettings.get_setting("application/config/version")],
			(panel.find_child("Version", true, false) as Label).text.contains(String(ProjectSettings.get_setting("application/config/version"))))
		check("%s: GitHub, Telegram, Reddit y X; sin Facebook" % mode, panel.find_child("Social_reddit", true, false) != null
			and panel.find_child("Social_github", true, false) != null and panel.find_child("Social_telegram", true, false) != null
			and panel.find_child("Social_x", true, false) != null
			and str(panel.find_children("*", "", true, false)).to_lower().find("facebook") < 0)
		var r := panel.get_global_rect()
		var vp := root.get_visible_rect()
		check("%s: la ventana cabe en pantalla" % mode, vp.encloses(r), "%s en %s" % [r, vp])
		if mode == "smart":
			await shot("01_smart")
			# Simular una release nueva en GitHub.
			up.latest = {"version": "9.9.9", "tag": "v9.9.9", "page": "https://github.com", "assets": []}
			up.update_available.emit(up.latest)
			await frames(6)
			check("aviso: botón «Descargar e instalar»", (panel.find_child("InstallUpdate", true, false) as Control).visible)
			check("aviso: punto rojo sobre el logo", logo.find_child("UpdateBadge", true, false) != null and (logo.find_child("UpdateBadge", true, false) as Control).visible)
			await shot("02_actualizacion")
			root.get_node("ThemeManager").set_mode("dark")
			await frames(20)
			await shot("03_oscuro")
			root.get_node("ThemeManager").set_mode("light")
			await frames(6)
		else:
			await shot("01_" + mode)
		if mode != "smart":
			check("%s: el punto de aviso también está en este logo" % mode, logo.find_child("UpdateBadge", true, false) != null and (logo.find_child("UpdateBadge", true, false) as Control).visible)
		await click(logo.get_node("Button") if mode == "smart" else logo)
		check("%s: otro clic cierra la ventana" % mode, not panel.is_visible_in_tree())
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
