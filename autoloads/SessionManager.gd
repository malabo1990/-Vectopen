# ==========================================
# RUTA: res://autoloads/SessionManager.gd
# CONFIGURACIÓN: Autoload (Singleton)
# ORDEN DE CARGA: Después de GlobalEvents / DataRepository, antes que ProjectManager lo necesite
# ==========================================
extends Node

## Extraído de DataRepository.gd el 19/08/2026 (ver docs/*/reports).
## Dueño del estado de sesión (no persistente en el proyecto en sí):
## cámara, visibilidad de reglas/rejilla, paneles abiertos, portapapeles,
## configuración por herramienta y la herramienta activa.
## ProjectManager lee/serializa `session` al guardar/cargar un proyecto.

var GlobalEvents: Node = null  # Se asigna en _ready()

var session: SessionData = null   # Datos temporales de sesión
var current_tool: String = "select"  # Nombre de herramienta activa


func _ready() -> void:
	GlobalEvents = get_node_or_null("/root/GlobalEvents")
	if not GlobalEvents:
		push_warning("SessionManager: GlobalEvents no encontrado. Las señales no se emitirán.")

	session = SessionData.new()
	print("SessionManager: Inicializado correctamente")


func reset_session() -> void:
	session = SessionData.new()


# ==========================================
# HERRAMIENTAS
# ==========================================

func set_current_tool(tool_name: String) -> void:
	if current_tool == tool_name:
		return

	current_tool = tool_name

	if GlobalEvents:
		GlobalEvents.emit_safe("data_tool_changed", tool_name)
		GlobalEvents.emit_safe("tool_changed", tool_name)  # Compatibilidad


func update_tool_config(tool_name: String, config_key: String, value) -> void:
	if not session.tool_configs.has(tool_name):
		session.tool_configs[tool_name] = {}

	session.tool_configs[tool_name][config_key] = value

	if GlobalEvents:
		GlobalEvents.emit_safe("data_tool_config_changed", tool_name, config_key, value)


func get_tool_config(tool_name: String, config_key: String, default_value = null):
	if session.tool_configs.has(tool_name):
		return session.tool_configs[tool_name].get(config_key, default_value)
	return default_value


# ==========================================
# CLASES INTERNAS DE DATOS
# ==========================================

## Datos de Sesión
class SessionData:
	var camera_zoom: float = 1.0
	var camera_offset: Vector2 = Vector2.ZERO
	var rulers_visible: bool = true
	var grid_visible: bool = true
	var open_panels: Array[String] = []
	var tool_configs: Dictionary = {}   # tool_name -> {config_key: value}
	var clipboard_shapes: Array = []    # Array[ProjectManager.ShapeData]

	func serialize() -> Dictionary:
		return {
			"camera_zoom": camera_zoom,
			"camera_offset": [camera_offset.x, camera_offset.y],
			"rulers_visible": rulers_visible,
			"grid_visible": grid_visible,
			"open_panels": open_panels.duplicate()
		}

	func deserialize(data: Dictionary) -> void:
		camera_zoom = data.get("camera_zoom", camera_zoom)
		var off = data.get("camera_offset", [0, 0])
		camera_offset = Vector2(off[0], off[1])
		rulers_visible = data.get("rulers_visible", rulers_visible)
		grid_visible = data.get("grid_visible", grid_visible)
		# JSON.parse devuelve un Array sin tipo → hay que convertir a Array[String]
		# o la asignación revienta al cargar un proyecto.
		open_panels.clear()
		for p in data.get("open_panels", []):
			open_panels.append(String(p))
		tool_configs = data.get("tool_configs", {})
