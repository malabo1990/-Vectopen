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

	# Switch to conic / spiral
	gc._on_tab_pressed("conic")
	assert_str(gc.current_tab).is_equal("conic")
	assert_bool(grad_ctrl.visible).is_true()
	assert_int(grad_ctrl.get("gradient_type")).is_equal(2)

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


