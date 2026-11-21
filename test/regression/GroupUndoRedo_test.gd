extends GdUnitTestSuite

## Deshacer y rehacer la creación de figuras + agrupar (encargo 12: tras
## deshacer/rehacer 20 pasos se perdían figuras).

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api
	HistoryManager.clear()

func _count() -> int:
	return _api.shapes(null, true).size()

func test_crear_agrupar_deshacer_rehacer() -> void:
	for k in 3:
		var parts := []
		parts.append(_api.add_rect(Vector2(50 + k * 100, 50), Vector2(30, 30)))
		parts.append(_api.add_ellipse(Vector2(50 + k * 100, 100), Vector2(30, 30)))
		parts.append(_api.add_path(PackedVector2Array([Vector2(k * 100, 150), Vector2(k * 100 + 40, 170)]), false))
		_api.group(parts, "G%d" % k)
	var n0 := _count()
	assert_int(n0).is_equal(12)
	for i in 8:
		HistoryManager.undo()
		await get_tree().process_frame
	for i in 8:
		HistoryManager.redo()
		await get_tree().process_frame
	assert_int(_count()).is_equal(n0)
