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

const _ALIGN_TOOLS := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/TOOLS ALINEACION/VBoxContainer"
# Fila de iconos: distribuir-h, alinear-izq, alinear-centro-h, distribuir-h, alinear-der.
const _ALIGN_ROW := {
	"HBoxContainer4/Button":  ["distribute", "h"],
	"HBoxContainer4/Button2": ["align", "left"],
	"HBoxContainer4/Button3": ["align", "center_h"],
	"HBoxContainer4/Button4": ["distribute", "h"],
	"HBoxContainer4/Button7": ["align", "right"],
}
# Grid 4×4 de alineación: 9 puntos combinados + barras de un solo eje.
const _ALIGN_GRID := {
	"BoxContainer/GridContainer/Button":    ["align", ["left", "top"]],
	"BoxContainer/GridContainer/Button2":   ["align", ["center_h", "top"]],
	"BoxContainer/GridContainer/Button3":   ["align", ["right", "top"]],
	"BoxContainer/GridContainer/Button4":   ["align", ["top"]],
	"BoxContainer/GridContainer/Button5":   ["align", ["left", "middle"]],
	"BoxContainer/GridContainer/Button6":   ["align", ["center_h", "middle"]],
	"BoxContainer/GridContainer/Button7":   ["align", ["right", "middle"]],
	"BoxContainer/GridContainer/Button8":   ["align", ["middle"]],
	"BoxContainer/GridContainer/Button9":   ["align", ["left", "bottom"]],
	"BoxContainer/GridContainer/Button10":  ["align", ["center_h", "bottom"]],
	"BoxContainer/GridContainer/Button11":  ["align", ["right", "bottom"]],
	"BoxContainer/GridContainer/Button12":  ["align", ["bottom"]],
	"BoxContainer/GridContainer/Button13":  ["align", ["left"]],
	"BoxContainer/GridContainer/Button14":  ["align", ["center_h"]],
	"BoxContainer/GridContainer/Button15":  ["align", ["right"]],
	"BoxContainer/GridContainer/Button17":  ["align", ["center_h", "middle"]],
}

func _conectar_botones() -> void:
	for nombre in _ACCIONES:
		var b := get_node_or_null(_MENU_BASE + "/" + nombre) as Button
		if b and not b.pressed.is_connected(_on_accion.bind(_ACCIONES[nombre])):
			b.pressed.connect(_on_accion.bind(_ACCIONES[nombre]))
	var cut := get_node_or_null(_MENU_BASE + "/Cut") as Button
	if cut and not cut.pressed.is_connected(_on_accion.bind("cut_selected")):
		cut.pressed.connect(_on_accion.bind("cut_selected"))
	# Renombrar (botones "name" y "Button6") → editor inline de nombre.
	for rn in ["name", "Button6"]:
		var rb := get_node_or_null(_MENU_BASE + "/" + rn) as Button
		if rb and not rb.pressed.is_connected(_on_rename):
			rb.pressed.connect(_on_rename)
	# Alineación / distribución → InspectorCore (opera sobre la selección, con undo).
	for mapa in [_ALIGN_ROW, _ALIGN_GRID]:
		for rel in mapa:
			var ab := get_node_or_null(_ALIGN_TOOLS + "/" + rel) as Button
			var op: Array = mapa[rel]
			if ab and not ab.pressed.is_connected(_on_align.bind(op[0], op[1])):
				ab.pressed.connect(_on_align.bind(op[0], op[1]))

## Editor inline del nombre de la figura seleccionada (selección única).
func _on_rename() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	var props: Dictionary = ic.current_props()
	if not props.has("name"):
		return   # multiselección o nada seleccionado
	var le := LineEdit.new()
	le.text = String(props["name"]["value"])
	le.custom_minimum_size = Vector2(180, 26)
	le.size = le.custom_minimum_size
	add_child(le)
	le.global_position = get_global_mouse_position()
	le.select_all()
	le.grab_focus()
	le.text_submitted.connect(func(t: String):
		ic.apply("name", t)
		le.queue_free()
		if target_node: target_node.visible = false)
	le.focus_exited.connect(func(): if is_instance_valid(le): le.queue_free())

func _on_align(kind: String, arg) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if kind == "align":
		ic.align(arg)
	else:
		ic.distribute(arg)
	if target_node:
		target_node.visible = false

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
