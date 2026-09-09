@tool
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

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	_find_nodes()
	_load_draw_prefs()
	_populate_language()
	_populate_ui_colors()
	_populate_mcp_section()
	_connect_signals()

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
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm: return
	for slot in tm.get_all_slots():
		var slot_name = tm.get_slot_name(slot).replace("_", " ").capitalize()
		var color = tm.get_color(slot)

		var row := HBoxContainer.new()
		_ui_colors.add_child(row)

		var lbl := Label.new()
		lbl.text = slot_name
		lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
		row.add_child(lbl)

		var picker := ColorPickerButton.new()
		picker.color = color
		picker.custom_minimum_size = Vector2(18, 18)
		picker.theme_type_variation = "FlatButton"
		picker.color_changed.connect(func(c): tm.set_custom_color(slot, c))
		row.add_child(picker)

## Sección "Integraciones IA (MCP)": checkbox que enciende/apaga el
## servidor MCP embebido (VectopenMCPServer) que deja a un agente de IA
## consultar/controlar el lienzo en vivo (HTTP+JSON-RPC, solo 127.0.0.1).
func _populate_mcp_section() -> void:
	if not _slot_container:
		return
	var srv = get_node_or_null("/root/VectopenMCPServer")
	if not srv:
		return

	_slot_container.add_child(HSeparator.new())

	var sec := Label.new()
	sec.text = "Integraciones IA (MCP)"
	sec.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1))
	_slot_container.add_child(sec)

	var row := HBoxContainer.new()
	_slot_container.add_child(row)
	var lbl := Label.new()
	lbl.text = "Servidor MCP"
	lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	row.add_child(lbl)
	_mcp_check = CheckBox.new()
	_mcp_check.button_pressed = srv.is_enabled()
	_mcp_check.toggled.connect(_on_mcp_toggled)
	row.add_child(_mcp_check)

	var token_row := HBoxContainer.new()
	_slot_container.add_child(token_row)
	var token_lbl := Label.new()
	token_lbl.text = "Token"
	token_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	token_row.add_child(token_lbl)
	_mcp_token_field = LineEdit.new()
	_mcp_token_field.text = srv.get_token()
	_mcp_token_field.editable = true
	_mcp_token_field.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	_mcp_token_field.add_theme_font_size_override("font_size", 10)
	token_row.add_child(_mcp_token_field)
	var regen_btn := Button.new()
	regen_btn.text = "Regenerar"
	regen_btn.tooltip_text = "Invalida el token actual. Cualquier cliente MCP ya conectado dejará de funcionar hasta que uses el nuevo."
	regen_btn.pressed.connect(_on_regen_token_pressed)
	token_row.add_child(regen_btn)

	_mcp_status = Label.new()
	_mcp_status.add_theme_font_size_override("font_size", 10)
	_mcp_status.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 1))
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
		_mcp_status.text = "Escuchando en http://127.0.0.1:%d/mcp (solo este equipo). Requiere el token de arriba en la cabecera Authorization: Bearer <token>." % srv.get_port()
	else:
		_mcp_status.text = "Desactivado. Al activarlo, un agente de IA podrá leer y editar el lienzo (crear/editar/borrar figuras, deshacer/rehacer, exportar) vía MCP."

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

func _on_fill_changed(_c) -> void: _save_prefs()
func _on_stroke_changed(_c) -> void: _save_prefs()
func _on_text_color_changed(_c) -> void: _save_prefs()
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
		for c in _ui_colors.get_children():
			c.queue_free()
		_populate_ui_colors()

func _save_prefs() -> void:
	var dp = get_node_or_null("/root/DrawPreferences")
	if not dp: return
	if _fill_picker: dp.fill_color = _fill_picker.color
	if _stroke_picker: dp.stroke_color = _stroke_picker.color
	if _text_picker: dp.text_color = _text_picker.color
	if _text_size_spin: dp.text_size = int(_text_size_spin.value)
