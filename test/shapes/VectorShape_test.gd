extends GdUnitTestSuite

func test_default_properties() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	assert_str(s.object_id).is_equal("")
	assert_vector(s.position).is_equal(Vector2.ZERO)
	assert_that(s.fill_color).is_equal(Color.WHITE)
	assert_that(s.stroke_color).is_equal(Color.BLACK)
	assert_float(s.stroke_width).is_equal(2.0)
	assert_bool(s.is_selected).is_false()
	assert_array(s.effects).is_empty()

func test_set_selected_changes_modulate() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	s.set_selected(true)
	assert_that(s.modulate).is_equal(Color(1.2, 1.2, 1.2, 1.0))
	assert_bool(s.is_selected).is_true()

	s.set_selected(false)
	assert_that(s.modulate).is_equal(Color(1.0, 1.0, 1.0, 1.0))
	assert_bool(s.is_selected).is_false()

func test_get_state_returns_dictionary() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	s.object_id = "test-123"
	s.position = Vector2(100, 200)
	s.fill_color = Color.RED

	var state: Dictionary = s.get_state()
	assert_dict(state).contains_keys(["id", "position", "rotation", "scale", "fill_color", "stroke_color", "stroke_width"])
	assert_str(state["id"] as String).is_equal("test-123")
	assert_vector(state["position"] as Vector2).is_equal(Vector2(100, 200))
	assert_that(state["fill_color"] as Color).is_equal(Color.RED)

func test_serialize_returns_same_as_get_state() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	s.object_id = "serialize-test"
	var state: Dictionary = s.get_state()
	var serialized: Dictionary = s.serialize()
	assert_dict(serialized).contains_keys(state.keys())

func test_to_svg_returns_empty_string() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	assert_str(s.to_svg()).is_equal("")

func test_custom_properties() -> void:
	var s: Node2D = auto_free(VectorShape.new())
	add_child(s)

	s.object_id = "custom"
	s.stroke_width = 5.0
	s.stroke_color = Color.BLUE
	s.fill_color = Color.YELLOW

	assert_str(s.object_id).is_equal("custom")
	assert_float(s.stroke_width).is_equal(5.0)
	assert_that(s.stroke_color).is_equal(Color.BLUE)
	assert_that(s.fill_color).is_equal(Color.YELLOW)

func test_vector_rectangle_extends_shape() -> void:
	var r: Node2D = auto_free(VectorRectangle.new())
	add_child(r)

	assert_object(r).is_instanceof(VectorShape)
	assert_object(r).is_instanceof(Node2D)
	assert_str(r.object_id).is_equal("")
	assert_float(r.corner_radius).is_equal(0.0)
	assert_vector(r.size).is_equal(Vector2(100, 100))

func test_vector_circle_extends_shape() -> void:
	var c: Node2D = auto_free(VectorCircle.new())
	add_child(c)

	assert_object(c).is_instanceof(VectorShape)
	assert_object(c).is_instanceof(Node2D)
	assert_vector(c.size).is_equal(Vector2(100, 100))
