# =============================================================================
# FASE B · ENCARGO 17 — Portada de álbum (modo Modern)
# Foco: degradados, texto en curva.
# Portada cuadrada 1500 × 1500: fondo con degradado lineal de 3 paradas,
# sol con degradado radial, anillo con degradado cónico y trazo con
# degradado, título siguiendo un arco (texto en trazado), artista con
# degradado en el texto, grano (filtro). Editar una parada del degradado
# (deshacer), exportar PNG a 3000 px (plataformas), JPG, SVG con los
# degradados y PDF, reabrir sin perder degradados ni el texto en curva.
#   test/run_e2e.sh proyecto_17_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/17"
const S := 1500.0
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func arc_path(c: Vector2, r: float, name: String) -> Node2D:
	var cv := Curve2D.new()
	var k := r * 0.5523
	cv.add_point(c + Vector2(-r, 0), Vector2.ZERO, Vector2(0, -k))
	cv.add_point(c + Vector2(0, -r), Vector2(-k, 0), Vector2(k, 0))
	cv.add_point(c + Vector2(r, 0), Vector2(0, -k), Vector2.ZERO)
	var p = api.add_curve(cv, false, name)
	api.set_props(p, {"stroke_width": 0.0})
	return p

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("modern"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(S, S), "Portada", Color.BLACK)
	var bg = api.add_rect(Vector2(S / 2, S / 2), Vector2(S, S), 0.0, "Fondo")
	api.set_prop(bg, "stroke_width", 0.0)
	api.set_prop(bg, "fill_paint", {"type": "linear", "angle": PI / 2.0,
		"stops": [[0.0, Color("#1d1145")], [0.55, Color("#a2264d")], [1.0, Color("#f9a03f")]]})
	var sun = api.add_ellipse(Vector2(S / 2, 900), Vector2(700, 700), "Sol")
	api.set_prop(sun, "stroke_width", 0.0)
	api.set_prop(sun, "fill_paint", {"type": "radial", "stops": [[0.0, Color("#fff4c2")], [0.7, Color("#ffb347")], [1.0, Color(1, 0.5, 0.2, 0.0)]]})
	var ring = api.add_ellipse(Vector2(S / 2, 900), Vector2(980, 980), "Anillo")
	api.set_props(ring, {"shape_mode": "donut", "inner_radius_ratio": 0.93, "stroke_width": 6.0})
	api.set_prop(ring, "fill_paint", {"type": "conic", "center": Vector2(0.5, 0.5), "angle": 0.0,
		"stops": [[0.0, Color("#7bdff2")], [0.5, Color("#f2b5d4")], [1.0, Color("#7bdff2")]]})
	api.set_prop(ring, "stroke_paint", {"type": "linear", "angle": 0.0, "stops": [[0.0, Color.WHITE], [1.0, Color(1, 1, 1, 0.1)]]})
	var p_bg = api.get_prop(bg, "fill_paint")
	var p_sun = api.get_prop(sun, "fill_paint")
	var p_ring = api.get_prop(ring, "fill_paint")
	K.check("fondo: degradado lineal de 3 paradas", p_bg is Dictionary and String(p_bg.get("type")) == "linear", str(p_bg.get("type")) if p_bg is Dictionary else str(p_bg))
	K.check("sol: degradado radial", p_sun is Dictionary and String(p_sun.get("type")) == "radial")
	K.check("anillo: degradado cónico", p_ring is Dictionary and String(p_ring.get("type")) == "conic")
	var sp = api.get_prop(ring, "stroke_paint")
	K.check("anillo: trazo con degradado", sp is Dictionary and String(sp.get("type", "solid")) != "solid", str(sp))
	# Título en curva
	var arc = arc_path(Vector2(S / 2, 900), 560.0, "Arco título")
	var title: Line2D = await K.text_on_path("ECUADOR NOCTURNO", 96, Color.WHITE, arc, {"align": 0.5, "tracking": 0.12})
	K.check("título siguiendo el arco (texto en trazado)", title != null and title.has_meta("brush_ref"))
	# Artista con degradado en el texto
	var artist = api.add_text(Vector2(420, 1300), "MALABO SOUND", 110, Color.WHITE)
	artist.name = "Artista"
	api.set_prop(artist, "font_weight", 800)
	api.set_prop(artist, "fill_paint", {"type": "linear", "angle": 0.0, "stops": [[0.0, Color("#f9a03f")], [1.0, Color("#f2b5d4")]]})
	var ap = api.get_prop(artist, "fill_paint")
	K.check("texto del artista con degradado", ap is Dictionary and String(ap.get("type", "solid")) == "linear", str(ap.get("type", "?")) if ap is Dictionary else str(ap))
	# Grano
	var f: Dictionary = api.add_filter(bg, "grain", {"amount": 0.12})
	K.check("grano sobre el fondo", not f.is_empty())
	# Editar una parada y deshacer
	var stops0: Array = (p_bg as Dictionary).get("stops", [])
	var stops1: Array = stops0.duplicate(true)
	if stops1.size() >= 2:
		stops1[1] = [0.4, Color("#3a86ff")]
	api.set_prop(bg, "fill_paint", {"type": "linear", "angle": PI / 2.0, "stops": stops1})
	var mid = (api.get_prop(bg, "fill_paint") as Dictionary).get("stops", [])
	K.check("editar la parada central del degradado", mid.size() == 3 and (mid[1][1] as Color).is_equal_approx(Color("#3a86ff")), str(mid))
	api.undo()
	var mid2 = (api.get_prop(bg, "fill_paint") as Dictionary).get("stops", [])
	K.check("deshacer la parada", mid2.size() == 3 and (mid2[1][1] as Color).is_equal_approx(Color("#a2264d")), str(mid2))
	await K.look_at(ab)
	await K.shot("01_portada")
	# Exportar para plataformas
	var png := ProjectSettings.globalize_path(OUT.path_join("portada_3000.png"))
	var t0 := Time.get_ticks_msec()
	var ok: bool = await api.export(png, ab, {"scale": 2.0})
	var img := Image.load_from_file(png) if ok else null
	K.check("PNG 3000 × 3000 para plataformas", img != null and img.get_size() == Vector2i(3000, 3000), "%s · %d ms" % [str(img.get_size()) if img else "-", Time.get_ticks_msec() - t0])
	if img:
		var top := img.get_pixel(1500, 40)
		var bottom := img.get_pixel(1500, 2960)
		K.check("el PNG muestra el degradado (arriba oscuro, abajo cálido)", top.get_luminance() < 0.25 and bottom.r > 0.6, "%s / %s" % [top, bottom])
	await K.frames(30)
	var ex: Dictionary = await K.export_all(ab, "portada")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con degradados lineal y radial", svg.contains("<linearGradient") and svg.contains("<radialGradient"),
			"%d lineales · %d radiales" % [svg.count("<linearGradient"), svg.count("<radialGradient")])
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("portada")
	for a in abs:
		if String(a.name) == "Portada":
			var b2: Node = a.find_child("Fondo", false, false)
			var r2: Node = a.find_child("Anillo", false, false)
			var t2: Node = a.find_child("Artista", true, false)
			K.check("reabrir: degradado del fondo con 3 paradas", b2 != null and ((api.get_prop(b2, "fill_paint") as Dictionary).get("stops", []) as Array).size() == 3)
			K.check("reabrir: degradado cónico del anillo", r2 != null and String((api.get_prop(r2, "fill_paint") as Dictionary).get("type")) == "conic")
			K.check("reabrir: degradado del texto", t2 != null and String((api.get_prop(t2, "fill_paint") as Dictionary).get("type", "solid")) == "linear")
			var tl := 0
			for c in a.find_children("*", "Line2D", true, false):
				if c.has_meta("brush_ref"):
					tl += 1
			K.check("reabrir: el título sigue en el arco", tl == 1, str(tl))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
