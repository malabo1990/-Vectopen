# =============================================================================
# ARRASTRAR PARA MOVER con el ratón (herramienta Mover), en todos los casos:
# objeto sin seleccionar (se coge por su forma) y ya seleccionado (desde
# dentro de su recuadro), trazo de pincel, curva, imagen, figura sin relleno,
# texto en trazado, grupo y un trazo diminuto con zoom 7400 %.
#   test/run_e2e.sh drag_move_e2e
# =============================================================================
extends SceneTree

const OUT := "user://drag_move"
var fails := 0
var canvas
var sm
var ab: Node2D

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

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

## Arrastre real con el ratón (pantalla) de `a_g` a `b_g` (lienzo).
func drag(a_g: Vector2, b_g: Vector2) -> void:
	var a := scr(a_g)
	var b := scr(b_g)
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	_send(mm)
	await frames(2)
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await frames(2)
	for i in range(1, 11):
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, i / 10.0)
		m2.global_position = m2.position
		m2.relative = (b - a) / 10.0
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m2)
		await process_frame
		if OS.has_environment("DRAG_TRACE") and _trace_node:
			var mt = canvas.get_current_tool()
			print("TRACE paso ", i, " centro=", center_of(_trace_node), " dragging=", mt.is_dragging_shape, " sel=", mt.selected_shapes.size(), " hover_ui=", root.get_node("GlobalUI").is_mouse_over_ui, " gui=", root.gui_get_hovered_control())
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_send(up)
	await frames(4)

var _trace_node: Node2D = null

func center_of(n: Node2D) -> Vector2:
	return canvas.get_current_tool()._global_rect(n).get_center()

## Arrastra y comprueba que el objeto se movió `delta` (± 1,5 px de pantalla).
func expect_move(name: String, n: Node2D, grab_g: Vector2, delta: Vector2) -> void:
	var c0 := center_of(n)
	_trace_node = n
	print("TRACE ---- ", name)
	await drag(grab_g, grab_g + delta)
	var moved := center_of(n) - c0
	var tol: float = 1.5 / canvas.get_viewport().get_canvas_transform().get_scale().x
	check(name, moved.distance_to(delta) <= tol, "movido %s · esperado %s" % [moved, delta])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name.left(30).replace(" ", "_").replace("/", "_") + ".png"))

func stroke(name: String, pts: PackedVector2Array, w: float) -> Line2D:
	var l := Line2D.new()
	l.name = name
	l.points = pts
	l.width = w
	l.default_color = Color(0.1, 0.1, 0.1)
	l.set_meta("brush_style", "pen")
	ab.add_child(l)
	load("res://script_gdscript/shapes/brush_stroke_render.gd").attach(l)
	return l

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
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	sm = root.get_node("SelectionManager")
	var cam: Camera2D = canvas.camera
	ab = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	var cur = canvas.get_current_tool()
	if cur == null or not cur.has_method("get_class_name") or cur.get_class_name() != "MoveTool":
		canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/MoveTool.gd")))
	await frames(4)
	cam.zoom = Vector2.ONE
	cam.position = ab.to_global(ac)
	await frames(4)
	var D := Vector2(60, 40)
	# Imán apagado para medir el movimiento exacto (con imán se ajusta a otros
	# objetos; se prueba aparte al final).
	var snap = root.get_node_or_null("SnapManager")
	var snap_prev := [snap.snap_to_objects, snap.snap_to_center, snap.snap_to_guides] if snap else []
	if snap:
		snap.snap_to_objects = false
		snap.snap_to_center = false
		snap.snap_to_guides = false

	# 1. Figura con relleno, sin seleccionar
	var rect = api.add_rect(ac + Vector2(-300, -200), Vector2(80, 60), 0.0, "Relleno")
	sm.clear()
	await frames(4)
	await expect_move("figura con relleno (sin seleccionar)", rect, ab.to_global(ac + Vector2(-300, -200)), D)

	# 2. Trazo de pincel, sin seleccionar: se coge por el trazo
	var l := stroke("Trazo", PackedVector2Array([ac + Vector2(-100, -250), ac + Vector2(0, -150)]), 6.0)
	sm.clear()
	await frames(6)
	await expect_move("trazo de pincel (sin seleccionar)", l, ab.to_global(ac + Vector2(-50, -200)), D)

	# 3. Ya seleccionado: arrastrar desde dentro del recuadro, fuera del trazo
	sm.select(l)
	await frames(6)
	var lr: Rect2 = canvas.get_current_tool()._global_rect(l)
	var off_stroke: Vector2 = lr.position + Vector2(lr.size.x * 0.85, lr.size.y * 0.15)
	await expect_move("trazo seleccionado, arrastrando desde su recuadro", l, off_stroke, D)
	sm.clear()

	# 4. Curva abierta, sin seleccionar: se coge por su línea
	var c := Curve2D.new()
	c.add_point(ac + Vector2(100, -250), Vector2.ZERO, Vector2(80, -60))
	c.add_point(ac + Vector2(260, -150), Vector2(-60, -80), Vector2.ZERO)
	var path = api.add_curve(c, false, "Curva")
	path.stroke_width = 3.0
	sm.clear()
	await frames(6)
	await expect_move("curva (sin seleccionar)", path, ab.to_global(c.sample(0, 0.5)), D)

	# 5. Imagen, por su parte opaca
	var img := Image.create(100, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.3, 1))
	var sp = api.add_image(img, ac + Vector2(-300, 50), "Foto")
	sm.clear()
	await frames(6)
	await expect_move("imagen (sin seleccionar)", sp, ab.to_global(ac + Vector2(-300, 50)), D)

	# 6. Figura sin relleno, por su borde
	var hollow = api.add_rect(ac + Vector2(-80, 50), Vector2(100, 70), 0.0, "Hueca")
	hollow.fill_color = Color(1, 1, 1, 0)
	hollow.stroke_width = 2.0
	sm.clear()
	await frames(6)
	await expect_move("figura sin relleno (por su borde)", hollow, ab.to_global(ac + Vector2(-130, 50)), D)
	# …y ya seleccionada, desde su interior
	sm.select(hollow)
	await frames(6)
	await expect_move("figura sin relleno seleccionada (desde dentro)", hollow, center_of(hollow), D)
	sm.clear()

	# 7. Grupo de dos figuras
	var g1 = api.add_rect(ac + Vector2(150, 50), Vector2(40, 40), 0.0, "G1")
	var g2 = api.add_rect(ac + Vector2(220, 80), Vector2(40, 40), 0.0, "G2")
	await frames(4)
	var grp: Node2D = null
	if api.has_method("group"):
		grp = api.group([g1, g2])
	await frames(6)
	if grp:
		sm.clear()
		await frames(4)
		await expect_move("grupo (sin seleccionar)", grp, ab.to_global(ac + Vector2(150, 50)), D)

	# 8. Texto en trazado
	var txt = api.add_text(ac + Vector2(-300, 200), "Hola trazo", 32, Color(0.1, 0.1, 0.1))
	var c2 := Curve2D.new()
	c2.add_point(ac + Vector2(-300, 300), Vector2.ZERO, Vector2(100, -80))
	c2.add_point(ac + Vector2(-50, 300), Vector2(-100, -80), Vector2.ZERO)
	var arc = api.add_curve(c2, false, "Arco")
	await frames(6)
	var tl: Line2D = api.text_on_path(txt, arc)
	await frames(8)
	sm.clear()
	await frames(4)
	if tl:
		sm.select(tl)
		await frames(6)
		var t0 := center_of(tl)
		var a0: Vector2 = arc.global_position
		await drag(t0, t0 + D)
		await frames(6)
		check("texto en trazado: se mueve lo arrastrado", center_of(tl).distance_to(t0 + D) < 2.0, "%s → %s" % [t0, center_of(tl)])
		check("…y su trazado se mueve con él", arc.global_position.distance_to(a0 + D) < 1.0, "%s → %s" % [a0, arc.global_position])
		root.get_node("HistoryManager").undo()
		await frames(6)
		check("deshacer devuelve texto y trazado", center_of(tl).distance_to(t0) < 2.0 and arc.global_position.distance_to(a0) < 1.0, "%s · %s" % [center_of(tl), arc.global_position])
		sm.clear()

	# 9. Trazo diminuto con zoom 7400 %
	var tiny := stroke("Diminuto", PackedVector2Array([ac + Vector2(300, 300), ac + Vector2(300.8, 300.6)]), 0.3)
	cam.zoom = Vector2(74, 74)
	cam.position = ab.to_global(ac + Vector2(300.4, 300.3))
	await frames(8)
	sm.clear()
	await frames(4)
	await expect_move("trazo diminuto con 7400 % (sin seleccionar)", tiny, ab.to_global(ac + Vector2(300.4, 300.3)), Vector2(0.8, 0.5))
	sm.select(tiny)
	await frames(6)
	await expect_move("trazo diminuto con 7400 % (seleccionado)", tiny, center_of(tiny), Vector2(0.8, 0.5))
	# 10. Con imán: se mueve (puede ajustarse unos píxeles a otros objetos)
	if snap:
		snap.snap_to_objects = true
		snap.snap_to_center = true
		snap.snap_to_guides = true
		cam.zoom = Vector2.ONE
		cam.position = ab.to_global(ac)
		await frames(6)
		sm.clear()
		var c0 := center_of(rect)
		await drag(center_of(rect), center_of(rect) + D)
		var mv := center_of(rect) - c0
		check("con imán también se arrastra (≥ 80 % del gesto)", mv.length() >= D.length() * 0.8, str(mv))
		snap.snap_to_objects = snap_prev[0]
		snap.snap_to_center = snap_prev[1]
		snap.snap_to_guides = snap_prev[2]
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
