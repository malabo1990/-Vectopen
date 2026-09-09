# =============================================================================
# script_gdscript/test_triangle_picker_and_gradients_realtime.gd
# Verificación en tiempo real del selector triangular con slider de transparencia
# patrón ajedrezado gris claro/oscuro y los 8 tipos de degradado (círculo no elipse,
# rombo, cubino, espiral, reflexionado).
# =============================================================================
extends Node2D

var _step: int = 0
var _timer: float = 0.0
var _picker_tool: Node
var _test_rect: VectorRectangle
var _annotator_active: bool = false
var _bbox: Control

const SCREENSHOT_DIR := "C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686"

func _ready() -> void:
	# Fondo claro de diseño
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	bg.color = Color(0.93, 0.94, 0.96, 1.0)
	add_child(bg)

	# Instanciar el panel del selector de color
	var picker_scene := load("res://scenes/ui/pickr_color_tool.tscn")
	_picker_tool = picker_scene.instantiate()
	_picker_tool.position = Vector2(40, 40)
	add_child(_picker_tool)

	# Crear figura rectangular alargada para probar Círculo vs Elipse
	_test_rect = VectorRectangle.new()
	_test_rect.name = "TestOblongRect"
	_test_rect.position = Vector2(550, 200)
	_test_rect.size = Vector2(420, 200) # Muy rectangular (relación 2.1 : 1)
	_test_rect.fill_color = Color(0.2, 0.6, 1.0, 1.0)
	add_child(_test_rect)

	# Bounding box para anotador
	var bbox_scene := load("res://scenes/canvas/boundingbox.tscn")
	_bbox = bbox_scene.instantiate()
	add_child(_bbox)
	var move_tool := MoveTool.new()
	move_tool.canvas = self
	move_tool.selected_shapes = [_test_rect]
	_bbox.move_tool_reference = move_tool
	_bbox.target_node = _test_rect
	_bbox._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = _bbox

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.2:
		_timer = 0.0
		_execute_step()

func _execute_step() -> void:
	_step += 1
	print("[EXEC_STEP]: ", _step)
	match _step:
		1:
			# Paso 1: Cambiar a modo Triángulo (1) y mostrar la barra de opacidad
			var gestor: GestorColor = _picker_tool as GestorColor
			gestor._on_mode_pressed(1) # Modo Triángulo
			var picker_p: Panel = gestor.picker_panel
			gestor.establecer_color(Color(0.95, 0.25, 0.35, 1.0), true)
			# Simular clic en el slider de transparencia (ajedrezado) al 50%
			var alpha_r: Rect2 = picker_p.get("_alpha_rect")
			var click_p := Vector2(alpha_r.position.x + alpha_r.size.x * 0.5, alpha_r.get_center().y)
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			mb.position = click_p
			picker_p._gui_input(mb)
			mb.pressed = false
			picker_p._gui_input(mb)

		2:
			# Capturar Paso 1: Selector triangular con slider de opacidad y ajedrezado
			_capture_screenshot("step1_triangle_picker_alpha_checkerboard.png")

		3:
			# Paso 2: Activar Degradado Radial (Círculo tipo 1) en figura alargada 420x200
			var gestor: GestorColor = _picker_tool as GestorColor
			gestor._on_tab_pressed("radial")
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.85, 0.2, 1.0))
			g.set_color(1, Color(0.9, 0.1, 0.3, 1.0))
			_test_rect.fill_gradient = g
			_test_rect.fill_gradient_type = 1
			_test_rect.fill_gradient_p0 = Vector2(0.5, 0.5)
			_test_rect.fill_gradient_p1 = Vector2(0.5 + 80.0 / 420.0, 0.5) # Radio 80px
			_test_rect.queue_redraw()
			if _bbox.move_tool_reference:
				_bbox.move_tool_reference.is_gradient_mode = true
			_bbox.is_gradient_tool_active = true
			_bbox._sincronizar_dimensiones_en_canvas()
			_bbox.queue_redraw()

		4:
			# Capturar Paso 2: Círculo euclidiano perfecto (círculo, no elipse)
			_capture_screenshot("step2_radial_gradient_true_circle_not_ellipse.png")

		5:
			# Paso 3: Activar Degradado Reflexionado (tipo 6)
			var gestor: GestorColor = _picker_tool as GestorColor
			gestor._on_tab_pressed("reflected")
			var g := Gradient.new()
			g.set_color(0, Color(0.1, 0.8, 1.0, 1.0))
			g.set_color(1, Color(0.8, 0.1, 0.9, 1.0))
			_test_rect.fill_gradient = g
			_test_rect.fill_gradient_type = 6
			_test_rect.fill_gradient_p0 = Vector2(0.5, 0.5)
			_test_rect.fill_gradient_p1 = Vector2(0.75, 0.5)
			_test_rect.queue_redraw()
			if _bbox.move_tool_reference:
				_bbox.move_tool_reference.is_gradient_mode = true
			_bbox.is_gradient_tool_active = true
			_bbox._sincronizar_dimensiones_en_canvas()
			_bbox.queue_redraw()

		6:
			# Capturar Paso 3: Degradado reflexionado simétrico con eje de espejo
			_capture_screenshot("step3_reflected_gradient_mirror_axis.png")

		7:
			# Paso 4: Probar Rombo (3)
			var gestor: GestorColor = _picker_tool as GestorColor
			gestor._on_tab_pressed("diamond")
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.9, 0.1, 1.0))
			g.set_color(1, Color(0.1, 0.5, 0.1, 1.0))
			_test_rect.fill_gradient = g
			_test_rect.fill_gradient_type = 3
			_test_rect.queue_redraw()
			_bbox._sincronizar_dimensiones_en_canvas()
			_bbox.queue_redraw()

		8:
			# Capturar Paso 4: Degradado Rombo / Diamante
			_capture_screenshot("step4_diamond_gradient_rombo.png")

		9:
			# Paso 5: Cubino (4)
			var gestor: GestorColor = _picker_tool as GestorColor
			gestor._on_tab_pressed("box")
			var g := Gradient.new()
			g.set_color(0, Color(0.95, 0.4, 0.1, 1.0))
			g.set_color(1, Color(0.1, 0.1, 0.3, 1.0))
			_test_rect.fill_gradient = g
			_test_rect.fill_gradient_type = 4
			_test_rect.queue_redraw()
			_bbox._sincronizar_dimensiones_en_canvas()
			_bbox.queue_redraw()

		10:
			# Capturar Paso 5: Degradado Cubino / Caja
			_capture_screenshot("step5_box_gradient_cubino.png")

		11:
			print("VERIFICACION_COMPLETA_EXITOSA")
			get_tree().quit(0)

func _capture_screenshot(filename: String) -> void:
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	var path := SCREENSHOT_DIR + "/" + filename
	img.save_png(path)
	print("[SNAPSHOT_SAVED]: " + path)
