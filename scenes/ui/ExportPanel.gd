# =============================================================================
# VECTOPEN EXPORT PANEL
# RUTA: res://scenes/ui/ExportPanel.gd
# =============================================================================
class_name ExportPanel
extends Panel

## Panel de gestión de archivos con FileFlowLayout (Drag & Drop)
##
## Features:
## - Importar/exportar archivos mediante arrastrar y soltar
## - Gestión de archivos recientes
## - Exportación en múltiples formatos (SVG, PNG, PDF, JPEG)
## - Integración con el canvas para arrastrar elementos

signal export_started(format: String, path: String)
signal export_finished(format: String, path: String)
signal export_error(format: String, message: String)
signal project_saved(path: String)
signal project_loaded(path: String)
signal autosave_finished(path: String)
signal element_dropped_internally(element: Variant, position: Vector2)

# --- Referencias a sistemas ---
@onready var import_export_manager = get_node("/root/ImportExportManager")
@onready var export_cache = get_node("/root/ExportCache")
@onready var data_repository = get_node("/root/DataRepository")
@onready var file_flow_layout = $HBoxContainer/FileFlowLayout

# --- Estado interno ---
var _current_artboard: Node = null
var _artboards: Array[Node] = []
var _export_in_progress: bool = false

# ==========================================
# CICLO DE VIDA
# ==========================================

func _ready() -> void:
	# Conectar señales
	_setup_signals()
	
	# Cargar artboards disponibles
	_load_artboards()
	
	# Conectar señales globales
	GlobalEvents.artboard_created.connect(_on_artboard_created)
	GlobalEvents.artboard_removed.connect(_on_artboard_removed)
	
	# Configurar auto-save
	_setup_autosave()
	
	# Verificar si hay un auto-save al iniciar
	_check_autosave()


func _setup_signals() -> void:
	# Conectar señales del FileFlowLayout
	if file_flow_layout:
		file_flow_layout.connect("element_dropped_internally", _on_element_dropped_internally)
		file_flow_layout.connect("export_requested", _on_export_requested)


func _setup_defaults() -> void:
	# Configurar valores por defecto
	name_edit.text = "vectopen_export"
	quantity_spin.value = 1
	resolution_spin.value = 2.0  # 2x por defecto
	
	# Configurar menú de artboards
	if artboard_menu:
		artboard_menu.get_popup().id_pressed.connect(_on_artboard_selected)


func _load_artboards() -> void:
	# Obtener todos los artboards disponibles
	_artboards.clear()
	
	if data_repository and data_repository.has_method("get_artboards"):
		_artboards = data_repository.get_artboards()
		
		# Actualizar menú de artboards
		_update_artboard_menu()
		
		# Seleccionar el primer artboard por defecto
		if _artboards.size() > 0:
			_current_artboard = _artboards[0]
			_update_artboard_selection()


# ==========================================
# MÉTODOS DE UI
# ==========================================

func _update_artboard_menu() -> void:
	if not artboard_menu:
		return
	
	var popup = artboard_menu.get_popup()
	popup.clear()
	
	for i in range(_artboards.size()):
		var artboard = _artboards[i]
		var name = artboard.name if artboard else "Artboard %d" % (i + 1)
		popup.add_item(name, i)


func _update_artboard_selection() -> void:
	if not artboard_menu or not _current_artboard:
		return
	
	var popup = artboard_menu.get_popup()
	for i in range(_artboards.size()):
		if _artboards[i] == _current_artboard:
			popup.set_item_checked(i, true)
		else:
			popup.set_item_checked(i, false)


func _update_cache_status() -> void:
	if cache_toggle and export_cache:
		var cache_enabled = export_cache.get_cache_stats()["enabled"]
		cache_toggle.set_pressed_no_signal(cache_enabled)


# ==========================================
# MANEJO DE ARTBOARDS
# ==========================================

func _on_artboard_created(artboard: Node) -> void:
	_artboards.append(artboard)
	_update_artboard_menu()
	
	# Seleccionar el nuevo artboard si es el primero
	if _artboards.size() == 1:
		_current_artboard = artboard
		_update_artboard_selection()


func _on_artboard_removed(artboard: Node) -> void:
	_artboards.erase(artboard)
	
	# Actualizar selección
	if _current_artboard == artboard:
		if _artboards.size() > 0:
			_current_artboard = _artboards[0]
		else:
			_current_artboard = null
	
	_update_artboard_menu()
	_update_artboard_selection()


func _on_artboard_selected(id: int) -> void:
	if id >= 0 and id < _artboards.size():
		_current_artboard = _artboards[id]
		_update_artboard_selection()


# ==========================================
# MÉTODOS DE EXPORTACIÓN
# ==========================================










# ==========================================
# MÉTODOS AUXILIARES
# ==========================================




# ==========================================
# GESTIÓN DE PROYECTOS (GUARDAR/ABRIR)
# ==========================================

func _on_save_pressed() -> void:
	var path = await _get_save_path()
	if path == "":
		return  # Usuario canceló
	
	var project_data = {
		"artboards": _get_all_artboards_data(),
		"metadata": {
			"version": "1.0",
			"created_at": Time.get_unix_time_from_system(),
			"modified_at": Time.get_unix_time_from_system()
		}
	}
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(project_data))
		file.close()
		GlobalEvents.project_saved.emit(path)
		_add_to_recent_files(path)
		if GlobalUI:
			GlobalUI.show_notification("Project saved: %s" % path)
	else:
		push_error("Failed to save project")
		if GlobalUI:
			GlobalUI.show_error("Failed to save project")


func _on_open_pressed() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.vectopen"])
	
	var main_view = get_tree().root.get_main_scene()
	if main_view:
		main_view.add_child(file_dialog)
		file_dialog.popup_centered()
		
		await file_dialog.confirmed
		var path = file_dialog.current_path
		file_dialog.queue_free()
		
		if path != "":
			_load_project(path)
			_add_to_recent_files(path)


func _get_save_path() -> String:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.vectopen"])
	file_dialog.current_file = "vectopen_project.vectopen"
	
	var main_view = get_tree().root.get_main_scene()
	if main_view:
		main_view.add_child(file_dialog)
		file_dialog.popup_centered()
		
		await file_dialog.confirmed
		var path = file_dialog.current_path
		file_dialog.queue_free()
		return path
	
	return ""


func _load_project(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: %s" % path)
		if GlobalUI:
			GlobalUI.show_error("Failed to open file")
		return
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	json.parse(content)
	var project_data = json.data
	
	if not project_data:
		push_error("Invalid project file")
		if GlobalUI:
			GlobalUI.show_error("Invalid project file")
		return
	
	# Limpiar artboards actuales
	for artboard in _artboards.duplicate():
		GlobalEvents.artboard_removed.emit(artboard)
		artboard.queue_free()
	
	# Cargar nuevos artboards
	if project_data.has("artboards") and data_repository:
		for artboard_data in project_data["artboards"]:
			if data_repository.has_method("create_artboard_from_state"):
				var artboard = data_repository.create_artboard_from_state(artboard_data)
				if artboard:
					GlobalEvents.artboard_created.emit(artboard)
	
	GlobalEvents.project_loaded.emit(path)
	if GlobalUI:
		GlobalUI.show_notification("Project loaded: %s" % path)


func _get_all_artboards_data() -> Array:
	var artboards_data = []
	for artboard in _artboards:
		if data_repository and data_repository.has_method("get_artboard_state"):
			artboards_data.append(data_repository.get_artboard_state(artboard))
	return artboards_data


func _add_to_recent_files(path: String) -> void:
	var config = ConfigFile.new()
	config.load("user://recent_files.cfg")
	
	var recent_files = config.get_value("RecentFiles", "files", [])
	if recent_files.has(path):
		recent_files.erase(path)
	
	recent_files.insert(0, path)
	if recent_files.size() > 5:
		recent_files.resize(5)
	
	config.set_value("RecentFiles", "files", recent_files)
	config.save("user://recent_files.cfg")
	_update_recent_files_menu()


func _update_recent_files_menu() -> void:
	if not recent_menu:
		return
	
	var config = ConfigFile.new()
	config.load("user://recent_files.cfg")
	
	var recent_files = config.get_value("RecentFiles", "files", [])
	var popup = recent_menu.get_popup()
	popup.clear()
	
	for file_path in recent_files:
		popup.add_item(file_path, popup.get_item_count())
		popup.set_item_metadata(popup.get_item_count() - 1, file_path)


func _on_element_dropped_internally(element: Variant, position: Vector2) -> void:
	# Manejar elementos soltados en el canvas o en la biblioteca
	if typeof(element) == TYPE_STRING:
		# Es una ruta de archivo (reciente o externo)
		if element.get_extension() in ["svg", "png", "pdf", "jpeg", "jpg"]:
			# Importar el archivo al canvas
			if data_repository and data_repository.has_method("import_file"):
				data_repository.import_file(element, _current_artboard)
	elif typeof(element) == TYPE_OBJECT and element is Node:
		# Es un nodo del canvas (arrastrado a la biblioteca)
		if file_flow_layout:
			file_flow_layout._add_to_recent_files(FileSystemManager.save_canvas_element_to_recent(element, "svg"))
	
	emit_signal("element_dropped_internally", element, position)


func _on_export_requested(element: Node, format: String, destination: String) -> void:
	# Exportar el elemento al formato y destino especificados
	if import_export_manager and import_export_manager.has_method("export_artboard"):
		import_export_manager.export_artboard(element, _get_export_format(format), destination, {})
		self.export_finished.emit(format, destination)
	else:
		push_error("ImportExportManager not available")
		self.export_error.emit(format, "ImportExportManager not available")


func _get_export_format(format: String) -> int:
	match format.to_lower():
		"svg": return ImportExportManager.ExportFormat.SVG
		"pdf": return ImportExportManager.ExportFormat.PDF
		"png": return ImportExportManager.ExportFormat.PNG
		"jpeg", "jpg": return ImportExportManager.ExportFormat.JPEG
		_: return ImportExportManager.ExportFormat.PNG  # Default


# ==========================================
# AUTO-SAVE (GUARDADO TEMPORAL)
# ==========================================

func _setup_autosave() -> void:
	var autosave_timer = Timer.new()
	add_child(autosave_timer)
	autosave_timer.timeout.connect(_on_autosave_timeout)
	autosave_timer.start(300.0)  # 5 minutos


func _on_autosave_timeout() -> void:
	var autosave_path = "user://autosave.vectopen"
	var project_data = {
		"artboards": _get_all_artboards_data(),
		"metadata": {
			"version": "1.0",
			"created_at": Time.get_unix_time_from_system(),
			"modified_at": Time.get_unix_time_from_system(),
			"is_autosave": true
		}
	}
	
	var file = FileAccess.open(autosave_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(project_data))
		file.close()
		GlobalEvents.autosave_finished.emit(autosave_path)
		if GlobalUI:
			GlobalUI.show_notification("Auto-save completed")


func _check_autosave() -> void:
	var autosave_path = "user://autosave.vectopen"
	if FileAccess.file_exists(autosave_path) and GlobalUI:
		GlobalUI.show_confirmation_dialog(
			"Auto-save found. Do you want to restore?",
			self,
			"_on_restore_autosave"
		)


func _on_restore_autosave() -> void:
	_load_project("user://autosave.vectopen")


# TODO: async function placeholder
