# =============================================================================
# VECTOPEN — BOTÓN CENTRAL PARA DESPLAZAR CUALQUIER PANEL
# RUTA: res://script_gdscript/ui/components/global_middle_scroll.gd
#
# Con la tableta gráfica la rueda no existe: el botón del lápiz (= central)
# pulsado sobre un panel con barra de desplazamiento + arrastrar = desplazar
# (Iluminación, Pincel, Efectos, Exportar, Páginas, Recursos…). Pedido del
# usuario. Los paneles que ya tienen su propio MiddleDragScroll (Inspector,
# Capas) siguen con el suyo; sobre el lienzo no hace nada (allí el botón
# central navega).
# =============================================================================
extends Node

var _scroll: ScrollContainer = null
var _last := Vector2.ZERO

static func install(tree: SceneTree) -> void:
	if tree.root.get_node_or_null("GlobalMiddleScroll"):
		return
	var n = load("res://script_gdscript/ui/components/global_middle_scroll.gd").new()
	n.name = "GlobalMiddleScroll"
	tree.root.add_child.call_deferred(n)

## El ScrollContainer (desplazable) bajo `c`, o null.
static func scroll_for(c: Control) -> ScrollContainer:
	var n: Node = c
	while n:
		if n is ScrollContainer:
			var sc := n as ScrollContainer
			if sc.get_node_or_null("MiddleDragScroll"):
				return null   # ya lo gestiona su propio componente
			var vb := sc.get_v_scroll_bar()
			var hb := sc.get_h_scroll_bar()
			if (vb and vb.max_value - vb.page > 0.5) or (hb and hb.max_value - hb.page > 0.5):
				return sc
		n = n.get_parent()
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var hov := get_viewport().gui_get_hovered_control()
			var sc := scroll_for(hov) if hov else null
			if sc:
				_scroll = sc
				_last = mb.position
				get_viewport().set_input_as_handled()
		elif _scroll:
			_scroll = null
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _scroll:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_scroll = null
			return
		if not is_instance_valid(_scroll):
			_scroll = null
			return
		var d := mm.position - _last
		_scroll.scroll_vertical -= int(round(d.y))
		_scroll.scroll_horizontal -= int(round(d.x))
		_last = mm.position
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_scroll = null
