# =============================================================================
# PINCEL DE OBJETO por la interfaz (VGSE fase 2): dos figuras de colores
# seleccionadas → panel Pincel ▸ Objeto ▸ «Selección» → trazo con presión.
# Las figuras salen estampadas a lo largo; «Una a una» las alterna; el trazo
# se guarda y se recupera igual; las figuras de serie funcionan. Capturas en
# user://object_brush.
#   test/run_e2e.sh object_brush_e2e
# =============================================================================
extends SceneTree

const OUT := "user://object_brush"
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

func wave(o: Vector2, w: float, amp: float) -> Array:
	var c := PackedVector2Array()
	var cp := PackedFloat32Array()
	for i in 60:
		var t := i / 59.0
		c.append(o + Vector2(t * w, sin(t * TAU) * amp))
		cp.append(clampf(0.3 + 0.6 * sin(t * PI), 0.05, 0.95))
	return [c, cp]

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
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	cam.zoom = Vector2.ONE
	cam.position = ab.global_position + ab.artboard_size / 2.0
	await frames(6)
	var vs := root.get_visible_rect().size
	var ac: Vector2 = ab.artboard_size / 2.0
	var RED := Color(0.9, 0.1, 0.1)
	var BLUE := Color(0.1, 0.3, 0.9)
	var r1 = api.add_rect(ac + Vector2(-260, -260), Vector2(60, 30))
	api.set_fill(r1, RED)
	var e1 = api.add_ellipse(ac + Vector2(-190, -260), Vector2(30, 30))
	api.set_fill(e1, BLUE)
	api.select([r1, e1])
	await frames(6)
	# abrir el pincel con su botón y elegir Objeto
	var tb: Button = null
	for x in root.find_children("*", "Button", true, false):
		var bx := x as Button
		if bx.is_visible_in_tree() and String(bx.name) == "button_toolbrush":
			tb = bx
	check("botón del pincel en la barra", tb != null)
	if tb == null:
		quit(1)
		return
	await click(tb)
	await frames(10)
	var bt = canvas.current_tool
	# (sin volver a seleccionar: «Selección» usa lo seleccionado al elegir el pincel)
	var so := root.find_child("Style_object", true, false) as Button
	check("estilo Objeto en el panel", so != null and so.is_visible_in_tree())
	await click(so)
	await frames(4)
	check("Objeto elegido", bt.brush_style == "object", bt.brush_style)
	var box := root.find_child("ObjectBrush", true, false) as Control
	check("opciones del pincel de objeto visibles", box != null and box.is_visible_in_tree())
	var fs := root.find_child("ObjFromSelection", true, false) as Button
	await click(fs)
	await frames(4)
	# 2 figuras juntas = 1 estampa; cada figura aporta relleno y borde
	check("la selección pasa a ser el pincel (2 figuras juntas, con relleno y borde)", bt.object_source.size() == 1 and (bt.object_source[0] as Array).size() == 4, "%d estampas, %d piezas" % [bt.object_source.size(), (bt.object_source[0] as Array).size() if bt.object_source.size() > 0 else 0])
	bt.brush_width = 26.0
	var o := vs * Vector2(0.2, 0.45)
	var wv: Array = wave(o, 600.0, 50.0)
	var l1 := await draw(wv[0], wv[1])
	check("trazo de objeto creado", l1 != null and l1.has_meta("brush_obj"))
	root.get_node("SelectionManager").clear()
	await frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(OUT.path_join("seleccion_juntas.png"))
	var area := Rect2(o - Vector2(30, 90), Vector2(660, 180))
	var nr := count_color(img, area, RED)
	var nb := count_color(img, area, BLUE)
	check("salen las dos figuras estampadas (rojo %d, azul %d)" % [nr, nb], nr > 40 and nb > 20)
	var r = l1.get_node_or_null(load("res://script_gdscript/shapes/brush_stroke_render.gd").NODE_NAME)
	var stamps: int = int(r._geom["m"]["stamps"]) if r else 0
	check("varias estampas a lo largo del trazo (%d)" % stamps, stamps >= 8)
	# Guardar y recuperar: misma geometría
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var tmp := Node2D.new()
	holder.add_child(tmp)
	var dup := Line2D.new()
	dup.points = l1.points
	dup.width = l1.width
	dup.width_curve = l1.width_curve
	dup.default_color = l1.default_color
	for k in l1.get_meta_list():
		dup.set_meta(k, l1.get_meta(k))
	tmp.add_child(dup)
	var data: Array = Ser.serialize_elements(tmp)
	var back_parent := Node2D.new()
	holder.add_child(back_parent)
	Ser.instantiate_elements(back_parent, JSON.parse_string(JSON.stringify(data)))
	var back: Line2D = null
	for c in back_parent.get_children():
		if c is Line2D:
			back = c
	check("el trazo se recupera con su pincel de objeto", back != null and back.has_meta("brush_obj") and String(back.get_meta("brush_style", "")) == "object")
	if back:
		var R2 = load("res://script_gdscript/shapes/brush_stroke_render.gd")
		var rb = R2.attach(back)
		rb._draw()
		check("al recuperarlo, mismas estampas (%d)" % int(rb._geom["m"]["stamps"]), int(rb._geom["m"]["stamps"]) == stamps)
	holder.queue_free()
	# Una a una: cada figura por separado, alternándose
	api.select([r1, e1])
	await frames(4)
	var each := root.find_child("ObjEach", true, false) as CheckBox
	each.button_pressed = true
	await click(fs)
	await frames(4)
	check("«Una a una»: dos estampas distintas", bt.object_source.size() == 2, str(bt.object_source.size()))
	var o2 := o + Vector2(0, 170)
	var wv2: Array = wave(o2, 600.0, 30.0)
	var l2 := await draw(wv2[0], wv2[1])
	root.get_node("SelectionManager").clear()
	await frames(8)
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	img2.save_png(OUT.path_join("una_a_una.png"))
	var a2 := Rect2(o2 - Vector2(30, 70), Vector2(660, 140))
	check("alternadas: salen rojas y azules", count_color(img2, a2, RED) > 20 and count_color(img2, a2, BLUE) > 20)
	# Figura de serie: estrella
	var star := root.find_child("ObjStar", true, false) as Button
	await click(star)
	await frames(4)
	var o3 := o + Vector2(0, 300)
	var wv3: Array = wave(o3, 600.0, 30.0)
	var l3 := await draw(wv3[0], wv3[1])
	root.get_node("SelectionManager").clear()
	await frames(8)
	await RenderingServer.frame_post_draw
	var img3 := root.get_texture().get_image()
	img3.save_png(OUT.path_join("estrellas.png"))
	check("figura de serie (estrella) estampada", count_color(img3, Rect2(o3 - Vector2(30, 70), Vector2(660, 140)), Color(0.95, 0.7, 0.15)) > 40)
	# Patrón: la selección (juntas) DOBLADA a lo largo de la curva
	api.select([r1, e1])
	await frames(4)
	each.button_pressed = false
	await click(fs)
	var pat := root.find_child("ObjPattern", true, false) as CheckBox
	await click(pat)
	await frames(4)
	check("modo patrón activado desde el panel", String(bt.object_params.get("mode", "")) == "pattern")
	var o4 := o + Vector2(0, -170)
	var wv4: Array = wave(o4, 600.0, 60.0)
	var l4 := await draw(wv4[0], wv4[1])
	root.get_node("SelectionManager").clear()
	await frames(8)
	await RenderingServer.frame_post_draw
	var img4 := root.get_texture().get_image()
	img4.save_png(OUT.path_join("patron.png"))
	var r4 = l4.get_node_or_null(load("res://script_gdscript/shapes/brush_stroke_render.gd").NODE_NAME) if l4 else null
	var inside := true
	if r4:
		var ax4: Array = r4._geom["ax"]
		var axis: PackedVector2Array = ax4[0]
		var hmax := 0.0
		for hh in ax4[1]:
			hmax = maxf(hmax, hh)
		for q in r4._geom["m"]["points"]:
			var best := INF
			for k in range(0, axis.size() - 1):
				best = minf(best, Geometry2D.get_closest_point_to_segment(q, axis[k], axis[k + 1]).distance_to(q))
			if best > hmax * 1.05 + 0.5:
				inside = false
				break
	check("patrón doblado: toda la figura dentro del grosor del trazo", r4 != null and inside)
	check("patrón: salen las dos figuras", count_color(img4, Rect2(o4 - Vector2(30, 100), Vector2(660, 200)), RED) > 40 and count_color(img4, Rect2(o4 - Vector2(30, 100), Vector2(660, 200)), BLUE) > 20)
	# Convertir el trazo de patrón en figuras sueltas (Ctrl+Mayús+O)
	var stamps4: int = int(r4._geom["m"]["stamps"]) if r4 else 0
	var g = api.stroke_to_outline(l4)
	await frames(6)
	var nfig: int = g.get_child_count() if g else 0
	var per_tile: int = (bt.object_source[0] as Array).size()
	check("patrón → grupo de figuras (%d figuras de %d teselas × %d piezas)" % [nfig, stamps4, per_tile], g != null and nfig == stamps4 * per_tile and l4.get_parent() == null)
	await RenderingServer.frame_post_draw
	var img5 := root.get_texture().get_image()
	img5.save_png(OUT.path_join("patron_figuras.png"))
	check("las figuras se ven igual (rojas y azules)", count_color(img5, Rect2(o4 - Vector2(30, 100), Vector2(660, 200)), RED) > 40 and count_color(img5, Rect2(o4 - Vector2(30, 100), Vector2(660, 200)), BLUE) > 20)
	root.get_node("HistoryManager").undo()
	await frames(4)
	check("deshacer devuelve el trazo", l4.get_parent() != null and (g == null or g.get_parent() == null))
	await click(pat)   # volver a copias rígidas
	# El grosor no cambió al elegir Objeto
	check("el grosor se conserva (26)", is_equal_approx(bt.brush_width, 26.0), str(bt.brush_width))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
