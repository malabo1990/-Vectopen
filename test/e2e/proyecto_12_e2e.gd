# =============================================================================
# FASE B · ENCARGO 12 — Set de 24 iconos de línea (modo Smart)
# Foco: trazo coherente, exportar cada icono en SVG suelto.
# Rejilla de 6 × 4 iconos de 48 px sobre una página de 576 × 384: casa,
# lupa, corazón, campana, nube, sobre, calendario, candado… hechos con
# trazados Bézier, elipses y rectángulos sin relleno. Seleccionar TODO y poner
# en una sola acción grosor 2 px, extremos y uniones redondas (deshacer = un
# paso). Exportar cada icono como SVG individual (recortado a su caja de
# 48 px), comprobar viewBox, grosor y que se reimporta igual; PNG del set;
# guardar / reabrir.
#   test/run_e2e.sh proyecto_12_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/12"
const INK := Color("#1f2430")
const CELL := 96.0
const ICON := 48.0
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

# ── primitivas de línea (coordenadas en una caja de 48 con origen en `o`) ───
var _parts: Array = []

func line(o: Vector2, pts: Array, closed := false) -> void:
	var pv := PackedVector2Array()
	for p in pts:
		pv.append(o + p)
	var n = api.add_path(pv, closed, "Trazo")
	_parts.append(n)

func curve(o: Vector2, pts: Array, closed := false) -> void:
	## pts: [[punto, tirador_in, tirador_out], …]
	var c := Curve2D.new()
	for e in pts:
		c.add_point(o + e[0], e[1], e[2])
	_parts.append(api.add_curve(c, closed, "Curva"))

func circle(o: Vector2, c: Vector2, r: float) -> void:
	_parts.append(api.add_ellipse(o + c, Vector2(r * 2, r * 2), "Círculo"))

func rect(o: Vector2, c: Vector2, s: Vector2, rad := 4.0) -> void:
	_parts.append(api.add_rect(o + c, s, rad, "Caja"))

func make_icon(i: int, name: String, draw: Callable) -> Node2D:
	var o := Vector2((i % 6) * CELL + (CELL - ICON) / 2.0, (i / 6) * CELL + (CELL - ICON) / 2.0)
	_parts = []
	draw.call(o)
	var g = api.group(_parts, name)
	return g

func star_pts() -> Array:
	var p := []
	for j in 11:
		p.append(Vector2(24, 25) + Vector2.from_angle(-PI / 2 + j * PI / 5) * (16.0 if j % 2 == 0 else 7.0))
	return p

func icons_spec() -> Array:
	return [
		["casa", func(o): line(o, [Vector2(6, 22), Vector2(24, 7), Vector2(42, 22)]); line(o, [Vector2(11, 18), Vector2(11, 41), Vector2(37, 41), Vector2(37, 18)]); rect(o, Vector2(24, 33), Vector2(8, 16), 1.0)],
		["lupa", func(o): circle(o, Vector2(21, 21), 13); line(o, [Vector2(31, 31), Vector2(42, 42)])],
		["corazon", func(o): curve(o, [[Vector2(24, 41), Vector2.ZERO, Vector2(-14, -10)], [Vector2(8, 17), Vector2(0, 8), Vector2(0, -9)], [Vector2(24, 15), Vector2(-6, -9), Vector2(6, -9)], [Vector2(40, 17), Vector2(0, -9), Vector2(0, 8)], [Vector2(24, 41), Vector2(14, -10), Vector2.ZERO]])],
		["campana", func(o): curve(o, [[Vector2(10, 35), Vector2.ZERO, Vector2(4, -4)], [Vector2(14, 20), Vector2(0, 6), Vector2(0, -8)], [Vector2(24, 9), Vector2(-7, 0), Vector2(7, 0)], [Vector2(34, 20), Vector2(0, -8), Vector2(0, 6)], [Vector2(38, 35), Vector2(-4, -4), Vector2.ZERO]]); line(o, [Vector2(8, 35), Vector2(40, 35)]); line(o, [Vector2(20, 41), Vector2(28, 41)])],
		["nube", func(o): curve(o, [[Vector2(12, 36), Vector2.ZERO, Vector2(-7, 0)], [Vector2(8, 27), Vector2(0, 6), Vector2(0, -6)], [Vector2(17, 20), Vector2(-5, 0), Vector2(2, -8)], [Vector2(30, 14), Vector2(-8, 0), Vector2(8, 0)], [Vector2(38, 24), Vector2(0, -6), Vector2(5, 1)], [Vector2(36, 36), Vector2(6, 0), Vector2.ZERO]], false); line(o, [Vector2(12, 36), Vector2(36, 36)])],
		["sobre", func(o): rect(o, Vector2(24, 24), Vector2(36, 26), 3.0); line(o, [Vector2(7, 13), Vector2(24, 26), Vector2(41, 13)])],
		["calendario", func(o): rect(o, Vector2(24, 26), Vector2(34, 30), 4.0); line(o, [Vector2(7, 19), Vector2(41, 19)]); line(o, [Vector2(16, 7), Vector2(16, 14)]); line(o, [Vector2(32, 7), Vector2(32, 14)])],
		["candado", func(o): rect(o, Vector2(24, 31), Vector2(28, 20), 4.0); curve(o, [[Vector2(16, 21), Vector2.ZERO, Vector2(0, -12)], [Vector2(32, 21), Vector2(0, -12), Vector2.ZERO]])],
		["usuario", func(o): circle(o, Vector2(24, 16), 8); curve(o, [[Vector2(9, 42), Vector2.ZERO, Vector2(0, -14)], [Vector2(39, 42), Vector2(0, -14), Vector2.ZERO]])],
		["ajustes", func(o): circle(o, Vector2(24, 24), 6); circle(o, Vector2(24, 24), 15)],
		["mas", func(o): line(o, [Vector2(24, 9), Vector2(24, 39)]); line(o, [Vector2(9, 24), Vector2(39, 24)])],
		["cerrar", func(o): line(o, [Vector2(12, 12), Vector2(36, 36)]); line(o, [Vector2(36, 12), Vector2(12, 36)])],
		["check", func(o): line(o, [Vector2(9, 25), Vector2(19, 35), Vector2(39, 13)])],
		["flecha", func(o): line(o, [Vector2(8, 24), Vector2(40, 24)]); line(o, [Vector2(28, 12), Vector2(40, 24), Vector2(28, 36)])],
		["descarga", func(o): line(o, [Vector2(24, 7), Vector2(24, 31)]); line(o, [Vector2(14, 22), Vector2(24, 32), Vector2(34, 22)]); line(o, [Vector2(9, 40), Vector2(39, 40)])],
		["camara", func(o): rect(o, Vector2(24, 27), Vector2(36, 24), 4.0); circle(o, Vector2(24, 27), 7); line(o, [Vector2(17, 15), Vector2(20, 10), Vector2(28, 10), Vector2(31, 15)])],
		["reloj", func(o): circle(o, Vector2(24, 24), 16); line(o, [Vector2(24, 14), Vector2(24, 24), Vector2(31, 29)])],
		["estrella", func(o): line(o, star_pts())],
		["papelera", func(o): line(o, [Vector2(9, 13), Vector2(39, 13)]); line(o, [Vector2(13, 13), Vector2(15, 41), Vector2(33, 41), Vector2(35, 13)]); line(o, [Vector2(19, 13), Vector2(20, 8), Vector2(28, 8), Vector2(29, 13)])],
		["lapiz", func(o): line(o, [Vector2(10, 38), Vector2(12, 30), Vector2(32, 10), Vector2(38, 16), Vector2(18, 36), Vector2(10, 38)])],
		["carrito", func(o): line(o, [Vector2(6, 9), Vector2(12, 9), Vector2(17, 31), Vector2(37, 31), Vector2(41, 15), Vector2(14, 15)]); circle(o, Vector2(19, 39), 3); circle(o, Vector2(35, 39), 3)],
		["mapa", func(o): curve(o, [[Vector2(24, 42), Vector2.ZERO, Vector2(-10, -12)], [Vector2(12, 19), Vector2(0, 8), Vector2(0, -7)], [Vector2(24, 7), Vector2(-7, 0), Vector2(7, 0)], [Vector2(36, 19), Vector2(0, -7), Vector2(0, 8)], [Vector2(24, 42), Vector2(10, -12), Vector2.ZERO]]); circle(o, Vector2(24, 19), 4)],
		["telefono", func(o): rect(o, Vector2(24, 24), Vector2(22, 36), 5.0); line(o, [Vector2(21, 37), Vector2(27, 37)])],
		["compartir", func(o): circle(o, Vector2(34, 12), 4); circle(o, Vector2(14, 24), 4); circle(o, Vector2(34, 36), 4); line(o, [Vector2(30, 14), Vector2(18, 22)]); line(o, [Vector2(18, 26), Vector2(30, 34)])],
	]

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("smart"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(CELL * 6, CELL * 4), "Iconos", Color.WHITE)
	var icons: Array = []
	var spec := icons_spec()
	K.check("24 iconos en la especificación", spec.size() == 24, str(spec.size()))
	for i in spec.size():
		icons.append(make_icon(i, String(spec[i][0]), spec[i][1]))
	await K.frames(4)
	K.check("24 iconos agrupados", icons.filter(func(g): return g != null).size() == 24)
	# Todas las piezas: sin relleno y estilo de trazo común en UNA acción
	var parts: Array = []
	for g in icons:
		for c in g.get_children():
			if c is Node2D:
				parts.append(c)
	K.sm.set_selection(parts)
	await K.frames(2)
	var fills0 := parts.map(func(p) -> Color: return api.get_prop(p, "fill_color"))
	K.ic.apply_multi({"fill_color": Color(0, 0, 0, 0), "stroke_color": INK, "stroke_width": 2.0,
		"stroke_cap_start": 1, "stroke_cap_end": 1, "stroke_join": 1}, "Estilo de icono")
	await K.frames(3)
	var widths := {}
	for p in parts:
		widths[snappedf(float(api.get_prop(p, "stroke_width")), 0.01)] = true
	K.check("grosor idéntico (2 px) en las %d piezas" % parts.size(), widths.keys() == [2.0], str(widths.keys()))
	K.hm.undo()
	await K.frames(2)
	var diff := 0
	for i in parts.size():
		if not (api.get_prop(parts[i], "fill_color") as Color).is_equal_approx(fills0[i]):
			diff += 1
	K.check("deshacer el estilo común = un paso (rellenos como antes)", diff == 0, "%d distintos" % diff)
	K.hm.redo()
	await K.frames(2)
	K.sm.clear()
	await K.look_at(ab)
	await K.shot("01_set")
	# ── Exportar cada icono como SVG suelto ──────────────────────────────────
	var ok_n := 0
	var bad: Array = []
	for g in icons:
		var path := ProjectSettings.globalize_path(OUT.path_join("icon_%s.svg" % g.name))
		var err: Error = await K.IEM.export_nodes(ab, [g], "SVG", path)
		var svg := FileAccess.get_file_as_string(path) if err == OK else ""
		var vb := RegEx.create_from_string('viewBox="([0-9.\\- ]+)"').search(svg)
		var dims := (vb.get_string(1).split(" ") if vb else PackedStringArray())
		var w := float(dims[2]) if dims.size() == 4 else 0.0
		var h := float(dims[3]) if dims.size() == 4 else 0.0
		var fine := err == OK and w > 8.0 and w <= ICON + 4.0 and h <= ICON + 4.0 and svg.contains('stroke-width="2"') \
			and svg.contains('stroke-linejoin="round"') and not svg.contains("Artboard")
		if fine:
			ok_n += 1
		else:
			bad.append("%s(%s %.0fx%.0f)" % [g.name, error_string(err), w, h])
	K.check("24 SVG sueltos: recortados al icono (≤ 52 px), trazo 2 px y uniones redondas", ok_n == 24, ", ".join(bad))
	# Reimportar uno: mismo número de piezas
	var lupa_svg := ProjectSettings.globalize_path(OUT.path_join("icon_lupa.svg"))
	var tmp: Node2D = api.add_artboard(Vector2(200, 200), "Reimport")
	await K.frames(2)
	var res: Dictionary = K.IEM.import_any(lupa_svg, tmp)
	await K.frames(6)
	K.check("reimportar icon_lupa.svg: 2 piezas", res.get("ok", false) and K.count_shapes(tmp) >= 2, str(K.count_shapes(tmp)))
	# PNG del set completo a 2×
	var png := ProjectSettings.globalize_path(OUT.path_join("set@2x.png"))
	var okp: bool = await api.export(png, ab, {"scale": 2.0})
	var img := Image.load_from_file(png) if okp else null
	K.check("PNG del set a 2×: 1152 × 768", img != null and img.get_size() == Vector2i(1152, 768), str(img.get_size()) if img else "-")
	await K.frames(30)   # la exportación a imagen libera sus copias temporales
	await K.undo_redo(20)
	var abs: Array = await K.save_reload("iconos")
	for a in abs:
		if String(a.name) == "Iconos":
			var gs: Array = a.get_children().filter(func(c) -> bool: return String(c.get_meta("shape_type", "")) == "group")
			K.check("reabrir: 24 grupos", gs.size() == 24, str(gs.size()))
			var w2 := {}
			for g in gs:
				for c in g.get_children():
					if c is Node2D:
						w2[snappedf(float(api.get_prop(c, "stroke_width")), 0.01)] = true
			K.check("reabrir: grosor sigue en 2 px", w2.keys() == [2.0], str(w2.keys()))
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
