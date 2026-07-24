extends GdUnitTestSuite

var _manager: UndoRedoManager

func before_test() -> void:
	_manager = UndoRedoManager.new()

func test_create_action_adds_to_stack() -> void:
	assert_int(_manager.undo_stack.size()).is_equal(0)
	assert_bool(_manager.can_undo()).is_false()

	_manager.create_action("Test Action")

	assert_int(_manager.undo_stack.size()).is_equal(1)
	assert_bool(_manager.can_undo()).is_true()
	assert_str(_manager.get_undo_name()).is_equal("Test Action")

func test_create_action_clears_redo_stack() -> void:
	_manager.create_action("First")
	_manager.commit_action()
	_manager.undo()

	assert_bool(_manager.can_redo()).is_true()

	_manager.create_action("Second")

	assert_bool(_manager.can_redo()).is_false()
	assert_int(_manager.undo_stack.size()).is_equal(1)

func test_undo_redo_cycle() -> void:
	var state := [5]

	_manager.create_action("Set")
	_manager.add_do_method(func(): state[0] = 5)
	_manager.add_undo_method(func(): state[0] = 0)
	_manager.commit_action()

	_manager.undo()
	assert_int(state[0]).is_equal(0)

	_manager.redo()
	assert_int(state[0]).is_equal(5)

func test_double_undo_redo() -> void:
	var state := [0]

	_manager.create_action("First")
	_manager.add_do_method(func(): state[0] += 1)
	_manager.add_undo_method(func(): state[0] -= 1)
	_manager.commit_action()

	_manager.create_action("Second")
	_manager.add_do_method(func(): state[0] += 2)
	_manager.add_undo_method(func(): state[0] -= 2)
	_manager.commit_action()

	_manager.undo()
	assert_int(state[0]).is_equal(-2)

	_manager.undo()
	assert_int(state[0]).is_equal(-3)

	_manager.redo()
	assert_int(state[0]).is_equal(-2)

	_manager.redo()
	assert_int(state[0]).is_equal(0)

func test_undo_empty_stack() -> void:
	_manager.undo()
	assert_int(_manager.undo_stack.size()).is_equal(0)

func test_redo_empty_stack() -> void:
	_manager.redo()
	assert_int(_manager.redo_stack.size()).is_equal(0)

func test_version_changed_signal_on_create() -> void:
	var fired: Array = [false]
	_manager.version_changed.connect(func(_cu, _cr): fired[0] = true, CONNECT_ONE_SHOT)
	_manager.create_action("Test")
	assert_bool(fired[0]).is_true()

func test_version_changed_signal_on_undo() -> void:
	var fired: Array = [false]
	_manager.version_changed.connect(func(_cu, _cr): fired[0] = true, CONNECT_ONE_SHOT)
	_manager.create_action("Test")
	_manager.commit_action()
	_manager.undo()
	assert_bool(fired[0]).is_true()

func test_version_changed_signal_on_clear() -> void:
	var fired: Array = [false]
	_manager.version_changed.connect(func(_cu, _cr): fired[0] = true, CONNECT_ONE_SHOT)
	_manager.clear()
	assert_bool(fired[0]).is_true()

func test_get_undo_name_empty() -> void:
	assert_str(_manager.get_undo_name()).is_equal("")

func test_get_redo_name_empty() -> void:
	assert_str(_manager.get_redo_name()).is_equal("")

func test_get_redo_name_after_undo() -> void:
	_manager.create_action("First")
	_manager.commit_action()
	_manager.undo()
	assert_str(_manager.get_redo_name()).is_equal("First")

func test_add_do_method_empty_stack() -> void:
	var called := [false]
	_manager.add_do_method(func(): called[0] = true)
	assert_bool(called[0]).is_false()

func test_clear_empties_both_stacks() -> void:
	_manager.create_action("A")
	_manager.create_action("B")
	_manager.clear()
	assert_bool(_manager.can_undo()).is_false()
	assert_bool(_manager.can_redo()).is_false()
	assert_int(_manager.undo_stack.size()).is_equal(0)
	assert_int(_manager.redo_stack.size()).is_equal(0)

func test_max_history_trims_oldest() -> void:
	_manager.max_history = 3
	for i in range(5):
		_manager.create_action("Action %d" % i)
	assert_int(_manager.undo_stack.size()).is_equal(3)
	assert_str(_manager.get_undo_name()).is_equal("Action 4")

func test_invalid_callable_skipped() -> void:
	_manager.create_action("Test")
	_manager.add_do_method(func(): pass)
	_manager.add_undo_method(func(): pass)
	_manager.commit_action()
	_manager.undo()
	assert_bool(true).is_true()

func test_action_constructor() -> void:
	var action := UndoRedoManager.Action.new("Named")
	assert_str(action.name).is_equal("Named")
	assert_array(action.do_callables).is_empty()
	assert_array(action.undo_callables).is_empty()
