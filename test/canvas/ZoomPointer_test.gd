extends GdUnitTestSuite

func test_zoom_mantiene_punto_bajo_cursor() -> void:
	var canvas: Node2D = Node2D.new()
	canvas.set_script(load("res://scripts/canvas/canvas.gd"))
	var cam := Camera2D.new()
	cam.position = Vector2(300, 200)
	cam.zoom = Vector2.ONE
	canvas.set("camera", cam)
	canvas.set("zoom_min", 0.05)
	canvas.set("zoom_max", 20.0)
	add_child(cam)
	add_child(canvas)
	await get_tree().process_frame

	var viewport_size: Vector2 = canvas.get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var cursor_screen := Vector2(600, 420)
	var world_before: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x

	canvas.zoom_at_point(1.5, world_before)

	var world_after: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x
	assert_that(world_after.distance_to(world_before)).is_less(0.01)

	canvas.zoom_at_point(0.7, world_before)
	var world_after2: Vector2 = cam.position + (cursor_screen - center) / cam.zoom.x
	assert_that(world_after2.distance_to(world_before)).is_less(0.01)


## BUG real (lápiz, botón 2 = botón central): pulsar Super en GNOME abre las
## actividades y Vectopen nunca recibe el "soltar" → el lienzo creía Super
## pulsado y arrastrar con el botón central hacía ZOOM en vez de desplazar.
func _canvas_cam() -> Node2D:
	var canvas: Node2D = Node2D.new()
	canvas.set_script(load("res://scripts/canvas/canvas.gd"))
	var cam := Camera2D.new()
	cam.position = Vector2(300, 200)
	cam.zoom = Vector2.ONE
	canvas.set("camera", cam)
	add_child(cam)
	add_child(canvas)
	auto_free(canvas)
	auto_free(cam)
	return canvas

func _middle(pressed: bool) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_MIDDLE
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_MIDDLE if pressed else 0
	return b

func test_super_pegado_no_convierte_el_boton_central_en_zoom() -> void:
	var canvas := _canvas_cam()
	await get_tree().process_frame
	canvas.set("is_cmd_pressed", true)     # Super "pegado"
	var cam: Camera2D = canvas.get("camera")
	Input.parse_input_event(_middle(true))   # botón central pulsado de verdad
	Input.flush_buffered_events()
	canvas._handle_mouse_button(_middle(true))
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(30, 40)
	m.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	m.meta_pressed = false                  # el evento dice: Super NO pulsado
	canvas._handle_mouse_motion(m)
	assert_vector(cam.zoom).is_equal(Vector2.ONE)              # sin zoom
	assert_bool(cam.position != Vector2(300, 200)).is_true()   # desplazó
	canvas._handle_mouse_button(_middle(false))
	Input.parse_input_event(_middle(false))
	Input.flush_buffered_events()

func test_perder_el_foco_suelta_espacio_y_z() -> void:
	var canvas := _canvas_cam()
	await get_tree().process_frame
	canvas.set("is_space_pressed", true)
	canvas.set("is_z_pressed", true)
	canvas.set("is_cmd_pressed", true)
	canvas.set("is_ctrl_pressed", true)
	canvas.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(canvas.get("is_space_pressed")).is_false()
	assert_bool(canvas.get("is_z_pressed")).is_false()
	assert_bool(canvas.get("is_cmd_pressed")).is_false()
	assert_bool(canvas.get("is_ctrl_pressed")).is_false()


# ── Zoom con arrastre estilo Krita: Ctrl + botón central (botón 2 del lápiz) ──
func _mid_motion(rel: Vector2, ctrl: bool) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	m.ctrl_pressed = ctrl
	return m

func test_ctrl_boton_central_arrastrar_hace_zoom_anclado_y_simetrico() -> void:
	var canvas := _canvas_cam()
	await get_tree().process_frame
	var cam: Camera2D = canvas.get("camera")
	canvas._handle_mouse_button(_middle(true))
	var anchor: Vector2 = canvas.get("_zoom_anchor")
	var screen_before: Vector2 = (anchor - cam.position) * cam.zoom.x
	for i in 10:
		canvas._handle_mouse_motion(_mid_motion(Vector2(0, -6), true))   # arriba = acercar
	assert_float(cam.zoom.x).is_greater(1.3)
	var screen_after: Vector2 = (anchor - cam.position) * cam.zoom.x
	assert_float(screen_after.distance_to(screen_before)).is_less(0.01)   # el ancla no se mueve
	for i in 10:
		canvas._handle_mouse_motion(_mid_motion(Vector2(0, 6), true))    # bajar lo mismo
	assert_float(cam.zoom.x).is_equal_approx(1.0, 0.001)                  # vuelve igual
	canvas._handle_mouse_button(_middle(false))

func test_boton_central_sin_ctrl_desplaza_sin_zoom() -> void:
	var canvas := _canvas_cam()
	await get_tree().process_frame
	var cam: Camera2D = canvas.get("camera")
	var before: Vector2 = cam.position
	canvas._handle_mouse_button(_middle(true))
	canvas._handle_mouse_motion(_mid_motion(Vector2(20, -15), false))
	assert_vector(cam.zoom).is_equal(Vector2.ONE)
	assert_vector(cam.position - before).is_equal(Vector2(-20, 15))
	canvas._handle_mouse_button(_middle(false))

## Una herramienta que se queda con todos los eventos (pluma, pincel…) no
## puede quitarle el botón central a la navegación.
class _GreedyTool extends Node:
	var got := 0
	func handle_input(_e: InputEvent) -> bool:
		got += 1
		return true

func test_la_navegacion_tiene_prioridad_sobre_la_herramienta() -> void:
	var canvas := _canvas_cam()
	await get_tree().process_frame
	var tool := _GreedyTool.new()
	auto_free(tool)
	canvas.set("current_tool", tool)
	var cam: Camera2D = canvas.get("camera")
	canvas._unhandled_input(_middle(true))
	canvas._unhandled_input(_mid_motion(Vector2(0, -30), true))
	assert_int(tool.got).is_equal(0)
	assert_float(cam.zoom.x).is_greater(1.0)
	canvas._unhandled_input(_middle(false))
