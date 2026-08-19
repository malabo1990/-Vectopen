extends GdUnitTestSuite

func test_resize_round_trip_preserves_subpixel_precision() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)

	var precise: float = 100.00001234
	shape.set_doc_position(DVec2.new(200.0, 150.0))
	shape.set_doc_extent(DVec2.new(precise, precise))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.resize_handle = "br"
	tool.transform_initial_mouse = Vector2.ZERO

	# 40 ciclos de "agrandar 37px, volver a encoger 37px" por el mismo handle,
	# re-capturando el snapshot en cada paso (como ocurriría con 40 gestos de
	# resize reales, uno tras otro). Con el .size nativo (Vector2/float32) de
	# antes, cada paso releía como "exacto" un valor ya redondeado a ~7 dígitos
	# significativos, así que el error se acumulaba de forma medible tras
	# unas pocas decenas de ciclos. Con doc_extent (float de 64 bits), cada
	# paso parte siempre del valor doble exacto guardado por el paso anterior.
	for i in range(40):
		tool.selected_shapes = [shape]
		var current_extent: Vector2 = shape.get_doc_extent().to_v2()
		var current_rect: Rect2 = Rect2(shape.doc_position.to_v2() - current_extent / 2.0, current_extent)

		tool.transform_macro_rect = current_rect
		tool.transform_initial_states = {shape: tool._snapshot(shape)}
		tool._apply_resize(Vector2(37, 0))

		current_extent = shape.get_doc_extent().to_v2()
		current_rect = Rect2(shape.doc_position.to_v2() - current_extent / 2.0, current_extent)
		tool.transform_macro_rect = current_rect
		tool.transform_initial_states = {shape: tool._snapshot(shape)}
		tool._apply_resize(Vector2(-37, 0))

	assert_float(shape.get_doc_extent().x).is_equal_approx(precise, 1e-6)
	assert_float(shape.get_doc_extent().y).is_equal_approx(precise, 1e-6)

func test_snapshot_captures_doc_space_for_vector_shape() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)
	shape.set_doc_position(DVec2.new(10.5, 20.5))
	shape.set_doc_extent(DVec2.new(30.5, 40.5))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	var snap: Dictionary = tool._snapshot(shape)

	assert_bool(snap.has("doc_pos")).is_true()
	assert_bool(snap.has("doc_rot")).is_true()
	assert_bool(snap.has("doc_extent")).is_true()
	assert_float(snap["doc_pos"].x).is_equal(10.5)
	assert_float(snap["doc_extent"].x).is_equal(30.5)

func test_translate_syncs_doc_position() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	canvas.add_child(shape)
	shape.set_doc_position(DVec2.new(0.0, 0.0))

	var tool: MoveTool = auto_free(MoveTool.new())
	tool.canvas = canvas
	tool.selected_shapes = [shape]
	tool.transform_initial_mouse = Vector2.ZERO
	tool.transform_initial_states = {shape: tool._snapshot(shape)}

	# Simula el bloque de traslación directa de _on_motion() sin pasar por
	# eventos de input reales (SnapManager no está registrado en este árbol
	# de test, así que la rama de snap simplemente no se activa).
	var delta: Vector2 = Vector2(15.0, -5.0)
	for s in tool.selected_shapes:
		var snap: Dictionary = tool.transform_initial_states[s]
		var new_pos: Vector2 = snap["gpos"] + delta
		s.global_position = new_pos
		tool._sync_doc_position_from_native(s)

	assert_vector(shape.position).is_equal(Vector2(15.0, -5.0))
	assert_float(shape.doc_position.x).is_equal(15.0)
	assert_float(shape.doc_position.y).is_equal(-5.0)
