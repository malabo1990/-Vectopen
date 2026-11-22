## E2E Fusión (Blend, informe §3): clic derecho ▸ «Crear fusión» con un
## cuadrado rojo y un círculo azul (Modern); intermedios en pantalla;
## pasos y modo desde el inspector; editar A rehace la fusión; deshacer;
## guía curva; expandir; guardar / abrir.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(280.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func steps(g: Node) -> Array:
	return g.get_children().filter(func(c) -> bool: return c.has_meta("_blend_step"))

## Fusión de TRES objetos (A → B → C) desde el menú, con y sin guía.
func chain_test() -> void:
	var ab3: Node2D = await K.artboard(Vector2(1200, 500), "Cadena", Color.WHITE)
	await K.look_at(ab3)
	var A = api.add_rect(Vector2(100, 250), Vector2(100, 100), 0.0, "A")
	api.set_props(A, {"fill_color": Color(0.9, 0.1, 0.1), "stroke_width": 0.0})
	var B = api.add_ellipse(Vector2(600, 250), Vector2(100, 100), "B")
	api.set_props(B, {"fill_color": Color(0.1, 0.8, 0.1), "stroke_width": 0.0})
	var C = api.add_rect(Vector2(1100, 250), Vector2(60, 160), 0.0, "C")
	api.set_props(C, {"fill_color": Color(0.1, 0.2, 0.9), "stroke_width": 0.0})
	api.select([A, B, C])
	await K.frames(4)
	var menu: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("modern_context_menu.gd"):
			menu = n
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	K.check("cadena: con TRES figuras se ofrece «Crear fusión»", not CMA.blend_parts(menu if menu else root).is_empty())
	CMA.execute("make_blend", menu if menu else root)
	await K.frames(4)
	var g: Node2D = A.get_parent()
	var BL = load("res://script_gdscript/shapes/blend.gd")
	K.check("cadena: un grupo de fusión con las tres claves en orden", BL.is_blend(g) and BL.keys(g) == [A, B, C], str(BL.keys(g)))
	var st := steps(g)
	K.check("cadena: 5 pasos entre A-B y 5 entre B-C", st.size() == 10, str(st.size()))
	if st.size() == 10:
		var ab_mid: Node = st.filter(func(x) -> bool: return int(x.get_meta("_blend_step")) == 2)[0]
		var bc_mid: Node = st.filter(func(x) -> bool: return int(x.get_meta("_blend_step")) == 1002)[0]
		var c1: Color = ab_mid.fill_color
		var c2: Color = bc_mid.fill_color
		K.check("cadena: entre A y B mezcla rojo→verde (sin azul)", c1.r > 0.3 and c1.g > 0.3 and c1.b < 0.2, str(c1))
		K.check("cadena: entre B y C mezcla verde→azul (sin rojo)", c2.g > 0.3 and c2.b > 0.3 and c2.r < 0.2, str(c2))
		var x1: float = (ab_mid as Node2D).position.x + BL._centroid(BL.outline(ab_mid)).x
		var x2: float = (bc_mid as Node2D).position.x + BL._centroid(BL.outline(bc_mid)).x
		K.check("cadena: cada tramo está entre sus dos claves", x1 > 150 and x1 < 550 and x2 > 650 and x2 < 1050, "%.0f %.0f" % [x1, x2])
		# orden de apilado: pasos A-B debajo de B, pasos B-C debajo de C
		K.check("cadena: apilado A < pasos < B < pasos < C", A.get_index() < ab_mid.get_index() and ab_mid.get_index() < B.get_index() and B.get_index() < bc_mid.get_index() and bc_mid.get_index() < C.get_index())
	await K.shot("cadena")
	# cambiar la clave del medio rehace los dos tramos
	api.set_props(B, {"fill_color": Color(1, 1, 0)})
	await K.frames(4)
	var mid2: Node = steps(g).filter(func(x) -> bool: return int(x.get_meta("_blend_step")) == 1002)[0]
	K.check("cadena: cambiar B rehace también el tramo B-C", (mid2.fill_color as Color).r > 0.3, str(mid2.fill_color))
	api.undo()   # color de B
	await K.frames(3)
	api.undo()   # crear fusión
	await K.frames(4)
	K.check("cadena: deshacer → tres figuras sueltas, sin pasos", A.get_parent() == ab3 or A.get_parent().get_parent() == ab3 and not BL.is_blend(A.get_parent()), str(A.get_parent()))
	K.check("cadena: deshacer quita las marcas de clave", not A.has_meta("_blend_end") and not C.has_meta("_blend_end"))
	api.redo()
	await K.frames(4)
	g = A.get_parent()
	K.check("cadena: rehacer → fusión otra vez", BL.is_blend(g) and steps(g).size() == 10)
	# guardar / abrir conserva la cadena
	var abs: Array = await K.save_reload("cadena")
	var g2: Node2D = null
	for x in abs:
		for c in x.find_children("*", "Node2D", true, false):
			if BL.is_blend(c) and BL.keys(c).size() == 3:
				g2 = c
	K.check("cadena: reabrir conserva las tres claves y los 10 pasos", g2 != null and steps(g2).size() == 10)
	# con guía: tres claves + un trazado abierto
	var ab4: Node2D = await K.artboard(Vector2(1000, 600), "Cadena guía", Color.WHITE)
	await K.look_at(ab4)
	var p1 = api.add_ellipse(Vector2(100, 500), Vector2(60, 60), "G1")
	var p2 = api.add_ellipse(Vector2(500, 100), Vector2(60, 60), "G2")
	var p3 = api.add_ellipse(Vector2(900, 500), Vector2(60, 60), "G3")
	var guide = api.add_path(PackedVector2Array([Vector2(100, 500), Vector2(500, 100), Vector2(900, 500)]), false, "Guía")
	api.select([p1, p2, p3, guide])
	await K.frames(4)
	CMA.execute("make_blend", menu if menu else root)
	await K.frames(4)
	var gg: Node2D = p1.get_parent()
	K.check("cadena con guía: 3 claves + guía", BL.is_blend(gg) and BL.keys(gg).size() == 3 and BL.spine_of(gg) == guide)
	var on_path := true
	for s in steps(gg):
		var c: Vector2 = (s as Node2D).position + BL._centroid(BL.outline(s))
		var d := Geometry2D.get_closest_point_to_segment(c, Vector2(100, 500), Vector2(500, 100)).distance_to(c)
		d = minf(d, Geometry2D.get_closest_point_to_segment(c, Vector2(500, 100), Vector2(900, 500)).distance_to(c))
		if d > 6.0:
			on_path = false
	K.check("cadena con guía: todos los pasos van sobre la guía", on_path and steps(gg).size() == 10)
	await K.shot("cadena_guia")

## Degradados: A con degradado rojo→amarillo, B azul liso → los pasos llevan
## un degradado mezclado (y se ve en pantalla).
func gradient_test() -> void:
	var ab5: Node2D = await K.artboard(Vector2(1000, 400), "Fusión degradado", Color.WHITE)
	await K.look_at(ab5)
	var A = api.add_rect(Vector2(120, 200), Vector2(160, 160), 0.0, "GA")
	api.set_props(A, {"stroke_width": 0.0})
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 0, 0))
	gr.set_color(1, Color(1, 1, 0))
	A.fill_gradient = gr
	A.fill_gradient_angle = 0.0
	var B = api.add_rect(Vector2(880, 200), Vector2(160, 160), 0.0, "GB")
	api.set_props(B, {"fill_color": Color(0, 0, 1), "stroke_width": 0.0})
	var BL = load("res://script_gdscript/shapes/blend.gd")
	var g: Node2D = api.make_blend(A, B, {"steps": 3})
	await K.frames(4)
	var st := steps(g)
	K.check("degradado: 3 pasos", st.size() == 3, str(st.size()))
	if st.size() != 3:
		return
	var mid: Node = st[1]
	K.check("degradado: el paso del medio tiene degradado", "fill_gradient" in mid and mid.fill_gradient is Gradient)
	if "fill_gradient" in mid and mid.fill_gradient is Gradient:
		var c0: Color = (mid.fill_gradient as Gradient).sample(0.0)
		var c1: Color = (mid.fill_gradient as Gradient).sample(1.0)
		K.check("degradado: colores mezclados (rojo→azul y amarillo→azul a la mitad)", absf(c0.r - 0.5) < 0.05 and absf(c0.b - 0.5) < 0.05 and absf(c1.g - 0.5) < 0.05, "%s %s" % [c0, c1])
		await K.frames(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var tf: Transform2D = K.canvas.get_viewport().get_canvas_transform()
		var ctr: Vector2 = (mid as Node2D).global_transform * BL._centroid((mid as Node2D).get_effect_points())
		var pl := img.get_pixelv(Vector2i(tf * (ctr + Vector2(-60, 0))))
		var pr := img.get_pixelv(Vector2i(tf * (ctr + Vector2(60, 0))))
		K.check("degradado: se VE el degradado en el paso (izquierda ≠ derecha)", absf(pl.g - pr.g) > 0.15, "%s %s" % [pl, pr])
	await K.shot("degradado")
	# cambiar el degradado de A rehace los pasos
	var gr2 := Gradient.new()
	gr2.set_color(0, Color(0, 1, 0))
	gr2.set_color(1, Color(0, 1, 0))
	A.fill_gradient = gr2
	BL.rebuild(g)
	await K.frames(3)
	var mid2: Node = steps(g)[1]
	K.check("degradado: cambiar el de A rehace los pasos", (mid2.fill_gradient as Gradient).sample(0.0).g > 0.4, str((mid2.fill_gradient as Gradient).sample(0.0)))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://blend")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(1000, 600), "Fusión", Color.WHITE)
	var a = api.add_rect(Vector2(150, 300), Vector2(120, 120), 0.0, "Cuadrado")
	api.set_props(a, {"fill_color": Color(0.9, 0.1, 0.1), "stroke_width": 0.0})
	var b = api.add_ellipse(Vector2(850, 300), Vector2(120, 120), "Círculo")
	api.set_props(b, {"fill_color": Color(0.1, 0.2, 0.9), "stroke_width": 0.0})
	await K.look_at(ab)
	api.select([a, b])
	await K.frames(4)
	# Menú de Modern: la opción aparece con dos figuras
	var menu: Node = null
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("modern_context_menu.gd"):
			menu = n
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	K.check("con dos figuras se ofrece «Crear fusión»", not CMA.blend_parts(menu if menu else root).is_empty())
	CMA.execute("make_blend", menu if menu else root)
	await K.frames(6)
	var sel: Array = api.selection()
	var g: Node2D = sel[0] if sel.size() == 1 else null
	K.check("se crea el grupo «Fusión» y queda seleccionado", g != null and g.has_meta("blend"))
	if g == null:
		print("RESULT: %d FAIL" % (K.fails + 1))
		quit(1)
		return
	K.check("5 pasos intermedios", steps(g).size() == 5, str(steps(g).size()))
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var mid_p: Vector2 = K.canvas.get_viewport().get_canvas_transform() * (ab.global_position + Vector2(500, 300))
	var c: Color = img.get_pixelv(Vector2i(mid_p))
	K.check("en el centro, un color intermedio (morado)", c.r > 0.3 and c.b > 0.3 and c.g < 0.3, str(c))
	await K.shot("fusion")
	var ic = root.get_node("InspectorCore")
	K.check("el inspector ofrece los ajustes de la fusión", ic.current_props().has("blend_steps"))
	ic.apply("blend_steps", 12)
	await K.frames(3)
	K.check("Pasos = 12 desde el inspector", steps(g).size() == 12)
	api.undo()
	await K.frames(3)
	K.check("deshacer vuelve a 5 pasos", steps(g).size() == 5, str(steps(g).size()))
	ic.apply("blend_mode", "distance")
	ic.apply("blend_spacing", 100.0)
	await K.frames(3)
	K.check("por distancia (700 px / 100 → 6 pasos)", steps(g).size() == 6, str(steps(g).size()))
	# Editar un extremo rehace la fusión
	api.set_props(a, {"fill_color": Color(0.1, 0.8, 0.1)})
	await K.frames(4)
	var first: Node = steps(g)[0]
	K.check("cambiar el color de A rehace los pasos", (first.fill_color as Color).g > 0.5, str(first.fill_color))
	# Guardar / abrir
	var abs: Array = await K.save_reload("fusion")
	var g2: Node = null
	for x in abs:
		g2 = x.find_child("Fusión", true, false)
		if g2:
			break
	K.check("reabrir: sigue siendo una fusión con sus pasos", g2 != null and g2.has_meta("blend") and steps(g2).size() == 6)
	if g2:
		api.expand_blend(g2)
		await K.frames(3)
		K.check("expandir: figuras independientes", not g2.has_meta("blend") and steps(g2).is_empty() and g2.get_child_count() >= 8)
	await chain_test()
	await gradient_test()
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
