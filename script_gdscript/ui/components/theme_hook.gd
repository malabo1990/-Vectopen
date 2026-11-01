# =============================================================================
# RUTA: res://script_gdscript/ui/components/theme_hook.gd
# Nodo auxiliar que vive DENTRO de un panel y repinta sus colores al cambiar
# el tema. Al liberarse con el panel, Godot borra la conexión solo.
# (Antes ToolPanelDock conectaba una lambda desde una función estática que
# capturaba el panel: nunca se desconectaba y, con el panel ya liberado, cada
# cambio de tema daba «Lambda capture at index 0 was freed» — miles de veces.)
# =============================================================================
extends Node

func _on_theme_changed(_mode = null) -> void:
	var p := get_parent()
	if p is Control:
		load("res://script_gdscript/ui/tool_panel_dock.gd").apply_theme_colors(p)
