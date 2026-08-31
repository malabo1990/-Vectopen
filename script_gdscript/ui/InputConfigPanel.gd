@tool
extends PanelContainer

@export var action_container: VBoxContainer
@export var filter_line_edit: LineEdit

var _capture_action: String = ""
var _capture_index: int = -1
var _capture_label: Label
var _current_filter: String = ""

const CONFIG_PATH := "user://vectopen_inputmap.cfg"

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
	_current_filter = filter
	for c in action_container.get_children():
		c.queue_free()
	if _capture_label:
		_capture_label = null

	var actions := _get_relevant_actions()
	actions.sort()

	for action in actions:
		if filter != "" and not action.contains(filter.to_lower()):
			continue

		var display := _action_display_name(action)
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_constant_override("separation", 8)
		action_container.add_child(row)

		var label := Label.new()
		label.text = display
		label.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		label.mouse_filter = MOUSE_FILTER_STOP
		label.theme_type_variation = "BindRowLabel"
		row.add_child(label)

		var binds := HBoxContainer.new()
		binds.add_theme_constant_override("separation", 4)
		var events: Array = []
		if InputMap.has_action(action):
			events = InputMap.action_get_events(action)
		for i in events.size():
			binds.add_child(_make_bind_chip(action, i, events[i] as InputEvent))
		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.custom_minimum_size = Vector2(22, 24)
		add_btn.tooltip_text = tr("Add binding")
		add_btn.theme_type_variation = "BindChip"
		add_btn.pressed.connect(_start_capture.bind(action, -1))
		binds.add_child(add_btn)
		row.add_child(binds)

		var reset_btn := Button.new()
		reset_btn.text = tr("Reset")
		reset_btn.theme_type_variation = "ResetLink"
		reset_btn.pressed.connect(_reset_action.bind(action))
		row.add_child(reset_btn)

func _make_bind_chip(action: String, index: int, event: InputEvent) -> HBoxContainer:
	var vi := get_node_or_null("/root/VectopenInput")
	var text := "..."
	if vi:
		text = vi.event_text(event)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var chip := Button.new()
	chip.text = text
	chip.custom_minimum_size = Vector2(0, 24)
	chip.theme_type_variation = "BindChip"
	chip.pressed.connect(_start_capture.bind(action, index))
	box.add_child(chip)
	var x_btn := Button.new()
	x_btn.text = "×"
	x_btn.custom_minimum_size = Vector2(18, 24)
	x_btn.tooltip_text = tr("Remove binding")
	x_btn.theme_type_variation = "BindChip"
	x_btn.pressed.connect(_remove_bind.bind(action, index))
	box.add_child(x_btn)
	return box

# ============================================================================
#                        CAPTURA DE INPUT (escuchando)
# ============================================================================

func _start_capture(action: String, index: int) -> void:
	if not _capture_action.is_empty():
		_cancel_capture()
	_capture_action = action
	_capture_index = index
	if not _capture_label:
		_capture_label = Label.new()
		_capture_label.theme_type_variation = "CaptureHint"
		_capture_label.custom_minimum_size = Vector2(0, 22)
		action_container.add_child(_capture_label)
		action_container.move_child(_capture_label, 0)
	_capture_label.text = tr("Listening for input... (Esc cancela)")
	_capture_label.visible = true

func _cancel_capture() -> void:
	_capture_action = ""
	_capture_index = -1
	if _capture_label:
		_capture_label.visible = false

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _capture_action.is_empty():
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_cancel_capture()
				_build_action_list(_current_filter)
				get_viewport().set_input_as_handled()
				return
			_apply_bind(_capture_action, _capture_index, _get_vi().event_to_dict(event))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_apply_bind(_capture_action, _capture_index, _get_vi().event_to_dict(event))
		get_viewport().set_input_as_handled()

func _get_vi() -> Node:
	return get_node_or_null("/root/VectopenInput")

func _apply_bind(action: String, index: int, bind_dict: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	var new_event: InputEvent = _get_vi().dict_to_event(bind_dict)
	if index >= 0 and index < events.size():
		events[index] = new_event
	else:
		events.append(new_event)
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)
	_save_rebinding(action, events)
	_cancel_capture()
	_build_action_list(_current_filter)

func _remove_bind(action: String, index: int) -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	if index >= 0 and index < events.size():
		events.remove_at(index)
		InputMap.action_erase_events(action)
		for e in events:
			InputMap.action_add_event(action, e)
		_save_rebinding(action, events)
		_build_action_list(_current_filter)

func _reset_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var vi := _get_vi()
	InputMap.action_erase_events(action)
	for entry in vi.get_default_binds(action):
		InputMap.action_add_event(action, vi.dict_to_event(entry))
	_save_rebinding(action, InputMap.action_get_events(action))
	_build_action_list(_current_filter)

func _save_rebinding(action: String, events: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	var dicts: Array = []
	for e in events:
		dicts.append(_get_vi().event_to_dict(e))
	cfg.set_value("rebinds", action, dicts)
	cfg.save(CONFIG_PATH)

func _on_filter_changed(new_text: String) -> void:
	_build_action_list(new_text)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_build_action_list(_current_filter)
