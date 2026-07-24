extends Node

signal theme_changed(mode: String)
signal color_slot_changed(slot_name: String, color: Color)

const CONFIG_PATH := "user://vectopen_theme.cfg"
const SETTINGS_KEY := "application/vectopen/theme_mode"

enum Slot {
	PANEL_BG,
	PANEL_SURFACE,
	PANEL_TEXT,
	ACCENT,
	BUTTON_BG,
	BUTTON_HOVER,
	BUTTON_PRESSED,
	BUTTON_TEXT,
	TOOLBAR_BG,
	RULER_BG,
	CANVAS_BG,
	ARBOARD_BG,
	INPUT_BG,
	INPUT_BORDER,
	SCROLLBAR_BG,
	SCROLLBAR_GRAB,
}

const SLOT_NAMES: Dictionary = {
	Slot.PANEL_BG: "panel_bg",
	Slot.PANEL_SURFACE: "panel_surface",
	Slot.PANEL_TEXT: "panel_text",
	Slot.ACCENT: "accent",
	Slot.BUTTON_BG: "button_bg",
	Slot.BUTTON_HOVER: "button_hover",
	Slot.BUTTON_PRESSED: "button_pressed",
	Slot.BUTTON_TEXT: "button_text",
	Slot.TOOLBAR_BG: "toolbar_bg",
	Slot.RULER_BG: "ruler_bg",
	Slot.CANVAS_BG: "canvas_bg",
	Slot.ARBOARD_BG: "artboard_bg",
	Slot.INPUT_BG: "input_bg",
	Slot.INPUT_BORDER: "input_border",
	Slot.SCROLLBAR_BG: "scrollbar_bg",
	Slot.SCROLLBAR_GRAB: "scrollbar_grab",
}

var _dark_palette: Dictionary = {
	Slot.PANEL_BG: Color(0.118, 0.118, 0.18, 1),
	Slot.PANEL_SURFACE: Color(0.192, 0.192, 0.267, 1),
	Slot.PANEL_TEXT: Color(0.804, 0.839, 0.957, 1),
	Slot.ACCENT: Color(0.271, 0.278, 0.361, 1),
	Slot.BUTTON_BG: Color(0.192, 0.192, 0.267, 1),
	Slot.BUTTON_HOVER: Color(0.271, 0.278, 0.361, 1),
	Slot.BUTTON_PRESSED: Color(0.118, 0.118, 0.18, 1),
	Slot.BUTTON_TEXT: Color(0.804, 0.839, 0.957, 1),
	Slot.TOOLBAR_BG: Color(0.137, 0.137, 0.2, 1),
	Slot.RULER_BG: Color(0.157, 0.157, 0.22, 1),
	Slot.CANVAS_BG: Color(0.3, 0.3, 0.3, 1),
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.192, 0.192, 0.267, 1),
	Slot.INPUT_BORDER: Color(0.271, 0.278, 0.361, 1),
	Slot.SCROLLBAR_BG: Color(0.15, 0.15, 0.2, 1),
	Slot.SCROLLBAR_GRAB: Color(0.3, 0.3, 0.4, 1),
}

var _light_palette: Dictionary = {
	Slot.PANEL_BG: Color(0.949, 0.953, 0.961, 1),
	Slot.PANEL_SURFACE: Color(1, 1, 1, 1),
	Slot.PANEL_TEXT: Color(0.2, 0.2, 0.27, 1),
	Slot.ACCENT: Color(0.537, 0.706, 0.98, 1),
	Slot.BUTTON_BG: Color(1, 1, 1, 1),
	Slot.BUTTON_HOVER: Color(0.95, 0.95, 0.98, 1),
	Slot.BUTTON_PRESSED: Color(0.9, 0.9, 0.95, 1),
	Slot.BUTTON_TEXT: Color(0.2, 0.2, 0.27, 1),
	Slot.TOOLBAR_BG: Color(0.9, 0.905, 0.915, 1),
	Slot.RULER_BG: Color(0.85, 0.855, 0.865, 1),
	Slot.CANVAS_BG: Color(0.3, 0.3, 0.3, 1),
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BORDER: Color(0.8, 0.8, 0.85, 1),
	Slot.SCROLLBAR_BG: Color(0.85, 0.85, 0.9, 1),
	Slot.SCROLLBAR_GRAB: Color(0.6, 0.6, 0.7, 1),
}

var current_mode: String = "dark"
var _overrides: Dictionary = {}

func _ready() -> void:
	var saved = ProjectSettings.get_setting(SETTINGS_KEY, "dark")
	_load_overrides()
	_apply(saved)

func set_mode(mode: String) -> void:
	if mode == current_mode:
		return
	_apply(mode)
	ProjectSettings.set_setting(SETTINGS_KEY, current_mode)
	ProjectSettings.save()

func toggle() -> void:
	set_mode("light" if current_mode == "dark" else "dark")

func is_dark() -> bool:
	return current_mode == "dark"

func get_color(slot: int) -> Color:
	if slot in _overrides:
		return _overrides[slot]
	var palette = _dark_palette if current_mode == "dark" else _light_palette
	return palette.get(slot, Color.MAGENTA)

func get_color_name(slot: int) -> String:
	return SLOT_NAMES.get(slot, "unknown")

func set_custom_color(slot: int, color: Color) -> void:
	_overrides[slot] = color
	_save_overrides()
	_reapply_current()
	color_slot_changed.emit(SLOT_NAMES.get(slot, ""), color)

func reset_custom_color(slot: int) -> void:
	_overrides.erase(slot)
	_save_overrides()
	_reapply_current()
	var default_color = _get_default(slot)
	color_slot_changed.emit(SLOT_NAMES.get(slot, ""), default_color)

func reset_all_custom_colors() -> void:
	_overrides.clear()
	_save_overrides()
	_reapply_current()

func has_custom_color(slot: int) -> bool:
	return slot in _overrides

func get_all_slots() -> Array:
	return SLOT_NAMES.keys()

func get_slot_name(slot: int) -> String:
	return SLOT_NAMES.get(slot, "")

func _get_default(slot: int) -> Color:
	var palette = _dark_palette if current_mode == "dark" else _light_palette
	return palette.get(slot, Color.MAGENTA)

func _apply(mode: String) -> void:
	current_mode = mode
	_reapply_current()

func _reapply_current() -> void:
	_apply_theme_resource()
	theme_changed.emit(current_mode)
	if has_node("/root/GlobalEvents"):
		GlobalEvents.theme_changed.emit(current_mode)

func _apply_theme_resource() -> void:
	var theme = _build_theme()
	if not theme:
		return
	get_tree().root.theme = theme

func _build_theme() -> Theme:
	var theme = Theme.new()
	theme.resource_name = "Vectopen %s" % current_mode.capitalize()

	var panel_bg = _make_stylebox(get_color(Slot.PANEL_SURFACE), 4)
	var btn_bg = _make_stylebox(get_color(Slot.BUTTON_BG), 6)
	var btn_hover = _make_stylebox(get_color(Slot.BUTTON_HOVER), 6)
	var btn_pressed = _make_stylebox(get_color(Slot.BUTTON_PRESSED), 6)
	var input_bg = _make_stylebox(get_color(Slot.INPUT_BG), 4)
	input_bg.border_width_left = 1
	input_bg.border_width_top = 1
	input_bg.border_width_right = 1
	input_bg.border_width_bottom = 1
	input_bg.border_color = get_color(Slot.INPUT_BORDER)

	var text_color = get_color(Slot.PANEL_TEXT)
	var btn_text = get_color(Slot.BUTTON_TEXT)

	theme.set_stylebox("panel", "Panel", panel_bg)
	theme.set_stylebox("panel", "PanelContainer", panel_bg)
	theme.set_stylebox("normal", "Button", btn_bg)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_color("font_color", "Button", btn_text)
	theme.set_color("font_hover_color", "Button", btn_text)
	theme.set_color("font_pressed_color", "Button", btn_text)
	theme.set_color("font_color", "Label", text_color)
	theme.set_color("font_color", "Window", text_color)
	theme.set_stylebox("normal", "LineEdit", input_bg)
	theme.set_stylebox("focus", "LineEdit", input_bg)
	theme.set_color("font_color", "LineEdit", text_color)

	return theme

func _make_stylebox(color: Color, radius: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	if radius > 0:
		sb.set_corner_radius_all(int(radius))
	return sb

func _save_overrides() -> void:
	var cfg = ConfigFile.new()
	for slot in _overrides:
		cfg.set_value("colors", str(slot), _overrides[slot])
	cfg.save(CONFIG_PATH)

func _load_overrides() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section("colors"):
		return
	for slot_str in cfg.get_section_keys("colors"):
		var slot = int(slot_str)
		_overrides[slot] = cfg.get_value("colors", slot_str)
