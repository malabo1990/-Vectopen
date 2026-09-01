extends GdUnitTestSuite

## SelectionManager (Fase 1) — autoridad única de la selección viva.

var _sm: Node

func before_test() -> void:
	_sm = get_node_or_null("/root/SelectionManager")
	assert_object(_sm).is_not_null()
	_sm.clear()

func after_test() -> void:
	if is_instance_valid(_sm):
		_sm.clear()

func _n(parent: Node = null) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	if parent:
		parent.add_child(n)
	else:
		add_child(n)
	return n


func test_select_replace_sets_single() -> void:
	var a := _n()
	var b := _n()
	_sm.select(a)
	_sm.select(b)
	assert_array(_sm.get_selected()).contains_exactly([b])
	assert_object(_sm.get_active()).is_same(b)


func test_select_add_accumulates() -> void:
	var a := _n()
	var b := _n()
	_sm.select(a)
	_sm.select(b, _sm.Mode.ADD)
	assert_array(_sm.get_selected()).contains_exactly([a, b])


func test_select_toggle_removes_and_readds() -> void:
	var a := _n()
	_sm.select(a)
	_sm.select(a, _sm.Mode.TOGGLE)
	assert_array(_sm.get_selected()).is_empty()
	_sm.select(a, _sm.Mode.TOGGLE)
	assert_array(_sm.get_selected()).contains_exactly([a])


func test_locked_nodes_are_not_selectable() -> void:
	var a := _n()
	a.set_meta("locked", true)
	_sm.select(a)
	assert_array(_sm.get_selected()).is_empty()


func test_lock_is_inherited_from_ancestor() -> void:
	var grupo := _n()
	grupo.set_meta("locked", true)
	var hijo := _n(grupo)
	_sm.select(hijo)
	assert_array(_sm.get_selected()).is_empty()
	assert_bool(_sm.locked_by_inheritance(hijo)).is_true()
	assert_bool(_sm.locked_by_inheritance(grupo)).is_false()  # bloqueo directo, no heredado


func test_render_helper_names_are_not_selectable() -> void:
	var a := _n()
	a.name = "Contorno_Stroke"
	_sm.select(a)
	assert_array(_sm.get_selected()).is_empty()


func test_freed_nodes_are_pruned() -> void:
	var a: Node2D = Node2D.new()
	add_child(a)
	_sm.select(a)
	a.free()
	assert_array(_sm.get_selected()).is_empty()


func test_emits_changed_once_per_op() -> void:
	var a := _n()
	var b := _n()
	var spy := [0]   # array: los lambdas de GDScript capturan por valor
	var cb := func(_sel): spy[0] += 1
	_sm.changed.connect(cb)
	_sm.select_many([a, b])
	_sm.changed.disconnect(cb)
	assert_int(spy[0]).is_equal(1)


func test_batch_coalesces_into_one_changed() -> void:
	var a := _n()
	var b := _n()
	var spy := [0]
	var cb := func(_sel): spy[0] += 1
	_sm.changed.connect(cb)
	_sm.begin_batch()
	_sm.select(a, _sm.Mode.ADD)
	_sm.select(b, _sm.Mode.ADD)
	assert_int(spy[0]).is_equal(0)
	_sm.end_batch()
	_sm.changed.disconnect(cb)
	assert_int(spy[0]).is_equal(1)


func test_reemits_global_selection_changed() -> void:
	var a := _n()
	var got := [null]
	var cb := func(shapes): got[0] = shapes
	GlobalEvents.selection_changed.connect(cb)
	_sm.select(a)
	GlobalEvents.selection_changed.disconnect(cb)
	assert_array(got[0]).contains_exactly([a])


func test_select_children_selects_direct_layers_only() -> void:
	var group := _n()
	var c1 := _n(group)
	var c2 := _n(group)
	var grand := _n(c1)
	_sm.select_children(group)
	assert_array(_sm.get_selected()).contains_exactly([c1, c2])
	assert_bool(_sm.is_selected(grand)).is_false()


func test_select_descendants_recurses() -> void:
	var group := _n()
	var c1 := _n(group)
	var grand := _n(c1)
	_sm.select_descendants(group)
	assert_array(_sm.get_selected()).contains([c1, grand])
	assert_bool(_sm.is_selected(group)).is_false()


func test_select_branch_includes_node_and_descendants() -> void:
	var group := _n()
	var c1 := _n(group)
	_sm.select_branch(group)
	assert_array(_sm.get_selected()).contains([group, c1])


func test_clear_resets_active_and_anchor() -> void:
	var a := _n()
	_sm.select(a)
	_sm.clear()
	assert_array(_sm.get_selected()).is_empty()
	assert_object(_sm.get_active()).is_null()
	assert_object(_sm.get_anchor()).is_null()
