extends GdUnitTestSuite

func test_handle_input_returns_false() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	var event: InputEvent = InputEventMouseButton.new()
	assert_bool(tool.handle_input(event)).is_false()

func test_draw_preview_does_nothing() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	var c: Node2D = auto_free(Node2D.new())
	tool.draw_preview(c)
	assert_bool(true).is_true()

func test_get_class_name_empty() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	assert_str(tool.get_class_name()).is_equal("")

func test_default_state() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	assert_vector(tool.box_start_global).is_equal(Vector2.ZERO)
	assert_vector(tool.box_current_global).is_equal(Vector2.ZERO)
	assert_bool(tool.is_drawing).is_false()

func test_default_constants() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	assert_that(ToolBase.STROKE_COLOR).is_equal(Color(0.0, 0.0, 0.0, 1.0))
	assert_float(ToolBase.STROKE_WIDTH).is_equal(1.0)
	assert_that(ToolBase.FILL_COLOR).is_equal(Color(0.88, 0.88, 0.88, 1.0))

func test_deactivate_resets_is_drawing() -> void:
	var tool: Node = auto_free(ToolBase.new())
	add_child(tool)

	tool.is_drawing = true
	tool.deactivate()
	assert_bool(tool.is_drawing).is_false()

func test_refresh_dependencies_finds_canvas_from_parent() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "CanvasRoot"
	var tool: Node = auto_free(ToolBase.new())
	canvas.add_child(tool)

	tool._refresh_dependencies()
	assert_object(tool.canvas).is_not_null()
	assert_object(tool.canvas).is_same(canvas)

func test_refresh_dependencies_finds_artboard() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "CanvasRoot"
	var container: Node2D = auto_free(Node2D.new())
	container.name = "ArtboardsContainer"
	var artboard_node: Node2D = auto_free(Node2D.new())
	artboard_node.name = "Artboard"
	container.add_child(artboard_node)
	canvas.add_child(container)

	var tool: Node = auto_free(ToolBase.new())
	canvas.add_child(tool)

	tool._refresh_dependencies()
	assert_object(tool.artboard).is_not_null()
	assert_object(tool.artboard).is_same(artboard_node)

func test_refresh_dependencies_finds_shape_manager() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	canvas.name = "CanvasRoot"
	var sm: Node = auto_free(Node.new())
	sm.name = "ShapeManager"
	canvas.add_child(sm)

	var tool: Node = auto_free(ToolBase.new())
	canvas.add_child(tool)

	tool._refresh_dependencies()
	assert_object(tool.shape_manager).is_not_null()
	assert_object(tool.shape_manager).is_same(sm)
