extends Node
## Acciones extra del menú contextual Smart (tool_in_mouse.tscn) que dependen de
## la selección: «Texto en trazado» y «Separar texto del trazado».
## Vive como hijo del menú para no tocar clickrigth_nodo.gd.

const _LIST := "PanelContainer/MarginContainer/VBoxContainer/PanelContainer/VBoxContainer/PanelContainer/VBoxContainer"
const _ITEMS := [
	["TextOnPath", "text_on_path", "Texto en trazado"],
	["ReleaseTextOnPath", "release_text_on_path", "Separar texto del trazado"],
]

@onready var _menu: Control = get_parent() as Control

func _ready() -> void:
	if _menu:
		_menu.visibility_changed.connect(_refresh)
		_refresh()

func _refresh() -> void:
	if _menu == null or not _menu.visible:
		return
	var list := _menu.get_node_or_null(_LIST) as Container
	if list == null:
		return
	for spec in _ITEMS:
		var b := _ensure_button(list, spec)
		if b:
			_match_style(b, list.get_node_or_null("Copy") as Button)
			b.visible = _applies(String(spec[1]))

const _COLORS := ["font_color", "font_hover_color", "font_pressed_color",
	"icon_normal_color", "icon_hover_color", "icon_pressed_color"]
const _BOXES := ["normal", "hover", "pressed"]

## Mismos colores y fondos que «Copy» (el tema puede haber cambiado).
func _match_style(b: Button, ref: Button) -> void:
	if ref == null:
		return
	for k in _COLORS:
		b.add_theme_color_override(k, ref.get_theme_color(k))
	for k in _BOXES:
		b.add_theme_stylebox_override(k, ref.get_theme_stylebox(k))

func _applies(action: String) -> bool:
	if action == "text_on_path":
		return not ContextMenuActions.text_on_path_pair(_menu).is_empty()
	var sel := ContextMenuActions.selection(_menu)
	return sel.size() == 1 and sel[0] is Line2D and sel[0].has_meta("brush_ref")

## Copia el estilo del botón «Copy» para que encaje con el resto del menú.
func _ensure_button(list: Container, spec: Array) -> Button:
	var b := list.get_node_or_null(String(spec[0])) as Button
	if b:
		return b
	var ref := list.get_node_or_null("Copy") as Button
	b = (ref.duplicate(0) as Button) if ref else Button.new()
	b.name = String(spec[0])
	b.text = tr(String(spec[2]))
	# Icono en blanco: los colores del tema (copiados de «Copy») lo tiñen igual que al resto.
	var raw: Texture2D = load("res://icon/UI/stroke_curve.svg")
	var tm := get_node_or_null("/root/ThemeManager")
	b.icon = tm.make_white_icon(raw, 16) if tm and tm.has_method("make_white_icon") else raw
	b.tooltip_text = ""
	for c in b.get_children():
		c.queue_free()   # sin atajo de teclado
	var action: String = spec[1]
	b.pressed.connect(func():
		ContextMenuActions.execute(action, _menu)
		_menu.visible = false)
	list.add_child(b)
	return b
