# btn_toggle.gd
extends Node

@export var nodo_disparador: Node # Puede ser un Button, TextureButton, Area2D, etc.
@export var target_nodo: Node     # Puede ser un Label, Panel, Node2D, otra Escena, etc.

func _ready() -> void:
	if nodo_disparador and target_nodo:
		# Buscamos la señal de activación típica de Godot ("pressed" o "input_event")
		if nodo_disparador.has_signal("pressed"):
			nodo_disparador.pressed.connect(_on_toggle)
		elif nodo_disparador.has_signal("input_event"):
			nodo_disparador.input_event.connect(func(_viewport, _event, _shape_idx): if _event.is_action_pressed("click_izquierdo"): _on_toggle())

func _on_toggle() -> void:
	# Cambia la visibilidad de manera segura si el nodo tiene la propiedad
	if "visible" in target_nodo:
		target_nodo.visible = !target_nodo.visible
