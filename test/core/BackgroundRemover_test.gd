extends GdUnitTestSuite

## Cubre el GDExtension nativo BackgroundRemover (U2Net-p vía ort/onnxruntime,
## ver rust/vectopen_vectorizer). Sin mocks: corre el modelo real sobre una
## imagen real y verifica que produjo una máscara alfa no trivial (no basta
## con que el archivo exista — un PNG totalmente opaco significaría que la
## inferencia no hizo nada útil).

const INPUT_IMAGE := "res://addons/godot_mcp/cache/screenshots/realtime_stroke_test.png"

func test_extension_nativa_cargada_y_clase_disponible() -> void:
	assert_bool(ClassDB.class_exists("BackgroundRemover")).is_true()

func test_quita_fondo_de_una_imagen_real_y_produce_alfa_variable() -> void:
	if not ClassDB.class_exists("BackgroundRemover"):
		fail("BackgroundRemover no está registrada: el GDExtension no cargó")
		return

	var remover = ClassDB.instantiate("BackgroundRemover")
	assert_object(remover).is_not_null()

	var input_abs := ProjectSettings.globalize_path(INPUT_IMAGE)
	var output_abs := ProjectSettings.globalize_path("user://test_bg_removed.png")

	var err: String = remover.remove_background_to_file(input_abs, output_abs)
	assert_str(err).is_equal("")
	assert_bool(FileAccess.file_exists(output_abs)).is_true()

	var img := Image.new()
	var load_err := img.load(output_abs)
	assert_int(load_err).is_equal(OK)
	assert_bool(img.detect_alpha() != Image.ALPHA_NONE).is_true()

	# La máscara real debe variar: si todos los píxeles quedan igual de
	# opacos (o igual de transparentes) es que la inferencia no aportó nada.
	var min_a := 255
	var max_a := 0
	for y in range(0, img.get_height(), max(1, img.get_height() / 40)):
		for x in range(0, img.get_width(), max(1, img.get_width() / 40)):
			var a: int = img.get_pixel(x, y).a8
			min_a = mini(min_a, a)
			max_a = maxi(max_a, a)
	assert_int(max_a - min_a).is_greater(10)

	DirAccess.remove_absolute(output_abs)
