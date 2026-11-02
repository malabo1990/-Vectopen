# =============================================================================
# FASE B · ENCARGO 01 — Libro de 20 páginas (modo Pro)
# Foco: páginas, pliegos 1-2-2-2, índice y numeración.
# Lo construye como un diseñador: formato A5, 20 páginas, portada, índice,
# capítulos con cabecera, cuerpo y pie con número de página automático.
# Recorre los puntos aplicables de PENDIENTE §19.3 y guarda el fixture en
# test/fixtures/proyectos/01-libro.vtc y capturas en user://proyectos/01/.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_01_e2e.gd
# =============================================================================
extends SceneTree

# El serializador se carga en _run (con preload, se compilaba antes que los
# autoloads y fallaba con «Identifier not found: GlobalEvents»).
var CS
const OUT := "user://proyectos/01"
const FIXTURE := "res://test/fixtures/proyectos/01-libro.vtc"
const A5 := Vector2(559, 794)        # 148 × 210 mm a 96 ppp
const N_PAGES := 20
const CHAPTERS := ["Introducción", "El trazo", "La forma", "El color", "La letra", "La página", "Epílogo"]

var fails := 0
var api
var cv
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

func label_of(t: Node) -> String:
	var dl = t.get_node_or_null("DisplayLabel")
	return String(dl.text) if dl else ""

func footer_of(ab: Node) -> Node:
	for n in ab.find_children("Pie*", "", true, false):
		return n
	return null

func pages_panel() -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().get_global_name() == "PagesPanel":
			return n
	return null

func build_book() -> void:
	var first: Node2D = api.artboard()
	first.artboard_size = A5
	first.name = "Pagina 01"
	for i in range(1, N_PAGES):
		api.add_artboard(A5, "Pagina %02d" % (i + 1))
	await frames(4)
	var ps := pages()
	# Portada.
	api.set_active_artboard(ps[0])
	var bg = api.add_rect(A5 / 2.0, A5, 0.0, "Fondo portada")
	api.set_fill(bg, Color(0.12, 0.16, 0.30))
	api.set_stroke(bg, Color(0, 0, 0, 0), 0.0)
	var title = api.add_text(Vector2(60, 300), "Manual de diseño", 44, Color.WHITE)
	title.name = "Titulo portada"
	api.group([bg, title], "Portada")
	# Índice (página 2).
	api.set_active_artboard(ps[1])
	var idx_lines := ["Índice", ""]
	for c in CHAPTERS.size():
		idx_lines.append("%d. %s ........ %d" % [c + 1, CHAPTERS[c], 3 + c * 2])
	var idx = api.add_text(Vector2(60, 80), "\n".join(idx_lines), 18, Color.BLACK)
	idx.name = "Indice"
	# Capítulos: cabecera, cuerpo y pie con número automático.
	for i in range(1, N_PAGES):
		api.set_active_artboard(ps[i])
		var items: Array = []
		if i >= 2:
			var ch: int = mini((i - 2) / 2, CHAPTERS.size() - 1)
			var head = api.add_text(Vector2(60, 50), CHAPTERS[ch].to_upper(), 12, Color(0.4, 0.4, 0.45))
			head.name = "Cabecera"
			var body = api.add_text(Vector2(60, 110), "Texto del capítulo %d, página %d.\nLorem ipsum dolor sit amet." % [ch + 1, i + 1], 14, Color.BLACK)
			body.name = "Cuerpo"
			items.append_array([head, body])
		var foot = api.add_text(Vector2(A5.x / 2.0 - 30, A5.y - 60), "{pág} / {total}", 11, Color(0.3, 0.3, 0.3))
		foot.name = "Pie"
		items.append(foot)
		if items.size() > 1:
			api.group(items, "Pagina %02d contenido" % (i + 1))
	api.set_active_artboard(ps[0])
	await frames(30)   # los campos de página se resuelven al refrescar

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test/fixtures/proyectos"))
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
	cv = get_first_node_in_group("_vectopen_canvas")
	cont = cv.artboards_container
	var t0 := Time.get_ticks_msec()
	await build_book()
	var build_ms := Time.get_ticks_msec() - t0
	var ps := pages()
	# 1. Formato exacto.
	check("20 páginas", ps.size() == N_PAGES, str(ps.size()))
	check("todas A5 (559 × 794)", ps.all(func(p): return (p.artboard_size as Vector2).is_equal_approx(A5)))
	# 2. Pliegos 1-2-2-2 (panel y lienzo).
	var pp := pages_panel()
	check("panel de páginas", pp != null)
	if pp:
		pp.set_view_mode(1)
		await frames(10)
		var sp: Array = pp.get_script().spreads(N_PAGES)
		check("pliegos 1-2-2-2…: 11 pliegos (portada sola, 9 dobles, última sola)", sp.size() == 11 and sp[0].size() == 1 and sp[1].size() == 2 and sp[10].size() == 1, str(sp))
		ps = pages()
		var p1: Node2D = ps[0]
		var p2: Node2D = ps[1]
		var p3: Node2D = ps[2]
		check("lienzo en pliegos: 2 y 3 enfrentadas sin hueco", is_equal_approx(p3.global_position.x, p2.global_position.x + A5.x) and is_equal_approx(p2.global_position.y, p3.global_position.y),
			"%s %s" % [p2.global_position, p3.global_position])
		check("lienzo en pliegos: la portada va a la derecha", is_equal_approx(p1.global_position.x, p3.global_position.x), "%s vs %s" % [p1.global_position, p3.global_position])
		check("lienzo en pliegos: un pliego debajo del otro", p2.global_position.y > p1.global_position.y + A5.y)
	await shot("01_pliegos")
	# 3. Numeración automática.
	ps = pages()
	var ok_num := true
	var bad := ""
	for i in range(1, N_PAGES):
		var f := footer_of(ps[i])
		var want := "%d / %d" % [i + 1, N_PAGES]
		if f == null or label_of(f) != want:
			ok_num = false
			bad = "pág %d: «%s» (esperado «%s»)" % [i + 1, label_of(f) if f else "-", want]
			break
	check("pie con número de página automático en las 19 páginas", ok_num, bad)
	var foot5 := footer_of(ps[4])
	check("el texto guardado conserva el marcador", foot5 != null and String(foot5.get_meta("text", "")) == "{pág} / {total}")
	# Reordenar: la página 5 pasa a ser la 3 → los números siguen al orden.
	if pp:
		pp.call("_select_range", ps[4], ps[4])
		pp.move_selected_to(2)
		await frames(40)
		ps = pages()
		check("tras mover la página 5 a la 3, su pie dice «3 / 20»", label_of(footer_of(ps[2])) == "3 / 20", label_of(footer_of(ps[2])))
		check("y la que era la 3 dice ahora «4 / 20»", label_of(footer_of(ps[3])) == "4 / 20", label_of(footer_of(ps[3])))
		root.get_node("HistoryManager").undo()
		await frames(40)
	# 4. Capas: grupos por página.
	ps = pages()
	var groups := 0
	for p in ps:
		for c in (p as Node).get_children():
			if String(c.name).begins_with("Pagina ") and String(c.name).ends_with("contenido"):
				groups += 1
	check("contenido agrupado por página (Capas)", groups == N_PAGES - 2, str(groups))
	# 5. Deshacer 20 pasos.
	var bg = ps[0].find_child("Fondo portada", true, false)
	var c0: Color = bg.fill_color
	for k in 20:
		api.set_fill(bg, Color.from_hsv(k / 20.0, 0.6, 0.8))
	await frames(4)
	for k in 20:
		api.undo()
	await frames(4)
	check("20 cambios y 20 deshacer vuelven al original", (bg.fill_color as Color).is_equal_approx(c0), str(bg.fill_color))
	# 6. Guardar, cerrar, reabrir.
	var path := ProjectSettings.globalize_path(FIXTURE)
	check("guardar .vtc", CS.write_vtc(path, cont))
	var texts_before := 0
	for p in pages():
		texts_before += (p as Node).find_children("*", "Node2D", true, false).filter(func(n): return n.has_meta("text")).size()
	for p in pages():
		cont.remove_child(p)
		p.free()
	await frames(4)
	CS.rebuild_from_vtc(cont, path)
	await frames(10)
	# Las páginas se reabren «dormidas» (carga diferida): se despiertan todas,
	# como al recorrer el documento.
	for p in pages():
		if p.get("is_dormant"):
			await p.wake()
	await frames(40)
	ps = pages()
	var texts_after := 0
	for p in ps:
		texts_after += (p as Node).find_children("*", "Node2D", true, false).filter(func(n): return n.has_meta("text")).size()
	check("reabrir: 20 páginas A5", ps.size() == N_PAGES and ps.all(func(p): return (p.artboard_size as Vector2).is_equal_approx(A5)), str(ps.size()))
	check("reabrir: mismos textos", texts_after == texts_before, "%d → %d" % [texts_before, texts_after])
	check("reabrir: la numeración sigue funcionando", ps.size() > 7 and label_of(footer_of(ps[7])) == "8 / 20", label_of(footer_of(ps[7])) if ps.size() > 7 else "-")
	# 7. Exportar PNG / SVG / PDF de una página interior.
	var p8: Node2D = ps[7] if ps.size() > 7 else null
	if p8:
		for ext in ["png", "svg", "pdf"]:
			var f := ProjectSettings.globalize_path(OUT.path_join("pagina08.%s" % ext))
			var ok: bool = await api.export(f, p8)
			check("exportar página 8 a %s" % ext.to_upper(), ok and FileAccess.file_exists(f) and FileAccess.get_file_as_bytes(f).size() > 200)
		var svg_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(OUT.path_join("pagina08.svg")))
		check("el SVG lleva el número de página (no el marcador)", svg_text.contains("8 / 20") and not svg_text.contains("{pág}"))
		var img := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("pagina08.png")))
		check("el PNG tiene la proporción de la página", img != null and absf(float(img.get_width()) / img.get_height() - A5.x / A5.y) < 0.02, str(img.get_size()) if img else "-")
	# 8. Rendimiento.
	check("construir el libro (20 páginas, ~60 objetos) en < 8 s", build_ms < 8000, "%d ms" % build_ms)
	# 9. Tema oscuro.
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(10)
	await shot("03_claro")
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
