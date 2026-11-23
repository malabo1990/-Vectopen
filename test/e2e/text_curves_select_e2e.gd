## Texto convertido a curvas (Bézier): sale en Capas, un clic lo selecciona
## (el grupo entero, como Inkscape / Affinity / Illustrator) y se arrastra.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func tree_has(txt: String) -> bool:
	for tr_ in root.find_children("*", "Tree", true, false):
		if not (tr_ as Control).is_visible_in_tree():
			continue
		var stack: Array = [(tr_ as Tree).get_root()]
		while not stack.is_empty():
			var it: TreeItem = stack.pop_back()
			if it == null:
				continue
			if it.get_text(0).contains(txt):
				return true
			for ch in it.get_children():
				stack.append(ch)
	return false

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://text_curves_sel")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(1000, 600), "Curvas " + mode, Color.WHITE)
		await K.look_at(ab)
		var t = api.add_text(Vector2(300, 250), "Hola mundo en curva", 48, Color.BLACK)
		var cv := Curve2D.new()
		cv.add_point(Vector2(150, 400), Vector2.ZERO, Vector2(150, -250))
		cv.add_point(Vector2(750, 400), Vector2(-150, -250))
		var path = api.add_curve(cv, false, "Guía")
		await K.frames(4)
		api.select([t, path])
		await K.frames(3)
		var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
		CMA.execute("text_on_path", root)
		await K.frames(8)
		var g: Node2D = null
		for n in ab.get_children():
			if n.has_meta("brush_ref"):
				g = n
		K.check("%s: hay texto en trazado" % mode, g != null)
		if g == null:
			continue
		print("DBG grupo ", g.name, " parent=", g.get_parent().name, " hijos=", g.get_child_count(), " clase=", g.get_class(), " script=", g.get_script())
		await K.frames(10)
		K.check("%s: el texto en trazado sale en Capas" % mode, tree_has(String(g.name)), String(g.name))
		K.canvas.switch_tool("move")
		api.select([])
		await K.frames(4)
		var lp: PackedVector2Array = (g as Line2D).points
		# centro de la PRIMERA letra (malla dibujada), no un píxel del glifo
		var rr = g.get_node_or_null(load("res://script_gdscript/shapes/brush_stroke_render.gd").NODE_NAME)
		var mv: PackedVector2Array = rr.visual_mesh()["points"]
		var lmin := mv[0]
		var lmax := mv[0]
		for q in mv:
			if q.x < mv[0].x + float((g as Line2D).width) * 0.5:
				lmin = Vector2(minf(lmin.x, q.x), minf(lmin.y, q.y))
				lmax = Vector2(maxf(lmax.x, q.x), maxf(lmax.y, q.y))
		var gp: Vector2 = g.to_global((lmin + lmax) * 0.5)
		K.check("%s: el texto en trazado queda ENCIMA de su guía" % mode, g.get_index() > path.get_index(), "%d vs %d" % [g.get_index(), path.get_index()])
		var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * gp
		var mm := InputEventMouseMotion.new()
		mm.position = sp
		mm.global_position = sp
		_send(mm)
		await K.frames(2)
		var b := InputEventMouseButton.new()
		b.position = sp
		b.global_position = sp
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = true
		b.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(b)
		await K.frames(2)
		var sel: Array = root.get_node("InspectorCore").selection()
		K.check("%s: un clic en el texto en trazado lo selecciona" % mode, sel.size() == 1 and sel[0] == g, str(sel))
		var p0 := g.global_position
		for k in range(1, 31):
			var m := InputEventMouseMotion.new()
			m.position = sp + Vector2(k * 3, k)
			m.global_position = m.position
			m.button_mask = MOUSE_BUTTON_MASK_LEFT
			_send(m)
			await process_frame
		var u := InputEventMouseButton.new()
		u.position = sp + Vector2(90, 30)
		u.global_position = u.position
		u.button_index = MOUSE_BUTTON_LEFT
		u.pressed = false
		_send(u)
		await K.frames(3)
		K.check("%s: se arrastra con Mover" % mode, g.global_position.distance_to(p0) > 20.0, str(g.global_position - p0))
		await K.shot("curvas_" + mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
