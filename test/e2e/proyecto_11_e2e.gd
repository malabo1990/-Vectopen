# =============================================================================
# FASE B · ENCARGO 11 — Wireframe de landing (modo Modern)
# Foco: bloques, alineación, imán (snapping).
# Página 1440 × 2200: barra de navegación, héroe con titular y botón, tres
# tarjetas de características (componente vinculado), testimonios y pie.
# Alinear y distribuir desde la API (la del panel), arrastre REAL con el ratón
# de una tarjeta que se engancha al borde de otra (imán), estilos de texto con
# nombre para títulos, deshacer 20 pasos, exportar PNG/SVG/PDF, guardar/reabrir.
#   test/run_e2e.sh proyecto_11_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/11"
const W := 1440.0
const GRAY := Color("#d9dce3")
const DARK := Color("#2b2f3a")
const ACCENT := Color("#4f6bed")
var K

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(gp: Vector2) -> Vector2:
	return K.canvas.get_viewport().get_canvas_transform() * gp

## Arrastre real (como drag_move_e2e): pulsar, mover en 12 pasos, soltar.
func drag(a_g: Vector2, b_g: Vector2) -> void:
	var a := scr(a_g)
	var b := scr(b_g)
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	_send(mm)
	await K.frames(2)
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await K.frames(2)
	for i in range(1, 13):
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, i / 12.0)
		m2.global_position = m2.position
		m2.relative = (b - a) / 12.0
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m2)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await K.frames(4)

func grect(n: Node2D) -> Rect2:
	return K.ic._mt._global_rect(n)

func block(c: Vector2, s: Vector2, name: String, col: Color = GRAY, r: float = 8.0) -> Node2D:
	var b = K.api.add_rect(c, s, r, name)
	K.api.set_props(b, {"fill_color": col, "stroke_width": 0.0})
	return b

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	var api = K.api
	var ab: Node2D = await K.artboard(Vector2(W, 2200), "Landing", Color("#f7f8fb"))
	# ── Navegación ───────────────────────────────────────────────────────────
	var nav = block(Vector2(W / 2, 40), Vector2(W, 80), "Navegación", Color.WHITE, 0.0)
	var logo = block(Vector2(120, 40), Vector2(120, 32), "Logo", DARK, 6.0)
	var links: Array = []
	for i in 4:
		links.append(block(Vector2(760 + i * 130, 40), Vector2(90, 14), "Enlace %d" % (i + 1)))
	var cta_nav = block(Vector2(1320, 40), Vector2(140, 44), "Botón nav", ACCENT, 22.0)
	api.align(links + [logo, cta_nav], "middle")
	var y0: float = grect(links[0]).get_center().y
	K.check("navegación: enlaces, logo y botón centrados en vertical",
		(links + [logo, cta_nav]).all(func(n) -> bool: return absf(grect(n).get_center().y - y0) < 0.6))
	api.distribute(links, "h")
	var gaps: Array = []
	for i in range(1, 4):
		gaps.append(grect(links[i]).position.x - grect(links[i - 1]).end.x)
	K.check("navegación: enlaces repartidos con el mismo hueco", gaps.all(func(g) -> bool: return absf(g - gaps[0]) < 0.6), str(gaps))
	# ── Héroe ────────────────────────────────────────────────────────────────
	var hero = block(Vector2(W / 2, 420), Vector2(1280, 560), "Héroe", Color("#e9ecf5"), 16.0)
	var h1 = api.add_text(Vector2(180, 260), "Diseña más rápido", 72, DARK)
	h1.name = "Titular"
	api.set_prop(h1, "font_weight", 700)
	var sub = api.add_text(Vector2(180, 370), "Wireframes claros en minutos, sin perder precisión.", 24, Color("#5b6070"))
	sub.name = "Subtítulo"
	var cta = block(Vector2(290, 480), Vector2(220, 60), "Botón héroe", ACCENT, 30.0)
	var img = block(Vector2(1060, 420), Vector2(420, 420), "Imagen héroe", Color("#c9cfdf"), 12.0)
	api.align([h1, sub, cta], "left")
	var lx: float = grect(h1).position.x
	K.check("héroe: titular, subtítulo y botón alineados a la izquierda",
		[sub, cta].all(func(n) -> bool: return absf(grect(n).position.x - lx) < 0.6))
	# Estilos de texto con nombre para los títulos de sección
	var sid: String = api.add_text_style("Título de sección", {"font_size": 40, "font_weight": 700, "fill_color": DARK})
	# ── Tarjetas: componente vinculado ───────────────────────────────────────
	var card_bg = block(Vector2(260, 1000), Vector2(360, 300), "Fondo tarjeta", Color.WHITE, 14.0)
	api.set_props(card_bg, {"stroke_width": 1.0, "stroke_color": GRAY})
	var icon = api.add_ellipse(Vector2(160, 920), Vector2(56, 56), "Icono")
	api.set_props(icon, {"fill_color": ACCENT, "stroke_width": 0.0})
	var ct = api.add_text(Vector2(120, 970), "Característica", 26, DARK)
	ct.name = "Título tarjeta"
	var card = api.make_symbol([card_bg, icon, ct], "Tarjeta")
	K.check("tarjeta convertida en componente", card != null and api.symbol_of(card) != "")
	var c2 = api.place_symbol(api.symbol_of(card), Vector2(720, 1000))
	var c3 = api.place_symbol(api.symbol_of(card), Vector2(1180, 1000))
	await K.frames(4)
	api.align([card, c2, c3], "top")
	api.distribute([card, c2, c3], "h")
	var cy: float = grect(card).position.y
	K.check("tarjetas alineadas arriba", [c2, c3].all(func(n) -> bool: return absf(grect(n).position.y - cy) < 0.6))
	# Cambiar el color del icono en una copia → las tres
	api.set_fill(c3.find_child("Icono*", true, false), Color("#e8743b"))
	api.sync_symbols()
	K.check("cambiar el icono de una tarjeta cambia las tres",
		[card, c2].all(func(n) -> bool: return (n.find_child("Icono*", true, false).fill_color as Color).is_equal_approx(Color("#e8743b"))))
	var sec = api.add_text(Vector2(120, 760), "Características", 30, Color.GRAY)
	sec.name = "Título características"
	api.apply_text_style(sid, [sec])
	K.check("título de sección con estilo", is_equal_approx(float(api.get_prop(sec, "font_size")), 40.0))
	# ── Imán: arrastrar un bloque cerca del borde izquierdo de la 1.ª tarjeta ─
	var note = block(Vector2(700, 1400), Vector2(300, 80), "Nota", Color("#fff3c4"), 6.0)
	await K.look_at(ab, 0.55)
	await K.frames(4)
	api.clear_selection()
	await K.frames(2)
	var target_x: float = grect(card).position.x
	var from: Vector2 = grect(note).get_center()
	var want_dx: float = target_x - grect(note).position.x
	# Soltar 3 px de pantalla antes del borde: el imán (6 px) debe completarlo.
	var z: float = K.canvas.camera.zoom.x
	await drag(from, from + Vector2(want_dx + 3.0 / z, 0))
	K.check("imán: el bloque arrastrado se engancha al borde de la tarjeta",
		absf(grect(note).position.x - target_x) < 0.6, "%.2f vs %.2f" % [grect(note).position.x, target_x])
	# ── Testimonios y pie ────────────────────────────────────────────────────
	var quotes: Array = []
	for i in 2:
		quotes.append(block(Vector2(400 + i * 640, 1650), Vector2(560, 220), "Testimonio %d" % (i + 1), Color.WHITE, 14.0))
	var tsec = api.add_text(Vector2(120, 1480), "Lo que dicen", 30, Color.GRAY)
	tsec.name = "Título testimonios"
	api.apply_text_style(sid, [tsec])
	var foot = block(Vector2(W / 2, 2100), Vector2(W, 200), "Pie", DARK, 0.0)
	api.update_text_style(sid, {"font_size": 44})
	K.check("redefinir el estilo cambia los dos títulos de sección",
		[sec, tsec].all(func(n) -> bool: return is_equal_approx(float(api.get_prop(n, "font_size")), 44.0)))
	await K.look_at(ab)
	await K.frame_ms("landing")
	await K.shot("01_landing")
	K.note("figuras", K.count_shapes(ab))
	# ── Deshacer, exportar, reabrir ──────────────────────────────────────────
	await K.undo_redo(20)
	var ex: Dictionary = await K.export_all(ab, "landing")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con los bloques de las tres tarjetas", svg.count("<rect") + svg.count("<path") >= 15, "%d bytes" % svg.length())
	var abs: Array = await K.save_reload("landing")
	for a in abs:
		if String(a.name) == "Landing":
			var n_inst := 0
			for c in a.get_children():
				if api.symbol_of(c) != "":
					n_inst += 1
			K.check("reabrir: las tres tarjetas siguen vinculadas", n_inst == 3, str(n_inst))
			var titles := 0
			for c in a.get_children():
				if api.text_style_of(c) != "":
					titles += 1
			K.check("reabrir: los títulos conservan su estilo", titles == 2, str(titles))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
