extends GdUnitTestSuite

## VAL-45: una capa bloqueada sigue bloqueada al guardar y reabrir.

const CS = preload("res://scripts/canvas/canvas_serializer.gd")

func test_bloqueo_se_guarda() -> void:
	var r := VectorRectangle.new()
	r.name = "Mar"
	r.set_meta("locked", true)
	var d: Dictionary = CS._serialize_element(r)
	assert_bool(bool(d.get("locked", false))).is_true()
	var n: Node2D = CS._element_from(d)
	CS._apply_transform(n, d)
	assert_bool(bool(n.get_meta("locked", false))).is_true()
	r.free()
	n.free()
