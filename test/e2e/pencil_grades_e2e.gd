# =============================================================================
# Lápiz de grafito con durezas (2H … 8B): grano del papel común a todos los
# trazos, la presión rellena el grano, las blandas más oscuras. Capturas a
# tamaño real y con zoom. Comprueba que cada dureza oscurece más que la
# anterior y que el selector del panel cambia la dureza del pincel.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/pencil_grades_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://pencil_grades"
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(170.0).timeout.connect(func() -> void:
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

func stroke(a: Vector2, b: Vector2, wave: float, fixed_p := -1.0) -> void:
	await move(a, false, 0.0)
	await btn(a, true)
	for i in 50:
		var t := i / 49.0
		var pr := fixed_p if fixed_p >= 0.0 else clampf(0.15 + 0.85 * sin(t * PI), 0.05, 0.98)
		await move(a.lerp(b, t) + Vector2(0, sin(t * TAU) * wave), true, pr)
	await btn(b, false)
	await frames(4)
	# Color de grafito (el de fábrica es azul) para juzgar el aspecto.
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var l := ab.get_child(ab.get_child_count() - 1)
	if l is Line2D:
		var a0: float = (l as Line2D).default_color.a
		(l as Line2D).default_color = Color(0.16, 0.16, 0.18, a0)
	await frames(2)

func darkness(rect: Rect2) -> float:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var acc := 0.0
	var n := 0
	for y in range(int(rect.position.y), int(rect.end.y), 2):
		for x in range(int(rect.position.x), int(rect.end.x), 2):
			acc += 1.0 - img.get_pixel(x, y).get_luminance()
			n += 1
	return acc / maxf(1.0, n)

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
	var bt = canvas.current_tool
	# Selector de dureza del panel
	var panel := root.find_child("PencilGrades", true, false)
	var gb := root.find_child("Grade_4B", true, false) as Button
	bt.apply_brush_style("pencil")
	check("selector de dureza en el panel", panel != null and gb != null)
	if gb:
		gb.pressed.emit()
		check("pulsar 4B cambia la dureza del pincel", bt.pencil_grade == "4B")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.position = ab.global_position + ab.artboard_size / 2.0
	cam.zoom = Vector2.ONE
	await frames(6)
	var vs := root.get_visible_rect().size
	var grades := ["2H", "HB", "2B", "4B", "8B"]
	var dark: Array = []
	var y := vs.y * 0.2
	for g in grades:
		bt.apply_brush_style("pencil")
		bt.pencil_grade = g
		bt.brush_width = 10.0
		var a := Vector2(vs.x * 0.3, y)
		await stroke(a, a + Vector2(380, 0), 12.0)
		y += 70.0
		root.get_node("SelectionManager").clear()
		await frames(3)
		dark.append(await darkness(Rect2(a + Vector2(40, -22), Vector2(300, 44))))
	print("INFO oscuridad por dureza: %s" % str(dark))
	var alphas: Array = ab.get_children().filter(func(c): return c is Line2D).map(func(c): return snappedf((c as Line2D).default_color.a, 0.01))
	check("todos los trazos con la opacidad del pincel (no se van aclarando)", alphas.all(func(a): return absf(a - 1.0) < 0.011), str(alphas))
	var mono := true
	for i in range(1, dark.size()):
		mono = mono and dark[i] > dark[i - 1]
	check("cada dureza más blanda es más oscura (2H < HB < 2B < 4B < 8B)", mono, str(dark))
	# Presión: rozar = muy transparente, apretar = casi negro (4B y 8B).
	var press := {}
	var py := vs.y * 0.2 + 5 * 70.0
	for g in ["4B", "8B"]:
		for pp in [0.12, 0.95]:
			bt.pencil_grade = g
			bt.brush_width = 10.0
			var a2 := Vector2(vs.x * 0.3, py)
			await stroke(a2, a2 + Vector2(240, 0), 0.0, pp)
			root.get_node("SelectionManager").clear()
			await frames(3)
			press["%s_%.2f" % [g, pp]] = await darkness(Rect2(a2 + Vector2(60, -3), Vector2(120, 6)))
			py += 40.0
	print("INFO presión → oscuridad: %s" % str(press))
	# Dos trazos cruzados (2B): mismo grano de papel en el cruce
	bt.pencil_grade = "2B"
	var c0 := Vector2(vs.x * 0.5, vs.y * 0.2)
	await stroke(c0, c0 + Vector2(260, 200), 0.0)
	await stroke(c0 + Vector2(0, 200), c0 + Vector2(260, 0), 0.0)
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.get_region(Rect2i(Rect2(Vector2(vs.x * 0.28, vs.y * 0.15), Vector2(vs.x * 0.4, vs.y * 0.75)))).save_png(OUT.path_join("durezas.png"))
	cam.position = canvas.get_viewport().get_canvas_transform().affine_inverse() * Vector2(vs.x * 0.3 + 190, vs.y * 0.2 + 70 * 3)
	cam.zoom = Vector2.ONE * 5.0
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(Rect2(vs / 2.0 - Vector2(300, 150), Vector2(600, 300)))).save_png(OUT.path_join("zoom_4B.png"))
	# Punta (inicio y final) del 4B con zoom
	for endp in [["inicio", Vector2(vs.x * 0.3, vs.y * 0.2 + 70 * 3)], ["final", Vector2(vs.x * 0.3 + 380, vs.y * 0.2 + 70 * 3)]]:
		cam.zoom = Vector2.ONE
		cam.position = ab.global_position + ab.artboard_size / 2.0
		await frames(4)
		var wpos: Vector2 = canvas.get_viewport().get_canvas_transform().affine_inverse() * (endp[1] as Vector2)
		cam.position = wpos
		cam.zoom = Vector2.ONE * 8.0
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().get_region(Rect2i(Rect2(vs / 2.0 - Vector2(200, 120), Vector2(400, 240)))).save_png(OUT.path_join("punta_%s.png" % endp[0]))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
