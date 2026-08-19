extends Button

@export var tool_name: String = ""
@export var create_at_center: bool = false

var canvas_editor: Node = null


func _ready() -> void:
	# Button.focus_mode es FOCUS_ALL por defecto en Godot — al pulsar
	# cualquier botón de herramienta se quedaba con el foco de teclado
	# indefinidamente (nada lo libera después), y canvas.gd::_handle_keyboard()
	# bloquea TODOS los atajos globales (undo/redo/zoom/portapapeles/mover
	# con flechas...) mientras haya un foco de UI activo — es el guard
	# correcto para no robarle atajos a un campo de texto, pero un botón de
	# icono no debería retenerlo. Encontrado el 19/08/2026 verificando en
	# vivo la Fase 1 de teclado: Ctrl+A/flechas no hacían nada tras pulsar
	# cualquier botón de la barra de herramientas.
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)
	_find_canvas_editor()


func _find_canvas_editor() -> void:
	if is_instance_valid(canvas_editor):
		return
	if get_tree():
		canvas_editor = get_tree().get_first_node_in_group("_vectopen_canvas")
	if not canvas_editor:
		var parent = get_parent()
		while parent:
			if parent.has_method("switch_tool") or parent is CanvasEditor:
				canvas_editor = parent
				return
			parent = parent.get_parent()


func _on_pressed() -> void:
	if tool_name.is_empty():
		return
	if not is_instance_valid(canvas_editor):
		_find_canvas_editor()
	if not is_instance_valid(canvas_editor):
		return
	if canvas_editor.has_method("switch_tool"):
		canvas_editor.switch_tool(tool_name)
	if create_at_center:
		if canvas_editor.has_method("get_current_tool"):
			var tool_instance = canvas_editor.get_current_tool()
			if tool_instance and tool_instance.has_method("create_at_center"):
				tool_instance.create_at_center()
