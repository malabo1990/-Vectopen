# =============================================================================
# FASE B · ENCARGO 24 — Certificado / diploma (modo Modern)
# Foco: texto centrado, adornos, PDF.
# A4 apaisado (1123 × 794): doble marco, adornos en las esquinas (componente
# vinculado), «CERTIFICADO» con tracking, nombre grande, párrafo centrado,
# sello con estrella degradada y texto en círculo, dos líneas de firma con
# su rótulo. Cada elemento centrado en la página (alinear con un solo objeto
# = respecto a la página), editar el nombre y que siga centrado tras volver a
# centrar, PDF A4 apaisado, reabrir.
#   test/run_e2e.sh proyecto_24_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/24"
const SIZE := Vector2(1123, 794)
const NAVY := Color("#1d3557")
const GOLD := Color("#b08d2a")
var K
var api
var ab: Node2D

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func center_x(n: Node) -> float:
	return K.ic._visual_rect(n).get_center().x - ab.global_position.x

func center_on_page(n: Node) -> void:
	api.align([n], "center_h")

func circle_path(c: Vector2, r: float, name: String) -> Node2D:
	var cv := Curve2D.new()
	for k in 4:
		var a := -PI + k * PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * r
		var tg := Vector2(-sin(a), cos(a)) * r * 0.5523
		cv.add_point(p, -tg, tg)
	cv.add_point(c + Vector2(-r, 0), Vector2(0, r * 0.5523), Vector2.ZERO)
	var p2 = api.add_curve(cv, false, name)
	api.set_props(p2, {"stroke_width": 0.0})
	return p2

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	ab = await K.artboard(SIZE, "Certificado", Color("#fdfbf5"))
	var outer = api.add_rect(SIZE / 2.0, SIZE - Vector2(60, 60), 0.0, "Marco exterior")
	api.set_props(outer, {"fill_color": Color(0, 0, 0, 0), "stroke_color": NAVY, "stroke_width": 6.0})
	var inner = api.add_rect(SIZE / 2.0, SIZE - Vector2(90, 90), 0.0, "Marco interior")
	api.set_props(inner, {"fill_color": Color(0, 0, 0, 0), "stroke_color": GOLD, "stroke_width": 1.5})
	# Adorno de esquina como componente, colocado en las 4 esquinas
	var s1 = api.add_star(Vector2(80, 80), 18, 8, 0.45, "Estrella adorno")
	api.set_props(s1, {"fill_color": GOLD, "stroke_width": 0.0})
	var d1 = api.add_ellipse(Vector2(80, 80), Vector2(10, 10), "Punto adorno")
	api.set_props(d1, {"fill_color": NAVY, "stroke_width": 0.0})
	var orn = api.make_symbol([s1, d1], "Adorno")
	var corners := [orn]
	for p in [Vector2(SIZE.x - 80, 80), Vector2(80, SIZE.y - 80), Vector2(SIZE.x - 80, SIZE.y - 80)]:
		corners.append(api.place_symbol(api.symbol_of(orn), p))
	K.check("4 adornos de esquina vinculados", corners.all(func(c) -> bool: return c != null and api.symbol_of(c) == api.symbol_of(orn)))
	# Textos
	var title = api.add_text(Vector2(300, 110), "CERTIFICADO", 64, NAVY)
	title.name = "Título"
	api.set_props(title, {"font_weight": 800, "letter_spacing": 10.0})
	var sub = api.add_text(Vector2(300, 200), "DE RECONOCIMIENTO", 22, GOLD)
	sub.name = "Subtítulo"
	api.set_prop(sub, "letter_spacing", 6.0)
	var pre = api.add_text(Vector2(300, 260), "Se otorga a", 20, NAVY)
	pre.name = "Se otorga"
	var who = api.add_text(Vector2(300, 300), "María Nchama Obiang", 58, NAVY)
	who.name = "Nombre"
	api.set_props(who, {"font_italic": true, "font_weight": 600})
	var body = api.add_text_box(Rect2(200, 400, 723, 90), "Por su destacada participación en el Taller de Diseño Vectorial celebrado en Malabo durante el mes de noviembre de 2026.", 18, NAVY)
	body.name = "Motivo"
	api.set_prop(body, "text_align", "center")
	var texts := [title, sub, pre, who, body]
	await K.frames(6)
	for n in texts:
		center_on_page(n)
	await K.frames(4)
	var off: Array = texts.map(func(n) -> float: return absf(center_x(n) - SIZE.x / 2.0))
	K.check("título, subtítulo, nombre y párrafo centrados en la página", off.all(func(o) -> bool: return o < 2.0), str(off))
	# Editar el nombre (más largo) y volver a centrar
	api.set_prop(who, "text", "María Nchama Obiang Esono")
	await K.frames(6)
	center_on_page(who)
	K.check("nombre editado y recentrado", absf(center_x(who) - SIZE.x / 2.0) < 2.0, "%.1f" % center_x(who))
	# Sello: estrella degradada + texto en círculo
	var seal_c := Vector2(SIZE.x / 2.0, 640)
	var star = api.add_star(seal_c, 62, 24, 0.86, "Sello")
	api.set_prop(star, "stroke_width", 0.0)
	api.set_prop(star, "fill_paint", {"type": "radial", "stops": [[0.0, Color("#f1d38a")], [1.0, GOLD]]})
	var ring = circle_path(seal_c, 44.0, "Aro sello")
	var seal_t: Line2D = await K.text_on_path("· MALABO · 2026 · TALLER ", 13, NAVY, ring, {"align": 0.5})
	K.check("sello con texto en círculo", seal_t != null)
	# Líneas de firma con rótulo centrado bajo cada una
	for i in 2:
		var x0 := 180.0 + i * 543.0
		var ln = api.add_path(PackedVector2Array([Vector2(x0, 650), Vector2(x0 + 220, 650)]), false, "Firma %d" % (i + 1))
		api.set_props(ln, {"stroke_color": NAVY, "stroke_width": 1.2})
		var lab = api.add_text(Vector2(x0, 660), ["Dirección", "Coordinación"][i], 16, NAVY)
		lab.name = "Rótulo firma %d" % (i + 1)
		await K.frames(3)
		api.align([ln, lab], "center_h")
		var lr: Rect2 = K.ic._visual_rect(ln)
		K.check("rótulo «%s» centrado bajo su línea" % ["Dirección", "Coordinación"][i], absf(K.ic._visual_rect(lab).get_center().x - lr.get_center().x) < 2.0)
	await K.look_at(ab)
	await K.shot("01_certificado")
	await K.undo_redo(20)
	var ex: Dictionary = await K.export_all(ab, "certificado")
	if ex.has("pdf"):
		var raw := FileAccess.get_file_as_bytes(ex["pdf"]).get_string_from_ascii()
		var mb := RegEx.create_from_string("/MediaBox \\[0 0 ([0-9.]+) ([0-9.]+)\\]").search(raw)
		var w := float(mb.get_string(1)) if mb else 0.0
		var h := float(mb.get_string(2)) if mb else 0.0
		K.check("PDF A4 apaisado (842 × 595 pt)", absf(w - 842.25) < 2.0 and absf(h - 595.5) < 2.0, "%.1f × %.1f" % [w, h])
	var abs: Array = await K.save_reload("certificado")
	for a in abs:
		if String(a.name) == "Certificado":
			var w2: Node = a.find_child("Nombre", true, false)
			await K.frames(6)
			K.check("reabrir: el nombre sigue centrado", w2 != null and absf(K.ic._visual_rect(w2).get_center().x - a.global_position.x - SIZE.x / 2.0) < 3.0)
			var sy := 0
			for n in a.get_children():
				if api.symbol_of(n) != "":
					sy += 1
			K.check("reabrir: 4 adornos vinculados", sy == 4, str(sy))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
