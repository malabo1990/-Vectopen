extends Control
class_name SpinBoxValue

## Widget numérico reutilizable (spin_box.tscn).
## Salida:  value_changed(value) - se emite ante cualquier cambio de valor
##          (botones < >, arrastre vertical o set_value).
## Entrada: set_value(v) o la propiedad exportada `value` (inspector/código).
## Config:  min_value, max_value, step, sensitivity - exportadas y
##          sincronizadas con el ControlVertical interno.

signal value_changed(value: float)

@export_range(-1000000.0, 1000000.0, 0.01) var min_value: float = 0.0:
	set(v):
		min_value = v
		if _progress_bar:
			_progress_bar.min_value = v
		if _control_vertical:
			_control_vertical.valor_minimo = v

@export_range(-1000000.0, 1000000.0, 0.01) var max_value: float = 100.0:
	set(v):
		max_value = v
		if _progress_bar:
			_progress_bar.max_value = v
		if _control_vertical:
			_control_vertical.valor_maximo = v

@export_range(0.001, 100000.0, 0.001) var step: float = 1.0:
	set(v):
		step = v
		if _control_vertical:
			_control_vertical.paso_incremento = v

@export_range(0.01, 10.0, 0.01) var sensitivity: float = 0.5:
	set(v):
		sensitivity = v
		if _control_vertical:
			_control_vertical.sensibilidad_drag = v

@export var suffix: String = "px":
	set(v):
		suffix = v
		_update_display()

@export var value: float = 0.0:
	set(v):
		value = clampf(v, min_value, max_value)
		if _progress_bar:
			_progress_bar.value = value
		_update_display()

@onready var _progress_bar: ProgressBar = $BoxContainer/ProgressBar
@onready var _control_vertical: ControlVertical = $BoxContainer/Button
var _val_label: Label = null
var _compact: bool = false

func set_compact(is_compact: bool) -> void:
	_compact = is_compact
	_apply_compact()

func _apply_compact() -> void:
	var b_res := get_node_or_null("BoxContainer/Button3") as Control
	var b_calc := get_node_or_null("BoxContainer/Button4") as Control
	if b_res:
		b_res.visible = not _compact
	if b_calc:
		b_calc.visible = not _compact

func _ready() -> void:
	_apply_compact()
	var bc := get_node_or_null("BoxContainer") as Control
	if bc:
		bc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.min_value = min_value
	_progress_bar.max_value = max_value
	_progress_bar.value = value
	_progress_bar.show_percentage = false
	_control_vertical.valor_minimo = min_value
	_control_vertical.valor_maximo = max_value
	_control_vertical.paso_incremento = step
	_control_vertical.sensibilidad_drag = sensitivity
	_progress_bar.value_changed.connect(_on_progress_changed)
	_ensure_value_label()
	_update_display()
	_conectar_tema()
	_aplicar_tema()

func _ensure_value_label() -> void:
	if _val_label == null and _progress_bar:
		_val_label = _progress_bar.get_node_or_null("ValueLabel") as Label
		if _val_label == null:
			_val_label = Label.new()
			_val_label.name = "ValueLabel"
			_val_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_val_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_val_label.add_theme_font_size_override("font_size", 10)
			_progress_bar.add_child(_val_label)

func _update_display() -> void:
	_ensure_value_label()
	if _val_label:
		var rounded: float = roundf(value * 100.0) / 100.0
		var s: String
		if is_equal_approx(rounded, roundf(rounded)):
			s = "%d" % int(rounded)
		else:
			s = "%.1f" % rounded
		if suffix.is_empty():
			_val_label.text = s
		elif suffix == "°":
			_val_label.text = "%s°" % s
		else:
			_val_label.text = "%s %s" % [s, suffix]

func _conectar_tema() -> void:
	if not is_inside_tree():
		return
	var tm = get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		if tm.has_signal("color_slot_changed") and not tm.color_slot_changed.is_connected(_on_color_slot_changed):
			tm.color_slot_changed.connect(_on_color_slot_changed)

func _on_theme_changed(_mode: String) -> void:
	_aplicar_tema()

func _on_color_slot_changed(_slot: String, _col: Color) -> void:
	_aplicar_tema()

func _aplicar_tema() -> void:
	if not is_inside_tree():
		return
	var tm = get_node_or_null("/root/ThemeManager")
	if not tm:
		return
	var S = tm.Slot
	var btn_bg: Color = tm.get_color(S.BUTTON_BG)
	var btn_hov: Color = tm.get_color(S.BUTTON_HOVER)
	var border_col: Color = tm.get_color(S.BORDER)
	var text_col: Color = tm.get_color(S.PANEL_TEXT)
	var input_bg: Color = tm.get_color(S.INPUT_BG)
	var input_border: Color = tm.get_color(S.INPUT_BORDER)
	var accent_soft: Color = tm.get_color(S.ACCENT_SOFT)
	var accent: Color = tm.get_color(S.ACCENT)
	var icon_primary: Color = tm.get_color(S.ICON_PRIMARY)
	var surface_col: Color = tm.get_color(S.PANEL_SURFACE)

	# 1. Botón < (reducir)
	var btn_dec := get_node_or_null("BoxContainer/Button") as Button
	if btn_dec:
		var sb_dec := StyleBoxFlat.new()
		sb_dec.bg_color = btn_bg
		sb_dec.border_color = border_col
		sb_dec.border_width_left = 1
		sb_dec.border_width_top = 1
		sb_dec.border_width_bottom = 1
		sb_dec.corner_radius_top_left = 5
		sb_dec.corner_radius_bottom_left = 5
		sb_dec.content_margin_left = 2
		sb_dec.content_margin_right = 2
		btn_dec.add_theme_stylebox_override("normal", sb_dec)
		var sb_dec_h := sb_dec.duplicate() as StyleBoxFlat
		sb_dec_h.bg_color = btn_hov
		btn_dec.add_theme_stylebox_override("hover", sb_dec_h)
		btn_dec.add_theme_color_override("font_color", text_col)

	# 2. Botón > (aumentar)
	var btn_inc := get_node_or_null("BoxContainer/Button2") as Button
	if btn_inc:
		var sb_inc := StyleBoxFlat.new()
		sb_inc.bg_color = btn_bg
		sb_inc.border_color = border_col
		sb_inc.border_width_right = 1
		sb_inc.border_width_top = 1
		sb_inc.border_width_bottom = 1
		sb_inc.corner_radius_top_right = 5
		sb_inc.corner_radius_bottom_right = 5
		sb_inc.content_margin_left = 2
		sb_inc.content_margin_right = 2
		btn_inc.add_theme_stylebox_override("normal", sb_inc)
		var sb_inc_h := sb_inc.duplicate() as StyleBoxFlat
		sb_inc_h.bg_color = btn_hov
		btn_inc.add_theme_stylebox_override("hover", sb_inc_h)
		btn_inc.add_theme_color_override("font_color", text_col)

	# 3. ProgressBar
	if _progress_bar:
		var pb_bg := StyleBoxFlat.new()
		pb_bg.bg_color = input_bg
		pb_bg.border_color = input_border
		pb_bg.border_width_top = 1
		pb_bg.border_width_bottom = 1
		_progress_bar.add_theme_stylebox_override("background", pb_bg)
		var pb_fill := StyleBoxFlat.new()
		pb_fill.bg_color = accent_soft
		pb_fill.border_color = accent
		pb_fill.border_width_top = 1
		pb_fill.border_width_bottom = 1
		_progress_bar.add_theme_stylebox_override("fill", pb_fill)
		_progress_bar.add_theme_color_override("font_color", text_col)

	# 4. Botón reset (Button3) y calculadora (Button4)
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = btn_bg
	chip_sb.border_color = border_col
	chip_sb.set_border_width_all(1)
	chip_sb.set_corner_radius_all(5)
	chip_sb.content_margin_left = 2
	chip_sb.content_margin_right = 2

	var chip_hov := chip_sb.duplicate() as StyleBoxFlat
	chip_hov.bg_color = btn_hov

	for btn_name in ["BoxContainer/Button3", "BoxContainer/Button4"]:
		var b := get_node_or_null(btn_name) as Button
		if b:
			b.add_theme_stylebox_override("normal", chip_sb)
			b.add_theme_stylebox_override("hover", chip_hov)
			b.add_theme_stylebox_override("pressed", chip_sb)
			if b.icon and tm.has_method("make_white_icon"):
				b.icon = tm.make_white_icon(b.icon, 14)
			b.modulate = Color.WHITE
			b.add_theme_color_override("icon_normal_color", icon_primary)
			b.add_theme_color_override("icon_hover_color", text_col)

	# 5. Popup calculadora
	var calc_pop := get_node_or_null("BoxContainer/Button4/PanelContainer") as PanelContainer
	if calc_pop:
		var psb := StyleBoxFlat.new()
		psb.bg_color = surface_col
		psb.border_color = border_col
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(8)
		psb.shadow_size = 8
		psb.shadow_color = Color(0, 0, 0, 0.3 if tm.is_dark() else 0.1)
		calc_pop.add_theme_stylebox_override("panel", psb)

	if _val_label:
		_val_label.add_theme_color_override("font_color", text_col)

func _on_progress_changed(new_value: float) -> void:
	value = new_value
	_update_display()
	value_changed.emit(new_value)

func get_value() -> float:
	return _progress_bar.value if _progress_bar else value

func set_value(new_value: float) -> void:
	value = new_value

func set_value_no_signal(new_value: float) -> void:
	if _progress_bar:
		var was_blocked: bool = _progress_bar.is_blocking_signals()
		_progress_bar.set_block_signals(true)
		value = new_value
		_progress_bar.set_block_signals(was_blocked)
	else:
		value = new_value
