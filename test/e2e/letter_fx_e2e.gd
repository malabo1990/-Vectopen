## E2E del panel "Letras avanzadas" sobre la app real, midiendo la TINTA en
## pantalla (con y sin extensión nativa):
##   proporciones (preajuste y curva), onda / arco, interletra progresiva,
##   caja ajustada, edición sin hornear efectos, guardar/recargar, deshacer.
##   godot --path . -s res://test/e2e/letter_fx_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var fails: Array[String] = []
var out := "user://letter_fx_e2e"
var canvas: Node2D
var CS = null
var hide_list: Array = []   # paneles que se ocultan al medir (su fondo oscuro no es tinta)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("E2E OK   " if cond else "E2E FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _region(shape: Node2D) -> Rect2i:
	var w := float(shape.get_meta("width", 300.0))
	var h := float(shape.get_meta("height", 80.0))
	var xf := canvas.get_viewport().get_canvas_transform()
	var p0: Vector2 = xf * shape.global_position
	var p1: Vector2 = xf * (shape.global_position + Vector2(w, h))
	return Rect2i(Rect2(p0, p1 - p0).grow(90.0))

## Columnas con tinta (casi negro) → {rect, cols: {x: [ymin, ymax]}}.
func _ink(tag: String, shape: Node2D) -> Dictionary:
	var was: Array = []
	for c in hide_list:
		was.append(c.visible)
		c.visible = false
	await _frames(6)
	var img := root.get_texture().get_image()
	for i in hide_list.size():
		hide_list[i].visible = was[i]
	img.save_png("%s/%s.png" % [out, tag])
	var r := _region(shape).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var minp := Vector2i(1 << 30, 1 << 30)
	var maxp := Vector2i(-1, -1)
	var cols := {}
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var c := img.get_pixel(x, y)
			if c.r < 0.2 and c.g < 0.2 and c.b < 0.2:
				minp = Vector2i(mini(minp.x, x), mini(minp.y, y))
				maxp = Vector2i(maxi(maxp.x, x), maxi(maxp.y, y))
				if not cols.has(x):
					cols[x] = [y, y]
				else:
					cols[x][1] = y
	if maxp.x < 0:
		return {"rect": Rect2i(), "cols": {}}
	return {"rect": Rect2i(minp, maxp - minp + Vector2i.ONE), "cols": cols}

## Altura y techo medios de la tinta en la franja [a, b) (0..1) del ancho.
func _band(ink: Dictionary, a: float, b: float) -> Dictionary:
	var r: Rect2i = ink["rect"]
	var x0 := r.position.x + int(r.size.x * a)
	var x1 := r.position.x + int(r.size.x * b)
	var top := 1e9
	var bottom := -1e9
	for x in range(x0, x1):
		if ink["cols"].has(x):
			top = minf(top, ink["cols"][x][0])
			bottom = maxf(bottom, ink["cols"][x][1])
	return {"top": top, "h": bottom - top}

func _shape_screen_rect(shape: Node2D) -> Rect2:
	var xf := canvas.get_viewport().get_canvas_transform()
	var p0: Vector2 = xf * shape.global_position
	var p1: Vector2 = xf * (shape.global_position + Vector2(float(shape.get_meta("width")), float(shape.get_meta("height"))))
	return Rect2(p0, p1 - p0)

func _baked(shape: Node2D) -> bool:
	for r in shape.get_meta("runs", []):
		if absf(float(r.get("baseline_shift", 0.0))) > 0.01 or absf(float(r.get("letter_spacing", 0.0))) > 0.01:
			return true
		if float(r.get("size", 0.0)) > 0.0 and not is_equal_approx(float(r.get("size")), float(shape.get_meta("font_size"))):
			return true
	return false

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var sm = root.get_node("SelectionManager")
	var native := ClassDB.class_exists("VectorRichText")
	print("E2E modo: ", "nativo" if native else "GDScript")
	canvas.switch_tool("text")
	await _frames()
	var t: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(t)
	ic._sync_selection()
	ic.apply("text", "Proporciones")
	ic.apply("font_size", 48)
	await _frames(3)
	var cam = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.zoom = Vector2.ONE
		cam.global_position = t.global_position + Vector2(200, 30)
	await _frames(4)
	var plain := await _ink("0_normal", t)
	_check(plain["rect"].size.x > 0, "se ve el texto normal")
	var pb := _band(plain, 0.0, 0.12)
	var pe := _band(plain, 0.88, 1.0)

	# Panel Tipografía → botón Letras avanzadas
	var typo_root: Control = root.find_child("Panel_tooltext", true, false)
	var n: Node = typo_root
	while n and n != root:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
		n = n.get_parent()
	await _frames(4)
	var typo = typo_root.get_node("BoxContainer")
	var vb: Control = typo.get_node("Panel/VBoxContainer")
	_check(not (vb.get_node("BoxContainer5") as CanvasItem).visible and not (vb.get_node("HBoxContainer") as CanvasItem).visible, "las proporciones ya no están en Tipografía")
	var adv: Button = vb.get_node("RowAdvanced")
	_check(adv.is_visible_in_tree(), "botón 'Letras avanzadas' en Tipografía")
	adv.pressed.emit()
	await _frames(4)
	var pop = root.find_child("LetterFxPopover", true, false)
	_check(pop != null and pop.visible, "el botón abre el panel Letras avanzadas")
	var anchor: Control = typo._menu_anchor()
	_check(not pop.get_global_rect().intersects(anchor.get_global_rect()), "el panel se abre al lado del menú, sin taparlo")
	hide_list = [pop, anchor]
	var im := root.get_texture().get_image()
	var shot := Rect2i(pop.get_global_rect().merge(anchor.get_global_rect()).grow(8)).intersection(Rect2i(Vector2i.ZERO, im.get_size()))
	im.get_region(shot).save_png("%s/panel_letras_avanzadas.png" % out)

	# 1) Proporciones Aaa
	hm.clear()
	pop._prop_btns["Aaa"].pressed.emit()
	await _frames(3)
	_check(String(t.get_meta("letter_proportions", {}).get("mode", "")) == "Aaa", "preajuste Aaa guardado")
	_check(not _baked(t), "los runs del usuario no se tocan (efecto paramétrico)")
	var aaa := await _ink("1_Aaa", t)
	var ab := _band(aaa, 0.0, 0.12)
	var ae := _band(aaa, 0.88, 1.0)
	print("  alturas: normal %s/%s  Aaa %s/%s" % [pb["h"], pe["h"], ab["h"], ae["h"]])
	_check(ab["h"] > ae["h"] * 2.0, "Aaa: la primera letra es mucho más alta que la última (%s vs %s)" % [ab["h"], ae["h"]])
	_check(pop._prop_btns["Aaa"].button_pressed, "el preajuste queda marcado")
	_check(adv.get_meta("fx_active", false), "el botón indica que hay efectos activos")
	var sr := _shape_screen_rect(t).grow(4.0)
	_check(sr.encloses(Rect2(aaa["rect"])), "la caja del texto contiene todas las letras (%s ⊇ %s)" % [sr, aaa["rect"]])
	_check(hm.can_undo(), "preajuste con deshacer")
	hm.undo(); await _frames(3)
	var und := await _ink("1b_undo", t)
	_check(absf(_band(und, 0.0, 0.12)["h"] - pb["h"]) <= 3 and t.get_meta("letter_proportions", {}).is_empty(), "deshacer → letras normales")

	# 2) Curva: arrastrar el primer punto hacia arriba
	hm.clear()
	var cv: Control = pop._curve
	var p0: Vector2 = pop._curve_pt(0, 1.0)
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = p0
	cv.gui_input.emit(down)
	for i in 6:
		var mv := InputEventMouseMotion.new(); mv.position = p0 - Vector2(0, 4 * (i + 1))
		cv.gui_input.emit(mv)
		await process_frame
	_check(not hm.can_undo() and float(t.get_meta("letter_proportions", {}).get("start", 1.0)) > 1.2, "arrastrar la curva cambia la 1ª letra EN VIVO (%s)" % t.get_meta("letter_proportions", {}).get("start", "-"))
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = p0 - Vector2(0, 24)
	cv.gui_input.emit(up)
	await _frames(3)
	_check(String(t.get_meta("letter_proportions", {}).get("mode", "")) == "custom" and hm.can_undo(), "curva propia guardada con UN deshacer")
	hm.undo(); await _frames(2)
	_check(t.get_meta("letter_proportions", {}).is_empty() and not hm.can_undo(), "deshacer la curva de una vez")

	# 3) Arco: las letras del centro suben
	pop._wave_btns["arc"].pressed.emit()
	await _frames(2)
	var amt = pop._w_amount
	amt.line_edit().text = "30"; amt.line_edit().text_submitted.emit("30")
	await _frames(3)
	_check(String(t.get_meta("letter_wave", {}).get("mode", "")) == "arc" and is_equal_approx(float(t.get_meta("letter_wave", {}).get("amount", 0)), 30.0), "arco de 30 px guardado")
	var arc := await _ink("3_arco", t)
	var mid_top: float = _band(arc, 0.42, 0.58)["top"]
	var ends_top: float = minf(_band(arc, 0.0, 0.1)["top"], _band(arc, 0.9, 1.0)["top"])
	print("  techo centro %s  extremos %s" % [mid_top, ends_top])
	_check(mid_top < ends_top - 12.0, "arco: el centro sube respecto a los extremos")
	_check(_shape_screen_rect(t).grow(4.0).encloses(Rect2(arc["rect"])), "la caja contiene el arco")
	pop._wave_btns[""].pressed.emit()
	await _frames(2)
	_check(t.get_meta("letter_wave", {}).is_empty(), "'sin onda' quita el efecto")

	# 4) Interletra progresiva: el texto se ensancha
	var w0: int = (await _ink("4a", t))["rect"].size.x
	var re = pop._r_end
	re.line_edit().text = "20"; re.line_edit().text_submitted.emit("20")
	await _frames(3)
	var ramp := await _ink("4_interletra", t)
	print("  ancho %s → %s" % [w0, ramp["rect"].size.x])
	_check(ramp["rect"].size.x > w0 + 60, "interletra 0→20: el texto se ensancha (%s → %s)" % [w0, ramp["rect"].size.x])
	_check(_shape_screen_rect(t).grow(4.0).encloses(Rect2(ramp["rect"])), "la caja crece con la interletra")

	# 5) Editar no hornea los efectos; al salir vuelven
	pop._prop_btns["Aaa"].pressed.emit()
	await _frames(2)
	var with_fx := await _ink("5a_fx", t)
	canvas.switch_tool("text")
	await _frames()
	var tt = canvas.current_tool
	tt.target_artboard = t.get_parent()
	tt._check_and_trigger_edit_at(t.get_parent().to_local(t.global_position + Vector2(5, 5)))
	await _frames(4)
	pop.visible = false   # (su Esc cerraría el panel en vez de salir de la edición)
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(5)
	_check(not is_instance_valid(tt) or not tt.is_editing, "Esc sale de la edición")
	_check(not _baked(t), "tras editar y salir, los runs siguen sin efectos horneados")
	var after_edit := await _ink("5b_tras_editar", t)
	_check(absi(after_edit["rect"].size.x - with_fx["rect"].size.x) <= 4 and absi(after_edit["rect"].size.y - with_fx["rect"].size.y) <= 4, "al salir de editar los efectos vuelven igual (%s vs %s)" % [after_edit["rect"], with_fx["rect"]])

	# 6) Cambiar el color del objeto con efectos no los hornea
	sm.select(t); ic._sync_selection()
	ic.apply("fill_color", Color(0.05, 0.05, 0.1))
	await _frames(3)
	_check(not _baked(t), "cambiar el color no hornea los efectos")
	var col_ink := await _ink("6_color", t)
	_check(absi(col_ink["rect"].size.x - with_fx["rect"].size.x) <= 4, "y siguen viéndose igual")

	# 7) Guardar / recargar
	var ab_node: Node = t.get_parent()
	var data: Dictionary = CS._serialize_element(t)
	_check(data.has("letter_proportions") and data.has("letter_tracking_ramp"), "se guardan en el archivo")
	sm.set_selection([])
	ic._sync_selection()
	t.free()
	await _frames(2)
	var re_t: Node2D = CS._element_from(data)
	ab_node.add_child(re_t)
	CS._apply_transform(re_t, data)
	await _frames(6)
	var re_ink := await _ink("7_recargado", re_t)
	_check(absi(re_ink["rect"].size.x - with_fx["rect"].size.x) <= 4 and absi(re_ink["rect"].size.y - with_fx["rect"].size.y) <= 4, "tras recargar se ve igual (%s vs %s)" % [re_ink["rect"], with_fx["rect"]])
	_check(not _baked(re_t), "y los runs siguen limpios")

	# 8) Restablecer todo (UN deshacer) y cerrar con Esc
	sm.select(re_t); ic._sync_selection()
	pop._sync()
	hm.clear()
	pop._on_reset_all()
	await _frames(3)
	_check(not re_t.has_meta("letter_proportions") or re_t.get_meta("letter_proportions", {}).is_empty(), "restablecer quita las proporciones")
	_check(re_t.get_meta("letter_tracking_ramp", {}).is_empty(), "restablecer quita la interletra progresiva")
	_check(hm.can_undo(), "restablecer se puede deshacer")
	hm.undo(); await _frames(3)
	_check(String(re_t.get_meta("letter_proportions", {}).get("mode", "")) == "Aaa", "deshacer restablecer → vuelven los efectos")
	pop.visible = true
	Input.parse_input_event(esc)
	await _frames(2)
	_check(not pop.visible, "Esc cierra el panel")

	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	for f in fails:
		print("  - ", f)
	quit(0 if fails.is_empty() else 1)
