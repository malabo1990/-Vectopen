extends Node

## Vectopen Pro ThemeManager
## Genera el Theme de runtime desde los tokens de diseño (docs/design/design-tokens.json).
## Modos: dark (macOS Pro) / light (Studio). Overrides de usuario en user://vectopen_theme.cfg.

signal theme_changed(mode: String)
signal color_slot_changed(slot_name: String, color: Color)

const CONFIG_PATH := "user://vectopen_theme.cfg"
const SETTINGS_KEY := "application/vectopen/theme_mode"

enum Slot {
	PANEL_BG,
	PANEL_SURFACE,
	PANEL_TEXT,
	ACCENT,
	AFFIRMATIVE,
	NEGATIVE,
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
	WIDGET_BG,
	BORDER,
	TEXT_SECONDARY,
	TEXT_DISABLED,
}

const SLOT_NAMES: Dictionary = {
	Slot.PANEL_BG: "panel_bg",
	Slot.PANEL_SURFACE: "panel_surface",
	Slot.PANEL_TEXT: "panel_text",
	Slot.ACCENT: "accent",
	Slot.AFFIRMATIVE: "affirmative",
	Slot.NEGATIVE: "negative",
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
	Slot.WIDGET_BG: "widget_bg",
	Slot.BORDER: "border",
	Slot.TEXT_SECONDARY: "text_secondary",
	Slot.TEXT_DISABLED: "text_disabled",
}

# ============================================================================
#                             TOKENS — MODO OSCURO
# ============================================================================

const DARK_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.102, 0.102, 0.118, 0.88),
	Slot.PANEL_SURFACE: Color(0.094, 0.094, 0.102, 1.0),
	Slot.PANEL_TEXT: Color(0.96, 0.96, 0.968, 1.0),
	Slot.ACCENT: Color(0.039, 0.518, 1.0, 1.0),
	Slot.AFFIRMATIVE: Color(0.188, 0.82, 0.345, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.271, 0.227, 1.0),
	Slot.BUTTON_BG: Color(0.094, 0.094, 0.102, 1.0),
	Slot.BUTTON_HOVER: Color(0.16, 0.16, 0.19, 1.0),
	Slot.BUTTON_PRESSED: Color(0.07, 0.07, 0.078, 1.0),
	Slot.BUTTON_TEXT: Color(0.96, 0.96, 0.968, 1.0),
	Slot.TOOLBAR_BG: Color(0.094, 0.094, 0.11, 1.0),
	Slot.RULER_BG: Color(0.118, 0.118, 0.133, 1.0),
	Slot.CANVAS_BG: Color(0.094, 0.094, 0.102, 1.0),
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(1, 1, 1, 0.08),
	Slot.INPUT_BORDER: Color(1, 1, 1, 0.12),
	Slot.SCROLLBAR_BG: Color(1, 1, 1, 0.08),
	Slot.SCROLLBAR_GRAB: Color(0.28, 0.28, 0.34, 1),
	Slot.WIDGET_BG: Color(1, 1, 1, 0.05),
	Slot.BORDER: Color(1, 1, 1, 0.12),
	Slot.TEXT_SECONDARY: Color(1, 1, 1, 0.55),
	Slot.TEXT_DISABLED: Color(1, 1, 1, 0.25),
}

# ============================================================================
#                             TOKENS — MODO CLARO
# ============================================================================

const LIGHT_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.973, 0.973, 0.98, 0.92),
	Slot.PANEL_SURFACE: Color(0.973, 0.973, 0.98, 1.0),
	Slot.PANEL_TEXT: Color(0.11, 0.11, 0.118, 1.0),
	Slot.ACCENT: Color(0.0, 0.478, 1.0, 1.0),
	Slot.AFFIRMATIVE: Color(0.204, 0.78, 0.349, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.231, 0.188, 1.0),
	Slot.BUTTON_BG: Color(1, 1, 1, 1),
	Slot.BUTTON_HOVER: Color(0.941, 0.941, 0.957, 1.0),
	Slot.BUTTON_PRESSED: Color(0.898, 0.898, 0.918, 1.0),
	Slot.BUTTON_TEXT: Color(0.11, 0.11, 0.118, 1.0),
	Slot.TOOLBAR_BG: Color(0.941, 0.941, 0.953, 1.0),
	Slot.RULER_BG: Color(0.894, 0.894, 0.914, 1.0),
	Slot.CANVAS_BG: Color(0.937, 0.937, 0.957, 1.0),
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.898, 0.898, 0.918, 1.0),
	Slot.INPUT_BORDER: Color(0.82, 0.82, 0.84, 1.0),
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.05),
	Slot.SCROLLBAR_GRAB: Color(0, 0, 0, 0.3),
	Slot.WIDGET_BG: Color(1, 1, 1, 1),
	Slot.BORDER: Color(0.82, 0.82, 0.84, 1.0),
	Slot.TEXT_SECONDARY: Color(0.424, 0.424, 0.439, 1.0),
	Slot.TEXT_DISABLED: Color(0.557, 0.557, 0.576, 1.0),
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
	var palette = DARK_PALETTE if current_mode == "dark" else LIGHT_PALETTE
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
	color_slot_changed.emit(SLOT_NAMES.get(slot, ""), _get_default(slot))

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
	var palette = DARK_PALETTE if current_mode == "dark" else LIGHT_PALETTE
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
	var theme := _build_theme()
	if not theme:
		return
	get_tree().root.theme = theme

# ============================================================================
#                        CONSTRUCCIÓN DEL THEME
# ============================================================================

func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.resource_name = "Vectopen Pro %s" % current_mode.capitalize()
	theme.default_font_size = 14
	# Fuente Inter (OFL, con contornos TrueType) — la usa todo el editor y los
	# WorldTextLabel del lienzo: así el text-to-shape (build_outline_path)
	# tiene fdata disponible y todos los textos son vectoriales.
	theme.default_font = preload("res://assets/fonts/Inter-Regular.ttf")

	var panel_bg := get_color(Slot.PANEL_BG)
	var border := get_color(Slot.BORDER)
	var accent := get_color(Slot.ACCENT)
	var text_primary := get_color(Slot.PANEL_TEXT)
	var text_secondary := get_color(Slot.TEXT_SECONDARY)
	var text_disabled := get_color(Slot.TEXT_DISABLED)
	var affirmative := get_color(Slot.AFFIRMATIVE)
	var negative := get_color(Slot.NEGATIVE)

	# --- Paneles (12px, borde, sombra) ---
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = panel_bg
	panel_sb.border_color = border
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(12)
	theme.set_stylebox("panel", "Panel", panel_sb)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)
	theme.set_stylebox("panel", "PopupMenu", panel_sb)

	# --- Botón estándar (6px, widget bg) ---
	theme.set_stylebox("normal", "Button", _flat(get_color(Slot.BUTTON_BG), 6, border))
	theme.set_stylebox("hover", "Button", _flat(get_color(Slot.BUTTON_HOVER), 6, border))
	theme.set_stylebox("pressed", "Button", _flat(get_color(Slot.BUTTON_PRESSED), 6, border))
	theme.set_stylebox("focus", "Button", _flat(Color(0, 0, 0, 0), 6, accent))
	theme.set_stylebox("disabled", "Button", _flat(get_color(Slot.BUTTON_BG), 6, border))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(c, "Button", text_primary)
	theme.set_color("font_disabled_color", "Button", text_disabled)
	theme.set_font_size("font_size", "Button", 13)

	# --- Botón afirmativo (verde semántico) ---
	var aff_sb := _flat(affirmative, 6, affirmative)
	theme.set_stylebox("normal", "AffirmativeButton", aff_sb)
	theme.set_stylebox("hover", "AffirmativeButton", _flat(_hover(affirmative), 6, affirmative))
	theme.set_stylebox("pressed", "AffirmativeButton", _flat(_pressed(affirmative), 6, affirmative))
	theme.set_stylebox("focus", "AffirmativeButton", _flat(Color(0, 0, 0, 0), 6, affirmative))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(c, "AffirmativeButton", Color.WHITE)
	theme.set_font_size("font_size", "AffirmativeButton", 13)

	# --- Botón negativo (rojo semántico) ---
	theme.set_stylebox("normal", "NegativeButton", _flat(negative, 6, negative))
	theme.set_stylebox("hover", "NegativeButton", _flat(_hover(negative), 6, negative))
	theme.set_stylebox("pressed", "NegativeButton", _flat(_pressed(negative), 6, negative))
	theme.set_stylebox("focus", "NegativeButton", _flat(Color(0, 0, 0, 0), 6, negative))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(c, "NegativeButton", Color.WHITE)
	theme.set_font_size("font_size", "NegativeButton", 13)

	# --- Inputs (6px, foco con anillo accent) ---
	var input_sb := _flat(get_color(Slot.INPUT_BG), 6, get_color(Slot.INPUT_BORDER))
	var input_focus := _flat(get_color(Slot.INPUT_BG), 6, accent)
	input_focus.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	input_focus.shadow_size = 4
	theme.set_stylebox("normal", "LineEdit", input_sb)
	theme.set_stylebox("focus", "LineEdit", input_focus)
	theme.set_color("font_color", "LineEdit", text_primary)
	theme.set_color("caret_color", "LineEdit", text_primary)
	theme.set_color("placeholder_font_color", "LineEdit", text_secondary)
	theme.set_font_size("font_size", "LineEdit", 13)

	# --- Etiquetas / ventanas ---
	theme.set_color("font_color", "Label", text_primary)
	theme.set_color("font_color", "Window", text_primary)

	# --- Popups ---
	theme.set_color("font_color", "PopupMenu", text_primary)
	theme.set_color("font_hover_color", "PopupMenu", text_primary)
	theme.set_stylebox("hover", "PopupMenu", _flat(accent, 6, Color(0, 0, 0, 0)))

	# --- Árbol ---
	theme.set_color("font_color", "Tree", text_primary)
	theme.set_color("font_selected_color", "Tree", text_primary)
	theme.set_color("selected_color", "Tree", Color(accent.r, accent.g, accent.b, 0.25))
	theme.set_color("hover_color", "Tree", Color(1, 1, 1, 0.06) if is_dark() else Color(0, 0, 0, 0.04))
	theme.set_stylebox("panel", "Tree", _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	theme.set_font_size("font_size", "Tree", 13)

	# --- Scrollbars ---
	theme.set_constant("scrollbar_h_separation", "ScrollContainer", 8)
	theme.set_constant("scrollbar_v_separation", "ScrollContainer", 8)
	var grab_sb := StyleBoxFlat.new()
	grab_sb.bg_color = get_color(Slot.SCROLLBAR_GRAB)
	grab_sb.set_corner_radius_all(8)
	var grab_hover := grab_sb.duplicate() as StyleBoxFlat
	grab_hover.bg_color = get_color(Slot.SCROLLBAR_GRAB).lightened(0.15)
	theme.set_stylebox("scroll", "ScrollBar", _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("scroll_focus", "ScrollBar", _flat(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	theme.set_stylebox("grab", "ScrollBar", grab_sb)
	theme.set_stylebox("grab_highlight", "ScrollBar", grab_hover)

	# --- CheckButton / CheckBox: toggle estilo macOS ---
	var toggle_on := _load_sized("res://assets/icons/toggle_on.png", 34, 20)
	var toggle_off := _load_sized("res://assets/icons/toggle_off.png", 34, 20)
	if toggle_on and toggle_off:
		theme.set_icon("checked", "CheckButton", toggle_on)
		theme.set_icon("unchecked", "CheckButton", toggle_off)
		theme.set_icon("checked", "CheckBox", toggle_on)
		theme.set_icon("unchecked", "CheckBox", toggle_off)

	return theme

func _load_sized(path: String, width: int, height: int) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if not img:
		return null
	img.resize(width, height, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

func _flat(color: Color, radius: int, border_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	if radius > 0:
		sb.set_corner_radius_all(radius)
	if border_color.a > 0:
		sb.border_color = border_color
		sb.set_border_width_all(1)
	return sb

func _hover(color: Color) -> Color:
	if is_dark():
		return color.lightened(0.12)
	return color.darkened(0.08)

func _pressed(color: Color) -> Color:
	if is_dark():
		return color.lightened(0.02)
	return color.darkened(0.15)

# ============================================================================
#                           PERSISTENCIA DE OVERRIDES
# ============================================================================

func _save_overrides() -> void:
	var cfg := ConfigFile.new()
	for slot in _overrides:
		cfg.set_value("colors", str(slot), _overrides[slot])
	cfg.save(CONFIG_PATH)

func _load_overrides() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section("colors"):
		return
	for slot_str in cfg.get_section_keys("colors"):
		var slot := int(slot_str)
		_overrides[slot] = cfg.get_value("colors", slot_str)
