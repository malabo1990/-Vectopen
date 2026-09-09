extends GdUnitTestSuite

## Valida la ESCENA REAL (canvas.tscn) — no nodos sueltos con set_script.
## Reproduce los bugs reportados en la sesión: título invisible, artboard
## deformado a zoom extremo, y drag & drop del artboard roto.

const CANVAS_SCENE := "res://scenes/canvas/canvas.tscn"

func _instanciar_canvas() -> Node2D:
	var scene: Node2D = load(CANVAS_SCENE).instantiate()
	add_child(scene)
	auto_free(scene)
	return scene

func test_escena_real_titulo_artboard_funcional() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard: Node2D = scene.get_node_or_null("ArtboardsContainer/Artboard")
	assert_object(artboard).is_not_null()
	var label := artboard.get_node_or_null("ArtboardTitle") as Control
	assert_object(label).is_not_null()
	assert_that(label.text).is_equal("Artboard")
	assert_that(label.scale).is_equal(Vector2.ONE)
	assert_that(label.position).is_equal(Vector2(0, -20))
	assert_that(label.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_that(label.gui_input.is_connected(Callable(artboard, "_on_title_gui_input"))).is_true()

func test_escena_real_zoom_maximo_no_deforma_artboard() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame

	var canvas: Node2D = scene
	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	var artboard: Node2D = scene.get_node_or_null("ArtboardsContainer/Artboard")
	var label := artboard.get_node_or_null("ArtboardTitle") as Control

	var size_antes: Vector2 = artboard.artboard_size
	var scale_artboard_antes := artboard.scale
	var label_world_antes: Vector2 = label.size * label.scale  # rect en MUNDO
	var label_pos_antes := label.position

	var p := Vector2(400, 300)
	for i in 30:
		canvas.zoom_at_point(2.0, p)
		await get_tree().process_frame

	assert_that(cam.zoom.x).is_greater(1000.0)
	assert_that(artboard.scale).is_equal(Vector2.ONE)
	assert_that(artboard.artboard_size).is_equal(size_antes)
	# El título es WorldTextLabel: su scale local cambia (compensación de
	# re-rasterizado) pero su RECT EN MUNDO debe mantenerse constante.
	var label_world_final: Vector2 = label.size * label.scale
	assert_that(label_world_final.distance_to(label_world_antes)).is_less(24.0)
	assert_that(label.position).is_equal(label_pos_antes)

func test_escena_real_drag_artboard_funciona() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	artboard.is_selected = true
	var pos_inicial := artboard.global_position

	# La inyección de ratón (parse_input_event/warp_mouse) NO es fiable en
	# headless: get_global_mouse_position() devuelve la posición real del
	# cursor del SO, no la inyectada (igual que en test_escena_real_resize_*).
	# Ejercitamos la máquina de estados real del arrastre con coords
	# deterministas: press → _handle_motion → release.
	var mouse_press := artboard.to_global(Vector2(300, 300))
	var mouse_drag := mouse_press + Vector2(150, 120)

	# 1) press sobre el cuerpo del artboard estando seleccionado
	assert_that(artboard._is_selection_tool()).is_true()
	assert_that(Rect2(Vector2.ZERO, artboard.artboard_size).has_point(artboard.to_local(mouse_press))).is_true()
	artboard._mode = "drag"
	artboard._drag_start_mouse = mouse_press
	artboard._drag_start_pos = artboard.global_position

	# 2) motion: el artboard sigue al ratón
	artboard._handle_motion(mouse_drag)
	await get_tree().process_frame
	assert_that(artboard.global_position).is_equal(pos_inicial + Vector2(150, 120))

	# 3) release: termina el arrastre y limpia el modo
	artboard._unhandled_input(_btn(1, false, mouse_drag))
	assert_str(artboard._mode).is_equal("")

	assert_that(artboard.global_position).is_equal(pos_inicial + Vector2(150, 120))
	assert_that(artboard.artboard_size).is_equal(Vector2(794, 1123))

static func _btn(button: int, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e

func test_escena_real_resize_mantiene_ratio() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	artboard.is_selected = true

	# El resize usa valores absolutos de get_global_mouse_position(), que en
	# headless no coincide con el transform del canvas (cámara centrada).
	# Validamos la lógica del borde con coordenadas locales consistentes.
	var local_esquina := Vector2(794, 1123)
	assert_that(artboard.is_on_handle(local_esquina)).is_true()
	assert_that(artboard.get_resize_edge(local_esquina)).is_equal(Vector2(1, 1))

	# Aplicamos el resize vía la misma ruta que _handle_motion("resize")
	var motion_pos := Vector2(900, 1250)
	artboard._apply_resize(Vector2(1, 1), artboard.to_global(motion_pos))

	assert_that(artboard.artboard_size.x).is_greater(794.0)
	assert_that(artboard.artboard_size.y).is_greater(1123.0)
	assert_that(artboard.scale).is_equal(Vector2.ONE)

func test_escena_real_doble_click_titulo_selecciona() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	var label := artboard.get_node_or_null("ArtboardTitle") as Control

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = label.global_position + Vector2(20, 8)

	# Sin ArtboardManager en el árbol de test, cae al fallback: is_selected = true
	label.gui_input.emit(click)
	assert_that(artboard.is_selected).is_true()

func test_escena_real_key_g_activa_degradado_y_anotador() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	assert_object(artboard).is_not_null()

	var shape := VectorRectangle.new()
	shape.size = Vector2(200, 150)
	shape.position = Vector2(100, 100)
	artboard.add_child(shape)

	var move_tool = scene._new_tool(scene.MoveTool_Script)
	scene.change_tool(move_tool)
	await get_tree().process_frame

	move_tool._select(shape)
	await get_tree().process_frame

	var bbox = move_tool._bounding_box
	assert_object(bbox).is_not_null()

	# Pulsar tecla G en el canvas real
	var ev_g := InputEventKey.new()
	ev_g.keycode = KEY_G
	ev_g.pressed = true
	scene._unhandled_input(ev_g)
	await get_tree().process_frame

	assert_that(move_tool.is_gradient_mode).is_true()
	assert_that(shape.has_gradient_fill()).is_true()
	assert_that(bbox.has_gradient_annotator()).is_true()

func test_escena_real_camara_zoom_pan_drag_p1_p0_fijo() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	cam.position = Vector2(300, 200)
	cam.zoom = Vector2(1.8, 1.8)
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	var shape := VectorRectangle.new()
	shape.size = Vector2(200, 200)
	shape.position = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.set_gradient_points(Vector2(0.2, 0.5), Vector2(0.8, 0.5))
	artboard.add_child(shape)

	var move_tool = scene._new_tool(scene.MoveTool_Script)
	scene.change_tool(move_tool)
	await get_tree().process_frame
	move_tool._select(shape)
	await get_tree().process_frame
	move_tool._handle_key_shortcuts(KEY_G)
	await get_tree().process_frame

	var bbox = move_tool._bounding_box
	assert_object(bbox).is_not_null()

	var p0_init := shape.fill_gradient_p0
	var data: Dictionary = bbox._get_gradient_annotator_data()
	var p1_local: Vector2 = data["p1"]
	var p1_screen: Vector2 = bbox.get_screen_transform() * p1_local

	# Presionar sobre el handle p1 con coordenadas de pantalla reales de la cámara
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = p1_screen
	ev_press.position = p1_screen
	bbox._gui_input(ev_press)

	# Arrastrar p1 hacia abajo a la derecha (normalizado a 0.9, 0.9)
	var new_p1_local := Vector2(180, 180)
	var new_p1_screen: Vector2 = bbox.get_screen_transform() * new_p1_local
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = new_p1_screen
	ev_motion.position = new_p1_screen
	bbox._gui_input(ev_motion)

	# Soltar
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.global_position = new_p1_screen
	ev_release.position = new_p1_screen
	bbox._gui_input(ev_release)

	# p0 DEBE permanecer EXACTAMENTE FIJO en (0.2, 0.5)
	assert_vector(shape.fill_gradient_p0).is_equal_approx(p0_init, Vector2(0.001, 0.001))
	# p1 se movió a (0.9, 0.9)
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.9, 0.9), Vector2(0.01, 0.01))

func test_escena_real_camara_zoom_pan_drag_p0_p1_fijo() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	cam.position = Vector2(150, 100)
	cam.zoom = Vector2(2.5, 2.5)
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	var shape := VectorRectangle.new()
	shape.size = Vector2(200, 200)
	shape.position = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.set_gradient_points(Vector2(0.2, 0.2), Vector2(0.8, 0.8))
	artboard.add_child(shape)

	var move_tool = scene._new_tool(scene.MoveTool_Script)
	scene.change_tool(move_tool)
	await get_tree().process_frame
	move_tool._select(shape)
	await get_tree().process_frame
	move_tool._handle_key_shortcuts(KEY_G)
	await get_tree().process_frame

	var bbox = move_tool._bounding_box
	var p1_init := shape.fill_gradient_p1
	var data: Dictionary = bbox._get_gradient_annotator_data()
	var p0_local: Vector2 = data["p0"]
	var p0_screen: Vector2 = bbox.get_screen_transform() * p0_local

	# Presionar sobre el handle p0 con coordenadas de pantalla
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = p0_screen
	ev_press.position = p0_screen
	bbox._gui_input(ev_press)

	# Arrastrar p0 hacia (20, 100) local -> normalizado (0.1, 0.5)
	var new_p0_local := Vector2(20, 100)
	var new_p0_screen: Vector2 = bbox.get_screen_transform() * new_p0_local
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = new_p0_screen
	ev_motion.position = new_p0_screen
	bbox._gui_input(ev_motion)

	# Soltar
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.global_position = new_p0_screen
	ev_release.position = new_p0_screen
	bbox._gui_input(ev_release)

	# p1 DEBE permanecer EXACTAMENTE FIJO en (0.8, 0.8)
	assert_vector(shape.fill_gradient_p1).is_equal_approx(p1_init, Vector2(0.001, 0.001))
	# p0 se movió a (0.1, 0.5)
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.1, 0.5), Vector2(0.01, 0.01))

func test_escena_real_camara_zoom_pan_drag_stop_intermedio() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	cam.position = Vector2(200, 150)
	cam.zoom = Vector2(1.2, 1.2)
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	var shape := VectorRectangle.new()
	shape.size = Vector2(200, 200)
	shape.position = Vector2(50, 50)
	var g := Gradient.new()
	g.add_point(0.4, Color.RED)
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
	artboard.add_child(shape)

	var move_tool = scene._new_tool(scene.MoveTool_Script)
	scene.change_tool(move_tool)
	await get_tree().process_frame
	move_tool._select(shape)
	await get_tree().process_frame
	move_tool._handle_key_shortcuts(KEY_G)
	await get_tree().process_frame

	var bbox = move_tool._bounding_box
	var p0_init := shape.fill_gradient_p0
	var p1_init := shape.fill_gradient_p1

	var data: Dictionary = bbox._get_gradient_annotator_data()
	var stop_s = data.stops[1] # stop del medio en 0.4
	var stop_local: Vector2 = stop_s.position
	var stop_screen: Vector2 = bbox.get_screen_transform() * stop_local

	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = stop_screen
	ev_press.position = stop_screen
	bbox._gui_input(ev_press)

	# Arrastrar stop hacia el 75% de la línea
	var target_local: Vector2 = data.p0.lerp(data.p1, 0.75)
	var target_screen: Vector2 = bbox.get_screen_transform() * target_local
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = target_screen
	ev_motion.position = target_screen
	bbox._gui_input(ev_motion)

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.global_position = target_screen
	ev_release.position = target_screen
	bbox._gui_input(ev_release)

	# p0 y p1 100% FIJOS
	assert_vector(shape.fill_gradient_p0).is_equal_approx(p0_init, Vector2(0.001, 0.001))
	assert_vector(shape.fill_gradient_p1).is_equal_approx(p1_init, Vector2(0.001, 0.001))
	# offset del stop desplazado a ~0.75
	var fg: Gradient = shape.fill_gradient
	var found_offset := false
	for i in range(fg.get_point_count()):
		if absf(fg.get_offset(i) - 0.75) < 0.03:
			found_offset = true
			break
	assert_that(found_offset).is_true()

func test_escena_real_seleccion_arrastra_figura_con_degradado_sin_editar_degradado() -> void:
	var scene := _instanciar_canvas()
	await get_tree().process_frame
	await get_tree().process_frame

	var artboard := scene.get_node_or_null("ArtboardsContainer/Artboard") as Node2D
	var shape := VectorRectangle.new()
	shape.size = Vector2(100, 100)
	shape.position = Vector2(80, 80)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.set_gradient_points(Vector2(0.2, 0.5), Vector2(0.8, 0.5))
	artboard.add_child(shape)

	# Usar herramienta de selección (MoveTool)
	var move_tool = scene._new_tool(scene.MoveTool_Script)
	scene.change_tool(move_tool)
	await get_tree().process_frame
	assert_object(move_tool).is_not_null()
	assert_that(move_tool.is_gradient_mode).is_false()

	# Seleccionar la figura
	move_tool._select(shape)
	await get_tree().process_frame

	# En modo selección, el anotador de degradado DEBE estar bloqueado
	assert_that(move_tool.is_gradient_mode).is_false()
	var bbox = move_tool._bounding_box
	assert_object(bbox).is_not_null()
	assert_that(bbox.has_gradient_annotator()).is_false()

	var p0_init := shape.fill_gradient_p0
	var p1_init := shape.fill_gradient_p1
	# Clic y arrastre sobre el relleno de la figura en modo selección
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = Vector2(100, 100)
	bbox._on_drag_panel_gui_input(ev_press)

	assert_that(bbox._is_dragging_canvas_area).is_true()
	assert_that(move_tool.is_dragging_shape).is_true()
	assert_that(bbox._annotator_drag_mode).is_equal("")

	# Arrastrar 40px a la derecha y 30px abajo
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev_motion.global_position = Vector2(140, 130)
	bbox._on_drag_panel_gui_input(ev_motion)

	# Soltar
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.global_position = Vector2(140, 130)
	bbox._on_drag_panel_gui_input(ev_up)
	await get_tree().process_frame

	assert_that(bbox._is_dragging_canvas_area).is_false()
	assert_that(move_tool.is_dragging_shape).is_false()
	# El degradado permaneció 100% INTACTO
	assert_vector(shape.fill_gradient_p0).is_equal_approx(p0_init, Vector2(0.001, 0.001))
	assert_vector(shape.fill_gradient_p1).is_equal_approx(p1_init, Vector2(0.001, 0.001))


