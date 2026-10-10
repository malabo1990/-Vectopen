# =============================================================================
# RUTA: res://script_gdscript/ui/panel_trazos.gd
# Panel de control de trazos (Stroke Panel) para Vectopen Studio.
# Selector 100% visual con iconos (sin menús desplegables).
# Estilo Blanco / Claro Studio (Apple / Figma / Sketch) acorde con Capas y Layout.
# =============================================================================
@tool
extends PanelContainer
class_name PanelTrazos
const StrokeProfile = preload("res://script_gdscript/shapes/stroke_profile.gd")

## Referencias a controles UI
@onready var _color_picker: ColorPickerButton = get_node_or_null("MarginContainer/BoxContainer/RowColor/ColorPickerButton")
@onready var _spin_size: Node = get_node_or_null("MarginContainer/BoxContainer/RowGrosor/SpinBox")

# Alineación (0: Centro, 1: Interior, 2: Exterior)
@onready var _btn_align_medio: Button = get_node_or_null("MarginContainer/BoxContainer/RowAlign/BtnAlignMedio")
@onready var _btn_align_interior: Button = get_node_or_null("MarginContainer/BoxContainer/RowAlign/BtnAlignInterior")
@onready var _btn_align_exterior: Button = get_node_or_null("MarginContainer/BoxContainer/RowAlign/BtnAlignExterior")

# Extremos / Caps Inicio (0: Plano, 1: Redondo, 2: Cuadrado)
@onready var _btn_cap_start_butt: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapStart/BtnCapStartButt")
@onready var _btn_cap_start_round: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapStart/BtnCapStartRound")
@onready var _btn_cap_start_square: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapStart/BtnCapStartSquare")

# Extremos / Caps Fin (0: Plano, 1: Redondo, 2: Cuadrado)
@onready var _btn_cap_end_butt: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapEnd/BtnCapEndButt")
@onready var _btn_cap_end_round: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapEnd/BtnCapEndRound")
@onready var _btn_cap_end_square: Button = get_node_or_null("MarginContainer/BoxContainer/RowCapEnd/BtnCapEndSquare")

# Estilos de Trazo (0: Solid, 1: Dashed, 2: Dotted, 3: Tapered, 4: Double)
@onready var _btn_style_solid: Button = get_node_or_null("MarginContainer/BoxContainer/RowStyle/BtnStyleSolid")
@onready var _btn_style_dashed: Button = get_node_or_null("MarginContainer/BoxContainer/RowStyle/BtnStyleDashed")
@onready var _btn_style_dotted: Button = get_node_or_null("MarginContainer/BoxContainer/RowStyle/BtnStyleDotted")
@onready var _btn_style_tapered: Button = get_node_or_null("MarginContainer/BoxContainer/RowStyle/BtnStyleTapered")
@onready var _btn_style_double: Button = get_node_or_null("MarginContainer/BoxContainer/RowStyle/BtnStyleDouble")

# Parámetros Discontinuo
@onready var _box_dash_params: Control = get_node_or_null("MarginContainer/BoxContainer/BoxDashParams")
@onready var _spin_dash_len: SpinBox = get_node_or_null("MarginContainer/BoxContainer/BoxDashParams/SpinDashLen")
@onready var _spin_dash_gap: SpinBox = get_node_or_null("MarginContainer/BoxContainer/BoxDashParams/SpinDashGap")

# Punteros / Flechas Inicio (0: None, 1: Arrow, 2: Triangle, 3: Circle, 4: Square)
@onready var _btn_pointer_start_none: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerStart/BtnPointerStartNone")
@onready var _btn_pointer_start_arrow: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerStart/BtnPointerStartArrow")
@onready var _btn_pointer_start_triangle: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerStart/BtnPointerStartTriangle")
@onready var _btn_pointer_start_circle: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerStart/BtnPointerStartCircle")
@onready var _btn_pointer_start_square: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerStart/BtnPointerStartSquare")

# Punteros / Flechas Fin (0: None, 1: Arrow, 2: Triangle, 3: Circle, 4: Square)
@onready var _btn_pointer_end_none: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerEnd/BtnPointerEndNone")
@onready var _btn_pointer_end_arrow: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerEnd/BtnPointerEndArrow")
@onready var _btn_pointer_end_triangle: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerEnd/BtnPointerEndTriangle")
@onready var _btn_pointer_end_circle: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerEnd/BtnPointerEndCircle")
@onready var _btn_pointer_end_square: Button = get_node_or_null("MarginContainer/BoxContainer/RowPointerEnd/BtnPointerEndSquare")

# Editor de Curva
@onready var _box_curve: Control = get_node_or_null("MarginContainer/BoxContainer/BoxCurveEditor")
@onready var _btn_toggle_curve: Button = get_node_or_null("MarginContainer/BoxContainer/RowCurveToggle/BtnToggleCurve")

# Grupos de botones
var _align_buttons: Array[Button] = []
var _cap_start_buttons: Array[Button] = []
var _cap_end_buttons: Array[Button] = []
var _style_buttons: Array[Button] = []
var _pointer_start_buttons: Array[Button] = []
var _pointer_end_buttons: Array[Button] = []

var _sync_guard: bool = false
var _current_align: int = 0
var _current_cap_start: int = 0
var _current_cap_end: int = 0
var _current_style: int = 0
var _current_pointer_start: int = 0
var _current_pointer_end: int = 0

# Tokens de estilo idénticos a toolbar.gd y layers_system.gd
const _ICONO_OFF := Color(0.44, 0.44, 0.47, 1.0)   # Inactivo: gris medio
const _ICONO_HOVER := Color(0.10, 0.10, 0.11, 1.0) # Hover: negro
const _ICONO_ON := Color(0.10, 0.10, 0.11, 1.0)    # Activo: negro sobre chip destacado

var _COLOR_PANEL_BG := Color(1.0, 1.0, 1.0, 1.0)
var _COLOR_TEXT_PRIMARY := Color(0.11, 0.11, 0.12, 1.0)
var _COLOR_TEXT_SECONDARY := Color(0.42, 0.42, 0.46, 1.0)
var _COLOR_CHIP_NORMAL := Color(0.95, 0.95, 0.97, 1.0)
var _COLOR_CHIP_HOVER := Color(0.90, 0.91, 0.94, 1.0)
var _COLOR_CHIP_ACTIVE := Color(0.86, 0.88, 0.92, 1.0) # SURFACE_RAISED
var _COLOR_BORDER := Color(0.86, 0.87, 0.90, 1.0)
var _COLOR_BORDER_ACTIVE := Color(0.68, 0.70, 0.76, 1.0)

const _Swatch = preload("res://script_gdscript/ui/pro/stroke_swatch.gd")
const _NumField = preload("res://script_gdscript/ui/pro/pro_num_field.gd")
const _Popover = preload("res://script_gdscript/ui/pro/stroke_popover.gd")
const _LABEL_W := 52

## Filas compactas (construidas en código sobre el .tscn):
##   Color [■]  Grosor [≡ 2 px]
##   Alinear [centro][interior][exterior]
##   Extremos            [← +] [→ +]   (inicio / fin a la derecha)
##   Estilo              [─── +]
##   Perfil              [◀▶ +]
## Cada "+" abre el panel desplegable con la lista completa (stroke_popover).
var _num_width: Control = null
var _chips: Dictionary = {}      # "start" | "end" | "style" | "profile" -> Button
var _swatches: Dictionary = {}   # mismo -> Swatch
var _live_w_before: Dictionary = {}

func _ready() -> void:
	_init_refs()
	if not Engine.is_editor_hint():
		_build_compact_ui()
	_apply_theme_tokens()
	_aplicar_estilos_generales()
	_style_spinbox(_spin_dash_len)
	_style_spinbox(_spin_dash_gap)
	_connect_ui_signals()
	_refresh_all_button_groups()

	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		if not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)
		_on_inspector_changed(ic.current_props())

	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		if not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)

func _on_theme_changed(_mode: String) -> void:
	_apply_theme_tokens()
	_aplicar_estilos_generales()
	_theme_compact_ui()
	_style_spinbox(_spin_dash_len)
	_style_spinbox(_spin_dash_gap)
	_refresh_all_button_groups()

func _init_refs() -> void:
	if _color_picker == null:
		_color_picker = find_child("ColorPickerButton", true, false) as ColorPickerButton
	if _spin_size == null:
		_spin_size = find_child("SpinBox", true, false)
	if _btn_align_medio == null:
		_btn_align_medio = find_child("BtnAlignMedio", true, false) as Button
	if _btn_align_interior == null:
		_btn_align_interior = find_child("BtnAlignInterior", true, false) as Button
	if _btn_align_exterior == null:
		_btn_align_exterior = find_child("BtnAlignExterior", true, false) as Button

	# Caps Start
	if _btn_cap_start_butt == null: _btn_cap_start_butt = find_child("BtnCapStartButt", true, false) as Button
	if _btn_cap_start_round == null: _btn_cap_start_round = find_child("BtnCapStartRound", true, false) as Button
	if _btn_cap_start_square == null: _btn_cap_start_square = find_child("BtnCapStartSquare", true, false) as Button

	# Caps End
	if _btn_cap_end_butt == null: _btn_cap_end_butt = find_child("BtnCapEndButt", true, false) as Button
	if _btn_cap_end_round == null: _btn_cap_end_round = find_child("BtnCapEndRound", true, false) as Button
	if _btn_cap_end_square == null: _btn_cap_end_square = find_child("BtnCapEndSquare", true, false) as Button

	# Styles
	if _btn_style_solid == null: _btn_style_solid = find_child("BtnStyleSolid", true, false) as Button
	if _btn_style_dashed == null: _btn_style_dashed = find_child("BtnStyleDashed", true, false) as Button
	if _btn_style_dotted == null: _btn_style_dotted = find_child("BtnStyleDotted", true, false) as Button
	if _btn_style_tapered == null: _btn_style_tapered = find_child("BtnStyleTapered", true, false) as Button
	if _btn_style_double == null: _btn_style_double = find_child("BtnStyleDouble", true, false) as Button

	# Dash params
	if _box_dash_params == null: _box_dash_params = find_child("BoxDashParams", true, false) as Control
	if _spin_dash_len == null: _spin_dash_len = find_child("SpinDashLen", true, false) as SpinBox
	if _spin_dash_gap == null: _spin_dash_gap = find_child("SpinDashGap", true, false) as SpinBox

	# Pointers Start
	if _btn_pointer_start_none == null: _btn_pointer_start_none = find_child("BtnPointerStartNone", true, false) as Button
	if _btn_pointer_start_arrow == null: _btn_pointer_start_arrow = find_child("BtnPointerStartArrow", true, false) as Button
	if _btn_pointer_start_triangle == null: _btn_pointer_start_triangle = find_child("BtnPointerStartTriangle", true, false) as Button
	if _btn_pointer_start_circle == null: _btn_pointer_start_circle = find_child("BtnPointerStartCircle", true, false) as Button
	if _btn_pointer_start_square == null: _btn_pointer_start_square = find_child("BtnPointerStartSquare", true, false) as Button

	# Pointers End
	if _btn_pointer_end_none == null: _btn_pointer_end_none = find_child("BtnPointerEndNone", true, false) as Button
	if _btn_pointer_end_arrow == null: _btn_pointer_end_arrow = find_child("BtnPointerEndArrow", true, false) as Button
	if _btn_pointer_end_triangle == null: _btn_pointer_end_triangle = find_child("BtnPointerEndTriangle", true, false) as Button
	if _btn_pointer_end_circle == null: _btn_pointer_end_circle = find_child("BtnPointerEndCircle", true, false) as Button
	if _btn_pointer_end_square == null: _btn_pointer_end_square = find_child("BtnPointerEndSquare", true, false) as Button

	# Curve
	if _box_curve == null: _box_curve = find_child("BoxCurveEditor", true, false) as Control
	if _btn_toggle_curve == null: _btn_toggle_curve = find_child("BtnToggleCurve", true, false) as Button

	# Listas de botones agrupados
	_align_buttons = [_btn_align_medio, _btn_align_interior, _btn_align_exterior]
	_cap_start_buttons = [_btn_cap_start_butt, _btn_cap_start_round, _btn_cap_start_square]
	_cap_end_buttons = [_btn_cap_end_butt, _btn_cap_end_round, _btn_cap_end_square]
	_style_buttons = [_btn_style_solid, _btn_style_dashed, _btn_style_dotted, _btn_style_tapered, _btn_style_double]
	_pointer_start_buttons = [_btn_pointer_start_none, _btn_pointer_start_arrow, _btn_pointer_start_triangle, _btn_pointer_start_circle, _btn_pointer_start_square]
	_pointer_end_buttons = [_btn_pointer_end_none, _btn_pointer_end_arrow, _btn_pointer_end_triangle, _btn_pointer_end_circle, _btn_pointer_end_square]

func _apply_theme_tokens() -> void:
	var tm := get_node_or_null("/root/ThemeManager") if is_inside_tree() else null
	if tm != null and tm.has_method("get_color"):
		var S = tm.Slot
		_COLOR_PANEL_BG = tm.get_color(S.PANEL_SURFACE)
		_COLOR_TEXT_PRIMARY = tm.get_color(S.PANEL_TEXT)
		_COLOR_TEXT_SECONDARY = tm.get_color(S.TEXT_SECONDARY)
		_COLOR_CHIP_NORMAL = tm.get_color(S.BUTTON_BG)
		_COLOR_CHIP_HOVER = tm.get_color(S.BUTTON_HOVER)
		_COLOR_CHIP_ACTIVE = tm.get_color(S.SURFACE_RAISED)
		_COLOR_BORDER = tm.get_color(S.BORDER)
		_COLOR_BORDER_ACTIVE = tm.get_color(S.ACCENT)
	else:
		_COLOR_PANEL_BG = Color(1.0, 1.0, 1.0, 1.0)
		_COLOR_TEXT_PRIMARY = Color(0.11, 0.11, 0.12, 1.0)
		_COLOR_TEXT_SECONDARY = Color(0.42, 0.42, 0.46, 1.0)
		_COLOR_CHIP_NORMAL = Color(0.95, 0.95, 0.97, 1.0)
		_COLOR_CHIP_HOVER = Color(0.90, 0.91, 0.94, 1.0)
		_COLOR_CHIP_ACTIVE = Color(0.85, 0.85, 0.88, 1.0)
		_COLOR_BORDER = Color(0.86, 0.87, 0.90, 1.0)
		_COLOR_BORDER_ACTIVE = Color(0.70, 0.71, 0.75, 1.0)

func _aplicar_estilos_generales() -> void:
	# Panel principal: blanco puro sin bordes ni sombras de tarjeta anidada
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = _COLOR_PANEL_BG
	panel_sb.set_corner_radius_all(0)
	panel_sb.set_border_width_all(0)
	panel_sb.border_color = Color.TRANSPARENT
	panel_sb.shadow_size = 0
	panel_sb.content_margin_left = 0
	panel_sb.content_margin_right = 0
	panel_sb.content_margin_top = 0
	panel_sb.content_margin_bottom = 0
	add_theme_stylebox_override("panel", panel_sb)

	# Título y etiquetas de texto
	var title := find_child("LabelTitle", true, false) as Label
	if title:
		title.add_theme_color_override("font_color", _COLOR_TEXT_PRIMARY)
		title.add_theme_font_size_override("font_size", 12)

	for l in find_children("", "Label", true, false):
		if l != title and l is Label:
			l.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)
			l.add_theme_font_size_override("font_size", 11)

	# Separador sutil
	var sep := find_child("HSeparator1", true, false) as HSeparator
	if sep:
		var sep_sb := StyleBoxLine.new()
		sep_sb.color = _COLOR_BORDER
		sep.add_theme_stylebox_override("separator", sep_sb)

	# Botón Toggle Curve (estilo gris como tool.tscn y layout.tscn)
	if _btn_toggle_curve:
		var is_open: bool = _box_curve.visible if _box_curve else false
		_style_toggle_button(_btn_toggle_curve, is_open)

func _style_spinbox(sb: SpinBox) -> void:
	if sb == null:
		return
	var le := sb.get_line_edit()
	if le == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = _COLOR_CHIP_NORMAL
	style.border_color = _COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	le.add_theme_stylebox_override("normal", style)
	le.add_theme_stylebox_override("focus", style)
	le.add_theme_color_override("font_color", _COLOR_TEXT_PRIMARY)
	le.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0, 1.0))
	le.add_theme_font_size_override("font_size", 10)

func _connect_ui_signals() -> void:
	if _color_picker and not _color_picker.color_changed.is_connected(_on_color_changed):
		_color_picker.color_changed.connect(_on_color_changed)

	if _spin_size:
		if _spin_size.has_signal("value_changed"):
			if not _spin_size.is_connected("value_changed", _on_size_changed):
				_spin_size.connect("value_changed", _on_size_changed)

	# Alineación
	for i in range(_align_buttons.size()):
		var b := _align_buttons[i]
		if b and not b.pressed.is_connected(_on_align_pressed.bind(i)):
			b.pressed.connect(_on_align_pressed.bind(i))

	# Caps Start
	for i in range(_cap_start_buttons.size()):
		var b := _cap_start_buttons[i]
		if b and not b.pressed.is_connected(_on_cap_start_pressed.bind(i)):
			b.pressed.connect(_on_cap_start_pressed.bind(i))

	# Caps End
	for i in range(_cap_end_buttons.size()):
		var b := _cap_end_buttons[i]
		if b and not b.pressed.is_connected(_on_cap_end_pressed.bind(i)):
			b.pressed.connect(_on_cap_end_pressed.bind(i))

	# Styles
	for i in range(_style_buttons.size()):
		var b := _style_buttons[i]
		if b and not b.pressed.is_connected(_on_style_pressed.bind(i)):
			b.pressed.connect(_on_style_pressed.bind(i))

	# Dash Params
	if _spin_dash_len and not _spin_dash_len.value_changed.is_connected(_on_dash_len_changed):
		_spin_dash_len.value_changed.connect(_on_dash_len_changed)
	if _spin_dash_gap and not _spin_dash_gap.value_changed.is_connected(_on_dash_gap_changed):
		_spin_dash_gap.value_changed.connect(_on_dash_gap_changed)

	# Pointers Start
	for i in range(_pointer_start_buttons.size()):
		var b := _pointer_start_buttons[i]
		if b and not b.pressed.is_connected(_on_pointer_start_pressed.bind(i)):
			b.pressed.connect(_on_pointer_start_pressed.bind(i))

	# Pointers End
	for i in range(_pointer_end_buttons.size()):
		var b := _pointer_end_buttons[i]
		if b and not b.pressed.is_connected(_on_pointer_end_pressed.bind(i)):
			b.pressed.connect(_on_pointer_end_pressed.bind(i))

	if _btn_toggle_curve and not _btn_toggle_curve.pressed.is_connected(_on_toggle_curve_pressed):
		_btn_toggle_curve.pressed.connect(_on_toggle_curve_pressed)

# ── Interfaz compacta ────────────────────────────────────────────────────────
func _build_compact_ui() -> void:
	var vb := find_child("BoxContainer", false, false)
	if vb == null:
		vb = get_node_or_null("MarginContainer/BoxContainer")
	if vb == null or vb.has_node("RowEnds"):
		return
	# Las filas antiguas (4 filas de remates / puntas, 5 estilos, editor de
	# curva sin conectar) se sustituyen por chips con "+".
	for rel in ["RowCapStart", "RowCapEnd", "RowStyle", "RowPointerStart", "RowPointerEnd",
			"RowCurveToggle", "BoxCurveEditor", "BoxDashParams", "RowGrosor"]:
		var n := vb.get_node_or_null(rel) as CanvasItem
		if n:
			n.visible = false
	var title := find_child("LabelTitle", true, false) as Label
	if title:
		title.text = tr("TRAZO")
	# Grosor junto al color, con el campo de arrastre de los demás paneles
	# (el SpinBox original sigue en la escena, oculto, por compatibilidad).
	var row_color := vb.get_node_or_null("RowColor") as HBoxContainer
	if row_color:
		var spacer := row_color.get_node_or_null("Spacer") as Control
		if spacer:
			spacer.size_flags_horizontal = Control.SIZE_FILL
			spacer.custom_minimum_size = Vector2(4, 0)
		var lbl := Label.new()
		lbl.text = tr("Grosor")
		lbl.add_theme_font_size_override("font_size", 11)
		row_color.add_child(lbl)
		_num_width = _NumField.new("", "≡", tr("Grosor del trazo (arrastra para ajustar)"))
		_num_width.min_value = 0
		_num_width.max_value = 500
		_num_width.step = 0.5
		_num_width.suffix = "px"
		_num_width.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_num_width.value_changed.connect(_on_size_changed)
		_num_width.scrub_changed.connect(_on_width_scrub)
		_num_width.scrub_ended.connect(_on_width_scrub_end)
		row_color.add_child(_num_width)
	var at := (vb.get_node("RowAlign") as Node).get_index() + 1
	var ends := _row(vb, "RowEnds", tr("Extremos"), at)
	ends.add_child(_chip("start", "marker", 0, true, tr("Inicio del trazo: punta y remate"), 58))
	ends.add_child(_chip("end", "marker", 0, false, tr("Fin del trazo: punta y remate"), 58))
	var st := _row(vb, "RowStyleChip", tr("Estilo"), at + 1)
	st.add_child(_chip("style", "style", 0, false, tr("Estilo: sólido, discontinuo, punteado, doble"), 0, true))
	var pr := _row(vb, "RowProfile", tr("Perfil"), at + 2)
	pr.add_child(_chip("profile", "profile", PackedVector2Array(), false, tr("Perfil de grosor (Ideal, Afilado… o personalizado)"), 0, true))
	_theme_compact_ui()

func _row(vb: Node, nm: String, text: String, idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = nm
	row.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(_LABEL_W, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	vb.add_child(row)
	vb.move_child(row, idx)
	return row

## Chip: muestra dibujada de lo actual + "+" que abre la lista completa.
func _chip(key: String, kind: String, value: Variant, at_start: bool, tip: String, w: float, expand: bool = false) -> Button:
	var b := Button.new()
	b.name = "Chip_" + key
	b.text = "+"
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 26)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 2.6
	b.add_theme_font_size_override("font_size", 13)
	var sw: Control = _Swatch.new(kind, value, at_start)
	sw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sw.offset_left = 6
	sw.offset_right = -18
	b.add_child(sw)
	b.pressed.connect(func() -> void: _Popover.toggle(_popover_anchor(), key, b))
	_chips[key] = b
	_swatches[key] = sw
	return b

## El menú contextual completo (para abrir el desplegable a su lado).
func _popover_anchor() -> Control:
	var vp := get_viewport_rect().size
	var a: Control = self
	var n: Node = get_parent()
	while n is Control:
		var cr := (n as Control).get_global_rect()
		if cr.size.x > vp.x * 0.5 or cr.size.y > vp.y * 0.95 or not cr.grow(1.0).encloses(get_global_rect()):
			break
		a = n
		n = n.get_parent()
	return a

func _theme_compact_ui() -> void:
	for key in _chips:
		var b: Button = _chips[key]
		if not is_instance_valid(b):
			continue
		b.add_theme_stylebox_override("normal", ProUIStyle.flat(ProUIStyle.col("INPUT_BG"), 4, ProUIStyle.col("INPUT_BORDER"), 6, 0))
		b.add_theme_stylebox_override("hover", ProUIStyle.flat(ProUIStyle.col("BUTTON_HOVER"), 4, ProUIStyle.col("BORDER_STRONG"), 6, 0))
		b.add_theme_stylebox_override("pressed", ProUIStyle.flat(ProUIStyle.col("BUTTON_PRESSED"), 4, ProUIStyle.col("ACCENT"), 6, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", ProUIStyle.col("TEXT_SECONDARY"))
		b.add_theme_color_override("font_hover_color", ProUIStyle.col("PANEL_TEXT"))
		(_swatches[key] as Control).queue_redraw()
	if is_instance_valid(_num_width) and _num_width.has_method("apply_theme"):
		_num_width.apply_theme()
	for row_name in ["RowEnds", "RowStyleChip", "RowProfile", "RowColor"]:
		var row := find_child(row_name, true, false)
		if row:
			for c in row.get_children():
				if c is Label:
					c.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)

func _update_swatches(props: Dictionary) -> void:
	if _swatches.is_empty():
		return
	var g := func(k: String, d: Variant) -> Variant:
		return props[k]["value"] if props.has(k) and not props[k]["mixed"] else d
	_swatches["start"].set_value(int(g.call("stroke_pointer_start", 0)))
	_swatches["end"].set_value(int(g.call("stroke_pointer_end", 0)))
	var st := int(g.call("stroke_style", 0))
	_swatches["style"].set_value(0 if st == 3 else st)
	var prof := StrokeProfile.normalize(g.call("stroke_profile", PackedVector2Array()))
	if st == 3 and StrokeProfile.is_uniform(prof):
		prof = StrokeProfile.preset("taper")
	_swatches["profile"].set_value(prof)
	if is_instance_valid(_num_width) and props.has("stroke_width"):
		if props["stroke_width"]["mixed"]:
			_num_width.set_mixed(true)
		else:
			_num_width.set_value_no_signal(float(props["stroke_width"]["value"]))

## Arrastre del grosor: en vivo y UN paso de deshacer al soltar.
func _on_width_scrub(v: float) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("_write"):
		return
	if _live_w_before.is_empty():
		for s in ic.selection():
			var b = ic._read(s, "stroke_width")
			if b != null:
				_live_w_before[s] = b
	for s in _live_w_before:
		if is_instance_valid(s):
			ic._write(s, "stroke_width", v)
	ic.post_write_live()

func _on_width_scrub_end(_v: float) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and not _live_w_before.is_empty():
		ic.commit_live("stroke_width", _live_w_before)
	_live_w_before = {}

# ── Eventos de UI hacia InspectorCore ────────────────────────────────────────

func _apply_prop(prop: String, val: Variant) -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic != null and ic.has_method("apply"):
		ic.apply(prop, val)

func _on_color_changed(col: Color) -> void:
	_apply_prop("stroke_color", col)

func _on_size_changed(val: float) -> void:
	_apply_prop("stroke_width", val)

func _on_align_pressed(idx: int) -> void:
	_current_align = idx
	_update_button_group_ui(_align_buttons, _current_align)
	_apply_prop("stroke_align", idx)

func _on_cap_start_pressed(idx: int) -> void:
	_current_cap_start = idx
	_update_button_group_ui(_cap_start_buttons, _current_cap_start)
	_apply_prop("stroke_cap_start", idx)

func _on_cap_end_pressed(idx: int) -> void:
	_current_cap_end = idx
	_update_button_group_ui(_cap_end_buttons, _current_cap_end)
	_apply_prop("stroke_cap_end", idx)

func _on_style_pressed(idx: int) -> void:
	_current_style = idx
	_update_button_group_ui(_style_buttons, _current_style)
	_update_style_visibility(idx)
	_apply_prop("stroke_style", idx)

func _on_dash_len_changed(val: float) -> void:
	_apply_prop("stroke_dash_len", val)

func _on_dash_gap_changed(val: float) -> void:
	_apply_prop("stroke_dash_gap", val)

func _on_pointer_start_pressed(idx: int) -> void:
	_current_pointer_start = idx
	_update_button_group_ui(_pointer_start_buttons, _current_pointer_start)
	_apply_prop("stroke_pointer_start", idx)

func _on_pointer_end_pressed(idx: int) -> void:
	_current_pointer_end = idx
	_update_button_group_ui(_pointer_end_buttons, _current_pointer_end)
	_apply_prop("stroke_pointer_end", idx)

func _on_toggle_curve_pressed() -> void:
	if _box_curve:
		_box_curve.visible = not _box_curve.visible
		if _btn_toggle_curve:
			_btn_toggle_curve.text = "▲ Ocultar Perfil Curva" if _box_curve.visible else "▼ Editor Perfil Cónico"
			_style_toggle_button(_btn_toggle_curve, _box_curve.visible)

# ── Sincronización desde InspectorCore hacia UI ─────────────────────────────

func _on_inspector_changed(props: Dictionary) -> void:
	if _sync_guard or props.is_empty():
		return
	_sync_guard = true

	# Color
	if _color_picker and props.has("stroke_color") and not props["stroke_color"]["mixed"]:
		_color_picker.color = props["stroke_color"]["value"]

	# Ancho
	if _spin_size and props.has("stroke_width") and not props["stroke_width"]["mixed"]:
		var w: float = float(props["stroke_width"]["value"])
		if _spin_size.has_method("set_value"):
			_spin_size.set_value(w)
		elif "value" in _spin_size:
			_spin_size.value = w

	# Alineación
	if props.has("stroke_align") and not props["stroke_align"]["mixed"]:
		_current_align = int(props["stroke_align"]["value"])
		_update_button_group_ui(_align_buttons, _current_align)

	# Caps
	if props.has("stroke_cap_start") and not props["stroke_cap_start"]["mixed"]:
		_current_cap_start = int(props["stroke_cap_start"]["value"])
		_update_button_group_ui(_cap_start_buttons, _current_cap_start)
	if props.has("stroke_cap_end") and not props["stroke_cap_end"]["mixed"]:
		_current_cap_end = int(props["stroke_cap_end"]["value"])
		_update_button_group_ui(_cap_end_buttons, _current_cap_end)

	# Style
	if props.has("stroke_style") and not props["stroke_style"]["mixed"]:
		_current_style = int(props["stroke_style"]["value"])
		_update_button_group_ui(_style_buttons, _current_style)
		_update_style_visibility(_current_style)

	# Dash params
	if _spin_dash_len and props.has("stroke_dash_len") and not props["stroke_dash_len"]["mixed"]:
		_spin_dash_len.value = float(props["stroke_dash_len"]["value"])
	if _spin_dash_gap and props.has("stroke_dash_gap") and not props["stroke_dash_gap"]["mixed"]:
		_spin_dash_gap.value = float(props["stroke_dash_gap"]["value"])

	_update_swatches(props)

	# Pointers
	if props.has("stroke_pointer_start") and not props["stroke_pointer_start"]["mixed"]:
		_current_pointer_start = int(props["stroke_pointer_start"]["value"])
		_update_button_group_ui(_pointer_start_buttons, _current_pointer_start)
	if props.has("stroke_pointer_end") and not props["stroke_pointer_end"]["mixed"]:
		_current_pointer_end = int(props["stroke_pointer_end"]["value"])
		_update_button_group_ui(_pointer_end_buttons, _current_pointer_end)

	_sync_guard = false

func _update_style_visibility(st: int) -> void:
	if _box_dash_params:
		_box_dash_params.visible = (st == 1 or st == 2) # Dashed o Dotted
	if _box_curve and _btn_toggle_curve:
		if st == 3: # Tapered
			_box_curve.visible = true
			_btn_toggle_curve.text = "▲ Ocultar Perfil Curva"
			_style_toggle_button(_btn_toggle_curve, true)

func _actualizar_interfaz_completa() -> void:
	_update_button_group_ui(_align_buttons, _current_align)
	_update_button_group_ui(_cap_start_buttons, _current_cap_start)
	_update_button_group_ui(_cap_end_buttons, _current_cap_end)
	_update_button_group_ui(_style_buttons, _current_style)
	_update_button_group_ui(_pointer_start_buttons, _current_pointer_start)
	_update_button_group_ui(_pointer_end_buttons, _current_pointer_end)

func _refresh_all_button_groups() -> void:
	_actualizar_interfaz_completa()

func _update_button_group_ui(buttons: Array[Button], selected_index: int) -> void:
	for i in range(buttons.size()):
		var b := buttons[i]
		if b == null:
			continue
		var is_sel: bool = (i == selected_index)
		_style_toggle_button(b, is_sel)

func _style_toggle_button(b: Button, active: bool) -> void:
	b.modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	
	var tm := get_node_or_null("/root/ThemeManager") if is_inside_tree() else null
	var S = tm.Slot if tm else null
	var col_act: Color = tm.get_color(S.ACCENT) if tm else _COLOR_BORDER_ACTIVE
	var col_off: Color = tm.get_color(S.ICON_MUTED) if tm else _COLOR_TEXT_SECONDARY
	var col_hov: Color = tm.get_color(S.PANEL_TEXT) if tm else _COLOR_TEXT_PRIMARY

	if active:
		sb.bg_color = _COLOR_CHIP_ACTIVE
		sb.border_color = _COLOR_BORDER_ACTIVE
		sb.set_border_width_all(1)
		b.add_theme_color_override("icon_normal_color", col_act)
		b.add_theme_color_override("icon_hover_color", col_act)
		b.add_theme_color_override("icon_pressed_color", col_act)
		b.add_theme_color_override("icon_focus_color", col_act)
		b.add_theme_color_override("font_color", col_act)
	else:
		sb.bg_color = _COLOR_CHIP_NORMAL
		sb.border_color = _COLOR_BORDER
		sb.set_border_width_all(1)
		b.add_theme_color_override("icon_normal_color", col_off)
		b.add_theme_color_override("icon_hover_color", col_hov)
		b.add_theme_color_override("icon_pressed_color", col_hov)
		b.add_theme_color_override("icon_focus_color", col_off)
		b.add_theme_color_override("font_color", _COLOR_TEXT_SECONDARY)

	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	if not active:
		sb_hover.bg_color = _COLOR_CHIP_HOVER
	b.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate() as StyleBoxFlat
	b.add_theme_stylebox_override("pressed", sb_pressed)
