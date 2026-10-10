# =============================================================================
# VECTOPEN — PROFESSIONAL STUDIO
# RUTA: res://script_gdscript/ui/pro/pro_studio.gd
# Compact right-hand studio for Professional mode. Two tabbed studio groups
# (Color | Swatches | Stroke and Transform | Text | Effects) with 20px rows.
# Bound to InspectorCore and ColorCore. The whole UI is rebuilt on theme
# change so every control always matches the active theme.
# =============================================================================
class_name ProStudio
extends PanelContainer

signal closed()

const STUDIO_WIDTH := 272.0
const PICKER_HEIGHT := 150.0
const TEXT_ALIGN_MODES: Array[String] = ["left", "center", "right", "fill"]
const TEXT_VALIGN_MODES: Array[String] = ["top", "middle", "bottom"]
const FONT_FAMILIES: Array[String] = ["Inter", "Roboto", "Segoe UI", "Arial"]
const FONT_WEIGHTS: Array[int] = [300, 400, 500, 700]
const FONT_WEIGHT_NAMES: Array[String] = ["Light", "Regular", "Medium", "Bold"]

# ── Overlapping fill / stroke swatches ──
class StudioSwatch extends Button:
	var color: Color = Color.WHITE:
		set(val):
			color = val
			queue_redraw()
	var is_stroke_ring: bool = false

	func _init(initial_color: Color = Color.WHITE, ring: bool = false) -> void:
		color = initial_color
		is_stroke_ring = ring
		custom_minimum_size = Vector2(22, 22)
		size = custom_minimum_size
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var edge := ProUIStyle.col("BORDER_STRONG")
		if is_stroke_ring:
			draw_rect(r, ProUIStyle.col("PANEL_BG"), true)
			draw_rect(r.grow(-3), color, false, 5.0)
			draw_rect(r, edge, false, 1.0)
		else:
			if color.a < 1.0:
				_draw_checker(r)
			draw_rect(r, color, true)
			draw_rect(r, edge, false, 1.0)

	func _draw_checker(r: Rect2) -> void:
		var s := 5.0
		var y := r.position.y
		var row := 0
		while y < r.end.y:
			var x := r.position.x
			var col_i := row
			while x < r.end.x:
				var c := Color(0.8, 0.8, 0.8) if col_i % 2 == 0 else Color(1, 1, 1)
				draw_rect(Rect2(x, y, minf(s, r.end.x - x), minf(s, r.end.y - y)), c, true)
				x += s
				col_i += 1
			y += s
			row += 1

# ── Rotation dial (kept as a subclass so tests and callers keep the type) ──
class RotationClockWidget extends RotationDial:
	func _init(size_px: float = 20.0) -> void:
		super._init(size_px)

	func update_theme(_bg: Color, _border: Color, _needle: Color, _tick: Color) -> void:
		queue_redraw()

# ── Structure ──
var _root: VBoxContainer
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _tabs_a: Array[Button] = []
var _tabs_b: Array[Button] = []
var _pages_a: Array[Control] = []
var _pages_b: Array[Control] = []
var _tab_a: int = 0
var _tab_b: int = 0

# Pages
var _sec_color: VBoxContainer
var _sec_swatches: VBoxContainer
var _sec_stroke: VBoxContainer
var _sec_transform: VBoxContainer
var _sec_typography: VBoxContainer
var _sec_effects: VBoxContainer

# Color
var _swatch_fill: StudioSwatch
var _swatch_stroke: StudioSwatch
var _btn_grad_solid: Button
var _btn_grad_linear: Button
var _btn_grad_radial: Button
var _btn_shape_circle: Button
var _btn_shape_triangle: Button
var _btn_shape_square: Button
var _btn_open_picker: Button
var _embedded_picker: Control = null
var _opt_color_model: OptionButton
var _is_hsl_mode: bool = false
var _slider_c1: HSlider
var _slider_c2: HSlider
var _slider_c3: HSlider
var _lbl_c1: Label
var _lbl_c2: Label
var _lbl_c3: Label
var _spin_c1: NumericField
var _spin_c2: NumericField
var _spin_c3: NumericField
var _slider_opacity: HSlider
var _lbl_opacity_val: Label
var _line_hex: LineEdit
var _palette_grid: GridContainer
var _grad_mode: String = "solid"
var _picker_shape: int = 2
var _active_color_target: String = "fill"

# Color popover (full picker)
var _color_popover: PanelContainer
var _color_popover_header_title: Label
var _pickr_instance: GestorColor

# Stroke
var _spin_stroke_w: NumericField
var _btn_stroke_solid: Button
var _btn_stroke_dash: Button
var _btn_cap_butt: Button
var _btn_cap_round: Button
var _btn_cap_square: Button
var _btn_align_center: Button
var _btn_align_inside: Button
var _btn_align_outside: Button
var _spin_dash_len: NumericField
var _spin_dash_gap: NumericField
var _row_dash_params: HBoxContainer
var _stroke_style: int = 0
var _stroke_cap: int = 0
var _stroke_align: int = 0

# Transform
var _ref_points: Array[Button] = []
var _active_ref_point: int = 4
var _spin_x: NumericField
var _spin_y: NumericField
var _spin_w: NumericField
var _spin_h: NumericField
var _btn_aspect_lock: Button
var _is_aspect_locked: bool = false
var _spin_rot: NumericField
var _clock_rot: RotationClockWidget

# Text
var _tab_typo_general: Button
var _tab_typo_parrafo: Button
var _box_typo_general: VBoxContainer
var _box_typo_parrafo: VBoxContainer
var _typo_subtab: int = 0
var _opt_font_family: OptionButton
var _opt_font_weight: OptionButton
var _spin_font_size: NumericField
var _spin_tracking: NumericField
var _btn_style_bold: Button
var _btn_style_italic: Button
var _btn_case_upper: Button
var _btn_case_lower: Button
var _btn_case_title: Button
var _swatch_text_color: StudioSwatch
var _btn_text_align_left: Button
var _btn_text_align_center: Button
var _btn_text_align_right: Button
var _btn_text_align_justify: Button
var _btn_valign_top: Button
var _btn_valign_middle: Button
var _btn_valign_bottom: Button
var _spin_leading: NumericField
var _spin_indent_l: NumericField
var _spin_indent_r: NumericField
var _spin_indent_first: NumericField
var _text_align: int = 0
var _text_valign: int = 0
var _lbl_threading_status: Label
var _btn_unlink_threading: Button
var _btn_reflow_threading: Button

# Effects (only the types the shape renderer supports)
var _chk_drop_shadow: CheckBox
var _slider_shadow_blur: HSlider
var _slider_shadow_opacity: HSlider
var _chk_inner_shadow: CheckBox
var _slider_inner_blur: HSlider
var _chk_outline: CheckBox
var _slider_outline_width: HSlider
var _chk_color_overlay: CheckBox
var _slider_overlay_opacity: HSlider
var _effect_rows: Dictionary = {}

# State
var _sync_guard: bool = false
var _has_selection: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(STUDIO_WIDTH, 0)
	z_index = 50
	_build_ui()
	_connect_cores()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		tm.theme_changed.connect(func(_mode): _rebuild())

## Full rebuild: simplest way to guarantee no control keeps a stale theme color.
func _rebuild() -> void:
	if is_instance_valid(_color_popover):
		_color_popover.queue_free()
		_color_popover = null
		_pickr_instance = null
	if is_instance_valid(_root):
		# Keep the old tree inside the scene until it is freed: its widgets are
		# still connected to the theme_changed emission currently in progress.
		_root.visible = false
		_root.queue_free()
	_build_ui()
	_connect_cores()

func _build_ui() -> void:
	_setup_panel_style()
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 0)
	add_child(_root)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 0)
	_scroll.add_child(_vbox)

	_build_color_page()
	_build_swatches_page()
	_build_stroke_page()
	_pages_a = [_sec_color, _sec_swatches, _sec_stroke]
	_vbox.add_child(_tab_group(["Color", "Muestras", "Trazo"], _pages_a, _tabs_a, _tab_a, _select_tab_a))

	_build_transform_page()
	_build_typography_page()
	_build_effects_page()
	_pages_b = [_sec_transform, _sec_typography, _sec_effects]
	_vbox.add_child(_tab_group(["Transformar", "Texto", "Efectos"], _pages_b, _tabs_b, _tab_b, _select_tab_b))

func _setup_panel_style() -> void:
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_BG"))
	sb.border_color = ProUIStyle.col("BORDER")
	sb.border_width_left = 1
	add_theme_stylebox_override("panel", sb)

# ── TABBED STUDIO GROUP ──
func _tab_group(titles: Array, pages: Array[Control], out_tabs: Array[Button], active: int, on_select: Callable) -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 0)

	var strip := PanelContainer.new()
	var strip_sb := ProUIStyle.flat(ProUIStyle.col("TOOLBAR_BG"))
	strip_sb.border_color = ProUIStyle.col("BORDER")
	strip_sb.border_width_bottom = 1
	strip_sb.border_width_top = 1
	strip.add_theme_stylebox_override("panel", strip_sb)
	group.add_child(strip)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	strip.add_child(tabs)
	out_tabs.clear()
	for i in titles.size():
		var t := Button.new()
		t.text = tr(titles[i])
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size = Vector2(0, 24)
		t.add_theme_font_size_override("font_size", ProUIStyle.FONT_SIZE)
		var idx: int = i
		t.pressed.connect(func(): on_select.call(idx))
		tabs.add_child(t)
		out_tabs.append(t)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 8)
	body.add_theme_constant_override("margin_right", 8)
	body.add_theme_constant_override("margin_top", 6)
	body.add_theme_constant_override("margin_bottom", 8)
	group.add_child(body)
	var stack := VBoxContainer.new()
	body.add_child(stack)
	for p in pages:
		stack.add_child(p)
	_apply_tab_state(out_tabs, pages, active)
	return group

func _apply_tab_state(tabs: Array[Button], pages: Array[Control], active: int) -> void:
	for i in tabs.size():
		var on := i == active
		var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_BG") if on else Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 10, 2)
		if on:
			sb.border_color = ProUIStyle.col("ACCENT")
			sb.border_width_top = 2
		var hover := sb.duplicate() as StyleBoxFlat
		if not on:
			hover.bg_color = ProUIStyle.col("BUTTON_HOVER")
		tabs[i].add_theme_stylebox_override("normal", sb)
		tabs[i].add_theme_stylebox_override("hover", hover)
		tabs[i].add_theme_stylebox_override("pressed", sb)
		tabs[i].add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var fc := ProUIStyle.col("PANEL_TEXT") if on else ProUIStyle.col("TEXT_SECONDARY")
		tabs[i].add_theme_color_override("font_color", fc)
		tabs[i].add_theme_color_override("font_hover_color", ProUIStyle.col("PANEL_TEXT"))
		tabs[i].add_theme_color_override("font_pressed_color", fc)
	for i in pages.size():
		if is_instance_valid(pages[i]):
			pages[i].visible = i == active

func _select_tab_a(idx: int) -> void:
	_tab_a = idx
	_apply_tab_state(_tabs_a, _pages_a, idx)

func _select_tab_b(idx: int) -> void:
	_tab_b = idx
	_apply_tab_state(_tabs_b, _pages_b, idx)

# ── ROW HELPERS ──
func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	return v

func _hrow(sep: int = 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func _row_label(text: String, width: float = 48.0) -> Label:
	var l := ProUIStyle.label(tr(text))
	l.custom_minimum_size.x = width
	return l

func _field(prefix: String, suffix: String, min_v: float, max_v: float, step: float, expand: bool = true) -> NumericField:
	var nf := NumericField.new(prefix, suffix, min_v, max_v, step)
	nf.custom_minimum_size = Vector2(0, ProUIStyle.ROW_H)
	if expand:
		nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return nf

func _slider(min_v: float, max_v: float, value: float, expand: bool = true) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	if expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ProUIStyle.style_slider(s)
	return s

## Segmented group of toggle buttons; returns the buttons in order.
func _segmented(parent: Control, specs: Array, active: int, on_pick: Callable) -> Array[Button]:
	var out: Array[Button] = []
	var box := _hrow(1)
	parent.add_child(box)
	for i in specs.size():
		var spec: Array = specs[i]
		var b := ProUIStyle.toggle_button(spec[0], spec[1], tr(spec[2]))
		ProUIStyle.style_toggle(b, i == active)
		var idx: int = i
		b.pressed.connect(func(): on_pick.call(idx))
		box.add_child(b)
		out.append(b)
	return out

func _set_segment(buttons: Array, active: int) -> void:
	for i in buttons.size():
		ProUIStyle.style_toggle(buttons[i], i == active)

# ── 1. COLOR ──
func _build_color_page() -> void:
	_sec_color = _page()

	var row1 := _hrow(8)
	_sec_color.add_child(row1)
	var swatches_box := Control.new()
	swatches_box.custom_minimum_size = Vector2(36, 30)
	row1.add_child(swatches_box)
	_swatch_fill = StudioSwatch.new(Color(0.2, 0.4, 0.9, 1.0), false)
	_swatch_fill.tooltip_text = tr("Relleno")
	_swatch_fill.pressed.connect(func(): _set_color_target("fill"))
	swatches_box.add_child(_swatch_fill)
	_swatch_stroke = StudioSwatch.new(Color(0.1, 0.1, 0.1, 1.0), true)
	_swatch_stroke.tooltip_text = tr("Trazo")
	_swatch_stroke.position = Vector2(12, 8)
	_swatch_stroke.pressed.connect(func(): _set_color_target("stroke"))
	swatches_box.add_child(_swatch_stroke)

	var lbl_target := ProUIStyle.label(tr("Relleno"), true, ProUIStyle.FONT_SIZE)
	lbl_target.name = "LblColorTarget"
	row1.add_child(lbl_target)

	var scene := load("res://scenes/ui/pickr_color_tool.tscn")
	if scene:
		_pickr_instance = scene.instantiate() as GestorColor
		_pickr_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pickr_instance.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_sec_color.add_child(_pickr_instance)
		if _pickr_instance and _pickr_instance.has_signal("color_actualizado"):
			_pickr_instance.color_actualizado.connect(func(c: Color):
				if not _sync_guard:
					_apply_selected_color(c)
			)
		var cur_col: Color = _swatch_fill.color if _active_color_target == "fill" else _swatch_stroke.color
		if _pickr_instance and _pickr_instance.has_method("establecer_color"):
			_pickr_instance.establecer_color(cur_col, false)

	_update_swatches_ui(_active_color_target)

# ── 2. SWATCHES ──
func _build_swatches_page() -> void:
	_sec_swatches = _page()
	_palette_grid = GridContainer.new()
	_palette_grid.columns = 10
	_palette_grid.add_theme_constant_override("h_separation", 3)
	_palette_grid.add_theme_constant_override("v_separation", 3)
	_sec_swatches.add_child(_palette_grid)
	var colors: Array[Color] = []
	for i in 10:
		var v := float(i) / 9.0
		colors.append(Color(v, v, v))
	for hex in ["#e02020", "#fa6400", "#f7b500", "#6dd400", "#20c997", "#0091ff", "#3d5afe", "#6236ff", "#b620e0", "#e91e63",
			"#ff8a80", "#ffcc80", "#fff59d", "#c5e1a5", "#80cbc4", "#81d4fa", "#9fa8da", "#b39ddb", "#ce93d8", "#f48fb1"]:
		colors.append(Color(hex))
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 18)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "#" + c.to_html(false).to_upper()
		var sb := ProUIStyle.flat(c, 2, ProUIStyle.col("BORDER"))
		b.add_theme_stylebox_override("normal", sb)
		var hov := ProUIStyle.flat(c, 2, ProUIStyle.col("ACCENT"))
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		var cc := c
		b.pressed.connect(func(): _apply_selected_color(cc))
		_palette_grid.add_child(b)

# ── 3. STROKE ──
func _build_stroke_page() -> void:
	_sec_stroke = _page()

	var row_w := _hrow(4)
	_sec_stroke.add_child(row_w)
	row_w.add_child(_row_label("Ancho"))
	_spin_stroke_w = _field("", " px", 0.0, 200.0, 0.5)
	_spin_stroke_w.value = 1.0
	_spin_stroke_w.value_changed.connect(_on_stroke_width_changed)
	row_w.add_child(_spin_stroke_w)
	var style := _segmented(row_w, [
		["", "res://icon/UI/style_solid.svg", "Trazo sólido"],
		["", "res://icon/UI/style_dashed.svg", "Trazo discontinuo"],
	], _stroke_style, _set_stroke_style)
	_btn_stroke_solid = style[0]
	_btn_stroke_dash = style[1]

	_row_dash_params = _hrow(4)
	_row_dash_params.visible = _stroke_style == 1
	_sec_stroke.add_child(_row_dash_params)
	_row_dash_params.add_child(_row_label("Guion"))
	_spin_dash_len = _field("", "", 1.0, 50.0, 1.0)
	_spin_dash_len.value = 6.0
	_spin_dash_len.tooltip_text = tr("Longitud del guion")
	_spin_dash_len.value_changed.connect(_on_dash_params_changed)
	_row_dash_params.add_child(_spin_dash_len)
	_spin_dash_gap = _field("", "", 1.0, 50.0, 1.0)
	_spin_dash_gap.value = 4.0
	_spin_dash_gap.tooltip_text = tr("Espacio entre guiones")
	_spin_dash_gap.value_changed.connect(_on_dash_params_changed)
	_row_dash_params.add_child(_spin_dash_gap)

	var row_cap := _hrow(4)
	_sec_stroke.add_child(row_cap)
	row_cap.add_child(_row_label("Remate"))
	var caps := _segmented(row_cap, [
		["", "res://icon/UI/cap_butt.svg", "Remate plano"],
		["", "res://icon/UI/cap_round.svg", "Remate redondo"],
		["", "res://icon/UI/cap_square.svg", "Remate cuadrado"],
	], _stroke_cap, _set_stroke_cap)
	_btn_cap_butt = caps[0]
	_btn_cap_round = caps[1]
	_btn_cap_square = caps[2]

	var row_align := _hrow(4)
	_sec_stroke.add_child(row_align)
	row_align.add_child(_row_label("Alinear"))
	var aligns := _segmented(row_align, [
		["", "res://icon/UI/line_medio.svg", "Trazo centrado"],
		["", "res://icon/UI/line_interior.svg", "Trazo interior"],
		["", "res://icon/UI/line_exterior.svg", "Trazo exterior"],
	], _stroke_align, _set_stroke_align)
	_btn_align_center = aligns[0]
	_btn_align_inside = aligns[1]
	_btn_align_outside = aligns[2]

# ── 4. TRANSFORM ──
func _build_transform_page() -> void:
	_sec_transform = _page()
	var main_row := _hrow(8)
	_sec_transform.add_child(main_row)

	var matrix_grid := GridContainer.new()
	matrix_grid.columns = 3
	matrix_grid.add_theme_constant_override("h_separation", 2)
	matrix_grid.add_theme_constant_override("v_separation", 2)
	matrix_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	matrix_grid.tooltip_text = tr("Punto de origen")
	main_row.add_child(matrix_grid)
	_ref_points.clear()
	for i in range(9):
		var btn_pt := Button.new()
		btn_pt.custom_minimum_size = Vector2(12, 12)
		btn_pt.focus_mode = Control.FOCUS_NONE
		_style_ref_point_button(btn_pt, i == _active_ref_point)
		var idx := i
		btn_pt.pressed.connect(func(): _set_active_ref_point(idx))
		matrix_grid.add_child(btn_pt)
		_ref_points.append(btn_pt)

	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 4)
	main_row.add_child(fields)

	var row_xy := _hrow(4)
	fields.add_child(row_xy)
	_spin_x = _field("X", "", -99999.0, 99999.0, 1.0)
	_spin_x.value_changed.connect(_on_x_changed)
	row_xy.add_child(_spin_x)
	_spin_y = _field("Y", "", -99999.0, 99999.0, 1.0)
	_spin_y.value_changed.connect(_on_y_changed)
	row_xy.add_child(_spin_y)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(22, 0)
	row_xy.add_child(pad)

	var row_wh := _hrow(4)
	fields.add_child(row_wh)
	_spin_w = _field("W", "", 1.0, 99999.0, 1.0)
	_spin_w.value = 100.0
	_spin_w.value_changed.connect(_on_w_changed)
	row_wh.add_child(_spin_w)
	_spin_h = _field("H", "", 1.0, 99999.0, 1.0)
	_spin_h.value = 100.0
	_spin_h.value_changed.connect(_on_h_changed)
	row_wh.add_child(_spin_h)
	_btn_aspect_lock = ProUIStyle.toggle_button("", "res://icon/UI/lock.svg", tr("Mantener proporción"))
	ProUIStyle.style_toggle(_btn_aspect_lock, _is_aspect_locked)
	_btn_aspect_lock.pressed.connect(_toggle_aspect_lock)
	row_wh.add_child(_btn_aspect_lock)

	var row_r := _hrow(4)
	fields.add_child(row_r)
	_spin_rot = _field("R", "°", -360.0, 360.0, 0.5)
	_spin_rot.value_changed.connect(func(v: float):
		if not _sync_guard:
			_clock_rot.angle_degrees = v
			_on_rotation_changed(v)
	)
	row_r.add_child(_spin_rot)
	_clock_rot = RotationClockWidget.new(20.0)
	_clock_rot.tooltip_text = tr("Rotación (Shift: pasos de 15°)")
	_clock_rot.angle_changed.connect(func(deg: float):
		if not _sync_guard:
			_spin_rot.set_value_silent(deg)
			_on_rotation_changed(deg)
	)
	row_r.add_child(_clock_rot)
	var pad2 := Control.new()
	pad2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_r.add_child(pad2)

# ── 5. TEXT ──
func _build_typography_page() -> void:
	_sec_typography = _page()
	var sub := _segmented(_sec_typography, [
		["Carácter", "", "Carácter"],
		["Párrafo", "", "Párrafo"],
	], _typo_subtab, _switch_typography_subtab)
	_tab_typo_general = sub[0]
	_tab_typo_parrafo = sub[1]
	for b in sub:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub[0].get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_box_typo_general = VBoxContainer.new()
	_box_typo_general.add_theme_constant_override("separation", 5)
	_sec_typography.add_child(_box_typo_general)

	# Fila 1: Familia tipográfica y peso
	var row_font := _hrow(4)
	_box_typo_general.add_child(row_font)
	_opt_font_family = OptionButton.new()
	for f in FONT_FAMILIES:
		_opt_font_family.add_item(f)
	_opt_font_family.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ProUIStyle.style_option(_opt_font_family)
	_opt_font_family.item_selected.connect(func(i: int):
		if not _sync_guard:
			_apply_inspector_prop("font_family", FONT_FAMILIES[i])
	)
	row_font.add_child(_opt_font_family)
	_opt_font_weight = OptionButton.new()
	for w in FONT_WEIGHT_NAMES:
		_opt_font_weight.add_item(w)
	_opt_font_weight.select(1)
	_opt_font_weight.custom_minimum_size.x = 82
	ProUIStyle.style_option(_opt_font_weight)
	_opt_font_weight.item_selected.connect(func(i: int):
		if not _sync_guard:
			_apply_inspector_prop("font_weight", FONT_WEIGHTS[i])
	)
	row_font.add_child(_opt_font_weight)

	# Fila 2: Tamaño y espaciado entre letras (Tracking)
	var row_size := _hrow(4)
	_box_typo_general.add_child(row_size)
	_spin_font_size = _field("", " pt", 4.0, 500.0, 1.0)
	_spin_font_size.value = 16.0
	_spin_font_size.tooltip_text = tr("Tamaño de fuente")
	_spin_font_size.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("font_size", v)
	)
	row_size.add_child(_spin_font_size)
	_spin_tracking = _field("VA ", "", -100.0, 500.0, 1.0)
	_spin_tracking.value = 0.0
	_spin_tracking.tooltip_text = tr("Espaciado entre letras")
	_spin_tracking.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("letter_spacing", v)
	)
	row_size.add_child(_spin_tracking)

	# Fila 3: Estilos rápidos (B, I) y Transformación de texto (AA, aa, Aa)
	var row_styles := _hrow(4)
	_box_typo_general.add_child(row_styles)
	_btn_style_bold = ProUIStyle.toggle_button("B", "", tr("Negrita"))
	_btn_style_bold.custom_minimum_size = Vector2(24, ProUIStyle.ROW_H)
	_btn_style_bold.pressed.connect(_toggle_style_bold)
	ProUIStyle.style_toggle(_btn_style_bold, false)
	row_styles.add_child(_btn_style_bold)

	_btn_style_italic = ProUIStyle.toggle_button("I", "", tr("Cursiva"))
	_btn_style_italic.custom_minimum_size = Vector2(24, ProUIStyle.ROW_H)
	_btn_style_italic.pressed.connect(_toggle_style_italic)
	ProUIStyle.style_toggle(_btn_style_italic, false)
	row_styles.add_child(_btn_style_italic)

	var case_sep := VSeparator.new()
	row_styles.add_child(case_sep)

	_btn_case_upper = ProUIStyle.action_button("AA", "", tr("MAYÚSCULAS"))
	_btn_case_upper.custom_minimum_size = Vector2(26, ProUIStyle.ROW_H)
	_btn_case_upper.pressed.connect(func(): _apply_case_transform("upper"))
	row_styles.add_child(_btn_case_upper)

	_btn_case_lower = ProUIStyle.action_button("aa", "", tr("minúsculas"))
	_btn_case_lower.custom_minimum_size = Vector2(26, ProUIStyle.ROW_H)
	_btn_case_lower.pressed.connect(func(): _apply_case_transform("lower"))
	row_styles.add_child(_btn_case_lower)

	_btn_case_title = ProUIStyle.action_button("Aa", "", tr("Tipo Título"))
	_btn_case_title.custom_minimum_size = Vector2(26, ProUIStyle.ROW_H)
	_btn_case_title.pressed.connect(func(): _apply_case_transform("title"))
	row_styles.add_child(_btn_case_title)

	# Fila 4: Color de texto con swatch interactivo
	var row_color := _hrow(4)
	_box_typo_general.add_child(row_color)
	row_color.add_child(_row_label("Color", 44.0))
	_swatch_text_color = StudioSwatch.new(Color.WHITE, false)
	_swatch_text_color.custom_minimum_size = Vector2(28, 20)
	_swatch_text_color.tooltip_text = tr("Color de texto — Clic para abrir paleta")
	_swatch_text_color.pressed.connect(func():
		_set_color_target("fill")
		_select_tab_a(0)
	)
	row_color.add_child(_swatch_text_color)
	var lbl_col_hint := ProUIStyle.label(tr("Color del texto (Relleno)"), false, ProUIStyle.FONT_SIZE_SMALL)
	lbl_col_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_color.add_child(lbl_col_hint)

	# ── Párrafo ──
	_box_typo_parrafo = VBoxContainer.new()
	_box_typo_parrafo.add_theme_constant_override("separation", 5)
	_sec_typography.add_child(_box_typo_parrafo)

	# Fila 1 Párrafo: Alineación horizontal
	var row_align := _hrow(4)
	_box_typo_parrafo.add_child(row_align)
	row_align.add_child(_row_label("Alinear", 44.0))
	var aligns := _segmented(row_align, [
		["", "res://icon/UI/align-left.svg", "Alinear a la izquierda"],
		["", "res://icon/UI/align-center.svg", "Centrar"],
		["", "res://icon/UI/align-right.svg", "Alinear a la derecha"],
		["", "res://icon/UI/align-justify.svg", "Justificar"],
	], _text_align, _set_text_alignment)
	_btn_text_align_left = aligns[0]
	_btn_text_align_center = aligns[1]
	_btn_text_align_right = aligns[2]
	_btn_text_align_justify = aligns[3]

	# Fila 2 Párrafo: Alineación vertical
	var row_valign := _hrow(4)
	_box_typo_parrafo.add_child(row_valign)
	row_valign.add_child(_row_label("V-Align", 44.0))
	var valigns := _segmented(row_valign, [
		["Arriba", "", "Alinear arriba"],
		["Centro", "", "Alinear al centro vertical"],
		["Abajo", "", "Alinear abajo"],
	], _text_valign, _set_text_valign)
	_btn_valign_top = valigns[0]
	_btn_valign_middle = valigns[1]
	_btn_valign_bottom = valigns[2]

	# Fila 3 Párrafo: Interlineado (Leading)
	var row_lead := _hrow(4)
	_box_typo_parrafo.add_child(row_lead)
	row_lead.add_child(_row_label("Interlín.", 44.0))
	_spin_leading = _field("", " px", 0.0, 300.0, 1.0)
	_spin_leading.tooltip_text = tr("Interlineado")
	_spin_leading.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("line_spacing", v)
	)
	row_lead.add_child(_spin_leading)

	# Fila 3b Párrafo: Sangrías (Publisher: izquierda / derecha / primera línea)
	var row_indent := _hrow(4)
	_box_typo_parrafo.add_child(row_indent)
	row_indent.add_child(_row_label("Sangría", 44.0))
	_spin_indent_l = _field("Iz ", " px", 0.0, 500.0, 1.0)
	_spin_indent_l.tooltip_text = tr("Sangría izquierda")
	_spin_indent_l.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("indent_left", v)
	)
	row_indent.add_child(_spin_indent_l)
	_spin_indent_r = _field("De ", " px", 0.0, 500.0, 1.0)
	_spin_indent_r.tooltip_text = tr("Sangría derecha")
	_spin_indent_r.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("indent_right", v)
	)
	row_indent.add_child(_spin_indent_r)
	_spin_indent_first = _field("1ª ", " px", -500.0, 500.0, 1.0)
	_spin_indent_first.tooltip_text = tr("Sangría de primera línea (negativa = francesa)")
	_spin_indent_first.value_changed.connect(func(v: float):
		if not _sync_guard:
			_apply_inspector_prop("indent_first", v)
	)
	row_indent.add_child(_spin_indent_first)

	# Fila 4 Párrafo: Encadenamiento de marcos de texto (Text Threading)
	var sep_flow := HSeparator.new()
	_box_typo_parrafo.add_child(sep_flow)
	var lbl_thread_hdr := ProUIStyle.label(tr("Flujo de texto (Threading)"), true, ProUIStyle.FONT_SIZE_SMALL)
	_box_typo_parrafo.add_child(lbl_thread_hdr)

	_lbl_threading_status = ProUIStyle.label(tr("Marco independiente"), false, ProUIStyle.FONT_SIZE_SMALL)
	_lbl_threading_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box_typo_parrafo.add_child(_lbl_threading_status)

	var row_thread_btns := _hrow(4)
	_box_typo_parrafo.add_child(row_thread_btns)
	_btn_unlink_threading = ProUIStyle.action_button(tr("Romper enlace"), "", tr("Desvincular marco siguiente de la cadena"))
	_btn_unlink_threading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_unlink_threading.pressed.connect(_on_unlink_threading_pressed)
	row_thread_btns.add_child(_btn_unlink_threading)

	_btn_reflow_threading = ProUIStyle.action_button(tr("Reorganizar"), "", tr("Recalcular flujo de texto en la cadena"))
	_btn_reflow_threading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_reflow_threading.pressed.connect(_on_reflow_threading_pressed)
	row_thread_btns.add_child(_btn_reflow_threading)

	_switch_typography_subtab(_typo_subtab)

# ── 6. EFFECTS ──
func _build_effects_page() -> void:
	_sec_effects = _page()
	_effect_rows.clear()
	var ds := _effect_row("drop_shadow", "Sombra paralela", "Desenfoque", 0, 60, 6)
	_chk_drop_shadow = ds[0]
	_slider_shadow_blur = ds[1]
	_slider_shadow_opacity = _effect_extra_slider("drop_shadow", "Opacidad", 0, 100, 40)
	var ins := _effect_row("inner_shadow", "Sombra interior", "Desenfoque", 0, 50, 4)
	_chk_inner_shadow = ins[0]
	_slider_inner_blur = ins[1]
	var ol := _effect_row("outline", "Contorno", "Grosor", 0, 30, 2)
	_chk_outline = ol[0]
	_slider_outline_width = ol[1]
	var co := _effect_row("color_overlay", "Superposición de color", "Opacidad", 0, 100, 50)
	_chk_color_overlay = co[0]
	_slider_overlay_opacity = co[1]

## Checkbox header + parameter slider row shown while the effect is enabled.
func _effect_row(fx_type: String, title: String, param: String, min_v: float, max_v: float, def: float) -> Array:
	var chk := CheckBox.new()
	chk.text = tr(title)
	ProUIStyle.style_check(chk)
	_sec_effects.add_child(chk)
	var params := VBoxContainer.new()
	params.add_theme_constant_override("separation", 3)
	params.visible = false
	_sec_effects.add_child(params)
	var row := _hrow(4)
	params.add_child(row)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 16
	row.add_child(spacer)
	row.add_child(_row_label(param, 64))
	var s := _slider(min_v, max_v, def)
	row.add_child(s)
	chk.toggled.connect(func(on: bool):
		params.visible = on
		if not _sync_guard:
			_commit_effects()
	)
	s.value_changed.connect(func(_v: float):
		if not _sync_guard:
			_commit_effects()
	)
	_effect_rows[fx_type] = {"check": chk, "params": params, "slider": s}
	return [chk, s]

func _effect_extra_slider(fx_type: String, param: String, min_v: float, max_v: float, def: float) -> HSlider:
	var params: VBoxContainer = _effect_rows[fx_type]["params"]
	var row := _hrow(4)
	params.add_child(row)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 16
	row.add_child(spacer)
	row.add_child(_row_label(param, 64))
	var s := _slider(min_v, max_v, def)
	row.add_child(s)
	s.value_changed.connect(func(_v: float):
		if not _sync_guard:
			_commit_effects()
	)
	return s

const CANONICAL_FX_NAMES := {
	"drop_shadow": "Drop Shadow",
	"inner_shadow": "Inner Shadow",
	"outline": "Outline",
	"color_overlay": "Color Overlay",
	"blur": "Blur",
	"gradient_overlay": "Gradient Overlay",
	"inner_glow": "Inner Glow",
	"3d": "3D",
	"threed": "3D",
}

## Writes the effect list back through InspectorCore, preserving any effect
## types this panel doesn't edit.
func _commit_effects() -> void:
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("apply"):
		return
	var current: Array = []
	var props: Dictionary = ic.current_props() if ic.has_method("current_props") else {}
	if props.has("effects") and not props["effects"].get("mixed", false) and props["effects"]["value"] is Array:
		current = (props["effects"]["value"] as Array).duplicate(true)
	var managed := _effect_rows.keys()
	var out: Array = []
	for fx in current:
		if fx is Dictionary and not managed.has(_fx_type(fx)):
			out.append(fx)
	for t in managed:
		var row: Dictionary = _effect_rows[t]
		if not (row["check"] as CheckBox).button_pressed:
			continue
		var prev := {}
		for fx in current:
			if fx is Dictionary and _fx_type(fx) == t:
				prev = fx.duplicate(true)
		var v: float = (row["slider"] as HSlider).value
		prev["type"] = CANONICAL_FX_NAMES.get(t, t.capitalize())
		prev["enabled"] = true
		match t:
			"drop_shadow":
				prev["blur"] = v
				prev["offset_x"] = prev.get("offset_x", 4.0)
				prev["offset_y"] = prev.get("offset_y", 4.0)
				var alpha: float = _slider_shadow_opacity.value / 100.0 if is_instance_valid(_slider_shadow_opacity) else 0.4
				prev["color"] = Color(0, 0, 0, alpha)
			"inner_shadow":
				prev["blur"] = v
				prev["offset_x"] = prev.get("offset_x", 2.0)
				prev["offset_y"] = prev.get("offset_y", 2.0)
				prev["color"] = prev.get("color", Color(0, 0, 0, 0.5))
			"outline":
				prev["width"] = v
				prev["color"] = prev.get("color", Color(0, 0, 0, 1))
			"color_overlay":
				var c: Color = prev.get("color", Color(0.2, 0.4, 0.9)) if prev.get("color") is Color else Color(0.2, 0.4, 0.9)
				c.a = v / 100.0
				prev["color"] = c
		out.append(prev)
	ic.apply("effects", out)

func _fx_type(fx: Dictionary) -> String:
	return String(fx.get("type", "")).to_lower().replace(" ", "_")

func _sync_effects(effects: Array) -> void:
	var prev_guard := _sync_guard
	_sync_guard = true
	for t in _effect_rows.keys():
		var row: Dictionary = _effect_rows[t]
		var found: Dictionary = {}
		for fx in effects:
			if fx is Dictionary and _fx_type(fx) == t and bool(fx.get("enabled", true)):
				found = fx
		var on := not found.is_empty()
		(row["check"] as CheckBox).set_pressed_no_signal(on)
		(row["params"] as Control).visible = on
		if not on:
			continue
		var s: HSlider = row["slider"]
		match t:
			"drop_shadow":
				s.set_value_no_signal(float(found.get("blur", 6.0)))
				if found.get("color") is Color and is_instance_valid(_slider_shadow_opacity):
					_slider_shadow_opacity.set_value_no_signal((found["color"] as Color).a * 100.0)
			"inner_shadow":
				s.set_value_no_signal(float(found.get("blur", 4.0)))
			"outline":
				s.set_value_no_signal(float(found.get("width", 2.0)))
			"color_overlay":
				if found.get("color") is Color:
					s.set_value_no_signal((found["color"] as Color).a * 100.0)
	_sync_guard = prev_guard

# ── CORE WIRING ──
func _connect_cores() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed"):
		if not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)
		if ic.has_method("current_props"):
			_on_inspector_changed(ic.current_props())
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		if cc.has_signal("changed") and not cc.changed.is_connected(_on_color_core_changed):
			cc.changed.connect(_on_color_core_changed)
		_on_color_core_changed(cc.fill_color, cc.stroke_color, cc.active_target)

func _set_color_target(target: String) -> void:
	_active_color_target = target
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_target"):
		cc.set_target(target)
	_update_swatches_ui(target)
	var active_c: Color = _swatch_fill.color if target == "fill" else _swatch_stroke.color
	_push_to_picker(active_c)
	_update_color_sliders(active_c)

func _update_swatches_ui(target: String) -> void:
	if not is_instance_valid(_swatch_fill) or not is_instance_valid(_swatch_stroke):
		return
	# The active target is drawn on top, like in desktop vector editors.
	var parent := _swatch_fill.get_parent()
	if parent == null:
		return
	if target == "fill":
		parent.move_child(_swatch_fill, parent.get_child_count() - 1)
	else:
		parent.move_child(_swatch_stroke, parent.get_child_count() - 1)

func _toggle_color_mode(hsl: bool) -> void:
	_is_hsl_mode = hsl
	if is_instance_valid(_opt_color_model) and _opt_color_model.selected != (1 if hsl else 0):
		_opt_color_model.select(1 if hsl else 0)
	var labels: Array = ["H", "S", "L"] if hsl else ["R", "G", "B"]
	var maxes: Array = [360.0, 100.0, 100.0] if hsl else [255.0, 255.0, 255.0]
	var lbls := [_lbl_c1, _lbl_c2, _lbl_c3]
	var sliders := [_slider_c1, _slider_c2, _slider_c3]
	var spins := [_spin_c1, _spin_c2, _spin_c3]
	for i in 3:
		lbls[i].text = labels[i]
		sliders[i].max_value = maxes[i]
		spins[i].max_value = maxes[i]
	_update_color_sliders(_get_active_color())

func _get_active_color() -> Color:
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("active_color"):
		return cc.active_color()
	return _swatch_fill.color if is_instance_valid(_swatch_fill) else Color.WHITE

func _update_color_sliders(c: Color) -> void:
	if not is_instance_valid(_slider_c1):
		return
	_sync_guard = true
	var vals: Array = [c.h * 360.0, c.s * 100.0, c.v * 100.0] if _is_hsl_mode else [c.r * 255.0, c.g * 255.0, c.b * 255.0]
	var sliders := [_slider_c1, _slider_c2, _slider_c3]
	var spins := [_spin_c1, _spin_c2, _spin_c3]
	for i in 3:
		sliders[i].value = vals[i]
		spins[i].value = roundf(vals[i])
	_slider_opacity.value = c.a * 100.0
	_lbl_opacity_val.text = str(roundi(c.a * 100.0)) + "%"
	_line_hex.text = c.to_html(false).to_upper()
	_sync_guard = false

func _on_channel_changed(channel_idx: int, val: float) -> void:
	if _sync_guard:
		return
	var cur := _get_active_color()
	var vals := [_slider_c1.value, _slider_c2.value, _slider_c3.value]
	vals[channel_idx] = val
	var new_col: Color
	if _is_hsl_mode:
		new_col = Color.from_hsv(vals[0] / 360.0, vals[1] / 100.0, vals[2] / 100.0, cur.a)
	else:
		new_col = Color(vals[0] / 255.0, vals[1] / 255.0, vals[2] / 255.0, cur.a)
	_apply_selected_color(new_col)

func _on_opacity_slider_changed(val: float) -> void:
	if _sync_guard:
		return
	_lbl_opacity_val.text = str(roundi(val)) + "%"
	var cur := _get_active_color()
	cur.a = val / 100.0
	_apply_selected_color(cur)

func _on_hex_submitted(new_text: String) -> void:
	var clean := new_text.strip_edges().lstrip("#")
	if clean.is_valid_html_color():
		var col := Color.html(clean)
		col.a = _get_active_color().a if clean.length() <= 6 else col.a
		_apply_selected_color(col)

func _apply_selected_color(c: Color) -> void:
	if _active_color_target == "fill" and is_instance_valid(_swatch_fill):
		_swatch_fill.color = c
	elif _active_color_target == "stroke" and is_instance_valid(_swatch_stroke):
		_swatch_stroke.color = c
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		if cc.has_method("set_color"):
			cc.set_color(c, _active_color_target)
		elif cc.has_method("apply_color"):
			cc.apply_color(c)
	_update_color_sliders(c)
	_push_to_picker(c)

func _push_to_picker(c: Color) -> void:
	if is_instance_valid(_embedded_picker) and _embedded_picker.has_method("set_color") and not _sync_guard:
		_sync_guard = true
		_embedded_picker.set_color(c)
		_sync_guard = false

func _on_color_core_changed(fill: Color, stroke: Color, target: String) -> void:
	_active_color_target = target
	if is_instance_valid(_swatch_fill):
		_swatch_fill.color = fill
	if is_instance_valid(_swatch_stroke):
		_swatch_stroke.color = stroke
	_update_swatches_ui(target)
	var active_c := fill if target == "fill" else stroke
	_update_color_sliders(active_c)
	_push_to_picker(active_c)

func _set_gradient_mode(mode: String) -> void:
	_grad_mode = mode
	if is_instance_valid(_btn_grad_solid):
		_set_segment([_btn_grad_solid, _btn_grad_linear, _btn_grad_radial], ["solid", "linear", "radial"].find(mode))
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_fill_mode"):
		cc.set_fill_mode(mode)

func _set_picker_shape(shape_idx: int) -> void:
	_picker_shape = shape_idx
	_set_segment([_btn_shape_circle, _btn_shape_triangle, _btn_shape_square], shape_idx)
	if is_instance_valid(_embedded_picker) and "current_mode" in _embedded_picker:
		_embedded_picker.current_mode = shape_idx

# ── TRANSFORM ──
func _set_active_ref_point(idx: int) -> void:
	_active_ref_point = idx
	for i in range(_ref_points.size()):
		_style_ref_point_button(_ref_points[i], i == idx)

func _style_ref_point_button(btn: Button, active: bool) -> void:
	var accent := ProUIStyle.col("ACCENT")
	var sb := ProUIStyle.flat(accent if active else ProUIStyle.col("INPUT_BG"), 2,
		accent if active else ProUIStyle.col("BORDER_STRONG"))
	btn.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.border_color = accent
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _toggle_aspect_lock() -> void:
	_is_aspect_locked = not _is_aspect_locked
	ProUIStyle.style_toggle(_btn_aspect_lock, _is_aspect_locked)

func _on_x_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("pos_x", val)

func _on_y_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("pos_y", val)

func _on_w_changed(val: float) -> void:
	if _sync_guard: return
	_apply_extent("width", val)

func _on_h_changed(val: float) -> void:
	if _sync_guard: return
	_apply_extent("height", val)

## Width/height edit; with the proportion lock on, both change in one undo step.
func _apply_extent(prop: String, val: float) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null:
		return
	if not _is_aspect_locked or not ic.has_method("apply_multi"):
		ic.apply(prop, val)
		return
	var props: Dictionary = ic.current_props()
	if not props.has("width") or not props.has("height") or props["width"]["mixed"] or props["height"]["mixed"]:
		ic.apply(prop, val)
		return
	var w: float = props["width"]["value"]
	var h: float = props["height"]["value"]
	if w <= 0.0 or h <= 0.0:
		ic.apply(prop, val)
		return
	var ratio := h / w
	var nw := val if prop == "width" else val / ratio
	var nh := val if prop == "height" else val * ratio
	ic.apply_multi({"width": nw, "height": nh}, "Escalar proporcional")

func _on_rotation_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("rotation", val)

# ── STROKE ──
func _on_stroke_width_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("stroke_width", val)

func _set_stroke_style(style_idx: int) -> void:
	_stroke_style = style_idx
	_set_segment([_btn_stroke_solid, _btn_stroke_dash], style_idx)
	_row_dash_params.visible = style_idx == 1
	if not _sync_guard:
		_apply_inspector_prop("stroke_style", style_idx)

func _set_stroke_cap(cap_idx: int) -> void:
	_stroke_cap = cap_idx
	_set_segment([_btn_cap_butt, _btn_cap_round, _btn_cap_square], cap_idx)
	if _sync_guard:
		return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply_multi"):
		ic.apply_multi({"stroke_cap_start": cap_idx, "stroke_cap_end": cap_idx}, "Remate de trazo")

func _set_stroke_align(align_idx: int) -> void:
	_stroke_align = align_idx
	_set_segment([_btn_align_center, _btn_align_inside, _btn_align_outside], align_idx)
	if not _sync_guard:
		_apply_inspector_prop("stroke_align", align_idx)

func _on_dash_params_changed(_v: float) -> void:
	if _sync_guard: return
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply_multi"):
		ic.apply_multi({"stroke_dash_len": _spin_dash_len.value, "stroke_dash_gap": _spin_dash_gap.value}, "Guiones de trazo")

# ── TEXT ──
func _switch_typography_subtab(idx: int) -> void:
	_typo_subtab = idx
	_set_segment([_tab_typo_general, _tab_typo_parrafo], idx)
	if is_instance_valid(_box_typo_general):
		_box_typo_general.visible = idx == 0
	if is_instance_valid(_box_typo_parrafo):
		_box_typo_parrafo.visible = idx == 1

func _set_text_alignment(align_idx: int) -> void:
	_text_align = align_idx
	_set_segment([_btn_text_align_left, _btn_text_align_center, _btn_text_align_right, _btn_text_align_justify], align_idx)
	if not _sync_guard:
		_apply_inspector_prop("text_align", TEXT_ALIGN_MODES[align_idx])

func _set_text_valign(valign_idx: int) -> void:
	_text_valign = valign_idx
	_set_segment([_btn_valign_top, _btn_valign_middle, _btn_valign_bottom], valign_idx)
	if not _sync_guard:
		_apply_inspector_prop("text_valign", TEXT_VALIGN_MODES[valign_idx])

func _toggle_style_bold() -> void:
	var to_bold := true
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		var props: Dictionary = ic.current_props()
		if props.has("font_weight") and not bool(props["font_weight"].get("mixed", false)):
			to_bold = int(props["font_weight"].get("value", 400)) < 700
	if not _sync_guard:
		_apply_inspector_prop("font_weight", 700 if to_bold else 400)
	ProUIStyle.style_toggle(_btn_style_bold, to_bold)

func _toggle_style_italic() -> void:
	var to_italic := true
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		var props: Dictionary = ic.current_props()
		if props.has("font_italic") and not bool(props["font_italic"].get("mixed", false)):
			to_italic = not bool(props["font_italic"].get("value", false))
	if not _sync_guard:
		_apply_inspector_prop("font_italic", to_italic)
	ProUIStyle.style_toggle(_btn_style_italic, to_italic)

func _apply_case_transform(mode: String) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic == null or not ic.has_method("selection"):
		return
	for shape in ic.selection():
		var cur = ic._read(shape, "text")
		if cur == null:
			continue
		var t: String = String(cur)
		match mode:
			"upper":
				t = t.to_upper()
			"lower":
				t = t.to_lower()
			"title":
				t = t.capitalize()
		ic.apply("text", t)

func _threading_targets() -> Array:
	var sm := get_node_or_null("/root/SelectionManager")
	if sm and sm.has_method("get_selected"):
		return sm.get_selected()
	return []

func _on_unlink_threading_pressed() -> void:
	for node in _threading_targets():
		ParagraphThreading.unlink_next(node)

func _on_reflow_threading_pressed() -> void:
	var heads: Array = []
	for node in _threading_targets():
		var head := ParagraphThreading.get_chain_head(node)
		if is_instance_valid(head) and head not in heads:
			heads.append(head)
	for head in heads:
		ParagraphThreading.reflow_chain(head)

func _apply_inspector_prop(prop: String, val: Variant) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(prop, val)

# ── SYNC FROM INSPECTORCORE ──
func _prop(props: Dictionary, key: String) -> Variant:
	if props.has(key) and not props[key].get("mixed", false):
		return props[key]["value"]
	return null

func _on_inspector_changed(props: Dictionary) -> void:
	if not is_instance_valid(_spin_x):
		return
	_sync_guard = true
	_has_selection = not props.is_empty() and props.has("pos_x")
	var v: Variant
	v = _prop(props, "pos_x")
	if v != null: _spin_x.value = v
	v = _prop(props, "pos_y")
	if v != null: _spin_y.value = v
	v = _prop(props, "width")
	if v != null: _spin_w.value = v
	v = _prop(props, "height")
	if v != null: _spin_h.value = v
	v = _prop(props, "rotation")
	if v != null:
		_spin_rot.value = v
		_clock_rot.angle_degrees = v
	v = _prop(props, "stroke_width")
	if v != null: _spin_stroke_w.value = v
	v = _prop(props, "stroke_style")
	if v != null: _set_stroke_style(int(v))
	v = _prop(props, "stroke_cap_start")
	if v != null: _set_stroke_cap(clampi(int(v), 0, 2))
	v = _prop(props, "stroke_align")
	if v != null: _set_stroke_align(clampi(int(v), 0, 2))
	v = _prop(props, "stroke_dash_len")
	if v != null: _spin_dash_len.value = v
	v = _prop(props, "stroke_dash_gap")
	if v != null: _spin_dash_gap.value = v
	v = _prop(props, "fill_color")
	if v is Color and is_instance_valid(_swatch_fill): _swatch_fill.color = v
	v = _prop(props, "stroke_color")
	if v is Color and is_instance_valid(_swatch_stroke): _swatch_stroke.color = v
	var active_c: Color = _swatch_fill.color if _active_color_target == "fill" else _swatch_stroke.color
	_update_color_sliders(active_c)
	_push_to_picker(active_c)
	v = _prop(props, "font_size")
	if v != null: _spin_font_size.value = v
	v = _prop(props, "letter_spacing")
	if v != null: _spin_tracking.value = v
	v = _prop(props, "line_spacing")
	if v != null: _spin_leading.value = v
	v = _prop(props, "indent_left")
	if v != null and is_instance_valid(_spin_indent_l): _spin_indent_l.value = v
	v = _prop(props, "indent_right")
	if v != null and is_instance_valid(_spin_indent_r): _spin_indent_r.value = v
	v = _prop(props, "indent_first")
	if v != null and is_instance_valid(_spin_indent_first): _spin_indent_first.value = v
	v = _prop(props, "font_family")
	if v != null:
		var fi := FONT_FAMILIES.find(String(v))
		if fi >= 0: _opt_font_family.select(fi)
	v = _prop(props, "font_weight")
	if v != null:
		var wi := FONT_WEIGHTS.find(int(v))
		if wi >= 0: _opt_font_weight.select(wi)
	v = _prop(props, "text_align")
	if v != null:
		var ai := TEXT_ALIGN_MODES.find(String(v))
		if ai >= 0: _set_text_alignment(ai)
	v = _prop(props, "effects")
	_sync_effects(v if v is Array else [])
	_sync_guard = false

# ── FULL COLOR PICKER POPOVER ──
func _ensure_color_popover() -> void:
	if is_instance_valid(_color_popover):
		return
	_color_popover = PanelContainer.new()
	_color_popover.top_level = true
	_color_popover.visible = false
	_color_popover.z_index = 250
	var sb := ProUIStyle.flat(ProUIStyle.col("PANEL_SURFACE"), 6, ProUIStyle.col("BORDER_STRONG"), 8, 8)
	sb.shadow_color = Color(0, 0, 0, 0.35 if ProUIStyle.is_dark() else 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	_color_popover.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_color_popover.add_child(vbox)
	var header := _hrow(4)
	_color_popover_header_title = ProUIStyle.label(tr("Selector de color"))
	_color_popover_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_color_popover_header_title)
	var btn_close := ProUIStyle.action_button("✕", "", tr("Cerrar"))
	btn_close.pressed.connect(func(): _color_popover.visible = false)
	header.add_child(btn_close)
	vbox.add_child(header)

	var scene := load("res://scenes/ui/pickr_color_tool.tscn")
	if scene:
		_pickr_instance = scene.instantiate() as GestorColor
		vbox.add_child(_pickr_instance)
		if _pickr_instance and _pickr_instance.has_signal("color_actualizado"):
			_pickr_instance.color_actualizado.connect(func(col: Color): _apply_selected_color(col))
	add_child(_color_popover)

func _open_color_popover(target: String, anchor: Control) -> void:
	_ensure_color_popover()
	if not is_instance_valid(_color_popover):
		return
	if _color_popover.visible and _active_color_target == target:
		_color_popover.visible = false
		return
	_active_color_target = target
	if is_instance_valid(_color_popover_header_title):
		match target:
			"fill": _color_popover_header_title.text = tr("Relleno")
			"stroke": _color_popover_header_title.text = tr("Trazo")
			_: _color_popover_header_title.text = tr("Selector de color")
	var cur_col: Color = _swatch_fill.color if target == "fill" else _swatch_stroke.color
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_target"):
		cc.set_target(target)
	if is_instance_valid(_pickr_instance) and _pickr_instance.has_method("establecer_color"):
		_pickr_instance.establecer_color(cur_col, false)
	_color_popover.visible = true
	_color_popover.reset_size()
	var pop_w: float = _color_popover.size.x if _color_popover.size.x > 0 else 240.0
	var pos_x: float = global_position.x - pop_w - 8.0
	var pos_y: float = anchor.global_position.y - 20.0
	var vp_rect := get_viewport_rect()
	pos_y = clampf(pos_y, 40.0, maxf(40.0, vp_rect.size.y - _color_popover.size.y - 10.0))
	_color_popover.global_position = Vector2(pos_x, pos_y)

func _input(event: InputEvent) -> void:
	if not (is_instance_valid(_color_popover) and _color_popover.visible):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_color_popover.visible = false
		if get_viewport():
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		var mp := get_global_mouse_position()
		for c in [_color_popover, _swatch_fill, _swatch_stroke, _btn_open_picker]:
			if is_instance_valid(c) and c.get_global_rect().has_point(mp):
				return
		_color_popover.visible = false
