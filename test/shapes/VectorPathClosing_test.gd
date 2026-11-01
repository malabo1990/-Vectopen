extends GdUnitTestSuite

## Un trazado cerrado se dibuja con su tramo de cierre CURVO (antes se cerraba
## con una recta y a un círculo de 4 curvas le faltaba un cuarto).

const VectorPathScript = preload("res://script_gdscript/shapes/VectorPath.gd")

func _circle(r: float) -> Curve2D:
	var k := 0.5522848 * r
	var c := Curve2D.new()
	c.add_point(Vector2(r, 0), Vector2(0, -k), Vector2(0, k))
	c.add_point(Vector2(0, r), Vector2(k, 0), Vector2(-k, 0))
	c.add_point(Vector2(-r, 0), Vector2(0, k), Vector2(0, -k))
	c.add_point(Vector2(0, -r), Vector2(-k, 0), Vector2(k, 0))
	return c

func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5

func test_circulo_cerrado_completo() -> void:
	var pts: PackedVector2Array = VectorPathScript.closed_points(_circle(100.0))
	assert_float(_area(pts)).is_equal_approx(PI * 100.0 * 100.0, 300.0)

func test_cierre_recto_no_cambia() -> void:
	var c := Curve2D.new()
	for p in [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]:
		c.add_point(p)
	var pts: PackedVector2Array = VectorPathScript.closed_points(c)
	assert_int(pts.size()).is_equal(3)
