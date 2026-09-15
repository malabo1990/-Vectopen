# =============================================================================
# VECTOPEN — MODERN NAVIGATION RAIL (FIGMA UI3 STYLE)
# RUTA: res://script_gdscript/ui/modern/modern_nav_rail.gd
# Riel lateral estrecho que permite conmutar áreas de trabajo y paneles
# =============================================================================
class_name ModernNavRail
extends PanelContainer

signal section_selected(section_id: String)
signal left_panel_toggled(is_open: bool)

var _buttons: Dictionary = {}
var _active_section: String = "layers"
var _panel_open: bool = true

func _ready() -> void:
	_setup_styles()
	_build_ui()
	_sync_active_button()

func _setup_styles() -> void:
	custom_minimum_size = Vector2(42, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
	sb.border_width_right = 1
	sb.border_color = Color(0.88, 0.88, 0.90, 1.0)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var sections := [
		{"id": "canvas", "icon": "◈", "tooltip": "Canvas (Área de Trabajo)"},
		{"id": "layers", "icon": "▱", "tooltip": "Capas y Jerarquía"},
		{"id": "assets", "icon": "◇", "tooltip": "Componentes y Recursos"},
	]

	for s in sections:
		var btn := Button.new()
		btn.text = s["icon"]
		btn.tooltip_text = s["tooltip"]
		btn.custom_minimum_size = Vector2(34, 34)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		
		var sid: String = s["id"]
		btn.pressed.connect(func(): _on_section_pressed(sid))
		vbox.add_child(btn)
		_buttons[sid] = btn

	# Espacio flexible hacia abajo
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Botón de Preferencias / Configuración abajo
	var btn_settings := Button.new()
	btn_settings.text = "⚙"
	btn_settings.tooltip_text = "Configuración y Preferencias"
	btn_settings.custom_minimum_size = Vector2(34, 34)
	btn_settings.focus_mode = Control.FOCUS_NONE
	btn_settings.add_theme_font_size_override("font_size", 14)
	btn_settings.pressed.connect(_on_settings_pressed)
	vbox.add_child(btn_settings)
	_buttons["settings"] = btn_settings

func _on_section_pressed(section_id: String) -> void:
	if section_id == "canvas":
		_active_section = "canvas"
		_panel_open = false
	elif _active_section == section_id:
		# Si se vuelve a presionar la misma sección, colapsa/expande el panel izquierdo
		_panel_open = !_panel_open
	else:
		_active_section = section_id
		_panel_open = true

	_sync_active_button()
	section_selected.emit(_active_section)
	left_panel_toggled.emit(_panel_open)

func _on_settings_pressed() -> void:
	section_selected.emit("settings")
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_settings_dialog"):
		ge.emit_safe("request_settings_dialog")

func _sync_active_button() -> void:
	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color(0.86, 0.86, 0.88, 1.0)
	active_sb.set_corner_radius_all(6)

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	normal_sb.set_corner_radius_all(6)

	for sid in _buttons:
		var btn: Button = _buttons[sid]
		if sid == _active_section and _panel_open:
			btn.add_theme_stylebox_override("normal", active_sb)
			btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08, 1.0))
		else:
			btn.add_theme_stylebox_override("normal", normal_sb)
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45, 1.0))

func is_panel_open() -> bool:
	return _panel_open

func get_active_section() -> String:
	return _active_section
