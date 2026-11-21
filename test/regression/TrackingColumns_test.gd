extends GdUnitTestSuite

## VAL-52: el tracking de todo el texto se ve (llega al motor nativo).
## VAL-53: un marco de varias columnas reparte el texto (columnas equilibradas).

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api

func test_tracking_cambia_el_ancho() -> void:
	if not ClassDB.class_exists("VectorRichText"):
		return
	var t := _api.add_text(Vector2(10, 10), "TRACKING", 40)
	var vrt = t.get_node("VectorRichText")
	var w0: float = vrt.get_content_size().x
	_api.set_prop(t, "letter_spacing", 20.0)
	var w1: float = vrt.get_content_size().x
	assert_float(w1).is_greater(w0 + 100.0)
	assert_float(float(_api.get_prop(t, "width"))).is_greater(w1 * 0.9)   # la caja sigue al texto
	_api.undo()
	assert_float(vrt.get_content_size().x).is_equal_approx(w0, 1.0)

func test_dos_columnas_equilibradas() -> void:
	if not ClassDB.class_exists("VectorRichText"):
		return
	var txt := "Columna de prueba con bastante texto para repartir. ".repeat(12)
	var one := _api.add_text_box(Rect2(10, 10, 600, 100), txt, 16, Color.BLACK, 1)
	var two := _api.add_text_box(Rect2(10, 400, 600, 100), txt, 16, Color.BLACK, 2)
	var h1 := float(_api.get_prop(one, "height"))
	var h2 := float(_api.get_prop(two, "height"))
	# Dos columnas de la MITAD de ancho: el doble de líneas repartidas en dos ≈ mismo alto, nunca el doble.
	assert_float(h2).is_less(h1 * 1.5)
	assert_bool(two.get_node("VectorRichText").is_overset()).is_false()
