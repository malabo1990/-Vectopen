extends Node

signal project_saved(path: String)
signal project_loaded(path: String)
signal save_state_changed(is_modified: bool)

var current_path: String = ""
var is_modified: bool = false
var _active_file_dialog: FileDialog = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save"):
		save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("new_project"):
		new_project()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_N and not event.shift_pressed and not event.alt_pressed:
			new_project()
			get_viewport().set_input_as_handled()

func save() -> void:
	if current_path.is_empty():
		save_as()
		return
	_save_to_path(current_path)

func save_as() -> void:
	if is_instance_valid(_active_file_dialog):
		_active_file_dialog.queue_free()
		_active_file_dialog = null

	var fd := FileDialog.new()
	_active_file_dialog = fd
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Guardar proyecto"
	fd.add_filter("*.vtc", "Vectopen Project")
	fd.add_filter("*.json", "JSON Backup")
	fd.file_selected.connect(func(path: String):
		_on_save_as_selected(path)
		if is_instance_valid(fd):
			fd.queue_free()
	)
	fd.canceled.connect(func():
		if is_instance_valid(fd):
			fd.queue_free()
	)
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
	_clean_canvas_for_new_project()

func _clean_canvas_for_new_project() -> void:
	var tree := get_tree()
	if not tree:
		return
	var sm = tree.root.get_node_or_null("SelectionManager")
	if sm and sm.has_method("clear_selection"):
		sm.clear_selection()

	var canvas = tree.get_first_node_in_group("_vectopen_canvas")
	var container: Node = null
	if canvas:
		container = canvas.get_node_or_null("ArtboardsContainer")
	if not container and tree.current_scene:
		container = tree.current_scene.find_child("ArtboardsContainer", true, false)

	if container:
		var artboards: Array[Node] = []
		for child in container.get_children():
			if child is ArtboardEditor:
				artboards.append(child)
			else:
				child.queue_free()

		if artboards.is_empty():
			var default_ab = ArtboardEditor.new()
			default_ab.name = "Artboard_1"
			default_ab.position = Vector2(100, 100)
			default_ab.artboard_size = Vector2(1920, 1080)
			container.add_child(default_ab)
		else:
			var first_ab = artboards[0] as ArtboardEditor
			first_ab.position = Vector2(100, 100)
			first_ab.artboard_size = Vector2(1920, 1080)
			for child in first_ab.get_children():
				if child is Node2D and String(child.name) not in ["ArtboardTitle", "Contorno_Stroke"]:
					child.queue_free()
			first_ab.queue_redraw()

			for i in range(1, artboards.size()):
				artboards[i].queue_free()

	var layers = tree.root.find_child("LayersSystem", true, false)
	if not layers and tree.current_scene:
		layers = tree.current_scene.find_child("LayersSystem", true, false)
	if layers and layers.has_method("sincronizar_arbol_completo"):
		layers.sincronizar_arbol_completo()

	if canvas and canvas.has_method("queue_redraw"):
		canvas.queue_redraw()

func mark_modified() -> void:
	is_modified = true
	save_state_changed.emit(true)
