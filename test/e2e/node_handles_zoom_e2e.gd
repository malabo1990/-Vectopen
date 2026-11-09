# =============================================================================
# NODOS Y TIRADORES con mucho zoom: deben verse del MISMO tamaño en pantalla
# a cualquier zoom (como el recuadro de selección), y la línea roja del tramo
# y la marca azul, finas y cortas (estilo Affinity).
#   test/run_e2e.sh node_handles_zoom_e2e
# =============================================================================
extends SceneTree

const OUT := "user://node_handles_zoom"
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

## Píxeles del color dado (± tolerancia) alrededor de `at` (pantalla).
func count_px(img: Image, at: Vector2, half: int, col: Color, tol: float = 0.12) -> int:
	var n := 0
	for y in range(int(at.y) - half, int(at.y) + half):
		for x in range(int(at.x) - half, int(at.x) + half):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := img.get_pixel(x, y)
			if absf(p.r - col.r) < tol and absf(p.g - col.g) < tol and absf(p.b - col.b) < tol:
				n += 1
	return n

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
	var c := Curve2D.new()
	c.add_point(ac + Vector2(-200, 50), Vector2.ZERO, Vector2(60, -120))
	c.add_point(ac + Vector2(0, 0), Vector2(-80, 0), Vector2(80, 0))
	c.add_point(ac + Vector2(200, 60), Vector2(-60, -100), Vector2.ZERO)
	var path = api.add_curve(c, false, "Curva")
	path.stroke_width = 2.0
	await frames(4)
	sm.select(path)
	await frames(4)
	var tool = canvas._new_tool(load("res://script_gdscript/tools/NodeSelectionTool.gd"))
	canvas.change_tool(tool)
	await frames(6)
	tool = canvas.get_current_tool()
	tool.edit_path = path
	tool.selected_nodes.clear()
	tool.selected_nodes.append(1)
	var node_g: Vector2 = path.to_global(c.get_point_position(1))
	var areas := []
	for z in [1.0, 20.0]:
		cam.zoom = Vector2(z, z)
		cam.position = node_g
		await frames(4)
		# tramo bajo el ratón (línea roja + marca azul) en el primer segmento
		tool.hovered_segment_idx = 0
		tool.hovered_segment_point = c.sample(0, 0.97)
		tool.hovered_segment_normal = Vector2.UP
		canvas.queue_redraw()
		await frames(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT.path_join("zoom_%d.png" % int(z)))
		var scr: Vector2 = canvas.get_viewport().get_canvas_transform() * node_g
		var a := count_px(img, scr, 14, Color(0.95, 0.20, 0.20))
		areas.append(a)
		print("zoom ", z, " → nodo rojo ", a, " px")
	check("el nodo se ve (zoom 1)", areas[0] > 20, str(areas[0]))
	var ratio := float(areas[1]) / maxf(float(areas[0]), 1.0)
	check("mismo tamaño del nodo con zoom 20× que con 1× (±25 %)", ratio > 0.75 and ratio < 1.25, "%d → %d px" % [areas[0], areas[1]])
	check("nodo de ≈ 8 px (área ≤ 100 px)", areas[0] <= 100, str(areas[0]))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
