# =============================================================================
# FASE B · ENCARGO 09 — Enciclopedia visual, 12 fichas (modo Pro)
# Foco: rejilla de páginas, consistencia.
# Ficha modelo (cabecera, título, número, ilustración, texto) → «Duplicar»
# en el panel Páginas hasta 12; vista Rejilla de 4 columnas que ordena también
# el LIENZO (3 filas × 4); cada ficha con su contenido pero la misma
# estructura y posiciones; PNG de las 12 en tiempo razonable; guardar/reabrir
# conserva orden y contenido.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_09_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/09"
const FIXTURE := "res://test/fixtures/proyectos/09-enciclopedia.vtc"
const CARD := Vector2(600, 840)
const N := 12
const ANIMALS := ["Águila", "Ballena", "Camaleón", "Delfín", "Elefante", "Flamenco",
	"Gorila", "Hipopótamo", "Iguana", "Jaguar", "Koala", "León"]
const PALETTE := [Color("#e76f51"), Color("#2a9d8f"), Color("#e9c46a"), Color("#264653")]

var fails := 0
var api
var CS
var cont: Node2D

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

func pages() -> Array:
	return cont.get_children().filter(func(c): return c.is_in_group("artboards"))

func find_cls(cls: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == cls:
			return n
	return null

## Firma de la estructura de una ficha: nombres y posiciones de sus capas.
func layout_sig(ab: Node) -> String:
	var parts: Array = []
	for c in ab.get_children():
		if c is Node2D and not String(c.name).begins_with("Artboard") and c.name != "ArtboardTitle":
			parts.append("%s@%d,%d" % [String(c.name).rstrip("0123456789"), roundi(c.position.x), roundi(c.position.y)])
	parts.sort()
	return "|".join(parts)

func content_ok(ps: Array) -> bool:
	if ps.size() != N:
		return false
	for i in N:
		if String(ps[i].find_child("Titulo", false, false).get_meta("text", "")) != ANIMALS[i]:
			return false
		if String(ps[i].find_child("Numero", false, false).get_meta("text", "")) != "%02d" % (i + 1):
			return false
	return true

func order_ok(ps: Array) -> bool:
	if ps.size() != N:
		return false
	for i in N:
		if String(ps[i].name) != "Ficha %02d" % (i + 1):
			return false
	return true

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
	root.get_node("GlobalUI").set_ui_mode("professional")
	await frames(30)
	api = root.get_node("PluginManager").api
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	cont = get_first_node_in_group("_vectopen_canvas").artboards_container
	# 1. Ficha modelo.
	var first: Node2D = api.artboard()
	first.artboard_size = CARD
	first.name = "Ficha 01"
	var head = api.add_rect(Vector2(CARD.x / 2.0, 60), Vector2(CARD.x, 120), 0.0, "Cabecera")
	api.set_props(head, {"stroke_width": 0.0, "fill_color": PALETTE[0]})
	var num = api.add_text(Vector2(36, 34), "01", 44, Color.WHITE)
	num.name = "Numero"
	var title = api.add_text(Vector2(120, 40), ANIMALS[0], 40, Color.WHITE)
	title.name = "Titulo"
	var art = api.add_ellipse(Vector2(CARD.x / 2.0, 380), Vector2(360, 360), "Ilustracion")
	api.set_props(art, {"stroke_width": 0.0, "fill_color": PALETTE[0].lightened(0.5)})
	var txt = api.add_text_box(Rect2(Vector2(40, 600), Vector2(520, 200)), "Ficha de la enciclopedia visual. ".repeat(6), 16, Color(0.15, 0.15, 0.2), 1, 20.0, "Texto")
	await frames(6)
	var model_sig := layout_sig(first)
	# 2. Duplicar en el panel Páginas hasta 12.
	var ls = find_cls("LayerSystem")
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("paginas")
		await frames(6)
	var pp = find_cls("PagesPanel")
	check("el panel Páginas está disponible", pp != null)
	if pp == null:
		print("RESULT: 1 FAIL")
		quit(1)
		return
	for i in N - 1:
		pp.selected = {}
		root.get_node("PluginManager").api.set_active_artboard(pages().back())
		pp.duplicate_selected()
		await frames(2)
	var ps := pages()
	check("12 fichas", ps.size() == N, str(ps.size()))
	check("todas con la estructura de la ficha modelo", ps.all(func(p): return layout_sig(p) == model_sig))
	# 3. Contenido propio en cada ficha (como haría el usuario, por script).
	for i in ps.size():
		var p: Node2D = ps[i]
		p.name = "Ficha %02d" % (i + 1)
		var col: Color = PALETTE[i % PALETTE.size()]
		api.set_prop(p.find_child("Cabecera", false, false), "fill_color", col)
		api.set_prop(p.find_child("Ilustracion", false, false), "fill_color", col.lightened(0.5))
		api.set_prop(p.find_child("Titulo", false, false), "text", ANIMALS[i])
		api.set_prop(p.find_child("Numero", false, false), "text", "%02d" % (i + 1))
	await frames(6)
	ps = pages()
	check("cada ficha con su animal y su número", content_ok(ps))
	# VAL-22: las copias se ven igual que la ficha modelo.
	var same := true
	var a0: Vector2 = ps[0].find_child("Titulo", false, false).get_node("VectorRichText").get_content_size()
	for i in range(1, ps.size()):
		var t: Node = ps[i].find_child("Titulo", false, false)
		if t.get_node_or_null("VectorRichText") == null or absf(t.get_node("VectorRichText").get_content_size().y - a0.y) > 1.0:
			same = false
	check("los títulos copiados tienen el mismo tamaño que el modelo", same)
	check("el marco de texto no pinta la etiqueta antigua encima", ps.all(func(p): return not (p.find_child("Texto", false, false).get_node("DisplayLabel") as CanvasItem).visible))
	# 4. Vista Rejilla de 4 columnas: también el lienzo.
	pp.grid_cols = 4
	pp.set_view_mode(2)   # GRID
	await frames(6)
	ps = pages()
	var rows := {}
	var cols := {}
	for p in ps:
		rows[roundi(p.global_position.y)] = true
		cols[roundi(p.global_position.x)] = true
	check("el lienzo se ordena en rejilla: 3 filas × 4 columnas", rows.size() == 3 and cols.size() == 4, "%d filas, %d columnas" % [rows.size(), cols.size()])
	var gap_ok := ps.size() == N and absf(ps[1].global_position.x - ps[0].global_position.x - CARD.x - pp.GAP) < 1.0 \
		and absf(ps[4].global_position.y - ps[0].global_position.y - CARD.y - pp.GAP) < 1.0
	check("rejilla con la separación de páginas en ambos sentidos", gap_ok)
	# Cambiar a 3 columnas con el deslizador → 4 filas.
	pp._on_zoom(3.0)
	await frames(4)
	rows = {}
	for p in pages():
		rows[roundi(p.global_position.y)] = true
	check("con 3 columnas el lienzo pasa a 4 filas", rows.size() == 4, "%d filas" % rows.size())
	pp._on_zoom(4.0)
	await frames(4)
	var cv = get_first_node_in_group("_vectopen_canvas")
	if cv and cv.has_method("zoom_to_fit_all"):
		cv.zoom_to_fit_all()
	await frames(10)
	await shot("01_rejilla")
	# 5. Exportar las 12 fichas a PNG.
	var t0 := Time.get_ticks_msec()
	var ok_all := true
	for i in ps.size():
		var f := ProjectSettings.globalize_path(OUT.path_join("ficha_%02d.png" % (i + 1)))
		var ok: bool = await api.export(f, ps[i])
		ok_all = ok_all and ok and FileAccess.file_exists(f)
	var ms := Time.get_ticks_msec() - t0
	check("exportar las 12 fichas a PNG", ok_all)
	check("12 PNG en < 15 s", ms < 15000, "%d ms" % ms)
	var a := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("ficha_02.png")))
	var b := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("ficha_03.png")))
	if a and b:
		check("cada PNG con el color de su ficha", a.get_pixel(5, 5).is_equal_approx(PALETTE[1]) or absf(a.get_pixel(5, 5).g - PALETTE[1].g) < 0.03,
			"%s / %s" % [a.get_pixel(5, 5), b.get_pixel(5, 5)])
	# 6. Guardar y reabrir.
	var path := ProjectSettings.globalize_path(FIXTURE)
	check("guardar .vtc", CS.write_vtc(path, cont))
	for p in pages():
		cont.remove_child(p)
		p.free()
	await frames(4)
	CS.rebuild_from_vtc(cont, path)
	await frames(10)
	for p in pages():
		if p.get("is_dormant"):
			await p.wake()
	await frames(20)
	ps = pages()
	check("reabrir: 12 fichas en orden", order_ok(ps))
	check("reabrir: contenido y estructura", ps.size() == N and content_ok(ps) and ps.all(func(p): return layout_sig(p) == model_sig))
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	pp.set_view_mode(0)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
