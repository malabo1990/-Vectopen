extends GdUnitTestSuite

## Importar PDF, AI (moderno = PDF) y EPS (también el de Illustrator antiguo)
## → trazados editables con curvas Bézier reales, colores, grosor y discontinuo.
## Los archivos de test/fixtures/import salen de sample.svg (Inkscape/cairo) y
## de un EPS escrito a mano con los operadores cortos de Illustrator 8.

const PsImport = preload("res://script_gdscript/system/ps_import.gd")
const SvgImport = preload("res://script_gdscript/system/svg_import.gd")
const DIR := "res://test/fixtures/import/"

func _near(a: Variant, b: Color, tol := 0.08) -> bool:
	return a is Color and absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol

func _find(items: Array, pred: Callable) -> Dictionary:
	for it in items:
		if pred.call(it):
			return it
	return {}

func _bounds(it: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for sub in it["subs"]:
		for p in sub["anchors"]:
			if first:
				r = Rect2(p, Vector2.ZERO); first = false
			else:
				r = r.expand(p)
	return r

func _has_curves(it: Dictionary) -> bool:
	for sub in it["subs"]:
		for v in sub["outs"]:
			if (v as Vector2).length() > 0.5:
				return true
	return false

func _check_sample(path: String, page_sized := true) -> void:
	var d := PsImport.parse_file(path)
	var items: Array = d["items"]
	assert_int(items.size()).override_failure_message("%s: sin objetos" % path).is_greater_equal(5)
	# PDF / AI: la página entera (400×300 px = 300×225 pt). EPS: la caja del
	# CONTENIDO (así funciona el formato), así que solo se comparan tamaños.
	var k := 0.75
	if page_sized:
		assert_vector(d["size"]).is_equal_approx(Vector2(300, 225), Vector2(0.5, 0.5))
	var red := _find(items, func(it): return _near(it["fill"], Color("#e5484d")))
	assert_bool(red.is_empty()).override_failure_message("%s: falta el rectángulo rojo" % path).is_false()
	var rb := _bounds(red)
	if page_sized:
		assert_float(rb.position.x).is_equal_approx(20 * k, 1.5)
		assert_float(rb.position.y).is_equal_approx(20 * k, 1.5)
	assert_float(rb.size.x).is_equal_approx(120 * k, 1.5)
	assert_float(rb.size.y).is_equal_approx(80 * k, 1.5)
	var blue := _find(items, func(it): return _near(it["fill"], Color("#3e63dd")))
	assert_bool(blue.is_empty()).is_false()
	assert_bool(_has_curves(blue)).override_failure_message("%s: el círculo perdió las curvas" % path).is_true()
	var green := _find(items, func(it): return _near(it["stroke"], Color("#30a46c")) and it["fill"] == null)
	assert_bool(green.is_empty()).override_failure_message("%s: falta la curva verde" % path).is_false()
	assert_float(float(green["width"])).is_equal_approx(6 * k, 0.6)
	assert_bool(_has_curves(green)).is_true()
	var orange := _find(items, func(it): return _near(it["fill"], Color("#ffb020")))
	assert_bool(orange.is_empty()).is_false()
	var dashed := _find(items, func(it): return it["dash"] != null)
	assert_bool(dashed.is_empty()).override_failure_message("%s: se perdió el discontinuo" % path).is_false()
	# Se construyen nodos editables.
	var g := SvgImport.build(d, "Importado")
	assert_int(g.get_child_count()).is_equal(items.size())
	g.free()

func test_importar_pdf() -> void:
	_check_sample(DIR + "sample.pdf")

func test_importar_ai_moderno() -> void:
	_check_sample(DIR + "sample.ai")

func test_importar_eps() -> void:
	_check_sample(DIR + "sample.eps", false)

func test_importar_eps_de_illustrator_antiguo() -> void:
	var d := PsImport.parse_file(DIR + "illustrator_old.eps")
	var items: Array = d["items"]
	assert_int(items.size()).is_equal(2)
	# Rectángulo: relleno rojo (Xa), trazo negro (K) de 2 px.
	assert_bool(_near(items[0]["fill"], Color(0.9, 0.1, 0.1))).is_true()
	assert_bool(_near(items[0]["stroke"], Color.BLACK)).is_true()
	assert_float(float(items[0]["width"])).is_equal_approx(2.0, 0.01)
	var rb := _bounds(items[0])
	assert_vector(rb.position).is_equal_approx(Vector2(10, 10), Vector2(0.01, 0.01))
	assert_vector(rb.size).is_equal_approx(Vector2(80, 80), Vector2(0.01, 0.01))
	# Forma curva con v / y: amarillo CMYK, con curvas.
	assert_bool(_near(items[1]["fill"], Color(1, 1, 0))).is_true()
	assert_bool(_has_curves(items[1])).is_true()

func test_archivo_vacio_o_raro_no_rompe() -> void:
	var d := PsImport.parse_bytes("hola, esto no es un EPS".to_utf8_buffer())
	assert_int((d["items"] as Array).size()).is_equal(0)
	var d2 := PsImport.parse_bytes("%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF".to_utf8_buffer())
	assert_int((d2["items"] as Array).size()).is_equal(0)
	assert_int((d2["warnings"] as Array).size()).is_greater(0)


## Integración: importar un .ai desde la app (ImportExportManager) crea un
## grupo de trazados en la mesa de trabajo.
func test_import_any_ai_crea_trazados_en_el_artboard() -> void:
	var s: Node2D = load("res://scenes/canvas/canvas.tscn").instantiate()
	add_child(s)
	auto_free(s)
	await get_tree().process_frame
	var ab: Node2D = null
	for ch in s.get_node("ArtboardsContainer").get_children():
		if ch is ArtboardEditor:
			ab = ch
			break
	assert_object(ab).is_not_null()
	var iem = get_tree().root.get_node("ImportExportManager")
	var res: Dictionary = iem.import_any(ProjectSettings.globalize_path(DIR + "sample.ai"), ab)
	assert_bool(bool(res.get("ok", false))).override_failure_message(str(res)).is_true()
	var g: Node = res.get("node")
	assert_object(g).is_not_null()
	assert_int(g.get_child_count()).is_equal(5)
