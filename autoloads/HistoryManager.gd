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

func register_action(action_name: String) -> void:
	_undo_redo.create_action(action_name)

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

## Registra la creación de una figura YA añadida a la escena (una herramienta
## de dibujo, un panel…): deshacer la quita, rehacer la vuelve a poner en el
## mismo padre y posición. No ejecuta nada ahora.
func record_create(node: Node, action_name: String = "") -> void:
	if not is_instance_valid(node) or node.get_parent() == null:
		return
	var parent := node.get_parent()
	var idx := node.get_index()
	var owner_node := node.owner
	register_action(action_name if not action_name.is_empty() else "Crear %s" % node.name)
	add_do(func() -> void:
		if is_instance_valid(parent) and is_instance_valid(node) and node.get_parent() == null:
			parent.add_child(node)
			parent.move_child(node, mini(idx, parent.get_child_count() - 1))
			node.owner = owner_node)
	add_undo(func() -> void:
		if is_instance_valid(node) and node.get_parent() == parent:
			var sm := get_node_or_null("/root/SelectionManager")
			if sm and sm.has_method("is_selected") and sm.is_selected(node):
				sm.deselect(node)
			parent.remove_child(node))
	commit()

func clear() -> void:
	_undo_redo.clear()

func _on_version_changed(undo_available: bool, redo_available: bool) -> void:
	history_changed.emit(undo_available, redo_available, _undo_redo.get_undo_name(), _undo_redo.get_redo_name())
