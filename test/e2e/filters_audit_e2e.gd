## AUDITORÍA de la pestaña "Filters" (panel Efectos) sobre la app real:
##   · la pestaña existe y alterna con las demás;
##   · cada filtro × figura (rectángulo, círculo, polígono, título, párrafo):
##     se guarda, SE VE, coste por frame, 5 cambios = 1 deshacer, archivo;
##   · valores altos, cristal sobre fondo, orden de dibujo, deshacer,
##     guardar/recargar y rendimiento con muchos objetos.
##   godot --path . -s res://test/e2e/filters_audit_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var canvas: Node2D
var out := "user://filters_audit"
var CS = null
var fails: Array[String] = []

const FILTERS := ["glass", "grain", "duotone", "neon", "chromatic", "glitch", "halftone", "pixelate"]

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame

func _find_script_node(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find_script_node(c, suffix)
		if r:
			return r
	return null

func _region(shape: Node2D) -> Rect2i:
	var xf := canvas.get_viewport().get_canvas_transform()
	var mt = canvas.current_tool
	var gr: Rect2 = mt._global_rect(shape) if mt and mt.has_method("_global_rect") else Rect2(shape.global_position, Vector2(200, 150))
	var p0: Vector2 = xf * gr.position
	var p1: Vector2 = xf * gr.end
	return Rect2i(Rect2(p0, p1 - p0).grow(60.0))

func _grab(shape: Node2D) -> Image:
	await _frames(5)
	var img := root.get_texture().get_image()
	var r := _region(shape).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return img.get_region(r)

func _diff(a: Image, b: Image) -> int:
	var n := 0
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.08:
				n += 1
	return n

func _mean_diff(a: Image, b: Image) -> float:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var acc := 0.0
	var n := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			acc += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return acc / maxf(1.0, n) * 255.0

func _frame_ms(n: int) -> float:
	var best := INF
	for r in 3:
		var t0 := Time.get_ticks_usec()
		await _frames(maxi(1, n / 3))
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0 / maxi(1, n / 3))
	return best

func _frame_ms_step(n: int, step: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		step.call(i)
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _make_shapes(ab: Node2D) -> Array:
	var shapes: Array = []
	var rect = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.size = Vector2(160, 110)
	rect.fill_color = Color(0.2, 0.5, 0.9)
	rect.stroke_width = 0.0
	ab.add_child(rect)
	rect.position = Vector2(80, 80)
	rect.set_meta("_audit_name", "rectángulo")
	shapes.append(rect)
	var circ = load("res://script_gdscript/shapes/VectorCircle.gd").new()
	if "size" in circ:
		circ.size = Vector2(130, 130)
	circ.fill_color = Color(0.9, 0.4, 0.2)
	ab.add_child(circ)
	circ.position = Vector2(400, 80)
	circ.set_meta("_audit_name", "círculo")
	shapes.append(circ)
	var poly = load("res://script_gdscript/shapes/VectorPolygon.gd").new()
	poly.vertices = PackedVector2Array([Vector2(70, 0), Vector2(140, 50), Vector2(115, 130), Vector2(25, 130), Vector2(0, 50)])
	ab.add_child(poly)
	poly.position = Vector2(80, 330)
	poly.fill_color = Color(0.3, 0.7, 0.3)
	poly.set_meta("_audit_name", "polígono")
	shapes.append(poly)
	return shapes

func _run() -> void:
	var env_out := OS.get_environment("E2E_OUT")
	if env_out != "": out = env_out
	DirAccess.make_dir_recursive_absolute(out)
	# Pruebas con ventana en la 2.ª pantalla (Huion), no en la principal.
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)  # pantalla Huion completa
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	# Arranque por fases (StartupPhases): esperar a que estén todos los paneles.
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"): break
		await process_frame
	await _frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var sm = root.get_node("SelectionManager")
	root.get_node("ThemeManager").set_mode("light")
	print("FILTERS modo: ", "nativo" if ClassDB.class_exists("VectorRichText") else "GDScript")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var shapes := _make_shapes(ab)
	canvas.switch_tool("text")
	await _frames()
	var title: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(title); ic._sync_selection()
	ic.apply("text", "Filtros")
	ic.apply("font_size", 64)
	title.position = Vector2(300, 330)
	title.set_meta("_audit_name", "título")
	shapes.append(title)
	canvas.switch_tool("paragraph")
	await _frames()
	var para: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(para); ic._sync_selection()
	ic.apply("text", "Párrafo con filtros de imagen aplicados")
	para.position = Vector2(80, 580)
	para.set_meta("_audit_name", "párrafo")
	shapes.append(para)
	canvas.switch_tool("move")
	await _frames(3)
	var cam = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.zoom = Vector2.ONE
		cam.global_position = ab.global_position + Vector2(420, 420)
	await _frames(5)

	# ── 1. La pestaña ──────────────────────────────────────────────────────
	var fx_panel = _find_script_node(root, "panels/effects/effects.gd")
	_check(fx_panel != null, "panel de efectos encontrado")
	await _frames(2)
	var content: Node = fx_panel.get_parent()
	var panel = content.get_node_or_null("Filters")
	var header: Node = content.get_parent().get_node("MarginContainer/HBoxContainer")
	var btn: Button = header.get_node_or_null("ButtonFilters")
	_check(panel != null, "existe la pestaña Filters")
	_check(btn != null and btn.text in ["Filters", "Filtros"], "existe el botón Filters en la cabecera")
	if panel == null or btn == null:
		_finish()
		return
	_check(btn.get_index() < header.get_node("Spacer").get_index(), "el botón va junto a las demás pestañas")
	btn.pressed.emit()
	_check(panel.visible and not fx_panel.visible, "pulsar Filters muestra la pestaña y oculta Efectos")
	(header.get_node("ButtonEffects") as Button).pressed.emit()
	_check(fx_panel.visible and not panel.visible, "pulsar Effects vuelve a Efectos")
	(header.get_node("ButtonShader") as Button).pressed.emit()
	_check(content.get_node("Shader").visible and not panel.visible, "las otras pestañas siguen funcionando (Shader)")
	btn.pressed.emit()
	await _frames(2)
	sm.set_selection([]); ic._sync_selection()
	await _frames(2)
	_check(panel._add_btn.disabled, "sin selección: añadir desactivado")

	# Captura de la pestaña con tres filtros (para revisar el diseño)
	sm.select(shapes[0]); ic._sync_selection()
	panel.sync_from_selection()
	panel.add_filter("duotone")
	panel.add_filter("grain")
	panel.add_filter("neon")
	var win: Node = content.owner
	var prev_vis: bool = win.visible
	var anc: Node = win
	while anc is CanvasItem:
		(anc as CanvasItem).visible = true
		anc = anc.get_parent()
	btn.pressed.emit()
	await _frames(8)
	var pimg := root.get_texture().get_image()
	var prect := Rect2i((win as Control).get_global_rect().grow(20)).intersection(Rect2i(Vector2i.ZERO, pimg.get_size()))
	if prect.size.x > 0 and prect.size.y > 0:
		pimg.get_region(prect).save_png(out + "/panel_filtros.png")
	_check((win as Control).get_global_rect().encloses(Rect2(header.get_global_rect().position, header.get_combined_minimum_size())), "la fila de pestañas cabe en la ventana")
	print("FILTERS ventana ", (win as Control).get_global_rect(), " panel ", panel.get_global_rect(), " min ", panel.get_combined_minimum_size())
	_check(panel._list.get_child_count() == 3, "la pestaña muestra 3 tarjetas (%d)" % panel._list.get_child_count())
	win.visible = prev_vis
	ic.apply("filters", [])
	await _frames(2)

	# ── 2. Cada filtro × cada figura ───────────────────────────────────────
	for shape in shapes:
		sm.select(shape); ic._sync_selection()
		ic.apply("filters", [])
		sm.set_selection([]); ic._sync_selection()
		await _frames(2)
		var base := await _grab(shape)
		var base_ms := await _frame_ms(30)
		for f in FILTERS:
			if f == "glass":
				continue   # sobre fondo liso no cambia nada: prueba propia abajo
			sm.select(shape); ic._sync_selection()
			await _frames(1)
			ic.apply("filters", [])
			panel.sync_from_selection()
			panel.add_filter(f)
			await _frames(2)
			var now = ic._read(shape, "filters")
			var stored: bool = now is Array and (now as Array).size() == 1 and String(now[0]["type"]) == f
			sm.set_selection([]); ic._sync_selection()
			var img := await _grab(shape)
			img.save_png("%s/%s_%s.png" % [out, shape.get_meta("_audit_name"), f])
			var d := _diff(base, img)
			var ms := await _frame_ms(30)
			# 5 cambios de un valor desde el panel = 1 paso de deshacer
			sm.select(shape); ic._sync_selection()
			panel.sync_from_selection()
			await _frames(2)
			hm.clear()
			var steps := -1
			var card: Node = panel._list.get_child(0) if panel._list.get_child_count() > 0 else null
			var nf = null
			if card:
				for c in card.find_children("Value", "", true, false):
					if "min_value" in c:
						nf = c
						break
			if nf:
				for k in 5:
					var v: float = float(nf.value) + float(nf.step) * (1.0 if float(nf.value) < float(nf.max_value) - float(nf.step) * 6.0 else -1.0)
					nf.value = v
					await process_frame
				await _wait_ms(700)
				steps = 0
				while hm.can_undo() and steps < 50:
					hm.undo()
					steps += 1
			var data: Dictionary = CS._serialize_element(shape)
			var saved: bool = data.get("filters") is Array and (data["filters"] as Array).size() == 1
			var nm := "%s / %s" % [shape.get_meta("_audit_name"), f]
			_check(stored, nm + ": se guarda en el objeto")
			_check(d > 40, nm + ": se VE (%d px cambian)" % d)
			_check(steps == 1, nm + ": 5 cambios de un valor = 1 paso de deshacer (%d)" % steps)
			_check(saved, nm + ": se guarda en el archivo")
			_check(ms - base_ms < 4.0, nm + ": coste por frame bajo (%.2f ms)" % (ms - base_ms))
			print("FILTERS %-10s %-10s guardado=%s visible_px=%5d frame+%.2fms undo_pasos=%d archivo=%s" % [shape.get_meta("_audit_name"), f, stored, d, ms - base_ms, steps, saved])
		sm.select(shape); ic._sync_selection()
		ic.apply("filters", [])
		await _frames(2)
		sm.set_selection([]); ic._sync_selection()
		var back := await _grab(shape)
		_check(_mean_diff(base, back) < 1.0, "%s: sin filtros vuelve a verse igual que al principio (%.2f)" % [shape.get_meta("_audit_name"), _mean_diff(base, back)])
		_check(shape.get_node_or_null("FilterFx") == null, "%s: sin filtros no queda nodo" % shape.get_meta("_audit_name"))

	# ── 3. Valores altos + combinaciones ───────────────────────────────────
	var HIGH := {
		"grano_100": [{"type": "grain", "enabled": true, "amount": 100.0, "size": 4.0, "mono": false}],
		"neon_100": [{"type": "neon", "enabled": true, "color": Color(1, 0.1, 0.9), "radius": 100.0, "intensity": 400.0, "tint": 100.0}],
		"aberr_50": [{"type": "chromatic", "enabled": true, "amount": 50.0, "angle": 30.0}],
		"glitch_200": [{"type": "glitch", "enabled": true, "amount": 100.0, "shift": 200.0, "band": 3.0, "seed": 7.0}],
		"semitono_40": [{"type": "halftone", "enabled": true, "cell": 40.0, "angle": 30.0, "scale": 200.0}],
		"pixel_100": [{"type": "pixelate", "enabled": true, "size": 100.0}],
		"todos": [
			{"type": "duotone", "enabled": true, "dark": Color(0.1, 0, 0.3), "light": Color(1, 0.8, 0.2), "mix": 100.0},
			{"type": "grain", "enabled": true, "amount": 40.0, "size": 1.0, "mono": true},
			{"type": "neon", "enabled": true, "color": Color(0.1, 1, 0.9), "radius": 20.0, "intensity": 150.0, "tint": 50.0},
			{"type": "chromatic", "enabled": true, "amount": 4.0, "angle": 0.0},
			{"type": "glitch", "enabled": true, "amount": 30.0, "shift": 12.0, "band": 6.0, "seed": 2.0},
			{"type": "pixelate", "enabled": true, "size": 4.0},
		],
	}
	for shape in [shapes[0], shapes[3]]:
		sm.select(shape); ic._sync_selection()
		ic.apply("filters", [])
		sm.set_selection([]); ic._sync_selection()
		var base_h := await _grab(shape)
		for k in HIGH:
			sm.select(shape); ic._sync_selection()
			ic.apply("filters", (HIGH[k] as Array).duplicate(true))
			sm.set_selection([]); ic._sync_selection()
			var img_h := await _grab(shape)
			img_h.save_png("%s/ALTO_%s_%s.png" % [out, shape.get_meta("_audit_name"), k])
			_check(_diff(base_h, img_h) > 40, "ALTO %s / %s: se ve" % [shape.get_meta("_audit_name"), k])
		sm.select(shape); ic._sync_selection()
		ic.apply("filters", [])

	# ── 4. Cristal esmerilado sobre un fondo de rayas ──────────────────────
	var stripes: Array = []
	for i in 8:
		var s = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
		s.size = Vector2(14, 220)
		s.fill_color = Color.from_hsv(i / 8.0, 0.8, 0.9)
		s.stroke_width = 0.0
		ab.add_child(s)
		ab.move_child(s, 0)
		s.position = Vector2(30 + i * 28, 30)
		stripes.append(s)
	var glass_rect: Node2D = shapes[0]
	glass_rect.fill_color = Color(1, 1, 1, 0.15)
	await _frames(3)
	var g0 := await _grab(glass_rect)
	sm.select(glass_rect); ic._sync_selection()
	panel.sync_from_selection()
	panel.add_filter("glass")
	sm.set_selection([]); ic._sync_selection()
	var g1 := await _grab(glass_rect)
	g0.save_png(out + "/cristal_antes.png")
	g1.save_png(out + "/cristal_despues.png")
	_check(_diff(g0, g1) > 200, "cristal: el fondo de detrás se desenfoca (%d px)" % _diff(g0, g1))
	# las rayas FUERA de la figura no cambian (la copia del fondo no se escapa):
	# franja de la captura por debajo del rectángulo
	var xf := canvas.get_viewport().get_canvas_transform()
	var gr: Rect2 = canvas.current_tool._global_rect(glass_rect)
	var reg := _region(glass_rect)
	var below_y := int((xf * gr.end).y) - reg.position.y + 8
	var strip_h := 40
	var outside0 := g0.get_region(Rect2i(0, below_y, g0.get_width(), strip_h))
	var outside1 := g1.get_region(Rect2i(0, below_y, g1.get_width(), strip_h))
	_check(_mean_diff(outside0, outside1) < 1.0, "cristal: fuera de la figura el fondo queda intacto (%.2f)" % _mean_diff(outside0, outside1))
	sm.select(glass_rect); ic._sync_selection()
	ic.apply("filters", [])
	glass_rect.fill_color = Color(0.2, 0.5, 0.9)
	for s in stripes:
		s.queue_free()
	await _frames(3)

	# ── 5. Orden de dibujo: el filtrado no salta por encima de los de arriba ─
	var low: Node2D = shapes[0]
	var top = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	top.size = Vector2(80, 60)
	top.fill_color = Color(1, 0.9, 0.1)
	top.stroke_width = 0.0
	ab.add_child(top)
	top.position = low.position
	sm.select(low); ic._sync_selection()
	ic.apply("filters", [{"type": "duotone", "enabled": true, "dark": Color(0, 0, 0.3), "light": Color(1, 0.2, 0.2), "mix": 100.0}])
	sm.set_selection([]); ic._sync_selection()
	await _frames(5)
	xf = canvas.get_viewport().get_canvas_transform()
	var px_top: Vector2 = xf * top.global_position
	var col_top := root.get_texture().get_image().get_pixelv(Vector2i(px_top))
	_check(col_top.r > 0.9 and col_top.g > 0.8 and col_top.b < 0.3, "el objeto de arriba sigue encima del filtrado (%s)" % col_top)
	# subir el filtrado por encima (reordenar capas) → ahora tapa al otro
	ab.move_child(low, ab.get_child_count() - 1)
	await _frames(5)
	var col_after := root.get_texture().get_image().get_pixelv(Vector2i(px_top))
	_check(not (col_after.r > 0.9 and col_after.g > 0.8 and col_after.b < 0.3), "reordenar: el filtrado pasa por encima (%s)" % col_after)
	top.queue_free()
	sm.select(low); ic._sync_selection()
	ic.apply("filters", [])
	await _frames(3)

	# ── 6. Deshacer al añadir + guardar / recargar ─────────────────────────
	var tt: Node2D = shapes[3]
	sm.set_selection([]); ic._sync_selection()
	var t_base := await _grab(tt)
	sm.select(tt); ic._sync_selection()
	panel.sync_from_selection()
	hm.clear()
	panel.add_filter("duotone")
	await _frames(3)
	_check(tt.get_node_or_null("FilterFx") != null, "texto con filtro: tiene su nodo")
	hm.undo()
	await _frames(3)
	sm.set_selection([]); ic._sync_selection()
	var t_undo := await _grab(tt)
	_check(_mean_diff(t_base, t_undo) < 1.0 and tt.get_node_or_null("FilterFx") == null, "deshacer quita el filtro (%.2f)" % _mean_diff(t_base, t_undo))
	sm.select(tt); ic._sync_selection()
	hm.redo()
	await _frames(3)
	sm.set_selection([]); ic._sync_selection()
	var t_fx := await _grab(tt)
	_check(_diff(t_base, t_fx) > 40, "rehacer lo devuelve")
	var data2: Dictionary = CS._serialize_element(tt)
	var parent := tt.get_parent()
	tt.free()
	await _frames(2)
	var re: Node2D = CS._element_from(data2)
	parent.add_child(re)
	CS._apply_transform(re, data2)
	await _frames(8)
	var re_img := await _grab(re)
	re_img.save_png(out + "/texto_filtro_recargado.png")
	t_fx.save_png(out + "/texto_filtro.png")
	_check(re.get_node_or_null("FilterFx") != null, "recargado: tiene su nodo de filtros")
	_check(_mean_diff(t_fx, re_img) < 3.0, "recargado: se ve igual (%.2f)" % _mean_diff(t_fx, re_img))

	# ── 6b. Exportar a PNG incluye el filtro ───────────────────────────────
	var er: Node2D = shapes[0]
	sm.select(er); ic._sync_selection()
	ic.apply("filters", [{"type": "duotone", "enabled": true, "dark": Color(0.4, 0, 0), "light": Color(1, 0.1, 0.1), "mix": 100.0}])
	sm.set_selection([]); ic._sync_selection()
	await _frames(3)
	if ab.has_method("render_to_image"):
		var ex: Image = await ab.render_to_image(1.0)
		var ec := ex.get_pixelv(Vector2i(er.position))
		ex.save_png(out + "/export_png.png")
		_check(ec.r > 0.35 and ec.b < 0.2, "exportar PNG: el rectángulo sale con el filtro (%s)" % ec)
	sm.select(er); ic._sync_selection()
	ic.apply("filters", [])
	await _frames(2)

	# ── 7. Rendimiento: 60 objetos con filtros ─────────────────────────────
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var pm = root.get_node_or_null("PerformanceManager")
	if pm:
		pm.target_fps = 0
		if pm.has_method("set_idle_render"):
			pm.set_idle_render(false)
	var many: Array = []
	var rect_script = load("res://script_gdscript/shapes/VectorRectangle.gd")
	for i in 60:
		var r = rect_script.new()
		r.size = Vector2(50, 35)
		r.fill_color = Color.from_hsv(i / 60.0, 0.7, 0.9)
		ab.add_child(r)
		r.position = Vector2(60 + (i % 10) * 75, 700 + (i / 10) * 45)
		r.set_meta("filters", [FilterFx_make("grain"), FilterFx_make("duotone"), FilterFx_make(["neon", "glitch", "pixelate", "halftone", "chromatic"][i % 5])])
		load("res://script_gdscript/shapes/filter_fx.gd").sync(r)
		many.append(r)
	await _frames(10)
	if cam:
		cam.zoom = Vector2(0.8, 0.8)
		cam.global_position = ab.global_position + Vector2(420, 760)
	await _frames(10)
	var idle := await _frame_ms(60)
	var z0: Vector2 = cam.zoom if cam else Vector2.ONE
	var zoom_ms := await _frame_ms_step(60, func(i): if cam: cam.zoom = z0 * (1.0 + 0.4 * sin(i * 0.2)))
	if cam: cam.zoom = z0
	for r in many:
		r.set_meta("filters", [])
		load("res://script_gdscript/shapes/filter_fx.gd").sync(r)
	await _frames(5)
	var idle0 := await _frame_ms(60)
	print("E2E PERF frame reposo 60 objetos con 3 filtros   %.2f ms (sin filtros %.2f)" % [idle, idle0])
	print("E2E PERF frame zoom   60 objetos con 3 filtros   %.2f ms" % zoom_ms)
	_check(idle - idle0 < 8.0, "60 objetos con filtros: reposo razonable (+%.2f ms)" % (idle - idle0))
	_finish()

func FilterFx_make(t: String) -> Dictionary:
	return load("res://script_gdscript/shapes/filter_fx.gd").make(t)

func _finish() -> void:
	print("FILTERS FIN")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
