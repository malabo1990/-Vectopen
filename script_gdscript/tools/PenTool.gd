# res://scripts/PenTool.gd
class_name PenTool
extends ToolBase

var target_artboard: Node2D = null
var active_line: Line2D = null
# `is_drawing` ya lo declara ToolBase (Fase migración 2026-08-19) — no redeclarar.

const LINE_COLOR := Color("#00aaff")
const LINE_WIDTH := 2.5

func _find_artboard() -> void:
	if not is_instance_valid(canvas):
		return
	var manager = canvas.find_child("ArtboardManager", true, false)
	if manager and "active_artboard" in manager and is_instance_valid(manager.active_artboard):
		target_artboard = manager.active_artboard
	elif canvas.artboards_container and canvas.artboards_container.get_child_count() > 0:
		target_artboard = canvas.artboards_container.get_child(0)

func activate() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_find_artboard()
	print("PenTool: Activada - target_artboard=", target_artboard)

func deactivate() -> void:
	_finish_current_line()

func handle_input(event: InputEvent) -> bool:
	if not is_instance_valid(canvas):
		return false
	if not is_instance_valid(target_artboard):
		_find_artboard()
	if not is_instance_valid(target_artboard):
		return false

	var global_mouse = canvas.get_global_mouse_position()
	var local_mouse: Vector2 = target_artboard.to_local(global_mouse)
	var artboard_rect = Rect2(Vector2.ZERO, target_artboard.artboard_size)

	if not artboard_rect.has_point(local_mouse):
		return false

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not is_instance_valid(active_line):
					_start_new_line(local_mouse)
				else:
					active_line.add_point(local_mouse)
				return true
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_finish_current_line()
			return true

	elif event is InputEventMouseMotion and is_instance_valid(active_line):
		if active_line.get_point_count() > 0:
			active_line.set_point_position(active_line.get_point_count() - 1, local_mouse)
			return true

	return false

func _start_new_line(start_pos: Vector2) -> void:
	active_line = Line2D.new()
	active_line.name = "BezierPath_%d" % (target_artboard.get_child_count() + 1)
	active_line.width = LINE_WIDTH
	active_line.default_color = LINE_COLOR
	active_line.antialiased = true
	active_line.joint_mode = Line2D.LINE_JOINT_ROUND
	active_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	active_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	target_artboard.add_child(active_line)
	active_line.add_point(start_pos)
	active_line.add_point(start_pos)
	is_drawing = true

func _finish_current_line() -> void:
	if is_instance_valid(active_line):
		if active_line.get_point_count() <= 2:
			active_line.queue_free()
		else:
			active_line.remove_point(active_line.get_point_count() - 1)
			print("PenTool: Trayecto finalizado")
	active_line = null
	is_drawing = false
