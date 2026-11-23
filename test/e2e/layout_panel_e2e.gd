## E2E panel «Contenedor» (Auto Layout; Modern y Smart): se abre al
## seleccionar un contenedor y se cierra al deseleccionarlo; tipo fila /
## columna / rejilla / salto recoloca los elementos; arrastrar «Separación»
## con el ratón en vivo y UN paso de deshacer; alineación; columnas solo en
## rejilla; quitar el contenedor (y deshacer).
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
	for c in root.find_children("layout", "PanelContainer", true, false):
		if (c as Control).is_visible_in_tree() and c.get_script() and String(c.get_script().resource_path).ends_with("panel_layout.gd"):
			return c
	return null

func press(p: Control, name: String) -> void:
	var b: Button = p.find_child(name, true, false)
	if b:
		b.pressed.emit()
	await K.frames(4)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://layout_panel")
	var AL = load("res://script_gdscript/shapes/auto_layout.gd")
	for mode in ["modern", "smart"]:
		if not await K.boot(mode):
			quit(1)
			return
		api = K.api
		var ab: Node2D = await K.artboard(Vector2(900, 500), "Panel contenedor " + mode, Color.WHITE)
		await K.look_at(ab)
		var items: Array = []
		for i in 4:
			var r = api.add_rect(Vector2(100 + i * 120, 150), Vector2(80, 60 + i * 10), 0.0, "E%d" % i)
			items.append(r)
		var AL0 = load("res://script_gdscript/shapes/auto_layout.gd")
		var union := func(list: Array) -> Rect2:
			var u := Rect2()
			for i in list.size():
				var r: Rect2 = AL0.box(list[i])
				var pxf: Transform2D = (list[i].get_parent() as Node2D).global_transform   # box() va en coords del padre
				var gr := Rect2(pxf * r.position, r.size * pxf.get_scale())
				u = gr if i == 0 else u.merge(gr)
			return u
		var u0: Rect2 = union.call(items)
		var g: Node2D = api.make_layout(items, {"mode": "row", "gap": 16.0})
		await K.frames(3)
		var u1: Rect2 = union.call(items)
		K.check("%s: al crear el contenedor NO cambia de sitio (misma esquina del conjunto)" % mode, u1.position.distance_to(u0.position) < 1.0, "%s → %s" % [u0.position, u1.position])
		# objetos creados en orden INVERSO a como se ven: se respeta lo que se ve
		var rev: Array = []
		for i in 3:
			rev.append(api.add_ellipse(Vector2(700 - i * 90, 380), Vector2(60, 60), "R%d" % i))
		var r0: Rect2 = union.call(rev)
		var g2: Node2D = api.make_layout(rev, {"mode": "row", "gap": 10.0})
		await K.frames(3)
		K.check("%s: respeta el orden en que se ven (izquierda → derecha)" % mode, rev[2].global_position.x < rev[1].global_position.x and rev[1].global_position.x < rev[0].global_position.x, "%s" % [rev.map(func(n): return n.global_position.x)])
		K.check("%s: y tampoco salta de sitio" % mode, (union.call(rev) as Rect2).position.distance_to(r0.position) < 1.0, "%s → %s" % [r0.position, (union.call(rev) as Rect2).position])
		api.select([])
		await K.frames(4)
		K.check("%s: sin contenedor seleccionado no hay panel" % mode, panel() == null)
		api.select([g])
		await K.frames(8)
		var p := panel()
		K.check("%s: al seleccionar el contenedor se abre su panel" % mode, p != null)
		if p == null:
			continue
		var info: Label = p.find_child("Info", true, false)
		K.check("%s: resumen «4 elementos · Fila»" % mode, info.text.contains("4 elementos") and info.text.contains("Fila"), info.text)
		K.check("%s: el panel no llega al borde inferior" % mode, p.get_global_rect().end.y <= root.get_visible_rect().size.y - 12.0, str(p.get_global_rect()))
		# Columna: los elementos quedan uno debajo de otro
		await press(p, "mode_column")
		var xs: Array = items.map(func(n) -> float: return snappedf((n as Node2D).global_position.x, 0.5))
		var ys: Array = items.map(func(n) -> float: return (n as Node2D).global_position.y)
		K.check("%s: Columna → elementos uno debajo de otro" % mode, String(AL.read_prop(g, "layout_mode")) == "column" and ys[1] > ys[0] and ys[2] > ys[1], "%s %s" % [xs, ys])
		# Rejilla: aparece Columnas y reparte en 2 columnas
		await press(p, "mode_grid")
		var cols: Control = p.find_child("Layout_columns", true, false)
		K.check("%s: Rejilla muestra «Columnas»" % mode, cols != null and cols.is_visible_in_tree())
		AL.write_prop(g, "layout_columns", 2.0)
		await K.frames(3)
		K.check("%s: rejilla de 2 columnas (E2 debajo de E0)" % mode, absf(items[2].global_position.x - items[0].global_position.x) < 1.0 and items[2].global_position.y > items[0].global_position.y)
		await press(p, "mode_row")
		K.check("%s: en Fila «Columnas» se oculta" % mode, not cols.is_visible_in_tree())
		# arrastrar Separación con el ratón: en vivo y un deshacer
		var gap_f: Control = p.find_child("Layout_gap", true, false)
		var x1_before: float = items[1].global_position.x
		var p0: Vector2 = gap_f.get_global_rect().get_center()
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
			m2.position = p0 + Vector2(i * 6, 0)
			m2.global_position = m2.position
			m2.button_mask = MOUSE_BUTTON_MASK_LEFT
			_send(m2)
			await K.frames(1)
		K.check("%s: arrastrar Separación separa los elementos EN VIVO" % mode, items[1].global_position.x > x1_before + 5.0, "%.1f → %.1f" % [x1_before, items[1].global_position.x])
		var up := InputEventMouseButton.new()
		up.position = p0 + Vector2(48, 0)
		up.global_position = up.position
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		_send(up)
		await K.frames(4)
		api.undo()
		await K.frames(4)
		K.check("%s: un Ctrl+Z deshace el arrastre entero" % mode, absf(items[1].global_position.x - x1_before) < 1.0, "%.1f vs %.1f" % [items[1].global_position.x, x1_before])
		# alineación cruzada: centro
		await press(p, "cross_center")
		K.check("%s: alineación cruzada «centro»" % mode, String(AL.read_prop(g, "layout_cross")) == "center")
		# quitar contenedor
		await press(p, "Release")
		await K.frames(4)
		K.check("%s: Quitar contenedor → elementos sueltos" % mode, not AL.is_layout(g) or items[0].get_parent() != g, str(items[0].get_parent()))
		K.check("%s: al quitarlo, el panel se cierra" % mode, panel() == null)
		api.undo()
		await K.frames(6)
		K.check("%s: deshacer → vuelve el contenedor" % mode, AL.is_layout(items[0].get_parent()))
		api.select([items[0].get_parent()])
		await K.frames(6)
		await K.shot("panel_contenedor_" + mode)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
