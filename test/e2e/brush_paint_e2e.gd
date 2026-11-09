# =============================================================================
# PINTURA DE LOS TRAZOS DE PINCEL (VGSE fase 4): sombreador propio con
# parámetros, filtros (duotono), degradado 2D. Capturas en user://brush_paint.
#   test/run_e2e.sh brush_paint_e2e
# =============================================================================
extends SceneTree

const OUT := "user://brush_paint"
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

const RED_SHADER := "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(tint.rgb, c.a);\n}\n"

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
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.zoom = Vector2.ONE
	cam.position = ab.global_position + ab.artboard_size / 2.0
	canvas.switch_tool("brush")
	await frames(4)
	var bt = canvas.current_tool
	bt.apply_brush_style("pen")
	bt.brush_width = 18.0
	var vs := root.get_visible_rect().size
	var o := vs * Vector2(0.3, 0.45)
	var c := PackedVector2Array()
	var cp := PackedFloat32Array()
	for i in 50:
		c.append(o + Vector2(i * 9.0, sin(i * 0.15) * 30.0))
		cp.append(0.9)
	var l := await draw(c, cp)
	l.default_color = Color(0.1, 0.1, 0.1, 1.0)
	root.get_node("SelectionManager").clear()
	canvas.switch_tool("move")
	await frames(6)
	var area := Rect2(o - Vector2(20, 60), Vector2(500, 120))
	var ic = root.get_node("InspectorCore")
	root.get_node("SelectionManager").set_selection([l])
	await frames(4)
	# 1) sombreador propio (tinte rojo como parámetro)
	ic.apply("custom_shader", {"enabled": true, "code": RED_SHADER, "params": {"tint": Color(1, 0, 0, 1)}})
	root.get_node("SelectionManager").clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("1_sombreador.png"))
	check("sombreador propio en un trazo de pincel (rojo: %d px)" % count_color(img, area, Color(1, 0, 0)), count_color(img, area, Color(1, 0, 0)) > 200)
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("custom_shader", {})
	# 2) filtro duotono
	ic.apply("filters", [{"type": "duotone", "enabled": true}])
	root.get_node("SelectionManager").clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	img2.save_png(OUT.path_join("2_filtro.png"))
	var dark := count_color(img2, area, Color(0.1, 0.1, 0.1))
	check("filtro en un trazo de pincel (cambia el color: quedan %d px del original)" % dark, dark < 50)
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("filters", [])
	# 3) textura dentro del trazo (rayas: alterna tinta y casi transparente)
	ic.apply("brush_texture", "stripes")
	ic.apply("brush_texture_scale", 1.0)
	root.get_node("SelectionManager").clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	var img3 := root.get_texture().get_image()
	img3.save_png(OUT.path_join("3_textura_rayas.png"))
	var light := count_color(img3, area, Color(0.78, 0.78, 0.78))
	check("textura «rayas» dentro del trazo (zonas claras: %d px)" % light, light > 100 and l.has_meta("brush_texture"))
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("brush_texture_mode", "paper")
	await frames(4)
	check("la textura puede seguir al papel", String(l.get_meta("brush_texture")["mode"]) == "paper")
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(ab)
	var saved := false
	for it in JSON.parse_string(JSON.stringify(data)):
		if it is Dictionary and it.has("brush_texture"):
			saved = true
	check("la textura se guarda en el archivo", saved)
	ic.apply("brush_texture", "none")
	await frames(4)
	check("«Ninguna» quita la textura", not l.has_meta("brush_texture"))
	root.get_node("HistoryManager").undo()
	await frames(4)
	check("deshacer devuelve la textura", l.has_meta("brush_texture"))
	# 4) variación de color a lo largo (con color saturado para verla)
	root.get_node("SelectionManager").set_selection([l])
	ic.apply("brush_texture", "none")
	l.default_color = Color(0.2, 0.4, 0.9, 1.0)
	ic.apply("brush_color_jitter", 1.0)
	root.get_node("SelectionManager").clear()
	await frames(10)
	await RenderingServer.frame_post_draw
	var img4 := root.get_texture().get_image()
	img4.save_png(OUT.path_join("4_variacion_color.png"))
	var hues := {}
	for x in range(int(area.position.x), int(area.end.x), 4):
		for y in range(int(area.position.y), int(area.end.y), 4):
			var px := img4.get_pixel(x, y)
			if px.s > 0.3:
				hues[int(px.h * 36.0)] = true
	check("variación de color: varios tonos a lo largo (%d)" % hues.size(), hues.size() >= 3)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
