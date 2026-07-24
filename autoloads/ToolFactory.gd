# =============================================================================
# VECTOPEN CORE — TOOL FACTORY
# RUTA: res://autoloads/ToolFactory.gd
# ORDEN DE CARGA: Después de GlobalEvents, antes de ToolManager
# =============================================================================
extends Node

## Factoría para crear instancias de herramientas
## Separa el "cómo se crea" (factory) del "cuándo se activa" (ToolManager)


# ==========================================
# CONSTANTES
# ==========================================

const TOOLS_BASE_PATH := "res://tools/"
const SCRIPTS_BASE_PATH := "res://script_gdscript/tools/"


# ==========================================
# CACHÉ DE ESCENAS
# ==========================================

var _scene_cache: Dictionary = {}


# ==========================================
# API PÚBLICA — INSTANCIACIÓN
# ==========================================

func create_tool_from_scene(scene_path: String) -> Node:
	if not scene_path:
		if ErrorHandler: ErrorHandler.report_file("scene_path vacío")
		else: push_error("ToolFactory: scene_path vacío")
		return null

	if not FileAccess.file_exists(scene_path):
		if ErrorHandler: ErrorHandler.report_file("escena no encontrada - " + scene_path)
		else: push_error("ToolFactory: escena no encontrada - ", scene_path)
		return null

	var scene: PackedScene = _get_cached_scene(scene_path)
	if not scene:
		return null

	var instance = scene.instantiate()
	if not instance:
		push_error("ToolFactory: no se pudo instanciar - ", scene_path)
		return null

	return instance


func create_tool_from_script(script_path: String, canvas_node = null) -> Node:
	if not script_path:
		push_error("ToolFactory: script_path vacío")
		return null

	var script: Script = load(script_path)
	if not script:
		push_error("ToolFactory: no se pudo cargar script - ", script_path)
		return null

	var base_type = script.get_instance_base_type()
	var instance: Node

	if base_type == "RefCounted":
		push_error("ToolFactory: los scripts RefCounted no son compatibles como Node: ", script_path)
		return null
	else:
		instance = script.new()

	if canvas_node and instance.has("canvas") and not instance.canvas:
		instance.canvas = canvas_node

	if instance.has_method("_ready"):
		instance._ready()

	return instance


# ==========================================
# CACHÉ
# ==========================================

func precache_scene(scene_path: String) -> void:
	if not _scene_cache.has(scene_path) and FileAccess.file_exists(scene_path):
		var scene = load(scene_path)
		if scene:
			_scene_cache[scene_path] = scene


func clear_cache() -> void:
	_scene_cache.clear()


func _get_cached_scene(scene_path: String) -> PackedScene:
	if _scene_cache.has(scene_path):
		return _scene_cache[scene_path]

	var scene: PackedScene = load(scene_path)
	if scene:
		_scene_cache[scene_path] = scene
	return scene
