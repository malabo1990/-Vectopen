@tool
class_name ThemeConfigPanel
extends PanelContainer

var _fill_picker: ColorPickerButton
var _stroke_picker: ColorPickerButton
var _text_picker: ColorPickerButton
var _text_size_spin: Node
var _lang_option: OptionButton
var _ui_colors: VBoxContainer
var _slot_container: VBoxContainer
var _mcp_check: CheckBox
var _mcp_status: Label
var _mcp_token_field: LineEdit

var _opt_theme: OptionButton
var _lbl_ui_mode: Label
var _lbl_theme_preset: Label
var _sec_mcp: Label
var _lbl_mcp: Label
var _lbl_token: Label
var _btn_regen_token: Button
var _btn_reset_colors: Button

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	_find_nodes()
	_load_draw_prefs()
	_populate_ui_mode()
	_populate_theme_preset()
	_populate_language()
	_populate_ui_colors()
	_populate_mcp_section()
	_connect_signals()
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
	_sync_theme_dropdown()

func _on_color_slot_changed(_slot_name: String, _color: Color) -> void:
	_apply_theme()

func _apply_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY)
	var is_dark: bool = tm.is_dark()

	# 1. Contenedor principal
	var is_embedded: bool = get_parent() != null and get_parent().name == "Container"
	if is_embedded:
		var empty_sb := StyleBoxEmpty.new()
		add_theme_stylebox_override("panel", empty_sb)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = surface_col
		sb.border_color = border_col
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(0, 0, 0, 0.30 if is_dark else 0.08)
		sb.shadow_size = 12
		sb.shadow_offset = Vector2(0, 4)
		add_theme_stylebox_override("panel", sb)

	# 2. Header
	var title_lbl := get_node_or_null("MarginContainer/VBoxContainer/Header/Title") as Label
	if title_lbl:
		title_lbl.add_theme_color_override("font_color", text_col)
		title_lbl.add_theme_font_size_override("font_size", 12)

	var reset_all_btn := get_node_or_null("MarginContainer/VBoxContainer/Header/ResetAll") as Button
	if reset_all_btn:
		_style_chip_button(reset_all_btn, false)

	var close_btn := get_node_or_null("MarginContainer/VBoxContainer/Header/ButtonClose") as Button
	if close_btn:
		close_btn.visible = not is_embedded
		_style_close_button(close_btn)

	# 3. Encabezados de sección fijos en SlotContainer
	var sec_dibujo := get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/SecDibujo") as Label
	if sec_dibujo: _style_section_label(sec_dibujo, text_col)
	var sec_texto := get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/SecTexto") as Label
	if sec_texto: _style_section_label(sec_texto, text_col)
	var sec_ui := get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/SecUI") as Label
	if sec_ui: _style_section_label(sec_ui, text_col)
	if _sec_mcp: _style_section_label(_sec_mcp, text_col)

	# 4. Etiquetas fijas de filas
	for lbl_path in [
		"MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowFill/LblFill",
		"MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowStroke/LblStroke",
		"MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowTextColor/LblTextColor",
		"MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowTextSize/LblTextSize",
		"MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowLang/LblLang",
	]:
		var l := get_node_or_null(lbl_path) as Label
		if l:
			l.add_theme_color_override("font_color", text_col)
			l.add_theme_font_size_override("font_size", 11)

	if _lbl_ui_mode:
		_lbl_ui_mode.add_theme_color_override("font_color", text_col)
		_lbl_ui_mode.add_theme_font_size_override("font_size", 11)
	if _lbl_theme_preset:
		_lbl_theme_preset.add_theme_color_override("font_color", text_col)
		_lbl_theme_preset.add_theme_font_size_override("font_size", 11)
	if _lbl_mcp:
		_lbl_mcp.add_theme_color_override("font_color", text_col)
		_lbl_mcp.add_theme_font_size_override("font_size", 11)
	if _lbl_token:
		_lbl_token.add_theme_color_override("font_color", text_col)
		_lbl_token.add_theme_font_size_override("font_size", 11)

	# 5. Botones de acción al final de SlotContainer
	var btn_apply := get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/BtnApply") as Button
	if btn_apply: _style_chip_button(btn_apply, true)
	var btn_theme := get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/BtnTheme") as Button
	if btn_theme: _style_chip_button(btn_theme, false)

	# 6. OptionButtons
	if _lang_option: _style_option_button(_lang_option)
	if _opt_theme: _style_option_button(_opt_theme)

	# 7. Controles MCP
	if _mcp_check:
		_mcp_check.add_theme_color_override("font_color", text_col)
	if _mcp_token_field:
		_style_line_edit(_mcp_token_field)
	if _btn_regen_token:
		_style_chip_button(_btn_regen_token, false)
	if _mcp_status:
		_mcp_status.add_theme_color_override("font_color", text_sec)

	# 8. Controles de colores UI
	if _btn_reset_colors:
		_style_chip_button(_btn_reset_colors, false)
	if _ui_colors:
		for c in _ui_colors.get_children():
			if c is HBoxContainer:
				for sub in c.get_children():
					if sub is Label:
						sub.add_theme_color_override("font_color", text_col)
					elif sub is ColorPickerButton:
						_style_color_picker(sub)

	# Estilar color pickers fijos
	if _fill_picker: _style_color_picker(_fill_picker)
	if _stroke_picker: _style_color_picker(_stroke_picker)
	if _text_picker: _style_color_picker(_text_picker)

func _style_section_label(lbl: Label, col: Color) -> void:
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_font_size_override("font_size", 11)

func _style_chip_button(btn: Button, is_primary: bool) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_method("style_button"):
		tm.style_button(btn, is_primary, 6)
	else:
		btn.add_theme_font_size_override("font_size", 11)

func _style_close_button(btn: Button) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var text_sec: Color = tm.get_color(S.TEXT_SECONDARY) if (tm and S) else Color(0.6, 0.6, 0.6)
	var neg: Color = tm.get_color(S.NEGATIVE) if (tm and S) else Color(0.9, 0.3, 0.3)
	btn.add_theme_color_override("font_color", text_sec)
	btn.add_theme_color_override("font_hover_color", neg)
	btn.add_theme_color_override("font_pressed_color", neg)
	btn.flat = true

func _style_color_picker(cp: ColorPickerButton) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.7, 0.7, 0.7)
	var sb := StyleBoxFlat.new()
	sb.bg_color = cp.color
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	cp.add_theme_stylebox_override("normal", sb)

func _style_line_edit(le: LineEdit) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.95, 0.95, 0.96)
	var border: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.85, 0.85, 0.88)
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.1, 0.1, 0.1)
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

func _style_option_button(opt: OptionButton) -> void:
	if not is_instance_valid(opt):
		return
	var tm = get_node_or_null("/root/ThemeManager")
	var S = tm.Slot if tm else null
	var bg_col: Color = tm.get_color(S.INPUT_BG) if (tm and S) else Color(0.95, 0.95, 0.96)
	var border_col: Color = tm.get_color(S.BORDER) if (tm and S) else Color(0.85, 0.85, 0.88)
	var text_col: Color = tm.get_color(S.PANEL_TEXT) if (tm and S) else Color(0.1, 0.1, 0.1)
	var is_light: bool = text_col.v < 0.5

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = border_col
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	opt.add_theme_stylebox_override("normal", sb)

	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = tm.get_color(S.INPUT_HOVER) if (tm and S) else (Color(0.88, 0.88, 0.91) if is_light else Color(0.24, 0.24, 0.26))
	opt.add_theme_stylebox_override("hover", sb_h)

	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = tm.get_color(S.BUTTON_PRESSED) if (tm and S) else (Color(0.82, 0.82, 0.86) if is_light else Color(0.30, 0.30, 0.32))
	sb_p.border_color = tm.get_color(S.ACCENT) if (tm and S) else Color(0.16, 0.5, 0.98)
	opt.add_theme_stylebox_override("pressed", sb_p)
	opt.add_theme_stylebox_override("focus", sb)
	opt.add_theme_stylebox_override("disabled", sb)

	opt.add_theme_color_override("font_color", text_col)
	opt.add_theme_color_override("font_hover_color", text_col)
	opt.add_theme_color_override("font_pressed_color", text_col)
	opt.add_theme_color_override("font_focus_color", text_col)

	var pop := opt.get_popup()
	if is_instance_valid(pop):
		var pop_sb := StyleBoxFlat.new()
		pop_sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if is_light else Color(0.14, 0.14, 0.16, 1.0)
		pop_sb.border_color = border_col
		pop_sb.set_border_width_all(1)
		pop_sb.set_corner_radius_all(6)
		pop_sb.content_margin_left = 6
		pop_sb.content_margin_right = 6
		pop_sb.content_margin_top = 4
		pop_sb.content_margin_bottom = 4
		pop_sb.shadow_color = Color(0, 0, 0, 0.12 if is_light else 0.40)
		pop_sb.shadow_size = 8
		pop_sb.shadow_offset = Vector2(0, 3)
		pop.add_theme_stylebox_override("panel", pop_sb)

		var pop_hov := StyleBoxFlat.new()
		var accent: Color = tm.get_color(S.ACCENT) if (tm and S) else Color(0.16, 0.50, 0.98)
		pop_hov.bg_color = Color(accent.r, accent.g, accent.b, 0.18 if is_light else 0.35)
		pop_hov.set_corner_radius_all(4)
		pop.add_theme_stylebox_override("hover", pop_hov)

		pop.add_theme_color_override("font_color", text_col)
		pop.add_theme_color_override("font_hover_color", text_col)
		var muted: Color = tm.get_color(S.TEXT_MUTED) if (tm and S) else Color(0.5, 0.5, 0.5)
		pop.add_theme_color_override("font_disabled_color", muted)
		pop.add_theme_color_override("font_separator_color", border_col)

func _sync_theme_dropdown() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm or not is_instance_valid(_opt_theme):
		return
	var themes: Dictionary = tm.get_available_themes() if tm.has_method("get_available_themes") else {}
	var keys := themes.keys()
	for i in range(keys.size()):
		var k: String = keys[i]
		if k == tm.current_mode or (k == "light" and tm.current_mode == "blanco"):
			_opt_theme.select(i)
			break

func _load_draw_prefs() -> void:
	var dp = get_node_or_null("/root/DrawPreferences")
	if not dp: return
	if _fill_picker: _fill_picker.color = dp.fill_color
	if _stroke_picker: _stroke_picker.color = dp.stroke_color
	if _text_picker: _text_picker.color = dp.text_color
	if _text_size_spin: _text_size_spin.value = dp.text_size

func _find_nodes() -> void:
	_fill_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowFill/PickFill")
	_stroke_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowStroke/PickStroke")
	_text_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowTextColor/PickTextColor")
	_text_size_spin = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowTextSize/SpinTextSize")
	_lang_option = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/RowLang/OptLang")
	_ui_colors = _get_node("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer/UIColors")
	_slot_container = get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/MarginContainer/SlotContainer") as VBoxContainer

func _get_node(node_path: String):
	var n = get_node_or_null(node_path)
	if n == null:
		return null
	if n is ColorPickerButton: return n as ColorPickerButton
	if n is SpinBox: return n as SpinBox
	if n is OptionButton: return n as OptionButton
	if n is VBoxContainer: return n as VBoxContainer
	if "value" in n: return n
	return null

func _populate_ui_mode() -> void:
	if not _slot_container: return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_lbl_ui_mode = Label.new()
	_lbl_ui_mode.text = "UI Mode"
	_lbl_ui_mode.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_lbl_ui_mode.add_theme_font_size_override("font_size", 11)
	row.add_child(_lbl_ui_mode)

	var selector_script := preload("res://script_gdscript/ui/ui_mode_selector.gd")
	var selector = selector_script.new()
	selector.compact = true
	row.add_child(selector)

	_slot_container.add_child(row)
	_slot_container.move_child(row, 0)

func _populate_theme_preset() -> void:
	if not _slot_container: return
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm: return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_lbl_theme_preset = Label.new()
	_lbl_theme_preset.text = "Tema / Preset"
	_lbl_theme_preset.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_lbl_theme_preset.add_theme_font_size_override("font_size", 11)
	row.add_child(_lbl_theme_preset)

	_opt_theme = OptionButton.new()
	_opt_theme.custom_minimum_size = Vector2(140, 24)
	var themes: Dictionary = tm.get_available_themes() if tm.has_method("get_available_themes") else {
		"light": "Blanco",
		"godot_blue": "Azul Godot Engine",
		"blender_gray": "Gris de Blender",
		"dark": "Dark",
		"dark_contrast": "Dark Contraste"
	}
	var keys := themes.keys()
	for i in range(keys.size()):
		var k: String = keys[i]
		_opt_theme.add_item(themes[k], i)
		if k == tm.current_mode or (k == "light" and tm.current_mode == "blanco"):
			_opt_theme.select(i)

	_opt_theme.item_selected.connect(func(idx: int):
		var selected_key: String = keys[idx]
		tm.set_mode(selected_key)
		_populate_ui_colors()
	)
	row.add_child(_opt_theme)

	_slot_container.add_child(row)
	_slot_container.move_child(row, 1)

func _populate_language() -> void:
	if not _lang_option: return
	_lang_option.clear()
	var lm = get_node_or_null("/root/LanguageManager")
	if not lm: return
	for locale in lm.get_locale_list():
		_lang_option.add_item(lm.get_locale_name(locale))
		if locale == lm.current_locale:
			_lang_option.select(_lang_option.item_count - 1)
	_lang_option.item_selected.connect(_on_lang_selected.bind(lm))

func _populate_ui_colors() -> void:
	if not _ui_colors: return
	for c in _ui_colors.get_children():
		c.queue_free()

	var tm = get_node_or_null("/root/ThemeManager")
	if not tm: return

	# Botón de Restablecer colores
	_btn_reset_colors = Button.new()
	_btn_reset_colors.text = "Restablecer colores por defecto"
	_btn_reset_colors.custom_minimum_size = Vector2(0, 24)
	_btn_reset_colors.add_theme_font_size_override("font_size", 10)
	_btn_reset_colors.pressed.connect(func():
		tm.reset_all_custom_colors()
		_populate_ui_colors()
		_apply_theme()
	)
	_ui_colors.add_child(_btn_reset_colors)

	var text_col: Color = tm.get_color(tm.Slot.PANEL_TEXT) if tm else Color(0.9, 0.9, 0.95)

	for slot in tm.get_all_slots():
		var slot_name = tm.get_slot_name(slot).replace("_", " ").capitalize()
		var color = tm.get_color(slot)

		var row := HBoxContainer.new()
		_ui_colors.add_child(row)

		var lbl := Label.new()
		lbl.text = slot_name
		lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", text_col)
		row.add_child(lbl)

		var picker := ColorPickerButton.new()
		picker.color = color
		picker.custom_minimum_size = Vector2(22, 20)
		picker.theme_type_variation = "FlatButton"
		_style_color_picker(picker)
		picker.color_changed.connect(func(c):
			tm.set_custom_color(slot, c)
			_style_color_picker(picker)
		)
		row.add_child(picker)

func _populate_mcp_section() -> void:
	if not _slot_container:
		return
	var srv = get_node_or_null("/root/VectopenMCPServer")
	if not srv:
		return

	var sep := HSeparator.new()
	_slot_container.add_child(sep)

	_sec_mcp = Label.new()
	_sec_mcp.text = "Integraciones IA (MCP)"
	_slot_container.add_child(_sec_mcp)

	var row := HBoxContainer.new()
	_slot_container.add_child(row)
	_lbl_mcp = Label.new()
	_lbl_mcp.text = "Servidor MCP"
	_lbl_mcp.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.add_child(_lbl_mcp)
	_mcp_check = CheckBox.new()
	_mcp_check.button_pressed = srv.is_enabled()
	_mcp_check.toggled.connect(_on_mcp_toggled)
	row.add_child(_mcp_check)

	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 6)
	_slot_container.add_child(token_row)
	_lbl_token = Label.new()
	_lbl_token.text = "Token"
	token_row.add_child(_lbl_token)
	_mcp_token_field = LineEdit.new()
	_mcp_token_field.text = srv.get_token()
	_mcp_token_field.editable = true
	_mcp_token_field.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_mcp_token_field.add_theme_font_size_override("font_size", 10)
	token_row.add_child(_mcp_token_field)
	_btn_regen_token = Button.new()
	_btn_regen_token.text = "Regenerar"
	_btn_regen_token.tooltip_text = "Invalida el token actual. Cualquier cliente MCP ya conectado dejará de funcionar hasta que uses el nuevo."
	_btn_regen_token.pressed.connect(_on_regen_token_pressed)
	token_row.add_child(_btn_regen_token)

	_mcp_status = Label.new()
	_mcp_status.add_theme_font_size_override("font_size", 10)
	_mcp_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_slot_container.add_child(_mcp_status)
	_update_mcp_status(srv)

func _on_mcp_toggled(pressed: bool) -> void:
	var srv = get_node_or_null("/root/VectopenMCPServer")
	if not srv:
		return
	srv.set_enabled(pressed)
	_update_mcp_status(srv)

func _on_regen_token_pressed() -> void:
	var srv = get_node_or_null("/root/VectopenMCPServer")
	if not srv:
		return
	var new_token: String = srv.regenerate_token()
	if _mcp_token_field:
		_mcp_token_field.text = new_token

func _update_mcp_status(srv: Node) -> void:
	if not _mcp_status:
		return
	if srv.is_listening():
		_mcp_status.text = "Escuchando en http://127.0.0.1:%d/mcp (solo este equipo). Requiere el token en Authorization: Bearer <token>." % srv.get_port()
	else:
		_mcp_status.text = "Desactivado. Al activarlo, un agente de IA podrá leer y editar el lienzo vía MCP."

func _connect_signals() -> void:
	if _fill_picker and not _fill_picker.color_changed.is_connected(_on_fill_changed):
		_fill_picker.color_changed.connect(_on_fill_changed)
	if _stroke_picker and not _stroke_picker.color_changed.is_connected(_on_stroke_changed):
		_stroke_picker.color_changed.connect(_on_stroke_changed)
	if _text_picker and not _text_picker.color_changed.is_connected(_on_text_color_changed):
		_text_picker.color_changed.connect(_on_text_color_changed)
	if _text_size_spin and _text_size_spin.has_signal("value_changed"):
		if not _text_size_spin.value_changed.is_connected(_on_text_size_changed):
			_text_size_spin.value_changed.connect(_on_text_size_changed)

func _on_fill_changed(_c) -> void:
	if _fill_picker: _style_color_picker(_fill_picker)
	_save_prefs()

func _on_stroke_changed(_c) -> void:
	if _stroke_picker: _style_color_picker(_stroke_picker)
	_save_prefs()

func _on_text_color_changed(_c) -> void:
	if _text_picker: _style_color_picker(_text_picker)
	_save_prefs()

func _on_text_size_changed(_v) -> void: _save_prefs()

func _on_lang_selected(idx: int, lm: Node) -> void:
	var locales = lm.get_locale_list()
	if idx >= 0 and idx < locales.size():
		lm.set_locale(locales[idx])

func _on_close_pressed() -> void:
	visible = false

func _on_apply_clicked() -> void:
	_save_prefs()
	if has_node("/root/GlobalEvents"):
		GlobalEvents.object_style_changed.emit()

func _on_toggle_theme() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_method("toggle"):
		tm.toggle()

func reset_all() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_method("reset_all_custom_colors"):
		tm.reset_all_custom_colors()
		_populate_ui_colors()
	var dp = get_node_or_null("/root/DrawPreferences")
	if dp:
		dp.fill_color = Color(0.88, 0.88, 0.88, 1)
		dp.stroke_color = Color(0, 0, 0, 1)
		dp.text_color = Color(0, 0, 0, 1)
		dp.text_size = 16
		_load_draw_prefs()
	_apply_theme()

func _save_prefs() -> void:
	var dp = get_node_or_null("/root/DrawPreferences")
	if not dp: return
	if _fill_picker: dp.fill_color = _fill_picker.color
	if _stroke_picker: dp.stroke_color = _stroke_picker.color
	if _text_picker: dp.text_color = _text_picker.color
	if _text_size_spin: dp.text_size = int(_text_size_spin.value)
