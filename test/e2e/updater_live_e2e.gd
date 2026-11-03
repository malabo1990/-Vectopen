# =============================================================================
# Actualizaciones EN VIVO contra GitHub (necesita red y una release publicada).
# Simula tener instalada una versión vieja (UPD_FAKE_VERSION, por defecto
# 0.2.0), pulsa «Buscar actualizaciones» en la ventana del logo, comprueba que
# aparece la release nueva con paquetes para los 3 sistemas y DESCARGA el de
# Linux (.rpm) a user://updates/ — sin instalarlo. Deja la ruta en
# user://updates/last_download.txt para comprobarlo con `rpm -qp`.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/updater_live_e2e.gd
# =============================================================================
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

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
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	var real := String(ProjectSettings.get_setting("application/config/version"))
	var fake := OS.get_environment("UPD_FAKE_VERSION") if OS.has_environment("UPD_FAKE_VERSION") else "0.2.0"
	ProjectSettings.set_setting("application/config/version", fake)   # desde el arranque
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	var up = root.get_node("Updater")
	var logo: Control = null
	for n in root.find_children("Logo", "Control", true, false):
		if n.get_node_or_null("Panel") and (n as Control).is_visible_in_tree():
			logo = n
	check("logo de Vectopen a la vista", logo != null)
	if logo == null:
		print("RESULT: 1 FAIL")
		quit(1)
		return
	await click(logo.get_node("Button"))
	var panel: Control = logo.get_node("Panel")
	var btn := panel.find_child("CheckUpdates", true, false) as Button
	check("botón «Buscar actualizaciones» visible", btn != null and btn.is_visible_in_tree())
	await click(btn)
	var info: Dictionary = {}
	var got := [false]
	up.check_finished.connect(func(i: Dictionary) -> void:
		info.merge(i)
		got[0] = true, CONNECT_ONE_SHOT)
	for _w in 600:
		if got[0]:
			break
		await process_frame
	await frames(4)
	print("INFO GitHub: %s" % info.get("tag", "(nada)"))
	check("GitHub responde con una versión más nueva que %s" % fake, not info.is_empty() and up.compare_versions(info.get("version", ""), fake) > 0, str(info.get("version", "-")))
	var names: Array = (info.get("assets", []) as Array).map(func(a): return String(a["name"]))
	print("INFO paquetes: %s" % ", ".join(names))
	for kind in ["rpm", "deb", "windows", "macos", "tar"]:
		check("la release trae paquete para «%s»" % kind, not up.asset_for(info.get("assets", []), kind).is_empty())
	var status := panel.find_child("UpdateStatus", true, false) as Label
	check("la ventana dice que hay versión nueva", status != null and status.text.contains(String(info.get("version", "?"))), status.text if status else "-")
	var inst := panel.find_child("InstallUpdate", true, false) as Button
	check("aparece «Descargar e instalar»", inst != null and inst.is_visible_in_tree())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://about"))
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://about/live_dark.png")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	check("punto rojo en el logo", logo.find_child("UpdateBadge", true, false) != null and (logo.find_child("UpdateBadge", true, false) as Control).visible)
	# Descargar el .rpm (sin instalar).
	var rpm: Dictionary = up.asset_for(info.get("assets", []), "rpm")
	if not rpm.is_empty():
		var path := [""]
		var done := [false]
		var progress := [0]
		up.download_progress.connect(func(d: int, _t: int) -> void: progress[0] = maxi(progress[0], d))
		up.download_finished.connect(func(p: String) -> void:
			path[0] = p
			done[0] = true, CONNECT_ONE_SHOT)
		up.download(rpm)
		for _w in 12000:
			if done[0]:
				break
			await process_frame
		var sz := FileAccess.get_file_as_bytes(path[0]).size() if path[0] != "" else 0
		check("descarga del .rpm completa (%.1f MB)" % (sz / 1048576.0), path[0] != "" and sz == int(rpm["size"]), "%d de %d bytes" % [sz, int(rpm["size"])])
		check("la barra de progreso avanzó", progress[0] > 0)
		var f := FileAccess.open("user://updates/last_download.txt", FileAccess.WRITE)
		if f:
			f.store_string(path[0])
	ProjectSettings.set_setting("application/config/version", real)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
