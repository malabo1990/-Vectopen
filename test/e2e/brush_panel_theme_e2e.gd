# =============================================================================
# UX-06 — Panel de Pincel y estilos: acabado y colores del tema (claro y
# oscuro) en Smart, Modern y Pro. Ver tool_panel_theme_common.gd.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/brush_panel_theme_e2e.gd
# =============================================================================
extends "res://test/e2e/tool_panel_theme_common.gd"

func _init() -> void:
	PANEL_NAME = "brush"
	TOOL_ID = "brush"
	SCRIPT_PATH = "res://script_gdscript/ui/panel_brush.gd"
	SCENE_PATH = "res://scenes/ui/panels/panel_brush.tscn"
	OUT = "user://brush_panel_theme"
	super._init()
