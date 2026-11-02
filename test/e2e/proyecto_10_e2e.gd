# =============================================================================
# FASE B · ENCARGO 10 — UI kit de aplicación (modo Modern)
# Foco: componentes repetidos, estilos de texto.
# Pantalla móvil 390 × 844; botón (rectángulo redondeado + texto) agrupado y
# guardado en Recursos con «+ Selección»; colocado 4 veces desde Recursos
# (copias idénticas); tarjeta repetida con «Duplicar»; jerarquía de texto
# (H1, cuerpo, pie) reutilizada; alinear/distribuir; exportar PNG a 3×;
# guardar/reabrir. Comprueba también si hay componentes vinculados y estilos
# de texto con nombre (VAL-23 / VAL-24).
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_10_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/10"
const FIXTURE := "res://test/fixtures/proyectos/10-ui-kit.vtc"
const SIZE := Vector2(390, 844)
const PRIMARY := Color("#5b4cf2")
const INK := Color("#17151f")

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

func find_cls(cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null

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
	var ic = root.get_node("InspectorCore")
	var cont: Node2D = get_first_node_in_group("_vectopen_canvas").artboards_container
	var ab: Node2D = api.artboard()
	ab.artboard_size = SIZE
	ab.fill_color = Color("#f6f6fb")
	# 1. Jerarquía de texto.
	var h1 = api.add_text(Vector2(24, 64), "Hola, Lucía", 32, INK)
	h1.name = "H1"
	var body = api.add_text(Vector2(24, 112), "Tienes 3 tareas para hoy.", 16, Color("#5c5f70"))
	body.name = "Cuerpo"
	# 2. Botón: rectángulo redondeado + texto centrado, agrupado.
	var bg = api.add_rect(Vector2(195, 0), Vector2(342, 52), 14.0, "Fondo boton")
	api.set_props(bg, {"stroke_width": 0.0, "fill_color": PRIMARY})
	var lbl = api.add_text(Vector2(150, -12), "Continuar", 17, Color.WHITE)
	lbl.name = "Texto boton"
	await frames(4)
	api.align([bg, lbl], ["center_h", "middle"])
	await frames(2)
	var vr = lbl.get_node("VectorRichText")
	var tc: Vector2 = vr.get_global_transform().origin + vr.get_content_size() / 2.0
	var bc: Vector2 = root.get_node("InspectorCore")._mt._global_rect(bg).get_center()
	check("el texto queda centrado en el botón (lo que se ve)", tc.distance_to(bc) < 2.0, "%s vs %s" % [tc, bc])
	var btn = api.group([bg, lbl], "Boton primario")
	await frames(4)
	# 3. Guardarlo en Recursos con «+ Selección».
	var ls = find_cls("LayerSystem")
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("recursos")
		await frames(8)
	var assets: Node = null
	for n in root.find_children("*", "", true, false):
		if n.is_in_group("vectopen_assets_panel") and (n as Control).is_visible_in_tree():
			assets = n
	check("Modern: la pestaña Recursos está disponible", assets != null)
	var copies: Array = []
	if assets:
		api.select([btn])
		await frames(4)
		var it: Dictionary = assets.add_selection("Boton primario")
		check("«+ Selección» guarda el botón en Recursos", not it.is_empty(), str(it.get("name", "")))
		# 4. Colocarlo 4 veces desde Recursos.
		btn.queue_free()
		await frames(2)
		for i in 4:
			var before := ab.get_child_count()
			assets.place_item(it, Vector2(195, 560 + i * 66))   # centro, en coordenadas de la página
			await frames(3)
			if ab.get_child_count() > before:
				copies.append(ab.get_child(ab.get_child_count() - 1))
	check("4 botones colocados desde Recursos", copies.size() == 4, str(copies.size()))
	if copies.size() == 4:
		var same := true
		for c in copies:
			var f = c.find_child("Fondo boton*", true, false)
			var t = c.find_child("Texto boton*", true, false)
			same = same and f != null and t != null and (f.fill_color as Color).is_equal_approx(PRIMARY) and String(t.get_meta("text", "")) == "Continuar"
		check("los 4 botones son idénticos (color, texto)", same)
		api.distribute(copies, "v")
		await frames(3)
		var mt = ic._mt
		var g: Array = []
		for i in range(1, 4):
			g.append(mt._global_rect(copies[i]).position.y - mt._global_rect(copies[i - 1]).end.y)
		check("distribuir los botones en vertical (mismo espacio)", g.all(func(x): return absf(x - g[0]) < 1.0), str(g))
		# Componentes vinculados: cambiar uno NO cambia los demás (son copias).
		var f0 = copies[0].find_child("Fondo boton*", true, false)
		api.set_prop(f0, "fill_color", Color("#e23d6b"))
		await frames(2)
		var f1 = copies[1].find_child("Fondo boton*", true, false)
		var linked := (f1.fill_color as Color).is_equal_approx(Color("#e23d6b"))
		print("INFO VAL-23 componentes vinculados: %s" % ("sí" if linked else "no (copias independientes)"))
		api.set_prop(f0, "fill_color", PRIMARY)
	# 5. Tarjeta repetida con Duplicar (consistencia).
	var card = api.add_rect(Vector2(195, 250), Vector2(342, 120), 18.0, "Tarjeta")
	api.set_props(card, {"stroke_width": 1.0, "stroke_color": Color("#e3e4ee"), "fill_color": Color.WHITE})
	api.add_effect(card, "Drop Shadow", {"distance": 4.0, "blur": 16.0})
	var card2 = api.duplicate(card, Vector2(0, 136))
	check("la tarjeta duplicada conserva sombra y radio", card2 != null and (api.get_prop(card2, "effects") as Array).size() == 1
		and is_equal_approx(float(api.get_prop(card2, "corner_radius")), 18.0))
	# Estilos de texto con nombre.
	var has_styles: bool = api.has_method("text_styles") or ic.has_method("apply_text_style")
	print("INFO VAL-24 estilos de texto con nombre: %s" % ("sí" if has_styles else "no"))
	api.clear_selection()
	await frames(10)
	await shot("01_ui_kit")
	# 6. Exportar a 3× (pantalla de móvil @3x).
	var png := ProjectSettings.globalize_path(OUT.path_join("pantalla@3x.png"))
	var ok: bool = await api.export(png, ab, {"scale": 3.0})
	var img := Image.load_from_file(png) if ok else null
	check("PNG @3x: 1170 × 2532", img != null and img.get_size() == Vector2i(1170, 2532), str(img.get_size()) if img else "-")
	if img and copies.size() == 4:
		# Los 4 botones idénticos también en el PNG: el texto de los que no se
		# ven en pantalla no puede salir borroso (VAL-25).
		var mt2 = ic._mt
		var crops: Array = []
		for c in copies:
			var r: Rect2 = mt2._global_rect(c)
			var lp: Vector2 = ab.get_global_transform().affine_inverse() * r.position
			crops.append(img.get_region(Rect2i(Vector2i((lp * 3.0).round()) + Vector2i(30, 12), Vector2i(900, 120))))
		var diff := 0.0
		for i in range(1, 4):
			for y in range(0, 120, 2):
				for x in range(0, 900, 2):
					var a: Color = crops[0].get_pixel(x, y)
					var b: Color = crops[i].get_pixel(x, y)
					diff = maxf(diff, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b))
		check("PNG @3x: los 4 botones salen igual de nítidos", diff < 0.3, "dif. máx. %.2f" % diff)
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
	var n_btn := 0
	if ab2:
		for c in ab2.get_children():
			if c.find_child("Texto boton*", true, false):
				n_btn += 1
	check("reabrir: 4 botones y 2 tarjetas", n_btn == 4 and ab2.find_children("Tarjeta*", "", false, false).size() == 2, "%d botones" % n_btn)
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
