# ==========================================
# RUTA: res://scripts/drawing.gd
# ==========================================
extends Node2D

var current_line: Line2D = null
var is_drawing = false
var lines: Array[Line2D] = []

func _ready() -> void:
	pass # Las líneas se configuran dinámicamente al presionar el ratón

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_drawing = true
			start_new_line()
		else:
			if is_drawing:
				is_drawing = false
				finish_current_line()
	elif event is InputEventMouseMotion and is_drawing:
		add_point_to_current_line(get_local_mouse_position())

func start_new_line() -> void:
	current_line = Line2D.new()
	current_line.width = 8.0
	current_line.default_color = Color.BLACK
	current_line.joint_mode = Line2D.LINE_JOINT_ROUND
	current_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	current_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(current_line)
	current_line.add_point(get_local_mouse_position())

func add_point_to_current_line(pos: Vector2) -> void:
	if current_line:
		current_line.add_point(pos)

func finish_current_line() -> void:
	if current_line:
		lines.append(current_line)
		current_line = null
