extends Node

signal plugin_loaded(plugin_name: String)
signal plugin_unloaded(plugin_name: String)
signal plugin_error(plugin_name: String, message: String)

const PLUGINS_DIR := "res://plugins/"
const CONFIG_PATH := "user://vectopen_plugins.cfg"

var _plugins: Dictionary = {}
var _loaded_order: Array[String] = []

func _ready() -> void:
	_discover_plugins()

func _discover_plugins() -> void:
	var dir := DirAccess.open(PLUGINS_DIR)
	if not dir:
		return

	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			_load_plugin(file_name.trim_suffix(".gd"), cfg)
		file_name = dir.get_next()

func _load_plugin(p_name: String, cfg: ConfigFile) -> void:
	if cfg.has_section_key(p_name, "disabled") and cfg.get_value(p_name, "disabled"):
		return

	var path := PLUGINS_DIR + p_name + ".gd"
	var script := load(path) as Script
	if not script:
		plugin_error.emit(p_name, "Failed to load script: " + path)
		return

	var instance: Node = script.new()
	if not instance:
		plugin_error.emit(p_name, "Failed to instantiate: " + path)
		return
	if not instance.has_method("on_load"):
		instance.free()
		plugin_error.emit(p_name, "Plugin must implement on_load()")
		return

	instance.name = p_name
	add_child(instance)
	_plugins[p_name] = instance
	_loaded_order.append(p_name)

	if instance.has_method("on_load"):
		instance.call("on_load")

	plugin_loaded.emit(p_name)

func get_plugin(p_name: String) -> Node:
	return _plugins.get(p_name, null)

func get_all_plugins() -> Array[String]:
	return _loaded_order.duplicate()

func is_plugin_loaded(p_name: String) -> bool:
	return p_name in _plugins

func disable_plugin(p_name: String) -> void:
	if p_name not in _plugins:
		return
	var plugin := _plugins[p_name] as Node
	if plugin and plugin.has_method("on_unload"):
		plugin.call("on_unload")
	remove_child(plugin)
	_plugins.erase(p_name)
	_loaded_order.erase(p_name)

	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(p_name, "disabled", true)
	cfg.save(CONFIG_PATH)

	plugin_unloaded.emit(p_name)

func reload_plugin(p_name: String) -> void:
	disable_plugin(p_name)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(p_name, "disabled", false)
	cfg.save(CONFIG_PATH)
	_discover_plugins()
