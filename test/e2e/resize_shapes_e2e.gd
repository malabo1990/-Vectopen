# =============================================================================
# PRUEBA DE UI REAL: redimensionar arrastrando el asa de la caja de selección.
# Pedido del usuario: "hay fallos sobre estrellas y otros no puede drag para
# cambiar tamaño". Crea cada figura, la selecciona con un clic y arrastra la
# esquina inferior derecha; el tamaño tiene que crecer.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/resize_shapes_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
const OUT := "user://resize_shapes"
var fails := 0
var made: Array = []

func _init() -> void:
	_run.call_deferred()
	create_timer(200.0).timeout.connect(func() -> void:
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
	if ev is InputEventMouse:
		Input.warp_mouse((ev as InputEventMouse).position)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func btn(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e)
	await process_frame

func mv(at: Vector2, prev: Vector2, down: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - prev
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(e)
	await process_frame

func drag(a: Vector2, b: Vector2) -> void:
	await mv(a, a, false)
	await btn(a, true)
	var prev := a
	for i in 12:
		var p := a.lerp(b, (i + 1) / 12.0)
		await mv(p, prev, true)
		prev = p
	await btn(b, false)
	await frames(4)

## Centro VISIBLE de la figura (su origen puede ser una esquina o un vértice).
func center_on_screen(n: Node2D) -> Vector2:
	if n.has_method("get_evaluated_geometry"):
		var geo: Array = n.get_evaluated_geometry()
		if not geo.is_empty() and (geo[0] as PackedVector2Array).size() > 0:
			var bb := Rect2((geo[0] as PackedVector2Array)[0], Vector2.ZERO)
			for p in geo[0]:
				bb = bb.expand(p)
			return screen_of(n, bb.get_center())
	return screen_of(n, Vector2.ZERO)

func screen_of(ci: CanvasItem, local: Vector2) -> Vector2:
	return ci.get_global_transform_with_canvas() * local

## Caja de selección visible y su asa inferior derecha (en pantalla).
func handle_br(canvas: Node) -> Vector2:
	for n in canvas.get_children():
		if n is Control and (n as Control).visible and n.get_script() and String(n.get_script().resource_path).ends_with("bounding_box.gd"):
			var h := (n as Control).find_child("handle_DB", true, false) as Control
			if h and h.is_visible_in_tree():
				return screen_of(h, h.size / 2.0)
	return Vector2(-1, -1)

func size_of(n: Node2D) -> Vector2:
	var ic = root.get_node("InspectorCore")
	root.get_node("SelectionManager").set_selection([n])
	var p: Dictionary = ic.current_props()
	return Vector2(float(p.get("width", {}).get("value", 0.0)), float(p.get("height", {}).get("value", 0.0)))

func _run() -> void:
	Input.use_accumulated_input = false
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
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var modes := ["smart", "modern"]
	if OS.has_environment("VECTOPEN_RESIZE_MODES"):
		modes = Array(OS.get_environment("VECTOPEN_RESIZE_MODES").split(","))
	for mode in modes:
		root.get_node("GlobalUI").set_ui_mode(mode)
		await frames(30)
		var poly = null
		for c in root.find_children("polygon", "Control", true, false):
			if c.get_script() and c.get_script().get_global_name() == "PanelPolygon":
				poly = c
		# 0 polígono, 1 estrella, 2 rectángulo, 3 elipse, 4 gota, 5 formas (corazón)
		for k in [1, 0, 2, 3, 4, 5]:
			poly.kind = k
			poly._build_params()
			var s: Node2D = poly.create_in_center()
			await frames(4)
			made.append(s)
			var kname := String(s.name)
			canvas.switch_tool("move")
			await frames(4)
			# Seleccionar con un clic de verdad en el centro de la figura.
			root.get_node("SelectionManager").set_selection([])
			await frames(2)
			var cen := screen_of(s, Vector2.ZERO)
			await mv(cen, cen, false)
			await btn(cen, true)
			await btn(cen, false)
			await frames(6)
			var before := size_of(s)
			var h := handle_br(canvas)
			check("%s · %s: hay asa para redimensionar" % [mode, kname], h.x >= 0.0, str(h))
			if h.x < 0.0:
				continue
			await drag(h, h + Vector2(70, 50))
			var after := size_of(s)
			check("%s · %s: arrastrar el asa cambia el tamaño" % [mode, kname],
				after.x > before.x + 20.0 and after.y > before.y + 15.0, "%s → %s" % [before, after])
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT.path_join("%s_%d.png" % [mode, k]))
			s.queue_free()
			await frames(4)
	# Figuras DIBUJADAS con su herramienta (arrastrando en el lienzo).
	root.get_node("GlobalUI").set_ui_mode("smart")
	await frames(20)
	var ab_node: Node = null
	var m = canvas.get_node_or_null("manager_script")
	if m and m.has_method("get_active_artboard"):
		ab_node = m.get_active_artboard()
	for tool in ["star", "star4", "star5", "triangle", "pentagon", "waterdrop", "ellipse", "rectangle"]:
		var before_kids: Array = ab_node.get_children() if ab_node else []
		canvas.switch_tool(tool)
		await frames(3)
		await drag(Vector2(850, 400), Vector2(960, 510))
		var s: Node2D = null
		for c in ab_node.get_children():
			if not (c in before_kids) and c is Node2D:
				s = c
		check("dibujar %s crea una figura" % tool, s != null)
		if s == null:
			continue
		canvas.switch_tool("move")
		await frames(4)
		root.get_node("SelectionManager").set_selection([])
		await frames(2)
		var cen := center_on_screen(s)
		await mv(cen, cen, false)
		await btn(cen, true)
		await btn(cen, false)
		await frames(6)
		var sel: Array = root.get_node("SelectionManager").get_selected()
		check("%s (%s): se selecciona con un clic" % [tool, s.get_class()], sel.size() == 1 and sel[0] == s, str(sel))
		var before := size_of(s)
		var h := handle_br(canvas)
		if h.x < 0.0:
			check("%s: hay asa" % tool, false)
			s.queue_free()
			continue
		await drag(h, h + Vector2(70, 50))
		var after := size_of(s)
		check("dibujada con %s (%s): arrastrar el asa cambia el tamaño" % [tool, s.get_script().get_global_name() if s.get_script() else s.get_class()],
			after.x > before.x + 20.0 and after.y > before.y + 15.0, "%s → %s" % [before, after])
		s.queue_free()
		await frames(4)

	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
