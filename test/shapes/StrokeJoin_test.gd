extends GdUnitTestSuite

## UX-08: uniones del trazo (inglete con límite → bisel, redonda, bisel).
## Geometría exacta, sin solapes (un trazo semitransparente no oscurece las
## esquinas), guardado de las propiedades de trazo de las figuras y
## exportación / importación SVG, PDF y EPS.

const SG = preload("res://script_gdscript/shapes/stroke_geom.gd")
const CS = preload("res://scripts/canvas/canvas_serializer.gd")
const VX = preload("res://script_gdscript/system/vector_export.gd")
const CANVAS := "res://scenes/canvas/canvas.tscn"

## Esquina en L de 90°: (0,0) → (100,0) → (100,100), grosor 20.
const L := [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)]
const W := 20.0

func _mesh(join: int, limit: float = 4.0, pts: Array = L) -> Dictionary:
	return SG.build(PackedVector2Array(pts), false, 0, W, 0, 0, PackedVector2Array(), 1.0, 1.0, join, limit)

func _area(m: Dictionary) -> float:
	var p: PackedVector2Array = m["points"]
	var idx: PackedInt32Array = m["indices"]
	var a := 0.0
	for i in range(0, idx.size(), 3):
		a += absf((p[idx[i + 1]] - p[idx[i]]).cross(p[idx[i + 2]] - p[idx[i]])) * 0.5
	return a

## Distancia máxima al vértice de los puntos de la malla en su entorno
## (los extremos de la línea quedan lejos y no cuentan).
func _max_dist(m: Dictionary, c: Vector2, near: float = 80.0) -> float:
	var d := 0.0
	for q in m["points"]:
		var e := (q as Vector2).distance_to(c)
		# solo el lado EXTERIOR de la esquina (el punto interior está a √2·h)
		if e < near and (q as Vector2).x >= c.x - 0.01 and (q as Vector2).y <= c.y + 0.01:
			d = maxf(d, e)
	return d

## Área exacta: dos rectángulos 100×20 (contando el cuadrado de la esquina
## interior una sola vez) + la pieza exterior de la unión.
func _expected(join_piece: float) -> float:
	var h := W * 0.5
	# tramo 1: x de 0 a 100, y de -10 a 10; tramo 2: x 90..110, y 0..100
	# unión de los dos sin la pieza exterior (esquina 100..110 × -10..0):
	var body := 100.0 * W + 100.0 * W - h * h   # el cuadrado interior 90..100×0..10 se cuenta una vez
	return body + join_piece

func test_miter_corner_is_square_tip() -> void:
	var m := _mesh(SG.JOIN_MITER)
	var h := W * 0.5
	assert_float(_area(m)).is_equal_approx(_expected(h * h), 0.5)
	# la punta del inglete es (110, -10)
	assert_float(_max_dist(m, Vector2(100, 0))).is_equal_approx(sqrt(2.0) * h, 0.01)

func test_bevel_corner_cuts_the_tip() -> void:
	var m := _mesh(SG.JOIN_BEVEL)
	var h := W * 0.5
	assert_float(_area(m)).is_equal_approx(_expected(h * h * 0.5), 0.5)
	assert_float(_max_dist(m, Vector2(100, 0))).is_less_equal(h * 1.0001 + 0.01)

func test_round_corner_is_quarter_circle() -> void:
	var m := _mesh(SG.JOIN_ROUND)
	var h := W * 0.5
	assert_float(_area(m)).is_equal_approx(_expected(PI * h * h * 0.25), 1.5)
	assert_float(_max_dist(m, Vector2(100, 0))).is_less_equal(h + 0.01)

func test_miter_limit_falls_back_to_bevel() -> void:
	# Giro muy cerrado (≈ 160°): ratio de inglete ≈ 5,8 > 4 → bisel.
	var sharp := [Vector2(0, 0), Vector2(100, 0), Vector2(0, 35)]
	var m4 := _mesh(SG.JOIN_MITER, 4.0, sharp)
	var bev := _mesh(SG.JOIN_BEVEL, 4.0, sharp)
	assert_float(_area(m4)).is_equal_approx(_area(bev), 0.01)
	# Con límite 10 sí hay punta (más área y más lejos del vértice).
	var m10 := _mesh(SG.JOIN_MITER, 10.0, sharp)
	assert_float(_area(m10)).is_greater(_area(bev) + 1.0)
	assert_float(_max_dist(m10, Vector2(100, 0))).is_greater(W * 2.0)

func test_no_overlap_on_closed_square() -> void:
	# Cuadrado cerrado 100×100: área exacta del anillo según la unión.
	var sq := [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	var h := W * 0.5
	var ring := 120.0 * 120.0 - 80.0 * 80.0
	var mm := SG.build(PackedVector2Array(sq), true, 0, W, 0, 0, PackedVector2Array(), 1.0, 1.0, SG.JOIN_MITER, 4.0)
	var mb := SG.build(PackedVector2Array(sq), true, 0, W, 0, 0, PackedVector2Array(), 1.0, 1.0, SG.JOIN_BEVEL, 4.0)
	var mr := SG.build(PackedVector2Array(sq), true, 0, W, 0, 0, PackedVector2Array(), 1.0, 1.0, SG.JOIN_ROUND, 4.0)
	assert_float(_area(mm)).is_equal_approx(ring, 0.5)
	assert_float(_area(mb)).is_equal_approx(ring - 4.0 * h * h * 0.5, 0.5)
	assert_float(_area(mr)).is_equal_approx(ring - 4.0 * (h * h - PI * h * h * 0.25), 2.0)

func test_shape_and_path_properties() -> void:
	var r := VectorRectangle.new()
	auto_free(r)
	assert_int(r.stroke_join).is_equal(0)
	assert_float(r.stroke_miter_limit).is_equal(4.0)
	r.stroke_join = 7
	assert_int(r.stroke_join).is_equal(2)
	r.stroke_miter_limit = 0.2
	assert_float(r.stroke_miter_limit).is_equal(1.0)
	var p := VectorPath.new()
	auto_free(p)
	assert_bool("stroke_join" in p and "stroke_miter_limit" in p).is_true()

func test_shape_stroke_survives_save_and_reload() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	auto_free(s)
	var r := VectorRectangle.new()
	r.size = Vector2(80, 40)
	r.stroke_width = 6.0
	r.stroke_style = 1
	r.stroke_align = 2
	r.stroke_dash_len = 20.0
	r.stroke_dash_gap = 5.0
	r.stroke_join = 2
	var d := CS._serialize_element(r)
	var back = CS._element_from(d)
	auto_free(r)
	auto_free(back)
	assert_int(back.stroke_style).is_equal(1)
	assert_int(back.stroke_align).is_equal(2)
	assert_float(back.stroke_dash_len).is_equal(20.0)
	assert_float(back.stroke_dash_gap).is_equal(5.0)
	assert_int(back.stroke_join).is_equal(2)
	var p := VectorPath.new()
	var c := Curve2D.new()
	for q in L:
		c.add_point(q)
	p.curve = c
	p.stroke_join = 1
	p.stroke_miter_limit = 9.0
	var dp := CS._serialize_element(p)
	var bp = CS._element_from(dp)
	auto_free(p)
	auto_free(bp)
	assert_int(int(bp.stroke_join)).is_equal(1)
	assert_float(float(bp.stroke_miter_limit)).is_equal(9.0)

func test_export_writes_each_join() -> void:
	var it := {"join": 2, "miter": 4.0}
	assert_str(VX._svg_join(it)).contains('stroke-linejoin="bevel"')
	it = {"join": 0, "miter": 7.5}
	assert_str(VX._svg_join(it)).contains('stroke-linejoin="miter"').contains('stroke-miterlimit="7.5"')
	var r := VectorRectangle.new()
	auto_free(r)
	r.stroke_join = 1
	var pit := {}
	VX._add_join(pit, r)
	assert_int(int(pit["join"])).is_equal(1)

# ── UX-18: desfase, patrón propio y trazo detrás del relleno ────────────────
func _dashed(offset: float, pattern: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(200, 0)])
	return SG.build(line, false, 1, 4.0, 0, 0, PackedVector2Array(), 20.0, 20.0, 0, 4.0, offset, pattern)

func _min_x(m: Dictionary) -> float:
	var x := INF
	for q in m["points"]:
		x = minf(x, (q as Vector2).x)
	return x

func test_dash_offset_moves_the_pattern() -> void:
	var a := _dashed(0.0)
	var b := _dashed(10.0)
	# Sin desfase el primer guion empieza en 0; con 10 px, el primer guion
	# visible es medio guion (empieza en 0 pero acaba 10 px antes).
	assert_float(_min_x(a)).is_equal_approx(0.0, 0.01)
	assert_float(_area(b)).is_less(_area(a))
	var c := _dashed(40.0)   # un periodo entero: igual que sin desfase
	assert_float(_area(c)).is_equal_approx(_area(a), 0.01)

func test_custom_dash_pattern() -> void:
	var plain := _dashed(0.0)
	var custom := _dashed(0.0, PackedFloat32Array([30.0, 5.0, 5.0, 5.0]))
	# Más tinta: 35 de cada 45 frente a 20 de cada 40.
	assert_float(_area(custom)).is_greater(_area(plain) * 1.3)
	assert_str(SG.pattern_text(SG.parse_pattern("12, 4 2 4"))).is_equal("12 4 2 4")
	assert_int(SG.custom_pattern(PackedFloat32Array([6.0]), 12.0, 8.0).size()).is_equal(2)

func test_new_stroke_props_save_and_export() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	auto_free(s)
	var r := VectorRectangle.new()
	r.size = Vector2(80, 40)
	r.stroke_style = 1
	r.stroke_dash_offset = 7.0
	r.stroke_dash_pattern = PackedFloat32Array([10.0, 3.0, 2.0, 3.0])
	r.stroke_behind_fill = true
	var back = CS._element_from(CS._serialize_element(r))
	auto_free(r)
	auto_free(back)
	assert_float(back.stroke_dash_offset).is_equal(7.0)
	assert_str(SG.pattern_text(back.stroke_dash_pattern)).is_equal("10 3 2 3")
	assert_bool(back.stroke_behind_fill).is_true()
	var it := {"stroke": Color.BLACK}
	VX._add_dash(it, r, 1.0)
	assert_str(VX._dash_list(it)).is_equal("10 3 2 3")
	assert_float(float(it["dash_offset"])).is_equal(7.0)
	assert_bool(it.get("behind", false)).is_true()
