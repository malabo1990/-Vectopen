extends Node

const CONFIG_PATH := "user://vectopen_inputmap.cfg"

## Atajos por defecto. SOLO acciones que la app ejecuta de verdad: el panel de
## teclado las lista, y cambiar una aquí cambia lo que hace la tecla. (Antes se
## listaban 64 acciones y solo 13 estaban conectadas; las teclas de herramienta
## mostraban O/G cuando las reales eran E/D.)
const DEFAULTS: Dictionary = {
	# --- Herramientas (una letra, sin modificadores; ver canvas.gd) ---
	"tool_select": [{"key": KEY_V}],
	"tool_rectangle": [{"key": KEY_R}],
	"tool_ellipse": [{"key": KEY_E}],
	"tool_star": [{"key": KEY_S}],
	"tool_bezier": [{"key": KEY_D}],
	"tool_brush": [{"key": KEY_B}],
	"tool_text": [{"key": KEY_T}],
	"tool_paragraph": [{"key": KEY_P}],
	"tool_artboard": [{"key": KEY_A}],
	"tool_hand": [{"key": KEY_W}],
	# --- Canvas / Vista ---
	"canvas_zoom_in": [{"key": KEY_EQUAL, "ctrl": true}],
	"canvas_zoom_out": [{"key": KEY_MINUS, "ctrl": true}],
	"canvas_reset_zoom": [{"key": KEY_5}],
	# --- Archivo ---
	"save": [{"key": KEY_S, "ctrl": true}],
	"new_project": [{"key": KEY_N, "ctrl": true}],
	# --- Edición ---
	"undo": [{"key": KEY_Z, "ctrl": true}],
	"redo": [{"key": KEY_Z, "shift": true, "ctrl": true}],
	"copy": [{"key": KEY_C, "ctrl": true}],
	"paste": [{"key": KEY_V, "ctrl": true}],
	"cut": [{"key": KEY_X, "ctrl": true}],
	"select_all": [{"key": KEY_A, "ctrl": true}],
	"duplicate": [{"key": KEY_D, "ctrl": true}],
	"delete": [{"key": KEY_DELETE}, {"key": KEY_BACKSPACE}, {"key": KEY_X}],
	# --- Objeto ---
	"group": [{"key": KEY_G, "ctrl": true}],
	"ungroup": [{"key": KEY_G, "shift": true, "ctrl": true}],
	"text_to_curves": [{"key": KEY_O, "shift": true, "ctrl": true}],
}

## Acción de herramienta → id de herramienta del canvas.
const TOOL_ACTIONS := {
	"tool_select": "select", "tool_rectangle": "rectangle", "tool_ellipse": "ellipse",
	"tool_star": "star", "tool_bezier": "bezier", "tool_brush": "brush", "tool_text": "text",
	"tool_paragraph": "paragraph", "tool_artboard": "artboard", "tool_hand": "hand",
}

## Teclas de BORRAR en TODOS los contextos (lienzo, nodos, capas, páginas,
## puntos de degradado, guías): X, Supr / Delete (la misma tecla; «Supr» en
## los teclados españoles) y Retroceso (UX-10).
const DELETE_KEYS := [KEY_X, KEY_DELETE, KEY_BACKSPACE]

## ¿Es `event` una pulsación de borrar? Sin Ctrl / Alt / Cmd (Ctrl+X es
## cortar) y nunca mientras se escribe en un campo (ahí borra texto).
func is_delete_event(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed:
		return false
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	var kc: int = k.keycode if k.keycode != 0 else k.physical_keycode
	return kc in DELETE_KEYS and not is_typing()

## Herramienta para esta tecla (sin modificadores), o "" si no es de herramienta.
## Mientras se escribe en un campo de texto NUNCA es atajo (UX-02).
func tool_for_event(event: InputEvent) -> String:
	if is_typing():
		return ""
	for action in TOOL_ACTIONS:
		if is_action_exact(event, action):
			return TOOL_ACTIONS[action]
	return ""

const PenScrub = preload("res://script_gdscript/ui/pen_scrub.gd")

## ¿Hay un campo de texto con el teclado? (LineEdit, TextEdit, SpinBox o un
## editor propio que diga is_editing()). Guarda única para los atajos de una
## letra: si es así, la tecla es texto, no herramienta.
func is_typing() -> bool:
	var vp := get_viewport()
	var fo: Control = vp.gui_get_focus_owner() if vp else null
	if fo == null or not fo.is_visible_in_tree():
		return false
	if fo is LineEdit:
		return (fo as LineEdit).editable
	if fo is TextEdit:
		return (fo as TextEdit).editable
	if fo is SpinBox:
		return true
	return fo.has_method("is_editing") and bool(fo.call("is_editing"))

## Escape en un campo de texto: el campo lo recibe primero (cancela o
## restaura su valor) y después se suelta el foco para que el teclado vuelva
## al lienzo. Los editores de código (Script/Shader) usan Escape para cerrar
## el autocompletado: no se tocan.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo == null or fo is CodeEdit:
		return
	if fo is LineEdit or fo is TextEdit or fo is SpinBox:
		_release_later.call_deferred(fo)

func _release_later(fo: Control) -> void:
	if is_instance_valid(fo) and fo.has_focus():
		fo.release_focus()

func _ready() -> void:
	_register_defaults()
	# Todos los SpinBox: arrastre del número apto para lápiz de tableta.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is SpinBox:
			PenScrub.attach(n))

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

## Como is_action_triggered pero con los modificadores EXACTOS (Ctrl+G no es
## Ctrl+Shift+G). En macOS, Cmd cuenta como Ctrl.
func is_action_exact(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action) or not (event is InputEventKey):
		return false
	var ev := event as InputEventKey
	if ev.meta_pressed and not ev.ctrl_pressed:
		ev = ev.duplicate() as InputEventKey
		ev.meta_pressed = false
		ev.ctrl_pressed = true
	return InputMap.event_is_action(ev, action, true)
