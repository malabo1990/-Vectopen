# =============================================================================
# VECTOPEN — COMPONENTE COLLAPSIBLE SECTION (DESIGN SYSTEM)
# RUTA: res://script_gdscript/ui/components/collapsible_section.gd
# Cabecera colapsable interactiva con flecha ▼/▶, título y separador tenue
# =============================================================================
class_name CollapsibleSection
extends VBoxContainer

signal toggled(is_expanded: bool)

@export var title: String = "":
	set(v):
		title = v
		if is_instance_valid(_lbl_title):
			_lbl_title.text = title

@export var is_expanded: bool = true:
	set(v):
		is_expanded = v
		_update_expanded_state()

var content: VBoxContainer

var _header_btn: Button
var _lbl_arrow: Label
var _lbl_title: Label
var _sep_line: HSeparator

func _init(p_title: String = "", p_expanded: bool = true) -> void:
	title = p_title
	is_expanded = p_expanded
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	_build_ui()
	_update_expanded_state()
	_update_theme_styles()

	var tm = get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_m): _update_theme_styles())

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	_header_btn = Button.new()
	_header_btn.flat = true
	_header_btn.focus_mode = Control.FOCUS_NONE
	_header_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_btn.custom_minimum_size = Vector2(0, 22)
	_header_btn.pressed.connect(_on_header_pressed)
	add_child(_header_btn)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_btn.add_child(hbox)

	_lbl_arrow = Label.new()
	_lbl_arrow.text = "▼" if is_expanded else "▶"
	_lbl_arrow.add_theme_font_size_override("font_size", 9)
	_lbl_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_lbl_arrow)

	_lbl_title = Label.new()
	_lbl_title.text = title
	_lbl_title.add_theme_font_size_override("font_size", 10)
	_lbl_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_lbl_title)

	_sep_line = HSeparator.new()
	_sep_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sep_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sep_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_sep_line)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)

func _on_header_pressed() -> void:
	is_expanded = not is_expanded
	toggled.emit(is_expanded)

func _update_expanded_state() -> void:
	if is_instance_valid(_lbl_arrow):
		_lbl_arrow.text = "▼" if is_expanded else "▶"
	if is_instance_valid(content):
		content.visible = is_expanded

func add_content(ctrl: Control) -> void:
	if is_instance_valid(content):
		content.add_child(ctrl)

func _update_theme_styles() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var text_col := Color(0.85, 0.85, 0.85, 1.0)
	var arrow_col := Color(0.6, 0.6, 0.6, 1.0)
	var line_col := Color(0.3, 0.3, 0.3, 0.5)

	if tm:
		var S = tm.Slot
		text_col = tm.get_color(S.PANEL_TEXT)
		arrow_col = tm.get_color(S.TEXT_MUTED) if "TEXT_MUTED" in S else tm.get_color(S.TEXT_SECONDARY)
		line_col = tm.get_color(S.BORDER)
		line_col.a = 0.4

	if is_instance_valid(_lbl_title):
		_lbl_title.add_theme_color_override("font_color", text_col)
	if is_instance_valid(_lbl_arrow):
		_lbl_arrow.add_theme_color_override("font_color", arrow_col)
	if is_instance_valid(_sep_line):
		var sb := StyleBoxLine.new()
		sb.color = line_col
		sb.thickness = 1
		_sep_line.add_theme_stylebox_override("separator", sb)
