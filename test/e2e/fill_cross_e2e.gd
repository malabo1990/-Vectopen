# =============================================================================
# RELLENO de un trazado cerrado que se CRUZA consigo mismo (caso del usuario):
# todas las zonas cerradas se rellenan (regla «no cero», como Illustrator /
# Affinity), no solo una.
#   test/run_e2e.sh fill_cross_e2e
# =============================================================================
extends SceneTree

const OUT := "user://fill_cross"
const FILL := Color(0.2, 0.4, 0.9)
var fails := 0

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
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var o: Vector2 = ab.artboard_size / 2.0 - Vector2(480, 300)
	# Como la figura del usuario: línea arriba, triángulo derecho, pico y lazo izquierdo
	var c := Curve2D.new()
	c.add_point(o + Vector2(227, 163))
	c.add_point(o + Vector2(550, 205), Vector2(-40, -5), Vector2(40, 5))
	c.add_point(o + Vector2(752, 253), Vector2(0, -20), Vector2(0, 20))
	c.add_point(o + Vector2(570, 390), Vector2(60, -40), Vector2(-30, 20))
	c.add_point(o + Vector2(390, 90), Vector2(40, 0), Vector2(-40, 0))
	c.add_point(o + Vector2(243, 511), Vector2(30, 0), Vector2(-30, 0))
	c.add_point(o + Vector2(222, 420), Vector2(0, 30), Vector2(0, -30))
	var path = api.add_curve(c, true, "Cruzada")
	path.fill_color = FILL
	path.stroke_width = 6.0
	path.stroke_color = Color(0.1, 0.1, 0.1)
	await frames(4)
	sm_clear()
	cam.zoom = Vector2.ONE
	cam.position = path.to_global(o + Vector2(480, 300))
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("cruzada.png"))
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	for spot in [["triángulo derecho", Vector2(640, 270)], ["lazo izquierdo", Vector2(262, 300)], ["pico de arriba", Vector2(400, 140)]]:
		var sp: Vector2 = xf * path.to_global(o + spot[1])
		var px := img.get_pixel(int(sp.x), int(sp.y))
		check("se rellena el %s" % spot[0], absf(px.r - FILL.r) < 0.12 and absf(px.g - FILL.g) < 0.12 and absf(px.b - FILL.b) < 0.12, str(px))
	var out_sp: Vector2 = xf * path.to_global(o + Vector2(700, 450))
	var po := img.get_pixel(int(out_sp.x), int(out_sp.y))
	check("fuera de la figura no hay relleno", absf(po.b - FILL.b) > 0.05 or absf(po.r - FILL.r) > 0.2, str(po))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)

func sm_clear() -> void:
	var sm = root.get_node_or_null("SelectionManager")
	if sm and sm.has_method("clear"):
		sm.clear()
