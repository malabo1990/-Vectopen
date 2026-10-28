# =============================================================================
# PRUEBA DE UI REAL: botón central + arrastrar desplaza el inspector (Modern)
# y el lateral de Pro, como en Capas; sobre el lienzo sigue moviendo el lienzo.
# Pedido del usuario: "falta drag con el botón medio para panel inspector como
# lo hace en capas" — "en moderno y pro".
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/middle_scroll_e2e.gd
# =============================================================================
extends SceneTree

const UI_CFG := "user://vectopen_ui.cfg"
var fails := 0
var checks := 0
## Si el script se corta a medias (error), no puede dar OK.
const EXPECTED_CHECKS := 11

func _init() -> void:
	_run.call_deferred()
	create_timer(150.0).timeout.connect(func() -> void:
		print("RESULT: TIMEOUT")
		quit(2))

func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
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

func mid(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	e.pressed = down
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_MIDDLE if down else 0
	_send(e)
	await process_frame

func mv(at: Vector2, prev: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - prev
	e.button_mask = mask
	_send(e)
	await process_frame

func mid_drag(a: Vector2, b: Vector2) -> void:
	await mv(a, a, 0)
	await mid(a, true)
	var prev := a
	for i in 10:
		var p := a.lerp(b, (i + 1) / 10.0)
		await mv(p, prev, MOUSE_BUTTON_MASK_MIDDLE)
		prev = p
	await mid(b, false)
	await frames(3)

func is_cls(n: Object, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls

func cam_pos(canvas) -> Vector2:
	return canvas.camera.position if "camera" in canvas and is_instance_valid(canvas.camera) else Vector2.ZERO

func check_panel(mode: String, scroll: ScrollContainer, canvas) -> void:
	check("%s: el panel tiene zona desplazable" % mode, scroll != null and scroll.is_visible_in_tree())
	if scroll == null:
		return
	# Relleno alto: garantiza contenido de sobra en cualquier pantalla.
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(10, 1400)
	filler.mouse_filter = Control.MOUSE_FILTER_PASS
	var content: Control = null
	for ch in scroll.get_children():
		if ch is Control:
			content = ch
			break
	content.add_child(filler)
	var bar := scroll.get_v_scroll_bar()
	await frames(6)
	check("%s: hay contenido para desplazar" % mode, bar.max_value - bar.page > 50.0, "max %s page %s" % [bar.max_value, bar.page])
	bar.value = 0
	await frames(2)
	var cam0 := cam_pos(canvas)
	var c := scroll.get_global_rect().get_center()
	await mid_drag(c, c + Vector2(0, -160))
	check("%s: botón central + arrastrar hacia arriba desplaza el panel" % mode, bar.value > 100.0, str(bar.value))
	check("%s: el lienzo NO se mueve" % mode, cam_pos(canvas).is_equal_approx(cam0), "%s → %s" % [cam0, cam_pos(canvas)])
	var v := bar.value
	await mid_drag(c, c + Vector2(0, 90))
	check("%s: arrastrar hacia abajo vuelve atrás" % mode, bar.value < v - 60.0, "%s → %s" % [v, bar.value])
	filler.queue_free()

func _run() -> void:
	Input.use_accumulated_input = false
	var ui_backup := FileAccess.get_file_as_string(UI_CFG) if FileAccess.file_exists(UI_CFG) else ""
	DisplayServer.window_set_current_screen(int(OS.get_environment("VECTOPEN_TEST_SCREEN")) if OS.has_environment("VECTOPEN_TEST_SCREEN") else mini(1, DisplayServer.get_screen_count() - 1))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for _w in 600:
		if Engine.has_meta(&"vectopen_startup_done"):
			break
		await process_frame
	await frames(30)
	var canvas = get_first_node_in_group("_vectopen_canvas")
	var gui = root.get_node("GlobalUI")

	# Contenido largo: un círculo seleccionado + panel de polígonos abierto.
	var poly = null
	for c in root.find_children("polygon", "Control", true, false):
		if is_cls(c, "PanelPolygon"):
			poly = c
	poly.kind = 3
	poly._build_params()
	var shape: Node2D = poly.create_in_center()
	await frames(4)

	gui.set_ui_mode("modern")
	await frames(30)
	root.get_node("SelectionManager").set_selection([shape])
	root.get_node("GlobalEvents").emit_safe("request_tool_panel", "polygon")
	await frames(8)
	var di := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "DockedInspector"))
	await check_panel("modern", di[0].scroll_container if di.size() > 0 else null, canvas)

	gui.set_ui_mode("professional")
	await frames(30)
	root.get_node("SelectionManager").set_selection([shape])
	root.get_node("GlobalEvents").emit_safe("request_tool_panel", "polygon")
	await frames(8)
	var ps := root.find_children("*", "", true, false).filter(func(n): return is_cls(n, "ProStudio"))
	await check_panel("pro", ps[0]._scroll if ps.size() > 0 else null, canvas)

	# Sobre el lienzo, el botón central sigue moviendo el lienzo.
	var vp := root.get_visible_rect().size
	var cam0 := cam_pos(canvas)
	var mid_canvas := Vector2(vp.x * 0.45, vp.y * 0.5)
	await mid_drag(mid_canvas, mid_canvas + Vector2(120, 80))
	check("lienzo: botón central sigue moviendo el lienzo", not cam_pos(canvas).is_equal_approx(cam0), "%s → %s" % [cam0, cam_pos(canvas)])

	if is_instance_valid(shape):
		shape.queue_free()
	for n in ["polygon", "text", "Selector", "bezier", "brush"]:
		root.get_node("GlobalEvents").emit_safe("request_tool_panel", "")
	if ui_backup != "":
		var f := FileAccess.open(UI_CFG, FileAccess.WRITE)
		f.store_string(ui_backup)
		f.close()
	if checks < EXPECTED_CHECKS:
		check("el test hizo todas sus comprobaciones", false, "%d de %d" % [checks, EXPECTED_CHECKS])
	print("RESULT: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
