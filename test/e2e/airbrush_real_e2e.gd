# =============================================================================
# Trazos REALES del usuario con lápiz (aerógrafo), sacados de su copia de
# Recuperar: las puntas no deben tener «aletas» ni «pinchos».
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/airbrush_real_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://airbrush_real"
const FIXTURE := "res://test/fixtures/strokes/usuario_aerografo.json"
var fails := 0

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
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var els = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var CS = load("res://scripts/canvas/canvas_serializer.gd")
	for e in els:
		if e is Dictionary and String(e.get("kind", "")) == "line":
			e["brush_style"] = OS.get_environment("UX98_STYLE") if OS.has_environment("UX98_STYLE") else "airbrush"
	CS.instantiate_elements(ab, els)
	await frames(10)
	var cam: Camera2D = canvas.camera
	cam.position = ab.global_position + ab.artboard_size / 2.0
	cam.zoom = Vector2.ONE * minf(root.get_visible_rect().size.y / ab.artboard_size.y, 1.2)
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("todo.png"))
	check("trazos cargados", ab.get_children().filter(func(c): return c is Line2D).size() > 10)
	# Uno a uno (los anchos), con su eje en rojo, para ver de dónde sale cada fallo.
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var lines: Array = ab.get_children().filter(func(c): return c is Line2D and (c as Line2D).width >= 25.0)
	for l in lines:
		(l as Line2D).visible = false
	var dbg := Line2D.new()
	dbg.width = 1.0
	dbg.default_color = Color(1, 0, 0, 0.8)
	ab.add_child(dbg)
	for l in lines:
		var ln := l as Line2D
		ln.visible = true
		var ax: Array = R.centerline(ln)
		dbg.points = ax[0]
		dbg.position = ln.position
		var r := Rect2(ln.points[0], Vector2.ZERO)
		for q in ln.points:
			r = r.expand(q)
		r = r.grow(ln.width)
		var vs := root.get_visible_rect().size
		cam.position = ab.to_global(ln.position + r.get_center())
		cam.zoom = Vector2.ONE * clampf(minf(vs.x / r.size.x, vs.y / r.size.y) * 0.8, 0.2, 8.0)
		await frames(6)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png(OUT.path_join("uno_%s.png" % String(ln.name).replace(" ", "_")))
		ln.visible = false
		print("INFO %s eje=%d puntos (de %d)" % [ln.name, (ax[0] as PackedVector2Array).size(), ln.points.size()])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
