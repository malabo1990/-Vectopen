# =============================================================================
# MÁSCARAS Y EFECTOS EN TRAZOS DE PINCEL (VGSE fase 5): un trazo dentro de una
# figura con máscara de recorte solo se ve dentro; sombra paralela en un
# trazo. Capturas en user://brush_mask_fx.
#   test/run_e2e.sh brush_mask_fx_e2e
# =============================================================================
extends SceneTree

const OUT := "user://brush_mask_fx"
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

func count_color(img: Image, r: Rect2, target: Color) -> int:
	var n := 0
	for y in range(int(r.position.y), int(r.end.y), 2):
		for x in range(int(r.position.x), int(r.end.x), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - target.r) < 0.12 and absf(c.g - target.g) < 0.12 and absf(c.b - target.b) < 0.12:
				n += 1
	return n

func _yspread(pts: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for q in pts:
		lo = minf(lo, q.y)
		hi = maxf(hi, q.y)
	return hi - lo

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
	await frames(10)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.zoom = Vector2.ONE
	cam.position = ab.global_position + ab.artboard_size / 2.0
	await frames(6)
	canvas.switch_tool("brush")
	await frames(4)
	var bt = canvas.current_tool
	bt.apply_brush_style("pen")
	bt.brush_width = 16.0
	var vs := root.get_visible_rect().size
	var o := vs * Vector2(0.25, 0.4)
	var c := PackedVector2Array()
	var cp := PackedFloat32Array()
	for i in 60:
		c.append(o + Vector2(i * 9.0, 0))
		cp.append(0.9)
	var l := await draw(c, cp)
	l.default_color = Color(0.1, 0.1, 0.1, 1.0)
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(4)
	# 1) máscara: figura que cubre solo la mitad central del trazo
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var mid_world: Vector2 = xf.affine_inverse() * (o + Vector2(270, 0))
	var mask = api.add_rect(ab.to_local(mid_world), Vector2(160, 80))
	api.set_fill(mask, Color(0.9, 0.9, 0.95))
	await frames(4)
	var gl := l.global_transform
	l.reparent(mask)
	l.global_transform = gl
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.set_meta("clip_mask", true)
	await frames(10)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("1_mascara.png"))
	var inside := count_color(img, Rect2(o + Vector2(230, -10), Vector2(80, 20)), Color(0.1, 0.1, 0.1))
	var outside := count_color(img, Rect2(o + Vector2(10, -10), Vector2(120, 20)), Color(0.1, 0.1, 0.1))
	check("máscara de recorte: el trazo se ve dentro (%d px) y no fuera (%d px)" % [inside, outside], inside > 50 and outside < 5)
	# 2) sombra paralela en el trazo
	var gl2 := l.global_transform
	l.reparent(ab)
	l.global_transform = gl2
	mask.queue_free()
	await frames(4)
	var ic = root.get_node("InspectorCore")
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("effects", [{"type": "drop_shadow", "enabled": true, "color": Color(0.8, 0.1, 0.1, 1.0), "offset_x": 0.0, "offset_y": 24.0, "blur": 0.0}])
	root.get_node("SelectionManager").clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	img2.save_png(OUT.path_join("2_sombra.png"))
	var shadow := count_color(img2, Rect2(o + Vector2(0, 14), Vector2(540, 30)), Color(0.8, 0.1, 0.1))
	check("sombra paralela en un trazo de pincel (%d px rojos debajo)" % shadow, shadow > 100)
	# 3) efecto geométrico (ondulado): la forma real se mueve por la normal
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("effects", [])
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var flat: Array = R.centerline(l)
	var spread0 := _yspread(flat[0])
	ic.apply("brush_geo", "wave")
	ic.apply("brush_geo_amount", 1.0)
	await frames(6)
	var wav: Array = R.centerline(l)
	var spread1 := _yspread(wav[0])
	check("«Ondulado» cambia la forma real del trazo (alto %.1f → %.1f)" % [spread0, spread1], spread1 > spread0 + l.width)
	var api2 = root.get_node("PluginManager").api
	var outl = api2.stroke_to_outline(l)
	await frames(4)
	var ob := Rect2()
	if outl:
		var pts2: PackedVector2Array = outl.curve.get_baked_points()
		ob = Rect2(pts2[0], Vector2.ZERO)
		for q in pts2:
			ob = ob.expand(q)
	check("convertir en contorno conserva la onda (alto %.1f)" % ob.size.y, outl != null and ob.size.y > l.width * 2.5)
	root.get_node("HistoryManager").undo()
	await frames(4)
	root.get_node("SelectionManager").clear()
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("3_ondulado.png"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
