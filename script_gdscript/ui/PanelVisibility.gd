extends BoxContainer

# Cada fila: Label + VSeparator + CheckButton
# conectada por índices en _load_checks()

var _panels: Dictionary = {}

const PANEL_LIST := [
	["panel__effects", "Efectos"],
	["Panel_PREVIEW", "Vista previa"],
	["pickr_color_windows", "Selector color"],
	["Panel_manager", "Exportar"],
	["PanelContainer2", "Panel numérico"],
]

var _note: Label = null

func _ready() -> void:
	_load_checks()
	_connect()
	# Estos paneles flotantes son de Smart: en Modern y Pro todo está en el
	# panel derecho, así que aquí no se ofrecen (antes se podía encender el
	# selector de color de Smart en Pro y salía tapado por la regla).
	var gui := get_node_or_null("/root/GlobalUI")
	if gui and gui.has_signal("ui_mode_changed"):
		gui.ui_mode_changed.connect(func(_m: String) -> void: _sync_mode())
	visibility_changed.connect(_sync_mode)
	_sync_mode()

func _sync_mode() -> void:
	var gui := get_node_or_null("/root/GlobalUI")
	var smart: bool = gui == null or not gui.has_method("get_ui_mode") or gui.get_ui_mode() == "smart"
	for i in get_child_count():
		var row := get_child(i) as Control
		if row and row != _note and i < PANEL_LIST.size():
			row.visible = smart
	if not smart and _note == null:
		_note = Label.new()
		_note.name = "OnlySmartNote"
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.add_theme_font_size_override("font_size", 11)
		add_child(_note)
	if _note:
		_note.text = tr("Estos paneles flotantes son del modo Smart. En Modern y Pro todo está en el panel derecho.")
		_note.visible = not smart
		_note.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
	if smart:
		_scan_panels()

func _load_checks() -> void:
	for i in get_child_count():
		var row = get_child(i) as HBoxContainer
		if row and row.get_child_count() >= 3:
			var cb = row.get_child(2) as CheckButton
			if not cb: continue
			if i < PANEL_LIST.size():
				_panels[PANEL_LIST[i][0]] = {"check": cb, "label": PANEL_LIST[i][1]}
	_scan_panels()

func _scan_panels() -> void:
	var root = get_tree().root if get_tree() else null
	if not root: return
	for panel_name in _panels:
		var node = root.find_child(panel_name, true, false)
		if node:
			_panels[panel_name]["node"] = node
			_panels[panel_name]["check"].button_pressed = node.visible

func _connect() -> void:
	for panel_name in _panels:
		_panels[panel_name]["check"].toggled.connect(_on_toggle.bind(panel_name))

func _on_toggle(toggled: bool, panel_name: String) -> void:
	if _panels.has(panel_name) and _panels[panel_name].has("node"):
		_panels[panel_name]["node"].visible = toggled
