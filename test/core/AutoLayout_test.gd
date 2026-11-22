extends GdUnitTestSuite
## Auto Layout (informe §4): fila, columna, rejilla, salto de línea, fondo a
## la medida, repartir, recolocar al cambiar un hijo, guardar / abrir.

const AL = preload("res://script_gdscript/shapes/auto_layout.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

var _g: Node2D

func _rect(sz: Vector2, pos := Vector2.ZERO) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = sz
	r.position = pos
	_g.add_child(r)
	return r

func before_test() -> void:
	_g = auto_free(Node2D.new())
	_g.set_meta("shape_type", "group")
	add_child(_g)

func _left(n: Node2D) -> float:
	return AL.box(n).position.x

func _top(n: Node2D) -> float:
	return AL.box(n).position.y

func test_fila_con_separacion_y_margen() -> void:
	var a := _rect(Vector2(100, 50), Vector2(500, 500))
	var b := _rect(Vector2(60, 80), Vector2(-300, 40))
	var bg := _rect(Vector2(10, 10))
	bg.move_to_front()
	_g.move_child(bg, 0)
	AL.make(_g, {"mode": "row", "gap": 10.0, "padding": 20.0, "cross": "center"}, bg)
	# fondo en (0,0) tras el ajuste: a a 20 del borde, b tras a + 10
	var o := AL.box(bg).position
	assert_float(_left(a) - o.x).is_equal_approx(20.0, 0.01)
	assert_float(_left(b) - o.x).is_equal_approx(20.0 + 100.0 + 10.0, 0.01)
	# fondo a la medida: 20 + 100 + 10 + 60 + 20 = 210 × (20 + 80 + 20) = 120
	assert_vector(AL.box(bg).size).is_equal_approx(Vector2(210, 120), Vector2(0.01, 0.01))
	# centrado en vertical: a (50 de alto) a 15 del borde interior
	assert_float(_top(a) - o.y).is_equal_approx(20.0 + 15.0, 0.01)

func test_columna() -> void:
	var a := _rect(Vector2(40, 30))
	var b := _rect(Vector2(40, 30), Vector2(300, 300))
	AL.make(_g, {"mode": "column", "gap": 8.0, "padding": 0.0})
	assert_float(_top(b) - _top(a)).is_equal_approx(38.0, 0.01)
	assert_float(_left(b)).is_equal_approx(_left(a), 0.01)

func test_rejilla() -> void:
	var r: Array = []
	for i in 5:
		r.append(_rect(Vector2(20, 20), Vector2(i * 7, i * 3)))
	AL.make(_g, {"mode": "grid", "columns": 2, "gap": 5.0, "padding": 0.0})
	assert_float(_left(r[1]) - _left(r[0])).is_equal_approx(25.0, 0.01)
	assert_float(_top(r[2]) - _top(r[0])).is_equal_approx(25.0, 0.01)
	assert_float(_left(r[2])).is_equal_approx(_left(r[0]), 0.01)
	assert_float(_top(r[4]) - _top(r[0])).is_equal_approx(50.0, 0.01)

func test_salto_de_linea() -> void:
	var r: Array = []
	for i in 4:
		r.append(_rect(Vector2(100, 20)))
	AL.make(_g, {"mode": "wrap", "wrap_width": 250.0, "gap": 10.0, "padding": 0.0})
	# caben 2 por línea (100 + 10 + 100 = 210 ≤ 250; el tercero no)
	assert_float(_top(r[1])).is_equal_approx(_top(r[0]), 0.01)
	assert_float(_top(r[2]) - _top(r[0])).is_equal_approx(30.0, 0.01)

func test_repartir_con_tamano_fijo() -> void:
	var bg := _rect(Vector2(300, 100))
	_g.move_child(bg, 0)
	var a := _rect(Vector2(50, 20))
	var b := _rect(Vector2(50, 20))
	AL.make(_g, {"mode": "row", "align": "space-between", "padding": 10.0, "auto": false}, bg)
	var o := AL.box(bg).position
	assert_float(_left(a) - o.x).is_equal_approx(10.0, 0.01)
	assert_float(AL.box(b).end.x - o.x).is_equal_approx(290.0, 0.01)
	assert_vector(AL.box(bg).size).is_equal_approx(Vector2(300, 100), Vector2(0.01, 0.01))

func test_recoloca_al_cambiar_un_hijo() -> void:
	var a := _rect(Vector2(100, 20))
	var b := _rect(Vector2(50, 20))
	AL.make(_g, {"mode": "row", "gap": 0.0, "padding": 0.0})
	var x0 := _left(b)
	a.size = Vector2(160, 20)
	AL.sync_now(get_tree())
	assert_float(_left(b) - x0).is_equal_approx(60.0, 0.01)

func test_guardar_y_abrir() -> void:
	_rect(Vector2(10, 10))
	AL.make(_g, {"mode": "grid", "columns": 4})
	var d: Dictionary = CS._serialize_element(_g)
	var n: Node2D = CS._element_from(d)
	CS._apply_transform(n, d)
	assert_bool(AL.is_layout(n)).is_true()
	assert_int(int(AL.params(n)["columns"])).is_equal(4)
	n.free()
