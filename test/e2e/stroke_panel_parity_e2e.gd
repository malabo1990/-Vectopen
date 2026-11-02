# =============================================================================
# UX-08 — «Panel de trazos incompleto en Modern y Pro».
# Paridad con Smart: con una línea y un rectángulo seleccionados se usan con
# clics reales TODOS los controles del panel de trazos de Smart («Trazos y
# Borde»), del Inspector de Modern y de la barra lateral de Pro (y de los
# desplegables que abren). En cada modo deben poder editarse TODAS las
# propiedades de trazo del objeto (color, grosor, alineación, extremos,
# estilo, guiones, puntas, escala de puntas y perfil), cada cambio debe dejar
# un paso de deshacer y deshacerlo todo devuelve el objeto a como estaba.
# Reutiliza el arnés de cobertura del Inspector (UX-06) limitado a «stroke_».
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/stroke_panel_parity_e2e.gd
# =============================================================================
extends "res://test/e2e/inspector_props_coverage_e2e.gd"

func _init() -> void:
	OS.set_environment("UX06_PROPS", "stroke_")
	OS.set_environment("UX06_ONLY", "path,rect")
	OS.set_environment("UX06_MODES", "smart,modern,professional")
	super._init()
