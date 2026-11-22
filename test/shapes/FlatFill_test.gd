extends GdUnitTestSuite
## Relleno ligero (VAL-39): rectángulo alineado → draw_rect; resto →
## triángulos; contorno que se cruza → vuelve a draw_colored_polygon.

const FF = preload("res://script_gdscript/shapes/flat_fill.gd")

func test_reconoce_rectangulos_alineados() -> void:
	assert_bool(FF.is_axis_rect(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 5), Vector2(0, 5)]))).is_true()
	assert_bool(FF.is_axis_rect(PackedVector2Array([Vector2(0, 0), Vector2(10, 2), Vector2(10, 5), Vector2(0, 5)]))).is_false()
	assert_bool(FF.is_axis_rect(PackedVector2Array([Vector2(5, 0), Vector2(10, 5), Vector2(5, 10), Vector2(0, 5)]))).is_false()

func test_dibuja_sin_errores_cualquier_forma() -> void:
	var n := Node2D.new()
	add_child(n)
	n.draw.connect(func() -> void:
		FF.draw(n, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 5), Vector2(0, 5)]), Color.RED)
		FF.draw(n, PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(10, 15)]), Color.BLUE)
		FF.draw(n, PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)]), Color.GREEN)
		FF.draw(n, PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]), Color.BLACK))
	n.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(n)).is_true()
	n.queue_free()

## Contorno que se cruza (como dos esquinas en zigzag que se pisan): se limpia
## en trozos simples que sí se pueden rellenar.
func test_contorno_que_se_cruza_se_limpia() -> void:
	var bowtie := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	assert_int(Geometry2D.triangulate_polygon(bowtie).size()).is_equal(0)
	var parts: Array = FF.simple_polys(bowtie)
	assert_bool(parts.is_empty()).is_false()
	for p in parts:
		assert_int(Geometry2D.triangulate_polygon(p).size()).is_greater_equal(3)

## Rectángulos estrechos con esquinas en zigzag / sierra y mucho redondeo:
## su contorno siempre da trozos rellenables (antes el relleno desaparecía).
func test_esquinas_que_se_pisan_siempre_se_rellenan() -> void:
	var R = load("res://script_gdscript/shapes/VectorRectangle.gd")
	for st in [2, 3, 4, 5]:
		for sz in [Vector2(228, 123), Vector2(80, 220), Vector2(300, 40)]:
			var r = R.new()
			r.size = sz
			r.corner_radius = minf(sz.x, sz.y) * 0.5
			r.corner_style = st
			var parts: Array = FF.triangulable_polys(r.get_effect_points())
			assert_bool(parts.is_empty()).override_failure_message("estilo %d %s sin relleno" % [st, sz]).is_false()
			r.free()
