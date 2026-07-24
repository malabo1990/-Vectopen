extends Control

## Sistema de cursor personalizado para UI que reemplaza el cursor del sistema por una escena instanciada.
## Soporta hotspot, escalado, visibilidad, prioridad de renderizado y visualización del hotspot.

@export var cursor_scene: PackedScene = null:
	## Escena del cursor (.tscn) que se instanciará como cursor personalizado.
	set(value):
		cursor_scene = value
		update_cursor()
@export var hotspot: Vector2 = Vector2(0, 0):
	## Punto de clic del cursor relativo a la esquina superior izquierda de la escena.
	## Se escala con cursor_scale para mantener la alineación.
	set(value):
		hotspot = value
		update_cursor()
		queue_redraw() # Redibuja para actualizar la visualización del hotspot
@export var cursor_scale: Vector2 = Vector2(1, 1):
	## Escala aplicada al cursor instanciado.
	set(value):
		cursor_scale = value
		update_cursor()
@export var cursor_visible: bool = true:
	## Controla la visibilidad del cursor instanciado.
	set(value):
		cursor_visible = value
		update_cursor()
@export var cursor_z_index: int = 100:
	## Prioridad de renderizado (z-index) del cursor.
	set(value):
		cursor_z_index = value
		update_cursor()
@export var use_camera: bool = false:
	## Si es true, usa las coordenadas globales de la Camera2D para posicionar el cursor.
	## En UI, normalmente se desactiva (false) para usar coordenadas de pantalla.
	set(value):
		use_camera = value
		update_cursor()
@export var draw_hotspot: bool = true # Línea 39 corregida
	## Si es true, dibuja una cruz en el hotspot para depuración.

var cursor_instance: Node = null ## Referencia al cursor instanciado.

func _ready() -> void:
	## Inicializa el cursor al cargar el nodo, salvo en el editor.
	if Engine.is_editor_hint():
		return # Evita lógica de juego en el editor
	if cursor_scene and cursor_scene.can_instantiate():
		initialize_cursor()
	else:
		push_warning("No se asignó una escena válida para el cursor en el Inspector.")

func _input(event: InputEvent) -> void:
	## Actualiza la posición del cursor según el movimiento del ratón.
	if Engine.is_editor_hint():
		return
	if cursor_instance and cursor_instance is CanvasItem and event is InputEventMouseMotion:
		var mouse_pos: Vector2 = event.position
		if use_camera:
			var camera: Camera2D = get_viewport().get_camera_2d()
			if camera:
				mouse_pos = camera.get_global_mouse_position()
			else:
				push_warning("No se encontró Camera2D, usando posición local del ratón.")
		else:
			# En UI, usamos las coordenadas de pantalla directamente
			mouse_pos = get_global_mouse_position()
		var scale_factor: Vector2 = get_viewport().get_final_transform().get_scale()
		if scale_factor.x != 0 and scale_factor.y != 0:
			mouse_pos /= scale_factor
		else:
			push_warning("El factor de escala del viewport es cero, se ignora el ajuste.")
		cursor_instance.global_position = mouse_pos - (hotspot * cursor_scale)
		queue_redraw() # Redibuja la cruz en tiempo de ejecución
		# Imprime las posiciones para depuración
		print("Mouse Position: ", mouse_pos, " Cursor Position: ", cursor_instance.global_position, " Hotspot: ", (hotspot * cursor_scale))

func _draw() -> void:
	## Dibuja una cruz en el hotspot para depuración.
	if draw_hotspot and cursor_instance and cursor_instance is CanvasItem:
		# Dibuja la cruz en la posición (0, 0) del nodo Control
		var origin_pos: Vector2 = Vector2(0, 0) # Origen local del nodo Control
		var color: Color = Color(1, 0, 0, 0.8) # Rojo para el origen
		var size: float = 10.0
		draw_line(origin_pos - Vector2(size, 0), origin_pos + Vector2(size, 0), color, 2.0)
		draw_line(origin_pos - Vector2(0, size), origin_pos + Vector2(0, size), color, 2.0)
		draw_circle(origin_pos, 2.0, color)
		# Dibuja la cruz en la posición del hotspot
		var hotspot_pos: Vector2 = cursor_instance.global_position + (hotspot * cursor_scale)
		var color_hotspot: Color = Color(0, 1, 0, 0.8) # Verde para el hotspot
		draw_line(hotspot_pos - Vector2(size, 0), hotspot_pos + Vector2(size, 0), color_hotspot, 2.0)
		draw_line(hotspot_pos - Vector2(0, size), hotspot_pos + Vector2(0, size), color_hotspot, 2.0)
		draw_circle(hotspot_pos, 2.0, color_hotspot)

func initialize_cursor() -> void:
	## Instancia la escena del cursor y configura sus propiedades.
	if cursor_instance:
		cursor_instance.queue_free()
		cursor_instance = null
	if cursor_scene and cursor_scene.can_instantiate():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		cursor_instance = cursor_scene.instantiate()
		if cursor_instance is CanvasItem:
			add_child(cursor_instance)
			cursor_instance.set_as_top_level(true)
			cursor_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cursor_instance.scale = cursor_scale
			cursor_instance.visible = cursor_visible
			cursor_instance.z_index = cursor_z_index
		else:
			push_error("La escena del cursor debe ser un CanvasItem.")
			cursor_instance.queue_free()
			cursor_instance = null
	else:
		push_warning("No se asignó una escena válida para el cursor.")
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func update_cursor() -> void:
	## Actualiza las propiedades del cursor o lo reinstancia en el editor.
	if Engine.is_editor_hint() and cursor_scene and cursor_scene.can_instantiate():
		if cursor_instance and cursor_instance is CanvasItem:
			# Actualiza propiedades en lugar de recrear si ya existe
			cursor_instance.scale = cursor_scale
			cursor_instance.visible = cursor_visible
			cursor_instance.z_index = cursor_z_index
		else:
			# Instancia nueva si no existe o no es CanvasItem
			if cursor_instance:
				cursor_instance.queue_free()
			cursor_instance = cursor_scene.instantiate()
			if cursor_instance is CanvasItem:
				add_child(cursor_instance)
				cursor_instance.set_as_top_level(true)
				cursor_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cursor_instance.scale = cursor_scale
				cursor_instance.visible = cursor_visible
				cursor_instance.z_index = cursor_z_index
			else:
				push_error("La escena del cursor debe ser un CanvasItem.")
				cursor_instance.queue_free()
				cursor_instance = null
	elif cursor_instance and cursor_instance is CanvasItem:
		# Actualiza propiedades en tiempo de ejecución
		cursor_instance.scale = cursor_scale
		cursor_instance.visible = cursor_visible
		cursor_instance.z_index = cursor_z_index
	queue_redraw() # Asegura que la visualización del hotspot se actualice

func _exit_tree() -> void:
	## Libera el cursor al salir del árbol de nodos.
	if cursor_instance:
		cursor_instance.queue_free()
		cursor_instance = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
