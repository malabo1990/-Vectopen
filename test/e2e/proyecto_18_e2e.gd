# =============================================================================
# FASE B · ENCARGO 18 — Packaging con texto en curva (modo Pro)
# Foco: texto sobre trayectoria, 3D de texto.
# Troquel de una caja de chocolate 1600 × 1100: caras (frontal, laterales,
# trasera, solapas) con líneas de corte (magenta) y de plegado (discontinuas),
# marca con EXTRUSIÓN 3D y bisel, sello circular con texto encima e invertido
# debajo, eslogan siguiendo una onda en el lateral, bloque de ingredientes.
# Cambiar la profundidad de la extrusión (se ve), editar el texto de origen
# y que el texto en curva se rehaga, deshacer, exportar PDF/SVG/PNG, reabrir
# con efectos y textos en curva.
#   test/run_e2e.sh proyecto_18_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/18"
const CUT := Color("#e6007e")
const BROWN := Color("#4b2e1e")
const GOLD := Color("#d4a017")
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func panel(r: Rect2, name: String, col: Color) -> Node2D:
	var n = api.add_rect(r.get_center(), r.size, 0.0, name)
	api.set_props(n, {"fill_color": col, "stroke_color": CUT, "stroke_width": 1.5})
	return n

func fold(a: Vector2, b: Vector2) -> Node2D:
	var n = api.add_path(PackedVector2Array([a, b]), false, "Plegado")
	api.set_props(n, {"stroke_color": CUT, "stroke_width": 1.0, "stroke_style": 1, "stroke_dash_len": 6.0, "stroke_dash_gap": 4.0})
	return n

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

func region_sig(img: Image, r: Rect2i) -> float:
	var acc := 0.0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			acc += img.get_pixel(x, y).get_luminance()
	return acc

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1600, 1100), "Troquel", Color.WHITE)
	# Caras del troquel
	var front = panel(Rect2(450, 300, 500, 500), "Frontal", Color("#f3e1c7"))
	var back = panel(Rect2(1150, 300, 400, 500), "Trasera", Color("#f3e1c7"))
	panel(Rect2(250, 300, 200, 500), "Lateral izq", Color("#e9cfa8"))
	panel(Rect2(950, 300, 200, 500), "Lateral der", Color("#e9cfa8"))
	panel(Rect2(450, 100, 500, 200), "Solapa sup", Color("#e9cfa8"))
	panel(Rect2(450, 800, 500, 200), "Solapa inf", Color("#e9cfa8"))
	for x in [450.0, 950.0, 1150.0]:
		fold(Vector2(x, 300), Vector2(x, 800))
	fold(Vector2(450, 300), Vector2(950, 300))
	fold(Vector2(450, 800), Vector2(950, 800))
	# Marca con 3D
	var brand = api.add_text(Vector2(520, 380), "COCOA BIOKO", 64, GOLD)
	brand.name = "Marca"
	api.set_prop(brand, "font_weight", 900)
	var ex3d: Dictionary = api.add_effect(brand, "Extrusion", {"depth": 14.0, "angle": 45.0})
	var bev: Dictionary = api.add_effect(brand, "Bevel Emboss", {})
	K.check("marca con extrusión 3D y bisel", not ex3d.is_empty() and not bev.is_empty() and (api.get_prop(brand, "effects") as Array).size() == 2)
	# Sello circular: texto encima e invertido debajo
	var c := Vector2(700, 610)
	var disc = api.add_ellipse(c, Vector2(240, 240), "Sello")
	api.set_props(disc, {"fill_color": BROWN, "stroke_color": GOLD, "stroke_width": 4.0})
	var top_ring = circle_path(c, 95.0, "Aro sup")
	var t_top: Line2D = await K.text_on_path("CACAO DE BIOKO", 22, GOLD, top_ring, {"start_at": 0.0, "end_at": 0.5, "align": 0.5, "tracking": 0.08})
	var bottom_ring = circle_path(c, 95.0, "Aro inf")
	var t_bot: Line2D = await K.text_on_path("70 % · ORIGEN ÚNICO", 20, GOLD, bottom_ring, {"start_at": 0.5, "end_at": 1.0, "align": 0.5, "reverse": true, "valign": "top"})
	K.check("sello: texto encima del círculo", t_top != null)
	K.check("sello: texto invertido por debajo", t_bot != null and bool((t_bot.get_meta("brush_obj") as Dictionary)["params"].get("reverse", false)))
	# Eslogan en onda sobre el lateral (vertical)
	var wv := Curve2D.new()
	wv.add_point(Vector2(1050, 760), Vector2.ZERO, Vector2(40, -80))
	wv.add_point(Vector2(1050, 550), Vector2(-40, 80), Vector2(40, -80))
	wv.add_point(Vector2(1050, 340), Vector2(-40, 80), Vector2.ZERO)
	var wave = api.add_curve(wv, false, "Onda eslogan")
	api.set_props(wave, {"stroke_width": 0.0})
	var slogan: Line2D = await K.text_on_path("Hecho con calma", 26, BROWN, wave, {"align": 0.5})
	K.check("eslogan siguiendo una onda", slogan != null)
	# Ingredientes
	var ing = api.add_text_box(Rect2(1180, 360, 340, 300), "Ingredientes: pasta de cacao, azúcar de caña, manteca de cacao, vainilla. Puede contener trazas de frutos secos.", 16, BROWN)
	ing.name = "Ingredientes"
	await K.look_at(ab)
	await K.frames(6)
	await K.shot("01_troquel")
	# Cambiar la profundidad de la extrusión: se nota en pantalla
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var rr := Rect2(xf * (ab.global_position + Vector2(500, 360)), (Vector2(420, 110) * xf.get_scale())).abs()
	var region := Rect2i(rr)
	await RenderingServer.frame_post_draw
	var s0 := region_sig(root.get_texture().get_image(), region)
	var fx: Array = (api.get_prop(brand, "effects") as Array).duplicate(true)
	for e in fx:
		if String(e.get("type", "")).to_lower().begins_with("extru"):
			e["depth"] = 40.0
	api.set_prop(brand, "effects", fx)
	await K.frames(6)
	await RenderingServer.frame_post_draw
	var s1 := region_sig(root.get_texture().get_image(), region)
	K.check("más profundidad de extrusión cambia lo que se ve", absf(s1 - s0) > 1.0, "%.1f → %.1f" % [s0, s1])
	api.undo()
	# Editar el texto de origen del eslogan: el texto en curva se rehace
	var src: Node = K.ic.path_text_source(slogan)
	var sig0: String = str(slogan.get_meta("brush_obj"))
	if src:
		api.set_prop(src, "text", "Hecho con calma en Bioko")
	await K.frames(6)
	var shape_n := 0
	for ch in slogan.get_children():
		shape_n += 1
	K.check("editar el texto de origen rehace el texto en curva", src != null and String(api.get_prop(slogan, "path_text_content")) == "Hecho con calma en Bioko",
		str(api.get_prop(slogan, "path_text_content")))
	var fxn0: int = brand.find_children("*", "", true, false).size()
	await K.undo_redo(20)
	var fxn1: int = brand.find_children("*", "", true, false).size()
	K.check("los efectos de la marca no acumulan nodos al deshacer/rehacer", fxn1 <= fxn0 + 2, "%d → %d" % [fxn0, fxn1])
	# Exportar
	var exd: Dictionary = await K.export_all(ab, "troquel")
	if exd.has("svg"):
		var svg := FileAccess.get_file_as_string(exd["svg"])
		K.check("SVG: líneas de plegado discontinuas y textos en curva", svg.contains("stroke-dasharray") and svg.count("<path") > 40, "%d paths" % svg.count("<path"))
	var abs: Array = await K.save_reload("troquel")
	for a in abs:
		if String(a.name) == "Troquel":
			var b2: Node = a.find_child("Marca", true, false)
			K.check("reabrir: sin nodos fantasma dentro del texto (VAL-48)", b2 != null and b2.get_children().filter(func(ch) -> bool: return ch.has_meta("shape_type")).is_empty())
			K.check("reabrir: la marca conserva extrusión y bisel", b2 != null and (api.get_prop(b2, "effects") as Array).size() == 2)
			var tl := 0
			for ch in a.find_children("*", "Line2D", true, false):
				if ch.has_meta("brush_ref"):
					tl += 1
			K.check("reabrir: los 3 textos en curva", tl == 3, str(tl))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
