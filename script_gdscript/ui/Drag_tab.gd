@tool
extends Node

@export var cursor_scene: PackedScene = null: # Escena del cursor (.tscn)
	set(value):
		cursor_scene = value
		update_cursor()
@export var cursor_scale: Vector2 = Vector2(1, 1): # Escala del cursor
	set(value):
		cursor_scale = value
		update_cursor()
@export var cursor_visible: bool = true: # Visibilidad del cursor
	set(value):
		cursor_visible = value
		update_cursor()
@export var z_index: int = 100: # Prioridad de renderizado (Z Index)
	set(value):
		z_index = value
		update_cursor()
@export var use_camera: bool = true: # Usar Camera2D para transformar coordenadas
	set(value):
		use_camera = value
		update_cursor()

var cursor_instance: Node = null # Referencia al cursor instanciado

func _ready():
	if Engine.is_editor_hint():
		return # Evita ejecutar lógica en el editor
	if cursor_scene:
		initialize_cursor()

func _input(event):
	if Engine.is_editor_hint():
		return
	if cursor_instance and event is InputEventMouseMotion:
		var mouse_pos = event.position
		if use_camera:
			var camera = get_viewport().get_camera_2d()
			if camera:
				mouse_pos = camera.get_global_mouse_position()
		var scale_factor = get_viewport().get_final_transform().get_scale()
		mouse_pos /= scale_factor
		cursor_instance.global_position = mouse_pos
		# Depuración: descomentar para verificar alineación
		# print("Mouse: ", mouse_pos, " Cursor: ", cursor_instance.global_position)

func initialize_cursor():
	if cursor_instance:
		cursor_instance.queue_free()
	if cursor_scene:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		cursor_instance = cursor_scene.instantiate()
		add_child(cursor_instance)
		if cursor_instance is CanvasItem:
			cursor_instance.set_as_top_level(true)
			cursor_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cursor_instance.scale = cursor_scale
			cursor_instance.visible = cursor_visible
			cursor_instance.z_index = z_index

func update_cursor():
	if Engine.is_editor_hint() and cursor_scene:
		# Actualiza el cursor en el editor
		if cursor_instance:
			cursor_instance.queue_free()
		cursor_instance = cursor_scene.instantiate()
		add_child(cursor_instance)
		if cursor_instance is CanvasItem:
			cursor_instance.set_as_top_level(true)
			cursor_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cursor_instance.scale = cursor_scale
			cursor_instance.visible = cursor_visible
			cursor_instance.z_index = z_index
	elif cursor_instance:
		# Actualiza propiedades en tiempo de ejecución
		if cursor_instance is CanvasItem:
			cursor_instance.scale = cursor_scale
			cursor_instance.visible = cursor_visible
			cursor_instance.z_index = z_index

func _exit_tree():
	if cursor_instance:
		cursor_instance.queue_free()
