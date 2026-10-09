# =============================================================================
# VECTOPEN — CAMPO NUMÉRICO PROFESIONAL (estilo Figma / Illustrator)
# RUTA: res://script_gdscript/ui/pro/pro_num_field.gd
# [icono o letra][valor][unidad] en una sola caja de 24 px:
#   · arrastrar el icono en horizontal ajusta el valor (Shift ×0.1, Ctrl ×10)
#     → `scrub_changed` en vivo y `scrub_ended` al soltar;
#   · el texto acepta expresiones ("12*2", "24+6") y se confirma con Intro o
#     al perder el foco; Flecha arriba/abajo = ±paso (Shift ×10);
#   · `set_mixed(true)` muestra "Mixto" cuando la selección no coincide.
# API compatible con SpinBoxValue: value / min_value / max_value / step /
# suffix / set_value_no_signal / value_changed.
# =============================================================================
class_name ProNumField
extends PanelContainer

signal value_changed(value: float)
signal scrub_changed(value: float)
signal scrub_ended(value: float)

const H := 24

var min_value: float = 0.0
var max_value: float = 100.0
var step: float = 1.0
var suffix: String = "":
	set(v):
		suffix = v
		if is_instance_valid(_suffix):
			_suffix.text = v
			_suffix.visible = v != ""
var value: float = 0.0:
	set(v):
		var nv := _clamp(v)
		var changed := not is_equal_approx(nv, value)
		value = nv
		_mixed = false
		_refresh_text()
		if changed:
			value_changed.emit(value)

var _icon_path: String = ""
var _glyph: String = ""
var _lead: Control = null
var _edit: LineEdit = null
var _suffix: Label = null
var _mixed := false
var _placeholder := "Mixto"
var _hover := false
var _scrub := {"active": false, "x": 0.0, "v0": 0.0, "moved": false}

## `icon_path` (SVG de 16 px) o `glyph` (letra corta, p.ej. "W") a la izquierda.
func _init(icon_path: String = "", glyph: String = "", tip: String = "") -> void:
	_icon_path = icon_path
	_glyph = glyph
	tooltip_text = tip
	custom_minimum_size = Vector2(0, H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	if _icon_path != "":
		var tr_ := TextureRect.new()
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr_.custom_minimum_size = Vector2(20, H - 2)
		_lead = tr_
	else:
		var l := Label.new()
		l.text = _glyph
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(18 if _glyph.length() <= 1 else 26, H - 2)
		l.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
		_lead = l
	_lead.mouse_filter = Control.MOUSE_FILTER_STOP
	_lead.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_lead.tooltip_text = tip
	_lead.gui_input.connect(_on_lead_input)
	row.add_child(_lead)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(24, H - 2)
	_edit.flat = true
	# Por defecto LineEdit reserva 4 caracteres: en filas de 3 campos
	# estrechas (192 px) desbordaba el panel.
	_edit.add_theme_constant_override("minimum_character_width", 2)
	_edit.select_all_on_focus = true
	_edit.caret_blink = true
	_edit.context_menu_enabled = false
	_edit.tooltip_text = tip
	_edit.text_submitted.connect(func(_t: String) -> void: _commit_text(); _edit.release_focus())
	_edit.focus_exited.connect(_commit_text)
	_edit.focus_entered.connect(_restyle)
	_edit.gui_input.connect(_on_edit_input)
	row.add_child(_edit)
	_suffix = Label.new()
	_suffix.text = suffix
	_suffix.visible = suffix != ""
	_suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_suffix.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE_SMALL)
	_suffix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_suffix)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(4, 0)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	mouse_entered.connect(func() -> void: _hover = true; _restyle())
	mouse_exited.connect(func() -> void: _hover = false; _restyle())

func _ready() -> void:
	_refresh_text()
	apply_theme()

func set_value_no_signal(v: float) -> void:
	_mixed = false
	_set_raw(_clamp(v))

## Sin valor común: campo vacío con `placeholder` ("Mixto" o "—" sin selección).
func set_mixed(mixed: bool, placeholder: String = "Mixto") -> void:
	_mixed = mixed
	_placeholder = placeholder
	_refresh_text()

func is_mixed() -> bool:
	return _mixed

func line_edit() -> LineEdit:
	return _edit

func _set_raw(v: float) -> void:
	# Asigna sin pasar por el setter (no emite).
	set_block_signals(true)
	value = v
	set_block_signals(false)
	_refresh_text()

func _clamp(v: float) -> float:
	var out := clampf(v, min_value, max_value)
	if step > 0.0:
		out = snappedf(out, step)
	return out

func _fmt(v: float) -> String:
	if step >= 1.0 and is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 2).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func _refresh_text() -> void:
	if not is_instance_valid(_edit) or _edit.has_focus():
		return
	if _mixed:
		_edit.text = ""
		_edit.placeholder_text = tr(_placeholder)
	else:
		_edit.placeholder_text = ""
		_edit.text = _fmt(value)

func _commit_text() -> void:
	if not is_instance_valid(_edit):
		return
	var t := _edit.text.strip_edges().replace(",", ".")
	if t == "":
		_refresh_text()
		_restyle()
		return
	var parsed := value
	if t.is_valid_float():
		parsed = t.to_float()
	else:
		var ex := Expression.new()
		if ex.parse(t) == OK:
			var r = ex.execute()
			if not ex.has_execute_failed() and (r is float or r is int):
				parsed = float(r)
	_mixed = false
	value = parsed
	_edit.text = _fmt(value)
	_restyle()

func _on_edit_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_UP or ev.keycode == KEY_DOWN):
		var mul := 10.0 if ev.shift_pressed else 1.0
		var d := step * mul * (1.0 if ev.keycode == KEY_UP else -1.0)
		value = value + d
		_edit.text = _fmt(value)
		_edit.caret_column = _edit.text.length()
		_edit.accept_event()

func _on_lead_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_scrub = {"active": true, "x": ev.global_position.x, "v0": value, "moved": false}
		elif _scrub["active"]:
			_scrub["active"] = false
			if _scrub["moved"]:
				scrub_ended.emit(value)
				value_changed.emit(value)
			else:
				_edit.grab_focus()
		_lead.accept_event()
	elif ev is InputEventMouseMotion and _scrub["active"]:
		var dx: float = ev.global_position.x - float(_scrub["x"])
		if absf(dx) < 2.0 and not _scrub["moved"]:
			return
		_scrub["moved"] = true
		var mul := 1.0
		if Input.is_key_pressed(KEY_SHIFT):
			mul = 0.1
		elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
			mul = 10.0
		var stp := maxf(step, 0.01)
		var nv := _clamp(float(_scrub["v0"]) + roundf(dx / 2.0) * stp * mul)
		if not is_equal_approx(nv, value) or _mixed:
			_mixed = false
			_set_raw(nv)
			scrub_changed.emit(nv)
		_lead.accept_event()

## Colores del ThemeManager (claro / oscuro).
func apply_theme() -> void:
	var text := ProUIStyle.col("PANEL_TEXT")
	var muted := ProUIStyle.col("TEXT_SECONDARY")
	if _lead is TextureRect:
		(_lead as TextureRect).texture = ProUIStyle.icon(_icon_path, muted, 16)
	elif _lead is Label:
		(_lead as Label).add_theme_color_override("font_color", muted)
	_edit.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE + 1)
	_edit.add_theme_color_override("font_color", text)
	_edit.add_theme_color_override("caret_color", text)
	_edit.add_theme_color_override("font_placeholder_color", muted)
	_edit.add_theme_color_override("selection_color", Color(ProUIStyle.col("ACCENT"), 0.35))
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "focus", "read_only"]:
		_edit.add_theme_stylebox_override(k, empty)
	_suffix.add_theme_color_override("font_color", muted)
	_restyle()

func _restyle() -> void:
	if not is_instance_valid(_edit):
		return
	var focused := _edit.has_focus()
	var border := ProUIStyle.col("ACCENT") if focused else (ProUIStyle.col("BORDER_STRONG") if _hover else ProUIStyle.col("INPUT_BORDER"))
	var sb := ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, border, 0, 0)
	add_theme_stylebox_override("panel", sb)
