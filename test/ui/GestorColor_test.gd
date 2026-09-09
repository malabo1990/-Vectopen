extends GdUnitTestSuite

const _GestorColor := preload("res://script_gdscript/ui/managercolor_pickrColor.gd")

func _make_gestor() -> GestorColor:
	return auto_free(_GestorColor.new())

func _scene_con_brillo() -> Array:
	var root: Node = auto_free(Node.new())
	var gc: GestorColor = _make_gestor()
	var cr: ColorRect = ColorRect.new()
	cr.name = "ColorRect_fill"
	cr.color = Color(1.0, 0.0, 0.0, 1.0)
	gc.add_child(cr)
	var vs: VSlider = VSlider.new()
	vs.name = "VSlider_brillo"
	vs.max_value = 100.0
	gc.add_child(vs)
	root.add_child(gc)
	add_child(root)
	gc.nodo_color_rect = cr
	gc._brillo_slider = vs
	return [gc, cr, vs]

func test_ready_configura_slider() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var vs: VSlider = r[2]

	gc._ready()

	assert_float(vs.max_value).is_equal(100.0)

func test_brillo_50_oscurece_rojo() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var cr: ColorRect = r[1]

	gc._ready()
	cr.color = Color(1.0, 0.0, 0.0, 1.0)

	gc._on_brillo_changed(50.0)

	assert_float(cr.color.r).is_equal(0.5)
	assert_float(cr.color.g).is_equal(0.0)
	assert_float(cr.color.b).is_equal(0.0)

func test_brillo_0_hace_negro() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var cr: ColorRect = r[1]

	gc._ready()
	cr.color = Color(1.0, 0.5, 0.2, 1.0)

	gc._on_brillo_changed(0.0)

	assert_float(cr.color.r).is_equal(0.0)
	assert_float(cr.color.g).is_equal(0.0)
	assert_float(cr.color.b).is_equal(0.0)

func test_brillo_100_devuelve_color_original() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var cr: ColorRect = r[1]

	gc._ready()
	cr.color = Color(1.0, 0.0, 0.0, 1.0)

	gc._on_brillo_changed(100.0)

	assert_float(cr.color.r).is_equal(1.0)
	assert_float(cr.color.g).is_equal(0.0)
	assert_float(cr.color.b).is_equal(0.0)

func test_brillo_no_afecta_alpha() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var cr: ColorRect = r[1]

	gc._ready()
	cr.color = Color(1.0, 0.0, 0.0, 0.5)

	gc._on_brillo_changed(50.0)

	assert_float(cr.color.a).is_equal(0.5)

func test_brillo_75_escala_valor_hsv() -> void:
	var r = _scene_con_brillo()
	var gc: GestorColor = r[0]
	var cr: ColorRect = r[1]

	gc._ready()
	cr.color = Color(1.0, 0.0, 0.0, 1.0)

	gc._on_brillo_changed(75.0)

	assert_float(cr.color.v).is_equal(0.75)

func test_establecer_color_cambia_color_rect() -> void:
	var gc: GestorColor = _make_gestor()
	var cr: ColorRect = ColorRect.new()
	gc.add_child(cr)
	gc.nodo_color_rect = cr

	gc.establecer_color(Color.GREEN)

	assert_that(cr.color).is_equal(Color.GREEN)

var _senal_recibida := false

func test_establecer_color_notifica_senal() -> void:
	_senal_recibida = false
	var gc: GestorColor = _make_gestor()
	var cr: ColorRect = ColorRect.new()
	gc.add_child(cr)
	gc.nodo_color_rect = cr

	gc.color_actualizado.connect(_on_prueba_senal)
	gc.establecer_color(Color.BLUE)

	assert_bool(_senal_recibida).is_true()

func _on_prueba_senal(_c: Color) -> void:
	_senal_recibida = true

func test_obtener_color_devuelve_actual() -> void:
	var gc: GestorColor = _make_gestor()
	var cr: ColorRect = ColorRect.new()
	cr.color = Color.MAGENTA
	gc.add_child(cr)
	gc.nodo_color_rect = cr

	assert_that(gc.obtener_color()).is_equal(Color.MAGENTA)

func test_obtener_color_sin_color_rect_devuelve_blanco() -> void:
	var gc: GestorColor = _make_gestor()

	assert_that(gc.obtener_color()).is_equal(Color.WHITE)

func test_cambio_tabs_solid_linear_radial() -> void:
	var gc: GestorColor = _make_gestor()
	var tab_s := Button.new()
	var tab_l := Button.new()
	var tab_r := Button.new()
	var tab_c := Button.new()
	var grad_ctrl := Control.new()
	grad_ctrl.set_script(load("res://script_gdscript/ui/control_gradient.gd"))
	gc.tab_solid = tab_s
	gc.tab_linear = tab_l
	gc.tab_radial = tab_r
	gc.tab_conic = tab_c
	gc.gradient_editor = grad_ctrl
	gc.add_child(tab_s)
	gc.add_child(tab_l)
	gc.add_child(tab_r)
	gc.add_child(tab_c)
	gc.add_child(grad_ctrl)

	gc._conectar_controles_ui()

	# Default tab is solid, editor invisible
	assert_str(gc.current_tab).is_equal("solid")
	assert_bool(grad_ctrl.visible).is_false()

	# Switch to linear
	gc._on_tab_pressed("linear")
	assert_str(gc.current_tab).is_equal("linear")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(0)

	# Switch to radial
	gc._on_tab_pressed("radial")
	assert_str(gc.current_tab).is_equal("radial")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(1)

	# Switch to conic
	gc._on_tab_pressed("conic")
	assert_str(gc.current_tab).is_equal("conic")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(2)

	# Switch to diamond
	gc._on_tab_pressed("diamond")
	assert_str(gc.current_tab).is_equal("diamond")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(3)

	# Switch to box
	gc._on_tab_pressed("box")
	assert_str(gc.current_tab).is_equal("box")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(4)

	# Switch to spiral
	gc._on_tab_pressed("spiral")
	assert_str(gc.current_tab).is_equal("spiral")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(5)

	# Switch to reflected
	gc._on_tab_pressed("reflected")
	assert_str(gc.current_tab).is_equal("reflected")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(6)

	# Switch back to solid
	gc._on_tab_pressed("solid")
	assert_str(gc.current_tab).is_equal("solid")
	assert_bool(grad_ctrl.visible).is_false()

func test_cambio_modos_picker_circulo_triangulo_cuadrado() -> void:
	var gc: GestorColor = _make_gestor()
	var picker := Panel.new()
	picker.set_script(load("res://script_gdscript/ui/hsl_colorpickr.gd"))
	var btn_c := Button.new()
	var btn_t := Button.new()
	var btn_s := Button.new()
	gc.picker_panel = picker
	gc.btn_mode_circle = btn_c
	gc.btn_mode_triangle = btn_t
	gc.btn_mode_square = btn_s
	gc.add_child(picker)
	gc.add_child(btn_c)
	gc.add_child(btn_t)
	gc.add_child(btn_s)

	gc._conectar_controles_ui()

	# Mode 0 = Circle
	gc._on_mode_pressed(0)
	assert_int(picker.get_picker_mode()).is_equal(0)

	# Mode 1 = Triangle
	gc._on_mode_pressed(1)
	assert_int(picker.get_picker_mode()).is_equal(1)

	# Mode 2 = Square (Figma style)
	gc._on_mode_pressed(2)
	assert_int(picker.get_picker_mode()).is_equal(2)

func test_stop_seleccionado_actualiza_color_picker() -> void:
	var gc: GestorColor = _make_gestor()
	var picker := Panel.new()
	picker.set_script(load("res://script_gdscript/ui/hsl_colorpickr.gd"))
	var cr := ColorRect.new()
	gc.picker_panel = picker
	gc.nodo_color_rect = cr
	gc.add_child(picker)
	gc.add_child(cr)

	gc._on_gradient_stop_selected(Color.CYAN)

	assert_that(cr.color).is_equal(Color.CYAN)
	assert_that(picker.get("_final_color").call()).is_equal(Color.CYAN)

func test_picker_color_changed_in_solid_tab_updates_nodo_and_colorcore() -> void:
	var gc: GestorColor = _make_gestor()
	var cr := ColorRect.new()
	cr.color = Color.WHITE
	gc.nodo_color_rect = cr
	gc.add_child(cr)
	add_child(gc)

	gc.current_tab = "solid"
	gc._on_picker_color_changed(Color.ORANGE)

	assert_that(cr.color).is_equal(Color.ORANGE)
	assert_that(ColorCore.fill_color).is_equal(Color.ORANGE)
	assert_str(ColorCore.active_paint()["type"]).is_equal("solid")

func test_on_colorcore_paint_changed_to_solid_updates_tab_and_color() -> void:
	var gc: GestorColor = _make_gestor()
	var picker := Panel.new()
	picker.set_script(load("res://script_gdscript/ui/hsl_colorpickr.gd"))
	var cr := ColorRect.new()
	cr.color = Color.BLACK
	gc.picker_panel = picker
	gc.nodo_color_rect = cr
	gc.add_child(picker)
	gc.add_child(cr)
	add_child(gc)

	gc.current_tab = "linear"
	gc._on_colorcore_paint_changed({"type": "solid", "color": Color.PURPLE})

	assert_str(gc.current_tab).is_equal("solid")
	assert_that(cr.color).is_equal(Color.PURPLE)
	assert_that((picker.get("_final_color").call() as Color).is_equal_approx(Color.PURPLE)).is_true()

func test_triangle_picker_alpha_slider_and_checkerboard() -> void:
	var picker: Panel = auto_free(Panel.new())
	picker.set_script(load("res://script_gdscript/ui/hsl_colorpickr.gd"))
	picker.size = Vector2(192, 240)
	add_child(picker)
	picker._ready()

	# Cambiar a Modo Triángulo (1)
	picker.set_picker_mode(1)
	assert_int(picker.get_picker_mode()).is_equal(1)

	# Simular clic en la barra de opacidad (alpha_rect) al 40% del ancho
	var alpha_r: Rect2 = picker.get("_alpha_rect")
	assert_that(alpha_r.size.x > 0.0).is_true()

	var click_x := alpha_r.position.x + alpha_r.size.x * 0.40
	var click_y := alpha_r.get_center().y

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(click_x, click_y)
	picker._gui_input(mb)

	assert_float(picker.current_a).is_equal_approx(0.40, 0.05)
	var fc: Color = picker._final_color()
	assert_float(fc.a).is_equal_approx(0.40, 0.05)

	# Arrastrar alpha al 80%
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(alpha_r.position.x + alpha_r.size.x * 0.80, click_y)
	picker._gui_input(mm)
	assert_float(picker.current_a).is_equal_approx(0.80, 0.05)

	# Soltar ratón
	mb.pressed = false
	picker._gui_input(mb)

func test_euclidean_circle_gradient_on_oblong_shape() -> void:
	# En figuras rectangulares (ej. 400x200), el degradado radial tipo 1
	# DEBE ser un círculo euclidiano exacto, NO una elipse achatada.
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(400, 200)
	var g := Gradient.new()
	g.set_color(0, Color(1, 0, 0, 1)) # Centro rojo (t = 0)
	g.set_color(1, Color(0, 0, 1, 1)) # Exterior azul (t = 1)
	shape.fill_gradient = g
	shape.fill_gradient_type = 1 # Círculo (Radial euclidiano)
	shape.fill_gradient_p0 = Vector2(0.5, 0.5) # Centro en (200px, 100px)
	shape.fill_gradient_p1 = Vector2(0.5 + 80.0 / 400.0, 0.5) # Radio = 80px hacia la derecha

	var tex: ImageTexture = shape._ensure_grad_tex()
	assert_that(tex).is_not_null()
	var img := tex.get_image()

	# En una elipse tradicional no compensada, la distancia horizontal y vertical daría valores distintos.
	# En nuestro círculo euclidiano compensado, a 50px a la derecha y a 50px hacia abajo el color DEBE ser IDÉNTICO.
	var center_uv := Vector2(0.5, 0.5)
	var center_px := Vector2(center_uv.x * (img.get_width() - 1), center_uv.y * (img.get_height() - 1))

	# Para una figura 400x200 (proporción 2:1), 32px en X equivalen exactamente a 64px en Y en espacio de textura
	var dx_tex := 32
	var dy_tex := 64

	var col_h := img.get_pixel(int(center_px.x + dx_tex), int(center_px.y))
	var col_v := img.get_pixel(int(center_px.x), int(center_px.y + dy_tex))

	# Ambos puntos están a la misma distancia euclidiana (25px) del centro en el canvas:
	# En un círculo euclidiano sus valores coinciden (en una elipse achatada diferirían por > 0.30)
	assert_float(col_h.r).is_equal_approx(col_v.r, 0.02)
	assert_float(col_h.b).is_equal_approx(col_v.b, 0.02)

func test_reflected_gradient_symmetry() -> void:
	# Degradado reflexionado (tipo 6): simétrico a ambos lados del eje P0
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(200, 200)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0, 1)) # P0 Amarillo
	g.set_color(1, Color(0, 1, 0, 1)) # P1 Verde
	shape.fill_gradient = g
	shape.fill_gradient_type = 6 # Reflexionado
	shape.fill_gradient_p0 = Vector2(0.5, 0.5) # Centro en 0.5
	shape.fill_gradient_p1 = Vector2(0.8, 0.5) # Span = +0.3 hacia la derecha

	var tex: ImageTexture = shape._ensure_grad_tex()
	assert_that(tex).is_not_null()
	var img := tex.get_image()

	# Puntos exactamente simétricos respecto al centro 255.5:
	# (256 + k) y (255 - k) suman 511 y equidistan de 255.5 exactamente
	var k := 60
	var x_right := 256 + k
	var x_left := 255 - k
	var cy := 256

	var col_right := img.get_pixel(x_right, cy)
	var col_left := img.get_pixel(x_left, cy)

	# Reflejado simétrico: izquierda y derecha a igual distancia deben coincidir
	assert_that(col_right.is_equal_approx(col_left)).is_true()

func test_checkerboard_rect_component() -> void:
	var cr: CheckerboardRect = auto_free(CheckerboardRect.new())
	cr.size = Vector2(40, 40)
	cr.tile_size = 8.0
	add_child(cr)
	cr.queue_redraw()
	assert_that(cr.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)



