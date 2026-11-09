# =============================================================================
# TEXTO EN TRAZADO — interfaz (fallos que vio el usuario):
#  · en una curva en S las letras deben APOYARSE en el trazo (su línea base,
#    no el pie de la «p») y conservar su separación: ni separadas al
#    principio ni amontonadas al final; no debe faltar ninguna letra;
#  · el inspector (Modern y Pro) cambia texto, tamaño, espaciado, inicio y final;
#  · tiradores en el lienzo: ▶ inicio, ◀ final y ◆ deslizar, con el ratón,
#    y deshacer.
#   test/run_e2e.sh text_path_ui_e2e
# =============================================================================
extends SceneTree

const OUT := "user://text_path_ui"
const OB = preload("res://script_gdscript/shapes/object_brush.gd")
const R = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
const TPH = preload("res://script_gdscript/tools/move/text_path_handles.gd")
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(400.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func move(at: Vector2, held: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	await process_frame

func btn(at: Vector2, down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = at
	mb.global_position = at
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(mb)
	await process_frame

func to_screen(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

func zoom() -> float:
	return canvas.get_viewport().get_canvas_transform().get_scale().x

## Arrastra con el ratón de un punto global a otro (en pasos).
func drag(from_g: Vector2, to_g: Vector2) -> void:
	var a := to_screen(from_g)
	var b := to_screen(to_g)
	await move(a, false)
	await btn(a, true)
	for i in range(1, 11):
		await move(a.lerp(b, i / 10.0), true)
	await btn(b, false)
	await frames(3)

func prm(l: Line2D) -> Dictionary:
	return (l.get_meta("brush_obj", {}) as Dictionary).get("params", {})

func dist_to_path(q: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	for k in path.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, path[k], path[k + 1]).distance_to(q))
	return best

## Letras colocadas: [{base (punto de la línea base bajo su centro), s}].
func glyphs(l: Line2D) -> Array:
	var ax: Array = R.centerline(l)
	var pts: PackedVector2Array = ax[0]
	var half: PackedFloat32Array = ax[1]
	var bo: Dictionary = l.get_meta("brush_obj", {})
	var src: Array = OB.from_data(bo["src"])
	var pr := OB.DEFAULTS.duplicate()
	pr.merge(bo["params"], true)
	var t: Dictionary = OB._to_tile(src[0])
	var asp := float(t["aspect"])
	var ctx: Dictionary = OB._pattern_ctx(pts, half, [asp], pr)
	var out: Array = []
	for grp in OB._rigid_groups(ctx, t["polys"], asp, pr):
		var xf: Transform2D = OB._glyph_xf(ctx, 0, grp, asp)
		var uc := (float(grp["u0"]) + float(grp["u1"])) * 0.5
		out.append({"base": xf * Vector2(uc, -float(ctx["vshift"])), "u": uc + float(grp["du"]), "hu": xf.x.length()})
	return out

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var gui = root.get_node("GlobalUI")
	gui.set_ui_mode("smart")
	await frames(20)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var sm = root.get_node("SelectionManager")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	cam.zoom = Vector2.ONE
	cam.position = ab.global_position + ac
	await frames(6)

	# ── 1. Curva en S como la del usuario: arco, valle y subida ──
	var txt = api.add_text(ac + Vector2(-300, -200), "Título Corporativo", 48, Color(0.08, 0.08, 0.1))
	var c := Curve2D.new()
	c.add_point(ac + Vector2(-330, 60), Vector2.ZERO, Vector2(30, -120))
	c.add_point(ac + Vector2(-140, -30), Vector2(-90, 0), Vector2(90, 0))
	c.add_point(ac + Vector2(-60, 40), Vector2(-20, -40), Vector2(20, 40))
	c.add_point(ac + Vector2(140, 110), Vector2(-160, -30), Vector2(160, 30))
	c.add_point(ac + Vector2(330, -160), Vector2(-20, 120), Vector2.ZERO)
	var path = api.add_curve(c, false, "Onda S")
	path.stroke_width = 2.0
	await frames(6)
	var l: Line2D = api.text_on_path(txt, path)
	await frames(8)
	check("se crea el texto en trazado", l != null)
	if l == null:
		quit(1)
		return
	var gl := glyphs(l)
	check("están todas las letras (17, sin contar el espacio)", gl.size() == 17, str(gl.size()))
	var axis: PackedVector2Array = R.centerline(l)[0]
	var worst := 0.0
	for g in gl:
		worst = maxf(worst, dist_to_path(g["base"], axis))
	check("cada letra se apoya en el trazo por su línea base (≤ 1 px)", worst <= 1.0, "%.2f px" % worst)
	# separación: la distancia por la curva entre letras = la del texto recto
	var bad := 0.0
	for i in range(1, gl.size()):
		var want := (float(gl[i]["u"]) - float(gl[i - 1]["u"])) * float(gl[i]["hu"])
		var got := _arc_between(axis, gl[i - 1]["base"], gl[i]["base"])
		bad = maxf(bad, absf(got - want) / maxf(want, 1.0))
	check("separación entre letras igual en toda la curva (≤ 4 %)", bad <= 0.04, "%.1f %%" % (bad * 100.0))
	await shot("1_curva_s.png")

	# ── 2. Inspector (Modern): filas y cambios con deshacer ──
	gui.set_ui_mode("modern")
	await frames(30)
	sm.select(l)
	await frames(8)
	for key in ["path_text_content", "path_text_size", "path_text_spacing", "path_text_start", "path_text_end"]:
		check("Modern: el inspector muestra «%s»" % key, _row_visible(key))
	var w0 := l.width
	ic.apply("path_text_size", 72.0)
	await frames(6)
	check("tamaño de letra: el texto crece", l.width > w0 * 1.3, "%.1f → %.1f" % [w0, l.width])
	hm.undo()
	await frames(6)
	check("deshacer devuelve el tamaño", absf(l.width - w0) < 0.5, "%.1f" % l.width)
	var span0: Dictionary = TPH.layout(l)
	ic.apply("path_text_spacing", 0.3)
	await frames(4)
	var span1: Dictionary = TPH.layout(l)
	var len0: float = span0["span"].y - span0["span"].x
	var len1: float = span1["span"].y - span1["span"].x
	check("espaciado: el texto ocupa más trazado", len1 > len0 * 1.2, "%.0f → %.0f" % [len0, len1])
	hm.undo()
	await frames(4)
	ic.apply("path_text_content", "Hola mundo")
	await frames(6)
	check("cambiar el texto desde el inspector", glyphs(l).size() == 9, str(glyphs(l).size()))
	hm.undo()
	await frames(6)
	check("deshacer devuelve el texto", glyphs(l).size() == 17)
	ic.apply("path_text_start", 0.4)
	await frames(4)
	var lay: Dictionary = TPH.layout(l)
	check("«Empieza en» 40 %: el texto arranca ahí", absf(lay["span"].x - 0.4 * float(lay["total"])) < 2.0, "%.0f / %.0f" % [lay["span"].x, 0.4 * float(lay["total"])])
	hm.undo()
	await frames(4)

	# ── 2b. Debajo del trazo, invertir dirección y espejo ──
	for key in ["path_text_valign", "path_text_reverse", "path_text_flip"]:
		check("Modern: el inspector muestra «%s»" % key, _row_visible(key))
	var side0 := _side(l)
	for opt in [["path_text_valign", "top", "debajo"], ["path_text_reverse", true, "invertido"], ["path_text_flip", true, "espejo"]]:
		ic.apply(opt[0], opt[1])
		await frames(4)
		var sd := _side(l)
		check("«%s»: el texto pasa al otro lado del trazo" % opt[2], signf(sd) == -signf(side0) and absf(sd) > 0.5, "%.2f → %.2f" % [side0, sd])
		await shot("opcion_%s.png" % opt[2])
		hm.undo()
		await frames(4)
	check("deshacer devuelve el lado original", signf(_side(l)) == signf(side0))
	# invertido: la primera letra queda al final del tramo (se lee al revés)
	ic.apply("path_text_reverse", true)
	await frames(4)
	var g_rev := glyphs(l)
	check("invertido: siguen todas las letras", g_rev.size() == 17, str(g_rev.size()))
	hm.undo()
	await frames(4)

	# ── 2c. Panel de texto (tipografía) con sus controles reales ──
	sm.select(l)
	await frames(6)
	var full: Control = null
	for n in root.find_children("FullTypography", "", true, false):
		if (n as Control).is_visible_in_tree():
			full = n
	check("Modern: el panel de tipografía se muestra con el texto en trazado", full != null)
	if full:
		var pnl: Node = null
		for n in full.find_children("*", "", true, false):
			if "_sliders" in n and not (n._sliders as Dictionary).is_empty():
				pnl = n
		var key0 := _src_key(l)
		var bb := full.find_child("Btn_bold", true, false) as Button
		check("hay botón Negrita", bb != null)
		if bb:
			bb.pressed.emit()
			await frames(6)
			check("Negrita cambia las letras del trazado", _src_key(l) != key0 and int(ic._read(l, "font_weight")) >= 700)
		var key1 := _src_key(l)
		var bi := full.find_child("Btn_italic", true, false) as Button
		if bi:
			bi.pressed.emit()
			await frames(6)
			check("Cursiva cambia las letras del trazado", _src_key(l) != key1 and bool(ic._read(l, "font_italic")))
		if pnl:
			var w1 := l.width
			(pnl._sliders["font_size"] as Slider).value = 80.0
			await frames(6)
			check("el deslizador de tamaño agranda el texto en trazado", l.width > w1 * 1.3, "%.1f → %.1f" % [w1, l.width])
			if pnl.has_method("_on_font_color_changed"):
				pnl._on_font_color_changed(Color(0.8, 0.1, 0.1))
				await frames(6)
				var cols := []
				for pc in (l.get_meta("brush_obj")["src"] as Array)[0]:
					cols.append(Color.from_string(String(pc["col"]), Color.BLACK))
				check("el color del texto se aplica a las letras", cols.size() > 0 and cols.all(func(c): return c.r > 0.7 and c.g < 0.2), str(cols.slice(0, 2)))
			var fc = root.get_node_or_null("FontCore")
			var cur := String(ic._read(l, "font_family"))
			var other := ""
			if fc:
				for f in fc.list_families():
					if f != cur and not fc.is_google(f) and (other == "" or fc.is_bundled(f)):
						other = f
						if fc.is_bundled(f):
							break
			check("hay otra fuente para probar", other != "", "actual: %s" % cur)
			if other != "" and pnl.has_method("_elegir_fuente"):
				var key2 := _src_key(l)
				pnl._elegir_fuente(other)
				await frames(10)
				check("elegir otra fuente cambia las letras (%s)" % other, _src_key(l) != key2 and String(ic._read(l, "font_family")) == other)
		# Letras avanzadas: proporciones (grande → pequeña) y onda
		var key3 := _src_key(l)
		ic.apply("letter_proportions", {"mode": "Aaa", "start": 1.6, "mid": 1.2, "mid2": 0.8, "end": 0.4})
		await frames(6)
		check("Letras avanzadas (proporciones) cambian el texto en trazado", _src_key(l) != key3)
		var key4 := _src_key(l)
		ic.apply("letter_wave", {"mode": "wave", "amount": 12.0, "cycles": 1.5, "phase": 0.0})
		await frames(6)
		check("Letras avanzadas (onda) cambian el texto en trazado", _src_key(l) != key4)
		await shot("tipografia.png")
		# deshacer los pasos de tipografía (no la creación del texto en trazado)
		for i in 20:
			if not String(hm.get_undo_name()).begins_with("Inspector") and not String(hm.get_undo_name()).begins_with("Texto ·"):
				break
			hm.undo()
			await frames(2)
		await frames(6)
		var fw = ic._read(l, "font_weight")
		check("deshacer devuelve la tipografía", is_instance_valid(l) and l.get_parent() != null and fw != null and int(fw) < 700 and glyphs(l).size() == 17, str(fw))

	# ── 3. Pro: también las filas ──
	gui.set_ui_mode("professional")
	await frames(30)
	sm.select(l)
	await frames(8)
	check("Pro: el inspector muestra «Tamaño de letra»", _row_visible("path_text_size"))
	check("Pro: el inspector muestra «Empieza en»", _row_visible("path_text_start"))
	check("Pro: la página de tipografía se habilita (hay tamaño de letra)", ic.current_props().has("font_size"))

	# ── 4. Tiradores en el lienzo, con el ratón ──
	gui.set_ui_mode("smart")
	await frames(20)
	var mt_script = load("res://script_gdscript/tools/MoveTool.gd")
	var cur = canvas.get_current_tool()
	if cur == null or not cur.has_method("get_class_name") or cur.get_class_name() != "MoveTool":
		canvas.change_tool(canvas._new_tool(mt_script))
	await frames(4)
	sm.select(l)
	await frames(6)
	cam.position = ab.global_position + ac
	await frames(6)
	var z := zoom()
	lay = TPH.layout(l)
	check("hay tiradores de inicio, final y centro", lay.has("start") and lay.has("end") and lay.has("mid"))
	await shot("2_tiradores.png")
	var total: float = lay["total"]
	var target_s := 0.3 * total
	var target_g: Vector2 = l.get_global_transform() * _point_at(R.centerline(l)[0], target_s)
	await drag(TPH._handle_pos(lay["start"], "start", z), target_g)
	check("arrastrar ▶ mueve el inicio (≈30 %)", absf(float(prm(l).get("start_at", 0.0)) - 0.3) < 0.03, str(prm(l).get("start_at", 0.0)))
	lay = TPH.layout(l)
	check("el texto empieza en el tirador", absf(lay["span"].x - lay["range"].x) < 2.0)
	await shot("3_inicio_movido.png")
	hm.undo()
	await frames(4)
	check("deshacer devuelve el inicio", float(prm(l).get("start_at", 0.0)) < 0.001)
	lay = TPH.layout(l)
	target_g = l.get_global_transform() * _point_at(R.centerline(l)[0], 0.8 * total)
	await drag(TPH._handle_pos(lay["end"], "end", z), target_g)
	check("arrastrar ◀ mueve el final (≈80 %)", absf(float(prm(l).get("end_at", 1.0)) - 0.8) < 0.03, str(prm(l).get("end_at", 1.0)))
	# ◆ deslizar: el tramo entero se mueve
	ic.apply("path_text_range", Vector2(0.1, 0.8))
	await frames(4)
	lay = TPH.layout(l)
	var mid_s: float = (lay["span"].x + lay["span"].y) * 0.5
	target_g = l.get_global_transform() * _point_at(R.centerline(l)[0], mid_s + 0.1 * total)
	await drag(TPH._handle_pos(lay["mid"], "mid", z), target_g)
	var a := float(prm(l).get("start_at", 0.0))
	check("arrastrar ◆ desliza el texto por el trazado", absf(a - 0.2) < 0.03, "%.3f" % a)
	await shot("4_deslizado.png")
	check("el arrastre no movió la figura", l.position == Vector2.ZERO)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)

## Lado del trazo donde queda el texto: media del signo (+1 / -1) de cada
## punto de la malla respecto a la normal del eje más cercano.
func _side(l: Line2D) -> float:
	var r = l.get_node_or_null(R.NODE_NAME)
	r._draw()
	var axis: PackedVector2Array = R.centerline(l)[0]
	var acc := 0.0
	var n := 0
	for q in r._geom["m"]["points"]:
		var best := INF
		var sg := 0.0
		for k in axis.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(q, axis[k], axis[k + 1])
			var d := c.distance_to(q)
			if d < best and d > 0.5:
				best = d
				var t := (axis[k + 1] - axis[k]).normalized()
				sg = signf((q - c).dot(Vector2(-t.y, t.x)))
		acc += sg
		n += 1
	return acc / maxf(n, 1)

func _src_key(l: Line2D) -> int:
	return var_to_str((l.get_meta("brush_obj", {}) as Dictionary).get("src", [])).hash()

func _row_visible(key: String) -> bool:
	for ep in root.find_children("ExtraProps", "", true, false):
		if not (ep as Control).is_visible_in_tree():
			continue
		for ch in ep.find_children("*", "", true, false):
			if String(ch.name).contains(key) and ch is Control and (ch as Control).is_visible_in_tree():
				return true
	return false

func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if acc + d >= s:
			return pts[i].lerp(pts[i + 1], (s - acc) / maxf(d, 0.0001))
		acc += d
	return pts[pts.size() - 1]

## Distancia por la curva entre dos puntos (proyectados sobre ella).
func _arc_between(pts: PackedVector2Array, p: Vector2, q: Vector2) -> float:
	return absf(_arc_of(pts, q) - _arc_of(pts, p))

func _arc_of(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var acc := 0.0
	for i in pts.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := c.distance_to(p)
		if d < best:
			best = d
			best_s = acc + pts[i].distance_to(c)
		acc += pts[i].distance_to(pts[i + 1])
	return best_s
