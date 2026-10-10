# =============================================================================
# RUTA: res://script_gdscript/api/vectopen_addon.gd
# Base de los COMPLEMENTOS (como los add-ons de Blender). Un complemento es
# una carpeta con:
#     addon.cfg   [addon] name, version, author, description, category,
#                 api ("1.0"), main ("main.gd")
#     main.gd     extends VectopenAddon
#
#   func _enable() -> void:       # al activarlo
#       add_operator("Repetir", _repetir, "Copia la selección en cuadrícula")
#       add_panel(mi_control)     # opcional: ajustes en su ficha
#   func _disable() -> void:      # al desactivarlo (lo registrado se quita solo)
#
# Se instala desde la pestaña Script → Complementos (.zip, carpeta o .gd).
# =============================================================================
class_name VectopenAddon
extends Node

var api: VectopenAPI = null
## Id (nombre de la carpeta) y datos de addon.cfg.
var addon_id: String = ""
var info: Dictionary = {}

var _op_ids: Array[String] = []
var _panels: Array[Control] = []

## Para sobrescribir.
func _enable() -> void:
	pass

## Para sobrescribir.
func _disable() -> void:
	pass

## Registra una acción: aparece como botón en la ficha del complemento.
## `fn` corre como UN paso de deshacer.
func add_operator(label: String, fn: Callable, tooltip: String = "", id: String = "") -> String:
	var op_id := "%s.%s" % [addon_id, id if id != "" else label.to_snake_case()]
	api.register_operator(op_id, label, fn, tooltip, addon_id)
	_op_ids.append(op_id)
	return op_id

## Añade un control (ajustes, botones propios…) a la ficha del complemento.
func add_panel(control: Control) -> void:
	_panels.append(control)

func get_panels() -> Array[Control]:
	return _panels

## Ajustes persistentes del complemento (user://vectopen_addons.cfg).
func get_setting(key: String, default: Variant = null) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(VectopenAddon.SETTINGS_PATH)
	return cfg.get_value("settings:" + addon_id, key, default)

func set_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(VectopenAddon.SETTINGS_PATH)
	cfg.set_value("settings:" + addon_id, key, value)
	cfg.save(VectopenAddon.SETTINGS_PATH)

const SETTINGS_PATH := "user://vectopen_addons.cfg"

## Llamado por PluginManager.
func _vp_enable(p_api: VectopenAPI) -> void:
	api = p_api
	_enable()

func _vp_disable() -> void:
	_disable()
	for id in _op_ids:
		if api:
			api.unregister_operator(id)
	_op_ids.clear()
	for c in _panels:
		if is_instance_valid(c):
			if c.get_parent():
				c.get_parent().remove_child(c)
			c.queue_free()
	_panels.clear()
