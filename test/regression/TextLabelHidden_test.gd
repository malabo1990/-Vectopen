extends GdUnitTestSuite

## VAL-49: un texto creado por la API (o la herramienta Texto) ocultaba su
## etiqueta con visible=false; el CullManager la volvía a encender y el texto
## salía DOBLE. La etiqueta debe quedar transparente aunque esté visible.

const CANVAS := "res://scenes/canvas/canvas.tscn"

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame

func test_etiqueta_transparente_aunque_se_encienda() -> void:
	if not ClassDB.class_exists("VectorRichText"):
		return
	var api: VectopenAPI = PluginManager.api
	for t in [api.add_text(Vector2(10, 10), "Título", 30), api.add_text_box(Rect2(10, 80, 200, 60), "Párrafo de prueba", 14)]:
		var dl: CanvasItem = t.get_node("DisplayLabel")
		dl.visible = true   # lo que hace el CullManager con lo que está a la vista
		assert_float(dl.self_modulate.a).is_less(0.01)
