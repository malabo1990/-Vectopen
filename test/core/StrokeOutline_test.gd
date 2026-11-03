extends GdUnitTestSuite
## VGSE fase 1 — «Convertir trazo en contorno»: el trazo de pincel pasa a una
## figura rellena con su misma forma (cruces rellenos, lazos huecos, remates
## redondos, anchura por presión), con un solo paso de deshacer.
const CANVAS := "res://scenes/canvas/canvas.tscn"
const SG = preload("res://script_gdscript/shapes/stroke_geom.gd")
const Render = preload("res://script_gdscript/shapes/brush_stroke_render.gd")
var _api: VectopenAPI = null
var _ab: Node2D = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	_ab = _api.artboard()
	HistoryManager.clear()

func _inside(polys: Array, q: Vector2) -> bool:
	var c := 0
	for p in polys:
		if Geometry2D.is_point_in_polygon(q, p):
			c += 1
	return c % 2 == 1

func _eight(width: float) -> Line2D:
	var l := Line2D.new()
	l.name = "Dibujo"
	l.width = width
	l.default_color = Color(0.2, 0.4, 0.9, 1.0)
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	var pts := PackedVector2Array()
	for i in 200:
		var t := i / 199.0 * TAU
		pts.append(Vector2(300, 300) + Vector2(sin(t) * 110.0, sin(t * 2.0) * 45.0))
	l.points = pts
	_ab.add_child(l)
	Render.attach(l)
	return l

func test_geometria_recta_con_remates() -> void:
	var r := SG.outline(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), PackedFloat32Array([5, 5]), 1, 1)
	assert_int(r.size()).is_equal(1)
	assert_bool(_inside(r, Vector2(50, 0))).is_true()
	assert_bool(_inside(r, Vector2(50, 7))).is_false()
	assert_bool(_inside(r, Vector2(103, 0))).is_true()    # remate redondo
	assert_bool(_inside(r, Vector2(106, 0))).is_false()
	var plano := SG.outline(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), PackedFloat32Array([5, 5]), 0, 0)
	assert_bool(_inside(plano, Vector2(103, 0))).is_false()

func test_geometria_ocho_cruce_lleno_y_lazos_huecos() -> void:
	var l := _eight(16.0)
	var ax: Array = Render.centerline(l)
	var r := SG.outline(ax[0], ax[1], 1, 1)
	assert_bool(_inside(r, Vector2(300, 300))).is_true()    # cruce
	assert_bool(_inside(r, Vector2(360, 300))).is_false()   # dentro del lazo: hueco
	assert_bool(_inside(r, Vector2(410, 300))).is_true()    # cuerpo
	assert_bool(_inside(r, Vector2(425, 300))).is_false()

func test_anchura_variable_sigue_la_presion() -> void:
	var pts := PackedVector2Array()
	var half := PackedFloat32Array()
	for i in 101:
		pts.append(Vector2(i * 2.0, 0))
		half.append(1.0 + 9.0 * sin(i / 100.0 * PI))   # fino → grueso → fino
	var r := SG.outline(pts, half, 1, 1)
	assert_bool(_inside(r, Vector2(100, 9))).is_true()    # centro grueso
	assert_bool(_inside(r, Vector2(10, 4))).is_false()    # punta fina

func test_api_convierte_y_deshace() -> void:
	var l := _eight(16.0)
	var n0 := _ab.get_child_count()
	var p = _api.stroke_to_outline(l)
	assert_object(p).is_not_null()
	assert_bool(p is VectorPath).is_true()
	assert_bool(p.closed).is_true()
	assert_that(p.fill_color).is_equal(l.default_color)
	assert_float(p.stroke_width).is_equal(0.0)
	assert_int(p.subpaths.size()).is_greater_equal(2)     # los dos huecos del ocho
	assert_object(l.get_parent()).is_null()
	assert_int(_ab.get_child_count()).is_equal(n0)
	# Figura editable: pocos nodos Bézier, no miles de puntos.
	var nodes: int = p.curve.point_count
	for c in p.subpaths:
		nodes += c.point_count
	assert_int(nodes).is_less(120)
	HistoryManager.undo()
	assert_object(l.get_parent()).is_equal(_ab)
	assert_object(p.get_parent()).is_null()
	HistoryManager.redo()
	assert_object(p.get_parent()).is_equal(_ab)

func test_no_convierte_lo_que_no_es_trazo() -> void:
	var r := _api.add_rect(Vector2(10, 10), Vector2(50, 50))
	assert_object(_api.stroke_to_outline(r)).is_null()

