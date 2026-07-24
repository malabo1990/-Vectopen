@tool
extends PanelContainer

var _fill_picker: ColorPickerButton
var _stroke_picker: ColorPickerButton
var _text_picker: ColorPickerButton
var _text_size_spin: SpinBox
var _lang_option: OptionButton
var _ui_colors: VBoxContainer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	_find_nodes()
	_load_draw_prefs()
	_populate_language()
	_populate_ui_colors()
	_connect_signals()

func _load_draw_prefs() -> void:
	var dp = get_node_or_null("/root/DrawPreferences")
	if not dp: return
	if _fill_picker: _fill_picker.color = dp.fill_color
	if _stroke_picker: _stroke_picker.color = dp.stroke_color
	if _text_picker: _text_picker.color = dp.text_color
	if _text_size_spin: _text_size_spin.value = dp.text_size

func _find_nodes() -> void:
	_fill_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/RowFill/PickFill")
	_stroke_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/RowStroke/PickStroke")
	_text_picker = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/RowTextColor/PickTextColor")
	_text_size_spin = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/RowTextSize/SpinTextSize")
	_lang_option = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/RowLang/OptLang")
	_ui_colors = _get_node("MarginContainer/VBoxContainer/ScrollContainer/SlotContainer/UIColors")

func _get_node(node_path: String):
	var n = get_node_or_null(node_path)
	if n is ColorPickerButton: return n as ColorPickerButton
	if n is SpinBox: return n as SpinBox
	if n is OptionButton: return n as OptionButton
	if n is VBoxContainer: return n as VBoxContainer
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
		row.add_child(lbl)

		var picker := ColorPickerButton.new()
		picker.color = color
		picker.custom_minimum_size = Vector2(18, 18)
		picker.color_changed.connect(func(c): tm.set_custom_color(slot, c))
		row.add_child(picker)

func _connect_signals() -> void:
	if _fill_picker: _fill_picker.color_changed.connect(func(_c): _save_prefs())
	if _stroke_picker: _stroke_picker.color_changed.connect(func(_c): _save_prefs())
	if _text_picker: _text_picker.color_changed.connect(func(_c): _save_prefs())
	if _text_size_spin: _text_size_spin.value_changed.connect(func(_v): _save_prefs())

func _on_lang_selected(idx: int, lm: Node) -> void:
	var locales = lm.get_locale_list()
	if idx >= 0 and idx < locales.size():
		lm.set_locale(locales[idx])

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
