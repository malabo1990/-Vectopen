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
