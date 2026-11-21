extends GdUnitTestSuite

## §5.3: exportaciones deterministas (mismo documento → mismos bytes) en
## SVG, PDF, EPS y VOP.

const CANVAS := "res://scenes/canvas/canvas.tscn"
var _api: VectopenAPI = null

func before_test() -> void:
	var s: Node2D = load(CANVAS).instantiate()
	add_child(s)
	get_tree().current_scene = s
	auto_free(s)
	await get_tree().process_frame
	_api = PluginManager.api

func test_mismo_documento_mismos_bytes() -> void:
	var r := _api.add_rect(Vector2(100, 100), Vector2(120, 80), 10.0)
	_api.set_prop(r, "fill_paint", {"type": "linear", "angle": 0.5, "stops": [[0.0, Color.RED], [1.0, Color.BLUE]]})
	_api.add_star(Vector2(260, 120), 50, 6)
	_api.add_text(Vector2(40, 220), "Determinista", 28)
	var c := Curve2D.new()
	c.add_point(Vector2(20, 300), Vector2.ZERO, Vector2(60, -40))
	c.add_point(Vector2(200, 300), Vector2(-60, -40), Vector2.ZERO)
	_api.add_curve(c, false)
	await get_tree().process_frame
	for ext in ["svg", "pdf", "eps", "vop"]:
		var a: String = "user://det_a." + ext
		var b: String = "user://det_b." + ext
		assert_bool(await _api.export(ProjectSettings.globalize_path(a), null)).is_true()
		assert_bool(await _api.export(ProjectSettings.globalize_path(b), null)).is_true()
		var ba := FileAccess.get_file_as_bytes(a)
		var bb := FileAccess.get_file_as_bytes(b)
		assert_int(ba.size()).override_failure_message(ext).is_greater(64)
		assert_bool(ba == bb).override_failure_message("%s distinto entre dos exportaciones" % ext).is_true()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(a))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(b))
