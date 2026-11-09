# =============================================================================
# FASE B · ENCARGO 34 — Campaña «Residencial Bahía» (Modern) — CARGA MEDIA
# Valla 1920×1080 con horizonte de 300 edificios (polígonos) y ~2 400
# ventanas, máscara de foto en el cielo, texto en trazado sobre la bahía,
# pinceles; folleto A5. Mide: fotograma con todo a la vista, seleccionar
# todo, mover la selección, pasar el ratón (clic preciso) sobre miles de
# figuras, exportar, guardar y reabrir.
#   test/run_e2e.sh proyecto_34_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/34"
const SKY := Color("#1b3a5c")
const SUN := Color("#ffb347")
const SEA := Color("#2a7f9e")
const BLD := Color("#0e1a26")
const WIN := Color("#ffe39a")
var K

func _init() -> void:
	_run.call_deferred()
	create_timer(900.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	var api = K.api
	var t0 := Time.get_ticks_msec()
	var bill: Node2D = await K.artboard(Vector2(1920, 1080), "Valla", SKY)
	var sky = api.add_rect(Vector2(960, 330), Vector2(1920, 660), 0.0, "Cielo")
	api.set_props(sky, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var sky_img = api.add_image(K.gradient_image(480, 165, SKY, SUN), Vector2(960, 330), "Foto cielo")
	sky_img.scale = Vector2(4, 4)
	sky_img.position = Vector2.ZERO
	K.check("máscara del cielo", await K.mask(sky, sky_img))
	var sun = api.add_ellipse(Vector2(1450, 420), Vector2(260, 260), "Sol")
	api.set_props(sun, {"fill_color": SUN, "stroke_width": 0.0})
	# Horizonte: 300 edificios + ventanas
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	var buildings: Array = []
	var windows: Array = []
	var x := 0.0
	for i in 300:
		var w := rng.randf_range(18, 46)
		var h := rng.randf_range(120, 460)
		var b = api.add_rect(Vector2(x + w * 0.5, 760 - h * 0.5), Vector2(w, h), 0.0, "Edificio %d" % i)
		api.set_props(b, {"fill_color": BLD.lerp(SKY, rng.randf() * 0.35), "stroke_width": 0.0})
		buildings.append(b)
		if i % 3 == 0:
			for r in int(h / 40):
				var wn = api.add_rect(Vector2(x + w * 0.5, 760 - h + 24 + r * 40), Vector2(w * 0.5, 12), 0.0, "Ventana %d-%d" % [i, r])
				api.set_props(wn, {"fill_color": WIN if rng.randf() > 0.3 else Color(WIN, 0.25), "stroke_width": 0.0})
				windows.append(wn)
		x += w * 0.64
	var g_city = api.group(buildings + windows, "Ciudad")
	K.check("horizonte agrupado (%d edificios, %d ventanas)" % [buildings.size(), windows.size()], g_city != null)
	var sea = K.wave(Vector2(-20, 860), Vector2(1940, 860), 22, 7, SEA, 40.0, "Bahía")
	var tp: Line2D = await K.text_on_path("VIVE FRENTE AL MAR · RESIDENCIAL BAHÍA", 46, Color.WHITE, sea, {"valign": "top", "align": 0.5, "tracking": 0.05})
	K.check("texto en trazado sobre la bahía", tp != null)
	for i in 4:
		K.brush(K.scribble(Vector2(80, 930 + i * 30), Vector2(1840, 925 + i * 30), 8.0, 90, 20 + i), 6.0, "marker", Color(SEA, 0.5), true, "Reflejo %d" % i)
	var h1 = api.add_text(Vector2(90, 120), "Tu casa con vistas", 110, Color.WHITE)
	h1.name = "Titular"
	K.note("montaje_ms", Time.get_ticks_msec() - t0)
	K.note("figuras", K.count_shapes(K.cont))
	await K.look_at(bill)
	var fm: float = await K.frame_ms("valla")
	K.check("fotograma con todo a la vista < 50 ms", fm < 50.0, "%.1f ms" % fm)
	await K.shot("01_valla")
	# Pasar el ratón por encima (clic preciso sobre miles de figuras)
	var mt = K.canvas.get_current_tool()
	if mt and mt.has_method("_shape_at"):
		var t_h := Time.get_ticks_usec()
		for i in 200:
			mt._shape_at(bill.to_global(Vector2(20 + i * 9.5, 500 + (i % 7) * 30)))
		var hover_ms := (Time.get_ticks_usec() - t_h) / 1000.0 / 200.0
		K.note("hover_ms", snappedf(hover_ms, 0.01))
		K.check("buscar la figura bajo el ratón < 4 ms", hover_ms < 4.0, "%.2f ms" % hover_ms)
	# Seleccionar todo y mover
	var all: Array = []
	for c in bill.get_children():
		if c is Node2D and String(c.name) != "ArtboardTitle":
			all.append(c)
	var t_s := Time.get_ticks_msec()
	K.sm.set_selection(all)
	await K.frames(2)
	K.note("seleccionar_todo_ms", Time.get_ticks_msec() - t_s)
	var t_m := Time.get_ticks_msec()
	for i in 10:
		for n in all:
			(n as Node2D).position += Vector2(1, 0)
		await process_frame
	K.note("mover_seleccion_ms_por_paso", (Time.get_ticks_msec() - t_m) / 10)
	K.sm.clear()
	await K.frames(2)
	# ── Folleto A5 ───────────────────────────────────────────────────────────
	var flyer: Node2D = await K.artboard(Vector2(559, 794), "Folleto A5", Color.WHITE)
	var hero = api.add_rect(Vector2(280, 250), Vector2(500, 420), 30.0, "Marco")
	api.set_props(hero, {"fill_color": Color.WHITE, "stroke_width": 0.0})
	var foto = api.add_image(K.gradient_image(520, 440, SEA, SUN), Vector2(280, 250), "Foto vivienda")
	K.check("máscara del folleto", await K.mask(hero, foto))
	var price = api.add_text(Vector2(40, 520), "Desde 189.000 €", 46, BLD)
	price.name = "Precio"
	await K.look_at(flyer)
	await K.shot("02_folleto")
	# ── Exportar / guardar / reabrir ─────────────────────────────────────────
	var ex: Dictionary = await K.export_all(bill, "valla")
	if ex.has("svg"):
		K.check("SVG de la valla con el horizonte completo", FileAccess.get_file_as_string(ex["svg"]).count("<path") > 900)
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("bahia")
	K.check("reabrir: valla y folleto", abs.size() >= 2)
	for a in abs:
		if String(a.name) == "Valla":
			await K.look_at(a)
			await K.frame_ms("valla_reabierta")
			await K.shot("03_reabierta")
	K.note("memoria_mb", K.memory_mb())
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
