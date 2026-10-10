# =============================================================================
# VECTOPEN — PROFESSIONAL TOP BAR
# RUTA: res://script_gdscript/ui/pro/pro_top_bar.gd
# Compact full-width context toolbar for Professional mode. Occupies the strip
# above the docked Layers panel and Studio so it uses the same panel color
# instead of leaving the window background exposed.
# =============================================================================
class_name ProTopBar
extends PanelContainer

const BAR_HEIGHT := 30.0

var _row: HBoxContainer
var _selection_buttons: Array[Button] = []
var _multi_buttons: Array[Button] = []
var _btn_undo: Button
var _btn_redo: Button
var _lbl_selection: Label
var _mode_selector: Control

func _ready() -> void:
	name = "ProTopBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 0.0
	offset_bottom = BAR_HEIGHT
	_build()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m): _build())
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("selection_size_changed"):
		ic.selection_size_changed.connect(_on_selection_size_changed)
	var hm := get_node_or_null("/root/HistoryManager")
	if hm and hm.has_signal("history_changed"):
		hm.history_changed.connect(func(cu: bool, cr: bool, _u: String, _r: String): _update_history(cu, cr))

func _build() -> void:
	add_theme_stylebox_override("panel", _bar_style())
	if is_instance_valid(_row):
		# The mode selector is kept alive across rebuilds (it restyles itself).
		if is_instance_valid(_mode_selector) and _mode_selector.get_parent() == _row:
			_row.remove_child(_mode_selector)
		_row.visible = false
		_row.queue_free()
	_selection_buttons.clear()
	_multi_buttons.clear()

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_row)

	var brand := ProUIStyle.label("VECTOPEN", true, ProUIStyle.FONT_SIZE_SMALL)
	brand.custom_minimum_size.x = 64
	_row.add_child(brand)
	_row.add_child(ProUIStyle.vsep())

	_btn_undo = _action("↶", "", "Deshacer (Ctrl+Z)", "undo")
	_btn_redo = _action("↷", "", "Rehacer (Ctrl+Y)", "redo")
	for b in [_btn_undo, _btn_redo]:
		b.add_theme_font_size_override("font_size", 14)
	_row.add_child(ProUIStyle.vsep())

	_selection_buttons.append(_action("", "res://icon/UI/align_left_pro.svg", "Alinear a la izquierda", "align_left"))
	_selection_buttons.append(_action("", "res://icon/UI/align_center_h_pro.svg", "Centrar horizontalmente", "align_center_h"))
	_selection_buttons.append(_action("", "res://icon/UI/align_right_pro.svg", "Alinear a la derecha", "align_right"))
	_selection_buttons.append(_action("", "res://icon/UI/align_top_pro.svg", "Alinear arriba", "align_top"))
	_selection_buttons.append(_action("", "res://icon/UI/align_center_v_pro.svg", "Centrar verticalmente", "align_middle"))
	_selection_buttons.append(_action("", "res://icon/UI/align_bottom_pro.svg", "Alinear abajo", "align_bottom"))
	_multi_buttons.append(_action("", "res://icon/UI/distribute_h_pro.svg", "Distribuir horizontalmente", "dist_h"))
	_multi_buttons.append(_action("", "res://icon/UI/distribute_v_pro.svg", "Distribuir verticalmente", "dist_v"))
	_row.add_child(ProUIStyle.vsep())

	_multi_buttons.append(_action("", "res://icon/UI/boolean_union.svg", "Unión Booleana (No destructiva)", "boolean_union"))
	_multi_buttons.append(_action("", "res://icon/UI/boolean_subtract.svg", "Sustracción Booleana (No destructiva)", "boolean_subtract"))
	_multi_buttons.append(_action("", "res://icon/UI/boolean_intersect.svg", "Intersección Booleana (No destructiva)", "boolean_intersect"))
	_multi_buttons.append(_action("", "res://icon/UI/boolean_exclude.svg", "Exclusión Booleana / XOR (No destructiva)", "boolean_exclude"))
	_multi_buttons.append(_action("", "res://icon/UI/shape_builder.svg", "Shape Builder (Smart Fusion)", "shape_builder"))
	_selection_buttons.append(_action("", "res://icon/UI/boolean_flatten.svg", "Aplanar a Curvas Bézier", "boolean_flatten"))
	_selection_buttons.append(_action("", "res://icon/UI/boolean_release.svg", "Liberar Booleano", "boolean_release"))
	_row.add_child(ProUIStyle.vsep())

	_selection_buttons.append(_action("", "res://icon/UI/flip.svg", "Voltear horizontal (Shift+H)", "flip_h"))
	_selection_buttons.append(_action("", "res://icon/UI/flip-reverse.svg", "Voltear vertical (Shift+V)", "flip_v"))
	_row.add_child(ProUIStyle.vsep())

	_selection_buttons.append(_action("", "res://icon/UI/page-up.svg", "Traer al frente (Ctrl+Shift+])", "bring_to_front"))
	_selection_buttons.append(_action("", "res://icon/UI/nav-arrow-up.svg", "Avanzar (Ctrl+])", "bring_forward"))
	_selection_buttons.append(_action("", "res://icon/UI/nav-arrow-down.svg", "Retroceder (Ctrl+[)", "send_backward"))
	_selection_buttons.append(_action("", "res://icon/UI/page-down.svg", "Enviar al fondo (Ctrl+Shift+[)", "send_to_back"))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	_lbl_selection = ProUIStyle.label("", true, ProUIStyle.FONT_SIZE_SMALL)
	_row.add_child(_lbl_selection)
	_row.add_child(ProUIStyle.vsep())

	var btn_settings := ProUIStyle.action_button("", "res://icon/UI/settings.svg", tr("Configuración"))
	btn_settings.custom_minimum_size = Vector2(24, 22)
	btn_settings.pressed.connect(func():
		var ge := get_node_or_null("/root/GlobalEvents")
		if ge and ge.has_signal("request_settings_dialog"):
			ge.emit_safe("request_settings_dialog"))
	_row.add_child(btn_settings)

	if not is_instance_valid(_mode_selector):
		_mode_selector = UIModeSelector.new()
		_mode_selector.compact = true
	_row.add_child(_mode_selector)

	var ic := get_node_or_null("/root/InspectorCore")
	var count: int = ic.selection().size() if ic and ic.has_method("selection") else 0
	_on_selection_size_changed(count)
	var hm := get_node_or_null("/root/HistoryManager")
	_update_history(hm.can_undo() if hm else false, hm.can_redo() if hm else false)

func _bar_style() -> StyleBoxFlat:
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_BG"), 0, Color(0, 0, 0, 0), 8, 3)
	sb.border_color = ProUIStyle.col("BORDER")
	sb.border_width_bottom = 1
	return sb

func _action(text: String, icon_path: String, tooltip: String, action_id: String) -> Button:
	var b := ProUIStyle.action_button(text, icon_path, tr(tooltip))
	b.custom_minimum_size = Vector2(24, 22)
	b.set_meta("action_id", action_id)
	b.pressed.connect(func(): ContextMenuActions.execute(action_id, self))
	_row.add_child(b)
	return b

func _on_selection_size_changed(count: int) -> void:
	for b in _selection_buttons:
		_set_enabled(b, count >= 1)
	for b in _multi_buttons:
		_set_enabled(b, count >= 2)
	if is_instance_valid(_lbl_selection):
		match count:
			0: _lbl_selection.text = tr("Sin selección")
			1: _lbl_selection.text = tr("1 objeto")
			_: _lbl_selection.text = tr("%d objetos") % count

func _update_history(can_undo: bool, can_redo: bool) -> void:
	_set_enabled(_btn_undo, can_undo)
	_set_enabled(_btn_redo, can_redo)

func _set_enabled(b: Button, on: bool) -> void:
	if not is_instance_valid(b):
		return
	b.disabled = not on
	b.modulate.a = 1.0 if on else 0.35

## Buttons bound to an action id, for tests and tooling.
func get_action_button(action_id: String) -> Button:
	if not is_instance_valid(_row):
		return null
	for c in _row.get_children():
		if c is Button and String(c.get_meta("action_id", "")) == action_id:
			return c
	return null
