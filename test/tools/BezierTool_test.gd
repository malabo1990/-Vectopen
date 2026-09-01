extends GdUnitTestSuite

## La herramienta Bézier debe producir un nodo Path2D con VectorPath.gd —
## el MISMO tipo estilizable que reconstruye el cargador — para que el
## Inspector y el panel de trazos operen sobre él sin ramas especiales.

const BEZIER := "res://script_gdscript/tools/beziertool.gd"

func test_crea_un_vectorpath_estilizable_y_cerrable() -> void:
	var tool: Node = auto_free(load(BEZIER).new())
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "Canvas"
	add_child(canvas)
	var ab: Node2D = auto_free(Node2D.new())
	ab.name = "AB"
	canvas.add_child(ab)
	canvas.add_child(tool)

	tool.canvas = canvas
	tool.target_artboard = ab

	tool._start_new_path()
	assert_object(tool.current_path).is_not_null()

	var cu: Curve2D = tool.current_path.curve
	cu.add_point(Vector2(0, 0))
	cu.add_point(Vector2(60, 0))
	cu.add_point(Vector2(60, 40))
	tool._finalize(true)
	await get_tree().process_frame

	var vp: Path2D = null
	for ch in ab.get_children():
		if ch is Path2D:
			vp = ch
	assert_object(vp).is_not_null()
	assert_str(vp.get_script().resource_path).is_equal("res://script_gdscript/shapes/VectorPath.gd")

	# estilo editable + estado cerrado sincronizado con la meta
	assert_bool(bool(vp.get("closed"))).is_true()
	assert_bool(bool(vp.get_meta("is_closed"))).is_true()
	vp.set("stroke_width", 9.0)
	vp.set("stroke_color", Color.RED)
	assert_float(vp.get("stroke_width")).is_equal_approx(9.0, 0.01)
	assert_that(vp.get("stroke_color")).is_equal(Color.RED)
