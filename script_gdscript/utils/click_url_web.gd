# clickable_link.gd (CORREGIDO)
# Script para Godot 4.x
# Atachar a cualquier nodo que herede de 'Control' (UI) para abrir una URL al hacer clic.

extends Control
class_name ClickableLink # Buena práctica añadir un nombre de clase

# Exportamos la variable 'url' para que aparezca en el Inspector.
@export var url: String = "https://godotengine.org"

# Variable para rastrear si el clic se inició DENTRO de este control.
var clicked_inside: bool = false

func _ready():
	# Advertencia si la URL está vacía al iniciar la escena
	if url.is_empty():
		print_rich("[color=yellow]Advertencia:[/color] El nodo '", name, "' tiene un script ClickableLink sin URL definida.")

	# Asegurarse de que el nodo procese eventos de input del ratón.
	# STOP: Consume el evento aquí. PASS: Permite que siga propagándose.
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent):
	# Se llama cuando hay input DENTRO de los límites del Control.
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			
			if event.is_pressed():
				# Botón izquierdo presionado DENTRO del control.
				clicked_inside = true
				# (Opcional: Añadir feedback visual, como cambiar modulate)
				# modulate = Color(0.8, 0.8, 0.8)
				accept_event() # Aceptar el evento de presionar
				
			elif event.is_released() and clicked_inside:
				# Botón izquierdo soltado DENTRO del control, y se había presionado dentro antes.
				# ¡Este es nuestro clic válido!
				clicked_inside = false # Reseteamos el estado
				# (Opcional: Restaurar feedback visual)
				# modulate = Color(1, 1, 1)
				
				if not url.is_empty():
					print("Abriendo URL: ", url)
					# OS.shell_open abre la URL en el navegador por defecto.
					var err = OS.shell_open(url)
					if err != OK:
						print_rich("[color=red]Error:[/color] No se pudo abrir la URL '", url, "'. Código de error: ", err)
				else:
					print_rich("[color=yellow]Advertencia:[/color] Clic en '", name, "' sin URL configurada.")
				
				accept_event() # Aceptar el evento de soltar
				
			else:
				# Botón soltado, pero o no fue presionado dentro o ya se manejó/canceló.
				clicked_inside = false
				# (Opcional: Asegurarse de restaurar feedback visual)
				# modulate = Color(1, 1, 1)

# _notification se llama para varios eventos del nodo.
func _notification(what):
	# NOTIFICATION_MOUSE_EXIT se envía cuando el cursor sale de los límites del control.
	if what == NOTIFICATION_MOUSE_EXIT:
		# Si el ratón sale del control mientras estábamos en estado "presionado dentro",
		# cancelamos ese estado para que no se active al soltar fuera.
		if clicked_inside:
			clicked_inside = false
			# (Opcional: Restaurar feedback visual si se salió mientras estaba presionado)
			# modulate = Color(1, 1, 1)

	# NOTIFICATION_MOUSE_ENTER se envía cuando el cursor entra. Útil para efectos hover.
	# elif what == NOTIFICATION_MOUSE_ENTER:
		# pass # Aquí podrías poner lógica para hover si quisieras
