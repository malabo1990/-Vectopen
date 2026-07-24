@tool
extends Button

var _tm: Node = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_text()
		return
	pressed.connect(_on_toggle)
	_tm = get_node_or_null("/root/ThemeManager")
	if _tm and _tm.has_signal("theme_changed"):
		_tm.theme_changed.connect(_update_text)

func _on_toggle() -> void:
	if not _tm:
		_tm = get_node_or_null("/root/ThemeManager")
	if _tm and _tm.has_method("toggle"):
		_tm.toggle()
	else:
		push_error("ThemeManager not available")

func _update_text() -> void:
	if not _tm:
		return
	var is_dark = _tm.get("current_mode") == "dark" if _tm else true
	text = "D" if is_dark else "L"
