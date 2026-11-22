## E2E Auto Layout (informe §4): clic derecho ▸ «Convertir en contenedor» con
## tres figuras; quedan en fila; inspector: columna, separación; un rectángulo
## solo se convierte en contenedor con fondo a la medida; añadir un hijo lo
## recoloca; deshacer; guardar / abrir.
extends SceneTree

var K
var api
const AL = preload("res://script_gdscript/shapes/auto_layout.gd")

func _init() -> void:
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://auto_layout")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(900, 600), "Contenedores", Color.WHITE)
	var a = api.add_rect(Vector2(150, 120), Vector2(80, 60), 0.0, "A")
	var b = api.add_ellipse(Vector2(400, 400), Vector2(60, 60), "B")
	var c = api.add_rect(Vector2(700, 200), Vector2(100, 40), 0.0, "C")
	await K.look_at(ab)
	api.select([a, b, c])
	await K.frames(3)
	var CMA = load("res://script_gdscript/ui/context_menu_actions.gd")
	K.check("con tres figuras se ofrece «Convertir en contenedor»", CMA.can_make_layout(root))
	CMA.execute("make_layout", root)
	await K.frames(4)
	var g: Node2D = api.selection()[0] if api.selection().size() == 1 else null
	K.check("se crea el contenedor y queda seleccionado", g != null and AL.is_layout(g))
	if g == null:
		quit(1)
		return
	var ba: Rect2 = AL.box(a)
	var bb: Rect2 = AL.box(b)
	var bc: Rect2 = AL.box(c)
	K.check("en fila con separación 16", absf(bb.position.x - ba.end.x - 16.0) < 0.5 and absf(bc.position.x - bb.end.x - 16.0) < 0.5, "%s %s %s" % [ba, bb, bc])
	var ic = root.get_node("InspectorCore")
	K.check("el inspector ofrece los ajustes del contenedor", ic.current_props().has("layout_mode") and ic.current_props().has("layout_gap"))
	ic.apply("layout_mode", "column")
	ic.apply("layout_gap", 30.0)
	await K.frames(3)
	K.check("columna con separación 30", absf(AL.box(b).position.y - AL.box(a).end.y - 30.0) < 0.5, "%s %s" % [AL.box(a), AL.box(b)])
	api.undo()
	await K.frames(3)
	K.check("deshacer la separación", absf(AL.box(b).position.y - AL.box(a).end.y - 16.0) < 0.5)
	# Mover un hijo a mano: el contenedor lo devuelve a su sitio
	var b0: Rect2 = AL.box(b)
	api.move(b, Vector2(200, 0))
	await K.frames(4)
	K.check("un hijo movido vuelve a su sitio", AL.box(b).position.distance_to(b0.position) < 0.5, "%s → %s" % [b0, AL.box(b)])
	# Un rectángulo solo → contenedor con fondo; añadir hijos lo agranda
	var card = api.add_rect(Vector2(600, 450), Vector2(50, 50), 0.0, "Tarjeta")
	api.set_props(card, {"fill_color": Color(0.92, 0.94, 1.0)})
	var g2: Node2D = api.make_layout([card], {"mode": "row", "padding": 12.0, "gap": 8.0})
	K.check("un rectángulo se convierte en contenedor con fondo", g2 != null and card.has_meta(AL.BG_META))
	var t1 = api.add_rect(Vector2(0, 0), Vector2(40, 40), 0.0, "Icono")
	var t2 = api.add_rect(Vector2(0, 0), Vector2(120, 40), 0.0, "Etiqueta")
	for t in [t1, t2]:
		t.get_parent().remove_child(t)
		g2.add_child(t)
	AL.sync_now(self)
	await K.frames(3)
	K.check("el fondo se ajusta al contenido (12 + 40 + 8 + 120 + 12 = 192)", absf(AL.box(card).size.x - 192.0) < 0.5 and absf(AL.box(card).size.y - 64.0) < 0.5, str(AL.box(card).size))
	await K.shot("contenedores")
	# Guardar / abrir
	var abs: Array = await K.save_reload("contenedores")
	var g3: Node = null
	for x in abs:
		for n in x.find_children("*", "Node2D", true, false):
			if AL.is_layout(n) and String(AL.params(n)["mode"]) == "column":
				g3 = n
	K.check("reabrir: el contenedor y su modo", g3 != null)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
