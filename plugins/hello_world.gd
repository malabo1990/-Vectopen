extends Node

func on_load() -> void:
	set_meta("description", "Ejemplo de plugin para Vectopen")
	set_meta("version", "1.0.0")
	print("[Plugin] Hello Vectopen! Plugin '%s' v%s loaded." % [name, get_meta("version")])

func on_unload() -> void:
	print("[Plugin] Goodbye from '%s'." % name)
