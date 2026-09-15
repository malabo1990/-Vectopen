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

# Estilos visuales Studio (monocromáticos, legibles y accesibles)
var _style_active: StyleBoxFlat
var _style_inactive: StyleBoxFlat

func _ready() -> void:
	_setup_styles()
	_create_buttons()
	_update_active_button(GlobalUI.get_ui_mode() if is_instance_valid(GlobalUI) else "smart")
	_connect_events()

func _setup_styles() -> void:
	# Chip activo: gris sutil (#D8D8DC), esquinas redondeadas de 6px
	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = Color(0.84, 0.84, 0.86, 1.0)
	_style_active.border_width_left = 1
	_style_active.border_width_top = 1
	_style_active.border_width_right = 1
	_style_active.border_width_bottom = 1
	_style_active.border_color = Color(0.68, 0.68, 0.72, 1.0)
	_style_active.set_corner_radius_all(6)
	_style_active.content_margin_left = 10
	_style_active.content_margin_right = 10
	_style_active.content_margin_top = 4
	_style_active.content_margin_bottom = 4

	# Chip inactivo: transparente / neutro muy suave
	_style_inactive = StyleBoxFlat.new()
	_style_inactive.bg_color = Color(0.96, 0.96, 0.97, 0.6)
	_style_inactive.border_width_left = 1
	_style_inactive.border_width_top = 1
	_style_inactive.border_width_right = 1
	_style_inactive.border_width_bottom = 1
	_style_inactive.border_color = Color(0.88, 0.88, 0.90, 0.8)
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

func _make_pill(mode_id: String, label_text: String, tooltip_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.tooltip_text = tooltip_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(60, 26) if compact else Vector2(76, 28)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.05, 0.05, 0.07, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.0, 0.0, 0.0, 1.0))
	btn.add_theme_stylebox_override("normal", _style_inactive)
	btn.add_theme_stylebox_override("hover", _style_active)
	btn.add_theme_stylebox_override("pressed", _style_active)
	btn.pressed.connect(func(): _on_button_pressed(mode_id))
	return btn

func _connect_events() -> void:
	if is_instance_valid(GlobalUI) and GlobalUI.has_signal("ui_mode_changed"):
		if not GlobalUI.ui_mode_changed.is_connected(_on_ui_mode_changed):
			GlobalUI.ui_mode_changed.connect(_on_ui_mode_changed)

func _on_button_pressed(mode_id: String) -> void:
	if is_instance_valid(GlobalUI):
		GlobalUI.set_ui_mode(mode_id)
	else:
		_update_active_button(mode_id)

func _on_ui_mode_changed(new_mode: String) -> void:
	_update_active_button(new_mode)

func _update_active_button(active_mode: String) -> void:
	if not is_instance_valid(btn_smart) or not is_instance_valid(btn_modern) or not is_instance_valid(btn_pro):
		return

	var map := {
		"smart": btn_smart,
		"modern": btn_modern,
		"professional": btn_pro
	}

	for m in map:
		var btn: Button = map[m]
		if m == active_mode:
			btn.add_theme_stylebox_override("normal", _style_active)
			btn.text = ("● " if not compact else "") + (
				"Smart" if m == "smart" else ("Modern" if m == "modern" else "Pro")
			)
			btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08, 1.0))
		else:
			btn.add_theme_stylebox_override("normal", _style_inactive)
			btn.text = "Smart" if m == "smart" else ("Modern" if m == "modern" else "Pro")
			btn.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38, 1.0))
