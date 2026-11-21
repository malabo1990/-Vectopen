extends GdUnitTestSuite

## «Simplificar trazado» (encargo 29): menos nodos con la misma forma; la
## costura de un contorno cerrado no se deforma; un paso de deshacer.

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	HistoryManager.clear()

func _bbox(p: VectorPath) -> Rect2:
	var pts := VectorPath.closed_points(p.curve)
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r

func test_circulo_de_120_puntos() -> void:
	var pts := PackedVector2Array()
	for i in 120:
		pts.append(Vector2(300, 300) + Vector2.from_angle(TAU * i / 120.0) * 150.0)
	var p := _api.add_path(pts, true, "Círculo escaneado") as VectorPath
	var b0 := _bbox(p)
	var removed := _api.simplify_path(p, 1.0)
	assert_int(removed).is_greater(100)
	assert_int(p.curve.point_count).is_less(16)
	var b1 := _bbox(p)
	assert_float(b1.position.distance_to(b0.position)).is_less(2.0)
	assert_float(absf(b1.size.x - b0.size.x)).is_less(2.0)
	# Todos los puntos del nuevo contorno a ≈150 px del centro (sin aplanados)
	for q in VectorPath.closed_points(p.curve):
		assert_float(absf(q.distance_to(Vector2(300, 300)) - 150.0)).is_less(2.5)
	_api.undo()
	assert_int(p.curve.point_count).is_equal(120)

func test_cuadrado_conserva_esquinas() -> void:
	var pts := PackedVector2Array()
	for side in 4:
		for k in 10:
			var t := k / 10.0
			var a: Vector2 = [Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)][side]
			var b: Vector2 = [Vector2(200, 0), Vector2(200, 200), Vector2(0, 200), Vector2(0, 0)][side]
			pts.append(a.lerp(b, t) + Vector2(100, 100))
	var p := _api.add_path(pts, true, "Cuadrado") as VectorPath
	_api.simplify_path(p, 1.0)
	assert_int(p.curve.point_count).is_less_equal(6)
	var b := _bbox(p)
	assert_float(b.size.x).is_equal_approx(200.0, 2.0)
	assert_float(b.size.y).is_equal_approx(200.0, 2.0)
