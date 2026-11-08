# =============================================================================
# Todos los estilos del pincel con MUCHO ZOOM (8×): curva suave, zigzag de
# picos agudos y garabato pequeño. Comprueba que el trazo pasa por donde
# iba el lápiz (desviación en px de pantalla) y guarda capturas por estilo
# en user://brush_zoom_styles.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_zoom_styles_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://brush_zoom_styles"
const ZOOM := 8.0
const MAX_DEV_PX := 3.0
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(400.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

## Sin warp_mouse: un movimiento = una muestra (warp añadía otra casi en el
## mismo sitio y la prueba no se parecía al lápiz real).
func _send(ev: InputEvent) -> void:
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

## Dibuja la lista de puntos (pantalla) con su presión; devuelve el Line2D.
func draw(pts: PackedVector2Array, prs: PackedFloat32Array) -> Line2D:
	await move(pts[0], false, 0.0)
	await btn(pts[0], true)
	for i in pts.size():
		await move(pts[i], true, prs[i])
	await btn(pts[pts.size() - 1], false)
	await frames(4)
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var l := ab.get_child(ab.get_child_count() - 1)
	if l is Line2D:
		var a0: float = (l as Line2D).default_color.a
		(l as Line2D).default_color = Color(0.16, 0.16, 0.18, a0)
		return l
	return null

## Desviación (px de pantalla) de cada muestra respecto al trazo dibujado.
func deviation(l: Line2D, pts: PackedVector2Array) -> Vector2:
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var poly := PackedVector2Array()
	for q in l.points:
		poly.append(xf * l.to_global(q))
	var worst := 0.0
	var acc := 0.0
	var cnt := 0
	for i in range(2, pts.size() - 2):
		var best := INF
		for k in poly.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(pts[i], poly[k], poly[k + 1])
			best = minf(best, c.distance_to(pts[i]))
		worst = maxf(worst, best)
		acc += best
		cnt += 1
	return Vector2(worst, acc / maxf(1, cnt))

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
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var vs := root.get_visible_rect().size
	var o := vs * Vector2(0.18, 0.3)
	var widths := {"pen": 3.0, "pencil": 3.0, "marker": 5.0, "calligraphy": 4.0, "airbrush": 6.0}
	var row := 0
	for style in ["pen", "pencil", "marker", "calligraphy", "airbrush"]:
		canvas.switch_tool("brush")
		await frames(2)
		bt = canvas.current_tool
		bt.apply_brush_style(style)
		bt.brush_width = widths[style]
		# Zona nueva del lienzo para cada estilo, con zoom 8×
		cam.zoom = Vector2.ONE * ZOOM
		cam.position = ab.global_position + Vector2(60 + row * 140, 60)
		row += 1
		await frames(6)
		# 1) curva en S con presión variable
		var c := PackedVector2Array()
		var cp := PackedFloat32Array()
		for i in 70:
			var t := i / 69.0
			c.append(o + Vector2(t * 520.0, sin(t * TAU) * 70.0))
			cp.append(clampf(0.25 + 0.7 * sin(t * PI), 0.05, 0.95))
		var l1 := await draw(c, cp)
		# 2) zigzag de picos agudos
		var z := PackedVector2Array()
		var zp := PackedFloat32Array()
		for k in 6:
			for q in 7:
				var t2 := q / 7.0
				z.append(o + Vector2(0, 230) + Vector2((k + t2) * 85.0, (90.0 * t2) if k % 2 == 0 else 90.0 * (1.0 - t2)))
				zp.append(0.8)
		var l2 := await draw(z, zp)
		# 3) garabato pequeño (lazos de 14 px de radio)
		var g := PackedVector2Array()
		var gp := PackedFloat32Array()
		for i in 96:
			var t3 := i / 95.0
			var ang := t3 * TAU * 5.0
			g.append(o + Vector2(620, 160) + Vector2(t3 * 160.0 + cos(ang) * 14.0, sin(ang) * 18.0))
			gp.append(0.6)
		var l3 := await draw(g, gp)
		root.get_node("SelectionManager").clear()
		canvas.switch_tool("move")
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().get_region(Rect2i(Rect2(o - Vector2(60, 140), Vector2(900, 520)))).save_png(OUT.path_join("%s.png" % style))
		for pair in [["curva", l1, c], ["zigzag", l2, z], ["garabato", l3, g]]:
			if pair[1] == null:
				check("%s · %s: trazo creado" % [style, pair[0]], false)
				continue
			var d := deviation(pair[1], pair[2])
			check("%s · %s sigue al lápiz (máx %.1f px, media %.2f px)" % [style, pair[0], d.x, d.y], d.x <= MAX_DEV_PX)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
