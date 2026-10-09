## E2E: el panel de la herramienta Texto (ParagraphConfig) y el panel
## Tipografía del menú contextual (Panel_tooltext) se mantienen sincronizados
## EN TIEMPO REAL en ambos sentidos, también durante arrastres y al editar.
##   godot --path . -s res://test/e2e/text_panels_sync_e2e.gd
extends SceneTree

var fails: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await _frames(2)

func _move(at: Vector2, dx: float) -> void:
	for i in int(absf(dx) / 2.0):
		var m := InputEventMouseMotion.new()
		m.position = at
		m.global_position = at
		m.relative = Vector2(signf(dx) * 2.0, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await process_frame
	await _frames(2)

func _show_all(n: Node) -> void:
	while n and n != root:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
		n = n.get_parent()

func _run() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(30)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var sm = root.get_node("SelectionManager")
	var tool_p = root.find_child("ParagraphConfig", true, false)
	var typo_root: Control = root.find_child("Panel_tooltext", true, false)
	var typo = typo_root.get_node("BoxContainer")
	canvas.switch_tool("paragraph")
	await _frames()
	var para: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(para)
	ic._sync_selection()

	# Ambos paneles abiertos a la vez (popup de herramienta + menú contextual)
	tool_p._popup.visible = true
	_show_all(typo_root)
	# Raíz del menú contextual: el PanelContainer exterior de tool_in_mouse
	# (…/PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_tooltext).
	var top: Control = typo_root
	for i in 5:
		top = top.get_parent()
	await _frames(6)
	tool_p._popup.global_position = Vector2(top.get_global_rect().end.x + 40, 120)
	await _frames(3)
	_check(not top.get_global_rect().intersects(tool_p._popup.get_global_rect()), "los dos paneles no se solapan (%s / %s)" % [top.get_global_rect(), tool_p._popup.get_global_rect()])
	var s_size: Slider = typo._sliders["font_size"]
	var s_ls: Slider = typo._sliders["letter_spacing"]
	var s_lead: Slider = typo._sliders["line_spacing"]

	# 1) Texto → Tipografía: escribir tamaño
	var le: LineEdit = tool_p._fields["font_size"].line_edit()
	le.text = "48"; le.text_submitted.emit("48")
	await _frames()
	_check(is_equal_approx(s_size.value, 48.0), "Texto→Tipografía: tamaño 48 (slider %s)" % s_size.value)

	# 2) Texto → Tipografía EN VIVO durante un arrastre de interletra
	var c: Vector2 = tool_p._fields["letter_spacing"].line_edit().get_global_rect().get_center()
	await _press(c, true)
	await _move(c, 12.0)
	var live := float(para.get_meta("letter_spacing", 0.0))
	_check(live > 0.0 and is_equal_approx(s_ls.value, live), "Texto→Tipografía en vivo al arrastrar (meta %s, slider %s)" % [live, s_ls.value])
	await _press(c, false)

	# 3) Tipografía → Texto EN VIVO al arrastrar un slider + un solo undo
	hm.clear()
	var before_lead := float(para.get_meta("line_spacing", 0.0))
	s_lead.drag_started.emit()
	for v in [4.0, 8.0, 12.0]:
		s_lead.value = v
		await _frames(1)
		_check(is_equal_approx(tool_p._fields["line_spacing"].value, v), "Tipografía→Texto en vivo: interlineado %s (campo %s)" % [v, tool_p._fields["line_spacing"].value])
	s_lead.drag_ended.emit(true)
	await _frames()
	_check(is_equal_approx(float(para.get_meta("line_spacing", 0.0)), 12.0), "interlineado final 12")
	_check(hm.can_undo(), "arrastre en Tipografía crea su paso de deshacer")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("line_spacing", 0.0)), before_lead), "deshacer vuelve a %s (%s)" % [before_lead, para.get_meta("line_spacing", 0.0)])
	_check(is_equal_approx(tool_p._fields["line_spacing"].value, before_lead) and is_equal_approx(s_lead.value, before_lead), "tras deshacer AMBOS paneles muestran %s" % before_lead)
	_check(not hm.can_undo(), "fue UN solo paso de deshacer")

	# 4) Alineación en ambos sentidos
	(typo.get_node("Panel/VBoxContainer/BoxContainer2/Button3") as Button).pressed.emit()   # derecha
	await _frames()
	_check(tool_p._align_btns[2].button_pressed and not tool_p._align_btns[0].button_pressed, "Tipografía→Texto: alineación derecha marcada")
	tool_p._align_btns[1].pressed.emit()
	await _frames()
	_check(typo._current_align == "center", "Texto→Tipografía: alineación centro (%s)" % typo._current_align)
	tool_p._valign_btns[2].pressed.emit()
	await _frames()
	_check(typo._current_valign == "bottom", "Texto→Tipografía: vertical abajo (%s)" % typo._current_valign)

	# 5) Estilo / peso
	tool_p._opt_style.select(4); tool_p._opt_style.item_selected.emit(4)
	await _frames()
	var opt: OptionButton = typo.get_node("Panel/BoxContainer/OptionButton")
	_check(opt.get_item_text(opt.selected) == "Bold", "Texto→Tipografía: estilo Bold (%s)" % (opt.get_item_text(opt.selected) if opt.selected >= 0 else "-"))
	var reg := -1
	for i in opt.item_count:
		if opt.get_item_text(i) == "Regular": reg = i
	opt.select(reg); opt.item_selected.emit(reg)
	await _frames()
	_check(tool_p._opt_style.get_item_text(tool_p._opt_style.selected) == "Regular" and not tool_p._btn_bold.button_pressed, "Tipografía→Texto: estilo Regular y B desmarcada")

	# 6) Color
	var cp: ColorPickerButton = typo.get_node("Panel/BoxContainer/FontColorPicker")
	cp.color = Color.RED; cp.color_changed.emit(Color.RED)
	await _frames()
	_check(tool_p._cp_fill.color.is_equal_approx(Color.RED), "Tipografía→Texto: color rojo")
	tool_p._cp_fill.color = Color.BLUE; tool_p._cp_fill.color_changed.emit(Color.BLUE)
	await _frames()
	_check(cp.color.is_equal_approx(Color.BLUE), "Texto→Tipografía: color azul")

	# 7) Sangrías
	var ind: LineEdit = tool_p._fields["indent_left"].line_edit()
	ind.text = "20"; ind.text_submitted.emit("20")
	await _frames()
	_check(is_equal_approx(typo._indent_spins["indent_left"].value, 20.0), "Texto→Tipografía: sangría 20")
	var ind2: LineEdit = typo._indent_spins["indent_right"].line_edit()
	ind2.text = "7"; ind2.text_submitted.emit("7")
	await _frames()
	_check(is_equal_approx(tool_p._fields["indent_right"].value, 7.0), "Tipografía→Texto: sangría derecha 7")

	# 8) Panel oculto: se pone al día al abrirse
	typo_root.visible = false
	await _frames()
	le.text = "30"; le.text_submitted.emit("30")
	await _frames()
	typo_root.visible = true
	await _frames(3)
	_check(is_equal_approx(s_size.value, 30.0), "Tipografía oculta se actualiza al abrirse (slider %s)" % s_size.value)

	# 9) Editando con letras seleccionadas: ambos muestran el tamaño de esas letras
	canvas.switch_tool("paragraph")
	await _frames()
	canvas.current_tool._check_and_trigger_edit_at(para)
	await _frames(3)
	var vrt = para.get_node_or_null("VectorRichText")
	var native: bool = vrt != null and vrt.is_editing()
	ic.apply("text", "Hola mundo")
	await _frames()
	if native:
		vrt.set_selection_range(0, 4)
	else:
		var te := para.get_node_or_null("MultiLineEdit") as TextEdit
		te.select(0, 0, 0, 4)
	await _frames()
	tool_p._popup.visible = true
	_show_all(typo_root)
	await _frames(2)
	tool_p._popup.global_position = Vector2(top.get_global_rect().end.x + 40, 120)
	await _frames(4)
	var cs: Vector2 = tool_p._fields["font_size"].line_edit().get_global_rect().get_center()
	await _press(cs, true)
	await _move(cs, 20.0)
	var sel_sz := float(tool_p._fields["font_size"].value)
	_check(sel_sz > 30.0 and is_equal_approx(s_size.value, sel_sz), "editando: Tipografía sigue en vivo el tamaño de las letras (campo %s, slider %s)" % [sel_sz, s_size.value])
	await _press(cs, false)
	_check(is_equal_approx(float(tool_p._fields["font_size"].value), sel_sz), "al soltar el campo conserva el tamaño de la selección (%s)" % tool_p._fields["font_size"].value)
	# mover la selección a letras sin cambiar → ambos vuelven a 30
	if native:
		vrt.set_selection_range(6, 9)
	else:
		(para.get_node("MultiLineEdit") as TextEdit).select(0, 6, 0, 9)
	await _frames(4)
	_check(is_equal_approx(float(tool_p._fields["font_size"].value), 30.0) and is_equal_approx(s_size.value, 30.0), "otra selección → ambos muestran 30 (campo %s, slider %s)" % [tool_p._fields["font_size"].value, s_size.value])

	# 10) Tipografía → letras seleccionadas (editando) + panel Texto lo sigue
	if native:
		vrt.set_selection_range(0, 4)
	else:
		(para.get_node("MultiLineEdit") as TextEdit).select(0, 0, 0, 4)
	await _frames(3)
	hm.clear()
	var sz_before := float(tool_p._fields["font_size"].value)
	s_size.drag_started.emit()
	for v in [60.0, 70.0]:
		s_size.value = v
		await _frames(2)
		_check(is_equal_approx(float(tool_p._fields["font_size"].value), v), "Tipografía (editando) → Texto en vivo: %s (campo %s)" % [v, tool_p._fields["font_size"].value])
	s_size.drag_ended.emit(true)
	await _frames(2)
	var rr: Array = para.get_meta("runs", [])
	_check(not rr.is_empty() and int(rr[0].get("length", 0)) == 4 and is_equal_approx(float(rr[0].get("size", 0)), 70.0), "solo 'Hola' a 70 (%s)" % [rr.slice(0, 2)])
	_check(hm.can_undo(), "slider de Tipografía editando: undo")
	hm.undo(); await _frames(3)
	_check(is_equal_approx(float(tool_p._fields["font_size"].value), sz_before) and is_equal_approx(s_size.value, sz_before), "deshacer → ambos paneles vuelven a %s (campo %s, slider %s)" % [sz_before, tool_p._fields["font_size"].value, s_size.value])
	_check(not hm.can_undo(), "UN solo paso de deshacer")

	print("E2E modo: ", "nativo" if native else "GDScript")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
