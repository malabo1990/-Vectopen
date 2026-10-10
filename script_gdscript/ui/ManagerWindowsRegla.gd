# =============================================================================
# VECTOPEN — GESTOR DE VENTANA DE CONFIGURACIÓN Y REGLAS
# RUTA: res://script_gdscript/ui/ManagerWindowsRegla.gd
# Controla la apertura, cierre (botón ✕, tecla ESC), adaptación de tema y visibilidad
# =============================================================================
class_name ManagerWindowsRegla
extends PanelContainer

signal closed
signal opened

@onready var btn_close: Button = find_child("BtnClose", true, false) as Button

var _active_tab_index: int = 0
var _tab_container: BoxContainer = null

func _ready() -> void:
	if not btn_close:
		btn_close = find_child("ButtonClose", true, false) as Button
	if btn_close and not btn_close.pressed.is_connected(close_settings):
		btn_close.pressed.connect(close_settings)

	_tab_container = find_child("tab", true, false) as BoxContainer

	var tm_node = find_child("TabManager", true, false)
	if tm_node and tm_node.has_signal("button_clicked"):
		if not tm_node.button_clicked.is_connected(_on_tab_changed):
			tm_node.button_clicked.connect(_on_tab_changed)

	_connect_theme()
	_apply_theme()

func _connect_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

func _on_theme_changed(_mode: String) -> void:
	_apply_theme()

func _on_color_slot_changed(_slot: String, _color: Color) -> void:
	_apply_theme()

func _on_tab_changed(index: int) -> void:
	_active_tab_index = index
	_update_tab_styles()

func _apply_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY)
	var neg_col: Color = tm.get_color(S.NEGATIVE)
	var is_dark: bool = tm.is_dark()

	# 1. Contenedor principal
	var sb := StyleBoxFlat.new()
	sb.bg_color = surface_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.30 if is_dark else 0.08)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 5)
	add_theme_stylebox_override("panel", sb)

	# 2. Header
	var title_lbl := find_child("Header", true, false)
	if title_lbl:
		var lbl = title_lbl.find_child("Label", true, false) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", text_col)
			lbl.add_theme_font_size_override("font_size", 13)

	if btn_close:
		btn_close.add_theme_color_override("font_color", text_sec)
		btn_close.add_theme_color_override("font_hover_color", neg_col)
		btn_close.add_theme_color_override("font_pressed_color", neg_col)
		btn_close.flat = true

	# 3. Pestañas
	_update_tab_styles()

	# 4. Recursivamente estilar controles en las páginas de Container
	var content_container = find_child("Container", true, false)
	if content_container:
		_style_tree_controls(content_container, tm)

func _update_tab_styles() -> void:
	if not _tab_container:
		return
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var btn_bg: Color = tm.get_color(S.BUTTON_BG)
	var btn_hov: Color = tm.get_color(S.BUTTON_HOVER)
	var surface_raised: Color = tm.get_color(S.SURFACE_RAISED)
	var accent: Color = tm.get_color(S.ACCENT)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY)

	var t_norm := StyleBoxFlat.new()
	t_norm.bg_color = btn_bg
	t_norm.border_color = border_col
	t_norm.set_border_width_all(1)
	t_norm.set_corner_radius_all(6)
	t_norm.content_margin_left = 12
	t_norm.content_margin_right = 12
	t_norm.content_margin_top = 5
	t_norm.content_margin_bottom = 5

	var t_hov := StyleBoxFlat.new()
	t_hov.bg_color = btn_hov
	t_hov.border_color = border_col
	t_hov.set_border_width_all(1)
	t_hov.set_corner_radius_all(6)
	t_hov.content_margin_left = 12
	t_hov.content_margin_right = 12
	t_hov.content_margin_top = 5
	t_hov.content_margin_bottom = 5

	var t_act := StyleBoxFlat.new()
	t_act.bg_color = surface_raised
	t_act.border_color = accent
	t_act.set_border_width_all(1)
	t_act.set_corner_radius_all(6)
	t_act.content_margin_left = 12
	t_act.content_margin_right = 12
	t_act.content_margin_top = 5
	t_act.content_margin_bottom = 5

	for i in range(_tab_container.get_child_count()):
		var btn = _tab_container.get_child(i) as Button
		if btn:
			var is_act := (i == _active_tab_index)
			btn.add_theme_stylebox_override("normal", t_act if is_act else t_norm)
			btn.add_theme_stylebox_override("hover", t_hov)
			btn.add_theme_stylebox_override("pressed", t_act)
			btn.add_theme_color_override("font_color", text_col if is_act else text_sec)
			btn.add_theme_color_override("font_hover_color", text_col)
			btn.add_theme_color_override("font_pressed_color", text_col)
			btn.add_theme_font_size_override("font_size", 11)

func _style_tree_controls(node: Node, tm: Node) -> void:
	var S = tm.Slot
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var border_col: Color = tm.get_color(S.BORDER)

	for child in node.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", text_col)
			child.add_theme_font_size_override("font_size", 11)
		elif child is CheckButton:
			child.add_theme_color_override("font_color", text_col)
			child.add_theme_font_size_override("font_size", 11)
		elif child is CheckBox:
			child.add_theme_color_override("font_color", text_col)
			child.add_theme_font_size_override("font_size", 11)
		elif child is Button and not child.get_parent() is ColorPickerButton:
			if not (child is CheckButton or child is CheckBox):
				_style_dialog_button(child, tm)
		elif child is ColorPickerButton:
			_style_color_picker_button(child, border_col)
		elif child is LineEdit:
			_style_line_edit(child, tm)

		if child.get_child_count() > 0 and not (child is ThemeConfigPanel):
			_style_tree_controls(child, tm)

func _style_dialog_button(btn: Button, tm: Node) -> void:
	if tm.has_method("style_button"):
		tm.style_button(btn, false, 6)
	else:
		btn.add_theme_font_size_override("font_size", 11)

func _style_color_picker_button(cp: ColorPickerButton, border_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cp.color
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	cp.add_theme_stylebox_override("normal", sb)

func _style_line_edit(le: LineEdit, tm: Node) -> void:
	var S = tm.Slot
	var bg: Color = tm.get_color(S.INPUT_BG)
	var border: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", sb)
	le.add_theme_color_override("font_color", text_col)

func open_settings() -> void:
	_apply_theme()
	_clamp_to_viewport()
	visible = true
	move_to_front()
	opened.emit()

func close_settings() -> void:
	visible = false
	closed.emit()

func toggle_settings() -> void:
	if visible:
		close_settings()
	else:
		open_settings()

func _clamp_to_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var w: float = maxf(size.x, custom_minimum_size.x)
	var h: float = maxf(size.y, custom_minimum_size.y)
	if offset_right > vp.x:
		var shift_x = offset_right - vp.x + 16.0
		offset_left = maxf(16.0, offset_left - shift_x)
		offset_right = offset_left + w
	if offset_bottom > vp.y:
		var shift_y = offset_bottom - vp.y + 16.0
		offset_top = maxf(16.0, offset_top - shift_y)
		offset_bottom = offset_top + h

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_settings()
		get_viewport().set_input_as_handled()

