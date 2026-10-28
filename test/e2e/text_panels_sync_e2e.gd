## E2E: panel Texto (párrafo/marco) + panel Tipografía (carácter) abiertos a
## la vez sobre la app real:
##  · no se repite ningún control entre los dos;
##  · Tipografía se actualiza EN TIEMPO REAL (arrastres, deshacer, panel
##    oculto que se abre) y, editando, refleja y cambia SOLO las letras
##    seleccionadas, con UN paso de deshacer;
##  · las muestras de color abren el selector de la app (pickr_color_tool).
##   godot --path . -s res://test/e2e/text_panels_sync_e2e.gd   (E2E_OUT=carpeta)
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

func _click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	await _press(at, true)
	await _press(at, false)

func _show_all(n: Node) -> void:
	while n and n != root:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
		n = n.get_parent()

func _sizes(runs: Array) -> Array:
	return runs.map(func(r): return [int(r.get("length", 0)), float(r.get("size", 0.0))])

func _run() -> void:
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
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

	# Raíz del menú contextual (…/PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/Panel_tooltext)
	var top: Control = typo_root
	for i in 5:
		top = top.get_parent()
	var open_both := func() -> void:
		tool_p._popup.visible = true
		_show_all(typo_root)
		await _frames(3)
		tool_p._popup.global_position = Vector2(top.get_global_rect().end.x + 40, 120)
		await _frames(3)
	await open_both.call()
	_check(not top.get_global_rect().intersects(tool_p._popup.get_global_rect()), "los dos paneles abiertos sin solaparse")
	var s_size: Slider = typo._sliders["font_size"]
	var s_lead: Slider = typo._sliders["line_spacing"]

	# 1) Nada repetido: lo que controla un panel no está en el otro
	var typo_props := ["font_size", "line_spacing", "letter_spacing", "fill_color", "font_family", "font_weight", "stroke_width"]
	var dup := typo_props.filter(func(p): return tool_p._fields.has(p))
	var typo_par_visible := (typo.get_node("Panel/VBoxContainer/BoxContainer2") as CanvasItem).visible \
		or (typo.get_node("Panel/VBoxContainer/BoxContainer_Valign") as CanvasItem).visible \
		or typo.get_node_or_null("Panel/VBoxContainer/RowIndents") != null
	_check(dup.is_empty() and not typo_par_visible, "ningún control repetido entre Texto y Tipografía (%s)" % [dup])

	# 2) Tipografía en vivo al arrastrar + UN paso de deshacer
	hm.clear()
	var lead0 := float(ic._read(para, "line_spacing"))
	s_lead.drag_started.emit()
	for v in [4.0, 8.0, 12.0]:
		s_lead.value = v
		await _frames(1)
		_check(is_equal_approx(float(para.get_meta("line_spacing", 0.0)), v), "interlineado EN VIVO al arrastrar: %s" % v)
	s_lead.drag_ended.emit(true)
	await _frames()
	_check(hm.can_undo(), "arrastre en Tipografía crea su paso de deshacer")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(ic._read(para, "line_spacing")), lead0) and is_equal_approx(s_lead.value, lead0), "deshacer → %s en objeto y slider" % lead0)
	_check(not hm.can_undo(), "fue UN solo paso de deshacer")

	# 3) Cambios hechos fuera (p.ej. deshacer, otro panel, atajos) llegan a Tipografía
	ic.apply("font_size", 48)
	await _frames()
	_check(is_equal_approx(s_size.value, 48.0), "cambio externo de tamaño → Tipografía 48 (%s)" % s_size.value)
	hm.undo(); await _frames()
	_check(is_equal_approx(s_size.value, 24.0), "deshacer externo → Tipografía 24 (%s)" % s_size.value)

	# 4) Oculto: se pone al día al abrirse
	typo_root.visible = false
	await _frames()
	ic.apply("font_size", 30)
	await _frames()
	typo_root.visible = true
	await _frames(3)
	_check(is_equal_approx(s_size.value, 30.0), "Tipografía oculta se actualiza al abrirse (%s)" % s_size.value)

	# 5) Editando con letras seleccionadas
	canvas.switch_tool("paragraph")
	await _frames()
	canvas.current_tool._check_and_trigger_edit_at(para)
	await _frames(3)
	var vrt = para.get_node_or_null("VectorRichText")
	var native: bool = vrt != null and vrt.is_editing()
	var te := para.get_node_or_null("MultiLineEdit") as TextEdit
	ic.apply("text", "Hola mundo")
	await _frames()
	var select := func(a: int, b: int) -> void:
		if native:
			vrt.set_selection_range(a, b)
		else:
			te.select(0, a, 0, b)
		await _frames(3)
	await open_both.call()
	await select.call(0, 4)
	hm.clear()
	s_size.drag_started.emit()
	for v in [40.0, 50.0]:
		s_size.value = v
		await _frames(2)
		var rr: Array = para.get_meta("runs", [])
		_check(not rr.is_empty() and int(rr[0].get("length", 0)) == 4 and is_equal_approx(float(rr[0].get("size", 0)), v), "editando: solo 'Hola' a %s EN VIVO (%s)" % [v, _sizes(rr)])
	s_size.drag_ended.emit(true)
	await _frames(2)
	_check(is_equal_approx(s_size.value, 50.0), "Tipografía muestra el tamaño de la selección (50)")
	await select.call(6, 9)
	_check(is_equal_approx(s_size.value, 30.0), "otra selección → Tipografía muestra 30 (%s)" % s_size.value)
	await select.call(0, 4)
	_check(is_equal_approx(s_size.value, 50.0), "volver a 'Hola' → 50 (%s)" % s_size.value)
	_check(hm.can_undo(), "arrastre por letras: undo")
	hm.undo(); await _frames(3)
	var any_big := false
	for r in para.get_meta("runs", []):
		any_big = any_big or float(r.get("size", 0.0)) > 30.0
	_check(not any_big, "deshacer → 'Hola' vuelve a 30 (%s)" % [_sizes(para.get_meta("runs", []))])
	_check(not hm.can_undo(), "UN solo paso de deshacer")

	# B con letras seleccionadas → solo esas letras
	await select.call(0, 4)
	hm.clear()
	var bb: Button = typo._fmt_btns["bold"]
	bb.pressed.emit()
	await _frames(3)
	var rb: Array = para.get_meta("runs", [])
	var first_bold := not rb.is_empty() and (bool(rb[0].get("bold", false)) or int(rb[0].get("weight", 400)) >= 700) and int(rb[0].get("length", 0)) == 4
	var rest_bold := rb.size() > 1 and (bool(rb[1].get("bold", false)) or int(rb[1].get("weight", 400)) >= 700)
	_check(first_bold and not rest_bold and int(para.get_meta("font_weight", 400)) == 400, "B editando → solo 'Hola' en negrita, el objeto sigue a 400")
	_check(bb.button_pressed, "el botón B se marca con 'Hola' seleccionado")
	await select.call(6, 9)
	_check(not bb.button_pressed, "con 'mun' seleccionado el botón B se desmarca")
	hm.undo(); await _frames(3)
	var rb2: Array = para.get_meta("runs", [])
	var any_bold := false
	for r in rb2:
		any_bold = any_bold or bool(r.get("bold", false)) or int(r.get("weight", 400)) >= 700
	_check(not any_bold, "deshacer negrita por letras")

	# 6) Muestras de color → selector de la app (pickr_color_tool.tscn)
	await select.call(0, 4)
	var cp: ColorPickerButton = typo.get_node("Panel/BoxContainer/FontColorPicker")
	await _click(cp)
	var pop = root.find_child("TextColorPopover", true, false)
	_check(pop != null and pop.visible and not cp.get_popup().visible, "la muestra abre el selector de la app (no el de Godot)")
	var pk = pop._pickr if pop else null
	_check(pk != null and pk.scene_file_path.ends_with("pickr_color_tool.tscn"), "el selector es pickr_color_tool.tscn")
	if pk:
		if OS.get_environment("E2E_OUT") != "":
			await _frames(4)
			var im := root.get_texture().get_image()
			var shot_r := Rect2i(pop.get_global_rect().merge(top.get_global_rect()).grow(10)).intersection(Rect2i(Vector2i.ZERO, im.get_size()))
			im.get_region(shot_r).save_png(OS.get_environment("E2E_OUT") + "/selector_color_tipografia.png")
		var linked := false
		var cc = root.get_node("ColorCore")
		for sig in ["changed", "paint_changed"]:
			for conn in cc.get_signal_connection_list(sig):
				linked = linked or (conn["callable"] as Callable).get_object() == pk
		_check(not linked and bool(pk.get("_from_core")), "selector aislado de ColorCore")
		var tabs_ok := true
		for prop in ["tab_linear", "tab_radial", "tab_conic"]:
			var t = pk.get(prop)
			tabs_ok = tabs_ok and not (t is CanvasItem and (t as CanvasItem).visible)
		_check(tabs_ok, "sin pestañas de degradado (texto = color sólido)")
		hm.clear()
		var green := Color(0.1, 0.7, 0.3)
		pk.picker_panel.color_changed.emit(green)
		await _frames(3)
		var rc: Array = para.get_meta("runs", [])
		var c0 = rc[0].get("color") if not rc.is_empty() else null
		var c1 = rc[1].get("color") if rc.size() > 1 else null
		_check(c0 is Color and (c0 as Color).is_equal_approx(green) and int(rc[0].get("length", 0)) == 4, "color elegido → solo 'Hola' en verde")
		_check(not (c1 is Color and (c1 as Color).is_equal_approx(green)), "' mundo' conserva su color")
		_check(cp.color.is_equal_approx(green), "la muestra muestra el verde")
		_check(hm.can_undo(), "color por letras con deshacer")
		await _press(Vector2(5, 900), true)
		await _press(Vector2(5, 900), false)
		_check(not pop.visible, "clic fuera cierra el selector")
		var sb: ColorPickerButton = typo._stroke_btn
		await _click(sb)
		_check(pop.visible and pop.current_target() == sb and not sb.get_popup().visible, "la muestra de trazo abre el mismo selector")
		var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true
		Input.parse_input_event(esc)
		await _frames(2)
		_check(not pop.visible, "Esc cierra el selector")

	print("E2E modo: ", "nativo" if native else "GDScript")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
