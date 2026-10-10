extends GdUnitTestSuite

## Cubre el GDExtension nativo ImageUpscaler (Real-ESRGAN-General-x4v3 vía
## ort/onnxruntime, ver rust/vectopen_vectorizer). Sin mocks: corre el
## modelo real. Usa una imagen sintética pequeña (no la captura de pantalla
## grande de otros tests) para que el test siga siendo rápido — el modelo
## trabaja en tiles fijos de 128x128, una imagen de 40x30 es un solo tile.

func test_extension_nativa_cargada_y_clase_disponible() -> void:
	assert_bool(ClassDB.class_exists("ImageUpscaler")).is_true()

func test_escala_x4_una_imagen_real_y_produce_detalle_no_trivial() -> void:
	if not ClassDB.class_exists("ImageUpscaler"):
		fail("ImageUpscaler no está registrada: el GDExtension no cargó")
		return

	var img := Image.create(40, 30, false, Image.FORMAT_RGB8)
	for y in range(30):
		for x in range(40):
			# patrón con bordes duros, para que un "solo estirar píxeles"
			# ingenuo se distinga claramente de una reconstrucción real
			var v: float = 1.0 if ((x / 4) + (y / 4)) % 2 == 0 else 0.0
			img.set_pixel(x, y, Color(v, v, v))

	var input_abs := ProjectSettings.globalize_path("user://test_upscale_input.png")
	var output_abs := ProjectSettings.globalize_path("user://test_upscale_output.png")
	img.save_png(input_abs)

	var upscaler = ClassDB.instantiate("ImageUpscaler")
	assert_object(upscaler).is_not_null()

	var err: String = upscaler.upscale_to_file(input_abs, output_abs)
	assert_str(err).is_equal("")
	assert_bool(FileAccess.file_exists(output_abs)).is_true()

	var out_img := Image.new()
	assert_int(out_img.load(output_abs)).is_equal(OK)
	assert_int(out_img.get_width()).is_equal(40 * 4)
	assert_int(out_img.get_height()).is_equal(30 * 4)

	# El modelo debe producir algo distinto de un "nearest-neighbor" ingenuo
	# (comprobamos que hay variación de gris que NO es un bloque uniforme de
	# 16x16 px, es decir que hubo reconstrucción real, no solo repetir píxeles).
	var distinct_values := {}
	for y in range(0, out_img.get_height(), 3):
		for x in range(0, out_img.get_width(), 3):
			var g: float = out_img.get_pixel(x, y).r
			distinct_values[roundi(g * 50.0)] = true
	assert_int(distinct_values.size()).is_greater(5)

	DirAccess.remove_absolute(input_abs)
	DirAccess.remove_absolute(output_abs)

func test_imagen_mas_grande_que_un_tile_se_reensambla_sin_huecos() -> void:
	if not ClassDB.class_exists("ImageUpscaler"):
		fail("ImageUpscaler no está registrada: el GDExtension no cargó")
		return

	# 200x150 con TILE_IN=128 exige una rejilla 2x2 con padding en los bordes
	# derecho/inferior: ejercita el recorte valid_w/valid_h, no solo el
	# caso de un único tile completo.
	var img := Image.create(200, 150, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.3, 0.2))

	var input_abs := ProjectSettings.globalize_path("user://test_upscale_multitile_input.png")
	var output_abs := ProjectSettings.globalize_path("user://test_upscale_multitile_output.png")
	img.save_png(input_abs)

	var upscaler = ClassDB.instantiate("ImageUpscaler")
	var err: String = upscaler.upscale_to_file(input_abs, output_abs)
	assert_str(err).is_equal("")

	var out_img := Image.new()
	assert_int(out_img.load(output_abs)).is_equal(OK)
	assert_int(out_img.get_width()).is_equal(200 * 4)
	assert_int(out_img.get_height()).is_equal(150 * 4)

	# Ningún píxel debe quedar sin escribir (negro puro por defecto de
	# RgbaImage::new de Rust) en las esquinas de cada cuadrante de la rejilla
	# 2x2, que es justo donde un error de offset/recorte se notaría.
	var corners := [
		Vector2i(0, 0), Vector2i(799, 0), Vector2i(0, 599), Vector2i(799, 599),
		Vector2i(511, 511), Vector2i(512, 512),
	]
	for c in corners:
		var px := out_img.get_pixel(c.x, c.y)
		assert_bool(px.a > 0.99).is_true()

	DirAccess.remove_absolute(input_abs)
	DirAccess.remove_absolute(output_abs)
