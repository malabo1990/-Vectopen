# =============================================================================
# VECTOPEN — Audit of every parametric shape property through InspectorCore:
# the geometry must really change and undo must restore it.
# RUTA: res://test/shapes/ParametricAudit_test.gd
# =============================================================================
extends GdUnitTestSuite

func _setup_shape(shape: Node2D) -> MoveTool:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var ab: ArtboardEditor = auto_free(ArtboardEditor.new())
	root.add_child(ab)
	ab.add_child(shape)
	shape.position = Vector2(200, 200)
	var mt: MoveTool = auto_free(MoveTool.new())
	mt.canvas = root
	mt.target_artboard = ab
	mt.selected_shapes = [shape]
	SelectionManager.set_selection([shape])
	InspectorCore._sync_selection()
	HistoryManager.clear()
	return mt

## Applies `prop = value`, checks the outline changed, then undo restores it.
func _check(shape: Node2D, prop: String, value) -> void:
	var before: PackedVector2Array = shape.get_effect_points().duplicate()
	InspectorCore.apply(prop, value)
	await get_tree().process_frame
	var after: PackedVector2Array = shape.get_effect_points()
	assert_bool(before != after).override_failure_message("%s: %s=%s did not change the geometry" % [shape.get_class(), prop, str(value)]).is_true()
	assert_bool(HistoryManager.can_undo()).override_failure_message("%s: %s not undoable" % [shape.get_class(), prop]).is_true()
	HistoryManager.undo()
	await get_tree().process_frame
	assert_bool(shape.get_effect_points() == before).override_failure_message("%s: undo of %s did not restore" % [shape.get_class(), prop]).is_true()

func test_circle_parameters() -> void:
	var c: VectorCircle = auto_free(VectorCircle.new())
	_setup_shape(c)
	await _check(c, "shape_mode", "pie")
	c.shape_mode = "arc"
	await _check(c, "start_angle_deg", 45.0)
	await _check(c, "end_angle_deg", 200.0)
	c.shape_mode = "donut"
	await _check(c, "inner_radius_ratio", 0.2)

func test_star_parameters() -> void:
	var s: VectorStar = auto_free(VectorStar.new())
	_setup_shape(s)
	await _check(s, "points_count", 8)
	await _check(s, "inner_radius_ratio", 0.7)
	await _check(s, "corner_radius", 6.0)

func test_polygon_parameters() -> void:
	var p: VectorPolygon = auto_free(VectorPolygon.new())
	p.is_regular = true
	p.sides = 5
	_setup_shape(p)
	await _check(p, "sides", 8)
	await _check(p, "corner_radius", 10.0)

func after_test() -> void:
	SelectionManager.clear()
