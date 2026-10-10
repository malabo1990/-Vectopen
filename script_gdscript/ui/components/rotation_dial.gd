# =============================================================================
# VECTOPEN — COMPONENTE ROTATION DIAL (DESIGN SYSTEM)
# RUTA: res://script_gdscript/ui/components/rotation_dial.gd
# Dial de rotación compacto (28-32 px), elegante y sincronizado en tiempo real
# =============================================================================
class_name RotationDial
extends Control

signal angle_changed(degrees: float)
signal drag_started()
signal drag_ended()

@export var angle_degrees: float = 0.0:
	set(v):
		var wrapped := wrapf(v, 0.0, 360.0)
		if not is_equal_approx(angle_degrees, wrapped):
			angle_degrees = wrapped
			queue_redraw()

@export var enabled: bool = true:
	set(v):
		enabled = v
		mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		queue_redraw()

var _is_dragging: bool = false

func _init(size_px: float = 28.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_NONE

func _ready() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m): queue_redraw())

func _draw() -> void:
	var center := size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 - 2.0
	if radius <= 0:
		return

	var tm = get_node_or_null("/root/ThemeManager")
	var bg_col := Color(0.14, 0.14, 0.14, 1.0)
	var border_col := Color(0.3, 0.3, 0.3, 1.0)
	var needle_col := Color(0.04, 0.52, 1.0, 1.0)
	var tick_col := Color(0.5, 0.5, 0.5, 0.4)

	if tm:
		var S = tm.Slot
		bg_col = tm.get_color(S.INPUT_BG)
		border_col = tm.get_color(S.INPUT_BORDER)
		needle_col = tm.get_color(S.ACCENT)
		tick_col = tm.get_color(S.BORDER_STRONG) if "BORDER_STRONG" in S else tm.get_color(S.BORDER)
		tick_col.a = 0.5

	if not enabled:
		border_col.a = 0.3
		needle_col.a = 0.3
		tick_col.a = 0.2

	# Fondo y aro exterior
	draw_circle(center, radius, bg_col)
	draw_arc(center, radius, 0.0, TAU, 32, border_col, 1.0, true)

	# 4 Marcas de cuadrante (0°, 90°, 180°, 270°)
	for i in range(4):
		var a: float = deg_to_rad(i * 90.0)
		var p1 := center + Vector2(cos(a), sin(a)) * (radius - 3.5)
		var p2 := center + Vector2(cos(a), sin(a)) * (radius - 1.0)
		draw_line(p1, p2, tick_col, 1.0, true)

	# Aguja del dial
	var rad := deg_to_rad(angle_degrees)
	var dir := Vector2(cos(rad), sin(rad))
	var needle_tip := center + dir * (radius - 2.5)
	draw_line(center, needle_tip, needle_col, 1.8, true)
	draw_circle(center, 2.0, needle_col)

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			drag_started.emit()
			_update_angle_from_pos(event.position, event.is_shift_pressed())
		else:
			if _is_dragging:
				_is_dragging = false
				drag_ended.emit()

	elif event is InputEventMouseMotion and _is_dragging:
		_update_angle_from_pos(event.position, event.is_shift_pressed())

	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			drag_started.emit()
			_update_angle_from_pos(event.position, false)
		else:
			if _is_dragging:
				_is_dragging = false
				drag_ended.emit()

	elif event is InputEventScreenDrag and _is_dragging:
		_update_angle_from_pos(event.position, false)

func _update_angle_from_pos(pos: Vector2, snap_15: bool) -> void:
	var center := size / 2.0
	var offset := pos - center
	if offset.length_squared() < 4.0:
		return
	var deg := wrapf(rad_to_deg(atan2(offset.y, offset.x)), 0.0, 360.0)
	if snap_15:
		deg = snappedf(deg, 15.0)
		if is_equal_approx(deg, 360.0):
			deg = 0.0
	angle_degrees = deg
	angle_changed.emit(angle_degrees)
