# =============================================================================
# Garabatos con el LÁPIZ (curvas muy cerradas que se cruzan, presión
# variable): sin tubos cortados donde el trazo se pisa, borde que llega a
# transparente. Capturas a tamaño real y con zoom en user://pencil_scribble.
# (cabecera original:) Lápiz de grafito con durezas (2H … 8B): grano del papel común a todos los
# trazos, la presión rellena el grano, las blandas más oscuras. Capturas a
# tamaño real y con zoom. Comprueba que cada dureza oscurece más que la
# anterior y que el selector del panel cambia la dureza del pincel.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/pencil_grades_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://pencil_scribble"
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

func scribble(c: Vector2, r: float, turns: int, w: float) -> void:
	var a := c
	await move(a, false, 0.0)
	await btn(a, true)
	var n := turns * 24
	for i in n:
		var t := i / float(n - 1)
		var ang := t * TAU * turns
		var p := c + Vector2(t * 260.0 + cos(ang) * r, sin(ang) * r * 1.3)
		await move(p, true, clampf(0.3 + 0.6 * sin(t * PI), 0.05, 0.95))
	await btn(c + Vector2(260 + r, 0), false)
	await frames(4)
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var l := ab.get_child(ab.get_child_count() - 1)
	if l is Line2D:
		(l as Line2D).default_color = Color(0.16, 0.16, 0.18, 1.0)
	await frames(2)

## Zigzag de picos agudos (giros más cerrados que el grosor).
func zigzag(a: Vector2, teeth: int, amp: float, step: float) -> void:
	await move(a, false, 0.0)
	await btn(a, true)
	for k in teeth:
		for q in 8:
			var t := q / 8.0
			var x0 := a.x + (k + t) * step
			var y := a.y + (amp * t if k % 2 == 0 else amp * (1.0 - t))
			await move(Vector2(x0, y), true, 0.85)
	await btn(a + Vector2(teeth * step, 0), false)
	await frames(4)
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var l := ab.get_child(ab.get_child_count() - 1)
	if l is Line2D:
		(l as Line2D).default_color = Color(0.16, 0.16, 0.18, 1.0)
	await frames(2)

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
	bt.apply_brush_style("pencil")
	bt.pencil_grade = "HB"
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.position = ab.global_position + ab.artboard_size / 2.0
	cam.zoom = Vector2.ONE
	await frames(6)
	var vs := root.get_visible_rect().size
	bt.brush_width = 14.0
	await scribble(Vector2(vs.x * 0.3, vs.y * 0.3), 22.0, 7, 14.0)
	bt.brush_width = 6.0
	await scribble(Vector2(vs.x * 0.3, vs.y * 0.5), 10.0, 9, 6.0)
	# Curvas MÁS cerradas que el grosor (garabato apretado)
	bt.brush_width = 16.0
	await scribble(Vector2(vs.x * 0.3, vs.y * 0.62), 5.0, 14, 16.0)
	bt.brush_width = 24.0
	await zigzag(Vector2(vs.x * 0.3, vs.y * 0.72), 9, 60.0, 30.0)
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.get_region(Rect2i(Rect2(Vector2(vs.x * 0.25, vs.y * 0.2), Vector2(vs.x * 0.35, vs.y * 0.68)))).save_png(OUT.path_join("garabatos.png"))
	cam.position = canvas.get_viewport().get_canvas_transform().affine_inverse() * Vector2(vs.x * 0.3 + 100, vs.y * 0.3)
	cam.zoom = Vector2.ONE * 3.0
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(Rect2(vs / 2.0 - Vector2(400, 220), Vector2(800, 440)))).save_png(OUT.path_join("garabato_zoom.png"))
	print("RESULT: OK")
	quit(0)
