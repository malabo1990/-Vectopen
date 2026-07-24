extends Control

@export var panel: Control
@export var title_label: Label
@export var content_label: RichTextLabel
@export var buttons: Array[Button] = []
@export var json_file_path: String = ""
@export var hover_delay: float = 2.0
@export var display_time: float = 3.0

var json_data: Dictionary = {}
var current_button: Button = null
var hover_timer: float = 0.0
var display_timer: float = 0.0
var is_hovering: bool = false
var is_panel_visible: bool = false

func _ready() -> void:
	# Initialize panel visibility
	if panel:
		panel.visible = false
	else:
		push_warning("Panel is not assigned!")
	
	# Load JSON and connect buttons
	load_json_file()
	connect_buttons()

func load_json_file() -> void:
	if json_file_path.is_empty():
		push_warning("No JSON file path assigned")
		return
	
	if not FileAccess.file_exists(json_file_path):
		push_error("JSON file does not exist: " + json_file_path)
		return
	
	var file = FileAccess.open(json_file_path, FileAccess.READ)
	if file == null:
		push_error("Error opening JSON file: ", FileAccess.get_open_error())
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		push_error("Error parsing JSON: ", json.get_error_message())
		return
	
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("JSON data is not a dictionary")
		return
	
	json_data = json.data
	print("JSON loaded successfully")

func connect_buttons() -> void:
	for button in buttons:
		if button:
			button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
			button.mouse_exited.connect(_on_button_mouse_exited)
			button.pressed.connect(_on_button_pressed)
		else:
			push_warning("Null element in buttons array")

func _on_button_mouse_entered(button: Button) -> void:
	current_button = button
	is_hovering = true
	hover_timer = 0.0
	display_timer = 0.0

func _on_button_mouse_exited() -> void:
	is_hovering = false
	hover_timer = 0.0
	# Don't hide panel immediately; let _process handle it
	current_button = null

func _on_button_pressed() -> void:
	_hide_panel()

func _show_panel() -> void:
	if not current_button or not json_data.has(current_button.name):
		return
	
	if not panel or not title_label or not content_label:
		push_warning("Panel, title_label, or content_label not assigned")
		return
	
	@warning_ignore("incompatible_ternary")
	title_label.text = current_button.text if current_button.text else current_button.name
	content_label.text = str(json_data[current_button.name])
	panel.visible = true
	is_panel_visible = true
	display_timer = 0.0

func _hide_panel() -> void:
	if panel:
		panel.visible = false
	is_panel_visible = false
	display_timer = 0.0

func _process(delta: float) -> void:
	# Ensure panel is valid
	if not panel:
		return

	# Handle hover delay for showing panel
	if is_hovering and not is_panel_visible:
		hover_timer += delta
		if hover_timer >= hover_delay:
			_show_panel()
	
	# Handle display time for hiding panel
	if is_panel_visible:
		display_timer += delta
		if display_timer >= display_time:
			_hide_panel()
	
	# Hide panel if not hovering and mouse is outside panel
	if is_panel_visible and not is_hovering:
		if panel.visible:
			var panel_rect = panel.get_global_rect()
			var mouse_pos = get_global_mouse_position()
			if not panel_rect.has_point(mouse_pos):
				_hide_panel()
