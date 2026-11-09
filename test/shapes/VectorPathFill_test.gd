extends GdUnitTestSuite
## Relleno de trazados cerrados que se CRUZAN consigo mismos: se rellenan
## todas las zonas cerradas (antes solo las recorridas en un sentido: en una
## figura como la del usuario faltaba el lazo grande de la izquierda).

const VP = preload("res://script_gdscript/shapes/VectorPath.gd")

func _covered(polys: Array, q: Vector2) -> bool:
	for p in polys:
		if Geometry2D.is_point_in_polygon(q, p):
			return true
	return false

func _area(polys: Array) -> float:
	var a := 0.0
	for p in polys:
		for t in range(0, Geometry2D.triangulate_polygon(p).size(), 3):
			var idx := Geometry2D.triangulate_polygon(p)
			var p0: Vector2 = p[idx[t]]
			a += absf((p[idx[t + 1]] - p0).cross(p[idx[t + 2]] - p0)) * 0.5
	return a

## La figura del usuario: línea arriba, triángulo a la derecha, subida en
## pico y lazo a la izquierda (tres zonas, con sentidos de giro distintos).
func test_figura_que_se_cruza_rellena_todas_las_zonas() -> void:
	var pts := PackedVector2Array([
		Vector2(227, 163), Vector2(550, 205), Vector2(752, 253), Vector2(570, 390),
		Vector2(390, 90), Vector2(243, 511), Vector2(222, 420)])
	var polys: Array = VP.fill_polygons(pts)
	assert_bool(_covered(polys, Vector2(620, 270))).is_true()   # triángulo derecho
	assert_bool(_covered(polys, Vector2(260, 300))).is_true()   # lazo izquierdo
	assert_bool(_covered(polys, Vector2(395, 150))).is_true()   # pico de arriba
	assert_bool(_covered(polys, Vector2(700, 400))).is_false()  # fuera

func test_ocho_rellena_los_dos_lazos() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 100), Vector2(100, 0), Vector2(0, 100)])
	var polys: Array = VP.fill_polygons(pts)
	assert_bool(_covered(polys, Vector2(10, 50))).is_true()
	assert_bool(_covered(polys, Vector2(90, 50))).is_true()

func test_figura_simple_sigue_igual() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)])
	var polys: Array = VP.fill_polygons(sq)
	assert_int(polys.size()).is_equal(1)
	assert_float(_area(polys)).is_equal_approx(2500.0, 1.0)
	var rev := sq.duplicate()
	rev.reverse()
	assert_float(_area(VP.fill_polygons(rev))).is_equal_approx(2500.0, 1.0)
