extends BoxContainer

# Rows detectadas automáticamente por índice en _setup_refs()
var _check_windowed: CheckButton
var _check_fullscreen: CheckButton
var _check_borderless: CheckButton
var _check_maximize: CheckButton
var _check_desktop_res: CheckButton
var _spin_width: SpinBox
var _spin_height: SpinBox

const CONFIG_PATH := "user://vectopen_window.cfg"

func _ready() -> void:
	_setup_refs()
	_setup_spinboxes()
	_load_config()
	_connect_signals()
	_update_mode_checkboxes()

func _setup_refs() -> void:
	for i in get_child_count():
		var row = get_child(i) as HBoxContainer
		if not row or row.get_child_count() < 3: continue
		var cb = row.get_child(2) as CheckButton
		if not cb: continue
		match i:
			0: _check_windowed = cb
			1: _check_fullscreen = cb
			2: _check_borderless = cb
			3: _check_maximize = cb
			6: _check_desktop_res = cb  # BoxContainer8

func _setup_spinboxes() -> void:
	if get_child_count() > 8:
		var row = get_child(8) as HBoxContainer  # BoxContainer10
		if row and row.get_child_count() >= 3:
			_spin_width = row.get_child(1) as SpinBox if row.get_child(1) is SpinBox else null
			_spin_height = row.get_child(2) as SpinBox if row.get_child(2) is SpinBox else null

func _connect_signals() -> void:
	for check in [_check_windowed, _check_fullscreen, _check_borderless]:
		if check: check.toggled.connect(_on_mode_changed)
	if _check_maximize: _check_maximize.toggled.connect(_on_maximize)
	if _check_desktop_res: _check_desktop_res.toggled.connect(_on_desktop_res)
	if _spin_width: _spin_width.value_changed.connect(_on_resolution_changed)
	if _spin_height: _spin_height.value_changed.connect(_on_resolution_changed)

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK: return
	if _check_maximize: _check_maximize.button_pressed = cfg.get_value("window", "maximize", false)
	if _check_windowed: _check_windowed.button_pressed = cfg.get_value("window", "windowed", true)
	if _check_fullscreen: _check_fullscreen.button_pressed = cfg.get_value("window", "fullscreen", false)
	if _check_borderless: _check_borderless.button_pressed = cfg.get_value("window", "borderless", false)
	if _check_desktop_res: _check_desktop_res.button_pressed = cfg.get_value("window", "desktop_res", true)
	_apply_loaded_mode()

func _save_config() -> void:
	var cfg := ConfigFile.new()
	if _check_maximize: cfg.set_value("window", "maximize", _check_maximize.button_pressed)
	if _check_windowed: cfg.set_value("window", "windowed", _check_windowed.button_pressed)
	if _check_fullscreen: cfg.set_value("window", "fullscreen", _check_fullscreen.button_pressed)
	if _check_borderless: cfg.set_value("window", "borderless", _check_borderless.button_pressed)
	if _check_desktop_res: cfg.set_value("window", "desktop_res", _check_desktop_res.button_pressed)
	cfg.save(CONFIG_PATH)

func _on_mode_changed(_toggled: bool) -> void:
	_update_mode_checkboxes()
	_apply_window_mode()
	_save_config()

func _update_mode_checkboxes() -> void:
	var id = _get_active_mode_index()
	for i in [0, 1, 2]:
		var checks = [_check_windowed, _check_fullscreen, _check_borderless]
		if checks[i]: checks[i].set_block_signals(true)

	if _check_windowed: _check_windowed.button_pressed = (id == 0)
	if _check_fullscreen: _check_fullscreen.button_pressed = (id == 1)
	if _check_borderless: _check_borderless.button_pressed = (id == 2)

	for i in [0, 1, 2]:
		var checks = [_check_windowed, _check_fullscreen, _check_borderless]
		if checks[i]: checks[i].set_block_signals(false)

func _get_active_mode_index() -> int:
	if _check_windowed and _check_windowed.button_pressed: return 0
	if _check_fullscreen and _check_fullscreen.button_pressed: return 1
	if _check_borderless and _check_borderless.button_pressed: return 2
	return 0

func _apply_window_mode() -> void:
	var mode = _get_active_mode_index()
	match mode:
		0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _apply_loaded_mode() -> void:
	if _check_fullscreen.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif _check_borderless.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _on_maximize(toggled: bool) -> void:
	ProjectSettings.set_setting("display/window/size/mode", 2 if toggled else 0)
	_save_config()

func _on_desktop_res(toggled: bool) -> void:
	if toggled:
		var screen = DisplayServer.screen_get_size()
		DisplayServer.window_set_size(screen)
		if _spin_width: _spin_width.editable = false
		if _spin_height: _spin_height.editable = false
	else:
		if _spin_width: _spin_width.editable = true
		if _spin_height: _spin_height.editable = true
		_on_resolution_changed(0)
	_save_config()

func _on_resolution_changed(_val: float) -> void:
	if _check_desktop_res and _check_desktop_res.button_pressed: return
	var w = int(_spin_width.value) if _spin_width else 1920
	var h = int(_spin_height.value) if _spin_height else 1080
	if w > 0 and h > 0:
		DisplayServer.window_set_size(Vector2i(w, h))
