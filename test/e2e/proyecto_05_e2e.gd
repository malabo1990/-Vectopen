# =============================================================================
# FASE B · ENCARGO 05 — Logo vectorial con variantes (modo Pro)
# Foco: booleanas, uniones, versiones monocromas.
# Marca = círculo ∪ rectángulo (unión viva), menos un círculo pequeño (agujero);
# cambiar la operación en vivo; aplanar a trazado; deshacer. Tres páginas:
# color, mono negro y mono blanco sobre fondo oscuro. SVG/PDF/PNG por variante
# (el agujero sale como agujero, un solo trazado, color correcto); deshacer 20
# pasos; guardar/reabrir; tema oscuro.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_05_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/05"
const FIXTURE := "res://test/fixtures/proyectos/05-logo.vtc"
const SIZE := Vector2(600, 600)
const BRAND := Color(0.1, 0.45, 0.85)
const DARK := Color(0.08, 0.08, 0.1)

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

func near(a: Color, b: Color, tol := 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol

## Área con regla par-impar (contorno mayor menos los interiores), sea cual
## sea el sentido de cada contorno.
func area(node: Node) -> float:
	var parts: Array = []
	for poly in node.get_evaluated_geometry():
		var s := 0.0
		for i in poly.size():
			s += poly[i].cross(poly[(i + 1) % poly.size()])
		parts.append(absf(s / 2.0))
	if parts.is_empty():
		return 0.0
	parts.sort()
	var a: float = parts.pop_back()
	for x in parts:
		a -= x
	return a

## Construye la marca en `ab`: unión viva de círculo + barra, menos un agujero.
func build_logo(ab: Node2D, color: Color) -> Node:
	api.set_active_artboard(ab)
	var c = api.add_ellipse(Vector2(300, 260), Vector2(260, 260), "Circulo")
	var bar = api.add_rect(Vector2(300, 420), Vector2(360, 80), 20.0, "Barra")
	var hole = api.add_ellipse(Vector2(300, 260), Vector2(100, 100), "Agujero")
	for s in [c, bar, hole]:
		api.set_props(s, {"stroke_width": 0.0, "fill_color": color})
	var uni = api.boolean("union", [c, bar])
	var res = api.boolean("subtract", [uni, hole])
	if res:
		res.name = "Marca"
	return res

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
	var p1: Node2D = api.artboard()
	p1.artboard_size = SIZE
	p1.name = "Color"
	# 1. Booleanas vivas.
	var logo = build_logo(p1, BRAND)
	await frames(6)
	check("la marca es un booleano vivo (resta)", logo != null and logo.has_method("get_source_shapes") and String(logo.operation) == "subtract")
	var a_sub := area(logo) if logo else 0.0
	var expect := PI * 130.0 * 130.0 - PI * 50.0 * 50.0   # aprox.: círculo − agujero (+ parte de la barra fuera del círculo)
	check("el área descuenta el agujero", a_sub > expect and a_sub < PI * 130.0 * 130.0 + 360.0 * 80.0, "%.0f" % a_sub)
	# Cambiar la operación en vivo: intersección → solo el agujero.
	api.boolean("intersect", [logo])
	await frames(4)
	var a_int := area(logo)
	check("cambiar en vivo a «intersección» deja solo el agujero", absf(a_int - PI * 50.0 * 50.0) < 300.0, "%.0f" % a_int)
	api.undo()
	await frames(4)
	check("deshacer vuelve a la resta", String(logo.operation) == "subtract" and absf(area(logo) - a_sub) < 1.0, String(logo.operation))
	# Aplanar a un trazado y deshacer el aplanado.
	var flat = api.boolean("flatten", [logo])
	await frames(4)
	check("aplanar la marca da un trazado", flat != null and not flat.has_method("get_source_shapes") and absf(area(flat) - a_sub) < a_sub * 0.01,
		"%.0f vs %.0f, %s, vivo=%s" % [area(flat) if flat else 0.0, a_sub, flat.get_class() if flat else "-", flat.has_method("get_source_shapes") if flat else "-"])
	api.undo()
	await frames(4)
	var live: Node = p1.find_child("Marca", true, false)
	check("deshacer el aplanado recupera el booleano vivo", live != null and live.has_method("get_source_shapes"))
	api.redo()
	await frames(4)
	logo = p1.find_child("Marca", true, false)
	# 2. Variantes en páginas nuevas (copiar la marca y recolorear).
	var p2: Node2D = api.add_artboard(SIZE, "Mono negro")
	var p3: Node2D = api.add_artboard(SIZE, "Mono blanco")
	p3.fill_color = DARK
	for v in [[p2, Color.BLACK], [p3, Color.WHITE]]:
		var c: Node2D = logo.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
		api.add(c, v[0])
		c.name = "Marca"
		api.set_fill(c, v[1])
	await frames(6)
	check("3 páginas: color, mono negro, mono blanco", pages().size() == 3)
	# 3. Deshacer 20 pasos (rotar la variante de color).
	var r0: float = logo.rotation
	for i in 20:
		api.set_props(logo, {"rotation": float(i + 1)})
	for i in 20:
		api.undo()
	await frames(4)
	check("deshacer 20 pasos", is_equal_approx(logo.rotation, r0), "%.3f" % logo.rotation)
	await frames(10)
	await shot("01_logo")
	# 4. Exportar cada variante.
	var names := ["color", "negro", "blanco"]
	var fills := [BRAND, Color.BLACK, Color.WHITE]
	var bgs := [Color.WHITE, Color.WHITE, DARK]
	var ps := pages()
	for i in 3:
		var base := ProjectSettings.globalize_path(OUT.path_join("logo_%s" % names[i]))
		var ok_svg: bool = await api.export(base + ".svg", ps[i])
		var svg := FileAccess.get_file_as_string(base + ".svg")
		var re := RegEx.new()
		re.compile("<path [^>]*>")
		var paths := re.search_all(svg)
		check("SVG %s: un solo trazado con su color" % names[i], ok_svg and paths.size() == 1 and paths[0].get_string().contains("#" + (fills[i] as Color).to_html(false)),
			"%d trazados" % paths.size())
		var ok_pdf: bool = await api.export(base + ".pdf", ps[i])
		check("PDF %s" % names[i], ok_pdf and FileAccess.get_file_as_bytes(base + ".pdf").size() > 300)
		var ok_png: bool = await api.export(base + ".png", ps[i])
		var img := Image.load_from_file(base + ".png") if ok_png else null
		if img:
			var k := float(img.get_width()) / SIZE.x
			var hole := img.get_pixel(int(300 * k), int(260 * k))
			var body := img.get_pixel(int(300 * k), int(170 * k))
			check("PNG %s: el agujero deja ver el fondo y la marca su color" % names[i], near(hole, bgs[i]) and near(body, fills[i]), "%s / %s" % [hole, body])
		else:
			check("PNG %s" % names[i], false)
	# 5. Guardar y reabrir.
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
	var ok_re := ps.size() == 3
	for i in ps.size():
		var m = ps[i].find_child("Marca", true, false)
		ok_re = ok_re and m != null and near(m.fill_color, fills[i]) and absf(area(m) - a_sub) < a_sub * 0.01
	check("reabrir: 3 variantes con su color y su forma", ok_re)
	check("reabrir: el fondo oscuro de la versión blanca", ps.size() == 3 and near(ps[2].fill_color, DARK))
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
