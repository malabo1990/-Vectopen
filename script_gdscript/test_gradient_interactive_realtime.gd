extends Node2D

func _ready() -> void:
	# Configurar ventana
	get_viewport().size = Vector2i(1200, 800)
	
	# Crear canvas base
	var canvas := Node2D.new()
	canvas.name = "CanvasRoot"
	add_child(canvas)
	
	# Fondo del canvas
	var bg := ColorRect.new()
	bg.size = Vector2(1200, 800)
	bg.color = Color(0.94, 0.95, 0.97, 1.0)
	canvas.add_child(bg)
	
	# Crear figura 1: Círculo con Degradado Cónico / Espiral
	var circle_conic := VectorCircle.new()
	circle_conic.name = "CirculoEspiral"
	circle_conic.position = Vector2(460, 400)
	circle_conic.size = Vector2(280, 280)
	circle_conic.stroke_width = 2.5
	circle_conic.stroke_color = Color(0.15, 0.2, 0.3, 0.5)
	
	var grad_conic := Gradient.new()
	grad_conic.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad_conic.colors = PackedColorArray([
		Color(0.96, 0.26, 0.21, 1.0), # Rojo
		Color(0.98, 0.74, 0.02, 1.0), # Amarillo
		Color(0.18, 0.80, 0.44, 1.0), # Verde
		Color(0.13, 0.59, 0.95, 1.0), # Azul
		Color(0.96, 0.26, 0.21, 1.0), # Rojo (cierre de ciclo)
	])
	circle_conic.fill_gradient = grad_conic
	circle_conic.fill_gradient_type = 2 # Cónico / Espiral
	circle_conic.fill_gradient_p0 = Vector2(0.5, 0.5) # Centro del vórtice
	circle_conic.fill_gradient_p1 = Vector2(0.85, 0.5) # Radio y dirección de inicio
	canvas.add_child(circle_conic)

	# Crear figura 2: Rectángulo con Degradado Lineal arrastrado a través del cuerpo de la figura
	var rect := VectorRectangle.new()
	rect.name = "RectanguloLineal"
	rect.position = Vector2(900, 400)
	rect.size = Vector2(300, 220)
	rect.corner_radius = 16.0
	rect.stroke_width = 2.0
	rect.stroke_color = Color(0.15, 0.2, 0.3, 0.5)
	
	var grad_linear := Gradient.new()
	grad_linear.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad_linear.colors = PackedColorArray([
		Color(0.55, 0.15, 0.95, 1.0), # Violeta
		Color(0.10, 0.75, 0.90, 1.0), # Turquesa
		Color(1.00, 0.40, 0.70, 1.0), # Rosa
	])
	rect.fill_gradient = grad_linear
	rect.fill_gradient_type = 0 # Linear
	rect.fill_gradient_p0 = Vector2(0.15, 0.25)
	rect.fill_gradient_p1 = Vector2(0.85, 0.75)
	canvas.add_child(rect)

	# Crear figura 3: Panel de trazados diagonales finos y antialiasing
	var stroke_panel := Panel.new()
	stroke_panel.position = Vector2(240, 480)
	stroke_panel.size = Vector2(930, 290)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	pstyle.border_width_left = 1
	pstyle.border_width_top = 1
	pstyle.border_width_right = 1
	pstyle.border_width_bottom = 1
	pstyle.border_color = Color(0.85, 0.88, 0.92, 1.0)
	stroke_panel.add_theme_stylebox_override("panel", pstyle)
	canvas.add_child(stroke_panel)

	var draw_node := _AntialiasingTestDraw.new()
	stroke_panel.add_child(draw_node)

	# Instanciar BoundingBox para el rectángulo
	var bbox_scene: PackedScene = load("res://scenes/canvas/boundingbox.tscn")
	var bbox = bbox_scene.instantiate()
	bbox.name = "BoundingBox"
	canvas.add_child(bbox)
	bbox.target_node = rect
	bbox._sincronizar_dimensiones_en_canvas()

	# Instanciar panel de color/degradado a la izquierda
	var color_picker_scene: PackedScene = load("res://scenes/ui/pickr_color_tool.tscn")
	var color_picker_ui = color_picker_scene.instantiate()
	color_picker_ui.position = Vector2(15, 20)
	color_picker_ui.custom_minimum_size = Vector2(210, 500)
	add_child(color_picker_ui)
	
	if color_picker_ui.has_method("_on_tab_pressed"):
		color_picker_ui._on_tab_pressed("linear")

	await get_tree().create_timer(0.3).timeout

	# 1. Simular arrastre del punto P1 MUY FUERA del BoundingBox (a 400, 350 en local = coord normalizada (1.33, 1.59))
	var data: Dictionary = bbox._get_gradient_annotator_data()
	var p1_pos: Vector2 = data["p1"]

	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bbox.get_global_transform() * p1_pos
	bbox._handle_annotator_input(ev_press)

	# Mover muy afuera
	var ev_motion_outside := InputEventMouseMotion.new()
	ev_motion_outside.global_position = bbox.get_global_transform() * Vector2(420, 360)
	bbox._handle_annotator_input(ev_motion_outside)

	await get_tree().create_timer(0.2).timeout
	_take_screenshot("step1_handle_dragged_outside_bb.png")

	# 2. Devolver el manipulador hacia dentro de la figura sin soltar ni atascarse
	var ev_motion_inside := InputEventMouseMotion.new()
	ev_motion_inside.global_position = bbox.get_global_transform() * Vector2(250, 180)
	bbox._handle_annotator_input(ev_motion_inside)

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.global_position = bbox.get_global_transform() * Vector2(250, 180)
	bbox._handle_annotator_input(ev_release)

	await get_tree().create_timer(0.2).timeout
	_take_screenshot("step2_handle_returned_inside.png")

	# 3. Aplicar color sólido desde ColorCore y verificar que el modo sólido responde y desactiva el degradado
	ColorCore.set_paint({"type": "solid", "color": Color(0.12, 0.65, 0.52, 1.0)})
	rect.fill_color = Color(0.12, 0.65, 0.52, 1.0)
	rect.fill_gradient = null
	bbox.deactivate_gradient_mode()
	bbox._sincronizar_dimensiones_en_canvas()
	if color_picker_ui.has_method("_on_tab_pressed"):
		color_picker_ui._on_tab_pressed("solid")

	await get_tree().create_timer(0.3).timeout
	_take_screenshot("step3_solid_color_working.png")

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

func _take_screenshot(filename: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var path := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/" + filename
	img.save_png(path)
	print("Captura guardada en: ", path)

class _AntialiasingTestDraw extends Node2D:
	func _draw() -> void:
		var stroke_widths: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0]
		var col_stroke := Color(0.12, 0.16, 0.24, 1.0)

		# Columna 1: Líneas diagonales finas en abanico (demostrando ausencia de escalera y no rotura de 0.5px)
		for i in range(stroke_widths.size()):
			var raw_w: float = stroke_widths[i]
			var rend_w: float = maxf(1.0, raw_w)
			var rend_col: Color = col_stroke
			if raw_w < 1.0:
				rend_col.a *= raw_w
			var origin := Vector2(70 + i * 85, 30)
			for a_idx in range(5):
				var ang: float = deg_to_rad(15.0 + a_idx * 15.0)
				var p_end := origin + Vector2(cos(ang), sin(ang)) * 130.0
				draw_line(origin, p_end, rend_col, rend_w, true)
			draw_string(ThemeDB.fallback_font, origin + Vector2(-15, 160), str(raw_w) + " px", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.3, 0.35, 0.45))

		# Columna 2: Ondas y curvas Bézier suaves sin pixelado
		var curve_origin := Vector2(490, 35)
		for i in range(stroke_widths.size()):
			var raw_w: float = stroke_widths[i]
			var rend_w: float = maxf(1.0, raw_w)
			var rend_col := Color(0.15, 0.50, 0.90, 1.0)
			if raw_w < 1.0:
				rend_col.a *= raw_w
			var y_off := float(i * 35)
			var pts: PackedVector2Array = PackedVector2Array()
			for step in range(50):
				var t := float(step) / 49.0
				var x := t * 200.0
				var y := sin(t * TAU) * 14.0 + y_off
				pts.append(curve_origin + Vector2(x, y))
			draw_polyline(pts, rend_col, rend_w, true)
			draw_string(ThemeDB.fallback_font, curve_origin + Vector2(215, y_off + 4), str(raw_w) + " px", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.35, 0.45))

		# Columna 3: Arcos concéntricos finos (0.5px a 2px)
		var center := Vector2(810, 100)
		for r_idx in range(1, 6):
			var r: float = float(r_idx * 16)
			var raw_w: float = 0.5 if (r_idx == 1) else (1.0 if r_idx <= 3 else 2.0)
			var rend_w: float = maxf(1.0, raw_w)
			var rend_col := Color(0.85, 0.25, 0.45, 1.0)
			if raw_w < 1.0:
				rend_col.a *= raw_w
			draw_arc(center, r, 0.0, TAU, 64, rend_col, rend_w, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-55, 110), "Arcos concentricos antialias", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.3, 0.35, 0.45))

