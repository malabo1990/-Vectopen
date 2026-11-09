# =============================================================================
# PRECISIÓN de selección (editor profesional):
#  · el recuadro de un trazo de pincel fino o de una curva abraza lo que se
#    ve (sin márgenes fijos que, con mucho zoom, lo hacían enorme);
#  · un clic solo coge el objeto si toca su FORMA: no su recuadro, ni el
#    hueco de una curva, ni lo transparente de una imagen, ni el interior de
#    una figura sin relleno.
#   test/run_e2e.sh select_precision_e2e
# =============================================================================
extends SceneTree

const OUT := "user://select_precision"
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
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

func click_at(gp: Vector2) -> void:
	var p: Vector2 = canvas.get_viewport().get_canvas_transform() * gp
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	_send(mm)
	await process_frame
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = p
		mb.global_position = p
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(mb)
		await process_frame
	await frames(3)

func marquee(a_g: Vector2, b_g: Vector2) -> void:
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var a := xf * a_g
	var b := xf * b_g
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	_send(mm)
	await process_frame
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await process_frame
	for i in range(1, 7):
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, i / 6.0)
		m2.global_position = m2.position
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m2)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await frames(3)

func selected() -> Array:
	return root.get_node("SelectionManager").get_selected()

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
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var sm = root.get_node("SelectionManager")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	var mt_script = load("res://script_gdscript/tools/MoveTool.gd")
	var cur = canvas.get_current_tool()
	if cur == null or not cur.has_method("get_class_name") or cur.get_class_name() != "MoveTool":
		canvas.change_tool(canvas._new_tool(mt_script))
	await frames(4)
	var mt = canvas.get_current_tool()

	# ── 1. Recuadro de un trazo de pincel FINO con mucho zoom ──
	var l := Line2D.new()
	l.name = "Trazo fino"
	l.points = PackedVector2Array([ac + Vector2(-15, 0), ac + Vector2(0, 4), ac + Vector2(15, 0)])
	l.width = 1.0
	l.default_color = Color(0.1, 0.1, 0.1)
	l.set_meta("brush_style", "pen")
	ab.add_child(l)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
	cam.zoom = Vector2(20, 20)
	cam.position = ab.to_global(ac)
	await frames(8)
	var r: Rect2 = mt._global_rect(l)
	var pts_r := Rect2(ab.to_global(ac + Vector2(-15, 0)), Vector2(30, 4))
	check("recuadro del trazo fino ajustado (≤ trazo + su grosor)", r.size.x <= pts_r.size.x + 1.5 and r.size.y <= pts_r.size.y + 1.5, "%s vs %s" % [r.size, pts_r.size])
	sm.select(l)
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("trazo_fino_zoom20.png"))
	sm.clear()

	# ── 1b. Zoom 7400 % con un trazo diminuto en «C» (caso del usuario) ──
	var tiny := Line2D.new()
	tiny.name = "C diminuta"
	var tc := ac + Vector2(-100, -100)
	var tp := PackedVector2Array()
	for k in 25:
		var ang := PI * 0.3 + PI * 1.4 * k / 24.0
		tp.append(tc + Vector2(cos(ang), sin(ang)) * 0.55)
	tiny.points = tp
	tiny.width = 0.3
	tiny.default_color = Color(0.6, 0.1, 0.8)   # morado: no se confunde con las flechas roja / verde
	tiny.set_meta("brush_style", "pen")
	ab.add_child(tiny)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(tiny)
	cam.zoom = Vector2(74, 74)
	cam.position = ab.to_global(tc)
	await frames(6)
	sm.select(tiny)
	await frames(8)
	await RenderingServer.frame_post_draw
	var timg := root.get_texture().get_image()
	timg.save_png(OUT.path_join("c_diminuta_7400.png"))
	var csp: Vector2 = canvas.get_viewport().get_canvas_transform() * ab.to_global(tc)
	var cy := int(csp.y)
	var cx := int(csp.x)
	var red_min := 99999
	var red_max := -1
	var blue_min := 99999
	var blue_max := -1
	for yy in range(cy - 60, cy + 60):
		for xx in range(maxi(cx - 200, 0), mini(cx + 200, timg.get_width())):
			var px := timg.get_pixel(xx, yy)
			if px.r > 0.45 and px.g < 0.25 and px.b > 0.6:
				red_min = mini(red_min, xx)
				red_max = maxi(red_max, xx)
			elif px.b > 0.8 and px.r < 0.35 and px.g > 0.35 and px.g < 0.75:
				blue_min = mini(blue_min, xx)
				blue_max = maxi(blue_max, xx)
	check("7400 %: el recuadro cubre el trazo por la izquierda", blue_min <= red_min + 2, "caja %d · trazo %d" % [blue_min, red_min])
	check("7400 %: el recuadro cubre el trazo por la derecha y no se pasa", blue_max >= red_max - 2 and blue_max <= red_max + 14, "caja %d · trazo %d" % [blue_max, red_max])
	sm.clear()

	# ── 2. Curva abierta en «C» encima de un círculo que queda en su hueco ──
	cam.zoom = Vector2.ONE
	cam.position = ab.to_global(ac + Vector2(0, 200))
	var dot = api.add_rect(ac + Vector2(260, 200), Vector2(40, 40), 0.0, "Debajo")
	var c := Curve2D.new()
	c.add_point(ac + Vector2(300, 100), Vector2.ZERO, Vector2(-120, -40))
	c.add_point(ac + Vector2(300, 300), Vector2(-120, 40), Vector2.ZERO)
	var cpath = api.add_curve(c, false, "Curva C")
	cpath.stroke_width = 2.0
	await frames(6)
	sm.clear()
	await click_at(ab.to_global(ac + Vector2(260, 200)))
	check("clic en el hueco de la curva coge lo de debajo (no la curva)", selected().size() == 1 and selected()[0] == dot, str(selected()))
	sm.clear()
	await click_at(ab.to_global(c.sample(0, 0.5)))
	check("clic sobre la línea de la curva la coge", selected().size() == 1 and selected()[0] == cpath, str(selected()))
	var cr: Rect2 = mt._global_rect(cpath)
	var bake_r := Rect2()
	var first := true
	for q in c.get_baked_points():
		var gq: Vector2 = cpath.to_global(q)
		bake_r = Rect2(gq, Vector2.ZERO) if first else bake_r.expand(gq)
		first = false
	check("recuadro de la curva = su forma + medio grosor", absf(cr.size.x - (bake_r.size.x + 2.0)) < 1.5, "%s vs %s" % [cr.size, bake_r.size])
	sm.clear()

	# ── 3. Trazo de pincel diagonal: clic en su recuadro pero lejos del trazo ──
	var d := Line2D.new()
	d.name = "Diagonal"
	d.points = PackedVector2Array([ac + Vector2(-300, 100), ac + Vector2(-150, 300)])
	d.width = 6.0
	d.default_color = Color(0.1, 0.1, 0.1)
	d.set_meta("brush_style", "pen")
	ab.add_child(d)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(d)
	await frames(6)
	await click_at(ab.to_global(ac + Vector2(-170, 120)))
	check("clic en el recuadro del trazo pero fuera de él: no lo coge", not selected().has(d), str(selected()))
	sm.clear()
	await click_at(ab.to_global(ac + Vector2(-225, 200)))
	check("clic sobre el trazo lo coge", selected().has(d), str(selected()))
	sm.clear()
	# marquee que pisa el recuadro del trazo pero no el trazo
	await marquee(ab.to_global(ac + Vector2(-190, 105)), ab.to_global(ac + Vector2(-160, 135)))
	check("marquee en el recuadro pero sin tocar el trazo: no lo coge", not selected().has(d), str(selected()))
	sm.clear()
	await marquee(ab.to_global(ac + Vector2(-250, 180)), ab.to_global(ac + Vector2(-200, 220)))
	check("marquee que cruza el trazo lo coge", selected().has(d), str(selected()))
	sm.clear()

	# ── 4. Imagen con mitad transparente ──
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(0, 0, 50, 100), Color(0.9, 0.3, 0.2, 1))
	var sp = api.add_image(img, ac + Vector2(-250, -200), "Media")
	await frames(6)
	await click_at(ab.to_global(ac + Vector2(-220, -200)))
	check("clic en lo transparente de la imagen no la coge", not selected().has(sp), str(selected()))
	sm.clear()
	await click_at(ab.to_global(ac + Vector2(-280, -200)))   # parte pintada
	check("clic en lo pintado de la imagen la coge", selected().has(sp), str(selected()))
	sm.clear()

	# ── 5. Rectángulo SIN relleno: solo su borde ──
	var hollow = api.add_rect(ac + Vector2(150, -200), Vector2(120, 80), 0.0, "Hueco")
	hollow.fill_color = Color(1, 1, 1, 0)
	hollow.stroke_width = 2.0
	await frames(6)
	await click_at(ab.to_global(ac + Vector2(150, -200)))
	check("clic dentro de una figura sin relleno no la coge", not selected().has(hollow), str(selected()))
	sm.clear()
	await click_at(ab.to_global(ac + Vector2(90, -200)))   # borde izquierdo
	check("clic en su borde la coge", selected().has(hollow), str(selected()))
	sm.clear()
	# figura con relleno: dentro sí
	var full = api.add_rect(ac + Vector2(150, -60), Vector2(80, 60), 0.0, "Lleno")
	await frames(4)
	await click_at(ab.to_global(ac + Vector2(150, -60)))
	check("clic dentro de una figura con relleno la coge", selected().has(full), str(selected()))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("escena.png"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
