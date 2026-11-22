## E2E panel «Fusión» (Modern y Smart): se abre al seleccionar una fusión y
## se cierra al deseleccionarla; arrastrar «Pasos» con el ratón cambia los
## pasos en vivo y deja UN paso de deshacer; modo por distancia; invertir
## orden; soltar (y deshacer); no llega al borde inferior.
extends SceneTree

var K
var api

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func panel() -> Control:
	for c in root.find_children("blend", "PanelContainer", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null

func steps(g: Node) -> int:
	return g.get_children().filter(func(c) -> bool: return c.has_meta("_blend_step")).size()

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://blend_panel")
	var BL = load("res://script_gdscript/shapes/blend.gd")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(900, 400), "Panel fusión " + mode, Color.WHITE)
		await K.look_at(ab)
		var a = api.add_rect(Vector2(100, 200), Vector2(80, 80), 0.0, "A")
		api.set_props(a, {"fill_color": Color(0.9, 0.1, 0.1), "stroke_width": 0.0})
		var b = api.add_ellipse(Vector2(450, 200), Vector2(80, 80), "B")
		api.set_props(b, {"fill_color": Color(0.1, 0.8, 0.1), "stroke_width": 0.0})
		var c = api.add_rect(Vector2(800, 200), Vector2(40, 120), 0.0, "C")
		api.set_props(c, {"fill_color": Color(0.1, 0.2, 0.9), "stroke_width": 0.0})
		var g: Node2D = api.make_blend_chain([a, b, c], {"steps": 3})
		api.select([])
		await K.frames(4)
		K.check("%s: sin fusión seleccionada no hay panel" % mode, panel() == null)
		api.select([g])
		await K.frames(8)
		var p := panel()
		K.check("%s: al seleccionar la fusión se abre su panel" % mode, p != null)
		if p == null:
			continue
		var info: Label = p.find_child("Info", true, false)
		K.check("%s: resumen «3 objetos · 6 pasos»" % mode, info != null and info.text.contains("3 objetos") and info.text.contains("6 pasos"), info.text if info else "")
		var pr: Rect2 = p.get_global_rect()
		K.check("%s: el panel no llega al borde inferior" % mode, pr.end.y <= root.get_visible_rect().size.y - 12.0, str(pr))
		# arrastrar «Pasos» con el ratón
		var nf: Control = p.find_child("Blend_steps", true, false)
		K.check("%s: campo Pasos visible" % mode, nf != null and nf.is_visible_in_tree())
		if nf:
			var p0: Vector2 = nf.get_global_rect().get_center()
			var mm := InputEventMouseMotion.new()
			mm.position = p0
			mm.global_position = p0
			_send(mm)
			await K.frames(2)
			var dn := InputEventMouseButton.new()
			dn.position = p0
			dn.global_position = p0
			dn.button_index = MOUSE_BUTTON_LEFT
			dn.pressed = true
			dn.button_mask = MOUSE_BUTTON_MASK_LEFT
			_send(dn)
			await K.frames(2)
			for i in range(1, 9):
				var m2 := InputEventMouseMotion.new()
				m2.position = p0 + Vector2(i * 2.5, 0)
				m2.global_position = m2.position
				m2.button_mask = MOUSE_BUTTON_MASK_LEFT
				_send(m2)
				await K.frames(1)
			var mid := steps(g)
			K.check("%s: arrastrar Pasos cambia los pasos EN VIVO" % mode, mid > 6, "pasos %d" % mid)
			var up := InputEventMouseButton.new()
			up.position = p0 + Vector2(20, 0)
			up.global_position = up.position
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			_send(up)
			await K.frames(4)
			api.undo()
			await K.frames(4)
			K.check("%s: un Ctrl+Z deshace el arrastre entero (vuelven 6 pasos)" % mode, steps(g) == 6, "pasos %d" % steps(g))
		# modo por distancia
		var md: Button = p.find_child("Mode_distance", true, false)
		md.pressed.emit()
		await K.frames(4)
		var sp: Control = p.find_child("Blend_spacing", true, false)
		K.check("%s: «Por distancia» muestra Distancia y oculta Pasos" % mode, String(BL.read_prop(g, "blend_mode")) == "distance" and sp.is_visible_in_tree() and not nf.is_visible_in_tree())
		(p.find_child("Mode_steps", true, false) as Button).pressed.emit()
		await K.frames(4)
		# invertir orden
		(p.find_child("Reverse", true, false) as Button).pressed.emit()
		await K.frames(4)
		K.check("%s: Invertir → la cadena va C → B → A" % mode, BL.keys(g) == [c, b, a], str(BL.keys(g)))
		api.undo()
		await K.frames(3)
		K.check("%s: deshacer Invertir" % mode, BL.keys(g) == [a, b, c])
		# soltar
		(p.find_child("Release", true, false) as Button).pressed.emit()
		await K.frames(6)
		K.check("%s: Soltar → objetos sueltos, sin fusión" % mode, a.get_parent() == ab and c.get_parent() == ab and not a.has_meta("_blend_end"), str(a.get_parent()))
		K.check("%s: al soltar, el panel se cierra" % mode, panel() == null)
		api.undo()
		await K.frames(6)
		K.check("%s: deshacer Soltar → vuelve la fusión con sus 6 pasos" % mode, BL.is_blend(a.get_parent()) and steps(a.get_parent()) == 6)
		api.select([a.get_parent()])
		await K.frames(6)
		await K.shot("panel_fusion_" + mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
