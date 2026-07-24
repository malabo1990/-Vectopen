extends Node
class_name VectopenPlugin

var plugin_name: String:
	get: return name

var plugin_version: String:
	get: return get_meta("version", "0.1.0")

var plugin_description: String:
	get: return get_meta("description", "")

func on_load() -> void:
	pass

func on_unload() -> void:
	pass
