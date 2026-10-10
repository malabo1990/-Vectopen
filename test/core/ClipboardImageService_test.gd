extends GdUnitTestSuite

const SERVICE := "res://script_gdscript/shapes/ClipboardImageService.gd"

## Doble de prueba: mismo método que espera try_paste_into
## (target_artboard.vectorize_image), sin arrastrar toda la complejidad real
## de Artboard.gd (título, capas, etc.) que no hace falta para este test.
class FakeArtboard extends Node2D:
	var vectorize_image_called_with: String = ""
	func vectorize_image(file_path: String) -> void:
		vectorize_image_called_with = file_path

## _resolve_active_artboard cae a artboards_container.get_child(0) cuando no
## hay ArtboardManager en el árbol (canvas fuera de escena) — mismo patrón de
## fallback que usan PenTool/BrushTool para encontrar el artboard destino.
func test_resolve_active_artboard_cae_al_primer_hijo_del_contenedor() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "Canvas"
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	canvas.add_child(container)

	var ab: Node2D = auto_free(Node2D.new())
	ab.name = "AB"
	container.add_child(ab)

	var resolved = load(SERVICE)._resolve_active_artboard(canvas)
	assert_object(resolved).is_same(ab)

func test_resolve_active_artboard_sin_contenedor_ni_manager_da_null() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	var resolved = load(SERVICE)._resolve_active_artboard(canvas)
	assert_object(resolved).is_null()

## try_paste_into no depende de mocks para la lectura real del portapapeles
## (esa lógica está cubierta en Rust, cargo test paste_image_impl_lee_lo_...,
## donde sí se controla el contenido). Aquí solo verificamos que, sea lo que
## sea que haya en el portapapeles del sistema en la máquina que corre el
## test, la llamada no crashea y devuelve un bool — nunca null.
func test_try_paste_into_no_crashea_sin_importar_el_estado_del_portapapeles() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	canvas.add_child(container)
	var ab: FakeArtboard = auto_free(FakeArtboard.new())
	container.add_child(ab)

	var result = load(SERVICE).try_paste_into(canvas)
	assert_bool(result is bool).is_true()
	# Si el portapapeles del sistema SÍ tenía una imagen, debe haber llamado
	# a vectorize_image; si no, debe haber devuelto false sin llamarlo.
	if result:
		assert_str(ab.vectorize_image_called_with).is_not_empty()
	else:
		assert_str(ab.vectorize_image_called_with).is_empty()
