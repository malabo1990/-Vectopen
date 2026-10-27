## GOOGLE FONTS bajo demanda: el catálogo aparece en la lista, elegir una
## familia la descarga a user://fonts/google/, FontCore la resuelve a sus
## archivos reales (regular / negrita / cursiva) y el texto que la usa se
## refresca solo al terminar. Necesita red.
##   godot --path . -s res://test/e2e/google_fonts_e2e.gd
extends SceneTree

var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)
	else:
		print("ok   ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	var fc = root.get_node("FontCore")
	var fam := "Lobster"
	# empezar sin caché
	var g = fc.get_node("GoogleFonts")
	var d: String = g.dir_for(fam)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + f)
	_check(fc.list_families().has("Playfair Display") and fc.list_families().has(fam), "el catálogo de Google está en la lista")
	_check(fc.google_state(fam) == "remote", "sin descargar: estado remote")

	# Un texto que usa la familia antes de tenerla
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var sm = root.get_node("SelectionManager")
	canvas.switch_tool("text")
	var t: Node2D = canvas.current_tool.create_at_center()
	sm.select(t); ic._sync_selection()
	ic.apply("text", "Hola")
	ic.apply("font_family", fam)
	_check(fc.google_state(fam) == "downloading", "elegirla lanza la descarga")
	var t0 := Time.get_ticks_msec()
	while fc.google_state(fam) != "cached" and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	_check(fc.google_state(fam) == "cached", "descargada en %d ms" % (Time.get_ticks_msec() - t0))
	await _frames(5)
	var f: Font = fc.get_font(fc.make_spec(fam))
	_check(f is FontFile and (f as FontFile).get_font_name() == fam, "FontCore la resuelve al archivo real (%s)" % (f.get_font_name() if f else "null"))
	var dl = t.get_node("DisplayLabel")
	var used: Font = dl.get_theme_font("font")
	var base: Font = used.base_font if used is FontVariation else used
	_check(base == f, "el texto se refrescó solo con la fuente descargada")
	var bytes: PackedByteArray = fc.font_bytes(fc.make_spec(fam))
	_check(bytes.size() > 10000, "bytes para text-to-shape (%d)" % bytes.size())
	var fb: Font = fc.get_font(fc.make_spec("Playfair Display", 700, true))
	print("GOOGLE estado Playfair tras pedir 700i: ", fc.google_state("Playfair Display"))
	t0 = Time.get_ticks_msec()
	while fc.google_state("Playfair Display") != "cached" and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	fb = fc.get_font(fc.make_spec("Playfair Display", 700, true))

	_check(fb is FontFile and (fb as FontFile).get_font_weight() == 700 and ((fb as FontFile).get_font_style() & TextServer.FONT_ITALIC) != 0, "Playfair negrita cursiva = cara real 700 italic")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
