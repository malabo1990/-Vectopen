extends PanelContainer

@export var action_container: VBoxContainer
@export var filter_line_edit: LineEdit

var _rebind_action: String = ""
var _action_rows: Dictionary = {}

const CONFIG_PATH := "user://vectopen_inputmap.cfg"
const EXCLUDED_PREFIXES := ["ui_", "spatial_editor/"]

func _ready() -> void:
	if filter_line_edit:
		filter_line_edit.text_changed.connect(_on_filter_changed)
	_build_action_list()

func _get_relevant_actions() -> Array:
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_names"):
		return vi.get_action_names()
	return []

func _action_display_name(action: String) -> String:
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_display"):
		return vi.get_action_display(action)
	return action

func _get_action_events_text(action: String) -> String:
	var vi := get_node_or_null("/root/VectopenInput")
	if vi and vi.has_method("get_action_text"):
		return vi.get_action_text(action)
	return "..."

func _build_action_list(filter: String = "") -> void:
	if not action_container:
		return
	for c in action_container.get_children():
		c.queue_free()
	_action_rows.clear()

	var actions := _get_relevant_actions()
	actions.sort()

	for action in actions:
		if filter != "" and not action.contains(filter.to_lower()):
			continue

		var display := _action_display_name(action)
		var current := _get_action_events_text(action)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)
		action_container.add_child(row)

		var label := Label.new()
		label.text = display
		label.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		label.mouse_filter = MOUSE_FILTER_STOP
		row.add_child(label)

		var bind_btn := Button.new()
		bind_btn.text = current
		bind_btn.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		bind_btn.toggle_mode = true
		bind_btn.toggled.connect(_on_bind_toggled.bind(action, bind_btn))
		row.add_child(bind_btn)

		var reset_btn := Button.new()
		reset_btn.text = "R"
		reset_btn.custom_minimum_size = Vector2(24, 24)
		reset_btn.pressed.connect(_on_reset_action.bind(action, bind_btn))
		row.add_child(reset_btn)

		_action_rows[action] = bind_btn

func _on_bind_toggled(toggled: bool, action: String, btn: Button) -> void:
	if not toggled:
		_rebind_action = ""
		btn.text = _get_action_events_text(action)
		return
	_rebind_action = action
	btn.text = "Press a key..."

func _input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	if event is InputEventKey and event.pressed:
		var new_event := InputEventKey.new()
		new_event.keycode = event.keycode
		new_event.ctrl_pressed = event.ctrl_pressed
		new_event.shift_pressed = event.shift_pressed
		new_event.alt_pressed = event.alt_pressed
		new_event.meta_pressed = event.meta_pressed

		InputMap.action_erase_events(_rebind_action)
		InputMap.action_add_event(_rebind_action, new_event)

		_save_rebinding(_rebind_action, new_event)

		if _action_rows.has(_rebind_action):
			var btn = _action_rows[_rebind_action]
			btn.button_pressed = false
			btn.text = _get_action_events_text(_rebind_action)

		_rebind_action = ""
		get_viewport().set_input_as_handled()

func _on_reset_action(action: String, btn: Button) -> void:
	InputMap.action_erase_events(action)
	if _action_rows.has(action):
		btn.text = _get_action_events_text(action)
	_remove_saved_rebinding(action)

func _on_filter_changed(new_text: String) -> void:
	_build_action_list(new_text)

func _save_rebinding(action: String, event: InputEventKey) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var existing = cfg.get_value("rebinds", action, [])
	existing.append({
		"keycode": event.keycode,
		"ctrl": event.ctrl_pressed,
		"shift": event.shift_pressed,
		"alt": event.alt_pressed,
		"meta": event.meta_pressed,
	})
	cfg.set_value("rebinds", action, existing)
	cfg.save(CONFIG_PATH)

func _remove_saved_rebinding(action: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		cfg.set_value("rebinds", action, [])
		cfg.save(CONFIG_PATH)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_build_action_list()
