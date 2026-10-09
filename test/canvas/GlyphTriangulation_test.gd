extends GdUnitTestSuite

## Cada glifo del overlay vectorial debe triangularse y conservar sus huecos.
## Regresión: el puente hueco→contorno buscaba un VÉRTICE a <2 px de altura;
## con el teselado adaptativo la "a" y la "e" (contorno exterior con tramos
## rectos) quedaban sin dibujar en modo GDScript con sangría/proporciones.

const CHARSET := "ABCDEFGHIJKLMNÑOPQRSTUVWXYZabcdefghijklmnñopqrstuvwxyz0123456789áéíóúüÁÉÍÓÚ&@%$#?!¿¡()[]{}/\\.,;:-_+=*"

func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var j := (i + 1) % pts.size()
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return absf(a) * 0.5

## Área "tinta" esperada: contornos de profundidad par suman, impar restan.
func _ink_area(contours: Array[PackedVector2Array]) -> float:
	var total := 0.0
	for i in contours.size():
		var depth := 0
		for j in contours.size():
			if i != j and Geometry2D.is_point_in_polygon(contours[i][0], contours[j]):
				depth += 1
		total += _area(contours[i]) * (1.0 if depth % 2 == 0 else -1.0)
	return total

func _check_style(weight: int, italic: bool) -> void:
	var host: Node2D = auto_free(Node2D.new())
	host.set_meta("font_weight", weight)
	host.set_meta("font_italic", italic)
	add_child(host)
	var lbl := WorldTextLabel.new()
	lbl.name = "DisplayLabel"
	host.add_child(lbl)
	lbl.base_font_size = 24
	var fails: Array[String] = []
	for ch in CHARSET:
		lbl.text = ch
		var outline: Node2D = lbl._build_outline_at(WorldTextLabel.VECTOR_FONT)
		if outline == null:
			fails.append("%s sin contorno" % ch)
			continue
		var got := 0.0
		var want := 0.0
		var any_poly := false
		for g in outline.get_children():
			var contours: Array[PackedVector2Array] = lbl._outline_polygons(g)
			if contours.is_empty():
				continue
			var polys: Array = lbl._triangulate_contours(contours)
			any_poly = any_poly or not polys.is_empty()
			for p in polys:
				got += _area(p)
			want += _ink_area(contours)
		outline.free()
		if not any_poly:
			fails.append("%s sin polígonos" % ch)
		elif want > 1.0 and absf(got - want) / want > 0.03:
			fails.append("%s área %.0f ≠ %.0f (hueco perdido/relleno)" % [ch, got, want])
	assert_array(fails).override_failure_message("peso %d cursiva %s: %s" % [weight, italic, fails]).is_empty()

func test_todos_los_glifos_regular() -> void:
	_check_style(400, false)

func test_todos_los_glifos_negrita() -> void:
	_check_style(700, false)

func test_todos_los_glifos_cursiva() -> void:
	_check_style(400, true)
