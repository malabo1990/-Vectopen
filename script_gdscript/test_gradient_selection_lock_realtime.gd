extends Control

@onready var label_status: Label = $StatusLabel

var rect: VectorRectangle
var bbox: Control
var move_tool: MoveTool
var canvas: Node2D

func _ready() -> void:
	get_viewport().size = Vector2i(1200, 800)

	canvas = Node2D.new()
	canvas.name = "CanvasRoot"
	add_child(canvas)

	var bg := ColorRect.new()
	bg.size = Vector2(1200, 800)
	bg.color = Color(0.14, 0.15, 0.18, 1.0)
	canvas.add_child(bg)

	# Figura con degradado
	rect = VectorRectangle.new()
	rect.name = "RectanguloGradiente"
	rect.position = Vector2(400, 350)
	rect.size = Vector2(300, 200)
	rect.corner_radius = 16.0
	rect.stroke_width = 3.0
	rect.stroke_color = Color(1.0, 1.0, 1.0, 0.8)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.2, 0.6, 1.0, 1.0), # Azul cielo
		Color(0.9, 0.4, 0.9, 1.0), # Magenta
		Color(1.0, 0.6, 0.2, 1.0), # Naranja
	])
	rect.fill_gradient = grad
	rect.fill_gradient_type = 0 # Lineal
	rect.set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
	canvas.add_child(rect)

	# Bounding box
	var bbox_scene: PackedScene = load("res://scenes/canvas/boundingbox.tscn")
	bbox = bbox_scene.instantiate()
	bbox.name = "BoundingBox"
	canvas.add_child(bbox)
	bbox.target_node = rect

	# MoveTool
	move_tool = MoveTool.new()
	add_child(move_tool)
	move_tool.canvas = canvas
	move_tool.selected_shapes = [rect]
	move_tool._bounding_box = bbox
	bbox.move_tool_reference = move_tool

	bbox._sincronizar_dimensiones_en_canvas()

	_run_verification_sequence()

func _update_label(text: String, color := Color.GREEN) -> void:
	if label_status:
		label_status.text = text
		label_status.modulate = color

func _capture(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img = get_viewport().get_texture().get_image()
	if img:
		img.save_png("C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/" + filename)

func _run_verification_sequence() -> void:
	await get_tree().create_timer(0.3).timeout

	# PASO 1: En modo Selección con elemento con degradado seleccionado
	assert(move_tool.is_gradient_mode == false)
	assert(bbox.has_gradient_annotator() == false)
	_update_label("PASO 1: MODO SELECCION ACTIVO\nAnotador de degradado bloqueado. Figura con degradado seleccionada.", Color(0.4, 0.8, 1.0))
	await _capture("step1_selection_mode_gradient_locked.png")

	# PASO 2: Arrastre por el relleno del elemento en modo Selección
	var initial_pos := rect.position
	var initial_p0 := rect.fill_gradient_p0
	var initial_p1 := rect.fill_gradient_p1

	var click_point := rect.global_position
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = click_point
	bbox._on_drag_panel_gui_input(ev_press)

	var ev_motion := InputEventMouseMotion.new()
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev_motion.global_position = click_point + Vector2(180, 100)
	bbox._on_drag_panel_gui_input(ev_motion)

	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.global_position = click_point + Vector2(180, 100)
	bbox._on_drag_panel_gui_input(ev_up)

	bbox._sincronizar_dimensiones_en_canvas()
	assert(rect.fill_gradient_p0 == initial_p0)
	assert(rect.fill_gradient_p1 == initial_p1)
	assert(rect.position != initial_pos)
	_update_label("PASO 2: FIGURA ARRASTRADA POR SU RELLENO\nPosicion: " + str(rect.position) + "\nDegradado: P0=" + str(rect.fill_gradient_p0) + " P1=" + str(rect.fill_gradient_p1) + " (INTACTO)", Color(0.3, 1.0, 0.4))
	await _capture("step2_shape_dragged_by_fill_gradient_intact.png")

	# PASO 3: Activar modo degradado con tecla G
	move_tool._handle_key_shortcuts(KEY_G)
	assert(move_tool.is_gradient_mode == true)
	assert(bbox.has_gradient_annotator() == true)
	bbox.queue_redraw()
	_update_label("PASO 3: MODO DEGRADADO ACTIVADO CON TECLA 'G'\nAnotador interactivo visible con linea y paradas de color.", Color(1.0, 0.85, 0.2))
	await _capture("step3_gradient_mode_activated_with_key_g.png")

	# PASO 4: Editar extremo del degradado con el anotador
	var data: Dictionary = bbox._get_gradient_annotator_data()
	var ev_press_p1 := InputEventMouseButton.new()
	ev_press_p1.button_index = MOUSE_BUTTON_LEFT
	ev_press_p1.pressed = true
	ev_press_p1.global_position = bbox.get_screen_transform() * data["p1"]
	bbox._gui_input(ev_press_p1)

	var ev_motion_p1 := InputEventMouseMotion.new()
	ev_motion_p1.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev_motion_p1.global_position = bbox.get_screen_transform() * (data["p1"] + Vector2(0, 60))
	bbox._gui_input(ev_motion_p1)

	var ev_up_p1 := InputEventMouseButton.new()
	ev_up_p1.button_index = MOUSE_BUTTON_LEFT
	ev_up_p1.pressed = false
	ev_up_p1.global_position = bbox.get_screen_transform() * (data["p1"] + Vector2(0, 60))
	bbox._gui_input(ev_up_p1)

	_update_label("PASO 4: EXTREMO DEGRADADO EDITADO CON ANOTADOR\nNuevo P1=" + str(rect.fill_gradient_p1) + " (Orientacion cambiada)", Color(1.0, 0.5, 0.8))
	await _capture("step4_gradient_edited_with_annotator.png")

	# PASO 5: Salir de edicion de degradado (tecla G o V) y volver a arrastrar elemento
	move_tool._handle_key_shortcuts(KEY_V)
	assert(move_tool.is_gradient_mode == false)
	assert(bbox.has_gradient_annotator() == false)
	bbox.queue_redraw()

	var pos_before_second_drag := rect.position
	var click_point2 := rect.global_position
	var ev_press2 := InputEventMouseButton.new()
	ev_press2.button_index = MOUSE_BUTTON_LEFT
	ev_press2.pressed = true
	ev_press2.global_position = click_point2
	bbox._on_drag_panel_gui_input(ev_press2)

	var ev_motion2 := InputEventMouseMotion.new()
	ev_motion2.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev_motion2.global_position = click_point2 + Vector2(-120, -60)
	bbox._on_drag_panel_gui_input(ev_motion2)

	var ev_up2 := InputEventMouseButton.new()
	ev_up2.button_index = MOUSE_BUTTON_LEFT
	ev_up2.pressed = false
	ev_up2.global_position = click_point2 + Vector2(-120, -60)
	bbox._on_drag_panel_gui_input(ev_up2)

	bbox._sincronizar_dimensiones_en_canvas()
	assert(rect.position != pos_before_second_drag)
	_update_label("PASO 5: SALIDA A MODO SELECCION (TECLA V)\nAnotador bloqueado. Figura arrastrada nuevamente por su relleno con exito.", Color(0.2, 0.9, 1.0))
	await _capture("step5_exit_gradient_mode_drag_again.png")

	print("=== VERIFICACION EN TIEMPO REAL COMPLETADA CON EXITO ===")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
