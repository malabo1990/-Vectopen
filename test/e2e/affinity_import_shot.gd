## Importa archivos de Affinity en la app real y hace una captura de cada uno.
##   AFF_FILES="a.afdesign|b.af" E2E_OUT=carpeta godot --path . --screen 1 -s res://test/e2e/affinity_import_shot.gd
extends SceneTree

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): printerr("WATCHDOG"); quit(2))
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var out := OS.get_environment("E2E_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_current_screen(mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var iem = root.get_node("ImportExportManager")
	var api = root.get_node("PluginManager").api
	var k := 0
	for p in OS.get_environment("AFF_FILES").split("|", false):
		k += 1
		var before: int = api.artboards().size()
		var t := Time.get_ticks_msec()
		var r: Dictionary = iem.import_any(p, api.artboard())
		printerr("IMPORT %s ok=%s ms=%d artboards=%d→%d err=%s" % [p.get_file(), r.get("ok"), Time.get_ticks_msec() - t, before, api.artboards().size(), r.get("error", "")])
		await _frames(10)
		# Encuadrar los artboards nuevos (o el activo).
		var abs: Array = api.artboards().slice(before) if api.artboards().size() > before else [api.artboard()]
		var rect := Rect2()
		for i in abs.size():
			var a: Node2D = abs[i]
			var ra := Rect2(a.global_position, a.artboard_size)
			rect = ra if i == 0 else rect.merge(ra)
		var vs: Vector2 = canvas.get_viewport_rect().size
		var z := minf(vs.x / rect.size.x, vs.y / rect.size.y) * 0.8
		canvas.camera.zoom = Vector2(z, z)
		canvas.camera.position = rect.get_center()
		canvas.mark_region_dirty(Rect2(Vector2.ZERO, vs))
		await _frames(20)
		root.get_texture().get_image().save_png("%s/%02d.png" % [out, k])
	quit(0)
