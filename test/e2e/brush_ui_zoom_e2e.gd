# =============================================================================
# Estilos del pincel ELEGIDOS EN EL PANEL (clic real en cada botón) con zoom
# EXTREMO (~5000 %, como el usuario) y el grosor mínimo: curva con presión
# de suave a fuerte, trazo muy suave, zigzag y garabato. Comprueba que se
# siga al lápiz y que el aerógrafo sea continuo (sin «rosario» de puntos).
# Capturas de la ventana COMPLETA (con la interfaz) en user://brush_ui_zoom.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_ui_zoom_e2e.gd
# =============================================================================
extends SceneTree

const OUT := "user://brush_ui_zoom"
const ZOOM := 50.0
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
	canvas.switch_tool("brush")
	await frames(10)
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var vs := root.get_visible_rect().size
	var o := vs * Vector2(0.12, 0.25)
	var row := 0
	for style in ["pencil", "pen", "marker", "calligraphy", "airbrush"]:
		# Abrir el pincel con su botón de la barra (como el usuario): eso
		# muestra el panel «Pincel y estilos».
		var btn_s := root.find_child("Style_" + style, true, false) as Button
		if btn_s == null or not btn_s.is_visible_in_tree():
			var tb: Button = null
			for x in root.find_children("*", "Button", true, false):
				var bx := x as Button
				if bx.is_visible_in_tree() and (String(bx.name).to_lower().contains("brush") or String(bx.tooltip_text).to_lower().contains("pincel") or String(bx.tooltip_text).to_lower().contains("brush")) and not String(bx.name).begins_with("Style_"):
					tb = bx
					break
			if tb:
				print("INFO botón de la barra: %s «%s»" % [tb.name, tb.tooltip_text])
				await click(tb)
				await frames(10)
			btn_s = root.find_child("Style_" + style, true, false) as Button
		check("%s: botón del panel visible" % style, btn_s != null and btn_s.is_visible_in_tree())
		if btn_s == null or not btn_s.is_visible_in_tree():
			continue
		await click(btn_s)
		await frames(4)
		var bt = canvas.current_tool
		check("%s: el clic elige el estilo" % style, bt.brush_style == style, bt.brush_style)
		bt.brush_width = bt.MIN_BRUSH_WIDTH * 1.2
		cam.zoom = Vector2.ONE * ZOOM
		cam.position = ab.global_position + Vector2(60 + row * 40, 60)
		row += 1
		await frames(6)
		# curva: presión de suave a fuerte y otra vez suave
		var c := PackedVector2Array()
		var cp := PackedFloat32Array()
		for i in 70:
			var t := i / 69.0
			c.append(o + Vector2(t * 520.0, sin(t * TAU) * 70.0))
			cp.append(clampf(0.1 + 0.85 * sin(t * PI), 0.05, 0.95))
		var l1 := await draw(c, cp)
		# trazo MUY suave
		var s := PackedVector2Array()
		var sp := PackedFloat32Array()
		for i in 50:
			s.append(o + Vector2(0, 170) + Vector2(i * 10.0, sin(i * 0.3) * 12.0))
			sp.append(0.15)
		var l2 := await draw(s, sp)
		# zigzag
		var z := PackedVector2Array()
		var zp := PackedFloat32Array()
		for k in 6:
			for q in 7:
				var t2 := q / 7.0
				z.append(o + Vector2(0, 260) + Vector2((k + t2) * 85.0, (90.0 * t2) if k % 2 == 0 else 90.0 * (1.0 - t2)))
				zp.append(0.7)
		var l3 := await draw(z, zp)
		# garabato
		var g := PackedVector2Array()
		var gp := PackedFloat32Array()
		for i in 96:
			var t3 := i / 95.0
			var ang := t3 * TAU * 5.0
			g.append(o + Vector2(620, 120) + Vector2(t3 * 160.0 + cos(ang) * 14.0, sin(ang) * 18.0))
			gp.append(0.6)
		var l4 := await draw(g, gp)
		root.get_node("SelectionManager").clear()
		await frames(8)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT.path_join("%s.png" % style))
		for pair in [["curva", l1, c], ["muy suave", l2, s], ["zigzag", l3, z], ["garabato", l4, g]]:
			if pair[1] == null:
				check("%s · %s: trazo creado" % [style, pair[0]], false)
				continue
			var d := deviation(pair[1], pair[2])
			var cov := coverage(img, pair[2])
			check("%s · %s sigue al lápiz (máx %.1f px) y es continuo (%.0f %% con tinta)" % [style, pair[0], d.x, cov * 100.0], d.x <= MAX_DEV_PX and cov >= 0.9)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
