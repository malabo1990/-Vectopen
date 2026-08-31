extends Node

const CONFIG_PATH := "user://vectopen_inputmap.cfg"

const DEFAULTS: Dictionary = {
	# --- Herramientas ---
	"tool_select": [{"key": KEY_Q}],
	"tool_move": [{"key": KEY_V}],
	"tool_brush": [{"key": KEY_B}],
	"tool_rectangle": [{"key": KEY_M}],
	"tool_ellipse": [{"key": KEY_E}],
	"tool_pen": [{"key": KEY_P}],
	"tool_bezier": [{"key": KEY_G}],
	"tool_text": [{"key": KEY_T}],
	"tool_hand": [{"key": KEY_H}],
	"tool_artboard": [{"key": KEY_A}],
	# --- Canvas / Vista ---
	"canvas_zoom_in": [{"key": KEY_EQUAL, "ctrl": true}],
	"canvas_zoom_out": [{"key": KEY_MINUS, "ctrl": true}],
	"canvas_reset_zoom": [{"key": KEY_5}],
	"canvas_zoom_fit": [{"key": KEY_F}],
	"canvas_zoom_100": [{"key": KEY_1}],
	"canvas_pan": [{"button": MOUSE_BUTTON_MIDDLE}],
	"canvas_pan_key": [{"key": KEY_SPACE}],
	"view_toggle_grid": [{"key": KEY_G, "shift": true}],
	"view_toggle_rulers": [{"key": KEY_R, "ctrl": true}],
	# --- Archivo ---
	"save": [{"key": KEY_S, "ctrl": true}],
	"save_as": [{"key": KEY_S, "shift": true, "ctrl": true}],
	"open": [{"key": KEY_O, "ctrl": true}],
	"new_project": [{"key": KEY_N, "ctrl": true}],
	# --- Edición ---
	"undo": [{"key": KEY_Z, "ctrl": true}],
	"redo": [{"key": KEY_Z, "shift": true, "ctrl": true}],
	"copy": [{"key": KEY_C, "ctrl": true}],
	"paste": [{"key": KEY_V, "ctrl": true}],
	"cut": [{"key": KEY_X, "ctrl": true}],
	"select_all": [{"key": KEY_A, "ctrl": true}],
	"duplicate": [{"key": KEY_D, "ctrl": true}],
	"delete": [{"key": KEY_DELETE}, {"key": KEY_BACKSPACE}],
	"deselect": [{"key": KEY_ESCAPE}],
	# --- Objeto ---
	"group": [{"key": KEY_G, "ctrl": true}],
	"ungroup": [{"key": KEY_G, "shift": true, "ctrl": true}],
	"bring_forward": [{"key": KEY_BRACKETRIGHT, "ctrl": true}],
	"send_backward": [{"key": KEY_BRACKETLEFT, "ctrl": true}],
	"bring_to_front": [{"key": KEY_BRACKETRIGHT, "shift": true, "ctrl": true}],
	"send_to_back": [{"key": KEY_BRACKETLEFT, "shift": true, "ctrl": true}],
	"flip_horizontal": [{"key": KEY_H, "shift": true}],
	"flip_vertical": [{"key": KEY_V, "shift": true}],
	"rotate_left": [{"key": KEY_BRACKETLEFT}],
	"rotate_right": [{"key": KEY_BRACKETRIGHT}],
	# --- Alineación ---
	"align_left": [{"key": KEY_L, "shift": true}],
	"align_center_h": [{"key": KEY_C, "shift": true}],
	"align_right": [{"key": KEY_R, "shift": true}],
	"align_top": [{"key": KEY_T, "shift": true}],
	"align_middle_v": [{"key": KEY_M, "shift": true}],
	"align_bottom": [{"key": KEY_B, "shift": true}],
	# --- Capas ---
	"layer_new": [{"key": KEY_N, "shift": true, "ctrl": true}],
	"layer_duplicate": [{"key": KEY_J, "ctrl": true}],
	"layer_delete": [{"key": KEY_DELETE, "shift": true, "ctrl": true}],
	"layer_up": [{"key": KEY_PAGEUP}],
	"layer_down": [{"key": KEY_PAGEDOWN}],
	"layer_top": [{"key": KEY_HOME}],
	"layer_bottom": [{"key": KEY_END}],
	# --- Texto ---
	"text_bold": [{"key": KEY_B, "ctrl": true}],
	"text_italic": [{"key": KEY_I, "ctrl": true}],
	"text_underline": [{"key": KEY_U, "ctrl": true}],
	# --- Ayuda ---
	"help_shortcuts": [{"key": KEY_F1}],
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
	InputMap.action_add_event(action, dict_to_event(entry))

func dict_to_event(entry: Dictionary) -> InputEvent:
	if entry.has("button"):
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = entry["button"]
		return mouse_event
	var key_event := InputEventKey.new()
	if entry.has("key"):
		key_event.keycode = entry["key"]
	if entry.has("ctrl"):
		key_event.ctrl_pressed = entry["ctrl"]
	if entry.has("shift"):
		key_event.shift_pressed = entry["shift"]
	if entry.has("alt"):
		key_event.alt_pressed = entry["alt"]
	if entry.has("meta"):
		key_event.meta_pressed = entry["meta"]
	return key_event

func get_default_binds(action: String) -> Array:
	return DEFAULTS.get(action, [])

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
		parts.append(event_text(e))
	return ", ".join(parts)

func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_name := OS.get_keycode_string(event.keycode)
		var mods := ""
		if event.shift_pressed: mods += "Shift+"
		if event.alt_pressed: mods += "Alt+"
		if event.ctrl_pressed: mods += "Ctrl+"
		if event.meta_pressed: mods += "Cmd+"
		return mods + key_name
	elif event is InputEventMouseButton:
		return _mouse_button_name(event.button_index)
	return "..."

func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {
			"key": event.keycode,
			"ctrl": event.ctrl_pressed,
			"shift": event.shift_pressed,
			"alt": event.alt_pressed,
			"meta": event.meta_pressed,
		}
	elif event is InputEventMouseButton:
		return {"button": event.button_index}
	return {}

func _mouse_button_name(index: int) -> String:
	match index:
		MOUSE_BUTTON_LEFT: return "Mouse Left"
		MOUSE_BUTTON_RIGHT: return "Mouse Right"
		MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
		MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		_: return "Mouse %d" % index

func is_action_triggered(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	return InputMap.event_is_action(event, action)
