# =============================================================================
# UX-07 — Panel Bézier y estilos: sin gris fijo, colores e iconos del tema
# (claro y oscuro) en Smart, Modern y Pro. Ver tool_panel_theme_common.gd.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/bezier_panel_theme_e2e.gd
# =============================================================================
extends "res://test/e2e/tool_panel_theme_common.gd"

func _init() -> void:
	PANEL_NAME = "bezier"
	TOOL_ID = "bezier"
	SCRIPT_PATH = "res://script_gdscript/ui/panel_bezier.gd"
	SCENE_PATH = "res://scenes/ui/panels/panel_bezier.tscn"
	OUT = "user://bezier_panel_theme"
	super._init()
