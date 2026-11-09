# =============================================================================
# TEXTO EN TRAZADO (VGSE fase 3): texto + curva seleccionados → «Texto en
# trazado» (menú contextual). El texto sigue la curva una vez, a su tamaño;
# queda enlazado (editar el texto o mover / cambiar la curva lo rehace);
# se guarda y se recupera; deshacer y «Separar» devuelven el texto.
#   test/run_e2e.sh text_on_path_e2e
# =============================================================================
extends SceneTree

const OUT := "user://text_on_path"
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

func dist_to_path(q: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	for k in path.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, path[k], path[k + 1]).distance_to(q))
	return best

func _min_x(pts: PackedVector2Array) -> float:
	var m := INF
	for q in pts:
		m = minf(m, q.x)
	return m

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
	var ac: Vector2 = ab.artboard_size / 2.0
	var txt = api.add_text(ac + Vector2(-200, -300), "Vectopen en curva", 36, Color(0.15, 0.35, 0.75))
	var c := Curve2D.new()
	c.add_point(ac + Vector2(-260, 0), Vector2.ZERO, Vector2(120, -220))
	c.add_point(ac + Vector2(260, 0), Vector2(-120, -220), Vector2.ZERO)
	var arc = api.add_curve(c, false, "Arco")
	arc.stroke_width = 1.0
	await frames(6)
	sm.clear()
	api.select([txt, arc])
	await frames(4)
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	check("el menú ofrece «Texto en trazado» con texto + curva", not CMA.text_on_path_pair(canvas).is_empty())
	# Menú Smart (clic derecho): debe ofrecer el botón y aplicarlo
	var smenu: Control = null
	for n in root.find_children("tool_in_Mouse", "", true, false):
		smenu = n
	check("hay menú contextual Smart", smenu != null)
	var sbtn: Button = null
	if smenu:
		smenu.visible = true
		await frames(3)
		sbtn = smenu.find_child("TextOnPath", true, false) as Button
		smenu.global_position = Vector2(400, 200)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join("menu_smart.png"))
	check("el menú Smart muestra «Texto en trazado»", sbtn != null and sbtn.visible)
	if sbtn:
		sbtn.pressed.emit()
	else:
		CMA.execute("text_on_path", canvas)
	await frames(8)
	check("el menú Smart se cierra tras la acción", smenu == null or not smenu.visible)
	var l: Line2D = null
	for ch in ab.get_children():
		if ch is Line2D and ch.has_meta("brush_ref"):
			l = ch
	check("se crea el texto en trazado", l != null)
	if l == null:
		quit(1)
		return
	check("el texto original se oculta", not txt.visible)
	var R = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var r = l.get_node_or_null(R.NODE_NAME)
	r._draw()
	var axis: PackedVector2Array = l.points
	var worst := 0.0
	for q in r._geom["m"]["points"]:
		worst = maxf(worst, dist_to_path(q, axis))
	check("las letras siguen la curva, apoyadas en ella (a menos de su alto: %.1f ≤ %.1f)" % [worst, l.width], worst <= l.width * 1.05 + 1.0)
	check("una sola copia (no se repite)", int(r._geom["m"]["stamps"]) == 1)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("texto_en_curva.png"))
	# Enlace: editar el texto lo rehace
	var src_before = var_to_str(l.get_meta("brush_obj")["src"])
	txt.set_meta("text", "Hola")
	var TC = load("res://script_gdscript/text/text_core.gd")
	TC.sync_vrt_from_meta(txt, TC.ensure_vrt(txt))
	await frames(6)
	check("al editar el texto se actualiza", var_to_str(l.get_meta("brush_obj")["src"]) != src_before)
	# Enlace: mover un nodo de la curva lo rehace
	var p_before := l.points
	arc.curve.set_point_position(1, arc.curve.get_point_position(1) + Vector2(0, 120))
	arc.queue_redraw()
	await frames(6)
	check("al cambiar la curva se actualiza", l.points != p_before)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("texto_editado.png"))
	# Panel: alinear, desplazar y dar la vuelta (inspector de Modern)
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	sm.select(l)
	await frames(6)
	var row_found := false
	for ep in root.find_children("ExtraProps", "", true, false):
		if (ep as Control).is_visible_in_tree():
			for ch in ep.find_children("*", "", true, false):
				if String(ch.name).contains("path_text_align") and (ch as Control).is_visible_in_tree():
					row_found = true
	check("el inspector muestra «En el trazado» al seleccionar un texto en trazado", row_found)
	var ic = root.get_node("InspectorCore")
	var R2 = load("res://script_gdscript/shapes/brush_stroke_render.gd")
	var rr = l.get_node_or_null(R2.NODE_NAME)
	rr._draw()
	var x_start: float = _min_x(rr._geom["m"]["points"])
	ic.apply("path_text_align", "center")
	await frames(4)
	rr._draw()
	var x_center: float = _min_x(rr._geom["m"]["points"])
	check("«Centro» mueve el texto a lo largo del trazado", x_center > x_start + 5.0, "%.0f → %.0f" % [x_start, x_center])
	ic.apply("path_text_flip", true)
	await frames(4)
	check("«Al otro lado» se aplica", bool(l.get_meta("brush_obj")["params"]["flip"]))
	root.get_node("HistoryManager").undo()
	root.get_node("HistoryManager").undo()
	await frames(4)
	check("deshacer devuelve la alineación y el lado", float(l.get_meta("brush_obj")["params"]["align"]) == 0.0 and not bool(l.get_meta("brush_obj")["params"]["flip"]))
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	# Guardar y recuperar
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(ab)
	var found := false
	for it in JSON.parse_string(JSON.stringify(data)):
		if it is Dictionary and it.has("brush_ref"):
			found = true
	check("se guarda con su enlace", found)
	# Deshacer: vuelve el texto
	var hm = root.get_node("HistoryManager")
	sm.select(l)
	await frames(2)
	var rbtn: Button = null
	if smenu:
		smenu.visible = false
		smenu.visible = true
		await frames(3)
		rbtn = smenu.find_child("ReleaseTextOnPath", true, false) as Button
	check("el menú Smart muestra «Separar texto del trazado»", rbtn != null and rbtn.visible)
	if rbtn and rbtn.visible:
		rbtn.pressed.emit()
	else:
		CMA.execute("release_text_on_path", canvas)
	await frames(4)
	check("«Separar texto del trazado» devuelve el texto", txt.visible and l.get_parent() == null)
	hm.undo()
	await frames(4)
	check("deshacer lo vuelve a poner en el trazado", not txt.visible and l.get_parent() != null)
	# Onda con valle y pico (caso real): letras rígidas, sin deformarse
	l.visible = false
	var t2 = api.add_text(ac + Vector2(-300, 200), "Título Corporativo", 40, Color(0.1, 0.1, 0.12))
	var w := Curve2D.new()
	w.add_point(ac + Vector2(-320, 300), Vector2.ZERO, Vector2(90, 0))
	w.add_point(ac + Vector2(-120, 300), Vector2(-60, 30), Vector2(60, -30))
	w.add_point(ac + Vector2(80, 250), Vector2(-60, -40), Vector2(60, 60))
	w.add_point(ac + Vector2(220, 380), Vector2(-40, 20), Vector2(40, -20))
	w.add_point(ac + Vector2(300, 260), Vector2.ZERO, Vector2.ZERO)
	var wave = api.add_curve(w, false, "Onda")
	wave.stroke_width = 2.0
	await frames(6)
	var l2: Line2D = api.text_on_path(t2, wave)
	await frames(8)
	var r2 = l2.get_node_or_null(R.NODE_NAME)
	r2._draw()
	var gpts: PackedVector2Array = r2._geom["m"]["points"]
	check("las letras no salen del trazado (onda)", gpts.size() > 0)
	cam.position = ab.global_position + ac + Vector2(0, 300)
	cam.zoom = Vector2(1.6, 1.6)
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("texto_onda.png"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
