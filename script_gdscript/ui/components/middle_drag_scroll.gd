# =============================================================================
# VECTOPEN — DESPLAZAR UN PANEL ARRASTRANDO CON EL BOTÓN CENTRAL
# RUTA: res://script_gdscript/ui/components/middle_drag_scroll.gd
#
# Igual que en Capas (Layertree): botón central (rueda o botón del lápiz)
# pulsado sobre el panel + arrastrar = desplazar píxel a píxel. Se engancha
# como hijo de un ScrollContainer:
#     MiddleDragScroll.attach(scroll)
# Lo usan el inspector de Modern (DockedInspector) y el lateral de Pro.
# Pedido del usuario: "falta drag con el botón medio para panel inspector
# como lo hace en capas" (Modern y Pro).
# =============================================================================
extends Node

const NODE_NAME := "MiddleDragScroll"

var _scroll: ScrollContainer
var _dragging := false
var _last_y := 0.0

static func attach(scroll: ScrollContainer) -> Node:
	var existing := scroll.get_node_or_null(NODE_NAME)
	if existing:
		return existing
	var n = load("res://script_gdscript/ui/components/middle_drag_scroll.gd").new()
	n.name = NODE_NAME
	scroll.add_child(n)
	return n

func _ready() -> void:
	_scroll = get_parent() as ScrollContainer

func is_dragging() -> bool:
	return _dragging

## ¿El clic cae de verdad sobre este panel? (no sobre un popover encima).
func _over_panel(pos: Vector2) -> bool:
	if not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():
		return false
	if not _scroll.get_global_rect().has_point(pos):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered == null or hovered == _scroll or _scroll.is_ancestor_of(hovered)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		var mb := event as InputEventMouseButton
		if mb.pressed and _over_panel(mb.position):
			_dragging = true
			_last_y = mb.position.y
			_scroll.mouse_default_cursor_shape = Control.CURSOR_DRAG
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _dragging:
			_stop()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		# Si se soltó el botón fuera de la ventana, no quedarse enganchado.
		# (Algunos movimientos llegan sin máscara de botón —p. ej. al recolocar
		# el puntero o con lápiz—: solo cuenta si el botón está suelto de verdad.)
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_stop()
			return
		var bar := _scroll.get_v_scroll_bar()
		if bar:
			bar.value -= mm.position.y - _last_y
		_last_y = mm.position.y
		get_viewport().set_input_as_handled()

func _stop() -> void:
	_dragging = false
	if is_instance_valid(_scroll):
		_scroll.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_stop()
