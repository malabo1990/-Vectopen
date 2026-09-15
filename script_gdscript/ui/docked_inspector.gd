# =============================================================================
# VECTOPEN — INSPECTOR LATERAL DOCKEADO (DOCKED INSPECTOR)
# RUTA: res://script_gdscript/ui/docked_inspector.gd
# Modos: Modern Panel (Figma UI3 / Apple Style) | Professional Panel (Affinity)
# Conectado a InspectorCore como fuente unica de verdad para la seleccion y Undo
# =============================================================================
class_name DockedInspector
extends PanelContainer

signal closed()

# ── Botón Swatch personalizado con previsualización para Modern UI ──
class ColorSwatchButton extends Button:
	signal color_changed(new_color: Color)
	var color: Color = Color.WHITE:
		set(val):
			color = val
			queue_redraw()

	func _init(initial_color: Color = Color.WHITE) -> void:
		color = initial_color
		custom_minimum_size = Vector2(24, 24)
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		if color.a < 1.0:
			draw_rect(r, Color(0.85, 0.85, 0.87, 1.0), true)
		draw_rect(r, color, true)
		draw_rect(r, Color(0, 0, 0, 0.2), false, 1.0)

# ── Popover de Color (Panel completo de Smart UI) ──
var _color_popover: PanelContainer
var _color_popover_header_title: Label
var _pickr_instance: GestorColor
var _active_color_target: String = ""

# ── Nodos de cabecera ──
var lbl_title: Label
var lbl_selection: Label
var mode_selector: Control

# ── Contenedor de contenido con Scroll ──
var scroll_container: ScrollContainer
var content_container: VBoxContainer

# ── Sección Lienzo / Página (cuando no hay selección) ──
var sec_canvas: VBoxContainer
var picker_canvas_bg: Button
var lbl_canvas_hex: Label
var lbl_canvas_size: Label

# ── Sección Alineación (Barra segmentada de 8 botones) ──
var sec_align: VBoxContainer
var align_container: HBoxContainer

# ── Sección Transformación (Cuadrícula compacta de 2 columnas) ──
var transform_panel: TransformPanel

# ── Sección Apariencia (Opacidad y visibilidad) ──
var sec_appearance: VBoxContainer
var spin_opacity: SpinBox
var btn_toggle_visibility: Button
var _current_item_visible: bool = true

# ── Sección Relleno (Fill) ──
var sec_fill: VBoxContainer
var picker_fill: Button
var lbl_fill_hex: Label

# ── Sección Trazo (Stroke) ──
var sec_stroke: VBoxContainer
var picker_stroke: Button
var spin_stroke_width: SpinBox
var opt_stroke_align: OptionButton

# ── Sección Efectos ──
var sec_effects: VBoxContainer
var btn_shadow_toggle: Button
var _has_shadow: bool = false

# ── Sección Exportación ──
var sec_export: VBoxContainer
var opt_export_format: OptionButton
var btn_export_selection: Button

# ── Estado de sincronización y tema ──
var _syncing: bool = false
var _is_dense: bool = false
var _has_selection: bool = false

# Tokens de color estándar (Figma UI3 neutral)
var _C_BG_INPUT := Color(0.945, 0.945, 0.961, 1.0) # #f1f1f5
var _C_BORDER_INPUT := Color(0.86, 0.86, 0.88, 1.0)
var _C_TEXT := Color(0.12, 0.12, 0.15, 1.0)
var _C_MUTED := Color(0.50, 0.50, 0.55, 1.0)
var _C_ACCENT := Color(0.04, 0.52, 1.0, 1.0)

func _ready() -> void:
	_pull_theme_tokens()
	_setup_panel_style()
	_build_ui()
	_connect_inspector_core()
	_update_from_inspector()

func _pull_theme_tokens() -> void:
	var tm = get_node_or_null("/root/ThemeManager")
	var is_dark := false
	if tm:
		if tm.has_method("get_mode"):
			is_dark = tm.get_mode() == "dark"
		elif "current_mode" in tm:
			is_dark = tm.current_mode == "dark"

	if is_dark:
		_C_BG_INPUT = Color(0.173, 0.173, 0.18, 1.0) # #2c2c2e
		_C_BORDER_INPUT = Color(1.0, 1.0, 1.0, 0.12)
		_C_TEXT = Color(0.96, 0.96, 0.97, 1.0)
		_C_MUTED = Color(0.58, 0.58, 0.62, 1.0)
		_C_ACCENT = Color(0.04, 0.52, 1.0, 1.0)
	else:
		_C_BG_INPUT = Color(0.945, 0.945, 0.961, 1.0) # #f1f1f5
		_C_BORDER_INPUT = Color(0.86, 0.86, 0.88, 1.0)
		_C_TEXT = Color(0.12, 0.12, 0.15, 1.0)
		_C_MUTED = Color(0.50, 0.50, 0.55, 1.0)
		_C_ACCENT = Color(0.04, 0.52, 1.0, 1.0)

func _setup_panel_style() -> void:
	custom_minimum_size = Vector2(268, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if _C_TEXT.v < 0.5 else Color(0.12, 0.12, 0.13, 1.0)
	sb.border_width_left = 1
	sb.border_color = _C_BORDER_INPUT
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)

func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root_vbox)

	# ── 1. CABECERA LIMPIA (SIN SELECTOR DE MODO DUPLICADO) ──
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	root_vbox.add_child(header)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	header.add_child(title_row)

	lbl_title = Label.new()
	lbl_title.text = "Inspector"
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.add_theme_font_size_override("font_size", 12)
	lbl_title.add_theme_color_override("font_color", _C_TEXT)
	title_row.add_child(lbl_title)

	# El selector de modo se mantiene instanciado para compatibilidad de tests,
	# pero invisible y sin ocupar espacio en el panel de propiedades (se aloja en TopBar)
	var selector_script = preload("res://script_gdscript/ui/ui_mode_selector.gd")
	mode_selector = selector_script.new()
	mode_selector.visible = false

	lbl_selection = Label.new()
	lbl_selection.text = "No selection"
	lbl_selection.add_theme_font_size_override("font_size", 10)
	lbl_selection.add_theme_color_override("font_color", _C_MUTED)
	header.add_child(lbl_selection)

	var sep1 := HSeparator.new()
	sep1.add_theme_constant_override("separation", 6)
	_style_separator(sep1)
	root_vbox.add_child(sep1)

	# ── 2. CONTENEDOR CON SCROLL PARA SECCIONES ──
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll_container)

	content_container = VBoxContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 10)
	scroll_container.add_child(content_container)

	# ── SECCION VACÍA: PROPIEDADES DE LIENZO / PÁGINA (CUANDO NO HAY SELECCIÓN) ──
	_build_canvas_section()

	# ── SECCION A: ALINEACION (BARRA SEGMENTADA INTEGRADA DE 8 BOTONES) ──
	_build_align_section()

	# ── SECCION B: TRANSFORM COMPACTO (FIGMA 2-COLUMN GRID) ──
	transform_panel = TransformPanel.new()
	transform_panel.name = "DockedTransformPanel"
	content_container.add_child(transform_panel)

	# ── SECCION C: APARIENCIA (OPACIDAD Y VISIBILIDAD) ──
	_build_appearance_section()

	# ── SECCION D: RELLENO (FILL - FILA COMPACTA) ──
	_build_fill_section()

	# ── SECCION E: TRAZO (STROKE - FILA COMPACTA) ──
	_build_stroke_section()

	# ── SECCION F: EFECTOS (SHADOW - FILA COMPACTA) ──
	_build_effects_section()

	# ── SECCION G: EXPORTAR (SOLO CUANDO HAY ELEMENTO SELECCIONADO) ──
	_build_export_section()

func _create_section_header(title: String, on_add: Callable = Callable()) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", _C_MUTED)
	hbox.add_child(lbl)

	if on_add.is_valid():
		var btn_add := _create_chip_button("+", "Añadir %s" % title.to_lower(), Vector2(20, 20))
		btn_add.pressed.connect(on_add)
		hbox.add_child(btn_add)

	return hbox

func _add_section_header(title: String, on_add: Callable = Callable()) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	_style_separator(sep)
	content_container.add_child(sep)
	content_container.add_child(_create_section_header(title, on_add))

func _style_separator(sep: HSeparator) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BORDER_INPUT
	sb.border_width_top = 1
	sb.border_color = _C_BORDER_INPUT
	sep.add_theme_stylebox_override("separator", sb)

# ── PROPIEDADES DE PÁGINA (ESTADO "NO SELECTION") ──
func _build_canvas_section() -> void:
	sec_canvas = VBoxContainer.new()
	sec_canvas.add_theme_constant_override("separation", 8)
	content_container.add_child(sec_canvas)

	sec_canvas.add_child(_create_section_header("PAGE"))

	var row_bg := HBoxContainer.new()
	row_bg.add_theme_constant_override("separation", 6)
	sec_canvas.add_child(row_bg)

	picker_canvas_bg = ColorSwatchButton.new(Color.WHITE)
	_style_color_picker(picker_canvas_bg)
	picker_canvas_bg.color_changed.connect(_on_canvas_bg_changed)
	picker_canvas_bg.pressed.connect(func(): _open_color_popover("canvas", picker_canvas_bg))
	row_bg.add_child(picker_canvas_bg)

	lbl_canvas_hex = Label.new()
	lbl_canvas_hex.text = "#FFFFFF"
	lbl_canvas_hex.add_theme_font_size_override("font_size", 11)
	lbl_canvas_hex.add_theme_color_override("font_color", _C_TEXT)
	lbl_canvas_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_bg.add_child(_wrap_input_pill(lbl_canvas_hex))

	var row_dim := HBoxContainer.new()
	row_dim.add_theme_constant_override("separation", 6)
	sec_canvas.add_child(row_dim)

	lbl_canvas_size = Label.new()
	lbl_canvas_size.text = "1920 × 1080 px"
	lbl_canvas_size.add_theme_font_size_override("font_size", 10)
	lbl_canvas_size.add_theme_color_override("font_color", _C_MUTED)
	lbl_canvas_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_dim.add_child(_wrap_input_pill(lbl_canvas_size))

	var hint_lbl := Label.new()
	hint_lbl.text = "Selecciona un objeto para editar sus propiedades."
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", _C_MUTED)
	sec_canvas.add_child(hint_lbl)

# ── SECCIÓN ALINEACIÓN (8 BOTONES SIN BORDES PESADOS) ──
func _build_align_section() -> void:
	sec_align = VBoxContainer.new()
	sec_align.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_align)

	sec_align.add_child(_create_section_header("ALIGNMENT"))

	# Contenedor tipo segmented control integrado
	var bar_panel := PanelContainer.new()
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = _C_BG_INPUT
	bar_sb.set_corner_radius_all(6)
	bar_sb.set_content_margin_all(2)
	bar_panel.add_theme_stylebox_override("panel", bar_sb)
	sec_align.add_child(bar_panel)

	align_container = HBoxContainer.new()
	align_container.add_theme_constant_override("separation", 1)
	align_container.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_panel.add_child(align_container)

	var aligns := [
		{"key": "left", "tooltip": "Alinear a la izquierda", "icon": "res://icon/UI/align_left_pro.svg", "fallback": "⇤"},
		{"key": "center_h", "tooltip": "Alinear al centro horizontal", "icon": "res://icon/UI/align_center_h_pro.svg", "fallback": "⇥⇤"},
		{"key": "right", "tooltip": "Alinear a la derecha", "icon": "res://icon/UI/align_right_pro.svg", "fallback": "⇥"},
		{"key": "top", "tooltip": "Alinear arriba", "icon": "res://icon/UI/align_top_pro.svg", "fallback": "⤒"},
		{"key": "middle", "tooltip": "Alinear al centro vertical", "icon": "res://icon/UI/align_center_v_pro.svg", "fallback": "⤓⤒"},
		{"key": "bottom", "tooltip": "Alinear abajo", "icon": "res://icon/UI/align_bottom_pro.svg", "fallback": "⤓"},
		{"key": "dist_h", "tooltip": "Distribuir horizontalmente", "icon": "res://icon/UI/distribute_h_pro.svg", "fallback": "⇹"},
		{"key": "dist_v", "tooltip": "Distribuir verticalmente", "icon": "res://icon/UI/distribute_v_pro.svg", "fallback": "⇳"}
	]

	for a in aligns:
		var btn := _create_flat_icon_button(a["fallback"], a["tooltip"], Vector2(28, 22))
		if ResourceLoader.exists(a["icon"]):
			btn.icon = load(a["icon"])
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.expand_icon = true
			btn.text = ""
		var k: String = a["key"]
		btn.pressed.connect(func(): _on_align_pressed(k))
		align_container.add_child(btn)

# ── SECCIÓN APARIENCIA ──
func _build_appearance_section() -> void:
	sec_appearance = VBoxContainer.new()
	sec_appearance.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_appearance)

	sec_appearance.add_child(_create_section_header("APPEARANCE"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	sec_appearance.add_child(row)

	var lbl_op := Label.new()
	lbl_op.text = "Opacity"
	lbl_op.add_theme_font_size_override("font_size", 10)
	lbl_op.add_theme_color_override("font_color", _C_MUTED)
	lbl_op.custom_minimum_size = Vector2(46, 0)
	row.add_child(lbl_op)

	spin_opacity = SpinBox.new()
	spin_opacity.min_value = 0.0
	spin_opacity.max_value = 100.0
	spin_opacity.step = 1.0
	spin_opacity.value = 100.0
	spin_opacity.suffix = "%"
	spin_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_spinbox(spin_opacity)
	spin_opacity.value_changed.connect(_on_fill_opacity_changed)
	row.add_child(spin_opacity)

	btn_toggle_visibility = _create_chip_button("👁", "Alternar visibilidad del objeto", Vector2(26, 24))
	btn_toggle_visibility.pressed.connect(_on_toggle_visibility_pressed)
	row.add_child(btn_toggle_visibility)

# ── SECCIÓN RELLENO (FILL) ──
func _build_fill_section() -> void:
	sec_fill = VBoxContainer.new()
	sec_fill.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_fill)

	sec_fill.add_child(_create_section_header("FILL", func(): _on_fill_color_changed(Color.WHITE)))

	# Fila compacta: Muestra + HEX + Opacidad + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_fill.add_child(row)

	picker_fill = ColorSwatchButton.new(Color.WHITE)
	_style_color_picker(picker_fill)
	picker_fill.color_changed.connect(_on_fill_color_changed)
	picker_fill.pressed.connect(func(): _open_color_popover("fill", picker_fill))
	row.add_child(picker_fill)

	lbl_fill_hex = Label.new()
	lbl_fill_hex.text = "#FFFFFF"
	lbl_fill_hex.add_theme_font_size_override("font_size", 11)
	lbl_fill_hex.add_theme_color_override("font_color", _C_TEXT)
	lbl_fill_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_wrap_input_pill(lbl_fill_hex))

	var btn_eye := _create_chip_button("👁", "Alternar relleno", Vector2(24, 24))
	btn_eye.pressed.connect(_on_toggle_visibility_pressed)
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar relleno", Vector2(24, 24))
	btn_minus.pressed.connect(func(): _on_fill_color_changed(Color(1, 1, 1, 0)))
	row.add_child(btn_minus)

# ── SECCIÓN TRAZO (STROKE) ──
func _build_stroke_section() -> void:
	sec_stroke = VBoxContainer.new()
	sec_stroke.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_stroke)

	sec_stroke.add_child(_create_section_header("STROKE", func(): _on_stroke_width_changed(1.0)))

	# Fila compacta: Muestra + Grosor + Alineación + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_stroke.add_child(row)

	picker_stroke = ColorSwatchButton.new(Color.BLACK)
	_style_color_picker(picker_stroke)
	picker_stroke.color_changed.connect(_on_stroke_color_changed)
	picker_stroke.pressed.connect(func(): _open_color_popover("stroke", picker_stroke))
	row.add_child(picker_stroke)

	spin_stroke_width = SpinBox.new()
	spin_stroke_width.min_value = 0.0
	spin_stroke_width.max_value = 100.0
	spin_stroke_width.step = 0.5
	spin_stroke_width.value = 1.0
	spin_stroke_width.suffix = "px"
	spin_stroke_width.custom_minimum_size = Vector2(62, 24)
	_style_spinbox(spin_stroke_width)
	spin_stroke_width.value_changed.connect(_on_stroke_width_changed)
	row.add_child(spin_stroke_width)

	opt_stroke_align = OptionButton.new()
	opt_stroke_align.add_item("Center")
	opt_stroke_align.add_item("Inside")
	opt_stroke_align.add_item("Outside")
	opt_stroke_align.custom_minimum_size = Vector2(68, 24)
	opt_stroke_align.focus_mode = Control.FOCUS_NONE
	opt_stroke_align.add_theme_font_size_override("font_size", 9)
	_style_option_button(opt_stroke_align)
	row.add_child(opt_stroke_align)

	var btn_eye := _create_chip_button("👁", "Alternar trazo", Vector2(24, 24))
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar trazo", Vector2(24, 24))
	btn_minus.pressed.connect(func(): _on_stroke_width_changed(0.0))
	row.add_child(btn_minus)

# ── SECCIÓN EFECTOS ──
func _build_effects_section() -> void:
	sec_effects = VBoxContainer.new()
	sec_effects.add_theme_constant_override("separation", 4)
	content_container.add_child(sec_effects)

	sec_effects.add_child(_create_section_header("EFFECTS", func(): _on_shadow_toggle_pressed()))

	# Fila compacta: Nombre de efecto + Ajustes + Ojo + Menos
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	sec_effects.add_child(row)

	btn_shadow_toggle = _create_chip_button("▨ Drop Shadow", "Alternar sombra suave", Vector2(0, 24))
	btn_shadow_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_shadow_toggle.pressed.connect(_on_shadow_toggle_pressed)
	row.add_child(btn_shadow_toggle)

	var btn_cfg := _create_chip_button("⚙", "Ajustes de sombra", Vector2(24, 24))
	row.add_child(btn_cfg)

	var btn_eye := _create_chip_button("👁", "Alternar sombra", Vector2(24, 24))
	btn_eye.pressed.connect(_on_shadow_toggle_pressed)
	row.add_child(btn_eye)

	var btn_minus := _create_chip_button("−", "Quitar sombra", Vector2(24, 24))
	btn_minus.pressed.connect(func():
		if _has_shadow: _on_shadow_toggle_pressed()
	)
	row.add_child(btn_minus)

# ── SECCIÓN EXPORTAR (CONSOLIDADA AL FINAL) ──
func _build_export_section() -> void:
	sec_export = VBoxContainer.new()
	sec_export.add_theme_constant_override("separation", 6)
	content_container.add_child(sec_export)

	sec_export.add_child(_create_section_header("EXPORT", func(): _on_export_selection_pressed()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	sec_export.add_child(row)

	opt_export_format = OptionButton.new()
	opt_export_format.add_item("PNG")
	opt_export_format.add_item("SVG")
	opt_export_format.add_item("JPG")
	opt_export_format.add_item("PDF")
	opt_export_format.custom_minimum_size = Vector2(62, 24)
	opt_export_format.focus_mode = Control.FOCUS_NONE
	opt_export_format.add_theme_font_size_override("font_size", 10)
	_style_option_button(opt_export_format)
	row.add_child(opt_export_format)

	btn_export_selection = _create_chip_button("Export", "Exportar seleccion activa", Vector2(0, 24))
	btn_export_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_export_selection.pressed.connect(_on_export_selection_pressed)
	row.add_child(btn_export_selection)

# ── HELPERS DE ESTILOS DE COMPONENTES ──
func _wrap_input_pill(inner: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = _C_BG_INPUT
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER_INPUT
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(inner)
	return pc

func _style_spinbox(sb: SpinBox) -> void:
	var le := sb.get_line_edit()
	if is_instance_valid(le):
		le.add_theme_font_size_override("font_size", 10)
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = _C_BG_INPUT
		sbf.set_corner_radius_all(4)
		sbf.set_border_width_all(1)
		sbf.border_color = _C_BORDER_INPUT
		sbf.content_margin_left = 4
		sbf.content_margin_right = 4
		sbf.content_margin_top = 1
		sbf.content_margin_bottom = 1
		le.add_theme_stylebox_override("normal", sbf)
		le.add_theme_stylebox_override("focus", sbf)

func _style_color_picker(cp: Button) -> void:
	cp.focus_mode = Control.FOCUS_NONE
	var sbf := StyleBoxFlat.new()
	sbf.set_corner_radius_all(4)
	sbf.set_border_width_all(1)
	sbf.border_color = _C_BORDER_INPUT
	sbf.draw_center = false
	sbf.content_margin_left = 2
	sbf.content_margin_right = 2
	sbf.content_margin_top = 2
	sbf.content_margin_bottom = 2
	cp.add_theme_stylebox_override("normal", sbf)
	cp.add_theme_stylebox_override("hover", sbf)

func _style_option_button(opt: OptionButton) -> void:
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = _C_BG_INPUT
	sbf.set_corner_radius_all(4)
	sbf.set_border_width_all(1)
	sbf.border_color = _C_BORDER_INPUT
	sbf.content_margin_left = 4
	sbf.content_margin_right = 4
	sbf.content_margin_top = 1
	sbf.content_margin_bottom = 1
	opt.add_theme_stylebox_override("normal", sbf)
	opt.add_theme_stylebox_override("hover", sbf)

func _create_flat_icon_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)

	var empty_sb := StyleBoxEmpty.new()
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.88, 0.88, 0.91, 1.0) if _C_TEXT.v < 0.5 else Color(0.24, 0.24, 0.26, 1.0)
	hover_sb.set_corner_radius_all(4)

	var press_sb := StyleBoxFlat.new()
	press_sb.bg_color = Color(0.82, 0.82, 0.86, 1.0) if _C_TEXT.v < 0.5 else Color(0.30, 0.30, 0.32, 1.0)
	press_sb.set_corner_radius_all(4)

	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", _C_TEXT)
	return btn

func _create_chip_button(btn_text: String, tooltip: String, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)

	var norm_sb := StyleBoxFlat.new()
	norm_sb.bg_color = _C_BG_INPUT
	norm_sb.set_corner_radius_all(4)
	norm_sb.set_border_width_all(1)
	norm_sb.border_color = _C_BORDER_INPUT
	norm_sb.content_margin_left = 4
	norm_sb.content_margin_right = 4
	norm_sb.content_margin_top = 2
	norm_sb.content_margin_bottom = 2

	var hover_sb := norm_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.88, 0.88, 0.91, 1.0) if _C_TEXT.v < 0.5 else Color(0.24, 0.24, 0.26, 1.0)

	var press_sb := norm_sb.duplicate() as StyleBoxFlat
	press_sb.bg_color = Color(0.82, 0.82, 0.86, 1.0) if _C_TEXT.v < 0.5 else Color(0.30, 0.30, 0.32, 1.0)

	btn.add_theme_stylebox_override("normal", norm_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", press_sb)
	btn.add_theme_color_override("font_color", _C_TEXT)
	return btn

# ── CONEXIÓN Y EVENTOS ──
func _connect_inspector_core() -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if ic:
		if ic.has_signal("changed") and not ic.changed.is_connected(_on_inspector_changed):
			ic.changed.connect(_on_inspector_changed)
		if ic.has_signal("selection_size_changed") and not ic.selection_size_changed.is_connected(_on_selection_size_changed):
			ic.selection_size_changed.connect(_on_selection_size_changed)

func _on_align_pressed(direction: String) -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if not ic: return
	if direction == "dist_h":
		if ic.has_method("distribute"): ic.distribute("horizontal")
	elif direction == "dist_v":
		if ic.has_method("distribute"): ic.distribute("vertical")
	elif ic.has_method("align"):
		ic.align(direction)

func _on_canvas_bg_changed(color: Color) -> void:
	if is_instance_valid(lbl_canvas_hex):
		lbl_canvas_hex.text = "#" + color.to_html(false).to_upper()
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_canvas_color_change"):
		ge.emit_safe("request_canvas_color_change", color)

func _on_fill_color_changed(color: Color) -> void:
	if is_instance_valid(lbl_fill_hex):
		lbl_fill_hex.text = "#" + color.to_html(false).to_upper()
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("fill_color", color)

func _on_fill_opacity_changed(val: float) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("opacity", val / 100.0)

func _on_toggle_visibility_pressed() -> void:
	_current_item_visible = !_current_item_visible
	btn_toggle_visibility.text = "👁" if _current_item_visible else "Ø"
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("visible", _current_item_visible)

func _on_stroke_color_changed(color: Color) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("stroke_color", color)

func _on_stroke_width_changed(val: float) -> void:
	if _syncing: return
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		ic.apply("stroke_width", val)

func _on_shadow_toggle_pressed() -> void:
	_has_shadow = !_has_shadow
	btn_shadow_toggle.modulate = Color(0.7, 1.0, 0.7) if _has_shadow else Color.WHITE
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("apply"):
		var effects := []
		if _has_shadow:
			effects.append({"type": "drop_shadow", "offset": Vector2(0, 4), "color": Color(0, 0, 0, 0.25), "blur": 8.0})
		ic.apply("effects", effects)

func _on_export_selection_pressed() -> void:
	var ge = get_node_or_null("/root/GlobalEvents")
	if ge and ge.has_signal("request_export_dialog"):
		ge.emit_safe("request_export_dialog")

# ── ACTUALIZACIÓN DE SELECCIÓN Y PROPIEDADES ──
func _on_selection_size_changed(count: int) -> void:
	_has_selection = count > 0
	if count == 0:
		lbl_title.text = "Page"
		lbl_selection.text = "No selection"
		if is_instance_valid(sec_canvas): sec_canvas.visible = true
		if is_instance_valid(sec_align): sec_align.visible = false
		if is_instance_valid(transform_panel): transform_panel.visible = false
		if is_instance_valid(sec_appearance): sec_appearance.visible = false
		if is_instance_valid(sec_fill): sec_fill.visible = false
		if is_instance_valid(sec_stroke): sec_stroke.visible = false
		if is_instance_valid(sec_effects): sec_effects.visible = false
		if is_instance_valid(sec_export): sec_export.visible = false
	else:
		if is_instance_valid(sec_canvas): sec_canvas.visible = false
		if is_instance_valid(sec_align): sec_align.visible = true
		if is_instance_valid(transform_panel): transform_panel.visible = true
		if is_instance_valid(sec_appearance): sec_appearance.visible = true
		if is_instance_valid(sec_fill): sec_fill.visible = true
		if is_instance_valid(sec_stroke): sec_stroke.visible = true
		if is_instance_valid(sec_effects): sec_effects.visible = true
		if is_instance_valid(sec_export): sec_export.visible = true

		if count == 1:
			var ic = get_node_or_null("/root/InspectorCore")
			var props = ic.current_props() if ic else {}
			var sname = props.get("name", {}).get("value", "Rectangle")
			lbl_title.text = str(sname)
			lbl_selection.text = "1 object selected"
		else:
			lbl_title.text = "Selection"
			lbl_selection.text = "%d objects selected" % count

func _on_inspector_changed(props: Dictionary) -> void:
	_syncing = true
	if is_instance_valid(picker_fill) and props.has("fill_color") and not props["fill_color"].get("mixed", false):
		var col: Color = props["fill_color"]["value"]
		picker_fill.color = col
		if is_instance_valid(lbl_fill_hex):
			lbl_fill_hex.text = "#" + col.to_html(false).to_upper()
	if is_instance_valid(spin_opacity) and props.has("opacity") and not props["opacity"].get("mixed", false):
		spin_opacity.value = float(props["opacity"]["value"]) * 100.0
	if is_instance_valid(picker_stroke) and props.has("stroke_color") and not props["stroke_color"].get("mixed", false):
		picker_stroke.color = props["stroke_color"]["value"]
	if is_instance_valid(spin_stroke_width) and props.has("stroke_width") and not props["stroke_width"].get("mixed", false):
		spin_stroke_width.value = float(props["stroke_width"]["value"])
	if props.has("visible") and not props["visible"].get("mixed", false):
		_current_item_visible = bool(props["visible"]["value"])
		if is_instance_valid(btn_toggle_visibility):
			btn_toggle_visibility.text = "👁" if _current_item_visible else "Ø"
	_syncing = false

func _update_from_inspector() -> void:
	var ic = get_node_or_null("/root/InspectorCore")
	if ic and ic.has_method("current_props"):
		_on_inspector_changed(ic.current_props())
		if ic.has_method("selection"):
			_on_selection_size_changed(ic.selection().size())

func set_density(dense: bool) -> void:
	_is_dense = dense
	custom_minimum_size = Vector2(286, 0) if dense else Vector2(268, 0)
	if is_instance_valid(content_container):
		content_container.add_theme_constant_override("separation", 6 if dense else 10)

# ── GESTIÓN DEL POPOVER DE COLOR (PICKERCOLOR DE SMART) ──
func _ensure_color_popover() -> void:
	if is_instance_valid(_color_popover):
		return
	_color_popover = PanelContainer.new()
	_color_popover.top_level = true
	_color_popover.visible = false
	_color_popover.z_index = 250

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.99, 1.0) if _C_TEXT.v < 0.5 else Color(0.14, 0.14, 0.15, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = _C_BORDER_INPUT
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_color_popover.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_color_popover.add_child(vbox)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_popover_header_title = Label.new()
	_color_popover_header_title.text = "Color"
	_color_popover_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_popover_header_title.add_theme_font_size_override("font_size", 11)
	_color_popover_header_title.add_theme_color_override("font_color", _C_MUTED)
	header.add_child(_color_popover_header_title)

	var btn_close := _create_chip_button("✕", "Cerrar", Vector2(20, 20))
	btn_close.pressed.connect(func(): _color_popover.visible = false)
	header.add_child(btn_close)
	vbox.add_child(header)

	var scene := load("res://scenes/ui/pickr_color_tool.tscn")
	if scene:
		_pickr_instance = scene.instantiate() as GestorColor
		vbox.add_child(_pickr_instance)
		if _pickr_instance and _pickr_instance.has_signal("color_actualizado"):
			_pickr_instance.color_actualizado.connect(_on_popover_color_actualizado)

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
			"fill": _color_popover_header_title.text = "Relleno (Fill)"
			"stroke": _color_popover_header_title.text = "Trazo (Stroke)"
			"canvas": _color_popover_header_title.text = "Color de Lienzo"
			_: _color_popover_header_title.text = "Color"

	var cur_col: Color = Color.WHITE
	if target == "fill" and is_instance_valid(picker_fill):
		cur_col = picker_fill.color
	elif target == "stroke" and is_instance_valid(picker_stroke):
		cur_col = picker_stroke.color
	elif target == "canvas" and is_instance_valid(picker_canvas_bg):
		cur_col = picker_canvas_bg.color

	var cc = get_node_or_null("/root/ColorCore")
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

func _on_popover_color_actualizado(col: Color) -> void:
	match _active_color_target:
		"fill":
			if is_instance_valid(picker_fill):
				picker_fill.color = col
				picker_fill.color_changed.emit(col)
			_on_fill_color_changed(col)
		"stroke":
			if is_instance_valid(picker_stroke):
				picker_stroke.color = col
				picker_stroke.color_changed.emit(col)
			_on_stroke_color_changed(col)
		"canvas":
			if is_instance_valid(picker_canvas_bg):
				picker_canvas_bg.color = col
				picker_canvas_bg.color_changed.emit(col)
			_on_canvas_bg_changed(col)

func _input(event: InputEvent) -> void:
	if is_instance_valid(_color_popover) and _color_popover.visible:
		if event is InputEventMouseButton and event.pressed:
			var mp := get_global_mouse_position()
			if not _color_popover.get_global_rect().has_point(mp):
				var on_swatch: bool = false
				for b in [picker_fill, picker_stroke, picker_canvas_bg]:
					if is_instance_valid(b) and b.get_global_rect().has_point(mp):
						on_swatch = true
						break
				if not on_swatch:
					_color_popover.visible = false
