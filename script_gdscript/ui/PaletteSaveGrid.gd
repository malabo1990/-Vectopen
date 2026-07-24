extends GridContainer
class_name PaletteSaveGrid

const SAVE_PATH := "user://vectopen_palette.cfg"

var saved_colors: Array[Color] = []
var add_button: Button


func _ready() -> void:
	_find_add_button()
	_load_colors()
	_refresh()


func _find_add_button() -> void:
	for child in get_children():
		if child is Button and child.text == "+":
			add_button = child
			if not add_button.pressed.is_connected(_on_add_pressed):
				add_button.pressed.connect(_on_add_pressed)
			break


func _on_add_pressed() -> void:
	var color_rect = _find_color_rect()
	if not color_rect:
		return
	saved_colors.append(color_rect.color)
	_save_colors()
	_refresh()


func _find_color_rect() -> ColorRect:
	return get_node_or_null("../../BoxContainer/ColorRect_fill")


func _refresh() -> void:
	for child in get_children():
		if child != add_button:
			child.queue_free()

	for c in saved_colors:
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(30, 30)
		rect.color = c
		rect.mouse_filter = Control.MOUSE_FILTER_PASS
		rect.gui_input.connect(_on_swatch_clicked.bind(rect))
		add_child(rect)


func _on_swatch_clicked(event: InputEvent, swatch: ColorRect) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var color_rect = _find_color_rect()
		if color_rect:
			color_rect.color = swatch.color


func _load_colors() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var arr = cfg.get_value("palette", "colors", [])
		for c in arr:
			if c is Color:
				saved_colors.append(c)


func _save_colors() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("palette", "colors", saved_colors)
	cfg.save(SAVE_PATH)
