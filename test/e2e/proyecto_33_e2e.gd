# =============================================================================
# FASE B · ENCARGO 33 — Campaña «Café de especialidad» (Smart)
# Etiqueta circular 600×600 + cartel A4 + publicación 1080×1350.
# Sello circular con texto ENCIMA del círculo y otro INVERTIDO por debajo,
# granos de café como pincel de figuras hecho con un GRUPO seleccionado
# (elipse + raya), ilustración a lápiz, foto con máscara, estrellas de
# valoración (polígonos), exportar + reimportar, guardar/reabrir, deshacer.
#   test/run_e2e.sh proyecto_33_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/33"
const CREAM := Color("#f4ead7")
const COFFEE := Color("#4a2c1d")
const CARAMEL := Color("#c8833d")
const GREEN := Color("#2f5d3a")
var K

func _init() -> void:
	_run.call_deferred()
	create_timer(600.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func circle_path(c: Vector2, r: float, name: String) -> Node2D:
	var cv := Curve2D.new()
	for k in 4:
		var a := -PI + k * PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * r
		var tg := Vector2(-sin(a), cos(a)) * r * 0.5523
		cv.add_point(p, -tg, tg)
	cv.add_point(c + Vector2(-r, 0), Vector2(0, r * 0.5523), Vector2.ZERO)
	var p2 = K.api.add_curve(cv, false, name)
	K.api.set_props(p2, {"stroke_width": 0.0})
	return p2

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("smart"):
		print("RESULT: no arranca")
		quit(1)
		return
	var api = K.api
	# ── Etiqueta circular ────────────────────────────────────────────────────
	var label: Node2D = await K.artboard(Vector2(600, 600), "Etiqueta", CREAM)
	var disc = api.add_ellipse(Vector2(300, 300), Vector2(520, 520), "Disco")
	api.set_props(disc, {"fill_color": COFFEE, "stroke_color": CARAMEL, "stroke_width": 10.0})
	var inner = api.add_ellipse(Vector2(300, 300), Vector2(330, 330), "Disco interior")
	api.set_props(inner, {"fill_color": Color(0, 0, 0, 0), "stroke_color": CREAM, "stroke_width": 3.0})
	var top_ring = circle_path(Vector2(300, 300), 205, "Aro superior")
	var t1: Line2D = await K.text_on_path("TOSTADO ARTESANAL", 40, CREAM, top_ring, {"start_at": 0.0, "end_at": 0.5, "align": 0.5, "tracking": 0.1})
	var bottom_ring = circle_path(Vector2(300, 300), 205, "Aro inferior")
	var t2: Line2D = await K.text_on_path("DESDE 1990 · BIOKO", 34, CARAMEL, bottom_ring, {"start_at": 0.5, "end_at": 1.0, "align": 0.5, "reverse": true, "valign": "top"})
	K.check("sello: texto encima del círculo", t1 != null)
	K.check("sello: texto invertido por debajo (se lee derecho)", t2 != null and bool((t2.get_meta("brush_obj") as Dictionary)["params"]["reverse"]))
	# Grano de café = grupo (elipse + raya), usado como pincel
	var bean = api.add_ellipse(Vector2(520, 560), Vector2(26, 36), "Grano")
	api.set_props(bean, {"fill_color": CARAMEL, "stroke_width": 0.0})
	var crack := Curve2D.new()
	crack.add_point(Vector2(520, 545), Vector2.ZERO, Vector2(6, 8))
	crack.add_point(Vector2(520, 575), Vector2(-6, -8), Vector2.ZERO)
	var crack_p = api.add_curve(crack, false, "Raya")
	api.set_props(crack_p, {"stroke_color": COFFEE, "stroke_width": 3.0})
	var bean_g = api.group([bean, crack_p], "Grano completo")
	K.sm.select(bean_g)
	await K.frames(2)
	var beans: Line2D = K.object_brush([bean_g], K.arc_points(Vector2(300, 300), 120, 0.0, TAU, 72), 22.0, {"spacing": 1.25, "angle_jitter": 30.0, "size_jitter": 0.2, "seed": 9}, "Corona de granos")
	K.check("pincel de figuras con un GRUPO seleccionado", beans != null and ((beans.get_meta("brush_obj") as Dictionary)["src"] as Array).size() >= 1)
	var cup_steam: Line2D = K.brush(K.scribble(Vector2(260, 330), Vector2(340, 250), 18.0, 50, 4), 4.0, "pencil", CREAM, true, "Vapor")
	var cname = api.add_text(Vector2(205, 275), "BIOKO", 44, CREAM)
	cname.name = "Marca"
	await K.look_at(label)
	await K.frame_ms("etiqueta")
	await K.shot("01_etiqueta")
	# ── Cartel A4 ────────────────────────────────────────────────────────────
	var poster: Node2D = await K.artboard(Vector2(794, 1123), "Cartel A4", CREAM)
	var arch = api.add_rect(Vector2(397, 420), Vector2(620, 620), 310.0, "Arco foto")
	api.set_props(arch, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var photo = api.add_image(K.gradient_image(640, 640, CARAMEL, COFFEE), Vector2(397, 420), "Foto taza")
	K.check("máscara en arco sobre la foto", await K.mask(arch, photo))
	var stars: Array = []
	for i in 5:
		var s = api.add_star(Vector2(260 + i * 68, 820), 24, 5, 0.45, "Valoración %d" % i)
		api.set_props(s, {"fill_color": CARAMEL if i < 4 else Color(CARAMEL, 0.3), "stroke_width": 0.0})
		stars.append(s)
	api.group(stars, "Valoración")
	var head = api.add_text(Vector2(110, 900), "Origen único", 70, COFFEE)
	head.name = "Titular"
	K.brush(K.scribble(Vector2(110, 990), Vector2(560, 985), 5.0, 60, 6), 6.0, "marker", GREEN, true, "Subrayado")
	await K.look_at(poster)
	await K.frame_ms("cartel")
	await K.shot("02_cartel")
	# ── Publicación ──────────────────────────────────────────────────────────
	var post: Node2D = await K.artboard(Vector2(1080, 1350), "Publicacion", COFFEE)
	for i in 30:
		var b = api.add_ellipse(Vector2(80 + (i % 6) * 185, 120 + (i / 6) * 230), Vector2(60, 84), "Grano %d" % i)
		api.set_props(b, {"fill_color": Color(CARAMEL, 0.35), "stroke_width": 0.0, "rotation": float(i) * 0.4})
	var cta = api.add_text(Vector2(120, 1150), "Pídelo hoy", 96, CREAM)
	cta.name = "Llamada"
	await K.look_at(post)
	await K.frame_ms("publicacion")
	await K.shot("03_publicacion")
	K.note("figuras", K.count_shapes(K.cont))
	# ── Exportar / importar / reabrir ────────────────────────────────────────
	var ex: Dictionary = await K.export_all(label, "etiqueta")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG de la etiqueta con el sello", svg.length() > 5000, "%d bytes" % svg.length())
	await K.export_all(poster, "cartel")
	await K.import_back(ex, "etiqueta")
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("cafe")
	for a in abs:
		if String(a.name) == "Etiqueta":
			var tl := 0
			for c in a.find_children("*", "Line2D", true, false):
				if c.has_meta("brush_ref"):
					tl += 1
			K.check("reabrir: los dos textos del sello", tl == 2, str(tl))
			await K.look_at(a)
			await K.shot("04_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
