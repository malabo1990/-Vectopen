# Complemento de ejemplo: la plantilla más corta posible.
extends VectopenAddon

func _enable() -> void:
	add_operator("Saludar", _saludar, "Escribe un saludo y crea un texto en el artboard")

func _saludar() -> void:
	api.info("¡Hola desde el complemento «%s»!" % info.get("name", addon_id))
	api.add_text(Vector2(40, 40), "Hola Vectopen", 32)
