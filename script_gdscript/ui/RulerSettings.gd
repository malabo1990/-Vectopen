extends BoxContainer

var _check_h: CheckButton
var _check_v: CheckButton
var _check_guides: CheckButton
var _check_snap: CheckButton
var _regla_node: Node
var _color_pickers: Dictionary = {}

const CONFIG_PATH := "user://vectopen_ruler.cfg"

func _ready() -> void:
	_load_checks()
	_add_color_section()
	_add_clear_button()
	_load_config()
	_connect()
	await get_tree().process_frame
	_apply_all()

func _load_checks() -> void:
	for i in get_child_count():
		var row = get_child(i) as HBoxContainer
		if row and row.get_child_count() >= 3:
			var cb = row.get_child(2)
			if cb is CheckButton:
				match i:
					0: _check_h = cb
					1: _check_v = cb
					2: _check_guides = cb
					3: _check_snap = cb

func _add_color_section() -> void:
	var header := Label.new()
	header.text = "Colores de guía"
	header.custom_minimum_size = Vector2(0, 28)
	add_child(header)

	var colors := {
		"color_guia_normal": "Guía normal",
		"color_guia_seleccionada": "Guía seleccionada",
		"color_guia_previsualizacion": "Previsualización",
		"color_flash_crear": "Flash crear",
		"color_flash_eliminar": "Flash eliminar",
	}
	for prop in colors:
		_add_color_row(prop, colors[prop])

func _add_color_row(prop_name: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 28)
	add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.add_child(lbl)

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(24, 24)
	picker.color = Color.WHITE
	picker.color_changed.connect(_on_color_changed.bind(prop_name, picker))
	row.add_child(picker)

	var reset := Button.new()
	reset.text = "↺"
	reset.custom_minimum_size = Vector2(24, 24)
	reset.pressed.connect(_on_reset_color.bind(prop_name, picker))
	row.add_child(reset)

	_color_pickers[prop_name] = picker

func _add_clear_button() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	add_child(row)

	var lbl := Label.new()
	lbl.text = "Limpiar guías"
	lbl.size_flags_horizontal = SIZE_EXPAND | SIZE_FILL
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = "×"
	btn.custom_minimum_size = Vector2(32, 24)
	btn.pressed.connect(_on_clear_guides)
	row.add_child(btn)

func _find_regla() -> Node:
	if _regla_node and is_instance_valid(_regla_node):
		return _regla_node
	var scene := get_tree().current_scene
	if scene:
		_regla_node = scene.find_child("windows_ recla", true, false)
	if not _regla_node:
		_regla_node = get_tree().root.find_child("windows_ recla", true, false)
	return _regla_node

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK: return
	if _check_h: _check_h.button_pressed = cfg.get_value("ruler", "show_h", true)
	if _check_v: _check_v.button_pressed = cfg.get_value("ruler", "show_v", true)
	if _check_guides: _check_guides.button_pressed = cfg.get_value("ruler", "show_guides", true)
	if _check_snap: _check_snap.button_pressed = cfg.get_value("ruler", "snap_guides", false)
	for prop in _color_pickers:
		var saved = cfg.get_value("colors", prop, null)
		if saved != null:
			_color_pickers[prop].color = saved
	_apply_colors()

func _save_config() -> void:
	var cfg := ConfigFile.new()
	if _check_h: cfg.set_value("ruler", "show_h", _check_h.button_pressed)
	if _check_v: cfg.set_value("ruler", "show_v", _check_v.button_pressed)
	if _check_guides: cfg.set_value("ruler", "show_guides", _check_guides.button_pressed)
	if _check_snap: cfg.set_value("ruler", "snap_guides", _check_snap.button_pressed)
	for prop in _color_pickers:
		cfg.set_value("colors", prop, _color_pickers[prop].color)
	cfg.save(CONFIG_PATH)

func _connect() -> void:
	if _check_h: _check_h.toggled.connect(_on_changed)
	if _check_v: _check_v.toggled.connect(_on_changed)
	if _check_guides: _check_guides.toggled.connect(_on_guides_changed)
	if _check_snap: _check_snap.toggled.connect(_on_changed)

func _on_changed(_t: bool) -> void:
	_apply_all()
	_save_config()

func _on_guides_changed(toggled: bool) -> void:
	var regla = _find_regla()
	if regla and regla.has_method("toggle_guides_visible"):
		regla.toggle_guides_visible(toggled)
	_save_config()

func _on_color_changed(color: Color, prop_name: String, _picker: ColorPickerButton) -> void:
	var regla = _find_regla()
	if regla:
		regla.set(prop_name, color)
	_save_config()

func _on_reset_color(prop_name: String, picker: ColorPickerButton) -> void:
	var defaults := {
		"color_guia_normal": Color(0, 0.7, 0.9, 0.4),
		"color_guia_seleccionada": Color(0, 0.9, 1, 0.8),
		"color_guia_previsualizacion": Color(1, 0.6, 0, 0.8),
		"color_flash_crear": Color(0, 1, 0, 0.3),
		"color_flash_eliminar": Color(1, 0, 0, 0.3),
	}
	var def = defaults.get(prop_name, Color.WHITE)
	picker.color = def
	var regla = _find_regla()
	if regla:
		regla.set(prop_name, def)
	_save_config()

func _on_clear_guides() -> void:
	var regla = _find_regla()
	if regla and regla.has_method("clear_all_guides"):
		regla.clear_all_guides()

func _apply_all() -> void:
	var regla = _find_regla()
	if not regla: return
	if regla.has_method("set_ruler_h_visible") and _check_h:
		regla.set_ruler_h_visible(_check_h.button_pressed)
	if regla.has_method("set_ruler_v_visible") and _check_v:
		regla.set_ruler_v_visible(_check_v.button_pressed)
	_apply_colors()

func _apply_colors() -> void:
	var regla = _find_regla()
	if not regla: return
	for prop in _color_pickers:
		regla.set(prop, _color_pickers[prop].color)
