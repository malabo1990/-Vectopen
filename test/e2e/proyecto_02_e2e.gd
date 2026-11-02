# =============================================================================
# FASE B · ENCARGO 02 — Revista de 8 páginas (modo Pro)
# Foco: retícula, texto en columnas, imágenes.
# A4, 8 páginas, retícula de 3 columnas (márgenes 15 mm, medianil 5 mm,
# sangrado 3 mm) puesta desde la pestaña Páginas; portada con fondo de color;
# artículo con titular, entradilla, texto a 3 columnas e imágenes encajadas en
# las columnas. Guardar/reabrir conserva retícula y color de página; el PNG
# exportado no lleva las guías.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_02_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/02"
const FIXTURE := "res://test/fixtures/proyectos/02-revista.vtc"
const A4 := Vector2(794, 1123)
const N := 8
const MM := 96.0 / 25.4

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
	root.get_node("GlobalUI").set_ui_mode("professional")
	await frames(30)
	api = root.get_node("PluginManager").api
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var cv = get_first_node_in_group("_vectopen_canvas")
	cont = cv.artboards_container
	# 1. Formato: 8 páginas A4.
	var first: Node2D = api.artboard()
	first.artboard_size = A4
	first.name = "Portada"
	for i in range(1, N):
		api.add_artboard(A4, "Pagina %d" % (i + 1))
	await frames(4)
	var ps := pages()
	check("8 páginas A4", ps.size() == N and ps.all(func(p): return (p.artboard_size as Vector2).is_equal_approx(A4)), str(ps.size()))
	# 2. Retícula desde la pestaña Páginas (todas las páginas).
	var ls = find_cls("LayerSystem")
	if ls and ls.has_method("_switch_left_tab"):
		ls._switch_left_tab("paginas")
		await frames(6)
	var grid: Node = find_cls("PageLayoutSection")
	check("la pestaña Páginas tiene la retícula", grid != null)
	if grid:
		check("«todas las páginas» marcado por defecto", grid.chk_all.button_pressed)
		await set_field(grid.f_margin, 15.0)
		await set_field(grid.f_columns, 3.0)
		await set_field(grid.f_gutter, 5.0)
		await set_field(grid.f_bleed, 3.0)
	ps = pages()
	check("retícula aplicada a las 8 páginas (3 col., márgenes 15 mm)", ps.all(func(p): return p.layout_columns == 3 and is_equal_approx(p.layout_margin, 15.0 * MM)),
		"%s col, %.1f px" % [ps[3].layout_columns, ps[3].layout_margin])
	var cols: Array = ps[2].column_rects()
	check("3 columnas con medianil de 5 mm", cols.size() == 3 and is_equal_approx(cols[1].position.x - cols[0].end.x, 5.0 * MM))
	root.get_node("HistoryManager").undo()
	await frames(4)
	check("deshacer la última medida (sangrado)", is_equal_approx(pages()[2].bleed, 0.0), str(pages()[2].bleed))
	root.get_node("HistoryManager").redo()
	await frames(4)
	# 3. Portada con color.
	api.set_active_artboard(ps[0])
	var cream := Color(0.96, 0.93, 0.86)
	ps[0].fill_color = cream
	var mast = api.add_text(Vector2(60, 70), "FORMA", 96, Color(0.75, 0.15, 0.2))
	mast.name = "Cabecera revista"
	var cover_sub = api.add_text(Vector2(60, 240), "Número 12 · Diseño y tipografía", 22, Color.BLACK)
	cover_sub.name = "Subtitulo"
	# 4. Artículo en las páginas 2-3: titular, entradilla, 3 columnas, imágenes.
	api.set_active_artboard(ps[1])
	var c: Array = ps[1].column_rects()
	var head = api.add_text(c[0].position, "La retícula invisible", 40, Color.BLACK)
	head.name = "Titular"
	var lead = api.add_text(c[0].position + Vector2(0, 70), "Cómo las columnas ordenan la lectura.", 18, Color(0.35, 0.35, 0.4))
	lead.name = "Entradilla"
	var body_txt := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ".repeat(40)
	# Marco de texto del ancho de la retícula, a 3 columnas con su medianil.
	var frame := Rect2(c[0].position + Vector2(0, 140), Vector2(c[2].end.x - c[0].position.x, 420))
	var body = api.add_text_box(frame, body_txt, 11, Color.BLACK, 3, 5.0 * MM, "Cuerpo")
	await frames(10)
	var ic = root.get_node("InspectorCore")
	check("el cuerpo es un marco a 3 columnas", body != null and int(ic._read(body, "columns")) == 3 and is_equal_approx(float(ic._read(body, "column_gap")), 5.0 * MM))
	if body:
		var bw := float(body.get_meta("width", 0.0))
		check("el marco ocupa el ancho de la retícula (no se sale de la página)", is_equal_approx(bw, frame.size.x) and body.position.x + bw <= A4.x - 15.0 * MM + 0.5, "%.0f px" % bw)
	check("un texto de punto no ofrece «Columnas» (no tendría efecto)", ic._read(head, "columns") == null)
	# Imagen encajada en la columna 3 (abajo).
	var img := Image.create(400, 300, false, Image.FORMAT_RGB8)
	for y in 300:
		for x in 400:
			img.set_pixel(x, y, Color(x / 400.0, 0.4, y / 300.0))
	var img_path := ProjectSettings.globalize_path(OUT.path_join("foto.png"))
	img.save_png(img_path)
	var photo = api.add_image(img_path, c[2].get_center() + Vector2(0, 250), "Foto articulo")
	check("se añade la imagen", photo != null)
	if photo:
		# Escalar al ancho de la columna y alinear a su borde izquierdo.
		var k: float = c[2].size.x / 400.0
		photo.scale = Vector2(k, k)
		photo.position.x = c[2].position.x
		await frames(4)
		var r: Rect2 = Rect2(photo.position, Vector2(400, 300) * k)
		check("la imagen ocupa exactamente la columna 3", absf(r.position.x - c[2].position.x) < 0.5 and absf(r.size.x - c[2].size.x) < 0.5, "%s vs %s" % [r, c[2]])
	# 5. Alinear: titular y entradilla a la izquierda (ya en la columna 1).
	api.align([head, lead], "left")
	await frames(2)
	check("titular y entradilla alineados a la izquierda", is_equal_approx(head.position.x, lead.position.x))
	await frames(10)
	await shot("01_revista")
	# 6. Guardar, cerrar, reabrir: retícula y color de página.
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
	check("reabrir: 8 páginas", ps.size() == N)
	check("reabrir: la retícula se conserva", ps.size() == N and ps.all(func(p): return p.layout_columns == 3 and is_equal_approx(p.layout_margin, 15.0 * MM) and is_equal_approx(p.bleed, 3.0 * MM)),
		"%s col" % (ps[4].layout_columns if ps.size() > 4 else -1))
	check("reabrir: el color de la portada se conserva", ps.size() > 0 and (ps[0].fill_color as Color).is_equal_approx(cream), str(ps[0].fill_color) if ps.size() > 0 else "-")
	var body2 = ps[1].find_child("Cuerpo", true, false) if ps.size() > 1 else null
	check("reabrir: el cuerpo sigue en 3 columnas", body2 != null and int(body2.get_meta("columns", 1)) == 3)
	# 7. Exportar: el PNG no lleva las guías y la portada sale de su color.
	if ps.size() > 1:
		for ext in ["png", "svg", "pdf"]:
			var f := ProjectSettings.globalize_path(OUT.path_join("articulo.%s" % ext))
			var ok: bool = await api.export(f, ps[1])
			check("exportar artículo a %s" % ext.to_upper(), ok and FileAccess.file_exists(f) and FileAccess.get_file_as_bytes(f).size() > 200)
		var png := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("articulo.png")))
		if png:
			# Línea del margen izquierdo (15 mm) a media altura: blanco, no magenta.
			var sx := float(png.get_width()) / A4.x
			var px := png.get_pixel(int(15.0 * MM * sx), int(png.get_height() * 0.97))
			check("el PNG no lleva las guías de la retícula", px.r > 0.9 and px.g > 0.9 and px.b > 0.9, str(px))
		var fc := ProjectSettings.globalize_path(OUT.path_join("portada.png"))
		await api.export(fc, ps[0])
		var pc := Image.load_from_file(fc)
		if pc:
			var corner := pc.get_pixel(3, pc.get_height() - 3)
			check("la portada exportada tiene su color de fondo", corner.is_equal_approx(cream) or (absf(corner.r - cream.r) < 0.02 and absf(corner.b - cream.b) < 0.02), str(corner))
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
