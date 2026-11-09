# =============================================================================
# FASE B · ENCARGO 32 — Campaña «Lanzamiento AERO RUN» (Pro)
# Instagram 1080×1080 + historia 1080×1920 + cabecera web 1920×1080.
# Silueta de la zapatilla en Bézier cerrado, patrón de 60 hexágonos agrupado,
# pincel hecho con un hexágono SELECCIONADO, líneas de velocidad con
# aerógrafo, foto del producto con máscara redondeada, texto en trazado
# DEBAJO de la curva e INVERTIDO, sombras, exportar todo + reimportar,
# guardar/reabrir, deshacer 20.
#   test/run_e2e.sh proyecto_32_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/32"
const VOLT := Color("#d7ff3c")
const INK := Color("#101418")
const ORANGE := Color("#ff6a2b")
const SKY := Color("#3fa7ff")
var K

func _init() -> void:
	_run.call_deferred()
	create_timer(600.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

## Silueta de zapatilla (Bézier cerrado) dentro del rectángulo `r`.
func shoe(r: Rect2, color: Color, name: String) -> Node2D:
	var c := Curve2D.new()
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	c.add_point(P.call(0.02, 0.78), Vector2.ZERO, Vector2(0, -0.1) * r.size)
	c.add_point(P.call(0.10, 0.40), Vector2(-0.03, 0.08) * r.size, Vector2(0.04, -0.1) * r.size)
	c.add_point(P.call(0.32, 0.18), Vector2(-0.08, 0.02) * r.size, Vector2(0.06, 0.0) * r.size)
	c.add_point(P.call(0.45, 0.42), Vector2(-0.04, -0.08) * r.size, Vector2(0.08, 0.05) * r.size)
	c.add_point(P.call(0.86, 0.55), Vector2(-0.12, -0.04) * r.size, Vector2(0.1, 0.04) * r.size)
	c.add_point(P.call(0.98, 0.78), Vector2(0.0, -0.1) * r.size, Vector2(0, 0.08) * r.size)
	c.add_point(P.call(0.90, 0.92), Vector2(0.06, 0.0) * r.size, Vector2(-0.3, 0.0) * r.size)
	var p = K.api.add_curve(c, true, name)
	K.api.set_props(p, {"fill_color": color, "stroke_color": INK, "stroke_width": 6.0})
	return p

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	var api = K.api
	var t_start := Time.get_ticks_msec()
	# ── Instagram 1080×1080 ──────────────────────────────────────────────────
	var ig: Node2D = await K.artboard(Vector2(1080, 1080), "IG cuadrado", INK)
	var hexes: Array = []
	for i in 60:
		var hx = api.add_polygon(Vector2(60 + (i % 10) * 105 + (52 if (i / 10) % 2 else 0), 70 + (i / 10) * 92), 46, 6, 4.0, "Hex %d" % i)
		api.set_props(hx, {"fill_color": Color(1, 1, 1, 0.0), "stroke_color": Color(VOLT, 0.25), "stroke_width": 2.0})
		hexes.append(hx)
	var g_hex = api.group(hexes, "Patrón hexagonal")
	K.check("patrón de 60 hexágonos agrupado", g_hex != null and g_hex.get_child_count() == 60)
	var sole = shoe(Rect2(140, 380, 800, 360), VOLT, "Zapatilla")
	var stripe := Curve2D.new()
	stripe.add_point(Vector2(300, 600), Vector2.ZERO, Vector2(160, -40))
	stripe.add_point(Vector2(780, 560), Vector2(-120, 60), Vector2.ZERO)
	var swoosh = api.add_curve(stripe, false, "Swoosh")
	api.set_props(swoosh, {"stroke_color": ORANGE, "stroke_width": 22.0})
	for i in 6:
		K.brush(PackedVector2Array([Vector2(40, 470 + i * 38), Vector2(150 + i * 20, 470 + i * 38)]), 10.0 - i, "airbrush", Color(SKY, 0.7), true, "Velocidad %d" % i)
	var seed_hex = api.add_polygon(Vector2(900, 980), 16, 6, 2.0, "Hex pincel")
	api.set_props(seed_hex, {"fill_color": VOLT, "stroke_width": 0.0})
	K.sm.select(seed_hex)
	await K.frames(2)
	var trail: Line2D = K.object_brush([seed_hex], K.scribble(Vector2(80, 900), Vector2(1000, 860), 40.0, 60, 5), 24.0, {"spacing": 1.3, "angle_jitter": 25.0, "seed": 2}, "Rastro hex")
	K.check("pincel de figuras con el hexágono seleccionado", trail != null)
	# Texto en trazado debajo del swoosh e invertido
	var under: Line2D = await K.text_on_path("AERO RUN · NUEVA ESPUMA", 40, Color.WHITE, swoosh, {"valign": "top", "align": 0.5})
	K.check("texto debajo del trazo", under != null and String((under.get_meta("brush_obj") as Dictionary)["params"]["valign"]) == "top")
	var arc := Curve2D.new()
	arc.add_point(Vector2(160, 300), Vector2.ZERO, Vector2(240, -160))
	arc.add_point(Vector2(920, 300), Vector2(-240, -160), Vector2.ZERO)
	var arc_p = api.add_curve(arc, false, "Arco titular")
	api.set_props(arc_p, {"stroke_width": 0.0})
	var rev: Line2D = await K.text_on_path("CORRE MÁS LIGERO", 64, VOLT, arc_p, {"reverse": true, "align": 0.5})
	K.check("texto invertido en el arco", rev != null and bool((rev.get_meta("brush_obj") as Dictionary)["params"]["reverse"]))
	api.add_effect(sole, "Drop Shadow", {"distance": 18.0})
	await K.look_at(ig)
	await K.frame_ms("ig")
	await K.shot("01_ig")
	# ── Historia ─────────────────────────────────────────────────────────────
	var story: Node2D = await K.artboard(Vector2(1080, 1920), "Historia", Color("#1a1f26"))
	var card = api.add_rect(Vector2(540, 760), Vector2(860, 860), 80.0, "Tarjeta producto")
	api.set_props(card, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var foto = api.add_image(K.gradient_image(900, 900, SKY, VOLT), Vector2(540, 760), "Foto producto")
	K.check("máscara redondeada sobre la foto del producto", await K.mask(card, foto))
	shoe(Rect2(160, 560, 760, 340), ORANGE, "Zapatilla historia")
	var price = api.add_text(Vector2(120, 1340), "129 €", 120, VOLT)
	price.name = "Precio"
	var buy = api.add_rect(Vector2(540, 1680), Vector2(700, 140), 70.0, "Comprar")
	api.set_props(buy, {"fill_color": VOLT, "stroke_width": 0.0})
	await K.look_at(story)
	await K.frame_ms("historia")
	await K.shot("02_historia")
	# ── Cabecera web ─────────────────────────────────────────────────────────
	var hero: Node2D = await K.artboard(Vector2(1920, 1080), "Cabecera web", INK)
	for i in 14:
		K.wave(Vector2(-40, 120 + i * 70), Vector2(1960, 120 + i * 70), 18, 6, Color(VOLT, 0.12 + 0.04 * (i % 4)), 3.0, "Línea %d" % i)
	shoe(Rect2(820, 260, 1000, 460), VOLT, "Zapatilla web")
	var h1 = api.add_text(Vector2(120, 300), "AERO RUN", 160, Color.WHITE)
	h1.name = "Titular web"
	await K.look_at(hero)
	await K.frame_ms("web")
	await K.shot("03_web")
	K.note("montaje_ms", Time.get_ticks_msec() - t_start)
	K.note("figuras", K.count_shapes(K.cont))
	# ── Exportar / importar / reabrir ────────────────────────────────────────
	var ex: Dictionary = await K.export_all(ig, "ig")
	await K.export_all(hero, "web")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con el patrón y la zapatilla", svg.contains("Zapatilla") or svg.length() > 20000, "%d bytes" % svg.length())
	await K.import_back(ex, "ig")
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("aero_run")
	K.check("reabrir: 3 mesas de la campaña", abs.filter(func(a): return String(a.name) in ["IG cuadrado", "Historia", "Cabecera web"]).size() == 3)
	for a in abs:
		if String(a.name) == "IG cuadrado":
			var tl := 0
			for c in a.find_children("*", "Line2D", true, false):
				if c.has_meta("brush_ref"):
					tl += 1
			K.check("reabrir: los dos textos en trazado", tl == 2, str(tl))
			await K.look_at(a)
			await K.shot("04_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
