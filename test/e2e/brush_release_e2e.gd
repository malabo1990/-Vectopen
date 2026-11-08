# =============================================================================
# Lo que se ve mientras se dibuja es lo que queda al SOLTAR el lápiz (lápiz,
# aerógrafo, rotulador, caligráfico): misma forma, grano y transparencia.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_release_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://brush_release"
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

func grab(rect: Rect2) -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().get_region(Rect2i(rect))

func diff(a: Image, b: Image) -> float:
	var strong := 0
	var ink := 0
	for y in range(0, a.get_height(), 1):
		for x in range(0, a.get_width(), 1):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.get_luminance() < 0.97 or cb.get_luminance() < 0.97:
				ink += 1
				if absf(ca.get_luminance() - cb.get_luminance()) > 0.12:
					strong += 1
	return float(strong) / maxf(1.0, ink)

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
	var vs := root.get_visible_rect().size
	var y := vs.y * 0.25
	for st in ["pencil", "airbrush", "marker", "calligraphy"]:
		bt.apply_brush_style(st)
		bt.brush_width = 14.0
		if st == "pencil":
			bt.pencil_grade = "4B"
		var a := Vector2(vs.x * 0.3, y)
		var rect := Rect2(a - Vector2(30, 45), Vector2(420, 90))
		y += 120.0
		await move(a, false, 0.0)
		await btn(a, true)
		var last := a
		for i in 80:
			var t := i / 79.0
			# temblor de mano real y presión que sube y baja
			last = a + Vector2(t * 360.0, sin(t * TAU) * 25.0 + sin(i * 1.7) * 1.2)
			await move(last, true, clampf(0.1 + 0.85 * sin(t * PI) + sin(i * 0.9) * 0.05, 0.05, 0.98))
		await frames(3)
		var before := await grab(rect)
		await btn(last, false)
		await frames(6)
		root.get_node("SelectionManager").clear()
		await frames(4)
		var after := await grab(rect)
		before.save_png(OUT.path_join("%s_antes.png" % st))
		after.save_png(OUT.path_join("%s_despues.png" % st))
		var d := diff(before, after)
		check("%s: al soltar no cambia (forma, grano, transparencia)" % st, d < 0.02, "%.1f %% de píxeles cambian" % (d * 100.0))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
