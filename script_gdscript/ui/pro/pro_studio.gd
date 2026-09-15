# =============================================================================
# VECTOPEN — PROFESSIONAL STUDIO (AFFINITY STUDIO + INDESIGN PUBLICATION)
# RUTA: res://script_gdscript/ui/pro/pro_studio.gd
# Panel lateral derecho de alta densidad para Vectopen Professional UI
# Conectado bidireccionalmente a InspectorCore, ColorCore y MoveTool
# =============================================================================
class_name ProStudio
extends PanelContainer

signal closed()

# ── Tokens de Color (Dark Studio Theme - Affinity Style) ──
const _C_BG_PANEL    := Color(0.12, 0.12, 0.13, 1.0) # #1f1f21
const _C_BG_HEADER   := Color(0.15, 0.15, 0.17, 1.0) # #26262b
const _C_BG_CARD     := Color(0.16, 0.16, 0.18, 1.0) # #29292e
const _C_BG_INPUT    := Color(0.10, 0.10, 0.11, 1.0) # #19191c
const _C_BORDER      := Color(0.22, 0.22, 0.25, 1.0) # #383840
const _C_TEXT        := Color(0.92, 0.92, 0.94, 1.0) # #ebebf0
const _C_MUTED       := Color(0.55, 0.55, 0.58, 1.0) # #8c8c94
const _C_ACCENT      := Color(0.04, 0.52, 1.00, 1.0) # #0a84ff
const _C_ACTIVE_TAB  := Color(0.25, 0.25, 0.29, 1.0) # #40404a

# ── Botón Swatch personalizado con dibujo ──
class StudioSwatch extends Button:
	var color: Color = Color.WHITE:
		set(val):
			color = val
			queue_redraw()
	var is_stroke_ring: bool = false

	func _init(initial_color: Color = Color.WHITE, ring: bool = false) -> void:
		color = initial_color
		is_stroke_ring = ring
		custom_minimum_size = Vector2(28, 28)
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		if is_stroke_ring:
			# Dibuja un anillo grueso para el trazo
			draw_rect(r, Color(0.2, 0.2, 0.2, 0.5), true)
			draw_rect(r, color, false, 4.0)
			draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0)
		else:
			# Dibuja un relleno sólido
			if color.a < 1.0:
				draw_rect(r, Color(0.85, 0.85, 0.87, 1.0), true)
			draw_rect(r, color, true)
			draw_rect(r, Color(0, 0, 0, 0.3), false, 1.0)

# ── Estructura de UI ──
var _scroll: ScrollContainer
var _vbox: VBoxContainer

# Studio Panels Collapsible Bodies
var _sec_color: VBoxContainer
var _sec_stroke: VBoxContainer
var _sec_transform: VBoxContainer
var _sec_layers: VBoxContainer
var _sec_publication: VBoxContainer

# Controls: Color Studio
var _swatch_fill: StudioSwatch
var _swatch_stroke: StudioSwatch
var _btn_color_mode_rgb: Button
var _btn_color_mode_hsl: Button
var _is_hsl_mode: bool = false
var _slider_c1: HSlider
var _slider_c2: HSlider
var _slider_c3: HSlider
var _lbl_c1: Label
var _lbl_c2: Label
var _lbl_c3: Label
var _spin_c1: SpinBox
var _spin_c2: SpinBox
var _spin_c3: SpinBox
var _slider_opacity: HSlider
var _lbl_opacity_val: Label
var _line_hex: LineEdit
var _palette_grid: GridContainer

# Controls: Trazo Studio
var _spin_stroke_w: SpinBox
var _btn_stroke_solid: Button
var _btn_stroke_dash: Button
var _btn_cap_butt: Button
var _btn_cap_round: Button
var _btn_cap_square: Button
var _btn_join_miter: Button
var _btn_join_round: Button
var _btn_join_bevel: Button
var _btn_align_center: Button
var _btn_align_inside: Button
var _btn_align_outside: Button
var _spin_dash_len: SpinBox
var _spin_dash_gap: SpinBox
var _row_dash_params: HBoxContainer
var _chk_scale_stroke: CheckBox

# Controls: Transformar Studio
var _ref_points: Array[Button] = []
var _active_ref_point: int = 4 # Center por defecto
var _spin_x: SpinBox
var _spin_y: SpinBox
var _spin_w: SpinBox
var _spin_h: SpinBox
var _btn_aspect_lock: Button
var _is_aspect_locked: bool = false
var _spin_rot: SpinBox
var _spin_shear: SpinBox

# Controls: Capas & Fusión
var _opt_blend_mode: OptionButton
var _slider_layer_opacity: HSlider
var _lbl_layer_opacity: Label
var _btn_lock: Button
var _btn_visible: Button
var _btn_bring_front: Button
var _btn_forward: Button
var _btn_backward: Button
var _btn_send_back: Button

# Controls: Publicación & Páginas
var _lbl_page_info: Label
var _btn_bleed_guides: Button
var _spin_bleed_mm: SpinBox
var _spin_margin_top: SpinBox
var _spin_margin_bottom: SpinBox
var _spin_margin_left: SpinBox
var _spin_margin_right: SpinBox

# Estado interno
var _sync_guard: bool = false
var _has_selection: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	_setup_panel_style()
	_build_ui()
	_connect_cores()

func _setup_panel_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_PANEL
	sb.border_width_left = 1
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.border_color = _C_BORDER
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# Studio Header
	root_vbox.add_child(_create_studio_header())

	# Scrollable Studio Panels Container
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	_scroll.add_child(_vbox)

	# 1. Panel Color / Muestras
	_build_color_panel()

	# 2. Panel Trazo
	_build_stroke_panel()

	# 3. Panel Transformar
	_build_transform_panel()

	# 4. Panel Capas & Fusión
	_build_layers_panel()

	# 5. Panel Publicación & Pliegos (InDesign)
	_build_publication_panel()

# ── CABECERA DEL STUDIO ──
func _create_studio_header() -> Control:
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_HEADER
	sb.border_width_bottom = 1
	sb.border_color = _C_BORDER
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	header.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_child(hbox)

	var lbl := Label.new()
	lbl.text = "STUDIO"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", _C_TEXT)
	hbox.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var badge := Label.new()
	badge.text = "PROFESSIONAL"
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_color_override("font_color", _C_MUTED)
	hbox.add_child(badge)

	return header

# ── BUILDER DE SECCIONES COLAPSABLES ──
func _create_collapsible_section(title: String, out_body_container: Array) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_CARD
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 6)
	panel.add_child(inner_vbox)

	# Section Header
	var header_hbox := HBoxContainer.new()
	inner_vbox.add_child(header_hbox)

	var btn_toggle := Button.new()
	btn_toggle.text = "▼ " + title
	btn_toggle.flat = true
	btn_toggle.focus_mode = Control.FOCUS_NONE
	btn_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_toggle.add_theme_font_size_override("font_size", 10)
	btn_toggle.add_theme_color_override("font_color", _C_TEXT)
	header_hbox.add_child(btn_toggle)

	# Body
	var body_vbox := VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 6)
	inner_vbox.add_child(body_vbox)
	out_body_container.append(body_vbox)

	btn_toggle.pressed.connect(func():
		body_vbox.visible = not body_vbox.visible
		btn_toggle.text = ("▼ " if body_vbox.visible else "▶ ") + title
	)

	return panel

# ── 1. COLOR & MUESTRAS (COLOUR STUDIO) ──
func _build_color_panel() -> void:
	var holder: Array = []
	var sec := _create_collapsible_section("COLOR Y MUESTRAS", holder)
	_vbox.add_child(sec)
	_sec_color = holder[0]

	# Fila 1: Swatches duales (Relleno y Trazo estilo Affinity) + Modo (RGB/HSL)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_sec_color.add_child(row1)

	# Contenedor para swatches entrelazados
	var swatches_box := Control.new()
	swatches_box.custom_minimum_size = Vector2(48, 36)
	row1.add_child(swatches_box)

	_swatch_fill = StudioSwatch.new(Color(0.2, 0.4, 0.9, 1.0), false)
	_swatch_fill.position = Vector2(0, 0)
	_swatch_fill.pressed.connect(func(): _set_color_target("fill"))
	swatches_box.add_child(_swatch_fill)

	_swatch_stroke = StudioSwatch.new(Color(0.1, 0.1, 0.1, 1.0), true)
	_swatch_stroke.position = Vector2(16, 8)
	_swatch_stroke.pressed.connect(func(): _set_color_target("stroke"))
	swatches_box.add_child(_swatch_stroke)

	# Selector de Modo [RGB] [HSL]
	var mode_hbox := HBoxContainer.new()
	mode_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_hbox.alignment = BoxContainer.ALIGNMENT_END
	row1.add_child(mode_hbox)

	_btn_color_mode_rgb = _create_chip_btn("RGB", true)
	_btn_color_mode_rgb.pressed.connect(func(): _toggle_color_mode(false))
	mode_hbox.add_child(_btn_color_mode_rgb)

	_btn_color_mode_hsl = _create_chip_btn("HSL", false)
	_btn_color_mode_hsl.pressed.connect(func(): _toggle_color_mode(true))
	mode_hbox.add_child(_btn_color_mode_hsl)

	# Fila Canales de Color: Sliders y SpinBoxes para 3 canales
	_slider_c1 = HSlider.new()
	_spin_c1 = SpinBox.new()
	_lbl_c1 = Label.new()
	_sec_color.add_child(_create_slider_row("R", _lbl_c1, _slider_c1, _spin_c1, 0, 255))

	_slider_c2 = HSlider.new()
	_spin_c2 = SpinBox.new()
	_lbl_c2 = Label.new()
	_sec_color.add_child(_create_slider_row("G", _lbl_c2, _slider_c2, _spin_c2, 0, 255))

	_slider_c3 = HSlider.new()
	_spin_c3 = SpinBox.new()
	_lbl_c3 = Label.new()
	_sec_color.add_child(_create_slider_row("B", _lbl_c3, _slider_c3, _spin_c3, 0, 255))

	# Conexiones sliders y spins
	_slider_c1.value_changed.connect(func(v): _on_channel_changed(0, v))
	_spin_c1.value_changed.connect(func(v): _on_channel_changed(0, v))
	_slider_c2.value_changed.connect(func(v): _on_channel_changed(1, v))
	_spin_c2.value_changed.connect(func(v): _on_channel_changed(1, v))
	_slider_c3.value_changed.connect(func(v): _on_channel_changed(2, v))
	_spin_c3.value_changed.connect(func(v): _on_channel_changed(2, v))

	# Fila Opacidad y Hex
	var row_aux := HBoxContainer.new()
	row_aux.add_theme_constant_override("separation", 6)
	_sec_color.add_child(row_aux)

	var lbl_hex_tag := Label.new()
	lbl_hex_tag.text = "#"
	lbl_hex_tag.add_theme_color_override("font_color", _C_MUTED)
	lbl_hex_tag.add_theme_font_size_override("font_size", 10)
	row_aux.add_child(lbl_hex_tag)

	_line_hex = LineEdit.new()
	_line_hex.text = "3366E6"
	_line_hex.custom_minimum_size = Vector2(70, 22)
	_style_line_edit(_line_hex)
	_line_hex.text_submitted.connect(_on_hex_submitted)
	row_aux.add_child(_line_hex)

	var lbl_op := Label.new()
	lbl_op.text = "Opacidad:"
	lbl_op.add_theme_color_override("font_color", _C_MUTED)
	lbl_op.add_theme_font_size_override("font_size", 10)
	row_aux.add_child(lbl_op)

	_slider_opacity = HSlider.new()
	_slider_opacity.min_value = 0
	_slider_opacity.max_value = 100
	_slider_opacity.value = 100
	_slider_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_opacity.value_changed.connect(_on_opacity_slider_changed)
	row_aux.add_child(_slider_opacity)

	_lbl_opacity_val = Label.new()
	_lbl_opacity_val.text = "100%"
	_lbl_opacity_val.custom_minimum_size = Vector2(34, 0)
	_lbl_opacity_val.add_theme_color_override("font_color", _C_TEXT)
	_lbl_opacity_val.add_theme_font_size_override("font_size", 10)
	row_aux.add_child(_lbl_opacity_val)

	# Fila de Paleta de Muestras Rápidas (Swatches)
	_palette_grid = GridContainer.new()
	_palette_grid.columns = 8
	_palette_grid.add_theme_constant_override("h_separation", 4)
	_palette_grid.add_theme_constant_override("v_separation", 4)
	_sec_color.add_child(_palette_grid)

	var preset_colors := [
		Color.BLACK, Color(0.25, 0.25, 0.25), Color(0.5, 0.5, 0.5), Color.WHITE,
		Color("#e02020"), Color("#fa6400"), Color("#f7b500"), Color("#6dd400"),
		Color("#0091ff"), Color("#6236ff"), Color("#b620e0"), Color.TRANSPARENT
	]
	for c in preset_colors:
		var btn_sw := Button.new()
		btn_sw.custom_minimum_size = Vector2(22, 18)
		btn_sw.focus_mode = Control.FOCUS_NONE
		var sb_sw := StyleBoxFlat.new()
		sb_sw.bg_color = c
		sb_sw.set_corner_radius_all(2)
		sb_sw.set_border_width_all(1)
		sb_sw.border_color = Color(1, 1, 1, 0.15)
		btn_sw.add_theme_stylebox_override("normal", sb_sw)
		btn_sw.pressed.connect(func(): _apply_selected_color(c))
		_palette_grid.add_child(btn_sw)

# ── 2. TRAZO (STROKE STUDIO) ──
func _build_stroke_panel() -> void:
	var holder: Array = []
	var sec := _create_collapsible_section("TRAZO", holder)
	_vbox.add_child(sec)
	_sec_stroke = holder[0]

	# Fila 1: Grosor (Width) y Estilo (Sólido / Guiones)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	_sec_stroke.add_child(row1)

	var lbl_w := Label.new()
	lbl_w.text = "Ancho:"
	lbl_w.add_theme_color_override("font_color", _C_MUTED)
	lbl_w.add_theme_font_size_override("font_size", 10)
	row1.add_child(lbl_w)

	_spin_stroke_w = SpinBox.new()
	_spin_stroke_w.min_value = 0.0
	_spin_stroke_w.max_value = 200.0
	_spin_stroke_w.step = 0.5
	_spin_stroke_w.value = 1.0
	_spin_stroke_w.suffix = "px"
	_spin_stroke_w.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_stroke_w)
	_spin_stroke_w.value_changed.connect(_on_stroke_width_changed)
	row1.add_child(_spin_stroke_w)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer)

	_btn_stroke_solid = _create_chip_btn("Sólido", true)
	_btn_stroke_solid.pressed.connect(func(): _set_stroke_style(0))
	row1.add_child(_btn_stroke_solid)

	_btn_stroke_dash = _create_chip_btn("Guiones", false)
	_btn_stroke_dash.pressed.connect(func(): _set_stroke_style(1))
	row1.add_child(_btn_stroke_dash)

	# Fila 2: Extremos (Caps) y Uniones (Joins)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_sec_stroke.add_child(row2)

	var lbl_cap := Label.new()
	lbl_cap.text = "Remate:"
	lbl_cap.add_theme_color_override("font_color", _C_MUTED)
	lbl_cap.add_theme_font_size_override("font_size", 10)
	row2.add_child(lbl_cap)

	_btn_cap_butt = _create_chip_btn("Plano", true)
	_btn_cap_butt.pressed.connect(func(): _set_stroke_cap(0))
	row2.add_child(_btn_cap_butt)

	_btn_cap_round = _create_chip_btn("Redondo", false)
	_btn_cap_round.pressed.connect(func(): _set_stroke_cap(1))
	row2.add_child(_btn_cap_round)

	_btn_cap_square = _create_chip_btn("Cuadrado", false)
	_btn_cap_square.pressed.connect(func(): _set_stroke_cap(2))
	row2.add_child(_btn_cap_square)

	# Fila 3: Alineación (Align: Centro, Interior, Exterior)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	_sec_stroke.add_child(row3)

	var lbl_align := Label.new()
	lbl_align.text = "Alinear:"
	lbl_align.add_theme_color_override("font_color", _C_MUTED)
	lbl_align.add_theme_font_size_override("font_size", 10)
	row3.add_child(lbl_align)

	_btn_align_center = _create_chip_btn("Centro", true)
	_btn_align_center.pressed.connect(func(): _set_stroke_align(0))
	row3.add_child(_btn_align_center)

	_btn_align_inside = _create_chip_btn("Interior", false)
	_btn_align_inside.pressed.connect(func(): _set_stroke_align(1))
	row3.add_child(_btn_align_inside)

	_btn_align_outside = _create_chip_btn("Exterior", false)
	_btn_align_outside.pressed.connect(func(): _set_stroke_align(2))
	row3.add_child(_btn_align_outside)

	# Fila 4: Parámetros de Guiones (oculta si es sólido)
	_row_dash_params = HBoxContainer.new()
	_row_dash_params.add_theme_constant_override("separation", 6)
	_row_dash_params.visible = false
	_sec_stroke.add_child(_row_dash_params)

	var lbl_dl := Label.new()
	lbl_dl.text = "Trazo:"
	lbl_dl.add_theme_color_override("font_color", _C_MUTED)
	lbl_dl.add_theme_font_size_override("font_size", 10)
	_row_dash_params.add_child(lbl_dl)

	_spin_dash_len = SpinBox.new()
	_spin_dash_len.min_value = 1.0
	_spin_dash_len.max_value = 50.0
	_spin_dash_len.value = 6.0
	_style_spinbox(_spin_dash_len)
	_spin_dash_len.value_changed.connect(_on_dash_params_changed)
	_row_dash_params.add_child(_spin_dash_len)

	var lbl_dg := Label.new()
	lbl_dg.text = "Espacio:"
	lbl_dg.add_theme_color_override("font_color", _C_MUTED)
	lbl_dg.add_theme_font_size_override("font_size", 10)
	_row_dash_params.add_child(lbl_dg)

	_spin_dash_gap = SpinBox.new()
	_spin_dash_gap.min_value = 1.0
	_spin_dash_gap.max_value = 50.0
	_spin_dash_gap.value = 4.0
	_style_spinbox(_spin_dash_gap)
	_spin_dash_gap.value_changed.connect(_on_dash_params_changed)
	_row_dash_params.add_child(_spin_dash_gap)

	# Fila 5: Escalar con objeto
	_chk_scale_stroke = CheckBox.new()
	_chk_scale_stroke.text = "Escalar trazo con objeto"
	_chk_scale_stroke.button_pressed = true
	_chk_scale_stroke.focus_mode = Control.FOCUS_NONE
	_chk_scale_stroke.add_theme_font_size_override("font_size", 10)
	_chk_scale_stroke.add_theme_color_override("font_color", _C_MUTED)
	_sec_stroke.add_child(_chk_scale_stroke)

# ── 3. TRANSFORMAR (TRANSFORM STUDIO) ──
func _build_transform_panel() -> void:
	var holder: Array = []
	var sec := _create_collapsible_section("TRANSFORMAR", holder)
	_vbox.add_child(sec)
	_sec_transform = holder[0]

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	_sec_transform.add_child(main_row)

	# Matriz 3x3 de Punto de Referencia (Anchor Point)
	var matrix_vbox := VBoxContainer.new()
	matrix_vbox.add_theme_constant_override("separation", 2)
	main_row.add_child(matrix_vbox)

	var lbl_matrix := Label.new()
	lbl_matrix.text = "Origen:"
	lbl_matrix.add_theme_color_override("font_color", _C_MUTED)
	lbl_matrix.add_theme_font_size_override("font_size", 9)
	matrix_vbox.add_child(lbl_matrix)

	var matrix_grid := GridContainer.new()
	matrix_grid.columns = 3
	matrix_grid.add_theme_constant_override("h_separation", 2)
	matrix_grid.add_theme_constant_override("v_separation", 2)
	matrix_vbox.add_child(matrix_grid)

	_ref_points.clear()
	for i in range(9):
		var btn_pt := Button.new()
		btn_pt.custom_minimum_size = Vector2(14, 14)
		btn_pt.focus_mode = Control.FOCUS_NONE
		_style_ref_point_button(btn_pt, i == _active_ref_point)
		var idx = i
		btn_pt.pressed.connect(func(): _set_active_ref_point(idx))
		matrix_grid.add_child(btn_pt)
		_ref_points.append(btn_pt)

	# Campos de Geometría: X, Y, W, H, R, S
	var fields_vbox := VBoxContainer.new()
	fields_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_vbox.add_theme_constant_override("separation", 4)
	main_row.add_child(fields_vbox)

	# Fila X / Y
	var row_xy := HBoxContainer.new()
	row_xy.add_theme_constant_override("separation", 6)
	fields_vbox.add_child(row_xy)

	var lbl_x := Label.new()
	lbl_x.text = "X"
	lbl_x.add_theme_color_override("font_color", _C_MUTED)
	lbl_x.add_theme_font_size_override("font_size", 10)
	row_xy.add_child(lbl_x)

	_spin_x = SpinBox.new()
	_spin_x.min_value = -99999
	_spin_x.max_value = 99999
	_spin_x.step = 1.0
	_spin_x.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_x)
	_spin_x.value_changed.connect(_on_x_changed)
	row_xy.add_child(_spin_x)

	var lbl_y := Label.new()
	lbl_y.text = "Y"
	lbl_y.add_theme_color_override("font_color", _C_MUTED)
	lbl_y.add_theme_font_size_override("font_size", 10)
	row_xy.add_child(lbl_y)

	_spin_y = SpinBox.new()
	_spin_y.min_value = -99999
	_spin_y.max_value = 99999
	_spin_y.step = 1.0
	_spin_y.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_y)
	_spin_y.value_changed.connect(_on_y_changed)
	row_xy.add_child(_spin_y)

	# Fila W / H con bloqueo de proporción
	var row_wh := HBoxContainer.new()
	row_wh.add_theme_constant_override("separation", 6)
	fields_vbox.add_child(row_wh)

	var lbl_w := Label.new()
	lbl_w.text = "W"
	lbl_w.add_theme_color_override("font_color", _C_MUTED)
	lbl_w.add_theme_font_size_override("font_size", 10)
	row_wh.add_child(lbl_w)

	_spin_w = SpinBox.new()
	_spin_w.min_value = 1.0
	_spin_w.max_value = 99999
	_spin_w.step = 1.0
	_spin_w.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_w)
	_spin_w.value_changed.connect(_on_w_changed)
	row_wh.add_child(_spin_w)

	_btn_aspect_lock = Button.new()
	_btn_aspect_lock.text = "🔗"
	_btn_aspect_lock.custom_minimum_size = Vector2(22, 22)
	_btn_aspect_lock.focus_mode = Control.FOCUS_NONE
	_style_chip_button(_btn_aspect_lock, _is_aspect_locked)
	_btn_aspect_lock.pressed.connect(_toggle_aspect_lock)
	row_wh.add_child(_btn_aspect_lock)

	var lbl_h := Label.new()
	lbl_h.text = "H"
	lbl_h.add_theme_color_override("font_color", _C_MUTED)
	lbl_h.add_theme_font_size_override("font_size", 10)
	row_wh.add_child(lbl_h)

	_spin_h = SpinBox.new()
	_spin_h.min_value = 1.0
	_spin_h.max_value = 99999
	_spin_h.step = 1.0
	_spin_h.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_h)
	_spin_h.value_changed.connect(_on_h_changed)
	row_wh.add_child(_spin_h)

	# Fila Rotación (R) e Inclinación / Shear (S)
	var row_rs := HBoxContainer.new()
	row_rs.add_theme_constant_override("separation", 6)
	_sec_transform.add_child(row_rs)

	var lbl_r := Label.new()
	lbl_r.text = "R:"
	lbl_r.add_theme_color_override("font_color", _C_MUTED)
	lbl_r.add_theme_font_size_override("font_size", 10)
	row_rs.add_child(lbl_r)

	_spin_rot = SpinBox.new()
	_spin_rot.min_value = -360.0
	_spin_rot.max_value = 360.0
	_spin_rot.step = 0.5
	_spin_rot.suffix = "°"
	_spin_rot.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_rot)
	_spin_rot.value_changed.connect(_on_rotation_changed)
	row_rs.add_child(_spin_rot)

	var lbl_s := Label.new()
	lbl_s.text = "S:"
	lbl_s.add_theme_color_override("font_color", _C_MUTED)
	lbl_s.add_theme_font_size_override("font_size", 10)
	row_rs.add_child(lbl_s)

	_spin_shear = SpinBox.new()
	_spin_shear.min_value = -89.0
	_spin_shear.max_value = 89.0
	_spin_shear.step = 0.5
	_spin_shear.suffix = "°"
	_spin_shear.custom_minimum_size = Vector2(70, 22)
	_style_spinbox(_spin_shear)
	row_rs.add_child(_spin_shear)

# ── 4. CAPAS & FUSIÓN (LAYERS & BLEND STUDIO) ──
func _build_layers_panel() -> void:
	var holder: Array = []
	var sec := _create_collapsible_section("CAPAS Y FUSIÓN", holder)
	_vbox.add_child(sec)
	_sec_layers = holder[0]

	# Fila 1: Modo de Fusión y Opacidad
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	_sec_layers.add_child(row1)

	var lbl_blend := Label.new()
	lbl_blend.text = "Fusión:"
	lbl_blend.add_theme_color_override("font_color", _C_MUTED)
	lbl_blend.add_theme_font_size_override("font_size", 10)
	row1.add_child(lbl_blend)

	_opt_blend_mode = OptionButton.new()
	_opt_blend_mode.add_item("Normal")
	_opt_blend_mode.add_item("Multiplicar")
	_opt_blend_mode.add_item("Trama")
	_opt_blend_mode.add_item("Superponer")
	_opt_blend_mode.add_item("Oscurecer")
	_opt_blend_mode.add_item("Aclarar")
	_opt_blend_mode.add_item("Diferencia")
	_opt_blend_mode.custom_minimum_size = Vector2(90, 22)
	_opt_blend_mode.focus_mode = Control.FOCUS_NONE
	_opt_blend_mode.add_theme_font_size_override("font_size", 9)
	_style_option_button(_opt_blend_mode)
	row1.add_child(_opt_blend_mode)

	_slider_layer_opacity = HSlider.new()
	_slider_layer_opacity.min_value = 0
	_slider_layer_opacity.max_value = 100
	_slider_layer_opacity.value = 100
	_slider_layer_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_layer_opacity.value_changed.connect(_on_layer_opacity_changed)
	row1.add_child(_slider_layer_opacity)

	_lbl_layer_opacity = Label.new()
	_lbl_layer_opacity.text = "100%"
	_lbl_layer_opacity.custom_minimum_size = Vector2(30, 0)
	_lbl_layer_opacity.add_theme_color_override("font_color", _C_TEXT)
	_lbl_layer_opacity.add_theme_font_size_override("font_size", 10)
	row1.add_child(_lbl_layer_opacity)

	# Fila 2: Acciones Rápidas (Bloquear, Ocultar, Reordenar Z)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_sec_layers.add_child(row2)

	_btn_visible = _create_chip_btn("👁 Visible", false)
	_btn_visible.pressed.connect(_toggle_selection_visibility)
	row2.add_child(_btn_visible)

	_btn_lock = _create_chip_btn("🔒 Bloquear", false)
	_btn_lock.pressed.connect(_toggle_selection_lock)
	row2.add_child(_btn_lock)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)

	_btn_bring_front = _create_chip_btn("⤒", false)
	_btn_bring_front.tooltip_text = "Traer al frente"
	_btn_bring_front.pressed.connect(func(): _trigger_reorder("bring_to_front"))
	row2.add_child(_btn_bring_front)

	_btn_forward = _create_chip_btn("↑", false)
	_btn_forward.tooltip_text = "Avanzar"
	_btn_forward.pressed.connect(func(): _trigger_reorder("bring_forward"))
	row2.add_child(_btn_forward)

	_btn_backward = _create_chip_btn("↓", false)
	_btn_backward.tooltip_text = "Retroceder"
	_btn_backward.pressed.connect(func(): _trigger_reorder("send_backward"))
	row2.add_child(_btn_backward)

	_btn_send_back = _create_chip_btn("⤓", false)
	_btn_send_back.tooltip_text = "Enviar al fondo"
	_btn_send_back.pressed.connect(func(): _trigger_reorder("send_to_back"))
	row2.add_child(_btn_send_back)

# ── 5. PUBLICACIÓN & PLIEGOS (PAGES / INDESIGN STUDIO) ──
func _build_publication_panel() -> void:
	var holder: Array = []
	var sec := _create_collapsible_section("PUBLICACIÓN Y PLIEGOS", holder)
	_vbox.add_child(sec)
	_sec_publication = holder[0]

	# Fila 1: Estado de Página / Artboard
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	_sec_publication.add_child(row1)

	var btn_prev_page := _create_chip_btn("◀", false)
	row1.add_child(btn_prev_page)

	_lbl_page_info = Label.new()
	_lbl_page_info.text = "Página 1 (Pliego Simple)"
	_lbl_page_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_page_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_page_info.add_theme_color_override("font_color", _C_TEXT)
	_lbl_page_info.add_theme_font_size_override("font_size", 10)
	row1.add_child(_lbl_page_info)

	var btn_next_page := _create_chip_btn("▶", false)
	row1.add_child(btn_next_page)

	# Fila 2: Sangrado (Bleed)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_sec_publication.add_child(row2)

	var lbl_bleed := Label.new()
	lbl_bleed.text = "Sangrado (Bleed):"
	lbl_bleed.add_theme_color_override("font_color", _C_MUTED)
	lbl_bleed.add_theme_font_size_override("font_size", 10)
	row2.add_child(lbl_bleed)

	_spin_bleed_mm = SpinBox.new()
	_spin_bleed_mm.min_value = 0.0
	_spin_bleed_mm.max_value = 20.0
	_spin_bleed_mm.step = 0.5
	_spin_bleed_mm.value = 3.0
	_spin_bleed_mm.suffix = "mm"
	_spin_bleed_mm.custom_minimum_size = Vector2(65, 22)
	_style_spinbox(_spin_bleed_mm)
	row2.add_child(_spin_bleed_mm)

	_btn_bleed_guides = _create_chip_btn("Guías", true)
	_btn_bleed_guides.tooltip_text = "Alternar guías de sangrado y corte"
	row2.add_child(_btn_bleed_guides)

	# Fila 3: Márgenes Editoriales
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	_sec_publication.add_child(row3)

	var lbl_m := Label.new()
	lbl_m.text = "Márgenes:"
	lbl_m.add_theme_color_override("font_color", _C_MUTED)
	lbl_m.add_theme_font_size_override("font_size", 9)
	row3.add_child(lbl_m)

	_spin_margin_top = _create_margin_spin("T", 15.0)
	row3.add_child(_spin_margin_top)

	_spin_margin_bottom = _create_margin_spin("B", 15.0)
	row3.add_child(_spin_margin_bottom)

	_spin_margin_left = _create_margin_spin("L", 15.0)
	row3.add_child(_spin_margin_left)

	_spin_margin_right = _create_margin_spin("R", 15.0)
	row3.add_child(_spin_margin_right)

func _create_margin_spin(tag: String, default_val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0.0
	sb.max_value = 100.0
	sb.value = default_val
	sb.prefix = tag + ":"
	sb.custom_minimum_size = Vector2(50, 20)
	_style_spinbox(sb)
	return sb

# ── CONEXIONES A CORES Y EVENTOS ──
func _connect_cores() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
		ic.changed.connect(_on_inspector_changed)
		if ic.has_method("current_props"):
			_on_inspector_changed(ic.current_props())

	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_signal("changed") and not cc.changed.is_connected(_on_color_core_changed):
		cc.changed.connect(_on_color_core_changed)

func _set_color_target(target: String) -> void:
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("set_target"):
		cc.set_target(target)
	_update_swatches_ui(target)

func _update_swatches_ui(target: String) -> void:
	if target == "fill":
		_swatch_fill.z_index = 2
		_swatch_stroke.z_index = 1
	else:
		_swatch_fill.z_index = 1
		_swatch_stroke.z_index = 2

func _toggle_color_mode(hsl: bool) -> void:
	_is_hsl_mode = hsl
	_style_chip_button(_btn_color_mode_rgb, not hsl)
	_style_chip_button(_btn_color_mode_hsl, hsl)

	if hsl:
		_lbl_c1.text = "H"
		_slider_c1.max_value = 360
		_spin_c1.max_value = 360
		_lbl_c2.text = "S"
		_slider_c2.max_value = 100
		_spin_c2.max_value = 100
		_lbl_c3.text = "L"
		_slider_c3.max_value = 100
		_spin_c3.max_value = 100
	else:
		_lbl_c1.text = "R"
		_slider_c1.max_value = 255
		_spin_c1.max_value = 255
		_lbl_c2.text = "G"
		_slider_c2.max_value = 255
		_spin_c2.max_value = 255
		_lbl_c3.text = "B"
		_slider_c3.max_value = 255
		_spin_c3.max_value = 255

	var cur_col := _get_active_color()
	_update_color_sliders(cur_col)

func _get_active_color() -> Color:
	var cc := get_node_or_null("/root/ColorCore")
	if cc and cc.has_method("active_color"):
		return cc.active_color()
	return _swatch_fill.color

func _update_color_sliders(c: Color) -> void:
	_sync_guard = true
	if _is_hsl_mode:
		_slider_c1.value = c.h * 360.0
		_spin_c1.value = c.h * 360.0
		_slider_c2.value = c.s * 100.0
		_spin_c2.value = c.s * 100.0
		_slider_c3.value = c.v * 100.0
		_spin_c3.value = c.v * 100.0
	else:
		_slider_c1.value = c.r * 255.0
		_spin_c1.value = c.r * 255.0
		_slider_c2.value = c.g * 255.0
		_spin_c2.value = c.g * 255.0
		_slider_c3.value = c.b * 255.0
		_spin_c3.value = c.b * 255.0

	_slider_opacity.value = c.a * 100.0
	_lbl_opacity_val.text = str(roundi(c.a * 100.0)) + "%"
	_line_hex.text = c.to_html(false).to_upper()
	_sync_guard = false

func _on_channel_changed(channel_idx: int, val: float) -> void:
	if _sync_guard:
		return
	var cur := _get_active_color()
	var new_col := cur
	if _is_hsl_mode:
		var h := (_slider_c1.value / 360.0) if channel_idx != 0 else (val / 360.0)
		var s := (_slider_c2.value / 100.0) if channel_idx != 1 else (val / 100.0)
		var l := (_slider_c3.value / 100.0) if channel_idx != 2 else (val / 100.0)
		new_col = Color.from_hsv(h, s, l, cur.a)
	else:
		var r := (_slider_c1.value / 255.0) if channel_idx != 0 else (val / 255.0)
		var g := (_slider_c2.value / 255.0) if channel_idx != 1 else (val / 255.0)
		var b := (_slider_c3.value / 255.0) if channel_idx != 2 else (val / 255.0)
		new_col = Color(r, g, b, cur.a)
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
	if clean.length() == 6 or clean.length() == 8:
		var col := Color.hex(clean.hex_to_int())
		_apply_selected_color(col)

func _apply_selected_color(c: Color) -> void:
	var cc := get_node_or_null("/root/ColorCore")
	if cc:
		if cc.has_method("apply_color"):
			cc.apply_color(c)
		elif cc.active_target == "fill" and cc.has_method("apply_fill"):
			cc.apply_fill(c)
		elif cc.active_target == "stroke" and cc.has_method("apply_stroke"):
			cc.apply_stroke(c)
	_update_color_sliders(c)

func _on_color_core_changed(fill: Color, stroke: Color, target: String) -> void:
	if is_instance_valid(_swatch_fill):
		_swatch_fill.color = fill
	if is_instance_valid(_swatch_stroke):
		_swatch_stroke.color = stroke
	_update_swatches_ui(target)
	_update_color_sliders(fill if target == "fill" else stroke)

# ── TRANSFORM SYNC ──
func _set_active_ref_point(idx: int) -> void:
	_active_ref_point = idx
	for i in range(_ref_points.size()):
		_style_ref_point_button(_ref_points[i], i == idx)

func _toggle_aspect_lock() -> void:
	_is_aspect_locked = not _is_aspect_locked
	_style_chip_button(_btn_aspect_lock, _is_aspect_locked)

func _on_x_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("pos_x", val)

func _on_y_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("pos_y", val)

func _on_w_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("width", val)
	if _is_aspect_locked and _spin_h.value > 0:
		pass

func _on_h_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("height", val)

func _on_rotation_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("rotation", val)

# ── STROKE SYNC ──
func _on_stroke_width_changed(val: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("stroke_width", val)

func _set_stroke_style(style_idx: int) -> void:
	_style_chip_button(_btn_stroke_solid, style_idx == 0)
	_style_chip_button(_btn_stroke_dash, style_idx == 1)
	_row_dash_params.visible = (style_idx == 1)
	_apply_inspector_prop("stroke_style", style_idx)

func _set_stroke_cap(cap_idx: int) -> void:
	_style_chip_button(_btn_cap_butt, cap_idx == 0)
	_style_chip_button(_btn_cap_round, cap_idx == 1)
	_style_chip_button(_btn_cap_square, cap_idx == 2)
	_apply_inspector_prop("stroke_cap_start", cap_idx)
	_apply_inspector_prop("stroke_cap_end", cap_idx)

func _set_stroke_align(align_idx: int) -> void:
	_style_chip_button(_btn_align_center, align_idx == 0)
	_style_chip_button(_btn_align_inside, align_idx == 1)
	_style_chip_button(_btn_align_outside, align_idx == 2)
	_apply_inspector_prop("stroke_align", align_idx)

func _on_dash_params_changed(_v: float) -> void:
	if _sync_guard: return
	_apply_inspector_prop("stroke_dash_len", _spin_dash_len.value)
	_apply_inspector_prop("stroke_dash_gap", _spin_dash_gap.value)

# ── CAPAS & REORDENAR ──
func _on_layer_opacity_changed(val: float) -> void:
	if _sync_guard: return
	_lbl_layer_opacity.text = str(roundi(val)) + "%"
	_apply_inspector_prop("opacity", val / 100.0)

func _toggle_selection_visibility() -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		var p = ic.current_props()
		var cur_vis: bool = p.get("visible", {}).get("value", true)
		_apply_inspector_prop("visible", not cur_vis)

func _toggle_selection_lock() -> void:
	var mt = _get_move_tool()
	if mt and mt.has_method("toggle_lock_selected"):
		mt.toggle_lock_selected()

func _trigger_reorder(action: String) -> void:
	var mt = _get_move_tool()
	if not mt: return
	match action:
		"bring_to_front":
			if mt.has_method("bring_to_front_selected"): mt.bring_to_front_selected()
		"bring_forward":
			if mt.has_method("bring_forward_selected"): mt.bring_forward_selected()
		"send_backward":
			if mt.has_method("send_backward_selected"): mt.send_backward_selected()
		"send_to_back":
			if mt.has_method("send_to_back_selected"): mt.send_to_back_selected()

func _get_move_tool() -> Node:
	var c := get_tree().get_first_node_in_group("_vectopen_canvas") if get_tree() else null
	if c and c.has_method("get_current_tool"):
		var t = c.get_current_tool()
		if t and t.has_method("get_class_name") and t.get_class_name() == "MoveTool":
			return t
	return null

func _apply_inspector_prop(prop: String, val: Variant) -> void:
	var ic := get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply(prop, val)

# ── SINCRONIZACIÓN GENERAL CON INSPECTORCORE ──
func _on_inspector_changed(props: Dictionary) -> void:
	_sync_guard = true
	_has_selection = not props.is_empty() and props.has("pos_x")

	if props.has("pos_x") and not props["pos_x"]["mixed"]:
		_spin_x.value = props["pos_x"]["value"]
	if props.has("pos_y") and not props["pos_y"]["mixed"]:
		_spin_y.value = props["pos_y"]["value"]
	if props.has("width") and not props["width"]["mixed"]:
		_spin_w.value = props["width"]["value"]
	if props.has("height") and not props["height"]["mixed"]:
		_spin_h.value = props["height"]["value"]
	if props.has("rotation") and not props["rotation"]["mixed"]:
		_spin_rot.value = props["rotation"]["value"]

	if props.has("stroke_width") and not props["stroke_width"]["mixed"]:
		_spin_stroke_w.value = props["stroke_width"]["value"]

	if props.has("opacity") and not props["opacity"]["mixed"]:
		var op: float = props["opacity"]["value"]
		_slider_layer_opacity.value = op * 100.0
		_lbl_layer_opacity.text = str(roundi(op * 100.0)) + "%"

	if props.has("fill_color") and not props["fill_color"]["mixed"] and is_instance_valid(_swatch_fill):
		_swatch_fill.color = props["fill_color"]["value"]
	if props.has("stroke_color") and not props["stroke_color"]["mixed"] and is_instance_valid(_swatch_stroke):
		_swatch_stroke.color = props["stroke_color"]["value"]

	_sync_guard = false

# ── HELPERS DE ESTILIZADO DE COMPONENTES ──
func _create_slider_row(channel_tag: String, out_lbl: Label, slider: HSlider, spin: SpinBox, min_v: float, max_v: float) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	out_lbl.text = channel_tag
	out_lbl.custom_minimum_size = Vector2(12, 0)
	out_lbl.add_theme_color_override("font_color", _C_MUTED)
	out_lbl.add_theme_font_size_override("font_size", 10)
	hbox.add_child(out_lbl)

	slider.min_value = min_v
	slider.max_value = max_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	hbox.add_child(slider)

	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1.0
	spin.custom_minimum_size = Vector2(56, 20)
	_style_spinbox(spin)
	hbox.add_child(spin)

	# Conexión espejo entre slider y spinbox
	slider.value_changed.connect(func(v):
		if not _sync_guard: spin.value = v
	)
	spin.value_changed.connect(func(v):
		if not _sync_guard: slider.value = v
	)

	return hbox

func _create_chip_btn(title: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = title
	btn.custom_minimum_size = Vector2(0, 22)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)
	_style_chip_button(btn, active)
	return btn

func _style_chip_button(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_ACTIVE_TAB if active else _C_BG_INPUT
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = _C_ACCENT if active else _C_BORDER
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", _C_TEXT if active else _C_MUTED)

func _style_ref_point_button(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_ACCENT if active else _C_BG_INPUT
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = Color.WHITE if active else _C_BORDER
	btn.add_theme_stylebox_override("normal", sb)

func _style_spinbox(spin: SpinBox) -> void:
	spin.add_theme_font_size_override("font_size", 10)
	var le = spin.get_line_edit()
	if le:
		_style_line_edit(le)

func _style_line_edit(le: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_INPUT
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_color_override("font_color", _C_TEXT)
	le.add_theme_font_size_override("font_size", 10)

func _style_option_button(opt: OptionButton) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_INPUT
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	opt.add_theme_stylebox_override("normal", sb)
	opt.add_theme_color_override("font_color", _C_TEXT)
