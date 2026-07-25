extends GdUnitTestSuite

func test_default_constructor() -> void:
	var v: DVec2 = DVec2.new()
	assert_float(v.x).is_equal(0.0)
	assert_float(v.y).is_equal(0.0)

func test_constructor_with_values() -> void:
	var v: DVec2 = DVec2.new(1.5, -2.25)
	assert_float(v.x).is_equal(1.5)
	assert_float(v.y).is_equal(-2.25)

func test_from_v2_and_to_v2_round_trip() -> void:
	var src: Vector2 = Vector2(12.5, -7.25)
	var v: DVec2 = DVec2.from_v2(src)
	assert_vector(v.to_v2()).is_equal(src)

func test_array_from_v2() -> void:
	var packed: PackedVector2Array = PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	var arr: Array[DVec2] = DVec2.array_from_v2(packed)
	assert_int(arr.size()).is_equal(2)
	assert_vector(arr[0].to_v2()).is_equal(Vector2(1, 2))
	assert_vector(arr[1].to_v2()).is_equal(Vector2(3, 4))

func test_added() -> void:
	var a: DVec2 = DVec2.new(1.0, 2.0)
	var b: DVec2 = DVec2.new(3.0, 4.0)
	var r: DVec2 = a.added(b)
	assert_float(r.x).is_equal(4.0)
	assert_float(r.y).is_equal(6.0)

func test_subtracted() -> void:
	var a: DVec2 = DVec2.new(5.0, 5.0)
	var b: DVec2 = DVec2.new(2.0, 1.0)
	var r: DVec2 = a.subtracted(b)
	assert_float(r.x).is_equal(3.0)
	assert_float(r.y).is_equal(4.0)

func test_scaled() -> void:
	var a: DVec2 = DVec2.new(2.0, -3.0)
	var r: DVec2 = a.scaled(2.5)
	assert_float(r.x).is_equal(5.0)
	assert_float(r.y).is_equal(-7.5)

func test_scaled2() -> void:
	var a: DVec2 = DVec2.new(2.0, 3.0)
	var r: DVec2 = a.scaled2(2.0, 4.0)
	assert_float(r.x).is_equal(4.0)
	assert_float(r.y).is_equal(12.0)

func test_rotated_quarter_turn() -> void:
	var a: DVec2 = DVec2.new(1.0, 0.0)
	var r: DVec2 = a.rotated(PI / 2.0)
	assert_float(r.x).is_equal_approx(0.0, 1e-9)
	assert_float(r.y).is_equal_approx(1.0, 1e-9)

func test_equals_approx() -> void:
	var a: DVec2 = DVec2.new(1.0000000001, 2.0)
	var b: DVec2 = DVec2.new(1.0000000002, 2.0)
	assert_bool(a.equals_approx(b, 1e-6)).is_true()
	assert_bool(a.equals_approx(b, 1e-12)).is_false()

func test_double_precision_survives_where_float32_would_not() -> void:
	# 100.00001234 no es representable con exactitud en float32 (~7 dígitos
	# significativos totales), pero sí en el float de 64 bits de GDScript.
	# DVec2.x conserva el valor exacto; el Vector2 equivalente (float32),
	# obtenido al convertir con to_v2(), ya no lo hace.
	var precise: float = 100.00001234
	var v: DVec2 = DVec2.new(precise, precise)
	assert_float(v.x).is_equal(precise)

	var as_v2: Vector2 = v.to_v2()
	var v2_error: float = absf(as_v2.x - precise)
	assert_bool(v2_error > 0.0).is_true()  # float32 sí perdió precisión al convertir
	assert_bool(v2_error < 1e-3).is_true()  # pero el error sigue siendo del orden float32, no catastrófico
