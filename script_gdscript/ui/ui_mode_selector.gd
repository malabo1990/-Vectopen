# =============================================================================
# VECTOPEN — SELECTOR DE MODO DE INTERFAZ ADAPTABLE
# RUTA: res://script_gdscript/ui/ui_mode_selector.gd
# Modos: Smart Panel (Vectopen) | Modern Panel (Figma) | Professional Panel (Affinity/Illustrator)
# =============================================================================
class_name UIModeSelector
extends HBoxContainer

@export var show_labels: bool = true
@export var compact: bool = false

var btn_smart: Button
var btn_modern: Button
var btn_pro: Button

# Estilos visuales — reconstruidos desde ThemeManager en cada cambio de tema
# (mismo patrón que PanelPolygon._update_shape_button_styles()).
var _style_active: StyleBoxFlat
var _style_inactive: StyleBoxFlat
var _color_text_active: Color = Color(0.05, 0.05, 0.08, 1.0)
var _color_text_inactive: Color = Color(0.35, 0.35, 0.38, 1.0)

var _current_mode: String = "smart"

func _ready() -> void:
	_setup_styles()
	_create_buttons()
	_current_mode = GlobalUI.get_ui_mode() if is_instance_valid(GlobalUI) else "smart"
	_update_active_button(_current_mode)
	_connect_events()
	_connect_theme()

func _connect_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

func _on_theme_changed(_mode: String) -> void:
	_setup_styles()
	_update_active_button(_current_mode)

func _on_color_slot_changed(_slot: String, _color: Color) -> void:
	_setup_styles()
	_update_active_button(_current_mode)

func _setup_styles() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var active_bg: Color = tm.get_color(S.SURFACE_RAISED) if tm else Color(0.84, 0.84, 0.86, 1.0)
	var active_border: Color = tm.get_color(S.ACCENT) if tm else Color(0.68, 0.68, 0.72, 1.0)
	var inactive_bg: Color = tm.get_color(S.BUTTON_BG) if tm else Color(0.96, 0.96, 0.97, 0.6)
	var inactive_border: Color = tm.get_color(S.BORDER) if tm else Color(0.88, 0.88, 0.90, 0.8)
	_color_text_active = tm.get_color(S.PANEL_TEXT) if tm else Color(0.05, 0.05, 0.08, 1.0)
	_color_text_inactive = tm.get_color(S.TEXT_SECONDARY) if tm else Color(0.35, 0.35, 0.38, 1.0)

	# Chip activo: superficie elevada + borde de acento, esquinas redondeadas de 6px
	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = active_bg
	_style_active.border_width_left = 1
	_style_active.border_width_top = 1
	_style_active.border_width_right = 1
	_style_active.border_width_bottom = 1
	_style_active.border_color = active_border
	_style_active.set_corner_radius_all(6)
	_style_active.content_margin_left = 10
	_style_active.content_margin_right = 10
	_style_active.content_margin_top = 4
	_style_active.content_margin_bottom = 4

	# Chip inactivo: fondo de botón neutro del tema activo
	_style_inactive = StyleBoxFlat.new()
	_style_inactive.bg_color = inactive_bg
	_style_inactive.border_width_left = 1
	_style_inactive.border_width_top = 1
	_style_inactive.border_width_right = 1
	_style_inactive.border_width_bottom = 1
	_style_inactive.border_color = inactive_border
	_style_inactive.set_corner_radius_all(6)
	_style_inactive.content_margin_left = 10
	_style_inactive.content_margin_right = 10
	_style_inactive.content_margin_top = 4
	_style_inactive.content_margin_bottom = 4

func _create_buttons() -> void:
	add_theme_constant_override("separation", 4)
	
	btn_smart = _make_pill("smart", "● Smart" if not compact else "Smart", "Smart Panel — Canvas amplio, Layers fija y contexto inteligente (Modo Vectopen)")
	btn_modern = _make_pill("modern", "Modern" if not compact else "Mod", "Modern Panel — Inspector lateral derecho permanente (Estilo Figma)")
	btn_pro = _make_pill("professional", "Pro" if not compact else "Pro", "Professional Panel — Paneles acoplados completos de alta densidad (Estilo Affinity / Illustrator)")

	add_child(btn_smart)
	add_child(btn_modern)
	add_child(btn_pro)

func _make_pill(mode_id: String, label_text: String, p_tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.tooltip_text = p_tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(60, 26) if compact else Vector2(76, 28)
	btn.add_theme_font_size_override("font_size", 11)
	# El estilado real (stylebox normal/hover/pressed + colores de fuente,
	# según tema y estado activo/inactivo) lo aplica _update_active_button()
	# — se llama justo después de _create_buttons() y en cada cambio de
	# tema/modo, así que este botón nace "en blanco" y se pinta una sola vez.
	btn.pressed.connect(func(): _on_button_pressed(mode_id))
	return btn

func _connect_events() -> void:
	if is_instance_valid(GlobalUI) and GlobalUI.has_signal("ui_mode_changed"):
		if not GlobalUI.ui_mode_changed.is_connected(_on_ui_mode_changed):
			GlobalUI.ui_mode_changed.connect(_on_ui_mode_changed)

func _exit_tree() -> void:
	if is_instance_valid(GlobalUI) and GlobalUI.has_signal("ui_mode_changed"):
		if GlobalUI.ui_mode_changed.is_connected(_on_ui_mode_changed):
			GlobalUI.ui_mode_changed.disconnect(_on_ui_mode_changed)

func _on_button_pressed(mode_id: String) -> void:
	if is_instance_valid(GlobalUI):
		GlobalUI.set_ui_mode(mode_id)
	else:
		_update_active_button(mode_id)

func _on_ui_mode_changed(new_mode: String) -> void:
	_current_mode = new_mode
	_update_active_button(new_mode)

func _update_active_button(active_mode: String) -> void:
	if not is_instance_valid(btn_smart) or not is_instance_valid(btn_modern) or not is_instance_valid(btn_pro):
		return
	_current_mode = active_mode

	var map := {
		"smart": btn_smart,
		"modern": btn_modern,
		"professional": btn_pro
	}

	for m in map:
		var btn: Button = map[m]
		var is_act: bool = (m == active_mode)
		var style: StyleBoxFlat = _style_active if is_act else _style_inactive
		var text_col: Color = _color_text_active if is_act else _color_text_inactive
		# Los 3 estados (normal/hover/pressed) comparten el MISMO stylebox del
		# estado activo/inactivo — igual criterio que PanelPolygon, evita que
		# el hover/pressed se quede pegado al color viejo tras un cambio de tema.
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_color_override("font_color", text_col)
		btn.add_theme_color_override("font_hover_color", text_col)
		btn.add_theme_color_override("font_pressed_color", text_col)
		btn.text = ("● " if (is_act and not compact) else "") + (
			"Smart" if m == "smart" else ("Modern" if m == "modern" else "Pro")
		)
