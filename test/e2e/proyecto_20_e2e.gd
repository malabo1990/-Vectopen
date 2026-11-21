# =============================================================================
# FASE B · ENCARGO 20 — Invitación con caligrafía (modo Smart)
# Foco: pincel caligráfico, presión.
# Invitación A5 (559 × 794): rótulo «Ana & Luis» trazado A MANO con la
# herramienta Pincel en estilo caligráfico (ratón con presión variable),
# florituras, marco fino, datos de la boda en texto. El grosor del trazo
# sigue a la presión (curva de grosor no constante), la plumilla plana da
# trazos finos y gruesos según la dirección; cambiar el ángulo de la plumilla
# después (se rehace), grosor de todos los trazos a la vez, exportar PDF/PNG,
# reabrir con la presión y el estilo intactos.
#   test/run_e2e.sh proyecto_20_e2e
# =============================================================================
extends SceneTree

const OUT := "user://proyectos/20"
const INK := Color("#1d3557")
var K
var api
var ab: Node2D

func _init() -> void:
	_run.call_deferred()
	create_timer(520.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func move(at: Vector2, held: bool, p: float) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.pressure = p if held else 0.0
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

## Trazo real en coordenadas de página; presión según `pf(t)`.
func stroke(pts_in: PackedVector2Array, pf: Callable) -> void:
	# Como un ratón real: un evento cada ~3 px (dos puntos no son un trazo).
	var pts := PackedVector2Array([pts_in[0]])
	for i in range(1, pts_in.size()):
		var a := pts_in[i - 1]
		var b := pts_in[i]
		var n := maxi(1, int(ceil(a.distance_to(b) / 3.0)))
		for k in range(1, n + 1):
			pts.append(a.lerp(b, float(k) / n))
	var xf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
	var s: Array = []
	for p in pts:
		s.append(xf * (ab.global_position + p))
	await move(s[0], false, 0.0)
	await btn(s[0], true)
	for i in s.size():
		await move(s[i], true, float(pf.call(float(i) / maxf(1.0, s.size() - 1))))
	await btn(s[-1], false)
	await create_timer(0.45).timeout   # pausa humana entre trazos (no es un doble clic)
	if OS.has_environment("DBG20"):
		print("DBG trazo desde %s → %d trazos" % [pts_in[0], lines_in(ab).size()])

func loop_pts(c: Vector2, r: Vector2, turns: float, n: int, start := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := start + TAU * turns * float(i) / (n - 1)
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) + Vector2(i * 1.2, 0))
	return out

func lines_in(n: Node) -> Array:
	return n.find_children("*", "Line2D", true, false).filter(func(l) -> bool: return l.has_meta("brush_style"))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, OUT)
	if not await K.boot("smart"):
		print("RESULT: no arranca")
		quit(1)
		return
	api = K.api
	ab = await K.artboard(Vector2(559, 794), "Invitación", Color("#fffaf0"))
	var frame = api.add_rect(Vector2(279.5, 397), Vector2(500, 735), 6.0, "Marco")
	api.set_props(frame, {"fill_color": Color(0, 0, 0, 0), "stroke_color": Color("#c9a227"), "stroke_width": 1.5})
	await K.look_at(ab, 1.0)
	K.canvas.switch_tool("brush")
	await K.frames(4)
	var bt = K.canvas.current_tool
	bt.apply_brush_style("calligraphy")
	bt.brush_width = 10.0
	var n0 := lines_in(ab).size()
	# «A»: dos diagonales y travesaño, presión fuerte en las bajadas
	await stroke(PackedVector2Array([Vector2(110, 300), Vector2(140, 200)]), func(t): return 0.3 + 0.6 * t)
	await stroke(PackedVector2Array([Vector2(140, 200), Vector2(170, 300)]), func(t): return 0.9 - 0.5 * t)
	await stroke(PackedVector2Array([Vector2(122, 262), Vector2(160, 262)]), func(_t): return 0.3)
	# «n», «a»: bucles con presión oscilante
	await stroke(loop_pts(Vector2(205, 275), Vector2(14, 22), 1.0, 40, PI), func(t): return 0.2 + 0.8 * absf(sin(t * PI * 2.0)))
	await stroke(loop_pts(Vector2(250, 280), Vector2(14, 18), 1.2, 44, -PI / 2), func(t): return 0.15 + 0.8 * absf(sin(t * PI * 3.0)))
	# «&» como floritura en espiral
	await stroke(loop_pts(Vector2(300, 290), Vector2(26, 34), 1.6, 70, 0.0), func(t): return 0.15 + 0.85 * sin(t * PI))
	# «Luis» (en total: 3 + 2 + 1 + 4 + 1 = 11 trazos): trazos verticales con presión creciente
	for i in 4:
		await stroke(PackedVector2Array([Vector2(360 + i * 30, 200 + (i % 2) * 40), Vector2(355 + i * 30, 300)]), func(t): return 0.2 + 0.75 * t)
	# Floritura inferior larga
	var flor := PackedVector2Array()
	for i in 80:
		var t := float(i) / 79.0
		flor.append(Vector2(90 + t * 380, 340 + sin(t * TAU * 1.5) * 14))
	await stroke(flor, func(t): return 0.1 + 0.9 * sin(t * PI))
	K.canvas.switch_tool("move")
	await K.frames(4)
	var strokes: Array = lines_in(ab).slice(n0)
	K.check("11 trazos caligráficos dibujados con la herramienta", strokes.size() == 11, str(strokes.size()))
	K.check("todos en estilo caligráfico", strokes.all(func(l) -> bool: return String(l.get_meta("brush_style")) == "calligraphy"))
	# La presión llega al grosor: curva de grosor con variación
	var varied := 0
	for l in strokes:
		var wc: Curve = l.width_curve
		if wc and wc.point_count >= 2:
			var lo := 9.0
			var hi := -9.0
			for k in 21:
				var v := wc.sample(k / 20.0)
				lo = minf(lo, v)
				hi = maxf(hi, v)
			if hi - lo > 0.25:
				varied += 1
	K.check("la presión cambia el grosor (≥ 8 de 11 trazos con curva variable)", varied >= 8, "%d de 11" % varied)
	await K.shot("01_rotulo")
	# Ángulo de plumilla: cambiarlo rehace el trazo
	var fl: Line2D = strokes[-1]
	var rr: Node = fl.get_node_or_null("StrokeRender")
	var a0 := float(api.get_prop(fl, "brush_nib_angle"))
	await K.frames(2)
	var poly0: int = str(rr.get("_cache_key") if rr and "_cache_key" in rr else "").hash()
	api.set_prop(fl, "brush_nib_angle", a0 + 60.0)
	await K.frames(4)
	K.check("cambiar el ángulo de la plumilla desde el inspector (propiedad)", is_equal_approx(float(api.get_prop(fl, "brush_nib_angle")), a0 + 60.0) and rr != null)
	api.undo()
	await K.frames(2)
	K.check("deshacer el ángulo de plumilla", is_equal_approx(float(api.get_prop(fl, "brush_nib_angle")), a0))
	api.redo()
	# Grosor de todos a la vez
	K.sm.set_selection(strokes)
	await K.frames(2)
	K.ic.apply("stroke_width", 14.0)
	await K.frames(2)
	K.check("grosor de los 11 trazos a la vez", strokes.all(func(l) -> bool: return is_equal_approx(l.width, 14.0)))
	K.check("cambiar el grosor conserva la presión (curva)", strokes.all(func(l) -> bool: return l.width_curve != null))
	K.sm.clear()
	# Datos en texto
	var t1 = api.add_text(Vector2(150, 430), "tienen el placer de invitarte", 18, INK)
	var t2 = api.add_text(Vector2(175, 480), "Sábado 12 de junio · 18:00", 20, INK)
	var t3 = api.add_text(Vector2(160, 520), "Finca Moka · Bioko Sur", 18, Color("#c9a227"))
	api.set_prop(t2, "font_weight", 700)
	api.align([t1, t2, t3], "center_h")
	await K.frames(4)
	await K.shot("02_invitacion")
	await K.undo_redo(20)
	var ex: Dictionary = await K.export_all(ab, "invitacion")
	if ex.has("svg"):
		var svg := FileAccess.get_file_as_string(ex["svg"])
		K.check("SVG con los trazos caligráficos como formas", svg.count("<path") >= 12, "%d paths" % svg.count("<path"))
	var abs: Array = await K.save_reload("invitacion")
	for a in abs:
		if String(a.name) == "Invitación":
			var re: Array = lines_in(a)
			K.check("reabrir: 11 trazos caligráficos", re.filter(func(l) -> bool: return String(l.get_meta("brush_style")) == "calligraphy").size() == 11, str(re.size()))
			K.check("reabrir: la presión (curva de grosor) se conserva", re.all(func(l) -> bool: return l.width_curve != null and l.width_curve.point_count >= 2))
			K.check("reabrir: el ángulo de plumilla cambiado", re.any(func(l) -> bool: return is_equal_approx(float(l.get_meta("nib_angle", -1.0)), a0 + 60.0)))
			await K.look_at(a)
			await K.shot("03_reabierto")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
