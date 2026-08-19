# ==========================================
# RUTA: res://autoloads/ProjectManager.gd
# CONFIGURACIÓN: Autoload (Singleton)
# ORDEN DE CARGA: Después de GlobalEvents / DataRepository
# ==========================================
extends Node

## Extraído de DataRepository.gd el 19/08/2026 (ver docs/*/reports).
## Dueño de los datos persistentes del proyecto: artboards, capas, shapes,
## guardado/carga/auto-guardado/recuperación y snap a rejilla.
## Estado de sesión (cámara, paneles abiertos, herramienta activa, config
## por herramienta) vive en SessionManager, no aquí.
## Desde el 19/08/2026 (ver informe §1.7) el undo/redo de shapes/capas/
## artboards se registra a través de HistoryManager en vez de tener su
## propia pila de UndoRedoManager — antes estaban desconectadas y Ctrl+Z
## nunca deshacía estas acciones.
## DataRepository sigue siendo la fachada pública — el resto del proyecto
## no debería llamar a este autoload directamente salvo los pocos sitios
## ya documentados en el informe técnico.

# ==========================================
# REFERENCIAS
# ==========================================

var GlobalEvents: Node = null  # Se asigna en _ready()


# ==========================================
# SUBSISTEMA DE DATOS
# ==========================================

var project: ProjectData = null       # Datos persistentes del proyecto
# El historial de undo/redo ya no vive aquí — ver HistoryManager (autoload)


# ==========================================
# ESTADO ACTUAL (Caché rápida)
# ==========================================

var selected_shapes: Array[String] = []   # IDs de shapes seleccionados
var current_layer_id: String = ""         # ID de capa activa
var current_artboard_id: String = ""      # ID de artboard activo
var is_project_modified: bool = false     # Proyecto con cambios sin guardar


# ==========================================
# CONFIGURACIÓN DE USUARIO
# ==========================================

var settings: Dictionary = {
	"auto_save_interval": 300,      # segundos (5 minutos)
	"max_undo_steps": 100,
	"grid_size": 20.0,
	"snap_enabled": true,
	"snap_threshold": 10.0,
	"recovery_enabled": true,
	"max_recovery_files": 10,
	"incremental_save_enabled": true # Guardado incremental
}

# Estado para guardado incremental
var _last_save_hash: String = ""
var _last_save_timestamp: int = 0
var _last_save_data: Dictionary = {}


# ==========================================
# INICIALIZACIÓN
# ==========================================

func _ready() -> void:
	GlobalEvents = get_node_or_null("/root/GlobalEvents")
	if not GlobalEvents:
		push_warning("ProjectManager: GlobalEvents no encontrado. Las señales no se emitirán.")

	_initialize_subsystems()
	_setup_auto_save()
	_setup_recovery()

	print("ProjectManager: Inicializado correctamente")


func _initialize_subsystems() -> void:
	project = ProjectData.new()


# ==========================================
# AUTO-SAVE Y RECUPERACIÓN
# ==========================================

var _auto_save_timer: Timer = null

func _setup_auto_save() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = settings.auto_save_interval
	_auto_save_timer.timeout.connect(_auto_save)
	add_child(_auto_save_timer)
	_auto_save_timer.start()


func _auto_save() -> void:
	if is_project_modified and project and not project.file_path.is_empty():
		var backup_path = "user://backups/" + project.get_safe_name() + "_" + str(Time.get_unix_time_from_system())
		var success: bool = false

		if settings.incremental_save_enabled:
			# Usar guardado incremental
			backup_path += "_incremental.save"
			success = _save_incremental(backup_path)
		else:
			# Usar guardado completo
			backup_path += ".save"
			success = _save_to_path(backup_path)

		if success and GlobalEvents:
			GlobalEvents.emit_safe("data_auto_save_triggered")


func _setup_recovery() -> void:
	if not settings.recovery_enabled:
		return

	# Crear directorio de recovery si no existe
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("recovery"):
		dir.make_dir("recovery")

	# Cargar última sesión recuperada
	_check_for_recovery()


func _check_for_recovery() -> void:
	var recovery_path = "user://recovery/last_session.json"
	if FileAccess.file_exists(recovery_path):
		var file = FileAccess.open(recovery_path, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		if data and data.get("timestamp", 0) > Time.get_unix_time_from_system() - 86400:  # Último día
			print("ProjectManager: Existe sesión de recuperación del día anterior")
			# No cargar automáticamente, solo notificar
			if GlobalEvents:
				GlobalEvents.emit_safe("data_auto_save_restored")


func save_recovery_state() -> void:
	if not settings.recovery_enabled:
		return

	var recovery_data = {
		"project": project.serialize() if project else {},
		"session": SessionManager.session.serialize(),
		"timestamp": Time.get_unix_time_from_system(),
		"current_artboard": current_artboard_id,
		"current_layer": current_layer_id,
		"current_tool": SessionManager.current_tool
	}

	var path = "user://recovery/last_session.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(recovery_data, "\t"))

	if GlobalEvents:
		GlobalEvents.emit_safe("data_recovery_saved")


# ==========================================
# PROYECTO: NUEVO / GUARDAR / CARGAR
# ==========================================

func new_project(project_name: String = "Nuevo Proyecto") -> void:
	# Guardar recovery del proyecto actual si existe
	if project and is_project_modified:
		save_recovery_state()

	# Crear nuevo proyecto
	project = ProjectData.new()
	project.name = project_name

	# Limpiar estado
	selected_shapes.clear()
	current_artboard_id = ""
	current_layer_id = ""
	is_project_modified = false

	# Limpiar historial
	HistoryManager.clear()

	# Crear artboard por defecto
	_create_default_artboard()

	# Emitir señal
	if GlobalEvents:
		GlobalEvents.emit_safe("data_project_loaded", project_name)
		GlobalEvents.emit_safe("data_undo_state_changed", false, false)

	print("ProjectManager: Nuevo proyecto creado - ", project_name)


func _create_default_artboard() -> void:
	var artboard_id = "artboard_default_" + str(Time.get_ticks_msec())
	var layer_id = "layer_default_" + str(Time.get_ticks_msec())

	project.artboards[artboard_id] = ArtboardData.new(artboard_id, "Artboard 1")
	project.layers[layer_id] = LayerData.new(layer_id, "Capa 1", artboard_id)

	current_artboard_id = artboard_id
	current_layer_id = layer_id

	if GlobalEvents:
		GlobalEvents.emit_safe("data_artboard_created", artboard_id)
		GlobalEvents.emit_safe("data_layer_created", layer_id, "Capa 1")


func save_project(path: String = "") -> String:
	if not project:
		push_error("ProjectManager: No hay proyecto activo para guardar")
		return ""

	var save_path = path if not path.is_empty() else project.file_path

	if save_path.is_empty():
		push_error("ProjectManager: No se especificó ruta para guardar")
		return ""

	var success = _save_to_path(save_path)

	if success:
		project.file_path = save_path
		is_project_modified = false

		if GlobalEvents:
			GlobalEvents.emit_safe("data_project_saved")

		print("ProjectManager: Proyecto guardado en - ", save_path)
		return save_path

	return ""


func _save_to_path(path: String) -> bool:
	if not project:
		return false

	# Asegurar extensión
	if not path.ends_with(".vectopen") and not path.ends_with(".json"):
		path += ".vectopen"

	var save_data = {
		"version": 2,
		"project": project.serialize(),
		"session": SessionManager.session.serialize(),
		"timestamp": Time.get_unix_time_from_system(),
		"app_version": "Vectopen 1.0"
	}

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("ProjectManager: No se pudo crear archivo - ", path)
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	return true


func load_project(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("ProjectManager: Archivo no existe - ", path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	var data = JSON.parse_string(content)

	if not data:
		push_error("ProjectManager: Error al parsear JSON")
		return false

	# Guardar recovery del proyecto actual
	if project and is_project_modified:
		save_recovery_state()

	# Cargar nuevo proyecto
	project = ProjectData.new()
	project.deserialize(data.get("project", {}))
	SessionManager.session.deserialize(data.get("session", {}))
	project.file_path = path

	# Restaurar estado desde el proyecto
	var artboard_keys = project.artboards.keys()
	if artboard_keys.size() > 0:
		current_artboard_id = artboard_keys[0]

	var layer_keys = project.layers.keys()
	if layer_keys.size() > 0:
		current_layer_id = layer_keys[0]

	selected_shapes.clear()
	is_project_modified = false

	HistoryManager.clear()

	if GlobalEvents:
		GlobalEvents.emit_safe("data_project_loaded", project.name)
		GlobalEvents.emit_safe("data_undo_state_changed", false, false)

	print("ProjectManager: Proyecto cargado - ", project.name)
	return true


func close_project() -> void:
	if is_project_modified:
		save_recovery_state()

	project = ProjectData.new()
	SessionManager.reset_session()
	selected_shapes.clear()
	current_artboard_id = ""
	current_layer_id = ""
	is_project_modified = false

	HistoryManager.clear()

	if GlobalEvents:
		GlobalEvents.emit_safe("data_project_closed")
		GlobalEvents.emit_safe("data_undo_state_changed", false, false)


# ==========================================
# SHAPES MANAGEMENT
# ==========================================

func create_shape(shape_type: String, data: Dictionary = {}, layer_id: String = "") -> String:
	if not project:
		push_error("ProjectManager: No hay proyecto activo")
		return ""

	var target_layer = layer_id if not layer_id.is_empty() else current_layer_id
	if not project.layers.has(target_layer):
		push_error("ProjectManager: Capa no existe - ", target_layer)
		return ""

	var shape_id = _generate_id("shape")
	var shape_data = ShapeData.new()
	shape_data.id = shape_id
	shape_data.type = shape_type
	shape_data.deserialize(data)

	# Registrar para undo
	HistoryManager.register_action("Crear " + shape_type)
	HistoryManager.add_do(_do_create_shape.bind(shape_id, shape_data, target_layer))
	HistoryManager.add_undo(_undo_create_shape.bind(shape_id, target_layer))
	HistoryManager.commit()

	# Ejecutar DO inmediatamente
	_do_create_shape(shape_id, shape_data, target_layer)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_shape_created", shape_id, shape_type)
		GlobalEvents.emit_safe("object_created")  # Compatibilidad con código existente

	is_project_modified = true
	return shape_id


func _do_create_shape(shape_id: String, shape_data: ShapeData, layer_id: String) -> void:
	project.layers[layer_id].shapes.append(shape_data)
	project.layers[layer_id].shape_ids.append(shape_id)


func _undo_create_shape(shape_id: String, layer_id: String) -> void:
	var layer = project.layers[layer_id]
	for i in range(layer.shapes.size()):
		if layer.shapes[i].id == shape_id:
			layer.shapes.remove_at(i)
			break
	for i in range(layer.shape_ids.size()):
		if layer.shape_ids[i] == shape_id:
			layer.shape_ids.remove_at(i)
			break


func update_shape(shape_id: String, property: String, value) -> void:
	var shape = _find_shape(shape_id)
	if not shape:
		push_error("ProjectManager: Shape no encontrado - ", shape_id)
		return

	var old_value = shape.get(property)
	if old_value == value:
		return

	HistoryManager.register_action("Cambiar " + property)
	HistoryManager.add_do(_do_update_shape.bind(shape_id, property, value))
	HistoryManager.add_undo(_do_update_shape.bind(shape_id, property, old_value))
	HistoryManager.commit()

	_do_update_shape(shape_id, property, value)


func _do_update_shape(shape_id: String, property: String, value) -> void:
	var shape = _find_shape(shape_id)
	if shape:
		shape.set(property, value)

		if GlobalEvents:
			GlobalEvents.emit_safe("data_shape_changed", shape_id, property, value)
			GlobalEvents.emit_safe("object_style_changed")

		is_project_modified = true


func delete_shape(shape_id: String) -> void:
	var result = _find_shape_and_layer(shape_id)
	if result.is_empty():
		push_error("ProjectManager: Shape no encontrado - ", shape_id)
		return

	var shape = result["shape"]
	var layer_id = result["layer_id"]
	var index = result["index"]

	HistoryManager.register_action("Eliminar shape")
	HistoryManager.add_do(_do_delete_shape.bind(shape_id, layer_id, index))
	HistoryManager.add_undo(_undo_delete_shape.bind(shape, layer_id, index))
	HistoryManager.commit()

	_do_delete_shape(shape_id, layer_id, index)


func _do_delete_shape(shape_id: String, layer_id: String, index: int) -> void:
	var layer = project.layers[layer_id]
	if index < layer.shapes.size() and layer.shapes[index].id == shape_id:
		layer.shapes.remove_at(index)
		layer.shape_ids.erase(shape_id)

		# Eliminar de selección si estaba seleccionado
		if selected_shapes.has(shape_id):
			selected_shapes.erase(shape_id)
			if GlobalEvents:
				GlobalEvents.emit_safe("data_selection_changed", selected_shapes.duplicate())

		if GlobalEvents:
			GlobalEvents.emit_safe("data_shape_deleted", shape_id)
			GlobalEvents.emit_safe("object_deleted")

		is_project_modified = true


func _undo_delete_shape(shape: ShapeData, layer_id: String, index: int) -> void:
	var layer = project.layers[layer_id]
	layer.shapes.insert(index, shape)
	layer.shape_ids.insert(index, shape.id)


# ==========================================
# SELECCIÓN
# ==========================================

func select_shape(shape_id: String, add_to_selection: bool = false) -> void:
	if not add_to_selection:
		selected_shapes.clear()

	if not selected_shapes.has(shape_id):
		selected_shapes.append(shape_id)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_selection_changed", selected_shapes.duplicate())
		GlobalEvents.emit_safe("data_shape_selected", shape_id, add_to_selection)
		GlobalEvents.emit_safe("object_selected")

func deselect_shape(shape_id: String) -> void:
	if selected_shapes.has(shape_id):
		selected_shapes.erase(shape_id)
		if GlobalEvents:
			GlobalEvents.emit_safe("data_selection_changed", selected_shapes.duplicate())
func clear_selection() -> void:
	if not selected_shapes.is_empty():
		selected_shapes.clear()
		if GlobalEvents:
			GlobalEvents.emit_safe("data_selection_changed", [])
			GlobalEvents.emit_safe("data_selection_cleared")


func get_selected_shapes() -> Array[ShapeData]:
	var result: Array[ShapeData] = []
	for shape_id in selected_shapes:
		var shape = _find_shape(shape_id)
		if shape:
			result.append(shape)
	return result


func get_selected_count() -> int:
	return selected_shapes.size()


# ==========================================
# CAPAS
# ==========================================

func create_layer(layer_name: String, artboard_id: String = "") -> String:
	if not project:
		return ""

	var target_artboard = artboard_id if not artboard_id.is_empty() else current_artboard_id
	var layer_id = _generate_id("layer")
	var layer_data = LayerData.new(layer_id, layer_name, target_artboard)

	HistoryManager.register_action("Crear capa")
	HistoryManager.add_do(_do_create_layer.bind(layer_id, layer_data))
	HistoryManager.add_undo(_undo_create_layer.bind(layer_id))
	HistoryManager.commit()

	_do_create_layer(layer_id, layer_data)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_layer_created", layer_id, layer_name)
		GlobalEvents.emit_safe("layer_created")

	is_project_modified = true
	return layer_id


func _do_create_layer(layer_id: String, layer_data: LayerData) -> void:
	project.layers[layer_id] = layer_data


func _undo_create_layer(layer_id: String) -> void:
	project.layers.erase(layer_id)


func delete_layer(layer_id: String) -> void:
	if not project.layers.has(layer_id):
		return

	var layer = project.layers[layer_id]

	HistoryManager.register_action("Eliminar capa")
	HistoryManager.add_do(_do_delete_layer.bind(layer_id))
	HistoryManager.add_undo(_undo_delete_layer.bind(layer_id, layer))
	HistoryManager.commit()

	_do_delete_layer(layer_id)


func _do_delete_layer(layer_id: String) -> void:
	project.layers.erase(layer_id)

	if current_layer_id == layer_id:
		var layer_keys = project.layers.keys()
		if layer_keys.size() > 0:
			current_layer_id = layer_keys[0]
		else:
			current_layer_id = ""

	if GlobalEvents:
		GlobalEvents.emit_safe("data_layer_deleted", layer_id)
		GlobalEvents.emit_safe("layer_deleted", 0)

	is_project_modified = true


func _undo_delete_layer(layer_id: String, layer_data: LayerData) -> void:
	project.layers[layer_id] = layer_data


func update_layer(layer_id: String, property: String, value) -> void:
	if not project.layers.has(layer_id):
		return

	var layer = project.layers[layer_id]
	var old_value = layer.get(property)

	if old_value == value:
		return

	layer.set(property, value)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_layer_changed", layer_id, property, value)

		if property == "is_visible":
			GlobalEvents.emit_safe("layer_visibility_toggled", 0, value)
		elif property == "is_locked":
			GlobalEvents.emit_safe("layer_locked_toggled")

	is_project_modified = true


# ==========================================
# ARTBOARDS
# ==========================================

func create_artboard(artboard_name: String, position: Vector2 = Vector2.ZERO) -> String:
	if not project:
		return ""

	var artboard_id = _generate_id("artboard")
	var artboard_data = ArtboardData.new(artboard_id, artboard_name)
	artboard_data.position = position

	HistoryManager.register_action("Crear artboard")
	HistoryManager.add_do(_do_create_artboard.bind(artboard_id, artboard_data))
	HistoryManager.add_undo(_undo_create_artboard.bind(artboard_id))
	HistoryManager.commit()

	_do_create_artboard(artboard_id, artboard_data)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_artboard_created", artboard_id)
		GlobalEvents.emit_safe("artboard_created")

	is_project_modified = true
	return artboard_id


func _do_create_artboard(artboard_id: String, artboard_data: ArtboardData) -> void:
	project.artboards[artboard_id] = artboard_data


func _undo_create_artboard(artboard_id: String) -> void:
	project.artboards.erase(artboard_id)


func delete_artboard(artboard_id: String) -> void:
	if not project.artboards.has(artboard_id):
		return

	var artboard = project.artboards[artboard_id]

	# También eliminar capas asociadas
	var layers_to_delete: Array[String] = []
	for layer_id in project.layers:
		var layer = project.layers[layer_id]
		if layer.artboard_id == artboard_id:
			layers_to_delete.append(layer_id)

	HistoryManager.register_action("Eliminar artboard")
	HistoryManager.add_do(_do_delete_artboard.bind(artboard_id, layers_to_delete))
	HistoryManager.add_undo(_undo_delete_artboard.bind(artboard_id, artboard, layers_to_delete))
	HistoryManager.commit()

	_do_delete_artboard(artboard_id, layers_to_delete)


func get_artboards() -> Array:
	return project.artboards.values()


func _do_delete_artboard(artboard_id: String, layers_to_delete: Array[String]) -> void:
	project.artboards.erase(artboard_id)

	for layer_id in layers_to_delete:
		project.layers.erase(layer_id)

	if current_artboard_id == artboard_id:
		var artboard_keys = project.artboards.keys()
		if artboard_keys.size() > 0:
			set_active_artboard(artboard_keys[0])
		else:
			current_artboard_id = ""

	if GlobalEvents:
		GlobalEvents.emit_safe("data_artboard_deleted", artboard_id)
		GlobalEvents.emit_safe("artboard_deleted")

	is_project_modified = true


func _undo_delete_artboard(artboard_id: String, artboard_data: ArtboardData, _layers_to_restore: Array[String]) -> void:
	project.artboards[artboard_id] = artboard_data
	# Nota: Las capas necesitarían ser restauradas con sus datos completos
	# Esto es simplificado, en producción se necesitaría más información


func set_active_artboard(artboard_id: String) -> void:
	if not project.artboards.has(artboard_id):
		return

	current_artboard_id = artboard_id

	if GlobalEvents:
		GlobalEvents.emit_safe("data_active_artboard_changed", artboard_id)
		GlobalEvents.emit_safe("active_artboard_changed")
		GlobalEvents.emit_safe("artboard_selected")


func update_artboard(artboard_id: String, property: String, value) -> void:
	if not project.artboards.has(artboard_id):
		return

	var artboard = project.artboards[artboard_id]
	var old_value = artboard.get(property)

	if old_value == value:
		return

	artboard.set(property, value)

	if GlobalEvents:
		GlobalEvents.emit_safe("data_artboard_changed", artboard_id, property, value)

		if property == "position":
			GlobalEvents.emit_safe("artboard_moved")
		elif property == "size":
			GlobalEvents.emit_safe("artboard_resized")

	is_project_modified = true


# ==========================================
# UNDO / REDO
# ==========================================
# Delegado en HistoryManager desde el 19/08/2026 (ver informe §1.7) — antes
# ProjectManager tenía su propia pila de UndoRedoManager, desconectada de la
# que Ctrl+Z/Y usa de verdad (HistoryManager), así que estos métodos nunca
# deshacían nada en la práctica. DataRepository.undo()/redo()/can_undo()/
# can_redo() siguen delegando aquí para no romper compatibilidad.

func undo() -> void:
	if HistoryManager.can_undo():
		HistoryManager.undo()
		if GlobalEvents:
			GlobalEvents.emit_safe("data_undo_performed")
			GlobalEvents.emit_safe("object_transformed")  # Compatibilidad


func redo() -> void:
	if HistoryManager.can_redo():
		HistoryManager.redo()
		if GlobalEvents:
			GlobalEvents.emit_safe("data_redo_performed")
			GlobalEvents.emit_safe("object_transformed")  # Compatibilidad


func can_undo() -> bool:
	return HistoryManager.can_undo()


func can_redo() -> bool:
	return HistoryManager.can_redo()


# ==========================================
# GRID Y SNAP
# ==========================================

func set_grid_size(size: float) -> void:
	settings.grid_size = max(1.0, size)
	if GlobalEvents:
		GlobalEvents.emit_safe("data_grid_settings_changed", settings.grid_size, settings.snap_enabled)


func set_snap_enabled(enabled: bool) -> void:
	settings.snap_enabled = enabled
	if GlobalEvents:
		GlobalEvents.emit_safe("data_grid_settings_changed", settings.grid_size, settings.snap_enabled)


func snap_position(position: Vector2) -> Vector2:
	if not settings.snap_enabled:
		return position

	return Vector2(
		round(position.x / settings.grid_size) * settings.grid_size,
		round(position.y / settings.grid_size) * settings.grid_size
	)


# ==========================================
# MÉTODOS DE UTILIDAD
# ==========================================

func _find_shape(shape_id: String) -> ShapeData:
	for layer_id in project.layers:
		var layer = project.layers[layer_id]
		for shape in layer.shapes:
			if shape.id == shape_id:
				return shape
	return null


func _find_shape_and_layer(shape_id: String) -> Dictionary:
	for layer_id in project.layers:
		var layer = project.layers[layer_id]
		for i in range(layer.shapes.size()):
			if layer.shapes[i].id == shape_id:
				return {
					"shape": layer.shapes[i],
					"layer_id": layer_id,
					"index": i
				}
	return {}


func _generate_id(prefix: String = "") -> String:
	return prefix + "_" + str(Time.get_ticks_msec()) + "_" + str(randi())


func _save_incremental(path: String) -> bool:
	# Generar hash del estado actual
	var current_hash = _generate_project_hash()

	# Si no ha cambiado nada desde el último guardado, no hacer nada
	if current_hash == _last_save_hash and _last_save_data:
		return true

	# Si no hay datos previos o el hash es diferente, guardar cambios
	var save_data = {
		"version": 2,
		"project": project.serialize(),
		"session": SessionManager.session.serialize(),
		"timestamp": Time.get_unix_time_from_system(),
		"app_version": "Vectopen 1.0",
		"incremental": true,
		"previous_hash": _last_save_hash
	}

	# Guardar los cambios
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("ProjectManager: No se pudo crear archivo incremental - ", path)
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()

	# Actualizar estado de guardado incremental
	_last_save_hash = current_hash
	_last_save_timestamp = int(Time.get_unix_time_from_system())
	_last_save_data = save_data

	return true


func _generate_project_hash() -> String:
	# Crear un hash basado en el estado actual del proyecto
	var hash_source = {
		"shapes_count": 0,
		"layers_count": project.layers.size(),
		"artboards_count": project.artboards.size(),
		"modified_at": project.modified_at if project else 0,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Contar shapes
	for layer_id in project.layers:
		hash_source["shapes_count"] += project.layers[layer_id].shapes.size()

	# Crear hash único
	return JSON.stringify(hash_source).md5_text()


# ==========================================
# GETTERS PARA ACCESO RÁPIDO
# ==========================================

func get_active_artboard() -> ArtboardData:
	return project.artboards.get(current_artboard_id, null)


func get_active_layer() -> LayerData:
	return project.layers.get(current_layer_id, null)


func get_all_shapes_in_active_layer() -> Array[ShapeData]:
	var layer = get_active_layer()
	if layer:
		return layer.shapes.duplicate()
	return []


func get_project_name() -> String:
	return project.name if project else "Sin proyecto"


func is_project_open() -> bool:
	return project != null and project.name != ""


# ==========================================
# CLASES INTERNAS DE DATOS
# ==========================================

## Datos del proyecto
class ProjectData:
	var name: String = "Nuevo Proyecto"
	var file_path: String = ""
	var artboards: Dictionary = {}   # artboard_id -> ArtboardData
	var layers: Dictionary = {}      # layer_id -> LayerData
	var created_at: int = 0
	var modified_at: int = 0

	func _init():
		created_at = int(Time.get_unix_time_from_system())
		modified_at = created_at

	func serialize() -> Dictionary:
		var serialized_artboards = {}
		for artboard_id in artboards:
			serialized_artboards[artboard_id] = artboards[artboard_id].serialize()

		var serialized_layers = {}
		for layer_id in layers:
			serialized_layers[layer_id] = layers[layer_id].serialize()

		return {
			"name": name,
			"artboards": serialized_artboards,
			"layers": serialized_layers,
			"created_at": created_at
		}

	func deserialize(data: Dictionary) -> void:
		name = data.get("name", "Nuevo Proyecto")
		created_at = data.get("created_at", Time.get_unix_time_from_system())

		artboards.clear()
		var artboards_data = data.get("artboards", {})
		for artboard_id in artboards_data:
			var artboard = ArtboardData.new()
			artboard.deserialize(artboards_data[artboard_id])
			artboards[artboard_id] = artboard

		layers.clear()
		var layers_data = data.get("layers", {})
		for layer_id in layers_data:
			var layer = LayerData.new()
			layer.deserialize(layers_data[layer_id])
			layers[layer_id] = layer

	func get_safe_name() -> String:
		return name.replace(" ", "_").replace("/", "_").replace("\\", "_")


## Datos de Artboard
class ArtboardData:
	var id: String = ""
	var name: String = "Artboard"
	var position: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2(1920, 1080)
	var background_color: Color = Color.WHITE
	var is_visible: bool = true

	func _init(p_id: String = "", p_name: String = ""):
		id = p_id
		name = p_name if not p_name.is_empty() else "Artboard"

	func serialize() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"position": [position.x, position.y],
			"size": [size.x, size.y],
			"bg_color": [background_color.r, background_color.g, background_color.b, background_color.a]
		}

	func deserialize(data: Dictionary) -> void:
		id = data.get("id", id)
		name = data.get("name", name)
		var pos = data.get("position", [0, 0])
		position = Vector2(pos[0], pos[1])
		var sz = data.get("size", [1920, 1080])
		size = Vector2(sz[0], sz[1])
		var bg = data.get("bg_color", [1, 1, 1, 1])
		background_color = Color(bg[0], bg[1], bg[2], bg[3])


## Datos de Capa
class LayerData:
	var id: String = ""
	var name: String = "Capa"
	var artboard_id: String = ""
	var is_visible: bool = true
	var is_locked: bool = false
	var opacity: float = 1.0
	var blend_mode: int = 0
	var shapes: Array[ShapeData] = []
	var shape_ids: Array[String] = []

	func _init(p_id: String = "", p_name: String = "", p_artboard_id: String = ""):
		id = p_id
		name = p_name if not p_name.is_empty() else "Capa"
		artboard_id = p_artboard_id

	func serialize() -> Dictionary:
		var serialized_shapes = []
		for shape in shapes:
			serialized_shapes.append(shape.serialize())

		return {
			"id": id,
			"name": name,
			"artboard_id": artboard_id,
			"visible": is_visible,
			"locked": is_locked,
			"opacity": opacity,
			"blend_mode": blend_mode,
			"shapes": serialized_shapes,
			"shape_ids": shape_ids.duplicate()
		}

	func deserialize(data: Dictionary) -> void:
		id = data.get("id", id)
		name = data.get("name", name)
		artboard_id = data.get("artboard_id", artboard_id)
		is_visible = data.get("visible", is_visible)
		is_locked = data.get("locked", is_locked)
		opacity = data.get("opacity", opacity)
		blend_mode = data.get("blend_mode", blend_mode)
		shape_ids = data.get("shape_ids", [])

		shapes.clear()
		var shapes_data = data.get("shapes", [])
		for shape_data in shapes_data:
			var shape = ShapeData.new()
			shape.deserialize(shape_data)
			shapes.append(shape)


## Datos de Shape
class ShapeData:
	var id: String = ""
	var type: String = "path"
	var name: String = ""
	var position: Vector2 = Vector2.ZERO
	var rotation: float = 0.0
	var scale: Vector2 = Vector2.ONE

	# Estilo
	var stroke_color: Color = Color.BLACK
	var stroke_width: float = 2.0
	var fill_color: Color = Color.TRANSPARENT
	var is_filled: bool = false

	# Geometría (varía según tipo)
	var points: PackedVector2Array = []      # Para path/polygon
	var size: Vector2 = Vector2(100, 100)    # Para rect/ellipse
	var text_content: String = ""            # Para text

	func serialize() -> Dictionary:
		var serialized_points = []
		for p in points:
			serialized_points.append([p.x, p.y])

		return {
			"id": id,
			"type": type,
			"name": name,
			"position": [position.x, position.y],
			"rotation": rotation,
			"scale": [scale.x, scale.y],
			"stroke_color": [stroke_color.r, stroke_color.g, stroke_color.b, stroke_color.a],
			"stroke_width": stroke_width,
			"fill_color": [fill_color.r, fill_color.g, fill_color.b, fill_color.a],
			"is_filled": is_filled,
			"points": serialized_points,
			"size": [size.x, size.y],
			"text_content": text_content
		}

	func deserialize(data: Dictionary) -> void:
		id = data.get("id", id)
		type = data.get("type", type)
		name = data.get("name", name)
		var pos = data.get("position", [0, 0])
		position = Vector2(pos[0], pos[1])
		rotation = data.get("rotation", rotation)
		var sc = data.get("scale", [1, 1])
		scale = Vector2(sc[0], sc[1])

		var scolor = data.get("stroke_color", [0, 0, 0, 1])
		stroke_color = Color(scolor[0], scolor[1], scolor[2], scolor[3])
		stroke_width = data.get("stroke_width", stroke_width)

		var fcolor = data.get("fill_color", [0, 0, 0, 0])
		fill_color = Color(fcolor[0], fcolor[1], fcolor[2], fcolor[3])
		is_filled = data.get("is_filled", is_filled)

		points.clear()
		var points_data = data.get("points", [])
		for p in points_data:
			points.append(Vector2(p[0], p[1]))

		var sz = data.get("size", [100, 100])
		size = Vector2(sz[0], sz[1])
		text_content = data.get("text_content", text_content)


# ==========================================
# MÉTODOS PARA FILE-FLOW
# ==========================================

func get_exportable_elements() -> Array:
	"""
	Devuelve una lista de elementos exportables del proyecto.
	"""
	var elements = []

	# Obtener artboards exportables
	for artboard in get_artboards():
		elements.append({
			"name": artboard.name,
			"node": artboard,
			"type": "artboard"
		})

		# Obtener shapes exportables dentro del artboard
		for child in artboard.get_children():
			if child is CanvasItem and child.name != "ArtboardTitle":
				elements.append({
					"name": child.name,
					"node": child,
					"type": "shape"
				})

	return elements


# ==========================================
# MÉTODOS DE GESTIÓN DE PROYECTOS
# ==========================================

func create_artboard_from_state(state: Dictionary) -> Node:
	"""
	Crea un artboard a partir de un estado guardado.
	"""
	if not state:
		return null

	var artboard_scene = load("res://scenes/canvas/artboard.tscn")
	var artboard = artboard_scene.instantiate() if artboard_scene else Node.new()

	# Configurar propiedades básicas
	if state.has("name"):
		artboard.name = state["name"]
	if state.has("size") and artboard.has_method("set_size"):
		artboard.set_size(state["size"])

	# Restaurar shapes
	if state.has("shapes"):
		for shape_state in state["shapes"]:
			var shape = _create_shape_from_state(shape_state)
			if shape:
				artboard.add_child(shape)

	return artboard


func _create_shape_from_state(state: Dictionary) -> Node:
	"""
	Crea una shape a partir de un estado guardado.
	"""
	if not state or not state.has("type"):
		return null

	var shape: Node = null
	var type = state["type"]

	match type:
		"Path2D":
			shape = Path2D.new()
			if state.has("properties") and state["properties"].has("points"):
				var curve = Curve2D.new()
				for point in state["properties"]["points"]:
					curve.add_point(point)
				shape.curve = curve
		"Polygon2D":
			shape = Polygon2D.new()
			if state.has("properties") and state["properties"].has("polygon"):
				shape.polygon = state["properties"]["polygon"]
		"Line2D":
			shape = Line2D.new()
			if state.has("properties") and state["properties"].has("points"):
				shape.points = state["properties"]["points"]
		"ColorRect":
			shape = ColorRect.new()
			if state.has("properties") and state["properties"].has("color"):
				shape.color = Color(state["properties"]["color"])
		_:
			shape = Node2D.new()

	# Configurar propiedades comunes
	if shape and state.has("position"):
		shape.position = state["position"]
	if shape and state.has("scale"):
		shape.scale = state["scale"]
	if shape and state.has("rotation"):
		shape.rotation = state["rotation"]

	# Configurar propiedades específicas
	if shape and state.has("properties"):
		for prop in state["properties"].keys():
			if shape.has(prop):
				shape.set(prop, state["properties"][prop])

	return shape
