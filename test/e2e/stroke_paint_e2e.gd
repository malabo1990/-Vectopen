# =============================================================================
# PRUEBA DE UI REAL (clics): color y degradado en TRAZOS, en Smart, Modern y Pro.
# Pedido del usuario: "trazos no puede añadir el color ni degradados".
# Causas: el selector de color forzaba «relleno» (pestaña Sólido y editor de
# degradado) y ColorCore convertía cualquier degradado de trazo en su primer
# color. En una línea abierta el relleno no se ve: el trazo no cambiaba.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/stroke_paint_e2e.gd
# Capturas en user://stroke_paint/.
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://stroke_paint"

var fails := 0
var made: Array = []

func _init() -> void:
	_run.call_deferred()
	# Vigilante: si algo se cuelga, cerrar Godot igualmente. Con `timeout`
	# solo moría el lanzador de flatpak y Godot seguía vivo escribiendo el
	# registro (llenó /tmp y dejó una ventana negra en la Huion).
	create_timer(180.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func push_mouse(at: Vector2, pressed: Variant = null) -> void:
	var ev: InputEvent
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		ev = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.position = at
		mb.global_position = at
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev = mb
	root.push_input(ev)
	await process_frame

func click(c: Control, what: String) -> void:
	if c == null or not c.is_visible_in_tree():
		check("se puede pulsar " + what, false, "no visible")
		return
	var at := c.get_global_rect().get_center()
	await push_mouse(at)
	var hit := root.gui_get_hovered_control()
	check("se puede pulsar " + what, hit == c or (hit != null and c.is_ancestor_of(hit)), str(hit))
	await push_mouse(at, true)
	await push_mouse(at, false)
	await frames(6)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func artboard() -> Node:
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var m = canvas.get_node_or_null("manager_script") if canvas else null
	return m.get_active_artboard() if m and m.has_method("get_active_artboard") else null

## Línea abierta como las de la herramienta Bézier/Pluma ("Trazo").
func new_line(y: float) -> Node2D:
	var ab := artboard()
	var vp: Node2D = load("res://script_gdscript/shapes/VectorPath.gd").new()
	vp.name = "Trazo prueba"
	var c := Curve2D.new()
	c.add_point(Vector2(120, y), Vector2.ZERO, Vector2(120, -90))
	c.add_point(Vector2(560, y), Vector2(-120, 90), Vector2.ZERO)
	vp.curve = c
	vp.closed = false
	vp.fill_color = Color(0, 0, 0, 0)
	vp.stroke_color = Color(0.1, 0.1, 0.1)
	vp.stroke_width = 14.0
	ab.add_child(vp)
	vp.owner = ab
	made.append(vp)
	await select(vp)
	return vp

func select(n: Node) -> void:
	root.get_node("SelectionManager").set_selection([n])
	await frames(6)

## El selector de color (GestorColor) visible ahora mismo.
func visible_picker() -> Control:
	for n in root.find_children("*", "", true, false):
		if is_cls(n, "GestorColor") and (n as Control).is_visible_in_tree():
			return n
	return null

func flow(mode: String, line: Node2D) -> void:
	var cc = root.get_node("ColorCore")
	check("%s: con una línea abierta el color va al trazo" % mode, cc.active_target == "stroke", cc.active_target)
	var pk := visible_picker()
	check("%s: selector de color visible" % mode, pk != null)
	if pk == null:
		return
	await click(pk.tab_linear, "%s: degradado lineal" % mode)
	check("%s: la línea tiene degradado en el trazo" % mode, line.has_gradient_stroke())
	check("%s: el relleno invisible no cambia" % mode, line.fill_color.a == 0.0, str(line.fill_color))
	await shot("%s_1_lineal" % mode)
	await click(pk.tab_radial, "%s: degradado radial" % mode)
	check("%s: radial en el trazo" % mode, line.has_gradient_stroke() and line.stroke_gradient_type == 1)
	await click(pk.tab_solid, "%s: sólido" % mode)
	check("%s: sólido quita el degradado del trazo" % mode, not line.has_gradient_stroke())
	pk.establecer_color(Color(0.9, 0.1, 0.2), true)
	await frames(4)
	check("%s: el color elegido llega al trazo" % mode, line.stroke_color.is_equal_approx(Color(0.9, 0.1, 0.2)), str(line.stroke_color))
	await shot("%s_2_rojo" % mode)

func _run() -> void:
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var main := current_scene.find_child("main", true, false) as Control
	var gui = root.get_node("GlobalUI")

	# ── SMART: panel de color flotante ───────────────────────────────────────
	gui.set_ui_mode("smart")
	await frames(30)
	var line := await new_line(300)
	var pcw := main.find_child("pickr_color_windows", true, false) as Control
	if pcw:
		pcw.visible = true
		await frames(6)
	await flow("smart", line)
	if pcw:
		pcw.visible = false

	# ── MODERN: muestra TRAZO del inspector → popover con el selector ────────
	gui.set_ui_mode("modern")
	await frames(30)
	line = await new_line(450)
	var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
	if di.size() > 0:
		await click(di[0].picker_stroke, "modern: muestra de trazo")
		await flow("modern", line)
		if is_instance_valid(di[0]._color_popover):
			di[0]._color_popover.visible = false

	# ── PRO: página Color del lateral ────────────────────────────────────────
	gui.set_ui_mode("professional")
	await frames(30)
	line = await new_line(600)
	await flow("pro", line)

	# Figura cerrada: elegir Trazo a mano y ponerle degradado; el relleno queda.
	var ab := artboard()
	var rect: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
	rect.name = "Rect prueba"
	ab.add_child(rect)
	rect.owner = ab
	rect.size = Vector2(220, 140)
	rect.stroke_width = 12.0
	rect.fill_color = Color(0.9, 0.9, 0.9)
	rect.position = Vector2(400, 820)
	made.append(rect)
	await select(rect)
	var cc = root.get_node("ColorCore")
	check("pro: figura cerrada vuelve a «relleno»", cc.active_target == "fill", cc.active_target)
	var ps := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "ProStudio"))
	if ps.size() > 0:
		await click(ps[0]._swatch_stroke, "pro: muestra de trazo")
		check("pro: objetivo trazo", cc.active_target == "stroke", cc.active_target)
		check("pro: la etiqueta dice «Trazo»", ps[0]._lbl_color_target.text == tr("Trazo"), ps[0]._lbl_color_target.text)
		var pk := visible_picker()
		if pk:
			await click(pk.tab_linear, "pro: lineal en el trazo del rectángulo")
			check("pro: el rectángulo tiene degradado en el trazo", rect.has_gradient_stroke())
			check("pro: el relleno del rectángulo sigue igual", rect.fill_color.is_equal_approx(Color(0.9, 0.9, 0.9)) and not rect.has_gradient_fill())
			await shot("pro_3_rectangulo")
			# Deshacer devuelve el trazo plano.
			var hm = root.get_node("HistoryManager")
			hm.undo()
			await frames(4)
			check("pro: deshacer quita el degradado del trazo", not rect.has_gradient_stroke())
			hm.redo()
			await frames(4)
			check("pro: rehacer lo vuelve a poner", rect.has_gradient_stroke())

	# Guardar/abrir y SVG conservan el degradado del trazo.
	var ser = load("res://scripts/canvas/canvas_serializer.gd")
	if ser and ser.has_method("_add_style"):
		var d := {}
		ser._add_style(d, rect)
		check("archivo: guarda el degradado del trazo", d.has("stroke_grad"))
		var r2: Node2D = load("res://script_gdscript/shapes/VectorRectangle.gd").new()
		ser._read_style(r2, d)
		check("archivo: lo recupera al abrir", r2.has_gradient_stroke())
		r2.free()
	var vx = load("res://script_gdscript/system/vector_export.gd")
	var svg: String = vx.to_svg(vx.collect(ab, false, [rect]))
	check("SVG: el trazo usa un degradado", svg.contains('stroke="url(#g'), svg.substr(0, 300))

	for n in made:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
