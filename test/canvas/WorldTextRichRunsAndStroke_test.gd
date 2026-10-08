extends GdUnitTestSuite

## Test Suite para Fase 1: Motor visual vectorial de texto y trazo (Stroke)
## Verifica que WorldTextLabel soporte colores por letra (rich_runs)
## y trazo/borde vectorial (stroke) a cualquier nivel de zoom.

func _nuevo_label(base: int = 24, texto: String = "Vectopen") -> WorldTextLabel:
	var l := WorldTextLabel.new()
	l.base_font_size = base
	l.text = texto
	l.add_theme_font_size_override("font_size", base)
	add_child(l)
	auto_free(l)
	return l

func test_rich_runs_color_per_letter() -> void:
	var l := _nuevo_label(24, "ABCDEF")
	await get_tree().process_frame

	# Inicialmente sin runs ricos:
	assert_bool(l.has_rich_runs()).is_false()
	assert_float(l.visible_ratio).is_equal(1.0)

	# Asignar 2 runs: 3 letras rojas, 3 letras azules
	var runs := [
		{"length": 3, "color": Color.RED, "bold": false, "italic": false, "underline": false},
		{"length": 3, "color": Color.BLUE, "bold": false, "italic": false, "underline": false}
	]
	l.set_rich_runs(runs)
	await get_tree().process_frame

	assert_bool(l.has_rich_runs()).is_true()
	assert_bool(l.is_vector_override_active()).is_true()
	# El bitmap plano del Label queda oculto para mostrar el render vectorial
	assert_float(l.visible_ratio).is_equal(0.0)

	var polys := l._get_triangle_polys()
	assert_int(polys.size()).is_greater(0)

	# Verificar que hay polígonos etiquetados para el run 0 y para el run 1
	var has_run_0 := false
	var has_run_1 := false
	for p in polys:
		if int(p.get("run", -1)) == 0:
			has_run_0 = true
		elif int(p.get("run", -1)) == 1:
			has_run_1 = true
	assert_bool(has_run_0).is_true()
	assert_bool(has_run_1).is_true()

func test_stroke_properties_and_rendering() -> void:
	var l := _nuevo_label(32, "StrokeTest")
	await get_tree().process_frame

	assert_bool(l.has_stroke()).is_false()

	# Configurar trazo
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.YELLOW)
	l.apply_stroke_meta()
	await get_tree().process_frame

	assert_bool(l.has_stroke()).is_true()
	assert_float(l.stroke_width()).is_equal(4.0)
	assert_bool(l.stroke_color().is_equal_approx(Color.YELLOW)).is_true()
	assert_bool(l.is_vector_override_active()).is_true()
	assert_float(l.visible_ratio).is_equal(0.0)

	var stroke_polys := l._get_stroke_polys()
	assert_int(stroke_polys.size()).is_greater(0)
	var first_entry: Dictionary = stroke_polys[0]
	assert_bool(first_entry.has("contours")).is_true()
	var contours: Array = first_entry["contours"]
	assert_int(contours.size()).is_greater(0)

func test_runs_of_and_merge_runs_with_stroke() -> void:
	var shape := Node2D.new()
	shape.set_meta("stroke_width", 3.0)
	shape.set_meta("stroke_color", Color.GREEN)
	shape.set_meta("text_color", Color.BLACK)
	auto_free(shape)

	var runs := WorldTextLabel.runs_of(shape, 8)
	assert_int(runs.size()).is_equal(1)
	assert_float(float(runs[0].get("stroke_width", 0.0))).is_equal(3.0)
	assert_bool((runs[0].get("stroke_color", Color.BLACK) as Color).is_equal_approx(Color.GREEN)).is_true()

	# Merge runs con distinto stroke no deben fusionarse
	var separate_runs := [
		{"length": 4, "color": Color.BLACK, "stroke_width": 2.0, "stroke_color": Color.RED, "bold": false, "italic": false, "underline": false},
		{"length": 4, "color": Color.BLACK, "stroke_width": 4.0, "stroke_color": Color.BLUE, "bold": false, "italic": false, "underline": false}
	]
	var merged := WorldTextLabel.merge_runs(separate_runs)
	assert_int(merged.size()).is_equal(2)

	# Merge runs con mismo stroke deben fusionarse
	var same_runs := [
		{"length": 4, "color": Color.BLACK, "stroke_width": 2.0, "stroke_color": Color.RED, "bold": false, "italic": false, "underline": false},
		{"length": 4, "color": Color.BLACK, "stroke_width": 2.0, "stroke_color": Color.RED, "bold": false, "italic": false, "underline": false}
	]
	var merged_same := WorldTextLabel.merge_runs(same_runs)
	assert_int(merged_same.size()).is_equal(1)
	assert_int(int(merged_same[0]["length"])).is_equal(8)

func test_to_svg_with_stroke_and_tspans() -> void:
	var l := _nuevo_label(20, "SVGText")
	await get_tree().process_frame

	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.apply_stroke_meta()

	var svg_simple := l.to_svg()
	assert_bool(svg_simple.contains('stroke="#000000"')).is_true()
	assert_bool(svg_simple.contains('stroke-width="2.000000"')).is_true()
	assert_bool(svg_simple.contains('paint-order="stroke fill"')).is_true()

	# Probar con múltiples runs
	var runs := [
		{"length": 3, "color": Color.RED, "bold": true, "italic": false, "underline": false, "stroke_width": 1.0, "stroke_color": Color.BLACK},
		{"length": 4, "color": Color.BLUE, "bold": false, "italic": true, "underline": false, "stroke_width": 0.0, "stroke_color": Color.BLACK}
	]
	l.set_rich_runs(runs)
	var svg_rich := l.to_svg()
	assert_bool(svg_rich.contains("<tspan")).is_true()
	assert_bool(svg_rich.contains('font-weight="bold"')).is_true()
	assert_bool(svg_rich.contains('font-style="italic"')).is_true()
