extends Node

@export var color_rect: ColorRect
@export var hex_label: Label
@export var rgba_label: Label
@export var panel_container: PanelContainer
@export var texture_rect: TextureRect

var is_capturing: bool = false
var last_captured_color: Color = Color.BLACK

func _ready() -> void:
	if not color_rect or not hex_label or not rgba_label or not panel_container or not texture_rect:
		push_error("cursor_mouse: missing node references")
		return
	panel_container.visible = false
	texture_rect.visible = true
	is_capturing = false
	update_ui_colors(last_captured_color)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_I and Input.is_key_pressed(KEY_CTRL):
		_toggle_panel()

func _process(_delta: float) -> void:
	if is_capturing:
		update_color()

func _toggle_panel() -> void:
	panel_container.visible = not panel_container.visible
	texture_rect.visible = not panel_container.visible
	is_capturing = panel_container.visible
	if is_capturing:
		update_color()

func update_color() -> void:
	var color := _pick_color()
	last_captured_color = color
	update_ui_colors(color)

func update_ui_colors(color: Color) -> void:
	color_rect.color = color
	hex_label.text = color.to_html(false)
	rgba_label.text = "RGBA: (%d, %d, %d, %d)" % [color.r8, color.g8, color.b8, color.a8]

func _pick_color() -> Color:
	var viewport := get_viewport()
	if not viewport:
		return Color(randf(), randf(), randf(), 1.0)
	var mouse_pos := viewport.get_mouse_position()
	var canvas := get_node_or_null("/root/CanvasRoot")
	if canvas and canvas.has_method("pick_color_at"):
		return canvas.pick_color_at(mouse_pos)
	return Color(randf(), randf(), randf(), 1.0)
