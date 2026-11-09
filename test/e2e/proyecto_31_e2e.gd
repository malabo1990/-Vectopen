# =============================================================================
# FASE B · ENCARGO 31 — Campaña «Festival de música» (Modern)
# Póster A3 + historia 1080×1920 + banner web 1200×628. Ondas Bézier,
# manchas, estrellas (polígonos), foto con máscara circular, pinceles
# (rotulador, lápiz, aerógrafo), pincel de figuras hecho con una estrella
# SELECCIONADA, texto en trazado alrededor de un círculo, grupos por capa,
# exportar a todos los formatos + reimportar, guardar/reabrir, deshacer 20.
#   test/run_e2e.sh proyecto_31_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/31"
const MAGENTA := Color("#e0218a")
const CYAN := Color("#18c6d8")
const NIGHT := Color("#14112b")
const GOLD := Color("#ffc93c")
var K

func _init() -> void:
	_run.call_deferred()
	create_timer(600.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	var api = K.api
	var t_start := Time.get_ticks_msec()
	# ── Póster A3 ────────────────────────────────────────────────────────────
	var poster: Node2D = await K.artboard(Vector2(842, 1191), "Poster A3", NIGHT)
	var fondo: Array = []
	for i in 5:
		fondo.append(K.wave(Vector2(-20, 760 + i * 60), Vector2(862, 760 + i * 60), 28.0 + i * 6, 4 + i, MAGENTA.lerp(CYAN, i / 4.0), 6.0, "Onda %d" % i))
	fondo.append(K.blob(Vector2(620, 260), 210, 6, 0.25, Color(MAGENTA, 0.85), "Mancha rosa", 7))
	fondo.append(K.blob(Vector2(210, 520), 160, 5, 0.3, Color(CYAN, 0.8), "Mancha cian", 11))
	var g_fondo = api.group(fondo, "Fondo")
	K.check("grupo Fondo con %d piezas" % fondo.size(), g_fondo != null and g_fondo.get_child_count() == fondo.size())
	# Estrellas (polígonos) y una de ellas como pincel
	var stars: Array = []
	for i in 12:
		var s = api.add_star(Vector2(60 + (i % 6) * 140, 80 + (i / 6) * 1000), 18.0 + (i % 3) * 8, 5, 0.45, "Estrella %d" % i)
		api.set_props(s, {"fill_color": GOLD, "stroke_width": 0.0})
		stars.append(s)
	var g_stars = api.group(stars, "Estrellas")
	var seed_star = api.add_star(Vector2(420, 640), 20, 5, 0.42, "Estrella pincel")
	api.set_props(seed_star, {"fill_color": GOLD, "stroke_width": 0.0})
	K.sm.select(seed_star)
	await K.frames(2)
	var trail: Line2D = K.object_brush([seed_star], K.arc_points(Vector2(421, 600), 330, PI * 1.05, PI * 1.95, 60), 26.0, {"spacing": 1.4, "size_jitter": 0.3, "seed": 4}, "Estela de estrellas")
	K.check("pincel hecho con la estrella seleccionada", trail != null and String(trail.get_meta("brush_style")) == "object")
	# Foto con máscara circular
	var frame = api.add_ellipse(Vector2(421, 470), Vector2(380, 380), "Marco foto")
	api.set_props(frame, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var photo = api.add_image(K.gradient_image(420, 420, MAGENTA, GOLD), Vector2(421, 470), "Foto artista")
	K.check("máscara circular sobre la foto", await K.mask(frame, photo))
	# Texto en trazado alrededor del círculo
	var ring := Curve2D.new()
	var rc := Vector2(421, 470)
	var rr := 230.0
	for k in 4:
		var a := -PI + k * PI * 0.5
		var p := rc + Vector2(cos(a), sin(a)) * rr
		var tg := Vector2(-sin(a), cos(a)) * rr * 0.5523
		ring.add_point(p, -tg, tg)
	ring.add_point(rc + Vector2(-rr, 0), Vector2(0, rr * 0.5523), Vector2.ZERO)
	var ring_path = api.add_curve(ring, false, "Aro texto")
	api.set_props(ring_path, {"stroke_width": 0.0})
	var tp: Line2D = await K.text_on_path("VECTOPEN FEST · 2026 · VECTOPEN FEST", 34, Color.WHITE, ring_path, {"tracking": 0.08, "align": 0.5})
	K.check("texto en trazado alrededor del círculo", tp != null)
	# Titulares y pinceles caligráficos
	var title = api.add_text(Vector2(70, 930), "NOCHE DE SINTES", 74, Color.WHITE)
	title.name = "Titular"
	var sub = api.add_text(Vector2(72, 1030), "12–14 JUNIO · PUERTO DE MALABO", 30, CYAN)
	sub.name = "Subtitulo"
	var b1: Line2D = K.brush(K.scribble(Vector2(70, 1015), Vector2(600, 1015), 6.0), 7.0, "marker", MAGENTA, true, "Subrayado")
	var b2: Line2D = K.brush(K.arc_points(Vector2(700, 140), 90, 0.2, PI * 1.6, 40), 4.0, "pencil", Color.WHITE, true, "Garabato")
	var b3: Line2D = K.brush(K.scribble(Vector2(80, 1120), Vector2(760, 1110), 14.0, 90, 9), 22.0, "airbrush", Color(CYAN, 0.6), true, "Bruma")
	K.check("tres pinceles de estilos distintos", b1 and b2 and b3)
	var g_txt = api.group([title, sub, b1], "Textos")
	K.check("grupo Textos", g_txt != null)
	await K.look_at(poster)
	await K.frame_ms("poster")
	await K.shot("01_poster")
	# ── Historia 1080×1920 ───────────────────────────────────────────────────
	var story: Node2D = await K.artboard(Vector2(1080, 1920), "Historia IG", NIGHT)
	for i in 8:
		K.wave(Vector2(-40, 300 + i * 190), Vector2(1120, 300 + i * 190), 40, 3 + i % 3, MAGENTA.lerp(CYAN, i / 7.0), 10.0, "Ola %d" % i)
	var arc_path = K.wave(Vector2(120, 900), Vector2(960, 900), 140, 1, Color(0, 0, 0, 0), 0.0, "Curva titulo")
	var tp2: Line2D = await K.text_on_path("DESLIZA ARRIBA PARA ENTRADAS", 54, GOLD, arc_path, {"align": 0.5, "valign": "center"})
	K.check("texto en trazado (historia, centrado en la curva)", tp2 != null and String((tp2.get_meta("brush_obj") as Dictionary)["params"].get("valign", "")) == "center")
	var stamp = api.add_polygon(Vector2(540, 1500), 160, 7, 10.0, "Sello")
	api.set_props(stamp, {"fill_color": MAGENTA, "stroke_color": GOLD, "stroke_width": 8.0})
	await K.look_at(story)
	await K.frame_ms("historia")
	await K.shot("02_historia")
	# ── Banner web 1200×628 ──────────────────────────────────────────────────
	var banner: Node2D = await K.artboard(Vector2(1200, 628), "Banner web", Color("#0d0b1d"))
	K.blob(Vector2(950, 300), 260, 7, 0.2, Color(MAGENTA, 0.9), "Mancha banner", 3)
	var bt = api.add_text(Vector2(60, 200), "VECTOPEN FEST", 96, Color.WHITE)
	bt.name = "Titular banner"
	var cta = api.add_rect(Vector2(240, 470), Vector2(320, 90), 45.0, "Boton entradas")
	api.set_props(cta, {"fill_color": GOLD, "stroke_width": 0.0})
	api.add_effect(cta, "Drop Shadow", {"distance": 10.0})
	K.object_brush([stars[0]], K.scribble(Vector2(640, 560), Vector2(1180, 520), 30.0, 50), 22.0, {"spacing": 1.6}, "Estrellas banner")
	await K.look_at(banner)
	await K.frame_ms("banner")
	await K.shot("03_banner")
	K.note("montaje_ms", Time.get_ticks_msec() - t_start)
	K.note("figuras", K.count_shapes(K.cont))
	K.note("memoria_mb", K.memory_mb())
	# ── Exportar, reimportar ─────────────────────────────────────────────────
	var ex_poster: Dictionary = await K.export_all(poster, "poster")
	var ex_banner: Dictionary = await K.export_all(banner, "banner")
	if ex_poster.has("svg"):
		var svg := FileAccess.get_file_as_string(ex_poster["svg"])
		K.check("SVG del póster con máscara y texto en trazado", svg.contains("clipPath") and svg.length() > 10000, "%d bytes" % svg.length())
	if ex_poster.has("png"):
		var img := Image.load_from_file(ex_poster["png"])
		K.check("PNG del póster: tamaño A3", img != null and img.get_width() >= 842, str(img.get_size() if img else Vector2i.ZERO))
	await K.import_back(ex_banner, "banner")
	# ── Deshacer, guardar y reabrir ──────────────────────────────────────────
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("festival")
	var names: Array = abs.map(func(a): return String(a.name))
	K.check("reabrir: las mesas siguen ahí", names.has("Poster A3") and names.has("Historia IG") and names.has("Banner web"), str(names))
	var p2: Node2D = null
	for a in abs:
		if String(a.name) == "Poster A3":
			p2 = a
	if p2:
		var mf = p2.find_child("Marco foto", true, false)
		K.check("reabrir: máscara de la foto", mf != null and mf.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED)
		var tl: Node = null
		for c in p2.find_children("*", "Line2D", true, false):
			if c.has_meta("brush_ref"):
				tl = c
		K.check("reabrir: texto en trazado enlazado", tl != null)
		await K.look_at(p2)
		await K.shot("04_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
