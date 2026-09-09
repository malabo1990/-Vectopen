extends Control

func _ready() -> void:
	get_viewport().size = Vector2i(1200, 800)

	var canvas := Node2D.new()
	canvas.name = "CanvasRoot"
	add_child(canvas)

	var bg := ColorRect.new()
	bg.size = Vector2(1200, 800)
	bg.color = Color(0.95, 0.96, 0.98, 1.0)
	canvas.add_child(bg)

	# Figura 1: Rectángulo para probar arrastre independiente de extremos
	var rect := VectorRectangle.new()
	rect.name = "RectanguloGradiente"
	rect.position = Vector2(480, 380)
	rect.size = Vector2(340, 240)
	rect.corner_radius = 16.0
	rect.stroke_width = 2.0
	rect.stroke_color = Color(0.2, 0.25, 0.35, 0.5)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.12, 0.53, 0.90, 1.0), # Azul vibrante
		Color(0.95, 0.75, 0.10, 1.0), # Amarillo centro
		Color(0.92, 0.22, 0.35, 1.0), # Carmín
	])
	rect.fill_gradient = grad
	rect.fill_gradient_type = 0 # Lineal
	rect.set_gradient_points(Vector2(0.2, 0.35), Vector2(0.8, 0.65))
	canvas.add_child(rect)

	# Bounding box
	var bbox_scene: PackedScene = load("res://scenes/canvas/boundingbox.tscn")
	var bbox = bbox_scene.instantiate()
	bbox.name = "BoundingBox"
	canvas.add_child(bbox)
	bbox.target_node = rect
	bbox._sincronizar_dimensiones_en_canvas()

	# MoveTool
	var move_tool := MoveTool.new()
	move_tool.canvas = canvas
	move_tool.selected_shapes = [rect]
	move_tool._bounding_box = bbox
	bbox.move_tool_reference = move_tool

	# Panel de color a la izquierda
	var color_picker_scene: PackedScene = load("res://scenes/ui/pickr_color_tool.tscn")
	var color_picker_ui = color_picker_scene.instantiate()
	color_picker_ui.position = Vector2(24, 24)
	color_picker_ui.custom_minimum_size = Vector2(210, 500)
	add_child(color_picker_ui)
	if color_picker_ui.has_method("_on_tab_pressed"):
		color_picker_ui._on_tab_pressed("linear")

	# Título explicativo en UI
	var title_lbl := Label.new()
	title_lbl.position = Vector2(300, 30)
	title_lbl.text = "Vectopen — Test de Puntos de Degradado Fijos, Drag de Paradas y Atajo G (Affinity Style)"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.15, 0.20, 0.30, 1.0))
	add_child(title_lbl)

	await get_tree().create_timer(0.3).timeout

	# ── TEST 1: Arrastrar extremo p1 manteniendo p0 COMPLETAMENTE FIJO ──────
	var data: Dictionary = bbox._get_gradient_annotator_data()
	var p0_before: Vector2 = rect.fill_gradient_p0

	# Clic sobre p1 y arrastre hacia (local 320, 220 -> norm ~0.94, ~0.92)
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bbox.get_global_transform() * data["p1"]
	bbox._handle_annotator_input(ev_press)

	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bbox.get_global_transform() * Vector2(320, 220)
	bbox._handle_annotator_input(ev_motion)

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	bbox._handle_annotator_input(ev_release)

	var p0_after: Vector2 = rect.fill_gradient_p0
	print("P0 ANTES: ", p0_before, " | P0 DESPUÉS DE ARRASTRAR P1: ", p0_after)
	assert(p0_before == p0_after, "Error: ¡P0 se movió cuando solo se arrastró P1!")

	await get_tree().create_timer(0.3).timeout
	_take_screenshot("realtime_gradient_p1_dragged_p0_fixed.png")

	# ── TEST 2: Arrastrar el círculo de parada intermedia a lo largo de la línea ─
	data = bbox._get_gradient_annotator_data()
	var stop_mid_pos: Vector2 = data["stops"][1]["position"]
	var ev_press_stop := InputEventMouseButton.new()
	ev_press_stop.button_index = MOUSE_BUTTON_LEFT
	ev_press_stop.pressed = true
	ev_press_stop.global_position = bbox.get_global_transform() * stop_mid_pos
	bbox._handle_annotator_input(ev_press_stop)

	# Deslizar parada intermedia hacia el 75% del recorrido
	var target_stop_pos: Vector2 = data["p0"].lerp(data["p1"], 0.75)
	var ev_motion_stop := InputEventMouseMotion.new()
	ev_motion_stop.global_position = bbox.get_global_transform() * target_stop_pos
	bbox._handle_annotator_input(ev_motion_stop)

	var ev_release_stop := InputEventMouseButton.new()
	ev_release_stop.button_index = MOUSE_BUTTON_LEFT
	ev_release_stop.pressed = false
	bbox._handle_annotator_input(ev_release_stop)

	print("NUEVO OFFSET DE PARADA INTERMEDIA: ", grad.get_offset(1))

	await get_tree().create_timer(0.3).timeout
	_take_screenshot("realtime_gradient_stop_dragged.png")

	# ── TEST 3: Atajo G y Clic en Lienzo Vacío sin perder la línea ni selección ──
	move_tool._handle_key_shortcuts(KEY_G)

	# Simular clic en el espacio vacío del lienzo (850, 650) fuera de toda figura
	var ev_click_empty := InputEventMouseButton.new()
	ev_click_empty.button_index = MOUSE_BUTTON_LEFT
	ev_click_empty.pressed = true
	ev_click_empty.global_position = bbox.get_global_transform() * Vector2(500, 300)
	bbox.handle_annotator_input(ev_click_empty)

	var ev_click_empty_rel := InputEventMouseButton.new()
	ev_click_empty_rel.button_index = MOUSE_BUTTON_LEFT
	ev_click_empty_rel.pressed = false
	ev_click_empty_rel.global_position = bbox.get_global_transform() * Vector2(500, 300)
	bbox.handle_annotator_input(ev_click_empty_rel)

	print("SELECCIÓN TRAS CLIC FUERA: ", move_tool.selected_shapes.size(), " | ANOTADOR VISIBLE: ", bbox.visible)
	assert(move_tool.selected_shapes.size() == 1, "Error: ¡La selección se perdió al hacer clic fuera!")

	await get_tree().create_timer(0.3).timeout
	_take_screenshot("realtime_gradient_key_g_persistent.png")

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

func _take_screenshot(filename: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/" + filename
	img.save_png(path)
	print("Captura guardada en: ", path)
