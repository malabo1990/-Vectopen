extends GdUnitTestSuite

## Cubre el GDExtension nativo ClipboardImage (arboard, ver
## rust/vectopen_vectorizer). No controlamos qué hay en el portapapeles real
## de la máquina que corre el test, así que solo verificamos que la clase
## está registrada y que la llamada no crashea y devuelve algo sensato
## ("" con archivo escrito, "EMPTY", o un mensaje de error) — nunca null ni
## una excepción. El test de verdad de la lógica de lectura vive en Rust
## (cargo test paste_image_impl_lee_lo_que_se_puso_en_el_portapapeles),
## donde sí se controla el contenido del portapapeles.

func test_extension_nativa_cargada_y_clase_disponible() -> void:
	assert_bool(ClassDB.class_exists("ClipboardImage")).is_true()

func test_paste_image_to_file_no_crashea_y_devuelve_algo_sensato() -> void:
	if not ClassDB.class_exists("ClipboardImage"):
		fail("ClipboardImage no está registrada: el GDExtension no cargó")
		return

	var clip = ClassDB.instantiate("ClipboardImage")
	assert_object(clip).is_not_null()

	var output_abs := ProjectSettings.globalize_path("user://test_clipboard_paste.png")
	var result: String = clip.paste_image_to_file(output_abs)

	if result == "":
		assert_bool(FileAccess.file_exists(output_abs)).is_true()
		DirAccess.remove_absolute(output_abs)
	elif result == "EMPTY":
		assert_bool(FileAccess.file_exists(output_abs)).is_false()
	else:
		# Cualquier otro string es un mensaje de error legible, no un crash.
		assert_str(result).is_not_empty()
