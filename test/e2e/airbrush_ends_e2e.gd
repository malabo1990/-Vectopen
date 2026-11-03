# =============================================================================
# Aerógrafo: el INICIO y el FINAL del trazo (con ratón y con lápiz que sube
# y baja la presión) — capturas con zoom en cada punta.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/airbrush_ends_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://airbrush_ends"
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(150.0).timeout.connect(func() -> void:
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

func zoom_shot(name: String, at_screen: Vector2) -> void:
	var cam: Camera2D = canvas.camera
	var keep_pos := cam.position
	var keep_zoom := cam.zoom
	cam.position = canvas.get_viewport().get_canvas_transform().affine_inverse() * at_screen
	cam.zoom = keep_zoom * 5.0
	await frames(8)
	await RenderingServer.frame_post_draw
	var vs := root.get_visible_rect().size
	root.get_texture().get_image().get_region(Rect2i(Rect2(vs / 2.0 - Vector2(250, 160), Vector2(500, 320)))).save_png(OUT.path_join(name + ".png"))
	cam.position = keep_pos
	cam.zoom = keep_zoom
	await frames(4)

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
	bt.apply_brush_style("airbrush")
	var vs := root.get_visible_rect().size
	var ends := []
	for kind in ["raton", "lapiz"]:
		var o := Vector2(vs.x * 0.3, vs.y * (0.35 if kind == "raton" else 0.6))
		var pts := []
		for i in 60:
			var t := i / 59.0
			pts.append(o + Vector2(t * 360.0, sin(t * PI * 1.5) * 50.0))
		await move(pts[0], false, 0.0)
		await btn(pts[0], true)
		for i in pts.size():
			var t := i / 59.0
			var pr := 1.0 if kind == "raton" else clampf(0.15 + 0.85 * sin(t * PI), 0.05, 0.98)
			await move(pts[i], true, pr)
		await btn(pts[pts.size() - 1], false)
		await frames(6)
		ends.append([kind, pts[0], pts[pts.size() - 1]])
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(6)
	for e in ends:
		await zoom_shot("%s_inicio" % e[0], e[1])
		await zoom_shot("%s_final" % e[0], e[2])
	check("capturas hechas", true)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
