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

## Invariante de la caja de multiselección: debe ser exactamente el AABB que
## envuelve a TODAS las figuras seleccionadas (min de los left/top, max de los
## right/bottom) — ni más grande ni más chica. Antes solo se comprobaba
## rotación/escala aquí; esto es lo que realmente detecta un bounding box mal
## calculado (encogido, desplazado, o que ignora alguna figura).
func test_multi_selection_box_bounds_match_combined_aabb() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape_a: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape_a)
	shape_a.position = Vector2(0, 0)
	shape_a.size = Vector2(80, 40)  # AABB: (-40,-20) a (40,20)

	var shape_b: VectorRectangle = auto_free(VectorRectangle.new())
	root.add_child(shape_b)
	shape_b.position = Vector2(250, 120)
	shape_b.size = Vector2(60, 100)  # AABB: (220,70) a (280,170)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape_a, shape_b]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool

	bb._sincronizar_dimensiones_en_canvas()

	assert_float(bb.position.x).is_equal_approx(-40.0, 0.01)
	assert_float(bb.position.y).is_equal_approx(-20.0, 0.01)
	assert_float(bb.position.x + bb.size.x).is_equal_approx(280.0, 0.01)
	assert_float(bb.position.y + bb.size.y).is_equal_approx(170.0, 0.01)

	# Invariante general (no atada a estos números concretos): la caja debe
	# encerrar completamente el AABB de cada figura seleccionada.
	var box_rect := Rect2(bb.position, bb.size)
	for shape: Node2D in move_tool.selected_shapes:
		var shape_size: Vector2 = shape.get("size")
		var shape_rect := Rect2(shape.global_position - shape_size * 0.5, shape_size)
		assert_bool(box_rect.encloses(shape_rect)).is_true()

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

func test_gradient_annotator_data_linear() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.fill_gradient_angle = 0.0
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var data: Dictionary = bb._get_gradient_annotator_data()
	assert_bool(data.is_empty()).is_false()
	assert_int(data["type"]).is_equal(0)
	assert_int(data["stops"].size()).is_equal(2)
	assert_float(data["p0"].y).is_equal_approx(data["p1"].y, 0.01)

func test_gradient_annotator_data_radial() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 1
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var data: Dictionary = bb._get_gradient_annotator_data()
	assert_bool(data.is_empty()).is_false()
	assert_int(data["type"]).is_equal(1)
	assert_vector(data["p0"]).is_equal_approx(data["center"], Vector2(0.01, 0.01))

func test_gradient_annotator_hit_test_and_interaction() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.fill_gradient_angle = 0.0
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var data: Dictionary = bb._get_gradient_annotator_data()
	var p_end: Vector2 = data["p_rot"]

	# Hit test on end handle
	var hit: Dictionary = bb._hit_gradient_annotator(p_end, 1.0)
	assert_str(hit["hit"]).is_equal("end")

	# Simulate dragging end handle to 90 degrees directly below p0
	bb._annotator_drag_mode = "end"
	var mouse_event := InputEventMouseMotion.new()
	mouse_event.global_position = bb.get_global_transform() * (data["p0"] + Vector2(0, 50))
	var handled: bool = bb._handle_annotator_input(mouse_event)
	assert_bool(handled).is_true()
	assert_float(shape.fill_gradient_angle).is_equal_approx(PI * 0.5, 0.05)

func test_gradient_annotator_two_points_independent_positioning() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	assert_bool(bb.has_gradient_annotator()).is_true()

	# 1. Drag start handle (p0) to (10, 20)
	bb._annotator_drag_mode = "start"
	var ev_start := InputEventMouseMotion.new()
	ev_start.global_position = bb.get_global_transform() * Vector2(10, 20)
	bb._handle_annotator_input(ev_start)

	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.1, 0.2), Vector2(0.01, 0.01))

	# 2. Drag end handle (p1) to (90, 80)
	bb._annotator_drag_mode = "end"
	var ev_end := InputEventMouseMotion.new()
	ev_end.global_position = bb.get_global_transform() * Vector2(90, 80)
	bb._handle_annotator_input(ev_end)

	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.9, 0.8), Vector2(0.01, 0.01))

	# 3. Verify UV coordinates mapping
	var uvs: PackedVector2Array = shape._gradient_uvs(PackedVector2Array([Vector2(-50, -50), Vector2(50, 50)]))
	assert_int(uvs.size()).is_equal(2)

func test_gradient_annotator_drag_entire_line() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 0
	shape.fill_gradient_p0 = Vector2(0.2, 0.3)
	shape.fill_gradient_p1 = Vector2(0.8, 0.7)
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var data: Dictionary = bb._get_gradient_annotator_data()
	var mid_p: Vector2 = (data["p0"] + data["p1"]) * 0.5

	# 1. Clic sobre la línea (hit test)
	var hit: Dictionary = bb._hit_gradient_annotator(mid_p, 1.0)
	assert_str(hit["hit"]).is_equal("line")

	# 2. Iniciar arrastre sobre la línea
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_global_transform() * mid_p
	bb._handle_annotator_input(ev_press)

	assert_str(bb._annotator_drag_mode).is_equal("line")

	# 3. Desplazar la línea en (+20, +10) píxeles (delta normalizado: +0.2, +0.1)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_global_transform() * (mid_p + Vector2(20, 10))
	bb._handle_annotator_input(ev_motion)

	# Ambos extremos deben trasladarse simultáneamente
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.4, 0.4), Vector2(0.01, 0.01))
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(1.0, 0.8), Vector2(0.01, 0.01))

	# 4. Soltar ratón
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	bb._handle_annotator_input(ev_release)

	assert_str(bb._annotator_drag_mode).is_equal("")

func test_gradient_conic_spiral_rendering() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.fill_gradient_type = 2 # Cónico / Espiral
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var data: Dictionary = bb._get_gradient_annotator_data()
	assert_int(data["type"]).is_equal(2)

	var tex: GradientTexture2D = shape._ensure_grad_tex()
	assert_object(tex).is_not_null()
	assert_int(tex.fill).is_equal(GradientTexture2D.FILL_CONIC)

func test_gradient_endpoint_0_fixed_when_dragging_endpoint_1() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.2, 0.3), Vector2(0.8, 0.7))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	# 1. Clic sobre endpoint 1 (p1: 80, 70 local)
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_global_transform() * Vector2(80, 70)
	bb._handle_annotator_input(ev_press)

	assert_str(bb._annotator_drag_mode).is_equal("end")

	# 2. Arrastrar endpoint 1 a una nueva posición (90, 95 local -> 0.9, 0.95 norm)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_global_transform() * Vector2(90, 95)
	bb._handle_annotator_input(ev_motion)

	# Endpoint 1 debe haber cambiado a (0.9, 0.95)
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.9, 0.95), Vector2(0.001, 0.001))
	# Endpoint 0 DEBE permanecer EXACTAMENTE en (0.2, 0.3), completamente FIJO!
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.2, 0.3), Vector2(0.001, 0.001))

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	bb._handle_annotator_input(ev_release)

func test_gradient_endpoint_1_fixed_when_dragging_endpoint_0() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.2, 0.3), Vector2(0.8, 0.7))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	# 1. Clic sobre endpoint 0 (p0: 20, 30 local)
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_global_transform() * Vector2(20, 30)
	bb._handle_annotator_input(ev_press)

	assert_str(bb._annotator_drag_mode).is_equal("start")

	# 2. Arrastrar endpoint 0 a una nueva posición (5, 10 local -> 0.05, 0.10 norm)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_global_transform() * Vector2(5, 10)
	bb._handle_annotator_input(ev_motion)

	# Endpoint 0 debe haber cambiado a (0.05, 0.10)
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.05, 0.10), Vector2(0.001, 0.001))
	# Endpoint 1 DEBE permanecer EXACTAMENTE en (0.8, 0.7), completamente FIJO!
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.8, 0.7), Vector2(0.001, 0.001))

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	bb._handle_annotator_input(ev_release)

func test_gradient_intermediate_stop_drag_and_fixed_endpoints() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.add_point(0.5, Color.RED)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	# 1. Clic sobre la parada intermedia (offset 0.5 -> pos 50, 50 local)
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_global_transform() * Vector2(50, 50)
	bb._handle_annotator_input(ev_press)

	assert_str(bb._annotator_drag_mode).is_equal("stop")

	# 2. Arrastrar a x=75 (offset 0.75)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_global_transform() * Vector2(75, 50)
	bb._handle_annotator_input(ev_motion)

	# El stop debe haberse movido a ~0.75
	assert_float(g.get_offset(1)).is_equal_approx(0.75, 0.02)
	# Los extremos p0 y p1 deben seguir intactos
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.0, 0.5), Vector2(0.001, 0.001))
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(1.0, 0.5), Vector2(0.001, 0.001))

	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	bb._handle_annotator_input(ev_release)

func test_key_g_toggles_gradient_mode() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	shape.fill_color = Color(0.2, 0.5, 0.9, 1.0)
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb

	assert_bool(move_tool.is_gradient_mode).is_false()

	# Pulsar tecla G
	var ev_g := InputEventKey.new()
	ev_g.keycode = KEY_G
	ev_g.pressed = true
	move_tool._handle_key_shortcuts(KEY_G)

	# Modo degradado activo
	assert_bool(move_tool.is_gradient_mode).is_true()
	assert_bool(bb.is_gradient_active()).is_true()
	assert_bool(shape.has_gradient_fill()).is_true()
	assert_bool(bb.has_gradient_annotator()).is_true()

	# Pulsar tecla G de nuevo conmuta a desactivado (bloqueado)
	move_tool._handle_key_shortcuts(KEY_G)
	assert_bool(move_tool.is_gradient_mode).is_false()
	assert_bool(bb.is_gradient_active()).is_false()
	assert_bool(bb.has_gradient_annotator()).is_false()

	# Pulsar tecla G de nuevo y luego ESCAPE desactiva el modo degradado
	move_tool._handle_key_shortcuts(KEY_G)
	assert_bool(move_tool.is_gradient_mode).is_true()
	assert_bool(bb.has_gradient_annotator()).is_true()

	move_tool._handle_key_shortcuts(KEY_ESCAPE)
	assert_bool(move_tool.is_gradient_mode).is_false()
	assert_bool(bb.is_gradient_tool_active).is_false()
	assert_bool(bb.has_gradient_annotator()).is_false()

func test_exit_gradient_mode_allows_dragging_shape_by_fill_without_editing_gradient() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.position = Vector2(50, 50)
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.2, 0.5), Vector2(0.8, 0.5))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb

	# 1. Entrar en modo degradado (tecla G)
	move_tool._handle_key_shortcuts(KEY_G)
	assert_bool(move_tool.is_gradient_mode).is_true()
	assert_bool(bb.has_gradient_annotator()).is_true()

	# 2. Salir del modo degradado (tecla G conmutada para bloquear / usar selección)
	move_tool._handle_key_shortcuts(KEY_G)
	assert_bool(move_tool.is_gradient_mode).is_false()
	assert_bool(bb.has_gradient_annotator()).is_false()

	# 3. Clic y arrastre sobre el relleno del elemento (panel de arrastre)
	# Clic en Vector2(100, 100), justo donde cruza la línea del degradado
	var p0_init: Vector2 = shape.get_gradient_p0_norm()
	var p1_init: Vector2 = shape.get_gradient_p1_norm()

	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = Vector2(100, 100)
	bb._on_drag_panel_gui_input(ev_press)

	assert_bool(bb._is_dragging_canvas_area).is_true()
	assert_bool(move_tool.is_dragging_shape).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("")

	# Mover el ratón con botón izquierdo
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev_motion.global_position = Vector2(130, 120)
	bb._on_drag_panel_gui_input(ev_motion)

	# Soltar el clic
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.global_position = Vector2(130, 120)
	bb._on_drag_panel_gui_input(ev_up)

	assert_bool(bb._is_dragging_canvas_area).is_false()
	assert_bool(move_tool.is_dragging_shape).is_false()

	# Los puntos del degradado NO fueron alterados accidentalmente
	assert_vector(shape.get_gradient_p0_norm()).is_equal_approx(p0_init, Vector2(0.0001, 0.0001))
	assert_vector(shape.get_gradient_p1_norm()).is_equal_approx(p1_init, Vector2(0.0001, 0.0001))

func test_empty_click_in_gradient_mode_preserves_selection_and_annotator() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.1, 0.5), Vector2(0.9, 0.5))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]
	move_tool.is_gradient_mode = true

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb

	# Clic en el canvas fuera de la figura y fuera de los handles (ej: (300, 300))
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_global_transform() * Vector2(300, 300)
	var handled_down: bool = bb.handle_annotator_input(ev_press)
	assert_bool(handled_down).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("drag_new")

	# Soltar el clic sin arrastre
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.global_position = bb.get_global_transform() * Vector2(300, 300)
	var handled_up: bool = bb.handle_annotator_input(ev_release)
	assert_bool(handled_up).is_true()

	# La figura sigue seleccionada y el anotador sigue activo y visible!
	assert_int(move_tool.selected_shapes.size()).is_equal(1)
	assert_bool(bb.has_gradient_annotator()).is_true()
	assert_bool(bb.visible).is_true()

func test_gradient_stop_selection_and_sync() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	g.add_point(0.5, Color.GREEN)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var received_data: Dictionary = {"idx": -1, "color": Color.BLACK}
	var on_stop_selected = func(c: Color, idx: int):
		received_data["idx"] = idx
		received_data["color"] = c
	GlobalEvents.gradient_stop_selected.connect(on_stop_selected)

	var xform: Transform2D = bb.get_global_transform()

	# 1. Clic en p0 (x=0, y=50) debe seleccionar el stop 0
	var ev_p0 := InputEventMouseButton.new()
	ev_p0.button_index = MOUSE_BUTTON_LEFT
	ev_p0.pressed = true
	ev_p0.global_position = xform * Vector2(0, 50)
	bb._handle_annotator_input(ev_p0)
	assert_int(bb._selected_gradient_stop_idx).is_equal(0)
	assert_int(received_data["idx"]).is_equal(0)
	assert_str((received_data["color"] as Color).to_html()).is_equal(Color.RED.to_html())

	# 2. Clic en p1 (x=100, y=50) debe seleccionar el último stop (índice 2)
	var ev_p1 := InputEventMouseButton.new()
	ev_p1.button_index = MOUSE_BUTTON_LEFT
	ev_p1.pressed = true
	ev_p1.global_position = xform * Vector2(100, 50)
	bb._handle_annotator_input(ev_p1)
	assert_int(bb._selected_gradient_stop_idx).is_equal(2)
	assert_int(received_data["idx"]).is_equal(2)
	assert_str((received_data["color"] as Color).to_html()).is_equal(Color.BLUE.to_html())

	# 3. Clic en stop intermedio (x=50, y=50) debe seleccionar el stop 1
	var ev_stop1 := InputEventMouseButton.new()
	ev_stop1.button_index = MOUSE_BUTTON_LEFT
	ev_stop1.pressed = true
	ev_stop1.global_position = xform * Vector2(50, 50)
	bb._handle_annotator_input(ev_stop1)
	assert_int(bb._selected_gradient_stop_idx).is_equal(1)
	assert_int(received_data["idx"]).is_equal(1)
	assert_str((received_data["color"] as Color).to_html()).is_equal(Color.GREEN.to_html())

	GlobalEvents.gradient_stop_selected.disconnect(on_stop_selected)

func test_gradient_color_panel_sync_preserves_endpoints() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	shape.fill_gradient = g
	# Endpoints personalizados en diagonal
	shape.set_gradient_points(Vector2(0.2, 0.1), Vector2(0.8, 0.9))
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	var p0_orig := shape.fill_gradient_p0
	var p1_orig := shape.fill_gradient_p1
	var angle_orig := shape.fill_gradient_angle

	# Simular actualización de color de stop a través de ColorCore (como lo hace el color picker)
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		var updated_paint: Dictionary = cc.make_linear(g, angle_orig, p0_orig, p1_orig)
		# Modificar el color del primer stop
		g.set_color(0, Color.YELLOW)
		cc.set_paint(updated_paint, "fill")

		# Verificar que los endpoints p0 y p1 NO se corrompieron ni resetearon
		assert_vector(shape.fill_gradient_p0).is_equal_approx(p0_orig, Vector2(0.001, 0.001))
		assert_vector(shape.fill_gradient_p1).is_equal_approx(p1_orig, Vector2(0.001, 0.001))

func test_delete_intermediate_stop_preserves_endpoints() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	g.add_point(0.4, Color.YELLOW)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.1, 0.2), Vector2(0.9, 0.8))
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	assert_int(g.get_point_count()).is_equal(3)
	bb._selected_gradient_stop_idx = 1 # Seleccionar el stop intermedio amarillo

	# Presionar tecla DELETE
	var ev_del := InputEventKey.new()
	ev_del.keycode = KEY_DELETE
	ev_del.pressed = true
	var handled: bool = bb._handle_annotator_input(ev_del)
	assert_bool(handled).is_true()

	# Ahora el gradiente debe tener 2 stops
	assert_int(g.get_point_count()).is_equal(2)
	# Los extremos p0 y p1 deben permanecer 100% fijos
	assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.1, 0.2), Vector2(0.001, 0.001))
	assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.9, 0.8), Vector2(0.001, 0.001))

func test_gradient_extended_types_data_and_rendering() -> void:
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(120, 80)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	shape.fill_gradient = g

	# Probar Diamante (3)
	shape.fill_gradient_type = 3
	var tex_diamond = shape._ensure_grad_tex()
	assert_that(tex_diamond).is_not_null()
	assert_int(tex_diamond.get_width()).is_equal(512)

	# Probar Box (4)
	shape.fill_gradient_type = 4
	var tex_box = shape._ensure_grad_tex()
	assert_that(tex_box).is_not_null()
	assert_int(tex_box.get_width()).is_equal(512)

	# Probar Spiral (5)
	shape.fill_gradient_type = 5
	var tex_spiral = shape._ensure_grad_tex()
	assert_that(tex_spiral).is_not_null()
	assert_int(tex_spiral.get_width()).is_equal(512)

func test_gradient_alt_drag_duplicates_stop() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	g.add_point(0.5, Color.GREEN)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	assert_int(g.get_point_count()).is_equal(3)

	# Clic en stop intermedio con Alt presionado
	var ev_alt := InputEventMouseButton.new()
	ev_alt.button_index = MOUSE_BUTTON_LEFT
	ev_alt.pressed = true
	ev_alt.alt_pressed = true
	ev_alt.global_position = bb.get_global_transform() * Vector2(50, 50)
	bb._handle_annotator_input(ev_alt)

	# Debe haberse clonado el stop intermedio (ahora 4 stops)
	assert_int(g.get_point_count()).is_equal(4)

func test_gradient_shift_snapping() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	g.add_point(0.5, Color.GREEN)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.0, 0.5), Vector2(1.0, 0.5))
	root.add_child(shape)

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()

	# 1. Drag stop con Shift presionado: t = 0.48 debe snappear a 0.5
	bb._annotator_drag_mode = "stop"
	bb._annotator_drag_stop_idx = 1
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.shift_pressed = true
	ev_motion.global_position = bb.get_global_transform() * Vector2(48, 50) # 0.48 local
	bb._handle_annotator_input(ev_motion)

	assert_float(g.get_offset(1)).is_equal_approx(0.5, 0.01)

func test_gradient_copy_paste_style() -> void:
	var shape1: VectorRectangle = auto_free(VectorRectangle.new())
	shape1.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.YELLOW)
	g.set_color(1, Color.MAGENTA)
	shape1.fill_gradient = g
	shape1.fill_gradient_type = 3 # Diamond
	shape1.set_gradient_points(Vector2(0.25, 0.25), Vector2(0.75, 0.75))

	var shape2: VectorRectangle = auto_free(VectorRectangle.new())
	shape2.size = Vector2(100, 100)

	var cc = get_node_or_null("/root/ColorCore")
	assert_that(cc).is_not_null()
	cc.copy_gradient_style(shape1)

	var pasted: bool = cc.paste_gradient_style(shape2)
	assert_bool(pasted).is_true()
	assert_int(shape2.fill_gradient_type).is_equal(3)
	assert_vector(shape2.fill_gradient_p0).is_equal_approx(Vector2(0.25, 0.25), Vector2(0.001, 0.001))
	assert_vector(shape2.fill_gradient_p1).is_equal_approx(Vector2(0.75, 0.75), Vector2(0.001, 0.001))
	assert_str(shape2.fill_gradient.get_color(0).to_html()).is_equal(Color.YELLOW.to_html())
	assert_str(shape2.fill_gradient.get_color(1).to_html()).is_equal(Color.MAGENTA.to_html())

func test_gradient_non_destructive_type_switching() -> void:
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	g.add_point(0.4, Color.GREEN)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.2, 0.3), Vector2(0.8, 0.7))

	# Iterar por los 6 tipos (0..5)
	for t in [0, 1, 2, 3, 4, 5, 0]:
		shape.fill_gradient_type = t
		# El número de stops debe ser siempre 3
		assert_int(shape.fill_gradient.get_point_count()).is_equal(3)
		# Los colores deben preservarse exactamente
		assert_str(shape.fill_gradient.get_color(0).to_html()).is_equal(Color.RED.to_html())
		assert_str(shape.fill_gradient.get_color(1).to_html()).is_equal(Color.GREEN.to_html())
		assert_str(shape.fill_gradient.get_color(2).to_html()).is_equal(Color.BLUE.to_html())
		# Los puntos extremos p0 y p1 deben preservarse
		assert_vector(shape.fill_gradient_p0).is_equal_approx(Vector2(0.2, 0.3), Vector2(0.001, 0.001))
		assert_vector(shape.fill_gradient_p1).is_equal_approx(Vector2(0.8, 0.7), Vector2(0.001, 0.001))

func test_gradient_presets_application() -> void:
	var editor: Control = auto_free(load("res://scenes/ui/gradient.tscn").instantiate())
	add_child(editor)
	
	# Aplicar preset "Sunset"
	editor.apply_preset("Sunset")
	var g: Gradient = editor.get_gradient()
	assert_int(g.get_point_count()).is_equal(3)
	assert_str(g.get_color(0).to_html()).is_equal(editor.PRESETS["Sunset"][0].to_html())

	# Aplicar preset "Cyber Neon"
	editor.apply_preset("Cyber Neon")
	var g2: Gradient = editor.get_gradient()
	assert_int(g2.get_point_count()).is_equal(3)
	assert_str(g2.get_color(0).to_html()).is_equal(editor.PRESETS["Cyber Neon"][0].to_html())

func test_drag_handle_outside_and_back_inside() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	g.set_color(0, Color.RED)
	g.set_color(1, Color.BLUE)
	shape.fill_gradient = g
	shape.set_gradient_points(Vector2(0.2, 0.5), Vector2(0.8, 0.5))
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes = [shape]

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	# 1. Handle p1 inicial está en (80, 50)
	var data: Dictionary = bb._get_gradient_annotator_data()
	assert_vector(data.p1).is_equal_approx(Vector2(80, 50), Vector2(0.01, 0.01))

	# 2. Arrastrar p1 hacia afuera del bounding box (x = 250, > 100)
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_screen_transform() * data.p1
	assert_bool(bb.handle_annotator_input(ev_press)).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("end")

	var outside_pt := Vector2(250, 50)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_screen_transform() * outside_pt
	assert_bool(bb.handle_annotator_input(ev_motion)).is_true()
	assert_vector(shape.get_gradient_p1_norm()).is_equal_approx(Vector2(2.5, 0.5), Vector2(0.01, 0.01))

	# 3. Soltar el ratón afuera
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.global_position = bb.get_screen_transform() * outside_pt
	assert_bool(bb.handle_annotator_input(ev_up)).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("")

	# 4. Verificar que p1 quedó afuera
	var data2: Dictionary = bb._get_gradient_annotator_data()
	assert_vector(data2.p1).is_equal_approx(Vector2(250, 50), Vector2(0.01, 0.01))

	# 5. Pulsar sobre p1 afuera para arrastrarlo de vuelta hacia adentro (a x = 70)
	var ev_press2 := InputEventMouseButton.new()
	ev_press2.button_index = MOUSE_BUTTON_LEFT
	ev_press2.pressed = true
	ev_press2.global_position = bb.get_screen_transform() * data2.p1
	assert_bool(bb.handle_annotator_input(ev_press2)).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("end")

	var inside_pt := Vector2(70, 50)
	var ev_motion2 := InputEventMouseMotion.new()
	ev_motion2.global_position = bb.get_screen_transform() * inside_pt
	assert_bool(bb.handle_annotator_input(ev_motion2)).is_true()
	assert_vector(shape.get_gradient_p1_norm()).is_equal_approx(Vector2(0.7, 0.5), Vector2(0.01, 0.01))

	var ev_up2 := InputEventMouseButton.new()
	ev_up2.button_index = MOUSE_BUTTON_LEFT
	ev_up2.pressed = false
	ev_up2.global_position = bb.get_screen_transform() * inside_pt
	assert_bool(bb.handle_annotator_input(ev_up2)).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("")

	# 6. El endpoint regresó exitosamente adentro
	var data3: Dictionary = bb._get_gradient_annotator_data()
	assert_vector(data3.p1).is_equal_approx(Vector2(70, 50), Vector2(0.01, 0.01))

func test_switch_to_solid_color_clears_gradient_completely() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)

	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	shape.size = Vector2(100, 100)
	var g := Gradient.new()
	shape.fill_gradient = g
	root.add_child(shape)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = root
	move_tool.selected_shapes.assign([shape])
	SelectionManager.set_selection([shape])
	InspectorCore._sync_selection()

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	root.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	assert_bool(shape.has_gradient_fill()).is_true()
	assert_bool(bb.has_gradient_annotator()).is_true()

	# Aplicar color sólido vía InspectorCore
	InspectorCore.apply("fill_paint", {"type": "solid", "color": Color.YELLOW})
	bb._sincronizar_dimensiones_en_canvas()

	assert_bool(shape.has_gradient_fill()).is_false()
	assert_that(shape.fill_gradient).is_null()
	assert_that(shape._grad_tex).is_null()
	assert_str(shape.fill_color.to_html(false)).is_equal(Color.YELLOW.to_html(false))
	assert_bool(bb.has_gradient_annotator()).is_false()

func test_generate_visual_verification_snapshots() -> void:
	var subvp: SubViewport = auto_free(SubViewport.new())
	subvp.size = Vector2i(1000, 700)
	subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subvp.msaa_2d = Viewport.MSAA_8X
	add_child(subvp)

	var canvas: Node2D = auto_free(Node2D.new())
	subvp.add_child(canvas)

	var ab: Node2D = auto_free(Node2D.new())
	ab.name = "Artboard"
	canvas.add_child(ab)

	# 1. Trazo curvo y trazos diagonales (para verificar nitidez absoluta sin blur con zoom)
	var vpath: VectorPath = auto_free(VectorPath.new())
	vpath.stroke_color = Color(0.1, 0.1, 0.1, 1.0)
	vpath.stroke_width = 3.0
	var curve: Curve2D = Curve2D.new()
	curve.add_point(Vector2(50, 80), Vector2(0, 0), Vector2(40, -40))
	curve.add_point(Vector2(200, 150), Vector2(-40, 40), Vector2(40, 40))
	curve.add_point(Vector2(320, 80), Vector2(-40, -40), Vector2(0, 0))
	vpath.curve = curve
	ab.add_child(vpath)

	# 2. Rectángulo vectorial con degradado
	var rect_shape: VectorRectangle = auto_free(VectorRectangle.new())
	rect_shape.position = Vector2(450, 80)
	rect_shape.size = Vector2(250, 200)
	rect_shape.stroke_width = 2.0
	rect_shape.stroke_color = Color(0.2, 0.2, 0.2, 1.0)
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(0.95, 0.2, 0.3, 1.0))
	g.set_color(1, Color(0.1, 0.5, 0.95, 1.0))
	rect_shape.fill_gradient = g
	rect_shape.set_gradient_points(Vector2(0.1, 0.2), Vector2(0.9, 0.8))
	ab.add_child(rect_shape)

	# Cámara a 1.5x zoom
	var cam: Camera2D = auto_free(Camera2D.new())
	cam.position = Vector2(400, 250)
	cam.zoom = Vector2(1.5, 1.5)
	canvas.add_child(cam)

	var move_tool: MoveTool = auto_free(MoveTool.new())
	move_tool.canvas = canvas
	move_tool.target_artboard = ab
	canvas.add_child(move_tool)
	move_tool.selected_shapes.assign([rect_shape])
	SelectionManager.set_selection([rect_shape])
	InspectorCore._sync_selection()
	move_tool.activate()

	var bb: Control = auto_free(_BoundingBoxScene.instantiate())
	canvas.add_child(bb)
	bb.move_tool_reference = move_tool
	bb.target_node = rect_shape
	bb._sincronizar_dimensiones_en_canvas()
	move_tool._bounding_box = bb
	move_tool.is_gradient_mode = true
	bb.is_gradient_tool_active = true

	await get_tree().process_frame
	await get_tree().process_frame

	# Snapshot 1: Nitidez vectorial de trazos y degradado inicial
	subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var img1: Image = subvp.get_texture().get_image() if subvp.get_texture() else null
	if img1:
		img1.save_png("C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/final_verification_step1_initial.png")

	# Snapshot 2: Arrastre de endpoint P1 fuera del BoundingBox
	var data_init: Dictionary = bb._get_gradient_annotator_data()
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.global_position = bb.get_screen_transform() * data_init.p1
	bb.handle_annotator_input(ev_press)

	var outside_pos := Vector2(380, 260)
	var ev_motion := InputEventMouseMotion.new()
	ev_motion.global_position = bb.get_screen_transform() * outside_pos
	bb.handle_annotator_input(ev_motion)

	var ev_rel := InputEventMouseButton.new()
	ev_rel.button_index = MOUSE_BUTTON_LEFT
	ev_rel.pressed = false
	ev_rel.global_position = bb.get_screen_transform() * outside_pos
	bb.handle_annotator_input(ev_rel)

	await get_tree().process_frame
	await get_tree().process_frame

	subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var img2: Image = subvp.get_texture().get_image() if subvp.get_texture() else null
	if img2:
		img2.save_png("C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/final_verification_step2_dragged_outside.png")

	# Snapshot 3: Re-captura del handle desde fuera y arrastre de vuelta adentro
	var data_outside: Dictionary = bb._get_gradient_annotator_data()
	var ev_press2 := InputEventMouseButton.new()
	ev_press2.button_index = MOUSE_BUTTON_LEFT
	ev_press2.pressed = true
	ev_press2.global_position = bb.get_screen_transform() * data_outside.p1
	assert_bool(bb.handle_annotator_input(ev_press2)).is_true()
	assert_str(bb._annotator_drag_mode).is_equal("end")

	var inside_pos := Vector2(150, 150)
	var ev_motion2 := InputEventMouseMotion.new()
	ev_motion2.global_position = bb.get_screen_transform() * inside_pos
	bb.handle_annotator_input(ev_motion2)

	var ev_rel2 := InputEventMouseButton.new()
	ev_rel2.button_index = MOUSE_BUTTON_LEFT
	ev_rel2.pressed = false
	ev_rel2.global_position = bb.get_screen_transform() * inside_pos
	bb.handle_annotator_input(ev_rel2)

	await get_tree().process_frame
	await get_tree().process_frame

	subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var img3: Image = subvp.get_texture().get_image() if subvp.get_texture() else null
	if img3:
		img3.save_png("C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/final_verification_step3_dragged_back_inside.png")

	# Snapshot 4: Aplicar Color Sólido
	InspectorCore.apply("fill_paint", {"type": "solid", "color": Color(0.12, 0.78, 0.45, 1.0)})
	bb._sincronizar_dimensiones_en_canvas()

	await get_tree().process_frame
	await get_tree().process_frame

	subvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var img4: Image = subvp.get_texture().get_image() if subvp.get_texture() else null
	if img4:
		img4.save_png("C:/Users/User/.gemini/antigravity/brain/06b99786-f4f0-4362-b0cf-e6e599ce2686/final_verification_step4_solid_color_active.png")

	assert_bool(rect_shape.has_gradient_fill()).is_false()
	assert_bool(bb.has_gradient_annotator()).is_false()





