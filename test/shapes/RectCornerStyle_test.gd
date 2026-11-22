extends GdUnitTestSuite
## Informe §1: esquinas redondas, con redondeado INVERSO, chaflán y muesca.
## Cuadrado de 100 con radio 20 en las cuatro esquinas: área exacta de cada una.

const CS = preload("res://scripts/canvas/canvas_serializer.gd")

func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5

func _rect(style: int) -> VectorRectangle:
	var r: VectorRectangle = auto_free(VectorRectangle.new())
	r.size = Vector2(100, 100)
	r.corner_radius = 20.0
	r.corner_style = style
	return r

func test_areas_de_cada_tipo() -> void:
	var q := 20.0 * 20.0
	assert_float(_area(_rect(0).get_effect_points())).is_equal_approx(10000.0 - 4.0 * (q - PI * q / 4.0), 5.0)
	assert_float(_area(_rect(1).get_effect_points())).is_equal_approx(10000.0 - PI * q, 5.0)
	assert_float(_area(_rect(2).get_effect_points())).is_equal_approx(10000.0 - 4.0 * q / 2.0, 0.01)
	assert_float(_area(_rect(3).get_effect_points())).is_equal_approx(10000.0 - 4.0 * q, 0.01)

func test_inverso_no_sale_del_rectangulo() -> void:
	for p in _rect(1).get_effect_points():
		assert_bool(Rect2(-50, -50, 100, 100).grow(0.001).has_point(p)).is_true()

func test_se_guarda_y_se_reabre() -> void:
	var r := _rect(2)
	r.name = "Chaflán"
	var d: Dictionary = CS._serialize_element(r)
	var n: Node2D = CS._element_from(d)
	assert_int(int(n.corner_style)).is_equal(2)
	n.free()

func test_tipo_distinto_en_cada_esquina() -> void:
	var r := _rect(0)
	r.set_corner_style_at(1, 2)   # ↗ chaflán
	r.set_corner_style_at(2, 3)   # ↘ muesca
	assert_bool(r.corner_styles_mixed()).is_true()
	var q := 400.0
	var expect := 10000.0 - 2.0 * (q - PI * q / 4.0) - q / 2.0 - q
	assert_float(_area(r.get_effect_points())).is_equal_approx(expect, 5.0)
	var d: Dictionary = CS._serialize_element(r)
	var n: Node2D = CS._element_from(d)
	assert_array(Array(n.corner_styles)).is_equal([0, 2, 3, 0])
	n.free()
	r.corner_style = 1   # «Tipo de esquina» cambia las cuatro
	assert_array(Array(r.corner_styles)).is_equal([1, 1, 1, 1])
