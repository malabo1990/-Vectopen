@tool
extends EditorPlugin
## Registra el importador de .vop. Activar en Proyecto → Ajustes del
## proyecto → Plugins → «Vectopen».

var _importer: EditorImportPlugin = null

func _enter_tree() -> void:
	_importer = preload("vop_import_plugin.gd").new()
	add_import_plugin(_importer)

func _exit_tree() -> void:
	if _importer:
		remove_import_plugin(_importer)
		_importer = null
