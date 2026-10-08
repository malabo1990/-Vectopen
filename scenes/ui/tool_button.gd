extends Button

@export var tool_name: String = ""
@export var create_at_center: bool = false
@export var target_node: Node = null

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
	# El popup de texto trae los botones Texto/Párrafo pero no la sección de
	# configuración (el .tscn no se toca): el botón "paragraph" la monta por
	# código al arrancar, como el panel de polígonos pero embebida debajo.
	if tool_name == "paragraph":
		call_deferred("_mount_paragraph_config")


func _mount_paragraph_config() -> void:
	var p := get_parent()
	while p:
		if p is PanelContainer and p.name == "text":
			break
		p = p.get_parent()
	if p == null:
		return
	const PP := preload("res://script_gdscript/ui/panel_paragraph.gd")
	var old = PP.find_in(p)
	if old:
		old.visible = true
		return
	var box := p.get_node_or_null("MarginContainer/BoxContainer") as BoxContainer
	if box == null:
		return
	var pp: Control = PP.new()
	pp.name = "ParagraphConfig"
	box.add_child(pp)


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
	if tool_name == "3d" or tool_name == "model3d":
		var im = get_node_or_null("/root/ImportExportManager")
		if is_instance_valid(im) and im.has_method("import_3d_model"):
			im.import_3d_model()
		return
	if not is_instance_valid(canvas_editor):
		_find_canvas_editor()
	if not is_instance_valid(canvas_editor):
		return
	if canvas_editor.has_method("switch_tool"):
		canvas_editor.switch_tool(tool_name)
	if is_instance_valid(target_node) and "visible" in target_node:
		target_node.visible = not target_node.visible
	if create_at_center:
		if canvas_editor.has_method("get_current_tool"):
			var tool_instance = canvas_editor.get_current_tool()
			if tool_instance and tool_instance.has_method("create_at_center"):
				tool_instance.create_at_center()
