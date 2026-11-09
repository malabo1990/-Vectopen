# =============================================================================
# ZOOM EXTREMO (≈ 190 000 %) con una figura seleccionada (caso del usuario):
#  · Mayús + arrastrar sobre la figura cambia el grosor del trazo;
#  · los paneles muestran el valor al momento y con decimales;
#  · tiradores y punto de redondeo nítidos y de su tamaño en pantalla.
#   test/run_e2e.sh extreme_zoom_ui_e2e
# =============================================================================
extends SceneTree

const OUT := "user://extreme_zoom_ui"
const Z := 1885.0
var fails := 0
var canvas

func _init() -> void:
	_run.call_deferred()
	create_timer(300.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if extra == "" else "  [" + extra + "]"))
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func scr(gp: Vector2) -> Vector2:
	return canvas.get_viewport().get_canvas_transform() * gp

func shift_key(down: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_SHIFT
	k.physical_keycode = KEY_SHIFT
	k.pressed = down
	k.shift_pressed = down
	_send(k)
	await process_frame

## Arrastre con Mayús (pantalla).
func shift_drag(a: Vector2, b: Vector2) -> void:
	await shift_key(true)
	var mm := InputEventMouseMotion.new()
	mm.position = a
	mm.global_position = a
	mm.shift_pressed = true
	_send(mm)
	await process_frame
	var mb := InputEventMouseButton.new()
	mb.position = a
	mb.global_position = a
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.shift_pressed = true
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mb)
	await process_frame
	for i in range(1, 11):
		var m2 := InputEventMouseMotion.new()
		m2.position = a.lerp(b, i / 10.0)
		m2.global_position = m2.position
		m2.shift_pressed = true
		m2.button_mask = MOUSE_BUTTON_MASK_LEFT
		_send(m2)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = b
	up.global_position = b
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.shift_pressed = true
	_send(up)
	await process_frame
	await shift_key(false)
	await frames(3)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	root.get_node("GlobalUI").set_ui_mode("modern")
	await frames(30)
	canvas = get_first_node_in_group("_vectopen_canvas")
	var api = root.get_node("PluginManager").api
	var sm = root.get_node("SelectionManager")
	var ic = root.get_node("InspectorCore")
	var cam: Camera2D = canvas.camera
	var ab: Node2D = canvas.get_node("manager_script").get_active_artboard()
	var ac: Vector2 = ab.artboard_size / 2.0
	var cur = canvas.get_current_tool()
	if cur == null or not cur.has_method("get_class_name") or cur.get_class_name() != "MoveTool":
		canvas.change_tool(canvas._new_tool(load("res://script_gdscript/tools/MoveTool.gd")))
	await frames(4)
	# Rectángulo diminuto con esquinas redondeadas y borde muy fino
	var rc = api.add_rect(ac, Vector2(2.0, 1.4), 0.12, "Rect")
	rc.stroke_width = 0.02
	rc.stroke_color = Color.BLACK
	rc.fill_color = Color(0.88, 0.88, 0.88)
	await frames(4)
	sm.select(rc)
	await frames(6)
	cam.zoom = Vector2(Z, Z)
	cam.position = ab.to_global(ac - Vector2(0.92, 0.6))   # esquina superior izquierda
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("1_esquina.png"))
	# 1. Mayús + arrastrar sobre la figura (hacia la derecha = más grueso)
	var w0: float = rc.stroke_width
	var inside: Vector2 = scr(ab.to_global(ac - Vector2(0.85, 0.52)))
	await shift_drag(inside, inside + Vector2(60, 0))
	var w1: float = rc.stroke_width
	check("Mayús + arrastrar engruesa el trazo con zoom extremo", w1 > w0 * 1.5, "%.4f → %.4f" % [w0, w1])
	check("la figura sigue seleccionada", sm.get_selected().has(rc), str(sm.get_selected()))
	await shift_drag(inside, inside + Vector2(-80, 0))
	var w2: float = rc.stroke_width
	check("Mayús + arrastrar a la izquierda adelgaza", w2 < w1, "%.4f → %.4f" % [w1, w2])
	# 2. Paneles con el valor al momento y con decimales
	var shown := []
	for nf in root.find_children("*", "", true, false):
		if nf is Control and (nf as Control).is_visible_in_tree() and "adaptive_step" in nf and nf.adaptive_step and "value" in nf:
			shown.append(float(nf.value))
	var synced := false
	for v in shown:
		if absf(v - w2) < 0.0006:
			synced = true
	check("un campo de grosor visible muestra el valor actual", synced, "grosor %.4f · campos %s" % [w2, shown])
	var radius_txt := ""
	for le in root.find_children("*", "LineEdit", true, false):
		var p: Node = le.get_parent()
		while p and not (p is Control and String(p.name).to_lower().contains("radius")):
			p = p.get_parent() if p.get_parent() is Control else null
		if p:
			radius_txt = (le as LineEdit).text
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join("2_tras_grosor.png"))
	var tl_txt := ""
	for n in root.find_children("*", "", true, false):
		if n.get_script() and String(n.get_script().resource_path).ends_with("transform_panel.gd") and (n as Control).is_visible_in_tree():
			var d = n._corners.get("corner_tl")
			if d and is_instance_valid(d._le):
				tl_txt = d._le.text
	check("la esquina TL muestra su radio con decimales (0.12)", tl_txt.begins_with("0.12"), tl_txt)
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
