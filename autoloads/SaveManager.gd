extends Node

signal project_saved(path: String)
signal project_loaded(path: String)
signal save_state_changed(is_modified: bool)

var current_path: String = ""
var is_modified: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save"):
		save()
		get_viewport().set_input_as_handled()

func save() -> void:
	if current_path.is_empty():
		save_as()
		return
	_save_to_path(current_path)

func save_as() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Guardar proyecto"
	fd.add_filter("*.vtc", "Vectopen Project")
	fd.add_filter("*.json", "JSON Backup")
	fd.file_selected.connect(_on_save_as_selected)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 600))

func _on_save_as_selected(path: String) -> void:
	current_path = path
	_save_to_path(path)

func _save_to_path(path: String) -> void:
	if not DataRepository:
		push_error("SaveManager: DataRepository no disponible")
		return
	DataRepository.save_project(path)
	is_modified = false
	save_state_changed.emit(false)
	project_saved.emit(path)
	RecentFilesManager.add_file(path)

func open(path: String) -> void:
	if not DataRepository:
		push_error("SaveManager: DataRepository no disponible")
		return
	DataRepository.load_project(path)
	current_path = path
	is_modified = false
	save_state_changed.emit(false)
	project_loaded.emit(path)
	RecentFilesManager.add_file(path)

func new_project(project_name: String = "Sin título") -> void:
	if not DataRepository:
		return
	DataRepository.new_project(project_name)
	current_path = ""
	is_modified = false
	save_state_changed.emit(false)

func mark_modified() -> void:
	is_modified = true
	save_state_changed.emit(true)
