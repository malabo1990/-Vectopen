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

func _ready() -> void:
	_load_checks()
	_connect()

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
