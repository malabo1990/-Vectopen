extends Node
class_name FileSystemManager

## FileSystemManager: Manejo de operaciones de archivos para Vectopen
##
## Autoload responsable de:
## - Guardar/abrir archivos
## - Exportar elementos en múltiples formatos
## - Gestionar la lista de archivos recientes

# --- Señales ---
signal file_saved(path: String)
signal file_loaded(path: String)
signal export_completed(path: String, format: String)
signal export_failed(path: String, format: String, error: String)

# --- Configuración ---
const RECENT_CONFIG_PATH := "user://recent_assets.cfg"
const RECENT_FILES_LIMIT := 20

# ==========================================
# GESTIÓN DE ARCHIVOS RECIENTES
# ==========================================

func get_recent_files() -> Array:
	var config = ConfigFile.new()
	config.load(RECENT_CONFIG_PATH)
	return config.get_value("History", "items", [])

static func save_canvas_element_to_recent(element: Node, format: String) -> String:
	var target_path = "user://recent/%s.%s" % [element.name, format.to_lower()]
	var file = FileAccess.open(target_path, FileAccess.WRITE)
	if file:
		var data_content = _convert_node_to_format(element, format)
		file.store_string(data_content)
		file.close()
		_register_in_history(element.name, target_path, format)
		return target_path
	return ""

static func _register_in_history(file_name: String, path: String, format: String) -> void:
	var config = ConfigFile.new()
	config.load(RECENT_CONFIG_PATH)
	var recent_files = config.get_value("History", "items", [])
	
	# Verificar si el archivo ya está en la lista
	for i in range(recent_files.size()):
		if recent_files[i]["path"] == path:
			recent_files.remove_at(i)
			break
	
	# Añadir al inicio de la lista
	recent_files.insert(0, {
		"name": file_name,
		"path": path,
		"format": format,
		"time": Time.get_unix_time_from_system()
	})
	
	# Limitar a RECENT_FILES_LIMIT archivos recientes
	if recent_files.size() > RECENT_FILES_LIMIT:
		recent_files.resize(RECENT_FILES_LIMIT)
	
	config.set_value("History", "items", recent_files)
	config.save(RECENT_CONFIG_PATH)

# ==========================================
# CONVERSIÓN DE FORMATOS
# ==========================================

static func _convert_node_to_format(element: Node, format: String) -> String:
	match format.to_lower():
		"svg":
			if element.has_method("to_svg"):
				return element.to_svg()
			return _node_to_svg(element)
		"png":
			if element.has_method("to_png"):
				return element.to_png()
			return _node_to_png(element)
		"pdf":
			if element.has_method("to_pdf"):
				return element.to_pdf()
			return _node_to_pdf(element)
		"jpeg", "jpg":
			if element.has_method("to_jpeg"):
				return element.to_jpeg()
			return _node_to_jpeg(element)
		_:
			return ""

static func _node_to_svg(element: Node) -> String:
	var svg_content = """
	<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
		<!-- SVG content for %s -->
	</svg>
	""" % element.name
	return svg_content

static func _node_to_png(_element: Node) -> String:
	return ""

static func _node_to_pdf(_element: Node) -> String:
	return ""

static func _node_to_jpeg(_element: Node) -> String:
	return ""

# ==========================================
# EXPORTACIÓN FÍSICA
# ==========================================

static func export_element(element: Node, format: String, destination: String) -> void:
	var file_path = "%s/%s.%s" % [destination, element.name, format.to_lower()]
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var data_content = _convert_node_to_format(element, format)
		if data_content != "":
			file.store_string(data_content)
			file.close()
		else:
			push_error("Failed to convert element to format")
	else:
		push_error("Failed to open file for writing")

# ==========================================
# GESTIÓN DE ELEMENTOS EXPORTABLES
# ==========================================

func get_exportable_elements() -> Array:
	# Obtener elementos exportables del DataRepository
	if DataRepository and DataRepository.has_method("get_exportable_elements"):
		return DataRepository.get_exportable_elements()
	return []