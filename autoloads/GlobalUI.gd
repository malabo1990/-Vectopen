# ==========================================
# RUTA: res://scripts/GlobalUI.gd
# CONFIGURACIÓN: Mantener como Autoload (Singleton)
# ==========================================
extends Node

# Controla si el puntero está interactuando con los paneles o menús
var is_mouse_over_ui: bool = false

func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	# Se considera UI SOLO si el Control bajo el cursor pertenece a la interfaz
	# (bajo un CanvasLayer o Window). Los Controles del lienzo —boundingbox,
	# títulos de artboard, handles— viven bajo Node2D y NO deben bloquear
	# el zoom ni el arrastre del canvas. Ver _es_ui_real()
	is_mouse_over_ui = _es_ui_real(viewport.gui_get_hovered_control())

## Un Control es de la UI real si, subiendo por el árbol, aparece un
## CanvasLayer (paneles de main.tscn) o un Window (diálogos/popups) ANTES
## que un Node2D (el mundo del lienzo). Los controles del mundo no son UI.
func _es_ui_real(control: Control) -> bool:
	if control == null:
		return false
	var node: Node = control
	while node:
		if node is CanvasLayer or node is Window:
			return true
		if node is Node2D:
			return false
		node = node.get_parent()
	return true
