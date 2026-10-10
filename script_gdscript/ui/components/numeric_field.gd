# =============================================================================
# VECTOPEN — COMPONENTE NUMERIC FIELD (DESIGN SYSTEM)
# RUTA: res://script_gdscript/ui/components/numeric_field.gd
# Reemplazo moderno del SpinBox para Smart, Modern y Professional UI
# Soporta:
#   - Arrastre horizontal interactivo (scrubbing) con CURSOR_HSIZE
#   - Modificadores: Shift (precisión 0.1×) / Ctrl/Cmd (incremento rápido 5.0×)
#   - Rueda de ratón (wheel)
#   - Doble clic para seleccionar todo / Clic para editar
#   - Confirmación con Enter / Cancelación con Escape
#   - Evaluación de fórmulas matemáticas (+10, -5, *2, /2, etc.)
#   - Tokens semánticos reactivos a ThemeManager (INPUT_BG, INPUT_BORDER, ACCENT)
# =============================================================================
class_name NumericField
extends PanelContainer

signal value_changed(v: float)
signal drag_started()
signal drag_ended()
signal submitted(v: float)

@export var value: float = 0.0:
	set(v):
		var clamped := clampf(v, min_value, max_value)
		if not is_equal_approx(value, clamped):
			value = clamped
			_refresh_display()

@export var min_value: float = -999999.0
@export var max_value: float = 999999.0
@export var step: float = 1.0
@export var decimals: int = 2
@export var prefix: String = ""
@export var suffix: String = ""
@export var enabled: bool = true:
	set(v):
		enabled = v
		mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if is_instance_valid(_line_edit):
			_line_edit.editable = enabled
		_update_theme_styles()

var _is_editing: bool = false
var _is_dragging: bool = false
var _drag_start_mouse_x: float = 0.0
var _drag_start_val: float = 0.0
var _pre_edit_val: float = 0.0

var _box: HBoxContainer
var _lbl_prefix: Label
var _line_edit: LineEdit
var _lbl_suffix: Label

func _init(p_prefix: String = "", p_suffix: String = "", p_min: float = -999999.0, p_max: float = 999999.0, p_step: float = 1.0) -> void:
	prefix = p_prefix
	suffix = p_suffix
	min_value = p_min
	max_value = p_max
	step = p_step
	custom_minimum_size = Vector2(0, 26)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	focus_mode = Control.FOCUS_NONE

func _ready() -> void:
	_build_ui()
	_update_theme_styles()
	_refresh_display()

	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(_on_theme_changed)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_box)

	_lbl_prefix = Label.new()
	_lbl_prefix.text = prefix
	_lbl_prefix.visible = not prefix.is_empty()
	_lbl_prefix.add_theme_font_size_override("font_size", 10)
	_lbl_prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_prefix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_lbl_prefix)

	_line_edit = LineEdit.new()
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT if not prefix.is_empty() else HORIZONTAL_ALIGNMENT_CENTER
	_line_edit.add_theme_font_size_override("font_size", 11)
	_line_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_line_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_line_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_edit.text_submitted.connect(_on_line_edit_submitted)
	_line_edit.focus_exited.connect(_on_line_edit_focus_exited)
	_box.add_child(_line_edit)

	_lbl_suffix = Label.new()
	_lbl_suffix.text = suffix
	_lbl_suffix.visible = not suffix.is_empty()
	_lbl_suffix.add_theme_font_size_override("font_size", 10)
	_lbl_suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_suffix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_lbl_suffix)

func _on_theme_changed(_mode: String) -> void:
	_update_theme_styles()

func _update_theme_styles(is_hover: bool = false, is_focus: bool = false) -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var bg_col := Color(0.12, 0.12, 0.12, 1.0)
	var border_col := Color(0.3, 0.3, 0.3, 1.0)
	var text_col := Color(0.9, 0.9, 0.9, 1.0)
	var muted_col := Color(0.55, 0.55, 0.55, 1.0)
	var accent_col := Color(0.04, 0.52, 1.0, 1.0)

	if tm:
		var S = tm.Slot
		if is_focus:
			bg_col = tm.get_color(S.INPUT_FOCUS) if "INPUT_FOCUS" in S else tm.get_color(S.INPUT_BG)
			border_col = tm.get_color(S.ACCENT)
		elif is_hover:
			bg_col = tm.get_color(S.INPUT_HOVER) if "INPUT_HOVER" in S else tm.get_color(S.INPUT_BG)
			border_col = tm.get_color(S.BORDER_STRONG) if "BORDER_STRONG" in S else tm.get_color(S.INPUT_BORDER)
		else:
			bg_col = tm.get_color(S.INPUT_BG)
			border_col = tm.get_color(S.INPUT_BORDER)

		text_col = tm.get_color(S.PANEL_TEXT)
		muted_col = tm.get_color(S.TEXT_MUTED) if "TEXT_MUTED" in S else tm.get_color(S.TEXT_SECONDARY)
		accent_col = tm.get_color(S.ACCENT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2

	if is_focus:
		sb.shadow_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.25)
		sb.shadow_size = 2

	add_theme_stylebox_override("panel", sb)

	if is_instance_valid(_lbl_prefix):
		_lbl_prefix.add_theme_color_override("font_color", muted_col)
	if is_instance_valid(_lbl_suffix):
		_lbl_suffix.add_theme_color_override("font_color", muted_col)
	if is_instance_valid(_line_edit):
		_line_edit.add_theme_color_override("font_color", text_col)
		_line_edit.add_theme_color_override("caret_color", accent_col)

func set_value_silent(v: float) -> void:
	var clamped := clampf(v, min_value, max_value)
	value = clamped
	_refresh_display()

func set_prefix(p: String) -> void:
	prefix = p
	if is_instance_valid(_lbl_prefix):
		_lbl_prefix.text = prefix
		_lbl_prefix.visible = not prefix.is_empty()

func set_suffix(s: String) -> void:
	suffix = s
	if is_instance_valid(_lbl_suffix):
		_lbl_suffix.text = suffix
		_lbl_suffix.visible = not suffix.is_empty()

func _refresh_display() -> void:
	if _is_editing or not is_instance_valid(_line_edit):
		return
	if is_equal_approx(value, roundf(value)):
		_line_edit.text = "%d" % int(roundf(value))
	else:
		_line_edit.text = (("%." + str(decimals) + "f") % value).rstrip("0").rstrip(".")

func _enter_edit() -> void:
	if not enabled or _is_editing:
		return
	_is_editing = true
	_pre_edit_val = value
	_update_theme_styles(false, true)
	mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	_line_edit.grab_focus()
	_line_edit.select_all()

func _exit_edit(commit: bool) -> void:
	if not _is_editing:
		return
	_is_editing = false
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_line_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_theme_styles(false, false)

	if commit:
		var eval_res := eval_math(_line_edit.text, value)
		var new_val := clampf(eval_res, min_value, max_value)
		var changed := not is_equal_approx(value, new_val)
		value = new_val
		if changed:
			submitted.emit(value)
			value_changed.emit(value)
	else:
		value = _pre_edit_val

	_refresh_display()

func _on_line_edit_submitted(_t: String) -> void:
	_exit_edit(true)

func _on_line_edit_focus_exited() -> void:
	_exit_edit(true)

func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click:
					_enter_edit()
				else:
					_is_dragging = false
					_drag_start_mouse_x = mb.position.x
					_drag_start_val = value
			else:
				if _is_dragging:
					_is_dragging = false
					drag_ended.emit()
				elif not _is_editing:
					# Clic simple sin arrastre entra a editar
					_enter_edit()

		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var factor: float = _get_modifier_factor(mb)
			var new_v := clampf(value + step * factor, min_value, max_value)
			if not is_equal_approx(value, new_v):
				value = new_v
				value_changed.emit(value)
				submitted.emit(value)
				accept_event()

		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			var factor: float = _get_modifier_factor(mb)
			var new_v := clampf(value - step * factor, min_value, max_value)
			if not is_equal_approx(value, new_v):
				value = new_v
				value_changed.emit(value)
				submitted.emit(value)
				accept_event()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not _is_editing:
			var dx: float = mm.position.x - _drag_start_mouse_x
			if not _is_dragging and absf(dx) > 3.0:
				_is_dragging = true
				drag_started.emit()

			if _is_dragging:
				var factor: float = _get_modifier_factor(mm)
				var delta_val: float = dx * step * factor * 0.5
				var new_v := clampf(_drag_start_val + delta_val, min_value, max_value)
				if not is_equal_approx(value, new_v):
					value = new_v
					value_changed.emit(value)

	elif event is InputEventKey and _is_editing:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_exit_edit(false)
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		if not _is_editing:
			_update_theme_styles(true, false)
	elif what == NOTIFICATION_MOUSE_EXIT:
		if not _is_editing:
			_update_theme_styles(false, false)

func _get_modifier_factor(event: InputEvent) -> float:
	if event.is_shift_pressed():
		return 0.1 # Precisión fina
	if event.is_ctrl_pressed() or event.is_meta_pressed():
		return 5.0 # Salto grande
	return 1.0

## Evaluador de expresiones matemáticas (+10, -5, *2, /2, fórmulas).
static func eval_math(text: String, current: float) -> float:
	var t := text.strip_edges()
	if t == "":
		return current
	if t.begins_with("+") or t.begins_with("-") or t.begins_with("*") or t.begins_with("/"):
		t = str(current) + t
	elif t.is_valid_float():
		return float(t)
	var expr := Expression.new()
	var err := expr.parse(t)
	if err == OK:
		var res = expr.execute()
		if not expr.has_execute_failed() and (res is float or res is int):
			return float(res)
	return current
