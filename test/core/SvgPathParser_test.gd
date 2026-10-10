extends GdUnitTestSuite

## Fixture real: recorte exacto de la salida de vtracer para
## realtime_stroke_test.png (capturado corriendo el GDExtension de verdad),
## no un ejemplo inventado a mano. 5 anchors: M + 4 curvas C, la última
## termina donde empezó (0,0) — caso real de subtrazado cerrado redundante.
const SAMPLE_SVG := '<?xml version="1.0" encoding="UTF-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="1920" height="1009">
<path d="M0 0 C92.07 0 184.14 0 279 0 C279 181.83 279 363.66 279 551 C186.93 551 94.86 551 0 551 C0 369.17 0 187.34 0 0 Z " fill="#F9F9FB" transform="translate(17,412)"/>
</svg>'

func test_parse_document_extrae_d_fill_y_translate() -> void:
	var paths := SvgPathParser.parse_document(SAMPLE_SVG)
	assert_int(paths.size()).is_equal(1)
	var p: Dictionary = paths[0]
	assert_that(p.fill).is_equal(Color("#F9F9FB"))
	assert_that(p.translate).is_equal(Vector2(17, 412))
	assert_int(p.subpaths.size()).is_equal(1)

func test_d_to_subpaths_produce_anchors_y_handles_correctos() -> void:
	var d := "M0 0 C92.07 0 184.14 0 279 0 C279 181.83 279 363.66 279 551 C186.93 551 94.86 551 0 551 C0 369.17 0 187.34 0 0 Z "
	var subpaths := SvgPathParser.d_to_subpaths(d)
	assert_int(subpaths.size()).is_equal(1)

	var sub: Dictionary = subpaths[0]
	assert_bool(sub.closed).is_true()

	var anchors: PackedVector2Array = sub.anchors
	assert_int(anchors.size()).is_equal(5)
	assert_vector(anchors[0]).is_equal(Vector2(0, 0))
	assert_vector(anchors[1]).is_equal(Vector2(279, 0))
	assert_vector(anchors[4]).is_equal(Vector2(0, 0))

	var outs: PackedVector2Array = sub.outs
	# out del primer anchor = primer punto de control (92.07,0) - anchor(0,0)
	assert_vector(outs[0]).is_equal_approx(Vector2(92.07, 0), Vector2(0.01, 0.01))

	var ins: PackedVector2Array = sub.ins
	# in del segundo anchor = segundo punto de control (184.14,0) - anchor(279,0)
	assert_vector(ins[1]).is_equal_approx(Vector2(184.14 - 279, 0), Vector2(0.01, 0.01))

func test_subtrazados_multiples_en_un_mismo_d_se_separan() -> void:
	var d := "M0 0 L10 0 L10 10 Z M5 5 L8 5 L8 8 Z"
	var subpaths := SvgPathParser.d_to_subpaths(d)
	assert_int(subpaths.size()).is_equal(2)
	assert_int((subpaths[0].anchors as PackedVector2Array).size()).is_equal(3)
	assert_int((subpaths[1].anchors as PackedVector2Array).size()).is_equal(3)
	assert_bool(subpaths[0].closed).is_true()
	assert_bool(subpaths[1].closed).is_true()

func test_subtrazado_abierto_sin_z_final_se_conserva() -> void:
	var d := "M0 0 L10 0 L10 10"
	var subpaths := SvgPathParser.d_to_subpaths(d)
	assert_int(subpaths.size()).is_equal(1)
	assert_bool(subpaths[0].closed).is_false()

func test_d_vacio_o_sin_puntos_suficientes_no_produce_subtrazados() -> void:
	assert_int(SvgPathParser.d_to_subpaths("").size()).is_equal(0)
	assert_int(SvgPathParser.d_to_subpaths("M5 5").size()).is_equal(0)
