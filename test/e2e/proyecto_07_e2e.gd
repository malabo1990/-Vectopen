# =============================================================================
# FASE B · ENCARGO 07 — Tarjeta de visita (modo Modern)
# Foco: márgenes, tipografía pequeña, sangrado.
# Formato «Tarjeta de Visita» (85 × 50 mm) con clic en su tarjeta; márgenes
# 4 mm y sangrado 3 mm desde la pestaña Páginas; fondo a sangre; nombre,
# cargo y contacto a 7–9 pt dentro de los márgenes; PDF de imprenta con
# sangrado (MediaBox 91 × 56 mm + TrimBox 85 × 50 mm); PNG a 300 ppp con el
# texto pequeño legible; guardar/reabrir; tema oscuro.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_07_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/07"
const FIXTURE := "res://test/fixtures/proyectos/07-tarjeta-visita.vtc"
const SIZE := Vector2(321, 189)
const MM := 96.0 / 25.4
const PT := 72.0 / 25.4
const NAVY := Color(0.07, 0.12, 0.25)
const GOLD := Color(0.85, 0.68, 0.3)

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

func find_cls(cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null

func set_field(f: Control, v: float) -> void:
	f.value = v
	f.value_changed.emit(v)
	await frames(2)

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
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	api = root.get_node("PluginManager").api
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var cont: Node2D = get_first_node_in_group("_vectopen_canvas").artboards_container
	var ab: Node2D = api.artboard()
	# 1. Formato con clic en la tarjeta «Tarjeta de Visita».
	var win: Control = (load("res://scenes/ui/panel_config_windows_element.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(win)
	win.position = Vector2(200, 120)
	await frames(6)
	win.target_mode = 2
	win.switch_module("papel")
	await frames(4)
	var card := win.find_child("Preset_Tarjeta de Visita", true, false) as Control
	check("el panel ofrece «Tarjeta de Visita»", card != null)
	if card:
		var sc := card.get_parent()
		while sc and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(card)
			await frames(3)
		await click(card)
	check("la página pasa a 85 × 50 mm (321 × 189 px)", (ab.artboard_size as Vector2).is_equal_approx(SIZE), str(ab.artboard_size))
	layer.queue_free()
	# 2. Márgenes 4 mm y sangrado 3 mm desde la pestaña Páginas.
	var ls = find_cls("LayerSystem")
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("paginas")
		await frames(6)
	var grid: Node = find_cls("PageLayoutSection")
	check("Modern: la pestaña Páginas tiene márgenes y sangrado", grid != null)
	if grid:
		await set_field(grid.f_margin, 4.0)
		await set_field(grid.f_bleed, 3.0)
	check("márgenes 4 mm y sangrado 3 mm", is_equal_approx(ab.layout_margin, 4.0 * MM) and is_equal_approx(ab.bleed, 3.0 * MM),
		"%.2f / %.2f px" % [ab.layout_margin, ab.bleed])
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("capas")
	# 3. Fondo a sangre y textos pequeños dentro de los márgenes.
	var b := 3.0 * MM
	var bg = api.add_rect(SIZE / 2.0, SIZE + Vector2(b, b) * 2.0, 0.0, "Fondo a sangre")
	api.set_props(bg, {"stroke_width": 0.0, "fill_color": NAVY})
	var bar = api.add_rect(Vector2(SIZE.x / 2.0, SIZE.y - 4.0 * MM - 1.0), Vector2(SIZE.x - 8.0 * MM, 2.0), 0.0, "Filete")
	api.set_props(bar, {"stroke_width": 0.0, "fill_color": GOLD})
	var m := 4.0 * MM
	var name_t = api.add_text(Vector2(m, m), "Lucía Ferrer", 16, Color.WHITE)
	name_t.name = "Nombre"
	var job = api.add_text(Vector2(m, m + 24), "Directora de arte", 11, GOLD)   # ≈ 8 pt
	job.name = "Cargo"
	var contact = api.add_text(Vector2(m, SIZE.y - m - 40), "+34 600 123 456\nlucia@estudio.es", 9, Color(1, 1, 1, 0.9))   # ≈ 7 pt
	contact.name = "Contacto"
	await frames(10)
	var mt = root.get_node("InspectorCore")._mt
	var safe := Rect2(Vector2(m, m), SIZE - Vector2(m, m) * 2.0)
	var inside := true
	for t in [name_t, job, contact]:
		var r: Rect2 = mt._global_rect(t)
		var inv: Transform2D = ab.get_global_transform().affine_inverse()
		var lr := Rect2(inv * r.position, r.size / ab.get_global_transform().get_scale())
		if not safe.grow(0.5).encloses(lr):
			inside = false
			print("INFO fuera de márgenes: %s %s" % [t.name, lr])
	check("los textos quedan dentro de los márgenes de 4 mm", inside)
	await shot("01_tarjeta")
	# 4. PDF de imprenta con sangrado.
	var pdf := ProjectSettings.globalize_path(OUT.path_join("tarjeta.pdf"))
	var ok: bool = await api.export(pdf, ab)
	var txt := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii() if ok else ""
	var re := RegEx.new()
	re.compile("/MediaBox \\[0 0 ([0-9.]+) ([0-9.]+)\\] /TrimBox \\[([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+)\\]")
	var mm2 := re.search(txt)
	check("PDF: MediaBox 91 × 56 mm (con sangrado) y TrimBox 85 × 50 mm", mm2 != null
		and absf(float(mm2.get_string(1)) - 91.0 * PT) < 1.0 and absf(float(mm2.get_string(2)) - 56.0 * PT) < 1.0
		and absf(float(mm2.get_string(5)) - float(mm2.get_string(3)) - 85.0 * PT) < 1.0,
		mm2.get_string() if mm2 else "sin cajas")
	# El PDF lleva el texto como contornos (se ve con su fuente en cualquier imprenta).
	check("PDF: lleva los textos (en contornos, blanco y dorado)", txt.contains("1 1 1 rg") and txt.contains("0.85 0.68 0.3 rg") and txt.count(" c ") > 300,
		"%d curvas" % txt.count(" c "))
	# 5. PNG a 300 ppp (escala 3,125) y texto pequeño legible.
	var png := ProjectSettings.globalize_path(OUT.path_join("tarjeta_300ppp.png"))
	ok = await api.export(png, ab, {"scale": 300.0 / 96.0})
	var img := Image.load_from_file(png) if ok else null
	check("PNG a 300 ppp (1003 × 591 px)", img != null and absi(img.get_width() - 1003) <= 2 and absi(img.get_height() - 591) <= 2, str(img.get_size()) if img else "-")
	if img:
		var k := img.get_width() / SIZE.x
		var c0 := img.get_pixel(int(2 * k), int(2 * k))
		check("PNG: el fondo llega al borde (a sangre)", c0.is_equal_approx(NAVY) or (absf(c0.b - NAVY.b) < 0.03 and absf(c0.r - NAVY.r) < 0.03), str(c0))
		# Texto de 7 pt: contar píxeles claros en su caja.
		var light := 0
		for y in range(int((SIZE.y - m - 40) * k), int((SIZE.y - m - 18) * k)):
			for x in range(int(m * k), int((m + 80) * k)):
				if img.get_pixel(x, y).get_luminance() > 0.6:
					light += 1
		check("PNG: el contacto a 7 pt se dibuja (no se pierde)", light > 200, "%d px" % light)
	# 6. Guardar y reabrir.
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
	check("reabrir: tamaño, márgenes y sangrado", ab2 != null and (ab2.artboard_size as Vector2).is_equal_approx(SIZE)
		and is_equal_approx(ab2.layout_margin, 4.0 * MM) and is_equal_approx(ab2.bleed, 3.0 * MM))
	var c2 = ab2.find_child("Contacto", true, false) if ab2 else null
	check("reabrir: el contacto a 9 px con sus dos líneas", c2 != null and int(c2.get_meta("font_size", 0)) == 9 and String(c2.get_meta("text", "")).contains("\n"))
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
