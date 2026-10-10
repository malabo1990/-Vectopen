extends Node

## Vectopen Pro ThemeManager
## Genera el Theme de runtime desde los tokens de diseño (docs/design/design-tokens.json).
## Modos: dark (Vectopen Oscuro) / light (Vectopen Claro). Preferencia y overrides
## de color del usuario en user://vectopen_theme.cfg. Por defecto: CLARO.

signal theme_changed(mode: String)
signal color_slot_changed(slot_name: String, color: Color)

const CONFIG_PATH := "user://vectopen_theme.cfg"

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
	SURFACE_RAISED,  # chip/fila resaltada (barra de herramientas, selección suave)
	ACCENT_SOFT,     # tinte de acento a baja opacidad (relleno de selección)
	# Tokens semánticos avanzados de diseño:
	INPUT_HOVER,
	INPUT_FOCUS,
	BORDER_STRONG,
	TEXT_MUTED,
	ICON_PRIMARY,
	ICON_MUTED,
	ACCENT_HOVER,
	BUTTON_SELECTED,
	WARNING,
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
	Slot.SURFACE_RAISED: "surface_raised",
	Slot.ACCENT_SOFT: "accent_soft",
	Slot.INPUT_HOVER: "input_hover",
	Slot.INPUT_FOCUS: "input_focus",
	Slot.BORDER_STRONG: "border_strong",
	Slot.TEXT_MUTED: "text_muted",
	Slot.ICON_PRIMARY: "icon_primary",
	Slot.ICON_MUTED: "icon_muted",
	Slot.ACCENT_HOVER: "accent_hover",
	Slot.BUTTON_SELECTED: "button_selected",
	Slot.WARNING: "warning",
}

# ============================================================================
#                             TOKENS — MODO OSCURO (DARK)
# ============================================================================

const DARK_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.125, 0.125, 0.125, 1.0), # #202020
	Slot.PANEL_SURFACE: Color(0.145, 0.145, 0.145, 1.0), # #252525
	Slot.PANEL_TEXT: Color(0.941, 0.941, 0.941, 1.0), # #F0F0F0
	Slot.ACCENT: Color(0.35, 0.50, 0.68, 1.0), # #5980AD — tono de acento suave y neutro
	Slot.ACCENT_HOVER: Color(0.42, 0.58, 0.78, 1.0), # #6B94C7
	Slot.AFFIRMATIVE: Color(0.188, 0.82, 0.345, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.271, 0.227, 1.0),
	Slot.WARNING: Color(0.941, 0.647, 0.0, 1.0),
	Slot.BUTTON_BG: Color(0.141, 0.141, 0.141, 1.0), # #242424 (casi mismo tono de panel)
	Slot.BUTTON_HOVER: Color(0.180, 0.180, 0.180, 1.0), # #2E2E2E
	Slot.BUTTON_PRESSED: Color(0.220, 0.220, 0.220, 1.0), # #383838
	Slot.BUTTON_TEXT: Color(0.941, 0.941, 0.941, 1.0),
	Slot.BUTTON_SELECTED: Color(0.25, 0.35, 0.48, 1.0), # #40597A — selección sobria, no chillona
	Slot.TOOLBAR_BG: Color(0.094, 0.094, 0.094, 1.0), # #181818
	Slot.RULER_BG: Color(0.078, 0.078, 0.078, 1.0), # #141414
	Slot.CANVAS_BG: Color(0.094, 0.094, 0.094, 1.0), # #181818
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.094, 0.094, 0.094, 1.0), # #181818
	Slot.INPUT_HOVER: Color(0.176, 0.176, 0.176, 1.0), # #2D2D2D
	Slot.INPUT_FOCUS: Color(0.078, 0.078, 0.078, 1.0), # #141414
	Slot.INPUT_BORDER: Color(0.220, 0.220, 0.220, 1.0), # #383838
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.15),
	Slot.SCROLLBAR_GRAB: Color(0.32, 0.32, 0.35, 1.0),
	Slot.WIDGET_BG: Color(0.125, 0.125, 0.125, 1.0),
	Slot.BORDER: Color(0.220, 0.220, 0.220, 1.0), # #383838
	Slot.BORDER_STRONG: Color(0.282, 0.282, 0.282, 1.0), # #484848
	Slot.TEXT_SECONDARY: Color(0.663, 0.663, 0.663, 1.0), # #A9A9A9
	Slot.TEXT_MUTED: Color(0.451, 0.451, 0.451, 1.0), # #737373
	Slot.TEXT_DISABLED: Color(0.314, 0.314, 0.314, 1.0),
	Slot.ICON_PRIMARY: Color(0.831, 0.831, 0.831, 1.0), # #D4D4D4
	Slot.ICON_MUTED: Color(0.451, 0.451, 0.451, 1.0), # #737373
	Slot.SURFACE_RAISED: Color(0.176, 0.176, 0.176, 1.0), # #2D2D2D
	Slot.ACCENT_SOFT: Color(0.35, 0.50, 0.68, 0.20),
}

# ============================================================================
#                             TOKENS — MODO CLARO (WHITE / BLANCO)
# ============================================================================

const LIGHT_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(1.0, 1.0, 1.0, 1.0), # #FFFFFF
	Slot.PANEL_SURFACE: Color(0.969, 0.969, 0.969, 1.0), # #F7F7F7
	Slot.PANEL_TEXT: Color(0.11, 0.11, 0.118, 1.0), # #1C1C1E / #202020
	Slot.ACCENT: Color(0.22, 0.44, 0.68, 1.0), # #3870AD — azul pizarra neutro y suave
	Slot.ACCENT_HOVER: Color(0.18, 0.38, 0.60, 1.0), # #2E6199
	Slot.AFFIRMATIVE: Color(0.204, 0.78, 0.349, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.231, 0.188, 1.0),
	Slot.WARNING: Color(0.961, 0.651, 0.137, 1.0), # #F5A623
	Slot.BUTTON_BG: Color(0.969, 0.969, 0.969, 1.0), # #F7F7F7 (integrado con el panel)
	Slot.BUTTON_HOVER: Color(0.918, 0.918, 0.918, 1.0), # #EAEAEA (+ contraste)
	Slot.BUTTON_PRESSED: Color(0.875, 0.875, 0.875, 1.0), # #DFDFDF (+ contraste)
	Slot.BUTTON_TEXT: Color(0.125, 0.125, 0.125, 1.0),
	Slot.BUTTON_SELECTED: Color(0.82, 0.88, 0.94, 1.0), # #D1E0F0 — fondo seleccionado sutil con contraste
	Slot.TOOLBAR_BG: Color(0.969, 0.969, 0.969, 1.0), # #F7F7F7
	Slot.RULER_BG: Color(0.933, 0.933, 0.933, 1.0), # #EEEEEE
	Slot.CANVAS_BG: Color(0.953, 0.953, 0.953, 1.0), # #F3F3F3
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.925, 0.925, 0.925, 1.0), # #ECECEC
	Slot.INPUT_HOVER: Color(0.894, 0.894, 0.894, 1.0), # #E4E4E4
	Slot.INPUT_FOCUS: Color(1.0, 1.0, 1.0, 1.0), # #FFFFFF
	Slot.INPUT_BORDER: Color(0.835, 0.835, 0.835, 1.0), # #D5D5D5
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.05),
	Slot.SCROLLBAR_GRAB: Color(0, 0, 0, 0.25),
	Slot.WIDGET_BG: Color(1, 1, 1, 1),
	Slot.BORDER: Color(0.835, 0.835, 0.835, 1.0), # #D5D5D5
	Slot.BORDER_STRONG: Color(0.745, 0.745, 0.745, 1.0), # #BEBEBE
	Slot.TEXT_SECONDARY: Color(0.40, 0.40, 0.40, 1.0), # #666666
	Slot.TEXT_MUTED: Color(0.533, 0.533, 0.533, 1.0), # #888888
	Slot.TEXT_DISABLED: Color(0.667, 0.667, 0.667, 1.0),
	Slot.ICON_PRIMARY: Color(0.20, 0.20, 0.20, 1.0), # #333333
	Slot.ICON_MUTED: Color(0.467, 0.467, 0.467, 1.0), # #777777
	Slot.SURFACE_RAISED: Color(0.941, 0.941, 0.941, 1.0), # #F0F0F0
	Slot.ACCENT_SOFT: Color(0.22, 0.44, 0.68, 0.12),
}

# ============================================================================
#                       TOKENS — MODO AZUL GODOT ENGINE
# ============================================================================

const GODOT_BLUE_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.188, 0.212, 0.255, 1.0), # #303641
	Slot.PANEL_SURFACE: Color(0.212, 0.239, 0.282, 1.0), # #363D48
	Slot.PANEL_TEXT: Color(0.906, 0.918, 0.941, 1.0), # #E7EAF0
	Slot.ACCENT: Color(0.439, 0.729, 0.980, 1.0), # #70BAFA
	Slot.ACCENT_HOVER: Color(0.510, 0.773, 1.0, 1.0), # #82C5FF
	Slot.AFFIRMATIVE: Color(0.188, 0.82, 0.345, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.271, 0.227, 1.0),
	Slot.WARNING: Color(0.910, 0.722, 0.224, 1.0), # #E8B839
	Slot.BUTTON_BG: Color(0.173, 0.196, 0.239, 1.0), # #2C323D (casi mismo tono de panel)
	Slot.BUTTON_HOVER: Color(0.227, 0.259, 0.314, 1.0), # #3A4250
	Slot.BUTTON_PRESSED: Color(0.267, 0.306, 0.369, 1.0), # #444E5E
	Slot.BUTTON_TEXT: Color(0.906, 0.918, 0.941, 1.0),
	Slot.BUTTON_SELECTED: Color(0.439, 0.729, 0.980, 1.0),
	Slot.TOOLBAR_BG: Color(0.145, 0.165, 0.200, 1.0), # #252A33
	Slot.RULER_BG: Color(0.125, 0.141, 0.173, 1.0), # #20242C
	Slot.CANVAS_BG: Color(0.145, 0.165, 0.200, 1.0), # #252A33
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.145, 0.165, 0.196, 1.0), # #252A32
	Slot.INPUT_HOVER: Color(0.243, 0.275, 0.325, 1.0), # #3E4653
	Slot.INPUT_FOCUS: Color(0.122, 0.137, 0.169, 1.0), # #1F232B
	Slot.INPUT_BORDER: Color(0.290, 0.325, 0.380, 1.0), # #4A5361
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.15),
	Slot.SCROLLBAR_GRAB: Color(0.35, 0.40, 0.50, 1.0),
	Slot.WIDGET_BG: Color(0.188, 0.212, 0.255, 1.0),
	Slot.BORDER: Color(0.290, 0.325, 0.380, 1.0), # #4A5361
	Slot.BORDER_STRONG: Color(0.365, 0.408, 0.478, 1.0), # #5D687A
	Slot.TEXT_SECONDARY: Color(0.718, 0.745, 0.788, 1.0), # #B7BEC9
	Slot.TEXT_MUTED: Color(0.522, 0.557, 0.608, 1.0), # #858E9B
	Slot.TEXT_DISABLED: Color(0.361, 0.388, 0.439, 1.0),
	Slot.ICON_PRIMARY: Color(0.812, 0.835, 0.878, 1.0), # #CFD5E0
	Slot.ICON_MUTED: Color(0.522, 0.557, 0.608, 1.0), # #858E9B
	Slot.SURFACE_RAISED: Color(0.243, 0.275, 0.325, 1.0), # #3E4653
	Slot.ACCENT_SOFT: Color(0.439, 0.729, 0.980, 0.22),
}

# ============================================================================
#                       TOKENS — MODO GRIS DE BLENDER
# ============================================================================

const BLENDER_GRAY_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.220, 0.220, 0.220, 1.0), # #383838
	Slot.PANEL_SURFACE: Color(0.251, 0.251, 0.251, 1.0), # #404040
	Slot.PANEL_TEXT: Color(0.898, 0.898, 0.898, 1.0), # #E5E5E5
	Slot.ACCENT: Color(0.278, 0.447, 0.702, 1.0), # #4772B3 Blender Blue (active widget/highlight)
	Slot.ACCENT_HOVER: Color(0.337, 0.502, 0.761, 1.0), # #5680C2
	Slot.AFFIRMATIVE: Color(0.25, 0.75, 0.35, 1.0),
	Slot.NEGATIVE: Color(0.90, 0.25, 0.25, 1.0),
	Slot.WARNING: Color(0.898, 0.690, 0.165, 1.0),
	Slot.BUTTON_BG: Color(0.204, 0.204, 0.204, 1.0), # #343434 (casi mismo tono de panel)
	Slot.BUTTON_HOVER: Color(0.239, 0.239, 0.239, 1.0), # #3D3D3D
	Slot.BUTTON_PRESSED: Color(0.275, 0.275, 0.275, 1.0), # #464646
	Slot.BUTTON_TEXT: Color(0.898, 0.898, 0.898, 1.0),
	Slot.BUTTON_SELECTED: Color(0.278, 0.447, 0.702, 1.0),
	Slot.TOOLBAR_BG: Color(0.188, 0.188, 0.188, 1.0), # #303030
	Slot.RULER_BG: Color(0.150, 0.150, 0.150, 1.0),
	Slot.CANVAS_BG: Color(0.188, 0.188, 0.188, 1.0), # #303030
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.169, 0.169, 0.169, 1.0), # #2B2B2B
	Slot.INPUT_HOVER: Color(0.271, 0.271, 0.271, 1.0), # #454545
	Slot.INPUT_FOCUS: Color(0.133, 0.133, 0.133, 1.0), # #222222
	Slot.INPUT_BORDER: Color(0.200, 0.200, 0.200, 1.0), # #333333 sutil como en Blender
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.15),
	Slot.SCROLLBAR_GRAB: Color(0.40, 0.40, 0.40, 1.0),
	Slot.WIDGET_BG: Color(0.220, 0.220, 0.220, 1.0),
	Slot.BORDER: Color(0.200, 0.200, 0.200, 1.0), # #333333 sin marco naranja chillón
	Slot.BORDER_STRONG: Color(0.267, 0.267, 0.267, 1.0), # #444444
	Slot.TEXT_SECONDARY: Color(0.690, 0.690, 0.690, 1.0), # #B0B0B0
	Slot.TEXT_MUTED: Color(0.522, 0.522, 0.522, 1.0), # #858585
	Slot.TEXT_DISABLED: Color(0.376, 0.376, 0.376, 1.0),
	Slot.ICON_PRIMARY: Color(0.800, 0.800, 0.800, 1.0), # #CCCCCC
	Slot.ICON_MUTED: Color(0.522, 0.522, 0.522, 1.0), # #858585
	Slot.SURFACE_RAISED: Color(0.271, 0.271, 0.271, 1.0), # #454545
	Slot.ACCENT_SOFT: Color(0.278, 0.447, 0.702, 0.22),
}

# ============================================================================
#                      TOKENS — MODO DARK CONTRASTE
# ============================================================================

const DARK_CONTRAST_PALETTE: Dictionary = {
	Slot.PANEL_BG: Color(0.094, 0.094, 0.094, 1.0), # #181818
	Slot.PANEL_SURFACE: Color(0.125, 0.125, 0.125, 1.0), # #202020
	Slot.PANEL_TEXT: Color(1.0, 1.0, 1.0, 1.0), # #FFFFFF
	Slot.ACCENT: Color(0.40, 0.70, 0.92, 1.0), # #66B2EB — contraste legible y nítido pero no estridente
	Slot.ACCENT_HOVER: Color(0.50, 0.78, 0.98, 1.0),
	Slot.AFFIRMATIVE: Color(0.0, 1.0, 0.4, 1.0),
	Slot.NEGATIVE: Color(1.0, 0.2, 0.2, 1.0),
	Slot.WARNING: Color(1.0, 0.80, 0.0, 1.0),
	Slot.BUTTON_BG: Color(0.133, 0.133, 0.133, 1.0), # #222222
	Slot.BUTTON_HOVER: Color(0.188, 0.188, 0.188, 1.0), # #303030
	Slot.BUTTON_PRESSED: Color(0.251, 0.251, 0.251, 1.0), # #404040
	Slot.BUTTON_TEXT: Color(1.0, 1.0, 1.0, 1.0),
	Slot.BUTTON_SELECTED: Color(0.22, 0.38, 0.54, 1.0),
	Slot.TOOLBAR_BG: Color(0.063, 0.063, 0.063, 1.0), # #101010
	Slot.RULER_BG: Color(0.051, 0.051, 0.051, 1.0), # #0D0D0D
	Slot.CANVAS_BG: Color(0.063, 0.063, 0.063, 1.0), # #101010
	Slot.ARBOARD_BG: Color(1, 1, 1, 1),
	Slot.INPUT_BG: Color(0.157, 0.157, 0.157, 1.0), # #282828
	Slot.INPUT_HOVER: Color(0.200, 0.200, 0.200, 1.0), # #333333
	Slot.INPUT_FOCUS: Color(0.122, 0.122, 0.122, 1.0), # #1F1F1F
	Slot.INPUT_BORDER: Color(0.353, 0.353, 0.353, 1.0), # #5A5A5A
	Slot.SCROLLBAR_BG: Color(0, 0, 0, 0.30),
	Slot.SCROLLBAR_GRAB: Color(0.55, 0.55, 0.60, 1.0),
	Slot.WIDGET_BG: Color(0.094, 0.094, 0.094, 1.0),
	Slot.BORDER: Color(0.267, 0.267, 0.267, 1.0), # #444444
	Slot.BORDER_STRONG: Color(0.353, 0.353, 0.353, 1.0), # #5A5A5A
	Slot.TEXT_SECONDARY: Color(0.784, 0.784, 0.784, 1.0), # #C8C8C8
	Slot.TEXT_MUTED: Color(0.600, 0.600, 0.600, 1.0), # #999999
	Slot.TEXT_DISABLED: Color(0.400, 0.400, 0.400, 1.0),
	Slot.ICON_PRIMARY: Color(1.0, 1.0, 1.0, 1.0), # #FFFFFF
	Slot.ICON_MUTED: Color(0.600, 0.600, 0.600, 1.0), # #999999
	Slot.SURFACE_RAISED: Color(0.157, 0.157, 0.157, 1.0), # #282828
	Slot.ACCENT_SOFT: Color(0.40, 0.70, 0.92, 0.22),
}

# ============================================================================
#                       CATÁLOGO DE TEMAS DISPONIBLES
# ============================================================================

const THEMES: Dictionary = {
	"light": LIGHT_PALETTE,
	"blanco": LIGHT_PALETTE,
	"godot_blue": GODOT_BLUE_PALETTE,
	"blender_gray": BLENDER_GRAY_PALETTE,
	"dark": DARK_PALETTE,
	"dark_contrast": DARK_CONTRAST_PALETTE,
}

const THEME_LABELS: Dictionary = {
	"light": "Blanco",
	"godot_blue": "Azul Godot Engine",
	"blender_gray": "Gris de Blender",
	"dark": "Dark",
	"dark_contrast": "Dark Contraste",
}

var current_mode: String = "light"
var _overrides: Dictionary = {}

func _ready() -> void:
	_load_overrides()
	_apply(_leer_modo_guardado())

func _leer_modo_guardado() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		var m := String(cfg.get_value("theme", "mode", "light"))
		if THEMES.has(m):
			return m
	return "light"

func set_mode(mode: String) -> void:
	var normalized_mode := "light" if mode == "blanco" else mode
	if normalized_mode == current_mode:
		return
	if not THEMES.has(normalized_mode):
		push_warning("ThemeManager: modo no reconocido '%s'" % mode)
		return
	_apply(normalized_mode)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("theme", "mode", current_mode)
	cfg.save(CONFIG_PATH)

func toggle() -> void:
	set_mode("light" if is_dark() else "dark")

func is_dark() -> bool:
	return current_mode != "light" and current_mode != "blanco"

## Highlight for interactive states (selection, focus, drop targets): white on
## dark themes (blue reads poorly there), the accent blue on the light theme.
func get_interactive_color() -> Color:
	return Color.WHITE if is_dark() else get_color(Slot.ACCENT)

func get_available_themes() -> Dictionary:
	return THEME_LABELS

func get_color(slot: int) -> Color:
	if slot in _overrides:
		return _overrides[slot]
	var palette: Dictionary = THEMES.get(current_mode, DARK_PALETTE if is_dark() else LIGHT_PALETTE)
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
	var palette: Dictionary = THEMES.get(current_mode, DARK_PALETTE if is_dark() else LIGHT_PALETTE)
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
	# Sin tocar sus ajustes: es el MISMO recurso que usa FontCore en el lienzo
	# (sin MSDF, ver FontCore.setup_canvas_font). Antes aquí se le activaba
	# MSDF y ambos se pisaban según quién corriera último.
	var base_f = preload("res://assets/fonts/Inter-Regular.ttf")
	theme.default_font = base_f

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
	var icon_primary := get_color(Slot.ICON_PRIMARY)
	var icon_muted := get_color(Slot.ICON_MUTED)
	theme.set_color("icon_normal_color", "Button", icon_primary)
	theme.set_color("icon_hover_color", "Button", text_primary)
	theme.set_color("icon_pressed_color", "Button", accent)
	theme.set_color("icon_focus_color", "Button", icon_primary)
	theme.set_color("icon_disabled_color", "Button", icon_muted)
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
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_accelerator_color", "PopupMenu", text_secondary)
	theme.set_color("font_disabled_color", "PopupMenu", text_disabled)
	theme.set_color("font_separator_color", "PopupMenu", border)
	theme.set_stylebox("hover", "PopupMenu", _flat(accent, 4, Color(0, 0, 0, 0)))

	# --- OptionButton ---
	theme.set_stylebox("normal", "OptionButton", _flat(get_color(Slot.INPUT_BG), 4, border))
	theme.set_stylebox("hover", "OptionButton", _flat(get_color(Slot.INPUT_HOVER), 4, border))
	theme.set_stylebox("pressed", "OptionButton", _flat(get_color(Slot.BUTTON_PRESSED), 4, accent))
	theme.set_stylebox("focus", "OptionButton", _flat(Color(0, 0, 0, 0), 4, accent))
	theme.set_stylebox("disabled", "OptionButton", _flat(get_color(Slot.INPUT_BG), 4, border))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(c, "OptionButton", text_primary)
	theme.set_color("font_disabled_color", "OptionButton", text_disabled)
	theme.set_color("icon_normal_color", "OptionButton", text_secondary)


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

	# --- CheckButton / CheckBox: toggle elegante ---
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

var _stencil_cache: Dictionary = {}

## Convierte un icono (típicamente SVG negro) en una textura blanca con alfa (1, 1, 1, a).
## Esto permite que modulate o icon_*_color lo tiñan correctamente al color del tema.
func make_white_icon(tex: Texture2D, target_size: int = 0) -> Texture2D:
	if tex == null:
		return null
	var clave := "%s_%d" % [str(tex.get_rid()), target_size]
	if _stencil_cache.has(clave):
		return _stencil_cache[clave]
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	if target_size > 0 and (img.get_width() != target_size or img.get_height() != target_size):
		img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var out: Texture2D = ImageTexture.create_from_image(img)
	# Keep a trace of the source file (the stencil has no resource_path)
	out.resource_name = tex.resource_path if tex.resource_path != "" else tex.resource_name
	_stencil_cache[clave] = out
	return out

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

func get_button_stylebox(state: String = "normal", is_selected: bool = false, corner_radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(corner_radius)
	var border_col := get_color(Slot.BORDER)
	var accent_col := get_color(Slot.ACCENT)
	
	if is_selected:
		sb.bg_color = get_color(Slot.BUTTON_SELECTED)
		sb.border_color = accent_col
		sb.set_border_width_all(1)
	else:
		match state:
			"normal":
				sb.bg_color = get_color(Slot.BUTTON_BG)
				sb.border_color = border_col
				sb.set_border_width_all(1)
			"hover":
				sb.bg_color = get_color(Slot.BUTTON_HOVER)
				sb.border_color = border_col
				sb.set_border_width_all(1)
			"pressed":
				sb.bg_color = get_color(Slot.BUTTON_PRESSED)
				sb.border_color = accent_col
				sb.set_border_width_all(1)
			"disabled":
				sb.bg_color = get_color(Slot.BUTTON_BG)
				sb.border_color = border_col
				sb.set_border_width_all(1)
	return sb

func style_button(btn: Button, is_selected: bool = false, corner_radius: int = 4) -> void:
	if not is_instance_valid(btn):
		return
	var text_col: Color = Color.WHITE if is_selected else get_color(Slot.PANEL_TEXT)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_col)
	btn.add_theme_color_override("font_pressed_color", text_col)
	btn.add_theme_color_override("font_focus_color", text_col)
	btn.add_theme_color_override("font_disabled_color", get_color(Slot.TEXT_DISABLED))
	
	var icon_col: Color = Color.WHITE if is_selected else get_color(Slot.ICON_PRIMARY)
	btn.add_theme_color_override("icon_normal_color", icon_col)
	btn.add_theme_color_override("icon_hover_color", Color.WHITE if is_selected else get_color(Slot.PANEL_TEXT))
	btn.add_theme_color_override("icon_pressed_color", get_color(Slot.ACCENT))
	btn.add_theme_color_override("icon_focus_color", icon_col)
	btn.add_theme_color_override("icon_disabled_color", get_color(Slot.ICON_MUTED))

	btn.add_theme_stylebox_override("normal", get_button_stylebox("normal", is_selected, corner_radius))
	btn.add_theme_stylebox_override("hover", get_button_stylebox("hover", is_selected, corner_radius))
	btn.add_theme_stylebox_override("pressed", get_button_stylebox("pressed", is_selected, corner_radius))
	btn.add_theme_stylebox_override("disabled", get_button_stylebox("disabled", is_selected, corner_radius))

# ============================================================================
#                           PERSISTENCIA DE OVERRIDES
# ============================================================================

func _save_overrides() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)   # preserva [theme] mode= y demás secciones
	if cfg.has_section("colors"):
		cfg.erase_section("colors")
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
