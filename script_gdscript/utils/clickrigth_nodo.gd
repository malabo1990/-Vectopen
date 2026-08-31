extends Control
## Menú contextual del botón derecho (tool_in_Mouse.tscn): Copiar / Pegar /
## Duplicar / Eliminar / Renombrar sobre la selección del canvas.
##
## Antes: al click derecho SOLO se mostraba/ocultaba el panel y lo movía al
## ratón — y NINGUNO de sus botones estaba conectado a nada (Copy/Paste/…
## no hacían nada). Ahora se cablean a las acciones reales de MoveTool.

@export var target_node: Node   # el panel que se muestra/oculta (normalmente self)

# Ruta a los botones dentro de tool_in_mouse.tscn (relativa a este nodo raíz).
const _MENU_BASE := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"
const _ACCIONES := {
	"Paste": "paste_clipboard",
	"Copy": "copy_selected",
	"Duplicate": "duplicate_selected",
	"Remove": "delete_selected",
}

func _ready() -> void:
	if target_node:
		target_node.visible = false
	_conectar_botones()

func _conectar_botones() -> void:
	for nombre in _ACCIONES:
		var b := get_node_or_null(_MENU_BASE + "/" + nombre) as Button
		if b and not b.pressed.is_connected(_on_accion.bind(_ACCIONES[nombre])):
			b.pressed.connect(_on_accion.bind(_ACCIONES[nombre]))
	# Cut = Copy + Remove (no hay botón propio, pero por si se añade)
	var cut := get_node_or_null(_MENU_BASE + "/Cut") as Button
	if cut and not cut.pressed.is_connected(_on_accion.bind("cut_selected")):
		cut.pressed.connect(_on_accion.bind("cut_selected"))

func _move_tool():
	var canvas := get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if canvas and canvas.has_method("get_current_tool"):
		var t = canvas.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

func _on_accion(metodo: String) -> void:
	var mt = _move_tool()
	if mt and mt.has_method(metodo):
		mt.call(metodo)
	if target_node:
		target_node.visible = false   # cerrar el menú tras la acción

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		return
	if not target_node:
		return
	if target_node.visible:
		target_node.visible = false
		return
	# No abrir el menú si el click derecho cae sobre OTRA UI (paneles, etc.).
	var gui := get_node_or_null("/root/GlobalUI")
	if gui != null and gui.is_mouse_over_ui:
		return
	# Colocar el menú junto al cursor, sin salirse de la ventana.
	var mp: Vector2 = get_global_mouse_position()
	var vp: Vector2 = get_viewport_rect().size
	var menu_size: Vector2 = (target_node as Control).size if target_node is Control else Vector2(220, 360)
	mp.x = clampf(mp.x, 0.0, maxf(0.0, vp.x - menu_size.x))
	mp.y = clampf(mp.y, 0.0, maxf(0.0, vp.y - menu_size.y))
	if target_node is Control:
		target_node.global_position = mp
	else:
		target_node.position = mp
	target_node.visible = true
