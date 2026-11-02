# =============================================================================
# FASE B · ENCARGO 03 — Cartel A1 (modo Smart)
# Foco: formato grande, textos a escala, exportación PDF.
# A1 elegido en el panel de tamaños (clic en la tarjeta), fondo a sangre con
# degradado, titular enorme, subtítulo y datos; el bloque de texto se escala
# sin deformarse; el PDF sale con el tamaño FÍSICO del A1 (594 × 841 mm =
# 1684 × 2384 pt); PNG, rendimiento, guardar/reabrir.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_03_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/03"
const FIXTURE := "res://test/fixtures/proyectos/03-cartel-a1.vtc"
const A1 := Vector2(2245, 3179)

var fails := 0
var api
var CS

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(30)
	api = root.get_node("PluginManager").api
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var cont: Node2D = get_first_node_in_group("_vectopen_canvas").artboards_container
	var ab: Node2D = api.artboard()
	# 1. Formato A1 desde el panel de tamaños (clic en la tarjeta).
	var win: Control = (load("res://scenes/ui/panel_config_windows_element.tscn") as PackedScene).instantiate()
	# Flota encima de la interfaz, como cuando se abre desde su botón.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(win)
	win.position = Vector2(200, 120)
	await frames(6)
	win.target_mode = 2   # solo página
	win.switch_module("papel")
	await frames(4)
	var card := win.find_child("Preset_A1", true, false) as Control
	check("el panel de tamaños ofrece A1", card != null)
	if card:
		var sc := card.get_parent()
		while sc and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(card)
			await frames(3)
		var hit_ok := card.get_global_rect().has_point(card.get_global_rect().get_center())
		await click(card)
		check("se puede pulsar la tarjeta A1", hit_ok)
	check("la página pasa a A1 (2245 × 3179 px)", (ab.artboard_size as Vector2).is_equal_approx(A1), str(ab.artboard_size))
	layer.queue_free()
	# 2. Cartel: fondo a sangre con degradado, titular, subtítulo, datos.
	var bg = api.add_rect(A1 / 2.0, A1, 0.0, "Fondo")
	api.set_props(bg, {"stroke_width": 0.0})
	var ic = root.get_node("InspectorCore")
	root.get_node("SelectionManager").set_selection([bg])
	await frames(4)
	ic.apply("fill_paint", {"type": "linear", "angle": PI / 2.0, "stops": [[0.0, Color(0.95, 0.35, 0.2)], [1.0, Color(0.25, 0.1, 0.45)]]})
	await frames(4)
	check("fondo con degradado", bg.has_gradient_fill())
	var title = api.add_text(Vector2(160, 900), "FESTIVAL", 380, Color.WHITE)
	title.name = "Titular"
	var sub = api.add_text(Vector2(170, 1400), "de diseño y tipografía", 120, Color(1, 1, 1, 0.9))
	sub.name = "Subtitulo"
	var info = api.add_text(Vector2(170, 2800), "12 — 14 de marzo · Madrid", 90, Color.WHITE)
	info.name = "Datos"
	var block = api.group([title, sub, info], "Bloque texto")
	await frames(10)
	# 3. Escalar el bloque al 80 % sin deformar el texto (escala uniforme).
	var w0: float = title.get_meta("width", 0.0)
	block.scale = Vector2(0.8, 0.8)
	await frames(6)
	var gs: Vector2 = title.get_global_transform().get_scale()
	check("el texto se escala sin deformarse (escala uniforme)", is_equal_approx(gs.x, gs.y) and absf(gs.x - 0.8) < 0.01, str(gs))
	check("el titular conserva su tamaño de letra (lo escala el grupo)", int(title.get_meta("font_size", 0)) == 380 and is_equal_approx(float(title.get_meta("width", 0.0)), w0))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("01_cartel.png"))
	# 4. Exportar PDF con el tamaño físico del A1 y PNG.
	var pdf := ProjectSettings.globalize_path(OUT.path_join("cartel.pdf"))
	var t0 := Time.get_ticks_msec()
	var ok: bool = await api.export(pdf, ab)
	var pdf_ms := Time.get_ticks_msec() - t0
	check("exportar PDF", ok and FileAccess.file_exists(pdf))
	var txt := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii()
	var re := RegEx.new()
	re.compile("/MediaBox \\[0 0 ([0-9.]+) ([0-9.]+)\\]")
	var m := re.search(txt)
	var mb := Vector2(float(m.get_string(1)), float(m.get_string(2))) if m else Vector2.ZERO
	# A1 = 594 × 841 mm = 1683.8 × 2383.9 pt
	check("el PDF tiene el tamaño físico del A1 (1684 × 2384 pt)", absf(mb.x - 1683.8) < 2.0 and absf(mb.y - 2383.9) < 2.0, str(mb))
	check("exportar el PDF del cartel en < 5 s", pdf_ms < 5000, "%d ms" % pdf_ms)
	var png := ProjectSettings.globalize_path(OUT.path_join("cartel.png"))
	t0 = Time.get_ticks_msec()
	ok = await api.export(png, ab)
	var png_ms := Time.get_ticks_msec() - t0
	var img := Image.load_from_file(png)
	check("exportar PNG del A1 a tamaño real", ok and img != null and img.get_size() == Vector2i(A1), str(img.get_size()) if img else "-")
	check("exportar el PNG del A1 en < 10 s", png_ms < 10000, "%d ms" % png_ms)
	if img:
		var top := img.get_pixel(20, 20)
		var bottom := img.get_pixel(20, img.get_height() - 20)
		check("el degradado va de naranja (arriba) a morado (abajo)", top.r > 0.8 and bottom.b > bottom.g and bottom.r < 0.4, "%s / %s" % [top, bottom])
	# 5. Guardar y reabrir.
	var path := ProjectSettings.globalize_path(FIXTURE)
	check("guardar .vtc", CS.write_vtc(path, cont))
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			cont.remove_child(p)
			p.free()
	CS.rebuild_from_vtc(cont, path)
	await frames(10)
	var ab2: Node2D = null
	for p in cont.get_children():
		if p.is_in_group("artboards"):
			ab2 = p
			if p.get("is_dormant"):
				await p.wake()
	await frames(20)
	check("reabrir: A1", ab2 != null and (ab2.artboard_size as Vector2).is_equal_approx(A1))
	var t2 = ab2.find_child("Titular", true, false) if ab2 else null
	check("reabrir: titular a 380 px y bloque al 80 %", t2 != null and int(t2.get_meta("font_size", 0)) == 380 and (t2.get_parent() as Node2D).scale.is_equal_approx(Vector2(0.8, 0.8)))
	var bg2 = ab2.find_child("Fondo", true, false) if ab2 else null
	check("reabrir: el fondo conserva el degradado", bg2 != null and bg2.has_gradient_fill())
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
