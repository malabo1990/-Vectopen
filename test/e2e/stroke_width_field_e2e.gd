## E2E USR-39: grosor de trazo tipo Affinity en Modern y Pro. Arrastrar el
## número con el ratón cambia el grosor EN VIVO y deja UN paso de deshacer;
## grosores predefinidos; unidad pt/mm; escribir «3pt».
##   test/run_e2e.sh stroke_width_field_e2e
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

func field() -> Control:
	for n in root.find_children("StrokeWidthField", "", true, false):
		if n is Control and (n as Control).is_visible_in_tree():
			return n
	return null

func scrub(f: Control, dx: float) -> float:
	var num: Control = f.num
	var a: Vector2 = num.get_global_rect().get_center()
	var m0 := InputEventMouseMotion.new()
	m0.position = a
	m0.global_position = a
	_send(m0)
	await K.frames(2)
	var d := InputEventMouseButton.new()
	d.position = a
	d.global_position = a
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(d)
	await K.frames(2)
	var mid := -1.0
	for i in range(1, 11):
		var m := InputEventMouseMotion.new()
		m.position = a + Vector2(dx * i / 10.0, 0)
		m.global_position = m.position
		m.relative = Vector2(dx / 10.0, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m)
		await process_frame
		if i == 5:
			mid = float(api.get_prop(_shape, "stroke_width"))
	var u := InputEventMouseButton.new()
	u.position = a + Vector2(dx, 0)
	u.global_position = u.position
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	_send(u)
	await K.frames(4)
	return mid

var _shape

func run_mode(mode: String) -> void:
	if not await K.boot(mode):
		K.check("%s arranca" % mode, false)
		return
	api = K.api
	var ab: Node2D = await K.artboard(Vector2(600, 400), "Grosor " + mode, Color.WHITE)
	_shape = api.add_rect(Vector2(300, 200), Vector2(200, 120), 0.0, "R")
	api.set_props(_shape, {"stroke_width": 2.0, "stroke_color": Color.BLACK})
	await K.look_at(ab)
	api.select([_shape])
	await K.frames(6)
	var f := field()
	if f == null and mode == "professional":
		# Pro: el grosor está en la pestaña Trazo del estudio
		for b in root.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and String((b as Button).text).to_lower() in ["trazo", "stroke"]:
				(b as Button).pressed.emit()
				await K.frames(4)
				break
		f = field()
	if f == null and mode == "smart":
		# Smart: el panel Trazos se abre desde su botón; aquí se muestra a mano
		for n in root.find_children("StrokeWidthField", "", true, false):
			var p: Node = n
			while p != null and p != root:
				if p is CanvasItem:
					(p as CanvasItem).visible = true
				p = p.get_parent()
			break
		await K.frames(4)
		f = field()
	K.check("%s: hay campo de grosor común" % mode, f != null)
	if f == null:
		return
	var SW = load("res://script_gdscript/ui/components/stroke_width_field.gd")
	SW.set_unit("px")
	f.set_value_no_signal(2.0)
	await K.frames(2)
	var mid: float = await scrub(f, 120.0)
	var w1 := float(api.get_prop(_shape, "stroke_width"))
	K.check("%s: arrastrar el número sube el grosor" % mode, w1 > 2.5, str(w1))
	K.check("%s: vista previa en vivo (cambia a mitad del arrastre)" % mode, mid > 2.05 and mid < w1, "%.2f / %.2f" % [mid, w1])
	api.undo()
	await K.frames(3)
	K.check("%s: UN Ctrl+Z vuelve al grosor de antes" % mode, is_equal_approx(float(api.get_prop(_shape, "stroke_width")), 2.0), str(api.get_prop(_shape, "stroke_width")))
	api.redo()
	await K.frames(3)
	K.check("%s: rehacer vuelve al arrastrado" % mode, absf(float(api.get_prop(_shape, "stroke_width")) - w1) < 0.01)
	# Preajuste (índice 7 = 4)
	f.pick_preset(7)
	await K.frames(2)
	K.check("%s: preajuste 4 px" % mode, is_equal_approx(float(api.get_prop(_shape, "stroke_width")), 4.0), str(api.get_prop(_shape, "stroke_width")))
	# Unidad pt: el preajuste «4 pt» son 5,333 px; el campo muestra pt
	SW.set_unit("pt")
	await K.frames(2)
	K.check("%s: en pt, 4 px se muestran como 3 pt" % mode, absf(float(f.num.value) - 3.0) < 0.01, str(f.num.value))
	f.pick_preset(7)
	await K.frames(2)
	K.check("%s: preajuste 4 pt = 5,33 px" % mode, absf(float(api.get_prop(_shape, "stroke_width")) - 4.0 / 0.75) < 0.01, str(api.get_prop(_shape, "stroke_width")))
	# Escribir con unidad
	var le: LineEdit = f.num.line_edit()
	f.num.begin_edit()
	le.text = "1,5mm"
	f.num._commit_text()
	await K.frames(2)
	K.check("%s: escribir «1,5mm» = 5,67 px" % mode, absf(float(api.get_prop(_shape, "stroke_width")) - 1.5 * 96.0 / 25.4) < 0.02, str(api.get_prop(_shape, "stroke_width")))
	SW.set_unit("px")
	await K.shot("grosor_" + mode)

func _run() -> void:
	K = load("res://test/e2e/lib/campaign_kit.gd").new(self, "user://stroke_width")
	await run_mode("smart")
	await run_mode("modern")
	await run_mode("professional")
	print("RESULT: %s" % ("OK" if K.fails == 0 else "%d FAIL" % K.fails))
	quit(1 if K.fails else 0)
