# =============================================================================
# Calidad del trazo de pincel (USR-05 / VGSE fase 1): se dibujan con eventos
# reales de lápiz (presión) varios trazos difíciles — curva con presión que
# sube y baja, espiral cerrada, zigzag, lazo semitransparente que se cruza —
# y se guardan recortes ampliados ×3 para revisar borde, uniones y puntas.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_quality_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://brush_quality"
var fails := 0
var canvas
var bt
var aa_levels := 0
var _proc_acc := 0.0
var _proc_n := 0
var _measuring := false

func _process(_d: float) -> bool:
	if _measuring:
		_proc_acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_proc_n += 1
	return false

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
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
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

var _prev := Vector2.ZERO
func move(at: Vector2, held: bool, p: float) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.relative = at - _prev
	mm.pressure = p if held else 0.0
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(mm)
	_prev = at
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

## Dibuja la polilínea `pts` (pantalla) con presiones `pr`.
func stroke(pts: Array, pr: Array) -> Node:
	var ab = canvas.get_node("manager_script").get_active_artboard()
	var before: int = ab.get_child_count()
	await move(pts[0], false, 0.0)
	await btn(pts[0], true)
	for i in pts.size():
		await move(pts[i], true, pr[i])
	await btn(pts[pts.size() - 1], false)
	await frames(6)
	return ab.get_child(ab.get_child_count() - 1) if ab.get_child_count() > before else null

func crop(name: String, rect: Rect2, scale := 3) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var r := Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var c := img.get_region(r)
	if scale > 1:
		c.resize(c.get_width() * scale, c.get_height() * scale, Image.INTERPOLATE_NEAREST)
	c.save_png(OUT.path_join(name + ".png"))

## Picos de alfa a lo largo de un trazo semitransparente: con solapes se ven
## manchas más oscuras (uniones y remates pintados dos veces).
func alpha_spots(rect: Rect2, base: Color) -> int:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var bg := img.get_pixelv(Vector2i(rect.position) - Vector2i(6, 6))
	var lums := {}
	for y in range(int(rect.position.y), int(rect.end.y), 1):
		for x in range(int(rect.position.x), int(rect.end.x), 1):
			var c := img.get_pixel(x, y)
			if absf(c.get_luminance() - bg.get_luminance()) + absf(c.r - bg.r) + absf(c.b - bg.b) > 0.08:
				var q := snappedf(c.get_luminance(), 0.02)
				lums[q] = int(lums.get(q, 0)) + 1
	# Un solo «tono» de relleno (más el antialias del borde) = sin solapes.
	var tones := 0
	var total := 0
	for v in lums.values():
		total += v
	for k in lums:
		if lums[k] > total * 0.04:
			tones += 1
	print("INFO tonos del trazo semitransparente: %s" % str(lums))
	# Antialias: el borde pasa por muchos tonos intermedios (sin él, 1-2).
	var levels := 0
	for k in lums:
		if lums[k] > total * 0.003 and lums[k] <= total * 0.04:
			levels += 1
	aa_levels = levels
	return tones

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
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	canvas = get_first_node_in_group("_vectopen_canvas")
	canvas.switch_tool("brush")
	await frames(4)
	bt = canvas.current_tool
	bt.brush_width = 16.0
	var vs := root.get_visible_rect().size
	var o := Vector2(vs.x * 0.22, vs.y * 0.25)
	# 1) Curva en S con presión 0.1 → 1 → 0.1 (punta fina, cuerpo, punta).
	var pts := []
	var pr := []
	for i in 60:
		var t := i / 59.0
		pts.append(o + Vector2(t * 340.0, sin(t * TAU) * 60.0))
		pr.append(clampf(0.1 + 0.9 * sin(t * PI), 0.05, 1.0))
	var s1 = await stroke(pts, pr)
	check("trazo con presión creado", s1 != null)
	# 2) Espiral cerrada (radio menor que el grosor al final).
	var c2 := o + Vector2(520, 0)
	pts = []
	pr = []
	for i in 90:
		var a := i * 0.22
		pts.append(c2 + Vector2(cos(a), sin(a)) * (70.0 - i * 0.7))
		pr.append(0.8)
	var s2 = await stroke(pts, pr)
	# 3) Zigzag de ángulos cerrados.
	var o3 := o + Vector2(0, 200)
	pts = []
	pr = []
	# Muestras densas (cada ~4 px), como las de un lápiz real.
	for i in 8:
		var a3 := o3 + Vector2(i * 38.0, 0.0 if i % 2 == 0 else 70.0)
		var b3 := o3 + Vector2((i + 1) * 38.0, 0.0 if (i + 1) % 2 == 0 else 70.0)
		for k in 20:
			pts.append(a3.lerp(b3, k / 20.0))
			pr.append(0.9)
	pts.append(o3 + Vector2(8 * 38.0, 0.0))
	pr.append(0.9)
	var s3 = await stroke(pts, pr)
	# 4) Lazo semitransparente que se cruza consigo mismo.
	bt.brush_opacity = 0.5
	var c4 := o + Vector2(520, 220)
	pts = []
	pr = []
	for i in 80:
		var t := i / 79.0 * TAU
		pts.append(c4 + Vector2(sin(t) * 110.0, sin(t * 2.0) * 45.0))
		pr.append(0.9)
	var s4 = await stroke(pts, pr)
	bt.brush_opacity = 1.0
	# 5) Trazo largo: coste por movimiento con la vista previa de calidad.
	pts = []
	pr = []
	var o5 := Vector2(vs.x * 0.2, vs.y * 0.78)
	for i in 700:
		pts.append(o5 + Vector2(i * 1.0, sin(i * 0.05) * 40.0))
		pr.append(0.5 + 0.5 * sin(i * 0.02))
	var t0 := Time.get_ticks_usec()
	_proc_acc = 0.0
	_proc_n = 0
	_measuring = true
	var s5 = await stroke(pts, pr)
	_measuring = false
	print("INFO por fotograma: proceso %.1f ms, dibujo %d llamadas" % [_proc_acc / maxf(1.0, _proc_n), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	var per_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 700.0
	print("INFO trazo largo: %.2f ms por movimiento (incluye el fotograma)" % per_ms)
	# Con la vista previa de calidad, dibujar no debe bajar de ~30 fps.
	check("dibujar un trazo largo va fluido", per_ms < 34.0, "%.1f ms" % per_ms)
	check("trazo largo dibujado", s5 != null)
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(10)
	await crop("1_presion", Rect2(o - Vector2(30, 90), Vector2(400, 180)))
	await crop("2_espiral", Rect2(c2 - Vector2(90, 90), Vector2(180, 180)))
	await crop("3_zigzag", Rect2(o3 - Vector2(25, 25), Vector2(360, 120)))
	await crop("4_lazo", Rect2(c4 - Vector2(130, 65), Vector2(260, 130)))
	for s in [s1, s2, s3, s4]:
		if s:
			print("INFO %s puntos=%d ancho=%.1f render=%s" % [s.name, s.points.size(), s.width, s.get_node_or_null("StrokeRender") != null])
	var tones := await alpha_spots(Rect2(c4 - Vector2(120, 55), Vector2(240, 110)), Color.BLACK)
	check("lazo semitransparente sin manchas de solape", tones <= 2, "%d tonos" % tones)
	check("borde con antialias (tonos intermedios)", aa_levels >= 6, "%d niveles" % aa_levels)
	# 6) Estilos (lápiz, rotulador, aerógrafo, caligráfico): mismo render
	#    mientras se dibuja y al soltar; recortes en vivo y final.
	var oy := vs.y * 0.12
	canvas.switch_tool("brush")
	await frames(4)
	bt = canvas.current_tool
	for st in ["pencil", "marker", "airbrush", "calligraphy"]:
		bt.apply_brush_style(st)
		bt.brush_width = 18.0
		var o6 := Vector2(vs.x * 0.62, oy)
		oy += 110.0
		var p6 := []
		var r6 := []
		for i in 70:
			var t := i / 69.0
			p6.append(o6 + Vector2(t * 300.0, sin(t * TAU) * 30.0))
			r6.append(clampf(0.3 + 0.7 * sin(t * PI), 0.1, 1.0))
		var ab6 = canvas.get_node("manager_script").get_active_artboard()
		await move(p6[0], false, 0.0)
		await btn(p6[0], true)
		var live_ok := false
		for i in p6.size():
			await move(p6[i], true, r6[i])
			if i == 45:
				var cur: Node = ab6.get_child(ab6.get_child_count() - 1)
				live_ok = cur is Line2D and cur.get_node_or_null("StrokeRender") != null
				await crop("estilo_%s_vivo" % st, Rect2(o6 - Vector2(20, 50), Vector2(340, 100)))
		await btn(p6[p6.size() - 1], false)
		await frames(6)
		var fin: Node = ab6.get_child(ab6.get_child_count() - 1)
		check("%s: se ve con el render de calidad mientras se dibuja" % st, live_ok)
		check("%s: el trazo final también" % st, fin is Line2D and fin.get_node_or_null("StrokeRender") != null and (fin as Line2D).texture == null)
		root.get_node("SelectionManager").clear()
		await frames(4)
		await crop("estilo_%s" % st, Rect2(o6 - Vector2(20, 50), Vector2(340, 100)))
	# 7) Zoom ×8 en un giro cerrado (como en la prueba del usuario a 1071 %):
	#    sin rayos ni costuras en rotulador, aerógrafo y lápiz.
	var zooms := []
	var ox := vs.x * 0.30
	for st in ["marker", "airbrush", "pencil"]:
		bt.apply_brush_style(st)
		bt.brush_width = 24.0
		var a7 := Vector2(ox, vs.y * 0.55)
		var p7 := []
		var r7 := []
		for i in 30:
			p7.append(a7 + Vector2(i * 2.0, -i * 3.0))
			r7.append(0.9)
		for i in 30:
			p7.append(a7 + Vector2(60.0 + i * 2.0, -90.0 + i * 3.0))
			r7.append(0.9)
		await stroke(p7, r7)
		zooms.append([st, a7 + Vector2(60, -90)])
		ox += 170.0
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(4)
	var cam: Camera2D = canvas.camera
	var keep_pos := cam.position
	var keep_zoom := cam.zoom
	for z in zooms:
		var world: Vector2 = canvas.get_viewport().get_canvas_transform().affine_inverse() * (z[1] as Vector2)
		cam.position = world
		cam.zoom = keep_zoom * 8.0
		await frames(8)
		await crop("zoom_%s" % z[0], Rect2(vs / 2.0 - Vector2(300, 200), Vector2(600, 400)), 1)
		cam.position = keep_pos
		cam.zoom = keep_zoom
		await frames(4)
	canvas.switch_tool("brush")
	await frames(2)
	bt = canvas.current_tool
	bt.apply_brush_style("pen")
	bt.brush_width = 16.0
	canvas.switch_tool("move")
	await frames(4)
	# Convertir trazo en contorno (Ctrl+Mayús+O real): se ve igual.
	for pair in [[s1, Rect2(o - Vector2(30, 90), Vector2(400, 180)), "presion"], [s4, Rect2(c4 - Vector2(130, 65), Vector2(260, 130)), "lazo"]]:
		var line: Node = pair[0]
		var rect: Rect2 = pair[1]
		await RenderingServer.frame_post_draw
		var before_img := root.get_texture().get_image().get_region(Rect2i(rect))
		root.get_node("SelectionManager").set_selection([line])
		await frames(4)
		var k := InputEventKey.new()
		k.keycode = KEY_O
		k.physical_keycode = KEY_O
		k.ctrl_pressed = true
		k.shift_pressed = true
		k.pressed = true
		_send(k)
		k = k.duplicate()
		k.pressed = false
		_send(k)
		await frames(8)
		check("Ctrl+Mayús+O convierte el trazo «%s» en contorno" % pair[2], line.get_parent() == null)
		root.get_node("SelectionManager").clear()
		await frames(6)
		await RenderingServer.frame_post_draw
		var after_img := root.get_texture().get_image().get_region(Rect2i(rect))
		var diff := 0
		var ink := 0
		var cov_a := 0.0
		var cov_b := 0.0
		for y in before_img.get_height():
			for x in before_img.get_width():
				var a := before_img.get_pixel(x, y)
				var b := after_img.get_pixel(x, y)
				cov_a += 1.0 - a.get_luminance()
				cov_b += 1.0 - b.get_luminance()
				if a.get_luminance() < 0.95 or b.get_luminance() < 0.95:
					ink += 1
					# Solo diferencias fuertes (trazo en una, fondo en la otra): el
					# antialias del borde puede variar medio píxel.
					if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.45:
						diff += 1
		var frac := float(diff) / maxf(1.0, float(ink))
		var bp := Vector2i(before_img.get_width() / 2, before_img.get_height() / 2)
		print("INFO %s centro antes=%s después=%s" % [pair[2], before_img.get_pixelv(bp), after_img.get_pixelv(bp)])
		# Solo píxeles sueltos del borde pueden diferir (antialias distinto).
		check("el contorno «%s» se ve igual que el trazo" % pair[2], frac < 0.08, "%.1f %% de píxeles del borde" % (frac * 100.0))
		var ratio := cov_b / maxf(cov_a, 0.001)
		check("el contorno «%s» cubre la misma superficie" % pair[2], absf(ratio - 1.0) < 0.05, "%.3f" % ratio)
		after_img.save_png(OUT.path_join("contorno_%s.png" % pair[2]))
		before_img.save_png(OUT.path_join("antes_%s.png" % pair[2]))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
