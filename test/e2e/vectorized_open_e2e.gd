## VAL-66: abrir una foto vectorizada grande (la del encargo 30: ~1 650
## trazados, ~75 000 nodos) y medir el PRIMER fotograma (teselar todos los
## rellenos). Antes 25 s, luego 13 s; objetivo < 5 s.
##   test/run_e2e.sh proyecto_30_e2e   (crea user://proyectos/30/foto.vtc)
##   test/run_e2e.sh vectorized_open_e2e
##   E2E_ENV="VECTOPEN_GEOM=gdscript" … para comparar sin la librería nativa
extends SceneTree

func _initialize() -> void:
	create_timer(300).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	for i in 30:
		await process_frame
	var path := OS.get_environment("LOAD_FILE") if OS.has_environment("LOAD_FILE") else ProjectSettings.globalize_path("user://proyectos/30/foto.vtc")
	if not FileAccess.file_exists(path):
		print("FAIL falta %s (ejecuta antes proyecto_30_e2e)" % path)
		print("RESULT: 1 FAIL")
		quit(1)
		return
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	var api = root.get_node("PluginManager").api
	var cont: Node = api.artboard().get_parent()
	var t0 := Time.get_ticks_msec()
	CS.rebuild_from_vtc(cont, path)
	for ab in cont.get_children():
		if ab.has_method("wake_now"):
			ab.wake_now()
	var t_load := Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	await process_frame
	await RenderingServer.frame_post_draw
	var t_first := Time.get_ticks_msec() - t1
	var t2 := Time.get_ticks_msec()
	for i in 10:
		await process_frame
	var t_ten := Time.get_ticks_msec() - t2
	var shot := OS.get_environment("SHOT_PATH")
	if shot != "":
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(shot))
	var n := 0
	for c in cont.find_children("*", "", true, false):
		if c is VectorPath:
			n += 1
	print("BENCH abrir_ms=%d" % t_load)
	print("BENCH primer_fotograma_ms=%d" % t_first)
	print("BENCH diez_fotogramas_ms=%d" % t_ten)
	print("BENCH trazados=%d nativo=%s" % [n, str(OS.get_environment("VECTOPEN_GEOM") != "gdscript")])
	var fails := 0
	if n < 1000:
		print("FAIL pocos trazados (%d)" % n); fails += 1
	else:
		print("PASS el documento tiene sus trazados (%d)" % n)
	if t_first > 5000:
		print("FAIL primer fotograma %d ms (> 5 s)" % t_first); fails += 1
	else:
		print("PASS primer fotograma en %d ms" % t_first)
	if t_ten > 1000:
		print("FAIL 10 fotogramas %d ms (caché)" % t_ten); fails += 1
	else:
		print("PASS luego fluido: 10 fotogramas en %d ms" % t_ten)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
