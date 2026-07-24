# ==========================================
# RUTA: res://autoloads/ToolManager.gd
# CONFIGURACIÓN: Añadir como Autoload (Singleton)
# ORDEN DE CARGA: Después de GlobalEvents, DataRepository y ToolFactory
# ==========================================
extends Node

## Gestor de Herramientas para Vectopen
## Carga, instancia y gestiona herramientas modulares

# ==========================================
# REFERENCIAS
# ==========================================

var GlobalEvents: Node = null
var DataRepository: Node = null
var ToolFactory: Node = null


# ==========================================
# ESTADO
# ==========================================

var _available_tools: Dictionary = {}      # tool_name -> tool_info
var _current_tool_instance: Node = null   # Instancia activa
var _current_tool_name: String = ""
var _tool_container: Node = null           # Nodo contenedor para herramientas


# ==========================================
# ESTRUCTURA DE DATOS DE HERRAMIENTA
# ==========================================

class ToolInfo:
	var name: String
	var display_name: String
	var icon: Texture2D
	var scene_path: String
	var shortcut: String
	var tooltip: String
	
	func _init(p_name: String, p_display: String, p_path: String):
		name = p_name
		display_name = p_display
		scene_path = p_path
		icon = null
		shortcut = ""
		tooltip = ""


# ==========================================
# INICIALIZACIÓN
# ==========================================

func _ready() -> void:
	# Buscar referencias
	GlobalEvents = get_node_or_null("/root/GlobalEvents")
	DataRepository = get_node_or_null("/root/DataRepository")
	ToolFactory = get_node_or_null("/root/ToolFactory")
	
	if not DataRepository:
		push_warning("ToolManager: DataRepository no encontrado. Algunas funciones no estarán disponibles.")
	if not ToolFactory:
		push_warning("ToolManager: ToolFactory no encontrado. Se usará creación directa.")
	
	# Registrar herramientas disponibles
	_register_available_tools()
	
	# Conectar señales
	_connect_signals()
	
	print("ToolManager: Inicializado. Herramientas disponibles: ", _available_tools.keys())


func _register_available_tools() -> void:
	"""Registra todas las herramientas disponibles"""
	
	_register_tool("select", "Selección", "res://tools/select_tool/select_tool.tscn", "V", "Seleccionar y mover objetos")
	_register_tool("move", "Mover", "res://tools/move_tool/move_tool.tscn", "M", "Mover artboard")
	_register_tool("pen", "Pluma", "res://tools/pen_tool/pen_tool.tscn", "P", "Dibujo libre")
	_register_tool("bezier", "Bézier", "res://tools/bezier_tool/bezier_tool.tscn", "B", "Curvas Bézier")
	_register_tool("rectangle", "Rectángulo", "res://tools/rectangle_tool/rectangle_tool.tscn", "R", "Crear rectángulos")
	_register_tool("ellipse", "Elipse", "res://tools/ellipse_tool/ellipse_tool.tscn", "E", "Crear elipses")
	_register_tool("text", "Texto", "res://tools/text_tool/text_tool.tscn", "T", "Insertar texto")
	_register_tool("hand", "Mano", "res://tools/hand_tool/hand_tool.tscn", "H", "Navegar lienzo")
	_register_tool("brush", "Pincel", "res://tools/brush_tool/brush_tool.tscn", "", "Pincel vectorial de trazo libre")


func _register_tool(tool_name: String, display_name: String, scene_path: String, shortcut: String = "", tooltip: String = "") -> void:
	"""Registra una herramienta en el sistema"""
	var info = ToolInfo.new(tool_name, display_name, scene_path)
	info.shortcut = shortcut
	info.tooltip = tooltip
	_available_tools[tool_name] = info


func _connect_signals() -> void:
	if GlobalEvents:
		# Escuchar cambios de herramienta
		if GlobalEvents.has_signal("tool_changed"):
			GlobalEvents.tool_changed.connect(_on_tool_changed_from_ui)
		
		# Escuchar atajos de teclado
		if GlobalEvents.has_signal("tool_shortcut_pressed"):
			GlobalEvents.tool_shortcut_pressed.connect(_on_tool_shortcut)


# ==========================================
# CONFIGURACIÓN DEL CONTENEDOR
# ==========================================

func set_tool_container(container: Node) -> void:
	"""Establece el nodo contenedor donde se instanciarán las herramientas"""
	_tool_container = container
	print("ToolManager: Contenedor de herramientas establecido")


# ==========================================
# CAMBIO DE HERRAMIENTA
# ==========================================

func switch_tool(tool_name: String, force: bool = false) -> bool:
	"""Cambia a la herramienta especificada"""
	
	# Verificar si ya está activa
	if not force and _current_tool_name == tool_name:
		return true
	
	# Verificar que la herramienta existe
	if not _available_tools.has(tool_name):
		push_error("ToolManager: Herramienta no encontrada - ", tool_name)
		return false
	
	# Desactivar herramienta actual
	_deactivate_current_tool()
	
	# Cargar y activar nueva herramienta
	var success = _load_and_activate_tool(tool_name)
	
	if success:
		_current_tool_name = tool_name
		
		# Actualizar DataRepository
		if DataRepository:
			DataRepository.set_current_tool(tool_name)
		
		# Emitir señal
		if GlobalEvents:
			GlobalEvents.emit_safe("data_tool_changed", tool_name)
			GlobalEvents.emit_safe("tool_changed", tool_name)
		
		print("ToolManager: Herramienta cambiada a - ", tool_name)
	
	return success


func _deactivate_current_tool() -> void:
	"""Desactiva y elimina la herramienta actual"""
	if _current_tool_instance:
		if _current_tool_instance.has_method("deactivate"):
			_current_tool_instance.deactivate()
		
		_current_tool_instance.queue_free()
		_current_tool_instance = null


func _load_and_activate_tool(tool_name: String) -> bool:
	"""Carga e instancia una herramienta usando ToolFactory"""
	var tool_info = _available_tools[tool_name]

	if ToolFactory:
		_current_tool_instance = ToolFactory.create_tool_from_scene(tool_info.scene_path)
	else:
		# Fallback directo sin ToolFactory
		if not FileAccess.file_exists(tool_info.scene_path):
			push_error("ToolManager: Archivo de herramienta no encontrado - ", tool_info.scene_path)
			return false
		var tool_scene = load(tool_info.scene_path)
		if not tool_scene:
			push_error("ToolManager: No se pudo cargar - ", tool_info.scene_path)
			return false
		_current_tool_instance = tool_scene.instantiate()

	if not _current_tool_instance:
		push_error("ToolManager: No se pudo instanciar la herramienta - ", tool_name)
		return false

	var target_container = _tool_container if _tool_container else self
	target_container.add_child(_current_tool_instance)

	if _current_tool_instance.has_method("activate"):
		_current_tool_instance.activate()

	return true


# ==========================================
# ACCESO A HERRAMIENTA ACTIVA
# ==========================================

func get_current_tool() -> Node:
	"""Retorna la instancia de la herramienta actual"""
	return _current_tool_instance


func get_current_tool_name() -> String:
	"""Retorna el nombre de la herramienta actual"""
	return _current_tool_name


func get_current_tool_info() -> ToolInfo:
	"""Retorna la información de la herramienta actual"""
	return _available_tools.get(_current_tool_name, null)


# ==========================================
# LISTADO DE HERRAMIENTAS
# ==========================================

func get_available_tools() -> Array[String]:
	"""Retorna lista de nombres de herramientas disponibles"""
	var tools: Array[String] = []
	for tool_name in _available_tools.keys():
		tools.append(tool_name)
	return tools


func get_tool_info(tool_name: String) -> ToolInfo:
	"""Retorna información de una herramienta específica"""
	return _available_tools.get(tool_name, null)


func get_tools_for_ui() -> Array[Dictionary]:
	"""Retorna lista de herramientas formateada para UI"""
	var tools_ui: Array[Dictionary] = []
	
	for tool_name in _available_tools:
		var info = _available_tools[tool_name]
		
		tools_ui.append({
			"name": tool_name,
			"display_name": info.display_name,
			"icon": info.icon,
			"shortcut": info.shortcut,
			"tooltip": info.tooltip
		})
		
	return tools_ui


# ==========================================
# CONFIGURACIÓN DE HERRAMIENTAS
# ==========================================

func get_tool_config(tool_name: String, config_key: String, default_value = null):
	"""Obtiene una configuración de herramienta"""
	if DataRepository:
		return DataRepository.get_tool_config(tool_name, config_key, default_value)
	
	# Fallback local
	var config_path = "user://tools_config/" + tool_name + ".json"
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		var config = JSON.parse_string(file.get_as_text())
		if config and config.has(config_key):
			return config[config_key]
	
	return default_value


func set_tool_config(tool_name: String, config_key: String, value) -> void:
	"""Establece una configuración de herramienta"""
	if DataRepository:
		DataRepository.update_tool_config(tool_name, config_key, value)
	else:
		# Fallback local
		var config_path = "user://tools_config/" + tool_name + ".json"
		var config: Dictionary = {}
		var file: FileAccess
		
		if FileAccess.file_exists(config_path):
			file = FileAccess.open(config_path, FileAccess.READ)
			config = JSON.parse_string(file.get_as_text()) or {}
		
		config[config_key] = value
		
		# Asegurar directorio
		var dir = DirAccess.open("user://")
		if not dir.dir_exists("tools_config"):
			dir.make_dir("tools_config")
		
		file = FileAccess.open(config_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(config, "\t"))


# ==========================================
# ENVÍO DE ENTRADA A HERRAMIENTA ACTIVA
# ==========================================

func forward_input_to_tool(event: InputEvent, canvas_position: Vector2 = Vector2.ZERO) -> bool:
	"""Envía un evento de entrada a la herramienta activa"""
	if not _current_tool_instance:
		return false
	
	if _current_tool_instance.has_method("handle_input"):
		return _current_tool_instance.handle_input(event, canvas_position)
	
	return false


func forward_mouse_motion(position: Vector2, delta: Vector2) -> void:
	"""Envía movimiento del ratón a la herramienta activa"""
	if _current_tool_instance and _current_tool_instance.has_method("handle_mouse_motion"):
		_current_tool_instance.handle_mouse_motion(position, delta)


func forward_mouse_press(position: Vector2, button: int, pressed: bool) -> void:
	"""Envía clic del ratón a la herramienta activa"""
	if _current_tool_instance and _current_tool_instance.has_method("handle_mouse_press"):
		_current_tool_instance.handle_mouse_press(position, button, pressed)


# ==========================================
# MANEJADORES DE SEÑALES
# ==========================================

func _on_tool_changed_from_ui(tool_name: String) -> void:
	"""Responde a cambios de herramienta desde UI"""
	switch_tool(tool_name)


func _on_tool_shortcut(shortcut: String) -> void:
	"""Responde a atajos de teclado para herramientas"""
	for tool_name in _available_tools:
		var info = _available_tools[tool_name]
		
		if info.shortcut.to_lower() == shortcut.to_lower():
			switch_tool(tool_name)
			break


# ==========================================
# LIMPIEZA
# ==========================================

func _exit_tree() -> void:
	"""Limpia la herramienta actual al salir"""
	_deactivate_current_tool()
