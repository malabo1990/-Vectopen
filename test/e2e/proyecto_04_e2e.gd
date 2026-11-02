# =============================================================================
# FASE B · ENCARGO 04 — Flyer para redes 1080 × 1350 (modo Modern)
# Foco: composición rápida, exportar PNG.
# Formato elegido con clic en la tarjeta «Instagram Post Retrato»; fondo de
# color, foto con máscara circular, titular, botón (rectángulo redondeado con
# sombra) con su texto centrado; deshacer 20 pasos; Ctrl+Z; PNG idéntico a lo
# esperado (fondo, máscara, botón); guardar/reabrir; tema oscuro.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_04_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/04"
const FIXTURE := "res://test/fixtures/proyectos/04-flyer-redes.vtc"
const SIZE := Vector2(1080, 1350)
const BG := Color(0.07, 0.11, 0.2)
const ACCENT := Color(1.0, 0.78, 0.2)

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

func key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.ctrl_pressed = ctrl
		k.pressed = pressed
		Input.parse_input_event(k)
		await process_frame
	await frames(4)

func near(a: Color, b: Color, tol := 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol

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
	# 1. Formato desde el panel de tamaños: Redes sociales → Instagram retrato.
	var win: Control = (load("res://scenes/ui/panel_config_windows_element.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(win)
	win.position = Vector2(200, 120)
	await frames(6)
	win.target_mode = 2
	win.switch_module("red_social")
	await frames(4)
	var card := win.find_child("Preset_Instagram Post Retrato", true, false) as Control
	check("el panel ofrece «Instagram Post Retrato» (1080 × 1350)", card != null)
	if card:
		var sc := card.get_parent()
		while sc and not (sc is ScrollContainer):
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(card)
			await frames(3)
		await click(card)
	check("la página pasa a 1080 × 1350", (ab.artboard_size as Vector2).is_equal_approx(SIZE), str(ab.artboard_size))
	layer.queue_free()
	ab.fill_color = BG
	# 2. Composición: foto con máscara circular.
	var img := Image.create(600, 600, false, Image.FORMAT_RGB8)
	for y in 600:
		for x in 600:
			img.set_pixel(x, y, Color(0.9, 0.2 + 0.5 * x / 600.0, 0.3 + 0.4 * y / 600.0))
	var img_path := ProjectSettings.globalize_path(OUT.path_join("foto.png"))
	img.save_png(img_path)
	var circle = api.add_ellipse(Vector2(540, 520), Vector2(560, 560), "Marco foto")
	api.set_props(circle, {"stroke_width": 0.0, "fill_color": Color.WHITE})
	var photo = api.add_image(img_path, Vector2(540, 520), "Foto")
	check("se añade la foto", photo != null)
	var ls: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "LayerSystem":
			ls = n
			break
	if photo and circle and ls:
		var gp: Vector2 = photo.global_position
		photo.get_parent().remove_child(photo)
		circle.add_child(photo)
		photo.global_position = gp
		ls._set_clip(null, circle, ls._modo_clip(circle))
		await frames(4)
	check("la foto queda recortada por el círculo (máscara)", circle and circle.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED and photo.get_parent() == circle)
	# 3. Titular y botón con sombra.
	var title = api.add_text(Vector2(90, 860), "NUEVA COLECCIÓN", 86, Color.WHITE)
	title.name = "Titular"
	var btn = api.add_rect(Vector2(540, 1150), Vector2(520, 120), 60.0, "Boton")
	api.set_props(btn, {"stroke_width": 0.0, "fill_color": ACCENT})
	api.add_effect(btn, "Drop Shadow", {"distance": 12.0})
	var fx = api.get_prop(btn, "effects")
	check("el botón lleva sombra", fx is Array and fx.size() == 1 and String(fx[0].get("type", "")) == "Drop Shadow")
	var cta = api.add_text(Vector2(300, 1120), "Compra ya", 48, BG)
	cta.name = "CTA"
	await frames(6)
	# Centrar el texto del botón respecto al botón (botón como referencia: se alinea el texto a él).
	api.align([title], "center_h")
	api.select([btn, cta])
	await frames(2)
	var ic = root.get_node("InspectorCore")
	var mt = ic._mt
	var rb: Rect2 = mt._global_rect(btn)
	api.align([btn, cta], ["center_h", "middle"])
	await frames(4)
	var rc: Rect2 = mt._global_rect(cta)
	rb = mt._global_rect(btn)
	check("el texto del botón queda centrado en el botón", rc.get_center().distance_to(rb.get_center()) < 2.0, "%s vs %s" % [rc.get_center(), rb.get_center()])
	# 4. Deshacer 20 pasos.
	var chip = api.add_star(Vector2(940, 140), 70, 8, 0.6, "Sello")
	api.set_props(chip, {"stroke_width": 0.0, "fill_color": ACCENT})
	var p0: Vector2 = api.get_position(chip)
	for i in 20:
		api.set_position(chip, p0 + Vector2(-i * 3.0, i * 2.0))
	var p20: Vector2 = api.get_position(chip)
	for i in 20:
		api.undo()
	await frames(4)
	check("deshacer 20 pasos vuelve al punto de partida", api.get_position(chip).distance_to(p0) < 0.5, str(api.get_position(chip)))
	for i in 20:
		api.redo()
	await frames(4)
	check("rehacer 20 pasos", api.get_position(chip).distance_to(p20) < 0.5)
	# 5. Atajo Ctrl+Z sobre el lienzo.
	api.set_position(chip, p0)
	await frames(2)
	await key(KEY_Z, true)
	check("Ctrl+Z deshace el último cambio", api.get_position(chip).distance_to(p20) < 0.5, str(api.get_position(chip)))
	api.clear_selection()
	await frames(10)
	await shot("01_flyer")
	# 6. Exportar PNG y comprobar píxeles clave.
	var png := ProjectSettings.globalize_path(OUT.path_join("flyer.png"))
	var t0 := Time.get_ticks_msec()
	var ok: bool = await api.export(png, ab)
	var ms := Time.get_ticks_msec() - t0
	var out := Image.load_from_file(png) if ok else null
	check("exportar PNG a 1080 × 1350", out != null and out.get_size() == Vector2i(SIZE), str(out.get_size()) if out else "-")
	check("exportar PNG en < 3 s", ms < 3000, "%d ms" % ms)
	if out:
		check("PNG: fondo del color de la página", near(out.get_pixel(10, 10), BG), str(out.get_pixel(10, 10)))
		# Esquina del cuadrado de la foto, fuera del círculo: fondo, no foto.
		var corner := out.get_pixel(540 - 270, 520 - 270)
		check("PNG: la máscara circular recorta la foto", near(corner, BG), str(corner))
		var inside := out.get_pixel(540, 520)
		check("PNG: la foto se ve dentro del círculo", inside.r > 0.8 and inside.b > 0.4, str(inside))
		var bpx := out.get_pixel(540 - 200, 1150)
		check("PNG: el botón sale de su color", near(bpx, ACCENT), str(bpx))
	var svg := ProjectSettings.globalize_path(OUT.path_join("flyer.svg"))
	ok = await api.export(svg, ab)
	var svg_txt := FileAccess.get_file_as_string(svg) if ok else ""
	check("exportar SVG con la máscara (clipPath)", svg_txt.contains("clipPath") and svg_txt.contains("Compra ya"))
	# 7. Guardar y reabrir.
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
	check("reabrir: 1080 × 1350 y color de fondo", ab2 != null and (ab2.artboard_size as Vector2).is_equal_approx(SIZE) and (ab2.fill_color as Color).is_equal_approx(BG))
	var c2 = ab2.find_child("Marco foto", true, false) if ab2 else null
	check("reabrir: la máscara se conserva", c2 != null and c2.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED and c2.find_child("Foto", true, false) != null)
	var b2 = ab2.find_child("Boton", true, false) if ab2 else null
	var fx2 = api.get_prop(b2, "effects") if b2 else null
	check("reabrir: el botón conserva la sombra", fx2 is Array and fx2.size() == 1)
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
