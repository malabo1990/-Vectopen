## E2E clic derecho ▸ «Convertir en trazado Bézier»: rectángulo, elipse,
## estrella, polígono → trazado Bézier cerrado con la misma forma (caja),
## colores y posición; rectángulo = 4 nodos exactos, elipse = pocos nodos
## con curvas; texto → curvas; un paso de deshacer; la opción sale en los
## menús de Modern, Pro y Smart.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func gbox(n: Node2D) -> Rect2:
	var pts: PackedVector2Array
	if n is VectorPath:
		pts = (n as VectorPath).curve.get_baked_points()
	else:
		pts = n.get_effect_points()
	var r := Rect2(n.global_transform * pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(n.global_transform * q)
	return r

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://to_bezier")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1000, 600), "A Bézier", Color.WHITE)
	await K.look_at(ab)
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	var menu: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("modern_context_menu.gd"):
			menu = n
	var host: Node = menu if menu else root
	var cases := {
		"rectángulo": api.add_rect(Vector2(120, 150), Vector2(140, 90), 0.0, "Rect"),
		"elipse": api.add_ellipse(Vector2(360, 150), Vector2(140, 90), "Elipse"),
		"rect. redondeado": api.add_rect(Vector2(600, 150), Vector2(140, 90), 24.0, "Redondo"),
	}
	if api.has_method("add_star"):
		cases["estrella"] = api.add_star(Vector2(840, 150), 70.0, 5)
	if api.has_method("add_polygon"):
		cases["polígono"] = api.add_polygon(Vector2(120, 400), 70.0, 6)
	for k in cases:
		var s = cases[k]
		if s == null:
			continue
		api.set_props(s, {"fill_color": Color(0.2, 0.5, 0.8), "stroke_color": Color(0.9, 0.2, 0.1), "stroke_width": 4.0})
		s.rotation = 0.3 if k == "rectángulo" else 0.0
		await K.frames(2)
		var b0 := gbox(s)
		api.select([s])
		await K.frames(2)
		K.check("%s: el menú ofrece «Convertir en trazado Bézier»" % k, CMA.can_to_bezier(host))
		CMA.execute("to_bezier", host)
		await K.frames(3)
		var sel: Array = root.get_node("InspectorCore").selection()
		var p = sel[0] if sel.size() == 1 else null
		var nt = K.canvas.current_tool
		K.check("%s: se abre YA el editor de nodos sobre el trazado" % k, nt != null and String(nt.get_script().resource_path).ends_with("NodeSelectionTool.gd") and nt.edit_path == p, str(nt.get_script().resource_path.get_file() if nt else "-"))
		if p == null and nt and "edit_path" in nt:
			p = nt.edit_path
		K.check("%s: queda un trazado Bézier cerrado" % k, p is VectorPath and p.closed and not s.is_inside_tree(), str(p))
		if not (p is VectorPath):
			continue
		var b1 := gbox(p)
		K.check("%s: misma forma y posición (caja)" % k, b1.position.distance_to(b0.position) < 2.5 and (b1.size - b0.size).length() < 3.5, "%s vs %s" % [b0, b1])
		K.check("%s: conserva relleno, borde y grosor" % k, (p.fill_color as Color).is_equal_approx(Color(0.2, 0.5, 0.8)) and (p.stroke_color as Color).is_equal_approx(Color(0.9, 0.2, 0.1)) and is_equal_approx(float(p.stroke_width), 4.0))
		var nodes: int = (p as VectorPath).curve.point_count
		if k == "rectángulo":
			K.check("rectángulo: 4 nodos exactos", nodes == 4, str(nodes))
		if k == "elipse":
			var has_handles := false
			for i in nodes:
				if (p as VectorPath).curve.get_point_out(i).length() > 1.0:
					has_handles = true
			K.check("elipse: pocos nodos con curvas (≤ 12 y con tiradores)", nodes <= 12 and has_handles, str(nodes))
		api.undo()
		await K.frames(3)
		K.check("%s: un Ctrl+Z vuelve a la figura" % k, s.is_inside_tree() and not p.is_inside_tree())
	# texto → curvas
	K.canvas.switch_tool("move")
	await K.frames(3)
	var t = api.add_text(Vector2(400, 380), "Bézier", 48, Color.BLACK)
	api.select([t])
	await K.frames(3)
	K.check("texto: el menú ofrece la conversión", CMA.can_to_bezier(host))
	CMA.execute("to_bezier", host)
	await K.frames(4)
	var sel2: Array = root.get_node("InspectorCore").selection()
	var g = sel2[0] if sel2.size() == 1 else null
	K.check("texto: pasa a curvas (trazados Bézier)", g != null and not t.is_inside_tree() and g.find_children("*", "Path2D", true, false).size() > 0, str(g))
	# doble clic REAL en una letra → nodos de esa letra directamente
	if g:
		K.canvas.switch_tool("move")
		await K.frames(3)
		var letter: Path2D = g.find_children("*", "Path2D", true, false)[0]
		var lc: Vector2 = letter.to_global(letter.curve.get_baked_points()[0])
		var cpts: PackedVector2Array = letter.curve.get_baked_points()
		var acc := Vector2.ZERO
		for q in cpts:
			acc += q
		lc = letter.to_global(acc / cpts.size())
		var sp: Vector2 = K.canvas.get_viewport().get_canvas_transform() * lc
		for i in 2:
			for down in [true, false]:
				var b := InputEventMouseButton.new()
				b.position = sp
				b.global_position = sp
				b.button_index = MOUSE_BUTTON_LEFT
				b.pressed = down
				b.double_click = down and i == 1
				Input.parse_input_event(b)
				Input.flush_buffered_events()
				await K.frames(2)
		await K.frames(4)
		var nt2 = K.canvas.current_tool
		K.check("texto convertido: UN doble clic abre los nodos de la letra", nt2 != null and String(nt2.get_script().resource_path).ends_with("NodeSelectionTool.gd") and nt2.edit_path is Path2D and g.is_ancestor_of(nt2.edit_path), str(nt2.get("edit_path") if nt2 else "-"))
	# los menús de Pro y Smart la tienen
	var pro_src := FileAccess.get_file_as_string("res://script_gdscript/ui/pro/pro_context_menu.gd")
	var smart_src := FileAccess.get_file_as_string("res://script_gdscript/ui/smart_menu_extras.gd")
	K.check("Pro y Smart ofrecen «Convertir en trazado Bézier»", pro_src.contains("\"to_bezier\"") and smart_src.contains("\"to_bezier\""))
	K.check("la acción tiene icono propio", ResourceLoader.exists("res://icon/UI/menu/to_bezier.svg"))
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
