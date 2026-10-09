## E2E del panel de la herramienta Texto/Párrafo (popup "text" de la barra):
## diseño (capturas claro/oscuro) + que cada control haga lo que dice.
##   godot --path . -s res://test/e2e/text_panel_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var fails: Array[String] = []
var out := "user://text_panel_e2e"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _shot(popup: Control, tag: String) -> void:
	await _frames(8)
	var r := Rect2i(popup.get_global_rect().grow(8))
	var img := root.get_texture().get_image()
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img = img.get_region(r)
	img.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/%s.png" % [out, tag])

func _mouse(btn: bool, x: float) -> InputEvent:
	if btn:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.global_position = Vector2(x, 0)
		return e
	var m := InputEventMouseMotion.new()
	m.global_position = Vector2(x, 0)
	return m

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(30)
	var pp = root.find_child("ParagraphConfig", true, false)
	_check(pp != null, "el panel ParagraphConfig está montado")
	if pp == null:
		quit(1); return
	var popup: Control = pp._popup
	var tm = root.get_node("ThemeManager")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var sm = root.get_node("SelectionManager")
	var canvas = get_first_node_in_group("_vectopen_canvas")

	# 1) Sin selección: capturas de diseño + campos en "—"
	for mode in ["dark", "light"]:
		tm.set_mode(mode)
		popup.visible = true
		await _shot(popup, "panel_vacio_" + mode)
	_check(pp._fields["font_size"].is_mixed(), "sin selección el tamaño muestra '—'")

	# 2) Párrafo seleccionado → valores reales
	canvas.switch_tool("paragraph")
	await _frames()
	var para: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(para)
	ic._sync_selection()
	pp._sync({})
	await _frames()
	_check(not pp._fields["font_size"].is_mixed() and is_equal_approx(pp._fields["font_size"].value, 24.0), "con selección el tamaño muestra 24")
	_check(pp._align_btns[0].button_pressed, "alineación izquierda marcada")
	_check(pp._btn_family.text == "Inter", "familia = Inter (%s)" % pp._btn_family.text)
	_check(pp._opt_style.get_item_text(pp._opt_style.selected) == "Regular", "estilo = Regular")
	tm.set_mode("dark")
	await _shot(popup, "panel_seleccion_dark")

	# 3) Escribir un valor en el campo de tamaño (Intro) + deshacer
	hm.clear()
	var le: LineEdit = pp._fields["font_size"].line_edit()
	le.text = "36"
	le.text_submitted.emit("36")
	await _frames()
	_check(int(para.get_meta("font_size")) == 36, "tamaño escrito 36 → meta %s" % para.get_meta("font_size"))
	hm.undo(); await _frames()
	_check(int(para.get_meta("font_size")) == 24, "deshacer tamaño → 24 (%s)" % para.get_meta("font_size"))

	# 4) Expresión
	le.text = "12*3"
	le.text_submitted.emit("12*3")
	await _frames()
	_check(int(para.get_meta("font_size")) == 36, "expresión 12*3 → 36 (%s)" % para.get_meta("font_size"))

	# 5) Arrastre (scrub) del icono de interletra: en vivo + UNA acción de undo
	hm.clear()
	var tr_f = pp._fields["letter_spacing"]
	var lead: Control = tr_f._lead
	lead.gui_input.emit(_mouse(true, 100)); 
	var down := _mouse(true, 100); down.pressed = true
	lead.gui_input.emit(down)
	lead.gui_input.emit(_mouse(false, 110))
	await _frames(1)
	var live := float(para.get_meta("letter_spacing", 0.0))
	_check(live > 0.0, "arrastre: interletra cambia EN VIVO (%s)" % live)
	_check(not hm.can_undo(), "arrastre: aún sin acción de undo mientras arrastra")
	lead.gui_input.emit(_mouse(false, 120))
	var up := _mouse(true, 120); up.pressed = false
	lead.gui_input.emit(up)
	await _frames()
	var fin := float(para.get_meta("letter_spacing", 0.0))
	_check(fin > live, "arrastre: valor final mayor (%s > %s)" % [fin, live])
	_check(hm.can_undo(), "arrastre: una acción de undo al soltar")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("letter_spacing", 0.0)), 0.0), "deshacer arrastre → 0 de una vez (%s)" % para.get_meta("letter_spacing", 0.0))

	# 6) Teclas arriba/abajo en el campo
	var lf = pp._fields["line_spacing"]
	var lle: LineEdit = lf.line_edit()
	var k := InputEventKey.new(); k.keycode = KEY_UP; k.pressed = true; k.shift_pressed = true
	lle.gui_input.emit(k)
	await _frames()
	_check(is_equal_approx(float(para.get_meta("line_spacing", 0.0)), 10.0), "Shift+↑ en interlineado → 10 (%s)" % para.get_meta("line_spacing", 0.0))

	# 7) Alineación
	pp._align_btns[1].pressed.emit()
	await _frames()
	_check(String(para.get_meta("text_align", "")) == "center", "botón centrar → text_align=center")
	pp._sync({})
	_check(pp._align_btns[1].button_pressed and not pp._align_btns[0].button_pressed, "solo 'centrar' queda marcado")
	pp._valign_btns[2].pressed.emit()
	await _frames()
	_check(String(para.get_meta("text_valign", "")) == "bottom", "botón abajo → text_valign=bottom")

	# 8) Estilo (desplegable) y negrita
	pp._opt_style.select(4)
	pp._opt_style.item_selected.emit(4)
	await _frames()
	_check(int(para.get_meta("font_weight", 400)) == 700, "estilo Bold → peso 700 (%s)" % para.get_meta("font_weight", 400))
	pp._sync({})
	_check(pp._btn_bold.button_pressed, "botón B marcado con peso 700")
	pp._btn_bold.button_pressed = false
	pp._btn_bold.pressed.emit()
	await _frames()
	_check(int(para.get_meta("font_weight", 400)) == 400, "B de nuevo → peso 400 (%s)" % para.get_meta("font_weight", 400))

	# 9) Sangrías y columnas
	var ind: LineEdit = pp._fields["indent_left"].line_edit()
	ind.text = "15"; ind.text_submitted.emit("15")
	await _frames()
	_check(is_equal_approx(float(para.get_meta("indent_left", 0.0)), 15.0), "sangría izquierda 15")
	var cols: LineEdit = pp._fields["columns"].line_edit()
	cols.text = "2"; cols.text_submitted.emit("2")
	await _frames()
	_check(int(para.get_meta("columns", 1)) == 2, "columnas 2")

	# 10) Mixto: dos párrafos con tamaños distintos
	canvas.switch_tool("paragraph")
	await _frames()
	var p2: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(p2)
	ic._sync_selection()
	ic.apply("font_size", 50)
	if sm.has_method("set_selection"):
		sm.set_selection([para, p2])
	ic._sync_selection()
	pp._sync({})
	await _frames()
	_check(pp._fields["font_size"].is_mixed(), "dos tamaños distintos → 'Mixto'")
	tm.set_mode("light")
	await _shot(popup, "panel_mixto_light")

	# 11) Panel de texto del menú contextual (clic derecho) dentro de la app
	popup.visible = false
	var ctx: Control = root.find_child("Panel_tooltext", true, false)
	_check(ctx != null, "panel de texto del menú contextual presente")
	if ctx:
		var top: Control = ctx
		var n: Node = ctx
		while n and n != root:
			if n is CanvasItem:
				(n as CanvasItem).visible = true
			if n is Control:
				top = n
			n = n.get_parent()
		top.position = Vector2(60, 60)
		tm.set_mode("dark")
		await _frames(6)
		var box: Control = ctx.get_node("BoxContainer")
		var font_row: Control = box.get_node("Panel/BoxContainer")
		_check(font_row.get_combined_minimum_size().x <= box.get_node("Panel").size.x + 0.5, "fila familia/estilo/color cabe en el panel (%s ≤ %s)" % [font_row.get_combined_minimum_size().x, box.get_node("Panel").size.x])
		_check(box._indent_spins.size() == 3 and box._indent_spins["indent_left"].has_method("set_mixed"), "sangrías con campos de icono")
		var vb: Control = box.get_node("Panel/VBoxContainer")
		for c in vb.get_children():
			print("  fila ", c.name, " min=", (c as Control).get_combined_minimum_size().x)
		_check(vb.get_combined_minimum_size().x <= 192.5, "filas del panel contextual caben en 192 px (%s)" % vb.get_combined_minimum_size().x)
		await _shot(ctx, "panel_contextual_dark")

	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
