extends PanelContainer

@export var tab_container: VBoxContainer
@export var content_container: VBoxContainer

var _current_tab: String = "windows"
var _tab_buttons: Dictionary = {}

const TABS := ["windows", "rulers", "theme", "snap", "language"]

func _ready() -> void:
	_build_tabs()

func _build_tabs() -> void:
	if not tab_container:
		return
	for c in tab_container.get_children():
		c.queue_free()

	var tab_row := HBoxContainer.new()
	tab_container.add_child(tab_row)

	for tab in TABS:
		var btn := Button.new()
		btn.text = tr(tab.capitalize())
		btn.toggle_mode = true
		btn.button_pressed = tab == _current_tab
		btn.toggled.connect(_on_tab_selected.bind(tab, btn))
		tab_row.add_child(btn)
		_tab_buttons[tab] = btn

	_show_tab(_current_tab)

func _on_tab_selected(_pressed: bool, tab: String, btn: Button) -> void:
	if not btn.button_pressed:
		btn.button_pressed = true
		return
	_current_tab = tab
	for t in _tab_buttons:
		_tab_buttons[t].button_pressed = t == tab
	_show_tab(tab)

func _show_tab(tab: String) -> void:
	if not content_container:
		return
	for c in content_container.get_children():
		c.queue_free()

	match tab:
		"windows":
			_build_windows_tab(content_container)
		"rulers":
			_build_rulers_tab(content_container)
		"theme":
			_build_theme_link(content_container)
		"snap":
			_build_snap_tab(content_container)
		"language":
			_build_language_tab(content_container)

func _add_check_row(parent: Node, label: String, checked: bool) -> CheckButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = checked
	row.add_child(check)
	return check

func _build_windows_tab(parent: VBoxContainer) -> void:
	var items := [
		"Windowed", "Fullscreen", "Borderless",
		"Maximize on Start", "Resolution / Window Size",
	]
	for item in items:
		_add_check_row(parent, tr(item), false)

func _build_rulers_tab(parent: VBoxContainer) -> void:
	for i in range(4):
		_add_check_row(parent, tr("Enabled") + " " + str(i + 1), true)

func _build_theme_link(parent: VBoxContainer) -> void:
	var theme_instance := get_node_or_null("../tema")
	if theme_instance:
		theme_instance.get_parent().remove_child(theme_instance)
		parent.add_child(theme_instance)
		theme_instance.visible = true

func _build_snap_tab(parent: VBoxContainer) -> void:
	var enabled := _add_check_row(parent, tr("Grid Snap"), true)

	var size_row := HBoxContainer.new()
	parent.add_child(size_row)
	var size_lbl := Label.new()
	size_lbl.text = tr("Grid Size")
	size_lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	size_row.add_child(size_lbl)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 100
	spin.value = 10
	size_row.add_child(spin)

	var sm := get_node_or_null("/root/SnapManager")
	if sm:
		enabled.button_pressed = sm.grid_enabled
		spin.value = sm.grid_size
		enabled.toggled.connect(func(v): sm.set_grid_enabled(v))
		spin.value_changed.connect(func(v): sm.set_grid_size(v))

func _build_language_tab(parent: VBoxContainer) -> void:
	var lm := get_node_or_null("/root/LanguageManager")
	if not lm:
		return
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = tr("Language") + ":"
	lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.add_child(lbl)
	var option := OptionButton.new()
	option.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	for locale in lm.get_locale_list():
		option.add_item(lm.get_locale_name(locale))
		if locale == lm.current_locale:
			option.select(option.item_count - 1)
	option.item_selected.connect(_on_lang_selected.bind(option, lm))
	row.add_child(option)

func _on_lang_selected(index: int, option: OptionButton, lm: Node) -> void:
	var locales = lm.get_locale_list()
	if index >= 0 and index < locales.size():
		lm.set_locale(locales[index])
