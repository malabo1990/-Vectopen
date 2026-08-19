# ==========================================
# RUTA: res://autoloads/DataRepository.gd
# CONFIGURACIÓN: Añadir como Autoload (Singleton)
# ORDEN DE CARGA: Después de GlobalEvents
# ==========================================
extends Node

## Fachada pública de acceso a datos para Vectopen.
##
## Desde el 19/08/2026 este script ya NO contiene la lógica de negocio —
## fue dividido en dos autoloads más pequeños para dejar de ser un
## god-object de 1259 líneas (ver docs/*/reports/VECTOPEN_TECHNICAL_REPORT.md §1.6):
##   - ProjectManager: datos persistentes del proyecto (artboards, capas,
##     shapes, undo/redo, guardado/carga, auto-guardado, recuperación, snap)
##   - SessionManager: estado de sesión (cámara, paneles, portapapeles,
##     configuración por herramienta, herramienta activa)
## DataRepository se mantiene como fachada delgada que delega en ambos,
## para no romper el resto del proyecto (~15 sitios) que sigue llamando
## a `DataRepository.*` directamente. Las llamadas nuevas deberían ir
## directo a ProjectManager/SessionManager cuando sea razonable.

# ==========================================
# ALIAS DE CLASES DE DATOS (compatibilidad hacia atrás)
# ==========================================
# `DataRepository.ArtboardData`/`.LayerData`/`.ShapeData` se usan así en
# script_gdscript/data/DataResourceManager.gd — se mantienen resolviendo
# aquí aunque las clases reales ahora viven en ProjectManager/SessionManager.

const _ProjectManagerScript = preload("res://autoloads/ProjectManager.gd")
const _SessionManagerScript = preload("res://autoloads/SessionManager.gd")

const ProjectData = _ProjectManagerScript.ProjectData
const ArtboardData = _ProjectManagerScript.ArtboardData
const LayerData = _ProjectManagerScript.LayerData
const ShapeData = _ProjectManagerScript.ShapeData
const SessionData = _SessionManagerScript.SessionData


# ==========================================
# PROPIEDADES DELEGADAS (compatibilidad hacia atrás)
# ==========================================
# HistoryManager.gd hace `DataRepository.is_project_modified = true`
# directamente (asignación de campo, no llamada a método), así que estas
# tienen que seguir siendo propiedades, no solo métodos.

var project: ProjectData:
	get: return ProjectManager.project
	set(value): ProjectManager.project = value

var session: SessionData:
	get: return SessionManager.session
	set(value): SessionManager.session = value

var undo_redo: UndoRedoManager:
	get: return ProjectManager.undo_redo
	set(value): ProjectManager.undo_redo = value

var selected_shapes: Array[String]:
	get: return ProjectManager.selected_shapes
	set(value): ProjectManager.selected_shapes = value

var current_tool: String:
	get: return SessionManager.current_tool
	set(value): SessionManager.current_tool = value

var current_layer_id: String:
	get: return ProjectManager.current_layer_id
	set(value): ProjectManager.current_layer_id = value

var current_artboard_id: String:
	get: return ProjectManager.current_artboard_id
	set(value): ProjectManager.current_artboard_id = value

var is_project_modified: bool:
	get: return ProjectManager.is_project_modified
	set(value): ProjectManager.is_project_modified = value

var settings: Dictionary:
	get: return ProjectManager.settings
	set(value): ProjectManager.settings = value


func _ready() -> void:
	print("DataRepository: Inicializado correctamente (fachada sobre ProjectManager/SessionManager)")


# ==========================================
# PROYECTO: NUEVO / GUARDAR / CARGAR
# ==========================================

func new_project(project_name: String = "Nuevo Proyecto") -> void:
	ProjectManager.new_project(project_name)

func save_project(path: String = "") -> String:
	return ProjectManager.save_project(path)

func load_project(path: String) -> bool:
	return ProjectManager.load_project(path)

func close_project() -> void:
	ProjectManager.close_project()

func save_recovery_state() -> void:
	ProjectManager.save_recovery_state()


# ==========================================
# SHAPES
# ==========================================

func create_shape(shape_type: String, data: Dictionary = {}, layer_id: String = "") -> String:
	return ProjectManager.create_shape(shape_type, data, layer_id)

func update_shape(shape_id: String, property: String, value) -> void:
	ProjectManager.update_shape(shape_id, property, value)

func delete_shape(shape_id: String) -> void:
	ProjectManager.delete_shape(shape_id)


# ==========================================
# SELECCIÓN
# ==========================================

func select_shape(shape_id: String, add_to_selection: bool = false) -> void:
	ProjectManager.select_shape(shape_id, add_to_selection)

func deselect_shape(shape_id: String) -> void:
	ProjectManager.deselect_shape(shape_id)

func clear_selection() -> void:
	ProjectManager.clear_selection()

func get_selected_shapes() -> Array[ShapeData]:
	return ProjectManager.get_selected_shapes()

func get_selected_count() -> int:
	return ProjectManager.get_selected_count()


# ==========================================
# CAPAS
# ==========================================

func create_layer(layer_name: String, artboard_id: String = "") -> String:
	return ProjectManager.create_layer(layer_name, artboard_id)

func delete_layer(layer_id: String) -> void:
	ProjectManager.delete_layer(layer_id)

func update_layer(layer_id: String, property: String, value) -> void:
	ProjectManager.update_layer(layer_id, property, value)


# ==========================================
# ARTBOARDS
# ==========================================

func create_artboard(artboard_name: String, position: Vector2 = Vector2.ZERO) -> String:
	return ProjectManager.create_artboard(artboard_name, position)

func delete_artboard(artboard_id: String) -> void:
	ProjectManager.delete_artboard(artboard_id)

func get_artboards() -> Array:
	return ProjectManager.get_artboards()

func set_active_artboard(artboard_id: String) -> void:
	ProjectManager.set_active_artboard(artboard_id)

func update_artboard(artboard_id: String, property: String, value) -> void:
	ProjectManager.update_artboard(artboard_id, property, value)


# ==========================================
# HERRAMIENTAS
# ==========================================

func set_current_tool(tool_name: String) -> void:
	SessionManager.set_current_tool(tool_name)

func update_tool_config(tool_name: String, config_key: String, value) -> void:
	SessionManager.update_tool_config(tool_name, config_key, value)

func get_tool_config(tool_name: String, config_key: String, default_value = null):
	return SessionManager.get_tool_config(tool_name, config_key, default_value)


# ==========================================
# UNDO / REDO
# ==========================================

func undo() -> void:
	ProjectManager.undo()

func redo() -> void:
	ProjectManager.redo()

func can_undo() -> bool:
	return ProjectManager.can_undo()

func can_redo() -> bool:
	return ProjectManager.can_redo()


# ==========================================
# GRID Y SNAP
# ==========================================

func set_grid_size(size: float) -> void:
	ProjectManager.set_grid_size(size)

func set_snap_enabled(enabled: bool) -> void:
	ProjectManager.set_snap_enabled(enabled)

func snap_position(position: Vector2) -> Vector2:
	return ProjectManager.snap_position(position)


# ==========================================
# GETTERS PARA ACCESO RÁPIDO
# ==========================================

func get_active_artboard() -> ArtboardData:
	return ProjectManager.get_active_artboard()

func get_active_layer() -> LayerData:
	return ProjectManager.get_active_layer()

func get_all_shapes_in_active_layer() -> Array[ShapeData]:
	return ProjectManager.get_all_shapes_in_active_layer()

func get_project_name() -> String:
	return ProjectManager.get_project_name()

func is_project_open() -> bool:
	return ProjectManager.is_project_open()


# ==========================================
# MÉTODOS PARA FILE-FLOW
# ==========================================

func get_exportable_elements() -> Array:
	return ProjectManager.get_exportable_elements()

func create_artboard_from_state(state: Dictionary) -> Node:
	return ProjectManager.create_artboard_from_state(state)
