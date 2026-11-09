# =============================================================================
# CALIDAD CON MUCHO ZOOM (3100 % y 6000 %): figuras pequeñas con borde grueso
# deben verse lisas (sin facetas ni escalones en el trazo) y un trazo fino
# debe ser FINO, no una línea ancha transparente.
#   test/run_e2e.sh zoom_quality_e2e
# =============================================================================
extends SceneTree

const OUT := "user://zoom_quality"
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

## Desviación máxima (px) del borde exterior del aro negro de la elipse
## respecto a la elipse ideal, mirando en 180 direcciones desde el centro.
func ring_dev(img: Image, center: Vector2, outer: Vector2) -> float:
	var worst := 0.0
	for k in 180:
		var a := TAU * k / 180.0
		var d := Vector2(cos(a), sin(a))
		var ideal := 1.0 / sqrt(pow(d.x / outer.x, 2) + pow(d.y / outer.y, 2))
		var found := -1.0
		var r := ideal * 0.6
		while r < ideal * 1.4:
			var q := center + d * r
			if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
				break
			var lum := img.get_pixel(int(q.x), int(q.y)).get_luminance()
			if lum > 0.6 and r > ideal * 0.8:
				found = r
				break
			r += 0.25
		if found > 0.0:
			worst = maxf(worst, absf(found - ideal))
	return worst

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
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var o: Vector2 = ab.artboard_size / 2.0
	# Figuras pequeñas (como las del usuario) con borde grueso
	var el = api.add_ellipse(o + Vector2(0, 0), Vector2(4, 4.6), "Elipse")
	el.stroke_width = 1.2
	el.stroke_color = Color.BLACK
	el.fill_color = Color(0.88, 0.88, 0.88)
	var rc = api.add_rect(o + Vector2(-6, 0), Vector2(4.5, 7), 0.0, "Rect")
	rc.stroke_width = 0.9
	rc.stroke_color = Color(0.4, 0.4, 0.4)
	rc.fill_color = Color(0.88, 0.88, 0.88)
	var c := Curve2D.new()
	c.add_point(o + Vector2(-12, -12), Vector2(0, 3), Vector2(0, -3))
	c.add_point(o + Vector2(0, -16), Vector2(-6, 0), Vector2(6, 0))
	c.add_point(o + Vector2(12, -12), Vector2(0, -3), Vector2(0, 3))
	c.add_point(o + Vector2(0, -6), Vector2(8, 0), Vector2(-8, 0))
	var cp = api.add_curve(c, true, "Curva")
	cp.stroke_width = 1.5
	cp.stroke_color = Color.BLACK
	cp.fill_color = Color(0.88, 0.88, 0.88)
	var pg = api.add_star(o + Vector2(8, 2), 3.0, 5, 0.5, "Estrella")
	pg.stroke_width = 0.8
	pg.stroke_color = Color.BLACK
	# Trazo fino (Shift para adelgazar): 0,1 unidades
	var thin = api.add_curve(_line(o + Vector2(-12, 6), o + Vector2(12, 7)), false, "Fino")
	thin.stroke_width = 0.1
	thin.stroke_color = Color.BLACK
	await frames(6)
	root.get_node("SelectionManager").clear()
	for z in [31.0, 60.0]:
		cam.zoom = Vector2(z, z)
		cam.position = ab.to_global(o + Vector2(0, -3))
		await frames(8)
		await RenderingServer.frame_post_draw
		var zi := root.get_texture().get_image()
		zi.save_png(OUT.path_join("zoom_%d.png" % int(z * 100)))
		var ec: Vector2 = canvas.get_viewport().get_canvas_transform() * ab.to_global(o)
		var outer: Vector2 = (Vector2(4, 4.6) * 0.5 + Vector2(0.6, 0.6)) * z
		var dev := ring_dev(zi, ec, outer)
		check("elipse pequeña con %d %%: borde liso (≤ 2 px de la elipse ideal)" % int(z * 100), dev <= 2.0, "%.2f px" % dev)
	# Trazo fino con 6000 %: 0,1 u = 6 px de grosor real, opaco (no 60 px transparentes)
	cam.zoom = Vector2(60, 60)
	cam.position = ab.to_global(o + Vector2(0, 6.5))
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("fino_6000.png"))
	var sp: Vector2 = canvas.get_viewport().get_canvas_transform() * ab.to_global(o + Vector2(0, 6.5))
	var dark := 0
	var mid := 0
	for dy in range(-60, 61):
		var px := img.get_pixel(int(sp.x), int(sp.y) + dy)
		var lum := px.get_luminance()
		if lum < 0.35:
			dark += 1
		elif lum < 0.9:
			mid += 1
	check("trazo de 0,1 u con 6000 %: fino y opaco (≈ 6 px oscuros, sin banda gris ancha)", dark >= 3 and dark <= 10 and mid <= 6, "oscuros %d · grises %d" % [dark, mid])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)

func _line(a: Vector2, b: Vector2) -> Curve2D:
	var c := Curve2D.new()
	c.add_point(a)
	c.add_point(b)
	return c
