## E2E USR-38: los hijos de un grupo se pueden seleccionar, editar y arrastrar
## (antes «la selección salta al padre»). Ratón real sobre el lienzo.
##   test/run_e2e.sh group_children_e2e
extends SceneTree

var K
var api
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

func _btn(p: Vector2, pressed: bool, dbl := false, ctrl := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = p
	mb.global_position = p
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = dbl
	mb.ctrl_pressed = ctrl
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_send(mb)

func _move(p: Vector2, rel: Vector2, held: bool) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(m)

func click(g: Vector2, dbl := false) -> void:
	var a := scr(g)
	_move(a, Vector2.ZERO, false)
	await K.frames(2)
	_btn(a, true, dbl)
	await K.frames(2)
	_btn(a, false)
	await K.frames(3)

func drag(a_g: Vector2, b_g: Vector2, ctrl := false) -> void:
	var a := scr(a_g)
	var b := scr(b_g)
	_move(a, Vector2.ZERO, false)
	await K.frames(2)
	if ctrl:
		var k := InputEventKey.new()
		k.keycode = KEY_CTRL
		k.pressed = true
		_send(k)
	_btn(a, true, false, ctrl)
	await K.frames(2)
	for i in range(1, 11):
		_move(a.lerp(b, i / 10.0), (b - a) / 10.0, true)
		await process_frame
	_btn(b, false)
	if ctrl:
		var k2 := InputEventKey.new()
		k2.keycode = KEY_CTRL
		k2.pressed = false
		_send(k2)
	await K.frames(4)

func gpos(n: Node2D) -> Vector2:
	return n.global_position

func sel() -> Array:
	return canvas.get_current_tool().selected_shapes.filter(func(s) -> bool: return is_instance_valid(s))

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://group_children")
	if not await K.boot("modern"):
		quit(1)
		return
	api = K.api
	canvas = K.canvas
	var ab: Node2D = await K.artboard(Vector2(800, 600), "Grupos", Color.WHITE)
	var a = api.add_rect(Vector2(200, 200), Vector2(120, 120), 0.0, "A")
	var b = api.add_rect(Vector2(400, 200), Vector2(120, 120), 0.0, "B")
	var c = api.add_ellipse(Vector2(600, 200), Vector2(100, 100), "C")
	var g = api.group([a, b], "Grupo")
	var outer = api.group([g, c], "Exterior")
	await K.look_at(ab)
	if canvas.has_method("change_tool_by_name"):
		canvas.change_tool_by_name("move")
	await K.frames(4)
	var ga: Vector2 = gpos(a)
	var gb: Vector2 = gpos(b)
	var gc: Vector2 = gpos(c)
	var go: Vector2 = gpos(outer)

	# 1) Clic sencillo: el grupo de primer nivel (comportamiento profesional)
	await click(ab.to_global(Vector2(200, 200)))
	K.check("clic sencillo selecciona el grupo exterior", sel() == [outer], str(sel().map(func(s): return s.name)))

	# 2) Hijo elegido en Capas (api.select) → arrastrarlo mueve SOLO el hijo
	api.select([a])
	await K.frames(3)
	await drag(ab.to_global(Vector2(200, 200)), ab.to_global(Vector2(230, 240)))
	K.check("Capas: arrastrar el hijo seleccionado lo mueve", gpos(a).distance_to(ga + Vector2(30, 40)) < 2.0, "%s → %s" % [ga, gpos(a)])
	K.check("Capas: el hermano y el grupo no se mueven", gpos(b).distance_to(gb) < 0.5 and gpos(outer).distance_to(go) < 0.5)
	K.check("Capas: la selección sigue en el hijo", sel() == [a], str(sel().map(func(s): return s.name)))
	api.undo()
	await K.frames(3)
	K.check("Ctrl+Z devuelve el hijo a su sitio", gpos(a).distance_to(ga) < 0.5, str(gpos(a)))

	# 3) Con un hijo seleccionado, clic en su HERMANO → selecciona el hermano
	api.select([a])
	await K.frames(3)
	await click(ab.to_global(Vector2(400, 200)))
	K.check("dentro del grupo, clic en el hermano lo selecciona", sel() == [b], str(sel().map(func(s): return s.name)))
	await drag(ab.to_global(Vector2(400, 200)), ab.to_global(Vector2(400, 260)))
	K.check("y arrastrarlo mueve el hermano (no el hijo anterior)", gpos(b).distance_to(gb + Vector2(0, 60)) < 2.0 and gpos(a).distance_to(ga) < 0.5, "%s / %s" % [gpos(b), gpos(a)])
	api.undo()
	await K.frames(3)

	# 4) Doble clic entra en el grupo nivel a nivel y luego se arrastra
	api.select([])
	await K.frames(2)
	await click(ab.to_global(Vector2(600, 200)))
	await click(ab.to_global(Vector2(600, 200)), true)
	K.check("doble clic en C (hijo directo del exterior) lo selecciona", sel() == [c], str(sel().map(func(s): return s.name)))
	await drag(ab.to_global(Vector2(600, 200)), ab.to_global(Vector2(620, 180)))
	K.check("arrastrar C tras el doble clic lo mueve solo a él", gpos(c).distance_to(gc + Vector2(20, -20)) < 2.0 and gpos(a).distance_to(ga) < 0.5, str(gpos(c)))
	api.undo()
	await K.frames(3)

	# 5) Ctrl + arrastre directo sobre un hijo profundo
	api.select([])
	await K.frames(2)
	await drag(ab.to_global(Vector2(400, 200)), ab.to_global(Vector2(450, 200)), true)
	K.check("Ctrl + arrastre mueve el hijo profundo (B)", gpos(b).distance_to(gb + Vector2(50, 0)) < 2.0 and gpos(a).distance_to(ga) < 0.5, str(gpos(b)))
	K.check("Ctrl + arrastre deja seleccionado B", sel() == [b], str(sel().map(func(s): return s.name)))
	api.undo()
	await K.frames(3)

	# 6) Editar el hijo: el inspector actúa sobre él, no sobre el padre
	api.select([a])
	await K.frames(3)
	var ic = root.get_node("/root/InspectorCore")
	ic.apply("fill_color", Color(0.1, 0.6, 0.3))
	await K.frames(2)
	K.check("editar el relleno cambia el hijo", (a.fill_color as Color).is_equal_approx(Color(0.1, 0.6, 0.3)))
	K.check("y no el hermano", not (b.fill_color as Color).is_equal_approx(Color(0.1, 0.6, 0.3)))
	# 7) Contorno del contenedor: se dibuja sin errores y se captura
	api.select([a])
	await K.frames(4)
	await K.shot("contenedor")
	# 8) «Selección directa (atravesar grupos)»
	var SP = load("res://script_gdscript/tools/move/select_prefs.gd")
	SP.set_deep_select(true)
	api.select([])
	await K.frames(2)
	await click(ab.to_global(Vector2(400, 200)))
	K.check("selección directa: el clic coge B dentro de dos grupos", sel() == [b], str(sel().map(func(s): return s.name)))
	await drag(ab.to_global(Vector2(400, 200)), ab.to_global(Vector2(400, 230)))
	K.check("selección directa: arrastrar mueve solo B", gpos(b).distance_to(gb + Vector2(0, 30)) < 2.0 and gpos(a).distance_to(ga) < 0.5, str(gpos(b)))
	api.undo()
	await K.frames(3)
	api.select([])
	await K.frames(2)
	await drag(ab.to_global(Vector2(400, 200)), ab.to_global(Vector2(400, 200)), true)
	K.check("selección directa: Ctrl + clic coge el grupo exterior", sel() == [outer], str(sel().map(func(s): return s.name)))
	SP.set_deep_select(false)
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
