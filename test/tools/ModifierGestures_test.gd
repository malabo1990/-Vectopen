# =============================================================================
# VECTOPEN — Drag modifiers on the selection body, Alt+drag duplicate, opacity
# digit keys and the inspector's parametric polygon section.
# RUTA: res://test/tools/ModifierGestures_test.gd
# =============================================================================
extends GdUnitTestSuite

func _rig(with_artboard_target: bool = true) -> Dictionary:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var ab: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(ab)
	var shape: VectorRectangle = auto_free(VectorRectangle.new())
	ab.add_child(shape)
	shape.position = Vector2(100, 100)
	shape.size = Vector2(80, 60)
	shape.stroke_width = 2.0
	var mt: MoveTool = auto_free(MoveTool.new())
	mt.canvas = root
	if with_artboard_target:
		mt.target_artboard = ab
	mt.selected_shapes = [shape]
	return {"root": root, "ab": ab, "shape": shape, "mt": mt}

func _begin_body_drag(mt: MoveTool, at: Vector2) -> void:
	mt.is_dragging_shape = true
	mt.transform_initial_mouse = at
	mt.transform_initial_states.clear()
	for s in mt.selected_shapes:
		mt.transform_initial_states[s] = mt._snapshot(s)

func test_shift_drag_body_changes_stroke_not_position() -> void:
	var r := _rig()
	var mt: MoveTool = r["mt"]
	var shape: VectorRectangle = r["shape"]
	HistoryManager.clear()
	_begin_body_drag(mt, Vector2(100, 100))
	mt._on_motion(Vector2(140, 100), {"shift": true, "alt": false, "ctrl": false})
	assert_vector(shape.position).is_equal_approx(Vector2(100, 100), Vector2(0.01, 0.01))
	assert_float(shape.stroke_width).is_equal_approx(2.0 + 40.0 * 0.15, 0.01)
	mt._on_release(Vector2(140, 100))
	HistoryManager.undo()
	assert_float(shape.stroke_width).is_equal_approx(2.0, 0.01)

func test_ctrl_drag_body_locks_axis() -> void:
	var r := _rig()
	var mt: MoveTool = r["mt"]
	var shape: VectorRectangle = r["shape"]
	_begin_body_drag(mt, Vector2(100, 100))
	mt._on_motion(Vector2(160, 110), {"shift": false, "alt": false, "ctrl": true})
	assert_vector(shape.position).is_equal_approx(Vector2(160, 100), Vector2(0.01, 0.01))
	mt._on_release(Vector2(160, 110))

func test_alt_drag_duplicates_without_active_artboard() -> void:
	# Right after a session starts target_artboard is still null
	var r := _rig(false)
	var mt: MoveTool = r["mt"]
	var ab: ArtboardEditor = r["ab"]
	var shape: VectorRectangle = r["shape"]
	HistoryManager.clear()
	_begin_body_drag(mt, Vector2(100, 100))
	var count_before := ab.get_child_count()
	mt._on_motion(Vector2(160, 100), {"shift": false, "alt": true, "ctrl": false})
	assert_int(ab.get_child_count()).is_equal(count_before + 1)
	# The copy stays at the start position, below the dragged original
	var copy: Node2D = ab.get_child(shape.get_index() - 1)
	assert_object(copy).is_not_same(shape)
	assert_vector(copy.position).is_equal_approx(Vector2(100, 100), Vector2(0.01, 0.01))
	assert_vector(shape.position).is_equal_approx(Vector2(160, 100), Vector2(0.01, 0.01))
	mt._on_release(Vector2(160, 100))

func test_digit_keys_set_selection_opacity() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	if not (s.current_tool and s.current_tool.get_class_name() == "MoveTool"):
		s.switch_tool("move")
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var r := VectorRectangle.new()
	r.size = Vector2(50, 50)
	ab.add_child(r)
	s.current_tool.selected_shapes.assign([r])
	SelectionManager.set_selection([r])
	var ev := InputEventKey.new()
	ev.keycode = KEY_5
	ev.pressed = true
	assert_bool(s._handle_opacity_digit(ev)).is_true()
	assert_float(r.modulate.a).is_equal_approx(0.5, 0.001)
	# Two quick digits: 4 then 5 = 45%
	s._opacity_digit_first = -1
	ev.keycode = KEY_4
	s._handle_opacity_digit(ev)
	ev.keycode = KEY_5
	s._handle_opacity_digit(ev)
	assert_float(r.modulate.a).is_equal_approx(0.45, 0.001)
	SelectionManager.clear()
	# Without a selection the digit is left to other shortcuts (5 = reset zoom)
	s.current_tool.selected_shapes.clear()
	s._opacity_digit_first = -1
	assert_bool(s._handle_opacity_digit(ev)).is_false()

func test_inspector_polygon_section_live_drag_is_one_undo_step() -> void:
	var inspector: DockedInspector = auto_free(DockedInspector.new())
	add_child(inspector)
	await get_tree().process_frame
	var p: VectorPolygon = auto_free(VectorPolygon.new())
	p.is_regular = true
	p.sides = 5
	add_child(p)
	SelectionManager.set_selection([p])
	InspectorCore._sync_selection()
	inspector._on_selection_size_changed(1)
	assert_bool(inspector.sec_parametric_polygon.visible).is_true()
	HistoryManager.clear()
	# Scrub the Sides field: live updates, a single undo step at the end
	inspector.spin_poly_sides.drag_started.emit()
	for v in [6.0, 7.0, 8.0]:
		inspector.spin_poly_sides.value_changed.emit(v)
	inspector.spin_poly_sides.drag_ended.emit()
	assert_int(p.sides).is_equal(8)
	HistoryManager.undo()
	assert_int(p.sides).is_equal(5)
	assert_bool(HistoryManager.can_undo()).is_false()
	SelectionManager.clear()

## Regression: double-click on a text right after the session starts
## (target_artboard still null) crashed with
## "Cannot call method 'to_local' on a null value" (MoveTool.gd:704).
func test_double_click_text_without_target_artboard_does_not_crash() -> void:
	var s: Node2D = auto_free(load("res://scenes/canvas/canvas.tscn").instantiate())
	add_child(s)
	get_tree().current_scene = s
	await get_tree().process_frame
	var ab := (s.get_node("manager_script") as ArtboardManager).get_active_artboard()
	var t := Node2D.new()
	t.name = "Texto"
	t.set_meta("shape_type", "text_title")
	var dl := WorldTextLabel.new()
	dl.name = "DisplayLabel"
	dl.text = "Hola"
	t.add_child(dl)
	ab.add_child(t)
	t.position = Vector2(300, 300)
	await get_tree().process_frame
	s.switch_tool("select")
	var mt = s.get_current_tool()
	mt.target_artboard = null
	var gm: Vector2 = t.global_position + Vector2(5, 5)
	assert_object(mt._shape_at(gm)).is_same(t)
	assert_bool(mt._on_double_click(gm)).is_true()
	# Resolved to the text's own artboard and handed over to the text tool
	assert_object(s.get_current_tool().target_artboard).is_same(ab)
