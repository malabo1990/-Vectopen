# =============================================================================
# VECTOPEN — ASA PARA CAMBIAR EL ANCHO DE UN PANEL ARRASTRANDO SU BORDE
# RUTA: res://script_gdscript/ui/components/panel_edge_resizer.gd
#
# Pedido del usuario: el panel de Capas (Layout: capas + herramientas) se
# ensancha arrastrando su borde: el IZQUIERDO en Smart (panel a la derecha de
# la pantalla) y el DERECHO en Modern / Pro (entre el panel y la regla).
#
# Franja fina e invisible sobre el borde que sigue al panel en cada
# fotograma (vale en cualquier modo aunque el panel cambie de sitio). Al
# pasar el ratón: cursor ↔ y una línea fina de acento (estilo Apple / Figma).
# Emite `dragged(dx)` mientras se arrastra y `released` al soltar; quien lo
# usa decide el ancho (mínimo / máximo, reglas, guardar).
# =============================================================================
extends Control

signal dragged(dx: float)
signal released()

const GRAB_W := 8.0

var target: Control = null          ## el panel cuyo borde se sigue
var edge_left := true               ## true: borde izquierdo · false: derecho
var _dragging := false
var _hover := false
var _last_x := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	top_level = true
	z_index = 90
	tooltip_text = tr("Arrastra para cambiar el ancho del panel")
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())

func is_dragging() -> bool:
	return _dragging

func _process(_dt: float) -> void:
	var ok := is_instance_valid(target) and target.is_visible_in_tree() and target.size.x > 40.0
	visible = ok
	if not ok:
		return
	var r := target.get_global_rect()
	var x := r.position.x if edge_left else r.end.x
	global_position = Vector2(x - GRAB_W * 0.5, r.position.y)
	size = Vector2(GRAB_W, r.size.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_dragging = true
			_last_x = mb.global_position.x
		elif _dragging:
			_dragging = false
			released.emit()
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var dx := mm.global_position.x - _last_x
		_last_x = mm.global_position.x
		if absf(dx) > 0.0:
			dragged.emit(dx)
		accept_event()

func _draw() -> void:
	if not (_hover or _dragging):
		return
	var tm := get_node_or_null("/root/ThemeManager")
	var col: Color = tm.get_color(tm.Slot.ACCENT) if tm else Color(0.2, 0.55, 1.0)
	col.a = 0.9 if _dragging else 0.6
	draw_rect(Rect2(Vector2(size.x * 0.5 - 1.0, 6.0), Vector2(2.0, size.y - 12.0)), col)
