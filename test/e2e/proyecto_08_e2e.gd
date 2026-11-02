# =============================================================================
# FASE B · ENCARGO 08 — Infografía de datos (modo Pro)
# Foco: trazos, iconos, jerarquía tipográfica.
# Gráfico de barras con datos (alturas proporcionales), ejes con flecha,
# rejilla discontinua, barras repartidas con «Distribuir», iconos (estrellas
# y polígonos), titular / subtítulo / cuerpo / notas (4 niveles); el SVG
# conserva flechas y discontinuo; deshacer 20 pasos; guardar/reabrir.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/proyecto_08_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/08"
const FIXTURE := "res://test/fixtures/proyectos/08-infografia.vtc"
const SIZE := Vector2(1080, 1350)
const DATA := [42.0, 68.0, 55.0, 90.0, 74.0]
const LABELS := ["2021", "2022", "2023", "2024", "2025"]
const BAR := Color(0.16, 0.5, 0.95)
const INK := Color(0.1, 0.1, 0.14)

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
	var ic = root.get_node("InspectorCore")
	var cont: Node2D = get_first_node_in_group("_vectopen_canvas").artboards_container
	var ab: Node2D = api.artboard()
	ab.artboard_size = SIZE
	# 1. Jerarquía tipográfica: 4 niveles.
	var h1 = api.add_text(Vector2(80, 70), "Energía solar en España", 64, INK)
	h1.name = "Titular"
	var h2 = api.add_text(Vector2(80, 160), "Potencia instalada (GW), 2021–2025", 30, Color(0.35, 0.35, 0.42))
	h2.name = "Subtitulo"
	var body = api.add_text(Vector2(80, 1180), "La potencia se duplicó en cinco años.", 22, INK)
	body.name = "Cuerpo"
	var note = api.add_text(Vector2(80, 1260), "Fuente: datos de ejemplo.", 14, Color(0.5, 0.5, 0.55))
	note.name = "Nota"
	var sizes := [64, 30, 22, 14]
	check("4 niveles tipográficos de mayor a menor", [h1, h2, body, note].map(func(t): return int(t.get_meta("font_size", 0))) == sizes)
	# 2. Ejes con flecha y rejilla discontinua.
	var origin := Vector2(140, 1050)
	var x_axis = api.add_line(origin, Vector2(1000, 1050), 3.0, INK)
	x_axis.name = "Eje X"
	var y_axis = api.add_line(origin, Vector2(140, 300), 3.0, INK)
	y_axis.name = "Eje Y"
	for axis in [x_axis, y_axis]:
		api.set_prop(axis, "stroke_pointer_end", 2)   # triángulo
	check("los ejes llevan punta de flecha", int(ic._read(x_axis, "stroke_pointer_end")) == 2 and int(ic._read(y_axis, "stroke_pointer_end")) == 2)
	var grid_lines: Array = []
	for i in range(1, 5):
		var y := origin.y - i * 180.0
		var g = api.add_line(Vector2(140, y), Vector2(980, y), 1.0, Color(0.7, 0.7, 0.75))
		g.name = "Rejilla %d" % i
		api.set_props(g, {"stroke_style": 1, "stroke_dash_len": 8.0, "stroke_dash_gap": 6.0})
		grid_lines.append(g)
	check("rejilla discontinua (4 líneas)", grid_lines.all(func(g): return int(g.stroke_style) == 1))
	# 3. Barras proporcionales a los datos, repartidas con «Distribuir».
	var bars: Array = []
	var k := 720.0 / 100.0
	for i in DATA.size():
		var hgt: float = DATA[i] * k
		var b = api.add_rect(Vector2(240 + i * 150 + (i * i * 7), origin.y - hgt / 2.0), Vector2(90, hgt), 6.0, "Barra " + LABELS[i])
		api.set_props(b, {"stroke_width": 0.0, "fill_color": BAR if i != 3 else Color(1.0, 0.6, 0.1)})
		bars.append(b)
		var lbl = api.add_text(Vector2(240 + i * 150 - 30, origin.y + 14), LABELS[i], 20, INK)
		lbl.name = "Etiqueta " + LABELS[i]
	api.distribute(bars, "h")
	await frames(4)
	var mt = ic._mt
	var gaps: Array = []
	for i in range(1, bars.size()):
		gaps.append(mt._global_rect(bars[i]).position.x - mt._global_rect(bars[i - 1]).end.x)
	check("«Distribuir» deja el mismo espacio entre barras", gaps.all(func(g): return absf(g - gaps[0]) < 1.0), str(gaps))
	var ratio_ok := true
	for i in bars.size():
		ratio_ok = ratio_ok and absf(float(api.get_prop(bars[i], "height")) - DATA[i] * k) < 0.5
	check("las alturas siguen los datos (escala 7,2 px por unidad)", ratio_ok)
	# 4. Iconos: estrella sobre la barra mayor, hexágonos en la leyenda.
	var star = api.add_star(Vector2(mt._global_rect(bars[3]).get_center().x - ab.global_position.x, origin.y - 90.0 * k - 50), 26, 5, 0.45, "Icono record")
	api.set_props(star, {"stroke_width": 0.0, "fill_color": Color(1.0, 0.6, 0.1)})
	var hexes: Array = []
	for i in 2:
		var hx = api.add_polygon(Vector2(760 + i * 140, 240), 14, 6, 0.0, "Leyenda %d" % i)
		api.set_props(hx, {"stroke_width": 0.0, "fill_color": [BAR, Color(1.0, 0.6, 0.1)][i]})
		hexes.append(hx)
	check("iconos: estrella y 2 hexágonos", star != null and hexes.size() == 2 and int(hexes[0].sides) == 6)
	# 5. Deshacer 20 pasos (alturas de la barra 2025).
	var h0 := float(api.get_prop(bars[4], "height"))
	for i in 20:
		api.set_prop(bars[4], "height", h0 + (i + 1) * 4.0)
	for i in 20:
		api.undo()
	await frames(4)
	check("deshacer 20 pasos", absf(float(api.get_prop(bars[4], "height")) - h0) < 0.5, str(api.get_prop(bars[4], "height")))
	api.clear_selection()
	await frames(10)
	await shot("01_infografia")
	# 6. Exportar: SVG con discontinuo y flechas; PNG.
	var svg := ProjectSettings.globalize_path(OUT.path_join("infografia.svg"))
	var ok: bool = await api.export(svg, ab)
	var st := FileAccess.get_file_as_string(svg) if ok else ""
	check("SVG: la rejilla sale discontinua", st.count("stroke-dasharray") >= 4, "%d" % st.count("stroke-dasharray"))
	var png := ProjectSettings.globalize_path(OUT.path_join("infografia.png"))
	ok = await api.export(png, ab)
	var img := Image.load_from_file(png) if ok else null
	if img:
		# Punta de flecha del eje Y (arriba, x = 140): debe haber tinta encima del final de la línea.
		var tip := false
		for y in range(296, 320):
			for x in range(132, 149):
				if img.get_pixel(x, y).get_luminance() < 0.3:
					tip = true
		check("PNG: el eje Y termina en punta", tip)
	var pdf := ProjectSettings.globalize_path(OUT.path_join("infografia.pdf"))
	ok = await api.export(pdf, ab)
	var pt := FileAccess.get_file_as_bytes(pdf).get_string_from_ascii() if ok else ""
	check("PDF: la rejilla sale discontinua", pt.count("] 0 d") + pt.count("] 0.0 d") >= 4 or pt.count(" d ") >= 4)
	# Las puntas de flecha también en SVG/PDF (triángulo relleno junto al final del eje).
	var arrow_svg := false
	var re := RegEx.new()
	re.compile('<path d="M([0-9.]+) ([0-9.]+) L')
	for m in re.search_all(st):
		var p := Vector2(float(m.get_string(1)), float(m.get_string(2)))
		if p.distance_to(Vector2(140, 300)) < 25.0 and not m.get_string().contains("1050"):
			arrow_svg = true
	check("SVG: los ejes llevan su punta de flecha", arrow_svg)
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
	var y2 = ab2.find_child("Eje Y", true, false) if ab2 else null
	var g2 = ab2.find_child("Rejilla 2", true, false) if ab2 else null
	check("reabrir: flecha del eje y rejilla discontinua", y2 != null and int(ic._read(y2, "stroke_pointer_end")) == 2 and g2 != null and int(g2.stroke_style) == 1)
	var b2 = ab2.find_child("Barra 2024", true, false) if ab2 else null
	check("reabrir: barra 2024 con su altura", b2 != null and absf(float(api.get_prop(b2, "height")) - 90.0 * k) < 0.5)
	root.get_node("ThemeManager").set_mode("dark")
	await frames(20)
	await shot("02_oscuro")
	root.get_node("ThemeManager").set_mode("light")
	await frames(6)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
