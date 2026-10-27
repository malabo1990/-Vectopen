## AUDITORÍA del panel de Efectos sobre la app real: cada efecto × cada tipo
## de figura (rectángulo, círculo, polígono, título, párrafo). Por caso mide:
##   · VISIBLE: píxeles que cambian respecto a la figura sin efecto;
##   · frame (ms) con el efecto;
##   · cambiar un parámetro desde el panel: pasos de deshacer creados;
##   · guardar/recargar conserva el efecto.
##   godot --path . -s res://test/e2e/effects_audit_e2e.gd   (E2E_OUT=carpeta)
extends SceneTree

var canvas: Node2D
var out := "user://effects_audit"
var CS = null
var rows: Array = []
var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("E2E FAIL ", msg)

const EFFECTS := ["Drop Shadow", "Inner Shadow", "Outline", "Blur", "Color Overlay", "Gradient Overlay", "Inner Glow", "3D"]

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _find_script_node(n: Node, suffix: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find_script_node(c, suffix)
		if r:
			return r
	return null

## Caja REAL de la figura (la de la herramienta Mover) en pantalla.
func _region(shape: Node2D) -> Rect2i:
	var xf := canvas.get_viewport().get_canvas_transform()
	var mt = canvas.current_tool
	var gr: Rect2 = mt._global_rect(shape) if mt and mt.has_method("_global_rect") else Rect2(shape.global_position, Vector2(200, 150))
	var p0: Vector2 = xf * gr.position
	var p1: Vector2 = xf * gr.end
	return Rect2i(Rect2(p0, p1 - p0).grow(90.0))

func _grab(shape: Node2D, hide: Array) -> Image:
	for c in hide: c.visible = false
	await _frames(5)
	var img := root.get_texture().get_image()
	for c in hide: c.visible = true
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

## Mínimo de 3 tandas (quita picos ajenos: compilación de shaders, GC…).
## Diferencia MEDIA (niveles de gris 0..255) entre dos capturas.
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

func _make_shapes(ab: Node2D) -> Array:
	var shapes: Array = []
	var rect = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.size = Vector2(160, 110)
	rect.fill_color = Color(0.2, 0.5, 0.9)
	ab.add_child(rect)
	rect.position = Vector2(80, 80)
	rect.set_meta("_audit_name", "rectángulo")
	rect.set_meta("_audit_rect", Rect2(Vector2.ZERO, rect.size))
	shapes.append(rect)
	var circ = load("res://script_gdscript/shapes/VectorCircle.gd").new()
	if "size" in circ:
		circ.size = Vector2(130, 130)
	circ.fill_color = Color(0.9, 0.4, 0.2)
	ab.add_child(circ)
	circ.position = Vector2(400, 80)
	circ.set_meta("_audit_name", "círculo")
	circ.set_meta("_audit_rect", Rect2(Vector2.ZERO, Vector2(130, 130)))
	shapes.append(circ)
	var poly = load("res://script_gdscript/shapes/VectorPolygon.gd").new()
	poly.vertices = PackedVector2Array([Vector2(70, 0), Vector2(140, 50), Vector2(115, 130), Vector2(25, 130), Vector2(0, 50)])
	ab.add_child(poly)
	poly.position = Vector2(80, 330)
	poly.fill_color = Color(0.3, 0.7, 0.3)
	poly.set_meta("_audit_name", "polígono")
	poly.set_meta("_audit_rect", Rect2(-80, -80, 220, 220))
	shapes.append(poly)
	return shapes

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
	canvas = get_first_node_in_group("_vectopen_canvas")
	CS = load("res://scripts/canvas/canvas_serializer.gd")
	var ic = root.get_node("InspectorCore")
	var hm = root.get_node("HistoryManager")
	var sm = root.get_node("SelectionManager")
	var tm = root.get_node("ThemeManager")
	tm.set_mode("light")
	var native := ClassDB.class_exists("VectorRichText")
	print("AUDIT modo: ", "nativo" if native else "GDScript")
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var shapes := _make_shapes(ab)
	# texto (título) y párrafo
	canvas.switch_tool("text")
	await _frames()
	var title: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(title); ic._sync_selection()
	ic.apply("text", "Sombra")
	ic.apply("font_size", 64)
	title.position = Vector2(300, 330)
	await _frames(3)
	title.set_meta("_audit_name", "título")
	title.set_meta("_audit_rect", Rect2(Vector2.ZERO, Vector2(float(title.get_meta("width")), float(title.get_meta("height")))))
	shapes.append(title)
	canvas.switch_tool("paragraph")
	await _frames()
	var para: Node2D = canvas.current_tool.create_at_center()
	await _frames()
	sm.select(para); ic._sync_selection()
	ic.apply("text", "Párrafo con efectos de texto aplicados")
	para.position = Vector2(80, 580)
	await _frames(3)
	para.set_meta("_audit_name", "párrafo")
	para.set_meta("_audit_rect", Rect2(Vector2.ZERO, Vector2(float(para.get_meta("width")), float(para.get_meta("height")))))
	shapes.append(para)
	canvas.switch_tool("move")
	await _frames(3)

	var cam = canvas.get_node_or_null("Camera2D")
	if cam:
		cam.zoom = Vector2.ONE
		cam.global_position = ab.global_position + Vector2(420, 420)
	await _frames(5)

	var panel = _find_script_node(root, "panels/effects/effects.gd")
	print("AUDIT panel efectos: ", panel != null)
	var hide: Array = []
	var bbox = canvas.get_node_or_null("BoundingBox")
	for shape in shapes:
		sm.select(shape); ic._sync_selection()
		await _frames(2)
		ic.apply("effects", [])
		sm.set_selection([]); ic._sync_selection()
		await _frames(2)
		var base := await _grab(shape, hide)
		var base_ms := await _frame_ms(30)
		for eff in EFFECTS:
			sm.select(shape); ic._sync_selection()
			await _frames(1)
			ic.apply("effects", [])
			if panel:
				panel._sync_from_inspector()
				panel._add_new_effect(eff)
			await _frames(2)
			var fx_now = ic._read(shape, "effects")
			var stored: bool = fx_now is Array and (fx_now as Array).size() == 1
			sm.set_selection([]); ic._sync_selection()
			var img := await _grab(shape, hide)
			img.save_png("%s/%s_%s.png" % [out, shape.get_meta("_audit_name"), eff.replace(" ", "_")])
			var d := _diff(base, img)
			var ms := await _frame_ms(30)
			# parámetro desde el panel: pasos de deshacer
			sm.select(shape); ic._sync_selection()
			if panel:
				panel._sync_from_inspector()
			await _frames(2)
			hm.clear()
			var steps := -1
			if panel and panel._effects_list.get_child_count() > 0:
				var entry = panel._effects_list.get_child(0)
				var spins: Array = entry.find_children("*", "SpinBox", true, false)
				var spin_nodes: Array = []
				for c in entry.find_children("*", "", true, false):
					if c.has_signal("value_changed") and "value" in c and not (c is Slider) and not (c is SpinBox) and (c as CanvasItem).is_visible_in_tree():
						spin_nodes.append(c)
				var target = spin_nodes[0] if not spin_nodes.is_empty() else (spins[0] if not spins.is_empty() else null)
				if target:
					for k in 5:
						target.value = float(target.value) - 1.0 if float(target.value) >= float(target.max_value) - 1.0 else float(target.value) + 1.0
					# el gesto se confirma tras 0,45 s sin cambios
					var tw := Time.get_ticks_msec()
					while Time.get_ticks_msec() - tw < 700:
						await process_frame
					steps = 0
					while hm.can_undo() and steps < 50:
						hm.undo()
						steps += 1
			# guardar / recargar
			var data: Dictionary = CS._serialize_element(shape)
			var has_fx_saved: bool = (data.get("fx") is Array and (data["fx"] as Array).size() > 0) or (data.get("effects") is Array and (data["effects"] as Array).size() > 0)
			rows.append([shape.get_meta("_audit_name"), eff, stored, d, ms - base_ms, steps, has_fx_saved])
			var nm := "%s / %s" % [shape.get_meta("_audit_name"), eff]
			_check(stored, nm + ": se guarda en la figura")
			_check(d > 40, nm + ": se VE (%d px cambian)" % d)
			_check(steps == 1 or steps == -1, nm + ": 5 cambios de un valor = 1 paso de deshacer (%d)" % steps)
			_check(has_fx_saved, nm + ": se guarda en el archivo")
			_check(ms - base_ms < 4.0, nm + ": coste por frame bajo (%.2f ms)" % (ms - base_ms))
			print("AUDIT %-10s %-17s guardado=%s visible_px=%5d  frame+%.2fms  undo_pasos=%d  archivo=%s" % [shape.get_meta("_audit_name"), eff, stored, d, ms - base_ms, steps, has_fx_saved])
		sm.select(shape); ic._sync_selection()
		ic.apply("effects", [])
	# ── VALORES ALTOS: que nada se corte ni falle con parámetros extremos ──
	var HIGH := [
		{"type": "Drop Shadow", "enabled": true, "offset_x": 30.0, "offset_y": 30.0, "blur": 40.0, "spread": 10.0, "color": Color(0, 0, 0, 0.7)},
		{"type": "Inner Shadow", "enabled": true, "offset_x": 12.0, "offset_y": 12.0, "blur": 20.0, "spread": 0.0, "color": Color(0, 0, 0, 0.8)},
		{"type": "Outline", "enabled": true, "width": 12.0, "color": Color(0.9, 0.1, 0.1)},
		{"type": "Blur", "enabled": true, "radius": 40.0, "preserve_alpha": false, "blur_type": "gaussian"},
		{"type": "Blur", "enabled": true, "radius": 40.0, "preserve_alpha": false, "blur_type": "motion", "angle": 0.0},
		{"type": "Blur", "enabled": true, "radius": 30.0, "preserve_alpha": false, "blur_type": "radial"},
		{"type": "Blur", "enabled": true, "radius": 30.0, "preserve_alpha": false, "blur_type": "spin"},
		{"type": "Inner Glow", "enabled": true, "color": Color(1, 1, 0.6), "radius": 25.0, "opacity": 1.0},
		{"type": "3D", "enabled": true, "depth": 40.0, "bevel": 16.0, "angle": 45.0, "highlight": 90.0, "shadow": 80.0, "extrude": true},
		{"type": "3D", "enabled": true, "depth": 40.0, "bevel": 16.0, "angle": 45.0, "highlight": 90.0, "shadow": 80.0, "extrude": false},
	]
	var HIGH_NAMES := ["sombra_alta", "sombra_int_alta", "contorno_12", "desenf_gauss_40", "desenf_mov_40", "desenf_radial_30", "desenf_giro_30", "brillo_int_25", "3d_40_con_extr", "3d_40_sin_extr"]
	for shape in shapes:
		sm.select(shape); ic._sync_selection()
		ic.apply("effects", [])
		sm.set_selection([]); ic._sync_selection()
		await _frames(2)
		var base_h := await _grab(shape, hide)
		for hi in HIGH.size():
			sm.select(shape); ic._sync_selection()
			ic.apply("effects", [(HIGH[hi] as Dictionary).duplicate()])
			sm.set_selection([]); ic._sync_selection()
			var img_h := await _grab(shape, hide)
			img_h.save_png("%s/ALTO_%s_%s.png" % [out, shape.get_meta("_audit_name"), HIGH_NAMES[hi]])
			var dh := _diff(base_h, img_h)
			_check(dh > 40, "ALTO %s / %s: se ve (%d px)" % [shape.get_meta("_audit_name"), HIGH_NAMES[hi], dh])
		sm.select(shape); ic._sync_selection()
		ic.apply("effects", [])
	var ext_on = null
	var ext_off = null

	# El degradado del efecto NO debe tocar el relleno de la figura
	var r0: Node2D = shapes[0]
	sm.select(r0); ic._sync_selection()
	ic.apply("effects", [])
	panel._sync_from_inspector()
	panel._add_new_effect("Gradient Overlay")
	await _frames(3)
	panel._sync_from_inspector()
	await _frames(2)
	var entry = panel._effects_list.get_child(0)
	var ged = entry.find_child("GradientEditor", true, false)
	var fill_before = r0.fill_gradient
	if ged and ged.has_method("_emit_gradient"):
		var g := Gradient.new()
		g.colors = PackedColorArray([Color.YELLOW, Color.GREEN])
		ged.set_gradient_resource(g)
		ged._emit_gradient()
		await _frames(3)
		var tw2 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw2 < 700:
			await process_frame
	_check(r0.fill_gradient == fill_before, "editar el degradado del efecto NO cambia el relleno de la figura")
	var fxs = ic._read(r0, "effects")
	_check(fxs is Array and fxs.size() == 1 and (fxs[0].get("colors", []) as Array).size() == 2 and (fxs[0]["colors"][0] as Color).is_equal_approx(Color.YELLOW), "y sí cambia los colores del efecto (%s)" % [fxs])
	# Texto recargado con sombra: se sigue viendo
	var tt: Node2D = shapes[3]
	sm.select(tt); ic._sync_selection()
	ic.apply("effects", [{"type": "Drop Shadow", "enabled": true, "offset_x": 6.0, "offset_y": 6.0, "blur": 4.0, "color": Color(0, 0, 0, 0.6)}])
	sm.set_selection([]); ic._sync_selection()
	var with_fx := await _grab(tt, hide)
	# Tras 0,3 s sin cambios la sombra se HORNEA a textura: debe verse igual.
	var tb := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tb < 900:
		await process_frame
	var baked_n := 0
	for spr in tt.find_children("*", "Sprite2D", true, false):
		baked_n += 1
	var baked := await _grab(tt, hide)
	baked.save_png(out + "/sombra_horneada.png")
	with_fx.save_png(out + "/sombra_en_vivo.png")
	_check(baked_n >= 1, "la sombra estática se hornea a textura (%d)" % baked_n)
	_check(_mean_diff(with_fx, baked) < 3.0, "horneada se ve igual que en vivo (dif. media %.2f niveles)" % _mean_diff(with_fx, baked))
	var data2: Dictionary = CS._serialize_element(tt)
	var parent := tt.get_parent()
	tt.free()
	await _frames(2)
	var re: Node2D = CS._element_from(data2)
	parent.add_child(re)
	CS._apply_transform(re, data2)
	await _frames(8)
	var re_img := await _grab(re, hide)
	re_img.save_png(out + "/sombra_recargada.png")
	_check(_mean_diff(with_fx, re_img) < 3.0, "texto con sombra: tras recargar se ve igual (dif. media %.2f niveles)" % _mean_diff(with_fx, re_img))
	_check(re.get_node_or_null("TextFx") != null, "texto recargado: tiene su nodo de efectos")
	print("AUDIT FIN")
	print("E2E RESULT: ", "PASS" if fails.is_empty() else "FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
