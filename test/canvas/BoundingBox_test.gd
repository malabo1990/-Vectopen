extends GdUnitTestSuite

const _BoundingBoxScene := preload("res://scenes/canvas/boundingbox.tscn")

func _make_square_polygon(local_half_size: float = 20.0) -> Polygon2D:
	var poly := Polygon2D.new()
	var h := local_half_size
	poly.polygon = PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)
	])
	return poly

func test_single_shape_rotation_scale_position_tracked_exactly() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: Polygon2D = _make_square_polygon(20.0)
	shape.position = Vector2(100, 50)
	shape.rotation = deg_to_rad(30.0)
	shape.scale = Vector2(2.0, 2.0)
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape

	bb._sincronizar_dimensiones_en_canvas()

	# Rotación y escala de la caja deben ser exactamente las de la figura
	assert_float(bb.rotation).is_equal_approx(shape.rotation, 0.001)
	assert_vector(bb.scale).is_equal_approx(shape.scale, Vector2(0.001, 0.001))

	# El tamaño debe ser el rect LOCAL de la figura (su polígono va de -20,-20 a 20,20)
	assert_vector(bb.size).is_equal_approx(Vector2(40.0, 40.0), Vector2(0.01, 0.01))

	# La posición debe coincidir con transformar la esquina local (-20,-20)
	# por el transform real de la figura (rotación + escala + posición)
	var expected_world_pos: Vector2 = shape.to_global(Vector2(-20.0, -20.0))
	var expected_local_pos: Vector2 = root.to_local(expected_world_pos)
	assert_vector(bb.position).is_equal_approx(expected_local_pos, Vector2(0.01, 0.01))

func test_multi_selection_falls_back_to_axis_aligned_box() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape_a: Polygon2D = _make_square_polygon(20.0)
	shape_a.position = Vector2(0, 0)
	shape_a.rotation = deg_to_rad(45.0)  # rotada: no debería determinar la rotación de la caja
	root.add_child(shape_a)

	var shape_b: Polygon2D = _make_square_polygon(20.0)
	shape_b.position = Vector2(200, 0)
	root.add_child(shape_b)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape_a, shape_b]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()

	# Con selección múltiple no hay una rotación única válida: debe quedar alineada al mundo
	assert_float(bb.rotation).is_equal_approx(0.0, 0.001)
	assert_vector(bb.scale).is_equal_approx(Vector2.ONE, Vector2(0.001, 0.001))

func test_empty_selection_hides_box() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = null
	bb.show()

	bb._sincronizar_dimensiones_en_canvas()

	assert_bool(bb.visible).is_false()

func test_single_vector_shape_shows_and_syncs_position_fields() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape)
	shape.set_doc_position(DVec2.new(123.5, -45.25))
	shape.set_doc_extent(DVec2.new(80.0, 60.0))

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()

	assert_object(bb._bound_shape).is_same(shape)
	assert_bool(bb._fields_wrapper.visible).is_true()
	assert_float(bb._field_x.value).is_equal_approx(123.5, 1e-6)
	assert_float(bb._field_y.value).is_equal_approx(-45.25, 1e-6)

func test_field_x_committed_moves_shape() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape)
	shape.set_doc_position(DVec2.new(0.0, 0.0))

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()
	bb._on_field_x_committed(77.75)

	assert_float(shape.doc_position.x).is_equal_approx(77.75, 1e-6)
	assert_float(shape.position.x).is_equal_approx(77.75, 1e-6)

func test_field_y_committed_moves_shape() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape)
	shape.set_doc_position(DVec2.new(10.0, 10.0))

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()
	bb._on_field_y_committed(-33.125)

	assert_float(shape.doc_position.x).is_equal_approx(10.0, 1e-6)  # X no se toca
	assert_float(shape.doc_position.y).is_equal_approx(-33.125, 1e-6)

func test_non_vector_shape_hides_position_fields() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: Polygon2D = _make_square_polygon(20.0)
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape

	bb._sincronizar_dimensiones_en_canvas()

	assert_bool(bb._fields_wrapper.visible).is_false()
	assert_object(bb._bound_shape).is_null()

func test_multi_selection_hides_position_fields() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape_a: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape_a)
	shape_a.set_doc_position(DVec2.new(0.0, 0.0))

	var shape_b: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape_b)
	shape_b.set_doc_position(DVec2.new(200.0, 0.0))

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape_a, shape_b]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()

	assert_bool(bb._fields_wrapper.visible).is_false()
	assert_object(bb._bound_shape).is_null()
