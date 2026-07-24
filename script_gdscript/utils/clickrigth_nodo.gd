extends Control

# Exportar la referencia al nodo que se quiere mostrar/ocultar
@export var target_node: Node

func _ready():
	if target_node:
		target_node.visible = false
	else:
		print("Error: Nodo objetivo no asignado en el editor.")

func _input(event):
	if event is InputEventMouseButton:
		# Detectar clic derecho
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Verificar si el nodo objetivo está asignado
				if target_node:
					if target_node.visible:
						target_node.visible = false  # Hacer invisible el nodo
					else:
						# Hacer visible el nodo y moverlo a la posición del mouse
						target_node.position = get_global_mouse_position()
						target_node.visible = true
				else:
					print("Error: Nodo objetivo no asignado.")
