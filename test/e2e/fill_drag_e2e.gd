# =============================================================================
# RELLENO estable al ARRASTRAR un nodo a través de otro tramo (caso del
# usuario: el relleno parpadeaba y salían errores en el depurador). En cada
# fotograma del arrastre las dos zonas deben seguir rellenas.
#   test/run_e2e.sh fill_drag_e2e
# =============================================================================
extends SceneTree

const OUT := "user://fill_drag"
const FILL := Color(0.2, 0.4, 0.9)
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

func is_fill(img: Image, sp: Vector2) -> bool:
	var px := img.get_pixel(int(sp.x), int(sp.y))
	return absf(px.r - FILL.r) < 0.12 and absf(px.g - FILL.g) < 0.12 and absf(px.b - FILL.b) < 0.12

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
	var o: Vector2 = ab.artboard_size / 2.0 - Vector2(300, 250)
	# La figura del usuario (imagen 9): un nodo cae justo sobre otro tramo.
	var c := Curve2D.new()
	c.add_point(o + Vector2(250, 85))
	c.add_point(o + Vector2(533, 241))
	c.add_point(o + Vector2(351, 201))
	c.add_point(o + Vector2(206.8, 228), Vector2(-3, 0), Vector2(3, 0))
	c.add_point(o + Vector2(97, 285), Vector2(3, -3), Vector2(-3, 3))
	c.add_point(o + Vector2(148, 423), Vector2(-4, 0), Vector2(4, 0))
	var path = api.add_curve(c, true, "Toca")
	path.fill_color = FILL
	path.stroke_width = 3.0
	path.stroke_color = Color(0.1, 0.1, 0.1)
	await frames(4)
	cam.zoom = Vector2.ONE
	cam.position = path.to_global(o + Vector2(300, 250))
	await frames(4)
	sm.select(path)
	await frames(4)
	canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/NodeSelectionTool.gd")))
	await frames(6)
	canvas.get_current_tool().edit_path = path
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var n4_g: Vector2 = path.to_global(c.get_point_position(3))
	var a := xf * n4_g
	var up_probe: Vector2 = xf * path.to_global(o + Vector2(400, 190))    # zona de arriba
	var low_probe: Vector2 = xf * path.to_global(o + Vector2(140, 330))   # zona de abajo
	await move(a, false)
	await btn(a, true)
	var missing := 0
	var steps := 0
	for i in range(-30, 31):
		var p := a + Vector2(i * 0.5, i * 0.15)
		await move(p, true)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		steps += 1
		if not (is_fill(img, up_probe) and is_fill(img, low_probe)):
			missing += 1
			if missing <= 3:
				img.save_png(OUT.path_join("sin_relleno_%d.png" % missing))
	await btn(a + Vector2(15, 4.5), false)
	await frames(3)
	check("el relleno no parpadea al arrastrar el nodo (fotogramas sin relleno)", missing == 0, "%d de %d" % [missing, steps])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
