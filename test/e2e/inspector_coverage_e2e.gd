# =============================================================================
# UX-12 — Revisión profunda del Inspector (texto, trazos, párrafos, relleno…).
# Arnés de cobertura (UX-06) en modo ESTRICTO, en Modern y Pro, con los siete
# tipos de objeto (rectángulo, elipse, polígono, estrella, trazado, texto y
# modelo 3D). Falla si:
#   · una propiedad del objeto no tiene control que la edite;
#   · un control, usado con clics reales, no tiene efecto (no escribe nada,
#     no deja paso de historial, no muestra/oculta nada ni cambia su estado);
#   · deshacer no devuelve el objeto a como estaba;
#   · rehacer no repite exactamente lo hecho;
#   · una propiedad declarada en InspectorCore.PROPS no la tiene ningún objeto.
#   flatpak run --command=godot org.godotengine.Godot --path . --screen 1 \
#       -s res://test/e2e/inspector_coverage_e2e.gd
# =============================================================================
extends "res://test/e2e/inspector_props_coverage_e2e.gd"

func _init() -> void:
	OS.set_environment("UX12_STRICT", "1")
	super._init()
