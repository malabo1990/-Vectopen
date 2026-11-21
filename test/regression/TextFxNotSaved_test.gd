extends GdUnitTestSuite

## VAL-48: las capas internas de los efectos de un texto (TextFxBack/Front) no
## se guardan como hijos: al reabrir creaban un nodo fantasma.

const CANVAS := "res://scenes/canvas/canvas.tscn"
const CS = preload("res://scripts/canvas/canvas_serializer.gd")

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame

func test_efectos_de_texto_sin_hijos_guardados() -> void:
	var api: VectopenAPI = PluginManager.api
	var t := api.add_text(Vector2(20, 20), "Marca", 40)
	api.add_effect(t, "Drop Shadow", {})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(t.find_children("TextFx*", "", false, false).size() > 0).is_true()
	var d: Dictionary = CS._serialize_element(t)
	assert_bool(d.has("children")).override_failure_message(str(d.get("children", []))).is_false()
	assert_bool(d.has("fx")).is_true()
