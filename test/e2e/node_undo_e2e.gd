# =============================================================================
# EDICIÓN DE NODOS — historial: mover un nodo / tirador con el ratón, borrar
# nodos, cambiar el tipo de nodo… se deshace (Ctrl+Z) y se rehace.
#   test/run_e2e.sh node_undo_e2e
# =============================================================================
extends SceneTree

const OUT := "user://node_undo"
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
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

func move(at: Vector2, held: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
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

func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.ctrl_pressed = ctrl
		k.shift_pressed = shift
		k.pressed = down
		_send(k)
		await process_frame

func scr(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

func drag(a_g: Vector2, b_g: Vector2) -> void:
	var a := scr(a_g)
	var b := scr(b_g)
	await move(a, false)
	await btn(a, true)
	for i in range(1, 9):
		await move(a.lerp(b, i / 8.0), true)
	await btn(b, false)
	await frames(3)

## Puntos densos de la línea tal como se dibuja (incluye el tramo de cierre).
func _shape(p) -> PackedVector2Array:
	var cv: Curve2D = p.curve
	var out := PackedVector2Array()
	var closed: bool = bool(p.get("closed")) if "closed" in p else false
	var n := cv.point_count if closed else cv.point_count - 1
	for i in n:
		var j := (i + 1) % cv.point_count
		var c0 := cv.get_point_position(i)
		var c3 := cv.get_point_position(j)
		var c1 := c0 + cv.get_point_out(i)
		var c2 := c3 + cv.get_point_in(j)
		for k in 41:
			var t := k / 40.0
			var u := 1.0 - t
			out.append(c0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + c3 * t * t * t)
	return out

## Desviación máxima entre la forma guardada y la actual (en ambos sentidos).
func _shape_dev(a: PackedVector2Array, p) -> float:
	var b := _shape(p)
	var worst := 0.0
	for pair in [[a, b], [b, a]]:
		var from: PackedVector2Array = pair[0]
		var to: PackedVector2Array = pair[1]
		for q in from:
			var best := INF
			for k in to.size() - 1:
				best = minf(best, Geometry2D.get_closest_point_to_segment(q, to[k], to[k + 1]).distance_to(q))
			worst = maxf(worst, best)
	return worst

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
	var sm = root.get_node("SelectionManager")
	var hm = root.get_node("HistoryManager")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	var c := Curve2D.new()
	c.add_point(ac + Vector2(-200, 50), Vector2.ZERO, Vector2(60, -120))
	c.add_point(ac + Vector2(0, 0), Vector2(-80, 0), Vector2(80, 0))
	c.add_point(ac + Vector2(200, 60), Vector2(-60, -100), Vector2.ZERO)
	var path = api.add_curve(c, false, "Curva")
	path.stroke_width = 2.0
	await frames(4)
	cam.zoom = Vector2.ONE
	cam.position = path.to_global(ac)
	await frames(4)
	sm.select(path)
	await frames(4)
	canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/NodeSelectionTool.gd")))
	await frames(6)
	var tool = canvas.get_current_tool()
	tool.edit_path = path
	var curve: Curve2D = path.curve
	# 1. Arrastrar el nodo central con el ratón
	var p0 := curve.get_point_position(1)
	await drag(path.to_global(p0), path.to_global(p0 + Vector2(40, 70)))
	var p1 := curve.get_point_position(1)
	check("el arrastre mueve el nodo", p1.distance_to(p0) > 30.0, str(p1 - p0))
	await key(KEY_Z, true)
	await frames(3)
	check("Ctrl+Z devuelve el nodo a su sitio", curve.get_point_position(1).distance_to(p0) < 0.5, str(curve.get_point_position(1) - p0))
	hm.redo()
	await frames(3)
	check("rehacer lo vuelve a mover", curve.get_point_position(1).distance_to(p1) < 0.5)
	hm.undo()
	await frames(3)
	# 2. Arrastrar un tirador
	var h0 := curve.get_point_out(1)
	var hg: Vector2 = path.to_global(curve.get_point_position(1) + h0)
	await drag(hg, hg + Vector2(0, -60))
	check("el arrastre mueve el tirador", curve.get_point_out(1).distance_to(h0) > 20.0, str(curve.get_point_out(1)))
	await key(KEY_Z, true)
	await frames(3)
	check("Ctrl+Z devuelve el tirador", curve.get_point_out(1).distance_to(h0) < 0.5)
	# 3. Borrar un nodo
	tool.selected_nodes.clear()
	tool.selected_nodes.append(1)
	tool.delete_selected_nodes()
	await frames(3)
	check("borrar deja 2 nodos", curve.point_count == 2)
	hm.undo()
	await frames(3)
	check("deshacer devuelve el nodo borrado", curve.point_count == 3 and curve.get_point_position(1).distance_to(p0) < 0.5)
	# 4. Tipo de nodo (esquina)
	tool.selected_nodes.clear()
	tool.selected_nodes.append(1)
	tool.set_selected_nodes_mode("retract")
	await frames(3)
	check("«esquina» quita los tiradores", curve.get_point_out(1) == Vector2.ZERO)
	hm.undo()
	await frames(3)
	check("deshacer devuelve los tiradores", curve.get_point_out(1).distance_to(h0) < 0.5)
	# 5. Doble clic añade un nodo (sin deformar la línea)
	var shape0 := _shape(path)
	var mid := c.sample(0, 0.37)
	await move(scr(path.to_global(mid)), false)
	var dc := InputEventMouseButton.new()
	dc.position = scr(path.to_global(mid))
	dc.global_position = dc.position
	dc.button_index = MOUSE_BUTTON_LEFT
	dc.pressed = true
	dc.double_click = true
	_send(dc)
	await frames(2)
	await btn(scr(path.to_global(mid)), false)
	await frames(3)
	check("doble clic añade un nodo", curve.point_count == 4, str(curve.point_count))
	check("añadir un nodo NO deforma la línea (≤ 0,5 px)", _shape_dev(shape0, path) <= 0.5, "%.3f px" % _shape_dev(shape0, path))
	hm.undo()
	await frames(3)
	check("deshacer quita el nodo añadido", curve.point_count == 3, str(curve.point_count))
	# 6. Clic simple en el tramo (sin arrastrar) también inserta sin deformar
	var q := c.sample(1, 0.62)
	await move(scr(path.to_global(q)), false)
	await btn(scr(path.to_global(q)), true)
	await btn(scr(path.to_global(q)), false)
	await frames(3)
	check("clic en el tramo añade un nodo", curve.point_count == 4, str(curve.point_count))
	check("…sin deformar la línea (≤ 0,5 px)", _shape_dev(shape0, path) <= 0.5, "%.3f px" % _shape_dev(shape0, path))
	hm.undo()
	await frames(3)
	# 7. Trazado CERRADO: insertar en el tramo de cierre (último → primero)
	var cc := Curve2D.new()
	cc.add_point(ac + Vector2(-150, 200), Vector2(0, 60), Vector2(0, -60))
	cc.add_point(ac + Vector2(0, 120), Vector2(-70, 0), Vector2(70, 0))
	cc.add_point(ac + Vector2(150, 200), Vector2(0, -60), Vector2(0, 60))
	var closed_p = api.add_curve(cc, true, "Cerrada")
	if "fill_color" in closed_p:
		closed_p.fill_color = Color(0.2, 0.6, 0.9)
	cam.position = closed_p.to_global(ac + Vector2(0, 170))
	cam.zoom = Vector2(2, 2)
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("relleno_antes.png"))
	sm.select(closed_p)
	tool.edit_path = closed_p
	var shape_c := _shape(closed_p)
	var n0: int = closed_p.curve.point_count
	var ccv: Curve2D = closed_p.curve
	var ins: int = tool._insert_node_at(ccv, n0 - 1, 0.4)
	await frames(3)
	check("cerrado: nodo añadido en el tramo de cierre", ccv.point_count == n0 + 1 and ins == n0)
	check("cerrado: la forma no cambia (≤ 0,5 px)", _shape_dev(shape_c, closed_p) <= 0.5, "%.3f px" % _shape_dev(shape_c, closed_p))
	closed_p.queue_redraw()
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("relleno_despues.png"))
	# arrastrar el nodo nuevo con el ratón y mirar el relleno
	tool.selected_nodes.clear()
	var ng: Vector2 = closed_p.to_global(ccv.get_point_position(ins))
	await drag(ng, ng + Vector2(0, 50))
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("relleno_movido.png"))
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
