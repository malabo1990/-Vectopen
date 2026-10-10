# =============================================================================
# RUTA: res://script_gdscript/api/vectopen_script.gd
# Base de los scripts de la pestaña Script. Un script hereda de esta clase y
# escribe `run()`; `api` (VectopenAPI) ya está lista al llamarse.
#
#   extends VectopenScript
#   func run() -> void:
#       var s := api.add_star(Vector2(400, 300), 80, 5)
#       api.set_fill(s, Color.GOLD)
#
# Sin `extends` ni `func run()`, el código se envuelve solo (modo rápido).
# `run()` puede usar `await` (p.ej. await api.wait(0.5)).
# =============================================================================
class_name VectopenScript
extends RefCounted

var api: VectopenAPI = null

func run() -> void:
	pass
