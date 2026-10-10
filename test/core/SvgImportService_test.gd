extends GdUnitTestSuite

const SAMPLE_SVG := '<?xml version="1.0" encoding="UTF-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="1920" height="1009">
<path d="M0 0 C92.07 0 184.14 0 279 0 C279 181.83 279 363.66 279 551 C186.93 551 94.86 551 0 551 C0 369.17 0 187.34 0 0 Z " fill="#F9F9FB" transform="translate(17,412)"/>
</svg>'

const INPUT_IMAGE := "res://addons/godot_mcp/cache/screenshots/realtime_stroke_test.png"

func test_build_from_svg_crea_vectorpath_estilizable_en_la_posicion_correcta() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)

	var created := SvgImportService.build_from_svg(SAMPLE_SVG, parent)
	assert_int(created.size()).is_equal(1)

	var vp := created[0]
	assert_str(vp.get_script().resource_path).is_equal("res://script_gdscript/shapes/VectorPath.gd")
	assert_vector(vp.position).is_equal(Vector2(17, 412))
	assert_bool(bool(vp.get("closed"))).is_true()
	assert_that(vp.get("fill_color")).is_equal(Color("#F9F9FB"))
	assert_float(vp.get("stroke_width")).is_equal_approx(0.0, 0.001)
	assert_int(vp.curve.point_count).is_equal(5)
	assert_bool(vp.get_parent() == parent).is_true()

func test_vectorize_into_extremo_a_extremo_con_el_gdextension_real() -> void:
	if not ClassDB.class_exists("ImageVectorizer"):
		fail("ImageVectorizer no está registrada: el GDExtension no cargó")
		return

	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)

	var created := SvgImportService.vectorize_into(INPUT_IMAGE, parent, 4, 60, false)
	assert_int(created.size()).is_greater(0)
	for vp in created:
		assert_str(vp.get_script().resource_path).is_equal("res://script_gdscript/shapes/VectorPath.gd")
		assert_int(vp.curve.point_count).is_greater_equal(2)
