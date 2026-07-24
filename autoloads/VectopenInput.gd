extends Node

const CONFIG_PATH := "user://vectopen_inputmap.cfg"

const DEFAULTS: Dictionary = {
	"tool_move": [{"key": KEY_V}],
	"tool_brush": [{"key": KEY_B}],
	"tool_rectangle": [{"key": KEY_M}],
	"tool_pen": [{"key": KEY_P}],
	"tool_artboard": [{"key": KEY_A}],
	"canvas_reset_zoom": [{"key": KEY_5}],
	"canvas_zoom_in": [{"key": KEY_EQUAL, "ctrl": true}],
	"canvas_zoom_out": [{"key": KEY_MINUS, "ctrl": true}],
	"delete": [{"key": KEY_DELETE}, {"key": KEY_BACKSPACE}],
	"save": [{"key": KEY_S, "ctrl": true}],
	"undo": [{"key": KEY_Z, "ctrl": true}],
	"redo": [{"key": KEY_Z, "shift": true, "ctrl": true}],
	"copy": [{"key": KEY_C, "ctrl": true}],
	"paste": [{"key": KEY_V, "ctrl": true}],
	"cut": [{"key": KEY_X, "ctrl": true}],
	"select_all": [{"key": KEY_A, "ctrl": true}],
	"duplicate": [{"key": KEY_D, "ctrl": true}],
}

func _ready() -> void:
	_register_defaults()

func _register_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)

	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var saved = cfg.get_value("rebinds", action, [])
			if saved is Array and not saved.is_empty():
				for entry in saved:
					_add_event_from_dict(action, entry)
			else:
				for entry in DEFAULTS[action]:
					_add_event_from_dict(action, entry)

func _add_event_from_dict(action: String, entry: Dictionary) -> void:
	var event := InputEventKey.new()
	if entry.has("key"):
		event.keycode = entry["key"]
	if entry.has("ctrl"):
		event.ctrl_pressed = entry["ctrl"]
	if entry.has("shift"):
		event.shift_pressed = entry["shift"]
	if entry.has("alt"):
		event.alt_pressed = entry["alt"]
	if entry.has("meta"):
		event.meta_pressed = entry["meta"]
	InputMap.action_add_event(action, event)

func get_action_names() -> Array:
	var actions: Array = []
	for action in DEFAULTS:
		actions.append(action)
	actions.sort()
	return actions

func get_action_display(action: String) -> String:
	var parts := action.split("_")
	var result := ""
	for p in parts:
		if result.length() > 0:
			result += " "
		result += p.capitalize()
	return result

func get_action_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "..."
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "..."
	var parts: Array[String] = []
	for e in events:
		if e is InputEventKey:
			var key_name := OS.get_keycode_string(e.keycode)
			var mods := ""
			if e.shift_pressed: mods += "Shift+"
			if e.alt_pressed: mods += "Alt+"
			if e.ctrl_pressed: mods += "Ctrl+"
			if e.meta_pressed: mods += "Cmd+"
			parts.append(mods + key_name)
	return ", ".join(parts)

func is_action_triggered(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	return InputMap.event_is_action(event, action)
