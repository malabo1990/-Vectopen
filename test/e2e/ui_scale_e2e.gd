# =============================================================================
# TAMAÑO DE LA INTERFAZ (4K / pantallas pequeñas): la escala se aplica a toda
# la ventana; dibujar cae donde va el lápiz a cualquier escala; atajos
# Ctrl+Alt+= / - / 0; selector de Ajustes; se guarda; en una ventana
# pequeña (1024×600, 85 %) los paneles caben. Capturas en user://ui_scale.
#   test/run_e2e.sh ui_scale_e2e
# =============================================================================
extends SceneTree

const OUT := "user://ui_scale"
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
	# Con la interfaz escalada, los eventos llegan en px REALES de la ventana
	# (como los del ratón de verdad): de coordenadas de la UI a la ventana.
	if ev is InputEventMouse:
		var m := ev as InputEventMouse
		m.position = root.get_final_transform() * m.position
		m.global_position = m.position
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

func key(code: int) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = true
		ev.alt_pressed = true
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
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
	await frames(10)
	var svc := root.get_node_or_null("UIScaleService")
	check("servicio de escala instalado", svc != null)
	if svc == null:
		quit(1)
		return
	print("INFO escala automática en esta pantalla: %.2f" % svc.auto_scale())
	canvas = get_first_node_in_group("_vectopen_canvas")
	var tb: Button = null
	for x in root.find_children("*", "Button", true, false):
		if (x as Button).is_visible_in_tree() and String(x.name) == "button_toolbrush":
			tb = x
	svc.set_scale(1.0, false)
	await frames(10)
	var w1: float = (tb.get_global_transform_with_canvas().get_scale().x * tb.size.x) if tb else 0.0
	for sc in [0.8, 1.0, 1.5, 2.0]:
		svc.set_scale(sc, false)
		await frames(12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join("escala_%d.png" % int(sc * 100)))
	svc.set_scale(1.5, false)
	await frames(12)
	check("la escala se aplica a toda la ventana (1,5)", is_equal_approx(root.content_scale_factor, 1.5))
	var w15: float = (tb.get_global_transform_with_canvas().get_scale().x * tb.size.x) * root.content_scale_factor if tb else 0.0
	check("los botones crecen en proporción (%.0f → %.0f px)" % [w1, w15], w15 > w1 * 1.4 and w15 < w1 * 1.6)
	# Dibujar a escala 1,5: el trazo cae donde va el lápiz
	await click(tb)
	await frames(6)
	var bt = canvas.current_tool
	bt.apply_brush_style("pen")
	bt.brush_width = 4.0
	var vs := root.get_visible_rect().size
	var c := PackedVector2Array()
	var cp := PackedFloat32Array()
	for i in 30:
		c.append(vs * Vector2(0.3, 0.5) + Vector2(i * 8.0, 0))
		cp.append(0.8)
	var l := await draw(c, cp)
	var xf: Transform2D = canvas.get_viewport().get_canvas_transform()
	var d := INF
	if l:
		d = (xf * l.to_global(l.points[0])).distance_to(c[0])
	check("a escala 1,5 el trazo empieza donde va el lápiz (%.1f px)" % d, d < 3.0)
	# Atajos
	await key(KEY_EQUAL)
	await frames(4)
	check("Ctrl+Alt+= sube un paso (1,5 → 1,75)", is_equal_approx(svc.current_scale(), 1.75), str(svc.current_scale()))
	await key(KEY_MINUS)
	await key(KEY_MINUS)
	await frames(4)
	check("Ctrl+Alt+- baja (→ 1,25)", is_equal_approx(svc.current_scale(), 1.25), str(svc.current_scale()))
	var toast := root.find_child("UIScaleToast", true, false) as Label
	check("aviso con el tamaño («Interfaz 125 %»)", toast != null and toast.visible and toast.text.contains("125"), toast.text if toast else "")
	await key(KEY_0)
	await frames(4)
	check("Ctrl+Alt+0 vuelve a automático", svc.is_auto())
	var cfg := ConfigFile.new()
	svc.set_scale(1.1, false)
	check("se guarda la elección", cfg.load("user://ui_scale.cfg") == OK and is_equal_approx(float(cfg.get_value("ui", "scale", 0.0)), 1.1))
	# Ventana pequeña (portátil de 10"): 1024×600 al 85 %: el panel cabe
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1024, 600))
	svc.set_scale(0.85, false)
	await frames(20)
	var panel := root.find_child("brush", true, false) as Control
	var vr := root.get_visible_rect()
	var fits := panel != null and panel.is_visible_in_tree() and vr.encloses(panel.get_global_rect().grow(-1))
	check("ventana 1024×600 al 85 %: el panel del pincel cabe (%s en %s)" % [str(panel.get_global_rect() if panel else Rect2()), str(vr)], fits)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("pequena_1024x600.png"))
	svc.set_scale(0.0, false)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
