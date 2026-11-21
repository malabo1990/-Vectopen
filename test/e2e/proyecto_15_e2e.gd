# =============================================================================
# FASE B · ENCARGO 15 — Mapa estilizado (modo Pro)
# Foco: trazos cerrados, capas anidadas.
# Isla imaginaria 1200 × 900: costa (Bézier cerrada), 3 regiones con 2–3
# comarcas cada una (polígonos cerrados) en grupos ANIDADOS
# (Mapa ▸ Regiones ▸ Región ▸ Comarca), ríos (trazados abiertos), carreteras
# con guiones, ciudades y rótulos. Unir dos comarcas (booleana), ocultar una
# región entera desde el grupo, bloquear el mar y comprobar que un CLIC real
# no lo selecciona, renombrar capas, exportar SVG/PDF, guardar/reabrir con
# la misma profundidad de anidado.
#   test/run_e2e.sh proyecto_15_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/15"
const SEA := Color("#a8d5e2")
const LAND := [Color("#cfe1b9"), Color("#e9d8a6"), Color("#f4c095")]
var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(500.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func click(gp: Vector2) -> void:
	var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * gp
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	mm.global_position = sp
	_send(mm)
	await K.frames(3)
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = sp
		mb.global_position = sp
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(mb)
		await K.frames(2)

func depth(n: Node, ab: Node) -> int:
	var d := 0
	var best := 0
	for c in n.get_children():
		if c is Node2D:
			best = maxi(best, depth(c, ab))
	if String(n.get_meta("shape_type", "")) == "group":
		d = 1
	return d + best

func poly(pts: Array, name: String, col: Color) -> Node2D:
	var n = api.add_shape(PackedVector2Array(pts), name)
	api.set_props(n, {"fill_color": col, "stroke_color": Color("#5c5c5c"), "stroke_width": 1.5})
	return n

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("professional"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1200, 900), "Mapa", SEA)
	var sea = api.add_rect(Vector2(600, 450), Vector2(1200, 900), 0.0, "Mar")
	api.set_props(sea, {"fill_color": SEA, "stroke_width": 0.0})
	# Costa: Bézier cerrada
	var c := Curve2D.new()
	var coast := [[Vector2(250, 300), Vector2(0, 80), Vector2(0, -80)], [Vector2(520, 140), Vector2(-120, 0), Vector2(160, -20)],
		[Vector2(950, 260), Vector2(-40, -90), Vector2(40, 120)], [Vector2(880, 700), Vector2(120, -40), Vector2(-160, 60)],
		[Vector2(420, 760), Vector2(140, 20), Vector2(-150, -20)]]
	for e in coast:
		c.add_point(e[0], e[1], e[2])
	c.add_point(coast[0][0], coast[0][1], Vector2.ZERO)
	var shore = api.add_curve(c, true, "Costa")
	api.set_props(shore, {"fill_color": Color("#f6f2e6"), "stroke_color": Color("#3d5a80"), "stroke_width": 3.0})
	K.check("costa: Bézier cerrada", bool(shore.get("closed")))
	# Regiones con comarcas (polígonos cerrados), anidadas
	var regions_spec := [
		["Norte", [[[330, 260], [520, 190], [560, 330], [380, 380]], [[520, 190], [760, 220], [700, 360], [560, 330]]]],
		["Este", [[[760, 220], [900, 290], [860, 480], [700, 360]], [[700, 360], [860, 480], [780, 600], [640, 520]], [[860, 480], [870, 640], [780, 600]]]],
		["Sur", [[[380, 380], [560, 330], [640, 520], [460, 640]], [[460, 640], [640, 520], [780, 600], [560, 720]]]],
	]
	var region_groups: Array = []
	for ri in regions_spec.size():
		var comarcas: Array = []
		var spec: Array = regions_spec[ri][1]
		for ci in spec.size():
			var pts := []
			for q in spec[ci]:
				pts.append(Vector2(q[0], q[1]))
			comarcas.append(poly(pts, "%s %d" % [regions_spec[ri][0], ci + 1], (LAND[ri] as Color).darkened(ci * 0.06)))
		region_groups.append(api.group(comarcas, "Región %s" % regions_spec[ri][0]))
	var all_regions = api.group(region_groups, "Regiones")
	# Ríos y carreteras
	var rivers: Array = []
	for i in 3:
		var rc := Curve2D.new()
		rc.add_point(Vector2(450 + i * 150, 220 + i * 30), Vector2.ZERO, Vector2(40, 80))
		rc.add_point(Vector2(500 + i * 140, 520 + i * 40), Vector2(-60, -60), Vector2(30, 60))
		rc.add_point(Vector2(470 + i * 160, 740), Vector2(0, -50), Vector2.ZERO)
		var r = api.add_curve(rc, false, "Río %d" % (i + 1))
		api.set_props(r, {"stroke_color": Color("#3d85c6"), "stroke_width": 3.0 - i * 0.5})
		rivers.append(r)
	var road = api.add_path(PackedVector2Array([Vector2(300, 320), Vector2(520, 420), Vector2(760, 400), Vector2(840, 620)]), false, "Carretera")
	api.set_props(road, {"stroke_color": Color("#c0392b"), "stroke_width": 2.5, "stroke_style": 1, "stroke_dash_len": 10.0, "stroke_dash_gap": 6.0})
	var cities: Array = []
	for p in [Vector2(520, 420), Vector2(760, 400), Vector2(560, 640)]:
		var city = api.add_ellipse(p, Vector2(14, 14), "Ciudad")
		api.set_props(city, {"fill_color": Color("#222"), "stroke_color": Color.WHITE, "stroke_width": 2.0})
		cities.append(city)
	var labels: Array = []
	for e in [["Puerto Bata", Vector2(530, 400)], ["Riaba", Vector2(770, 380)], ["Luba", Vector2(570, 620)]]:
		var t = api.add_text(e[1], e[0], 18, Color("#222"))
		t.name = "Rótulo %s" % e[0]
		labels.append(t)
	var water = api.group(rivers, "Hidrografía")
	var towns = api.group(cities + labels, "Poblaciones")
	var map = api.group([shore, all_regions, water, road, towns], "Mapa")
	await K.frames(4)
	var d := depth(map, ab)
	K.check("anidado de 3 niveles (Mapa ▸ Regiones ▸ Región)", d >= 3, str(d))
	# Booleana: unir las dos comarcas del Sur
	var south: Node2D = region_groups[2]
	var kids: Array = south.get_children().filter(func(n) -> bool: return n is VectorShape)
	var merged = api.boolean("union", kids)
	K.check("unir las dos comarcas del Sur en una", merged != null and south.get_children().filter(func(n) -> bool: return n is Node2D).size() == 1,
		str(south.get_children().size()))
	# Ocultar la región Este desde su grupo
	api.set_prop(region_groups[1], "visible", false)
	await K.frames(2)
	K.check("ocultar la región Este (grupo) oculta sus comarcas", region_groups[1].get_children().all(func(n) -> bool: return not (n as CanvasItem).is_visible_in_tree()))
	api.set_prop(region_groups[1], "visible", true)
	# Renombrar
	api.set_prop(region_groups[0], "name", "Región Septentrional")
	K.check("renombrar una región", String(region_groups[0].name) == "Región Septentrional")
	# Bloquear el mar: un clic real en el mar no lo selecciona
	sea.set_meta("locked", true)
	K.canvas.switch_tool("move")
	await K.look_at(ab)
	K.sm.clear()
	await K.frames(2)
	# VAL-46: la página está activa y SELECCIONADA; los clics sobre objetos
	# deben ir a los objetos, no arrastrar la página.
	K.check("la página activa está seleccionada antes de los clics", ab.is_selected)
	var ab_pos := ab.position
	await click(ab.global_position + Vector2(80, 80))
	K.check("clic en el mar bloqueado: no se selecciona", not K.sm.is_selected(sea), str(K.sm.get_selected()))
	await K.frames(40)   # que no cuente como doble clic
	await click(ab.global_position + Vector2(860, 300))   # comarca del Este
	K.check("la página no se ha movido", ab.position.is_equal_approx(ab_pos))
	var picked: Array = K.sm.get_selected()
	K.check("clic en una comarca selecciona algo del mapa", not picked.is_empty() and map.is_ancestor_of(picked[0]) or (not picked.is_empty() and picked[0] == map), str(picked))
	K.sm.clear()
	await K.frames(4)
	await K.shot("01_mapa")
	await K.undo_redo(20)
	# Exportar
	var ex: Dictionary = await K.export_all(ab, "mapa")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG: comarcas, ríos y carretera con guiones", svg.count("<path") >= 12 and svg.contains("stroke-dasharray"), "%d paths" % svg.count("<path"))
	var abs: Array = await K.save_reload("mapa")
	for a in abs:
		if String(a.name) == "Mapa":
			var m2: Node = a.find_child("Mapa", false, false)
			K.check("reabrir: misma profundidad de anidado", m2 != null and depth(m2, a) == d, "%d vs %d" % [depth(m2, a) if m2 else -1, d])
			var s2: Node = a.find_child("Mar", false, false)
			K.check("reabrir: el mar sigue bloqueado", s2 != null and bool(s2.get_meta("locked", false)))
			var rd: Node = a.find_child("Carretera", true, false)
			K.check("reabrir: la carretera conserva los guiones", rd != null and float(api.get_prop(rd, "stroke_dash_len")) > 0.0)
			await K.look_at(a)
			await K.shot("02_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
