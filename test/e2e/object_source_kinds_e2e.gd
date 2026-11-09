# =============================================================================
# «Selección» del pincel de objeto con TODO tipo de objetos, como el
# usuario: herramienta Mover → seleccionar (uno o un grupo) → botón del
# pincel en la barra → estilo Objeto → «Selección» → dibujar.
# Rectángulo, polígono, estrella, curva Bézier abierta (solo trazo), trazo
# de pincel y grupo. Capturas en user://object_source_kinds.
#   test/run_e2e.sh object_source_kinds_e2e
# =============================================================================
extends SceneTree

const OUT := "user://object_source_kinds"
const ZOOM := 1.0
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

func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	_send(mm)
	await process_frame
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = p
		mb.global_position = p
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		_send(mb)
		await process_frame

## Cobertura a lo largo del trazo (fracción de muestras con tinta debajo):
## un aerógrafo en «rosario» deja huecos.
func coverage(img: Image, pts: PackedVector2Array) -> float:
	var hit := 0
	for i in range(3, pts.size() - 3):
		var q := pts[i]
		if img.get_pixel(int(q.x), int(q.y)).get_luminance() < 0.97:
			hit += 1
	return hit / float(maxi(1, pts.size() - 6))

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
	var api = root.get_node("PluginManager").api
	var sm = root.get_node("SelectionManager")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.zoom = Vector2.ONE
	cam.position = ab.global_position + ab.artboard_size / 2.0
	await frames(6)
	var vs := root.get_visible_rect().size
	var ac: Vector2 = ab.artboard_size / 2.0
	# Un trazo de pincel de verdad (dibujado con el pincel, estilo pluma)
	canvas.switch_tool("brush")
	await frames(4)
	canvas.current_tool.apply_brush_style("pen")
	canvas.current_tool.brush_width = 8.0
	var bs := PackedVector2Array()
	var bp := PackedFloat32Array()
	for i in 30:
		bs.append(vs * Vector2(0.25, 0.2) + Vector2(i * 4.0, sin(i * 0.3) * 10.0))
		bp.append(0.8)
	var stroke := await draw(bs, bp)
	var rect = api.add_rect(ac + Vector2(-250, -200), Vector2(50, 25))
	api.set_fill(rect, Color(0.9, 0.1, 0.1))
	var poly = api.add_polygon(ac + Vector2(-170, -200), 18, 6)
	var star = api.add_star(ac + Vector2(-110, -200), 18, 5)
	var curve = api.add_path(PackedVector2Array([ac + Vector2(-60, -210), ac + Vector2(-30, -190), ac + Vector2(0, -210)]), false, "Curva")
	curve.stroke_width = 4.0
	var ga = api.add_rect(ac + Vector2(60, -200), Vector2(20, 20))
	var gb = api.add_ellipse(ac + Vector2(90, -200), Vector2(20, 20))
	api.set_fill(gb, Color(0.1, 0.3, 0.9))
	var grp = api.group([ga, gb])
	var txt = api.add_text(ac + Vector2(140, -230), "Ao", 40, Color(0.2, 0.5, 0.2))
	await frames(6)
	var cases := [["rectángulo", [rect]], ["polígono", [poly]], ["estrella", [star]],
		["curva Bézier abierta", [curve]], ["trazo de pincel", [stroke]], ["grupo", [grp]],
		["varios a la vez", [rect, star, curve]], ["texto", [txt]]]
	var row := 0
	for cs in cases:
		var label: String = cs[0]
		# Como el usuario: herramienta Mover (su botón), seleccionar, botón del pincel
		var mv: Button = null
		for x in root.find_children("*", "Button", true, false):
			if (x as Button).is_visible_in_tree() and String(x.name) == "Button" and String(x.get_parent().name) == "ToolbarContainer_button_tool":
				mv = x
		if mv:
			await click(mv)
		else:
			canvas.switch_tool("move")
		await frames(4)
		sm.clear()
		api.select(cs[1])
		await frames(4)
		var tb: Button = null
		for x in root.find_children("*", "Button", true, false):
			if (x as Button).is_visible_in_tree() and String(x.name) == "button_toolbrush":
				tb = x
		await click(tb)
		await frames(8)
		var bt = canvas.current_tool
		var so := root.find_child("Style_object", true, false) as Button
		if so and bt.brush_style != "object":
			await click(so)
			await frames(4)
		var fs := root.find_child("ObjFromSelection", true, false) as Button
		bt.object_params["mode"] = "stamp"   # copias rígidas (no heredar el patrón)
		bt.object_source = []
		await click(fs)
		await frames(4)
		var pieces := 0
		for o in bt.object_source:
			pieces += (o as Array).size()
		check("%s: «Selección» lo convierte en pincel (%d piezas)" % [label, pieces], pieces > 0)
		if pieces == 0:
			continue
		bt.brush_width = 24.0
		var o0 := vs * Vector2(0.2, 0.42) + Vector2(0, row * 70)
		row += 1
		var c := PackedVector2Array()
		var cp := PackedFloat32Array()
		for i in 50:
			var t := i / 49.0
			c.append(o0 + Vector2(t * 500.0, sin(t * TAU) * 20.0))
			cp.append(0.8)
		var l := await draw(c, cp)
		var r = l.get_node_or_null(load("res://script_gdscript/shapes/brush_stroke_render.gd").NODE_NAME) if l else null
		check("%s: se dibuja con él" % label, r != null and int(r._geom["m"]["stamps"]) > 3)
	sm.clear()
	canvas.switch_tool("move")
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("todos.png"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
