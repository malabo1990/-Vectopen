extends GdUnitTestSuite

const PanelClass = preload("res://script_gdscript/ui/InputConfigPanel.gd")

func _panel() -> Node:
	var panel: Node = auto_free(PanelClass.new())
	var ac := VBoxContainer.new()
	var filter := LineEdit.new()
	panel.action_container = ac
	panel.filter_line_edit = filter
	add_child(panel)
	panel.add_child(ac)
	panel.add_child(filter)
	return panel

func _ensure_test_action() -> String:
	var action := "test_rebind_action"
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	return action

func test_capture_mouse_button() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	panel._start_capture(action, -1)

	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	panel._input(ev)

	assert_that(panel._capture_action).is_equal("")
	var events := InputMap.action_get_events(action)
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventMouseButton).is_true()
	assert_int((events[0] as InputEventMouseButton).button_index).is_equal(MOUSE_BUTTON_RIGHT)

func test_capture_key_with_modifier() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	panel._start_capture(action, -1)

	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.ctrl_pressed = true
	ev.pressed = true
	panel._input(ev)

	var events := InputMap.action_get_events(action)
	assert_int(events.size()).is_equal(1)
	var key_event := events[0] as InputEventKey
	assert_int(key_event.keycode).is_equal(KEY_T)
	assert_that(key_event.ctrl_pressed).is_true()

func test_capture_reemplaza_binding_existente() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, InputEventKey.new())
	(InputMap.action_get_events(action)[0] as InputEventKey).keycode = KEY_A
	panel._start_capture(action, 0)

	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = true
	panel._input(ev)

	var events := InputMap.action_get_events(action)
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventMouseButton).is_true()

func test_escape_cancela_captura() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	panel._start_capture(action, -1)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	panel._input(esc)

	assert_that(panel._capture_action).is_equal("")
	assert_that(InputMap.action_get_events(action).is_empty()).is_true()

func test_remove_binding() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, InputEventKey.new())
	(InputMap.action_get_events(action)[0] as InputEventKey).keycode = KEY_B
	InputMap.action_add_event(action, InputEventMouseButton.new())
	(InputMap.action_get_events(action)[1] as InputEventMouseButton).button_index = MOUSE_BUTTON_LEFT

	panel._remove_bind(action, 0)

	var events := InputMap.action_get_events(action)
	assert_int(events.size()).is_equal(1)
	assert_that(events[0] is InputEventMouseButton).is_true()

func test_save_guarda_formato_cargable() -> void:
	var panel := _panel()
	var action := _ensure_test_action()
	InputMap.action_erase_events(action)
	panel._start_capture(action, -1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = true
	panel._input(ev)

	var cfg := ConfigFile.new()
	cfg.load("user://vectopen_inputmap.cfg")
	var saved = cfg.get_value("rebinds", action, [])
	assert_int(saved.size()).is_equal(1)
	assert_that(saved[0]["button"]).is_equal(MOUSE_BUTTON_MIDDLE)
	cfg.set_value("rebinds", action, [])
	cfg.save("user://vectopen_inputmap.cfg")
	InputMap.action_erase_events(action)
