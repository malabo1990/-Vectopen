extends GdUnitTestSuite
## Fusión (Blend, informe §3): intermedios de forma y color, pasos o
## distancia, se rehace al cambiar un extremo, expandir, guardar/abrir.

const Blend = preload("res://script_gdscript/shapes/blend.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

var _layer: Node2D

func before_test() -> void:
	_layer = auto_free(Node2D.new())
	add_child(_layer)

func _sq(pos: Vector2, c: Color) -> VectorRectangle:
	var r := VectorRectangle.new()
	r.size = Vector2(40, 40)
	r.position = pos
	r.fill_color = c
	r.stroke_width = 0.0
	_layer.add_child(r)
	return r

func _steps(g: Node) -> Array:
	return g.get_children().filter(func(c) -> bool: return c.has_meta(Blend.STEP_META))

func test_pasos_y_color_intermedio() -> void:
	var a := _sq(Vector2(0, 0), Color.RED)
	var b := _sq(Vector2(400, 0), Color.BLUE)
	var g := Blend.make(a, b, {"steps": 3})
	var st := _steps(g)
	assert_int(st.size()).is_equal(3)
	var mid: VectorPath = st[1]
	assert_bool((mid.fill_color as Color).is_equal_approx(Color.RED.lerp(Color.BLUE, 0.5))).is_true()
	var c := Blend._centroid(Blend.outline(mid))
	assert_float(c.x).is_equal_approx(200.0, 1.0)
	# orden: A, pasos, B
	assert_int(a.get_index()).is_less(st[0].get_index())
	assert_int(st[2].get_index()).is_less(b.get_index())

func test_cuadrado_a_circulo_tiene_forma_intermedia() -> void:
	var a := _sq(Vector2(0, 0), Color.BLACK)
	var cir := VectorCircle.new()
	cir.size = Vector2(40, 40)
	cir.position = Vector2(300, 0)
	_layer.add_child(cir)
	var g := Blend.make(a, cir, {"steps": 1})
	var mid: VectorPath = _steps(g)[0]
	var pts := Blend.outline(mid)
	var area := absf(Blend._area(pts))
	# entre el círculo (1257) y el cuadrado (1600)
	assert_float(area).is_between(1257.0, 1600.0)

func test_modo_distancia() -> void:
	var a := _sq(Vector2(0, 0), Color.BLACK)
	var b := _sq(Vector2(500, 0), Color.BLACK)
	var g := Blend.make(a, b, {"mode": "distance", "spacing": 50.0})
	assert_int(_steps(g).size()).is_equal(9)   # 500 / 50 − 1

func test_se_rehace_al_cambiar_un_extremo() -> void:
	var a := _sq(Vector2(0, 0), Color.RED)
	var b := _sq(Vector2(400, 0), Color.BLUE)
	var g := Blend.make(a, b, {"steps": 1})
	a.fill_color = Color.GREEN
	assert_int(Blend.sync_now()).is_equal(1)
	var mid: VectorPath = _steps(g)[0]
	assert_bool((mid.fill_color as Color).is_equal_approx(Color.GREEN.lerp(Color.BLUE, 0.5))).is_true()
	assert_int(Blend.sync_now()).is_equal(0)   # sin cambios, no rehace

func test_expandir_deja_figuras_normales() -> void:
	var g := Blend.make(_sq(Vector2(0, 0), Color.RED), _sq(Vector2(400, 0), Color.BLUE), {"steps": 2})
	Blend.expand(g)
	assert_bool(Blend.is_blend(g)).is_false()
	for c in g.get_children():
		assert_bool(c.has_meta(Blend.STEP_META) or c.has_meta(Blend.END_META)).is_false()

func test_guardar_y_abrir() -> void:
	var g := Blend.make(_sq(Vector2(0, 0), Color.RED), _sq(Vector2(400, 0), Color.BLUE), {"steps": 2})
	var d: Dictionary = CS._serialize_element(g)
	var n: Node2D = CS._element_from(d)
	CS._apply_transform(n, d)
	assert_bool(Blend.is_blend(n)).is_true()
	assert_int(int(Blend.params(n)["steps"])).is_equal(2)
	n.free()

func test_a_lo_largo_de_una_guia() -> void:
	var a := _sq(Vector2(0, 0), Color.RED)
	var b := _sq(Vector2(400, 0), Color.BLUE)
	var spine := VectorPath.new()
	var cv := Curve2D.new()
	cv.add_point(Vector2(0, 0))
	cv.add_point(Vector2(200, 300))
	cv.add_point(Vector2(400, 0))
	spine.curve = cv
	spine.closed = false
	_layer.add_child(spine)
	var g := Blend.make(a, b, {"steps": 1}, spine)
	var mid: VectorPath = _steps(g)[0]
	var c := Blend._centroid(Blend.outline(mid))
	# a mitad de la guía (el vértice de abajo), no en la recta entre A y B
	assert_float(c.x).is_equal_approx(200.0, 2.0)
	assert_float(c.y).is_equal_approx(300.0, 2.0)
