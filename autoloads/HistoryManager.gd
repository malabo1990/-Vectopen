extends Node

signal history_changed(can_undo: bool, can_redo: bool, undo_name: String, redo_name: String)
signal undo_performed(action_name: String)
signal redo_performed(action_name: String)

var _undo_redo: UndoRedoManager

func _ready() -> void:
	_undo_redo = UndoRedoManager.new()
	_undo_redo.max_history = 100
	_undo_redo.version_changed.connect(_on_version_changed)

func register_action(name: String) -> void:
	_undo_redo.create_action(name)

func add_do(callable: Callable) -> void:
	_undo_redo.add_do_method(callable)

func add_undo(callable: Callable) -> void:
	_undo_redo.add_undo_method(callable)

func commit() -> void:
	_undo_redo.commit_action()

func undo() -> void:
	if _undo_redo.can_undo():
		_undo_redo.undo()
		undo_performed.emit(_undo_redo.get_undo_name())
		if DataRepository:
			DataRepository.is_project_modified = true

func redo() -> void:
	if _undo_redo.can_redo():
		_undo_redo.redo()
		redo_performed.emit(_undo_redo.get_redo_name())
		if DataRepository:
			DataRepository.is_project_modified = true

func can_undo() -> bool:
	return _undo_redo.can_undo()

func can_redo() -> bool:
	return _undo_redo.can_redo()

func get_undo_name() -> String:
	return _undo_redo.get_undo_name()

func get_redo_name() -> String:
	return _undo_redo.get_redo_name()

func clear() -> void:
	_undo_redo.clear()

func _on_version_changed(can_undo: bool, can_redo: bool) -> void:
	history_changed.emit(can_undo, can_redo, _undo_redo.get_undo_name(), _undo_redo.get_redo_name())
