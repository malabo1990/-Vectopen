## EFECTOS EN TRAZOS DE PINCEL (Line2D): sombra, contorno y superposición de
## color se DIBUJAN (antes solo se guardaban en el meta) y sobreviven a
## guardar → cargar.
##   godot --path . -s res://test/e2e/brush_fx_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)
	else:
		print("ok   ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _count(img: Image, pred: Callable) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if pred.call(img.get_pixel(x, y)):
				n += 1
	return n

func _run() -> void:
	var out := OS.get_environment("E2E_OUT")
	if out == "": out = "user://brush_fx"
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(30)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var sm = root.get_node("SelectionManager")
	for cl in root.find_children("*", "CanvasLayer", true, false):
		if not (cl as Node).is_ancestor_of(canvas):
			(cl as CanvasLayer).visible = false
	var cam = canvas.get_node("Camera2D")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var layer: Node = ab.get_node_or_null("VectorDrawingLayer")
	if layer == null: layer = ab

	# Trazo en "U" (curvas + extremos redondos), como lo deja el pincel.
	var l := Line2D.new()
	l.name = "Dibujo"
	var pts := PackedVector2Array()
	for i in 41:
		var a := PI * float(i) / 40.0
		pts.append(Vector2(300 + cos(a) * 120.0, 300 + sin(a) * 120.0))
	l.points = pts
	l.width = 30.0
	l.default_color = Color(0, 0, 0)
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	layer.add_child(l)
	cam.zoom = Vector2.ONE
	cam.global_position = l.global_position + Vector2(300, 330)
	await _frames(10)
	var img0 := root.get_texture().get_image()
	var red := func(c: Color) -> bool: return c.r > 0.6 and c.g < 0.35 and c.b < 0.35
	var blue := func(c: Color) -> bool: return c.b > 0.6 and c.r < 0.35 and c.g < 0.35
	var black := func(c: Color) -> bool: return c.r < 0.25 and c.g < 0.25 and c.b < 0.25
	var ink0: int = _count(img0, black)
	_check(ink0 > 200, "el trazo se ve (%d px)" % ink0)

	sm.select(l); ic._sync_selection()
	ic.apply("effects", [
		{"type": "Drop Shadow", "enabled": true, "offset_x": 40.0, "offset_y": 40.0, "blur": 0.0, "spread": 0.0, "color": Color(0, 0, 1, 1)},
		{"type": "Outline", "enabled": true, "width": 8.0, "color": Color(1, 0, 0, 1)},
	])
	sm.set_selection([]); ic._sync_selection()
	await _frames(20)
	var img1 := root.get_texture().get_image()
	img1.save_png("%s/brush_fx.png" % out)
	var n_blue: int = _count(img1, blue)
	var n_red: int = _count(img1, red)
	var n_black: int = _count(img1, black)
	print("BRUSH sombra=%d contorno=%d trazo=%d (antes %d)" % [n_blue, n_red, n_black, ink0])
	_check(n_blue > ink0 / 4, "la sombra del trazo se dibuja (%d px)" % n_blue)
	_check(n_red > 50, "el contorno del trazo se dibuja (%d px)" % n_red)
	_check(n_black > ink0 * 0.8, "el trazo sigue encima de su sombra (%d px)" % n_black)

	# Guardar → cargar: los efectos vuelven y se dibujan.
	var Ser = load("res://scripts/canvas/canvas_serializer.gd")
	var data: Array = Ser.serialize_elements(layer)
	l.queue_free()
	await _frames(3)
	Ser.instantiate_elements(layer, data)
	await _frames(20)
	var img2 := root.get_texture().get_image()
	img2.save_png("%s/brush_fx_reload.png" % out)
	var b2: int = _count(img2, blue)
	print("BRUSH recargado sombra=%d" % b2)
	_check(absi(b2 - n_blue) <= n_blue / 10 + 10, "tras guardar y cargar el efecto sigue igual (%d vs %d px)" % [b2, n_blue])
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
