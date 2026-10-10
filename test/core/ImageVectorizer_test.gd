extends GdUnitTestSuite

## Cubre el GDExtension nativo en rust/vectopen_vectorizer (clase
## "ImageVectorizer", vtracer por debajo). Si el .gdextension no cargó, la
## clase ni siquiera existe en ClassDB y este test lo detecta con claridad
## en vez de fallar más adelante con un error críptico de "clase no encontrada".

const INPUT_IMAGE := "res://addons/godot_mcp/cache/screenshots/realtime_stroke_test.png"

func test_extension_nativa_cargada_y_clase_disponible() -> void:
	assert_bool(ClassDB.class_exists("ImageVectorizer")).is_true()

func test_vectoriza_una_imagen_real_a_svg() -> void:
	if not ClassDB.class_exists("ImageVectorizer"):
		fail("ImageVectorizer no está registrada: el GDExtension no cargó (revisa vectopen_vectorizer.gdextension y el build en rust/vectopen_vectorizer/target/)")
		return

	var vectorizer = ClassDB.instantiate("ImageVectorizer")
	assert_object(vectorizer).is_not_null()

	var input_abs := ProjectSettings.globalize_path(INPUT_IMAGE)
	var output_abs := ProjectSettings.globalize_path("user://test_vectorize_output.svg")

	var err: String = vectorizer.vectorize_to_file(input_abs, output_abs, 4, 60, false)
	assert_str(err).is_equal("")

	assert_bool(FileAccess.file_exists(output_abs)).is_true()
	var svg_text := FileAccess.get_file_as_string(output_abs)
	assert_str(svg_text).contains("<svg")
	assert_str(svg_text).contains("path")

	DirAccess.remove_absolute(output_abs)
