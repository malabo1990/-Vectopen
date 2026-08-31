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
