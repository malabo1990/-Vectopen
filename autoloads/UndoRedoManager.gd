class_name UndoRedoManager
extends RefCounted

signal version_changed(can_undo: bool, can_redo: bool)

class Action:
	var name: String
	var do_callables: Array[Callable] = []
	var undo_callables: Array[Callable] = []

	func _init(p_name: String) -> void:
		name = p_name

var undo_stack: Array[Action] = []
var redo_stack: Array[Action] = []
var max_history: int = 100

func create_action(name: String) -> void:
	var action = Action.new(name)
	undo_stack.append(action)
	while undo_stack.size() > max_history:
		undo_stack.pop_front()
	redo_stack.clear()
	version_changed.emit(can_undo(), can_redo())

func add_do_method(callable: Callable) -> void:
	if undo_stack.is_empty():
		return
	undo_stack[-1].do_callables.append(callable)

func add_undo_method(callable: Callable) -> void:
	if undo_stack.is_empty():
		return
	undo_stack[-1].undo_callables.append(callable)

func commit_action() -> void:
	version_changed.emit(can_undo(), can_redo())

func undo() -> void:
	if undo_stack.is_empty():
		return
	var action = undo_stack.pop_back()
	_execute_callables_reverse(action.undo_callables)
	redo_stack.append(action)
	_trim_stack(redo_stack)
	version_changed.emit(can_undo(), can_redo())

func redo() -> void:
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back()
	_execute_callables(action.do_callables)
	undo_stack.append(action)
	_trim_stack(undo_stack)
	version_changed.emit(can_undo(), can_redo())

func can_undo() -> bool:
	return not undo_stack.is_empty()

func can_redo() -> bool:
	return not redo_stack.is_empty()

func clear() -> void:
	undo_stack.clear()
	redo_stack.clear()
	version_changed.emit(false, false)

func get_undo_name() -> String:
	if undo_stack.is_empty():
		return ""
	return undo_stack[-1].name

func get_redo_name() -> String:
	if redo_stack.is_empty():
		return ""
	return redo_stack[-1].name

func _execute_callables(arr: Array[Callable]) -> void:
	for c in arr:
		if c.is_valid():
			c.call()

func _execute_callables_reverse(arr: Array[Callable]) -> void:
	for i in range(arr.size() - 1, -1, -1):
		var c = arr[i]
		if c.is_valid():
			c.call()

func _trim_stack(stack: Array[Action]) -> void:
	while stack.size() > max_history:
		stack.pop_front()
