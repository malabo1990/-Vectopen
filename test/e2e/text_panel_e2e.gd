## E2E de los paneles de texto sobre la app real:
##  A) panel de la herramienta Texto (popup "text"): solo PÁRRAFO y MARCO;
##  B) panel Tipografía (menú contextual): CARÁCTER, con la fila B/I/U + trazo.
## Diseño (capturas claro/oscuro) + que cada control haga lo que dice, con
## ratón real sobre los campos numéricos.
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

func _shot(ctrl: Control, tag: String) -> void:
	await _frames(8)
	var r := Rect2i(ctrl.get_global_rect().grow(8))
	var img := root.get_texture().get_image()
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img = img.get_region(r)
	img.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/%s.png" % [out, tag])

var _pen_pos := Vector2.ZERO   # dónde quedó el puntero (arrastres en varios tramos)

func _press(at: Vector2, down: bool) -> void:
	if down:
		_pen_pos = at
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await _frames(2)

## Arrastre real en pasos de 2 px: la posición avanza (el campo ya no
## captura el ratón; mide la posición absoluta, como con un lápiz).
func _move(_at: Vector2, dx: float) -> void:
	for i in int(absf(dx) / 2.0):
		var m := InputEventMouseMotion.new()
		_pen_pos += Vector2(signf(dx) * 2.0, 0)
		var p := _pen_pos
		m.position = p
		m.global_position = p
		m.relative = Vector2(signf(dx) * 2.0, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await process_frame
	await _frames(2)

func _submit(f, txt: String) -> void:
	var le: LineEdit = f.line_edit()
	le.text = txt
	le.text_submitted.emit(txt)
	await _frames()

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
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

	# ── A) PANEL TEXTO: solo párrafo y marco ──
	for mode in ["dark", "light"]:
		tm.set_mode(mode)
		popup.visible = true
		await _shot(popup, "panel_vacio_" + mode)
	_check(pp._fields["indent_left"].is_mixed(), "sin selección los campos muestran '—'")
	var char_props := ["font_size", "line_spacing", "letter_spacing", "fill_color", "font_family"]
	var repeated := char_props.filter(func(p): return pp._fields.has(p))
	_check(repeated.is_empty() and not ("_btn_bold" in pp), "el panel Texto no repite nada de carácter (%s)" % [repeated])

	canvas.switch_tool("paragraph")
	await _frames()
	var para: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(para)
	ic._sync_selection()
	pp._sync({})
	await _frames()
	_check(is_equal_approx(pp._fields["width"].value, float(para.get_meta("width"))), "con selección el ancho muestra %s" % para.get_meta("width"))
	_check(pp._align_btns[0].button_pressed, "alineación izquierda marcada")
	tm.set_mode("dark")
	await _shot(popup, "panel_seleccion_dark")

	hm.clear()
	await _submit(pp._fields["indent_left"], "15")
	_check(is_equal_approx(float(para.get_meta("indent_left", 0.0)), 15.0), "sangría escrita 15")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("indent_left", 0.0)), 0.0), "deshacer sangría → 0")
	await _submit(pp._fields["indent_right"], "10*2")
	_check(is_equal_approx(float(para.get_meta("indent_right", 0.0)), 20.0), "expresión 10*2 → 20")

	# Arrastre REAL sobre el número: en vivo + UNA acción de undo
	hm.clear()
	var gap_f = pp._fields["column_gap"]
	var gap0 := float(ic._read(para, "column_gap"))
	var le_g: LineEdit = gap_f.line_edit()
	var cn: Vector2 = le_g.get_global_rect().get_center()
	await _press(cn, true)
	_check(not le_g.has_focus(), "pulsar sobre el número no entra a escribir todavía")
	await _move(cn, 12.0)
	var live := float(para.get_meta("column_gap", 0.0))
	_check(live > gap0, "arrastre sobre el número: medianil cambia EN VIVO (%s → %s)" % [gap0, live])
	_check(not hm.can_undo(), "aún sin undo mientras arrastra")
	await _move(cn, 10.0)
	await _press(cn, false)
	_check(float(para.get_meta("column_gap", 0.0)) > live, "valor final mayor")
	_check(hm.can_undo() and not le_g.has_focus(), "un undo al soltar y sin modo escritura")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "el ratón vuelve a ser visible al soltar")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("column_gap", 0.0)), gap0), "deshacer arrastre → %s de una vez" % gap0)
	_check(not hm.can_undo(), "fue UNA sola acción de undo")
	await _press(cn, true)
	await _move(cn, -400.0)
	await _press(cn, false)
	_check(is_equal_approx(float(para.get_meta("column_gap", 0.0)), 0.0), "arrastre a la izquierda topa en el mínimo 0")
	hm.undo(); await _frames()
	var ci: Vector2 = gap_f._lead.get_global_rect().get_center()
	await _press(ci, true)
	await _move(ci, 8.0)
	await _press(ci, false)
	_check(float(para.get_meta("column_gap", 0.0)) > gap0, "arrastre sobre el icono también cambia el valor")
	hm.undo(); await _frames()
	await _press(cn, true)
	await _press(cn, false)
	_check(le_g.has_focus() and le_g.has_selection(), "clic sin arrastrar → escribe con el valor seleccionado")
	le_g.text = "30"; le_g.text_submitted.emit("30")
	await _frames()
	_check(is_equal_approx(float(para.get_meta("column_gap", 0.0)), 30.0), "escrito tras el clic → 30")

	var lf_le: LineEdit = pp._fields["indent_first"].line_edit()
	var k := InputEventKey.new(); k.keycode = KEY_UP; k.pressed = true; k.shift_pressed = true
	lf_le.gui_input.emit(k)
	await _frames()
	_check(is_equal_approx(float(para.get_meta("indent_first", 0.0)), 10.0), "Shift+↑ en primera línea → 10")

	pp._align_btns[1].pressed.emit()
	await _frames()
	_check(String(para.get_meta("text_align", "")) == "center", "botón centrar → text_align=center")
	pp._sync({})
	_check(pp._align_btns[1].button_pressed and not pp._align_btns[0].button_pressed, "solo 'centrar' queda marcado")
	pp._valign_btns[2].pressed.emit()
	await _frames()
	_check(String(para.get_meta("text_valign", "")) == "bottom", "botón abajo → text_valign=bottom")
	await _submit(pp._fields["columns"], "2")
	_check(int(para.get_meta("columns", 1)) == 2, "columnas 2")

	canvas.switch_tool("paragraph")
	await _frames()
	var p2: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(p2)
	ic._sync_selection()
	ic.apply("width", 220)
	sm.set_selection([para, p2])
	ic._sync_selection()
	pp._sync({})
	await _frames()
	_check(pp._fields["width"].is_mixed(), "dos anchos distintos → 'Mixto'")
	tm.set_mode("light")
	await _shot(popup, "panel_mixto_light")
	popup.visible = false
	sm.select(para)
	ic._sync_selection()

	# ── B) TIPOGRAFÍA: carácter, con B/I/U + trazo ──
	var ctx: Control = root.find_child("Panel_tooltext", true, false)
	_check(ctx != null, "panel Tipografía presente")
	var n: Node = ctx
	while n and n != root:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
		n = n.get_parent()
	tm.set_mode("dark")
	await _frames(6)
	var box = ctx.get_node("BoxContainer")
	var vb: Control = box.get_node("Panel/VBoxContainer")
	_check(not (vb.get_node("BoxContainer2") as CanvasItem).visible and not (vb.get_node("BoxContainer_Valign") as CanvasItem).visible and vb.get_node_or_null("RowIndents") == null, "Tipografía no repite alineación ni sangrías")
	_check(box.get_node("Panel/BoxContainer").get_combined_minimum_size().x <= box.get_node("Panel").size.x + 0.5, "fila familia/estilo/color cabe")
	_check(vb.get_combined_minimum_size().x <= 192.5, "filas de Tipografía caben en 192 px (%s)" % vb.get_combined_minimum_size().x)
	await _shot(ctx, "panel_tipografia_dark")

	# Sin la "A": tamaño / interlineado / interletra con número visible
	_check(not (box.get_node("Panel/Label") as CanvasItem).visible, "la 'A' grande ya no está")
	var ff = box._metric_fields["font_size"]
	var fsl: Slider = box._sliders["font_size"]
	_check(ff.is_visible_in_tree() and fsl.is_visible_in_tree() and ff.line_edit().text == str(int(ic._read(para, "font_size"))), "tamaño con número visible (%s)" % ff.line_edit().text)
	hm.clear()
	await _submit(ff, "36")
	_check(int(para.get_meta("font_size")) == 36 and is_equal_approx(fsl.value, 36.0), "escribir 36 → texto y slider a 36")
	hm.undo(); await _frames()
	_check(ff.line_edit().text == "24", "deshacer → el número vuelve a 24 (%s)" % ff.line_edit().text)
	fsl.value = 60.0
	await _frames()
	_check(ff.line_edit().text == "60" and int(para.get_meta("font_size")) == 60, "mover el slider actualiza el número (%s)" % ff.line_edit().text)
	await _submit(ff, "300")
	_check(int(para.get_meta("font_size")) == 300, "se puede escribir más allá del recorrido del slider (300)")
	await _submit(ff, "24")
	hm.clear()
	var lf = box._metric_fields["letter_spacing"]
	var cl: Vector2 = lf.line_edit().get_global_rect().get_center()
	await _press(cl, true)
	await _move(cl, 10.0)
	var ls_live := float(para.get_meta("letter_spacing", 0.0))
	_check(ls_live > 0.0 and is_equal_approx(box._sliders["letter_spacing"].value, ls_live) and not hm.can_undo(), "arrastrar el número de interletra: en vivo, slider sigue, sin undo aún (%s)" % ls_live)
	await _press(cl, false)
	_check(hm.can_undo(), "al soltar: un undo")
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("letter_spacing", 0.0)), 0.0) and lf.line_edit().text == "0" and not hm.can_undo(), "deshacer → 0 en UN paso y el número también")
	box._on_prop_button_pressed("Aaa")
	await _frames()
	_check(box._prop_value_labels["start"].text == "1.60×", "proporciones muestran su valor (%s)" % box._prop_value_labels["start"].text)
	box.reset_letter_proportions()
	await _frames()
	_check(box._prop_value_labels["start"].text == "1.00×", "restablecer → 1.00×")
	sm.select_none() if sm.has_method("select_none") else sm.set_selection([])
	ic._sync_selection(); box._sincronizar(ic.current_props())
	await _frames()
	_check(ff.is_mixed(), "sin selección el tamaño muestra '—'")
	sm.select(para); ic._sync_selection(); box._sincronizar(ic.current_props())
	await _frames()

	var bb: Button = box._fmt_btns["bold"]
	hm.clear()
	bb.pressed.emit(); await _frames()
	_check(int(para.get_meta("font_weight", 400)) == 700 and bb.button_pressed, "B → peso 700 y marcado")
	var opt: OptionButton = box.get_node("Panel/BoxContainer/OptionButton")
	_check(opt.selected >= 0 and opt.get_item_text(opt.selected) == "Bold", "el estilo muestra Bold")
	bb.pressed.emit(); await _frames()
	_check(int(para.get_meta("font_weight", 400)) == 400 and not bb.button_pressed, "B otra vez → 400")
	box._fmt_btns["italic"].pressed.emit(); await _frames()
	_check(bool(para.get_meta("font_italic", false)), "I → cursiva")
	box._fmt_btns["underline"].pressed.emit(); await _frames()
	var und := true
	for r in para.get_meta("runs", []):
		und = und and bool(r.get("underline", false))
	_check(und and box._fmt_btns["underline"].button_pressed, "U → todo subrayado y marcado")
	hm.undo(); await _frames()
	var und2 := false
	for r in para.get_meta("runs", []):
		und2 = und2 or bool(r.get("underline", false))
	_check(not und2, "deshacer subrayado")

	await _submit(box._stroke_field, "2")
	_check(is_equal_approx(float(para.get_meta("stroke_width", 0.0)), 2.0), "grosor de trazo escrito 2")
	hm.clear()
	var cs: Vector2 = box._stroke_field.line_edit().get_global_rect().get_center()
	await _press(cs, true)
	await _move(cs, 8.0)
	var sw_live := float(para.get_meta("stroke_width", 0.0))
	_check(sw_live > 2.0 and not hm.can_undo(), "arrastre del grosor en vivo (%s) sin undo aún" % sw_live)
	await _press(cs, false)
	hm.undo(); await _frames()
	_check(is_equal_approx(float(para.get_meta("stroke_width", 0.0)), 2.0) and not hm.can_undo(), "deshacer arrastre de grosor → 2 en UN paso")

	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
