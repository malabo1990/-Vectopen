extends Node

## Pila única de undo/redo de la app (Ctrl+Z/Y en scripts/canvas/canvas.gd).
## Desde el 19/08/2026, ProjectManager registra aquí las acciones de
## CRUD de shapes/capas/artboards en vez de tener su propia pila
## desconectada — ver docs/*/reports/VECTOPEN_TECHNICAL_REPORT.md §1.7.

signal history_changed(can_undo: bool, can_redo: bool, undo_name: String, redo_name: String)
signal undo_performed(action_name: String)
signal redo_performed(action_name: String)

var _undo_redo: UndoRedoManager

func _ready() -> void:
	_undo_redo = UndoRedoManager.new()
	_undo_redo.max_history = ProjectManager.settings.max_undo_steps
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
