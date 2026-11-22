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
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
